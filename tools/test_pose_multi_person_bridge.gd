extends SceneTree

# Offline Godot watchdog, packet-age and autoload regression.
# --headless --path . --script res://tools/test_pose_multi_person_bridge.gd
# Never starts YOLO, camera, model preload, or a worker process.

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pose := root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload exists")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	pose.active = true
	pose.session_token = "offline-synthetic-test"
	var now := Time.get_ticks_msec()
	var packet := {"token": pose.session_token, "kind": "pose",
		"state": "tracking", "camera": true, "camera_phase": "tracking",
		"pose": true, "people": 1, "lock_state": "locked", "locked_id": -1,
		"x": 0.51, "plane_steering": 0.1, "plane_steering_valid": true,
		"plane_neutral_valid": true, "camera_frame_age_ms": 100}
	pose.call("_apply_pose_packet", packet, now)
	_check(bool(pose.call("has_valid_pose")), "fresh locked pose is valid")
	_check(bool(pose.get("_worker_was_streaming")), "camera streaming recognized even when no student later")
	pose.call("_record_fresh_calibration_pose", packet, 100.0)
	_check(int(pose.get("latest_pose_sample_id")) == 1, "fresh source packet earns one sample")
	pose.call("_record_fresh_calibration_pose", packet, 100.0)
	_check(int(pose.get("latest_pose_sample_id")) == 1, "duplicate source timestamp never counts twice")
	packet["camera_frame_age_ms"] = 780
	pose.call("_record_fresh_calibration_pose", packet, 101.0)
	_check(int(pose.get("latest_pose_sample_id")) == 1, "inferred image older than 650ms cannot calibrate")
	pose.call("_apply_pose_packet", packet, now)
	_check(not bool(pose.call("has_valid_pose")) and float(pose.get("player_x")) == -1.0,
		"late inference cannot remain live or steer")
	packet["camera_frame_age_ms"] = 100
	packet["token"] = "wrong-token"
	pose.call("_apply_pose_packet", packet, now)
	_check(not bool(pose.call("has_valid_pose")), "wrong session cannot revive stale student")

	# Model prewarm may wait for camera permission, but a stuck loading model
	# and a stuck native VideoCapture/open must finish with a bounded error.
	pose.set("_worker_was_streaming", false)
	pose.set("_worker_was_tracking", false)
	pose.set("_model_prestarting", true)
	pose.set("_camera_start_requested", false)
	pose.set("_launch_ms", now - 61000)
	pose.set("current_status", {"state": "prewarming", "model_ready": false})
	_check(pose.call("_camera_watchdog_status", now) == "prewarm_stalled",
		"offline model wedged beyond 60s has watchdog")
	pose.set("current_status", {"state": "ready", "model_ready": true})
	_check(pose.call("_camera_watchdog_status", now) == "",
		"ready model may safely wait for tutorial/play camera permission")
	pose.set("_model_prestarting", false)
	pose.set("_launch_ms", now - 31000)
	_check(pose.call("_camera_watchdog_status", now) == "camera_stalled",
		"native camera opening beyond 30s cannot hang forever")
	pose.set("_worker_was_streaming", true)
	pose.set("_last_packet_ms", now)
	_check(pose.call("_camera_watchdog_status", now) == "",
		"streaming camera can wait for child to enter scene")
	pose.set("_last_packet_ms", now - 21000)
	_check(pose.call("_camera_watchdog_status", now) == "stream_stalled",
		"camera streaming without any status for 20s triggers restart")
	pose.set("_worker_was_tracking", true)
	pose.set("_last_packet_ms", now - 6000)
	_check(pose.call("_camera_watchdog_status", now) == "stream_stalled",
		"tracked worker stopped updating beyond 5.5s triggers restart")
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)


func _finish() -> void:
	for description in failures:
		printerr("FAIL pose crowd/watchdog bridge: ", description)
	print("%s pose crowd/watchdog bridge: %d checks, %d failures" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
