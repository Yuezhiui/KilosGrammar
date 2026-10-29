extends SceneTree

# Graphical integration test (NOT --headless):
# Godot --path . --rendering-method gl_compatibility --resolution 1280x720 \
#   --script res://tools/test_fullscreen_navigation_resolution.gd
#
# Verifies the REAL DisplayServer window state during native Main > Tutorial /
# Play / Student Setup / Activity navigation and the Settings fullscreen toggle.
# No camera or pose service is started. The existing user:// settings file is
# snapshotted byte-for-byte and restored after the test.
const MAIN_SCENE := "res://ui/main_menu/main_menu.tscn"
const PREF_PATH := "user://kilos_settings.cfg"
const FULLSCREEN_DESIGN := Vector2i(1920, 1080)
const WINDOWED_DESIGN := Vector2i(1600, 900)

var failures: Array[String] = []
var checks := 0
var app: Control
var prefs_existed := false
var original_prefs := PackedByteArray()
var initial_mode := DisplayServer.WINDOW_MODE_WINDOWED
var initial_size := Vector2i.ZERO


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("FULLSCREEN TEST: real DisplayServer resolution requires graphical Godot, not --headless.")
		quit(2)
		return
	_save_original_settings()
	initial_mode = DisplayServer.window_get_mode()
	initial_size = DisplayServer.window_get_size()
	var scene := load(MAIN_SCENE) as PackedScene
	if scene == null:
		_check(false, "main_menu.tscn loads")
		await _finish()
		return
	app = scene.instantiate() as Control
	root.add_child(app)
	# Let the real initial menu logo animation settle. Do not force the window
	# mode manually: Main._ready() is responsible for fullscreen on launch.
	await create_timer(1.40).timeout
	_check_route("main", "launch")
	_check_display(true, "launch")
	_check_panel("main")

	# Main's original button connections must preserve fullscreen.
	await _press(app.get_node_or_null("MainLayer/CenterMenu/Tutorial") as Button, "Main Tutorial")
	_check_route("tutorial_home", "Main > Tutorial")
	_check_display(true, "Main > Tutorial")
	_check_panel("Tutorial")
	var tutorial := app.get("active_panel") as Control
	await _press(tutorial.get_node_or_null("TutorialStage/BackButton") as Button if tutorial != null else null,
		"Tutorial Back to Main")
	_check_route("main", "Tutorial > Main")
	_check_display(true, "Tutorial > Main")

	await _press(app.get_node_or_null("MainLayer/CenterMenu/Play") as Button, "Main Play")
	_check_route("student_setup", "Main > Play / Student Setup")
	_check_display(true, "Main > Play / Student Setup")
	_check_panel("Student Setup")
	var student := app.get("active_panel") as Control
	if student != null:
		var student_id := student.get("_student_id_edit") as LineEdit
		var student_name := student.get("_name_edit") as LineEdit
		var grade := student.get("_grade_edit") as LineEdit
		if student_id != null and student_name != null and grade != null:
			student_id.text = "QA-FULLSCREEN-01"
			student_name.text = "Resolution Test"
			grade.text = "Grade 4"
			student.call("_select_style", "Noun")
			student.call("_select_mode", "Seconds")
			student.call("_select_difficulty", "Easy")
			await _press(student.get("_continue_button") as Button, "Student Continue")
		else:
			_check(false, "Student ID, name and grade inputs present")
	_check_route("play_activity", "Student Setup > Activity")
	_check_display(true, "Student Setup > Activity")
	_check_panel("Activity")
	# Stop at Game Selection, before Next would start a webcam/YOLO session.
	var activity := app.get("active_panel") as Control
	if activity != null:
		await _press(activity.get_node_or_null("LayoutMargins/Content/Footer/BackButton") as Button,
			"Activity Back")
		_check_route("student_setup", "Activity > Student Setup")
		_check_display(true, "Activity > Student Setup")
		student = app.get("active_panel") as Control
		await _press(student.get("_back_button") as Button if student != null else null, "Student Back")
		_check_route("main", "Student Setup > Main")
		_check_display(true, "Student Setup > Main")

	await _press(app.get_node_or_null("MainLayer/LeftMenu/Settings") as Button, "Main Settings")
	_check_route("settings", "Main > Settings")
	_check_display(true, "Main > Settings")
	_check_panel("Settings")
	var settings := app.get("active_panel") as Control
	var toggle := settings.find_child("FullscreenCheck", true, false) as CheckButton if settings != null else null
	_check(toggle != null and toggle.button_pressed, "Settings fullscreen toggle initially ON")
	if toggle != null:
		# A native CheckButton property change emits toggled(bool), exercising
		# production's real DisplayServer.window_set_mode + preference save path.
		toggle.button_pressed = false
		await _window_settle()
		_check(not toggle.button_pressed, "Settings first toggle OFF")
		_check_display(false, "Settings fullscreen OFF -> 1600x900 window")
		_check_panel("Settings windowed")
		toggle.button_pressed = true
		await _window_settle()
		_check(toggle.button_pressed, "Settings second toggle ON")
		_check_display(true, "Settings fullscreen ON again")
		_check_panel("Settings fullscreen again")
	await _press(settings.get_node_or_null("MainStage/BackButton") as Button if settings != null else null,
		"Settings Back")
	_check_route("main", "Settings > Main")
	_check_display(true, "Settings > Main")
	# Test that the next navigations do not re-apply windowed settings.
	await _press(app.get_node_or_null("MainLayer/CenterMenu/Tutorial") as Button, "Reopened Tutorial")
	_check_route("tutorial_home", "Tutorial after Settings toggles")
	_check_display(true, "Tutorial after Settings toggles")
	await _finish()


func _save_original_settings() -> void:
	prefs_existed = FileAccess.file_exists(PREF_PATH)
	if prefs_existed:
		original_prefs = FileAccess.get_file_as_bytes(PREF_PATH)
	print("FULLSCREEN PREFS backup existed=", prefs_existed,
		" bytes=", original_prefs.size(), " path=", ProjectSettings.globalize_path(PREF_PATH))


func _restore_original_settings() -> void:
	if prefs_existed:
		var writer := FileAccess.open(PREF_PATH, FileAccess.WRITE)
		if writer == null:
			_check(false, "Original settings file can be restored")
			return
		writer.store_buffer(original_prefs)
		writer.close()
		_check(FileAccess.get_file_as_bytes(PREF_PATH) == original_prefs,
			"Original user settings restored byte-for-byte")
	else:
		if FileAccess.file_exists(PREF_PATH):
			var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(PREF_PATH))
			_check(err == OK, "Test-created settings file removed")
		else:
			_check(true, "No original settings file and no saved test preferences")


func _press(button: Button, label: String) -> void:
	_check(button != null and not button.disabled, label + " exists/enabled")
	if button == null or button.disabled:
		return
	button.pressed.emit()
	await process_frame
	await process_frame


func _window_settle() -> void:
	for index in range(5):
		await process_frame
	await create_timer(0.18).timeout
	await process_frame


func _check_route(expected: String, stage: String) -> void:
	_check(app != null and String(app.get("current_route")) == expected,
		"%s route is %s (actual %s)" %
		[stage, expected, String(app.get("current_route")) if app != null else "<null>"])


func _check_panel(stage: String) -> void:
	if app == null:
		return
	# project.godot uses canvas_items stretch: the renderable LOGICAL
	# viewport remains 1280x720 even when DisplayServer/Window are physically
	# 1920x1080 fullscreen (or 1600x900 windowed). Comparing app.size to
	# root.size would incorrectly mark healthy fullscreen as "shrunk."
	var logical_canvas := root.get_visible_rect().size
	var margin := 5.0
	_check(app.size.x >= logical_canvas.x - margin and app.size.y >= logical_canvas.y - margin,
		"%s root fills logical canvas (app=%s canvas=%s physical=%s)" %
		[stage, app.size, logical_canvas, root.size])
	var route := String(app.get("current_route"))
	if route == "main":
		return
	var panel := app.get("active_panel") as Control
	var host := app.get("panel_host") as Control
	_check(panel != null and host != null, "%s mounted screen and host exist" % stage)
	if panel != null and host != null:
		_check(host.size.x >= app.size.x - margin and host.size.y >= app.size.y - margin,
			"%s host fills main app (host=%s app=%s)" % [stage, host.size, app.size])
		_check(panel.size.x >= host.size.x - margin and panel.size.y >= host.size.y - margin,
			"%s route panel fills host (panel=%s host=%s)" % [stage, panel.size, host.size])


func _check_display(expect_fullscreen: bool, stage: String) -> void:
	var mode := DisplayServer.window_get_mode()
	var window_size := DisplayServer.window_get_size()
	var screen_index := DisplayServer.window_get_current_screen()
	var screen_size := DisplayServer.screen_get_size(screen_index)
	var usable := DisplayServer.screen_get_usable_rect(screen_index)
	var content_size := root.get_visible_rect().size
	var fullscreen := mode in [
		DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	print("FULLSCREEN STATE ", stage, " mode=", mode, " window=", window_size,
		" screen=", screen_size, " usable=", usable, " root=", root.size,
		" content=", content_size)
	_check(fullscreen == expect_fullscreen,
		"%s uses %s (mode=%d)" % [stage, "fullscreen" if expect_fullscreen else "windowed", mode])
	if expect_fullscreen:
		_check(abs(window_size.x - screen_size.x) <= 4 and abs(window_size.y - screen_size.y) <= 4,
			"%s covers real monitor (%s vs %s)" % [stage, window_size, screen_size])
		# Only require the 1920x1080 contract if the test monitor is actually
		# 1920x1080; another monitor must still fill ITS native resolution.
		if screen_size == FULLSCREEN_DESIGN:
			_check(_near(window_size, FULLSCREEN_DESIGN, 4),
				"%s exact 1920x1080 fullscreen window" % stage)
	else:
		# Window decorations / small or scaled monitors may constrain the
		# requested target. Record a clear skip when physically unavailable.
		var target_fits := usable.size.x >= WINDOWED_DESIGN.x + 8 \
			and usable.size.y >= WINDOWED_DESIGN.y + 8
		if target_fits:
			_check(_near(window_size, WINDOWED_DESIGN, 4),
				"%s windowed client is 1600x900 (actual=%s)" % [stage, window_size])
		else:
			print("FULLSCREEN INFO monitor usable ", usable.size,
				" cannot fit 1600x900 with decorations; exact pixel check skipped")
			_check(window_size.x <= usable.size.x and window_size.y <= usable.size.y,
				"%s constrained window fits the usable monitor" % stage)
	_check(content_size.x > 0 and content_size.y > 0,
		"%s real root viewport stays renderable (%s)" % [stage, content_size])


func _near(a: Vector2i, b: Vector2i, tolerance: int) -> bool:
	return absi(a.x - b.x) <= tolerance and absi(a.y - b.y) <= tolerance


func _check(ok: bool, explanation: String) -> void:
	checks += 1
	if not ok:
		failures.append(explanation)
		printerr("FULLSCREEN FAIL ", explanation)


func _finish() -> void:
	if is_instance_valid(app):
		var title_music := app.get("title_music_player") as AudioStreamPlayer
		if title_music != null:
			title_music.stop()
			title_music.stream = null
		app.queue_free()
		await process_frame
		await process_frame
	# Always restore the source preferences, even if the 1600x900 assertion
	# fails. The temporary application window itself exits immediately afterward.
	_restore_original_settings()
	print("FULLSCREEN RESULT ", "PASS" if failures.is_empty() else "FAIL",
		" ", checks - failures.size(), "/", checks, " checks")
	for problem in failures:
		printerr("FULLSCREEN REGRESSION ", problem)
	quit(0 if failures.is_empty() else 1)
