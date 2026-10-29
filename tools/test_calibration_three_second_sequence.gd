extends SceneTree

# Godot --headless --path . --script res://tools/test_calibration_three_second_sequence.gd
# Supplies synthetic *fresh pose packets*, never starts a webcam/YOLO worker.
# Exercises actual calibration state machine and routing without fake results.

const SCENE_PATH := "res://ui/vision/calibration/calibration.tscn"
const EXPECTED_ORDER := ["CENTER", "RIGHT", "LEFT"]
const EXPECTED_HOLD := 3.0
const EXPECTED_INTRO := 3.0
const EXPECTED_SUCCESS := 3.0
const LEGACY_NEON := ["ArtGuideCenter", "ArtGuideRight", "ArtGuideLeft"]
const ENGLISH := ["STAY IN THE CENTER", "MOVE TO THE RIGHT", "MOVE TO THE LEFT"]
const FILIPINO := ["MANATILI SA GITNA", "GUMALAW SA KANAN", "GUMALAW SA KALIWA"]

var failures: Array[String] = []
var checks := 0
var pose: Node
var scene: PackedScene
var source_clock := 1000.0


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
	await _check_intro_game_variants()
	await _check_no_camera()
	await _check_pose_hold(false)
	await _check_pose_hold(true)
	await _check_balloon_pose_phases()
	pose.stop_camera()
	_finish()


func _check_intro_navigation() -> void:
	# The initial three-second title has NO Back button; normal navigation
	# becomes available only when the actual calibration stage appears.
	pose.stop_camera()
	var calibration := _make_screen(true)
	if calibration == null:
		return
	var stage := calibration.get_node_or_null("TutorialStage") as Control
	var intro := stage.get_node_or_null("IntroOverlay") as Control if stage != null else null
	var normal_back := stage.get_node_or_null("Navigation/BackButton") as Button if stage != null else null
	var routes: Array[String] = []
	_check_intro_exclusivity(stage, "after initial set_context")
	calibration.requested.connect(func(target: String, _payload: Dictionary) -> void:
		routes.append(target))
	_expect(intro != null and intro.is_visible_in_tree(), "intro covers HUD immediately after ready")
	_expect(intro != null and intro.get_node_or_null("ArtIntroTitle") is Label,
			"3-second intro retains only its editor-authored CALIBRATION title")
	_expect(intro != null and intro.get_node_or_null("IntroBackButton") == null,
			"obsolete intro Back control cannot receive input")
	for path in ["Navigation/BackButton"]:
		var footer := stage.get_node_or_null(path) as Button if stage != null else null
		_expect(footer != null and not footer.is_visible_in_tree(),
			"intro prevents normal footer %s from receiving user input" % path)
	_expect(stage.get_node_or_null("ContinueButton") == null, "Obsolete Continue footer absent")
	for removed in ["SkipButton", "DemoButton", "RetryButton", "KeyboardButton"]:
		_expect(stage.get_node_or_null(removed) == null,
			"removed camera/keyboard action stays absent: " + removed)
	await process_frame
	await process_frame
	_expect(root.gui_get_focus_owner() != normal_back,
			"normal navigation cannot receive keyboard focus during intro")
	_expect(routes.is_empty(), "intro has no active Back navigation before 3 seconds")
	calibration.call("_process", EXPECTED_INTRO + 0.01)
	_expect(normal_back != null and normal_back.is_visible_in_tree() and not normal_back.disabled,
			"normal Back button becomes available after 3 seconds")
	await process_frame
	await process_frame
	_expect(normal_back != null and root.gui_get_focus_owner() == normal_back,
			"keyboard focus transfers to normal Back only after intro")
	if normal_back != null:
		normal_back.pressed.emit()
		_expect(routes == ["play_activity"], "post-intro Back goes to Choose Activity")
		_expect(not bool(pose.get("active")), "post-intro navigation never starts webcam capture")
	await _dispose(calibration)


func _check_preview_during_intro() -> void:
	# The webcam worker can deliver the first live frame while the intro is
	# covering the calibration page. It must be retained but never leak through
	# the intro; after 3.0 seconds the very same feed is shown as live video.
	pose.stop_camera()
	var calibration := _make_screen(false)
	if calibration == null:
		return
	var stage := calibration.get_node_or_null("TutorialStage") as Control
	var feed := stage.get_node_or_null("CameraArea/LiveCameraInset") as TextureRect if stage != null else null
	var offline := stage.get_node_or_null("CameraFeedback/CameraUnavailableLabel") as Label if stage != null else null
	var intro := stage.get_node_or_null("IntroOverlay") as Control if stage != null else null
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.25, 0.43, 0.59, 1.0))
	var texture := ImageTexture.create_from_image(image)
	_simulated_pose(0.5) # No webcam worker is started by the test.
	calibration.call("_on_live_preview", texture)
	_check_intro_exclusivity(stage, "after camera preview callback")
	_expect(feed != null and feed.texture == texture and not feed.visible,
		"real incoming frame is cached but hidden during intro")
	_expect(intro != null and intro.visible and intro.is_visible_in_tree(),
		"a new live camera frame cannot dismiss intro early")
	_expect(offline != null and not offline.is_visible_in_tree(),
		"fallback text does not leak through intro when camera starts")
	calibration.call("_process", EXPECTED_INTRO - 0.01)
	_check_intro_exclusivity(stage, "at 2.99 seconds before intro completion")
	_expect(feed != null and not feed.visible,
		"video remains hidden until full 3-second intro elapses")
	calibration.call("_process", 0.02)
	_expect(feed != null and feed.texture == texture and feed.visible and feed.is_visible_in_tree(),
		"same live frame resumes immediately after intro")
	_expect(offline != null and not offline.visible,
		"online camera never displays an unavailable-camera warning")
	_check_active_zone(stage, 0, "live camera feed resumes after intro")
	await _dispose(calibration)
	pose.stop_camera()


func _check_intro_game_variants() -> void:
	# Both entry routes use the same authored calibration Control. Their
	# set_context calls must never reveal graphics through the intro overlay,
	# including after a second context refresh or guide/heading synchronization.
	for activity in ["Catch the Word", "Balloon Popping", "Human Plane"]:
		for guided in [false, true]:
			pose.stop_camera()
			var calibration := _make_screen(guided)
			if calibration == null:
				continue
			var label := "%s %s" % ["Tutorial" if guided else "Play", activity]
			calibration.set_context({
				"camera_requested": false, "guided_tutorial": guided,
				"activity": activity, "game_mode": "Seconds",
				"difficulty": "Easy", "student_name": "TEST STUDENT"
			})
			var stage := calibration.get_node_or_null("TutorialStage") as Control
			_check_intro_exclusivity(stage, label + " after new-round context")
			calibration.call("_update_target_guide")
			calibration.call("_set_stage_instruction")
			_check_intro_exclusivity(stage, label + " after guide/title refresh")
			calibration.call("_process", EXPECTED_INTRO - 0.01)
			_check_intro_exclusivity(stage, label + " before 3 seconds")
			calibration.call("_process", 0.02)
			var intro := stage.get_node_or_null("IntroOverlay") as Control
			_expect(intro != null and not intro.visible, label + ": overlay ends after 3 seconds")
			var guide_name := ("PoseGuidePlaneCenter" if activity == "Human Plane" else
				"PoseGuideDefault")
			var guide := stage.get_node_or_null("PoseGuides/" + guide_name) as TextureRect
			_expect(guide != null and guide.is_visible_in_tree() and guide.texture != null,
				label + ": correct first-zone authored PNG appears after intro")
			for old in LEGACY_NEON:
				var neon := stage.get_node_or_null(old) as Control
				_expect(neon == null, label + ": retired neon " + old + " is absent")
			var title_name := "ArtTitleCenter"
			var title := stage.get_node_or_null("Directions/" + title_name) as Control
			var plane_heading := stage.get_node_or_null("PlaneSteeringTitle") as Control
			var plane: bool = String(activity) == "Human Plane"
			_expect(title != null and title.is_visible_in_tree() != plane,
				label + ": first-zone title restored for Catch/Balloon only")
			_expect(plane_heading == null and (stage.get_node_or_null("PoseGuides/PoseGuidePlaneCenter") as TextureRect).visible == plane,
					label + ": deleted PlaneSteeringTitle stays absent; Human Plane uses its own PNG")
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
	_expect(overlay != null and overlay.visible, "3-second intro is a separate visible overlay")
	_expect(calibration.get("intro_running") == true, "intro starts before first live pose capture")
	calibration.call("_process", EXPECTED_INTRO - 0.01)
	_expect(calibration.get("intro_running") == true and int(calibration.get("live_step")) == 0,
		"intro cannot be bypassed at 2.99s")
	_expect(float(calibration.get("live_timer")) == 0.0, "intro does not collect phantom hold time")
	calibration.call("_process", 0.02)
	_expect(calibration.get("intro_running") == false, "intro ends at 3.0s")
	if overlay != null:
		_expect(not overlay.visible, "intro overlay hides before calibration starts")
	var locked_continue := stage.get_node_or_null("ContinueButton") as Button if stage != null else null
	var back_button := stage.get_node_or_null("Navigation/BackButton") as Button if stage != null else null
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
	var hold_number := stage.get_node_or_null("CountdownArtwork/ArtCountdown3") as TextureRect if stage != null else null
	_expect(hold_number != null and hold_number.visible,
			"editor-authored countdown shows 3 while the actual hold remains at zero")
	_expect(stage.get_node_or_null("ContinueButton") == null, "No unmeasured Continue bypass is present")
	var camera_note := stage.get_node_or_null("CameraFeedback/CameraUnavailableLabel") as Label if stage != null else null
	_expect(camera_note != null and camera_note.visible, "explicitly visible no-camera fallback message")
	calibration.call("_continue_flow", false)
	_expect(requests.is_empty(), "Continue cannot bypass missing camera with unmeasured result")
	calibration.call("_continue_flow", true)
	_expect(requests.is_empty(), "deprecated skip parameter cannot bypass live calibration")
	var back := stage.get_node_or_null("Navigation/BackButton") as Button if stage != null else null
	_expect(back != null and back.accessibility_name == "Back to Choose Activity", "Back button names Choose Activity destination")
	if back != null:
		back.pressed.emit()
	_expect(requests.size() == 1 and String(requests[0].get("target", "")) == "play_activity",
		"Back to Choose Activity leaves calibration without opening game")
	await _dispose(calibration)


func _check_pose_hold(guided: bool) -> void:
	pose.stop_camera()
	# Finished success now requires LIVE source-authenticated raw SOLO boxes,
	# separate from the torso/wrist pose which earned the three physical holds.
	pose.peer = PacketPeerUDP.new()
	_expect(pose.peer.bind(0, "127.0.0.1") == OK,
		"guided=%s: synthetic loopback receiver for authenticated YOLO population" % guided)
	pose.worker_pid = OS.get_process_id() # Synthetic liveness; never spawn worker.
	pose.session_token = "three-second-verified-" + str(guided)
	pose.active = true
	var calibration := _make_screen(guided)
	if calibration == null:
		return
	var requests: Array[Dictionary] = []
	calibration.requested.connect(func(target: String, payload: Dictionary) -> void:
		requests.append({"target": target, "payload": payload}))
	var constants := calibration.get_script().get_script_constant_map() as Dictionary
	_expect((constants.get("CAPTURE_ORDER", []) as Array) == EXPECTED_ORDER, "hold order is CENTER → RIGHT → LEFT")
	_expect(is_equal_approx(float(constants.get("HOLD_SECONDS", 0.0)), EXPECTED_HOLD), "each stable hold requires 3.0 seconds")
	_expect(is_equal_approx(float(constants.get("INTRO_SECONDS", 0.0)), EXPECTED_INTRO), "intro lasts 3 seconds")
	_expect(is_equal_approx(float(constants.get("SUCCESS_SECONDS", 0.0)), EXPECTED_SUCCESS),
		"success screen requires a full separate 3.0 seconds")
	# First complete the timing gate with the camera off; no pose is counted.
	calibration.call("_process", EXPECTED_INTRO + 0.01)
	_expect(int(calibration.get("live_step")) == 0 and float(calibration.get("live_timer")) == 0.0,
		"intro does not pre-capture CENTER")
	var stage := calibration.get_node_or_null("TutorialStage") as Control
	_check_active_zone(stage, 0, "live CENTER at start")
	_simulated_pose(0.50)
	var hold_number := stage.get_node_or_null("CountdownArtwork/ArtCountdown3") as TextureRect if stage != null else null
	_expect(hold_number != null and hold_number.visible,
			"editor-authored 3 artwork is visible before any fresh pose earns time")
	_pose_frame(calibration, 0.50)
	_expect(hold_number != null and hold_number.visible,
			"first fresh pose displays the 3 PNG without restoring deleted CountdownLabel")
	for i in range(28):
		_pose_frame(calibration, 0.50)
	_expect(int(calibration.get("live_step")) == 0, "CENTER rejects 2.9 seconds")
	_pose_frame(calibration, 0.50)
	_pose_frame(calibration, 0.50)
	_expect(int(calibration.get("live_step")) == 1, "CENTER advances after at least 3 seconds with fresh packets")
	_expect((calibration.get("measured_points") as Dictionary).has("center"), "CENTER position is saved")
	var heading := stage.get_node_or_null("Directions/ArtTitleRight") as TextureRect if stage != null else null
	_expect(heading != null and heading.visible, "RIGHT art is prompted immediately after CENTER")
	_check_active_zone(stage, 1, "after successful CENTER hold")

	# The CENTER position cannot satisfy RIGHT even after a full hold period.
	for i in range(35):
		_pose_frame(calibration, 0.50)
	_expect(int(calibration.get("live_step")) == 1, "out-of-zone pose never advances RIGHT")
	_expect(float(calibration.get("live_timer")) == 0.0, "out-of-zone motion clears the hold timer")
	_expect(hold_number != null and hold_number.visible,
			"wrong zone resets real hold; static countdown art may remain on 3")

	# A stale pose packet must not accumulate time even if the last x is valid.
	_pose_frame(calibration, 0.80)
	for i in range(8):
		calibration.call("_process", 0.10)
	_expect(float(calibration.get("live_timer")) == 0.0,
		"no fresh pose packets for 0.8s invalidate a partial hold")
	_expect(int(calibration.get("live_step")) == 1, "stalled packet stream does not finish RIGHT")
	_expect(hold_number != null and hold_number.visible,
			"stale pose resets the live timer and leaves countdown art at 3")

	for i in range(8):
		_pose_frame(calibration, 0.80)
	_simulated_pose(0.91)
	_pose_frame(calibration, 0.91)
	_expect(float(calibration.get("live_timer")) == 0.0,
		"moving 11% camera width resets stability even within RIGHT zone")
	_expect(hold_number != null and hold_number.visible,
			"unstable movement clears the earned hold timer while authored 3 artwork remains visible")
	for i in range(29):
		_pose_frame(calibration, 0.80)
	_expect(int(calibration.get("live_step")) == 1, "RIGHT requires a fresh full hold after jitter")
	_pose_frame(calibration, 0.80)
	_pose_frame(calibration, 0.80)
	_expect(int(calibration.get("live_step")) == 2, "RIGHT completes after stable 3 seconds")
	_expect((calibration.get("measured_points") as Dictionary).has("right"), "RIGHT position is saved")
	_check_active_zone(stage, 2, "after successful RIGHT hold")
	if heading != null:
		_expect((stage.get_node_or_null("Directions/ArtTitleLeft") as TextureRect).visible,
			"LEFT art prompted only after RIGHT")

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
	var status := stage.get_node_or_null("CameraFeedback/CameraStatusLabel") as Label
	_expect(status != null and status.text == camera_detail,
		"tracking-loss text uses the live PoseService detail rather than a fabricated button instruction")
	_expect(status != null and not status.text.contains("RESET PLAYER"),
		"tracking-loss status never references deleted Reset Player control")
	var instruction := stage.get_node_or_null("CameraFeedback/ProgressLabel") as Label
	_expect(instruction != null and instruction.text.contains("Bumalik sa kamera"),
		"lost-pose screen gives a child-friendly Filipino return-to-camera prompt")
	_expect(hold_number != null and hold_number.visible, "lost pose returns 3 artwork while hold timer is zero")
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
	var success := stage.get_node_or_null("SuccessOverlay") as ColorRect
	var intro := stage.get_node_or_null("IntroOverlay") as ColorRect
	_expect(success != null and success.is_visible_in_tree() and bool(calibration.success_running),
		"completed pose holds display editor-authored success overlay")
	_expect(success != null and intro != null and is_equal_approx(success.color.a, intro.color.a),
		"success uses the same editor-authored 66% darkness as intro")
	_expect(success != null and success.get_node_or_null("SuccessTitle") is Label
		and success.get_node_or_null("SuccessSubtitle") is Label,
		"success includes editable title and bilingual subtitle")
	for child in stage.get_children():
		if child is Control and child != success:
			_expect(not (child as Control).visible,
				"success hides all stage graphics and navigation: " + child.name)
	calibration.call("_continue_flow", false)
	_expect(requests.is_empty(), "manual Continue cannot bypass success presentation")
	# The final hold can leave up to one residual test frame in the success
	# timer. Measure that actual state instead of assuming success began at 0.
	var before_ticks := maxi(0, floori((EXPECTED_SUCCESS - float(calibration.success_elapsed) - 0.15) / 0.10))
	for i in range(before_ticks):
		_pose_frame(calibration, 0.20)
	_expect(requests.is_empty() and success != null and success.visible
		and float(calibration.success_elapsed) < EXPECTED_SUCCESS,
		"fresh SOLO camera frames wait until the full 3s success in %s" %
		("guided" if guided else "normal Play"))
	for i in range(4):
		_pose_frame(calibration, 0.20)
	_expect(requests.size() == 1 and String(requests[0].get("target", "")) == "gameplay",
		"only completed 3s success enters gameplay for %s" % ("guided" if guided else "normal Play"))
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
	pose.worker_pid = -1 # Prevent stop_camera from terminating this Godot runner.
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
	pose.set("current_status", {"state": "tracking", "pose": true,
		"camera": true, "people": 1, "lock_state": "locked",
		"camera_frame_age_ms": 20, "x": x, "fps": 10.0,
		"hand_observation_valid": true, "hand_up": false})
	pose.set("last_pose_ms", Time.get_ticks_msec())


func _pose_frame(calibration: Control, x: float, delta: float = 0.10,
		raised: bool = false, wrists: bool = true,
		single_hand_only: bool = false) -> void:
	_simulated_pose(x)
	var data := pose.current_status.duplicate(true) as Dictionary
	data["hand_up"] = raised
	data["hand_observation_valid"] = wrists
	# Calibration can only trust fresh, same-packet bilateral evidence, not
	# the regular gameplay 'hand_up' (either hand) flag.
	data["both_hands_up"] = wrists and raised and not single_hand_only
	data["both_hands_down"] = wrists and not raised and not single_hand_only
	if pose.peer != null and pose.worker_pid > 0:
		data["token"] = pose.session_token
		data["kind"] = "pose"
		data["camera_phase"] = "tracking"
		pose._apply_pose_packet(data, Time.get_ticks_msec())
		pose.player_x = x # Stable synthetic source position, no renderer lag.
	pose.set("current_status", data)
	source_clock += delta
	pose.call("_record_fresh_calibration_pose", pose.current_status, source_clock)
	calibration.call("_process", delta)


func _check_balloon_pose_phases() -> void:
	# Keep the original intro/route/scene checks while asserting the newer six
	# physically verified phases (not just three standing zones).
	pose.stop_camera()
	var calibration := _make_screen(false)
	if calibration == null:
		return
	calibration.set_context({"activity":"Balloon Popping", "guided_tutorial":false,
		"camera_requested":false, "game_mode":"Seconds"})
	calibration.call("_process", 3.01)
	var stage := calibration.get_node_or_null("TutorialStage") as Control
	var default_art := stage.get_node_or_null("PoseGuides/PoseGuideDefault") as TextureRect
	_expect(default_art != null and default_art.visible,
		"Balloon first stage shows CENTER DEFAULT.png after 3-second intro")
	var completed_phases := 0
	for z in range(3):
		var location: float = [0.5, 0.8, 0.2][z]
		var zone: String = ["CENTER", "RIGHT", "LEFT"][z]
		var default_name := "PoseGuideDefault" if zone == "CENTER" else "PoseGuide" + zone.capitalize()
		var raised_name := "PoseGuideBalloonRaise" if zone == "CENTER" else "PoseGuideBalloonRaise" + zone.capitalize()
		var zone_default := stage.get_node_or_null("PoseGuides/" + default_name) as TextureRect
		var zone_raise := stage.get_node_or_null("PoseGuides/" + raised_name) as TextureRect
		for i in range(29):
			_pose_frame(calibration, location, 0.10, false, true)
		_expect(int(calibration.get("live_step")) == z and
			int(calibration.get("balloon_pose_phase")) == 0,
			"Balloon %s BOTH DOWN cannot pass before a complete 3s" % zone)
		for i in range(4):
			_pose_frame(calibration, location, 0.10, false, true)
		_expect(int(calibration.get("live_step")) == z and
			int(calibration.get("balloon_pose_phase")) == 1,
			"Balloon %s BOTH DOWN 3s leads to BOTH UP, not next zone" % zone)
		completed_phases += 1
		_expect(zone_raise != null and zone_raise.visible and zone_default != null and not zone_default.visible,
			"Balloon zone %d uses BALOON POP.png during raised hold" % z)
		# Four distinct wrong/unknown-wrist packets cannot fake an observed raise.
		for i in range(4):
			_pose_frame(calibration, location, 0.10, false, false)
		_expect(int(calibration.get("live_step")) == z and
			int(calibration.get("balloon_pose_phase")) == 1,
			"Balloon %s wrist-occluded frames cannot finish both-hands-up hold" % zone)
		for i in range(35):
			_pose_frame(calibration, location, 0.10, true, true, true)
		_expect(int(calibration.get("live_step")) == z and
			int(calibration.get("balloon_pose_phase")) == 1,
			"Balloon %s one-hand aggregate hand_up cannot substitute both hands UP" % zone)
		for i in range(29):
			_pose_frame(calibration, location, 0.10, true, true)
		_expect(int(calibration.get("live_step")) == z and
			int(calibration.get("balloon_pose_phase")) == 1,
			"Balloon %s BOTH UP cannot pass before 3s" % zone)
		for i in range(4):
			_pose_frame(calibration, location, 0.10, true, true)
		_expect(int(calibration.get("live_step")) == z + 1 and
			int(calibration.get("balloon_pose_phase")) == 0,
			"Balloon %s BOTH UP 3s finishes second genuine physical hold" % zone)
		completed_phases += 1
	_expect(completed_phases == 6 and int(calibration.live_step) == 3,
		"Balloon performs six fresh 3s holds (18s) in CENTER-RIGHT-LEFT order")
	_expect(bool((pose.calibration as Dictionary).get("valid", false)),
		"Balloon marks calibrated only after all six bilateral 3-second holds")
	await _dispose(calibration)
	pose.stop_camera()


func _check_active_zone(stage: Control, index: int, context_label: String) -> void:
	if stage == null:
		_expect(false, context_label + ": stage exists")
		return
	for i in range(LEGACY_NEON.size()):
		var zone := stage.get_node_or_null(LEGACY_NEON[i]) as Control
		_expect(zone == null,
			context_label + ": retired neon " + LEGACY_NEON[i] + " is absent")
		var old_panel := stage.get_node_or_null(["CenterCalibrationLane", "RightCalibrationLane", "LeftCalibrationLane"][i]) as Control
		_expect(old_panel == null,
			context_label + ": retired green standing panel is absent")
	var expected := "PoseGuideDefault" if index == 0 else "PoseGuideRight" if index == 1 else "PoseGuideLeft" if index == 2 else ""
	for name in ["PoseGuideDefault", "PoseGuideRight", "PoseGuideLeft"]:
		var guide := stage.get_node_or_null("PoseGuides/" + name) as TextureRect
		_expect(guide != null and guide.visible == (name == expected),
			context_label + ": independently placed Catch DEFAULT.png guide " + name)
	for other in ["PoseGuideBalloonRaise", "PoseGuideBalloonRaiseRight", "PoseGuideBalloonRaiseLeft",
			"PoseGuidePlaneCenter"]:
		var art := stage.get_node_or_null("PoseGuides/" + other) as TextureRect
		_expect(art != null and not art.visible,
			context_label + ": other mode pose PNG remains hidden: " + other)
	if index >= ENGLISH.size():
		return
	var active_title := stage.get_node_or_null("Directions/ArtTitle" + EXPECTED_ORDER[index].capitalize()) as TextureRect
	_expect(active_title != null and active_title.visible and active_title.texture != null,
		context_label + ": directional title PNG identifies " + EXPECTED_ORDER[index])
	_expect(stage.get_node_or_null("StageHeading") == null and stage.get_node_or_null("InstructionFIL") == null,
		context_label + ": user-deleted English/Filipino legacy labels are not regenerated")


func _check_intro_exclusivity(stage: Control, context_label: String) -> void:
	# The entire authored stage MUST be absent behind the transparent 66% intro.
	# A new-round set_context used to call _sync_reference_art and resurrect the
	# yellow guide, arrow, header and step through the translucent overlay.
	if stage == null:
		_expect(false, context_label + ": TutorialStage is available")
		return
	var intro := stage.get_node_or_null("IntroOverlay") as Control
	_expect(intro != null and intro.is_visible_in_tree(),
			context_label + ": intro overlay remains visible")
	for retired in ["IntroBackButton", "IntroHeading", "IntroDescription", "IntroCountdown"]:
		_expect(intro != null and intro.get_node_or_null(retired) == null,
				context_label + ": retired intro control is absent: " + retired)
	for child in stage.get_children():
		if child is Control and child != intro:
			_expect(not (child as Control).is_visible_in_tree(),
					"%s: stage asset %s must NOT leak behind CALIBRATION title" % [context_label, child.name])


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
