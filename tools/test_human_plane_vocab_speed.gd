extends SceneTree

# Run: Godot --headless --path . --script res://tools/test_human_plane_vocab_speed.gd
# Covers real GrammarBank integration without modifying game source or other tests.
const PLANE := preload("res://ui/minigames/human_plane.tscn")
const BANK := preload("res://ui/minigames/grammar_bank.gd")
const TOPICS := ["Noun", "Verb", "Adjective"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const SPEEDS := {"Easy": 0.20, "Normal": 0.27, "Hard": 0.34}
const WAVES := {"Easy": 12, "Normal": 14, "Hard": 16}

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for topic in TOPICS:
		for difficulty in DIFFICULTIES:
			for mode in ["Seconds", "Lives"]:
				await _check_session(topic, difficulty, mode)
	await _check_short_fallback_exhaustion()
	await _check_long_word_render_fit()
	await _check_seconds_rebuild_from_pause()
	_check(float(SPEEDS["Hard"]) > float(SPEEDS["Normal"]) and float(SPEEDS["Normal"]) > float(SPEEDS["Easy"]), "gate speeds strictly increase with difficulty")
	print("HUMAN PLANE VOCAB/SPEED: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks, ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)


func _check_session(topic: String, difficulty: String, mode: String) -> void:
	var label := "%s %s %s" % [topic, difficulty, mode]
	var game := PLANE.instantiate() as Control
	if game == null or not game.has_method("set_context"):
		_check(false, label + " Human Plane gameplay script failed to load")
		if game != null:
			game.free()
		return
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {"activity": "Human Plane", "topic": topic, "difficulty": difficulty, "game_mode": mode})
	await process_frame
	await process_frame
	game.set_process(false)
	var bank := game.get("grammar_bank") as Script
	_check(bank != null and bank.has_method("lane_round"), label + " shared GrammarBank loaded")
	_check(int(game.get("waves_total")) == int(WAVES[difficulty]), label + " preserves wave count")
	_check(int(game.get("lives")) == 3, label + " 3 hearts in Seconds/Lives on every difficulty")
	_check(is_zero_approx(float(game.get("time_remaining"))) if mode == "Lives" else float(game.get("time_remaining")) > 59.0, label + " preserves selected timing rule")
	var seen := {}
	var expected_count := int(WAVES[difficulty])
	# Start includes the initial wave in `_ensure_started`. Continue through a
	# full session, bypassing only gate collision/timer to inspect vocabulary.
	for wave in range(expected_count):
		if wave > 0:
			game.set("waves_completed", wave)
			game.call("_start_wave")
		var data := game.get("round_data") as Dictionary
		var options: Array = data.get("options", [])
		_check(options.size() == 3, label + " wave %d has three displayed words" % [wave + 1])
		if options.size() != 3:
			break
		var valid: Array = data.get("valid_indices", [])
		_check(valid.size() in [1, 2], label + " wave %d contains valid answer indices" % [wave + 1])
		for index in range(options.size()):
			var word := String(options[index]).strip_edges().to_lower()
			_check(not word.is_empty(), label + " wave %d word is nonempty" % [wave + 1])
			_check(not seen.has(word), label + " never repeats '%s' in wave %d" % [word, wave + 1])
			seen[word] = true
			if bank != null:
				var matching := bool(bank.call("is_matching", word, topic))
				_check(matching == (index in valid), label + " wave %d '%s' grammar class matches valid lane" % [wave + 1, word])
			# Matching and distractor words from the three expanded topics must
			# actually be drawn from the selected (Easy/Normal/Hard) vocabulary tier.
			for bank_topic in TOPICS:
				if not BANK.WORD_BANK[bank_topic].has(word):
					continue
				var window: Vector2i = BANK.TIER_RANGES[bank_topic][difficulty]
				var tier_pool: Array = BANK.WORD_BANK[bank_topic].slice(window.x, window.y)
				_check(tier_pool.has(word), label + " wave %d '%s' uses correct %s tier" % [wave + 1, word, difficulty])
		_check((game.get("used_round_words") as Dictionary).size() == seen.size(), label + " wave %d maintains shared session exclusions" % [wave + 1])
		_check(int(game.get("score")) == 0 and int(game.get("attempts")) == 0, label + " vocabulary prep does not award score or deduct lives")
	_check(seen.size() == expected_count * 3, label + " entire round has %d distinct displayed words" % (expected_count * 3))
	_check(not bool(game.get("finished")), label + " full-length session does not exhaust selected vocabulary")
	# Confirm the actual gate velocity instead of just checking a configuration value.
	game.call("_start_wave")
	game.call("_update_gate_wave", 0.5)
	_check(absf(float(game.get("gate_progress")) - float(SPEEDS[difficulty]) * 0.5) < 0.0001, label + " live gate speed matches tier")
	# Defensive rejection of duplicate words, including case variations and
	# reusing a word that appeared in an earlier wave.
	_check(not bool(game.call("_round_is_valid", {"prompt": "p", "options": ["Book", "BOOK", "go"], "valid_indices": [0]})), label + " rejects duplicates within one wave")
	if not seen.is_empty():
		var previously := String(seen.keys()[0])
		_check(not bool(game.call("_round_is_valid", {"prompt": "p", "options": [previously, "freshword1", "freshword2"], "valid_indices": [0]})), label + " rejects previously displayed word")
	game.queue_free()
	await process_frame
	await process_frame
	print("Verified vocabulary: ", label, " (", seen.size(), " unique options)")


func _check_short_fallback_exhaustion() -> void:
	var game := PLANE.instantiate() as Control
	if game == null or not game.has_method("set_context"):
		_check(false, "Human Plane gameplay script failed to load for fallback test")
		if game != null:
			game.free()
		return
	root.add_child(game)
	game.call("set_context", {"topic": "Pronoun", "difficulty": "Easy", "game_mode": "Lives"})
	await process_frame
	await process_frame
	game.set_process(false)
	# Force the independent no-bank fallback to exercise small-word exhaustion.
	game.set("grammar_bank", null)
	game.set("used_round_words", {})
	var result_events: Array[Dictionary] = []
	game.requested.connect(func(target: String, _payload: Dictionary) -> void:
		if target == "results":
			result_events.append(_payload.duplicate(true))
	)
	var seen := {}
	for _wave in range(15):
		game.call("_start_wave")
		if bool(game.get("finished")):
			break
		var options: Array = (game.get("round_data") as Dictionary).get("options", [])
		for option in options:
			var word := String(option).strip_edges().to_lower()
			_check(not seen.has(word), "fallback never repeats the displayed '%s'" % word)
			seen[word] = true
	_check(bool(game.get("finished")), "fallback finishes when unique matching pool is exhausted")
	_check(result_events.size() == 1, "fallback emits exactly one results event on exhaustion")
	game.queue_free()
	await process_frame
	await process_frame


func _check_long_word_render_fit() -> void:
	var game := PLANE.instantiate() as Control
	if game == null or not game.has_method("_gate_word_fit"):
		_check(false, "Human Plane word-fitting helper failed to load")
		if game != null:
			game.free()
		return
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	for viewport_width in [1280, 1920]:
		var gate_width := float(viewport_width) * 0.09 # narrowest horizon gate
		for word in ["INTERDISCIPLINARY", "MISCHARACTERIZATION", "INCOMPREHENSIBILITY"]:
			var fit := game.call("_gate_word_fit", word, gate_width, 22) as Dictionary
			var effective := float(fit["rendered_width"])
			_check(effective <= gate_width * 0.88 + 0.001, "long word %s fits %.0f-pixel gate header" % [word, gate_width])
			_check(float(fit["scale_x"]) > 0.0 and float(fit["scale_x"]) <= 1.0, "long word '%s' uses valid horizontal fit" % word)
			_check(int(fit["font_size"]) >= 8, "long word '%s' keeps minimum font size" % word)
	game.queue_free()
	await process_frame
	await process_frame


func _check_seconds_rebuild_from_pause() -> void:
	# Legacy pause/rebuild callers may still reconstruct the scene from its
	# payload. The 60s start value must not erase genuine elapsed round time.
	var game := PLANE.instantiate() as Control
	root.add_child(game)
	game.call("set_context", {"topic": "Noun", "difficulty": "Normal", "game_mode": "Seconds", "time_remaining": 21.5})
	await process_frame
	await process_frame
	game.set_process(false)
	var remaining := float(game.get("time_remaining"))
	_check(remaining <= 21.5 and remaining >= 21.2, "restored Seconds clock respects a paused 21.5s payload")
	game.call("_pause")
	var pause_payload := game.call("get_context") as Dictionary
	game.queue_free()
	await process_frame
	await process_frame
	var resumed := PLANE.instantiate() as Control
	root.add_child(resumed)
	resumed.call("set_context", pause_payload)
	await process_frame
	await process_frame
	resumed.set_process(false)
	var resumed_remaining := float(resumed.get("time_remaining"))
	_check(resumed_remaining <= remaining and resumed_remaining >= remaining - 0.2, "recreated Seconds game retains elapsed round time")
	resumed.queue_free()
	await process_frame
	await process_frame


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("FAIL HumanPlane words: ", description)
