extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_pose_preview_freshness_audit.gd
# No webcam, YOLO, DB, network or worker process. Tests real calibration scene.
const CALIBRATION := "res://ui/vision/calibration/calibration.tscn"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pose := root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload present")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	pose.active = true
	pose.session_token = "synthetic-offline-session"
	var packet: Dictionary = {
		"token": pose.session_token, "kind": "pose", "state": "tracking",
		"pose": true, "camera": true, "camera_phase": "tracking", "x": 0.52,
		"lock_state": "locked", "people": 1, "locked_id": 6,
		"camera_frame_age_ms": 100, "plane_steering": 0.52,
		"plane_steering_valid": true, "plane_neutral_valid": true
	}
	var now := Time.get_ticks_msec()
	pose.call("_apply_pose_packet", packet, now)
	_check(pose.has_valid_pose(), "real fresh locked packet allows tracking")
	pose.call("_record_fresh_calibration_pose", packet, 100.0)
	_check(pose.latest_pose_sample_id == 1, "trusted current frame enters sample history")
	var untrusted := packet.duplicate()
	untrusted["lock_state"] = "ambiguous"
	pose.call("_record_fresh_calibration_pose", untrusted, 101.0)
	_check(pose.latest_pose_sample_id == 1, "ambiguous bystander frame earns no calibration sample")
	pose.call("_apply_pose_packet", untrusted, now)
	_check(not pose.has_valid_pose(), "ambiguous pose cannot masquerade as valid tracking")
	untrusted["lock_state"] = "locked"
	untrusted["locked_id"] = -1
	pose.call("_apply_pose_packet", untrusted, now)
	_check(pose.has_valid_pose(), "idless stable one-person YOLO pose can control gameplay")
	for invalid_age in [-1, 651, INF, NAN, "oops"]:
		untrusted["locked_id"] = 6
		untrusted["camera_frame_age_ms"] = invalid_age
		pose.call("_apply_pose_packet", untrusted, now)
		_check(not pose.has_valid_pose(), "bad capture-frame age rejected: %s" % str(invalid_age))
		pose.call("_record_fresh_calibration_pose", untrusted, 102.0)
		_check(pose.latest_pose_sample_id == 1, "bad age never contributes to hold: %s" % str(invalid_age))

	var scene := load(CALIBRATION) as PackedScene
	_check(scene != null, "calibration scene dynamically loads after PoseService autoload")
	if scene == null:
		pose.stop_camera()
		_finish()
		return
	var screen := scene.instantiate() as Control
	_check(screen != null and screen.get_script() != null, "real authored calibration scene instantiated")
	if screen == null:
		pose.stop_camera()
		_finish()
		return
	root.add_child(screen)
	screen.set_process(false)
	# Set no context / camera_requested: deliberately do not start any webcam.
	# Keep this fixture aligned with the authored camera group used by
	# calibration.gd::_bind_scene_nodes; it never creates a surrogate preview.
	var inset := screen.get_node_or_null("TutorialStage/CameraArea/LiveCameraInset") as TextureRect
	_check(inset != null, "editor-authored preview available")
	if inset == null:
		screen.queue_free()
		await process_frame
		pose.stop_camera()
		_finish()
		return
	var image := Image.create(32, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.3, 0.5, 1.0))
	var texture := ImageTexture.create_from_image(image)
	pose.preview_texture = texture
	pose.set("_last_preview_ms", now)
	pose.preview_updated.emit(texture)
	_check(inset.texture == texture, "calibration receives real current preview texture")
	pose.call("_expire_preview", now + 500)
	_check(pose.preview_texture == texture and inset.texture == texture,
		"brief inference gap does not blink current camera image")
	pose.call("_expire_preview", now + 1700)
	_check(pose.preview_texture == null and inset.texture == null,
		"stalled preview expires from BOTH service and existing calibration UI")
	_check(not inset.visible, "stalled preview hides old skeleton, no frozen joints")
	pose.preview_texture = texture
	pose.set("_last_preview_ms", now + 1701)
	pose.preview_updated.emit(texture)
	_check(inset.texture == texture, "fresh incoming camera image resumes after timeout")
	# A teacher may request the camera while model/CUDA preparation is still
	# running. The ready-model camera timeout must not start during warmup.
	# Use an artificial monotonic epoch above all tested durations. A headless
	# Godot process itself has not necessarily existed for 61 real seconds.
	var synthetic_now := now + 100000
	pose.set("_worker_was_streaming", false)
	pose.set("_worker_was_tracking", false)
	pose.set("_last_packet_ms", synthetic_now)
	pose.set("_model_prestarting", true)
	pose.set("_camera_start_requested", true)
	pose.set("_launch_ms", synthetic_now - 31000)
	pose.set("_prewarm_started_ms", synthetic_now - 35000)
	pose.set("current_status", {"state": "prewarming", "model_ready": false})
	_check(pose.call("_camera_watchdog_status", synthetic_now) == "",
		"teacher can request camera before 35s model warmup is finished")
	pose.set("_prewarm_started_ms", synthetic_now - 61000)
	_check(pose.call("_camera_watchdog_status", synthetic_now) == "prewarm_stalled",
		"genuinely stuck requested warmup still has 60-second bound")
	pose.set("_prewarm_started_ms", synthetic_now - 40000)
	pose.set("current_status", {"state": "ready", "model_ready": true})
	pose.set("_camera_start_first_sent_ms", synthetic_now - 31000)
	_check(pose.call("_camera_watchdog_status", synthetic_now) == "camera_stalled",
		"ready model with unacknowledged camera start has 30-second bound")
	pose.set("_camera_start_first_sent_ms", synthetic_now - 1000)
	_check(pose.call("_camera_watchdog_status", synthetic_now) == "",
		"recent authenticated camera-start request is not timed out")
	pose.stop_camera()
	_check(pose.preview_texture == null and inset.texture == null,
		"explicit camera stop also clears the actual displayed preview")
	screen.queue_free()
	await process_frame
	pose.set_process(true)
	_finish()


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)


func _finish() -> void:
	for description in failures:
		printerr("FAIL preview freshness: ", description)
	print("%s preview freshness: %d checks, %d failures" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
