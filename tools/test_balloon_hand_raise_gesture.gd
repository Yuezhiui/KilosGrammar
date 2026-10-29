extends SceneTree

# Deterministic hand-raise firing regression. Run:
# Godot --headless --path . --script res://tools/test_balloon_hand_raise_gesture.gd

const GAME_SCENE := preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := GAME_SCENE.instantiate() as Control
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.set_context({"activity": "Balloon Popping", "topic": "Noun",
		"game_mode": "Seconds", "difficulty": "Normal", "time_remaining": 60.0})
	game.set_process(false)
	game.set_physics_process(false)
	_check(game.round_active and game.timer_running, "Game is active")
	_check(game.HAND_RAISE_RELOAD_MS == 500, "Reload is precisely 500ms")
	_check(game.projectiles.is_empty(), "No projectile fires automatically on setup")
	_check(not game._launch_projectile(0), "Direct firing outside the gesture API is blocked")

	# A hand that was already held up during tutorial or calibration must not
	# automatically shoot as soon as live gameplay becomes active.
	_sample(game, true, 0, false, "Initial high pose cannot shoot")
	_sample(game, true, 80, false, "Initial confirmed high pose stays disarmed")
	_sample(game, true, 100, false, "Holding initial high pose never repeats")
	_check(game.projectiles.is_empty(), "Holding a raised hand spawns no shots")

	_lower(game, 180, "First legitimate lowering")
	_sample(game, true, 420, false, "Rising edge waits for confirmation")
	_sample(game, true, 500, true, "Either raised hand fires one shot")
	_check(game.projectiles.size() == 1 and game.hand_raise_last_shot_ms == 500,
		"Exactly one projectile spawned and time recorded")
	_sample(game, true, 600, false, "Holding raised blocks a duplicate shot")

	# Brief incorrect lowered readings from YOLO must not rearm an unchanged
	# high hand. A real 180ms lowering re-arms, but the rise during cooldown
	# consumes its edge and never queues a delayed shot.
	_sample(game, false, 620, false, "Short false low begins")
	_sample(game, true, 670, false, "50ms low jitter cannot trigger firing")
	_sample(game, true, 690, false, "Post-jitter high remains latched")
	_check(game.projectiles.size() == 1, "Flickering false-to-true cannot double-fire")
	_lower(game, 700, "Confirmed low before early reload attempt")
	_sample(game, true, 919, false, "Early rise begins")
	_sample(game, true, 999, false, "499ms from last shot is still reloading")
	_sample(game, true, 1001, false, "Reload completion cannot auto-fire a held hand")
	_sample(game, true, 2500, false, "Early held raise never queues a late shot")
	_check(not game._launch_projectile(2600), "Direct duplicate bypass fails after cooldown")
	_check(game.projectiles.size() == 1, "Only the initial shot exists through cooldown")

	game._clear_projectiles()
	_lower(game, 4100, "Fresh low after cooldown")
	_sample(game, true, 4300, false, "Fresh rise requires confirmation")
	_sample(game, true, 4380, true, "Fresh rise after cooldown shoots once")
	_check(game.hand_raise_last_shot_ms == 4380, "Second shot records monotonic clock")
	game._clear_projectiles()

	# Exactly at the 0.5s deadline, a lower-then-raise edge succeeds.
	_lower(game, 4410, "Low before exact reload boundary")
	_sample(game, true, 4800, false, "Boundary rise begins")
	_sample(game, true, 4880, true, "500ms reload boundary permits the next shot")
	_check(game.hand_raise_last_shot_ms == 4880, "Boundary shot time is exact")
	game._clear_projectiles()

	# Lost tracking must never masquerade as a lowered hand. The returning
	# raised hand remains disarmed until it is visibly lowered and raised.
	_sample(game, false, 5900, false, "Tracking invalidates state", false)
	_check(not game.hand_raise_tracking_valid and not game.hand_raise_armed,
		"Tracking loss disarms while preserving cooldown")
	_check(game.hand_raise_last_shot_ms == 4880,
		"Tracking loss does not reset the 0.5s reload")
	_sample(game, true, 7450, false, "Reacquired high pose remains disarmed")
	_sample(game, true, 7530, false, "Confirmed high on reacquisition never shoots")
	_lower(game, 7600, "Recovered player genuinely lowers hand")
	_sample(game, true, 7800, false, "Post-recovery raise begins")
	_sample(game, true, 7880, true, "Post-recovery legitimate rise fires once")
	game._clear_projectiles()

	game._pause()
	_check(not game.timer_running and not game.hand_raise_armed,
		"Pause freezes gameplay and invalidates gesture latch")
	_sample(game, false, 9200, false, "Lowered readings during pause do not arm")
	_sample(game, true, 9280, false, "Raised readings during pause do not fire")
	_check(game.projectiles.is_empty(), "Pause produces no projectile")
	game._resume()
	_sample(game, true, 9600, false, "Resume with raised hand stays disarmed")
	_sample(game, true, 9680, false, "Holding on resume cannot shoot")
	_lower(game, 9800, "Player lowers after resume")
	_sample(game, true, 10000, false, "Post-pause rise begins")
	_sample(game, true, 10080, true, "Post-pause legitimate raise fires")
	game._clear_projectiles()

	game.clear_hand_raise_tracking()
	_sample(game, true, 11200, false, "Countdown disarm blocks already raised hand")
	_sample(game, true, 11280, false, "Countdown raised hold remains blocked")
	_lower(game, 11300, "Lower after countdown")
	_sample(game, true, 11500, false, "Raise exactly at boundary starts")
	_sample(game, true, 11580, true, "After countdown and reload, player can shoot")
	game._clear_projectiles()

	# An edge during a gap between questions must be discarded, never replayed
	# when another round becomes active.
	game.round_active = false
	_lower(game, 13000, "Lower during an inactive question")
	_sample(game, true, 13200, false, "Inactive question raising begins")
	_sample(game, true, 13280, false, "No shot during inactive question")
	game.round_active = true
	_sample(game, true, 13450, false, "Returning active while holding cannot shoot")
	_lower(game, 13500, "New low after inactive question")
	_sample(game, true, 13700, false, "New valid question rise begins")
	_sample(game, true, 13780, true, "New valid question raise fires exactly once")
	game._clear_projectiles()

	# Existing two-projectile capacity remains enforced and cannot be used to
	# bypass the edge/cooldown by repeated calls.
	for i in range(2):
		var dummy := Area2D.new()
		game.projectile_layer.add_child(dummy)
		game.projectiles.append(dummy)
	_lower(game, 15000, "Low before max projectile cap")
	_sample(game, true, 15300, false, "Capped projectile rise begins")
	_sample(game, true, 15380, false, "Two active projectiles block additional shot")
	_check(game.projectiles.size() == 2, "Projectile cap remains two")
	game._clear_projectiles()
	_sample(game, true, 16800, false, "Clearing projectile cap cannot replay held edge")
	_lower(game, 16900, "New low after projectile cap")
	_sample(game, true, 17100, false, "New raise after projectile cap begins")
	_sample(game, true, 17180, true, "New distinct rise fires after capacity clears")
	game._clear_projectiles()

	game._finish_round()
	_check(game.finishing and not game.hand_raise_armed, "Finishing round clears gesture latch")
	_sample(game, false, 18000, false, "No arming after round end")
	_sample(game, true, 19000, false, "No firing after round end")
	_check(game.projectiles.is_empty(), "Finishing keeps all projectiles cleared")
	game.queue_free()
	for _frame in range(5):
		await process_frame
	await create_timer(0.20).timeout
	if failures.is_empty():
		print("PASS Balloon hand-raise gesture: %d assertions" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("BALLOON GESTURE QA: " + failure)
		print("FAIL Balloon hand-raise gesture: %d failures in %d assertions" %
			[failures.size(), checks])
		quit(1)


func _lower(game: Control, start_ms: int, description: String) -> void:
	_sample(game, false, start_ms, false, description + " started")
	_sample(game, false, start_ms + 180, false, description + " confirmed")
	_check(game.hand_raise_armed, description + " arms a new edge")


func _sample(game: Control, raised: bool, at_ms: int, expected_shot: bool,
		description: String, tracking_valid: bool = true) -> void:
	var before: int = game.projectiles.size()
	var did_fire: bool = game.set_hand_raise_state(raised, tracking_valid, at_ms)
	_check(did_fire == expected_shot, description + " returns expected success status")
	_check(game.projectiles.size() == before + (1 if expected_shot else 0),
		description + " changes projectile count only on a real shot")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
