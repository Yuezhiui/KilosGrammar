extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_fixed_score_speed.gd
# Exercises real authored gates in both game modes, without a camera or database.
const GAME_SCENE := preload("res://ui/minigames/human_plane.tscn")
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]
const EXPECTED_SPEEDS := {"Easy": 0.20, "Normal": 0.27, "Hard": 0.34}
const START_SCORE := 250
const CORRECT_POINTS := 100

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for mode in MODES:
		for difficulty in DIFFICULTIES:
			await _check_game(mode, difficulty)
	_check(float(EXPECTED_SPEEDS["Easy"]) < float(EXPECTED_SPEEDS["Normal"])
		and float(EXPECTED_SPEEDS["Normal"]) < float(EXPECTED_SPEEDS["Hard"]),
		"gate speed strictly increases from Easy to Hard")
	print("HUMAN PLANE FIXED SCORE/SPEED: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check_game(mode: String, difficulty: String) -> void:
	var label := "%s/%s" % [mode, difficulty]
	var game := GAME_SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {"activity": "Human Plane", "topic": "Noun",
		"difficulty": difficulty, "game_mode": mode, "score": START_SCORE})
	await process_frame
	await process_frame
	game.set_process(false)
	_check(bool(game.get("started")) and not bool(game.get("finished")), label + " game starts")
	_check(int(game.get("score")) == START_SCORE, label + " previously earned score is restored")
	_check(int(game.get("lives")) == 3, label + " starts with three lives")
	_check(bool(game.get("is_lives_mode")) == (mode == "Lives"), label + " mode retained")
	_check(bool(game.get("airplane_pose_active")) == false, label + " camera pose gate remains inactive by default")

	# Exercise actual advancing gate movement, including the scene-based wave.
	game.call("_start_wave")
	game.call("_update_gate_wave", 0.5)
	var progress := float(game.get("gate_progress"))
	_check(absf(progress - float(EXPECTED_SPEEDS[difficulty]) * 0.5) < 0.0001,
		label + " advances at difficulty-specific gate speed")
	game.call("_start_wave")

	# A three-answer streak must always grant the same points per correct gate.
	for correct_number in range(1, 4):
		var valid: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
		_check(not valid.is_empty(), label + " wave has a valid answer")
		if valid.is_empty():
			break
		var lane := int(valid[0])
		_place_at_lane(game, lane)
		_check(int(game.call("_lane_hit_at_answer_line")) == lane,
			label + " real collision hits correct gate on streak %d" % correct_number)
		var old_score := int(game.get("score"))
		game.call("_resolve_at_answer_line")
		_check(bool(game.get("selected_was_correct")), label + " recognizes valid gate")
		_check(int(game.get("score")) - old_score == CORRECT_POINTS,
			label + " awards exactly +100 on correct streak %d" % correct_number)
		_check(int(game.get("streak")) == correct_number, label + " streak still counts")
		_check(int(game.get("correct_count")) == correct_number, label + " correct count still counts")
		_check(String(game.get("feedback_text")).begins_with("+100"), label + " feedback says +100")
		_check((game.get_node("HUDLayer/HUD/ScoreBottomContainer/ScoreNumber") as Label).text == str(game.get("score")),
			label + " HUD displays whole-number score")
		var payload: Dictionary = game.call("get_context")
		_check(int(payload.get("score", -1)) == int(game.get("score")) and
			typeof(payload.get("score")) == TYPE_INT, label + " result payload stores integer score")
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == old_score + CORRECT_POINTS,
			label + " repeated collision cannot grant points twice")
		game.call("_start_wave")

	# Existing wrong and missed gate penalties, hearts and streak reset stay intact.
	var invalid := -1
	var valid: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
	for lane in range(3):
		if lane not in valid:
			invalid = lane
			break
	_check(invalid >= 0, label + " has a wrong option")
	if invalid >= 0:
		_place_at_lane(game, invalid)
		_check(int(game.call("_lane_hit_at_answer_line")) == invalid, label + " collides with wrong gate")
		var before_wrong := int(game.get("score"))
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == maxi(before_wrong - 40, 0), label + " wrong gate retains -40 penalty")
		_check(int(game.get("lives")) == 2 and int(game.get("streak")) == 0,
			label + " wrong gate loses one life and breaks streak")
		game.call("_start_wave")
		game.set("plane_x_norm", -10.0)
		_check(int(game.call("_lane_hit_at_answer_line")) == -1, label + " offscreen plane misses all gates")
		var before_miss := int(game.get("score"))
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == maxi(before_miss - 20, 0), label + " miss retains -20 penalty")
		_check(int(game.get("lives")) == 1, label + " miss loses exactly one life")
		game.call("_start_wave")
		valid = (game.get("round_data") as Dictionary).get("valid_indices", [])
		if not valid.is_empty():
			_place_at_lane(game, int(valid[0]))
			var after_penalty := int(game.get("score"))
			game.call("_resolve_at_answer_line")
			_check(int(game.get("score")) == after_penalty + CORRECT_POINTS,
				label + " correct gate after penalty still grants +100")
			_check(int(game.get("lives")) == 1, label + " correct gate does not restore or deduct lives")
	game.queue_free()
	await process_frame
	await process_frame


func _place_at_lane(game: Control, lane: int) -> void:
	# Match the rendered PNG collision box and actual authored flight limits.
	var progress := float(game.call("_progress_for_answer_line"))
	var rect: Rect2 = game.call("_gate_visible_rect", lane, progress)
	var left: Control = game.get_node("FlightPaths/PlaneLeftLimit")
	var right: Control = game.get_node("FlightPaths/PlaneRightLimit")
	var plane_rig: Control = game.get_node("PlaneRig")
	var hitbox: Control = game.get_node("PlaneRig/Hitbox")
	var hitbox_offset := hitbox.get_rect().get_center().x - plane_rig.size.x * 0.5
	var left_x := left.get_rect().get_center().x
	var right_x := right.get_rect().get_center().x
	var authored_offset := float(game.get("_plane_authored_offset_x"))
	game.set("plane_x_norm", (rect.get_center().x - hitbox_offset - authored_offset - left_x) / (right_x - left_x))


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("HUMAN PLANE FIXED SCORE FAIL: ", label)
