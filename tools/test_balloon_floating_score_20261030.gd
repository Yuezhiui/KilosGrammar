extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_balloon_floating_score_20261030.gd
# Uses isolated scene instances; no camera, API or student records.

const BALLOON_SCENE := preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const PHYSICAL_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

var checks := 0
var scenarios := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for physical in PHYSICAL_SIZES:
		root.size = physical
		await process_frame
		var host := Control.new()
		host.name = "BalloonFeedbackTestHost"
		host.size = root.get_visible_rect().size
		root.add_child(host)
		for mode in ["Seconds", "Lives"]:
			await _check_mode(host, mode, str(physical) + " " + mode)
		host.queue_free()
		await process_frame
	for unused in range(3):
		await process_frame
	if failures.is_empty() and scenarios == PHYSICAL_SIZES.size() * 2 and checks >= scenarios * 15:
		print("PASS Balloon floating score: %d checks across 3 viewports and 2 modes" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("BALLOON FLOATING SCORE: " + failure)
		print("FAIL Balloon floating score: %d failures in %d checks" % [failures.size(), checks])
		quit(1)


func _check_mode(host: Control, mode: String, title: String) -> void:
	scenarios += 1
	var game := _new_game(host, mode)
	var two_correct: Array[int] = [0, 1]
	game.pending_valid_lanes = two_correct
	var correct_balloon := game.balloons[0] as Area2D
	correct_balloon.position.y = game._balloon_y()
	game._pop_balloon(0)
	_check(game.score == 100 and game.correct_count == 1 and game.attempts == 1,
		title + " correct pop grants exactly one 100-point award")
	_check(_popup_texts(game) == ["+100"], title + " green +100 on correct hit")
	var popup := _popup_nodes(game)[0]
	_check(popup.get_theme_color("font_color") == game.SCORE_CORRECT_COLOR,
		title + " correct feedback uses Catch green")
	game._pop_balloon(0)
	_check(game.score == 100 and _popup_texts(game) == ["+100"],
		title + " duplicate hit cannot reward or show feedback twice")
	await create_timer(0.10).timeout
	game._pause()
	var pause_y: float = popup.position.y
	var pause_alpha: float = popup.modulate.a
	game._pop_balloon(1)
	_check(game.score == 100 and _popup_texts(game) == ["+100"],
		title + " paused gameplay cannot register another correct hit")
	await create_timer(0.16).timeout
	_check(absf(popup.position.y - pause_y) <= 0.6 and absf(popup.modulate.a - pause_alpha) <= 0.02,
		title + " score popup animation freezes during Pause")
	game._resume()
	await create_timer(0.12).timeout
	_check(popup.position.y < pause_y - 0.1 and popup.modulate.a < pause_alpha,
		title + " score popup resumes movement and fade")
	game._exit_to_results()
	await process_frame
	_check(_popup_nodes(game).is_empty(), title + " exiting results removes stale score text")
	game.queue_free()
	await process_frame

	game = _new_game(host, mode)
	var final_target: Array[int] = [0]
	game.pending_valid_lanes = final_target
	var old_round: int = game.round_index
	game._pop_balloon(0)
	_check(game.score == 100 and game.next_round_pending and _popup_texts(game) == ["+100"],
		title + " final correct pop schedules a new question with exactly one popup")
	await create_timer(0.90).timeout
	_check(game.round_index > old_round and game.score == 100 and game.attempts == 1,
		title + " next question preserves scored result and cannot repeat award")
	_check(_popup_nodes(game).is_empty(), title + " popup expires after 0.75s across transitions")
	game.queue_free()
	await process_frame

	game = _new_game(host, mode)
	game.pending_valid_lanes = two_correct
	var wrong_balloon := game.balloons[2] as Area2D
	wrong_balloon.position.y = game._balloon_y()
	game._pop_balloon(2)
	_check(game.score == 0 and game.attempts == 1 and game.correct_count == 0,
		title + " wrong balloon never adds points")
	_check(game.hearts == (2 if mode == "Lives" else 0),
		title + " wrong balloon respects mode-specific hearts")
	_check(_popup_texts(game) == ["+0"], title + " wrong balloon shows +0 once")
	_check(_popup_nodes(game)[0].get_theme_color("font_color") == game.SCORE_ZERO_COLOR,
		title + " zero-point feedback uses Catch dark color")
	game.queue_free()
	await process_frame

	game = _new_game(host, mode)
	var above_line := game.balloons[0] as Area2D
	above_line.position.y = game.UPPER_LINE_Y - 2.0
	var projectile := _fake_projectile(game, Vector2(above_line.position.x, above_line.position.y))
	game._resolve_projectile_balloon_hit(projectile, 0)
	game._resolve_projectile_balloon_hit(projectile, 0)
	_check(_popup_texts(game) == ["+0"], title + " late upper-line burst shows exactly one +0")
	_check(game.score == 0 and game.attempts == 0 and game.balloons[0] == above_line,
		title + " upper-line burst preserves existing no-pop and no-attempt rule")
	game.queue_free()
	await process_frame

	game = _new_game(host, mode)
	projectile = _fake_projectile(game, Vector2(game._lane_x(1), 70.0))
	game._on_projectile_missed(projectile)
	game._on_projectile_missed(projectile)
	_check(_popup_texts(game) == ["+0"], title + " one projectile miss creates one visible +0")
	_check(game.attempts == 1 and game.score == 0,
		title + " projectile miss adds only one attempt and no points")
	_check(game.hearts == (2 if mode == "Lives" else 0),
		title + " projectile miss preserves Hearts/Seconds rules")
	_check(_popup_nodes(game)[0].position.y >= 70.0,
		title + " missed shot text remains on the playfield")
	game.queue_free()
	await process_frame

	game = _new_game(host, mode)
	game._on_question_timeout()
	game._on_question_timeout()
	_check(_popup_texts(game) == ["+0"], title + " timeout shows one +0 for a whole question")
	_check(game.attempts == 0 and game.score == 0 and not game.round_active,
		title + " timeout does not invent a hit/attempt")
	_check(game.hearts == (2 if mode == "Lives" else 0),
		title + " timeout respects mode-specific heart loss")
	game.queue_free()
	await process_frame

	game = _new_game(host, mode)
	if mode == "Seconds":
		game.time_remaining = 0.0
	else:
		game.hearts = 1
	game._on_question_timeout()
	if mode == "Seconds":
		game._finish_round()
	await process_frame
	_check(game.finishing and _popup_nodes(game).is_empty(),
		title + " end-of-game removes feedback and finishes once")
	game.queue_free()
	await process_frame


func _new_game(host: Control, mode: String) -> Control:
	var game := BALLOON_SCENE.instantiate() as Control
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_context({"activity": "Balloon Popping", "game_mode": mode,
		"topic": "Noun", "difficulty": "Normal", "score": 0, "correct": 0,
		"attempts": 0, "balloon_round": 0})
	return game


func _fake_projectile(game: Control, at: Vector2) -> Area2D:
	var projectile := Area2D.new()
	projectile.position = at
	game.projectile_layer.add_child(projectile)
	game.projectiles.append(projectile)
	game.projectile_velocities[projectile] = Vector2(0.0, -100.0)
	return projectile


func _popup_nodes(game: Node) -> Array[Label]:
	var found: Array[Label] = []
	for child in game.get_children():
		if child is Label and child.is_in_group("balloon_score_popup") and not child.is_queued_for_deletion():
			found.append(child as Label)
	return found


func _popup_texts(game: Node) -> Array[String]:
	var texts: Array[String] = []
	for popup in _popup_nodes(game):
		texts.append(popup.text)
	return texts


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
