extends SceneTree

## Deterministic calibration test: no webcam, network or YOLO model involved.
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := root.get_node_or_null("PoseService")
	_check(service != null, "PoseService is configured")
	if service == null:
		quit(1)
		return
	_check(not service.has_valid_pose(), "Idle camera cannot produce valid pose")
	_check(not service.set_calibration(0.45, 0.50, 0.53), "Reject tiny movement ranges")
	_check(not service.set_calibration(0.20, 0.24, 0.80), "Reject center too close to left")
	_check(service.set_calibration(0.20, 0.50, 0.80), "Accept ordered movement zones")
	service.calibration.clear()

	var check_scene := load("res://ui/vision/camera_check.tscn") as PackedScene
	_check(check_scene != null, "Camera Check scene loads")
	if check_scene != null:
		var check := check_scene.instantiate() as Control
		root.add_child(check)
		var camera_button := check.get_node_or_null("TutorialStage/CheckStatusButton") as Button
		_check(camera_button != null and camera_button.text == "START CAMERA", "Camera Check retains manual stop/start fallback")
		check.free()

	# Supply a synthetic already-open camera so the Calibration screen's
	# automatic start never opens physical webcam 0 during regression tests.
	service.active = true
	service.player_x = 0.5
	service.current_status = {"state": "tracking", "pose": true}
	service.last_pose_ms = Time.get_ticks_msec()
	var calib_scene := load("res://ui/vision/calibration.tscn") as PackedScene
	_check(calib_scene != null, "Auto Calibration scene loads")
	if calib_scene != null:
		var calib := calib_scene.instantiate() as Control
		root.add_child(calib)
		_check(calib.get_node_or_null("TutorialStage/ContinueButton") == null,
			"Calibration auto-advances without an obsolete Continue button")
		var center_guide := calib.get_node_or_null("TutorialStage/CenterCalibrationLane") as Control
		_check(is_instance_valid(center_guide), "Editor-authored center standing guide exists")
		# New full-screen tutorial displays an introductory card before capture.
		# Advance time without opening the physical webcam or waiting in real time.
		calib.call("_process", 2.6)
		_check(not bool(calib.get("intro_running")), "2.5s intro completes before first hold")
		for position in [0.50, 0.78, 0.25]:
			for sample in range(10):
				service.player_x = position + 0.002 * float(sample % 2)
				service.packet_sequence += 1
				service.last_pose_ms = Time.get_ticks_msec()
				calib.call("_process", 0.4)
		_check(bool(service.calibration.get("valid", false)), "3s Center-Right-Left creates calibration")
		_check(calib.get_node_or_null("TutorialStage/ContinueButton") == null
			and bool(calib.get("transition_queued")),
			"Valid three-zone measurement schedules automatic gameplay transition")
		calib.free()

	service.stop_camera()
	print("POSE CALIBRATION: ", "PASS" if failures == 0 else "FAIL", " checks complete")
	quit(0 if failures == 0 else 1)


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL auto calibration: ", message)
