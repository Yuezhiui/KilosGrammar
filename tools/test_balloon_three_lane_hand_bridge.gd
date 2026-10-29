extends SceneTree

# Full camera-free Balloon Popping input bridge: calibrated LEFT/CENTER/RIGHT
# steering stays independent of either-hand shooting; no real camera or DB.
const GAMEPLAY_SCENE := "res://ui/play/gameplay/gameplay.tscn"
const SESSION_TOKEN := "balloon-three-lane-synthetic"
var checks := 0
var failures: Array[String] = []
var mock_worker: PacketPeerUDP
var next_source_when := 20.0


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
	# The strict source gate requires an authenticated live camera session, a
	# current local worker process and a bound receiver. Use localhost UDP only;
	# neither a physical webcam nor the Python pose worker is launched.
	service.peer = PacketPeerUDP.new()
	_check(service.peer.bind(0, "127.0.0.1") == OK, "synthetic PoseService UDP receiver is bound")
	mock_worker = PacketPeerUDP.new()
	_check(mock_worker.set_dest_address("127.0.0.1", service.peer.get_local_port()) == OK,
		"synthetic worker sends authenticated packets on localhost")
	service.worker_pid = OS.get_process_id() # Test-only liveness; unset BEFORE stop_camera().
	service.active = true
	service.session_token = SESSION_TOKEN
	service._launch_ms = Time.get_ticks_msec()
	service._latest_worker_packet_time = -1.0
	_check(service.set_calibration(0.18, 0.50, 0.82), "three-stage calibration supports left/center/right")
	await _emit_pose(service, 0.50, false, true)
	_check(service.fresh_camera_population() == 1 and service.has_valid_pose() \
		and service.has_valid_hand_observation(),
		"fresh authenticated solo tracking exposes valid movement and hand observation")

	var wrapper := (load(GAMEPLAY_SCENE) as PackedScene).instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({"activity": "Balloon Popping", "game_mode": "Seconds",
		"topic": "Noun", "difficulty": "Easy", "camera_live": true,
		"guided_tutorial": false, "start_countdown": false,
		"calibration_measured": true})
	await process_frame
	await process_frame
	# Current production always puts a live camera round through a mandatory
	# 3-2-1 count-in. In this synthetic fixture the already-authenticated solo
	# frame + real 3-point calibration allow us to finish that count-in safely.
	_check(wrapper.guided_stage == "countdown",
		"camera game starts disabled until its required 3-2-1 completes")
	await _emit_pose(service, 0.50, false, true)
	_check(wrapper._has_live_calibrated_player(),
		"fresh authenticated solo player and measured calibration authorize GO")
	wrapper._complete_countdown_start()
	_check(wrapper.guided_stage.is_empty() and wrapper.active_game.process_mode != Node.PROCESS_MODE_DISABLED,
		"measured calibration and trusted sole person release gameplay after countdown cleanup")
	wrapper.set_process(false)
	var game := wrapper.get("active_game") as Control
	_check(game != null, "Balloon scene mounted in real gameplay wrapper")
	if game == null:
		service.worker_pid = -1
		mock_worker.close()
		service.stop_camera()
		quit(1)
		return
	game.set_process(false)
	game.set_physics_process(false)
	_check(game.round_active and game.timer_running, "game round is live")
	_check(game.HAND_RAISE_RELOAD_MS == 1000, "held-high reload is exactly one second")

	# An *invalid* hand observation with a tracked torso must neither re-arm
	# nor shoot. Reacquiring the SAME raised pose is still disarmed.
	await _emit_pose(service, 0.50, false, false)
	for _i in range(5):
		wrapper.call("_update_gesture_input")
	_check(not service.has_valid_hand_observation(), "tracked torso with occluded wrists is invalid for shooting")
	_check(not game.hand_raise_armed, "occluded wrists cannot re-arm gun")
	await _emit_pose(service, 0.50, true, true, true, false)
	_wrapper_raise(wrapper, game)
	_check(game.projectiles.is_empty(), "raised arm after occlusion cannot fire without genuine low")

	var lane_xs := [0.18, 0.50, 0.82]
	var lane_names := ["LEFT", "CENTER", "RIGHT"]
	var observed_xs: Array[float] = []
	for lane in range(3):
		# Restore a trustworthy lower-hand observation before aiming. The
		# movement pipeline processes camera position separately from the gun.
		await _emit_pose(service, lane_xs[lane], false, true)
		for _frame in range(55):
			# Real YOLO delivers a succession of position samples, not one
			# isolated new x followed by 55 repeated rendered frames.
			await _emit_pose(service, lane_xs[lane], false, true)
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
		# Clock manipulation stays confined to this synthetic test: exact
		# millisecond deadlines are tested by the deterministic gesture suites.
		if lane > 0:
			game.hand_raise_last_shot_ms = Time.get_ticks_msec() - 1100
		var left_hand := lane != 1
		await _emit_pose(service, lane_xs[lane], true, true, left_hand, not left_hand)
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
		_check(game.projectiles.size() == 1, "%s high wrist respects one-second cooldown" % lane_names[lane])
		game.call("_clear_projectiles")
		if lane < 2:
			# Advancing just the synthetic shot clock lets the same continuously
			# observed high wrist fire again, with no lower-to-rearm.
			game.hand_raise_last_shot_ms = Time.get_ticks_msec() - 1100
			wrapper.call("_update_gesture_input")
			_check(game.projectiles.size() == 1,
				"%s held-high wrist repeats after 1000ms without lowering" % lane_names[lane])
			game.call("_clear_projectiles")

	_check(observed_xs.size() == 3, "all three lane projectiles recorded")
	if observed_xs.size() == 3:
		_check(observed_xs[0] < observed_xs[1] and observed_xs[1] < observed_xs[2],
			"LEFT / CENTER / RIGHT projectile origins are monotonically ordered")

	# Same person still raising a hand after wrist loss must not shoot again,
	# even after the reload duration completes.
	await _emit_pose(service, 0.82, true, false)
	wrapper.call("_update_gesture_input")
	_check(not game.hand_raise_armed, "loss of hand confidence disarms firing")
	await _emit_pose(service, 0.82, true, true)
	_wrapper_raise(wrapper, game)
	_check(game.projectiles.is_empty(), "recovered raised arm never creates a phantom shot")

	# Gameplay._exit_tree() also calls stop_camera(); revoke the test-only
	# process-ID stub BEFORE freeing that wrapper, or it would kill this runner.
	service.worker_pid = -1
	wrapper.queue_free()
	await process_frame
	await process_frame
	mock_worker.close()
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
	next_source_when += 0.05
	var packet := {
		"kind": "pose", "token": SESSION_TOKEN,
		"state": "tracking", "camera": true, "camera_phase": "tracking",
		"camera_frame_age_ms": 20, "people": 1, "lock_state": "locked",
		"pose": true, "x": x, "when": next_source_when,
		"hand_up": hand_up, "left_hand_up": left, "right_hand_up": right,
		"hand_observation_valid": observation_valid,
		"airplane_pose": false, "wing_roll": 0.0
	}
	_check(mock_worker.put_packet(JSON.stringify(packet).to_utf8_buffer()) == OK,
		"authenticated source timestamp delivered to the local PoseService receiver")
	await process_frame
	service._process(0.016)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("BALLOON THREE-LANE FAIL: ", message)
