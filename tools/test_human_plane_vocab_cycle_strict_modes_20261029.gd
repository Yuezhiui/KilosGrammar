extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_vocab_cycle_strict_modes_20261029.gd
# Scene-backed vocabulary and collision QA. No physical camera, DB, or asset changes.
const GAME := preload("res://ui/minigames/human_plane/human_plane.tscn")
const BANK := preload("res://ui/minigames/shared/grammar_bank.gd")
const TOPICS := ["Noun", "Verb", "Adjective", "Adverb", "Pronoun"]
const TIERS := ["Easy", "Normal", "Hard"]
const EXPECTED_CAPS := {"Easy": 1.25, "Normal": 1.35, "Hard": 1.45}

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for topic in TOPICS:
		for tier in TIERS:
			await _many_lives_cycles(topic, tier)
			await _strict_sixty_seconds(topic, tier)
	await _forced_prefetch_cycle()
	await _restore_cycle_boundary()
	for mode in ["Lives", "Seconds"]:
		await _fallback_cycle_without_bank(mode)
	print("HUMAN PLANE VOCAB CYCLES STRICT MODES: %s (%d assertions, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _game(topic: String, tier: String, mode: String, score: int = 0) -> Control:
	var instance := GAME.instantiate() as Control
	root.add_child(instance)
	instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	instance.set_context({"activity": "Human Plane", "topic": topic,
		"difficulty": tier, "game_mode": mode, "score": score})
	return instance


func _many_lives_cycles(topic: String, tier: String) -> void:
	var label := "Lives %s/%s" % [topic, tier]
	var game := _game(topic, tier, "Lives", 100)
	var results: Array[Dictionary] = []
	game.requested.connect(func(destination: String, payload: Dictionary) -> void:
		if destination == "results":
			results.append(payload.duplicate(true))
	)
	await process_frame
	await process_frame
	game.set_process(false)
	game.rng.seed = 29061
	var used_this_cycle := {}
	var previous_options: Array = []
	var previous_cycle := int(game.get("_vocabulary_cycle"))
	var min_cycles := 3
	var completed := 0
	while int(game.get("_vocabulary_cycle")) < min_cycles and completed < 850:
		var data: Dictionary = game.get("round_data")
		var options: Array = data.get("options", [])
		var valid: Array = data.get("valid_indices", [])
		var current_cycle := int(game.get("_vocabulary_cycle"))
		_check(options.size() == 3 and valid.size() >= 1 and valid.size() <= 2,
			label + " fair round %d" % completed)
		if options.size() != 3 or valid.is_empty():
			break
		if current_cycle != previous_cycle:
			_check(current_cycle == previous_cycle + 1, label + " cycle advances once at boundary")
			for option in options:
				_check(String(option).to_lower() not in previous_options,
					label + " new cycle avoids previous wave where feasible")
			used_this_cycle.clear()
			previous_cycle = current_cycle
		var matching: Array = BANK._available_words(topic, true, tier, {})
		var distractors: Array = BANK._available_words(topic, false, tier, {})
		var this_wave := {}
		for index in range(3):
			var word := String(options[index]).to_lower()
			_check(not this_wave.has(word), label + " no duplicate within gate trio")
			this_wave[word] = true
			_check(word in matching if index in valid else word in distractors,
				label + " original GrammarBank topic/tier correctness")
			_check(not used_this_cycle.has(word), label + " no repeat inside cycle")
			used_this_cycle[word] = true
		previous_options = options.duplicate()
		var correct_lane := int(valid[0])
		_place_at_lane(game, correct_lane)
		var before_score := int(game.get("score"))
		var before_boost := float(game.get("speed_multiplier"))
		game.call("_advance_gate_step", 8.0)
		completed += 1
		_check(int(game.get("score")) == before_score + 100 and
			int(game.get("correct_count")) == completed,
			label + " real gate awards +100 across cycles")
		_check(int(game.get("waves_completed")) == completed,
			label + " wave hands off exactly once after visual resolution")
		_check(not bool(game.get("finished")) and results.is_empty() and
			int(game.get("lives")) == 3 and is_zero_approx(float(game.get("time_remaining"))),
			label + " no artificial time/wave/vocab Lives ending")
		_check(float(game.get("speed_multiplier")) >= before_boost and
			float(game.get("speed_multiplier")) <= float(EXPECTED_CAPS[tier]) + 0.00001,
			label + " earned speed never decreases or exceeds diminishing ceiling")
	_check(int(game.get("_vocabulary_cycle")) >= min_cycles and completed < 850,
		label + " completed three real GrammarBank wraparounds")
	_check(int(game.get("score")) == 100 + completed * 100,
		label + " cumulative integer score after many cycles")
	_check(int(game.get("lives")) == 3 and results.is_empty(),
		label + " correct-only run still has all three hearts")

	# Final Results can only be emitted by three real wrong/missed gate hits,
	# even after multiple vocabulary cycles and hundreds of correct answers.
	for remaining in [2, 1, 0]:
		game.set("plane_x_norm", -10.0)
		game.call("_resolve_at_answer_line")
		_check(int(game.get("lives")) == remaining,
			label + " wrong/miss drains exactly one of the three hearts")
		_check(results.is_empty() if remaining > 0 else results.size() == 1,
			label + " final result waits for actual Lives zero")
		if remaining > 0:
			game.call("_advance_gate_step", 8.0)
	_check(bool(game.get("finished")) and results.size() == 1 and
		int(results[0].get("score", -1)) == 100 + completed * 100,
		label + " Lives Results retain score and are emitted exactly once")
	print("LIVES CYCLES: %s/%s - cycles=%d, correct=%d, score=%d, results=%d" %
		[topic, tier, int(game.get("_vocabulary_cycle")), completed,
		int(game.get("score")), results.size()])
	game.queue_free()
	await process_frame
	await process_frame


func _strict_sixty_seconds(topic: String, tier: String) -> void:
	var label := "Seconds %s/%s" % [topic, tier]
	var game := _game(topic, tier, "Seconds")
	var results: Array[Dictionary] = []
	game.requested.connect(func(destination: String, payload: Dictionary) -> void:
		if destination == "results":
			results.append(payload.duplicate(true))
	)
	await process_frame
	await process_frame
	game.set_process(false)
	game.rng.seed = 28014
	# Artificially exhaust ALL legitimate words, as in a long session. This
	# forces at least one cycle during the clock run without altering the bank.
	var saturated := {}
	for bank_topic in BANK.WORD_BANK:
		for word in BANK.WORD_BANK[bank_topic]:
			saturated[String(word).to_lower()] = true
	game.set("used_round_words", saturated)
	game.call("_start_wave")
	_check(int(game.get("_vocabulary_cycle")) >= 1 and
		(game.get("round_data") as Dictionary).get("options", []).size() == 3,
		label + " recycled a fair question despite saturated pool")
	_check(not bool(game.get("_words_exhausted")) and results.is_empty(),
		label + " word recycling never causes early results")
	for second in range(60):
		game.call("_process", 1.0)
		_check(int(game.get("lives")) == 3, label + " no Seconds heart deductions")
		if second < 59:
			_check(not bool(game.get("finished")) and results.is_empty(),
				label + " seconds countdown never ends early")
	_check(bool(game.get("finished")) and results.size() == 1 and
		is_zero_approx(float(game.get("time_remaining"))),
		label + " ends only at actual timer zero")
	_check(int(results[0].get("lives", -1)) == 3 and
		int(results[0].get("score", -1)) == int(game.get("correct_count")) * 100,
		label + " Seconds Results score and hearts are correct")
	game.call("_finish_round")
	_check(results.size() == 1, label + " no duplicate Results event")
	game.queue_free()
	await process_frame
	await process_frame


func _forced_prefetch_cycle() -> void:
	var game := _game("Verb", "Normal", "Lives")
	await process_frame
	await process_frame
	game.set_process(false)
	var previous: Array = (game.get("round_data") as Dictionary).get("options", []).duplicate()
	var saturated := {}
	for bank_topic in BANK.WORD_BANK:
		for word in BANK.WORD_BANK[bank_topic]:
			saturated[String(word).to_lower()] = true
	game.set("used_round_words", saturated)
	var cycle_before := int(game.get("_vocabulary_cycle"))
	var previous_progress := float(game.get("gate_progress"))
	var chosen: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
	_place_at_lane(game, int(chosen[0]))
	game.call("_advance_gate_step", 3.0)
	_check(int(game.get("_vocabulary_cycle")) == cycle_before + 1,
		"prefetch triggered exactly one cycle reset when the source pool is spent")
	_check(int(game.get("waves_completed")) == 0 and float(game.get("gate_progress")) > previous_progress,
		"prefetch stays offscreen until previous gate finishes")
	var pending: Dictionary = game.get("next_round_data")
	var options: Array = pending.get("options", [])
	_check(options.size() == 3, "prefetch always produces a fair genuine next question")
	for option in options:
		_check(String(option) not in previous,
			"prefetch excludes all actual previous displayed gate words")
	game.call("_advance_gate_step", 3.0)
	_check(int(game.get("waves_completed")) == 1 and
		int(game.get("score")) == 100 and
		int(game.get("lives")) == 3,
		"prefetched gate hands off after genuine answer line with +100")
	_check(int(game.get("_vocabulary_cycle")) == cycle_before + 1 and
		(game.get("round_data") as Dictionary).get("options", []) == options,
		"prefetched cycle is promoted once without generating a second round")
	game.queue_free()
	await process_frame
	await process_frame


func _restore_cycle_boundary() -> void:
	var game := _game("Noun", "Easy", "Lives", 410)
	await process_frame
	await process_frame
	game.set_process(false)
	var saturated := {}
	for bank_topic in BANK.WORD_BANK:
		for word in BANK.WORD_BANK[bank_topic]:
			saturated[String(word).to_lower()] = true
	game.set("used_round_words", saturated)
	game.call("_start_wave")
	_check(int(game.get("_vocabulary_cycle")) == 1,
		"restoration setup enters second vocabulary cycle")
	var before: Array = (game.get("round_data") as Dictionary).get("options", []).duplicate()
	var correct: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
	_place_at_lane(game, int(correct[0]))
	game.call("_resolve_at_answer_line")
	game.call("_pause")
	var snapshot: Dictionary = game.get_context()
	_check(int(snapshot.get("plane_vocabulary_cycle", -1)) == 1 and
		(snapshot.get("plane_previous_wave_words", []) as Array).size() == 3,
		"pause snapshot includes cycle number and last displayed trio")
	game.queue_free()
	await process_frame
	await process_frame
	# Prime's regression: set_context() may occur BEFORE add_child(). Never
	# dereference parallax @onready before its own scene is ready.
	var resumed := GAME.instantiate() as Control
	resumed.set_context(snapshot)
	root.add_child(resumed)
	resumed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	resumed.set_process(false)
	_check(not bool(resumed.get("finished")) and
		int(resumed.get("score")) == 510 and
		int(resumed.get("speed_boost_count")) == 1,
		"reconstructed scene retains active score/boost")
	_check(int(resumed.get("_vocabulary_cycle")) >= 1,
		"reconstructed scene retains vocabulary cycle index")
	var next_options: Array = (resumed.get("round_data") as Dictionary).get("options", [])
	_check(next_options.size() == 3, "resumed game still generates a fresh fair round")
	for option in next_options:
		_check(String(option) not in before, "reconstruction avoids previous visible trio")
	resumed.queue_free()
	await process_frame
	await process_frame


func _fallback_cycle_without_bank(mode: String) -> void:
	var game := _game("Pronoun", "Easy", mode)
	await process_frame
	await process_frame
	game.set_process(false)
	game.set("grammar_bank", null)
	var seen := {}
	var last_cycle := int(game.get("_vocabulary_cycle"))
	var previous: Array = []
	for index in range(45):
		game.call("_start_wave")
		var current_cycle := int(game.get("_vocabulary_cycle"))
		if current_cycle != last_cycle:
			for last_option in previous:
				_check(String(last_option) not in (game.get("round_data") as Dictionary).get("options", []),
					"fallback %s prevents adjacent-wave repeats where possible" % mode)
			seen.clear()
			last_cycle = current_cycle
		var data: Dictionary = game.get("round_data")
		var options: Array = data.get("options", [])
		var valid: Array = data.get("valid_indices", [])
		_check(options.size() == 3 and valid.size() >= 1 and valid.size() <= 2,
			"fallback %s still supplies complete 3-lane question" % mode)
		for option in options:
			var word := String(option).to_lower()
			_check(not seen.has(word), "fallback %s no repeats within vocabulary cycle" % mode)
			seen[word] = true
		previous = options.duplicate()
		_place_at_lane(game, int(valid[0]))
		var before := int(game.get("score"))
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == before + 100 and
			int(game.get("lives")) == 3 and not bool(game.get("finished")),
			"fallback %s real scoring never ends before mode rule" % mode)
	_check(int(game.get("_vocabulary_cycle")) >= 3,
		"fallback %s cycles repeatedly without underlying GrammarBank" % mode)
	if mode == "Seconds":
		game.call("_process", 59.9)
		_check(not bool(game.get("finished")), "fallback Seconds remains active until 60.0s")
		game.call("_process", 0.2)
		_check(bool(game.get("finished")) and
			is_zero_approx(float(game.get("time_remaining"))),
			"fallback Seconds ends only at 60.0s")
	else:
		game.call("_process", 150.0)
		_check(not bool(game.get("finished")) and int(game.get("lives")) == 3,
			"fallback Lives does not finish from time or vocabulary cycling")
	game.queue_free()
	await process_frame
	await process_frame


func _place_at_lane(game: Control, lane: int) -> void:
	var progress: float = game.call("_progress_for_answer_line")
	var rect: Rect2 = game.call("_gate_visible_rect", lane, progress)
	var left: Control = game.get_node("FlightPaths/PlaneLeftLimit")
	var right: Control = game.get_node("FlightPaths/PlaneRightLimit")
	var plane: Control = game.get_node("PlaneRig")
	var hitbox: Control = game.get_node("PlaneRig/Hitbox")
	var offset := hitbox.get_rect().get_center().x - plane.size.x * 0.5
	game.set("plane_x_norm", (rect.get_center().x - offset -
		float(game.get("_plane_authored_offset_x")) - left.get_rect().get_center().x) /
		(right.get_rect().get_center().x - left.get_rect().get_center().x))


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		if failures.size() < 45:
			printerr("HUMAN PLANE VOCAB CYCLE FAIL: ", message)
