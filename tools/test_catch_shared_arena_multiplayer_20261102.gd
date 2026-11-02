extends SceneTree

# Godot --headless --path . --script res://tools/test_catch_shared_arena_multiplayer_20261102.gd
# Real scene, synthetic two-player steering/catches. No webcam, DB, or network.
const SCENE := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const MAIN_MENU_PATH := "res://ui/main_menu/main_menu.gd"
const CHARS := ["Bear", "Cat", "Dog", "Lion", "Panda"]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for character in CHARS:
		await _test_match(character)
	await _test_recovery_and_completion_gate()
	await _test_lives_completion_gate()
	await _test_inactive_overlap_arbitration()
	await _test_solo_restoration()
	for issue in failures.slice(0, 30):
		printerr("TWO PLAYER CATCH: ", issue)
	print("CATCH TWO PLAYER PILOT: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _make_game() -> Control:
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return game


func _test_match(character: String) -> void:
	var game := _make_game()
	await process_frame
	game.set_process(false)
	var original: Dictionary = {}
	for animal in CHARS:
		original[animal] = {
			"body": (game.get_node(animal + "/Body") as Sprite2D).position,
			"basket": (game.get_node(animal + "/Basket") as Sprite2D).position
		}
	game.set_context({
		"player_mode": "Multiplayer", "multiplayer": true,
		"topic": "Noun", "difficulty": "Hard", "game_mode": "Seconds",
		"catch_character": character, "player2_catch_character": character,
		"player2_student_id": "TEST-P2", "player2_student_name": "Student Two",
		"player2_grade_section": "Grade 5-A"
	})
	game.set_process(false)
	_check(game.multiplayer_enabled and game.is_seconds_mode and not game.is_lives_mode,
		character + ": two-player forces common 60s round")
	_check(is_equal_approx(game.time_remaining, 60.0) and game.lives == 3 and game.player2_lives == 3,
		character + ": independent three-heart capacity and shared timer")
	_check(game.selected_character == character and game.player2_character != character,
		character + ": two distinct existing characters")
	_check((game.get_node(character) as Node2D).visible and
		(game.get_node(game.player2_character) as Node2D).visible,
		character + ": both original animals visible")
	_check(game.multiplayer_board.visible and not game.score_draw_layer.visible,
		character + ": editor-authored dual HUD replaces ambiguous solo score art")
	_check(game.falling_tiles.size() == 3 and game.wave_phase == "falling",
		character + ": one three-apple arena")
	var p1_start: float = game.basket_x
	var p2_start: float = game.player2_basket_x
	game.set_multiplayer_body_x(0, 1.0)
	game.set_multiplayer_body_x(1, -1.0)
	game._update_basket(0.2)
	game._sync_character_position()
	game._sync_player2_position()
	_check(game.basket_x > p1_start and game.player2_basket_x < p2_start,
		character + ": P1 and P2 respond independently to signed velocity")
	game.clear_multiplayer_body_input(0)
	game.clear_multiplayer_body_input(1)
	var frozen_p1: float = game.basket_x
	var frozen_p2: float = game.player2_basket_x
	game._update_basket(0.4)
	_check(is_equal_approx(game.basket_x, frozen_p1) and
		is_equal_approx(game.player2_basket_x, frozen_p2),
		character + ": missing poses freeze each basket, not the clock")
	game._update_timer(0.4)
	_check(is_equal_approx(game.time_remaining, 59.6) and not game.round_finished,
		character + ": no global pause on pose loss")
	# Force an apple into stationary, temporarily untracked P1 hitbox: MUST
	# NOT score, then only P1 becomes tracked and can select it.
	var p1_basket: Rect2 = game._multiplayer_basket_rect(0)
	_set_correct_at(game, p1_basket.get_center())
	game._update_tiles(0.0)
	_check(game.score == 0 and game.player2_score == 0 and game.wave_phase == "falling",
		character + ": absent P1 cannot ghost-catch")
	game.set_multiplayer_body_x(0, 0.0)
	game._update_tiles(0.0)
	_check(game.score == 100 and game.player2_score == 0 and
		game.correct_count == 1 and game.player2_correct == 0,
		character + ": P1 correct apple credits P1 only")
	_check(game.wave_phase == "clearing" and game.falling_tiles.size() == 2,
		character + ": one catch retires the wave for both players")
	_advance_wave(game)
	# P2 now receives next word while P1's pose is inactive.
	game.clear_multiplayer_body_input(0)
	game.set_multiplayer_body_x(1, 0.0)
	_set_correct_at(game, game._multiplayer_basket_rect(1).get_center())
	game._update_tiles(0.0)
	_check(game.score == 100 and game.player2_score == 100 and
		game.correct_count == 1 and game.player2_correct == 1,
		character + ": P2 correct apple credits P2 only")
	_advance_wave(game)
	_set_wrong_at(game, game._multiplayer_basket_rect(1).get_center())
	game._update_tiles(0.0)
	_check(game.player2_lives == 2 and game.lives == 3 and game.player2_score == 100,
		character + ": P2 wrong apple costs ONLY P2 one heart/zero score")
	_advance_wave(game)
	# Both baskets overlap an apple; tie goes to P1 exactly once.
	game.basket_x = 640.0
	game.player2_basket_x = 640.0
	game._sync_character_position()
	game._sync_player2_position()
	game.set_multiplayer_body_x(0, 0.0)
	game.set_multiplayer_body_x(1, 0.0)
	var overlap: Vector2 = game._multiplayer_basket_rect(0).get_center()
	_set_correct_at(game, overlap)
	var prior_total: int = game.score + game.player2_score
	game._update_tiles(0.0)
	_check(game.score + game.player2_score == prior_total + 100,
		character + ": simultaneous overlap never doubles apple score")
	_check(game.score == 200 and game.player2_score == 100,
		character + ": deterministic overlap arbitration")
	var payload: Dictionary = game._result_payload()
	_check(payload.get("player1_score") == 200 and payload.get("player2_score") == 100 and
		payload.get("score") == 200 and payload.get("player2_lives") == 2,
		character + ": exact per-player score/heart attribution")
	_check(payload.get("player2_student_id") == "TEST-P2" and
		payload.get("player2_student_name") == "Student Two" and
		payload.get("player2_grade_section") == "Grade 5-A",
		character + ": P2 student identity retained in results")
	_check(payload.get("multiplayer_result_provisional") and
		payload.get("player_mode") == "Multiplayer",
		character + ": P2 backend persistence not falsely claimed")
	# Zero hearts disables just that student's basket. The other student and
	# common clock continue, even when both tracking inputs are present.
	_advance_wave(game)
	game.player2_lives = 0
	game.clear_multiplayer_body_input(0)
	var score_before_knockout: int = game.player2_score
	_set_correct_at(game, game._multiplayer_basket_rect(1).get_center())
	game._update_tiles(0.0)
	_check(game.player2_score == score_before_knockout and game.wave_phase == "falling",
		character + ": knocked-out P2 cannot receive ghost points")
	_check(not game.round_finished and game.time_remaining > 0.0,
		character + ": knocked-out child never pauses other student")
	game.player2_lives = 2
	game._update_timer(70.0)
	_check(game.round_finished and game.finish_reason == "time_up" and
		game.time_remaining == 0.0, character + ": shared 60s end")
	for animal in CHARS:
		_check((game.get_node(animal + "/Body") as Sprite2D).position == original[animal]["body"] and
			(game.get_node(animal + "/Basket") as Sprite2D).position == original[animal]["basket"],
			character + ": original cropped animal art untouched " + animal)
	game._stop_voice_feedback()
	game.queue_free()
	await process_frame


func _advance_wave(game: Control) -> void:
	game._update_spawning(game.WAVE_CLEAR_SECONDS + 0.01)


func _set_correct_at(game: Control, position: Vector2) -> void:
	_set_at(game, position, true)


func _set_wrong_at(game: Control, position: Vector2) -> void:
	_set_at(game, position, false)


func _set_at(game: Control, position: Vector2, matching: bool) -> void:
	for i in range(game.falling_tiles.size()):
		var tile: Dictionary = game.falling_tiles[i]
		if bool(tile["matching"]) == matching:
			tile["pos"] = position
			game.falling_tiles[i] = tile
			return


func _test_solo_restoration() -> void:
	var game := _make_game()
	await process_frame
	game.set_process(false)
	game.set_context({"topic": "Noun", "difficulty": "Normal",
		"game_mode": "Seconds", "catch_character": "Bear"})
	game.set_process(false)
	_check(not game.multiplayer_enabled and not game.multiplayer_board.visible and
		game.score_draw_layer.visible, "solo: original score art displayed")
	_check((game.get_node("Bear") as Node2D).visible and
		not (game.get_node("Cat") as Node2D).visible,
		"solo: only one animal visible")
	_check(game.base_fall_speed == 102.0 and game.lives == 3 and
		game.time_remaining == 60.0, "solo: normal speed, hearts, timer unchanged")
	game.set_multiplayer_body_x(1, 1.0)
	_check(not game.player2_input_active, "solo: P2 API ignored")
	# Only LIVE camera solo sessions gate scoring while input is absent;
	# ordinary non-camera/demo collision tests retain historical behavior.
	game.set_context({"topic": "Noun", "difficulty": "Easy",
		"game_mode": "Seconds", "catch_character": "Bear", "camera_live": true})
	game.clear_body_input()
	_set_correct_at(game, game._basket_rect().get_center())
	game._update_tiles(0.0)
	_check(game.score == 0 and game.wave_phase == "falling",
		"live solo: absent camera input cannot ghost-catch a word")
	game.set_body_x(0.0)
	game._update_tiles(0.0)
	_check(game.score == 100 and game.wave_phase == "clearing",
		"live solo: actual verified input allows catch")
	game._stop_voice_feedback()
	game.queue_free()
	await process_frame


func _test_recovery_and_completion_gate() -> void:
	var game := _make_game()
	await process_frame
	game.set_process(false)
	game.set_context({
		"player_mode": "Multiplayer", "multiplayer": true,
		"topic": "Verb", "difficulty": "Normal", "game_mode": "Seconds",
		"catch_character": "Bear", "player2_catch_character": "Cat",
		"student_id": "TEST-P1", "student_name": "Student One",
		"grade_section": "Grade 5-A",
		"player2_student_id": "TEST-P2", "player2_student_name": "Student Two",
		"player2_grade_section": "Grade 5-B"
	})
	game.set_process(false)
	_check(game.game_mode == "Seconds" and game.is_seconds_mode,
		"main_menu: selected Seconds remains a shared 60s multiplayer round")
	# A Seconds competitive match still uses independently depleting hearts.
	# Paused snapshots must preserve both players' heart counts.
	game.score = 300
	game.correct_count = 3
	game.lives = 1
	game.player2_score = 200
	game.player2_correct = 2
	game.player2_lives = 2
	game.player2_attempts = 4
	game.player2_streak = 1
	game.player2_best_streak = 2
	game.time_remaining = 37.5
	game._pause()
	var pause_payload: Dictionary = game._result_payload()
	_check(pause_payload.get("round_completed") == false and
		pause_payload.get("player_mode") == "Multiplayer",
		"recovery: pause is NOT a completed score")
	_check(pause_payload.get("score") == 300 and pause_payload.get("player2_score") == 200,
		"recovery: distinct player scores in pause snapshot")
	_check(pause_payload.get("lives") == 1 and pause_payload.get("player2_lives") == 2,
		"recovery: separate P1 and P2 lives in pause snapshot")
	_check(pause_payload.get("player2_student_id") == "TEST-P2" and
		pause_payload.get("player2_student_name") == "Student Two" and
		pause_payload.get("player2_grade_section") == "Grade 5-B",
		"recovery: P2 identity is preserved for distinct score journal")
	# Simulate reconstruction of a minigame from a previous paused payload.
	game.set_context(pause_payload)
	game.set_process(false)
	_check(game.score == 300 and game.player2_score == 200,
		"recovery: resume restores BOTH independent scores")
	_check(game.lives == 1 and game.player2_lives == 2,
		"recovery: resume restores BOTH independent hearts without refill")
	_check(game.player2_attempts == 4 and game.player2_streak == 1 and
		game.player2_best_streak == 2 and game.player2_correct == 2,
		"recovery: resume restores P2 stats")
	_check(is_equal_approx(game.time_remaining, 37.5) and
		game.is_seconds_mode and not game.round_finished,
		"recovery: resume preserves shared clock and Seconds mode")
	_check(not game.body_input_active and not game.player2_input_active,
		"recovery: no stale camera input after restoring session")
	var menu_script := load(MAIN_MENU_PATH) as Script
	_check(menu_script != null and menu_script.can_instantiate(),
		"main_menu: real completion validator can load in gameplay test")
	if menu_script == null or not menu_script.can_instantiate():
		game._stop_voice_feedback()
		game.queue_free()
		await process_frame
		return
	var menu := menu_script.new() as Control
	_check(not bool(menu.call("_valid_round_completion", pause_payload)),
		"main_menu: pause snapshot cannot be saved as completed round")
	# A completed round only reports time_up AFTER the shared 60s clock hits 0.
	game._update_timer(38.0)
	var completed: Dictionary = game._result_payload()
	_check(game.round_finished and game.round_completed and
		completed.get("game_mode") == "Seconds" and
		completed.get("completion_reason") == "time_up" and
		float(completed.get("time_remaining", -1.0)) == 0.0,
		"main_menu: valid shared-time completion evidence")
	_check(bool(menu.call("_valid_round_completion", completed)),
		"main_menu: accepts completed shared 60s multiplayer round")
	_check(completed.get("score") == 300 and
		completed.get("player2_score") == 200 and
		completed.get("player2_student_id") == "TEST-P2" and
		completed.get("player2_student_name") == "Student Two" and
		completed.get("player2_grade_section") == "Grade 5-B",
		"recovery: completed payload carries both journal scores and P2 identity")
	var fake_lives: Dictionary = completed.duplicate(true)
	fake_lives["game_mode"] = "Lives"
	_check(not bool(menu.call("_valid_round_completion", fake_lives)),
		"main_menu: rejects time_up if game_mode does not match Seconds")
	var fake_reason: Dictionary = completed.duplicate(true)
	fake_reason["completion_reason"] = "lives_empty"
	_check(not bool(menu.call("_valid_round_completion", fake_reason)),
		"main_menu: rejects lives_empty when multiplayer game_mode is Seconds")
	menu.free()
	game._stop_voice_feedback()
	game.queue_free()
	await process_frame


func _test_lives_completion_gate() -> void:
	var game := _make_game()
	await process_frame
	game.set_process(false)
	game.set_context({
		"player_mode": "Multiplayer", "multiplayer": true,
		"topic": "Noun", "difficulty": "Easy", "game_mode": "Lives",
		"catch_character": "Dog", "player2_catch_character": "Panda",
		"student_id": "TEST-P1", "student_name": "Student One",
		"grade_section": "Grade 5-A",
		"player2_student_id": "TEST-P2", "player2_student_name": "Student Two",
		"player2_grade_section": "Grade 5-B"
	})
	game.set_process(false)
	var menu_script := load(MAIN_MENU_PATH) as Script
	_check(menu_script != null and menu_script.can_instantiate(),
		"main_menu: real Lives validator can load in gameplay test")
	if menu_script == null or not menu_script.can_instantiate():
		game._stop_voice_feedback()
		game.queue_free()
		await process_frame
		return
	var menu := menu_script.new() as Control
	_check(game.game_mode == "Lives" and game.is_lives_mode and
		not game.is_seconds_mode and game.time_remaining == 0.0,
		"main_menu: multiplayer teacher-selected Lives mode is preserved")
	_check(game.lives == 3 and game.player2_lives == 3,
		"main_menu: both competitors independently start with three hearts")
	game.set_multiplayer_body_x(0, 0.0)
	game.clear_multiplayer_body_input(1)
	for hit in range(3):
		_set_wrong_at(game, game._multiplayer_basket_rect(0).get_center())
		game._update_tiles(0.0)
		_check(game.lives == 2 - hit and game.player2_lives == 3,
			"main_menu: wrong P1 hit %d only reduces P1 hearts" % hit)
		_check(not game.round_finished and not game.round_completed and
			game.finish_reason.is_empty(), "main_menu: P1 depletion cannot end multiplayer Lives")
		_advance_wave(game)
	_check(game.lives == 0 and game.player2_lives == 3 and
		not game.round_finished, "main_menu: zero P1 hearts still allows P2 to continue")
	var half_done: Dictionary = game._result_payload()
	_check(not bool(menu.call("_valid_round_completion", half_done)),
		"main_menu: cannot persist a Lives round with only P1 depleted")
	game.clear_multiplayer_body_input(0)
	game.set_multiplayer_body_x(1, 0.0)
	for hit in range(3):
		_set_wrong_at(game, game._multiplayer_basket_rect(1).get_center())
		game._update_tiles(0.0)
		_check(game.player2_lives == 2 - hit and game.lives == 0,
			"main_menu: wrong P2 hit %d only reduces P2 hearts" % hit)
		if hit < 2:
			_check(not game.round_finished,
				"main_menu: P2 with remaining hearts keeps match alive")
			_advance_wave(game)
	_check(game.round_finished and game.round_completed and
		game.finish_reason == "lives_empty" and
		game.lives == 0 and game.player2_lives == 0,
		"main_menu: lives_empty can occur only when BOTH players have zero hearts")
	var complete: Dictionary = game._result_payload()
	_check(complete.get("game_mode") == "Lives" and
		complete.get("completion_reason") == "lives_empty" and
		complete.get("lives") == 0 and complete.get("player2_lives") == 0,
		"main_menu: Lives completion proof has outer lives=0 and P2 lives=0")
	_check(bool(menu.call("_valid_round_completion", complete)),
		"main_menu: accepts finished multiplayer Lives round for P1/P2 journal")
	_check(complete.get("player2_score") == 0 and
		complete.get("player2_student_id") == "TEST-P2" and
		complete.get("player2_student_name") == "Student Two" and
		complete.get("player2_grade_section") == "Grade 5-B",
		"recovery: both zero-score Lives students still have independent identities")
	var fake_timed := complete.duplicate(true)
	fake_timed["completion_reason"] = "time_up"
	_check(not bool(menu.call("_valid_round_completion", fake_timed)),
		"main_menu: rejects time_up when game_mode is Lives")
	menu.free()
	game._stop_voice_feedback()
	game.queue_free()
	await process_frame


func _test_inactive_overlap_arbitration() -> void:
	var game := _make_game()
	await process_frame
	game.set_process(false)
	game.set_context({
		"player_mode": "Multiplayer", "multiplayer": true,
		"topic": "Noun", "game_mode": "Seconds", "catch_character": "Dog",
		"player2_catch_character": "Panda"
	})
	game.set_process(false)
	game.basket_x = 650.0
	game.player2_basket_x = 650.0
	game._sync_character_position()
	game._sync_player2_position()
	game.clear_multiplayer_body_input(0)
	game.clear_multiplayer_body_input(1)
	_set_correct_at(game, game._multiplayer_basket_rect(0).get_center())
	game._update_tiles(0.0)
	_check(game.score == 0 and game.player2_score == 0 and game.wave_phase == "falling",
		"collision: overlapping stationary baskets score ZERO when both inputs inactive")
	# P1 is absent; P2 alone can collect the apple even at exactly the same X.
	game.set_multiplayer_body_x(1, 0.0)
	game._update_tiles(0.0)
	_check(game.score == 0 and game.player2_score == 100,
		"collision: inactive P1 never steals an active P2 apple")
	_advance_wave(game)
	game.set_multiplayer_body_x(0, 0.0)
	game.clear_multiplayer_body_input(1)
	_set_correct_at(game, game._multiplayer_basket_rect(1).get_center())
	game._update_tiles(0.0)
	_check(game.score == 100 and game.player2_score == 100,
		"collision: inactive P2 never steals an active P1 apple")
	_advance_wave(game)
	# Lost-tracking sentinel must clear the input flag rather than being
	# clamped to -1 and retained as a ghost owner.
	game.set_multiplayer_body_x(0, -999.0)
	game.set_multiplayer_body_x(1, -999.0)
	_check(not game.body_input_active and not game.player2_input_active,
		"collision: -999 from PoseService clears each tracked input")
	_set_correct_at(game, game._multiplayer_basket_rect(1).get_center())
	game._update_tiles(0.0)
	_check(game.score == 100 and game.player2_score == 100 and
		game.wave_phase == "falling",
		"collision: no apple attributed after both PoseService inputs go inactive")
	game._stop_voice_feedback()
	game.queue_free()
	await process_frame


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
