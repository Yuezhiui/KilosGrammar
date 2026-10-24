extends SceneTree

# Backward-compatible script name. The old angle/gyro movement was retired:
# this verifies measured three-zone POSITION steering and wide-arms gating.
const GAMEPLAY_PATH := "res://ui/play/gameplay.tscn"
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var pose := root.get_node("PoseService")
	pose.stop_camera()
	pose.set_process(false)
	pose.active = true
	pose.session_token = "wing-angle-qa"
	_check(pose.set_calibration(0.18, 0.5, 0.82), "three REAL CENTER/RIGHT/LEFT holds calibrate Human Plane")
	_check(not bool(pose.calibration.get("center_only", false)), "no synthetic center-only side limits")
	# Load AFTER Godot registers the PoseService autoload; early preload can
	# parse a gameplay script before its global singleton identifier exists.
	var wrapper := (load(GAMEPLAY_PATH) as PackedScene).instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({"activity": "Human Plane", "camera_live": true, "difficulty": "Easy", "game_mode": "Seconds"})
	await process_frame
	await process_frame
	var plane := wrapper.get("active_game") as Control
	_check(plane != null and plane.has_method("set_body_x"), "Human Plane accepts calibrated body movement")
	if plane == null or not plane.has_method("set_body_x"):
		pose.stop_camera()
		wrapper.queue_free()
		quit(1)
		return
	wrapper.set_process(false)
	plane.set_process(false)
	for direction in [-1.0, 1.0]:
		plane.set("plane_x_norm", 0.5)
		plane.set("target_x_norm", 0.5)
		wrapper.set("smooth_x", 0.0)
		var physical_x := 0.18 if direction < 0.0 else 0.82
		# Roll deliberately disagrees with BODY x: no gyro may override it.
		_send(pose, physical_x, true, -direction)
		pose.set("player_x", physical_x)
		pose.set("_smoothed_x", physical_x)
		for i in range(30):
			wrapper.call("_process", 1.0 / 60.0)
			plane.call("_update_plane_motion", 1.0 / 60.0)
		var moved := float(plane.get("plane_x_norm"))
		_check(moved < 0.45 if direction < 0.0 else moved > 0.55,
			"three-zone body movement drives the correct side regardless of opposite wing roll")
		_check(bool(plane.get("airplane_pose_active")), "both arms spread activate measured side-stepping")
		_send(pose, 0.5, false, direction)
		var frozen := float(plane.get("plane_x_norm"))
		for i in range(30):
			wrapper.call("_process", 1.0 / 60.0)
			plane.call("_update_plane_motion", 1.0 / 60.0)
		_check(absf(frozen - float(plane.get("plane_x_norm"))) < 0.00001, "lowered arms freeze plane exactly")
	# Invalid packets may not carry old motion into the next scene.
	_send(pose, 0.5, true, 1.0)
	pose._apply_pose_packet({"kind": "pose", "token": "wing-angle-qa", "state": "lost", "pose": false,
		"x": -1.0, "airplane_pose": true, "wing_roll": 1.0}, Time.get_ticks_msec())
	wrapper.call("_clear_gesture_input")
	_check(not pose.has_airplane_pose(), "invalid/stale tracking never enables wide-arms gate")
	_check(not bool(plane.get("airplane_pose_active")), "tracking loss disables physical steering")
	pose.stop_camera()
	wrapper.queue_free()
	await process_frame
	print("AIRPLANE BODY/POSE BRIDGE: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _send(pose: Node, body_x: float, armed: bool, roll: float) -> void:
	pose._apply_pose_packet({"kind": "pose", "token": "wing-angle-qa", "state": "tracking",
		"pose": true, "x": body_x, "airplane_pose": armed, "wing_roll": roll}, Time.get_ticks_msec())


func _check(valid: bool, label: String) -> void:
	checks += 1
	if not valid:
		failures.append(label)
		printerr("BODY/POSE BRIDGE FAIL: ", label)
