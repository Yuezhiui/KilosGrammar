extends SceneTree

## Isolated regression for retiring ui/vision/camera_check entirely.
## No database service, real webcam, camera worker, or persisted student data.
## Godot 4.7.2 --headless --path . \
##   --script res://tools/test_camera_check_removal_20261029.gd
const OFFLINE_MENU := "res://tools/test_pause_ready_escape_menu_20261029.gd"
const MENU_SCENE := "res://ui/main_menu/main_menu.tscn"
const DIFFICULTY_SCENE := "res://ui/play/difficulty/play_difficulty.tscn"
const CALIBRATION_SCENE := "res://ui/vision/calibration/calibration.tscn"
const GAME_SCENES := ["Catch the Word", "Balloon Popping", "Human Plane"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	ProjectSettings.set_setting("kilos/recovery_test_directory",
		"user://test_camera_check_removal_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for retired in [
		"res://ui/vision/camera_check/camera_check.gd",
		"res://ui/vision/camera_check/camera_check.gd.uid",
		"res://ui/vision/camera_check/camera_check.tscn"
	]:
		_check(not FileAccess.file_exists(retired),
			"retired Camera Check file was removed: " + retired)
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(
		"res://ui/vision/camera_check")),
		"obsolete camera_check folder itself was deleted")

	var menu_script := load("res://ui/main_menu/main_menu.gd") as Script
	_check(menu_script != null, "current MainMenu router script parses")
	if menu_script == null:
		_finish()
		return
	var panel_scenes: Dictionary = menu_script.get_script_constant_map().get("PANEL_SCENES", {})
	_check(not panel_scenes.has("camera_check"),
		"MainMenu panel registry does NOT load deleted Camera Check scene")
	_check(not menu_script.source_code.contains('\"camera_check\"'),
		"MainMenu has no obsolete Camera Check router alias or Back handler")
	_check(panel_scenes.get("calibration", "") == CALIBRATION_SCENE
		and panel_scenes.get("gameplay", "") == "res://ui/play/gameplay/gameplay.tscn",
		"real calibration and gameplay scene routes remain intact")
	var calibration_scene := load(CALIBRATION_SCENE) as PackedScene
	_check(calibration_scene != null, "actual calibration scene still loads")
	if calibration_scene != null:
		var calibration := calibration_scene.instantiate() as Control
		_check(calibration.get_node_or_null("TutorialStage/Navigation/BackButton") is Button
			and calibration.get_node_or_null("TutorialStage/CameraArea/LiveCameraInset") is TextureRect,
			"calibration retains authored Back and live camera preview nodes")
		calibration.free()

	# Do not mount the real Calibration scene here: its production set_context
	# opens physical camera capture. The test-only subclass intercepts only the
	# final calibration panel mount, retaining the REAL MainMenu route logic.
	var app := (load(MENU_SCENE) as PackedScene).instantiate() as Control
	var mock_script := load(OFFLINE_MENU) as Script
	_check(mock_script != null and mock_script.can_instantiate(),
		"test-only router blocks database and camera/calibration startup")
	if mock_script == null or not mock_script.can_instantiate():
		app.free()
		_finish()
		return
	app.set_script(mock_script)
	root.add_child(app)
	await process_frame

	for source in ["play", "tutorial"]:
		for activity in GAME_SCENES:
			await _exercise_direct_calibration(app, source, activity)
	# A single deliberate retired-route probe should print exactly one
	# EXPECTED "Unknown panel route" warning. Never request it in production.
	await _exercise_retired_route_rejected(app, "play", "Catch the Word")
	await _exercise_retained_difficulty_next(app)
	await app.call("prepare_for_shutdown")
	app.queue_free()
	await process_frame
	_finish()


func _exercise_direct_calibration(app: Control, source: String, activity: String) -> void:
	var tag := source + " / " + activity
	app.call("_return_to_main")
	if source == "tutorial":
		app.call("_on_panel_requested", "play_activity", {
			"entry_source": "tutorial", "guided_tutorial": true, "activity": activity})
		await process_frame
	var payload := {
		"entry_source": source, "guided_tutorial": source == "tutorial",
		"activity": activity, "topic": "Noun", "game_mode": "Seconds",
		"difficulty": "Easy", "student_id": "QA-NON-PERSISTENT",
		"camera_requested": true, "keyboard_mode": false
	}
	var before := int(app.get("intercepted_calibration_routes"))
	app.call("_on_panel_requested", "calibration", payload)
	_check(String(app.get("current_route")) == "calibration"
		and int(app.get("intercepted_calibration_routes")) == before + 1,
		tag + ": direct entry routes to new Calibration, not Camera Check")
	var session := app.get("session_state") as Dictionary
	_check(String(session.get("activity", "")) == activity
		and String(session.get("student_id", "")) == "QA-NON-PERSISTENT"
		and bool(session.get("guided_tutorial", false)) == (source == "tutorial"),
		tag + ": selected activity, test student and Guided mode reach Calibration")


func _exercise_retired_route_rejected(app: Control, source: String, activity: String) -> void:
	# Only real Calibration is allowed. An accidental caller of the retired
	# route must NOT open a physical camera or resurrect a deleted screen.
	var tag := source + " / " + activity
	app.call("_return_to_main")
	var before := int(app.get("intercepted_calibration_routes"))
	app.call("_on_panel_requested", "camera_check", {
		"entry_source": source, "guided_tutorial": source == "tutorial",
		"activity": activity, "topic": "Noun", "difficulty": "Easy",
		"keyboard_mode": true, "camera_requested": false
	})
	_check(String(app.get("current_route")) == "main"
		and int(app.get("intercepted_calibration_routes")) == before
		and app.get("active_panel") == null,
		tag + ": retired route is rejected, never opening camera or a stale panel")


func _exercise_retained_difficulty_next(app: Control) -> void:
	app.call("_return_to_main")
	app.call("_on_panel_requested", "play_difficulty", {
		"entry_source": "play", "activity": "Catch the Word", "topic": "Noun",
		"difficulty": "Easy", "game_mode": "Seconds"
	})
	await process_frame
	_check(String(app.get("current_route")) == "play_difficulty",
		"legacy Difficulty UI can still mount without Camera Check")
	var difficulty := app.get("active_panel") as Control
	if difficulty == null:
		_check(false, "Difficulty panel exists")
		return
	var next := difficulty.get("next_button") as Button
	_check(next != null and not next.disabled
		and next.text.contains("CALIBRATION"),
		"Difficulty Next now advertises CALIBRATION (not CAMERA CHECK)")
	if next == null or next.disabled:
		return
	var before := int(app.get("intercepted_calibration_routes"))
	next.pressed.emit()
	_check(String(app.get("current_route")) == "calibration"
		and int(app.get("intercepted_calibration_routes")) == before + 1,
		"Difficulty native Next button routes straight to Calibration")
	var session := app.get("session_state") as Dictionary
	_check(String(session.get("activity", "")) == "Catch the Word"
		and String(session.get("topic", "")) == "Noun"
		and String(session.get("difficulty", "")) == "Easy",
		"Difficulty direct handoff retains game/topic/difficulty")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("CAMERA CHECK REMOVAL FAIL: ", message)


func _finish() -> void:
	print("CAMERA CHECK REMOVAL QA: %s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
