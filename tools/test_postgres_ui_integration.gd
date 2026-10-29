extends SceneTree

## Routed UI PostgreSQL regression test. All requests pass through a pure
## in-memory mock; no HTTP server, socket, migrations, or real database used.
## Run: godot --headless --path . --script res://tools/test_postgres_ui_integration.gd
const TEST_MENU_PATH := "res://tools/test_postgres_main_menu.gd"
const RECOVERY := preload("res://ui/database/recovery_journal.gd")

var failures: Array[String] = []
var checks := 0
var _app: Control
var _client: Node
var _test_recovery_dir := ""


func _initialize() -> void:
	# This MUST precede MainMenu mounting and every registration/score save.
	_test_recovery_dir = "user://test_recovery_ui_integration_%d_%d" % [
		OS.get_process_id(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("kilos/recovery_test_directory", _test_recovery_dir)
	call_deferred("_run")


func _run() -> void:
	_assert(RECOVERY._directory() == _test_recovery_dir
		and _test_recovery_dir.begins_with("user://test_recovery_"),
		"Recovery journal is isolated before any mock Main Menu or score save")
	_assert(RECOVERY.pending().is_empty(), "This mock run starts with an empty recovery outbox")
	root.size = Vector2i(1280, 720)
	var scene := load("res://ui/main_menu/main_menu.tscn") as PackedScene
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
	await _test_unwritable_local_recovery_blocks_new_student()
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
	_assert(form.find_child("LookupButton", true, false) == null
		and form.find_child("DatabasePanel", true, false) == null,
		"Retired lookup and status widgets stay absent")
	var stage := form.get_node("SetupStage") as Control
	var stage_position := stage.position
	_fill(form, "S-001", "", "")
	var id_field := form.get("_student_id_edit") as LineEdit
	id_field.text_changed.emit(id_field.text)
	form.call("_autofill_if_unchanged") # Deterministic simulated 2.5 s timer timeout.
	_assert(_client.call("count", "find_student") == 1, "Automatic idle ID lookup sends exactly one query")
	var pending: Dictionary = _client.call("find_pending", "find_student", "autofill")
	_assert(pending.get("args", {}).get("student_id", "") == "S-001"
		and pending.get("context", {}).get("autofill_field", "") == "id",
		"Autofill sends exact ID and its source field")
	_assert(_client.call("reply", "find_student", {
		"ok": true, "status": 200, "data": {"student": {
			"student_id": "S-001", "student_name": "Verified Student",
			"grade_section": "Grade 5",
		}},
	}, "autofill"), "Verified autofill callback dispatches to current Student Setup")
	_assert((form.get("_name_edit") as LineEdit).text == "Verified Student",
		"Autofill updates native name field from confirmed backend identity")
	_assert((form.get("_grade_edit") as LineEdit).text == "Grade 5",
		"Autofill updates native grade field from confirmed backend identity")
	_assert(stage.position == stage_position, "Database callback does not move editor-authored setup art")
	_assert(bool(form.get("context").get("student_lookup_connected", false)),
		"Verified identity is marked confirmed without a visible lookup action")
	var next := form.get("_continue_button") as Button
	_assert(not next.disabled, "Verified student can continue with selected activity")
	next.pressed.emit()
	_assert(_route() == "play_activity", "Verified database lookup proceeds directly to Game Selection")
	_assert(_client.call("count", "register_student") == 0,
		"Already verified profile is not redundantly registered again")
	var saved: Dictionary = _app.get("session_state") as Dictionary
	_assert(String(saved.get("student_name", "")) == "Verified Student"
		and String(saved.get("grade_section", "")) == "Grade 5",
		"Verified student identity remains unchanged after Continue")
	await process_frame
	_assert(_route() == "play_activity", "Confirmed existing student stays in Game Selection")
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
	_assert(not (_client.call("find_pending", "find_student", "registration_lookup") as Dictionary).is_empty(),
		"Continue requests a read-only student ID lookup before navigation")
	_assert(_client.call("count", "register_student") == 0 and RECOVERY.pending().is_empty(),
		"Continue creates neither a student profile nor a recovery-outbox entry")
	_assert(_client.call("reply", "find_student", {
		"ok": true, "status": 200, "data": {"student": {
			"student_id": "S-002", "student_name": "Registered Other",
			"grade_section": "Grade 6",
		}},
	}, "registration_lookup"), "Backend reports existing ID belonging to another full name")
	_assert(_route() == "student_setup", "Identity conflict blocks advancing and prevents silent overwrite")
	_assert(form.find_child("DatabaseStatus", true, false) == null
		and (form.get("_student_id_edit") as LineEdit).text == "S-002",
		"Identity conflict retains form for correction without internal database warnings")
	var feedback := form.get_node("SetupStage/GameSetupCard/GameContent/ValidationPanel/ValidationLabel") as Label
	_assert(continue_button.disabled
		and String(form.get("_registration_error")) == "PLEASE CHECK STUDENT ID AND NAME",
		"Existing-ID/full-name mismatch blocks Continue with a real identity hold")
	_assert(not feedback.is_visible_in_tree() and feedback.text.is_empty(),
		"old red identity-warning banner stays hidden and blank")
	var conflicted_id_color: Color = (form.get("_student_id_edit") as LineEdit).get_theme_color("font_color")
	_assert(conflicted_id_color.is_equal_approx(form.get_script().get_script_constant_map()["CONFLICT_ID_TEXT_COLOR"]),
		"conflicting Student ID uses a subtle inline color cue")
	# Teacher corrects the conflicting identity; a new read-only lookup must
	# verify it, even if the database goes offline before that second response.
	var name_field := form.get("_name_edit") as LineEdit
	name_field.text = "Registered Other"
	name_field.text_changed.emit(name_field.text)
	_assert(not continue_button.disabled,
		"Editing disputed identity clears the hold for a new verification attempt")
	continue_button.pressed.emit()
	_assert(_client.call("reply", "find_student", {
		"ok": false, "status": 0, "error": "connection_error", "data": null,
	}, "registration_lookup"), "Read-only lookup transport failure is dispatched without real PostgreSQL")
	await process_frame
	_assert(_route() == "play_activity", "Offline database does not trap the classroom in setup")
	_assert(not bool(_app.get("database_online")), "Connection error marks transport offline")
	_assert(not bool((_app.get("session_state") as Dictionary).get("database_connected", true)),
		"Offline play preserves explicit unsaved status in session")
	_assert(not bool((_app.get("session_state") as Dictionary).get("recovery_profile_queued", false))
		and RECOVERY.pending().is_empty(),
		"Offline pregame Continue saves no profile and does not fabricate a completed round")
	_client.call("check_health", {"purpose": "test_reconnected"})
	_client.call("reply", "health", _healthy(), "test_reconnected")
	_assert(bool(_app.get("database_online")), "A later successful health check can reconnect")
	_app.call("_flush_recovery_outbox")
	await process_frame
	_assert((_client.call("find_pending", "register_student", "recovery_replay") as Dictionary).is_empty(),
		"Reconnecting before gameplay cannot replay a nonexistent student profile")
	_assert(RECOVERY.pending().is_empty(), "No pregame profile or score can appear after reconnect")


func _test_unwritable_local_recovery_blocks_new_student() -> void:
	# Force an actual write failure *inside this run's isolated test directory*.
	# A regular file cannot be treated as a directory by the journal. Never
	# point at or modify the classroom's real user://recovery_outbox.
	_app.call("_return_to_main")
	await process_frame
	_app.get_node("MainLayer/CenterMenu/Play").pressed.emit()
	await process_frame
	var form := _app.get("active_panel") as Control
	_assert(form != null and _route() == "student_setup",
		"Storage failure test opens genuine Student Setup scene")
	if form == null:
		return
	_fill(form, "FILE-FAIL-001", "Storage Failure Student", "Grade 4")
	var blocked_path := _test_recovery_dir.path_join("blocked_directory_file")
	_assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_test_recovery_dir)) == OK,
		"Recovery failure fixture initializes its own isolated storage folder")
	var file := FileAccess.open(blocked_path, FileAccess.WRITE)
	_assert(file != null, "Created intentional file obstacle strictly within this test run's user:// directory")
	if file == null:
		return
	file.store_string("test_fixture_obstacle_not_an_outbox")
	file.flush()
	file.close()
	_app.set("database_online", false)
	var request_before: int = _client.call("count", "register_student")
	ProjectSettings.set_setting("kilos/recovery_test_directory", blocked_path)
	_assert(RECOVERY._directory() == blocked_path, "Failure injection remains under test_recovery_* isolation")
	(form.get("_continue_button") as Button).pressed.emit()
	_assert(_route() == "play_activity", "Offline Continue can open game without storing a premature profile")
	_assert(RECOVERY.pending().is_empty(), "Storage remains untouched before any completed round")
	# The real activity schedules an editor-authored focus target on its first
	# frame. Let that callback finish before the fixture simulates gameplay end.
	await process_frame
	# A completed round is the only permitted storage attempt, and must be
	# honestly unsaved if the isolated recovery directory is unwritable.
	var completed := {
		"student_id": "FILE-FAIL-001", "student_name": "Storage Failure Student",
		"grade_section": "Grade 4", "game_style": "Noun",
		"game_mode": "Seconds", "difficulty": "Easy",
		"activity": "Balloon Popping", "score": 18,
		"round_completed": true, "completion_reason": "time_up",
		"time_remaining": 0.0, "entry_source": "play",
		"student_lookup_connected": false,
	}
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", completed)
	await process_frame
	var session: Dictionary = _app.get("session_state")
	_assert(_route() == "results", "Completed round displays Results despite local storage failure")
	_assert(not bool(session.get("score_saved", false))
		and not bool(session.get("recovery_pending", false)),
		"Unwritable journal cannot report the completed score as saved")
	_assert(RECOVERY.pending().is_empty(), "Unwritable storage cannot fabricate a durable score or profile")
	# Restore the original test-only directory before subsequent independent
	# regression cases.
	ProjectSettings.set_setting("kilos/recovery_test_directory", _test_recovery_dir)
	_assert(_client.call("count", "register_student") == request_before,
		"Failed journal save never attempts a hidden PostgreSQL profile write")
	_app.call("_return_to_main")
	await process_frame
	_app.set("database_online", true)


func _test_completed_round_saves_only() -> void:
	var payload := {
		"student_id": "S-001", "student_name": "Verified Student",
		"grade_section": "Grade 5", "game_style": "Noun",
		"game_mode": "Seconds", "difficulty": "Easy",
		"activity": "Balloon Popping", "score": 987,
		"round_completed": false, "completion_reason": "pause_aborted",
		"entry_source": "play", "student_lookup_connected": true,
	}
	var initial_saves: int = _client.call("count", "complete_round")
	# Inject only the router's source route; do not launch a fake webcam or round.
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", payload)
	await process_frame
	_assert(_route() == "results", "Aborted gameplay can display the real Results scene")
	_assert(_client.call("count", "complete_round") == initial_saves,
		"Paused/aborted gameplay never writes score, even with numerical points")
	_assert(RECOVERY.pending().is_empty(), "Aborted round cannot create a durable recovery score")
	var results := _app.get("active_panel") as Control
	_assert(results.get_node_or_null("%SaveStatus") == null,
		"Results omits redundant save-status label")
	_assert(not bool((_app.get("session_state") as Dictionary).get("score_saved", false)),
		"Aborted round never receives saved-score confirmation")

	payload["score"] = 37
	payload["round_completed"] = true
	payload["completion_reason"] = "time_up"
	payload["time_remaining"] = 0.0
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", payload)
	await process_frame
	_assert(_client.call("count", "complete_round") == initial_saves + 1,
		"Actual completed round schedules precisely one recovery replay save")
	results = _app.get("active_panel") as Control
	_assert(bool((_app.get("session_state") as Dictionary).get("recovery_pending", false)),
		"Session records locally durable score while awaiting replay")
	var events: Array[Dictionary] = RECOVERY.pending()
	_assert(events.size() == 1 and events[0].get("kind", "") == "score"
		and (events[0].get("data", {}) as Dictionary).get("score", -1) == 37,
		"Completed score is durably recorded before mock HTTP acknowledgement")
	var pending: Dictionary = _client.call("find_pending", "complete_round", "recovery_replay")
	_assert(pending.get("args", {}).get("score", -1) == 37, "Replay sends exact completed score")
	_assert(pending.get("args", {}).get("student_id", "") == "S-001",
		"Recovery replay preserves verified student's ID")
	_assert(_client.call("reply", "complete_round", {
		"ok": true, "status": 201, "data": {"score": {"student_id": "S-001", "score": 37},
			"recovery_pending": false},
	}, "recovery_replay"), "Durable replay acknowledgement reaches Results")
	_assert(RECOVERY.pending().is_empty(), "Acknowledged result removed from isolated outbox")
	_assert(bool((_app.get("session_state") as Dictionary).get("score_saved", false)),
		"Only PostgreSQL replay acknowledgement marks the score saved")
	_assert(not bool((_app.get("session_state") as Dictionary).get("database_saving", true)),
		"Session clears obsolete saving flag after replay acknowledgement")
	_assert(results.get_node_or_null("ResultsStage/SaveStatusBoard") == null,
		"Results has no redundant save-status panel after callback")
	_assert((results.get_node("%ScoreValue") as Label).text == "37",
		"Results keeps actual completion score after callback")
	_app.call("_on_panel_requested", "results", payload)
	await process_frame
	_assert(_client.call("count", "complete_round") == initial_saves + 1,
		"Reloading Results never re-saves a completed round")
	_assert(RECOVERY.pending().is_empty(), "Reloading Results never duplicates acknowledged score")

	# Prove failed writes cannot be rendered as successful.
	payload["score"] = 80
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", payload)
	await process_frame
	_assert(RECOVERY.pending().size() == 1, "Another completed round is durably journaled")
	_assert(_client.call("reply", "complete_round", {
		"ok": false, "status": 503, "error": "database_unavailable", "data": null,
	}, "recovery_replay"), "Failed replay HTTP callback is surfaced")
	results = _app.get("active_panel") as Control
	_assert(not bool((_app.get("session_state") as Dictionary).get("score_saved", true)),
		"Database replay failure never invents persisted score")
	_assert(RECOVERY.pending().size() == 1
		and (RECOVERY.pending()[0].get("data", {}) as Dictionary).get("score", -1) == 80,
		"Failed replay retains exact unacknowledged score for durable retry")
	_assert(not bool((_app.get("session_state") as Dictionary).get("database_saving", true)),
		"Failed write clears pending save without an extra status display")


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
		"completion_reason": "time_up", "time_remaining": 0.0,
		"entry_source": "play", "student_lookup_connected": true,
	}
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", completed)
	await process_frame
	# The preceding failure left score 80 in the journal. Replay that older
	# event first so the 500-point request actually belongs to this new round.
	_assert(_client.call("reply", "complete_round", {
		"ok": true, "status": 201, "data": {"score": {"student_id": "S-001", "score": 80}},
	}, "recovery_replay"), "Previously failed score is replayed before newer same-student score")
	await process_frame
	var in_flight: Dictionary = _client.call("find_pending", "complete_round", "recovery_replay")
	_assert(in_flight.get("args", {}).get("score", -1) == 500,
		"Latest completed score now has its own in-flight replay request")
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
	}, "recovery_replay"), "Delayed completion replay arrives after a different aborted Results view")
	_assert(not bool((_app.get("session_state") as Dictionary).get("score_saved", false)),
		"Old completion callback never labels another aborted round as persisted")
	_assert(not bool((_app.get("session_state") as Dictionary).get("round_completed", false)),
		"Current aborted Results remains incomplete after unrelated old callback")


func _test_stale_registration_response() -> void:
	_app.call("_return_to_main")
	await process_frame
	_app.get_node("MainLayer/CenterMenu/Play").pressed.emit()
	await process_frame
	var form := _app.get("active_panel") as Control
	_client.call("reply", "health", _healthy(), "student_setup_health")
	_fill(form, "BACK-001", "Student Returning Home", "Grade 5")
	(form.get("_continue_button") as Button).pressed.emit()
	_assert(not (_client.call("find_pending", "find_student", "registration_lookup") as Dictionary).is_empty(),
		"Read-only ID validation remains pending until async server reply")
	(form.get("_back_button") as Button).pressed.emit()
	await process_frame
	_assert(_route() == "main", "Teacher can return Main while ID lookup is pending")
	_assert(_client.call("reply", "find_student", {
		"ok": true, "status": 200, "data": {"student": {
			"student_id": "BACK-001", "student_name": "Student Returning Home", "grade_section": "Grade 5",
		}},
	}, "registration_lookup"), "A delayed successful ID lookup can arrive after navigation")
	await process_frame
	_assert(_route() == "main", "Delayed ID lookup callback must not hijack navigation after Back")
	_assert(_app.get("active_panel") == null, "Stale ID lookup never resurrects an abandoned panel")

	_app.get_node("MainLayer/CenterMenu/Play").pressed.emit()
	await process_frame
	form = _app.get("active_panel") as Control
	_client.call("reply", "health", _healthy(), "student_setup_health")
	_fill(form, "EDIT-001", "First Spelling", "Grade 3")
	(form.get("_continue_button") as Button).pressed.emit()
	(form.get("_name_edit") as LineEdit).text = "Corrected Spelling"
	_assert(_client.call("reply", "find_student", {
		"ok": true, "status": 200, "data": {"student": {
			"student_id": "EDIT-001", "student_name": "First Spelling", "grade_section": "Grade 3",
		}},
	}, "registration_lookup"), "An old ID lookup can finish after name is corrected")
	await process_frame
	_assert(_route() == "student_setup",
		"Stale ID lookup response must not advance after teacher edits name during request")
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
	checks += 1
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
		" (%d assertions, %d failures)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
