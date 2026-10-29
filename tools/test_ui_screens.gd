extends SceneTree

# Run: Godot --headless --path . --script res://tools/test_ui_screens.gd
# Fast smoke test: load every current UI scene in the real menu tree with a
# no-socket database fixture (never connects to live student records).
const ROUTES := [
	"tutorial_home", "grammar_guide",
	"student_setup", "play_activity", "play_topic", "play_difficulty",
		"calibration", "gameplay", "pause",
	"results", "leaderboard", "settings", "credits"
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load("res://ui/main_menu/main_menu.tscn") as PackedScene
	if packed == null:
		push_error("Could not load original main menu")
		quit(1)
		return
	var app: Control = packed.instantiate() as Control
	app.set_script(load("res://tools/test_postgres_csv_delete_menu_fixture.gd") as Script)
	root.add_child(app)
	# The fixture suppresses title music and entrance timing for deterministic UI QA.
	await create_timer(1.35).timeout
	if AudioServer.get_bus_index("KilosMusic") < 0 or AudioServer.get_bus_index("KilosSFX") < 0:
		failures.append("Independent Music / Effects volume buses were not created")
	else:
		print("PASS  independent music/effects mixer buses")
	if String(app.get("current_route")) != "main":
		failures.append("No-socket Main Menu fixture did not start at Home")
	var play_button: Button = app.get_node("MainLayer/CenterMenu/Play")
	var focus_style: StyleBoxFlat = play_button.get_theme_stylebox("focus") as StyleBoxFlat
	if focus_style == null or focus_style.bg_color.a > 0.01 or focus_style.corner_radius_top_left < 8:
		failures.append("Play focus still has a rectangular opaque background")
	# Leaderboard / Settings still animate on hover, but the old
	# beige description bubble and native OS tooltip must never appear.
	if app.get_node_or_null("MainLayer/Tooltip") != null:
		failures.append("Obsolete Main Menu description popup remains in scene")
	for name in ["Leaderboard", "Settings"]:
		var button := app.get_node("MainLayer/LeftMenu/" + name) as Button
		if not button.tooltip_text.is_empty():
			failures.append(name + " still has a native hover tooltip")
		button.mouse_entered.emit()
		await create_timer(0.16).timeout
		if button.scale.x <= 1.0:
			failures.append(name + " lost its original hover animation")
		button.mouse_exited.emit()
		await create_timer(0.22).timeout
	app.get_node("MainLayer/CenterMenu/Play").emit_signal("pressed")
	await process_frame
	if not _assert_route(app, "student_setup", "Main Panel Play button -> Student Setup"):
		return
	var entry_form: Control = app.get("active_panel")
	var fresh_id: LineEdit = entry_form.get("_student_id_edit")
	if not fresh_id.text.is_empty():
		failures.append("Main Play did not open an EMPTY student form")
	app.call("_return_to_main")
	await process_frame
	for route in ROUTES:
		app.call("_on_panel_requested", route, {})
		await process_frame
		var panel: Control = app.get("active_panel") as Control
		if String(app.get("current_route")) != route:
			failures.append(route + " did not activate")
		elif panel == null or not is_instance_valid(panel):
			failures.append(route + " has no Control root")
		elif not panel.has_signal("requested"):
			failures.append(route + " has no navigation signal")
		else:
			print("PASS  ", route)

	# Exercise redesigned Settings beyond just checking scene loading.
	app.call("_on_panel_requested", "settings", {})
	await process_frame
	var settings_panel: Control = app.get("active_panel") as Control
	var settings_title: Control = settings_panel.find_child("SettingsTitle", true, false) as Control
	var title_has_art := settings_title is TextureRect and (settings_title as TextureRect).texture != null
	var title_has_text := settings_title is RichTextLabel and not (settings_title as RichTextLabel).text.is_empty()
	if settings_title == null or not settings_title.visible or not (title_has_art or title_has_text):
		failures.append("Settings title art or accessible fallback text missing")
	else:
		print("PASS  Settings title")
	_test_audio_slider(settings_panel, "VolumeSlider", "Master")
	_test_audio_slider(settings_panel, "MusicSlider", "KilosMusic")
	_test_audio_slider(settings_panel, "EffectsSlider", "KilosSFX")
	for removed_page in ["ControlsPage", "CameraPage", "SidebarPanel",
			"SidebarSettingsTab", "SidebarControlsTab", "SidebarCameraTab"]:
		if settings_panel.find_child(removed_page, true, false) != null:
			failures.append("Removed Settings component still exists: " + removed_page)
	var audio_only := settings_panel.find_child("SettingsPage", true, false) as Control
	if audio_only == null or not audio_only.visible:
		failures.append("Audio & Display should be the only visible Settings page")
	else:
		print("PASS  Settings Audio & Display only; obsolete tabs deleted")
	var restored_credits := app.get_node_or_null("MainLayer/LeftMenu/Credits") as Button
	if restored_credits == null or restored_credits.disabled:
		failures.append("Credits Main Menu button was not restored")
	if not ResourceLoader.exists("res://ui/secondary/credits/credits.tscn"):
		failures.append("Restored Credits scene is missing")

	# Verify complete teacher setup and single-pass game configuration.
	# Return to Main and explicitly choose Play. A preceding Tutorial-only
	# scene smoke-test deliberately leaves practice provenance active; that
	# must not silently convert into a savable Play session.
	app.call("_return_to_main")
	await process_frame
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	var form: Control = app.get("active_panel")
	(form.get("_student_id_edit") as LineEdit).text = "KG-0001"
	(form.get("_name_edit") as LineEdit).text = "John D. Doe"
	(form.get("_grade_edit") as LineEdit).text = "Grade 2 Apple"
	form.call("_select_style", "Noun")
	form.call("_select_mode", "Seconds")
	form.call("_select_difficulty", "Easy")
	form.call("_continue")
	await process_frame
	if not _assert_route(app, "play_activity", "Student Setup -> Activity"):
		return
	var game_select := app.get("active_panel") as Control
	game_select.call("_select_activity", "Catch the Word")
	if game_select.get_node_or_null("LayoutMargins/Content/Footer/PlayKeyboardButton") != null or game_select.has_method("_play_keyboard_now"):
		failures.append("Game Selection still exposes removed keyboard shortcut")
	# Synthetic camera presence prevents webcam startup during navigation,
	# but provides no calibration samples or fake completion.
	var pose_service := root.get_node("PoseService")
	pose_service.active = true
	pose_service.player_x = -1.0
	pose_service.current_status = {"state": "waiting", "pose": false}
	(game_select.get("next_button") as Button).pressed.emit()
	await process_frame
	if not _assert_route(app, "calibration", "Game Selection Next -> camera-only Calibration"):
		return
	var calibration_state := (app.get("session_state") as Dictionary).duplicate(true)
	if bool(calibration_state.get("keyboard_mode", true)) or not bool(calibration_state.get("camera_requested", false)):
		failures.append("Game Selection Next did not select camera-only calibration")
	var calibration_panel := app.get("active_panel") as Control
	if calibration_panel.get_node_or_null("TutorialStage/SkipButton") != null:
		failures.append("Calibration still contains a SKIP control")
	calibration_panel.call("_process", 3.01) # Title-only intro has no Back action.
	(calibration_panel.get_node("TutorialStage/Navigation/BackButton") as Button).pressed.emit()
	await process_frame
	_assert_route(app, "play_activity", "Calibration Back -> Choose Activity preserves teacher setup")
	# Gameplay/results can be smoke-tested independently by explicit router
	# injection. This does NOT signal a completed camera calibration.
	calibration_state["keyboard_mode"] = false
	calibration_state["start_countdown"] = false
	app.call("_on_panel_requested", "gameplay", calibration_state)
	await process_frame
	if not _assert_route(app, "gameplay", "Explicit isolated gameplay fixture"):
		return
	for activity in ["Catch the Word", "Balloon Popping", "Human Plane"]:
		app.call("_on_panel_requested", "gameplay", {"activity": activity, "topic": "Noun", "game_style": "Noun", "difficulty": "Easy", "demo_mode": true})
		await process_frame
		if not _assert_route(app, "gameplay", "Gameplay scene: " + activity):
			return
		var mounted_game: Control = (app.get("active_panel") as Control).get_node_or_null("ActiveMiniGame") as Control
		if mounted_game == null:
			failures.append("Could not instantiate playable activity: " + activity)
		elif not mounted_game.has_method("get_context") or not mounted_game.has_method("set_body_x"):
			failures.append("Missing playable game input/context API: " + activity)
	var gameplay: Control = app.get("active_panel") as Control
	gameplay.call("_finish_round")
	await process_frame
	if not _assert_route(app, "results", "Playable 2D Gameplay -> Results"):
		return
	(app.get("active_panel") as Control).call("_request", "student_setup")
	await process_frame
	if not _assert_route(app, "student_setup", "Game Over Retry -> Student Setup"):
		return
	var state: Dictionary = app.get("session_state")
	for stat_key in ["score", "streak", "best_streak", "correct", "attempts", "total", "accuracy", "time_remaining"]:
		if state.has(stat_key):
			failures.append("Retry retained old round stat: " + stat_key)
	var retry_form: Control = app.get("active_panel")
	if (retry_form.get("_student_id_edit") as LineEdit).text != "KG-0001":
		failures.append("Retry lost student ID prefill")
	(retry_form.get("_student_id_edit") as LineEdit).text = "KG-0002"
	retry_form.call("_on_student_id_changed", "KG-0002")
	if not (retry_form.get("_name_edit") as LineEdit).text.is_empty() or not (retry_form.get("_grade_edit") as LineEdit).text.is_empty():
		failures.append("Changing student ID retained the previous student's profile")
	print("PASS  retry prefill and student ID identity clearing")

	app.call("_on_panel_requested", "tutorial_home", {})
	await process_frame
	var tutorial_panel: Control = app.get("active_panel") as Control
	var tutorial_start: Button = tutorial_panel.get_node_or_null("TutorialStage/StartButton") as Button
	if tutorial_start == null:
		failures.append("Guided Tutorial has no scene-editable StartButton")
	else:
		tutorial_start.pressed.emit()
		await process_frame
		_assert_route(app, "play_activity", "Guided Tutorial begins with game selection")
		if not bool((app.get("session_state") as Dictionary).get("guided_tutorial", false)):
			failures.append("Guided Tutorial lost its flow flag at game selection")
		_assert_route(app, "play_activity", "Guided Tutorial remains in game selection until measured calibration")
	app.call("_return_to_main")
	await process_frame
	if String(app.get("current_route")) != "main":
		failures.append("Main panel was not restored")
	var music: AudioStreamPlayer = app.get("title_music_player")
	if music:
		music.stop()
		music.stream = null
	app.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("PASS  all %d UI scenes loaded and returned to Main Panel" % ROUTES.size())
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL  " + failure)
		quit(1)


func _assert_route(app: Control, expected: String, label: String) -> bool:
	if String(app.get("current_route")) == expected:
		print("PASS  ", label)
		return true
	else:
		var reason := "%s expected %s but got %s" % [label, expected, String(app.get("current_route"))]
		failures.append(reason)
		push_error("FAIL  " + reason)
		# A bad route must stop here instead of calling nonexistent functions
		# on the previous screen and leaving SceneTree running indefinitely.
		app.queue_free()
		quit(1)
		return false


func _test_audio_slider(settings_panel: Control, slider_name: String, bus_name: String) -> void:
	var slider: HSlider = settings_panel.find_child(slider_name, true, false) as HSlider
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if slider == null or bus_index < 0:
		failures.append("Settings audio control unavailable: %s -> %s" % [slider_name, bus_name])
		return
	var initial_db: float = AudioServer.get_bus_volume_db(bus_index)
	slider.value = 37.0
	var actual_percent: float = db_to_linear(AudioServer.get_bus_volume_db(bus_index)) * 100.0
	if absf(actual_percent - 37.0) > 1.0:
		failures.append("%s slider did not update the %s audio bus" % [slider_name, bus_name])
	else:
		print("PASS  ", slider_name, " changes real ", bus_name, " volume")
	AudioServer.set_bus_volume_db(bus_index, initial_db)
	slider.value = clampf(db_to_linear(initial_db) * 100.0, 0.0, 100.0)
