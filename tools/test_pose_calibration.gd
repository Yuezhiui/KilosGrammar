extends SceneTree

# Deterministic legacy calibration regression, updated for the physically
# authenticated camera protocol. No webcam, YOLO worker, database or Git.
# Godot --headless --path . --script res://tools/test_pose_calibration.gd
const SCENE := "res://ui/vision/calibration/calibration.tscn"
const DT := 0.10
const NEUTRAL_X := 0.50

var pose: Node
var packed: PackedScene
var source_when := 1800.0
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload is available")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	_check(not pose.has_valid_pose(), "Idle camera cannot produce a valid pose")
	_check(not pose.set_calibration(0.45, 0.50, 0.53),
		"Reject tiny physical movement range")
	_check(not pose.set_calibration(0.20, 0.24, 0.80),
		"Reject center too near LEFT")
	_check(pose.set_calibration(0.20, 0.50, 0.80),
		"Strictly ordered real floor positions calibrate")
	pose.calibration.clear()
	packed = load(SCENE) as PackedScene
	_check(packed != null, "Current authored Calibration scene loads")
	if packed == null:
		_finish()
		return
	for guided in [false, true]:
		await _exercise(guided)
	pose.worker_pid = -1
	pose.stop_camera()
	_finish()


func _exercise(guided: bool) -> void:
	var mode := "Tutorial" if guided else "Play"
	pose.worker_pid = -1
	pose.stop_camera()
	pose.peer = PacketPeerUDP.new()
	_check(pose.peer.bind(0, "127.0.0.1") == OK,
		mode + ": isolated loopback camera receiver is bound")
	pose.worker_pid = OS.get_process_id() # Mock process liveness only.
	pose.session_token = "pose-legacy-authenticated-" + mode
	pose.active = true # set_context must not start/open physical webcam.
	var screen := packed.instantiate() as Control
	_check(screen != null and screen.has_method("set_context"),
		mode + ": latest calibration script is attached")
	if screen == null or not screen.has_method("set_context"):
		if screen != null:
			screen.free()
		pose.worker_pid = -1
		pose.stop_camera()
		return
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.set_context({"activity": "Catch the Word", "guided_tutorial": guided,
		"camera_requested": false, "game_mode": "Seconds", "topic": "Noun",
		"difficulty": "Easy", "keyboard_mode": true,
		"student_name": "SYNTHETIC QA"})
	screen.set_process(false) # Synthetic clock only, no actual timer waits.
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target": target, "payload": payload.duplicate(true)}))
	var stage := screen.get_node_or_null("TutorialStage") as Control
	var intro := stage.get_node_or_null("IntroOverlay") as Control if stage != null else null
	var success := stage.get_node_or_null("SuccessOverlay") as Control if stage != null else null
	var neutral_guide := stage.get_node_or_null("NeutralInstruction") as Label if stage != null else null
	_check(intro != null and success != null and neutral_guide != null,
		mode + ": editor-authored intro/success/neutral instruction exist")
	_check(stage != null and stage.get_node_or_null("ContinueButton") == null
		and stage.get_node_or_null("CenterCalibrationLane") == null
		and stage.get_node_or_null("CheckStatusButton") == null,
		mode + ": removed manual Check Camera, neon lane and Continue bypass stay absent")
	_check(bool(screen.intro_running) and intro != null and intro.visible
		and not bool(screen.success_running), mode + ": intro starts without old success")
	screen._process(2.99)
	_check(screen.intro_running and screen.live_step == 0 and is_zero_approx(screen.live_timer),
		mode + ": no hold credited at 2.99 seconds of the real 3-second intro")
	screen._process(0.01)
	_check(not screen.intro_running and neutral_guide.visible
		and not (stage.get_node("PoseGuides/PoseGuideDefault") as Control).visible,
		mode + ": 3.00s intro gives way to neutral prompt, not old CENTER guide")
	# Absent/crowded raw population may not create a source-valid station.
	for people in [0, 2, 3]:
		_packet(screen, 0.50, people, true)
		_check(screen.live_step == 0 and is_zero_approx(screen.live_timer)
			and routes.is_empty(), mode + ": raw people=%d cannot fake CENTER" % people)
	for _i in range(29):
		_packet(screen, NEUTRAL_X, 1, true, false)
	_check(screen.live_step == 0,
		mode + ": 2.8s of 8+ monotonic SOLO torso samples cannot complete neutral hold")
	for _i in range(4):
		_packet(screen, NEUTRAL_X, 1, true, false)
	_check(screen.live_step == 1,
		mode + ": one genuine 3s neutral hold completes without wrist evidence")
	_check(bool(pose.calibration.get("valid", false))
		and String(pose.calibration.get("mode", "")) == "neutral_body"
		and screen.measured_points.has("center")
		and screen.measured_points.has("neutral_noise")
		and not screen.measured_points.has("right") and not screen.measured_points.has("left"),
		mode + ": single real neutral center/noise, no invented side measurements")
	_check(bool(screen.success_running) and success != null and success.visible
		and bool(screen.transition_queued) and routes.is_empty(),
		mode + ": separate CALIBRATION SUCCESS appears before any GO")
	screen._continue_flow(false)
	screen._continue_flow(true)
	_check(routes.is_empty(), mode + ": manual Continue/Skip cannot bypass full 3s success")
	var original_measurements: Dictionary = screen.measured_points.duplicate(true)
	for _i in range(10):
		_packet(screen, 0.67, 1, true, false) # Fresh SOLO torso, no wrist evidence.
	_check(screen.success_running and screen.live_step == 1
		and screen.measured_points == original_measurements and routes.is_empty(),
		mode + ": moving student with missing wrists cannot restart successful calibration")
	var elapsed_saved: float = screen.success_elapsed
	for people in [2, 0]:
		_packet(screen, 0.5, people, false)
		_check(screen.success_running and screen.live_step == 1
			and screen.measured_points == original_measurements and routes.is_empty()
			and is_equal_approx(float(screen.success_elapsed), elapsed_saved),
			mode + ": %d people freeze GO but do not erase measured holds" % people)
	pose._last_occupancy_packet_ms = Time.get_ticks_msec() - int(pose.OCCUPANCY_STALE_MS) - 200
	screen._process(6.0)
	_check(routes.is_empty() and screen.success_running and screen.live_step == 1
		and is_equal_approx(float(screen.success_elapsed), elapsed_saved),
		mode + ": long source disconnection cannot GO or restart calibration")
	var before_route := maxi(0, floori((3.0 - screen.success_elapsed - 0.15) / DT))
	for _i in range(before_route):
		_packet(screen, 0.67, 1, true, false)
	_check(routes.is_empty() and screen.success_elapsed < 3.0,
		mode + ": no GO before full 3s authenticated SOLO success")
	for _i in range(4):
		_packet(screen, 0.67, 1, true, false)
	_check(routes.size() == 1 and routes[0].get("target", "") == "gameplay",
		mode + ": exactly one automatic gameplay request with genuine raw SOLO")
	if routes.size() == 1:
		var payload: Dictionary = routes[0]["payload"]
		_check(bool(payload.get("guided_tutorial", not guided)) == guided
			and bool(payload.get("start_countdown", false))
			and bool(payload.get("camera_live", false))
			and bool(payload.get("calibration_measured", false))
			and not bool(payload.get("keyboard_mode", true))
			and not bool(payload.get("calibration_skipped", true)),
			mode + ": correct Play countdown or Tutorial Spotlight flag, no keyboard bypass")
		_check(bool(payload.get("calibration_neutral_only", false))
			and is_equal_approx(float(payload.get("calibration_center", -1.0)), NEUTRAL_X)
			and not payload.has("calibration_left") and not payload.has("calibration_right"),
			mode + ": outgoing payload carries neutral-only measurement without fake bounds")
	for _i in range(6):
		_packet(screen, 0.5, 1, false)
		screen._continue_flow(false)
	_check(routes.size() == 1, mode + ": repeated post-GO frames cannot route twice")
	pose.worker_pid = -1 # Never pass self PID to any stop_camera teardown.
	screen.queue_free()
	await process_frame
	await process_frame
	pose.stop_camera()


func _packet(screen: Control, x: float, people: int, has_pose: bool, wrist_valid: bool = true) -> void:
	source_when += DT
	var valid := people == 1 and has_pose
	var packet: Dictionary = {"token": pose.session_token, "kind": "pose",
		"state": "tracking", "camera": true, "camera_phase": "tracking",
		"people": people, "foreground_people": people,
		"foreground_ambiguous": people != 1, "occupancy_verified": people == 1,
		"player_lock_epoch": 1,
		"pose": has_pose, "lock_state": "locked" if valid else "pending",
		"camera_frame_age_ms": 20, "fps": 10.0,
		"x": x if has_pose else -1.0, "hand_observation_valid": valid and wrist_valid,
		"hand_up": false, "pose_conf": 0.98 if valid else 0.03}
	pose._apply_pose_packet(packet, Time.get_ticks_msec())
	if valid:
		pose.player_x = x # Renderer smoothing cannot move a stable source hold.
		pose._record_fresh_calibration_pose(packet, source_when)
	screen._process(DT)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL auto calibration: ", message)


func _finish() -> void:
	if pose != null:
		pose.worker_pid = -1
		pose.stop_camera()
	print("POSE CALIBRATION: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
