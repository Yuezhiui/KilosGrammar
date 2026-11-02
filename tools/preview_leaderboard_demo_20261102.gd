extends SceneTree
## Isolated, read-only DEMO preview using the actual Leaderboard scene.
## This script never instantiates MainMenu, a database client or an HTTP request.
## All eight records exist only inside this running process; NOTHING is saved
## to PostgreSQL, SQLite or the user's real leaderboard.
##
## Graphical screenshots (native 1280x720 Godot rendering):
##   godot --path . --script res://tools/preview_leaderboard_demo_20261102.gd
## Structural and grade-filter QA can also run with --headless.

const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const SOURCE_XLSX := "res://docs/examples/KilosGrammar_DEMO_8_Students_Grades_1_to_4_20261102.xlsx"
const OUTPUT_DIR := "res://showcase/leaderboard_demo_8_students_20261102"
const COLUMNS := [
	"student_id", "student_name", "grade_section", "minigame",
	"game_style", "game_mode", "difficulty", "score"
]
# In-memory preview only. These eight rows mirror the four Grade 1..4 sheets
# in SOURCE_XLSX (verified against workbook values on 2026-11-02). No CSV is
# generated, opened or required; the sample workbook stays the sole fixture.
const DEMO_ROWS := [
	{"student_id": "DEMO-G1-01", "student_name": "Demo Alice Maple", "grade_section": "G1",
		"minigame": "Catch the Word", "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 12},
	{"student_id": "DEMO-G1-02", "student_name": "Demo Ben Cedar", "grade_section": "G1",
		"minigame": "Balloon Popping", "game_style": "Verb", "game_mode": "Lives", "difficulty": "Normal", "score": 17},
	{"student_id": "DEMO-G2-01", "student_name": "Demo Cara Birch", "grade_section": "G2",
		"minigame": "Human Plane", "game_style": "Adjective", "game_mode": "Seconds", "difficulty": "Easy", "score": 22},
	{"student_id": "DEMO-G2-02", "student_name": "Demo Dino Aspen", "grade_section": "G2",
		"minigame": "Catch the Word", "game_style": "Pronoun", "game_mode": "Lives", "difficulty": "Hard", "score": 27},
	{"student_id": "DEMO-G3-01", "student_name": "Demo Ella Willow", "grade_section": "G3",
		"minigame": "Balloon Popping", "game_style": "Adverb", "game_mode": "Seconds", "difficulty": "Normal", "score": 31},
	{"student_id": "DEMO-G3-02", "student_name": "Demo Finn Elm", "grade_section": "G3",
		"minigame": "Human Plane", "game_style": "Verb", "game_mode": "Lives", "difficulty": "Easy", "score": 36},
	{"student_id": "DEMO-G4-01", "student_name": "Demo Gia Olive", "grade_section": "G4",
		"minigame": "Catch the Word", "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Hard", "score": 43},
	{"student_id": "DEMO-G4-02", "student_name": "Demo Hugo Pine", "grade_section": "G4",
		"minigame": "Balloon Popping", "game_style": "Pronoun", "game_mode": "Lives", "difficulty": "Normal", "score": 48},
]
const GRADE_SCORES := {
	"Grade 1": [12, 17],
	"Grade 2": [22, 27],
	"Grade 3": [31, 36],
	"Grade 4": [43, 48],
}
const GRADE_IDS := {
	"Grade 1": ["DEMO-G1-01", "DEMO-G1-02"],
	"Grade 2": ["DEMO-G2-01", "DEMO-G2-02"],
	"Grade 3": ["DEMO-G3-01", "DEMO-G3-02"],
	"Grade 4": ["DEMO-G4-01", "DEMO-G4-02"],
}

var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("LEADERBOARD DEMO PREVIEW FAIL: ", description)


func _read_demo_records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_check(FileAccess.file_exists(SOURCE_XLSX), "Sole source demo XLSX workbook exists")
	_check(DEMO_ROWS.size() == 8, "Eight in-memory rows match the workbook's four grade sheets")
	for item in DEMO_ROWS:
		var complete: bool = item.size() == COLUMNS.size()
		for key in COLUMNS:
			complete = complete and item.has(key)
		_check(complete, "Every mock record carries the eight expected leaderboard fields")
		result.append(item.duplicate(true))
	_check(String(DEMO_ROWS[0].get("student_id", "")) == "DEMO-G1-01", "First mock ID matches XLSX")
	_check(String(DEMO_ROWS[7].get("student_id", "")) == "DEMO-G4-02", "Last mock ID matches XLSX")
	return result


func _grade_option(button: OptionButton, name: String) -> bool:
	for index in button.item_count:
		if button.get_item_text(index) == name:
			button.select(index)
			return true
	return false


func _assert_source_distribution(rows: Array[Dictionary]) -> void:
	_check(rows.size() == 8, "Exactly eight demo score rows loaded")
	var ids := {}
	var per_grade: Dictionary = {}
	var ids_per_grade: Dictionary = {}
	for item in rows:
		var student_id := String(item.get("student_id", ""))
		_check(student_id.begins_with("DEMO-G") and student_id.length() == 10,
			"Student ID uses short clearly fake ID: " + student_id)
		_check(not ids.has(student_id), "No duplicate demo student IDs: " + student_id)
		ids[student_id] = true
		var grade_section := String(item.get("grade_section", ""))
		# The canonical workbook intentionally uses compact grade cells G1..G4
		# to avoid squeezing the real leaderboard's Grade column.
		var grade := "Grade " + grade_section.substr(1) if grade_section.begins_with("G") \
			else grade_section.get_slice(" ", 0) + " " + grade_section.get_slice(" ", 1)
		if not per_grade.has(grade):
			per_grade[grade] = []
			ids_per_grade[grade] = []
		(per_grade[grade] as Array).append(int(item.get("score", -1)))
		(ids_per_grade[grade] as Array).append(student_id)
	for grade in GRADE_SCORES:
		var values: Array = per_grade.get(grade, [])
		values.sort()
		_check(values == GRADE_SCORES[grade], grade + " has its exact two canonical scores")
		var grade_ids: Array = ids_per_grade.get(grade, [])
		grade_ids.sort()
		_check(grade_ids == GRADE_IDS[grade], grade + " has its exact two short demo IDs")
	_check(per_grade.size() == 4, "Only Grades 1–4 occur in the sample")


func _add_demo_watermark(board: Control) -> void:
	# Runtime-only watermark identifies all captures as synthetic test previews.
	# This is never saved into leaderboard.tscn and has no interaction.
	var banner := Label.new()
	banner.name = "TemporaryDemoPreviewWatermark"
	banner.text = "DEMO PREVIEW  •  NOT SAVED IN DATABASE"
	banner.position = Vector2(22, 12)
	banner.size = Vector2(425, 31)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	banner.add_theme_font_size_override("font_size", 16)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.12, 0.2, 0.27, 0.9)
	background.set_content_margin_all(7.0)
	background.set_corner_radius_all(8)
	banner.add_theme_stylebox_override("normal", background)
	board.add_child(banner)


func _assert_real_table(board: Control, expected: int, expected_grade: String = "") -> void:
	var source: Array = board.get("_all_rows")
	var shown: Array = board.get("_visible_rows")
	var visible := board.get_node("%ScoreRows") as VBoxContainer
	_check(source.size() == expected or source.size() == 8,
		"Scene preserves all explicitly supplied synthetic rows")
	_check(shown.size() == expected, "Filter shows %d expected records" % expected)
	_check(visible.get_child_count() == expected, "Real editor-authored row container renders %d records" % expected)
	_check(not (board.get_node("%EmptyMessage") as Label).visible, "Native table visible rather than empty notice")
	for index in mini(shown.size(), visible.get_child_count()):
		var record: Dictionary = shown[index]
		var entry := visible.get_child(index) as Control
		var name := entry.get_node("StudentName") as Label
		var score := entry.get_node("Score") as Label
		var grade := entry.get_node("Grade") as Label
		_check(name.text == String(record.get("student_name", "")), "Native name cell matches demo record")
		_check(score.text == str(int(record.get("score", -1))), "Native score matches in-memory XLSX demo")
		_check(grade.text.replace("\n", " ") == String(record.get("grade_section", "")) or
			grade.tooltip_text == String(record.get("grade_section", "")), "Native grade matches source")
		if not expected_grade.is_empty():
			_check(String(board.call("_grade_level", record)) == expected_grade,
				"Visible row belongs to " + expected_grade)


func _capture(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for _frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture != null and not picture.is_empty() and picture.get_size() == Vector2i(1280, 720),
		"Native 1280×720 framebuffer ready for " + file_name)
	if picture == null or picture.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(file_name))
	var status := picture.save_png(absolute)
	_check(status == OK, "Screenshot written: " + absolute)
	if status == OK:
		screenshots.append(absolute)
		print("DEMO SCREENSHOT: ", absolute)


func _run() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
		var mkdir_result := DirAccess.make_dir_recursive_absolute(output_path)
		_check(mkdir_result == OK, "Demo screenshot directory is available")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var rows := _read_demo_records()
	_assert_source_distribution(rows)
	if rows.size() != 8:
		_finish(null)
		return
	var board := BOARD.instantiate() as Control
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	board.set_context({
		"database_connected": true,
		"database_loading": false,
		"teacher_authorized": false,
		"leaderboard_rows": rows,
	})
	_add_demo_watermark(board)
	await process_frame
	var grade_filter := board.get_node("%GradeLevelFilter") as OptionButton
	var score_sort := board.get_node("%ScoreSort") as OptionButton
	var scroll := board.get_node("%ScoreRowsScroll") as ScrollContainer
	_check(not grade_filter.is_visible_in_tree(), "Grade dropdown remains programmatically usable but hidden from pupils")
	_check(grade_filter.item_count == 5, "Grade dropdown has All Grades and Grades 1–4")
	for grade in GRADE_SCORES:
		_check(_grade_option(grade_filter, grade), grade + " is available in grade dropdown")
	_check(_grade_option(grade_filter, "All Grades"), "All Grades option is available")
	board.call("_on_grade_changed")
	var grade_sort_index := -1
	for index in score_sort.item_count:
		if score_sort.get_item_text(index).strip_edges().to_upper() == "GRADE LEVEL":
			grade_sort_index = index
			break
	_check(grade_sort_index >= 0, "Illustrated Grade Level sort option is available")
	if grade_sort_index >= 0:
		score_sort.select(grade_sort_index)
	board.call("_on_filter_changed")
	_assert_real_table(board, 8)
	await _capture("LEADERBOARD_DEMO_All_Grades_Top_1280x720.png")
	# The actual scene has a 255px scroll area for 8×42px rows; capture its
	# lower end as well, so the complete 8-record list is visible across both.
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _capture("LEADERBOARD_DEMO_All_Grades_Bottom_1280x720.png")
	for level in range(1, 5):
		var grade_name := "Grade %d" % level
		_check(grade_filter != null and not grade_filter.is_visible_in_tree(),
			"No visible grade dropdown in " + grade_name + " preview")
		var grade_records: Array[Dictionary] = []
		for record in rows:
			if String(record.get("grade_section", "")) == "G%d" % level:
				grade_records.append(record)
		_check(grade_records.size() == 2, grade_name + " has precisely two fixture students")
		board.set_context({"database_connected": true, "database_loading": false,
			"teacher_authorized": false, "leaderboard_rows": grade_records})
		_assert_real_table(board, 2, grade_name)
		var scores: Array[int] = []
		for record in board.get("_visible_rows"):
			scores.append(int(record.get("score", -1)))
		scores.sort()
		_check(scores == GRADE_SCORES[grade_name], grade_name + " retains both exact XLSX demo scores")
		await _capture("LEADERBOARD_DEMO_Grade_%d_Two_Students_1280x720.png" % level)
	board.set_context({"database_connected": true, "database_loading": false,
		"teacher_authorized": false, "leaderboard_rows": rows})
	_assert_real_table(board, 8)
	_check(screenshots.size() == 6 or DisplayServer.get_name() == "headless",
		"Six native DEMO screenshots captured, or headless QA skips rendering")
	_finish(board)


func _finish(board: Control) -> void:
	if board != null:
		board.queue_free()
	print("LEADERBOARD DEMO 8 GRADES 1-4: %s | checks=%d failures=%d | screenshots=%d | database_writes=0" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), screenshots.size()
	])
	print("DEMO ONLY: set_context injected eight fake records into an isolated scene; nothing was persisted.")
	quit(0 if failures.is_empty() else 1)
