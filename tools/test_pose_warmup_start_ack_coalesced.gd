extends SceneTree

# Headless no-device regression: authenticated Play prewarm ACK is not lost
# when a later camera-opening status arrives in the same UDP render batch.
# Godot --headless --path . --script res://tools/test_pose_warmup_start_ack_coalesced.gd
var checks := 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pose := root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService loads")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	pose.status_updated.connect(_observe_status)
	await _check_batch(pose, "offline-ack-session", true)
	await _check_batch(pose, "offline-wrong-token-session", false)
	pose.status_updated.disconnect(_observe_status)
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _check_batch(pose: Node, token: String, authorized: bool) -> void:
	pose.stop_camera()
	pose.set_process(false)
	observations.clear()
	var receiver := PacketPeerUDP.new()
	_check(receiver.bind(0, "127.0.0.1") == OK, "Synthetic UDP receiver opens")
	pose.peer = receiver
	pose.active = true
	pose.session_token = token
	pose._model_prestarting = true
	pose._camera_start_requested = true
	pose._last_packet_ms = Time.get_ticks_msec()
	pose._launch_ms = Time.get_ticks_msec() - 12000
	pose._latest_worker_packet_time = -1.0
	pose.worker_pid = -1  # No subprocess, webcam, or YOLO ever runs.
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1", receiver.get_local_port())
	var ack_token := token if authorized else "invalid-token"
	var ack := {"kind": "pose", "token": ack_token, "when": 1000.0,
		"state": "loading", "camera": true, "camera_phase": "start_ack",
		"pose": false, "model_ready": false}
	var opening := {"kind": "pose", "token": token, "when": 1000.1,
		"state": "loading", "camera": false, "camera_phase": "opening",
		"pose": false, "model_ready": false}
	_check(sender.put_packet(JSON.stringify(ack).to_utf8_buffer()) == OK,
		"Synthetic camera-start status is queued")
	_check(sender.put_packet(JSON.stringify(opening).to_utf8_buffer()) == OK,
		"Newer opening status is queued in same render frame")
	await process_frame
	pose.call("_process", 0.016)
	_check(not observations.is_empty(), "Newest camera-opening status was delivered")
	if not observations.is_empty():
		var observed: Dictionary = observations.back()
		_check(bool(observed.get("started", false)) == authorized,
			"Authenticated ACK survives status coalescing; wrong-token ACK is rejected")
		_check(String(observed.get("phase", "")) == "opening",
			"Actual newest camera status is rendered")
		if authorized:
			_check(int(observed.get("startup_ms", -1)) < 1000,
				"Camera opening watchdog clock starts at ACK, not 12-second prewarm")
		_check(not bool(observed.get("pose", true)),
			"Camera-start ACK never manufactures a student pose")
	sender.close()
	pose.stop_camera()


func _observe_status(status: Dictionary) -> void:
	if String(status.get("camera_phase", "")) != "opening":
		return
	var pose := root.get_node_or_null("PoseService")
	observations.append({
		"phase": String(status.get("camera_phase", "")),
		"started": not bool(pose.get("_model_prestarting")) and
			not bool(pose.get("_camera_start_requested")),
		"startup_ms": Time.get_ticks_msec() - int(pose.get("_launch_ms")),
		"pose": bool(status.get("pose", false))
	})


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("POSE WARM START ACK FAIL: ", description)


func _finish() -> void:
	print("POSE WARM START ACK: %s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
