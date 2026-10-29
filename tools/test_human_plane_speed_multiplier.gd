extends SceneTree

# Run without camera or database:
# Godot --headless --path . --script res://tools/test_human_plane_speed_multiplier.gd
const GAME := preload("res://ui/minigames/human_plane/human_plane.tscn")
const MODES := ["Seconds", "Lives"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const SPEEDS := {"Easy": 0.20, "Normal": 0.27, "Hard": 0.34}
const CEILINGS := {"Easy": 1.25, "Normal": 1.35, "Hard": 1.45}
const REMAINING_PER_CORRECT := 0.80
const EARNED_CORRECT_GATES := 24

var checked := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	# The active game is now a single editor-authored 2D scene. Archived 3D
	# FBX meshes/materials must never be dependencies of normal gameplay QA.
	for mode in MODES:
		for difficulty in DIFFICULTIES:
			await _check_round(mode, difficulty)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_real_2d()
	print("HUMAN PLANE SPEED BOOST: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checked, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _capture_real_2d() -> void:
	if DisplayServer.get_name() == "headless":
		_expect(false, "GPU capture must use OpenGL window, not headless")
		return
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(dimensions)
		root.content_scale_size = dimensions
		root.size = dimensions
		var scene := GAME.instantiate() as Control
		root.add_child(scene)
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scene.set_context({"activity": "Human Plane", "topic": "Noun",
			"game_mode": "Seconds", "difficulty": "Normal"})
		(scene.get_node("PlaneRig") as Control).visible = true
		for _frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		_expect(capture != null and capture.get_size() == dimensions,
			"original 2D plane and arc gate GPU screenshot at %s" % dimensions)
		if capture != null:
			var path := "user://_qa_human_plane_2d_speed_%dx%d.png" % [dimensions.x, dimensions.y]
			_expect(capture.save_png(path) == OK,
				"saved pure 2D screenshot at " + path)
			print("HUMAN PLANE 2D GPU: ", ProjectSettings.globalize_path(path))
		scene.queue_free()
		await process_frame
		await process_frame


func _check_round(mode: String, difficulty: String) -> void:
	var label := "%s/%s" % [mode, difficulty]
	var game := GAME.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_expect(game.get_node_or_null("WorldView3D") == null and
		game.get_node_or_null("FlightBackground") is TextureRect,
		label + " uses the one-scene 2D background instead of 3D view")
	game.set_context({"activity": "Human Plane", "topic": "Noun",
		"game_mode": mode, "difficulty": difficulty, "score": 240})
	await process_frame
	await process_frame
	game.set_process(false)
	var base := float(SPEEDS[difficulty])
	_expect(is_equal_approx(float(game.get("speed_multiplier")), 1.0), label + " starts at x1.0")
	_expect(int(game.get("speed_boost_count")) == 0, label + " no boost until correct")
	_expect(game.get_node_or_null("PlaneRig/PlaneArtwork") is TextureRect and
		game.get_node_or_null("MovingGates/GateCenter/GateArtwork") is TextureRect,
		label + " uses editor-authored 2D plane and original arc")
	game.call("_start_wave")
	game.call("_advance_gate_step", 0.1)
	_expect(absf(float(game.get("gate_progress")) - base * 0.1) < 0.0001,
		label + " base gate speed matches difficulty")
	game.call("_start_wave")

	var previous_multiplier := 1.0
	var previous_gain := INF
	for count in range(1, EARNED_CORRECT_GATES + 1):
		var valid: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
		_expect(not valid.is_empty(), label + " next wave has correct option " + str(count))
		if valid.is_empty():
			break
		_place_at_lane(game, int(valid[0]))
		var old_score := int(game.get("score"))
		var old_attempts := int(game.get("attempts"))
		game.call("_resolve_at_answer_line")
		var multiplier := _expected_multiplier(difficulty, count)
		var earned := float(game.get("speed_multiplier"))
		_expect(absf(earned - multiplier) < 0.00001,
			label + " correct #%d uses the difficulty-capped diminishing boost" % count)
		_expect(earned > previous_multiplier and earned <= float(CEILINGS[difficulty]) + 0.00001,
			label + " correct #%d permanently increases speed without exceeding cap" % count)
		var gain := earned - previous_multiplier
		if count == 1:
			var expected_first_gain := (float(CEILINGS[difficulty]) - 1.0) * (1.0 - REMAINING_PER_CORRECT)
			_expect(absf(gain - expected_first_gain) < 0.00001,
				label + " first correct gives exactly the configured +5/+7/+9 percent boost")
		else:
			_expect(gain > 0.0 and gain < previous_gain,
				label + " correct #%d earns a smaller positive boost than previous correct" % count)
		previous_gain = gain
		previous_multiplier = earned
		_expect(int(game.get("speed_boost_count")) == count, label + " boost counter persists")
		_expect(int(game.get("score")) == old_score + 100,
			label + " +100 points independently from speed")
		_expect(int(game.get("attempts")) == old_attempts + 1,
			label + " correct gate records exactly one scoring attempt")
		_expect(game.get_node_or_null("WorldView3D") == null,
			label + " earned boost never reintroduces the 3D world")
		game.call("_resolve_at_answer_line")
		_expect(absf(float(game.get("speed_multiplier")) - multiplier) < 0.00001
			and int(game.get("score")) == old_score + 100
			and int(game.get("attempts")) == old_attempts + 1,
			label + " idempotent collision awards speed only once")
		game.call("_start_wave")
		game.call("_advance_gate_step", 0.1)
		_expect(absf(float(game.get("gate_progress")) - base * multiplier * 0.1) < 0.0001,
			label + " actual gate movement accelerated after correct answer")
		# Keep this same newly created wave for the next answer. Generating a
		# second, unused wave here would waste unique GrammarBank words and make
		# the test itself (not actual student play) exhaust the tier prematurely.

	var earned := float(game.get("speed_multiplier"))
	_expect(earned <= float(CEILINGS[difficulty]) and
		float(CEILINGS[difficulty]) - earned < 0.003,
		label + " repeated earned answers approach, but never exceed, the cap")
	_expect(not bool(game.get("finished")),
		label + " completing many waves cannot end Seconds/Lives before its mode condition")
	var points := int(game.get("score"))
	var before_lives := int(game.get("lives"))
	var valid_indices: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
	var wrong := -1
	for i in range(3):
		if i not in valid_indices:
			wrong = i
			break
	_expect(wrong >= 0, label + " test word bank provides invalid answer")
	if wrong >= 0:
		_place_at_lane(game, wrong)
		game.call("_resolve_at_answer_line")
		_expect(int(game.get("score")) == points, label + " wrong answer does not subtract points")
		_expect(float(game.get("speed_multiplier")) == earned,
			label + " wrong answer never reduces accumulated boost")
		_expect(int(game.get("lives")) == (before_lives - 1 if mode == "Lives" else before_lives),
			label + " incorrect answer deducts one heart only in Lives")
		_expect(int(game.get("streak")) == 0, label + " streak resets separately from boost")
		game.call("_start_wave")
		game.set("plane_x_norm", -10.0)
		points = int(game.get("score"))
		game.call("_resolve_at_answer_line")
		_expect(int(game.get("score")) == points, label + " missed ring no point deduction")
		_expect(float(game.get("speed_multiplier")) == earned,
			label + " missed ring never reduces boost")
		_expect(int(game.get("lives")) == (before_lives - 2 if mode == "Lives" else before_lives),
			label + " missed ring deducts one heart only in Lives")
		_expect(not bool(game.get("finished")), label + " two misses cannot end the round early")
		game.call("_start_wave")
		game.call("_advance_gate_step", 0.1)
		_expect(absf(float(game.get("gate_progress")) - base * earned * 0.1) < 0.0001,
			label + " boosted movement resumes at earned speed after a miss")
	var saved: Dictionary = game.get_context()
	_expect(is_equal_approx(float(saved.get("plane_speed_multiplier", 0.0)), earned),
		label + " pause/results payload preserves current speed")
	_expect(int(saved.get("plane_speed_boosts", -1)) == EARNED_CORRECT_GATES,
		label + " pause/results payload preserves boost counter")
	game.queue_free()
	await process_frame
	await process_frame
	var resumed := GAME.instantiate() as Control
	root.add_child(resumed)
	resumed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resumed.set_context(saved)
	await process_frame
	await process_frame
	resumed.set_process(false)
	_expect(is_equal_approx(float(resumed.get("speed_multiplier")), earned),
		label + " resumed round retains earned speed despite reset streak")
	_expect(int(resumed.get("speed_boost_count")) == EARNED_CORRECT_GATES,
		label + " resumed round retains independent boost count")
	_expect(int(resumed.get("score")) == points,
		label + " resume retains exactly the score before the mode-specific ending")
	var result_events: Array[Dictionary] = []
	resumed.requested.connect(func(target: String, payload: Dictionary) -> void:
		if target == "results":
			result_events.append(payload.duplicate(true)))
	if mode == "Seconds":
		_expect(int(resumed.get("lives")) == 3 and float(resumed.get("time_remaining")) > 59.0,
			label + " restored Seconds round still has all three inert hearts and a real 60s clock")
		resumed.call("_process", 59.0)
		_expect(not bool(resumed.get("finished")) and result_events.is_empty()
			and float(resumed.get("time_remaining")) > 0.0,
			label + " Seconds cannot end at 59 seconds even after all earned speed boosts")
		resumed.call("_process", 1.1)
		_expect(bool(resumed.get("finished")) and is_zero_approx(float(resumed.get("time_remaining")))
			and result_events.size() == 1 and int(resumed.get("lives")) == 3,
			label + " Seconds finishes exactly when timer reaches zero without heart loss")
	else:
		_expect(int(resumed.get("lives")) == 1 and is_zero_approx(float(resumed.get("time_remaining"))),
			label + " restored Lives round has one heart remaining and NO timer")
		resumed.set("plane_x_norm", -10.0)
		resumed.call("_resolve_at_answer_line")
		_expect(bool(resumed.get("finished")) and int(resumed.get("lives")) == 0
			and result_events.size() == 1,
			label + " third actual miss (zero hearts) ends Lives exactly once")
	_expect(int(resumed.get("score")) == points and
		absf(float(resumed.get("speed_multiplier")) - earned) < 0.00001,
		label + " mode-specific ending preserves cumulative correct-only speed and score")
	resumed.call("_process", 1.0)
	_expect(result_events.size() == 1, label + " finished game emits Results only once")
	resumed.queue_free()
	await process_frame
	await process_frame


func _expected_multiplier(difficulty: String, correct_gates: int) -> float:
	var ceiling := float(CEILINGS[difficulty])
	return 1.0 + (ceiling - 1.0) * (1.0 - pow(REMAINING_PER_CORRECT, correct_gates))


func _place_at_lane(game: Control, lane: int) -> void:
	var progress: float = game.call("_progress_for_answer_line")
	var rect: Rect2 = game.call("_gate_visible_rect", lane, progress)
	var left: Control = game.get_node("FlightPaths/PlaneLeftLimit")
	var right: Control = game.get_node("FlightPaths/PlaneRightLimit")
	var plane: Control = game.get_node("PlaneRig")
	var box: Control = game.get_node("PlaneRig/Hitbox")
	var offset := box.get_rect().get_center().x - plane.size.x * 0.5
	var left_x := left.get_rect().get_center().x
	var right_x := right.get_rect().get_center().x
	game.set("plane_x_norm", (rect.get_center().x - offset -
		float(game.get("_plane_authored_offset_x")) - left_x) / (right_x - left_x))


func _expect(ok: bool, description: String) -> void:
	checked += 1
	if not ok:
		failures.append(description)
		printerr("SPEED BOOST FAIL: ", description)
