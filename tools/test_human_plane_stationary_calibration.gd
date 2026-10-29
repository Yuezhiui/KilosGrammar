extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_stationary_calibration.gd
# Offline verified-source PROTOCOL fixture. Simulates fresh, per-frame YOLO
# packets with correct camera/token/solo/T-pose fields. Never opens a webcam,
# starts the model, alters production, or treats synthetic data as real footage.
const SCENE_PATH := "res://ui/vision/calibration/calibration.tscn"
const PERSON := 21
const CENTER := 0.50
const HOLD_DT := 0.45 # Eight real source frames span 7 * 0.45 = 3.15 seconds.
const SUCCESS_DT := 0.10

var failures: Array[String] = []
var checks := 0
var pose: Node
var scene: PackedScene
var source_clock := 100.0
var finished := false
var reset_number := 0


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(18.0).timeout
	if not finished:
		_check(false, "headless suite exceeded 18 seconds")
		_finish()


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "actual PoseService singleton exists")
	if pose == null:
		_finish()
		return
	scene = load(SCENE_PATH) as PackedScene
	_check(scene != null, "real calibration PackedScene loads")
	if scene == null:
		_finish()
		return
	await _check_plane_center_hold_and_handoff()
	await _check_other_games_still_require_physical_holds()
	_finish()


func _check_plane_center_hold_and_handoff() -> void:
	if not _reset_camera():
		return
	var screen := _screen("Human Plane")
	if screen == null:
		return
	var stage := screen.get_node_or_null("TutorialStage") as Control
	_check(stage != null, "editor-authored TutorialStage is present")
	if stage == null:
		await _dispose(screen)
		return
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(route: String, payload: Dictionary) -> void:
		routes.append({"route": route, "payload": payload.duplicate(true)}))
	var constants := screen.get_script().get_script_constant_map() as Dictionary
	_check(float(constants.get("PLANE_HOLD_SECONDS", -1)) == 3.0
		and int(constants.get("REQUIRED_SAMPLES", 0)) >= 8,
		"single CENTER T-pose requires 3.0 seconds and >=8 distinct detections")
	_check(screen.call("_capture_order") == ["CENTER"], "Plane calibrates only CENTER")
	_check(bool(screen.intro_running), "three-second intro begins before physical hold")
	screen._process(3.01)
	var intro := stage.get_node_or_null("IntroOverlay") as ColorRect
	var guide := stage.get_node_or_null("PoseGuides/PoseGuidePlaneCenter") as TextureRect
	_check(intro != null and intro.get_node_or_null("ArtIntroTitle") is Label,
		"authored IntroOverlay owns the CALIBRATION heading")
	_check(guide != null and guide.owner == screen and guide.texture != null
		and guide.texture.resource_path.contains("PLANE T POSE"),
		"source T-pose guide is authored and draggable at PoseGuides/PoseGuidePlaneCenter")
	var left_guide := stage.get_node_or_null("PoseGuides/PoseGuidePlaneLeft") as TextureRect
	var right_guide := stage.get_node_or_null("PoseGuides/PoseGuidePlaneRight") as TextureRect
	_check(guide != null and guide.visible
		and left_guide != null and right_guide != null
		and not left_guide.visible and not right_guide.visible
		and left_guide.position == guide.position and right_guide.position == guide.position
		and left_guide.size == guide.size and right_guide.size == guide.size,
		"only CENTER visible during physical T-pose; side images are aligned demo guides")
	var plane_text := constants.get("PLANE_STAGE_TEXT", {}) as Dictionary
	var center_text := plane_text.get("CENTER", []) as Array
	_check(not center_text.is_empty() and String(center_text[0]).contains("T-POSE"),
		"center instruction explicitly requests an extended-arms T-pose")
	screen._continue_flow(false)
	_check(routes.is_empty(), "Continue cannot skip the verified hold")

	# A cached displayed pose does not count. Seven fresh source packets do not
	# satisfy the eight-frame minimum even when 3.0 seconds have elapsed.
	for index in range(7):
		_packet(screen, CENTER, 1, true, HOLD_DT)
	_check(int(screen.live_step) == 0 and not pose.plane_calibration.get("valid", false),
		"7 source frames spanning 3.0s never complete >=8-frame calibration")
	var before_duplicate := int(pose.latest_pose_sample_id)
	var duplicate := _source(CENTER, 1, true)
	pose._record_fresh_calibration_pose(duplicate, source_clock)
	_check(int(pose.latest_pose_sample_id) == before_duplicate
		and (screen.live_samples as Array).size() == 7,
		"duplicate inference timestamp does not earn an eighth frame")

	# Losing SOLO or arm evidence resets only the ongoing hold. Neither a
	# two-person bystander frame nor a one-wrist T-pose can finish calibration.
	_packet(screen, CENTER, 2, false, HOLD_DT)
	_check(int(screen.live_step) == 0 and (screen.live_samples as Array).is_empty(),
		"two-person occupancy revokes the unfinished T-pose hold")
	_packet(screen, CENTER, 1, false, HOLD_DT)
	_check(int(screen.live_step) == 0 and (screen.live_samples as Array).is_empty(),
		"one confidently tracked student without full T-pose cannot progress")
	for index in range(8):
		_packet(screen, CENTER + 0.002 * float(index % 3 - 1), 1, true, HOLD_DT)
	var measured := pose.plane_calibration as Dictionary
	_check(int(screen.live_step) == 1 and bool(measured.get("valid", false)),
		"8 live T-pose frames spanning >=3s complete CENTER exactly once")
	if not bool(measured.get("valid", false)):
		await _dispose(screen)
		return
	_check(bool(screen.plane_demo_running) and not bool(screen.success_running)
		and left_guide.visible and routes.is_empty(), "physical hold enters visual LEFT guide demo")
	for i in range(11):
		_packet(screen, CENTER, 1, false, SUCCESS_DT)
	_check(right_guide.visible and screen.plane_demo_running,
		"RIGHT demonstration follows LEFT without another physical calibration stage")
	for i in range(11):
		_packet(screen, CENTER, 1, false, SUCCESS_DT)
	_check(bool(screen.success_running) and routes.is_empty(),
		"completed visual illustration enters existing authenticated SUCCESS overlay")
	_check((stage.get_node_or_null("SuccessOverlay") as Control).visible,
		"success artwork is the actual editor-authored SuccessOverlay")
	_check(bool(pose.calibration.get("valid", false))
		and String(measured.get("mode", "")) == "plane_stationary"
		and String(measured.get("steering_mode", "")) == "continuous_arm_bank"
		and bool(measured.get("neutral_only", false))
		and not measured.has("left") and not measured.has("right"),
		"plane saves only measured CENTER; no invented LEFT/RIGHT endpoints or legacy torso mode")
	_check(absf(float(measured.get("center", -1)) - CENTER) < 0.01
		and absf(float(measured.get("camera_center_x", -1)) - CENTER) < 0.01
		and absf(float(measured.get("neutral_noise", -1))) < 0.01,
		"actual solo torso center and T-pose bank jitter are measured independently")
	_check(bool(pose.has_stationary_plane_pose())
		and is_zero_approx(float(pose.normalized_plane_steering())),
		"fresh, locked SOLO neutral T-pose produces zero bank velocity")

	# Post-calibration banking is signed arm tilt at fixed torso X, not a
	# fabricated left/right body position. Confidence must be source fresh.
	for bank in [-0.8, 0.0, 0.75]:
		var bank_packet := _source(CENTER, 1, false, PERSON, bank, true)
		pose._apply_pose_packet(bank_packet, Time.get_ticks_msec())
		_check(bool(pose.has_stationary_plane_pose())
			and absf(float(pose.normalized_plane_steering()) - bank) < 0.001,
			"fresh SOLO bank %.2f produces matching signed plane velocity" % bank)
	var incomplete := _source(CENTER, 1, false, PERSON, 0.75, false)
	pose._apply_pose_packet(incomplete, Time.get_ticks_msec())
	_check(not pose.has_stationary_plane_pose()
		and is_zero_approx(float(pose.normalized_plane_steering())),
		"missing both-elbow/wrist bank evidence instantly freezes steering")
	pose._apply_pose_packet(_source(CENTER, 1, false, 77, -0.4, true),
		Time.get_ticks_msec())
	_check(pose.has_stationary_plane_pose()
		and absf(float(pose.normalized_plane_steering()) + 0.4) < 0.001,
		"new ByteTrack ID alone cannot erase authentic same-session SOLO calibration")

	var completed_measurements: Dictionary = (screen.measured_points as Dictionary).duplicate(true)
	var success_at_crowd: float = float(screen.success_elapsed)
	for population in [2, 0]:
		_packet(screen, CENTER, population, false, SUCCESS_DT)
		_check(screen.success_running and routes.is_empty()
			and screen.measured_points == completed_measurements
			and is_equal_approx(float(screen.success_elapsed), success_at_crowd),
			"%d-person YOLO occupancy freezes success without a new calibration" % population)
	# A current-session, raw SOLO frame resumes SUCCESS even without a keypoint
	# T-pose. It must remain pending until the full 3.0-second overlay elapses.
	for tick in range(26):
		_packet(screen, CENTER, 1, false, SUCCESS_DT, false)
	_check(routes.is_empty() and screen.success_running
		and float(screen.success_elapsed) < 3.0,
		"fresh SOLO occupancy cannot bypass the three-second success overlay")
	for tick in range(6):
		_packet(screen, CENTER, 1, false, SUCCESS_DT, false)
	_check(routes.size() == 1 and String(routes[0].get("route", "")) == "gameplay",
		"completed authenticated source sequence routes exactly once")
	if routes.size() == 1:
		var payload := routes[0].get("payload", {}) as Dictionary
		_check(payload.get("plane_steering_mode", "") == "continuous_arm_bank"
			and bool(payload.get("calibration_stationary", false))
			and bool(payload.get("calibration_neutral_only", false))
			and bool(payload.get("start_countdown", false))
			and not payload.has("calibration_left") and not payload.has("calibration_right"),
			"gameplay receives real one-center T-pose/arm-bank metadata and GO countdown")
	for tick in range(5):
		_packet(screen, CENTER, 1, false, SUCCESS_DT, false)
	_check(routes.size() == 1, "continued camera packets cannot emit duplicate gameplay")
	await _dispose(screen)


func _check_other_games_still_require_physical_holds() -> void:
	# Preserve cross-game regression coverage from the legacy test: Catch still
	# measures three positions; Balloon does six physical bilateral holds.
	for activity in ["Catch the Word", "Balloon Popping"]:
		if not _reset_camera():
			return
		var screen := _screen(activity)
		if screen == null:
			return
		screen._process(3.01)
		var order := screen.call("_capture_order") as Array
		var expected: Array = ["CENTER", "RIGHT", "LEFT"]
		_check(order == expected, activity + ": correct three-stage floor order")
		for zone in expected:
			var x := 0.5 if zone == "CENTER" else 0.80 if zone == "RIGHT" else 0.20
			for index in range(8):
				_packet(screen, x, 1, false, HOLD_DT, true, PERSON, false, true, true)
			if activity == "Balloon Popping":
				_check(int(screen.balloon_pose_phase) == 1,
					"Balloon " + zone + ": 3s bilateral DOWN advances only to UP phase")
				for index in range(8):
					_packet(screen, x, 1, false, HOLD_DT, true, PERSON, true, false, true)
		_check(int(screen.live_step) == 3 and bool(pose.calibration.get("valid", false))
			and pose.plane_calibration.is_empty(),
			activity + ": source-verified physical positions complete without plane calibration")
		await _dispose(screen)


func _reset_camera() -> bool:
	if pose.worker_pid == OS.get_process_id():
		pose.worker_pid = -1 # Never let stop_camera() kill this headless Godot.
	pose.stop_camera()
	pose.set_process(false)
	pose.peer = PacketPeerUDP.new()
	var bound: bool = pose.peer.bind(0, "127.0.0.1") == OK
	_check(bound, "offline authenticated pose listener binds loopback")
	if not bound:
		return false
	pose.worker_pid = OS.get_process_id() # Live-process stand-in, disarmed at cleanup.
	reset_number += 1
	pose.session_token = "plane-T-pose-test-session-" + str(reset_number)
	pose.active = true
	pose.player_x = -1.0
	return true


func _screen(activity: String) -> Control:
	var screen := scene.instantiate() as Control
	_check(screen != null and screen.has_method("set_context"),
		activity + ": actual authored calibration script loads")
	if screen == null or not screen.has_method("set_context"):
		if screen != null:
			screen.free()
		return null
	root.add_child(screen)
	screen.set_context({"activity": activity, "camera_requested": true,
		"student_name": "OFFLINE TEST", "game_mode": "Seconds", "topic": "Noun"})
	screen.set_process(false)
	return screen


func _source(x: float, population: int, t_pose: bool,
		track_id: int = PERSON, bank: float = 0.0, bank_valid: bool = true,
		hands_up: bool = false, hands_down: bool = false,
		hand_observation: bool = true) -> Dictionary:
	var solo := population == 1
	return {"kind": "pose", "token": pose.session_token,
		"camera": true, "camera_phase": "tracking", "state": "tracking",
		"camera_frame_age_ms": 20, "people": population, "fps": 8.0,
		"pose": solo and hand_observation, "lock_state": "locked" if solo and hand_observation else "occluded",
		"locked_id": track_id, "x": x if solo and hand_observation else -1.0,
		"plane_t_pose_valid": t_pose and solo and hand_observation,
		"plane_bank_valid": bank_valid and solo and hand_observation,
		"plane_bank": bank,
		"hand_observation_valid": hand_observation and solo,
		"both_hands_up": hands_up and solo,
		"both_hands_down": hands_down and solo,
		"hand_up": hands_up and solo}


func _packet(screen: Control, x: float, population: int, t_pose: bool,
		delta: float, count_source: bool = true, track_id: int = PERSON,
		hands_up: bool = false, hands_down: bool = false,
		hand_observation: bool = true) -> void:
	var data := _source(x, population, t_pose, track_id, 0.0, true,
		hands_up, hands_down, hand_observation)
	# The local camera packet carries the current authenticated session token,
	# source age, raw YOLO occupancy, lock and per-packet pose evidence.
	pose._apply_pose_packet(data, Time.get_ticks_msec())
	if count_source and population == 1 and hand_observation:
		source_clock += delta
		pose._record_fresh_calibration_pose(data, source_clock)
	# PoseService normally smooths rendering; tests assert the underlying
	# source-selected physical lane during each independent floor hold.
	if population == 1 and hand_observation:
		pose.player_x = x
	screen._process(delta)


func _dispose(screen: Control) -> void:
	# calibration.gd _exit_tree deliberately stops its camera. Its production
	# cleanup must never kill this headless process used as a live-PID stand-in.
	if pose.worker_pid == OS.get_process_id():
		pose.worker_pid = -1
	screen.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		failures.append(reason)
		printerr("PLANE SOURCE CALIBRATION FAIL: ", reason)


func _finish() -> void:
	if finished:
		return
	finished = true
	if is_instance_valid(pose):
		if pose.worker_pid == OS.get_process_id():
			pose.worker_pid = -1
		pose.stop_camera()
		pose.set_process(true)
	print("HUMAN PLANE VERIFIED T-POSE CALIBRATION: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
