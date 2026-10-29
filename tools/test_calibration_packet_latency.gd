extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_calibration_packet_latency.gd
# UDP worker protocol exercised locally; no YOLO, webcam, Python or database.
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pose := root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload available")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	var server := PacketPeerUDP.new()
	_check(server.bind(0, "127.0.0.1") == OK, "local UDP worker receiver binds")
	var sender := PacketPeerUDP.new()
	_check(sender.set_dest_address("127.0.0.1", server.get_local_port()) == OK,
		"local mock UDP sender has receiver address")
	pose.set("peer", server)
	pose.set("session_token", "fake-session-123456")
	pose.set("active", true)
	# We never launch a subprocess. Mark this SceneTree's still-running PID
	# temporarily as the mock worker so _process does not launch recovery.
	# Set it back to -1 BEFORE stop_camera so the game cannot kill itself.
	pose.set("worker_pid", OS.get_process_id())
	var now := Time.get_ticks_msec()
	pose.set("_launch_ms", now)
	pose.set("_last_packet_ms", now)
	var signal_states: Array[Dictionary] = []
	pose.status_updated.connect(func(data: Dictionary) -> void: signal_states.append(data.duplicate()))
	var token := "fake-session-123456"
	_send_preview(sender, Color(0.9, 0.1, 0.1))
	_send_preview(sender, Color(0.1, 0.1, 0.9))
	# The newest timestamp wins even when older pose datagrams are delivered
	# later, and a prior worker's token is never applied.
	_send(sender, token, 100.0, 0.2)
	_send(sender, token, 103.0, 0.8)
	_send(sender, token, 101.0, 0.3)
	_send(sender, "previous-worker-token", 120.0, 0.1)
	await process_frame
	pose.call("_process", 0.016)
	_check(int(pose.get("packet_sequence")) == 2,
		"Backlogged UDP batch preserves two monotonic source frames (100, 103), skipping out-of-order 101")
	_check(int(pose.get("latest_pose_sample_id")) == 2,
		"Two independently inferred student frames receive two fresh sample IDs")
	var received: Array = pose.call("get_pose_samples_after", 0)
	_check(received.size() == 2 and
		is_equal_approx(float(received[0].get("x", -1.0)), 0.2) and
		is_equal_approx(float(received[1].get("x", -1.0)), 0.8),
		"Calibration receives both real source x values, not just newest rendered pose")
	_check(absf(float(pose.get("player_x")) - 0.8) < 0.02,
		"newest timestamp wins over out-of-order datagrams")
	_check(int(pose.get("first_valid_pose_ms")) >= 0,
		"first real pose has measured local startup latency")
	_check(int(pose.get("first_camera_preview_ms")) >= 0,
		"first live camera preview records startup latency independently of YOLO")
	var preview := pose.get("preview_texture") as ImageTexture
	_check(preview != null and preview.get_size() == Vector2(32, 24),
		"32×24 synthetic image decodes into actual preview Texture2D")
	if preview != null:
		var color := preview.get_image().get_pixel(4, 4)
		_check(color.b > color.r + 0.3,
			"latest preview JPEG wins over older red frame in same UDP burst")
	_check(signal_states.size() == 1 and String(signal_states[0].get("state", "")) == "tracking",
		"only one status update emitted for burst of camera packets")
	var seq := int(pose.get("packet_sequence"))
	var last := int(pose.get("last_pose_ms"))
	_send(sender, token, 99.0, 0.1)
	_send(sender, token, 103.0, 0.4)
	await process_frame
	pose.call("_process", 0.016)
	_check(int(pose.get("packet_sequence")) == seq and
		int(pose.get("last_pose_ms")) == last,
		"duplicates and old worker timestamps cannot refresh pose freshness")
	_check(int(pose.get("latest_pose_sample_id")) == 2 and
		(pose.call("get_pose_samples_after", 0) as Array).size() == 2,
		"Duplicate/old source timestamps never make new calibration frames")
	_check(absf(float(pose.get("player_x")) - 0.8) < 0.02,
		"a stale camera packet cannot move the student backward")
	pose.set("calibration", {"left": 0.2, "center": 0.5, "right": 0.82, "valid": true})
	pose.set("last_pose_ms", Time.get_ticks_msec() - 1800)
	_check(not bool(pose.call("has_valid_pose")),
		"expired last-pose age prevents old coordinates becoming valid")
	_check(not bool(pose.call("has_fresh_gesture_pose")),
		"stale tracking also disables pose gesture control")
	pose.set("last_pose_ms", Time.get_ticks_msec() - 700)
	_check(bool(pose.call("has_valid_pose")) and not bool(pose.call("has_fresh_gesture_pose")),
		"body calibration grace exceeds gesture freshness without ghost control")
	# Reconnect keeps valid measurements while rejecting any old session token.
	pose.set("_ever_tracked", true)
	pose.set("worker_pid", -1)
	pose.call("_schedule_restart", Time.get_ticks_msec())
	_check(bool(pose.get("_restart_pending")), "tracked worker can reconnect automatically")
	_check(bool((pose.get("calibration") as Dictionary).get("valid", false)),
		"worker reconnection retains real center/right/left samples")
	_check(not bool(pose.call("has_valid_pose")),
		"reconnection immediately disables stale input")
	pose.stop_camera()
	pose.set_process(false)
	sender.close()
	_check((pose.get("calibration") as Dictionary).is_empty(),
		"explicit stop releases calibration and worker session")
	_finish()


func _send(sender: PacketPeerUDP, token: String, when: float, x: float) -> void:
	var payload := {"kind": "pose", "token": token, "when": when,
		# The current safety protocol requires a real raw SOLO observation and
		# a camera-authenticated source frame, not just a retained pose/X value.
		"state": "tracking", "pose": true, "x": x, "lock_state": "locked",
		"camera": true, "camera_phase": "tracking", "people": 1,
		"camera_frame_age_ms": 20, "fps": 20.0}
	sender.put_packet(JSON.stringify(payload).to_utf8_buffer())


func _send_preview(sender: PacketPeerUDP, tint: Color) -> void:
	var picture := Image.create(32, 24, false, Image.FORMAT_RGB8)
	picture.fill(tint)
	var bytes := PackedByteArray([1])
	bytes.append_array(picture.save_jpg_to_buffer(0.80))
	sender.put_packet(bytes)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("CALIBRATION LATENCY PACKETS FAIL: ", description)


func _finish() -> void:
	print("CALIBRATION LATENCY PACKETS: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
