extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_calibration_human_plane_center_only.gd
# Regression for restored THREE measured Human Plane positions, with synthetic
# fresh student poses and no real camera or YOLO process.
const SCENE_PATH := "res://ui/vision/calibration.tscn"

var failures: Array[String] = []
var checks := 0
var pose: Node
var scene: PackedScene


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload is registered")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	scene = load(SCENE_PATH) as PackedScene
	_check(scene != null, "real calibration scene loads")
	if scene != null:
		await _test_plane_three_positions()
		await _test_legacy_three_positions("Catch the Word")
		await _test_legacy_three_positions("Balloon Popping")
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _test_plane_three_positions() -> void:
	_reset_synthetic_camera()
	var screen := _make_screen("Human Plane")
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target": target, "payload": payload}))
	var stage := screen.get_node("TutorialStage") as Control
	var badge := stage.get_node_or_null("PlaneStepBadge") as Control
	var center_lane := stage.get_node("CenterCalibrationLane") as Control
	var right_lane := stage.get_node("RightCalibrationLane") as Control
	var left_lane := stage.get_node("LeftCalibrationLane") as Control
	var back := stage.get_node("BackButton") as Button
	_check(screen.call("_capture_order") == ["CENTER", "RIGHT", "LEFT"],
		"Human Plane uses the same real CENTER, RIGHT, LEFT stages as Catch")
	_check(stage.get_node("IntroOverlay").visible, "Human Plane keeps the existing calibration intro")
	screen.call("_process", 2.51)
	_check(badge != null and not badge.visible,
		"obsolete CENTER ONLY plaque remains hidden without altering authored scene")
	_check((stage.get_node("ArtStep1") as Control).visible,
		"Human Plane uses the original editor-authored STEP 1 / 3 artwork")
	_check(center_lane.visible and not right_lane.visible and not left_lane.visible,
		"Human Plane starts with the center standing guide")
	_check(back.visible and not back.disabled and back.focus_mode == Control.FOCUS_ALL,
		"Back to Main stays enabled after intro")
	_check((stage.get_node("StepBadge") as Label).text == "STEP 1 / 3",
		"step indicator correctly describes three required holds")
	screen.call("_continue_flow", false)
	_check(routes.is_empty(), "live camera alone cannot skip any standing measurements")
	_check(pose.set_center_calibration(0.5),
		"legacy single-center PoseService calibration can still be constructed for regression")
	screen.call("_continue_flow", false)
	_check(routes.is_empty(), "stale single-center pose calibration cannot start Human Plane")
	pose.calibration.clear()

	for index in range(38):
		_fresh_pose(screen, 0.78)
	_check(int(screen.get("live_step")) == 0 and float(screen.get("live_timer")) == 0.0,
		"right-side packets do not satisfy the initial CENTER standing guide")
	for index in range(10):
		_fresh_pose(screen, 0.5)
	pose.set("current_status", {"state": "stale", "pose": false})
	screen.call("_process", 0.1)
	_check(int(screen.get("live_step")) == 0 and float(screen.get("live_timer")) == 0.0,
		"player tracking loss cancels partial center hold")
	_fresh_pose(screen, 0.5)
	for index in range(8):
		screen.call("_process", 0.1)
	_check(float(screen.get("live_timer")) == 0.0 and int(screen.get("live_step")) == 0,
		"stalled pose frames cannot finish center hold")

	for index in range(29):
		_fresh_pose(screen, 0.5)
	_check(int(screen.get("live_step")) == 0,
		"first CENTER stage requires a full 3-second hold with fresh frames")
	for index in range(3):
		_fresh_pose(screen, 0.5)
	_check(int(screen.get("live_step")) == 1 and right_lane.visible
		and not center_lane.visible and not left_lane.visible,
		"measured CENTER advances to RIGHT guide, without jumping to gameplay")
	_check((stage.get_node("ArtStep2") as Control).visible
		and not (stage.get_node("ArtStep1") as Control).visible
		and not badge.visible,
		"Human Plane displays original STEP 2 / 3 artwork and no center-only plaque")
	_check((stage.get_node("StageHeading") as Label).text.contains("RIGHT")
		and (stage.get_node("InstructionFIL") as Label).text.to_upper().contains("KANAN"),
		"Human Plane next-step guidance names RIGHT in both languages")
	_check(not bool((pose.get("calibration") as Dictionary).get("valid", false)),
		"CENTER alone cannot establish valid Human Plane movement limits")
	_check((screen.get("measured_points") as Dictionary).has("center")
		and not (screen.get("measured_points") as Dictionary).has("right"),
		"only CENTER is measured at first stage")
	screen.call("_continue_flow", false)
	_check(routes.is_empty(), "calibration cannot route after only CENTER")

	for index in range(34):
		_fresh_pose(screen, 0.5)
	_check(int(screen.get("live_step")) == 1 and float(screen.get("live_timer")) == 0.0,
		"standing in CENTER cannot satisfy required RIGHT measurements")
	for index in range(33):
		_fresh_pose(screen, 0.8)
	_check(int(screen.get("live_step")) == 2 and left_lane.visible
		and not center_lane.visible and not right_lane.visible,
		"fresh 3-second RIGHT hold advances to LEFT guide")
	_check((stage.get_node("ArtStep3") as Control).visible and not badge.visible,
		"Human Plane displays original STEP 3 / 3 artwork")
	_check((stage.get_node("StageHeading") as Label).text.contains("LEFT")
		and (stage.get_node("InstructionFIL") as Label).text.to_upper().contains("KALIWA"),
		"Human Plane next-step guidance names LEFT in both languages")
	_check((screen.get("measured_points") as Dictionary).has("right")
		and not (screen.get("measured_points") as Dictionary).has("left"),
		"RIGHT position is recorded independently of LEFT")
	screen.call("_continue_flow", false)
	_check(routes.is_empty(), "gameplay cannot start with LEFT still missing")
	for index in range(33):
		_fresh_pose(screen, 0.2)
	var measured := pose.get("calibration") as Dictionary
	var samples := screen.get("measured_points") as Dictionary
	_check(int(screen.get("live_step")) == 3 and bool(measured.get("valid", false))
		and not bool(measured.get("center_only", false)),
		"three real holds produce full measured PoseService calibration")
	_check(samples.has("left") and samples.has("center") and samples.has("right"),
		"all three body positions are measured instead of synthesized")
	_check(is_equal_approx(float(measured.get("left", -1.0)), 0.2)
		and is_equal_approx(float(measured.get("center", -1.0)), 0.5)
		and is_equal_approx(float(measured.get("right", -1.0)), 0.8),
		"measured bounds reflect actual left / center / right packet positions")
	_check(is_equal_approx(float(pose.call("normalized_body_x")), -1.0),
		"calibrated student's LEFT measured bound produces full left plane input")
	pose.set("player_x", 0.8)
	_check(is_equal_approx(float(pose.call("normalized_body_x")), 1.0),
		"calibrated student's RIGHT measured bound produces full right plane input")
	pose.set("player_x", 0.5)
	_check(is_zero_approx(float(pose.call("normalized_body_x"))),
		"calibrated student's actual CENTER measurement gives neutral plane input")
	_check(not center_lane.visible and not right_lane.visible and not left_lane.visible,
		"all standing guides clear after three completed holds")
	_check(not badge.visible and not (stage.get_node("ArtStep3") as Control).visible,
		"art completion clears all step badges")
	_check(not (screen.get("continue_button") as Button).disabled,
		"auto-progression is armed after the complete third hold")
	screen.call("_continue_flow", false)
	_check(routes.size() == 1 and String(routes[0].get("target", "")) == "gameplay",
		"full three-position calibration enters shared gameplay once")
	if routes.size() == 1:
		var payload := routes[0]["payload"] as Dictionary
		_check(not bool(payload.get("calibration_center_only", true))
			and bool(payload.get("calibration_measured", false))
			and bool(payload.get("camera_live", false))
			and not bool(payload.get("calibration_skipped", true)),
			"Human Plane payload declares genuine three-position live calibration")
		_check(String(payload.get("activity", "")) == "Human Plane"
			and is_equal_approx(float(payload.get("calibration_center", -1.0)), 0.5)
			and is_equal_approx(float(payload.get("calibration_left", -1.0)), 0.2)
			and is_equal_approx(float(payload.get("calibration_right", -1.0)), 0.8),
			"Human Plane gameplay receives three measured (not nominal) body bounds")
	await _dispose(screen)


func _test_legacy_three_positions(activity: String) -> void:
	_reset_synthetic_camera()
	var screen := _make_screen(activity)
	var stage := screen.get_node("TutorialStage") as Control
	var badge := stage.get_node("PlaneStepBadge") as Control
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target": target, "payload": payload}))
	screen.call("_process", 2.51)
	_check(screen.call("_capture_order") == ["CENTER", "RIGHT", "LEFT"],
		activity + ": retains its exact center/right/left stages")
	_check(not badge.visible and (stage.get_node("ArtStep1") as Control).visible,
		activity + ": original STEP 1/3 artwork is unchanged")
	for index in range(33):
		_fresh_pose(screen, 0.5)
	_check(int(screen.get("live_step")) == 1 and
			(stage.get_node("RightCalibrationLane") as Control).visible,
		activity + ": right position still follows center")
	_check((stage.get_node("ArtStep2") as Control).visible,
		activity + ": original STEP 2/3 artwork follows center")
	for index in range(33):
		_fresh_pose(screen, 0.8)
	_check(int(screen.get("live_step")) == 2 and
			(stage.get_node("LeftCalibrationLane") as Control).visible,
		activity + ": left position still follows right")
	for index in range(33):
		_fresh_pose(screen, 0.2)
	_check(int(screen.get("live_step")) == 3 and bool((pose.get("calibration") as Dictionary).get("valid", false))
		and not bool((pose.get("calibration") as Dictionary).get("center_only", false)),
		activity + ": three real positions still produce full body calibration")
	screen.call("_continue_flow", false)
	_check(routes.size() == 1 and String(routes[0].get("target", "")) == "gameplay",
		activity + ": retains successful gameplay routing")
	if routes.size() == 1:
		_check(not bool((routes[0]["payload"] as Dictionary).get("calibration_center_only", true)),
			activity + ": routed result still identifies three-position calibration")
	await _dispose(screen)


func _make_screen(activity: String) -> Control:
	var screen := scene.instantiate() as Control
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.set_context({"activity": activity, "camera_requested": true, "game_mode": "Seconds",
		"difficulty": "Easy", "topic": "Noun", "student_name": "QA STUDENT"})
	screen.set_process(false)
	return screen


func _fresh_pose(screen: Control, position: float, delta: float = 0.1) -> void:
	pose.set("active", true)
	pose.set("player_x", position)
	pose.set("last_pose_ms", Time.get_ticks_msec())
	pose.set("current_status", {"state": "tracking", "pose": true, "lock_state": "locked"})
	pose.set("packet_sequence", int(pose.get("packet_sequence")) + 1)
	screen.call("_process", delta)


func _reset_synthetic_camera() -> void:
	pose.stop_camera()
	pose.set_process(false)
	pose.set("active", true)
	pose.set("player_x", 0.5)
	pose.set("last_pose_ms", Time.get_ticks_msec())
	pose.set("packet_sequence", 0)
	pose.set("current_status", {"state": "tracking", "pose": true, "lock_state": "locked"})


func _dispose(screen: Control) -> void:
	screen.queue_free()
	await process_frame
	await process_frame


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _finish() -> void:
	for failure in failures:
		printerr("FAIL three-position Human Plane calibration: ", failure)
	print("%s three-position Human Plane calibration: %d checks, %d failures" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
