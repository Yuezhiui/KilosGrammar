extends SceneTree

# Godot --headless --path . --script res://tools/test_calibration_single_guide.gd
# Synthetic PoseService data is for deterministic tests only. Runtime captures
# still require the real locked player and live YOLO pose packets.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var pose := root.get_node("PoseService")
	pose.active = true
	pose.calibration.clear()
	pose.player_x = 0.5
	pose.current_status = {"state": "tracking", "pose": true}
	pose.last_pose_ms = Time.get_ticks_msec()
	var scene := load("res://ui/vision/calibration.tscn") as PackedScene
	var calibration := scene.instantiate() as Control
	root.add_child(calibration)
	calibration.set_context({"guided_tutorial": true, "camera_requested": false, "keyboard_mode": false})
	var stage := calibration.get_node("TutorialStage")
	var guides: Array[Control] = [
		stage.get_node("LeftCalibrationLane") as Control,
		stage.get_node("CenterCalibrationLane") as Control,
		stage.get_node("RightCalibrationLane") as Control
	]
	var countdown := stage.get_node_or_null("CountdownLabel") as Label
	var step_badge := stage.get_node_or_null("StepBadge") as Label
	var english := stage.get_node_or_null("InstructionEN") as Label
	var filipino := stage.get_node_or_null("InstructionFIL") as Label
	_check(countdown != null, "Top-right countdown is an editor-authored Label")
	_check(step_badge != null, "Step badge is an editor-authored Label")
	_check(english != null and filipino != null, "English/Filipino labels are editor-authored")
	_check(stage.get_node("LiveCameraInset") is TextureRect, "Camera inset is editor-authored")
	_check(not (calibration.get("continue_button") as Button).visible, "Continue is hidden; calibration auto-advances")
	_check(bool(calibration.get("intro_running")), "Intro begins before pose capture")
	_check((calibration.get("intro_overlay") as Control).visible, "2.5-second intro overlay appears")
	var intro := calibration.get("intro_overlay") as Control
	var intro_back := stage.get_node("IntroOverlay/IntroBackButton") as Button
	_check(intro_back.visible and not intro_back.disabled, "Intro Back to Main is visible and clickable")
	for child in stage.get_children():
		if child is Control and child != intro:
			_check(not (child as Control).visible, "Intro hides all authored main-scene controls: " + child.name)
	_check(is_equal_approx((intro as ColorRect).color.a, 0.0), "Intro adds no second dark overlay to the classroom")
	var dim := (calibration.get_node("ClassroomDimmer") as ColorRect).color
	_check(is_zero_approx(dim.r) and is_zero_approx(dim.g) and is_zero_approx(dim.b) and dim.a >= 0.0 and dim.a <= 0.15,
		"New CALIB classroom remains bright with a subtle black overlay")
	var unused_before := (stage.get_node("Heading") as Label).visible
	# A live camera image arriving during intro must not resurrect the hidden
	# camera feed as a translucent ghost underneath CALIBRATION.
	var test_image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var test_texture := ImageTexture.create_from_image(test_image)
	calibration.call("_on_live_preview", test_texture)
	_check(not (stage.get_node("LiveCameraInset") as TextureRect).visible, "Intro suppresses live-video callbacks")
	calibration.call("_process", 2.6)
	_check(not bool(calibration.get("intro_running")), "Intro finishes at 2.5 seconds")
	_check(not intro.visible, "Intro overlay closes")
	_check((stage.get_node("BackButton") as Button).visible, "Main Back button restored after intro")
	for removed in ["DemoButton", "RetryButton", "SkipButton", "KeyboardButton"]:
		_check(stage.get_node_or_null(removed) == null, "Forbidden control removed: " + removed)
	_check(not (stage.get_node("Heading") as Label).visible and not unused_before, "Editor-hidden legacy header stays hidden")
	_check((stage.get_node("LiveCameraInset") as TextureRect).visible, "Buffered live video reappears after intro")
	_check(not (stage.get_node("InstructionEN") as Label).visible, "Duplicate English instruction remains hidden")
	_check((stage.get_node("InstructionFIL") as Label).visible, "Filipino instruction visible after intro")
	_assert_only_active(guides, 1, "CENTER guide")
	if step_badge != null:
		_check(step_badge.text == "STEP 1 / 3", "First stage updates authored step badge")
		calibration.set("live_step", 2)
		calibration.call("_update_target_guide")
		_check(step_badge.text == "STEP 3 / 3", "Standalone guide refresh updates badge after synthetic stage change")
		calibration.set("live_step", 0)
		calibration.call("_update_target_guide")
		_check(step_badge.text == "STEP 1 / 3", "Returning to center refreshes badge without stage function")
	_assert_only_active(guides, 1, "CENTER after synthetic step reset")
	_check((stage.get_node("StageHeading") as Label).text == "STAY IN THE CENTER", "Large header shows English instruction, not duplicate step")
	if english != null:
		_check(english.text == "STAY IN THE CENTER", "Center English prompt")
	if filipino != null:
		_check(filipino.text == "Manatili sa gitna", "Center Filipino prompt")

	# The countdown starts only with a real incoming pose packet. Movement
	# resets it, and static old packets must never keep accumulating time.
	calibration.call("_reset_current_hold")
	if countdown != null:
		_check(not countdown.visible, "Countdown hidden until stable valid pose")
	_send_pose(pose, calibration, 0.50, 0.42)
	if countdown != null:
		_check(countdown.visible and countdown.text == "3", "Stable pose begins 3-second countdown")
	pose.player_x = 0.74
	pose.packet_sequence += 1
	pose.last_pose_ms = Time.get_ticks_msec()
	calibration.call("_process", 0.22)
	_check(is_zero_approx(float(calibration.get("live_timer"))), "Leaving CENTER resets the clock")
	if countdown != null:
		_check(not countdown.visible, "Countdown vanishes on invalid zone")
	_send_pose(pose, calibration, 0.50, 0.42)
	calibration.call("_process", 0.45)
	calibration.call("_process", 0.45)
	_check(is_zero_approx(float(calibration.get("live_timer"))), "Stale packet resets the hold")
	if countdown != null:
		_check(not countdown.visible, "Stale pose hides the countdown")

	# Ten incoming stable samples over 3 seconds are sufficient; no false
	# timer/score/lives can be taken because gameplay has not yet mounted.
	for sample in range(10):
		_send_pose(pose, calibration, 0.50 + 0.002 * float(sample % 2), 0.4)
	_check(int(calibration.get("live_step")) == 1, "CENTER advances only after 3s and at least 8 frames")
	_assert_only_active(guides, 2, "RIGHT guide")
	if step_badge != null:
		_check(step_badge.text == "STEP 2 / 3", "Second stage updates authored step badge")
	if english != null:
		_check(english.text == "MOVE TO THE RIGHT", "Right English prompt")
	if filipino != null:
		_check(filipino.text == "Gumalaw sa kanan", "Right Filipino prompt")
	for sample in range(10):
		_send_pose(pose, calibration, 0.79 + 0.002 * float(sample % 2), 0.4)
	_check(int(calibration.get("live_step")) == 2, "RIGHT advances after stable hold")
	_assert_only_active(guides, 0, "LEFT guide")
	if step_badge != null:
		_check(step_badge.text == "STEP 3 / 3", "Third stage updates authored step badge")
	if english != null:
		_check(english.text == "MOVE TO THE LEFT", "Left English prompt")
	if filipino != null:
		_check(filipino.text == "Gumalaw sa kaliwa", "Left Filipino prompt")
	for sample in range(10):
		_send_pose(pose, calibration, 0.20 + 0.002 * float(sample % 2), 0.4)
	_check(bool(pose.calibration.get("valid", false)), "CENTER RIGHT LEFT measurements become valid")
	_assert_only_active(guides, -1, "Completed calibration hides all standing guides")
	_check(bool(calibration.get("transition_queued")), "Automatic transition is scheduled")
	_check(not (calibration.get("continue_button") as Button).visible, "Continue stays hidden after success")
	# If the pose drops during the success transition, the same locked
	# student can return and trigger another automatic handoff.
	calibration.set("transition_queued", false)
	calibration.call("_process", 0.016)
	_check(bool(calibration.get("transition_queued")), "Valid pose can restart a disrupted auto-handoff")
	var requests: Array[Dictionary] = []
	calibration.requested.connect(func(route: String, payload: Dictionary) -> void:
		requests.append({"route": route, "payload": payload}))
	calibration.call("_continue_flow", false)
	_check(requests.size() == 1 and requests[0]["route"] == "gameplay", "Live calibrated flow opens gameplay")
	if requests.size() == 1:
		var payload: Dictionary = requests[0]["payload"]
		_check(bool(payload.get("guided_tutorial", false)), "Guided flag preserved")
		_check(bool(payload.get("start_countdown", false)), "Gameplay receives one countdown flag")
		_check(bool(payload.get("camera_live", false)), "Valid camera tracking preserved for game")
	calibration.free()
	pose.stop_camera()
	# The intro's only clickable Back button cancels capture immediately;
	# no footer button is exposed before the 2.5-second transition.
	pose.active = true
	var intro_back_scene := scene.instantiate() as Control
	root.add_child(intro_back_scene)
	var intro_back_request := []
	intro_back_scene.requested.connect(func(route: String, _payload: Dictionary) -> void:
		intro_back_request.append(route))
	(intro_back_scene.get_node("TutorialStage/IntroOverlay/IntroBackButton") as Button).pressed.emit()
	_check(intro_back_request == ["main"], "Intro Back to Main routes directly to Main")
	_check(not pose.active, "Intro Back to Main stops camera capture")
	intro_back_scene.free()
	print("CALIBRATION SINGLE GUIDE: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	for failure in failures:
		printerr("FAIL calibration single guide: ", failure)
	quit(0 if failures.is_empty() else 1)


func _send_pose(pose: Node, calibration: Control, x: float, delta: float) -> void:
	pose.player_x = x
	pose.packet_sequence += 1
	pose.last_pose_ms = Time.get_ticks_msec()
	calibration.call("_process", delta)


func _assert_only_active(guides: Array[Control], active: int, description: String) -> void:
	for index in guides.size():
		_check(guides[index].visible == (index == active), description + ": guide %d visible correctly" % index)
		for child in guides[index].get_children():
			if child is Label:
				_check(not (child as Label).visible, description + ": no card label inside standing outline")


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
