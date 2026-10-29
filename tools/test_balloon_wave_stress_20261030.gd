extends SceneTree

# Native Godot 4.7.2 camera-free, DB-free 3-lane Balloon stress test.
# Run: Godot --headless --path . --script res://tools/test_balloon_wave_stress_20261030.gd
# All gameplay ticks are simulated. Six independent continuous sessions each
# complete 126 *actual* top-escape -> delayed-next-wave transitions. The test
# replenishes ONLY mode-specific Seconds/Lives budgets between waves so 126
# sequential missed questions can be tested without a normal game-over.
const GAME_SCENE: PackedScene = preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]
const WAVES_PER_SESSION := 126
const EPSILON := 0.8

var assertions := 0
var failures: Array[String] = []
var wave_transitions := 0
var total_projectiles := 0
var scenario_reports: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for difficulty in DIFFICULTIES:
		for mode in MODES:
			await _stress_session(difficulty, mode)
	for failure in failures.slice(0, 24):
		push_error("BALLOON WAVE STRESS: " + failure)
	for report in scenario_reports:
		print("BALLOON WAVE SESSION: ", report)
	var expected_transitions := DIFFICULTIES.size() * MODES.size() * WAVES_PER_SESSION
	_check(wave_transitions >= 120 and wave_transitions == expected_transitions,
		"Total verified successive wave transitions: %d (expected %d)" %
		[wave_transitions, expected_transitions])
	print("BALLOON WAVE STRESS %s: %d/%d real sequential wave transitions, " %
		["PASS" if failures.is_empty() else "FAIL", wave_transitions, expected_transitions] +
		"%d lane spawns, %d paired projectiles, %d checks, %d failures, 6 scenarios" %
		[wave_transitions * 3, total_projectiles, assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _stress_session(difficulty: String, mode: String) -> void:
	var label := "%s/%s" % [difficulty, mode]
	var game := GAME_SCENE.instantiate() as Control
	_check(game != null and game.get_script() != null, label + ": live Balloon script loads")
	if game == null or game.get_script() == null:
		if game != null:
			game.free()
		return
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.set_context({
		"activity": "Balloon Popping", "topic": "Noun",
		"difficulty": difficulty, "game_mode": mode, "camera_live": false,
		"score": 0, "correct": 0, "attempts": 0
	})
	game.set_process(false)
	game.set_physics_process(false)
	game.rng.seed = 20261030
	var first_round: int = game.round_index
	var slot_ids: Array[int] = []
	for lane in range(3):
		slot_ids.append((game.balloon_slots[lane] as Area2D).get_instance_id())
	_check(game.round_active and game.timer_running and first_round >= 1,
		label + ": real initial question has started")
	_check(game.game_mode == mode and game._difficulty() == difficulty,
		label + ": selected mode and difficulty loaded correctly")
	_check(game.HAND_RAISE_RELOAD_MS == 1000 and game.projectiles.is_empty(),
		label + ": one-second auto-fire and empty projectile queue at start")
	_check(game.get_context().get("completion_reason", "") == "" and
			game.get_context().get("camera_live", true) == false and
			game.get_context().get("database_connected", true) == false,
		label + ": no camera, DB, or false completed score")

	var session_transitions := 0
	for wave in range(WAVES_PER_SESSION):
		var wave_label := "%s wave %d" % [label, wave + 1]
		# Only test-side top-up of mode resources allows >120 sequential MISSED
		# waves in the same production game; real scoring and transition code run.
		if mode == "Seconds":
			game.time_remaining = 60.0
		else:
			game.hearts = 3
		game.set_process(false)
		game.set_physics_process(false)
		var hidden: float = game._balloon_hidden_y()
		var exposed: float = game._balloon_y()
		var exit_y: float = game.BALLOON_EXIT_Y
		var upper: float = game.UPPER_LINE_Y
		var speed: float = game.balloon_float_speed
		var duration: float = (hidden - exit_y) / speed
		var former_round: int = game.round_index
		_check(game.round_active and not game.next_round_pending and game.timer_running and
				not game.finishing and not game.round_completed,
			wave_label + ": active stage with no pending or completed result")
		_check(former_round == first_round + wave and
				game.balloons.size() == 3 and game.balloon_slots.size() == 3,
			wave_label + ": round counter advances one and all 3 lanes are reused")
		_check(game.round_time_remaining == game.round_time_limit and
				duration < game.round_time_limit and speed > 0.0,
			wave_label + ": path-aware question resets and allows all lanes to exit top")
		_check(game.valid_lanes.size() >= 1 and game.valid_lanes.size() < 3 and
				game.pending_valid_lanes == game.valid_lanes and
				game.last_round_words.size() == 3,
			wave_label + ": real grammar question resets correct lanes and 3 distinct words")
		var words: Dictionary = {}
		for lane in range(3):
			var balloon := game.balloons[lane] as Area2D
			var text_label := balloon.get_node("WordLabel") as Label
			var word := text_label.text.strip_edges()
			_check(is_instance_valid(balloon) and balloon == game.balloon_slots[lane] and
					balloon.get_instance_id() == slot_ids[lane] and balloon.visible and
					absf(balloon.position.x - game._lane_x(lane)) <= EPSILON and
					absf(balloon.position.y - hidden) <= EPSILON,
				wave_label + ": lane %d is same authored balloon fully concealed below wood" % lane)
			_check(not balloon.monitoring and not balloon.monitorable and
					word != "" and not words.has(word),
				wave_label + ": concealed lane %d non-hittable with a unique grammar word" % lane)
			words[word] = true

		# Launch two REAL stones from a safe test-only x outside the 3 lanes.
		# Both must move; the second may not stick on-screen or leak into wave 2.
		game.launcher_x = 4.0
		game.launcher.position = Vector2(4.0, game._launcher_y())
		var shot_clock := 10000 + wave * 5000
		game.set_hand_raise_state(false, true, shot_clock)
		game.set_hand_raise_state(false, true, shot_clock + 180)
		game.set_hand_raise_state(true, true, shot_clock + 200)
		var first_fired: bool = game.set_hand_raise_state(true, true, shot_clock + 280)
		var second_fired: bool = game.set_hand_raise_state(true, true, shot_clock + 1280)
		var cap_blocks: bool = not game.set_hand_raise_state(true, true, shot_clock + 2280)
		_check(first_fired and second_fired and cap_blocks and game.projectiles.size() == 2 and
				game.projectile_velocities.size() == 2,
			wave_label + ": 1000ms held high fires two live stones; cap blocks a third")
		if game.projectiles.size() == 2:
			total_projectiles += 2
			var first_stone := game.projectiles[0] as Area2D
			var second_stone := game.projectiles[1] as Area2D
			var first_y := first_stone.position.y
			var second_y := second_stone.position.y
			game._update_projectiles(0.035)
			_check(game.projectiles.size() == 2 and
					absf((first_y - first_stone.position.y) - game.projectile_speed * 0.035) < EPSILON and
					absf((second_y - second_stone.position.y) - game.projectile_speed * 0.035) < EPSILON,
				wave_label + ": BOTH live stones rise independently at the correct speed")
		_check(game.attempts == 0 and game.score == 0 and game.correct_count == 0,
			wave_label + ": concealed stones never generate false attempts or points")

		# Use deliberately unequal simulation steps. Exact linear positions
		# catch a tween, midpoint teleport, easing, or unexplained stall.
		var seconds := 0.0
		for delta in [0.11, 0.27, 0.05, 0.33, 0.14]:
			seconds += delta
			game._process(delta)
			game.set_process(false)
			for lane in range(3):
				var balloon := game.balloons[lane] as Area2D
				_check(balloon.visible and
						absf(balloon.position.y - (hidden - speed * seconds)) < EPSILON and
						absf(balloon.position.x - game._lane_x(lane)) < EPSILON,
					wave_label + ": lane %d constant-speed ascent across irregular frames" % lane)
		_check(absf(game.round_time_remaining -
					(game.round_time_limit - seconds)) < 0.01,
			wave_label + ": question clock ticks during ascent; no mid-flight pause")

		# Cross the bottom visibility threshold without moving any lane sideways.
		var enter_delta: float = (hidden - (exposed - 18.0)) / speed - seconds
		_check(enter_delta > 0.0, wave_label + ": conceal-to-visible interval is positive")
		seconds += enter_delta
		game._process(enter_delta)
		game.set_process(false)
		for lane in range(3):
			var balloon := game.balloons[lane] as Area2D
			_check(balloon.visible and balloon.monitoring and balloon.monitorable and
					absf(balloon.position.y - (exposed - 18.0)) < EPSILON,
				wave_label + ": lane %d emerges continuously with collision enabled" % lane)

		# Pass just beyond the upper hit line. An otherwise-perfect projectile
		# trajectory must NEVER score against one of these escaping balloons.
		var cross_delta: float = (hidden - (upper - 18.0)) / speed - seconds
		_check(cross_delta > 0.0, wave_label + ": remaining approach to top is positive")
		seconds += cross_delta
		game._process(cross_delta)
		game.set_process(false)
		for lane in range(3):
			var balloon := game.balloons[lane] as Area2D
			var shot_x: float = balloon.position.x
			_check(balloon.visible and not balloon.monitoring and not balloon.monitorable and
					absf(balloon.position.y - (upper - 18.0)) < EPSILON,
				wave_label + ": lane %d above upper line remains visible but non-hittable" % lane)
			_check(game._find_swept_balloon_lane(
					Vector2(shot_x, upper + 70.0), Vector2(shot_x, upper - 70.0)) == -1,
				wave_label + ": lane %d upper-line escape rejects swept projectile hit" % lane)

		# Exit all three balloon sprites beyond the actual top kill threshold,
		# then let the production delayed-wave callback spawn the next question.
		var exit_delta: float = (hidden - exit_y) / speed - seconds + 0.04
		_check(exit_delta > 0.0, wave_label + ": final top-escape interval positive")
		seconds += exit_delta
		var hearts_before: int = game.hearts
		var global_before: float = game.time_remaining
		game._process(exit_delta)
		game.set_process(false)
		_check(not game.round_active and game.next_round_pending and not game.finishing,
			wave_label + ": all 3 real top escapes schedule exactly one next stage")
		_check(game.hearts == hearts_before - (1 if mode == "Lives" else 0) and
				(mode != "Seconds" or game.time_remaining < global_before),
			wave_label + ": mode clock/heart penalty applied correctly to missed wave")
		_check(game.score == 0 and game.correct_count == 0 and game.attempts == 0 and
				game.get_context().get("completion_reason", "") == "",
			wave_label + ": escaped balloons cannot save/award an incomplete round")
		for lane in range(3):
			var retired := game.balloon_slots[lane] as Area2D
			# The real top exit has moved beyond the screen, then hidden the
			# target. The NEXT spawn is responsible for resetting its y to wood.
			_check(not retired.visible and not retired.monitoring and not retired.monitorable,
				wave_label + ": escaped lane %d is non-hittable before next spawn" % lane)
		# Delayed callback is invoked with simulated time: no wall-clock 0.55s.
		game._on_next_round_delay_elapsed()
		game.set_process(false)
		game.set_physics_process(false)
		_check(game.round_active and game.round_index == former_round + 1 and
				not game.next_round_pending and game.balloons.size() == 3,
			wave_label + ": actual delayed callback starts ONE next valid question")
		for lane in range(3):
			var reset_balloon := game.balloons[lane] as Area2D
			_check(reset_balloon == game.balloon_slots[lane] and reset_balloon.visible and
					absf(reset_balloon.position.y - hidden) < EPSILON and
					not reset_balloon.monitoring and not reset_balloon.monitorable,
				wave_label + ": new stage lane %d respawns concealed/non-colliding" % lane)
		_check(game.projectiles.is_empty() and game.projectile_velocities.is_empty() and
				game.hand_raise_last_shot_ms == shot_clock + 1280,
			wave_label + ": both stones cleared for next wave; no stuck second projectile")
		_check(game.round_time_remaining == game.round_time_limit and
				game.pending_valid_lanes == game.valid_lanes and
				game.get_context().get("completion_reason", "") == "",
			wave_label + ": next-wave clock, grammar targets and result state reset")
		wave_transitions += 1
		session_transitions += 1
		if wave % 18 == 17:
			# One real event-loop frame frees retired stones and incidental FX.
			# Any old 0.55s timers are harmless because pending was consumed.
			await process_frame
			game.set_process(false)
			game.set_physics_process(false)

	_check(session_transitions == WAVES_PER_SESSION and
			game.round_index == first_round + WAVES_PER_SESSION,
		label + ": all 126 waves transition in one uninterrupted game instance")
	# Independently check actual final-result conditions after the stress run.
	if mode == "Seconds":
		game.time_remaining = 0.01
		game._process(0.02)
		game.set_process(false)
		_check(game.finishing and game.round_completed and
				game.get_context().get("completion_reason") == "time_up",
			label + ": only real Seconds expiry finally marks completion")
	else:
		game.hearts = 1
		var final_exit: float = (game._balloon_hidden_y() - game.BALLOON_EXIT_Y) / game.balloon_float_speed + 0.04
		game._process(final_exit)
		game.set_process(false)
		_check(game.finishing and game.round_completed and not game.next_round_pending and
				game.get_context().get("completion_reason") == "lives_empty",
			label + ": only final lost Lives heart marks completion; no ghost wave")
	_check(game.projectiles.is_empty() and game.projectile_velocities.is_empty(),
		label + ": terminal result owns no stuck or orphan active stones")
	scenario_reports.append("%s %d transitions, %d total rounds, %d hearts, completed=%s" %
		[label, session_transitions, game.round_index, game.hearts,
		game.get_context().get("completion_reason", "")])
	game.queue_free()
	await process_frame
	await process_frame


func _check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok:
		failures.append(detail)
