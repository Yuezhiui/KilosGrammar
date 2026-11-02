extends SceneTree

## Isolated read-only route and visual-stage regression for the two independent
## Student Profile and Game Setup screens, reached through both Play and Tutorial.
## Uses the existing router test subclass to suppress camera and database work.
## Run: Godot --headless --path . --script res://tools/test_play_tutorial_two_stage_ui_20261102.gd
const MAIN := "res://ui/main_menu/main_menu.tscn"
const ROUTER_HARNESS := "res://tools/test_play_router_harness_20261030.gd"
const GAMEPLAY := "res://ui/play/gameplay/gameplay.tscn"
const SCREENS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const TUTORIAL_GAMES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const REMOVED_DOUBLE_PANEL := "res://Components/StudentSetup/Redesign/background.png"

var assertions := 0
var failures: Array[String] = []
var app: Control


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pose := root.get_node_or_null("PoseService")
	_check(pose != null and not bool(pose.get("active")), "PoseService starts inactive")
	if pose == null or bool(pose.get("active")):
		_finish()
		return
	pose.set_process(false)
	for screen in SCREENS:
		root.size = screen
		root.content_scale_size = screen
		await process_frame
		await _start_menu()
		if app == null:
			continue
		await _check_play(screen)
		await _check_tutorial(screen)
		await _close_menu()
	_check(not bool(pose.get("active")), "No camera opened during Play/Tutorial tests")
	pose.set_process(true)
	_finish()


func _start_menu() -> void:
	var packed := load(MAIN) as PackedScene
	var harness := load(ROUTER_HARNESS) as Script
	_check(packed != null and harness != null and harness.can_instantiate(),
		"Menu and test router load after autoload initialization")
	if packed == null or harness == null or not harness.can_instantiate():
		app = null
		return
	app = packed.instantiate() as Control
	if app == null:
		_check(false, "Main Menu scene instantiates")
		return
	app.set_script(harness)
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.set("database_online", false)
	await process_frame
	_check(_route() == "main", "Isolated Main Menu is ready")


func _close_menu() -> void:
	if is_instance_valid(app):
		app.call("_return_to_main")
		await process_frame
		app.queue_free()
		await process_frame
		await process_frame
	app = null


func _check_play(screen: Vector2i) -> void:
	var label := "Play %s" % screen
	(app.get_node("MainLayer/CenterMenu/Play") as Button).pressed.emit()
	await process_frame
	_check(_route() == "student_setup", label + " opens Student Profile")
	if _route() != "student_setup":
		return
	var setup := app.get("active_panel") as Control
	_check_stages(setup, "profile", label)
	_check(not bool(setup.get("context").get("guided_tutorial", false)), label + " has no guided flag")
	_check((setup.get("_student_id_edit") as LineEdit).text.is_empty(), label + " starts with empty Student ID")
	_check((setup.get("_continue_button") as Button).disabled, label + " begins with grey disabled Continue")
	await _fill_profile(setup, label)
	await _fill_game(setup, label)
	if _route() != "student_setup":
		return
	(setup.get("_continue_button") as Button).pressed.emit()
	await process_frame
	_check(_route() == "play_activity", label + " finished Game Setup opens activity selection")
	if _route() != "play_activity":
		return
	var chooser := app.get("active_panel") as Control
	(chooser.get("activity_buttons")["Catch the Word"] as Button).pressed.emit()
	(chooser.get("next_button") as Button).pressed.emit()
	await process_frame
	_check_calibration_payload(false, label, "Catch the Word")


func _check_tutorial(screen: Vector2i) -> void:
	var label := "Tutorial %s" % screen
	var activity: String = TUTORIAL_GAMES[SCREENS.find(screen)]
	app.call("_return_to_main")
	await process_frame
	(app.get_node("MainLayer/CenterMenu/Tutorial") as Button).pressed.emit()
	await process_frame
	_check(_route() == "tutorial_home", label + " opens Tutorial Home")
	if _route() != "tutorial_home":
		return
	var tutorial_home := app.get("active_panel") as Control
	(tutorial_home.get_node("TutorialStage/StartButton") as Button).pressed.emit()
	await process_frame
	_check(_route() == "play_activity", label + " Start opens activity chooser")
	if _route() != "play_activity":
		return
	var chooser := app.get("active_panel") as Control
	(chooser.get("activity_buttons")[activity] as Button).pressed.emit()
	(chooser.get("next_button") as Button).pressed.emit()
	await process_frame
	_check(_route() == "student_setup", label + " chooser Next opens Student Profile")
	if _route() != "student_setup":
		return
	var setup := app.get("active_panel") as Control
	_check_stages(setup, "profile", label)
	_check(bool(setup.get("context").get("guided_tutorial", false)), label + " retains guided flag")
	await _fill_profile(setup, label)
	await _fill_game(setup, label)
	if _route() != "student_setup":
		return
	(setup.get("_continue_button") as Button).pressed.emit()
	await process_frame
	_check_calibration_payload(true, label, activity)
	if _route() == "calibration":
		await _check_integrated_tutorial(label, activity)


func _fill_profile(setup: Control, label: String) -> void:
	var student_id := setup.get("_student_id_edit") as LineEdit
	var student_name := setup.get("_name_edit") as LineEdit
	var section := setup.get("_grade_edit") as LineEdit
	var next := setup.get("_continue_button") as Button
	student_id.text = "KG-QA-20261102"
	student_id.text_changed.emit(student_id.text)
	student_name.text = "QA Learner"
	student_name.text_changed.emit(student_name.text)
	section.text = "Grade 4 - Jade"
	section.text_changed.emit(section.text)
	_check(not next.disabled, label + " valid student fields enable green Continue")
	next.pressed.emit()
	await process_frame
	_check(_route() == "student_setup", label + " first Continue stays in Student Setup")
	_check_stages(setup, "game", label)
	_check(next.disabled, label + " Game Setup Continue disabled until game choices are complete")


func _fill_game(setup: Control, label: String) -> void:
	_check(_route() == "student_setup", label + " Game Setup still active before choices")
	if _route() != "student_setup":
		return
	(setup.get("_style_buttons")["Noun"] as Button).pressed.emit()
	(setup.get("_mode_buttons")["Seconds"] as Button).pressed.emit()
	(setup.get("_difficulty_buttons")["Easy"] as Button).pressed.emit()
	(setup.get("_player_mode_buttons")["Single Player"] as Button).pressed.emit()
	_check(not (setup.get("_continue_button") as Button).disabled,
		label + " complete Game Setup enables Continue")
	_check_stages(setup, "game", label)


func _check_stages(setup: Control, phase: String, label: String) -> void:
	var stage := setup.get_node_or_null("SetupStage") as Control
	var student := setup.get_node_or_null("SetupStage/StudentProfileCard") as Control
	var game := setup.get_node_or_null("SetupStage/GameSetupCard") as Control
	_check(stage != null and student != null and game != null,
		label + " has editor-authored independent full-screen stages")
	if stage == null or student == null or game == null:
		return
	_check(String(setup.get("_setup_phase")) == phase, label + " phase == " + phase)
	_check(student.visible == (phase == "profile") and game.visible == (phase == "game"),
		label + " shows only the " + phase + " board")
	_check(student.size.x >= 640.0 and game.size.x >= 640.0,
		label + " each board occupies useful width: " + str(student.size.x) + ", " + str(game.size.x))
	var extinct_art := false
	for node in stage.get_children():
		if node is TextureRect and node.visible and node.texture != null \
				and node.texture.resource_path == REMOVED_DOUBLE_PANEL:
			extinct_art = true
	_check(not extinct_art, label + " old double-panel frame is absent from visible scene")
	var next := setup.get("_continue_button") as Button
	var active_art := next.get_node_or_null("ButtonArtwork") as CanvasItem
	var grey_art := next.get_node_or_null("ContinueDisabledArtwork") as CanvasItem
	_check(active_art != null and grey_art != null,
		label + " Continue states have editor-authored assets")
	if active_art != null and grey_art != null:
		_check(active_art.visible != next.disabled and grey_art.visible == next.disabled,
			label + " Continue artwork matches enabled/disabled state")


func _check_calibration_payload(guided: bool, label: String, activity: String) -> void:
	_check(_route() == "calibration", label + " reaches camera calibration")
	if _route() != "calibration":
		return
	var payload: Dictionary = app.get("intercepted_calibration_payload")
	_check(String(payload.get("student_id", "")) == "KG-QA-20261102" and
		String(payload.get("game_style", "")) == "Noun" and
		String(payload.get("game_mode", "")) == "Seconds" and
		String(payload.get("difficulty", "")) == "Easy" and
		String(payload.get("activity", "")) == activity,
		label + " preserves student, selected game settings and activity")
	_check(bool(payload.get("guided_tutorial", false)) == guided and
		String(payload.get("entry_source", "")) == ("tutorial" if guided else "play"),
		label + " tutorial and Play persistence markers remain distinct")
	_check(bool(payload.get("camera_requested", false)) and not bool(payload.get("keyboard_mode", true)),
		label + " requires physical camera calibration")


func _check_integrated_tutorial(label: String, activity: String) -> void:
	var payload: Dictionary = app.get("intercepted_calibration_payload")
	var packed := load(GAMEPLAY) as PackedScene
	_check(packed != null, label + " gameplay scene loads")
	if packed == null:
		return
	var game_wrapper := packed.instantiate() as Control
	root.add_child(game_wrapper)
	game_wrapper.set_context(payload.merged({"camera_live": false, "start_countdown": true}, true))
	await process_frame
	await process_frame
	var minigame := game_wrapper.get("active_game") as Control
	_check(minigame != null, label + " embedded " + activity + " game loads")
	if minigame != null:
		_check(String(game_wrapper.get("guided_stage")) == "tutorial", label + " explanation opens before countdown")
		_check(bool(minigame.call("is_tutorial_active")), label + " guided component explanation is active")
		_check(game_wrapper.get("countdown_panel") == null, label + " 3-2-1 waits for guided explanation")
		var narration_path := "TutorialSpotlightLayer/TutorialNarration" if activity == "Human Plane" else \
			"GuidedTutorialLayer/GuidedTutorial/TutorialNarration"
		var narration := minigame.get_node_or_null(narration_path) as AudioStreamPlayer
		_check(narration != null and narration.stream != null,
			label + " embedded narration audio is present")
	game_wrapper.queue_free()
	await process_frame
	await process_frame


func _route() -> String:
	return String(app.get("current_route")) if is_instance_valid(app) else ""


func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)


func _finish() -> void:
	print("PLAY/TUTORIAL TWO-STAGE QA: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	for message in failures:
		printerr("TWO-STAGE FAIL: " + message)
	quit(0 if failures.is_empty() else 1)
