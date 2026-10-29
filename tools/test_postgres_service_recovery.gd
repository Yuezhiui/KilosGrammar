extends SceneTree

## Recovery and security regression for real Main Menu UI and in-memory service.
## Run: Godot --headless --path . --script res://tools/test_postgres_service_recovery.gd
## Never starts PostgreSQL, PowerShell, the Python API, or any actual HTTP port.
const RECOVERY_MENU := "res://tools/test_postgres_recovery_menu.gd"
const RECOVERY := preload("res://ui/database/recovery_journal.gd")
var _app: Control
var _mock: Node
var _failures: Array[String] = []
var _checks := 0
var _test_recovery_dir := ""


func _initialize() -> void:
	# Do not mount MainMenu until every outbox call is redirected to this run.
	_test_recovery_dir = "user://test_recovery_service_%d_%d" % [
		OS.get_process_id(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("kilos/recovery_test_directory", _test_recovery_dir)
	call_deferred("_run")


func _run() -> void:
	_check(RECOVERY._directory() == _test_recovery_dir
		and _test_recovery_dir.begins_with("user://test_recovery_"),
		"Mock service recovery uses an isolated per-run user:// outbox")
	_check(RECOVERY.pending().is_empty(), "Isolated service test outbox begins empty")
	root.size = Vector2i(1280, 720)
	var packed := load("res://ui/main_menu/main_menu.tscn") as PackedScene
	_check(packed != null, "Main Menu real scene loads")
	if packed == null:
		quit(1)
		return
	_app = packed.instantiate() as Control
	var subclass := load(RECOVERY_MENU) as Script
	_check(subclass != null and subclass.can_instantiate(),
		"Recovery subclass loads with Godot autoloads present")
	if subclass == null or not subclass.can_instantiate():
		_app.free()
		quit(1)
		return
	_app.set_script(subclass)
	root.add_child(_app)
	await process_frame
	_mock = _app.get("database_client") as Node
	_check(is_instance_valid(_mock), "Real UI uses mock client without network")
	if not is_instance_valid(_mock):
		await _finish()
		return
	_check(_mock.get_child_count() == 0, "No HTTPRequest or timer instantiated")
	_check(_mock.call("count", "ensure_local_service") == 1,
		"Main Menu automatically requests local service startup on first launch")
	_check(int(_mock.get("launch_attempts")) == 0,
		"Mock never starts local API or PowerShell subprocess")
	_check(not bool(_app.get("database_online")), "First-use state starts unconfirmed")

	await _test_first_use_setup_and_secret_safety()
	await _test_restore_and_queued_lookup()
	await _test_stale_async_lookup_response()
	await _test_leaderboard_recovery_and_inflight_race()
	await _test_results_save_truth()
	await _finish()


func _test_first_use_setup_and_secret_safety() -> void:
	(_app.get_node("MainLayer/CenterMenu/Play") as Button).pressed.emit()
	await process_frame
	_check(_route() == "student_setup", "Play button opens editor-authored student form")
	var form := _app.get("active_panel") as Control
	if form == null:
		_check(false, "Student Setup panel mounted for first-use security test")
		return
	_check(int(_mock.get("ensure_calls")) >= 2,
		"Entering the form automatically assures the local service")
	_check(form.find_child("DatabasePanel", true, false) == null
		and form.find_child("LookupButton", true, false) == null
		and form.find_child("DatabaseRecoveryButton", true, false) == null,
		"Retired database status/lookup/recovery buttons are not visible")
	_mock.call("probe", false)
	_check(not bool(_app.get("database_online")), "Internal unsuccessful health probe cannot declare connected")
	_mock.call("heartbeat")
	_check(not bool(_app.get("database_online")),
		"Repeated fake server-down heartbeats keep database unconfirmed")
	var secret := "DO_NOT_RENDER_TEST_SECRET_947321"
	_mock.call("finish_offline", "setup_required", {
		"password": secret, "connection_uri": "postgresql://" + secret,
		"raw_error": "auth token " + secret,
	})
	_check(bool(_app.get("database_setup_required")),
		"First-use schema setup still recorded internally without student-facing warning")
	_check(not str(_app.get("session_state")).contains(secret),
		"Service-provided secrets are never copied into session data")
	_check(not str(form.get("context")).contains(secret)
		and form.find_child("DatabaseStatus", true, false) == null,
		"Sensitive diagnostic text cannot render in the student form")
	_mock.call("ensure_local_service", {"purpose": "retry_no_secret"})
	_mock.call("heartbeat")
	_check(not bool(_app.get("database_online")), "Service retry remains pending until healthy")
	_mock.call("finish_offline", "database_auth_or_schema", {"password": secret})
	_check(bool(_app.get("database_setup_required")),
		"Authentication/schema problem remains available to the internal recovery controller")
	_check(not str(form.get("context")).contains(secret),
		"Repeated auth failure does not leak diagnostic credentials")
	_mock.call("finish_offline", "server_unreachable")
	_check(not bool(_app.get("database_setup_required")),
		"Transient outage does not pose as a permanent schema problem")
	var ensures_before: int = _mock.get("ensure_calls")
	_app.call("_ensure_database_service")
	_check(int(_mock.get("ensure_calls")) == ensures_before + 1,
		"Internal nonblocking watchdog retries without a visible setup button")
	_check(int(_mock.get("launch_attempts")) == 0,
		"Headless mock never launches Python/PostgreSQL/PowerShell subprocesses")

func _test_restore_and_queued_lookup() -> void:
	var form := _app.get("active_panel") as Control
	var field := form.get("_student_id_edit") as LineEdit
	# Emulate a previously completed OFFLINE registration persisted locally.
	# Only exact-ID matches may fill from local recovery: the name roster is
	# incomplete until the real PostgreSQL connection returns.
	var durable: Dictionary = RECOVERY.enqueue_profile("R-001", "Recovered Student", "Grade 4")
	_check(bool(durable.get("ok", false)), "Offline profile is durably stored in isolated user:// outbox")
	field.text = "R-001"
	field.text_changed.emit(field.text)
	form.call("_autofill_if_unchanged")
	_check(_mock.call("count", "find_student") == 0,
		"Offline exact-ID recovery uses durable local record without network")
	_check((form.get("_name_edit") as LineEdit).text == "Recovered Student"
		and (form.get("_grade_edit") as LineEdit).text == "Grade 4",
		"Exact ID from local outbox fills identity in offline mode")
	_check(bool(form.get("context").get("student_lookup_connected", false)),
		"Exact offline profile is marked resolved by local recovery")
	_mock.call("heartbeat")
	_check(not bool(_app.get("database_online")), "Retry heartbeat cannot claim early reconnection")
	_mock.call("restore_service")
	_mock.call("probe", true)
	_check(not bool(_app.get("database_online")),
		"Healthy internal probe alone cannot prematurely finalize reconnect")
	_mock.call("heartbeat")
	_check(bool(_app.get("database_online")),
		"Fake server restoration flips Main Menu to online at lifecycle event")
	await process_frame
	_check(not (_mock.call("find_pending", "register_student", "recovery_replay") as Dictionary).is_empty(),
		"Recovered service begins replaying durable offline student registration")
	_check(_mock.call("reply", "register_student", {
		"ok": true, "status": 201,
		"data": {"student": {"student_id": "R-001", "student_name": "Recovered Student"}},
	}, "recovery_replay"), "PostgreSQL accepts and acknowledges exact queued student profile")
	_check(RECOVERY.pending().is_empty(), "Acknowledged recovery profile removed from isolated outbox")
	field.text = "R-002"
	field.text_changed.emit(field.text)
	form.call("_autofill_if_unchanged")
	_check(_mock.call("count", "find_student") == 1,
		"Online automatic ID lookup issues one HTTP request after idle")
	var pending: Dictionary = _mock.call("find_pending", "find_student", "autofill")
	_check(pending.get("args", {}).get("student_id", "") == "R-002",
		"Online autofill submits exact new ID")
	_check(_mock.call("reply", "find_student", {
		"ok": true, "status": 200,
		"data": {"student": {"student_id": "R-002",
			"student_name": "Another Student", "grade_section": "Grade 5"}},
	}, "autofill"), "Recovered online student lookup callback arrives")
	_check((form.get("_name_edit") as LineEdit).text == "Another Student"
		and (form.get("_grade_edit") as LineEdit).text == "Grade 5",
		"Server-verified student fields fill after recovery")

func _test_stale_async_lookup_response() -> void:
	var form := _app.get("active_panel") as Control
	var field := form.get("_student_id_edit") as LineEdit
	field.text = "R-OLD"
	field.text_changed.emit(field.text)
	form.call("_autofill_if_unchanged")
	_check(_mock.call("count", "find_student") == 2,
		"Online automatic lookup is issued for original student ID")
	field.text = "R-NEW"
	field.text_changed.emit(field.text)
	_check(_mock.call("reply", "find_student", {
		"ok": true, "status": 200,
		"data": {"student": {"student_id": "R-OLD",
			"student_name": "Must Not Leak", "grade_section": "Wrong Student"}},
	}, "autofill"), "Late successful autofill for abandoned ID can arrive")
	_check((form.get("_name_edit") as LineEdit).text.is_empty()
		and (form.get("_grade_edit") as LineEdit).text.is_empty(),
		"Stale response never overwrites newly edited student identity")
	_check((form.get("_student_id_edit") as LineEdit).text == "R-NEW",
		"Abandoned response cannot rewrite latest ID")
	_mock.call("lose_service")
	_check(not bool(_app.get("database_online")), "Terminal connection loss marks UI offline")
	form.call("_autofill_if_unchanged")
	_check(_mock.call("count", "find_student") == 2,
		"Offline lookup does not issue a live student query")
	field.text = "R-FINAL"
	field.text_changed.emit(field.text)
	_mock.call("restore_service")
	_mock.call("ensure_local_service", {"purpose": "reconnect_for_autofill"})
	_mock.call("heartbeat")
	_check(_mock.call("count", "find_student") == 2,
		"Recovery cannot implicitly replay stale, obsolete ID searches")
	field.text_changed.emit(field.text)
	form.call("_autofill_if_unchanged")
	_check(_mock.call("count", "find_student") == 3
		and (_mock.call("find_pending", "find_student", "autofill") as Dictionary)
			.get("args", {}).get("student_id", "") == "R-FINAL",
		"Fresh current ID can be searched after reconnection")

func _test_leaderboard_recovery_and_inflight_race() -> void:
	_app.call("_return_to_main")
	await process_frame
	_mock.call("lose_service")
	var fetch_before: int = _mock.call("count", "get_leaderboard")
	(_app.get_node("MainLayer/LeftMenu/Leaderboard") as Button).pressed.emit()
	await process_frame
	_check(_route() == "leaderboard", "Native Leaderboard opens while local service is offline")
	var board := _app.get("active_panel") as Control
	var rows := board.get_node("%ScoreRows") as VBoxContainer
	var empty := board.get_node("%EmptyMessage") as Label
	_check(rows.get_child_count() == 0 and empty.text.contains("Loading"),
		"Offline leaderboard only shows a pending load, never demonstration scores")
	_check(_mock.call("count", "get_leaderboard") == fetch_before,
		"Unavailable service cannot send leaderboard HTTP request")
	_mock.call("finish_offline", "setup_required")
	_check(rows.get_child_count() == 0 and empty.text.contains("database unavailable"),
		"Final failure displays database unavailable with zero scores")
	_mock.call("restore_service")
	_mock.call("ensure_local_service", {"purpose": "manual_watchdog_resume"})
	_mock.call("heartbeat")
	_check(bool(_app.get("database_online")), "Recovered service becomes online")
	_check(_mock.call("count", "get_leaderboard") == fetch_before + 1,
		"Online status fetches actual leaderboard records once")
	_check(_mock.call("reply", "get_leaderboard", {
		"ok": true, "status": 200,
		"data": {"leaderboard": [{"student_id": "R-001", "student_name": "Recovered Student",
			"grade_section": "Grade 4", "game_style": "Noun",
			"game_mode": "Seconds", "difficulty": "Easy", "score": 12}]},
	}, "leaderboard"), "Fake restored service returns one completed score")
	_check(rows.get_child_count() == 1
		and (rows.get_child(0).get_node("Score") as Label).text == "12",
		"Only returned completed score is rendered")
	# A stale successful response from a request made while previously online
	# should never revive scores after a terminal offline lifecycle transition.
	_mock.call("ensure_local_service", {"purpose": "fresh_health"})
	_mock.call("heartbeat")
	_check(_mock.call("count", "get_leaderboard") == fetch_before + 2,
		"Refresh creates an in-flight leaderboard query")
	_mock.call("lose_service")
	_check(rows.get_child_count() == 0 and empty.text.contains("database unavailable"),
		"Terminal service loss clears prior scores before stale callback")
	_check(_mock.call("reply", "get_leaderboard", {
		"ok": true, "status": 200,
		"data": {"leaderboard": [{"student_id": "STALE-RANK", "score": 999,
			"game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy"}]},
	}, "leaderboard"), "Stale leaderboard callback can arrive after offline transition")
	_check(rows.get_child_count() == 0 and empty.text.contains("database unavailable")
		and not bool(_app.get("database_online")),
		"Late query must not resurrect an offline leaderboard or fake an online state")
	# Prove that an old request from BEFORE a disconnect cannot supersede the
	# newer request that completed AFTER the next successful watchdog recovery.
	_mock.call("restore_service")
	_mock.call("ensure_local_service", {"purpose": "recovery_cycle_A"})
	_mock.call("heartbeat")
	_check(bool(_app.get("database_online")),
		"First recovery cycle reconnects with an in-flight leaderboard request")
	_mock.call("lose_service")
	_mock.call("restore_service")
	_mock.call("ensure_local_service", {"purpose": "recovery_cycle_B"})
	_mock.call("heartbeat")
	_check(bool(_app.get("database_online")),
		"Second recovery cycle initiates a fresh leaderboard read")
	_check(_mock.call("reply", "get_leaderboard", {
		"ok": true, "status": 200,
		"data": {"leaderboard": [{"student_id": "NEW-RANK", "score": 33,
			"game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy"}]},
	}, "leaderboard"), "Newest leaderboard request returns one genuine score")
	_check(rows.get_child_count() == 1
		and (rows.get_child(0).get_node("Score") as Label).text == "33",
		"Latest saved leaderboard score is rendered after recovery")
	_check(_mock.call("reply_oldest", "get_leaderboard", {
		"ok": true, "status": 200,
		"data": {"leaderboard": [{"student_id": "OLD-RANK", "score": 900,
			"game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy"}]},
	}, "leaderboard"), "Pre-disconnect leaderboard response arrives after the fresh result")
	_check(rows.get_child_count() == 1
		and (rows.get_child(0).get_node("Score") as Label).text == "33",
		"Old out-of-order response cannot overwrite newer recovered scores")


func _test_results_save_truth() -> void:
	_app.call("_return_to_main")
	await process_frame
	_mock.call("lose_service")
	_check(not bool(_app.get("database_online")),
		"Results offline fixture starts after explicit terminal service loss")
	var initial_saves: int = _mock.call("count", "complete_round")
	var round := {"student_id": "R-001", "student_name": "Recovered Student",
		"grade_section": "Grade 4", "game_style": "Noun",
		"game_mode": "Seconds", "difficulty": "Easy",
		"activity": "Balloon Popping", "round_completed": true, "score": 19,
		"entry_source": "play", "student_lookup_connected": true}
	_check(RECOVERY.pending().is_empty(), "No recovery event left from registration or leaderboard tests")
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", round)
	await process_frame
	_check(_route() == "results", "Completed round opens the real Results scene")
	var results := _app.get("active_panel") as Control
	_check(_mock.call("count", "complete_round") == initial_saves,
		"Offline completion creates no network call while service is disconnected")
	var queued: Array[Dictionary] = RECOVERY.pending()
	_check(queued.size() == 1 and queued[0].get("kind", "") == "score"
		and (queued[0].get("data", {}) as Dictionary).get("score", -1) == 19,
		"Offline completed score is durably stored in test-only recovery journal")
	_check(bool((_app.get("session_state") as Dictionary).get("recovery_pending", false)),
		"Offline completed score is marked as pending durable recovery")
	_check(not bool((_app.get("session_state") as Dictionary).get("score_saved", true))
		and results.get_node_or_null("%SaveStatus") == null,
		"Offline Results keeps unsaved state without redundant save-status UI")
	_check(not bool((_app.get("session_state") as Dictionary).get("database_saving", true)),
		"Offline journal handoff cannot leave legacy HTTP saving indicator active")
	_mock.call("restore_service")
	_mock.call("ensure_local_service", {"purpose": "watchdog_recover"})
	_mock.call("heartbeat")
	_check(bool(_app.get("database_online")), "Restored fake server returns online before new completion")
	await process_frame
	var oldest: Dictionary = _mock.call("find_pending", "complete_round", "recovery_replay")
	_check(oldest.get("args", {}).get("score", -1) == 19
		and oldest.get("args", {}).get("student_id", "") == "R-001",
		"Connection recovery replays exact oldest offline score in order")
	_check(_mock.call("reply", "complete_round", {
		"ok": true, "status": 201, "data": {"score": {"score": 19}, "recovery_pending": false},
	}, "recovery_replay"), "Successful PostgreSQL replay acknowledges original offline result")
	_check(RECOVERY.pending().is_empty(), "Acknowledged offline score removed from isolated journal")
	_check(bool((_app.get("session_state") as Dictionary).get("score_saved", false))
		and not bool((_app.get("session_state") as Dictionary).get("database_saving", true)),
		"Replay acknowledgement marks score saved and clears pending status")
	_app.call("_return_to_main")
	await process_frame
	var next_round := round.duplicate(true)
	next_round["score"] = 20
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", next_round)
	await process_frame
	_check(_mock.call("count", "complete_round") == initial_saves + 2,
		"Completed online round adds exactly one new replay request after first acknowledgement")
	results = _app.get("active_panel") as Control
	_check(RECOVERY.pending().size() == 1
		and (RECOVERY.pending()[0].get("data", {}) as Dictionary).get("score", -1) == 20,
		"Even online completion is first durably journaled, not sent without a local copy")
	_check(_mock.call("reply", "complete_round", {
		"ok": false, "status": 503, "error": "database_unavailable", "data": null,
	}, "recovery_replay"), "Failed replay can arrive after service recovery")
	_check(not bool((_app.get("session_state") as Dictionary).get("score_saved", true))
		and not bool((_app.get("session_state") as Dictionary).get("database_saving", true)),
		"Failed replay never reports invented persisted points or stale saving flag")
	_check(RECOVERY.pending().size() == 1
		and (RECOVERY.pending()[0].get("data", {}) as Dictionary).get("score", -1) == 20,
		"Failed replay keeps score durably queued for future retry")
	_app.call("_return_to_main")
	await process_frame
	var aborted := round.duplicate(true)
	aborted["round_completed"] = false
	aborted["score"] = 42
	initial_saves = _mock.call("count", "complete_round")
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", aborted)
	await process_frame
	results = _app.get("active_panel") as Control
	_check(not bool((_app.get("session_state") as Dictionary).get("round_completed", false))
		and _mock.call("count", "complete_round") == initial_saves,
		"Aborted round never saves scores even after recovery")
	_check(RECOVERY.pending().size() == 1,
		"Aborted round cannot add a new durable journal event")
	_check(int(_mock.get("launch_attempts")) == 0 and _mock.get_child_count() == 0,
		"All recovery tests finished without any child process or HTTP socket")


func _route() -> String:
	return String(_app.get("current_route"))


func _check(passed: bool, description: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(description)
		printerr("FAIL Postgres recovery: ", description)


func _finish() -> void:
	if is_instance_valid(_app):
		_app.call("_return_to_main")
		_app.queue_free()
		await process_frame
		await process_frame
	print("POSTGRES MOCK RECOVERY: ",
		"PASS" if _failures.is_empty() else "FAIL",
		" (%d assertions, %d failures)" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
