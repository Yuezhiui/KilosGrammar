extends SceneTree
## Independently exercise router->transport->new StudentSetup, including
## duplicate names, late success and API outage. All requests are mocked.
## Use a separate recovery directory even when launched with a GUI renderer.
const MAIN := "res://ui/main_menu/main_menu.tscn"
const MOCK_MAIN := "res://tools/test_postgres_main_menu.gd"
const RECOVERY := preload("res://ui/database/recovery_journal.gd")

var checks := 0
var failures: Array[String] = []
var app: Control
var form: Control
var mock: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	ProjectSettings.set_setting("kilos/recovery_test_directory",
		"user://test_recovery_api_name_" + str(Time.get_ticks_usec()))
	var packed := load(MAIN) as PackedScene
	var script := load(MOCK_MAIN) as Script
	_check(packed != null and script != null, "production main menu scene/mock subclass load")
	if packed == null or script == null:
		_finish()
		return
	app = packed.instantiate() as Control
	app.set_script(script)
	root.add_child(app)
	await process_frame
	mock = app.get("database_client") as Node
	_check(mock != null and mock.has_method("find_student_by_name"),
		"mock transport supports same full-name endpoint as real client")
	app.call("_on_database_local_service_status_changed", "online", {})
	(app.get_node("MainLayer/CenterMenu/Play") as Button).pressed.emit()
	await process_frame
	form = app.get("active_panel") as Control
	_check(form != null and String(app.get("current_route")) == "student_setup",
		"production router mounts actual Student Setup")
	if form == null:
		_finish()
		return
	var sid := form.get("_student_id_edit") as LineEdit
	var fullname := form.get("_name_edit") as LineEdit
	var grade := form.get("_grade_edit") as LineEdit
	fullname.text = "Maria Santos"
	fullname.text_changed.emit(fullname.text)
	await create_timer(2.65).timeout
	var first: Dictionary = mock.call("find_pending", "find_student_by_name", "autofill")
	_check(not first.is_empty(), "exact full-name request after 2.5 seconds of idle")
	_check(String(first.get("args", {}).get("student_name", "")) == "Maria Santos",
		"request transmits exact complete full name")
	_check(bool(mock.call("reply", "find_student_by_name", {
		"ok": false, "status": 409, "error": "student_ambiguous",
	}, "autofill")), "duplicate-name response delivered")
	await process_frame
	_check(sid.text.is_empty() and grade.text.is_empty() and fullname.text == "Maria Santos",
		"409 duplicate full name never guesses a student's ID")
	fullname.text = "Jose Bonifacio"
	fullname.text_changed.emit(fullname.text)
	# The pending request for Jose becomes stale before a response is delivered.
	form.call("_autofill_if_unchanged")
	var stale: Dictionary = mock.call("find_pending", "find_student_by_name", "autofill")
	_check(String(stale.get("args", {}).get("student_name", "")) == "Jose Bonifacio",
		"second name schedules fresh exact lookup")
	fullname.text = "Juan Dela Cruz"
	fullname.text_changed.emit(fullname.text)
	_check(bool(mock.call("reply", "find_student_by_name", {
		"ok": true, "status": 200, "data": {"student": {
			"student_id": "ID-JOSE", "student_name": "Jose Bonifacio",
			"grade_section": "Grade 6 - Sampaguita"}},
	}, "autofill")), "stale HTTP success delivered while new name is being typed")
	await process_frame
	_check(sid.text.is_empty() and grade.text.is_empty() and fullname.text == "Juan Dela Cruz",
		"late HTTP response cannot corrupt a new teacher-entered identity")
	form.call("_autofill_if_unchanged")
	var newest: Dictionary = mock.call("find_pending", "find_student_by_name", "autofill")
	_check(String(newest.get("args", {}).get("student_name", "")) == "Juan Dela Cruz",
		"latest request targets the current complete name")
	_check(bool(mock.call("reply", "find_student_by_name", {
		"ok": true, "status": 200, "data": {"student": {
			"student_id": "ID-JUAN", "student_name": "Juan Dela Cruz",
			"grade_section": "Grade 4 - Rose"}},
	}, "autofill")), "matching server-confirmed student returned")
	await process_frame
	_check(sid.text == "ID-JUAN" and grade.text == "Grade 4 - Rose",
		"server-verified full name fills exact ID and grade")
	fullname.text = "Completely Unknown"
	fullname.text_changed.emit(fullname.text)
	_check(sid.text.is_empty() and grade.text.is_empty(),
		"editing a verified name immediately clears previously verified identity")
	form.call("_autofill_if_unchanged")
	_check(bool(mock.call("reply", "find_student_by_name", {
		"ok": false, "status": 404, "error": "student_not_found",
	}, "autofill")), "404 missing name returned")
	await process_frame
	_check(sid.text.is_empty() and grade.text.is_empty(),
		"unknown complete name never invents a student profile")
	var name_requests := int(mock.call("count", "find_student_by_name"))
	app.call("_on_database_local_service_status_changed", "offline", {"reason": "api_unreachable"})
	fullname.text = "Andrea Navarro"
	fullname.text_changed.emit(fullname.text)
	form.call("_autofill_if_unchanged")
	_check(int(mock.call("count", "find_student_by_name")) == name_requests,
		"offline HTTP never guesses full-name uniqueness from local queue")
	_check(sid.text.is_empty() and grade.text.is_empty(),
		"offline full name leaves unknown identity unfilled")
	var profile_id := "QA-OFF-" + str(Time.get_ticks_usec())
	var queued: Dictionary = RECOVERY.enqueue_profile(profile_id, "Andrea Navarro", "Grade 5 - Acacia")
	_check(bool(queued.get("ok", false)), "offline exact-ID test profile stored only in QA outbox")
	fullname.clear()
	fullname.text_changed.emit(fullname.text)
	sid.text = profile_id
	sid.text_changed.emit(sid.text)
	form.call("_autofill_if_unchanged")
	_check(sid.text == profile_id and fullname.text == "Andrea Navarro"
		and grade.text == "Grade 5 - Acacia",
		"offline pending profile may be recovered by exact unique student ID")
	app.queue_free()
	await process_frame
	await create_timer(0.4).timeout
	_finish()


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)


func _finish() -> void:
	print("STUDENT API AUTOFILL ROUTE: %s | checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for fail in failures:
		printerr("AUTOFILL ROUTE FAIL: " + fail)
	ProjectSettings.set_setting("kilos/recovery_test_directory", "")
	quit(0 if failures.is_empty() else 1)
