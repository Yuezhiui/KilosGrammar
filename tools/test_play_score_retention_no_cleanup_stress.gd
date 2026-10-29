extends SceneTree

## Offline Play score retention contract. Injection happens BEFORE the real
## Main Menu enters the scene, so no PostgreSQL process, sockets, files or
## student records are modified.
## Godot --headless --path . --script res://tools/test_play_score_retention_no_cleanup_stress.gd
const MENU := "res://ui/main_menu/main_menu.tscn"
const FIXTURE := "res://tools/test_postgres_csv_delete_menu_fixture.gd"
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const MODES := ["Seconds", "Lives"]
var checks := 0
var failures: Array[String] = []
var app: Control
var mock: Node


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(19.0).timeout
	_check(false, "No-socket score retention fixture timed out")
	quit(1)


func _run() -> void:
	var menu := load(MENU) as PackedScene
	var fixture := load(FIXTURE) as Script
	_check(menu != null and fixture != null and fixture.can_instantiate(),
		"MainMenu and no-socket test-only subclass parse")
	if menu == null or fixture == null or not fixture.can_instantiate():
		_finish()
		return
	app = menu.instantiate() as Control
	app.set_script(fixture)
	root.add_child(app)
	await process_frame
	mock = app.get("database_client") as Node
	_check(mock != null and mock.has_method("count") and mock.get_child_count() == 0,
		"DB mock cannot spawn PostgreSQL process or HTTP socket")
	if mock == null:
		_finish()
		return
	var last_count := 0
	for repeated_round in range(3):
		for activity in ACTIVITIES:
			for mode in MODES:
				app.set("database_online", true)
				app.set("session_state", {
					"entry_source": "play", "guided_tutorial": false,
					"student_id": "QA-VERIFIED-ONLY",
					"student_lookup_connected": true,
					"student_name": "MOCK", "grade_section": "TEST",
					"activity": activity, "game_mode": mode,
					"game_style": "Noun", "difficulty": "Easy",
				})
				app.set("current_route", "gameplay")
				app.call("_on_panel_requested", "results", {
					"round_completed": true,
					"activity": activity,
					"score": 100 + 100 * repeated_round})
				last_count += 1
				_check(mock.call("count", "complete_round") == last_count,
					"Each of 18 verified completed Play rounds adds exactly one save request")
				var saved_request: Dictionary = mock.call("find_pending", "complete_round", "completed_round")
				var args: Dictionary = saved_request.get("args", {})
				_check(String(args.get("student_id", "")) == "QA-VERIFIED-ONLY" and
					int(args.get("score", -1)) == 100 + 100 * repeated_round and
					String(args.get("game_mode", "")) == mode,
					"Saved verified Play history has exact student, mode, positive score")
				_check(String((saved_request.get("context", {}) as Dictionary).get("minigame", "")) == activity,
					"Saved completed score retains exact activity for leaderboard")
				mock.call("reply", "complete_round", {
					"ok": true, "status": 201,
					"data": {"score": {"id": last_count}},
				}, "completed_round")
				_check(bool((app.get("session_state") as Dictionary).get("score_saved", false)),
					"Persisted Play result confirmed only after backend success")
				_check(mock.call("count", "delete_all_data") == 0 and
					mock.call("count", "delete_data") == 0 and
					mock.call("count", "import_data_csv") == 0,
					"No automatic DB cleanup/purge/import after completed Play save")
				await process_frame
	_check(mock.call("count", "complete_round") == 18,
		"Mock request journal retains all 18 independent completed rounds")
	app.set("database_online", false)
	app.set("session_state", {
		"entry_source": "play", "guided_tutorial": false,
		"student_id": "QA-VERIFIED-ONLY", "student_lookup_connected": true,
		"activity": "Catch the Word", "game_mode": "Seconds"})
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {"round_completed": true, "score": 900})
	_check(mock.call("count", "complete_round") == 18 and
		not bool((app.get("session_state") as Dictionary).get("score_saved", false)),
		"Offline Play reports unsaved without silently deleting prior records")
	app.set("database_online", true)
	app.set("session_state", {"entry_source": "tutorial", "guided_tutorial": true,
		"student_id": "PRACTICE", "student_lookup_connected": true,
		"activity": "Human Plane", "game_mode": "Lives"})
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {"round_completed": true, "score": 9000})
	_check(mock.call("count", "complete_round") == 18 and
		mock.call("count", "register_student") == 0,
		"Tutorial never registers or saves even with spoofed verified-state flag")
	app.queue_free()
	await process_frame
	_finish()


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("SCORE RETENTION QA FAIL: ", description)


func _finish() -> void:
	print("PLAY COMPLETED SCORE RETENTION (NO DB): %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
