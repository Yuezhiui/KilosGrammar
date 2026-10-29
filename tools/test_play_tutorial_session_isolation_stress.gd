extends SceneTree

## Run: godot --headless --path . --script res://tools/test_play_tutorial_session_isolation_stress.gd
## Shared real menu, existing TEST-ONLY no-socket database fixture, no camera.
## Checks Play completed sessions save exactly once; Tutorial never saves or
## registers, even after retries, delayed callbacks or manual save attempts.
const MENU := "res://ui/main_menu/main_menu.tscn"
const FIXTURE := "res://tools/test_postgres_csv_delete_menu_fixture.gd"
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const MODES := ["Seconds", "Lives"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var app: Control
var db: Node
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_timeout")


func _timeout() -> void:
	await create_timer(22.0).timeout
	_check(false, "Offline test exceeded watchdog time")
	quit(1)


func _run() -> void:
	var packed := load(MENU) as PackedScene
	var script := load(FIXTURE) as Script
	_check(packed != null and script != null and script.can_instantiate(),
		"Real main menu and no-socket-only injected database script both load")
	if packed == null or script == null or not script.can_instantiate():
		_finish()
		return
	app = packed.instantiate() as Control
	app.set_script(script)
	root.add_child(app)
	await process_frame
	db = app.get("database_client") as Node
	_check(db != null and db.has_method("count") and db.get_child_count() == 0,
		"All database operations are in-memory requests without HTTPRequest/socket")
	if db == null:
		_finish()
		return
	app.set("database_online", true)
	for resolution in RESOLUTIONS:
		root.size = resolution
		root.content_scale_size = Vector2i(1280, 720)
		for activity in ACTIVITIES:
			for game_mode in MODES:
				await _verify_tutorial(activity, game_mode, resolution)
				await _verify_unverified_play(activity, game_mode, resolution)
				await _verify_aborted_play(activity, game_mode, resolution)
				await _verify_play(activity, game_mode, resolution)
	await _verify_no_registration_from_tutorial()
	await _verify_delayed_play_save_never_marks_tutorial()
	app.queue_free()
	await process_frame
	_finish()


func _verify_tutorial(activity: String, mode: String, resolution: Vector2i) -> void:
	var tag := "%s / %s / %s" % [resolution, activity, mode]
	var before_saves: int = db.call("count", "complete_round")
	var before_register: int = db.call("count", "register_student")
	app.set("session_state", {
		"entry_source": "tutorial", "guided_tutorial": true,
		"student_id": "PRACTICE-IGNORE", "student_name": "Practice only",
		"grade_section": "TEST", "activity": activity,
		"game_mode": mode, "topic": "Noun", "game_style": "Noun",
		"difficulty": "Easy", "score": 0,
	})
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {
		"round_completed": true, "score": 700, "activity": activity,
		"game_mode": mode, "attempts": 8, "correct": 7,
	})
	_check(db.call("count", "complete_round") == before_saves,
		tag + " Tutorial completed round never creates a save request")
	_check(db.call("count", "register_student") == before_register,
		tag + " Tutorial does not register a student")
	var state: Dictionary = app.get("session_state")
	_check(bool(state.get("guided_tutorial", false)) and
		String(state.get("entry_source", "")) == "tutorial" and
		not bool(state.get("score_saved", false)),
		tag + " Tutorial remains explicitly unsaved, never promoted into Play")
	app.call("_save_completed_round")
	_check(db.call("count", "complete_round") == before_saves,
		tag + " direct save entrypoint also rejects Tutorial")
	app.call("_on_panel_requested", "student_setup", {})
	# Allow deferred form _focus_first to finish while its new owner is mounted.
	# Immediately tearing it down causes Godot focus warnings unrelated to data.
	await process_frame
	await process_frame
	state = app.get("session_state")
	_check(bool(state.get("guided_tutorial", false)),
		tag + " Tutorial retries remain Tutorial-only after Results")
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {"round_completed": true,
		"score": 250, "activity": activity})
	_check(db.call("count", "complete_round") == before_saves,
		tag + " Tutorial Retry score still cannot save")
	await process_frame


func _verify_play(activity: String, mode: String, resolution: Vector2i) -> void:
	var tag := "%s / %s / %s" % [resolution, activity, mode]
	var before_saves: int = db.call("count", "complete_round")
	app.set("session_state", {
		"entry_source": "play", "guided_tutorial": false,
		"student_lookup_connected": true,
		"student_id": "SAFE-MOCK-ID", "student_name": "Mock only",
		"grade_section": "TEST", "activity": activity,
		"game_mode": mode, "game_style": "Noun", "topic": "Noun",
		"difficulty": "Easy", "score": 0,
	})
	app.set("database_online", true)
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {
		"round_completed": true, "score": 350, "activity": activity,
		"game_mode": mode, "attempts": 5, "correct": 3,
	})
	_check(db.call("count", "complete_round") == before_saves + 1,
		tag + " Play completed round submits exactly one score")
	var pending: Dictionary = db.call("find_pending", "complete_round", "completed_round")
	var args: Dictionary = pending.get("args", {})
	_check(args.get("student_id", "") == "SAFE-MOCK-ID" and
		int(args.get("score", -1)) == 350 and args.get("game_mode", "") == mode,
		tag + " Play score, ID and game mode are passed to isolated backend")
	_check((pending.get("context", {}) as Dictionary).get("minigame", "") == activity,
		tag + " Saved minigame is the one that actually finished")
	if not pending.is_empty():
		var callback: Dictionary = pending.get("context", {})
		_check(db.call("reply", "complete_round", {
			"ok": true, "status": 201,
			"data": {"score": {"score_id": 701}},
		}, "completed_round"), tag + " success callback delivered only inside mock")
		_check(bool((app.get("session_state") as Dictionary).get("score_saved", false)),
			tag + " confirmed Play completion marks Results saved")
		_check(db.call("count", "complete_round") == before_saves + 1,
			tag + " response does not cause duplicate persistence")
	await process_frame


func _verify_aborted_play(activity: String, mode: String, resolution: Vector2i) -> void:
	var before_saves: int = db.call("count", "complete_round")
	app.set("session_state", {
		"entry_source": "play", "guided_tutorial": false,
		"student_id": "REGISTERED", "student_lookup_connected": true,
		"activity": activity, "game_mode": mode, "game_style": "Noun"})
	app.set("database_online", true)
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {
		"round_completed": false, "score": 999, "activity": activity})
	_check(db.call("count", "complete_round") == before_saves,
		"%s/%s/%s aborted/paused results never save a Play session" % [resolution, activity, mode])
	await process_frame


func _verify_unverified_play(activity: String, mode: String, resolution: Vector2i) -> void:
	var tag := "%s / %s / %s" % [resolution, activity, mode]
	var before_saves: int = db.call("count", "complete_round")
	app.set("session_state", {
		"entry_source": "play", "guided_tutorial": false,
		"student_id": "UNVERIFIED-NO-SAVE", "student_lookup_connected": false,
		"activity": activity, "game_mode": mode, "topic": "Noun",
		"game_style": "Noun", "difficulty": "Normal"})
	app.set("database_online", true)
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {
		"round_completed": true, "score": 950, "activity": activity})
	_check(db.call("count", "complete_round") == before_saves,
		tag + " Unverified profile cannot insert an otherwise valid Play score")
	_check(not bool((app.get("session_state") as Dictionary).get("score_saved", false)),
		tag + " Unverified profile Results stays unsaved")
	await process_frame


func _verify_no_registration_from_tutorial() -> void:
	var before: int = db.call("count", "register_student")
	app.set("session_state", {"entry_source": "tutorial", "guided_tutorial": true})
	app.set("database_online", true)
	app.set("current_route", "student_setup")
	app.call("_on_panel_requested", "play_activity", {
		"student_id": "DONT-REGISTER", "student_name": "Tutorial",
		"grade_section": "TEST", "guided_tutorial": true,
	})
	_check(db.call("count", "register_student") == before,
		"Tutorial route cannot register a student even with a reachable mock DB")
	# The next route may tear down this native chooser; let its deferred focus
	# settle first rather than causing a harmless off-tree focus warning.
	await process_frame
	await process_frame


func _verify_delayed_play_save_never_marks_tutorial() -> void:
	app.set("session_state", {
		"entry_source": "play", "guided_tutorial": false,
		"student_id": "REGISTERED", "student_lookup_connected": true,
		"activity": "Human Plane", "game_mode": "Seconds", "game_style": "Noun"})
	app.set("database_online", true)
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {"score": 450,
		"round_completed": true, "activity": "Human Plane"})
	var pending: Dictionary = db.call("find_pending", "complete_round", "completed_round")
	_check(not pending.is_empty(), "Verified Play creates a delayed mocked score request")
	app.call("_on_panel_requested", "tutorial_home", {})
	if not pending.is_empty():
		_check(db.call("reply", "complete_round", {
			"ok": true, "status": 201,
			"data": {"score": {"score_id": 999}},
		}, "completed_round"), "Old Play backend reply arrives after opening Tutorial")
	var state: Dictionary = app.get("session_state")
	_check(not bool(state.get("score_saved", false)) and
		String(state.get("entry_source", "")) == "tutorial",
		"Stale save callback cannot mark a newly opened Tutorial as persisted")
	await process_frame


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("PLAY/TUTORIAL ISOLATION FAIL: ", description)


func _finish() -> void:
	print("PLAY/TUTORIAL SHARED-FLOW MOCK STRESS: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
