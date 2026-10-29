extends SceneTree

	# Synthetic, camera-free verification that the locked student's arm-spread
	# gate and measured LEFT/CENTER/RIGHT movement reach actual Human Plane.
	# Tilt/gyro values are irrelevant. No webcam, database or student writes.
const GAMEPLAY_PATH := "res://ui/play/gameplay/gameplay.tscn"
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var service := root.get_node_or_null("PoseService")
	_check(service != null, "local PoseService autoload exists")
	if service == null:
		quit(1)
		return
	service.stop_camera()
	# Never start or poll a real Python camera worker in this isolated test.
	service.set_process(false)
	service.active = true
	service.session_token = "gesture-qa-only"
	_check(service.set_calibration(0.18, 0.5, 0.82), "existing measured calibration remains valid")
	var now := Time.get_ticks_msec()
	_emit_pose(service, 0.5, false, false, now)
	_check(service.has_fresh_gesture_pose(), "live calibrated pose accepts new packet")
	_check(not service.has_hand_raised() and not service.has_airplane_pose(), "neutral arms do not invent gestures")

	# Runtime load follows the existing guided-onboarding harness convention:
	# Godot autoload singletons are registered before gameplay.gd is compiled.
	var wrapper := (load(GAMEPLAY_PATH) as PackedScene).instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({"activity": "Human Plane", "game_mode": "Seconds", "topic": "Noun",
		"difficulty": "Easy", "camera_live": true, "guided_tutorial": false})
	await process_frame
	await process_frame
	var game := wrapper.get("active_game") as Control
	_check(game != null and game.has_method("set_airplane_pose_active"), "actual Human Plane exposes pose gating")
	if game != null and game.has_method("set_airplane_pose_active"):
		wrapper.set_process(false)
		game.set_process(false)
		wrapper.call("_process", 0.016)
		_check(not bool(game.get("airplane_pose_active")), "neutral pose prevents plane steering")
		var anchored := float(game.get("plane_x_norm"))
		game.call("set_body_x", 0.9)
		game.call("_update_plane_motion", 0.3)
		_check(absf(float(game.get("plane_x_norm")) - anchored) < 0.001, "airplane stays still when both arms lowered")

		for i in range(5):
			# Wide arms are an ENABLE, not a direction. A measured LEFT body
			# position must go LEFT even if the old gyro value says RIGHT.
			_emit_pose(service, 0.18, false, true, Time.get_ticks_msec(), 0.8)
			service.set("player_x", 0.18)
			service.set("_smoothed_x", 0.18)
			wrapper.call("_process", 0.10)
			_check(bool(game.get("airplane_pose_active")), "airplane transition %d activates" % i)
			var before := float(game.get("plane_x_norm"))
			game.call("_update_plane_motion", 0.20)
			_check(float(game.get("plane_x_norm")) < before, "airplane transition %d moves LEFT by body position, not gyro" % i)
			# Arms lowered must instantly freeze horizontal movement.
			_emit_pose(service, 0.82, false, false, Time.get_ticks_msec())
			service.set("player_x", 0.82)
			service.set("_smoothed_x", 0.82)
			wrapper.call("_process", 0.10)
			var stopped := float(game.get("plane_x_norm"))
			game.call("set_body_x", 0.9)
			game.call("_update_plane_motion", 0.3)
			_check(not bool(game.get("airplane_pose_active")) and absf(float(game.get("plane_x_norm")) - stopped) < 0.001,
				"airplane transition %d freezes on lowered arms" % i)
			# Raise arms again at RIGHT; the new x target is accepted WITHOUT a
			# new calibration, even after all previous lowered frames were ignored.
			_emit_pose(service, 0.82, false, true, Time.get_ticks_msec(), -0.9)
			service.set("player_x", 0.82)
			service.set("_smoothed_x", 0.82)
			var before_right := float(game.get("plane_x_norm"))
			for frame in range(5):
				wrapper.call("_process", 0.07)
				game.call("_update_plane_motion", 0.07)
			_check(float(game.get("plane_x_norm")) > before_right,
				"airplane transition %d moves RIGHT after reopening wings" % i)

		# Temporary occlusion must never leave either action active.
		_emit_pose(service, 0.48, true, true, Time.get_ticks_msec())
		wrapper.call("_process", 0.016)
		_check(service.has_hand_raised() and service.has_airplane_pose(), "both independent flags arrive")
		var missing := {"kind": "pose", "token": "gesture-qa-only", "state": "tracking",
			"pose": false, "x": -1.0, "hand_up": true, "airplane_pose": true}
		service._apply_pose_packet(missing, Time.get_ticks_msec())
		_check(not service.has_hand_raised() and not service.has_airplane_pose(), "invalid pose cannot preserve true gesture fields")
		wrapper.call("_clear_gesture_input")
		_check(not bool(game.get("airplane_pose_active")), "tracking interruption disables plane control")
		_emit_pose(service, 0.5, false, true, Time.get_ticks_msec())
		wrapper.call("_process", 0.016)
		_check(bool(game.get("airplane_pose_active")), "reacquisition restores airplane pose without calibration restart")

	# The actual Balloon scene has its own independent 1.5s edge/cooldown QA;
	# assert that the wrapper never falls back to legacy direct `_launch_projectile`.
	_check(not String(wrapper.get_script().source_code).contains("last_fire_ms"),
		"old 800ms repeated/direct balloon firing path is absent")
	wrapper.queue_free()
	await process_frame
	await process_frame
	service.stop_camera()
	print("GESTURE/POSE BRIDGE: ", "PASS" if failures.is_empty() else "FAIL",
		" (%d checks, %d failures)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _emit_pose(service: Node, x: float, hand_up: bool, plane: bool, now: int, roll: float = 0.0) -> void:
	service._apply_pose_packet({"kind": "pose", "token": "gesture-qa-only",
		"state": "tracking", "pose": true, "x": x, "hand_up": hand_up,
		"airplane_pose": plane, "wing_roll": roll}, now)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("GESTURE/POSE BRIDGE FAIL: ", message)
