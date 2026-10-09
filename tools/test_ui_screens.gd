extends SceneTree

# Run: Godot --headless --path . --script res://tools/test_ui_screens.gd
# Fast smoke test: load every current UI scene in the real main menu host.
const ROUTES := [
	"tutorial_home", "tutorial_practice", "tutorial_complete", "grammar_guide",
	"student_setup", "play_activity", "play_topic", "play_difficulty",
	"camera_check", "calibration", "ready", "gameplay", "pause",
	"results", "leaderboard", "settings", "credits"
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed: PackedScene = load("res://main_menu.tscn") as PackedScene
	if packed == null:
		push_error("Could not load original main menu")
		quit(1)
		return
	var app: Control = packed.instantiate() as Control
	root.add_child(app)
	# Allow the original 1.12-second intro coroutine to finish before teardown.
	await create_timer(1.35).timeout
	if AudioServer.get_bus_index("KilosMusic") < 0 or AudioServer.get_bus_index("KilosSFX") < 0:
		failures.append("Independent Music / Effects volume buses were not created")
	else:
		print("PASS  independent music/effects mixer buses")
	var menu_music: AudioStreamPlayer = app.get("title_music_player")
	if menu_music == null or menu_music.bus != "KilosMusic":
		failures.append("TitleMusic is not routed to the Music volume bus")
	var play_button: Button = app.get_node("MainLayer/CenterMenu/Play")
	var focus_style: StyleBoxFlat = play_button.get_theme_stylebox("focus") as StyleBoxFlat
	if focus_style == null or focus_style.bg_color.a > 0.01 or focus_style.corner_radius_top_left < 8:
		failures.append("Play focus still has a rectangular opaque background")
	var settings_button: Button = app.get_node("MainLayer/LeftMenu/Settings")
	app.call("_show_tooltip", settings_button, "Settings tooltip test")
	await process_frame
	var tip: PanelContainer = app.get_node("MainLayer/Tooltip")
	if not tip.visible or tip.global_position.x < settings_button.get_global_rect().end.x + 18.0:
		failures.append("Settings tooltip hidden or too close to button")
	app.call("_hide_tooltip")
	app.call("_show_tooltip", app.get_node("MainLayer/LeftMenu/Credits"), "Credits tooltip test")
	await create_timer(0.14).timeout
	if not tip.visible or not String(app.get_node("MainLayer/Tooltip/Text").text).contains("Credits tooltip"):
		failures.append("Tooltip disappeared during quick hover change")
	app.call("_hide_tooltip")
	app.get_node("MainLayer/CenterMenu/Play").emit_signal("pressed")
	await process_frame
	_assert_route(app, "student_setup", "Main Panel Play button -> Student Setup")
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

	# Exercise redesigned Settings and Credits rather than just checking load.
	app.call("_on_panel_requested", "settings", {})
	await process_frame
	var settings_panel: Control = app.get("active_panel") as Control
	var settings_title: RichTextLabel = settings_panel.find_child("SettingsTitle", true, false) as RichTextLabel
	if settings_title == null or not settings_title.bbcode_enabled or not settings_title.text.contains("[wave amp=40.0 freq=4.0 connected=1]"):
		failures.append("Settings reference title lost Comic Lemon wave animation")
	else:
		print("PASS  Settings wave title")
	_test_audio_slider(settings_panel, "VolumeSlider", "Master")
	_test_audio_slider(settings_panel, "MusicSlider", "KilosMusic")
	_test_audio_slider(settings_panel, "EffectsSlider", "KilosSFX")
	settings_panel.call("_switch_tab", "controls")
	var control_page: Control = settings_panel.find_child("ControlsPage", true, false) as Control
	if control_page == null or not control_page.visible:
		failures.append("Settings CONTROLS tab did not open")
	settings_panel.call("_switch_tab", "camera")
	var camera_page: Control = settings_panel.find_child("CameraPage", true, false) as Control
	if camera_page == null or not camera_page.visible:
		failures.append("Settings CAMERA tab did not open")
	else:
		print("PASS  Settings tab navigation")
	app.call("_on_panel_requested", "credits", {})
	await process_frame
	await process_frame
	var credits_panel: Control = app.get("active_panel") as Control
	var credits_title: RichTextLabel = credits_panel.find_child("HeaderTitle", true, false) as RichTextLabel
	if credits_title == null or not credits_title.bbcode_enabled or not credits_title.text.contains("[wave amp=40.0 freq=4.0 connected=1]"):
		failures.append("Credits reference title lost Comic Lemon wave animation")
	else:
		print("PASS  Credits wave title")
	var credits_scroll: ScrollContainer = credits_panel.find_child("CreditsScroll", true, false) as ScrollContainer
	var credits_header: Control = credits_panel.find_child("Header", true, false) as Control
	if credits_scroll == null or credits_header == null or credits_scroll.is_ancestor_of(credits_header):
		failures.append("Credits header is missing or incorrectly inside its scroll area")
	else:
		print("PASS  Credits fixed header and separate scroll region")
		var scroll_bar: VScrollBar = credits_scroll.get_v_scroll_bar()
		var stack: Control = credits_panel.find_child("CreditsStack", true, false) as Control
		if stack.get_combined_minimum_size().y > credits_scroll.size.y + 2.0 and scroll_bar.max_value <= scroll_bar.page:
			failures.append("Credits overflow is not scrollable; names may be cut off")
		else:
			if scroll_bar.max_value > scroll_bar.page:
				credits_scroll.scroll_vertical = int(scroll_bar.max_value)
				print("PASS  Credits contributor list can scroll to legal credits")
			else:
				print("PASS  Credits contributor list fits without scrolling at this size")

	# Verify complete teacher setup and single-pass game configuration.
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	var form: Control = app.get("active_panel")
	(form.get("_student_id_edit") as LineEdit).text = "KG-0001"
	(form.get("_name_edit") as LineEdit).text = "John D. Doe"
	(form.get("_grade_edit") as LineEdit).text = "Grade 2 Apple"
	form.call("_select_style", "Noun")
	form.call("_select_mode", "Quiz")
	form.call("_select_difficulty", "Easy")
	form.call("_continue")
	await process_frame
	_assert_route(app, "play_activity", "Student Setup -> Activity")
	(app.get("active_panel") as Control).call("_select_activity", "Catch the Word")
	(app.get("active_panel") as Control).call("_go_next")
	await process_frame
	_assert_route(app, "camera_check", "Activity -> Camera (no duplicate configuration)")
	(app.get("active_panel") as Control).call("_go_back")
	await process_frame
	_assert_route(app, "play_activity", "Camera Back -> Game Selection for teacher flow")
	app.call("_on_panel_requested", "camera_check", {})
	await process_frame
	app.call("_on_panel_requested", "calibration", {"entry_source": "play"})
	await process_frame
	(app.get("active_panel") as Control).call("_continue_flow", false)
	await process_frame
	_assert_route(app, "ready", "Play Calibration -> Ready")
	app.call("_on_panel_requested", "gameplay", {"demo_mode": true})
	await process_frame
	var gameplay: Control = app.get("active_panel") as Control
	gameplay.call("_simulate_correct")
	gameplay.call("_simulate_wrong")
	gameplay.call("_finish_demo")
	await process_frame
	_assert_route(app, "results", "Gameplay -> Results")
	(app.get("active_panel") as Control).call("_request", "student_setup")
	await process_frame
	_assert_route(app, "student_setup", "Game Over Retry -> Student Setup")
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
	app.call("_on_panel_requested", "camera_check", {"entry_source": "tutorial"})
	await process_frame
	app.call("_on_panel_requested", "calibration", {})
	await process_frame
	(app.get("active_panel") as Control).call("_continue_flow", false)
	await process_frame
	_assert_route(app, "tutorial_practice", "Tutorial Calibration -> Practice")
	(app.get("active_panel") as Control).call("_go_back")
	await process_frame
	_assert_route(app, "calibration", "Guided Practice Back -> Calibration")
	app.call("_on_panel_requested", "tutorial_home", {})
	await process_frame
	app.call("_on_panel_requested", "tutorial_practice", {"from_calibration": false})
	await process_frame
	(app.get("active_panel") as Control).call("_go_back")
	await process_frame
	_assert_route(app, "tutorial_home", "Direct Practice Back -> Tutorial Home")
	app.call("_on_panel_requested", "tutorial_practice", {"from_calibration": false})
	await process_frame
	(app.get("active_panel") as Control).call("_request", "tutorial_complete", {"tutorial_practiced": true})
	await process_frame
	_assert_route(app, "tutorial_complete", "Practice -> Tutorial Complete")
	(app.get("active_panel") as Control).call("_request", "student_setup", {"fresh_setup": true})
	await process_frame
	_assert_route(app, "student_setup", "Tutorial Complete Play -> Student Setup")
	if not (app.get("active_panel") as Control).get("_student_id_edit").text.is_empty():
		failures.append("Tutorial-to-Play did not start with a blank student form")
	app.call("_on_panel_requested", "camera_check", {"entry_source": "play", "setup_preview": false})
	await process_frame
	(app.get("active_panel") as Control).call("_go_back")
	await process_frame
	_assert_route(app, "play_difficulty", "Camera Back -> Difficulty")
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


func _assert_route(app: Control, expected: String, label: String) -> void:
	if String(app.get("current_route")) == expected:
		print("PASS  ", label)
	else:
		failures.append("%s expected %s but got %s" % [label, expected, String(app.get("current_route"))])


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
