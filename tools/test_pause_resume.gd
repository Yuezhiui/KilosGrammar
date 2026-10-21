extends SceneTree

# Integration regression for the live gameplay pause overlay.
# Run:
# Godot --headless --path . --script res://tools/test_pause_resume.gd

const ACTIVITIES: Array[String] = [
	"Catch the Word",
	"Balloon Popping",
	"Human Plane",
]

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://main_menu.tscn") as PackedScene
	if packed == null:
		_fail("Could not load main_menu.tscn")
		_finish()
		return
	var app := packed.instantiate() as Control
	root.add_child(app)
	await create_timer(1.35).timeout

	for activity in ACTIVITIES:
		await _test_live_pause_resume(app, activity, "Seconds")
		if activity != "Human Plane":
			await _test_live_pause_resume(app, activity, "Lives")

	await _test_catch_restart_clears_round(app, "Seconds")
	await _test_catch_restart_clears_round(app, "Lives")
	await _test_catch_results_retry_clears_round(app)
	await _test_pause_results_discards(app)
	await _test_pause_main_discards(app)

	var music: AudioStreamPlayer = app.get("title_music_player")
	if music:
		music.stop()
		music.stream = null
	app.queue_free()
	await process_frame
	await process_frame
	# Allow MP3 playback references from the fast pause/restart fixtures to
	# release before shutting down the headless audio server.
	await create_timer(0.5).timeout
	_finish()


func _test_live_pause_resume(app: Control, activity: String, mode: String) -> void:
	app.call("_on_panel_requested", "gameplay", _game_context(activity, mode))
	await process_frame
	await process_frame
	_assert(String(app.get("current_route")) == "gameplay", "%s entered gameplay" % activity)

	var wrapper := app.get("active_panel") as Control
	var game := wrapper.get_node_or_null("ActiveMiniGame") as Control if wrapper else null
	if wrapper == null or game == null:
		_fail("%s did not mount ActiveMiniGame" % activity)
		return

	# Make Balloon Popping exercise preservation of an actual live projectile.
	if activity == "Balloon Popping" and game.has_method("_launch_projectile"):
		game.call("_launch_projectile")
		await physics_frame
		await process_frame

	var wrapper_id := wrapper.get_instance_id()
	var game_id := game.get_instance_id()
	var before_context := _context_of(wrapper)
	var before_transient := _snapshot_transient(game, activity)

	# ESC from gameplay must go through the minigame pause hook, then park the
	# exact wrapper under the pause overlay.
	app.call("_unhandled_input", _escape_event())
	await process_frame
	_assert(String(app.get("current_route")) == "pause", "%s ESC opens Pause" % activity)
	var pause_panel := app.get("active_panel") as Control
	var parked := app.get("paused_game_panel") as Control
	_assert(pause_panel != null and pause_panel.name == "Pause", "%s shows pause overlay" % activity)
	_assert(parked == wrapper, "%s parks the same gameplay wrapper" % activity)
	_assert(is_instance_valid(wrapper) and wrapper.get_instance_id() == wrapper_id, "%s wrapper instance survives pause" % activity)
	_assert(is_instance_valid(game) and game.get_instance_id() == game_id, "%s minigame instance survives pause" % activity)
	_assert(wrapper.process_mode == Node.PROCESS_MODE_DISABLED, "%s parked gameplay processing is disabled" % activity)

	var paused_context := _context_of(wrapper)
	_assert_core_state_equal(before_context, paused_context, activity + " pause entry")
	_assert_transient_equal(before_transient, _snapshot_transient(game, activity), activity + " pause entry")

	# Nothing in the parked game may continue ticking while the pause overlay is up.
	await create_timer(0.18).timeout
	var frozen_context := _context_of(wrapper)
	_assert_core_state_equal(paused_context, frozen_context, activity + " paused wait")
	_assert_transient_equal(before_transient, _snapshot_transient(game, activity), activity + " paused wait")

	# Use the real Pause RESUME action. It must restore the parked instance,
	# not build another gameplay scene/minigame.
	if pause_panel == null or not pause_panel.has_method("_resume"):
		_fail("%s pause overlay has no _resume action" % activity)
		return
	pause_panel.call("_resume")
	_assert(String(app.get("current_route")) == "gameplay", "%s Resume returns to gameplay" % activity)
	var resumed_wrapper := app.get("active_panel") as Control
	var resumed_game := resumed_wrapper.get_node_or_null("ActiveMiniGame") as Control if resumed_wrapper else null
	_assert(resumed_wrapper == wrapper, "%s Resume restores same gameplay wrapper" % activity)
	_assert(resumed_game == game, "%s Resume restores same minigame instance" % activity)
	_assert(app.get("paused_game_panel") == null, "%s clears parked-game slot on Resume" % activity)
	_assert_transient_equal(before_transient, _snapshot_transient(game, activity), activity + " immediate resume")

	# Seconds mode must resume its countdown; Lives mode has no global countdown,
	# so verify that its gameplay clock restarts without changing the sentinel.
	var resume_time := float(_context_of(wrapper).get("time_remaining", -1.0))
	var resume_progress := 0.0
	var balloon_y_before_resume := 0.0
	if mode == "Lives":
		if activity == "Catch the Word":
			resume_progress = float(game.get("spawn_clock"))
		elif activity == "Balloon Popping":
			resume_progress = float(game.get("round_time_remaining"))
			var slots_before: Array = game.get("balloon_slots")
			if not slots_before.is_empty():
				balloon_y_before_resume = (slots_before[0] as Area2D).position.y
	await create_timer(0.18).timeout
	var ticking_time := float(_context_of(wrapper).get("time_remaining", -1.0))
	if mode == "Lives":
		_assert(is_equal_approx(ticking_time, resume_time), "%s Lives mode has no global countdown" % activity)
		var ticking_progress := 0.0
		if activity == "Catch the Word":
			ticking_progress = float(game.get("spawn_clock"))
		elif activity == "Balloon Popping":
			ticking_progress = float(game.get("round_time_remaining"))
		if activity == "Balloon Popping":
			# A resumed 1.15s entrance is deliberately non-collidable and keeps
			# the question countdown frozen until all three balloons are exposed.
			# Its tween must resume *now*; question progress must resume *later*.
			var slots_after: Array = game.get("balloon_slots")
			_assert(not slots_after.is_empty()
				and (slots_after[0] as Area2D).position.y < balloon_y_before_resume - 1.0,
				"Balloon Popping Lives reveal animation moves after overlay closes")
			var rise_tween := game.get("balloon_motion_tween") as Tween
			if is_instance_valid(rise_tween) and rise_tween.is_running():
				_assert(absf(ticking_progress - resume_progress) < 0.01,
					"Balloon Popping Lives question countdown remains frozen until reveal ends")
				var reveal_deadline := Time.get_ticks_msec() + 2400
				while rise_tween.is_running() and Time.get_ticks_msec() < reveal_deadline:
					await process_frame
				_assert(not rise_tween.is_running(),
					"Balloon Popping Lives 1.15s reveal resumes and finishes after pause")
			await create_timer(0.12).timeout
			var after_reveal := float(game.get("round_time_remaining"))
			_assert(after_reveal < ticking_progress - 0.02,
				"Balloon Popping Lives gameplay countdown resumes after completed reveal")
		else:
			_assert(absf(ticking_progress - resume_progress) > 0.02,
					"%s Lives gameplay resumes after overlay closes" % activity)
	elif resume_time < 0.0 or ticking_time >= resume_time - 0.02:
		_fail("%s Seconds mode did not resume its countdown (%.3f -> %.3f)" % [activity, resume_time, ticking_time])
	else:
		_pass("%s Seconds countdown resumes after overlay closes" % activity)

	# Clear this round before testing the next activity.
	app.call("_return_to_main")
	await process_frame
	await process_frame


func _test_catch_restart_clears_round(app: Control, mode: String) -> void:
	# Starting from Play in the main menu clears the previous session, as it does
	# when a teacher begins a new game through the actual setup flow.
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	app.call("_on_panel_requested", "gameplay", _game_context("Catch the Word", mode))
	await process_frame
	await process_frame
	var old_wrapper := app.get("active_panel") as Control
	var old_game := old_wrapper.get_node_or_null("ActiveMiniGame") as Control if old_wrapper else null
	if old_game == null:
		_fail("Catch restart %s could not open a live minigame" % mode)
		return

	old_game.call("_handle_catch", {"matching": true, "word": "apple"})
	old_game.call("_handle_catch", {"matching": false, "word": "quietly"})
	old_game.set("time_remaining", 42.0)
	await process_frame
	var prior_context := _context_of(old_wrapper)
	_assert(int(prior_context.get("score", 0)) > 0, "Catch %s pre-restart score is nonzero" % mode)
	_assert((prior_context.get("catch_collected_words", []) as Array).size() == 1, "Catch %s pre-restart basket holds an apple" % mode)

	app.call("_unhandled_input", _escape_event())
	await process_frame
	var pause_panel := app.get("active_panel") as Control
	if pause_panel == null or String(app.get("current_route")) != "pause":
		_fail("Catch restart %s could not open pause menu" % mode)
		return
	pause_panel.call("_restart")
	await process_frame
	_assert(String(app.get("current_route")) == "ready", "Catch %s Restart Round opens Ready" % mode)
	var ready := app.get("active_panel") as Control
	if ready == null:
		_fail("Catch restart %s has no Ready screen" % mode)
		return
	ready.call("_start_countdown")
	await create_timer(2.8).timeout
	await process_frame
	_assert(String(app.get("current_route")) == "gameplay", "Catch %s restart enters gameplay again" % mode)
	var new_wrapper := app.get("active_panel") as Control
	var new_game := new_wrapper.get_node_or_null("ActiveMiniGame") as Control if new_wrapper else null
	if new_game == null:
		_fail("Catch restart %s did not create a new minigame" % mode)
		return
	_assert(new_game != old_game, "Catch %s restart uses a fresh minigame" % mode)
	var new_context := _context_of(new_wrapper)
	var apple_layer := new_game.get_node("CharacterRig/CollectedWords") as Node2D
	_assert((new_context.get("catch_collected_words", []) as Array).is_empty(), "Catch %s restart clears saved apple words" % mode)
	_assert(apple_layer.get_child_count() == 0, "Catch %s restart has no visible basket apples" % mode)
	_assert(int(new_context.get("score", -1)) == 0, "Catch %s restart resets score" % mode)
	_assert(int(new_context.get("correct", -1)) == 0 and int(new_context.get("attempts", -1)) == 0, "Catch %s restart resets statistics" % mode)
	_assert(int(new_context.get("streak", -1)) == 0 and int(new_context.get("best_streak", -1)) == 0, "Catch %s restart resets streaks" % mode)
	_assert(int(new_context.get("lives", -1)) == 3, "Catch %s restart resets lives" % mode)
	var expected_time := 60.0 if mode == "Seconds" else 999.0
	_assert(absf(float(new_context.get("time_remaining", -1.0)) - expected_time) < 1.0, "Catch %s restart resets the timer" % mode)
	app.call("_return_to_main")
	await process_frame
	await process_frame


func _test_catch_results_retry_clears_round(app: Control) -> void:
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	app.call("_on_panel_requested", "gameplay", _game_context("Catch the Word", "Seconds"))
	await process_frame
	await process_frame
	var wrapper := app.get("active_panel") as Control
	var game := wrapper.get_node_or_null("ActiveMiniGame") as Control if wrapper else null
	if game == null:
		_fail("Catch Results Retry could not open a minigame")
		return
	game.call("_handle_catch", {"matching": true, "word": "apple"})
	game.call("_finish_round")
	await process_frame
	_assert(String(app.get("current_route")) == "results", "Catch completed round opens Results")
	var results := app.get("active_panel") as Control
	if results == null:
		_fail("Catch Results Retry has no Results screen")
		return
	results.call("_request", "student_setup")
	await process_frame
	_assert(String(app.get("current_route")) == "student_setup", "Catch Results Retry opens student setup")
	var fresh_context: Dictionary = app.get("session_state")
	_assert(not fresh_context.has("catch_collected_words"), "Catch Results Retry clears saved apple words")
	_assert(not fresh_context.has("score") and not fresh_context.has("time_remaining"), "Catch Results Retry clears round score and time")
	app.call("_return_to_main")
	await process_frame
	await process_frame


func _test_pause_results_discards(app: Control) -> void:
	app.call("_on_panel_requested", "gameplay", _game_context("Catch the Word"))
	await process_frame
	await process_frame
	var wrapper := app.get("active_panel") as Control
	var game := wrapper.get_node_or_null("ActiveMiniGame") as Control if wrapper else null
	app.call("_unhandled_input", _escape_event())
	await process_frame
	var pause_panel := app.get("active_panel") as Control
	if pause_panel == null:
		_fail("Pause -> Results had no pause overlay")
		return
	pause_panel.call("_results")
	await process_frame
	await process_frame
	_assert(String(app.get("current_route")) == "results", "Pause -> Results reaches Results")
	_assert(app.get("paused_game_panel") == null, "Pause -> Results clears parked-game slot")
	_assert(not is_instance_valid(wrapper), "Pause -> Results frees parked gameplay wrapper")
	_assert(not is_instance_valid(game), "Pause -> Results frees parked minigame instance")
	app.call("_return_to_main")
	await process_frame
	await process_frame


func _test_pause_main_discards(app: Control) -> void:
	app.call("_on_panel_requested", "gameplay", _game_context("Human Plane"))
	await process_frame
	await process_frame
	var wrapper := app.get("active_panel") as Control
	var game := wrapper.get_node_or_null("ActiveMiniGame") as Control if wrapper else null
	app.call("_unhandled_input", _escape_event())
	await process_frame
	var pause_panel := app.get("active_panel") as Control
	if pause_panel == null:
		_fail("Pause -> Main had no pause overlay")
		return
	pause_panel.call("_main_menu")
	await process_frame
	await process_frame
	_assert(String(app.get("current_route")) == "main", "Pause -> Main reaches Main")
	_assert(app.get("paused_game_panel") == null, "Pause -> Main clears parked-game slot")
	_assert(not is_instance_valid(wrapper), "Pause -> Main frees parked gameplay wrapper")
	_assert(not is_instance_valid(game), "Pause -> Main frees parked minigame instance")
	var panel_host := app.get("panel_host") as Control
	_assert(panel_host != null and panel_host.get_child_count() == 0, "Pause -> Main leaves no stale panel children")

	# Starting again after discard must create a clean, unrelated instance.
	app.call("_on_panel_requested", "gameplay", _game_context("Human Plane"))
	await process_frame
	await process_frame
	var fresh_wrapper := app.get("active_panel") as Control
	var fresh_game := fresh_wrapper.get_node_or_null("ActiveMiniGame") as Control if fresh_wrapper else null
	_assert(fresh_wrapper != null and fresh_wrapper != wrapper, "New gameplay after discard uses a fresh wrapper")
	_assert(fresh_game != null and fresh_game != game, "New gameplay after discard uses a fresh minigame")
	var fresh_context := _context_of(fresh_wrapper)
	_assert(int(fresh_context.get("score", -1)) == 0, "New gameplay after discard has no stale score")
	_assert(int(fresh_context.get("attempts", -1)) == 0, "New gameplay after discard has no stale attempts")
	app.call("_return_to_main")
	await process_frame
	await process_frame


func _snapshot_transient(game: Control, activity: String) -> Dictionary:
	match activity:
		"Catch the Word":
			return {
				"falling_tiles": (game.get("falling_tiles") as Array).duplicate(true),
				"basket_x": float(game.get("basket_x")),
				"spawn_clock": float(game.get("spawn_clock")),
			}
		"Balloon Popping":
			var projectile_ids: Array[int] = []
			var projectile_positions: Array[Vector2] = []
			for projectile in (game.get("projectiles") as Array):
				if is_instance_valid(projectile):
					projectile_ids.append(projectile.get_instance_id())
					projectile_positions.append(projectile.position)
			var balloon_ids: Array[int] = []
			for balloon in (game.get("balloons") as Array):
				if is_instance_valid(balloon):
					balloon_ids.append(balloon.get_instance_id())
			return {
				"round_index": int(game.get("round_index")),
				"round_time_remaining": float(game.get("round_time_remaining")),
				"valid_lanes": (game.get("valid_lanes") as Array).duplicate(),
				"pending_valid_lanes": (game.get("pending_valid_lanes") as Array).duplicate(),
				"prompt": String((game.get("prompt_label") as Label).text),
				"balloon_ids": balloon_ids,
				"projectile_ids": projectile_ids,
				"projectile_positions": projectile_positions,
			}
		"Human Plane":
			return {
				"round_data": (game.get("round_data") as Dictionary).duplicate(true),
				"gate_progress": float(game.get("gate_progress")),
				"gate_resolved": bool(game.get("gate_resolved")),
				"selected_lane": int(game.get("selected_lane")),
				"inter_wave_delay": float(game.get("inter_wave_delay")),
				"plane_x_norm": float(game.get("plane_x_norm")),
			}
	return {}


func _assert_transient_equal(expected: Dictionary, actual: Dictionary, label: String) -> void:
	if expected.keys() != actual.keys():
		_fail("%s transient keys changed" % label)
		return
	for key in expected:
		var left = expected[key]
		var right = actual[key]
		if left is float or right is float:
			if absf(float(left) - float(right)) > 0.005:
				_fail("%s transient %s changed: %s -> %s" % [label, key, str(left), str(right)])
				return
		elif left != right:
			_fail("%s transient %s changed" % [label, key])
			return
	_pass("%s preserves transient gameplay state" % label)


func _assert_core_state_equal(expected: Dictionary, actual: Dictionary, label: String) -> void:
	for key in ["score", "correct", "attempts", "lives"]:
		if int(expected.get(key, 0)) != int(actual.get(key, 0)):
			_fail("%s changed %s: %s -> %s" % [label, key, str(expected.get(key)), str(actual.get(key))])
			return
	var expected_time := float(expected.get("time_remaining", -1.0))
	var actual_time := float(actual.get("time_remaining", -2.0))
	if expected_time < 0.0 or absf(expected_time - actual_time) > 0.005:
		_fail("%s changed time_remaining: %.3f -> %.3f" % [label, expected_time, actual_time])
		return
	_pass("%s preserves stats and timer" % label)


func _context_of(wrapper: Control) -> Dictionary:
	if wrapper != null and wrapper.has_method("get_context"):
		var value = wrapper.call("get_context")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}


func _game_context(activity: String, mode: String = "Lives") -> Dictionary:
	return {
		"activity": activity,
		"topic": "Noun",
		"game_style": "Noun",
		"game_mode": mode,
		"difficulty": "Normal",
		"student_id": "QA-PAUSE",
		"demo_mode": true,
		"database_connected": false,
		"camera_live": false,
	}


func _escape_event() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	event.echo = false
	return event


func _assert(condition: bool, label: String) -> void:
	if condition:
		_pass(label)
	else:
		_fail(label)


func _pass(label: String) -> void:
	checks += 1
	print("PASS  ", label)


func _fail(reason: String) -> void:
	failures.append(reason)


func _finish() -> void:
	if failures.is_empty():
		print("PASS  pause/resume overlay regression: %d checks" % checks)
		quit(0)
	else:
		for reason in failures:
			push_error("PAUSE QA: " + reason)
		quit(1)
