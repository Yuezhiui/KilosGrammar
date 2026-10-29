extends SceneTree

# Verify the Student Setup screen is visibly editable in Godot's scene tree.
# Use CAPTURE_STUDENT_SETUP=1 with a graphical renderer to save a temporary PNG.
const SCENE := preload("res://ui/student/setup/student_setup.tscn")
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
var checks := 0
var problems: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dimensions in SIZES:
		root.size = dimensions
		root.content_scale_size = dimensions
		var screen := SCENE.instantiate() as Control
		root.add_child(screen)
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		var parent := "LayoutMargins/StudentSetupColumn"
		var grid := screen.get_node_or_null(parent + "/StudentSetupScroll/SetupCardGrid") as GridContainer
		_verify(grid != null and grid.columns == (1 if dimensions.x < 1040 else 2), "screen card columns %s" % dimensions)
		if grid == null:
			screen.queue_free()
			await process_frame
			continue
		var profile := grid.get_node_or_null("StudentProfileCard/ProfileContent") as VBoxContainer
		var setup := grid.get_node_or_null("GameSetupCard/GameContent") as VBoxContainer
		_verify(profile != null and setup != null, "both cards editor authored")
		var input_ids := ["StudentIdGroup/StudentIdEdit", "StudentNameGroup/StudentNameEdit", "GradeSectionGroup/GradeSectionEdit"]
		for part in input_ids:
			var field := profile.get_node_or_null(part) as LineEdit
			_verify(field != null and field.focus_mode == Control.FOCUS_ALL, part + " native editable field")
		var button_count := 0
		var option_panels := [
			{"container": setup.get_node("GameStyleGrid"), "names": ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]},
			{"container": setup.get_node("LowerSelections/ModeColumn/ModeRow"), "names": ["Seconds", "Lives"]},
			{"container": setup.get_node("LowerSelections/DifficultyColumn/DifficultyRow"), "names": ["Easy", "Normal", "Hard"]},
		]
		for panel in option_panels:
			for item in panel["names"]:
				var native := (panel["container"] as Node).get_node_or_null(item + "Button") as Button
				_verify(native != null, item + " scene-authored game choice")
				if native != null:
					button_count += 1
					var art := native.get_node_or_null("ButtonArtwork") as TextureRect
					_verify(art != null and art.texture != null and art.mouse_filter == Control.MOUSE_FILTER_IGNORE, item + " editable child PNG")
					_verify(not native.disabled, item + " enabled state")
		_verify(button_count == 10, "all 10 editor-authored game choices")
		var styles := setup.get_node("GameStyleGrid") as GridContainer
		_verify(styles.get_child_count() == 5, "only five supported grammar topics appear")
		for child_name in ["BackButton", "ContinueButton"]:
			var child := screen.get_node_or_null(parent + "/SetupActions/" + child_name) as Button
			_verify(child != null and child.get_node_or_null("ButtonArtwork") is TextureRect, child_name + " native editable footer")
		_verify(screen.find_child("StudentClassroomBackdrop", true, false) is TextureRect, "independent backdrop image")
		_verify(screen.find_child("StudentReadabilityOverlay", true, false) is ColorRect, "independent readability layer")
		var student_id := screen.get("_student_id_edit") as LineEdit
		if student_id:
			student_id.grab_focus()
			await process_frame
			_verify(student_id.has_focus(), "Student ID keyboard focus")

		if dimensions == Vector2i(1280, 720) and OS.get_environment("CAPTURE_STUDENT_SETUP") == "1":
			if DisplayServer.get_name() == "headless":
				_verify(false, "visual capture requires renderer")
			else:
				await RenderingServer.frame_post_draw
				var filename := ProjectSettings.globalize_path("res://ui/student/_review_student_setup.png")
				_verify(root.get_texture().get_image().save_png(filename) == OK, "preview capture saved")
				print("STUDENT SETUP CAPTURE ", filename)
		screen.queue_free()
		await process_frame

	if DisplayServer.get_name() != "headless":
		# A compact physical window can still use a 1280-wide logical canvas;
		# the screen must stack both authored cards and show the scroll cue.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_size(Vector2i(875, 500))
		root.size = Vector2i(875, 500)
		root.content_scale_size = Vector2i(1280, 720)
		var compact := SCENE.instantiate() as Control
		root.add_child(compact)
		compact.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		var scroll := compact.get_node("LayoutMargins/StudentSetupColumn/StudentSetupScroll") as ScrollContainer
		var grid := scroll.get_node("SetupCardGrid") as GridContainer
		var cue := compact.get_node("LayoutMargins/StudentSetupColumn/GameSetupScrollHint") as Button
		_verify(grid.columns == 1, "physical 875 px viewport stacks cards")
		_verify(cue.visible and cue.text.begins_with("SCROLL DOWN"), "physical 875 px viewport displays scroll cue")
		cue.pressed.emit()
		for i in range(4):
			await process_frame
		_verify(scroll.scroll_vertical > 0, "scroll cue reveals editor-authored game choices")
		compact.queue_free()
		await process_frame

	if problems.is_empty():
		print("PASS scene-authored Student Setup: %d checks across 3 sizes" % checks)
		quit(0)
	else:
		for problem in problems:
			push_error(problem)
		print("FAIL scene-authored Student Setup: %d/%d checks" % [problems.size(), checks])
		quit(1)


func _verify(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		problems.append(message)
