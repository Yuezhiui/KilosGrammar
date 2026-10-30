extends SceneTree

## Independent Play / Manual Student ID QA using in-memory responses only.
## Run with Godot 4.7.2 --headless --path . --script res://tools/test_student_manual_registration_20261030.gd
## No database, HTTP, CSV, camera, recovery journal, Git or installer writes.
## Reuses the existing test-only main-menu harness which suppresses DB startup
## and camera calibration; all production MainMenu routing runs unchanged.

const STRESS_CYCLES := 120
var main_scene: PackedScene
var router_harness: Script

class FakeDatabase extends Node:
	signal request_finished(info: Dictionary, result: Dictionary)
	var profiles: Dictionary = {}
	var requests: Array[Dictionary] = []
	var outstanding: Dictionary = {}
	var cancelled: Array[int] = []
	var register_calls := 0
	var score_calls := 0
	var next_id := 1
	var hold := false
	var fault := ""

	func find_student(student_id: String, context: Dictionary = {}) -> int:
		return _request("find_student", student_id, context)

	func find_student_by_name(name: String, context: Dictionary = {}) -> int:
		return _request("find_student_by_name", name, context)

	func check_health(_context: Dictionary = {}) -> int:
		return 0 # Completely local and intentionally never probes a service.

	func cancel_request(id: int) -> void:
		cancelled.append(id)
		# Keep queued response so tests can emulate an already-arrived late packet.

	func register_student(_id: String, _name: String, _grade: String,
			_context: Dictionary = {}) -> int:
		register_calls += 1
		return -1

	func complete_round(_id: String, _style: String, _mode: String,
			_difficulty: String, _score: int, _context: Dictionary = {}) -> int:
		score_calls += 1
		return -1

	func _request(operation: String, value: String, context: Dictionary) -> int:
		var id := next_id
		next_id += 1
		var info := context.duplicate(true)
		info["operation"] = operation
		info["request_id"] = id
		var entry := {"id": id, "value": value, "info": info}
		requests.append(entry.duplicate(true))
		outstanding[id] = entry
		if not hold:
			call_deferred("deliver", id)
		return id

	func deliver(id: int) -> void:
		if not outstanding.has(id):
			return
		var entry: Dictionary = outstanding[id]
		outstanding.erase(id)
		var result := {"ok": false, "data": {}, "error": "student_not_found"}
		if not fault.is_empty():
			result["error"] = fault
		elif String(entry["info"]["operation"]) == "find_student":
			if profiles.has(String(entry["value"])):
				result = {"ok": true,
					"data": {"student": profiles[entry["value"]].duplicate(true)}, "error": ""}
		else:
			for candidate: Dictionary in profiles.values():
				if String(candidate.get("student_name", "")).to_lower() == String(entry["value"]).to_lower():
					result = {"ok": true, "data": {"student": candidate.duplicate(true)}, "error": ""}
					break
		request_finished.emit(entry["info"], result)


var checks := 0
var failures: Array[String] = []
var stress_cycles := STRESS_CYCLES


func _initialize() -> void:
	call_deferred("_run")


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _spawn() -> Dictionary:
	var menu := main_scene.instantiate() as Control
	menu.set_script(router_harness)
	root.add_child(menu)
	var fake := FakeDatabase.new()
	fake.name = "FakeDatabaseNoIO"
	menu.add_child(fake)
	fake.request_finished.connect(Callable(menu, "_on_database_request_finished"))
	menu.set("database_client", fake)
	menu.set("database_online", true)
	menu.call("_on_panel_requested", "student_setup", {})
	return {"menu": menu, "db": fake}


func _form(menu: Control) -> Control:
	return menu.get("active_panel") as Control


func _fill(form: Control, sid: String, name: String, grade: String,
		mode: String = "Seconds") -> void:
	var id_edit := form.get("_student_id_edit") as LineEdit
	var name_edit := form.get("_name_edit") as LineEdit
	var grade_edit := form.get("_grade_edit") as LineEdit
	id_edit.text = sid
	form.call("_on_student_id_changed", sid)
	name_edit.text = name
	form.call("_on_student_name_changed", name)
	grade_edit.text = grade
	form.call("_on_grade_changed", grade)
	form.call("_select_style", "Noun")
	form.call("_select_mode", mode)
	form.call("_select_difficulty", "Easy")
	(form.get("_autofill_timer") as Timer).stop()
	form.call("_update_validation")


func _drain(frames: int = 5) -> void:
	for _i in range(frames):
		await process_frame


func _release(menu: Control) -> void:
	if is_instance_valid(menu):
		menu.queue_free()
	await process_frame
	await process_frame


func _new_manual_id(mode: String) -> void:
	var env := _spawn()
	await process_frame
	var menu: Control = env["menu"]
	var fake: FakeDatabase = env["db"]
	var form := _form(menu)
	_fill(form, "123", "qqqq", "qq", mode)
	_expect(not (form.get("_continue_button") as Button).disabled,
		"new %s: 123/qqqq/qq input unlocks Continue without CSV" % mode)
	form.call("_continue")
	_expect(bool(menu.get("database_registration_pending")),
		"new %s: registration lookup is pending, not a DB write" % mode)
	await _drain()
	var state: Dictionary = menu.get("session_state")
	_expect(String(menu.get("current_route")) == "play_activity",
		"new %s: unknown 123 routes to Play game selection" % mode)
	_expect(String(state.get("student_id", "")) == "123" and
		String(state.get("student_name", "")) == "qqqq" and
		String(state.get("grade_section", "")) == "qq",
		"new %s: manual fields survive route" % mode)
	_expect(bool(state.get("registration_deferred", false)) and
		not bool(state.get("student_lookup_connected", true)),
		"new %s: new ID stays unverified, deferred until completed round" % mode)
	_expect(fake.register_calls == 0 and fake.score_calls == 0,
		"new %s: Continue does not register or save before completed round" % mode)
	_expect(fake.requests.size() == 1 and
		String(fake.requests[0]["info"].get("operation", "")) == "find_student",
		"new %s: one-word qqqq never triggers invalid full-name lookup" % mode)
	await _release(menu)


func _existing_match(mode: String) -> void:
	var env := _spawn()
	await process_frame
	var menu: Control = env["menu"]
	var fake: FakeDatabase = env["db"]
	fake.profiles["123"] = {"student_id": "123", "student_name": "qqqq", "grade_section": "qq"}
	var form := _form(menu)
	_fill(form, "123", "qqqq", "qq", mode)
	form.call("_continue")
	await _drain()
	var state: Dictionary = menu.get("session_state")
	_expect(String(menu.get("current_route")) == "play_activity",
		"existing %s: same ID/name routes to Play" % mode)
	_expect(bool(state.get("student_lookup_connected", false)) and
		not bool(state.get("registration_deferred", true)),
		"existing %s: exact returning profile marked verified" % mode)
	_expect(fake.requests.size() == 1 and fake.register_calls == 0,
		"existing %s: no duplicate registration or extra probe" % mode)
	await _release(menu)


func _new_two_word_name() -> void:
	var env := _spawn()
	await process_frame
	var menu: Control = env["menu"]
	var fake: FakeDatabase = env["db"]
	var form := _form(menu)
	_fill(form, "456", "Mira Santos", "Grade 5")
	form.call("_continue")
	await _drain()
	_expect(String(menu.get("current_route")) == "play_activity",
		"new two-word name can Play without existing CSV")
	_expect(fake.requests.size() == 2 and
		String(fake.requests[1]["info"].get("operation", "")) == "find_student_by_name",
		"two-word name uses safe ID-then-full-name verification")
	await _release(menu)


func _existing_case_normalization() -> void:
	var env := _spawn()
	await process_frame
	var menu: Control = env["menu"]
	var fake: FakeDatabase = env["db"]
	fake.profiles["KG-001"] = {"student_id": "KG-001", "student_name": "Mira Santos", "grade_section": "Grade 5"}
	var form := _form(menu)
	_fill(form, "kg-001", "mira  santos", "Grade 6")
	form.call("_continue")
	await _drain()
	var state: Dictionary = menu.get("session_state")
	_expect(String(menu.get("current_route")) == "play_activity" and
		bool(state.get("student_lookup_connected", false)),
		"case-normalized returning ID/name can Play")
	_expect(String(state.get("student_id", "")) == "KG-001" and
		String(state.get("student_name", "")) == "Mira Santos" and
		String(state.get("grade_section", "")) == "Grade 5",
		"server's exact canonical ID/name/grade prevails")
	_expect(fake.requests.size() == 2 and
		String(fake.requests[1]["value"]) == "KG-001",
		"lookup retries the uppercase student ID before new registration")
	await _release(menu)


func _mismatch_refuses() -> void:
	var env := _spawn()
	await process_frame
	var menu: Control = env["menu"]
	var fake: FakeDatabase = env["db"]
	fake.profiles["123"] = {"student_id": "123", "student_name": "Original Child", "grade_section": "Grade 4"}
	var form := _form(menu)
	_fill(form, "123", "qqqq", "qq")
	form.call("_continue")
	await _drain()
	_expect(String(menu.get("current_route")) == "student_setup",
		"conflicting name at registered ID blocks Play")
	_expect(not String(form.get("_registration_error")).is_empty() and
		(form.get("_continue_button") as Button).disabled,
		"conflicting ID/name shows validation hold")
	_expect(fake.register_calls == 0 and fake.score_calls == 0,
		"identity mismatch never writes a profile")
	await _release(menu)


func _network_failure_allows_play() -> void:
	for failure in ["connection_error", "database_unavailable", "schema_not_ready",
			"invalid_full_name", "lookup_unavailable"]:
		var env := _spawn()
		await process_frame
		var menu: Control = env["menu"]
		var fake: FakeDatabase = env["db"]
		fake.fault = failure
		var form := _form(menu)
		_fill(form, "123", "qqqq", "qq")
		form.call("_continue")
		await _drain()
		var state: Dictionary = menu.get("session_state")
		_expect(String(menu.get("current_route")) == "play_activity" and
			bool(state.get("registration_deferred", false)),
			"%s: transport/schema error allows unsaved Play" % failure)
		_expect(not bool(state.get("student_lookup_connected", true)),
			"%s: transport failure never claims ID verified" % failure)
		if failure in ["invalid_full_name", "lookup_unavailable"]:
			_expect(bool(menu.get("database_online")) and
				bool(state.get("database_connected", false)),
				"%s: optional/ambiguous lookup is not falsely called DB-offline" % failure)
		else:
			_expect(not bool(menu.get("database_online")),
				"%s: real transport/storage fault flags database unavailable" % failure)
		await _release(menu)


func _stale_request_is_ignored() -> void:
	var env := _spawn()
	await process_frame
	var menu: Control = env["menu"]
	var fake: FakeDatabase = env["db"]
	fake.hold = true
	var form := _form(menu)
	_fill(form, "123", "qqqq", "qq")
	form.call("_continue")
	var old_request := int(fake.requests[0]["id"])
	var name_edit := form.get("_name_edit") as LineEdit
	name_edit.text = "Second Student"
	form.call("_on_student_name_changed", "Second Student")
	fake.deliver(old_request)
	await _drain(2)
	_expect(String(menu.get("current_route")) == "student_setup",
		"response to edited form must not navigate old student")
	_expect(not bool(menu.get("database_registration_pending")),
		"stale edited form invalidates old registration ticket")
	_expect(fake.register_calls == 0, "stale callback never writes")
	await _release(menu)


func _stale_timeout_is_ignored() -> void:
	var env := _spawn()
	await process_frame
	var menu: Control = env["menu"]
	var fake: FakeDatabase = env["db"]
	fake.hold = true
	var form := _form(menu)
	_fill(form, "123", "qqqq", "qq")
	form.call("_continue")
	var old_request := int(fake.requests[0]["id"])
	var ticket := int(menu.get("database_registration_ticket"))
	menu.call("_expire_database_registration_navigation", ticket)
	await _drain(2)
	_expect(String(menu.get("current_route")) == "play_activity" and
		bool((menu.get("session_state") as Dictionary).get("registration_deferred", false)),
		"slow lookup timeout still allows deferred offline Play")
	fake.profiles["123"] = {"student_id": "123", "student_name": "Other Child", "grade_section": "Grade 6"}
	fake.deliver(old_request)
	await _drain(2)
	_expect(String(menu.get("current_route")) == "play_activity" and
		not bool((menu.get("session_state") as Dictionary).get("student_lookup_connected", true)),
		"late success after timeout cannot hijack current identity")
	await _release(menu)


func _duplicate_continue_is_single_request() -> void:
	var env := _spawn()
	await process_frame
	var menu: Control = env["menu"]
	var fake: FakeDatabase = env["db"]
	fake.hold = true
	var form := _form(menu)
	_fill(form, "123", "qqqq", "qq")
	form.call("_continue")
	form.call("_continue")
	_expect(fake.requests.size() == 1 and
		bool(menu.get("database_registration_pending")),
		"double Continue while lookup pending sends only one check")
	await _release(menu)


func _guided_tutorial_bypasses_registration() -> void:
	var env := _spawn()
	await process_frame
	var menu: Control = env["menu"]
	var fake: FakeDatabase = env["db"]
	var form := _form(menu)
	menu.set("session_state", {"guided_tutorial": true, "entry_source": "tutorial",
		"activity": "Catch the Word"})
	form.call("set_context", {"guided_tutorial": true, "entry_source": "tutorial",
		"activity": "Catch the Word"})
	_fill(form, "123", "qqqq", "qq")
	form.call("_continue")
	await _drain(2)
	_expect(String(menu.get("current_route")) == "calibration",
		"Tutorial continues to camera calibration without profile registration")
	_expect(fake.requests.is_empty() and fake.register_calls == 0,
		"Tutorial bypasses DB lookup and remains unsaved practice")
	_expect(bool((menu.get("session_state") as Dictionary).get("guided_tutorial", false)),
		"Tutorial navigation retains guide-only flag")
	await _release(menu)


func _stress_manual_play() -> void:
	var env := _spawn()
	await process_frame
	var menu: Control = env["menu"]
	var fake: FakeDatabase = env["db"]
	for cycle in range(stress_cycles):
		if cycle % 30 == 0:
			print("MANUAL STUDENT QA stress cycle %d/%d" % [cycle, stress_cycles])
		var form := _form(menu)
		var sid := "QA-%04d" % cycle
		var mode := "Seconds" if cycle % 2 == 0 else "Lives"
		_fill(form, sid, "Manual Student %d" % cycle, "qq", mode)
		_expect(not (form.get("_continue_button") as Button).disabled,
			"cycle %d: independent manual input can Continue" % cycle)
		form.call("_continue")
		await _drain(5)
		var state: Dictionary = menu.get("session_state")
		_expect(String(menu.get("current_route")) == "play_activity" and
			String(state.get("student_id", "")) == sid and
			String(state.get("game_mode", "")) == mode,
			"cycle %d: unknown ID reaches correct Play mode with no CSV" % cycle)
		_expect(bool(state.get("registration_deferred", false)) and
			not bool(state.get("student_lookup_connected", true)),
			"cycle %d: no false existing-identity claim" % cycle)
		menu.call("_on_panel_requested", "student_setup", {"fresh_setup": true})
		await process_frame
	_expect(fake.register_calls == 0 and fake.score_calls == 0,
		"%d manual Continue sessions create no premature DB writes" % stress_cycles)
	await _release(menu)


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--qa-cycles="):
			stress_cycles = maxi(1, int(argument.trim_prefix("--qa-cycles=")))
	# Resolve autoload class aliases after the SceneTree has initialized rather
	# than compiling a MainMenu preload before PoseService exists.
	await process_frame
	main_scene = load("res://ui/main_menu/main_menu.tscn") as PackedScene
	router_harness = load("res://tools/test_play_router_harness_20261030.gd") as Script
	if main_scene == null or router_harness == null:
		printerr("MANUAL STUDENT REGISTRATION QA FAIL: missing main scene/harness")
		quit(2)
		return
	for mode in ["Seconds", "Lives"]:
		await _new_manual_id(mode)
		await _existing_match(mode)
	await _new_two_word_name()
	await _existing_case_normalization()
	await _mismatch_refuses()
	await _network_failure_allows_play()
	await _stale_request_is_ignored()
	await _stale_timeout_is_ignored()
	await _duplicate_continue_is_single_request()
	await _guided_tutorial_bypasses_registration()
	await _stress_manual_play()
	for issue in failures:
		printerr("MANUAL STUDENT REGISTRATION QA FAIL: ", issue)
	print("MANUAL STUDENT REGISTRATION QA: %s checks=%d failures=%d stress_cycles=%d mocked_database=true" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), stress_cycles])
	quit(0 if failures.is_empty() else 1)
