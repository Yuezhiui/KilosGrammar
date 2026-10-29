extends SceneTree

# No sockets, database, teacher records or physical webcam. MainMenu runs
# against the existing deterministic no-socket client fixture.
const MENU_PATH := "res://ui/main_menu/main_menu.tscn"
const MOCK_MENU_SCRIPT_PATH := "res://tools/test_postgres_csv_delete_menu_fixture.gd"
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(15.0).timeout
	_check(false, "No-persistence / Credits regression exceeded watchdog")
	quit(1)


func _run() -> void:
	var app := (load(MENU_PATH) as PackedScene).instantiate() as Control
	app.set_script(load(MOCK_MENU_SCRIPT_PATH) as Script)
	root.add_child(app)
	await process_frame
	var db := app.get("database_client") as Node
	_check(db != null and db.has_method("count"), "No-socket mock database installed")
	var credits := app.get_node_or_null("MainLayer/LeftMenu/Credits") as Button
	_check(credits != null and credits.is_visible_in_tree(), "Restored Credits PNG button is editable on main menu")
	if credits != null:
		credits.pressed.emit()
		await process_frame
		_check(String(app.get("current_route")) == "credits"
			and (app.get("active_panel") as Control) != null, "Credits opens its original real scene")
		var back := (app.get("active_panel") as Control).get_node_or_null("%BackButton") as Button
		if back != null:
			back.pressed.emit()
			await process_frame
		_check(String(app.get("current_route")) == "main", "Credits Back returns to Main Menu")

	app.set("database_online", true)
	app.call("_on_panel_requested", "tutorial_home", {})
	await process_frame
	app.call("_on_panel_requested", "play_activity",
		{"guided_tutorial": true, "entry_source": "tutorial"})
	await process_frame
	app.set("current_route", "student_setup")
	app.call("_on_panel_requested", "play_activity",
		{"student_id": "NO-WRITE-TUTORIAL", "student_name": "Practice",
		"grade_section": "Sample", "guided_tutorial": true})
	await process_frame
	_check(db.call("count", "register_student") == 0,
		"Tutorial never registers a student even while DB is reachable")
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {"score": 900,
		"round_completed": true, "activity": "Catch the Word"})
	await process_frame
	_check(db.call("count", "complete_round") == 0,
		"Completed Tutorial score never writes to database")
	_check((app.get("active_panel") as Control).get_node_or_null("%SaveStatus") == null
		and bool((app.get("session_state") as Dictionary).get("guided_tutorial", false))
		and not bool((app.get("session_state") as Dictionary).get("score_saved", false)),
		"Tutorial Results keeps practice-only state with no redundant status label")
	app.call("_save_completed_round")
	_check(db.call("count", "complete_round") == 0,
		"Direct score-save entry point is guarded during Tutorial too")
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	_check(bool((app.get("session_state") as Dictionary).get("guided_tutorial", false)),
		"Tutorial Retry never silently converts the session to Play")
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {"round_completed": true, "score": 550})
	await process_frame
	_check(db.call("count", "complete_round") == 0,
		"Completed round after Tutorial Retry still cannot save scores")

	# Positive control: actual Play (not guided tutorial) still saves a real
	# completed round when an authenticated student is present, via mock ONLY.
	app.set("session_state", {
		"entry_source": "play", "guided_tutorial": false,
		"activity": "Catch the Word", "student_id": "SAFE-MOCK",
			"game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy",
			"database_connected": true, "student_lookup_connected": true
	})
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {"round_completed": true,
		"score": 100, "activity": "Catch the Word"})
	await process_frame
	_check(db.call("count", "complete_round") == 1,
		"Ordinary Play alone still saves a completed round")

	# The user explicitly retired Spotlight. Tutorial isolation is now
	# verified through the unsaved practice session and ordinary Play control
	# above, without creating the deleted overlay resource.
	_check(not ResourceLoader.exists("res://ui/tutorial/spotlight/spotlight_overlay.tscn"),
		"Retired Spotlight scene is absent without affecting tutorial score isolation")
	# This fixture deliberately ends on a low-scoring completed Play result,
	# which starts Results' "Better Luck" MP3. As in the real Quit path,
	# stop and drain the menu's audio players before removing the owning
	# scene; freeing it and immediately quitting leaked MP3 playback RIDs.
	await app.call("prepare_for_shutdown")
	_check(bool(app.get("_shutdown_audio_drain_complete")),
		"Completed Play audio drains before test teardown")
	app.queue_free()
	await process_frame
	await process_frame
	print("TUTORIAL NO DATA / CREDITS: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("FAIL tutorial isolation: " + description)
