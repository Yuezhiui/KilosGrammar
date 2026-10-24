extends SceneTree

## True app/router integration. No camera, PostgreSQL, or on-disk student data.
## Verifies Restart Round (not Resume) creates a fresh game for ALL modes.
const MAIN_PATH := "res://main_menu.tscn"
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	# Load only after SceneTree has registered the PoseService autoload.
	var scene := load(MAIN_PATH) as PackedScene
	_check(scene != null, "main menu scene loads")
	if scene == null:
		quit(1)
		return
	var app := scene.instantiate() as Control
	_check(app.has_method("_on_panel_requested"), "router script is attached")
	if not app.has_method("_on_panel_requested"):
		quit(1)
		return
	root.add_child(app)
	await create_timer(1.35).timeout
	for activity in ["Catch the Word", "Balloon Popping", "Human Plane"]:
		for mode in ["Seconds", "Lives"]:
			await _case(app, activity, mode)
	# The main menu intentionally owns active MP3 and WAV sound effects. The
	# real Quit path drains its audio mixer BEFORE freeing the scene; mirror
	# that sequence rather than queue_free() while playback is still active.
	await app.call("prepare_for_shutdown")
	app.queue_free()
	await process_frame
	await process_frame
	print("RESTART FRESH ROUND: ", "PASS" if failures.is_empty() else "FAIL",
		" (%d checks; %d failures)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _case(app: Control, activity: String, mode: String) -> void:
	var label := "%s / %s" % [activity, mode]
	var setup := {"student_id": "QA-RESTART", "student_name": "QA Student",
		"grade_section": "Test Grade", "activity": activity, "topic": "Noun",
		"game_style": "Noun", "game_mode": mode, "difficulty": "Normal",
		"demo_mode": true, "camera_live": false}
	app.call("_on_panel_requested", "gameplay", setup)
	await process_frame
	await process_frame
	var previous := app.get("active_panel") as Control
	var game := previous.get_node_or_null("ActiveMiniGame") as Control if previous else null
	_check(game != null, label + " enters original minigame")
	if game == null:
		return
	game.set("score", 123)
	game.set("time_remaining", 12.0)
	game.set("lives", 1) if activity != "Balloon Popping" else game.set("hearts", 1)
	game.set("attempts", 7)
	if activity == "Catch the Word":
		game.set("used_session_words", {"stale-apple": true})
	elif activity == "Balloon Popping":
		game.set("used_words", {"stale-balloon": true})
	else:
		game.set("used_round_words", {"stale-plane": true})
	# Real game pause request parks its existing gameplay wrapper.
	app.call("_on_panel_requested", "pause", previous.call("get_context"))
	await process_frame
	var pause_panel := app.get("active_panel") as Control
	_check(String(app.get("current_route")) == "pause" and pause_panel != null, label + " opened real Pause")
	if pause_panel == null:
		return
	_check(app.get("paused_game_panel") == previous, label + " original instance parked")
	pause_panel.call("_restart")
	await process_frame
	await process_frame
	var fresh := app.get("active_panel") as Control
	var fresh_game := fresh.get_node_or_null("ActiveMiniGame") as Control if fresh else null
	_check(String(app.get("current_route")) == "gameplay", label + " Restart goes to fresh gameplay")
	_check(fresh != previous and fresh_game != game, label + " Restart DOES NOT resume previous game")
	_check(app.get("paused_game_panel") == null, label + " old game released")
	if fresh_game != null:
		var result := fresh.call("get_context") as Dictionary
		_check(int(result.get("score", -1)) == 0, label + " score reset")
		_check(int(result.get("attempts", -1)) == 0, label + " questions/attempts reset")
		_check(int(result.get("lives", -1)) == 3, label + " three hearts restored")
		_check(float(result.get("time_remaining", -1.0)) >= 59.0 if mode == "Seconds"
			else (activity != "Human Plane" or is_zero_approx(float(result.get("time_remaining", -1.0)))),
			label + " Seconds 60s / Lives untimed reset")
		_check(String(result.get("student_id", "")) == "QA-RESTART", label + " student identity preserved")
		_check(String(fresh.get("guided_stage")) == "countdown", label + " new countdown before gameplay")
		var state: Dictionary = app.get("session_state")
		_check(not state.has("score") and not state.has("time_remaining") and not state.has("catch_used_words") and not state.has("balloon_used_words"),
			label + " stale session state eliminated")
		var history: Dictionary = (
			fresh_game.get("used_session_words") if activity == "Catch the Word" else
			fresh_game.get("used_words") if activity == "Balloon Popping" else fresh_game.get("used_round_words")
		)
		_check(not history.has("stale-apple") and not history.has("stale-balloon") and not history.has("stale-plane"),
			label + " old words/history eliminated")
	app.call("_return_to_main")
	await process_frame
	await process_frame


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("RESTART FRESH ROUND FAIL: ", label)
