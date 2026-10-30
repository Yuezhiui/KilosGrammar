extends SceneTree

# Actual Play -> Student Setup -> read-only registration lookup -> Game Selection
# -> Calibration with an in-memory PostgreSQL mock. No live API, DB or camera.
const MENU_PATH := "res://ui/main_menu/main_menu.tscn"
const TEST_MENU_PATH := "res://tools/test_postgres_main_menu.gd"
const JOURNAL := preload("res://ui/database/recovery_journal.gd")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting("kilos/recovery_test_directory",
		"user://test_recovery_play_continue_20261030_%s" % str(Time.get_ticks_usec()))
	call_deferred("_run")

func _run() -> void:
	_check(JOURNAL.pending().is_empty(), "no earlier recovery records in isolated test directory")
	for dimensions in SIZES:
		root.size = dimensions
		root.content_scale_size = dimensions
		var packed := load(MENU_PATH) as PackedScene
		var test_script := load(TEST_MENU_PATH) as Script
		_check(packed != null and test_script != null and test_script.can_instantiate(),
			"main menu and offline test script load after autoload initialization")
		if packed == null or test_script == null:
			continue
		var app := packed.instantiate() as Control
		app.set_script(test_script)
		root.add_child(app)
		await process_frame
		var db := app.get("database_client") as Node
		_check(db != null, "mock DB injected at " + str(dimensions))
		if db == null:
			app.queue_free()
			await process_frame
			continue
		_check(bool(db.call("reply", "health", {"ok": true,
			"status": 200, "data": {"database": "connected"}}, "startup")), "connected mock health")
		await _test_conflict_and_returning(app, db, dimensions)
		await _test_offline(app, db, dimensions)
		await _test_stale_setup_choice(app, db, dimensions)
		await _test_tutorial_parity(app, db, dimensions)
		app.call("_return_to_main")
		app.queue_free()
		await process_frame
		await process_frame
		_check(JOURNAL.pending().is_empty(), "no synthetic score or profile in outbox " + str(dimensions))
	_finish()

func _begin_play(app: Control) -> Control:
	app.call("_return_to_main")
	await process_frame
	(app.get_node("MainLayer/CenterMenu/Play") as Button).pressed.emit()
	await process_frame
	_check(String(app.get("current_route")) == "student_setup", "Play opens real Student Setup")
	return app.get("active_panel") as Control

func _fill(form: Control, id: String, name: String, grade: String) -> void:
	var student_id := form.get("_student_id_edit") as LineEdit
	var student_name := form.get("_name_edit") as LineEdit
	var student_grade := form.get("_grade_edit") as LineEdit
	student_id.text = id
	student_id.text_changed.emit(id)
	student_name.text = name
	student_name.text_changed.emit(name)
	student_grade.text = grade
	student_grade.text_changed.emit(grade)
	form.call("_select_style", "Noun")
	form.call("_select_mode", "Seconds")
	form.call("_select_difficulty", "Easy")

func _test_conflict_and_returning(app: Control, db: Node, dimensions: Vector2i) -> void:
	var form := await _begin_play(app)
	_check(form != null, "student form exists " + str(dimensions))
	if form == null:
		return
	var student_id := "TEST-RETURN-%d" % dimensions.x
	_fill(form, student_id, "Incorrect Learner", "Grade 4")
	var next := form.get("_continue_button") as Button
	_check(not next.disabled, "complete six-field setup is green before lookup")
	for repeated_click in range(20):
		next.pressed.emit()
	_check(bool(app.get("database_registration_pending")), "20 clicks share one pending identity check")
	_check(String(app.get("current_route")) == "student_setup", "pending lookup keeps form mounted")
	var feedback := form.get_node("SetupStage/GameSetupCard/GameContent/ValidationPanel/ValidationLabel") as Label
	_check(next.disabled and feedback.visible and feedback.text == "CHECKING STUDENT ID...",
		"read-only lookup briefly grays Continue and shows an explicit progress reason")
	_check(db.call("count", "find_student") == 1, "20 clicks create precisely one find_student request")
	_check(db.call("count", "register_student") == 0 and JOURNAL.pending().is_empty(),
		"Continue never writes to database or recovery before gameplay")
	_check(bool(db.call("reply", "find_student", {"ok": true, "status": 200,
		"data": {"student": {"student_id": student_id,
		"student_name": "Actual Learner", "grade_section": "Grade 4"}}}, "registration_lookup")),
		"read-only registered-ID callback arrives")
	_check(String(app.get("current_route")) == "student_setup",
		"genuine ID/name mismatch still blocks misattributed game")
	_check(next.disabled, "mismatch disables Continue and shows gray art")
	_check(feedback.visible and feedback.text == "CHECK STUDENT ID AND NAME",
		"rejected Play clearly explains next action without old red banner")
	_check(form.get("_registration_error") != "",
		"identity conflict retained as safety hold")
	var name_edit := form.get("_name_edit") as LineEdit
	name_edit.text = "Actual Learner"
	name_edit.text_changed.emit(name_edit.text)
	_check(not next.disabled, "editing conflicting name restores green for a fresh lookup")
	for repeated_click in range(20):
		next.pressed.emit()
	_check(db.call("count", "find_student") == 2,
		"20 retry clicks after correction create only one new lookup")
	_check(bool(db.call("reply", "find_student", {"ok": true, "status": 200,
		"data": {"student": {"student_id": student_id,
		"student_name": "Actual Learner", "grade_section": "Grade 4"}}}, "registration_lookup")),
		"same registered student identity verified")
	_check(String(app.get("current_route")) == "play_activity",
		"verified returning learner reaches Game Selection")
	_check(bool((app.get("session_state") as Dictionary).get("student_lookup_connected", false)),
		"verified returning learner may replay with original stored ID")
	_check(db.call("count", "register_student") == 0 and JOURNAL.pending().is_empty(),
		"replay neither recreates registered profile nor saves score before completion")
	await process_frame
	var chooser := app.get("active_panel") as Control
	_check(chooser != null and chooser.has_method("_select_activity"), "real game chooser mounted")
	if chooser != null:
		chooser.call("_select_activity", "Catch the Word")
		chooser.call("_go_next")
		await process_frame
		_check(String(app.get("current_route")) == "calibration",
			"Play selected minigame enters same calibration route as Tutorial")
		_check(bool((app.get("session_state") as Dictionary).get("camera_requested", false)),
			"Play calibration requires live camera")

func _test_offline(app: Control, db: Node, dimensions: Vector2i) -> void:
	var form := await _begin_play(app)
	if form == null:
		return
	_fill(form, "TEST-OFFLINE-%d" % dimensions.x, "Offline Student", "Grade 5")
	var next := form.get("_continue_button") as Button
	_check(not next.disabled, "offline candidate completes all fields")
	next.pressed.emit()
	_check(bool(db.call("reply", "find_student", {"ok": false, "status": 0,
		"error": "connection_error", "data": null}, "registration_lookup")),
		"simulated API outage while checking student identity")
	_check(String(app.get("current_route")) == "play_activity", "API outage still permits activity choice")
	_check(not bool((app.get("session_state") as Dictionary).get("student_lookup_connected", true)),
		"offline candidate has no false verified identity")
	_check(JOURNAL.pending().is_empty() and db.call("count", "register_student") == 0,
		"API outage never invents profile or score at Continue")
	await process_frame

func _test_stale_setup_choice(app: Control, db: Node, dimensions: Vector2i) -> void:
	# While a read-only lookup is pending, the teacher may still select a
	# different topic/mode/difficulty. The late callback must never resurrect
	# the old options, even though the student identity itself is unchanged.
	app.set("database_online", true)
	var form := await _begin_play(app)
	if form == null:
		return
	var student_id := "TEST-EDIT-%d" % dimensions.x
	_fill(form, student_id, "Changing Learner", "Grade 6")
	(form.get("_continue_button") as Button).pressed.emit()
	_check(bool(app.get("database_registration_pending")),
		"read-only lookup pending before teacher changes topic")
	form.call("_select_style", "Verb")
	form.call("_select_mode", "Lives")
	form.call("_select_difficulty", "Hard")
	_check(not (form.get("_continue_button") as Button).disabled,
		"changing setup selections cancels UI lookup lock, allowing resubmit")
	_check(bool(db.call("reply", "find_student", {
		"ok": true, "status": 200,
		"data": {"student": {"student_id": student_id, "student_name": "Changing Learner",
			"grade_section": "Grade 6"}}
	}, "registration_lookup")), "late response for earlier form selections is delivered")
	_check(String(app.get("current_route")) == "student_setup",
		"late callback must not route with stale grammar topic/mode/difficulty")
	_check(not bool(app.get("database_registration_pending")),
		"stale callback clears old pending request for fresh confirmation")
	(form.get("_continue_button") as Button).pressed.emit()
	_check(bool(db.call("reply", "find_student", {
		"ok": true, "status": 200,
		"data": {"student": {"student_id": student_id, "student_name": "Changing Learner",
			"grade_section": "Grade 6"}}
	}, "registration_lookup")), "fresh changed choices verified in a new read-only request")
	var state: Dictionary = app.get("session_state")
	_check(String(app.get("current_route")) == "play_activity"
		and String(state.get("game_style", "")) == "Verb"
		and String(state.get("game_mode", "")) == "Lives"
		and String(state.get("difficulty", "")) == "Hard",
		"newest topic/mode/difficulty survive checked navigation")
	await process_frame

func _test_tutorial_parity(app: Control, db: Node, dimensions: Vector2i) -> void:
	app.call("_return_to_main")
	await process_frame
	app.call("_on_panel_requested", "tutorial_home", {})
	await process_frame
	app.call("_on_panel_requested", "play_activity", {"guided_tutorial": true, "entry_source": "tutorial"})
	await process_frame
	var chooser := app.get("active_panel") as Control
	_check(String(app.get("current_route")) == "play_activity" and chooser != null,
		"Tutorial opens same activity chooser at " + str(dimensions))
	if chooser == null:
		return
	chooser.call("_select_activity", "Catch the Word")
	chooser.call("_go_next")
	await process_frame
	_check(String(app.get("current_route")) == "student_setup",
		"Tutorial routes selected activity to student form")
	var form := app.get("active_panel") as Control
	if form == null:
		return
	_fill(form, "QA-TUTORIAL-%d" % dimensions.x, "Tutorial Student", "Grade 3")
	var requests_before: int = db.call("count", "find_student")
	(form.get("_continue_button") as Button).pressed.emit()
	await process_frame
	_check(String(app.get("current_route")) == "calibration",
		"Tutorial enters same calibration scene as routed Play")
	_check(db.call("count", "find_student") == requests_before,
		"Tutorial intentionally bypasses database registration check")
	var calibration := app.get("active_panel") as Control
	_check(calibration != null and calibration.get_script().resource_path ==
		"res://ui/vision/calibration/calibration.gd",
		"Play and Tutorial share the exact production calibration script")
	var state: Dictionary = app.get("session_state")
	_check(bool(state.get("camera_requested", false))
		and bool(state.get("guided_tutorial", false)),
		"Tutorial also requests a physical camera; only guided flags differ")
	_check(JOURNAL.pending().is_empty(), "Tutorial creates no database records or scores")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("PLAY CONTINUE LOOKUP FAIL: " + label)

func _finish() -> void:
	print("PLAY CONTINUE LOOKUP STRESS: %s checks=%d failures=%d sizes=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size(), SIZES.size()])
	quit(0 if failures.is_empty() else 1)
