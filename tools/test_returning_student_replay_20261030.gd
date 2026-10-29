extends SceneTree
## Returning students can start unlimited new Play rounds without registration.
## Real Student Setup / MainMenu scenes with a no-socket database mock.
## ALL recovery files are under a unique test_recovery_ directory.

const MENU := "res://ui/main_menu/main_menu.tscn"
const MOCK_MENU := "res://tools/test_postgres_main_menu.gd"
const JOURNAL := preload("res://ui/database/recovery_journal.gd")
const CANON_ID := "STUDENT-REPEAT-001"
const CANON_NAME := "Alice Dela Cruz"
const CANON_GRADE := "Grade 5 - Rose"

var app: Control
var mock: Node
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	ProjectSettings.set_setting("kilos/recovery_test_directory",
		"user://test_recovery_returning_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var source := load(MENU) as PackedScene
	var script := load(MOCK_MENU) as Script
	_check(source != null and script != null, "real Main Menu and no-socket subclass load")
	if source == null or script == null:
		_finish()
		return
	app = source.instantiate() as Control
	app.set_script(script)
	root.add_child(app)
	await process_frame
	mock = app.get("database_client") as Node
	_check(is_instance_valid(mock) and mock.get_child_count() == 0,
		"test transport never creates HTTPRequest or real PostgreSQL connections")
	_check(bool(mock.call("reply", "health", {
		"ok": true, "data": {"database": "connected"},
	}, "startup")), "test fixture explicitly connects fake database")
	_check(bool(app.get("database_online")), "online service is simulated without a real server")

	# Same existing ID and full name; case and repeated spaces are immaterial.
	await _open_student_setup(CANON_ID, "  ALICE   Dela   CRUZ  ", " grade 5  - ROSE ", "Seconds")
	_check(bool(mock.call("reply", "find_student", _existing_profile(), "registration_lookup")),
		"first matching ID resolves through read-only GET")
	await process_frame
	_check(_route() == "play_activity", "returning student starts a new Play round")
	_check(_canonical_session() and bool(_state().get("student_lookup_connected", false)),
		"verified returning profile uses canonical server ID, name and grade")
	_check(_no_registration(), "first returning Continue never registers student or writes recovery")
	await _complete_score(410, "Seconds", "Catch the Word")
	_check(_no_registration(), "first returning completed round saves score without creating a new profile")

	# A student promoted or moved sections should not be locked out; current
	# registered grade is retained until a teacher explicitly updates it.
	await _open_student_setup(CANON_ID, " Alice   Dela Cruz ", "Grade 6 - New Section", "Lives")
	_check(bool(mock.call("reply", "find_student", _existing_profile(), "registration_lookup")),
		"same ID and name with changed grade obtains existing profile")
	await process_frame
	_check(_route() == "play_activity" and _canonical_session(),
		"changed grade alone allows Play but never overwrites registered grade")
	_check(_no_registration(), "changed grade does not register or queue a profile")
	await _complete_score(235, "Lives", "Human Plane")
	_check(_no_registration(), "second completed round is saved under same canonical student")

	# Different ID capitalization: exact lookup 404 then uppercase check returns
	# the same registered identity, without creating a duplicate lowercase ID.
	await _open_student_setup("student-repeat-001", "aLIce  dela  cRUz", "Grade 5-Rose", "Seconds")
	_check(bool(mock.call("reply", "find_student", _not_found(), "registration_lookup")),
		"lowercase ID first receives an exact backend miss")
	var uppercase_lookup: Dictionary = mock.call("find_pending", "find_student", "registration_lookup_upper")
	_check(String(uppercase_lookup.get("args", {}).get("student_id", "")) == CANON_ID,
		"read-only uppercase ID fallback checks existing canonical spelling")
	_check(bool(mock.call("reply", "find_student", _existing_profile(), "registration_lookup_upper")),
		"uppercase ID fallback confirms existing identity")
	await process_frame
	_check(_route() == "play_activity" and _canonical_session(),
		"differently capitalized ID reuses existing profile")
	await _complete_score(333, "Seconds", "Balloon Popping")
	_check(_no_registration(), "third completed score neither duplicates profile nor rewrites existing data")

	# Mixed-case older ID where upper fallback is insufficient. Unique full
	# name must also match the ID when compared without case.
	await _open_student_setup("student-repeat-002", "  karen   naVARRO ", "Grade 2 - X", "Seconds")
	_check(bool(mock.call("reply", "find_student", _not_found(), "registration_lookup")),
		"historical mixed-case ID exact lookup misses")
	_check(bool(mock.call("reply", "find_student", _not_found(), "registration_lookup_upper")),
		"historical mixed-case ID uppercase lookup also misses")
	var by_name: Dictionary = mock.call("find_pending", "find_student_by_name", "registration_lookup_name")
	_check(not by_name.is_empty(), "router performs read-only unique full-name lookup")
	_check(bool(mock.call("reply", "find_student_by_name", {
		"ok": true, "data": {"student": {
			"student_id": "StUdEnT-RePeAt-002", "student_name": "Karen Navarro",
			"grade_section": "Grade 2 - X",
		}},
	}, "registration_lookup_name")), "name lookup returns the matching historical mixed-case ID")
	await process_frame
	_check(_route() == "play_activity"
		and String(_state().get("student_id", "")) == "StUdEnT-RePeAt-002",
		"historical ID casing reuses canonical existing identity")
	_check(_no_registration(), "historical mixed-case returning session writes no profile")

	# An actually DIFFERENT name for the same stored ID must remain blocked.
	await _open_student_setup(CANON_ID, "Different Student", "Grade 5 - Rose", "Seconds")
	var before_scores := int(mock.call("count", "complete_round"))
	_check(bool(mock.call("reply", "find_student", _existing_profile(), "registration_lookup")),
		"wrong-name request still receives canonical existing ID")
	await process_frame
	_check(_route() == "student_setup", "different student name cannot enter Play on existing ID")
	_check(not bool((_state()).get("student_lookup_connected", false)),
		"genuine identity conflict cannot mark returning student as verified")
	_check(not String((app.get("active_panel") as Control).get("_registration_error")).is_empty(),
		"genuine conflict stays blocked with actionable form validation")
	_check(_no_registration() and int(mock.call("count", "complete_round")) == before_scores,
		"wrong identity never registers or creates a score request")
	_check(JOURNAL.pending().is_empty(), "all completed mock score replays left test-only outbox empty")
	await app.call("prepare_for_shutdown")
	app.queue_free()
	await process_frame
	await process_frame
	_finish()


func _existing_profile() -> Dictionary:
	return {"ok": true, "data": {"student": {
		"student_id": CANON_ID, "student_name": CANON_NAME, "grade_section": CANON_GRADE,
	}}}


func _not_found() -> Dictionary:
	return {"ok": false, "status": 404, "error": "student_not_found", "data": {}}


func _open_student_setup(id: String, name: String, grade: String, mode: String) -> void:
	app.call("_return_to_main")
	await process_frame
	(app.get_node("MainLayer/CenterMenu/Play") as Button).pressed.emit()
	await process_frame
	_check(_route() == "student_setup", "Play opens fresh student setup for each round")
	var form := app.get("active_panel") as Control
	(form.get("_student_id_edit") as LineEdit).text = id
	(form.get("_name_edit") as LineEdit).text = name
	(form.get("_grade_edit") as LineEdit).text = grade
	form.call("_select_style", "Noun")
	form.call("_select_mode", mode)
	form.call("_select_difficulty", "Easy")
	form.call("_update_validation")
	_check(not (form.get("_continue_button") as Button).disabled, "valid setup permits Continue")
	(form.get("_continue_button") as Button).pressed.emit()
	_check(not (mock.call("find_pending", "find_student", "registration_lookup") as Dictionary).is_empty(),
		"Continue checks database using read-only ID lookup")


func _complete_score(score: int, mode: String, minigame: String) -> void:
	var state := _state().duplicate(true)
	state["activity"] = minigame
	state["game_mode"] = mode
	state["score"] = score
	state["round_completed"] = true
	if mode == "Seconds":
		state["completion_reason"] = "time_up"
		state["time_remaining"] = 0.0
	else:
		state["completion_reason"] = "lives_empty"
		state["lives"] = 0
	var before_scores := int(mock.call("count", "complete_round"))
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", state)
	await process_frame
	_check(_route() == "results", "verified returning student reaches completed Results")
	_check(int(mock.call("count", "complete_round")) == before_scores + 1,
		"completed score submitted once for verified existing student")
	var pending: Dictionary = mock.call("find_pending", "complete_round", "recovery_replay")
	_check(String(pending.get("args", {}).get("student_id", "")) == CANON_ID
		and int(pending.get("args", {}).get("score", -1)) == score,
		"replay submits exact score under canonical registered student ID")
	_check(bool(mock.call("reply", "complete_round", {
		"ok": true, "data": {"score": {"score": score}, "recovery_pending": false},
	}, "recovery_replay")), "mocked backend acknowledges completed score")
	await process_frame
	_check(JOURNAL.pending().is_empty(), "acknowledged completed score removed from test-only outbox")


func _no_registration() -> bool:
	return int(mock.call("count", "register_student")) == 0 and JOURNAL.pending().is_empty()


func _route() -> String:
	return String(app.get("current_route"))


func _state() -> Dictionary:
	return app.get("session_state") as Dictionary


func _canonical_session() -> bool:
	var state := _state()
	return String(state.get("student_id", "")) == CANON_ID \
		and String(state.get("student_name", "")) == CANON_NAME \
		and String(state.get("grade_section", "")) == CANON_GRADE


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _finish() -> void:
	print("RETURNING STUDENT REPLAY: %s | checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for failure in failures:
		printerr("RETURNING STUDENT FAIL: " + failure)
	ProjectSettings.set_setting("kilos/recovery_test_directory", "")
	quit(0 if failures.is_empty() else 1)
