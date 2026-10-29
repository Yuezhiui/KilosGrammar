extends SceneTree

# Headless regression:
# Godot --headless --path . --script res://tools/test_balloon_difficulty_vocabulary.gd

const SCENE := preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const BANK := preload("res://ui/minigames/shared/grammar_bank.gd")
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const TOPICS := ["Noun", "Verb", "Adjective"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var speeds: Dictionary = {}
	for difficulty in DIFFICULTIES:
		var game := await _create_game("Noun", difficulty)
		speeds[difficulty] = [game.balloon_float_speed, game.balloon_reveal_seconds,
			game.projectile_speed, game.float_start_delay]
		_check(game.default_duration == 60.0 and game.time_remaining == 60.0,
			difficulty + " preserves 60-second mode")
		_check(game.is_seconds_mode and game.round_active and not game.finishing,
			difficulty + " starts active Seconds gameplay")
		game.set_process(false)
		game.set_physics_process(false)
		if is_instance_valid(game.balloon_motion_tween):
			game.balloon_motion_tween.kill()
		game.balloon_floating = true
		var target: Area2D = game.balloon_slots[0]
		var original_y := target.position.y
		game._process(0.25)
		_check(is_equal_approx(original_y - target.position.y, game.balloon_float_speed * 0.25),
			difficulty + " uses elapsed-time-scaled upward balloon motion")
		game.queue_free()
		await process_frame

	_check(speeds["Easy"][0] < speeds["Normal"][0] and speeds["Normal"][0] < speeds["Hard"][0],
		"Normal and Hard progressively increase balloon float speed")
	_check(speeds["Easy"][1] > speeds["Normal"][1] and speeds["Normal"][1] > speeds["Hard"][1],
		"Normal and Hard progressively shorten rising reveal")
	_check(speeds["Easy"][2] < speeds["Normal"][2] and speeds["Normal"][2] < speeds["Hard"][2],
		"Normal and Hard progressively increase projectile speed")
	_check(speeds["Easy"][3] > speeds["Normal"][3] and speeds["Normal"][3] > speeds["Hard"][3],
		"Normal and Hard start floating sooner")

	await _exercise_long_word_labels()
	for topic in TOPICS:
		for difficulty in ["Normal", "Hard"]:
			await _exercise_session(topic, difficulty)

	await _exercise_exhaustion()
	await create_timer(0.65).timeout
	await process_frame
	if failures.is_empty():
		print("PASS Balloon difficulty vocabulary: %d checks" % checks)
		quit(0)
	else:
		for failure in failures.slice(0, 16):
			push_error("BALLOON WORD QA: " + failure)
		print("FAIL Balloon difficulty vocabulary: %d failures / %d checks" %
			[failures.size(), checks])
		quit(1)


func _create_game(topic: String, difficulty: String) -> Control:
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.set_context({
		"topic": topic, "difficulty": difficulty, "game_mode": "Seconds",
		"score": 0, "attempts": 0, "correct": 0, "balloon_round": 0,
		"time_remaining": 60.0
	})
	game.set_process(false)
	game.set_physics_process(false)
	return game


func _exercise_session(topic: String, difficulty: String) -> void:
	var game := await _create_game(topic, difficulty)
	var seen: Dictionary = {}
	for question in range(24):
		_check(not game.finishing, "%s/%s question %d remains answerable" % [topic, difficulty, question])
		if game.finishing:
			break
		_check(game.balloons.size() == 3 and game.valid_lanes.size() >= 1
			and game.valid_lanes.size() < 3, "%s/%s question %d has 3 balanced lanes" %
			[topic, difficulty, question])
		for lane in range(3):
			var label := game.balloon_slots[lane].get_node("WordLabel") as Label
			var key := label.text.strip_edges().to_lower()
			_check(not key.is_empty() and not seen.has(key),
				"%s/%s question %d lane %d never repeats displayed '%s'" %
				[topic, difficulty, question, lane, key])
			seen[key] = true
			_check(game.used_words.has(key),
				"%s/%s tracks each displayed word, including false options" % [topic, difficulty])
			var font_size := label.get_theme_font_size("font_size")
			_check(font_size <= 18 and font_size >= 8 and
				game.FONT.get_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
				<= label.size.x, "%s/%s label keeps vocabulary within authored text width" %
				[topic, difficulty])
		game._start_new_round()
		game.set_process(false)
		game.set_physics_process(false)
	_check(seen.size() >= 70, "%s/%s supplies more than 70 unique displayed words" %
		[topic, difficulty])

	game._pause()
	_check(game.used_words.size() >= seen.size(),
		"%s/%s pause retains displayed-word history" % [topic, difficulty])
	game._resume()
	var saved: Dictionary = game.get_context()
	_check(not saved.has("balloon_used_words"),
		"%s/%s round results do not leak exclusions into a new retry session" % [topic, difficulty])
	# Explicit snapshots can carry exclusion state; a normal retry starts clean.
	saved["balloon_used_words"] = game.used_words.keys()
	game.set_context(saved)
	game.set_process(false)
	game.set_physics_process(false)
	if not game.finishing:
		for slot in game.balloon_slots:
			var word := String((slot.get_node("WordLabel") as Label).text).to_lower()
			_check(not seen.has(word),
				"%s/%s restored snapshot never reuses an earlier word" % [topic, difficulty])
	game.set_context({
		"topic": topic, "difficulty": difficulty, "game_mode": "Seconds",
		"balloon_round": 0, "time_remaining": 60.0
	})
	_check(game.used_words.size() == 3 and game.round_index == 1,
		"%s/%s fresh retry resets the previous session's exclusions" % [topic, difficulty])
	game.queue_free()
	await process_frame


func _exercise_long_word_labels() -> void:
	var game := await _create_game("Noun", "Hard")
	var label := game.balloon_slots[0].get_node("WordLabel") as Label
	for topic in TOPICS:
		for word in BANK.WORD_BANK[topic]:
			label.text = String(word)
			game._fit_balloon_word_label(label)
			var font_size := label.get_theme_font_size("font_size")
			var width: float = game.FONT.get_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER,
				-1, font_size).x
			_check(width <= 145.0, "%s vocabulary '%s' stays inside balloon's readable text area" %
				[topic, word])
	game.queue_free()
	await process_frame


func _exercise_exhaustion() -> void:
	# Pronoun has a small eligible matching pool. After exhaustion, that pool
	# must recycle without ending the Lives game or repeating adjacent rounds.
	var game := await _create_game("Pronoun", "Easy")
	game.set_context({"topic": "Pronoun", "difficulty": "Easy", "game_mode": "Lives"})
	var rounds := 0
	var previous_words: Dictionary = {}
	while rounds < 160:
		var current_words: Dictionary = {}
		for lane in range(game.balloons.size()):
			var word := String((game.balloon_slots[lane].get_node("WordLabel") as Label).text).to_lower()
			_check(not current_words.has(word), "Recycled question has three distinct displayed words")
			_check(not previous_words.has(word), "Recycled question avoids immediate previous-round word")
			_check(game.used_words.has(word), "Recycled displayed word belongs to active cycle history")
			current_words[word] = true
		previous_words = current_words
		game._start_new_round()
		game.set_process(false)
		game.set_physics_process(false)
		rounds += 1
		_check(not game.finishing and not game.round_completed and game.round_active
			and game.timer_running and game.hearts == 3,
			"Vocabulary cycling never ends Lives while three hearts remain")
	_check(game.used_words.size() > 0, "Recycled pool retains displayed word cycle history")
	_check(game.round_index >= 161, "Small Pronoun bank supports more than 160 real rounds")
	game._finish_round()
	_check(not game.finishing and game.hearts == 3,
		"Only losing final heart, never vocabulary exhaustion, may finish Lives")
	_check(game._normalize_round({"options": ["abc", "ABC", "def"], "valid_indices": [0]}).is_empty(),
		"Round validation rejects repeated words independent of casing")
	_check(game._normalize_round({"options": [], "valid_indices": []}).is_empty(),
		"Round validation rejects empty bank response without fallback words")
	game.queue_free()
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
