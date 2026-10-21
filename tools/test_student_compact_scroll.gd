extends SceneTree

# Focused regression for the physical 875px window with a 1280px logical
# canvas. The setup panel must stack, expose its scroll cue, and move keyboard
# focus to the actual game choices instead of shrinking two cards side by side.
const SIZE := Vector2i(875, 500)
const OUTPUT := "res://showcase/ui_redesign_20261016/final"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Student compact scroll QA requires a graphical display")
		quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(SIZE)
	root.content_scale_size = Vector2i(1280, 720)
	root.size = SIZE
	var setup := (load("res://ui/student/student_setup.tscn") as PackedScene).instantiate() as Control
	root.add_child(setup)
	setup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	var grid := setup.get_node("LayoutMargins/StudentSetupColumn/StudentSetupScroll/SetupCardGrid") as GridContainer
	var scroll := setup.get_node("LayoutMargins/StudentSetupColumn/StudentSetupScroll") as ScrollContainer
	var hint := setup.get_node("LayoutMargins/StudentSetupColumn/GameSetupScrollHint") as Button
	var issues: Array[String] = []
	if DisplayServer.window_get_size() != SIZE:
		issues.append("Native window is not 875x500")
	if grid.columns != 1:
		issues.append("Student/Game cards did not stack in the physical compact window")
	if not hint.visible or not hint.text.begins_with("SCROLL DOWN"):
		issues.append("Initial setup scroll hint does not direct students to game choices")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join("student_setup_compact_initial_875x500.png")))
	hint.pressed.emit()
	for i in range(5):
		await process_frame
	if scroll.scroll_vertical <= 0:
		issues.append("Scroll hint did not scroll toward grammar selection")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join("student_setup_compact_scrolled_875x500.png")))
	# Tab/focus must bring later topics and the bottom game controls into the
	# scroll viewport, rather than leaving them outside the visible card.
	for entry in [["_style_buttons", "Adverb"], ["_mode_buttons", "Lives"], ["_difficulty_buttons", "Hard"]]:
		var options: Dictionary = setup.get(entry[0])
		var choice := options.get(entry[1]) as Button
		if choice == null:
			issues.append("Missing keyboard selection " + entry[1])
			continue
		choice.grab_focus()
		for i in range(3):
			await process_frame
		var visible_part := choice.get_global_rect().intersection(scroll.get_global_rect())
		if root.gui_get_focus_owner() != choice or not visible_part.has_area():
			issues.append("Keyboard focus did not expose " + entry[1])
	if not hint.text.begins_with("↑ BACK TO STUDENT PROFILE"):
		issues.append("Scroll hint did not switch to profile navigation when game controls became visible")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT.path_join("student_setup_compact_bottom_875x500.png")))
	print("STUDENT_COMPACT grid=", grid.columns, " initial_cue=SCROLL DOWN", " after_scroll=", scroll.scroll_vertical, " focused=", get_focus_owner_name())
	setup.queue_free()
	await process_frame
	if issues.is_empty():
		print("PASS physical 875px Student Setup stacking, scroll cue and game navigation")
		quit(0)
	else:
		for issue in issues:
			push_error(issue)
		quit(1)


func get_focus_owner_name() -> String:
	var owner := root.gui_get_focus_owner()
	return owner.name if owner != null else "NONE"
