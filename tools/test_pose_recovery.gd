extends SceneTree

## Isolated protocol/calibration regression. No camera, Python, or inference.
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pose_service := root.get_node_or_null("PoseService")
	_check(pose_service != null, "Autoload is available")
	if pose_service == null:
		quit(1)
		return
	pose_service.stop_camera()
	pose_service.active = true
	pose_service.session_token = "unit-test-only"
	var now := Time.get_ticks_msec()
	var measured := {"kind": "pose", "token": "unit-test-only", "state": "tracking",
		"pose": true, "camera": true, "people": 1, "lock_state": "locked",
		"camera_frame_age_ms": 20, "x": 0.43}
	pose_service._apply_pose_packet(measured, now)
	_check(pose_service.has_valid_pose(), "Measured packet yields live pose")
	_check(is_equal_approx(pose_service.player_x, 0.43), "Actual measured camera x is preserved")
	_check(pose_service.packet_sequence == 1, "Valid packet increments fresh pose sequence")
	_check(pose_service.set_calibration(0.18, 0.43, 0.85), "Asymmetric real calibration accepted")
	_check(absf(pose_service.normalized_body_x()) < 0.0001, "Calibrated CENTER maps to zero")

	var wrong_token := measured.duplicate()
	wrong_token["token"] = "old-worker-session"
	wrong_token["x"] = 0.9
	pose_service._apply_pose_packet(wrong_token, now)
	_check(is_equal_approx(pose_service.player_x, 0.43), "Old session packets are rejected")

	var missing := {"kind": "pose", "token": "unit-test-only", "state": "tracking",
		"pose": false, "camera": true, "people": 0, "x": -1.0, "lock_state": "lost"}
	pose_service._apply_pose_packet(missing, now + 1)
	_check(not pose_service.has_valid_pose() and pose_service.player_x < 0.0, "Pose loss invalidates controls immediately")
	_check(pose_service.packet_sequence == 1, "Missing pose does not earn calibration samples")
	_check(bool(pose_service.calibration.get("valid", false)), "Measured calibration survives missing frames")
	_check(is_zero_approx(pose_service.normalized_body_x()), "Invalid tracking produces no movement")

	pose_service._smoothed_x = -1.0
	var return_packet := measured.duplicate()
	return_packet["x"] = 0.85
	return_packet["locked_id"] = -1 # No ID registration on fresh solo recovery.
	return_packet["tracking_epoch"] = 90
	pose_service._apply_pose_packet(return_packet, now + 2)
	_check(pose_service.has_valid_pose(), "Real pose can return without recalibration")
	_check(absf(pose_service.normalized_body_x() - 1.0) < 0.001, "Right measured limit maps to +1")

	pose_service._schedule_restart(now + 3)
	_check(not pose_service.has_valid_pose(), "Worker restart invalidates controls")
	_check(bool(pose_service.calibration.get("valid", false)), "Automatic worker restart preserves calibration")
	_check(String(pose_service.current_status.get("state", "")) == "recovering", "Restart reports a helpful recovery state")
	pose_service.stop_camera()
	_check(pose_service.calibration.is_empty(), "Explicit stop still ends session calibration")

	# A previously healthy worker dying should schedule ONE bounded recovery;
	# this synthetic peer has no subprocess and never opens a camera.
	pose_service.active = true
	pose_service.peer = PacketPeerUDP.new()
	_check(pose_service.peer.bind(0, "127.0.0.1") == OK, "Local fake UDP receiver is available")
	pose_service.session_token = "unit-test-only"
	pose_service.worker_pid = -1
	pose_service._ever_tracked = true
	pose_service._automatic_restarts = 0
	pose_service._restart_pending = false
	pose_service.current_status = {"state": "tracking", "pose": false}
	pose_service._process(0.016)
	_check(pose_service._restart_pending, "Unexpected worker exit schedules safe recovery")
	_check(pose_service._automatic_restarts == 1, "Unexpected exit consumes one limited restart")
	_check(not pose_service.has_valid_pose(), "Restart never manufactures a player pose")
	pose_service.stop_camera()

	# A helper which never succeeded cannot restart indefinitely in the
	# background, for example when model weights or permissions are missing.
	pose_service.active = true
	pose_service.peer = PacketPeerUDP.new()
	pose_service.peer.bind(0, "127.0.0.1")
	pose_service.worker_pid = -1
	pose_service._ever_tracked = false
	pose_service._automatic_restarts = 0
	pose_service.current_status = {"state": "error", "pose": false}
	pose_service._process(0.016)
	_check(not pose_service.active and pose_service._automatic_restarts == 0, "Failed startup does not loop camera launches")
	pose_service.stop_camera()
	print("POSE RECOVERY: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL pose recovery: ", description)
