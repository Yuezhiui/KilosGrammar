extends SceneTree

# Pure Godot/localhost UDP simulation: NO physical webcam, YOLO, Python, DB.
# --headless --path . --script res://tools/test_pose_solo_pause_oscillation_stress.gd
# Gameplay must never pulse false on genuinely fresh stable SOLO frames, and
# must freeze immediately on any invalid/0/2+ packet, not on a track ID change.
const TOKEN := "solo-fresh-movement-stress"
var pose: Node
var udp: PacketPeerUDP
var checks := 0
var failures: Array[String] = []
var source_when := 10.0
var emitted: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService singleton loads")
	if pose == null:
		_finish()
		return
	_setup()
	await _continuous_moving_solo()
	await _strict_unsafe_population_and_resume()
	await _inference_recovery_and_out_of_order_frames()
	_source_latency_never_renews_old_body()
	_gesture_and_plane_capture_age()
	_worker_stall_and_restart()
	pose.worker_pid = -1
	if udp != null:
		udp.close()
	pose.stop_camera()
	_finish()


func _setup() -> void:
	pose.stop_camera()
	pose.set_process(false)
	pose.peer = PacketPeerUDP.new()
	_check(pose.peer.bind(0, "127.0.0.1") == OK, "Mock stream receives only localhost packets")
	udp = PacketPeerUDP.new()
	_check(udp.set_dest_address("127.0.0.1", pose.peer.get_local_port()) == OK,
		"Mock worker's UDP sender binds only loopback")
	pose.active = true
	pose.worker_pid = OS.get_process_id() # Never stop_camera until cleared.
	pose.session_token = TOKEN
	pose._launch_ms = Time.get_ticks_msec()
	pose._last_packet_ms = Time.get_ticks_msec()
	pose._worker_was_tracking = true
	pose._worker_was_streaming = true
	pose._latest_worker_packet_time = -1.0
	pose.set_calibration(0.18, 0.50, 0.82)
	pose.status_updated.connect(_observe_status)


func _observe_status(status: Dictionary) -> void:
	emitted.append(status.duplicate(true))


func _packet(people: int, x: float = 0.5, locked: String = "locked",
		age_ms: Variant = 20, active_pose: bool = true) -> Dictionary:
	return {
		"kind": "pose", "token": TOKEN, "state": "tracking",
		"camera": true, "camera_phase": "tracking", "pose": active_pose,
		"people": people, "x": x, "locked_id": -1,
		"lock_state": locked, "camera_frame_age_ms": age_ms,
		"hand_up": true, "hand_observation_valid": true,
		"plane_steering": x, "plane_steering_valid": true,
		"plane_bank": x * 2.0 - 1.0, "plane_bank_valid": true,
		"plane_neutral_valid": true
	}


func _send(status: Dictionary) -> void:
	source_when += 0.041
	status["when"] = source_when
	_check(udp.put_packet(JSON.stringify(status).to_utf8_buffer()) == OK,
		"Real serialized worker status accepted into local receiver")
	await process_frame
	pose._process(0.016)


func _continuous_moving_solo() -> void:
	var false_positives := 0
	var status_updates := emitted.size()
	# Left-to-right motion and back, 80 fresh inferred positions, never leaves
	# camera and is not tied to any external ByteTrack ID/epoch registration.
	for i in range(80):
		var measured_x: float = 0.2 + 0.6 * (float(i % 40) / 39.0)
		await _send(_packet(1, measured_x))
		if not pose.has_valid_pose():
			false_positives += 1
		_check(pose.player_x >= 0.0, "Solo moving pose remains current at packet %d" % i)
	_check(false_positives == 0,
		"80 stable fresh SOLO frames cause ZERO PAUSE-PLAY oscillations")
	_check(emitted.size() - status_updates == 80,
		"Each new trusted worker frame emits exactly one fresh status update")
	_check(pose.calibration.get("valid", false) and not pose.calibration.has("locked_id"),
		"Initial measured floor limits survive movement and tracker ID absence")
	_check(pose._camera_watchdog_status(Time.get_ticks_msec()) == "",
		"Healthy streaming source never schedules worker restart")


func _strict_unsafe_population_and_resume() -> void:
	for people in [0, 2, 3]:
		await _send(_packet(people, 0.73))
		_check(not pose.has_valid_pose() and pose.player_x == -1.0,
			"%d people revoke ALL controls on very first unsafe frame" % people)
		_check(not pose.has_fresh_gesture_pose() and
			is_zero_approx(pose.normalized_body_x()),
			"%d people cannot use stale gestures or camera steering" % people)
		await _send(_packet(1, 0.77))
		_check(pose.has_valid_pose() and pose.normalized_body_x() > 0.0,
			"Fresh new SOLO restores movement after %d people" % people)
	await _send(_packet(1, 0.53, "enrolling", 20, false))
	_check(not pose.has_valid_pose() and pose.player_x == -1.0,
		"One present but UNENROLLED person never receives gameplay permission")
	await _send(_packet(1, 0.53))
	_check(pose.has_valid_pose(),
		"New true stable solo immediately resumes, without physical recalibration")


func _inference_recovery_and_out_of_order_frames() -> void:
	var retained: float = float(pose.player_x)
	var sequence: int = int(pose.packet_sequence)
	# A deliberately OLD UDP event must never override a newer confirmed pose.
	var delayed := _packet(0, -1.0, "lost", 40, false)
	delayed["when"] = source_when - 10.0
	udp.put_packet(JSON.stringify(delayed).to_utf8_buffer())
	await process_frame
	pose._process(0.016)
	_check(pose.has_valid_pose() and is_equal_approx(pose.player_x, retained),
		"Out-of-order old missing status cannot override newer live SOLO")
	_check(pose.packet_sequence == sequence,
		"Out-of-order source packet earns no extra movement sample")
	# A genuinely NEW sensor failure MUST revoke control; never coalesce it
	# away simply to make UI stay in PLAY.
	var recovering := _packet(1, 0.5, "occluded", 800, false)
	recovering["state"] = "recovering"
	await _send(recovering)
	_check(not pose.has_valid_pose() and pose.player_x == -1.0,
		"Newer recovering/stale-inference status immediately suspends player")
	_check(not pose.has_hand_raised(),
		"Newer failed inference cannot leave previous raising gesture latched")
	await _send(_packet(1, 0.48))
	_check(pose.has_valid_pose() and
		bool(pose.calibration.get("valid", false)),
		"Fresh stable SOLO after recovering returns to SAME round without route")


func _source_latency_never_renews_old_body() -> void:
	var capture_lag := _packet(1, 0.64, "locked", 640)
	pose._apply_pose_packet(capture_lag, Time.get_ticks_msec())
	_check(pose.has_valid_pose(), "640ms YOLO source allowed only while TOTAL age remains <=1750")
	pose.last_pose_ms = Time.get_ticks_msec() - 20
	_check(not pose.has_fresh_gesture_pose(),
		"Already 640ms-old source cannot produce even a 20ms-old gesture")
	pose.last_pose_ms = Time.get_ticks_msec() - 1100
	_check(pose.has_valid_pose(), "Source total-age 640+1100ms remains under body budget")
	pose.last_pose_ms = Time.get_ticks_msec() - 1140
	_check(not pose.has_valid_pose(),
		"Source capture age PLUS elapsed reception age exceeds 1750ms budget")
	var before := emitted.size()
	pose._last_packet_ms = Time.get_ticks_msec()
	pose._process(0.016)
	_check(pose.player_x == -1.0 and String(pose.current_status.get("state")) == "stale",
		"Expiry revokes stale movement and emits an honest fresh-frame notice")
	_check(emitted.size() == before + 1 and not bool(emitted.back().get("pose", true)),
		"One authoritative status_updated(false) emitted for fully expired source")
	pose._process(0.016)
	_check(emitted.size() == before + 1,
		"Expired pose sends no repeated PAUSE events every UI render tick")
	pose._apply_pose_packet(_packet(1, 0.60), Time.get_ticks_msec())
	_check(pose.has_valid_pose(),
		"Fresh stable SOLO following capture timeout resumes without ID registration")


func _gesture_and_plane_capture_age() -> void:
	_check(pose.set_stationary_plane_calibration(0.5, -1, 0.5),
		"Single neutral Human Plane calibration works without identity")
	pose._apply_pose_packet(_packet(1, 0.62, "locked", 540), Time.get_ticks_msec())
	_check(pose.has_fresh_gesture_pose() and pose.has_stationary_plane_pose(),
		"540ms source still grants genuinely fresh wrist / plane steering")
	pose.last_pose_ms = Time.get_ticks_msec() - 125
	_check(pose.has_valid_pose() and not pose.has_fresh_gesture_pose()
		and not pose.has_stationary_plane_pose(),
		"Captured source age + receiver age >650ms blocks gesture AND plane pose")
	_check(is_zero_approx(pose.normalized_plane_steering()) and not pose.has_hand_raised(),
		"Expired plane/hand pose never steers or triggers ghost shooting")


func _worker_stall_and_restart() -> void:
	pose.worker_pid = -1 # NEVER kill the Godot test-runner PID.
	pose._last_packet_ms = Time.get_ticks_msec() - 6200
	pose._worker_was_tracking = true
	_check(pose._camera_watchdog_status(Time.get_ticks_msec()) == "stream_stalled",
		"6.2 seconds of no worker packets schedules bounded recovery")
	var retained: Dictionary = pose.calibration.duplicate(true)
	pose._schedule_restart(Time.get_ticks_msec())
	_check(not pose.has_valid_pose() and pose.player_x == -1.0 and pose._restart_pending,
		"Camera restart always clears tracking, never grants stale solo position")
	_check(pose.calibration == retained,
		"Same physical calibration remains valid throughout this interrupted round")
	pose._restart_pending = false
	pose.worker_pid = OS.get_process_id()
	pose.session_token = TOKEN
	pose._latest_worker_packet_time = -1.0
	pose._last_packet_ms = Time.get_ticks_msec()
	pose._apply_pose_packet(_packet(1, 0.55), Time.get_ticks_msec())
	_check(pose.has_valid_pose() and not pose.requires_player_recalibration(),
		"Fresh SOLO after replacement worker resumes ID-free with no route")


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
		printerr("POSE OSCILLATION FAIL: ", reason)


func _finish() -> void:
	print("POSE SOLO OSCILLATION: %s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
