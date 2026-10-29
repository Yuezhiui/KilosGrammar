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
	_check(game.round_active and game.timer_running, "Playable question is active")
	_check(game.HAND_RAISE_RELOAD_MS == 1000, "Continuous held-high firing uses 1000ms reload")
	_check(game.projectiles.is_empty() and not game._launch_projectile(0),
		"Setup has no shot and direct bypass is forbidden")

	# Startup hand already UP is not a fresh gesture.
	_sample(game, true, 0, false, "Initial held UP is disarmed")
	_sample(game, true, 80, false, "Confirmed initial UP remains disarmed")
	_sample(game, true, 100, false, "Initial UP cannot queue a shot")
	_lower(game, 180, "First confirmed genuine low")
	_sample(game, true, 420, false, "UP rise needs confirmation")
	_sample(game, true, 500, true, "First stable raise fires")
	_check(game.hand_raise_last_shot_ms == 500, "First shot timestamp is exact")
	_sample(game, true, 600, false, "UP 100ms later cannot duplicate")

	# Brief erroneous low readings cannot create extra bullets.
	_sample(game, false, 620, false, "False low starts")
	_sample(game, true, 670, false, "False low ends in 50ms")
	_sample(game, true, 690, false, "Jitter cannot duplicate a shot")
	_check(game.projectiles.size() == 1, "Flicker keeps one live stone")

	# Every held UP has exactly one-second cadence; two stone cap is real.
	_sample(game, true, 1499, false, "999ms since shot remains locked")
	_sample(game, true, 1500, true, "1000ms fires without lowering")
	_check(game.projectiles.size() == 2, "Continuous gesture creates two live stones")
	_sample(game, true, 2500, false, "Third stone blocked at live-projectile cap")
	_check(game.projectiles.size() == 2 and game.hand_raise_last_shot_ms == 1500,
		"Capacity block preserves exact timestamp and projectile count")
	game._clear_projectiles()
	_sample(game, true, 2501, true, "New capacity lets same held pose fire")
	_sample(game, true, 3500, false, "999ms boundary still suppresses held shot")
	_sample(game, true, 3501, true, "1000ms next held shot fires")
	_check(game.hand_raise_last_shot_ms == 3501, "Repeated intervals never drift")
	game._clear_projectiles()

	# Releasing is optional between ordinary shots, but tracking loss revokes
	# authorization until a new genuine low/high gesture.
	_sample(game, false, 5900, false, "Occlusion invalidates wrist tracking", false)
	_check(not game.hand_raise_tracking_valid and not game.hand_raise_armed,
		"Invalid observation must revoke auto-fire")
	_check(game.hand_raise_last_shot_ms == 3501, "Tracking loss retains prior shot time")
	_sample(game, true, 7450, false, "Reappearing high pose cannot shoot")
	_sample(game, true, 7530, false, "Held high remains disarmed after occlusion")
	_lower(game, 7600, "Fresh low after tracking recovery")
	_sample(game, true, 7800, false, "Recovered rise begins")
	_sample(game, true, 7880, true, "Recovered genuine raise authorizes fire")
	game._clear_projectiles()

	# Pause cannot accumulate queued shots, even if both hand states occur.
	game._pause()
	_check(not game.timer_running and not game.hand_raise_armed,
		"Pause revokes firing authorization and freezes gameplay")
	_sample(game, false, 9200, false, "Paused low cannot arm")
	_sample(game, true, 9280, false, "Paused up cannot shoot")
	_check(game.projectiles.is_empty(), "Pause adds no projectile")
	game._resume()
	_sample(game, true, 9600, false, "Resume high remains disarmed")
	_sample(game, true, 9680, false, "Held UP on resume cannot shoot")
	_lower(game, 9800, "Fresh low after resume")
	_sample(game, true, 10000, false, "Resume rise begins")
	_sample(game, true, 10080, true, "New resume raise fires")
	game._clear_projectiles()

	# Countdown and disabled process mode demand fresh gameplay gesture.
	game.process_mode = Node.PROCESS_MODE_DISABLED
	_sample(game, false, 11200, false, "Countdown low cannot arm")
	_sample(game, true, 11280, false, "Countdown UP cannot shoot")
	game.process_mode = Node.PROCESS_MODE_INHERIT
	_sample(game, true, 11300, false, "GO high has no queued shot")
	_lower(game, 11400, "Fresh low after GO")
	_sample(game, true, 11650, false, "After GO new raise starts")
	_sample(game, true, 11730, true, "After GO new raise fires")
	game._clear_projectiles()

	# A raised hand during inactive question is discarded; next wave must
	# demand a real gesture. A completed run must be globally time/lives ended.
	game.round_active = false
	_lower(game, 13000, "Low during inactive question")
	_sample(game, true, 13200, false, "Inactive wave UP starts")
	_sample(game, true, 13280, false, "Inactive wave cannot shoot")
	game.round_active = true
	_sample(game, true, 13450, false, "New wave cannot replay a held high")
	_lower(game, 13500, "New wave fresh low")
	_sample(game, true, 13700, false, "New wave new raise begins")
	_sample(game, true, 13780, true, "New wave genuine raise shoots")
	game._clear_projectiles()

	# Leave the same hand UP, inject two real in-flight dummy stones, and
	# verify no extra shot on a due deadline until capacity is released.
	for i in range(2):
		var dummy := Area2D.new()
		game.projectile_layer.add_child(dummy)
		game.projectiles.append(dummy)
	_sample(game, true, 14780, false, "Two active stones prohibit automatic third")
	_check(game.projectiles.size() == 2, "Maximum live projectiles remains two")
	game._clear_projectiles()
	_sample(game, true, 14781, true, "Held high can fire after capacity clears")
	game._clear_projectiles()

	game._finish_round()
	_check(not game.finishing and game.get_context().get("completion_reason") == "",
		"Manual finish cannot mark an incomplete 60-second game as completed")
	game.time_remaining = 0.05
	game._process(0.1)
	_check(game.finishing and game.round_completed and not game.hand_raise_armed,
		"Actual global timer ending clears all gestures")
	_check(game.get_context().get("completion_reason") == "time_up",
		"Only genuine time-up exports completed-round result")
	_sample(game, false, 18000, false, "No arming after terminal result")
	_sample(game, true, 19000, false, "No shots after terminal result")
	_check(game.projectiles.is_empty(), "Finished game has no projectiles")
	game.queue_free()
	for _frame in range(5):
		await process_frame
	await create_timer(0.20).timeout
	for failure in failures:
		push_error("BALLOON GESTURE QA: " + failure)
	print("BALLOON GESTURE %s: %d checks / %d failures" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
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
