extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_calibration_human_plane_center_only.gd
# Regression for rejecting old floor-shift/center-only calibration on Human
# Plane. The separate center-only steering test verifies source packet rules.
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
		await _test_plane_rejects_legacy_floor_positions()
		await _test_legacy_three_positions("Catch the Word")
		await _test_legacy_three_positions("Balloon Popping")
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _test_plane_rejects_legacy_floor_positions() -> void:
	_reset_synthetic_camera()
	var screen := _make_screen("Human Plane")
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target": target, "payload": payload}))
	var stage := screen.get_node("TutorialStage") as Control
	screen.call("_process", 2.51)
	_check(screen.call("_capture_order") == ["CENTER"],
		"Human Plane requires only the real neutral hand-pose stage")
	var intro := stage.get_node_or_null("IntroOverlay/IntroDescription") as Label
	_check(intro != null and intro.text.contains("STAND CENTER"),
		"Human Plane guides student to begin centered with both hands visible")
	for position in [0.5, 0.8, 0.2]:
		for index in range(40):
			_fresh_pose(screen, position)
	_check(int(screen.get("live_step")) == 0 and
		(screen.get("measured_points") as Dictionary).is_empty(),
		"Unverified position-only samples cannot bypass live dual-wrist neutral hold")
	_check(not bool((pose.get("calibration") as Dictionary).get("valid", false)),
		"No fabricated bounds are inferred from moving across the camera")
	screen.call("_continue_flow", false)
	_check(routes.is_empty(), "Plane refuses gameplay without one verified source-pose hold")
	_check(pose.set_center_calibration(0.5),
		"Legacy center-only helper exists solely for rejection regression")
	screen.call("_continue_flow", false)
	_check(routes.is_empty(), "Center-only synthetic bounds cannot unlock Human Plane")
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
			(stage.get_node("ArtGuideRight") as Control).visible
			and not (stage.get_node("RightCalibrationLane") as Control).visible,
		activity + ": right position still follows center")
	_check((stage.get_node("ArtStep2") as Control).visible,
		activity + ": original STEP 2/3 artwork follows center")
	for index in range(33):
		_fresh_pose(screen, 0.8)
	_check(int(screen.get("live_step")) == 2 and
			(stage.get_node("ArtGuideLeft") as Control).visible
			and not (stage.get_node("LeftCalibrationLane") as Control).visible,
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
