extends SceneTree

# Godot 4.7.2:
# --headless --path . --script res://tools/test_catch_seconds_layering.gd
# Exercises the Seconds/Lives timer contract and runtime score draw order.

const CATCH_SCENE := preload("res://ui/minigames/catch_word.tscn")
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1600, 900)]
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport_size in VIEWPORTS:
		root.size = viewport_size
		await process_frame
		var host := Control.new()
		host.size = Vector2(viewport_size)
		root.add_child(host)
		var game := _new_game(host)
		await process_frame
		game.set_process(false)
		game.set_context({"game_mode": "Seconds", "time_remaining": 999.0})
		_check(is_equal_approx(game.time_remaining, 60.0), "%s fresh Seconds inherits 999" % viewport_size)
		_check(game.time_label.text == "60s", "%s fresh Seconds label is not 60s" % viewport_size)
		_check(game.is_seconds_mode and not game.is_lives_mode, "%s Seconds flags" % viewport_size)
		_check(game.character_rig.z_index == 0, "%s character is not at requested z_index 0" % viewport_size)
		_check(game.falling_word_layer.z_index == 1, "%s falling apples must render at z_index 1" % viewport_size)
		_check(game.score_draw_layer != null and game.score_draw_layer.z_index < game.character_rig.z_index,
			"%s score must remain behind the character" % viewport_size)
		_check(game.score_plaque.get_parent() == game.score_draw_layer, "%s plaque is not in score layer" % viewport_size)
		_check(game.score_bottom_container.get_parent() == game.score_draw_layer, "%s number is not in score layer" % viewport_size)
		_check(game.score_draw_layer.get_parent() == game, "%s score remains on high HUD CanvasLayer" % viewport_size)
		# The score moves canvas, but retains its HUD-scaled viewport geometry.
		var expected_score_pos: Vector2 = game.hud.get_global_transform_with_canvas() * game.score_plaque.position
		var actual_score_pos: Vector2 = game.score_plaque.get_global_transform_with_canvas().origin
		_check(actual_score_pos.distance_to(expected_score_pos) < 1.0,
			"%s score position drifted: %s vs %s" % [viewport_size, actual_score_pos, expected_score_pos])
		var expected_score_size: Vector2 = game.score_plaque.size * game.hud.scale
		var actual_score_size: Vector2 = game.score_plaque.size * game.score_plaque.get_global_transform_with_canvas().get_scale()
		_check(actual_score_size.distance_to(expected_score_size) < 1.0,
			"%s score size drifted" % viewport_size)
		game.call("_update_timer", 13.0)
		_check(is_equal_approx(game.time_remaining, 47.0), "%s Seconds countdown" % viewport_size)
		game.call("_pause")
		var paused_remaining: float = game.time_remaining
		await create_timer(0.1).timeout
		_check(is_equal_approx(game.time_remaining, paused_remaining), "%s paused Seconds still ticks" % viewport_size)
		var pause_snapshot: Dictionary = game.get_context()
		game.call("_resume")
		_check(game.round_running, "%s cannot resume Seconds" % viewport_size)
		var resumed := _new_game(host)
		resumed.set_process(false)
		resumed.set_context(pause_snapshot)
		_check(is_equal_approx(resumed.time_remaining, paused_remaining), "%s pause snapshot did not restore timer" % viewport_size)
		resumed.set_context({"game_mode": "Seconds", "time_remaining": 999.0, "round_running": true})
		_check(is_equal_approx(resumed.time_remaining, 60.0), "%s corrupt resume was not clamped" % viewport_size)
		resumed.set_context({"game_mode": "Seconds"})
		_check(is_equal_approx(resumed.time_remaining, 60.0), "%s restart Seconds was not reset" % viewport_size)
		resumed.set_context({"game_mode": "Lives", "lives": 3, "time_remaining": 999.0})
		_check(resumed.is_lives_mode and not resumed.is_seconds_mode, "%s Lives mode flags" % viewport_size)
		var lives_remaining: float = resumed.time_remaining
		resumed.call("_update_timer", 50.0)
		_check(is_equal_approx(resumed.time_remaining, lives_remaining) and resumed.lives == 3,
			"%s Lives mode incorrectly uses countdown" % viewport_size)
		resumed.queue_free()
		game.queue_free()
		host.queue_free()
		await process_frame
	if failures.is_empty():
		print("PASS: Catch Seconds/Lives timers, pause/restart and 0/1 score/player draw order (", checks, " checks)")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _new_game(host: Control) -> Control:
	var game := CATCH_SCENE.instantiate() as Control
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return game


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
