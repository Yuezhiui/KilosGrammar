extends SceneTree

# No camera/YOLO/DB. Send synthetic worker JSON through actual local UDP.
# --headless --path . --script res://tools/test_pose_raw_solo_occupancy_gate.gd
const TOKEN := "raw-person-occupancy-session"
var pose: Node
var udp: PacketPeerUDP
var checks := 0
var failures: Array[String] = []
var next_when := 20.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService singleton is available")
	if pose == null:
		_finish()
		return
	_setup()
	_check(pose.fresh_camera_population() == -1 and not pose.has_fresh_solo_presence(),
		"No raw YOLO inference yet: occupancy is UNKNOWN")
	await _solo_without_pose()
	await _crowd_and_zeros()
	await _malformed_and_absent_source()
	await _latency_and_reordered_traffic()
	await _round_reset_and_restart()
	pose.worker_pid = -1 # Mock process: never allow Godot to kill itself.
	if udp != null:
		udp.close()
	pose.stop_camera()
	_finish()


func _setup() -> void:
	pose.stop_camera()
	pose.set_process(false)
	pose.peer = PacketPeerUDP.new()
	_check(pose.peer.bind(0, "127.0.0.1") == OK,
		"Transport binds only localhost, not a real camera")
	udp = PacketPeerUDP.new()
	_check(udp.set_dest_address("127.0.0.1", pose.peer.get_local_port()) == OK,
		"Mock UDP worker destination is localhost")
	pose.worker_pid = OS.get_process_id() # Stub live local process; never kill.
	pose.active = true
	pose.session_token = TOKEN
	pose._launch_ms = Time.get_ticks_msec()
	pose._last_packet_ms = Time.get_ticks_msec()
	pose._latest_worker_packet_time = -1.0
	_check(pose.set_calibration(0.18, 0.50, 0.82),
		"Physically measured calibration is available for test")


func _frame(count: Variant, pose_valid: bool = false, lock: String = "enrolling") -> Dictionary:
	return {
		"kind": "pose", "token": TOKEN, "state": "tracking", "camera": true,
		"camera_phase": "tracking", "camera_frame_age_ms": 35,
		"people": count, "pose": pose_valid, "lock_state": lock,
		"locked_id": -1, "x": 0.51, "hand_up": true,
		"airplane_pose": true, "hand_observation_valid": true,
		"plane_steering_valid": true, "plane_steering": 0.51
	}


func _send(data: Dictionary) -> void:
	next_when += 0.10
	data["when"] = next_when
	_check(udp.put_packet(JSON.stringify(data).to_utf8_buffer()) == OK,
		"Authenticated synthetic worker JSON sent over actual localhost UDP")
	await process_frame
	pose._process(0.016)


func _solo_without_pose() -> void:
	await _send(_frame(1))
	_check(pose.fresh_camera_population() == 1 and pose.has_fresh_solo_presence(),
		"1 raw YOLO body is present despite StudentLock enrolling/pose=false")
	_check(not pose.has_recent_missing_student_observation(),
		"One SOLO body missing pose cannot be misclassified as absent")
	_check(not pose.has_valid_pose() and pose.player_x == -1.0,
		"Presence never synthesizes movement when no valid body keypoints exist")
	_check(not pose.has_fresh_gesture_pose() and not pose.has_hand_raised(),
		"Presence never resurrects hand gestures from invalid pose data")
	await _send(_frame(1, false, "occluded"))
	_check(pose.has_fresh_solo_presence() and not pose.has_valid_pose(),
		"One person with occluded torso is STILL present without movement")
	await _send(_frame(1, true, "locked"))
	_check(pose.has_fresh_solo_presence() and pose.has_valid_pose(),
		"Fresh stable pose grants movement IN ADDITION TO one-person presence")
	await _send(_frame(1, false, "enrolling"))
	_check(pose.has_fresh_solo_presence() and not pose.has_valid_pose()
		and pose.player_x == -1.0,
		"Single bad keypoint frame revokes motion but NOT fresh solo occupancy")
	_check(bool(pose.calibration.get("valid", false)) and not pose.requires_player_recalibration(),
		"Same physical calibration survives transient keypoint/StudentLock loss")


func _crowd_and_zeros() -> void:
	for count in [0, 2, 3, 12]:
		await _send(_frame(count))
		_check(pose.fresh_camera_population() == count and not pose.has_fresh_solo_presence(),
			"YOLO count %d immediately disables occupancy-only play" % count)
		_check(pose.has_recent_missing_student_observation() == (count == 0),
			"Only one fresh real zero-person count justifies missing-student prompt")
		_check(not pose.has_valid_pose() and pose.player_x == -1.0
			and not pose.has_fresh_gesture_pose(),
			"Unsafe count %d immediately revokes all movement and gestures" % count)
		await _send(_frame(1, false, "enrolling"))
		_check(pose.has_fresh_solo_presence() and not pose.has_valid_pose(),
			"Returning 1 raw person can resume occupancy despite pose re-enrollment")


func _malformed_and_absent_source() -> void:
	for invalid_people in [-1, 13, 1.5, "1", null, {}, []]:
		await _send(_frame(invalid_people))
		_check(pose.fresh_camera_population() == -1 and not pose.has_fresh_solo_presence(),
			"Invalid/malformed count is UNKNOWN: %s" % str(invalid_people))
	var missing := _frame(1)
	missing.erase("people")
	await _send(missing)
	_check(pose.fresh_camera_population() == -1, "Missing real YOLO count is UNKNOWN")
	for invalid_age in [-1, 651, "old", null]:
		var data := _frame(1)
		data["camera_frame_age_ms"] = invalid_age
		await _send(data)
		_check(pose.fresh_camera_population() == -1,
			"Invalid/stale source age cannot fake presence: %s" % str(invalid_age))
	var no_age := _frame(1)
	no_age.erase("camera_frame_age_ms")
	await _send(no_age)
	_check(pose.fresh_camera_population() == -1,
		"Legacy pose packet without source age cannot claim current YOLO occupancy")
	for invalid_state in ["loading", "recovering", "stale", "error", "off"]:
		var data := _frame(1)
		data["state"] = invalid_state
		await _send(data)
		_check(pose.fresh_camera_population() == -1,
			"State %s cannot replay previously seen SOLO person" % invalid_state)
	var bad_phase := _frame(1)
	bad_phase["camera_phase"] = "preview"
	await _send(bad_phase)
	_check(pose.fresh_camera_population() == -1,
		"Only completed raw YOLO tracking inference can assert person count")
	bad_phase = _frame(1)
	bad_phase["camera"] = false
	await _send(bad_phase)
	_check(pose.fresh_camera_population() == -1,
		"Warmup worker camera=false cannot claim solo person")
	var missing_phase := _frame(1)
	missing_phase.erase("camera_phase")
	await _send(missing_phase)
	_check(pose.fresh_camera_population() == -1,
		"Legacy packet without explicit tracking-inference phase is UNKNOWN")


func _latency_and_reordered_traffic() -> void:
	await _send(_frame(1, false))
	var stored_when: float = next_when
	var old_zero := _frame(0)
	old_zero["when"] = stored_when - 2.0
	udp.put_packet(JSON.stringify(old_zero).to_utf8_buffer())
	await process_frame
	pose._process(0.016)
	_check(pose.fresh_camera_population() == 1,
		"Older reordered zero-person frame cannot replace newest SOLO source")
	var duplicate := _frame(2)
	duplicate["when"] = stored_when
	udp.put_packet(JSON.stringify(duplicate).to_utf8_buffer())
	await process_frame
	pose._process(0.016)
	_check(pose.fresh_camera_population() == 1,
		"Duplicate timestamp cannot forge newer crowd observation")
	pose._last_occupancy_packet_ms = Time.get_ticks_msec() - 1165
	_check(pose.fresh_camera_population() == -1,
		"Raw occupancy expires after Python capture age + Godot elapsed >1200ms")
	_check(not pose.has_recent_missing_student_observation(),
		"Stale camera never claims the classroom is empty")
	await _send(_frame(1, false))
	_check(pose.fresh_camera_population() == 1,
		"Subsequent fresh raw inference re-enables occupancy without a pose")
	var restored: int = pose._last_occupancy_packet_ms
	pose._set_status({"state": "loading", "pose": false, "detail": "starting"})
	_check(pose.fresh_camera_population() == -1,
		"Worker status overwrite never retains old SOLO as current observation")
	pose._last_occupancy_packet_ms = restored
	pose._apply_pose_packet(_frame(1, false), Time.get_ticks_msec())
	_check(pose.fresh_camera_population() == 1,
		"New authenticated inference allows raw occupancy again")


func _round_reset_and_restart() -> void:
	pose.begin_new_round_tracking()
	_check(pose.fresh_camera_population() == -1 and not pose.has_fresh_solo_presence(),
		"Retry invalidates old round's occupancy, not just torso measurements")
	await _send(_frame(1, false))
	_check(pose.fresh_camera_population() == 1 and not pose.has_valid_pose(),
		"First new round raw SOLO returns without requiring tracker enrollment")
	pose.worker_pid = -1 # Avoid OS.kill against the Godot test runner.
	pose._schedule_restart(Time.get_ticks_msec())
	_check(pose.fresh_camera_population() == -1 and not pose.has_fresh_solo_presence(),
		"Camera restart removes cached SOLO occupancy immediately")
	pose._restart_pending = false
	pose._latest_worker_packet_time = -1
	pose.worker_pid = OS.get_process_id()
	pose.session_token = "new-authenticated-camera"
	var stale_previous := _frame(1)
	stale_previous["when"] = next_when + 1.0
	udp.put_packet(JSON.stringify(stale_previous).to_utf8_buffer())
	await process_frame
	pose._process(0.016)
	_check(pose.fresh_camera_population() == -1,
		"Wrong-token old worker SOLO cannot re-enter after restart")
	var replacement := _frame(1, false)
	replacement["token"] = pose.session_token
	await _send(replacement)
	_check(pose.fresh_camera_population() == 1 and not pose.has_valid_pose(),
		"New authenticated worker sees fresh YOLO SOLO even with pose=false")
	pose.active = false
	_check(pose.fresh_camera_population() == -1,
		"Camera inactive immediately invalidates existing fresh presence")
	pose.active = true
	pose.worker_pid = -1
	_check(pose.fresh_camera_population() == -1,
		"Dead worker immediately invalidates fresh cached person count")
	pose.worker_pid = OS.get_process_id()
	pose.peer.close()
	pose.peer = null
	_check(pose.fresh_camera_population() == -1,
		"Broken UDP transport immediately invalidates cached person count")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("RAW OCCUPANCY FAIL: ", description)


func _finish() -> void:
	print("RAW YOLO SOLO OCCUPANCY: %s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
