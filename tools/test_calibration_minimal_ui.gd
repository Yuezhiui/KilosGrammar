extends SceneTree

# Godot --headless --path . --script res://tools/test_calibration_minimal_ui.gd
# Synthetic pose packets only. Does not start a real camera or fake a success
# in production; checks the actual calibration screen/state machine.

const SCENE := "res://ui/vision/calibration.tscn"
var failures: Array[String] = []
var checks := 0
var pose: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_assert(pose != null, "PoseService autoload is connected")
	if pose == null:
		quit(1)
		return
	pose.stop_camera()
	var packed := load(SCENE) as PackedScene
	_assert(packed != null, "Full-screen scene parses")
	if packed == null:
		quit(1)
		return
	var screen := packed.instantiate() as Control
	root.add_child(screen)
	var stage := screen.get_node("TutorialStage") as Control
	for removed in ["SkipButton", "RetryButton", "DemoButton", "KeyboardButton"]:
		_assert(stage.get_node_or_null(removed) == null, "Removed unwanted control: " + removed)
	_assert(stage.get_node_or_null("BackButton") is Button, "Teacher Back button remains editor-authored")
	_assert(stage.get_node_or_null("IntroOverlay/IntroBackButton") is Button, "Intro Back button remains editor-authored")
	_assert(not (stage.get_node("ContinueButton") as Button).visible, "Continue stays hidden with auto-advance")
	var new_dimmer := screen.get_node("ClassroomDimmer") as ColorRect
	_assert(new_dimmer.color.r <= 0.01 and new_dimmer.color.g <= 0.01
		and new_dimmer.color.b <= 0.01 and new_dimmer.color.a >= 0.0
		and new_dimmer.color.a <= 0.15,
		"New CALIB reference stays bright (at most 15% black dimming)")
	_assert(is_zero_approx((stage.get_node("IntroOverlay") as ColorRect).color.a), "Intro does not add a second dark overlay")
	_assert(bool(screen.get("intro_running")), "Intro begins first")
	for child in stage.get_children():
		if child is Control and child.name != "IntroOverlay":
			_assert(not (child as Control).visible, "HUD/guide hidden for intro: " + child.name)
	var routed: Array[Dictionary] = []
	screen.requested.connect(func(target: String, payload: Dictionary) -> void:
		routed.append({"target": target, "payload": payload}))
	screen.call("_continue_flow")
	screen.call("_continue_flow", true)
	_assert(routed.is_empty(), "No bypass without a real calibrated pose; legacy skip ignored")
	screen.call("_process", 2.6)
	_assert(not bool(screen.get("intro_running")), "Intro finishes after 2.5 s")
	_assert((stage.get_node("BackButton") as Button).visible, "Teacher Back is visible after intro")
	var zones := [
		stage.get_node("LeftCalibrationLane") as Control,
		stage.get_node("CenterCalibrationLane") as Control,
		stage.get_node("RightCalibrationLane") as Control
	]
	_check_one_zone(zones, 1, "CENTER")
	_assert(stage.get_node("LiveCameraInset") is TextureRect, "Live camera is an editor-authored TextureRect")
	_assert((stage.get_node("InstructionFIL") as Label).visible, "Filipino instruction visible")
	_assert(stage.get_node("StageHeading") is Label, "Gochi Hand stage title is scene-authored")
	_assert(stage.get_node("CountdownLabel") is Label, "Three-second countdown is scene-authored")
	# No context was supplied, so a screen inspection did not open a device.
	_assert(not bool(pose.get("active")), "Static scene inspection never starts the webcam")
	# Simulate fresh YOLO packets without launching a device: if camera state
	# disagrees or tracking goes stale, the state machine must refuse progress.
	pose.active = true
	pose.current_status = {"state": "tracking", "pose": true}
	for stage_x in [0.50, 0.79, 0.20]:
		for index in range(10):
			pose.player_x = stage_x + 0.002 * float(index % 2)
			pose.packet_sequence += 1
			pose.last_pose_ms = Time.get_ticks_msec()
			screen.call("_process", 0.40)
		var live_step := int(screen.get("live_step"))
		if stage_x == 0.50:
			_assert(live_step == 1, "CENTER saves only after real hold and fresh packets")
			_check_one_zone(zones, 2, "RIGHT")
		elif stage_x == 0.79:
			_assert(live_step == 2, "RIGHT saves only after real hold and fresh packets")
			_check_one_zone(zones, 0, "LEFT")
	_assert(bool(pose.calibration.get("valid", false)), "Three measured positions form valid calibration")
	_assert(int(screen.get("live_step")) == 3, "All steps measured")
	_assert(routed.is_empty(), "No gameplay request until completion transition")
	screen.call("set_context", {"guided_tutorial": true, "keyboard_mode": true, "camera_requested": false})
	_assert(not bool((screen.get("context") as Dictionary).get("keyboard_mode", true)), "Stale keyboard request is rejected")
	screen.call("_continue_flow")
	_assert(routed.size() == 1 and String(routed[0].get("target", "")) == "gameplay", "Guided success opens gameplay")
	if routed.size() == 1:
		var payload := routed[0]["payload"] as Dictionary
		_assert(bool(payload.get("guided_tutorial", false)), "Guided route is preserved")
		_assert(bool(payload.get("camera_live", false)), "Gameplay has real camera controls")
		_assert(not bool(payload.get("keyboard_mode", true)), "No keyboard fallback in payload")
		_assert(not bool(payload.get("calibration_skipped", true)), "Calibrated result is not skipped")
		_assert(bool(payload.get("start_countdown", false)), "Gameplay countdown begins once")
	screen.call("_continue_flow", true)
	_assert(routed.size() == 1, "Obsolete skip call cannot open a second route")
	screen.free()
	pose.stop_camera()
	# Normal Play uses the exact same calibrated-camera handoff, but no guided
	# overlay flag. Prefill only synthetic existing calibration for route QA.
	pose.active = true
	pose.player_x = 0.50
	pose.current_status = {"state": "tracking", "pose": true}
	pose.last_pose_ms = Time.get_ticks_msec()
	pose.calibration = {"left": 0.20, "center": 0.50, "right": 0.80, "valid": true}
	var regular := packed.instantiate() as Control
	root.add_child(regular)
	var normal_routes: Array[Dictionary] = []
	regular.requested.connect(func(target: String, payload: Dictionary) -> void:
		normal_routes.append({"target": target, "payload": payload}))
	regular.call("set_context", {"entry_source": "play", "keyboard_mode": true, "camera_requested": false})
	regular.call("_process", 2.6)
	regular.call("_continue_flow")
	_assert(normal_routes.size() == 1 and String(normal_routes[0].get("target", "")) == "gameplay", "Normal Play also routes to gameplay")
	if normal_routes.size() == 1:
		var normal_payload := normal_routes[0]["payload"] as Dictionary
		_assert(not bool(normal_payload.get("guided_tutorial", false)), "Normal play has no tutorial overlay flag")
		_assert(bool(normal_payload.get("camera_live", false)), "Normal play requires camera")
		_assert(not bool(normal_payload.get("keyboard_mode", true)), "Even stale keyboard entry never enables keyboard mode")
		_assert(bool(normal_payload.get("start_countdown", false)), "Normal play receives countdown")
	regular.call("_go_back")
	_assert(normal_routes.size() == 2 and String(normal_routes[1].get("target", "")) == "main", "Teacher Back returns Main")
	_assert(not bool(pose.get("active")), "Teacher Back stops camera")
	regular.free()
	pose.stop_camera()
	print("CALIBRATION MINIMAL UI: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check_one_zone(zones: Array, active_index: int, label: String) -> void:
	for index in range(zones.size()):
		_assert((zones[index] as Control).visible == (index == active_index),
			"%s stage displays only correct guide %d" % [label, index])


func _assert(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("FAIL calibration minimal UI: ", description)
