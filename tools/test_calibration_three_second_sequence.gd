extends SceneTree

# Godot --headless --path . --script res://tools/test_calibration_three_second_sequence.gd
# Supplies synthetic *fresh pose packets*, never starts a webcam/YOLO worker.
# Exercises actual calibration state machine and routing without fake results.

const SCENE_PATH := "res://ui/vision/calibration.tscn"
const EXPECTED_ORDER := ["CENTER", "RIGHT", "LEFT"]
const EXPECTED_HOLD := 3.0
const EXPECTED_INTRO := 2.5
const STAGE_ZONES := [
	"ArtGuideCenter", "ArtGuideRight", "ArtGuideLeft"
]
const ENGLISH := ["STAY IN THE CENTER", "MOVE TO THE RIGHT", "MOVE TO THE LEFT"]
const FILIPINO := ["MANATILI SA GITNA", "GUMALAW SA KANAN", "GUMALAW SA KALIWA"]

var failures: Array[String] = []
var checks := 0
var pose: Node
var scene: PackedScene


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_expect(pose != null, "PoseService autoload exists")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	scene = load(SCENE_PATH) as PackedScene
	_expect(scene != null, "calibration scene loads after autoload registration")
	if scene == null:
		_finish()
		return
	await _check_intro_navigation()
	await _check_preview_during_intro()
	await _check_no_camera()
	await _check_pose_hold(false)
	await _check_pose_hold(true)
	pose.stop_camera()
	_finish()


func _check_intro_navigation() -> void:
	# Verifies the actual input-facing Back button while the intro mask has
	# hidden every normal calibration sibling, including footer actions.
	pose.stop_camera()
	var calibration := _make_screen(true)
	if calibration == null:
		return
	var stage := calibration.get_node_or_null("TutorialStage") as Control
	var intro := stage.get_node_or_null("IntroOverlay") as Control if stage != null else null
	var back := intro.get_node_or_null("IntroBackButton") as Button if intro != null else null
	var routes: Array[String] = []
	calibration.requested.connect(func(target: String, _payload: Dictionary) -> void:
		routes.append(target))
	_expect(intro != null and intro.is_visible_in_tree(), "intro covers HUD immediately after ready")
	_expect(back != null and back.is_visible_in_tree() and not back.disabled,
			"intro has one usable Back to Choose Activity action")
	for path in ["BackButton"]:
		var footer := stage.get_node_or_null(path) as Button if stage != null else null
		_expect(footer != null and not footer.is_visible_in_tree(),
			"intro prevents normal footer %s from receiving user input" % path)
	_expect(stage.get_node_or_null("ContinueButton") == null, "Obsolete Continue footer absent")
	for removed in ["SkipButton", "DemoButton", "RetryButton", "KeyboardButton"]:
		_expect(stage.get_node_or_null(removed) == null,
			"removed camera/keyboard action stays absent: " + removed)
	await process_frame
	await process_frame
	_expect(back != null and root.gui_get_focus_owner() == back,
		"keyboard focus begins on the visible intro Back action")
	if back != null:
		back.pressed.emit()
		_expect(routes == ["play_activity"], "intro Back goes to Choose Activity without starting camera or gameplay")
	_expect(not bool(pose.get("active")), "intro navigation never starts webcam capture")
	await _dispose(calibration)


func _check_preview_during_intro() -> void:
	# The webcam worker can deliver the first live frame while the intro is
	# covering the calibration page. It must be retained but never leak through
	# the intro; after 2.5 seconds the very same feed is shown as live video.
	pose.stop_camera()
	var calibration := _make_screen(false)
	if calibration == null:
		return
	var stage := calibration.get_node_or_null("TutorialStage") as Control
	var feed := stage.get_node_or_null("LiveCameraInset") as TextureRect if stage != null else null
	var offline := stage.get_node_or_null("CameraUnavailableLabel") as Label if stage != null else null
	var intro := stage.get_node_or_null("IntroOverlay") as Control if stage != null else null
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.25, 0.43, 0.59, 1.0))
	var texture := ImageTexture.create_from_image(image)
	_simulated_pose(0.5) # No webcam worker is started by the test.
	calibration.call("_on_live_preview", texture)
	_expect(feed != null and feed.texture == texture and not feed.visible,
		"real incoming frame is cached but hidden during intro")
	_expect(intro != null and intro.visible and intro.is_visible_in_tree(),
		"a new live camera frame cannot dismiss intro early")
	_expect(offline != null and not offline.is_visible_in_tree(),
		"fallback text does not leak through intro when camera starts")
	calibration.call("_process", EXPECTED_INTRO - 0.01)
	_expect(feed != null and not feed.visible,
		"video remains hidden until full 2.5-second intro elapses")
	calibration.call("_process", 0.02)
	_expect(feed != null and feed.texture == texture and feed.visible and feed.is_visible_in_tree(),
		"same live frame resumes immediately after intro")
	_expect(offline != null and not offline.visible,
		"online camera never displays an unavailable-camera warning")
	_check_active_zone(stage, 0, "live camera feed resumes after intro")
	await _dispose(calibration)
	pose.stop_camera()


func _check_no_camera() -> void:
	pose.stop_camera()
	var calibration := _make_screen(false)
	if calibration == null:
		return
	var requests: Array[Dictionary] = []
	calibration.requested.connect(func(target: String, payload: Dictionary) -> void:
		requests.append({"target": target, "payload": payload}))
	var stage := calibration.get_node_or_null("TutorialStage") as Control
	var overlay := stage.get_node_or_null("IntroOverlay") as Control if stage != null else null
	_expect(overlay != null and overlay.visible, "2.5-second intro is a separate visible overlay")
	_expect(calibration.get("intro_running") == true, "intro starts before first live pose capture")
	calibration.call("_process", EXPECTED_INTRO - 0.01)
	_expect(calibration.get("intro_running") == true and int(calibration.get("live_step")) == 0,
		"intro cannot be bypassed at 2.49s")
	_expect(float(calibration.get("live_timer")) == 0.0, "intro does not collect phantom hold time")
	calibration.call("_process", 0.02)
	_expect(calibration.get("intro_running") == false, "intro ends at approximately 2.5s")
	if overlay != null:
		_expect(not overlay.visible, "intro overlay hides before calibration starts")
	var locked_continue := stage.get_node_or_null("ContinueButton") as Button if stage != null else null
	var back_button := stage.get_node_or_null("BackButton") as Button if stage != null else null
	_expect(back_button != null and back_button.visible and not back_button.disabled,
		"after intro only Back Choose Activity is an operable footer action")
	_expect(locked_continue == null, "Continue never appears automatically after intro")
	await process_frame
	await process_frame
	_expect(back_button != null and root.gui_get_focus_owner() == back_button,
		"keyboard focus transfers from intro Back to teacher Back Choose Activity")
	_check_active_zone(stage, 0, "offline, immediately after intro")
	calibration.call("_process", 9.0)
	_expect(int(calibration.get("live_step")) == 0, "camera-off cannot auto-complete calibration")
	_check_active_zone(stage, 0, "camera remains offline after 9 seconds")
	var hold_number := stage.get_node_or_null("CountdownLabel") as Label if stage != null else null
	_expect(hold_number != null and not hold_number.visible,
		"large 3/2/1 does not appear when there is no valid camera pose")
	_expect(stage.get_node_or_null("ContinueButton") == null, "No unmeasured Continue bypass is present")
	var camera_note := stage.get_node_or_null("CameraUnavailableLabel") as Label if stage != null else null
	_expect(camera_note != null and camera_note.visible, "explicitly visible no-camera fallback message")
	calibration.call("_continue_flow", false)
	_expect(requests.is_empty(), "Continue cannot bypass missing camera with unmeasured result")
	calibration.call("_continue_flow", true)
	_expect(requests.is_empty(), "deprecated skip parameter cannot bypass live calibration")
	var back := stage.get_node_or_null("BackButton") as Button if stage != null else null
	_expect(back != null and back.accessibility_name == "Back to Choose Activity", "Back button names Choose Activity destination")
	if back != null:
		back.pressed.emit()
	_expect(requests.size() == 1 and String(requests[0].get("target", "")) == "play_activity",
		"Back to Choose Activity leaves calibration without opening game")
	await _dispose(calibration)


func _check_pose_hold(guided: bool) -> void:
	pose.stop_camera()
	var calibration := _make_screen(guided)
	if calibration == null:
		return
	var requests: Array[Dictionary] = []
	calibration.requested.connect(func(target: String, payload: Dictionary) -> void:
		requests.append({"target": target, "payload": payload}))
	var constants := calibration.get_script().get_script_constant_map() as Dictionary
	_expect((constants.get("CAPTURE_ORDER", []) as Array) == EXPECTED_ORDER, "hold order is CENTER → RIGHT → LEFT")
	_expect(is_equal_approx(float(constants.get("HOLD_SECONDS", 0.0)), EXPECTED_HOLD), "each stable hold requires 3.0 seconds")
	_expect(is_equal_approx(float(constants.get("INTRO_SECONDS", 0.0)), EXPECTED_INTRO), "intro lasts 2.5 seconds")
	# First complete the timing gate with the camera off; no pose is counted.
	calibration.call("_process", EXPECTED_INTRO + 0.01)
	_expect(int(calibration.get("live_step")) == 0 and float(calibration.get("live_timer")) == 0.0,
		"intro does not pre-capture CENTER")
	var stage := calibration.get_node_or_null("TutorialStage") as Control
	_check_active_zone(stage, 0, "live CENTER at start")
	_simulated_pose(0.50)
	var hold_number := stage.get_node_or_null("CountdownLabel") as Label if stage != null else null
	_expect(hold_number != null and not hold_number.visible,
		"standing countdown begins hidden, before first fresh pose packet")
	_pose_frame(calibration, 0.50)
	_expect(hold_number != null and hold_number.visible and hold_number.text == "3",
		"first stable fresh pose frame displays large 3")
	for i in range(28):
		_pose_frame(calibration, 0.50)
	_expect(int(calibration.get("live_step")) == 0, "CENTER rejects 2.9 seconds")
	_pose_frame(calibration, 0.50)
	_pose_frame(calibration, 0.50)
	_expect(int(calibration.get("live_step")) == 1, "CENTER advances after at least 3 seconds with fresh packets")
	_expect((calibration.get("measured_points") as Dictionary).has("center"), "CENTER position is saved")
	var heading := stage.get_node_or_null("StageHeading") as Label if stage != null else null
	_expect(heading != null and heading.text.contains("RIGHT"), "RIGHT is prompted immediately after CENTER")
	_check_active_zone(stage, 1, "after successful CENTER hold")

	# The CENTER position cannot satisfy RIGHT even after a full hold period.
	for i in range(35):
		_pose_frame(calibration, 0.50)
	_expect(int(calibration.get("live_step")) == 1, "out-of-zone pose never advances RIGHT")
	_expect(float(calibration.get("live_timer")) == 0.0, "out-of-zone motion clears the hold timer")
	_expect(hold_number != null and not hold_number.visible,
		"wrong zone hides and resets big hold countdown")

	# A stale pose packet must not accumulate time even if the last x is valid.
	_pose_frame(calibration, 0.80)
	for i in range(8):
		calibration.call("_process", 0.10)
	_expect(float(calibration.get("live_timer")) == 0.0,
		"no fresh pose packets for 0.8s invalidate a partial hold")
	_expect(int(calibration.get("live_step")) == 1, "stalled packet stream does not finish RIGHT")
	_expect(hold_number != null and not hold_number.visible,
		"stale pose packets hide the countdown")

	for i in range(8):
		_pose_frame(calibration, 0.80)
	_simulated_pose(0.91)
	_pose_frame(calibration, 0.91)
	_expect(float(calibration.get("live_timer")) == 0.0,
		"moving 11% camera width resets stability even within RIGHT zone")
	_expect(hold_number != null and not hold_number.visible,
		"unstable movement clears visible 3/2/1 countdown")
	for i in range(29):
		_pose_frame(calibration, 0.80)
	_expect(int(calibration.get("live_step")) == 1, "RIGHT requires a fresh full hold after jitter")
	_pose_frame(calibration, 0.80)
	_pose_frame(calibration, 0.80)
	_expect(int(calibration.get("live_step")) == 2, "RIGHT completes after stable 3 seconds")
	_expect((calibration.get("measured_points") as Dictionary).has("right"), "RIGHT position is saved")
	_check_active_zone(stage, 2, "after successful RIGHT hold")
	if heading != null:
		_expect(heading.text.contains("LEFT"), "LEFT prompted only after RIGHT")

	for i in range(11):
		_pose_frame(calibration, 0.20)
	var camera_detail := "We lost sight of you. Step back into the camera view."
	pose.set("current_status", {"state": "stale", "pose": false, "detail": camera_detail})
	calibration.call("_process", 0.10)
	_expect(float(calibration.get("live_timer")) == 0.0, "loss of player tracking resets LEFT hold")
	_expect(int(calibration.get("live_step")) == 2, "tracking loss cannot complete LEFT")
	_expect((calibration.get("measured_points") as Dictionary).has("center")
		and (calibration.get("measured_points") as Dictionary).has("right"),
		"tracking loss keeps finished CENTER and RIGHT measurements")
	var status := stage.get_node_or_null("CameraStatusLabel") as Label
	_expect(status != null and status.text == camera_detail,
		"tracking-loss text uses the live PoseService detail rather than a fabricated button instruction")
	_expect(status != null and not status.text.contains("RESET PLAYER"),
		"tracking-loss status never references deleted Reset Player control")
	var instruction := stage.get_node_or_null("ProgressLabel") as Label
	_expect(instruction != null and instruction.text.contains("Bumalik sa kamera"),
		"lost-pose screen gives a child-friendly Filipino return-to-camera prompt")
	_expect(hold_number != null and not hold_number.visible, "lost pose hides big hold countdown")
	for i in range(29):
		_pose_frame(calibration, 0.20)
	_expect(int(calibration.get("live_step")) == 2, "LEFT rejects holds shorter than 3 seconds")
	_pose_frame(calibration, 0.20)
	_pose_frame(calibration, 0.20)
	_expect(int(calibration.get("live_step")) == 3, "LEFT ends the three-step calibration")
	_check_active_zone(stage, 3, "after calibration completion")
	_expect(bool((pose.get("calibration") as Dictionary).get("valid", false)),
		"stable LEFT/CENTER/RIGHT samples create real normalized bounds")
	_expect(stage.get_node_or_null("ContinueButton") == null and bool((pose.get("calibration") as Dictionary).get("valid", false)),
		"Measured zones permit automatic flow without a redundant Continue button")
	calibration.call("_continue_flow", false)
	_expect(requests.size() == 1 and String(requests[0]["target"]) == "gameplay",
		"completed calibration enters gameplay for %s" % ("guided" if guided else "normal Play"))
	if requests.size() > 0:
		var payload := requests[0]["payload"] as Dictionary
		_expect(bool(payload.get("start_countdown", false)), "measured flow requests the 3-2-1 countdown")
		_expect(bool(payload.get("camera_live", false)) and not bool(payload.get("keyboard_mode", true)),
			"successful calibration retains live YOLO movement controls")
		_expect(not bool(payload.get("preview_mode", true)), "measured calibration cannot fake preview-only gameplay")
		_expect(bool(payload.get("guided_tutorial", false)) == guided,
			"guided flag is retained only for guided sessions")
		_expect(not bool(payload.get("calibration_skipped", true)), "measured result is never mislabeled skipped")
	await _dispose(calibration)
	pose.stop_camera()


func _make_screen(guided: bool) -> Control:
	var calibration := scene.instantiate() as Control
	_expect(calibration != null, "calibration Control instantiates")
	if calibration == null:
		return null
	root.add_child(calibration)
	calibration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not calibration.has_method("set_context"):
		_expect(false, "calibration script compiled and exposes set_context")
		calibration.queue_free()
		return null
	calibration.set_context({
		"camera_requested": false, "guided_tutorial": guided, "keyboard_mode": false,
		"activity": "Catch the Word", "game_mode": "Seconds", "difficulty": "Easy",
		"student_name": "TEST STUDENT", "topic": "Noun"
	})
	calibration.set_process(false) # Drive time deterministically, without rendering FPS.
	return calibration


func _simulated_pose(x: float) -> void:
	pose.set("active", true)
	pose.set("player_x", x)
	pose.set("current_status", {"state": "tracking", "pose": true, "lock_state": "locked"})
	pose.set("last_pose_ms", Time.get_ticks_msec())


func _pose_frame(calibration: Control, x: float, delta: float = 0.10) -> void:
	_simulated_pose(x)
	pose.set("packet_sequence", int(pose.get("packet_sequence")) + 1)
	calibration.call("_process", delta)


func _check_active_zone(stage: Control, index: int, context_label: String) -> void:
	if stage == null:
		_expect(false, context_label + ": stage exists")
		return
	var visible_count := 0
	for i in range(STAGE_ZONES.size()):
		var zone := stage.get_node_or_null(STAGE_ZONES[i]) as Control
		_expect(zone != null, context_label + ": " + STAGE_ZONES[i] + " remains editor-authored")
		if zone == null:
			continue
		if zone.visible:
			visible_count += 1
		_expect(zone.visible == (i == index),
			context_label + ": only current PARAMETERS.png guide is visible: " + STAGE_ZONES[i])
		var old_panel := stage.get_node_or_null(["CenterCalibrationLane", "RightCalibrationLane", "LeftCalibrationLane"][i]) as Control
		_expect(old_panel != null and not old_panel.visible,
			context_label + ": obsolete green standing panel never overlays updated PNG")
	_expect(visible_count == (0 if index >= STAGE_ZONES.size() else 1),
		context_label + ": there is at most one visible glowing standing guide")
	if index >= ENGLISH.size():
		return
	var heading := stage.get_node_or_null("StageHeading") as Label
	var english := stage.get_node_or_null("StageHeading") as Label
	var filipino := stage.get_node_or_null("InstructionFIL") as Label
	_expect(heading != null and heading.text.contains(EXPECTED_ORDER[index]),
		context_label + ": stage heading identifies " + EXPECTED_ORDER[index])
	_expect(english != null and english.text.to_upper().contains(ENGLISH[index]),
		context_label + ": single authored English heading matches active guide")
	_expect(filipino != null and filipino.text.to_upper().contains(FILIPINO[index]),
		context_label + ": editor-authored Filipino instruction matches active guide")


func _dispose(calibration: Control) -> void:
	if is_instance_valid(calibration):
		calibration.queue_free()
		await process_frame


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _finish() -> void:
	for failure in failures:
		printerr("FAIL calibration sequence: ", failure)
	print("%s calibration sequence: %d checks, %d failures" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
