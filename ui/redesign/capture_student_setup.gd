extends SceneTree

# Graphical capture and focused functional QA of the redesigned Student Setup.
# Run from the Godot project root without --headless:
# Godot --path . --rendering-method gl_compatibility --script res://ui/redesign/capture_student_setup.gd
const SCENE := "res://ui/student/student_setup.tscn"
const OUTPUT := "res://showcase/ui_redesign_m1"
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var packed: PackedScene = load(SCENE)
	for size_value in SIZES:
		# Force a true 875-wide logical layout instead of shrinking the default
		# 1280 canvas (which would incorrectly avoid the one-column breakpoint).
		root.content_scale_size = size_value
		root.size = size_value
		DisplayServer.window_set_size(size_value)
		await process_frame
		var form: Control = packed.instantiate()
		root.add_child(form)
		form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		var prefix := "%d×%d" % [size_value.x, size_value.y]
		await RenderingServer.frame_post_draw
		var image_value := root.get_texture().get_image()
		if image_value.get_size() != size_value:
			_fail(prefix + ": wrong actual screenshot resolution " + str(image_value.get_size()))
		var image_path := ProjectSettings.globalize_path(OUTPUT.path_join("student_setup_classroom_%dx%d.png" % [size_value.x, size_value.y]))
		if image_value.save_png(image_path) != OK:
			_fail(prefix + ": failed to save screenshot")
		else:
			print("CAPTURE ", image_path)
		_check_form(form, prefix)
		await _check_compact_keyboard_navigation(form, size_value)
		form.queue_free()
		await process_frame
	if failures.is_empty():
		print("PASS Student Setup 875/1280/1920 redraw and interactions")
		quit(0)
	else:
		for problem in failures:
			push_error("STUDENT QA FAIL " + problem)
		quit(1)


func _check_form(form: Control, name: String) -> void:
	var classroom := form.find_child("StudentClassroomBackdrop", true, false) as TextureRect
	var wash := form.find_child("StudentReadabilityOverlay", true, false) as ColorRect
	if classroom == null or classroom.texture == null:
		_fail(name + ": classroom background texture missing")
	elif classroom.mouse_filter != Control.MOUSE_FILTER_IGNORE or classroom.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_COVERED:
		_fail(name + ": classroom image may intercept input or distort its aspect ratio")
	if wash == null or wash.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail(name + ": noninteractive readability overlay missing")
	elif wash.color.a < 0.15 or wash.color.a > 0.40:
		_fail(name + ": readability wash too faint or hides classroom illustration")
	var scroll := form.find_child("StudentSetupScroll", true, false) as ScrollContainer
	var grid := form.find_child("SetupCardGrid", true, false) as GridContainer
	var back := form.find_child("BackButton", true, false) as Button
	var next := form.get("_continue_button") as Button
	var identifier := form.get("_student_id_edit") as LineEdit
	var student_name := form.get("_name_edit") as LineEdit
	var grade := form.get("_grade_edit") as LineEdit
	var hint := form.find_child("GameSetupScrollHint", true, false) as Button
	if scroll == null or grid == null or back == null or next == null or identifier == null or student_name == null or grade == null:
		_fail(name + ": required live controls missing")
		return
	if not next.disabled:
		_fail(name + ": Continue enabled before filling required fields")
	# canvas_items/expand preserves a 1280-wide logical viewport when the
	# operating-system window scales down to 875 physical pixels.
	var logical_narrow := form.size.x < 1040.0
	if grid.columns != (1 if logical_narrow else 2):
		_fail(name + ": wrong card columns for logical width " + str(form.size.x))
	if hint == null or (hint.visible != logical_narrow):
		_fail(name + ": compact-only scroll guidance missing or wrongly visible")
	elif logical_narrow and hint.text != "SCROLL DOWN FOR GAME SETUP ↓":
		_fail(name + ": initial cue does not explain where to scroll")
	if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_fail(name + ": horizontal scrolling activated")
	var viewport_size := form.get_viewport_rect().size
	for control in [back, next]:
		var bounds: Rect2 = (control as Control).get_global_rect()
		if bounds.position.x < 0 or bounds.position.y < 0 or bounds.end.x > viewport_size.x or bounds.end.y > viewport_size.y:
			_fail(name + ": footer action outside viewport: " + str(bounds))
	var styles: Dictionary = form.get("_style_buttons")
	var modes: Dictionary = form.get("_mode_buttons")
	var difficulties: Dictionary = form.get("_difficulty_buttons")
	if styles.size() != 5 or modes.size() != 2 or difficulties.size() != 3:
		_fail(name + ": wrong enabled game-choice counts")
	var future_count := 0
	for button in grid.find_children("*", "Button", true, false):
		if "SOON" in (button as Button).text:
			future_count += 1
			if not (button as Button).disabled:
				_fail(name + ": future grammar option was enabled")
	if future_count != 3:
		_fail(name + ": expected exactly 3 disabled future grammar options")
	var lookup_ids: Array[String] = []
	form.student_lookup_requested.connect(func(student_id: String) -> void: lookup_ids.append(student_id))
	var requested_routes: Array[String] = []
	var sent_payloads: Array[Dictionary] = []
	form.requested.connect(func(target: String, payload: Dictionary) -> void:
		requested_routes.append(target)
		sent_payloads.append(payload)
	)
	identifier.text = "KG-0001"
	student_name.text = "Sample Student"
	grade.text = "Grade 2 Apple"
	form.call("_on_field_changed", student_name.text)
	form.call("_request_lookup")
	if lookup_ids != ["KG-0001"]:
		_fail(name + ": student_lookup_requested signal lost or wrong student ID")
	form.call("_select_style", "Noun")
	form.call("_select_mode", "Lives")
	form.call("_select_difficulty", "Hard")
	if next.disabled:
		_fail(name + ": Continue disabled with all six selections complete")
	form.call("_continue")
	if requested_routes != ["play_activity"] or sent_payloads.is_empty():
		_fail(name + ": valid Continue did not emit play_activity")
	else:
		var payload := sent_payloads[0]
		for key in ["student_id", "student_name", "grade_section", "game_style", "topic", "game_mode", "difficulty"]:
			if not payload.has(key):
				_fail(name + ": Continue omitted required context " + key)
		if payload.get("student_id") != "KG-0001" or payload.get("game_mode") != "Lives" or payload.get("difficulty") != "Hard":
			_fail(name + ": Continue emitted wrong form data")
	form.call("_on_student_id_changed", "KG-NEW")
	# text_changed does not fire when assigning LineEdit.text from a script;
	# set new text explicitly to simulate the keyboard-edited signal.
	identifier.text = "KG-NEW"
	form.call("_on_student_id_changed", "KG-NEW")
	if not student_name.text.is_empty() or not grade.text.is_empty() or not next.disabled:
		_fail(name + ": changing ID did not clear prior student's fields")


func _check_compact_keyboard_navigation(form: Control, dimensions: Vector2i) -> void:
	var scroll := form.find_child("StudentSetupScroll", true, false) as ScrollContainer
	var grid := form.find_child("SetupCardGrid", true, false) as GridContainer
	if grid.columns != 1:
		return
	var topic: Button = (form.get("_style_buttons") as Dictionary).get("Noun") as Button
	var grade := form.get("_grade_edit") as LineEdit
	var hint := form.find_child("GameSetupScrollHint", true, false) as Button
	if topic == null or grade == null or hint == null:
		_fail(str(dimensions) + ": compact keyboard test missing controls")
		return
	var bar := scroll.get_v_scroll_bar()
	if not hint.visible or bar.max_value <= bar.page + 3.0:
		_fail(str(dimensions) + ": stacked game panel does not expose visible guidance/scrollbar")
		return
	if scroll.scroll_vertical > 5:
		_fail(str(dimensions) + ": compact setup did not initially open at Student Profile")
	grade.grab_focus()
	await process_frame
	# Existing keyboard Enter binding from Grade & Section must take the
	# student to the first grammar topic, even when that topic is offscreen.
	grade.text_submitted.emit("Grade 2 Apple")
	await process_frame
	await process_frame
	await process_frame
	if form.get_viewport().gui_get_focus_owner() != topic:
		_fail(str(dimensions) + ": Grade Enter did not focus first grammar topic")
	if scroll.scroll_vertical <= 5:
		_fail(str(dimensions) + ": focused offscreen topic did not trigger scrolling")
	var clipped := scroll.get_global_rect()
	var visible_topic := topic.get_global_rect()
	if not clipped.intersects(visible_topic):
		_fail(str(dimensions) + ": focused topic still hidden outside scroll viewport")
	if hint.text != "↑ BACK TO STUDENT PROFILE":
		_fail(str(dimensions) + ": cue did not change after scrolling to Game Setup")
	await RenderingServer.frame_post_draw
	var image_value := root.get_texture().get_image()
	var image_path := ProjectSettings.globalize_path(OUTPUT.path_join("student_setup_compact_game_setup_%dx%d.png" % [dimensions.x, dimensions.y]))
	if image_value.save_png(image_path) == OK:
		print("CAPTURE ", image_path)
	else:
		_fail(str(dimensions) + ": scrolled Game Setup screenshot failed")
	# Every active grammar option and the final mode/difficulty row must be
	# reachable through native keyboard focus, not just by manually dragging
	# the scrollbar. Offscreen focused buttons should be brought into view.
	var active_styles: Dictionary = form.get("_style_buttons")
	var mode_buttons: Dictionary = form.get("_mode_buttons")
	var difficulty_buttons: Dictionary = form.get("_difficulty_buttons")
	for control in [
		active_styles["Pronoun"], active_styles["Verb"], active_styles["Adjective"],
		active_styles["Adverb"], mode_buttons["Seconds"], mode_buttons["Lives"],
		difficulty_buttons["Easy"], difficulty_buttons["Normal"], difficulty_buttons["Hard"]
	]:
		var focused_button := control as Button
		if focused_button.focus_mode != Control.FOCUS_ALL:
			_fail(str(dimensions) + ": game choice cannot receive keyboard focus: " + focused_button.text)
		focused_button.grab_focus()
		await process_frame
		await process_frame
		if form.get_viewport().gui_get_focus_owner() != focused_button:
			_fail(str(dimensions) + ": couldn't focus game choice: " + focused_button.text)
		if not scroll.get_global_rect().intersects(focused_button.get_global_rect()):
			_fail(str(dimensions) + ": keyboard-focused option stayed unreachable: " + focused_button.text)
	await RenderingServer.frame_post_draw
	var options_path := ProjectSettings.globalize_path(OUTPUT.path_join("student_setup_compact_options_%dx%d.png" % [dimensions.x, dimensions.y]))
	if root.get_texture().get_image().save_png(options_path) == OK:
		print("CAPTURE ", options_path)
	else:
		_fail(str(dimensions) + ": lower options screenshot failed")
	# Accessible cue also returns the user to the top and focuses ID.
	hint.pressed.emit()
	await process_frame
	await process_frame
	if scroll.scroll_vertical > 5 or form.get_viewport().gui_get_focus_owner() != form.get("_student_id_edit"):
		_fail(str(dimensions) + ": hint failed to return to Student Profile")


func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL ", message)
