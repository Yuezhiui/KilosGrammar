extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_calibration_human_plane_center_only.gd
# Regression for rejecting old floor-shift/center-only calibration on Human
# Plane. The separate center-only steering test verifies source packet rules.
const SCENE_PATH := "res://ui/vision/calibration/calibration.tscn"

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
	pose.worker_pid = -1 # Never kill Godot's synthetic process-ID stand-in.
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
	screen.call("_process", 3.01)
	_check(screen.call("_capture_order") == ["CENTER"],
		"Human Plane requires only the full 3-second T-pose CENTER stage")
	var intro := stage.get_node_or_null("IntroOverlay") as ColorRect
	_check(intro != null and intro.get_node_or_null("ArtIntroTitle") is Label
		and intro.get_node_or_null("IntroDescription") == null
		and intro.get_node_or_null("IntroBackButton") == null
		and intro.get_node_or_null("IntroCountdown") == null
		and intro.get_node_or_null("IntroHeading") == null,
		"Intro is a single editor-authored CALIBRATION title without retired controls")
	var plane_text := (screen.get_script().get_script_constant_map() as Dictionary).get("PLANE_STAGE_TEXT", {}) as Dictionary
	var center_words := plane_text.get("CENTER", []) as Array
	_check((stage.get_node_or_null("PoseGuides/PoseGuidePlaneCenter") as Control).visible
		and not center_words.is_empty() and String(center_words[0]).contains("T-POSE"),
		"Human Plane guides full T-pose using its editable centered PNG and instruction")
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
	# Real full T-pose is the ONLY permitted physical-plane setup; a torso
	# drift, 2.5-second old neutral hold or synthesized side positions cannot.
	screen.call("_reset_live_samples")
	for index in range(28):
		_fresh_pose(screen, 0.5, 0.10, false, true)
	_check(int(screen.get("live_step")) == 0 and
		not bool((pose.plane_calibration as Dictionary).get("valid", false)),
		"old 2.5s neutral time cannot complete new 3-second full T-pose")
	for index in range(8):
		_fresh_pose(screen, 0.5, 0.10, false, true)
		if screen.success_running:
			break
	_check(int(screen.get("live_step")) == 1 and
		bool((pose.plane_calibration as Dictionary).get("valid", false)) and
		not (pose.plane_calibration as Dictionary).has("left"),
		"3-second real fresh T-pose completes without fake LEFT/RIGHT")
	_check(is_equal_approx(float(pose.plane_calibration.get("center", -1.0)), 0.5),
		"real Human Plane torso center is measured independently from neutral arm steering")
	var measured_once: Dictionary = screen.measured_points.duplicate(true)
	var elapsed_before_invalid: float = float(screen.success_elapsed)
	for people in [2, 0]:
		_check(screen.success_running and routes.is_empty(),
			"Human Plane complete SOLO hold must show success before gameplay")
		# Authentic raw YOLO 0/2+ population revokes GO authorization,
		# NOT the completed source-verified CENTER T-pose measurements.
		pose._apply_pose_packet({"token": pose.session_token, "kind": "pose",
			"state": "tracking", "camera": true, "camera_phase": "tracking",
			"people": people, "pose": false, "lock_state": "lost",
			"camera_frame_age_ms": 20, "x": -1.0}, Time.get_ticks_msec())
		screen.call("_process", 0.10)
		_check(bool(screen.success_running) and int(screen.live_step) == 1
			and bool(pose.calibration.get("valid", false)) and routes.is_empty()
			and screen.measured_points == measured_once
			and is_equal_approx(float(screen.success_elapsed), elapsed_before_invalid),
			"Human Plane %d-person camera frame FREEZES success without recalibration" % people)
	_check_success_then_handoff(screen, routes, "Human Plane")
	await _dispose(screen)


func _test_legacy_three_positions(activity: String) -> void:
	_reset_synthetic_camera()
	var screen := _make_screen(activity)
	var stage := screen.get_node("TutorialStage") as Control
	_check(stage.get_node_or_null("PlaneStepBadge") == null,
		activity + ": retired PlaneStepBadge is absent")
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target": target, "payload": payload}))
	screen.call("_process", 3.01)
	_check(screen.call("_capture_order") == ["CENTER", "RIGHT", "LEFT"],
		activity + ": retains its exact center/right/left stages")
	_check((stage.get_node("Directions/ArtStep1") as Control).visible,
		activity + ": original STEP 1/3 artwork is unchanged")
	_hold_full_zone(screen, 0.5, activity)
	_check(int(screen.get("live_step")) == 1 and
			(stage.get_node("PoseGuides/PoseGuideRight") as Control).visible
			and (stage.get_node_or_null("ArtGuideRight") == null)
			and (stage.get_node_or_null("RightCalibrationLane") == null),
		activity + ": right DEFAULT pose follows fully verified CENTER holds")
	_check((stage.get_node("Directions/ArtStep2") as Control).visible,
		activity + ": original STEP 2/3 artwork follows center")
	_hold_full_zone(screen, 0.8, activity)
	_check(int(screen.get("live_step")) == 2 and
			(stage.get_node("PoseGuides/PoseGuideLeft") as Control).visible
			and (stage.get_node_or_null("ArtGuideLeft") == null)
			and (stage.get_node_or_null("LeftCalibrationLane") == null),
		activity + ": left DEFAULT pose follows fully verified RIGHT holds")
	_hold_full_zone(screen, 0.2, activity)
	_check(int(screen.get("live_step")) == 3 and bool((pose.get("calibration") as Dictionary).get("valid", false))
		and not bool((pose.get("calibration") as Dictionary).get("center_only", false)),
		activity + ": three measured locations and required wrist phases calibrate")
	_check_success_then_handoff(screen, routes, activity)
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


func _hold_full_zone(screen: Control, position: float, activity: String) -> void:
	for index in range(33):
		_fresh_pose(screen, position, 0.1, false)
	if activity == "Balloon Popping":
		for index in range(33):
			_fresh_pose(screen, position, 0.1, true)


func _fresh_pose(screen: Control, position: float, delta: float = 0.1,
		raised: bool = false, t_pose: bool = false) -> void:
	pose.set("active", true)
	# A camera frame must be fresh and SOLO. Real floor positions do not
	# register ByteTrack IDs; Human Plane additionally requires hand-pose fields.
	var packet := {"token": pose.session_token, "kind": "pose",
		"state": "tracking", "pose": true, "camera": true, "camera_phase": "tracking",
		"people": 1, "lock_state": "locked", "camera_frame_age_ms": 20,
		"x": position, "fps": 10.0,
		"hand_observation_valid": true, "hand_up": raised,
		"plane_t_pose_valid": t_pose,
		# A neutral extended-arms pose generates ~0 arm steering even though the
		# student's measured torso position is center x=0.5.
		"plane_steering": 0.0, "plane_steering_valid": true,
		"plane_neutral_valid": true}
	pose._apply_pose_packet(packet, Time.get_ticks_msec())
	pose.player_x = position # Source-authenticated position; no rendering smoothing.
	source_clock += delta
	pose.call("_record_fresh_calibration_pose", packet, source_clock)
	screen.call("_process", delta)


func _check_success_then_handoff(screen: Control, routes: Array[Dictionary],
		activity: String) -> void:
	var stage := screen.get_node_or_null("TutorialStage") as Control
	var success := stage.get_node_or_null("SuccessOverlay") as ColorRect
	_check(success != null and success.visible and bool(screen.success_running)
		and routes.is_empty(), activity + ": completed physical holds show success first")
	if success != null:
		_check(success.get_node_or_null("SuccessTitle") is Label
			and success.get_node_or_null("SuccessSubtitle") is Label,
			activity + ": success title/subtitle are authored in the Godot editor")
		for child in stage.get_children():
			if child is Control and child != success:
				_check(not (child as Control).visible,
					activity + ": success hides all calibration and Back art: " + child.name)
	screen.call("_continue_flow", false)
	_check(routes.is_empty(), activity + ": direct Continue cannot bypass 3s success")
	var before_ticks := maxi(0, floori((3.0 - float(screen.success_elapsed) - 0.15) / 0.10))
	for tick in range(before_ticks):
		_fresh_pose(screen, 0.5, 0.10, false, activity == "Human Plane")
	_check(routes.is_empty() and screen.success_running and screen.success_elapsed < 3.0,
		activity + ": fresh SOLO source remains blocked before 3 seconds of success")
	for tick in range(4):
		_fresh_pose(screen, 0.5, 0.10, false, activity == "Human Plane")
	_check(routes.size() == 1 and String(routes[0].get("target", "")) == "gameplay",
		activity + ": full 3-second success requests gameplay exactly once")
	if routes.size() == 1:
		var payload := routes[0].get("payload", {}) as Dictionary
		_check(bool(payload.get("start_countdown", false))
			and bool(payload.get("calibration_measured", false))
			and bool(payload.get("camera_live", false))
			and not bool(payload.get("keyboard_mode", true)),
			activity + ": gameplay receives verified live-calibration 3-2-1 GO contract")
		if activity == "Human Plane":
			_check(bool(payload.get("calibration_stationary", false))
				and not payload.has("calibration_left") and not payload.has("calibration_right")
				and is_equal_approx(float(payload.get("calibration_center", -1.0)), 0.5),
				"Human Plane handoff preserves actual torso center and never invents side bounds")
	for tick in range(3):
		_fresh_pose(screen, 0.5, 0.10, false, activity == "Human Plane")
	_check(routes.size() == 1, activity + ": success cannot emit duplicate gameplay routes")


func _reset_synthetic_camera() -> void:
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(false)
	pose.peer = PacketPeerUDP.new()
	_check(pose.peer.bind(0, "127.0.0.1") == OK,
		"Human Plane real-source gate uses synthetic bound localhost receiver")
	pose.worker_pid = OS.get_process_id() # Mock live PID, disarmed before stopping.
	pose.session_token = "calibration-plane-source-" + str(source_clock)
	pose.set("active", true)
	pose.set("player_x", 0.5)
	pose.set("last_pose_ms", Time.get_ticks_msec())
	pose.set("packet_sequence", 0)
	pose.set("current_status", {"state": "tracking", "pose": true,
		"camera": true, "camera_phase": "tracking", "people": 1,
		"token": pose.session_token, "lock_state": "locked",
		"camera_frame_age_ms": 20, "x": 0.5})


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
