extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_balloon_multiplayer_sequential_20261103.gd
# Synthetic input; verifies real existing scene/art without camera or database.
const BALLOON_SCENE := preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var game := BALLOON_SCENE.instantiate() as Control
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.set_context({
		"activity": "Balloon Popping", "player_mode": "Multiplayer",
		"multiplayer": true, "topic": "Noun", "game_mode": "Seconds",
		"difficulty": "Normal", "score": 9999, "player2_score": 9999,
		"player2_student_id": "STUDENT-2", "player2_student_name": "Student Two",
		"player2_grade_section": "Grade 3-A"
	})
	game.set_process(false)
	game.set_physics_process(false)
	_check(game.multiplayer_enabled and game.round_active and game.timer_running,
		"Real multiplayer game starts its own shared round")
	_check(game.score == 0 and game.player2_score == 0 and game.hearts == 3 \
		and game.player2_hearts == 3 and game.time_remaining == 60.0,
		"Both new players have independent clean scores/hearts and common 60s")
	_check(is_instance_valid(game.launcher) and is_instance_valid(game.player2_launcher) \
		and game.player2_launcher.visible and game.balloon_slots.size() == 3,
		"Two visible authored launcher instances in one three-balloon arena")
	_check(game.multiplayer_player_labels.size() == 2 \
		and game.multiplayer_score_plaque.visible,
		"Both live score/heart readouts are visible")
	_check(game.multiplayer_score_plaque.position.x < game.carnival_score_plaque.position.x \
		and game.multiplayer_player_labels[1].position.x < game.multiplayer_player_labels[0].position.x,
		"Runtime P2 scoreboard is on the opposite side from P1 immediately after setup")

	# Only P1 physically occupies a slot. P2 remains stationary and disarmed.
	var p1_start: float = game.multiplayer_launcher_x[0]
	var p2_start: float = game.multiplayer_launcher_x[1]
	game.set_multiplayer_body_x(0, 1.0)
	game.clear_multiplayer_body_input(1)
	game._update_multiplayer_launchers(0.15)
	_check(game.multiplayer_launcher_x[0] > p1_start \
		and is_equal_approx(game.multiplayer_launcher_x[1], p2_start),
		"P1 moves without animating inactive P2")
	game.clear_multiplayer_body_input(0)
	var frozen_p1: float = game.multiplayer_launcher_x[0]
	game._update_multiplayer_launchers(0.3)
	_check(is_equal_approx(game.multiplayer_launcher_x[0], frozen_p1),
		"Lost P1 source stops movement instantly")
	_check(not game.set_multiplayer_hand_raise_state(1, true, true, 500),
		"Untracked P2 cannot fire from an invented gesture")

	# Startup already-high hand must NOT fire, for either slot.
	game.set_multiplayer_body_x(0, 0.0)
	_check(not game.set_multiplayer_hand_raise_state(0, true, true, 0),
		"Initially raised P1 arm is disarmed")
	_check(not game.set_multiplayer_hand_raise_state(0, true, true, 80),
		"P1 does not shoot without verified low")
	_sample(game, 0, false, 100, false, "P1 starts lower")
	_sample(game, 0, false, 280, false, "P1 confirmed lower")
	_sample(game, 0, true, 350, false, "P1 begins raising")
	_sample(game, 0, true, 430, true, "P1 fires after confirmed raise")
	_check(game.projectile_owners.values() == [0], "First stone belongs only to P1")

	# Same person walks to right after leaving P1. The old bullet and arm
	# authority are revoked and cannot become a ghost balloon pop.
	game.clear_multiplayer_body_input(0)
	_check(game.projectiles.is_empty() and not game.multiplayer_hand_states[0]["armed"],
		"P1 leaves: projectile removed and gesture disarmed")
	game.set_multiplayer_body_x(1, -1.0)
	game._update_multiplayer_launchers(0.1)
	_check(game.multiplayer_launcher_x[1] < p2_start \
		and is_equal_approx(game.multiplayer_launcher_x[0], frozen_p1),
		"One body switches to P2 while P1 stays frozen")
	_sample(game, 1, true, 600, false, "P2 starts high without firing")
	_sample(game, 1, true, 680, false, "P2 high does not transfer P1 arm state")
	_sample(game, 1, false, 700, false, "P2 begins lower")
	_sample(game, 1, false, 880, false, "P2 confirmed lower")
	_sample(game, 1, true, 900, false, "P2 raises")
	_sample(game, 1, true, 980, true, "P2 fires own projectile")
	_check(game.projectile_owners.values() == [1] and game.player2_score == 0,
		"P2 owns its stone but has not received an invented score")
	game.clear_multiplayer_body_input(1)
	_check(game.projectiles.is_empty(), "Disappearing P2 stone cannot ghost-pop")

	# Two live people can shoot independently at the same time. A one-second
	# reload and two-live-stone cap apply per student.
	game.set_multiplayer_body_x(0, 0.0)
	game.set_multiplayer_body_x(1, 0.0)
	_arm(game, 0, 1200)
	_arm(game, 1, 1200)
	_sample(game, 0, true, 1900, false, "P1 raise pending")
	_sample(game, 1, true, 1900, false, "P2 raise pending")
	_sample(game, 0, true, 1980, true, "P1 fires concurrent stone")
	_sample(game, 1, true, 1980, true, "P2 fires concurrent stone")
	_check(game.projectiles.size() == 2 and game.projectile_owners.values().has(0) \
		and game.projectile_owners.values().has(1),
		"Both source-verified arms shoot in the shared arena")
	_sample(game, 1, true, 2979, false, "P2 reload blocks at 999ms")
	_sample(game, 1, true, 2980, true, "P2 held arm fires exactly at one second")
	_sample(game, 1, true, 3980, false, "P2 capacity limit blocks a third live stone")
	_check(game.projectiles.size() == 3, "P2 capacity cap does not block P1 shots")

	# Resolve one real projectile/balloon collision. Shared balloon vanishes
	# once; credit belongs exclusively to that projectile's owner.
	var correct_lane: int = game.pending_valid_lanes[0]
	var correct_balloon := game.balloons[correct_lane] as Area2D
	correct_balloon.position.y = game.UPPER_LINE_Y + 40.0
	correct_balloon.monitorable = true
	correct_balloon.monitoring = true
	var p2_projectile: Area2D = null
	for projectile in game.projectiles:
		if int(game.projectile_owners[projectile]) == 1:
			p2_projectile = projectile
			break
	_check(is_instance_valid(p2_projectile), "P2 collision projectile is live")
	if is_instance_valid(p2_projectile):
		game._resolve_projectile_balloon_hit(p2_projectile, correct_lane)
	_check(game.player2_score == 100 and game.score == 0 \
		and game.player2_correct == 1 and game.correct_count == 0,
		"Correct P2 pop credits only P2 and one shared balloon")
	game._refresh_hud()
	_check(game.multiplayer_score_number.text == "100" \
		and game.score_bottom_number.text == "0",
		"Visible score art displays each player's actual score")

	# Wrong and missed stones charge only their true owner.
	game._start_new_round()
	var invalid_lane := -1
	for lane in range(3):
		if not game.valid_lanes.has(lane):
			invalid_lane = lane
			break
	_check(invalid_lane >= 0, "Round has an actual incorrect word")
	if invalid_lane >= 0:
		game._pop_balloon(invalid_lane, 1)
		_check(game.player2_hearts == 2 and game.hearts == 3,
			"Wrong P2 balloon only loses P2 heart")
	game._clear_projectiles()
	_sample(game, 0, true, 2980, true, "P1 held arm has own one-second reload")
	var p1_projectile: Area2D = game.projectiles[0] if not game.projectiles.is_empty() else null
	if is_instance_valid(p1_projectile):
		game._on_projectile_missed(p1_projectile)
	_check(game.hearts == 2 and game.player2_hearts == 2 and game.score == 0,
		"Missed P1 stone loses only P1 heart")
	game.clear_multiplayer_body_input(0)
	game.clear_multiplayer_body_input(1)
	var time_before: float = game.time_remaining
	game._process(0.3)
	_check(is_equal_approx(game.time_remaining, time_before - 0.3) \
		and game.timer_running and not game.finishing,
		"Shared clock continues with both camera slots inactive")
	var payload: Dictionary = game.get_context()
	_check(payload.get("player1_score") == 0 and payload.get("player2_score") == 100 \
		and payload.get("player1_lives") == 2 and payload.get("player2_lives") == 2 \
		and payload.get("player2_student_id") == "STUDENT-2" \
		and payload.get("multiplayer_result_provisional", false),
		"Results attribute P2 score/lives/identity without claiming DB persistence")
	game.time_remaining = 0.03
	game._process(0.10)
	_check(game.finishing and payload.get("completion_reason") == "" \
		and game.get_context().get("completion_reason") == "time_up",
		"Only actual shared timeout completes timed multiplayer")
	game.queue_free()
	await process_frame

	await _test_lives_and_solo()
	for failure in failures.slice(0, 35):
		printerr("BALLOON TWO PLAYER: ", failure)
	print("BALLOON TWO PLAYER: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_lives_and_solo() -> void:
	var game := BALLOON_SCENE.instantiate() as Control
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.set_context({"player_mode": "Multiplayer", "activity": "Balloon Popping",
		"game_mode": "Lives", "difficulty": "Easy"})
	game.set_process(false)
	game.set_physics_process(false)
	game.hearts = 0
	game.player2_hearts = 1
	game._finish_round()
	_check(not game.finishing, "P1 elimination does not finish surviving P2 lives game")
	game.set_multiplayer_body_x(0, 1.0)
	_check(not game.multiplayer_input_active[0], "Zero-heart P1 may not regain steering")
	game.player2_hearts = 0
	game._finish_round()
	_check(game.finishing and game.get_context().get("completion_reason") == "lives_empty",
		"Both eliminated students end shared Lives round")
	game.set_context({"player_mode": "Single", "multiplayer": false,
		"activity": "Balloon Popping", "game_mode": "Seconds", "difficulty": "Normal"})
	_check(not game.multiplayer_enabled and not game.player2_launcher.visible \
		and game.hearts == 0 and game.score == 0,
		"Reusing the scene restores original single-player mode")
	_check(not game.set_multiplayer_hand_raise_state(1, true, true, 5000),
		"Multiplayer shooting API refuses input during solo game")
	game.queue_free()
	await process_frame


func _arm(game: Control, index: int, start_ms: int) -> void:
	_sample(game, index, false, start_ms, false, "Player %d lower start" % index)
	_sample(game, index, false, start_ms + 180, false, "Player %d lower confirms" % index)


func _sample(game: Control, index: int, raised: bool, at_ms: int, expected: bool,
		description: String, valid: bool = true) -> void:
	var prior: int = game.projectiles.size()
	var shot: bool = game.set_multiplayer_hand_raise_state(index, raised, valid, at_ms)
	_check(shot == expected and game.projectiles.size() == prior + (1 if expected else 0),
		description)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
