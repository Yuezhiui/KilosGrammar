extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_balloon_quick_hand_raise.gd
# Camera-free, deterministic timestamps. Exercises the actual projectile scene
# and gesture API without a database, preview camera or live pose worker.
const BALLOON_SCENE := preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := BALLOON_SCENE.instantiate() as Control
	root.add_child(game)
	await process_frame
	game.set_context({"activity": "Balloon Popping", "topic": "Noun",
		"game_mode": "Seconds", "difficulty": "Normal", "time_remaining": 60.0})
	game.set_process(false)
	game.set_physics_process(false)
	_check(game.round_active and game.timer_running, "real Balloon round starts live")
	_check(game.HAND_RAISE_RELOAD_MS == 1000, "held-high reload is exactly 1000ms")
	_check(game.HAND_RAISE_LOWER_CONFIRM_MS >= 100, "lower confirmation filters wrist flicker")
	_check(game.HAND_RAISE_UP_CONFIRM_MS > 0, "up confirmation ignores one bad frame")
	_check(game.projectiles.is_empty(), "setup does not auto-shoot")
	_check(not game._launch_projectile(100), "direct projectile call cannot bypass gesture")

	# Already-high hand at startup cannot launch until a real LOW-to-HIGH arm.
	_sample(game, true, 0, false, "Already-raised hand at gameplay entry")
	_sample(game, true, 80, false, "Initial raised hand confirmed but disarmed")
	_sample(game, true, 150, false, "Initial held UP cannot shoot")
	_lower(game, 200, "First deliberate lower")
	_wrist_sample(game, true, false, 410, false, "LEFT hand begins fresh rise")
	_wrist_sample(game, true, false, 490, true, "LEFT hand fires first stone")
	_check(game.hand_raise_last_shot_ms == 490, "first shot timestamp recorded")
	_sample(game, true, 530, false, "Repeated UP cannot fire before one second")
	_check(game.projectiles.size() == 1, "only one live projectile before reload")

	# Brief jitter and changing which hand is raised never create a duplicate.
	_sample(game, false, 540, false, "50ms invalid-looking low starts")
	_sample(game, true, 590, false, "brief low flicker recovers")
	_wrist_sample(game, false, true, 600, false, "RIGHT hand takes over while raised")
	_check(game.hand_raise_armed, "fresh gesture retains authorization under valid tracking")

	# Exact 999/1000ms boundary and the two-projectile cap.
	_wrist_sample(game, false, true, 1489, false, "999ms held-right high cannot shoot")
	_wrist_sample(game, false, true, 1490, true, "1000ms held-right high shoots")
	_check(game.projectiles.size() == 2 and game.hand_raise_last_shot_ms == 1490,
		"repeated high gesture creates exactly two live stones")
	_sample(game, true, 2490, false, "capacity prevents third held-high stone")
	_check(game.projectiles.size() == 2 and game.hand_raise_last_shot_ms == 1490,
		"blocked capacity cannot change timestamp or create a stone")
	game._clear_projectiles()
	_sample(game, true, 2491, true, "held high fires once capacity reopens")
	_sample(game, true, 3490, false, "999ms again is still reloading")
	_sample(game, true, 3491, true, "1000ms again fires without lowering")
	_check(game.hand_raise_last_shot_ms == 3491, "held-high repeated deadline is precise")
	game._clear_projectiles()
	# Invisible/occluded wrists must be UNKNOWN, never a DOWN observation.
	_sample(game, false, 4210, false, "Occluded wrist reports invalid observation", false)
	_check(not game.hand_raise_tracking_valid and not game.hand_raise_armed,
		"invalid wrist disarms and clears tracking")
	_sample(game, true, 4260, false, "Reappearing raised wrist is not an edge")
	_sample(game, true, 4340, false, "Reappearing raised hand remains disarmed")
	_lower(game, 4360, "Reacquired hand visibly lowers")
	_sample(game, true, 5610, false, "Reacquired hand begins a new rise")
	_sample(game, true, 5690, true, "Real rise after occlusion can shoot")
	game._clear_projectiles()

	# The parent gameplay wrapper disables minigame processing throughout the
	# guided tutorial/countdown. A direct call cannot arm or fire in this state.
	game.process_mode = Node.PROCESS_MODE_DISABLED
	_sample(game, false, 6000, false, "Calibration/countdown DOWN is ignored")
	_sample(game, false, 6300, false, "Calibration/countdown cannot arm")
	_sample(game, true, 6450, false, "Calibration/countdown UP cannot fire")
	_sample(game, true, 6530, false, "Calibration/countdown held UP cannot fire")
	_check(not game.hand_raise_armed and game.projectiles.is_empty(),
		"disabled minigame has no shot and no queued gesture")
	game.process_mode = Node.PROCESS_MODE_INHERIT
	_sample(game, true, 6600, false, "No shot on GO while hand remains raised")
	_sample(game, true, 6680, false, "Post-GO raised hold stays disarmed")
	_lower(game, 6700, "Post-GO genuine release")
	_sample(game, true, 7550, false, "Post-GO new rise begins")
	_sample(game, true, 7630, true, "Post-GO fresh raise shoots")
	game._clear_projectiles()

	game._pause()
	_sample(game, false, 7800, false, "Paused DOWN cannot rearm")
	_sample(game, true, 8100, false, "Paused UP cannot fire")
	_check(game.projectiles.is_empty(), "paused gameplay is projectile-free")
	game._resume()
	_sample(game, true, 8180, false, "Resume with raised hand does not shoot")
	_lower(game, 8200, "Pause recovery lower")
	_sample(game, true, 9150, false, "Pause recovery rise begins")
	_sample(game, true, 9230, true, "Fresh rise after resume fires once")
	game._clear_projectiles()

	# A rise while a new question is not active must not queue a projectile
	# for when that question becomes active.
	game.round_active = false
	_lower(game, 9350, "Question transition lower")
	_sample(game, true, 9660, false, "No shot during inactive question rise start")
	_sample(game, true, 9740, false, "No shot during inactive question")
	game.round_active = true
	_sample(game, true, 9860, false, "New question does not replay held raised hand")
	_lower(game, 9900, "New question lower")
	_sample(game, true, 10970, false, "New question raise starts")
	_sample(game, true, 11050, true, "New question accepts a fresh rise")
	game._clear_projectiles()

	# The game cannot end on vocabulary or manual finish requests; trigger the
	# real Seconds terminal condition instead of bypassing the game rules.
	game._finish_round()
	_check(not game.finishing and game.time_remaining > 0.0,
		"Manual finish request cannot bypass remaining 60-second clock")
	game._process(60.0)
	_check(game.finishing and game.round_completed and game.time_remaining == 0.0,
		"Only global timer reaching zero finishes Seconds")
	_sample(game, false, 11350, false, "Finished round cannot rearm")
	_sample(game, true, 11900, false, "Finished round cannot fire")
	_check(game.projectiles.is_empty(), "finished round contains no new shots")
	game.queue_free()
	for _frame in range(4):
		await process_frame
	for failure in failures:
		push_error("BALLOON QUICK RAISE FAIL: " + failure)
	print("BALLOON_QUICK_RAISE %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _lower(game: Control, started_ms: int, label: String) -> void:
	_sample(game, false, started_ms, false, label + " begins")
	_sample(game, false, started_ms + game.HAND_RAISE_LOWER_CONFIRM_MS,
		false, label + " confirmed")
	_check(game.hand_raise_armed, label + " rearms only after confirmation")


func _sample(game: Control, raised: bool, now_ms: int, expected_shot: bool,
		label: String, tracking_valid: bool = true) -> void:
	var before: int = game.projectiles.size()
	var fired: bool = game.set_hand_raise_state(raised, tracking_valid, now_ms)
	_check(fired == expected_shot, label + " returns expected firing state")
	_check(game.projectiles.size() == before + int(expected_shot),
		label + " changes projectile count only for a confirmed shot")


func _wrist_sample(game: Control, left_up: bool, right_up: bool, now_ms: int,
		expected_shot: bool, label: String) -> void:
	# PoseService already combines the validated wrists with OR; neither wrist
	# has special priority. Swapping active wrists without BOTH being lowered
	# must keep the same edge consumed.
	_sample(game, left_up or right_up, now_ms, expected_shot, label)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
