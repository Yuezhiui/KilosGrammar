extends SceneTree

# Full camera-free Balloon Popping input bridge: calibrated LEFT/CENTER/RIGHT
# steering stays independent of either-hand shooting; no real camera or DB.
const GAMEPLAY_SCENE := "res://ui/play/gameplay.tscn"
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var service := root.get_node_or_null("PoseService")
	_check(service != null, "PoseService autoload exists")
	if service == null:
		quit(1)
		return
	service.stop_camera()
	service.set_process(false)
	service.active = true
	service.session_token = "balloon-three-lane-synthetic"
	_check(service.set_calibration(0.18, 0.50, 0.82), "three-stage calibration supports left/center/right")
	_emit_pose(service, 0.50, false, true)

	var wrapper := (load(GAMEPLAY_SCENE) as PackedScene).instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({"activity": "Balloon Popping", "game_mode": "Seconds",
		"topic": "Noun", "difficulty": "Easy", "camera_live": true,
		"guided_tutorial": false, "start_countdown": false})
	await process_frame
	await process_frame
	wrapper.set_process(false)
	var game := wrapper.get("active_game") as Control
	_check(game != null, "Balloon scene mounted in real gameplay wrapper")
	if game == null:
		service.stop_camera()
		quit(1)
		return
	game.set_process(false)
	game.set_physics_process(false)
	_check(game.round_active and game.timer_running, "game round is live")
	_check(game.HAND_RAISE_RELOAD_MS == 1500, "existing reload remains 1.5 seconds")

	# An *invalid* hand observation with a tracked torso must neither re-arm
	# nor shoot. Reacquiring the SAME raised pose is still disarmed.
	_emit_pose(service, 0.50, false, false)
	for _i in range(5):
		wrapper.call("_update_gesture_input")
	_check(not service.has_valid_hand_observation(), "tracked torso with occluded wrists is invalid for shooting")
	_check(not game.hand_raise_armed, "occluded wrists cannot re-arm gun")
	_emit_pose(service, 0.50, true, true, true, false)
	_wrapper_raise(wrapper, game)
	_check(game.projectiles.is_empty(), "raised arm after occlusion cannot fire without genuine low")

	var lane_xs := [0.18, 0.50, 0.82]
	var lane_names := ["LEFT", "CENTER", "RIGHT"]
	var observed_xs: Array[float] = []
	for lane in range(3):
		# Restore a trustworthy lower-hand observation before aiming. The
		# movement pipeline processes camera position separately from the gun.
		_emit_pose(service, lane_xs[lane], false, true)
		for _frame in range(55):
			# Real YOLO delivers a succession of position samples, not one
			# isolated new x followed by 55 repeated rendered frames.
			_emit_pose(service, lane_xs[lane], false, true)
			wrapper.call("_process", 0.04)
			game.call("_update_launcher", 0.04)
		game.hand_raise_sample_since_ms = Time.get_ticks_msec() - 200
		wrapper.call("_update_gesture_input")
		_check(game.hand_raise_armed, "%s lower-hand confirmation re-arms" % lane_names[lane])
		var expected_x: float = (game.balloon_slots[lane] as Area2D).position.x
		_check(absf(game.launcher_x - expected_x) < 12.0,
			"%s calibrated launcher x=%.1f expected=%.1f (pose=%.3f)" %
			[lane_names[lane], game.launcher_x, expected_x, service.player_x])

		# The camera's aggregate 'hand_up' can come from EITHER wrist. The
		# per-wrist fields are metadata: they cannot steer the gun by themselves.
		var left_hand := lane != 1
		_emit_pose(service, lane_xs[lane], true, true, left_hand, not left_hand)
		_wrapper_raise(wrapper, game)
		_check(game.projectiles.size() == 1,
			"%s arm raise fires one stone (shots=%d, armed=%s, confirmed=%s, last=%d, now=%d, active=%s)" %
			[lane_names[lane], game.projectiles.size(), game.hand_raise_armed,
			game.hand_raise_confirmed_raised, game.hand_raise_last_shot_ms, Time.get_ticks_msec(), game.round_active])
		if game.projectiles.size() == 1:
			var projectile := game.projectiles[0] as Area2D
			observed_xs.append(projectile.position.x)
			_check(absf(projectile.position.x - game.launcher_x) <= 0.01,
				"%s projectile launches at the visible gun" % lane_names[lane])
			_check(absf(projectile.position.x - expected_x) < 12.0,
				"%s projectile x=%.1f expected=%.1f" %
				[lane_names[lane], projectile.position.x, expected_x])
		for _held in range(20):
			wrapper.call("_update_gesture_input")
		_check(game.projectiles.size() == 1, "%s sustained high pose never auto-fires" % lane_names[lane])
		game.call("_clear_projectiles")
		if lane < 2:
			# Headless Godot timer callbacks may advance virtual frames faster
			# than the Time.get_ticks_msec() monotonic cooldown clock. Simulate
			# time elapsed by shifting ONLY the test instance's last-shot mark.
			# Exact 1499/1500ms behavior is covered by the dedicated state test.
			game.hand_raise_last_shot_ms = Time.get_ticks_msec() - 1600
			wrapper.call("_update_gesture_input")
			_check(game.projectiles.is_empty(),
				"%s holding an arm up cannot re-fire when cooldown expires" % lane_names[lane])

	_check(observed_xs.size() == 3, "all three lane projectiles recorded")
	if observed_xs.size() == 3:
		_check(observed_xs[0] < observed_xs[1] and observed_xs[1] < observed_xs[2],
			"LEFT / CENTER / RIGHT projectile origins are monotonically ordered")

	# Same person still raising a hand after wrist loss must not shoot again,
	# even after the reload duration completes.
	_emit_pose(service, 0.82, true, false)
	wrapper.call("_update_gesture_input")
	_check(not game.hand_raise_armed, "loss of hand confidence disarms firing")
	_emit_pose(service, 0.82, true, true)
	_wrapper_raise(wrapper, game)
	_check(game.projectiles.is_empty(), "recovered raised arm never creates a phantom shot")

	wrapper.queue_free()
	await process_frame
	await process_frame
	service.stop_camera()
	if failures.is_empty():
		print("PASS Balloon three-lane hand bridge: %d assertions" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("BALLOON THREE-LANE: " + failure)
		print("FAIL Balloon three-lane hand bridge: %d failures in %d assertions" % [failures.size(), checks])
		quit(1)


func _wrapper_raise(wrapper: Control, game: Control) -> void:
	wrapper.call("_update_gesture_input")
	game.hand_raise_sample_since_ms = Time.get_ticks_msec() - 120
	wrapper.call("_update_gesture_input")


func _emit_pose(service: Node, x: float, hand_up: bool, observation_valid: bool,
		left: bool = false, right: bool = false) -> void:
	service._apply_pose_packet({
		"kind": "pose", "token": "balloon-three-lane-synthetic",
		"state": "tracking", "pose": true, "x": x,
		"hand_up": hand_up, "left_hand_up": left, "right_hand_up": right,
		"hand_observation_valid": observation_valid,
		"airplane_pose": false, "wing_roll": 0.0
	}, Time.get_ticks_msec())


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("BALLOON THREE-LANE FAIL: ", message)
