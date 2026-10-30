extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_mode_speed_lock_20261029.gd
# Scene-backed gate tests only; no camera, database, scene/PNG rewriting.
const SCENE := preload("res://ui/minigames/human_plane/human_plane.tscn")
const TIERS := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]
const TOPICS := ["Noun", "Verb", "Adjective", "Adverb", "Pronoun"]
const SPEEDS := {"Easy": 0.20, "Normal": 0.27, "Hard": 0.34}
const CEILINGS := {"Easy": 1.25, "Normal": 1.35, "Hard": 1.45}
const FIRST_BOOSTS := {"Easy": 0.05, "Normal": 0.07, "Hard": 0.09}

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for tier in TIERS:
		for mode in MODES:
			await _check_scoring_and_restore(tier, mode)
			await _check_ending(tier, mode)
	for mode in MODES:
		await _check_word_exhaustion(mode)
	for topic in TOPICS:
		for tier in TIERS:
			await _check_full_sixty_seconds(topic, tier)
	_check(float(SPEEDS["Easy"]) < float(SPEEDS["Normal"]) and
		float(SPEEDS["Normal"]) < float(SPEEDS["Hard"]),
		"base gate speed strictly increases by tier")
	print("HUMAN PLANE MODE/SPEED LOCK 20261029: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _make_game(tier: String, mode: String) -> Control:
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity": "Human Plane", "game_mode": mode,
		"topic": "Noun", "difficulty": tier, "score": 200})
	return game


func _check_scoring_and_restore(tier: String, mode: String) -> void:
	var label := "%s/%s" % [tier, mode]
	var game := _make_game(tier, mode)
	await process_frame
	await process_frame
	game.set_process(false)
	game.set_airplane_pose_active(true)
	var feedback := game.get_node_or_null("HUDLayer/HUD/FeedbackLabel") as Label
	_check(feedback == null, label + " unwanted duplicate FeedbackLabel is removed")
	_check(int(game.get("lives")) == 3, label + " starts with exactly three hearts")
	_check(is_zero_approx(float(game.get("time_remaining"))) if mode == "Lives" else
		float(game.get("time_remaining")) > 59.0, label + " correct mode time")
	_check(not (game.get_node("HUDLayer/HUD/LivesPlaque") as TextureRect).visible if mode == "Seconds" else
		(game.get_node("HUDLayer/HUD/LivesPlaque") as TextureRect).visible, label + " Hearts HUD only in Lives")
	var previous_gain := INF
	var last_speed := 1.0
	for correct in range(1, 7):
		game.call("_start_wave")
		var valid: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
		_check(not valid.is_empty(), label + " real grammar wave exists for hit %d" % correct)
		if valid.is_empty():
			break
		var lane := int(valid[0])
		_place_at_lane(game, lane)
		_check(int((game.get_node("HybridFlight3D") as Node2D).call("physical_lane_at_answer_line")) == lane,
			label + " correct airplane clears visible 3D arc %d" % correct)
		var old_points := int(game.get("score"))
		game.call("_resolve_at_answer_line")
		var expected := 1.0 + (float(CEILINGS[tier]) - 1.0) * (1.0 - pow(0.8, float(correct)))
		var actual := float(game.get("speed_multiplier"))
		_check(absf(actual - expected) < 0.0001, label + " diminishing permanent boost %d" % correct)
		_check(actual > last_speed and actual < float(CEILINGS[tier]) + 0.00001,
			label + " boost rises toward tier ceiling %d" % correct)
		var gain := actual - last_speed
		if correct == 1:
			_check(absf(gain - float(FIRST_BOOSTS[tier])) < 0.0001,
				label + " first correct grants tier's intended speed gain")
		else:
			_check(gain < previous_gain, label + " diminishing gain %d" % correct)
		previous_gain = gain
		last_speed = actual
		_check(int(game.get("score")) == old_points + 100, label + " correct awards exactly +100")
		_check(int(game.get("lives")) == 3, label + " correct does not affect hearts")
		_check("+100" in String(game.get("feedback_text")),
			label + " correct feedback remains in scoring/voice state without duplicate UI")
		_check(int(game.get("speed_boost_count")) == correct, label + " permanent boost count")
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == old_points + 100 and
			int(game.get("speed_boost_count")) == correct, label + " duplicate collision no double award")
		game.call("_start_wave")
		game.call("_advance_gate_step", 0.2)
		_check(absf(float(game.get("gate_progress")) - float(SPEEDS[tier]) * actual * 0.2) < 0.0001,
			label + " accelerated speed applies to gate approach")
		_check(is_equal_approx(float(game.BODY_MAX_TRAVEL_PER_SECOND), 0.82),
			label + " sideways pilot speed is not multiplied")

	var earned := float(game.get("speed_multiplier"))
	var points := int(game.get("score"))
	game.call("_start_wave")
	var valid: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
	var wrong := -1
	for lane in range(3):
		if lane not in valid:
			wrong = lane
			break
	_check(wrong >= 0, label + " real wave has wrong gate")
	if wrong >= 0:
		_place_at_lane(game, wrong)
		_check(int((game.get_node("HybridFlight3D") as Node2D).call("physical_lane_at_answer_line")) == wrong,
			label + " wrong gate detected by native 3D collision")
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == points, label + " wrong gate never deducts score")
		_check(int(game.get("lives")) == (3 if mode == "Seconds" else 2),
			label + " wrong gate only deducts Lives heart")
		_check(is_equal_approx(float(game.get("speed_multiplier")), earned),
			label + " wrong gate cannot lose earned speed")
		_check("TRY AGAIN" in String(game.get("feedback_text")),
			label + " wrong feedback remains in scoring/voice state without duplicate UI")
		game.call("_start_wave")
		game.set("plane_x_norm", -10.0)
		_check(int(game.call("_lane_hit_at_answer_line")) == -1,
			label + " offscreen plane misses all arcs")
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == points, label + " miss never deducts score")
		_check(int(game.get("lives")) == (3 if mode == "Seconds" else 1),
			label + " miss only deducts Lives heart")
		_check(is_equal_approx(float(game.get("speed_multiplier")), earned),
			label + " miss cannot lose permanent speed")
		_check("MISSED" in String(game.get("feedback_text")),
			label + " missed gate feedback remains in scoring/voice state without duplicate UI")
		game.call("_start_wave")
		game.call("_advance_gate_step", 0.2)
		_check(absf(float(game.get("gate_progress")) - float(SPEEDS[tier]) * earned * 0.2) < 0.0001,
			label + " approach speed survives wrong and miss")

	# The old wave count remains useful as a result statistic but cannot win
	# the game. In particular, advancing beyond the legacy target remains live.
	game.set("waves_completed", int(game.get("waves_total")) + 5)
	game.call("_start_wave")
	_check(not bool(game.get("finished")) and not (game.get("round_data") as Dictionary).is_empty(),
		label + " legacy wave target never ends game")
	game.call("_pause")
	var snapshot: Dictionary = game.get_context()
	_check(int(snapshot.get("plane_speed_boosts", 0)) == 6 and
		absf(float(snapshot.get("plane_speed_multiplier", 0.0)) - earned) < 0.0001,
		label + " paused payload retains boosts")
	_check(int(snapshot.get("waves_completed", 0)) > int(snapshot.get("total", 0)),
		label + " statistics do not clamp waves to old target")
	var used_before: Array = snapshot.get("plane_used_words", [])
	game.queue_free()
	await process_frame
	await process_frame
	var restored := SCENE.instantiate() as Control
	root.add_child(restored)
	restored.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	restored.set_context(snapshot)
	await process_frame
	await process_frame
	restored.set_process(false)
	_check(is_equal_approx(float(restored.get("speed_multiplier")), earned) and
		int(restored.get("speed_boost_count")) == 6,
		label + " reconstruction retains earned speed across pause")
	_check(int(restored.get("waves_completed")) > int(restored.get("waves_total")),
		label + " reconstructed wave count is not capped")
	_check(int(restored.get("score")) == points, label + " reconstruction retains integer score")
	_check(int(restored.get("lives")) == (3 if mode == "Seconds" else 1),
		label + " reconstruction retains mode's hearts")
	_check((restored.get("used_round_words") as Dictionary).size() >= used_before.size(),
		label + " already seen words remain excluded after reconstruction")
	var fresh: Array = (restored.get("round_data") as Dictionary).get("options", [])
	for option in fresh:
		_check(not used_before.has(String(option).to_lower()), label + " no word repeats across reconstruction")
	var alternate := "Normal" if tier == "Easy" else "Hard" if tier == "Normal" else "Easy"
	restored.set_context({"difficulty": alternate})
	var adjusted := 1.0 + (float(CEILINGS[alternate]) - 1.0) * (1.0 - pow(0.8, 6.0))
	_check(absf(float(restored.get("speed_multiplier")) - adjusted) < 0.0001 and
		int(restored.get("speed_boost_count")) == 6,
		label + " runtime difficulty change recalculates ceiling without losing boosts")
	restored.queue_free()
	await process_frame
	await process_frame


func _check_ending(tier: String, mode: String) -> void:
	var label := "ENDING %s/%s" % [tier, mode]
	var game := _make_game(tier, mode)
	var results: Array[Dictionary] = []
	game.requested.connect(func(destination: String, payload: Dictionary) -> void:
		if destination == "results":
			results.append(payload.duplicate(true))
	)
	await process_frame
	await process_frame
	game.set_process(false)
	if mode == "Seconds":
		# Even >wave target and repeated misses cannot end a timed session.
		game.set("waves_completed", int(game.get("waves_total")) + 12)
		game.call("_start_wave")
		for _n in range(3):
			game.set("plane_x_norm", -10.0)
			game.call("_resolve_at_answer_line")
			game.call("_start_wave")
		_check(int(game.get("lives")) == 3 and results.is_empty() and not bool(game.get("finished")),
			label + " neither 3 misses nor wave count ends Seconds")
		# Keep this isolated clock check free of random gate collisions.
		game.set("round_data", {})
		game.call("_process", 59.5)
		_check(results.is_empty() and not bool(game.get("finished")) and
			float(game.get("time_remaining")) > 0.0, label + " 59.5 seconds is still live")
		game.call("_process", 0.51)
		_check(results.size() == 1 and bool(game.get("finished")) and
			is_zero_approx(float(game.get("time_remaining"))), label + " ends exactly at zero timer")
	else:
		game.set("waves_completed", int(game.get("waves_total")) + 12)
		game.call("_start_wave")
		game.set("round_data", {})
		game.call("_process", 180.0)
		_check(results.is_empty() and not bool(game.get("finished")) and
			is_zero_approx(float(game.get("time_remaining"))),
			label + " Lives has no time or wave cutoff")
		# Real gates must deduct one heart each, including the last which must
		# emit results immediately at the collision, without waiting for fade.
		for remaining in [2, 1, 0]:
			game.call("_start_wave")
			game.set("plane_x_norm", -10.0)
			game.call("_resolve_at_answer_line")
			_check(int(game.get("lives")) == remaining,
				label + " missed gate decreases to %d lives" % remaining)
			_check(results.is_empty() if remaining > 0 else results.size() == 1,
				label + " ends only when the third heart is consumed")
		_check(bool(game.get("finished")) and results.size() == 1,
			label + " one final result event on Lives zero")
	game.call("_finish_round")
	_check(results.size() == 1, label + " results are never emitted twice")
	_check(int(results[0].get("score", -1)) == 200 and
		int(results[0].get("lives", -1)) == (3 if mode == "Seconds" else 0) and
		bool(results[0].get("round_completed", false)), label + " final result integer score, hearts and completion")
	game.queue_free()
	await process_frame
	await process_frame


func _check_word_exhaustion(mode: String) -> void:
	var game := _make_game("Easy", mode)
	var results: Array[Dictionary] = []
	game.requested.connect(func(destination: String, payload: Dictionary) -> void:
		if destination == "results":
			results.append(payload.duplicate(true))
	)
	await process_frame
	await process_frame
	game.set_process(false)
	# Saturate every authentic GrammarBank word to force the approved
	# replacement cycle. The new trio must still be real and exclude the
	# previous visible wave rather than fabricating a word or ending early.
	var previous: Array = (game.get("round_data") as Dictionary).get("options", []).duplicate()
	var cycle_before := int(game.get("_vocabulary_cycle"))
	var excluded := {}
	var bank: Script = game.get("grammar_bank") as Script
	for topic in bank.WORD_BANK:
		for word in bank.WORD_BANK[topic]:
			excluded[String(word).to_lower()] = true
	game.set("used_round_words", excluded)
	game.call("_start_wave")
	var hud := game.get_node_or_null("HUDLayer/HUD/FeedbackLabel")
	var replacement: Array = (game.get("round_data") as Dictionary).get("options", [])
	_check(not bool(game.get("_words_exhausted")) and
		replacement.size() == 3 and results.is_empty() and not bool(game.get("finished")),
		mode + " saturated pool safely cycles to a genuine new wave")
	_check(int(game.get("_vocabulary_cycle")) == cycle_before + 1,
		mode + " exhaustion starts one new vocabulary cycle")
	for word in replacement:
		_check(String(word) not in previous, mode + " prior displayed words excluded across cycle")
	_check(hud == null and String(game.get("feedback_text")) != "NO MORE UNIQUE WORDS",
		mode + " active replacement never displays no-question warning or duplicate feedback label")
	if mode == "Seconds":
		game.call("_process", 59.9)
		_check(results.is_empty() and not bool(game.get("finished")),
			mode + " recycled vocabulary never prematurely ends countdown")
		game.call("_process", 0.11)
		_check(results.size() == 1 and bool(game.get("finished")),
			mode + " recycled vocabulary ends only at sixty-second boundary")
	else:
		game.call("_process", 200.0)
		_check(results.is_empty() and not bool(game.get("finished")),
			mode + " recycled vocabulary does not fabricate a non-heart loss")
		game.call("_pause")
		_check(bool(game.get("paused")), mode + " teacher can pause a recycled pool")
	game.queue_free()
	await process_frame
	await process_frame


func _check_full_sixty_seconds(topic: String, tier: String) -> void:
	var label := "60s %s/%s" % [topic, tier]
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"game_mode": "Seconds", "topic": topic, "difficulty": tier})
	var results: Array[Dictionary] = []
	game.requested.connect(func(destination: String, payload: Dictionary) -> void:
		if destination == "results":
			results.append(payload.duplicate(true))
	)
	await process_frame
	await process_frame
	game.set_process(false)
	var seen := {}
	var last_wave := -1
	var cycle_at_last_wave := -1
	var last_visible_wave := {}
	for second in range(60):
		if int(game.get("waves_completed")) != last_wave:
			last_wave = int(game.get("waves_completed"))
			var vocabulary_cycle := int(game.get("_vocabulary_cycle"))
			var rolled_over := cycle_at_last_wave >= 0 and vocabulary_cycle != cycle_at_last_wave
			if vocabulary_cycle != cycle_at_last_wave:
				# Genuine GrammarBank words may recycle after their eligible tier
				# cannot form another fair three-lane question. They must remain
				# unique WITHIN each cycle, not forever in 60-second/Lives games.
				seen.clear()
				cycle_at_last_wave = vocabulary_cycle
			var options: Array = (game.get("round_data") as Dictionary).get("options", [])
			var current_visible := {}
			for option in options:
				var key := String(option).to_lower()
				_check(not seen.has(key), label + " no displayed words repeated WITHIN real GrammarBank cycle %d at second %d" % [vocabulary_cycle, second])
				if rolled_over and not last_visible_wave.is_empty():
					_check(not last_visible_wave.has(key), label + " no immediate boundary trio repeat")
				current_visible[key] = true
				seen[key] = true
			last_visible_wave = current_visible
		game.call("_process", 1.0)
		_check(int(game.get("lives")) == 3, label + " wrong/miss cannot decrement hearts")
		if second < 59:
			_check(not bool(game.get("finished")) and results.is_empty(),
				label + " remains live before 60 seconds, at second %d" % (second + 1))
	_check(bool(game.get("finished")) and results.size() == 1 and
		is_zero_approx(float(game.get("time_remaining"))),
		label + " ends at 60.0s with one result")
	_check(int(game.get("score")) == int(game.get("correct_count")) * 100,
		label + " all 60-second correct gates score exactly 100")
	_check(int(game.get("lives")) == 3 and int(results[0].get("lives", -1)) == 3,
		label + " final score payload retains fixed Seconds hearts")
	print("60s full flight: %s/%s, waves=%d, distinct_seen=%d, exhausted=%s" %
		[topic, tier, int(game.get("waves_completed")), seen.size(),
		str(bool(game.get("_words_exhausted")))])
	game.queue_free()
	await process_frame
	await process_frame


func _place_at_lane(game: Control, lane: int) -> void:
	var centers: PackedFloat32Array = game.call("_normalized_scoring_lane_centers",
		float(game.call("_progress_for_answer_line")))
	if centers.size() == 3:
		game.set("plane_x_norm", centers[lane])


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("HUMAN PLANE LOCK FAIL: ", description)
