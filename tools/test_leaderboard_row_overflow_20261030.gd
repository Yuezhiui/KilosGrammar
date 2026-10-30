extends SceneTree

## Native GPU leaderboard layout stress using only in-memory fictional records.
## This fixture never opens or modifies the local PostgreSQL database.
const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const CELLS := ["StudentId", "StudentName", "Grade", "GameStyle", "GameMode", "Difficulty", "Score"]
const CAPTURE_DIR := "res://showcase/qa_leaderboard_overflow_20261030"
const DEMO_ID := "DEMO-KG-20261030-C"
var checks := 0
var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var records := _records()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	for resolution in SIZES:
		root.size = resolution
		root.content_scale_size = resolution
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
		var leaderboard := BOARD.instantiate() as Control
		root.add_child(leaderboard)
		leaderboard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		leaderboard.set_context({"database_connected": true, "leaderboard_rows": records})
		await process_frame
		var scroll := leaderboard.get_node("%ScoreRowsScroll") as ScrollContainer
		var rows := leaderboard.get_node("%ScoreRows") as VBoxContainer
		_check(rows.get_child_count() == records.size(), "%s all 54 fictional rows render" % resolution)
		_check(scroll.visible, "%s list shows when records exist" % resolution)
		if rows.get_child_count() != records.size():
			leaderboard.queue_free()
			await process_frame
			continue
		for i in [0, 1, 2, 20, 53]:
			var row := rows.get_child(i) as Control
			var previous_end := -100.0
			for column in range(CELLS.size()):
				var cell := row.get_node(CELLS[column]) as Label
				_check(cell != null and cell.clip_text and cell.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
					"%s row %d %s bounded with ellipsis" % [resolution, i, CELLS[column]])
				if cell == null:
					continue
				_check(cell.position.x >= previous_end + 4.0,
					"%s row %d %s does not intersect previous column" % [resolution, i, CELLS[column]])
				previous_end = cell.position.x + cell.size.x
				_check(not cell.tooltip_text.is_empty(),
					"%s row %d %s has complete-value hover help" % [resolution, i, CELLS[column]])
		var first := rows.get_child(0) as Control
		var long_id := first.get_node("StudentId") as Label
		var first_grade := first.get_node("Grade") as Label
		_check(long_id.tooltip_text == "DEMO-KG-20261030-EXTRA-LONG-123456789",
			"%s long ID retains full exact value" % resolution)
		_check(first_grade.tooltip_text == "GRADE 6 - SAMPAGUITA SECTION A",
			"%s long grade retains full exact value" % resolution)
		_check(first_grade.position.x < 359.0, "%s grade editor position moved left" % resolution)
		var second := rows.get_child(1) as Control
		var ordinary_id := second.get_node("StudentId") as Label
		_check(ordinary_id.tooltip_text == DEMO_ID,
			"%s ordinary identifier is complete" % resolution)
		_check(ordinary_id.text.replace("\n", "") == DEMO_ID,
			"%s typical longer identifier is fully printed across two lines" % resolution)
		var available_width := ordinary_id.size.x - 6.0
		var font := ordinary_id.get_theme_font("font")
		var font_size := ordinary_id.get_theme_font_size("font_size")
		var widest_line := 0.0
		for line in ordinary_id.text.split("\n"):
			widest_line = maxf(widest_line, font.get_string_size(line,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
		_check(widest_line <= available_width,
			"%s full ID fits with no clipping" % resolution)
		_check(font_size >= 12, "%s ID remains legible at 12pt or larger" % resolution)
		await _capture("top", resolution)
		var bar := scroll.get_v_scroll_bar()
		_check(bar.max_value > bar.page, "%s vertical scrollbar reaches additional records" % resolution)
		scroll.scroll_vertical = 400
		await process_frame
		_check(scroll.scroll_vertical > 0, "%s scrolling advances through long list" % resolution)
		await _capture("scrolled", resolution)
		leaderboard.queue_free()
		await process_frame
	print("LEADERBOARD OVERFLOW QA: %s checks=%d failures=%d" % [
		"PASS" if errors.is_empty() else "FAIL", checks, errors.size()])
	quit(0 if errors.is_empty() else 1)


func _records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in range(54):
		var student_id := "KG-DEMO-%04d" % (i + 1)
		var student_name := "Demo Learner %02d" % (i + 1)
		var grade := "Grade %d - Section A" % ((i % 6) + 1)
		if i == 0:
			student_id = "DEMO-KG-20261030-EXTRA-LONG-123456789"
			student_name = "Demo Learner With A Particularly Long Name"
			grade = "GRADE 6 - SAMPAGUITA SECTION A"
		elif i == 1:
			student_id = DEMO_ID
			student_name = "Demo Learner Charlie"
			grade = "GRADE 5 - DEMO"
		result.append({"student_id": student_id, "student_name": student_name,
			"grade": grade, "minigame": ["Catch the Word", "Balloon Popping", "Human Plane"][i % 3],
			"game_style": ["Noun", "Verb", "Pronoun", "Adjective"][i % 4],
			"game_mode": "Seconds" if i % 2 == 0 else "Lives",
			"difficulty": ["Easy", "Normal", "Hard"][i % 3], "score": 9999 - i * 100})
	return result


func _capture(label: String, resolution: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image_data := root.get_texture().get_image()
	var file := "%s/%s_%dx%d.png" % [CAPTURE_DIR, label, resolution.x, resolution.y]
	_check(image_data != null and not image_data.is_empty() and image_data.save_png(file) == OK,
		"%s %s native GPU capture" % [resolution, label])


func _check(ok: bool, context: String) -> void:
	checks += 1
	if not ok:
		errors.append(context)
		printerr("LEADERBOARD OVERFLOW FAIL: " + context)
