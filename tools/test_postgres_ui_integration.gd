extends SceneTree

## Routed UI PostgreSQL regression test. All requests pass through a pure
## in-memory mock; no HTTP server, socket, migrations, or real database used.
## Run: godot --headless --path . --script res://tools/test_postgres_ui_integration.gd
const TEST_MENU_PATH := "res://tools/test_postgres_main_menu.gd"

var failures: Array[String] = []
var _app: Control
var _client: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := load("res://main_menu.tscn") as PackedScene
	_assert(scene != null, "Main Menu's real PackedScene loads")
	if scene == null:
		quit(1)
		return
	_app = scene.instantiate() as Control
	var isolated_script := load(TEST_MENU_PATH) as Script
	_assert(isolated_script != null and isolated_script.can_instantiate(),
		"Test-only Main Menu subclass loads after autoload initialization")
	if isolated_script == null or not isolated_script.can_instantiate():
		_app.free()
		quit(1)
		return
	_app.set_script(isolated_script)
	root.add_child(_app)
	await process_frame
	_client = _app.get("database_client") as Node
	_assert(is_instance_valid(_client), "Test Main Menu injects database mock")
	if not is_instance_valid(_client):
		await _finish()
		return
	_assert(_client.get_child_count() == 0, "Mock never creates HTTPRequest or a socket")
	_assert(_client.call("count", "health") == 1, "Startup probes database asynchronously")
	_assert(_client.call("reply", "health", _healthy(), "startup"), "Startup health response is received")
	_assert(bool(_app.get("database_online")), "Healthy PostgreSQL state reaches Main Menu")

	await _test_verified_student_and_idempotent_registration()
	await _test_conflict_and_offline_play()
	await _test_completed_round_saves_only()
	await _test_late_score_callback_after_abort()
	await _test_leaderboard_async_rows()
	await _test_stale_registration_response()
	await _finish()


func _test_verified_student_and_idempotent_registration() -> void:
	var play := _app.get_node("MainLayer/CenterMenu/Play") as Button
	var play_position := play.position
	play.pressed.emit()
	await process_frame
	_assert(_route() == "student_setup", "Native Main Play button routes to Student Setup")
	_assert(play.position == play_position, "Native Main Menu Play button position remains authored")
	var form := _app.get("active_panel") as Control
	if form == null or _route() != "student_setup":
		return
	_assert(_client.call("reply", "health", _healthy(), "student_setup_health"),
		"Student Setup receives asynchronous health status")
	_fill(form, "S-001", "Initially Typed Name", "Grade 1")
	var lookup_button := form.get("_lookup_button") as Button
	var database_status := form.get("_database_status") as Label
	var status_position := database_status.position
	_assert(not lookup_button.disabled, "Existing scene Lookup button is enabled when ID is present")
	lookup_button.pressed.emit()
	_assert(_client.call("count", "find_student") == 1, "Native Lookup button sends one find_student request")
	var pending: Dictionary = _client.call("find_pending", "find_student", "student_lookup")
	_assert(pending.get("args", {}).get("student_id", "") == "S-001", "Lookup sends edited student ID")
	_assert(_client.call("reply", "find_student", {
		"ok": true, "status": 200, "data": {"student": {
			"student_id": "S-001", "student_name": "Verified Student",
			"grade_section": "Grade 5",
		}},
	}, "student_lookup"), "Verified profile callback dispatches to current Student Setup")
	_assert((form.get("_name_edit") as LineEdit).text == "Verified Student",
		"Lookup updates native name field from confirmed backend identity")
	_assert((form.get("_grade_edit") as LineEdit).text == "Grade 5",
		"Lookup updates native grade field from confirmed backend identity")
	_assert(database_status.text.contains("STUDENT FOUND"), "Native status visibly confirms lookup")
	_assert(database_status.position == status_position, "Database callback does not move authored form UI")
	var next := form.get("_continue_button") as Button
	_assert(not next.disabled, "Verified student can continue with selected activity")
	next.pressed.emit()
	_assert(_route() == "student_setup", "Online registration awaits its asynchronous reply")
	_assert(_client.call("count", "register_student") == 1, "Continue sends one idempotent registration")
	next.pressed.emit()
	_assert(_client.call("count", "register_student") == 1, "Double-click while pending never duplicates registration")
	pending = _client.call("find_pending", "register_student", "registration")
	var registration: Dictionary = pending.get("args", {})
	_assert(registration.get("student_name", "") == "Verified Student"
		and registration.get("grade_section", "") == "Grade 5",
		"Existing confirmed identity is registered idempotently without changing profile")
	_assert(_client.call("reply", "register_student", {
		"ok": true, "status": 200,
		"data": {"student": {"student_id": "S-001", "student_name": "Verified Student", "grade_section": "Grade 5"}},
	}, "registration"), "Existing identity idempotent HTTP 200 callback is accepted")
	await process_frame
	_assert(_route() == "play_activity", "Confirmed existing student can enter Game Selection")
	_assert(bool((_app.get("session_state") as Dictionary).get("database_connected", false)),
		"Successful registration marks current session connected")


func _test_conflict_and_offline_play() -> void:
	_app.call("_return_to_main")
	await process_frame
	_app.get_node("MainLayer/CenterMenu/Play").pressed.emit()
	await process_frame
	_assert(_route() == "student_setup", "New Play opens a fresh Student Setup panel")
	var form := _app.get("active_panel") as Control
	if form == null or _route() != "student_setup":
		return
	_client.call("reply", "health", _healthy(), "student_setup_health")
	_fill(form, "S-002", "Conflicting Name", "Grade 6")
	var continue_button := form.get("_continue_button") as Button
	continue_button.pressed.emit()
	_assert(_client.call("reply", "register_student", {
		"ok": false, "status": 409, "error": "student_conflict", "data": null,
	}, "registration"), "Conflicting existing ID returns explicit 409")
	_assert(_route() == "student_setup", "Identity conflict blocks advancing and prevents silent overwrite")
	_assert((form.get("_database_status") as Label).text.contains("ALREADY REGISTERED"),
		"Student Setup explains conflict to teacher")
	continue_button.pressed.emit()
	_assert(_client.call("reply", "register_student", {
		"ok": false, "status": 0, "error": "connection_error", "data": null,
	}, "registration"), "Offline failure is dispatched without real PostgreSQL")
	await process_frame
	_assert(_route() == "play_activity", "Offline database does not trap the classroom in setup")
	_assert(not bool(_app.get("database_online")), "Connection error marks transport offline")
	_assert(not bool((_app.get("session_state") as Dictionary).get("database_connected", true)),
		"Offline play preserves explicit unsaved status in session")
	_client.call("check_health", {"purpose": "test_reconnected"})
	_client.call("reply", "health", _healthy(), "test_reconnected")
	_assert(bool(_app.get("database_online")), "A later successful health check can reconnect")


func _test_completed_round_saves_only() -> void:
	var payload := {
		"student_id": "S-001", "student_name": "Verified Student",
		"grade_section": "Grade 5", "game_style": "Noun",
		"game_mode": "Seconds", "difficulty": "Easy",
		"activity": "Balloon Popping", "score": 987,
		"round_completed": false, "completion_reason": "pause_aborted",
	}
	var initial_saves: int = _client.call("count", "complete_round")
	# Inject only the router's source route; do not launch a fake webcam or round.
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", payload)
	await process_frame
	_assert(_route() == "results", "Aborted gameplay can display the real Results scene")
	_assert(_client.call("count", "complete_round") == initial_saves,
		"Paused/aborted gameplay never writes score, even with numerical points")
	var results := _app.get("active_panel") as Control
	var status := results.get_node("%SaveStatus") as Label
	var status_position := status.position
	_assert(status.text.contains("ROUND NOT COMPLETED"), "Results explicitly says unsaved when aborted")
	_assert(not bool((_app.get("session_state") as Dictionary).get("score_saved", false)),
		"Aborted round never receives saved-score confirmation")

	payload["score"] = 37
	payload["round_completed"] = true
	payload["completion_reason"] = "timer_complete"
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", payload)
	await process_frame
	_assert(_client.call("count", "complete_round") == initial_saves + 1,
		"Actual completed round queues precisely one score save")
	results = _app.get("active_panel") as Control
	status = results.get_node("%SaveStatus") as Label
	_assert(status.text.contains("SAVING COMPLETED SCORE"), "Results shows saving state before response")
	var pending: Dictionary = _client.call("find_pending", "complete_round", "completed_round")
	_assert(pending.get("args", {}).get("score", -1) == 37, "Database receives real completed score")
	_assert(pending.get("args", {}).get("student_id", "") == "S-001",
		"Save preserves verified student's ID")
	_assert(_client.call("reply", "complete_round", {
		"ok": true, "status": 201, "data": {"score": {"student_id": "S-001", "score": 37}},
	}, "completed_round"), "Completed-score success callback reaches Results")
	_assert(bool((_app.get("session_state") as Dictionary).get("score_saved", false)),
		"Only real completion acknowledgement marks the score saved")
	_assert((results.get_node("%SaveStatus") as Label).text.contains("SCORE SAVED"),
		"Results visually confirms persisted completion after callback")
	_assert((results.get_node("%SaveStatus") as Label).position == status_position,
		"Native SaveStatus position is preserved through async updates")
	_assert((results.get_node("%ScoreValue") as Label).text == "37",
		"Results keeps actual completion score after callback")
	_app.call("_on_panel_requested", "results", payload)
	await process_frame
	_assert(_client.call("count", "complete_round") == initial_saves + 1,
		"Reloading Results never re-saves a completed round")

	# Prove failed writes cannot be rendered as successful.
	payload["score"] = 80
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", payload)
	await process_frame
	_assert(_client.call("reply", "complete_round", {
		"ok": false, "status": 503, "error": "database_unavailable", "data": null,
	}, "completed_round"), "Score write failure callback is surfaced")
	results = _app.get("active_panel") as Control
	_assert(not bool((_app.get("session_state") as Dictionary).get("score_saved", true)),
		"Database write failure never invents persisted score")
	_assert((results.get_node("%SaveStatus") as Label).text.contains("SCORE NOT SAVED"),
		"Failed write displays unsaved result to student")


func _test_leaderboard_async_rows() -> void:
	_app.call("_return_to_main")
	await process_frame
	_app.get_node("MainLayer/LeftMenu/Leaderboard").pressed.emit()
	await process_frame
	_assert(_route() == "leaderboard", "Native Main Menu Leaderboard button opens leaderboard")
	var board := _app.get("active_panel") as Control
	var empty := board.get_node("%EmptyMessage") as Label
	var rows := board.get_node("%ScoreRows") as VBoxContainer
	var authored_empty_pos := empty.position
	var authored_scroll_pos := (board.get_node("%ScoreRowsScroll") as ScrollContainer).position
	_assert(rows.get_child_count() == 0, "Leaderboard does not fabricate demo rankings")
	_assert(empty.text.contains("Loading"), "Leaderboard displays pending async request state")
	_assert(_client.call("reply", "get_leaderboard", {
		"ok": false, "status": 503, "error": "database_unavailable",
		"data": null,
	}, "leaderboard"), "Leaderboard handles database read failure")
	_assert(rows.get_child_count() == 0, "Offline leaderboard remains empty with no invented scores")
	_assert(empty.text.contains("database unavailable"), "Offline state is visible to teacher")

	_app.call("_return_to_main")
	await process_frame
	_app.get_node("MainLayer/LeftMenu/Leaderboard").pressed.emit()
	await process_frame
	board = _app.get("active_panel") as Control
	rows = board.get_node("%ScoreRows") as VBoxContainer
	empty = board.get_node("%EmptyMessage") as Label
	_assert(_client.call("reply", "get_leaderboard", {
		"ok": true, "status": 200, "data": {"leaderboard": [
			{"student_id": "S-002", "student_name": "Second", "grade_section": "Grade 5",
				"game_style": "Verb", "game_mode": "Lives", "difficulty": "Hard", "score": 37},
			{"student_id": "S-001", "student_name": "Verified Student", "grade_section": "Grade 5",
				"game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 100},
		]},
	}, "leaderboard"), "Leaderboard receives backend-owned rankings")
	_assert(rows.get_child_count() == 2, "Leaderboard displays exactly two server records")
	if rows.get_child_count() == 2:
		_assert((rows.get_child(0).get_node("StudentId") as Label).text == "S-001",
			"Leaderboard sorts actual server score records descending")
		_assert((rows.get_child(0).get_node("Score") as Label).text == "100",
			"Top leaderboard score is read from callback data")
	_assert(empty.position == authored_empty_pos, "Async rankings preserve native EmptyMessage position")
	_assert((board.get_node("%ScoreRowsScroll") as ScrollContainer).position == authored_scroll_pos,
		"Async rankings preserve editor-authored scroll panel position")
	var style_filter := board.get_node("%StyleFilter") as OptionButton
	var noun_index := -1
	for index in style_filter.item_count:
		if style_filter.get_item_text(index).to_upper() == "NOUN":
			noun_index = index
			break
	_assert(noun_index >= 0, "Existing native leaderboard style filter includes Noun")
	if noun_index >= 0:
		style_filter.select(noun_index)
		board.call("_on_filter_changed")
		_assert(rows.get_child_count() == 1,
			"Editor-authored filter narrows actual PostgreSQL ranking rows")


func _test_late_score_callback_after_abort() -> void:
	var completed := {
		"student_id": "S-001", "student_name": "Verified Student",
		"grade_section": "Grade 5", "game_style": "Noun",
		"game_mode": "Seconds", "difficulty": "Easy",
		"activity": "Balloon Popping", "score": 500, "round_completed": true,
	}
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", completed)
	await process_frame
	_assert(not (_client.call("find_pending", "complete_round", "completed_round") as Dictionary).is_empty(),
		"Completed round can have a network write pending")
	_app.call("_return_to_main")
	await process_frame
	var aborted := completed.duplicate(true)
	aborted["score"] = 3
	aborted["round_completed"] = false
	# Inject a gameplay-origin abort after a new navigation session.
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", aborted)
	await process_frame
	_assert(_route() == "results", "Aborted new session displays Results while older save remains in flight")
	_assert(not bool((_app.get("session_state") as Dictionary).get("score_saved", false)),
		"New aborted round starts in unsaved state")
	_assert(_client.call("reply", "complete_round", {
		"ok": true, "status": 201, "data": {"score": {"student_id": "S-001", "score": 500}},
	}, "completed_round"), "Delayed old completion callback can arrive after a new aborted Results view")
	_assert(not bool((_app.get("session_state") as Dictionary).get("score_saved", false)),
		"Old completion callback never labels another aborted round as persisted")
	_assert((( _app.get("active_panel") as Control).get_node("%SaveStatus") as Label).text.contains("ROUND NOT COMPLETED"),
		"Current aborted Results remains explicitly unsaved after unrelated old callback")


func _test_stale_registration_response() -> void:
	_app.call("_return_to_main")
	await process_frame
	_app.get_node("MainLayer/CenterMenu/Play").pressed.emit()
	await process_frame
	var form := _app.get("active_panel") as Control
	_client.call("reply", "health", _healthy(), "student_setup_health")
	_fill(form, "BACK-001", "Student Returning Home", "Grade 5")
	(form.get("_continue_button") as Button).pressed.emit()
	_assert(not (_client.call("find_pending", "register_student", "registration") as Dictionary).is_empty(),
		"Registration remains pending until async server reply")
	(form.get("_back_button") as Button).pressed.emit()
	await process_frame
	_assert(_route() == "main", "Teacher can return Main while registration is pending")
	_assert(_client.call("reply", "register_student", {
		"ok": true, "status": 201, "data": {"student": {
			"student_id": "BACK-001", "student_name": "Student Returning Home", "grade_section": "Grade 5",
		}},
	}, "registration"), "A delayed successful registration reply can arrive after navigation")
	await process_frame
	_assert(_route() == "main", "Delayed registration callback must not hijack navigation after Back")
	_assert(_app.get("active_panel") == null, "Stale registration callback never resurrects an abandoned panel")

	_app.get_node("MainLayer/CenterMenu/Play").pressed.emit()
	await process_frame
	form = _app.get("active_panel") as Control
	_client.call("reply", "health", _healthy(), "student_setup_health")
	_fill(form, "EDIT-001", "First Spelling", "Grade 3")
	(form.get("_continue_button") as Button).pressed.emit()
	(form.get("_name_edit") as LineEdit).text = "Corrected Spelling"
	_assert(_client.call("reply", "register_student", {
		"ok": true, "status": 201, "data": {"student": {
			"student_id": "EDIT-001", "student_name": "First Spelling", "grade_section": "Grade 3",
		}},
	}, "registration"), "A pending registration can finish after name is corrected")
	await process_frame
	_assert(_route() == "student_setup",
		"Stale registration response must not advance after teacher edits name during request")
	if _route() == "student_setup":
		_assert(((_app.get("active_panel") as Control).get("_name_edit") as LineEdit).text == "Corrected Spelling",
			"Teacher's corrected identity fields remain intact after stale response")


func _fill(form: Control, student_id: String, student_name: String, grade: String) -> void:
	(form.get("_student_id_edit") as LineEdit).text = student_id
	(form.get("_name_edit") as LineEdit).text = student_name
	(form.get("_grade_edit") as LineEdit).text = grade
	form.call("_select_style", "Noun")
	form.call("_select_mode", "Seconds")
	form.call("_select_difficulty", "Easy")
	form.call("_update_validation")


func _healthy() -> Dictionary:
	return {"ok": true, "status": 200, "data": {"database": "connected"}}


func _route() -> String:
	return String(_app.get("current_route"))


func _assert(passed: bool, label: String) -> void:
	if not passed:
		failures.append(label)
		printerr("FAIL postgres UI: ", label)


func _finish() -> void:
	if is_instance_valid(_app):
		_app.call("_return_to_main")
		_app.queue_free()
		await process_frame
		await process_frame
	print("POSTGRES UI INTEGRATION: ", "PASS" if failures.is_empty() else "FAIL",
		" (%d failures)" % failures.size())
	quit(0 if failures.is_empty() else 1)
