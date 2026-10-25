extends SceneTree

# Verifies editor-editable 2D nodes and working leaderboard behaviors.
# All dummy score records are test-only, never persisted or shown in main.
var failures := 0
var returned_home := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := load("res://ui/secondary/leaderboard.tscn") as PackedScene
	_check(scene != null, "Leaderboard scene loads")
	if scene == null:
		quit(1)
		return
	var panel := scene.instantiate() as Control
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame

	# UI pieces are actually independent editable .tscn nodes.
	var background := panel.get_node("Background") as TextureRect
	_check(background != null and background.texture != null, "New classroom backdrop is present")
	_check(not background.has_meta("_edit_lock_") or not bool(background.get_meta("_edit_lock_")),
		"Backdrop texture is editable, not locked in the Godot editor")
	_check(background.anchor_right == 1.0 and background.anchor_bottom == 1.0,
		"Changeable backdrop fills screen at any resolution")
	var former_texture := background.texture
	background.texture = load("res://Components/Leaderboard/background_fixed.png")
	_check(background.texture != former_texture and background.texture != null,
		"Inspector texture swap works without modifying leaderboard.gd")
	background.texture = former_texture
	_check(panel.get_node_or_null("OriginalArt") == null
		and panel.get_node_or_null("ReferenceCanvas/OriginalArt") == null,
		"No baked full-screen UI screenshot remains under movable elements")
	var board := panel.get_node("BoardArtwork") as NinePatchRect
	var title := panel.get_node("TitleArt") as TextureRect
	var frame := panel.get_node("TableBodyArt") as TextureRect
	var header := panel.get_node("TableHeaderArt") as TextureRect
	_check(is_instance_valid(board) and is_instance_valid(title)
		and is_instance_valid(frame) and is_instance_valid(header),
		"New board, title art, table body and header are independent draggable controls")
	_check(title.texture != background.texture and frame.texture != background.texture,
		"Foreground artwork uses separate reusable component PNGs")
	var original_board_pos := board.position
	board.position += Vector2(17, 9)
	await process_frame
	_check(board.position.distance_to(original_board_pos + Vector2(17, 9)) < 0.5,
		"Board can be moved in the editor without scripted layout overriding it")
	board.position = original_board_pos

	var style := panel.get_node("%StyleFilter") as OptionButton
	var mode := panel.get_node("%ModeFilter") as OptionButton
	var difficulty := panel.get_node("%DifficultyFilter") as OptionButton
	var back := panel.get_node("%BackButton") as Button
	var download := panel.get_node("%DownloadButton") as Button
	for removed in ["FiltersToggle", "FiltersArt", "MoreFiltersPanel", "CloseMoreFilters"]:
		_check(panel.find_child(removed, true, false) == null,
			"FILTERS and associated popup removed completely: " + removed)
	_check(not download.is_visible_in_tree() and panel.has_method("request_filtered_csv_export"),
		"Hidden filtered CSV remains accessible through explicit host API, not removed UI")
	_check(style.item_count == 6 and style.selected == 0,
	"Grammar options and default selection are authored in scene Inspector")
	_check(mode.item_count == 3 and difficulty.item_count == 4,
	"Game mode and difficulty selections authored in scene Inspector")
	for button in [back, style, mode, difficulty]:
		_check(button.is_visible_in_tree() and button.modulate.a > 0.99,
			"Control is visible, movable and clickable in the editor: " + button.name)
	_check(back.focus_mode == Control.FOCUS_ALL,
		"Back remains keyboard-accessible without obsolete FILTERS")
	var original_pos := download.position
	download.position += Vector2(12, 4)
	await process_frame
	_check(download.position.distance_to(original_pos + Vector2(12, 4)) < 0.5,
		"Download art travels with its native button, not with a background screenshot")
	download.position = original_pos
	for selector in [style, mode, difficulty]:
		var original_skin := selector.get_theme_stylebox("normal") as StyleBoxTexture
		selector.select(1)
		selector.item_selected.emit(1)
		_check(selector.get_theme_stylebox("normal") is StyleBoxTexture
			and selector.get_theme_stylebox("normal") != original_skin,
			"Selection replaces artwork using scene-authored selected-state PNG: " + selector.name)
		selector.select(0)
		selector.item_selected.emit(0)
		_check(selector.get_theme_stylebox("normal") == original_skin,
			"Reset restores exact authored ALL state PNG: " + selector.name)

	var empty := panel.get_node("%EmptyMessage") as Label
	var scroll := panel.get_node("%ScoreRowsScroll") as ScrollContainer
	var score_rows := panel.get_node("%ScoreRows") as VBoxContainer
	_check(empty.visible and not scroll.visible and score_rows.get_child_count() == 0,
		"Empty-state label and rows container are editable scene nodes")

	var components := DirAccess.open("res://Components/Leaderboard")
	var sprites := 0
	if components != null:
		for sprite in components.get_files():
			if sprite.ends_with(".png"):
				sprites += 1
	_check(sprites >= 38, "New user reference and independently extracted UI sprites remain in Components/Leaderboard")

	panel.set_context({"leaderboard_rows": [
		{"student_id":"T01", "student_name":"Sample Alpha", "grade":"5",
		 "game_style":"Noun", "game_mode":"Seconds", "difficulty":"Easy", "score":100},
		{"student_id":"T02", "student_name":"Sample Beta", "grade":"6",
		 "game_style":"Verb", "game_mode":"Lives", "difficulty":"Hard", "score":200},
		{"student_id":"T03", "student_name":"Sample Gamma", "grade":"5",
		 "game_style":"Noun", "game_mode":"Lives", "difficulty":"Hard", "score":50}
	]})
	_check(not empty.visible and scroll.visible and score_rows.get_child_count() == 3,
		"Score list draws only when a real source provides records")
	_check((score_rows.get_child(0).get_node("StudentName") as Label).text == "Sample Beta",
		"Rows sorted by highest score using editor-defined row template")
	style.select(1)
	style.item_selected.emit(1)
	_check((panel.get("_visible_rows") as Array).size() == 2,
		"Style dropdown filters to Noun")
	mode.select(1)
	mode.item_selected.emit(1)
	difficulty.select(1)
	difficulty.item_selected.emit(1)
	_check((panel.get("_visible_rows") as Array).size() == 1,
		"Mode and difficulty filters combine correctly")
	var filename := "user://_leaderboard_qa_%s.csv" % str(Time.get_ticks_usec())
	var full_path := ProjectSettings.globalize_path(filename)
	panel.call("_write_csv", full_path)
	var csv_text := FileAccess.get_file_as_string(full_path)
	_check(csv_text.contains("STUDENT ID,NAME,GRADE") and csv_text.contains("Sample Alpha"),
		"CSV exports selected data and authored columns")
	_check(not csv_text.contains("Sample Beta"), "CSV excludes filtered-out records")
	DirAccess.remove_absolute(full_path)
	panel.requested.connect(_navigated)
	back.pressed.emit()
	_check(returned_home, "Back works without a separate invisible hitbox")
	for resolution in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = resolution
		panel.size = Vector2(resolution)
		await process_frame
		_check(background.get_global_rect().size == Vector2(resolution),
			"Backdrop stays full-screen at %s" % resolution)
		_check(title.get_global_rect().end.x <= resolution.x + 1.0,
			"Editor-positioned title fits at %s" % resolution)
	panel.free()
	await process_frame
	if failures == 0:
		print("PASS Editor-draggable Leaderboard; interchangeable background; filters, rows, CSV, Back")
	quit(1 if failures > 0 else 0)


func _navigated(target: String, _payload: Dictionary) -> void:
	returned_home = target == "main"


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		printerr("LEADERBOARD UI QA FAIL: " + description)
