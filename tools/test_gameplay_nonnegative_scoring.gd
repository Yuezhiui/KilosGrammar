extends SceneTree

# Regression: Human Plane never deducts points for an incorrect or missed gate.
# Godot 4.7.2 --headless --path . --script res://tools/test_gameplay_nonnegative_scoring.gd
# Real PackedScene logic, synthetic inputs, no camera/DB or wrapper side effects.
const SCENE := preload("res://ui/minigames/human_plane.tscn")
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]
const INITIAL_SCORE := 325
const CORRECT_POINTS := 100

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dimensions in VIEWPORTS:
		for mode in MODES:
			for difficulty in DIFFICULTIES:
				await _exercise(dimensions, mode, difficulty)
	print("HUMAN PLANE NO SCORE DEDUCTION: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _exercise(dimensions: Vector2i, mode: String, difficulty: String) -> void:
	root.content_scale_size = dimensions
	root.size = dimensions
	var prefix := "%dx%d %s/%s" % [dimensions.x, dimensions.y, mode, difficulty]
	var game := SCENE.instantiate() as Control
	_check(game != null, prefix + " Human Plane scene loads")
	if game == null:
		return
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {"activity": "Human Plane", "topic": "Noun",
		"difficulty": difficulty, "game_mode": mode, "score": INITIAL_SCORE,
		"camera_live": false})
	await process_frame
	await process_frame
	game.set_process(false)
	_check(int(game.get("score")) == INITIAL_SCORE, prefix + " restores positive starting score")
	_check(int(game.get("lives")) == 3, prefix + " retains exactly three hearts")
	_check(absf(float(game.get("time_remaining")) - 60.0) < 1.0 if mode == "Seconds"
		else is_zero_approx(float(game.get("time_remaining"))), prefix + " uses native time mode")

	game.call("_start_wave")
	var data: Dictionary = game.get("round_data")
	var valid: Array = data.get("valid_indices", [])
	var wrong_lane := -1
	for lane in range(3):
		if lane not in valid:
			wrong_lane = lane
			break
	_check(wrong_lane >= 0, prefix + " current wave includes an incorrect gate")
	if wrong_lane >= 0:
		_check(_select_lane(game, wrong_lane), prefix + " incorrect ring is reachable")
		if int(game.call("_lane_hit_at_answer_line")) == wrong_lane:
			var original_lives := int(game.get("lives"))
			game.call("_resolve_at_answer_line")
			_check(int(game.get("score")) == INITIAL_SCORE,
				prefix + " wrong grammar answer NEVER deducts earned points")
			_check(int(game.get("lives")) == original_lives - 1 and int(game.get("attempts")) == 1,
				prefix + " wrong answer still records one attempt and one life")
			game.call("_resolve_at_answer_line")
			_check(int(game.get("score")) == INITIAL_SCORE and int(game.get("attempts")) == 1,
				prefix + " duplicate wrong ring cannot deduct or repeat attempt")

	game.call("_start_wave")
	game.set("plane_x_norm", -10.0)
	_check(int(game.call("_lane_hit_at_answer_line")) == -1, prefix + " deliberately misses all rings")
	var before_miss_lives := int(game.get("lives"))
	game.call("_resolve_at_answer_line")
	_check(int(game.get("score")) == INITIAL_SCORE,
		prefix + " missed gate NEVER deducts earned points")
	_check(int(game.get("lives")) == before_miss_lives - 1 and int(game.get("attempts")) == 2,
		prefix + " missed gate consumes only the intended life")
	game.call("_resolve_at_answer_line")
	_check(int(game.get("score")) == INITIAL_SCORE and int(game.get("attempts")) == 2,
		prefix + " duplicate missed collision is idempotent")

	game.call("_start_wave")
	data = game.get("round_data")
	valid = data.get("valid_indices", [])
	_check(not valid.is_empty(), prefix + " new wave includes a correct gate")
	if not valid.is_empty():
		var right_lane := int(valid[0])
		_check(_select_lane(game, right_lane), prefix + " correct ring is reachable")
		if int(game.call("_lane_hit_at_answer_line")) == right_lane:
			game.call("_resolve_at_answer_line")
			_check(int(game.get("score")) == INITIAL_SCORE + CORRECT_POINTS,
				prefix + " first correct answer grants exactly +100")
			game.call("_resolve_at_answer_line")
			_check(int(game.get("score")) == INITIAL_SCORE + CORRECT_POINTS and int(game.get("attempts")) == 3,
				prefix + " duplicate correct ring cannot award points twice")
			var payload: Dictionary = game.call("get_context")
			var score_label := game.get_node_or_null("HUDLayer/HUD/ScoreBottomContainer/ScoreNumber") as Label
			_check(int(payload.get("score", -1)) == INITIAL_SCORE + CORRECT_POINTS and
				(score_label != null and score_label.text == str(INITIAL_SCORE + CORRECT_POINTS)),
				prefix + " results payload and HUD show the same non-deducted score")

	game.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(game), prefix + " releases game safely")


func _select_lane(game: Control, lane: int) -> bool:
	# Scan true scoring hitboxes so these checks detect visual/logical mismatch.
	for candidate in range(301):
		game.set("plane_x_norm", float(candidate) / 300.0)
		if int(game.call("_lane_hit_at_answer_line")) == lane:
			return true
	return false


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("HUMAN PLANE NO DEDUCTION FAIL: ", description)
