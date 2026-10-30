extends SceneTree

## Isolated end-to-end routing stress, with production Student Setup, chooser,
## Tutorial Home, MainMenu router and three real gameplay/countdown scenes.
## Production MainMenu has a QA subclass that omits database startup and
## camera startup. Fake DB answers are delivered to its real callback.
## Run headless with APPDATA and LOCALAPPDATA pointed to a temporary QA-only
## directory (never to the teacher's real Godot user directory).

const APP_SCENE_PATH := "res://ui/main_menu/main_menu.tscn"
const QA_ROUTER_PATH := "res://tools/test_play_router_harness_20261030.gd"
const ACTIVITIES := ["Catch the Word", "Human Plane", "Balloon Popping"]
const ITERATIONS := 120

class FakeDatabase:
	extends Node
	var next_id := 20
	var requests: Array[Dictionary] = []
	var canceled: Array[int] = []

	func find_student(student_id: String, info: Dictionary = {}) -> int:
		next_id += 1
		requests.append({"id": next_id, "operation": "find_student", "value": student_id, "info": info.duplicate(true)})
		return next_id

	func find_student_by_name(student_name: String, info: Dictionary = {}) -> int:
		next_id += 1
		requests.append({"id": next_id, "operation": "find_student_by_name", "value": student_name, "info": info.duplicate(true)})
		return next_id

	func cancel_request(request_id: int) -> void:
		canceled.append(request_id)

	func check_health(_info: Dictionary = {}) -> int:
		return 0 # Never performs network IO; this is an inert memory stub.

	func ensure_local_service(_info: Dictionary = {}) -> void:
		pass


var app: Control
var fake: FakeDatabase
var checks := 0
var failures: Array[String] = []
var routed := 0
var timed_out := 0
var rejected := 0
var conflicts_blocked := 0
var actual_watchdog_recoveries := 0
var tutorial_routed := 0
var countdown_verified := 0
var planned_iterations := ITERATIONS


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Failing this condition protects existing school/student user:// records.
	var isolated_user_path := OS.get_user_data_dir().replace("\\", "/").to_lower()
	_check(isolated_user_path.contains("play_route_stress_20261030"),
		"isolated QA Windows user data dir required; observed " + isolated_user_path)
	if failures.size() > 0:
		_finish()
		return
	var pose := root.get_node_or_null("PoseService")
	_check(pose != null and not pose.active, "test starts with webcam and tracking disabled")
	if pose == null or pose.active:
		_finish()
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var packed := load(APP_SCENE_PATH) as PackedScene
	var qa_router := load(QA_ROUTER_PATH) as Script
	_check(packed != null and qa_router != null, "isolated production main-menu router compiled")
	if packed == null or qa_router == null:
		_finish()
		return
	app = packed.instantiate() as Control
	app.set_script(qa_router)
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fake = FakeDatabase.new()
	fake.name = "MockMemoryOnlyStudentDatabase"
	app.add_child(fake)
	app.set("database_client", fake)
	await process_frame
	_check(String(app.get("current_route")) == "main", "initial main route exists")
	var iterations := ITERATIONS
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--cycles="):
			iterations = maxi(1, int(argument.trim_prefix("--cycles=")))
	planned_iterations = iterations
	for index in range(iterations):
		await _run_play_cycle(index)
	await _check_identity_conflict()
	await _check_real_timeout_watchdog()
	for index in range(30):
		await _run_tutorial_cycle(index)
	for activity in ACTIVITIES:
		await _check_countdown_activity(activity)
	_check(not pose.active, "the complete stress run never opens a real webcam")
	app.call("_return_to_main")
	await process_frame
	app.queue_free()
	await process_frame
	_finish()


func _run_play_cycle(index: int) -> void:
	var scenario := index % 5
	var tag := "play cycle=%d scenario=%d" % [index, scenario]
	(app.get_node("MainLayer/CenterMenu/Play") as Button).pressed.emit()
	await process_frame
	_check(_route() == "student_setup", tag + " menu Play opened real Student Setup; got=" + _route())
	if _route() != "student_setup":
		app.call("_return_to_main")
		await process_frame
		return
	var form := app.get("active_panel") as Control
	var id := "KG-QA-%04d" % index
	var student := "Visual Test %04d" % index
	var grade := "Grade 4 Jade"
	_fill_form(form, id, student, grade)
	var next := form.get("_continue_button") as Button
	_check(not next.disabled and (next.get_node("ButtonArtwork") as CanvasItem).visible,
		tag + " all six fields yield green Continue")
	app.set("database_online", scenario != 0)
	var before := fake.requests.size()
	# Native Button's actual pressed signal exercises production binding.
	next.pressed.emit()
	_check(_route() == ("play_activity" if scenario == 0 else "student_setup"),
		tag + " Continue navigates immediately offline or starts online read-only lookup")
	if scenario != 0:
		_check(bool(app.get("database_registration_pending")), tag + " online lookup pending")
		_check(fake.requests.size() == before + 1,
			tag + " exactly one read-only ID check, no writes")
		# Genuine double click while lookup is pending must not spawn a second
		# HTTP request or release gameplay with unchecked identity.
		next.pressed.emit()
		_check(fake.requests.size() == before + 1, tag + " double press deduplicated")
		_check(_route() == "student_setup", tag + " no early navigation on second click")
		var first_req: Dictionary = fake.requests[before]
		var first_info: Dictionary = first_req["info"]
		first_info["operation"] = "find_student"
		match scenario:
			1: # New student, two explicit student_not_found responses.
				_deliver(first_info, false, {}, "student_not_found")
				_check(fake.requests.size() == before + 2,
					tag + " unresolved ID checked by full name before fresh Play")
				if fake.requests.size() == before + 2:
					var second_info: Dictionary = (fake.requests[before + 1]["info"] as Dictionary).duplicate(true)
					second_info["operation"] = "find_student_by_name"
					_deliver(second_info, false, {}, "student_not_found")
			2: # Existing identity: server's historical grade wins.
				_deliver(first_info, true, {"student": {"student_id": id,
					"student_name": student, "grade_section": "Grade 3 Emerald"}}, "")
			3: # Simulate exactly the 1.75s recovery callback after slow network.
				var ticket := int(app.get("database_registration_ticket"))
				app.call("_expire_database_registration_navigation", ticket)
				timed_out += 1
				_deliver(first_info, true, {"student": {"student_id": id,
					"student_name": student, "grade_section": grade}}, "")
			4: # ID edited during async lookup: callback cannot hijack identity.
				_edit(form.get("_student_id_edit") as LineEdit, id + "-NEW")
				_deliver(first_info, true, {"student": {"student_id": id,
					"student_name": student, "grade_section": grade}}, "")
				_check(_route() == "student_setup" and next.disabled,
					tag + " stale async match cannot navigate changed/blank form")
				rejected += 1
				_fill_form(form, id + "-NEW", student, grade)
				_check(not next.disabled, tag + " new ID re-entry yields green Continue")
				next.pressed.emit()
				_check(fake.requests.size() == before + 2,
					tag + " changed profile has new isolated ID request")
				if fake.requests.size() == before + 2:
					var renewed: Dictionary = (fake.requests[before + 1]["info"] as Dictionary).duplicate(true)
					renewed["operation"] = "find_student"
					_deliver(renewed, true, {"student": {"student_id": id + "-NEW",
						"student_name": student, "grade_section": grade}}, "")
	if _route() == "play_activity":
		# Allow the chooser's editor-authored deferred focus to settle before
		# leaving it; otherwise artificial same-frame switches focus freed nodes.
		await process_frame
		routed += 1
		var state: Dictionary = app.get("session_state")
		var expected_id := id + "-NEW" if scenario == 4 else id
		_check(String(state.get("student_id", "")) == expected_id
			and String(state.get("student_name", "")) == student,
			tag + " route preserves correct student ID and full name")
		if scenario == 2:
			_check(String(state.get("grade_section", "")) == "Grade 3 Emerald"
				and bool(state.get("student_lookup_connected", false)),
				tag + " returning ID authorized with server's verified grade")
		if scenario == 3:
			_check(bool(state.get("registration_deferred", false)),
				tag + " slow lookup marks registration_deferred and does not block Play")
		# Actual chooser real selection and Continue to the shared calibration.
		var chooser := app.get("active_panel") as Control
		var chosen_activity: String = ACTIVITIES[index % ACTIVITIES.size()]
		(chooser.get("activity_buttons")[chosen_activity] as Button).pressed.emit()
		(chooser.get("next_button") as Button).pressed.emit()
		_check(_route() == "calibration", tag + " chooser Next reaches calibration")
		await process_frame
		var calibrated: Dictionary = app.get("intercepted_calibration_payload")
		_check(String(calibrated.get("activity", "")) == chosen_activity
			and bool(calibrated.get("camera_requested", false))
			and not bool(calibrated.get("keyboard_mode", true)),
			tag + " calibration has chosen game and real-camera-required flags")
	else:
		_check(false, tag + " GREEN Continue route DROPPED, route=" + _route())
	app.call("_return_to_main")
	await process_frame
	_check(_route() == "main", tag + " successful reset to Main Menu")


func _run_tutorial_cycle(index: int) -> void:
	var tag := "tutorial cycle=%d" % index
	(app.get_node("MainLayer/CenterMenu/Tutorial") as Button).pressed.emit()
	await process_frame
	_check(_route() == "tutorial_home", tag + " Tutorial Home visible")
	if _route() != "tutorial_home":
		app.call("_return_to_main")
		return
	var homepage := app.get("active_panel") as Control
	(homepage.get_node("TutorialStage/StartButton") as Button).pressed.emit()
	_check(_route() == "play_activity", tag + " tutorial Start enters activity chooser")
	await process_frame
	var chooser := app.get("active_panel") as Control
	var chosen: String = ACTIVITIES[index % ACTIVITIES.size()]
	(chooser.get("activity_buttons")[chosen] as Button).pressed.emit()
	(chooser.get("next_button") as Button).pressed.emit()
	_check(_route() == "student_setup", tag + " tutorial chooser opens student setup")
	await process_frame
	if _route() != "student_setup":
		app.call("_return_to_main")
		await process_frame
		return
	var form := app.get("active_panel") as Control
	_fill_form(form, "TUTORIAL-%03d" % index, "Tutorial Student", "Grade 3 Jade")
	(form.get("_continue_button") as Button).pressed.emit()
	_check(_route() == "calibration", tag + " green Tutorial Continue reaches calibration directly")
	await process_frame
	var state: Dictionary = app.get("intercepted_calibration_payload")
	_check(bool(state.get("guided_tutorial", false)) and String(state.get("activity", "")) == chosen
		and String(state.get("entry_source", "")) == "tutorial",
		tag + " Tutorial shares the same calibration with guided flag")
	if _route() == "calibration":
		tutorial_routed += 1
	app.call("_return_to_main")
	await process_frame


func _check_identity_conflict() -> void:
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	var form := app.get("active_panel") as Control
	_fill_form(form, "KG-CONFLICT-CASE", "Original Sample", "Grade 4 Jade")
	var next := form.get("_continue_button") as Button
	_check(not next.disabled, "identity conflict case starts green before server reply")
	app.set("database_online", true)
	var first := fake.requests.size()
	next.pressed.emit()
	_check(fake.requests.size() == first + 1, "identity conflict performs one read-only lookup")
	if fake.requests.size() > first:
		var info: Dictionary = (fake.requests[first]["info"] as Dictionary).duplicate(true)
		info["operation"] = "find_student"
		_deliver(info, true, {"student": {"student_id": "KG-CONFLICT-CASE",
			"student_name": "Different Person", "grade_section": "Grade 4 Jade"}}, "")
		_check(_route() == "student_setup" and next.disabled,
			"identity conflict must block route and turn green Continue gray")
		_check((next.get_node("ContinueDisabledArtwork") as CanvasItem).visible,
			"identity conflict renders the actual gray disabled artwork")
		if _route() == "student_setup" and next.disabled:
			conflicts_blocked += 1
		_edit(form.get("_student_id_edit") as LineEdit, "KG-CONFLICT-CORRECTED")
		_fill_form(form, "KG-CONFLICT-CORRECTED", "Original Sample", "Grade 4 Jade")
		_check(not next.disabled,
			"editing a conflicting student ID clears warning and restores green Continue")
	app.call("_return_to_main")
	await process_frame


func _check_real_timeout_watchdog() -> void:
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	var form := app.get("active_panel") as Control
	_fill_form(form, "KG-ACTUAL-TIMEOUT", "Timeout Sample", "Grade 5 Jade")
	app.set("database_online", true)
	(form.get("_continue_button") as Button).pressed.emit()
	_check(_route() == "student_setup" and bool(app.get("database_registration_pending")),
		"real watchdog waits for database lookup before fallback")
	# This is a genuine elapsed Godot Timer, independent of synthetic direct
	# _expire_database_registration_navigation calls used by stress scenarios.
	await create_timer(2.15).timeout
	_check(_route() == "play_activity" and not bool(app.get("database_registration_pending")),
		"real 1.75-second registration watchdog must recover a slow lookup")
	if _route() == "play_activity":
		actual_watchdog_recoveries += 1
	app.call("_return_to_main")
	await process_frame


func _check_countdown_activity(activity: String) -> void:
	# Actual 3-game wrapper, native countdown scene and minigame instantiation.
	# A live camera is intentionally absent, so inspect countdown state without
	# releasing its 3-2-1; a valid physical pose remains a production condition.
	app.set("database_online", false)
	app.call("_on_panel_requested", "gameplay", {
		"entry_source": "play", "student_id": "COUNTDOWN-TEST",
		"student_name": "Countdown Sample", "grade_section": "Grade 4 Jade",
		"activity": activity, "game_style": "Noun", "game_mode": "Seconds",
		"difficulty": "Easy", "start_countdown": true,
		"camera_live": false, "camera_requested": true,
		"calibration_measured": false
	})
	await process_frame
	await process_frame
	var wrapper := app.get("active_panel") as Control
	_check(_route() == "gameplay", activity + " reaches real gameplay wrapper")
	if wrapper != null:
		var mini := wrapper.get_node_or_null("ActiveMiniGame") as Control
		_check(mini != null, activity + " actual minigame scene mounted")
		_check(String(wrapper.get("guided_stage")) == "countdown"
			and mini != null and mini.process_mode == Node.PROCESS_MODE_DISABLED,
			activity + " 3-2-1 entry freezes game before GO")
		var overlay := wrapper.get("countdown_panel") as Control
		_check(overlay != null and overlay.name == "GuidedCountdown",
			activity + " native GuidedCountdown scene visible")
		if mini != null and overlay != null:
			countdown_verified += 1
	app.call("_return_to_main")
	await process_frame


func _fill_form(form: Control, student_id: String, name: String, grade: String) -> void:
	_edit(form.get("_student_id_edit") as LineEdit, student_id)
	_edit(form.get("_name_edit") as LineEdit, name)
	_edit(form.get("_grade_edit") as LineEdit, grade)
	(form.get("_style_buttons")["Noun"] as Button).pressed.emit()
	(form.get("_mode_buttons")["Seconds"] as Button).pressed.emit()
	(form.get("_difficulty_buttons")["Easy"] as Button).pressed.emit()


func _edit(field: LineEdit, value: String) -> void:
	field.text = value
	field.text_changed.emit(value)


func _deliver(info: Dictionary, successful: bool, data: Dictionary, error: String) -> void:
	app.call("_on_database_request_finished", info, {"ok": successful, "data": data, "error": error})


func _route() -> String:
	return String(app.get("current_route"))


func _check(ok: bool, info: String) -> void:
	checks += 1
	if not ok:
		failures.append(info)
		printerr("PLAY CONTINUE STRESS FAIL ", info)


func _finish() -> void:
	print("PLAY CONTINUE STRESS: %s assertions=%d failures=%d play_routes=%d/%d tutorial_routes=%d/30 countdown_games=%d/3 manual_timeout_recoveries=%d real_watchdog=%d identity_conflicts_blocked=%d stale_callbacks_blocked=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size(), routed, planned_iterations,
		tutorial_routed, countdown_verified, timed_out, actual_watchdog_recoveries,
		conflicts_blocked, rejected])
	for failure in failures:
		printerr("STRESS FAILURE ", failure)
	quit(0 if failures.is_empty() else 1)
