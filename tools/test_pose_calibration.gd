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
		_check((calib.get("continue_button") as Button).disabled, "Calibration starts locked")
		var marker := calib.get("guide_cursor") as ColorRect
		_check(is_instance_valid(marker), "Moving player marker exists")
		for position in [0.50, 0.78, 0.25]:
			for sample in range(12):
				service.player_x = position + 0.002 * float(sample % 2)
				service.packet_sequence += 1
				service.last_pose_ms = Time.get_ticks_msec()
				calib.call("_process", 0.5)
		_check(bool(service.calibration.get("valid", false)), "5s Center-Right-Left creates calibration")
		var next_button := calib.get("continue_button") as Button
		_check(is_instance_valid(next_button) and not next_button.disabled, "Continue unlocked after all zones")
		calib.free()

	service.stop_camera()
	print("POSE CALIBRATION: ", "PASS" if failures == 0 else "FAIL", " checks complete")
	quit(0 if failures == 0 else 1)


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL auto calibration: ", message)
