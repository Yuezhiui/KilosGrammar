extends SceneTree

## Focused REAL MainMenu P2-then-P1 identity gate regression, with a local
## in-memory database SIGNAL stub and the existing test-only router harness.
##
## Godot 4.7.2 --headless --path . --script res://tools/test_multiplayer_two_student_registration_20261102.gd
##
## ZERO HTTP, PostgreSQL, recovery-journal writes, camera access, Git, or
## production changes. Calibration is intercepted before it creates its scene.

const MAIN_SCENE_PATH := "res://ui/main_menu/main_menu.tscn"
const ROUTER_HARNESS_PATH := "res://tools/test_play_router_harness_20261030.gd"


class StubLocalDatabase extends Node:
	signal request_finished(info: Dictionary, result: Dictionary)

	var requests: Array[Dictionary] = []
	var pending: Dictionary = {}
	var canceled: Array[int] = []
	var writes := 0
	var next_request_id := 1

	func find_student(student_id: String, context: Dictionary = {}) -> int:
		return _capture("find_student", student_id, context)

	func find_student_by_name(name: String, context: Dictionary = {}) -> int:
		return _capture("find_student_by_name", name, context)

	func check_health(_context: Dictionary = {}) -> int:
		return 0 # Intentionally no health TCP request, not even loopback.

	func _capture(operation: String, value: String, context: Dictionary) -> int:
		var request_id := next_request_id
		next_request_id += 1
		var info := context.duplicate(true)
		info["operation"] = operation
		info["request_id"] = request_id
		var record := {"id": request_id, "operation": operation, "value": value, "info": info}
		requests.append(record.duplicate(true))
		pending[request_id] = record
		return request_id

	func respond(request_id: int, existing: Dictionary = {}, error_code: String = "student_not_found") -> void:
		if not pending.has(request_id):
			return
		var request: Dictionary = pending[request_id]
		pending.erase(request_id)
		# Deliver even if canceled: an HTTP callback may already be queued when
		# the teacher edits a field or a timeout revokes its registration ticket.
		var result: Dictionary = {"ok": not existing.is_empty(), "data": {}, "error": error_code}
		if not existing.is_empty():
			result["data"] = {"student": existing.duplicate(true)}
			result["error"] = ""
		request_finished.emit(request["info"], result)

	func cancel_request(request_id: int) -> void:
		canceled.append(request_id)

	func register_student(_student_id: String, _student_name: String,
			_grade_section: String, _context: Dictionary = {}) -> int:
		writes += 1
		return -1

	func complete_round(_student_id: String, _style: String, _mode: String,
			_difficulty: String, _score: int, _context: Dictionary = {}) -> int:
		writes += 1
		return -1


var checks := 0
var failures: Array[String] = []
var main_scene: PackedScene
var router_harness: Script


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		printerr("TWO STUDENT REGISTRATION FAIL: ", detail)


func _drain(frames: int = 2) -> void:
	for _index in range(frames):
		await process_frame


func _spawn() -> Dictionary:
	var menu := main_scene.instantiate() as Control
	menu.set_script(router_harness)
	root.add_child(menu)
	var fake := StubLocalDatabase.new()
	fake.name = "IsolatedReadOnlyStudentLookup"
	menu.add_child(fake)
	fake.request_finished.connect(Callable(menu, "_on_database_request_finished"))
	menu.set("database_client", fake)
	menu.set("database_online", true)
	menu.call("_on_panel_requested", "student_setup", {})
	await _drain() # Let the real form's deferred focus settle before routing.
	return {"menu": menu, "database": fake}


func _release(menu: Control) -> void:
	# Flush UI's own deferred focus calls before freeing its form.
	await _drain()
	if is_instance_valid(menu):
		menu.queue_free()
	await _drain()


func _edit(field: LineEdit, value: String) -> void:
	field.text = value
	field.text_changed.emit(value)


func _prepare_multiplayer(menu: Control, p1_id: String = "P1-001",
		p2_id: String = "P2-002", p2_name: String = "Ben", mode: String = "Seconds") -> Control:
	var form := menu.get("active_panel") as Control
	# The actual two-stage student form: P1 profile, then Game Setup, then P2.
	_edit(form.get("_student_id_edit") as LineEdit, p1_id)
	_edit(form.get("_name_edit") as LineEdit, "Ada")
	_edit(form.get("_grade_edit") as LineEdit, "Grade 4 - Jade")
	form.call("_continue")
	await _drain() # Student->Game stage schedules a focus callback.
	_check(String(form.get("_setup_phase")) == "game", "P1 profile opens Game Setup without database mutation")
	form.call("_select_style", "Noun")
	form.call("_select_mode", mode)
	form.call("_select_difficulty", "Easy")
	form.call("_select_player_mode", "Multiplayer")
	_edit(form.get("_player_two_id_edit") as LineEdit, p2_id)
	_edit(form.get("_player_two_name_edit") as LineEdit, p2_name)
	_edit(form.get("_player_two_grade_edit") as LineEdit, "Grade 5 - Rose")
	(form.get("_autofill_timer") as Timer).stop()
	form.call("_update_validation")
	await _drain()
	return form


func _start_lookup(form: Control) -> void:
	_check(not (form.get("_continue_button") as Button).disabled,
		"valid P1+P2 profile and game setup enable final Continue")
	form.call("_continue")


func _request_matches(entry: Dictionary, student_id: String,
		purpose: String, menu: Control) -> bool:
	return String(entry.get("operation", "")) == "find_student" \
		and String(entry.get("value", "")) == student_id \
		and String((entry.get("info", {}) as Dictionary).get("purpose", "")) == purpose \
		and int((entry.get("info", {}) as Dictionary).get("registration_ticket", -1)) == int(menu.get("database_registration_ticket"))


func _assert_no_writes(fake: StubLocalDatabase, tag: String) -> void:
	_check(fake.writes == 0, tag + ": no POST/registration/score calls before completed gameplay")


func _duplicate_student_id_case_insensitive() -> void:
	var env := await _spawn()
	var menu: Control = env["menu"]
	var fake: StubLocalDatabase = env["database"]
	var form: Control = await _prepare_multiplayer(menu, "P1-001", "p1-001")
	_check((form.get("_continue_button") as Button).disabled,
		"P2 ID matching P1 case-insensitively disables Continue")
	_check(String((form.get("_player_two_status") as Label).text).contains("DIFFERENT STUDENT ID"),
		"duplicate case-insensitive P2 ID receives explicit teacher guidance")
	form.call("_continue")
	_check(fake.requests.is_empty() and String(menu.get("current_route")) == "student_setup",
		"duplicate P1/P2 ID cannot make any lookup or enter calibration")
	_assert_no_writes(fake, "case-insensitive duplicate")
	await _release(menu)


func _existing_p2_name_mismatch_blocks_calibration() -> void:
	var env := await _spawn()
	var menu: Control = env["menu"]
	var fake: StubLocalDatabase = env["database"]
	var form: Control = await _prepare_multiplayer(menu, "P1-001", "P2-002", "Incorrect Child")
	_start_lookup(form)
	_check(fake.requests.size() == 1 and _request_matches(fake.requests[0], "P2-002",
		"multiplayer_player2_lookup", menu), "P2 read-only lookup happens BEFORE any P1 request")
	_check(String(menu.get("current_route")) == "student_setup" and bool(menu.get("database_registration_pending")),
		"waiting for P2 reply never launches calibration")
	fake.respond(int(fake.requests[0]["id"]), {
		"student_id": "P2-002", "student_name": "Registered Student",
		"grade_section": "Grade 5 - Rose"})
	await _drain()
	_check(String(menu.get("current_route")) == "student_setup" and fake.requests.size() == 1,
		"existing P2 name mismatch blocks calibration AND P1 lookup")
	_check(not bool(menu.get("database_registration_pending")) and
		String(form.get("_registration_error")).contains("PLAYER TWO"),
		"P2 mismatch clears pending gate and shows identity conflict")
	_assert_no_writes(fake, "P2 existing-name mismatch")
	await _release(menu)


func _new_p2_then_p1_gate(mode: String) -> void:
	var env := await _spawn()
	var menu: Control = env["menu"]
	var fake: StubLocalDatabase = env["database"]
	var form: Control = await _prepare_multiplayer(menu, "P1-001", "P2-002", "Ben", mode)
	_start_lookup(form)
	_check(fake.requests.size() == 1 and _request_matches(fake.requests[0], "P2-002",
		"multiplayer_player2_lookup", menu), mode + ": first GET checks P2 only")
	form.call("_continue")
	_check(fake.requests.size() == 1, mode + ": duplicate Continue cannot issue a second P2/P1 lookup")
	_assert_no_writes(fake, mode + " before P2 result")
	fake.respond(int(fake.requests[0]["id"])) # 404 new P2, no registration
	_check(fake.requests.size() == 2 and _request_matches(fake.requests[1], "P1-001",
		"registration_lookup", menu), mode + ": P2 404 leads to P1 GET, never POST")
	_check(String(menu.get("current_route")) == "student_setup" and
		bool(menu.get("database_registration_pending")),
		mode + ": P1 still pending; calibration remains blocked")
	fake.respond(int(fake.requests[1]["id"])) # 404 new P1
	await _drain()
	var state: Dictionary = menu.get("session_state")
	var recorded: Dictionary = menu.get("intercepted_calibration_payload")
	_check(String(menu.get("current_route")) == "calibration" and
		String(state.get("player_mode", "")) == "Multiplayer" and String(state.get("game_mode", "")) == mode,
		mode + ": only both read-only lookups authorize routing to intercepted calibration")
	_check(String(recorded.get("student_id", "")) == "P1-001" and
		String(recorded.get("player2_student_id", "")) == "P2-002" and
		String(recorded.get("player2_student_name", "")) == "Ben" and
		bool(recorded.get("registration_deferred", false)) and
		not bool(recorded.get("student_lookup_connected", true)),
		mode + ": P1/P2 identities preserved, new profiles deferred until completed round")
	_check(not state.has("_player_two_gate_checked") and not state.has("_registration_gate_checked"),
		mode + ": transient registration gate markers are not persisted in session")
	_check(fake.requests.size() == 2 and fake.requests[0]["id"] != fake.requests[1]["id"],
		mode + ": exactly two ordered read-only GET requests and unique callback tickets")
	_assert_no_writes(fake, mode + " before GO and completed score")
	await _release(menu)


func _existing_p1_mismatch_after_new_p2_blocks_calibration() -> void:
	var env := await _spawn()
	var menu: Control = env["menu"]
	var fake: StubLocalDatabase = env["database"]
	var form: Control = await _prepare_multiplayer(menu)
	_start_lookup(form)
	_check(fake.requests.size() == 1, "P1 mismatch: P2 is still first lookup")
	fake.respond(int(fake.requests[0]["id"])) # P2 is a new student
	_check(fake.requests.size() == 2 and _request_matches(fake.requests[1], "P1-001",
		"registration_lookup", menu), "P1 mismatch: P1 checked only after P2 new result")
	fake.respond(int(fake.requests[1]["id"]), {
		"student_id": "P1-001", "student_name": "Other Registered Child",
		"grade_section": "Grade 4 - Jade"})
	await _drain()
	_check(String(menu.get("current_route")) == "student_setup" and
		(menu.get("route_history") as Array).find("calibration") < 0 and
		String(form.get("_registration_error")).contains("CHECK STUDENT ID AND NAME"),
		"P1 existing-name mismatch still blocks calibration after valid new P2")
	_assert_no_writes(fake, "P1 mismatch with new P2")
	await _release(menu)


func _existing_p2_canonicalized_before_p1_lookup() -> void:
	var env := await _spawn()
	var menu: Control = env["menu"]
	var fake: StubLocalDatabase = env["database"]
	var form: Control = await _prepare_multiplayer(menu, "P1-001", "p2-002", "Ben")
	_start_lookup(form)
	fake.respond(int(fake.requests[0]["id"]), {
		"student_id": "P2-002", "student_name": "BEN", "grade_section": "Grade 5 - Rose"})
	_check(fake.requests.size() == 2 and _request_matches(fake.requests[1], "P1-001",
		"registration_lookup", menu), "matched case-insensitive existing P2 advances to P1 lookup")
	fake.respond(int(fake.requests[1]["id"]), {
		"student_id": "P1-001", "student_name": "Ada", "grade_section": "Grade 4 - Jade"})
	await _drain()
	var state: Dictionary = menu.get("session_state")
	_check(String(menu.get("current_route")) == "calibration" and
		String(state.get("player2_student_id", "")) == "P2-002" and
		String(state.get("player2_student_name", "")) == "BEN" and
		String(state.get("player2_grade_section", "")) == "Grade 5 - Rose",
		"matched returning P2 uses authoritative DB ID/name/grade, not input spelling")
	_check(bool(state.get("student_lookup_connected", false)) and
		not bool(state.get("registration_deferred", true)),
		"P1 existing verified identity correctly completes after P2 match")
	_assert_no_writes(fake, "matched returning P2 and P1")
	await _release(menu)


func _existing_p2_grade_mismatch_never_enters_calibration() -> void:
	var env := await _spawn()
	var menu: Control = env["menu"]
	var fake: StubLocalDatabase = env["database"]
	var form: Control = await _prepare_multiplayer(menu)
	_start_lookup(form)
	_check(fake.requests.size() == 1, "grade mismatch: P2 check remains the first read-only lookup")
	fake.respond(int(fake.requests[0]["id"]), {
		"student_id": "P2-002", "student_name": "Ben", "grade_section": "Grade 6 - Different"})
	# The current backend match helper validates P2 ID+name and carries the
	# canonical grade into the pending P1 check. Whether a future implementation
	# refuses at P2 or after P1, a conflicting grade must NEVER calibrate.
	if fake.requests.size() > 1:
		fake.respond(int(fake.requests[1]["id"]), {
			"student_id": "P1-001", "student_name": "Ada", "grade_section": "Grade 4 - Jade"})
	await _drain()
	_check(String(menu.get("current_route")) == "student_setup" and
		(menu.get("route_history") as Array).find("calibration") < 0,
		"existing P2 conflicting grade/section cannot reach calibration")
	_check((form.get("_player_two_grade_edit") as LineEdit).text == "Grade 5 - Rose",
		"registered P2 grade conflict never silently overwrites teacher's form")
	_assert_no_writes(fake, "P2 grade conflict")
	await _release(menu)


func _stale_p2_callback_after_teacher_edit() -> void:
	var env := await _spawn()
	var menu: Control = env["menu"]
	var fake: StubLocalDatabase = env["database"]
	var form: Control = await _prepare_multiplayer(menu)
	_start_lookup(form)
	var stale_id := int(fake.requests[0]["id"])
	_edit(form.get("_player_two_name_edit") as LineEdit, "Another Student")
	fake.respond(stale_id, {"student_id": "P2-002", "student_name": "Ben", "grade_section": "Grade 5 - Rose"})
	await _drain()
	_check(String(menu.get("current_route")) == "student_setup" and fake.requests.size() == 1,
		"P2 old callback cannot advance to P1 or calibration after teacher changes P2 name")
	_check(not bool(menu.get("database_registration_pending")),
		"P2 stale callback invalidates outstanding registration stage")
	_check((form.get("_player_two_name_edit") as LineEdit).text == "Another Student",
		"stale P2 response never replaces teacher's updated profile")
	_assert_no_writes(fake, "stale P2 edited name")
	await _release(menu)


func _p2_then_p1_timeout_defer_without_registration() -> void:
	var env := await _spawn()
	var menu: Control = env["menu"]
	var fake: StubLocalDatabase = env["database"]
	var form: Control = await _prepare_multiplayer(menu)
	_start_lookup(form)
	var p2_id := int(fake.requests[0]["id"])
	var p2_ticket := int(menu.get("database_registration_ticket"))
	menu.call("_expire_database_registration_navigation", p2_ticket)
	_check(fake.canceled.has(p2_id) and fake.requests.size() == 2 and
		_request_matches(fake.requests[1], "P1-001", "registration_lookup", menu),
		"P2 timeout cancels P2 lookup and starts P1 read-only identity gate")
	_check(String(menu.get("current_route")) == "student_setup", "P2 timeout alone cannot start calibration")
	var p1_id := int(fake.requests[1]["id"])
	var p1_ticket := int(menu.get("database_registration_ticket"))
	menu.call("_expire_database_registration_navigation", p1_ticket)
	await _drain()
	var state: Dictionary = menu.get("session_state")
	_check(fake.canceled.has(p1_id) and String(menu.get("current_route")) == "calibration",
		"P1 timeout permits only deferred/practice route to intercepted calibration")
	_check(bool(state.get("registration_deferred", false)) and
		not bool(state.get("student_lookup_connected", true)) and
		not bool(state.get("database_connected", true)) and
		String(state.get("player2_student_id", "")) == "P2-002",
		"both timeouts preserve distinct P1/P2 IDs but NEVER assert verified database identities")
	_assert_no_writes(fake, "P2 + P1 timeout before GO")
	# Even if a transport callback was already queued, a timed-out P2 result
	# cannot restore the previous identity or relaunch the camera screen.
	var route_count := (menu.get("route_history") as Array).size()
	fake.respond(p2_id, {"student_id": "P2-002", "student_name": "Different Child", "grade_section": "Grade 6"})
	fake.respond(p1_id, {"student_id": "P1-001", "student_name": "Other Student", "grade_section": "Grade 3"})
	await _drain()
	_check((menu.get("route_history") as Array).size() == route_count and
		String((menu.get("session_state") as Dictionary).get("player2_student_name", "")) == "Ben",
		"late P2 and P1 responses after timeout do not hijack calibration identities")
	_assert_no_writes(fake, "late timeouts")
	await _release(menu)


func _run() -> void:
	await process_frame # Autoload PoseService must exist before scene load.
	main_scene = load(MAIN_SCENE_PATH) as PackedScene
	router_harness = load(ROUTER_HARNESS_PATH) as Script
	if main_scene == null or router_harness == null:
		printerr("TWO STUDENT REGISTRATION QA ERROR: MainMenu scene or no-camera harness missing")
		quit(2)
		return
	await _duplicate_student_id_case_insensitive()
	await _existing_p2_name_mismatch_blocks_calibration()
	for mode in ["Seconds", "Lives"]:
		await _new_p2_then_p1_gate(mode)
	await _existing_p1_mismatch_after_new_p2_blocks_calibration()
	await _existing_p2_canonicalized_before_p1_lookup()
	await _existing_p2_grade_mismatch_never_enters_calibration()
	await _stale_p2_callback_after_teacher_edit()
	await _p2_then_p1_timeout_defer_without_registration()
	var pose_service := root.get_node_or_null("PoseService")
	_check(pose_service == null or not bool(pose_service.get("active")),
		"QA harness never starts camera tracking, even after calibration routing")
	print("TWO STUDENT READ-ONLY REGISTRATION QA: %s checks=%d failures=%d no_http_db_camera=true" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
