extends SceneTree

## Recovery and security regression for real Main Menu UI and in-memory service.
## Run: Godot --headless --path . --script res://tools/test_postgres_service_recovery.gd
## Never starts PostgreSQL, PowerShell, the Python API, or any actual HTTP port.
const RECOVERY_MENU := "res://tools/test_postgres_recovery_menu.gd"
var _app: Control
var _mock: Node
var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://main_menu.tscn") as PackedScene
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
		return
	var status := form.get("_database_status") as Label
	_check(int(_mock.get("ensure_calls")) >= 2,
		"Entering the form automatically assures the local service")
	_mock.call("probe", false)
	_check(not bool(_app.get("database_online")), "Internal unsuccessful health probe cannot declare connected")
	_mock.call("heartbeat")
	_check(not bool(_app.get("database_online")),
		"Repeated fake server-down heartbeats keep database unconfirmed")
	_check(not status.text.contains("OFFLINE"),
		"Retries do not prematurely show final offline state")
	var secret := "DO_NOT_RENDER_TEST_SECRET_947321"
	_mock.call("finish_offline", "setup_required", {
		"password": secret, "connection_uri": "postgresql://" + secret,
		"raw_error": "auth token " + secret,
	})
	var recovery_button := form.get("_database_recovery_button") as Button
	_check(status.text.contains("OFFLINE") and status.text.contains("SET UP LOCAL DATABASE"),
		"Offline first use shows actionable secure local teacher setup instructions")
	_check(recovery_button != null and recovery_button.visible
		and recovery_button.text.contains("SET UP LOCAL DATABASE"),
		"Offline first use exposes a visible native button to configure PostgreSQL")
	_check(status.text.contains("will not save"), "Offline first use explicitly warns about unsaved scores")
	_check(not status.text.contains(secret), "Sensitive details never appear in native student form")
	_check(not str(_app.get("session_state")).contains(secret),
		"Service-provided sensitive details are never copied into session state")
	_mock.call("ensure_local_service", {"purpose": "retry_no_secret"})
	_mock.call("heartbeat")
	_check(status.text.contains("CONNECTING") and not status.text.contains(secret),
		"New attempt replaces stale error with safe connecting message")
	_mock.call("finish_offline", "database_auth_or_schema", {
		"password": secret,
	})
	_check(status.text.contains("SET UP LOCAL DATABASE") and not status.text.contains(secret),
		"Authentication/schema failure offers secure setup without rendering credentials")
	_check(recovery_button.visible and recovery_button.text.contains("SET UP LOCAL DATABASE"),
		"Auth/schema configuration problem retains the setup action")
	recovery_button.pressed.emit()
	_check(status.text.contains("Available on the Windows computer running Godot"),
		"Teacher Setup action is handled safely in headless test without launching PowerShell")
	_check(int(_mock.get("launch_attempts")) == 0,
		"Headless secure setup does not spawn a subprocess")
	_mock.call("finish_offline", "server_unreachable")
	_check(recovery_button.visible and recovery_button.text.contains("RETRY LOCAL CONNECTION"),
		"Temporary outage exposes explicit native Retry Connection button")
	var ensures_before: int = _mock.get("ensure_calls")
	recovery_button.pressed.emit()
	_check(int(_mock.get("ensure_calls")) == ensures_before + 1,
		"Retry Connection button forwards a fresh local-service ensure request")


func _test_restore_and_queued_lookup() -> void:
	var form := _app.get("active_panel") as Control
	var field := form.get("_student_id_edit") as LineEdit
	field.text = "R-001"
	field.text_changed.emit(field.text)
	form.call("_update_validation")
	(form.get("_lookup_button") as Button).pressed.emit()
	_check(String(_app.get("database_pending_lookup_id")) == "R-001",
		"Offline profile lookup is queued using the exact student ID")
	_check(_mock.call("count", "find_student") == 0,
		"No student query is issued while fake service is unavailable")
	_check(bool(_mock.get("watch_active")), "Offline lookup starts a logical watchdog attempt")
	_mock.call("heartbeat")
	_check(String(_app.get("database_pending_lookup_id")) == "R-001"
		and not bool(_app.get("database_online")),
		"Retry heartbeat does not consume queued student ID or declare connected")
	_mock.call("restore_service")
	_mock.call("probe", true)
	_check(not bool(_app.get("database_online")),
		"Healthy internal probe alone cannot prematurely finalize reconnect")
	_mock.call("heartbeat")
	_check(bool(_app.get("database_online")),
		"Fake server restoration flips Main Menu to online at the lifecycle event")
	_check(String(_app.get("database_pending_lookup_id")).is_empty(),
		"Queued student lookup is consumed exactly once upon recovery")
	_check(_mock.call("count", "find_student") == 1,
		"Automatic recovery issues exactly one real profile lookup request")
	_check(_mock.call("reply", "find_student", {
		"ok": true, "status": 200,
		"data": {"student": {"student_id": "R-001",
			"student_name": "Recovered Student", "grade_section": "Grade 4"}},
	}, "student_lookup"), "Recovered profile reply reaches current native form")
	_check((form.get("_name_edit") as LineEdit).text == "Recovered Student",
		"Verified student fields fill after fake server restoration")
	_check((form.get("_database_status") as Label).text.contains("STUDENT FOUND"),
		"Recovered profile shows accurate lookup success")


func _test_stale_async_lookup_response() -> void:
	var form := _app.get("active_panel") as Control
	var field := form.get("_student_id_edit") as LineEdit
	field.text = "R-OLD"
	field.text_changed.emit(field.text)
	form.call("_update_validation")
	(form.get("_lookup_button") as Button).pressed.emit()
	_check(_mock.call("count", "find_student") == 2,
		"Online lookup is issued for original student ID")
	field.text = "R-NEW"
	field.text_changed.emit(field.text)
	_check(_mock.call("reply", "find_student", {
		"ok": true, "status": 200,
		"data": {"student": {"student_id": "R-OLD",
			"student_name": "Must Not Leak", "grade_section": "Wrong Student"}},
	}, "student_lookup"), "Late successful lookup for abandoned ID can arrive")
	_check((form.get("_name_edit") as LineEdit).text.is_empty()
		and (form.get("_grade_edit") as LineEdit).text.is_empty(),
		"Delayed response never overwrites newly edited student identity")
	_check((form.get("_database_status") as Label).text.contains("REJECTED"),
		"Stale lookup is explicitly rejected in teacher UI")
	_mock.call("lose_service")
	_check(not bool(_app.get("database_online")), "Terminal connection loss marks UI offline")
	(form.get("_lookup_button") as Button).pressed.emit()
	_check(String(_app.get("database_pending_lookup_id")) == "R-NEW",
		"Second offline lookup queues latest student ID")
	field.text = "R-FINAL"
	field.text_changed.emit(field.text)
	_mock.call("restore_service")
	_mock.call("heartbeat")
	_check(_mock.call("count", "find_student") == 2,
		"Recovered connection refuses stale queued lookup after field edit")
	_check(String(_app.get("database_pending_lookup_id")).is_empty(),
		"Stale queued request cleared on recovery")
	_check((form.get("_student_id_edit") as LineEdit).text == "R-FINAL",
		"Latest identity remains intact")


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
		"activity": "Balloon Popping", "round_completed": true, "score": 19}
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", round)
	await process_frame
	_check(_route() == "results", "Completed round opens the real Results scene")
	var results := _app.get("active_panel") as Control
	var label := results.get_node("%SaveStatus") as Label
	_check(_mock.call("count", "complete_round") == initial_saves,
		"Completed offline result never attempts database save")
	_check(label.text.contains("SCORE NOT SAVED") and not label.text.contains("SCORE SAVED TO"),
		"Offline Results truthfully says the score was not saved")
	_app.call("_return_to_main")
	await process_frame
	_mock.call("restore_service")
	_mock.call("ensure_local_service", {"purpose": "watchdog_recover"})
	_mock.call("heartbeat")
	_check(bool(_app.get("database_online")), "Restored fake server returns online before new completion")
	_app.set("current_route", "gameplay")
	_app.call("_on_panel_requested", "results", round)
	await process_frame
	_check(_mock.call("count", "complete_round") == initial_saves + 1,
		"Completed online round sends exactly one save request")
	results = _app.get("active_panel") as Control
	label = results.get_node("%SaveStatus") as Label
	_check(label.text.contains("SAVING COMPLETED SCORE"),
		"While completion awaits DB response, Results displays saving state")
	_check(_mock.call("reply", "complete_round", {
		"ok": false, "status": 503, "error": "database_unavailable", "data": null,
	}, "completed_round"), "Failed in-flight save can arrive after service recovery")
	_check(label.text.contains("SCORE NOT SAVED")
		and not bool((_app.get("session_state") as Dictionary).get("score_saved", true)),
		"Failed save never reports invented persisted points")
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
	label = results.get_node("%SaveStatus") as Label
	_check(label.text.contains("ROUND NOT COMPLETED")
		and _mock.call("count", "complete_round") == initial_saves,
		"Aborted round never saves scores even after recovery")
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
