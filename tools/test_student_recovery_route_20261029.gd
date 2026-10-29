extends SceneTree
## Actual MainMenu → new Student Setup → Results route with a deliberately
## unavailable HTTP/PostgreSQL mock. Every write is checked on local disk,
## followed by a simulated server recovery. No real API/DB/camera is opened.
const MAIN := "res://ui/main_menu/main_menu.tscn"
const MOCK_MAIN := "res://tools/test_postgres_main_menu.gd"
const JOURNAL := preload("res://ui/database/recovery_journal.gd")

var failures: Array[String] = []
var checks := 0
var app: Control
var mock: Node
var ids: Array[String] = []
var storage_prefix := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	storage_prefix = "user://test_recovery_defense_" + str(Time.get_ticks_usec())
	ProjectSettings.set_setting("kilos/recovery_test_directory", storage_prefix)
	var scene := load(MAIN) as PackedScene
	var subclass := load(MOCK_MAIN) as Script
	_check(scene != null and subclass != null, "real menu scene and isolated mock script load")
	if scene == null or subclass == null:
		_finish()
		return
	app = scene.instantiate() as Control
	app.set_script(subclass)
	root.add_child(app)
	await process_frame
	mock = app.get("database_client") as Node
	_check(mock != null and mock.has_method("count"), "mock API has no HTTP requests")
	_check(not bool(app.get("database_online")), "simulate PostgreSQL and API outage")
	var play := app.get_node("MainLayer/CenterMenu/Play") as Button
	play.pressed.emit()
	await process_frame
	_check(String(app.get("current_route")) == "student_setup", "real menu opens new setup")
	var form := app.get("active_panel") as Control
	_check(form != null, "student setup actually mounted")
	if form == null:
		_finish()
		return
	var student_id := "QA-DEFS-" + str(Time.get_ticks_usec())
	var student_name := "Recovery Safety Student"
	(form.get("_student_id_edit") as LineEdit).text = student_id
	(form.get("_name_edit") as LineEdit).text = student_name
	(form.get("_grade_edit") as LineEdit).text = "Grade 4 - Rose"
	form.call("_select_style", "Noun")
	form.call("_select_mode", "Seconds")
	form.call("_select_difficulty", "Easy")
	form.call("_update_validation")
	_check(not (form.get("_continue_button") as Button).disabled, "complete new setup enables Continue")
	(form.get("_continue_button") as Button).pressed.emit()
	await process_frame
	_check(String(app.get("current_route")) == "play_activity",
		"offline storage allows game setup to continue")
	var session: Dictionary = app.get("session_state")
	_check(bool(session.get("registration_deferred", false))
		and not bool(session.get("recovery_profile_queued", false)),
		"new student registration is deferred until a completed Play round")
	var queued: Array[Dictionary] = JOURNAL.pending()
	_check(queued.is_empty() and int(mock.call("count", "register_student")) == 0,
		"Continue writes neither profile nor score, locally or via mocked API")
	# Exiting halfway through a game, even with nonzero points and a misleading
	# round_completed flag, cannot enqueue a profile or a score.
	var interrupted := session.duplicate(true)
	interrupted["activity"] = "Catch the Word"
	interrupted["score"] = 199
	interrupted["round_completed"] = true
	interrupted["completion_reason"] = "manual"
	interrupted["time_remaining"] = 0.0
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", interrupted)
	await process_frame
	_check(JOURNAL.pending().is_empty(), "manual results refuse profile and score despite forged completed flag")
	_check(not bool((app.get("session_state") as Dictionary).get("round_completed", true)),
		"aborted Results cannot inherit a completed flag")
	app.call("_return_to_main")
	await process_frame
	_check(JOURNAL.pending().is_empty(), "teacher Back and forced-exit equivalent leave no recovery records")
	# Start the same new student again and finish a legitimate Seconds round.
	play.pressed.emit()
	await process_frame
	form = app.get("active_panel") as Control
	(form.get("_student_id_edit") as LineEdit).text = student_id
	(form.get("_name_edit") as LineEdit).text = student_name
	(form.get("_grade_edit") as LineEdit).text = "Grade 4 - Rose"
	form.call("_select_style", "Noun")
	form.call("_select_mode", "Seconds")
	form.call("_select_difficulty", "Easy")
	form.call("_update_validation")
	(form.get("_continue_button") as Button).pressed.emit()
	await process_frame
	session = app.get("session_state")
	_check(JOURNAL.pending().is_empty(), "restarting unfinished student writes no profile during setup")
	# Score from the real route cannot rely on an old lookup flag: completed
	# round must still be durable when its new student's API registration is queued.
	var complete := session.duplicate(true)
	complete["activity"] = "Catch the Word"
	complete["score"] = 407
	complete["round_completed"] = true
	complete["completion_reason"] = "time_up"
	complete["time_remaining"] = 0.0
	complete["entry_source"] = "play"
	complete["guided_tutorial"] = false
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", complete)
	await process_frame
	_check(String(app.get("current_route")) == "results", "completed gameplay opens actual Results")
	queued = JOURNAL.pending()
	_check(queued.size() == 1 and String(queued[0].get("kind", "")) == "completed_round",
		"new student's completed identity and score are one atomic recovery event")
	if queued.size() != 1:
		_finish()
		return
	var profile: Dictionary = queued[0].get("data", {})
	_check(String(profile.get("student_id", "")) == student_id
		and String(profile.get("student_name", "")) == student_name,
		"only the finished round writes exact teacher-entered identity")
	var score: Dictionary = queued[0].get("data", {})
	_check(int(score.get("score", -1)) == 407
		and String(score.get("minigame", "")) == "Catch the Word",
		"durable score keeps actual points and game identity")
	_check(int(mock.call("count", "complete_round")) == 0,
		"no invented PostgreSQL success or requests during API outage")
	# Verify synthetic reconnect and ordering: register profile FIRST, then
	# completed round, acknowledging local files only on successful responses.
	app.call("_on_database_local_service_status_changed", "online", {})
	await process_frame
	var pending: Dictionary = mock.call("find_pending", "register_student", "recovery_replay")
	_check(not pending.is_empty(), "reconnected service first receives saved student profile")
	_check(String(pending.get("args", {}).get("student_id", "")) == student_id,
		"replayed registration is for exact verified ID")
	_check(bool(mock.call("reply", "register_student", {
		"ok": true, "status": 201,
		"data": {"student": profile, "recovery_pending": true},
	}, "recovery_replay")), "durable SQLite acceptance acknowledges profile")
	await process_frame
	_check(JOURNAL.pending().size() == 1 and String(JOURNAL.pending()[0].get("id", "")) == String(queued[0].get("id", "")),
		"composite event remains fully recoverable until score is acknowledged")
	pending = mock.call("find_pending", "complete_round", "recovery_replay")
	_check(not pending.is_empty(), "score replays after registration, never before it")
	_check(int(pending.get("args", {}).get("score", -1)) == 407,
		"replayed score payload unchanged")
	_check(bool(mock.call("reply", "complete_round", {
		"ok": false, "status": 503, "error": "database_unavailable",
	}, "recovery_replay")), "failed score half of atomic event is observable")
	await process_frame
	_check(JOURNAL.pending().size() == 1,
		"failed score half leaves complete student and score event intact")
	# Restart-style retry safely repeats the idempotent profile registration
	# before submitting the same completed score again.
	app.call("_flush_recovery_outbox")
	await process_frame
	pending = mock.call("find_pending", "register_student", "recovery_replay")
	_check(not pending.is_empty(), "retry resumes atomic event from profile registration")
	_check(bool(mock.call("reply", "register_student", {
		"ok": true, "status": 200, "data": {"student": profile},
	}, "recovery_replay")), "idempotent already-present student profile accepted")
	await process_frame
	pending = mock.call("find_pending", "complete_round", "recovery_replay")
	_check(int(pending.get("args", {}).get("score", -1)) == 407,
		"retry submits the original completed score unchanged")
	_check(bool(mock.call("reply", "complete_round", {
		"ok": true, "status": 200,
		"data": {"score": score, "recovery_pending": true},
	}, "recovery_replay")), "SQLite fallback can accept score while PostgreSQL remains down")
	await process_frame
	_check(JOURNAL.pending().is_empty(),
		"Godot outbox acks ONLY after service safely records both in SQLite")
	_check(bool((app.get("session_state") as Dictionary).get("recovery_pending", false)),
		"SQLite-only success never falsely claims PostgreSQL sync")
	# The old two-file completed format remains replayable across the upgrade.
	var legacy_profile := JOURNAL.enqueue_profile("QA-LEGACY-001", "Legacy Complete", "Grade 4")
	var legacy_score := JOURNAL.enqueue_score("QA-LEGACY-001", "Noun", "Seconds",
		"Easy", "Catch the Word", 241)
	_check(bool(legacy_profile.get("ok", false)) and bool(legacy_score.get("ok", false)),
		"legacy profile+score fixture stored inside test-only outbox")
	app.call("_flush_recovery_outbox")
	await process_frame
	pending = mock.call("find_pending", "register_student", "recovery_replay")
	_check(String(pending.get("args", {}).get("student_id", "")) == "QA-LEGACY-001",
		"legacy first profile replay unchanged")
	_check(bool(mock.call("reply", "register_student", {
		"ok": true, "data": {"student": {"student_id": "QA-LEGACY-001"}},
	}, "recovery_replay")), "legacy profile replay acknowledged")
	await process_frame
	pending = mock.call("find_pending", "complete_round", "recovery_replay")
	_check(int(pending.get("args", {}).get("score", -1)) == 241,
		"legacy score replay follows acknowledged profile")
	_check(bool(mock.call("reply", "complete_round", {
		"ok": true, "data": {"score": {"score": 241}, "recovery_pending": false},
	}, "recovery_replay")), "legacy completed score acknowledged")
	await process_frame
	_check(JOURNAL.pending().is_empty(), "legacy two-event completion fully replayed")
	# A legacy profile left at Continue by an older build must never replay
	# without a matching completed score. Keep it for manual reconciliation.
	var orphan := JOURNAL.enqueue_profile("QA-ORPHAN-20261030", "Legacy Unfinished", "Grade 2")
	_check(bool(orphan.get("ok", false)), "isolated legacy orphan fixture stored for replay audit")
	var before_orphan_replay: int = mock.call("count", "register_student")
	app.call("_flush_recovery_outbox")
	await process_frame
	_check(mock.call("count", "register_student") == before_orphan_replay,
		"legacy unfinished profile never registers after reconnection")
	app.call("_return_to_main")
	play.pressed.emit()
	await process_frame
	form = app.get("active_panel") as Control
	var lives_id := "QA-LIVES-" + str(Time.get_ticks_usec())
	(form.get("_student_id_edit") as LineEdit).text = lives_id
	(form.get("_name_edit") as LineEdit).text = "Finished Lives Student"
	(form.get("_grade_edit") as LineEdit).text = "Grade 3 - Blue"
	form.call("_select_style", "Verb")
	form.call("_select_mode", "Lives")
	form.call("_select_difficulty", "Normal")
	form.call("_update_validation")
	(form.get("_continue_button") as Button).pressed.emit()
	var lookup: Dictionary = mock.call("find_pending", "find_student", "registration_lookup")
	_check(not lookup.is_empty(), "online Continue uses read-only find_student lookup")
	_check(mock.call("count", "register_student") == before_orphan_replay,
		"online new student is not registered before gameplay")
	_check(bool(mock.call("reply", "find_student", {
		"ok": false, "status": 404, "error": "student_not_found", "data": {},
	}, "registration_lookup")), "server confirms new ID is not yet registered")
	_check(bool(mock.call("reply", "find_student_by_name", {
		"ok": false, "status": 404, "error": "student_not_found", "data": {},
	}, "registration_lookup_name")), "read-only name fallback confirms no existing differently-cased ID")
	await process_frame
	_check(String(app.get("current_route")) == "play_activity", "new ID can proceed without creating a profile")
	_check(JOURNAL.pending().size() == 1, "only legacy orphan exists after online Continue")
	var lives: Dictionary = app.get("session_state")
	lives["activity"] = "Human Plane"
	lives["score"] = 91
	lives["round_completed"] = true
	lives["completion_reason"] = "lives_empty"
	lives["lives"] = 3
	_check(not bool(app.call("_valid_round_completion", lives)),
		"claimed Lives completion with remaining hearts is rejected")
	lives["lives"] = 0
	_check(bool(app.call("_valid_round_completion", lives)),
		"legitimate Lives exhaustion is recognized")
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", lives)
	await process_frame
	queued = JOURNAL.pending()
	_check(queued.size() == 2 and String(queued[1].get("kind", "")) == "completed_round",
		"legitimate Lives completion durably queues one atomic new-student result")
	pending = mock.call("find_pending", "register_student", "recovery_replay")
	_check(String(pending.get("args", {}).get("student_id", "")) == lives_id,
		"replay bypasses legacy orphan and first registers genuinely completed Lives student")
	_check(bool(mock.call("reply", "register_student", {
		"ok": true, "data": {"student": {"student_id": lives_id}, "recovery_pending": false},
	}, "recovery_replay")), "completed Lives profile replay acknowledged")
	await process_frame
	pending = mock.call("find_pending", "complete_round", "recovery_replay")
	_check(int(pending.get("args", {}).get("score", -1)) == 91,
		"completed Lives score replays after its own profile")
	_check(bool(mock.call("reply", "complete_round", {
		"ok": true, "data": {"score": {"score": 91}, "recovery_pending": false},
	}, "recovery_replay")), "completed Lives score acknowledged")
	await process_frame
	_check(JOURNAL.pending().size() == 1, "unsynced legacy orphan remains quarantined after finished score replay")
	_check(JOURNAL.acknowledge(String(orphan.get("id", ""))), "test-only legacy orphan fixture cleaned up")
	_check(JOURNAL.pending().is_empty(), "isolated journal empty after all genuine completion replays")
	# Existing student ID with conflicting identity is read-only and blocked.
	app.call("_return_to_main")
	play.pressed.emit()
	await process_frame
	form = app.get("active_panel") as Control
	(form.get("_student_id_edit") as LineEdit).text = lives_id
	(form.get("_name_edit") as LineEdit).text = "Conflicting Name"
	(form.get("_grade_edit") as LineEdit).text = "Grade 3 - Blue"
	form.call("_select_style", "Noun")
	form.call("_select_mode", "Seconds")
	form.call("_select_difficulty", "Easy")
	form.call("_update_validation")
	var writes_before_conflict: int = mock.call("count", "register_student")
	(form.get("_continue_button") as Button).pressed.emit()
	_check(bool(mock.call("reply", "find_student", {
		"ok": true, "data": {"student": {"student_id": lives_id,
			"student_name": "Finished Lives Student", "grade_section": "Grade 3 - Blue"}},
	}, "registration_lookup")), "conflicting identity lookup returns an existing profile")
	await process_frame
	_check(String(app.get("current_route")) == "student_setup"
		and mock.call("count", "register_student") == writes_before_conflict
		and JOURNAL.pending().is_empty(),
		"conflicting ID remains blocked without profile or score writes")
	app.call("_return_to_main")
	# Exercise the real Results router across repeated exits and stale flags.
	# All identities are synthetic and the physical outbox remains untouched.
	var stress_failed := false
	for index in range(128):
		var variant := index % 8
		var is_tutorial := variant == 7
		var test_state := {
			"entry_source": "tutorial" if is_tutorial else "play",
			"guided_tutorial": is_tutorial,
			"student_id": "QA-ABORT-%03d" % index,
			"student_name": "Interrupted Student",
			"grade_section": "Grade 5",
			"game_style": "Noun", "game_mode": "Lives" if variant == 4 else "Seconds",
			"difficulty": "Easy",
			"student_lookup_connected": false,
			"registration_deferred": true,
		}
		app.set("session_state", test_state)
		app.set("current_route", "pause" if variant == 6 else "gameplay")
		var simulated := {
			"activity": "Catch the Word", "score": index + 10,
			"round_completed": variant in [2, 3, 4, 6, 7],
			"completion_reason": "manual" if variant == 2 else ("lives_empty" if variant == 4 else "time_up"),
			"time_remaining": 0.0 if variant in [1, 2, 6, 7] else 34.0,
			"lives": 2,
		}
		# Even a valid terminal-looking payload from a paused route or a
		# practice tutorial cannot persist a classroom student.
		app.call("_on_panel_requested", "results", simulated)
		if not JOURNAL.pending().is_empty() or mock.call("count", "register_student") != writes_before_conflict:
			stress_failed = true
			break
		app.call("_return_to_main")
	_check(not stress_failed, "128 mixed midgame abort/manual/pause/stale/tutorial results create zero student or score records")
	_check(JOURNAL.pending().is_empty(), "repeated abort stress leaves no durable recovery record")
	app.queue_free()
	await process_frame
	await process_frame
	# Native menu audio decoder releases asynchronously on Godot's mixer
	# thread. This test has already freed its UI; allow resource teardown.
	await create_timer(0.75).timeout
	_finish()


func _check(success: bool, description: String) -> void:
	checks += 1
	if not success:
		failures.append(description)


func _finish() -> void:
	print("STUDENT RECOVERY ROUTE: %s | checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for failure in failures:
		printerr("STUDENT RECOVERY FAIL: " + failure)
	ProjectSettings.set_setting("kilos/recovery_test_directory", "")
	quit(0 if failures.is_empty() else 1)
