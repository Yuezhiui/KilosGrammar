extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_balloon_vocab_recycle_20261029.gd
# Real-scene vocabulary progression, accelerated by direct question advance;
# not physical hand/webcam end-to-end play. No production assets are modified.

const GAME: PackedScene = preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const BANK = preload("res://ui/minigames/shared/grammar_bank.gd")
const TOPICS := ["Noun", "Verb", "Adjective", "Adverb", "Pronoun"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const QUESTIONS_PER_SESSION := 140

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var total_recycles := 0
	var total_rounds := 0
	for topic in TOPICS:
		for difficulty in DIFFICULTIES:
			var recycles: int = await _exercise_long_lives(topic, difficulty)
			total_recycles += recycles
			total_rounds += QUESTIONS_PER_SESSION
	# Check Seconds as an independent termination mode even past vocabulary
	# exhaustion; never finish early because the bank starts reusing words.
	await _exercise_seconds_timer_end()
	await create_timer(0.85).timeout
	for i in range(3):
		await process_frame
	if failures.is_empty():
		print("PASS Balloon vocabulary recycle: %d checks / %d long Lives rounds / %d pool recycles + Seconds timer" %
			[checks, total_rounds, total_recycles])
		quit(0)
	else:
		for failure in failures.slice(0, 30):
			push_error("BALLOON VOCAB RECYCLE: " + failure)
		print("FAIL Balloon vocabulary recycle: %d failures / %d checks" %
			[failures.size(), checks])
		quit(1)


func _exercise_long_lives(topic: String, difficulty: String) -> int:
	var title := "%s/%s" % [topic, difficulty]
	var game := GAME.instantiate() as Control
	root.add_child(game)
	await process_frame
	game.set_context({"activity": "Balloon Popping", "topic": topic,
		"difficulty": difficulty, "game_mode": "Lives", "score": 0,
		"correct": 0, "attempts": 0, "time_remaining": 60.0,
		"balloon_round": 0})
	game.set_process(false)
	game.set_physics_process(false)
	var matching := _set_from(BANK._available_words(topic, true, difficulty, {}))
	var distractors := _set_from(BANK._available_words(topic, false, difficulty, {}))
	_check(matching.size() > 2 and distractors.size() > 2,
		title + " eligible source bank has two viable grammar pools")
	var previous: Dictionary = {}
	var total_recycles := 0
	var observed_correct := 0
	var observed_words := 0
	for question in range(QUESTIONS_PER_SESSION):
		var prior_used: Dictionary = game.used_words.duplicate()
		var prior_match_count := _remaining_count(matching, prior_used)
		var prior_distractor_count := _remaining_count(distractors, prior_used)
		if question > 0:
			game._start_new_round()
			game.set_process(false)
			game.set_physics_process(false)
			var lost_matching := _removed_count(prior_used, game.used_words, matching)
			var lost_distractors := _removed_count(prior_used, game.used_words, distractors)
			if lost_matching + lost_distractors > 0:
				total_recycles += 1
				_check(prior_match_count == 0 or prior_distractor_count == 0
					or (prior_match_count == 1 and prior_distractor_count == 1),
						title + " recycle %d occurs only when a three-lane round is impossible" % total_recycles)
				_check(lost_matching == 0 or prior_match_count == 0,
						title + " used matching words recycle only after matching pool exhaustion")
				_check(lost_distractors == 0 or prior_distractor_count == 0
						or (prior_match_count == 1 and prior_distractor_count == 1),
						title + " used distractors recycle only if unable to supply a 3-word round")
			else:
				_check(_contains_all(game.used_words, prior_used),
						title + " existing cycle preserves all earlier shown choices")

		_check(not game.finishing and game.timer_running and game.round_active
			and game.hearts == 3 and game.time_remaining == 0.0,
			title + " Lives question %d stays active, without global clock or heart loss" % (question + 1))
		_check(game.round_index == question + 1 and game.balloons.size() == 3
			and game.valid_lanes.size() > 0 and game.valid_lanes.size() < 3,
			title + " question %d has exactly 3 lanes and a valid answer" % (question + 1))
		var current: Dictionary = {}
		var expected_negative: bool = difficulty == "Hard" or (difficulty == "Normal" and game.round_index % 3 == 0)
		var category := String(game.TOPIC_PLURALS.get(game._topic(), "NOUNS"))
		var expected_banner := ("POP NOT %s!" if expected_negative else "POP %s!") % category
		var banner := game.get_node_or_null("HudLayer/BannerTagline") as Label
		_check(banner != null and banner.text == expected_banner and
			game.get_node_or_null("HudLayer/PromptLabel") == null and
			game.get_node_or_null("HudLayer/PromptPanel") == null,
			title + " dynamic banner displays actual positive/negative difficulty rule without redundant prompt")
		var valid_matches := 0
		var valid_distractors := 0
		for lane in range(3):
			var balloon: Area2D = game.balloons[lane]
			var word := String((balloon.get_node("WordLabel") as Label).text).strip_edges().to_lower()
			var is_match := matching.has(word)
			var is_distractor := distractors.has(word)
			var is_valid: bool = game.valid_lanes.has(lane)
			_check(not word.is_empty() and (is_match != is_distractor),
				title + " word '%s' in correct %s tier/topic pool" % [word, difficulty])
			_check(not current.has(word),
				title + " repeated word within same question (%s)" % word)
			_check(not previous.has(word),
				title + " immediate back-to-back repeat (%s)" % word)
			_check(is_valid == (is_distractor if expected_negative else is_match),
				title + " selected correct/wrong lane classification for '%s'" % word)
			_check(game.used_words.has(word),
				title + " tracks all displayed choices in cycle history")
			current[word] = true
			if is_valid and is_match:
				valid_matches += 1
			if is_valid and is_distractor:
				valid_distractors += 1
			observed_words += 1
		_check((valid_distractors > 0) if expected_negative else (valid_matches > 0),
			title + " prompt always has an eligible correct target")
		previous = current
		# Sample real correct hit path in long Lives sessions; the rest use
		# direct round advance to stress the complete bank quickly.
		if question % 10 == 0:
			var lane: int = game.pending_valid_lanes[0]
			var popped: Area2D = game.balloons[lane]
			popped.position.y = game.UPPER_LINE_Y + 40.0
			game._handle_balloon_hit(lane, popped.position)
			observed_correct += 1
			_check(game.score == observed_correct * 100 and game.correct_count == observed_correct,
				title + " real pop during long Lives adds +100")
			_check(game.hearts == 3 and not game.finishing,
				title + " correct answer never causes early Results")

	_check(total_recycles > 0, title + " 140-round stress exhausts and recycles at least one pool")
	_check(observed_words == 3 * QUESTIONS_PER_SESSION,
		title + " displays 3 real options in every tested question")
	_check(game.score == observed_correct * 100 and not game.finishing,
		title + " long Lives score survives all vocabulary cycles")
	# Never allow manual call sites to finish for any reason other than 0 hearts.
	game._finish_round()
	_check(not game.finishing and game.hearts == 3,
		title + " Results guarded while hearts remain")
	# Confirm that after many cycles, the normal three wrong hits still end Lives.
	for loss in range(3):
		game._start_new_round()
		game.set_process(false)
		game.set_physics_process(false)
		var wrong_lane := -1
		for lane in range(3):
			if not game.pending_valid_lanes.has(lane):
				wrong_lane = lane
				break
		_check(wrong_lane >= 0, title + " has a wrong target for heart loss")
		if wrong_lane >= 0:
			var wrong: Area2D = game.balloons[wrong_lane]
			wrong.position.y = game.UPPER_LINE_Y + 45.0
			game._handle_balloon_hit(wrong_lane, wrong.position)
		_check(game.hearts == 2 - loss and game.finishing == (loss == 2),
			title + " only zero Lives opens Results after long vocabulary cycling")
	_check(game.get_context().get("score") == observed_correct * 100,
		title + " final result preserves long-session score")
	game.queue_free()
	await process_frame
	return total_recycles


func _exercise_seconds_timer_end() -> void:
	var game := GAME.instantiate() as Control
	root.add_child(game)
	await process_frame
	game.set_context({"topic": "Pronoun", "difficulty": "Hard", "game_mode": "Seconds",
		"time_remaining": 10000.0, "hearts": 42, "lives": 42})
	game.set_process(false)
	game.set_physics_process(false)
	for i in range(120):
		game._start_new_round()
		game.set_process(false)
		game.set_physics_process(false)
		_check(game.round_active and not game.finishing and game.hearts == 0,
			"Seconds vocabulary cycle %d cannot end game or deduct hearts" % i)
	game._finish_round()
	_check(not game.finishing and game.time_remaining == 60.0,
		"Seconds cannot open Results even after 120 question changes")
	game._process(59.99)
	game.set_process(false)
	_check(not game.finishing and game.time_remaining > 0.0,
		"Seconds game remains active just before timer reaches zero")
	game._process(0.02)
	_check(game.finishing and game.round_completed and game.time_remaining == 0.0
		and game.hearts == 0 and game.get_context().get("game_mode") == "Seconds",
		"Seconds Results only when global 60s timer expires")
	game.queue_free()
	await process_frame


func _set_from(words: Array[String]) -> Dictionary:
	var result := {}
	for word in words:
		result[word.strip_edges().to_lower()] = true
	return result


func _remaining_count(pool: Dictionary, used: Dictionary) -> int:
	var remaining := 0
	for word in pool:
		if not used.has(word):
			remaining += 1
	return remaining


func _removed_count(before: Dictionary, after: Dictionary, pool: Dictionary) -> int:
	var removed := 0
	for word in before:
		if pool.has(word) and not after.has(word):
			removed += 1
	return removed


func _contains_all(container: Dictionary, subset: Dictionary) -> bool:
	for word in subset:
		if not container.has(word):
			return false
	return true


func _check(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures.append(detail)
