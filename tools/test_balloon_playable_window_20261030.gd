extends SceneTree

# Real Balloon scene, no camera, network, DB, or waiting for real-time ascent.
# Godot --headless --path . --script res://tools/test_balloon_playable_window_20261030.gd
# Test geometry at four resolutions, both modes, each difficulty and both
# unboosted/max-cumulative-boost flight. Tick over the real collision gates.
const SCENE: PackedScene = preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]
const TARGET_BASE := {"Easy": 7.0, "Normal": 5.8, "Hard": 4.6}
const MINIMUM_CAPPED := {"Easy": 5.0, "Normal": 4.0, "Hard": 3.0}

var checks := 0
var failures: Array[String] = []
var measured_windows: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := root.size
	for screen_size in SIZES:
		root.size = screen_size
		await process_frame
		for difficulty in DIFFICULTIES:
			for mode in MODES:
				await _scenario(screen_size, difficulty, mode)
	root.size = original
	for difficulty in DIFFICULTIES:
		var pair: Array = measured_windows.get(difficulty, [0.0, 0.0])
		print("BALLOON HIT WINDOW %s @1280x720: base %.2fs, capped %.2fs (floor %.2fs)" %
			[difficulty, float(pair[0]), float(pair[1]), float(MINIMUM_CAPPED[difficulty])])
	for failure in failures.slice(0, 30):
		push_error("BALLOON PLAYABLE WINDOW QA: " + failure)
	print("BALLOON PLAYABLE WINDOW %s: %d assertions, %d failures / %d scenarios" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size(),
		SIZES.size() * DIFFICULTIES.size() * MODES.size() * 2])
	quit(0 if failures.is_empty() else 1)


func _scenario(screen_size: Vector2i, difficulty: String, mode: String) -> void:
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	game.position = Vector2.ZERO
	game.size = Vector2(screen_size)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.set_context({"activity": "Balloon Popping", "topic": "Noun",
		"difficulty": difficulty, "game_mode": mode, "camera_live": false})
	game.set_process(false)
	game.set_physics_process(false)
	var label := "%s/%s/%s" % [screen_size, difficulty, mode]
	_check(game.round_active and game.timer_running and game.round_time_limit > 7.0,
		label + ": genuine long, flight-aware question starts")
	_check(game.time_remaining == (60.0 if mode == "Seconds" else 0.0) and
		game.hearts == (0 if mode == "Seconds" else 3),
		label + ": 60-second and three-heart modes unchanged")
	_check(game.HAND_RAISE_RELOAD_MS == 1000 and
		game.get_context().get("completion_reason", "") == "",
		label + ": held-high cooldown and completed-only score unchanged")

	var base_speed: float = game.balloon_float_speed
	var hit_span: float = game._balloon_hit_entry_y() - game.UPPER_LINE_Y
	var initial_window := hit_span / base_speed
	_check(absf(initial_window - float(TARGET_BASE[difficulty])) < 0.025,
		label + ": geometry-based initial window meets exact accessibility target")
	_check(game._balloon_hidden_y() > game._balloon_hit_entry_y() + 60.0 and
		game._balloon_hit_entry_y() > game._balloon_y() and hit_span > 0.0,
		label + ": concealed spawn is before the visible hit strip and upper line")
	_check(game.round_time_limit > (game._balloon_hidden_y() - game.BALLOON_EXIT_Y) /
		base_speed,
		label + ": timer never discards last balloon before natural top escape")

	for phase in ["base", "capped"]:
		if phase == "capped":
			for index in range(200):
				game._boost_balloon_ascent()
			game._start_new_round()
			game.set_process(false)
		var speed: float = game.balloon_float_speed
		var playable := hit_span / speed
		_check(playable >= float(MINIMUM_CAPPED[difficulty]) + 0.25,
			label + "/" + phase + ": capped hit interval exceeds requested minimum")
		_check(speed <= base_speed * float(game.BALLOON_SPEED_CAPS[difficulty]) + 0.01,
			label + "/" + phase + ": repeated correct shots cannot bypass capped speed")
		_check(game.round_active and game.balloons.size() == 3 and
			game.round_time_remaining == game.round_time_limit,
			label + "/" + phase + ": new question resets all lanes and its complete clock")
		var hidden: float = game._balloon_hidden_y()
		var entry: float = game._balloon_hit_entry_y()
		var enter_at := (hidden - entry) / speed
		game._process(enter_at - 0.01)
		game.set_process(false)
		for lane in range(3):
			var balloon := game.balloons[lane] as Area2D
			_check(balloon.visible and not balloon.monitoring and not balloon.monitorable
				and balloon.position.y > entry,
				label + "/" + phase + ": lane %d cannot be hit before emerging" % lane)
		game._process(0.02)
		game.set_process(false)
		var first_hittable_y: float = (game.balloons[0] as Area2D).position.y
		for lane in range(3):
			var balloon := game.balloons[lane] as Area2D
			_check(balloon.monitoring and balloon.monitorable and
				absf(balloon.position.y - (entry - speed * 0.01)) < 0.5,
				label + "/" + phase + ": lane %d enters collision-enabled strip smoothly" % lane)
		game._process(playable - 0.04)
		game.set_process(false)
		for lane in range(3):
			var balloon := game.balloons[lane] as Area2D
			_check(balloon.monitoring and balloon.monitorable and
				absf(balloon.position.y - (game.UPPER_LINE_Y + speed * 0.03)) < 0.6,
				label + "/" + phase + ": lane %d stays shootable nearly to upper line" % lane)
		var proven_interval := (first_hittable_y -
			(game.balloons[0] as Area2D).position.y) / speed
		_check(proven_interval >= float(MINIMUM_CAPPED[difficulty]) and
			proven_interval > playable - 0.05,
			label + "/" + phase + ": simulated *actual collision-ON* window meets floor")
		_check(game.round_active and game.round_time_remaining > 0.1,
			label + "/" + phase + ": no question reset while last target is hittable")
		game._process(0.04)
		game.set_process(false)
		for lane in range(3):
			var balloon := game.balloons[lane] as Area2D
			_check(balloon.visible and not balloon.monitoring and not balloon.monitorable and
				balloon.position.y <= game.UPPER_LINE_Y,
				label + "/" + phase + ": lane %d cannot score after upper hit line" % lane)
		game._process(((game.balloons[0] as Area2D).position.y - game.BALLOON_EXIT_Y) / speed + 0.04)
		game.set_process(false)
		_check(not game.round_active and (game.next_round_pending or game.finishing),
			label + "/" + phase + ": all balloons exit top and retire correctly")
		if phase == "base":
			# Neutralize the ordinary Lives miss before testing many correct
			# boost steps. No production shortcuts or legacy source latches.
			if mode == "Lives":
				game.hearts = 3
			game._on_next_round_delay_elapsed()
			game.set_process(false)
		if screen_size == Vector2i(1280, 720) and mode == "Seconds":
			var pair: Array = measured_windows.get(difficulty, [0.0, 0.0])
			pair[0 if phase == "base" else 1] = proven_interval
			measured_windows[difficulty] = pair
	game.queue_free()
	await process_frame
	await process_frame


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
