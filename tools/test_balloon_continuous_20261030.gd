extends SceneTree

# Native/headless Balloon regression for held-hand fire, continuous ascent,
# seven-second question safety, and actual Catch-size HUD. No camera or DB.
# Godot --headless --path . --script res://tools/test_balloon_continuous_20261030.gd
const SCENE: PackedScene = preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
var assertions := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := root.size
	for physical in SIZES:
		root.size = physical
		await process_frame
		await process_frame
		for difficulty in DIFFICULTIES:
			await _check_game(physical, difficulty)
	root.size = original
	await create_timer(0.85).timeout
	for frame in range(4):
		await process_frame
	for failure in failures.slice(0, 24):
		push_error("BALLOON CONTINUOUS QA: " + failure)
	print("BALLOON CONTINUOUS %s: %d assertions, %d failures across %d scenarios" %
		["PASS" if failures.is_empty() else "FAIL", assertions, failures.size(), SIZES.size() * DIFFICULTIES.size()])
	quit(0 if failures.is_empty() else 1)


func _check_game(physical: Vector2i, difficulty: String) -> void:
	var host := Control.new()
	host.size = root.get_visible_rect().size
	root.add_child(host)
	var game := SCENE.instantiate() as Control
	if game == null or game.get_script() == null:
		_check(false, str(physical) + "/" + difficulty + " production Balloon script must compile")
		if game != null:
			game.free()
		host.queue_free()
		await process_frame
		return
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.set_context({"topic": "Noun", "game_mode": "Lives", "difficulty": difficulty})
	game.set_process(false)
	game.set_physics_process(false)
	var label := "%s/%s" % [physical, difficulty]
	_check(game.round_active and game.timer_running and game.round_time_limit > 7.0,
		label + " slow ascent receives a path-aware question deadline")
	_check(game.HAND_RAISE_RELOAD_MS == 1000 and game.projectiles.is_empty(),
		label + " fires at one-second intervals and no startup ghost shot")
	_check(game.get_context()["completion_reason"] == "", label + " incomplete game cannot save completed score")
	_check(not game.set_hand_raise_state(true, true, 0), label + " already-high start disarmed")
	_check(not game.set_hand_raise_state(true, true, 80), label + " confirmed high remains disarmed")
	_check(not game.set_hand_raise_state(false, true, 100), label + " genuine low begins")
	_check(not game.set_hand_raise_state(false, true, 280), label + " genuine low arms")
	_check(not game.set_hand_raise_state(true, true, 300), label + " up confidence waits 80ms")
	_check(game.set_hand_raise_state(true, true, 380), label + " fresh raised hand fires")
	_check(not game.set_hand_raise_state(true, true, 1379), label + " 999ms cannot fire twice")
	_check(game.set_hand_raise_state(true, true, 1380), label + " same held hand auto-fires at 1000ms")
	_check(game.projectiles.size() == 2, label + " two live stones")
	_check(not game.set_hand_raise_state(true, true, 2380), label + " projectile cap blocks third stone")
	game._clear_projectiles()
	_check(game.set_hand_raise_state(true, true, 2381), label + " held hand resumes when capacity available")
	game._clear_projectiles()
	_check(not game.set_hand_raise_state(false, false, 3200), label + " occluded hand has no shot")
	_check(not game.set_hand_raise_state(true, true, 4400), label + " reacquired held-high pose disarmed")
	_check(not game.set_hand_raise_state(true, true, 4480), label + " reacquired high cannot auto-shoot")
	game.set_hand_raise_state(false, true, 4510)
	game.set_hand_raise_state(false, true, 4690)
	game.set_hand_raise_state(true, true, 4710)
	_check(game.set_hand_raise_state(true, true, 4790), label + " fresh gesture after occlusion fires")
	game._clear_projectiles()
	game._pause()
	_check(not game.set_hand_raise_state(true, true, 6500), label + " pause ignores raised hand")
	game._resume()
	_check(not game.set_hand_raise_state(true, true, 7000), label + " paused raised hand not queued")
	game.set_hand_raise_state(false, true, 7100)
	game.set_hand_raise_state(false, true, 7280)
	game.set_hand_raise_state(true, true, 7300)
	_check(game.set_hand_raise_state(true, true, 7380), label + " new raise after resume fires")
	game._clear_projectiles()
	var hidden: float = game._balloon_hidden_y()
	var exposed: float = game._balloon_hit_entry_y()
	var travel: float = game.balloon_float_speed
	_check(travel > 0.0 and (hidden - game.BALLOON_EXIT_Y) / travel < game.round_time_limit,
		label + " balloon exits naturally before its path-aware question deadline")
	_check((exposed - game.UPPER_LINE_Y) / travel >=
			float({"Easy": 6.95, "Normal": 5.75, "Hard": 4.55}[difficulty]),
		label + " target is hittable for accessible seconds after emerging")
	for lane in range(3):
		var balloon := game.balloons[lane] as Area2D
		_check(absf(balloon.position.y - hidden) < 0.5 and not balloon.monitoring,
			label + " concealed lane %d starts hidden and cannot collide" % lane)
	var y0: float = game.balloons[1].position.y
	game._process(0.25)
	game.set_process(false)
	_check(is_equal_approx(y0 - game.balloons[1].position.y, travel * 0.25),
		label + " first 250ms rises uniformly without easing")
	_check(game.round_time_remaining < game.round_time_limit,
		label + " question countdown starts during continuous ascent")
	game._process((hidden - exposed) / travel + 0.12)
	game.set_process(false)
	_check(game.balloons[1].position.y < exposed and game.balloons[1].monitoring,
		label + " real Area2D collision activates after the sprite emerges")
	var hearts_before: int = game.hearts
	game._process((game.balloons[1].position.y - game.BALLOON_EXIT_Y) / travel + 0.08)
	game.set_process(false)
	_check(not game.round_active and game.next_round_pending and game.hearts == hearts_before - 1,
		label + " missed all balloons start next wave and cost one Lives heart")
	_check(game.projectiles.is_empty() and not game.round_completed,
		label + " missed wave clears stones and cannot export a completed run")
	game._on_next_round_delay_elapsed()
	game.set_process(false)
	_check(game.round_active and game.balloons.size() == 3,
		label + " next wave activates automatically from below")
	for lane in range(3):
		_check(absf(game.balloons[lane].position.y - hidden) < 0.5,
			label + " new wave lane %d restarts at the concealed coordinate" % lane)
	_check(game.get_context()["completion_reason"] == "",
		label + " only real terminal modes can mark results completed")
	if physical == Vector2i(1280, 720):
		_check_rect(game.get_node("HudLayer/ObjectivePanel"), Vector2(13, 10), Vector2(506, 157), label + " title")
		_check_rect(game.get_node("HudLayer/TimerPlaque"), Vector2(990, 8), Vector2(195, 76), label + " timer")
		_check_rect(game.get_node("HudLayer/LivesPlaque"), Vector2(990, 8), Vector2(195, 76), label + " lives")
		_check_rect(game.get_node("HudLayer/PausePlaque"), Vector2(1195, 8), Vector2(81, 81), label + " pause plaque")
		_check_rect(game.get_node("HudLayer/PauseButton"), Vector2(1212, 25), Vector2(48, 48), label + " pause button")
	var badge := game.shared_lives_plaque as TextureRect
	var score := game.carnival_score_plaque as TextureRect
	var pause := game.pause_plaque as TextureRect
	_check(not badge.get_global_rect().intersects(score.get_global_rect()) and
			not pause.get_global_rect().intersects(score.get_global_rect()),
		label + " score stays below and clear of timer/lives and pause")
	host.queue_free()
	await process_frame
	await process_frame


func _check_rect(control: Control, position: Vector2, size: Vector2, label: String) -> void:
	_check(control.position.distance_to(position) < 0.6 and control.size.distance_to(size) < 0.6,
		label + " matches Catch layout: actual " + str(control.get_rect()))


func _check(condition: bool, detail: String) -> void:
	assertions += 1
	if not condition:
		failures.append(detail)
