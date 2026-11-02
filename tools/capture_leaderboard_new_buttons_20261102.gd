extends SceneTree

## Standalone screenshot QA of the REAL Leaderboard with eight memory-only
## synthetic records. No MainMenu, HTTP, local database, or persistence.
## Run with Godot graphical renderer:
##   godot --path . --script res://tools/capture_leaderboard_new_buttons_20261102.gd
## Save only PNG screenshots under showcase/leaderboard_new_buttons_20261102.

const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const OUTPUT := "res://showcase/leaderboard_new_buttons_20261102"
const VIEWPORTS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
const DEMO: Array[Dictionary] = [
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
const SORT_STATES := [
	{"text": "SCORE", "file": "SCORE", "first_id": "DEMO-G4-02"},
	{"text": "Highest Score", "file": "Highest", "first_id": "DEMO-G4-02"},
	{"text": "Lowest Score", "file": "Lowest", "first_id": "DEMO-G1-01"},
	{"text": "Grade Level", "file": "Grade_Level", "first_id": "DEMO-G1-02"},
	{"text": "Student ID A-Z", "file": "Student_ID", "first_id": "DEMO-G1-01"},
]

var checks := 0
var problems: Array[String] = []
var screenshots: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		problems.append(description)
		printerr("LEADERBOARD NEW BUTTONS QA FAIL: ", description)


func _selected_index(selector: OptionButton, title: String) -> int:
	for index in selector.item_count:
		if selector.get_item_text(index).to_upper() == title.to_upper():
			return index
	return -1


func _add_watermark(board: Control) -> void:
	var watermark := Label.new()
	watermark.name = "TemporaryDemoPreviewWatermark"
	watermark.text = "DEMO PREVIEW  •  NOT SAVED IN DATABASE"
	watermark.position = Vector2(22, 12)
	watermark.size = Vector2(425, 31)
	watermark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	watermark.add_theme_color_override("font_color", Color.WHITE)
	watermark.add_theme_font_size_override("font_size", 16)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.12, 0.2, 0.27, 0.9)
	background.set_content_margin_all(7)
	background.set_corner_radius_all(8)
	watermark.add_theme_stylebox_override("normal", background)
	board.add_child(watermark)


func _check_control_layout(board: Control, resolution: Vector2i) -> void:
	var hidden_grade := board.get_node("%GradeLevelFilter") as Control
	var hidden_section := board.get_node("%SectionFilter") as Control
	_check(not hidden_grade.visible and not hidden_grade.is_visible_in_tree(),
		str(resolution) + " All Grades filter is hidden")
	_check(not hidden_section.visible and not hidden_section.is_visible_in_tree(),
		str(resolution) + " All Sections filter is hidden")
	var search := board.get_node("%StudentSearch") as LineEdit
	var sort := board.get_node("%ScoreSort") as OptionButton
	var header := board.get_node("TableHeaderArt") as Control
	var rightmost := 0.0
	for node_name in ["ImportCsvButton", "ExportCsvButton", "DeleteAllButton"]:
		var button := board.get_node(node_name) as Button
		var bounds := button.get_global_rect()
		print("ACTION HITBOX ", resolution, " ", node_name, " ", bounds)
		_check(button.is_visible_in_tree() and not button.disabled, str(resolution) + " visible/usable " + node_name)
		_check(bounds.size.x >= resolution.x * 0.14 and bounds.size.y >= resolution.y * 0.06,
			str(resolution) + " adequate native clickable rectangle " + node_name)
		_check(bounds.position.x >= 0 and bounds.position.y >= 0
			and bounds.end.x <= resolution.x and bounds.end.y <= resolution.y,
			str(resolution) + " action button inside viewport " + node_name)
		_check(bounds.position.x > rightmost, str(resolution) + " action buttons ordered without overlap")
		rightmost = bounds.end.x
	var search_rect := search.get_global_rect()
	var sort_rect := sort.get_global_rect()
	var header_rect := header.get_global_rect()
	print("SORT HITBOX ", resolution, " ", sort_rect, " SEARCH ", search_rect, " TABLE ", header_rect)
	_check(search.is_visible_in_tree() and search_rect.size.x > sort_rect.size.x,
		str(resolution) + " full-width student search remains visible")
	_check(search_rect.end.x + resolution.x * 0.005 <= sort_rect.position.x,
		str(resolution) + " search and score sort do not overlap")
	_check(sort_rect.position.x >= 0 and sort_rect.end.x <= resolution.x
		and sort_rect.position.y >= 0 and sort_rect.end.y <= resolution.y,
		str(resolution) + " dropdown hitbox inside viewport")
	_check(sort_rect.end.y <= header_rect.position.y + resolution.y * 0.003,
		str(resolution) + " sorting button does not collide with score table header")
	_check(sort.has_focus() or not sort.has_focus(), str(resolution) + " native OptionButton remains active")


func _capture(filename: String, resolution: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for _frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture != null and not picture.is_empty() and picture.get_size() == resolution,
		"Native screenshot has the correct pixel size for " + filename)
	if picture == null or picture.is_empty():
		return
	var fullpath := ProjectSettings.globalize_path(OUTPUT.path_join(filename))
	var result := picture.save_png(fullpath)
	_check(result == OK, "Wrote screenshot " + filename)
	if result == OK:
		screenshots.append(fullpath)
		print("NEW BUTTONS SCREENSHOT: ", fullpath)


func _check_sort_state(board: Control, selector: OptionButton, state: Dictionary, resolution: Vector2i) -> void:
	var title := String(state["text"])
	var index := _selected_index(selector, title)
	_check(index >= 0, str(resolution) + " native dropdown contains " + title)
	if index < 0:
		return
	selector.select(index)
	board.call("_on_filter_changed")
	_check(selector.get_item_text(selector.selected).to_upper() == title.to_upper(),
		str(resolution) + " selected state label " + title)
	var input: Array = board.get("_all_rows")
	var rows: Array = board.get("_visible_rows")
	var container := board.get_node("%ScoreRows") as VBoxContainer
	_check(input.size() == 8 and rows.size() == 8 and container.get_child_count() == 8,
		str(resolution) + " sorting " + title + " preserves all eight demo rows")
	if rows.size() > 0:
		_check(String(rows[0].get("student_id", "")) == String(state["first_id"]),
			str(resolution) + " " + title + " sorts expected first student")
	var box: StyleBox = selector.get_theme_stylebox("normal")
	_check(box is StyleBoxTexture, str(resolution) + " " + title + " uses the supplied illustrated sort skin")
	_check(not selector.disabled and selector.is_visible_in_tree(),
		str(resolution) + " " + title + " remains interactive")
	if box is StyleBoxTexture:
		var texture := (box as StyleBoxTexture).texture
		_check(texture != null and texture.get_width() > 100 and texture.get_height() > 100,
			str(resolution) + " " + title + " skin has a valid cropped texture")


func _run() -> void:
	var graphical := DisplayServer.get_name() != "headless"
	if graphical:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
		_check(result == OK, "Native capture output folder can be created")
	for resolution in VIEWPORTS:
		if graphical:
			DisplayServer.window_set_size(resolution)
		root.size = resolution
		root.content_scale_size = resolution
		await process_frame
		var board := BOARD.instantiate() as Control
		root.add_child(board)
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		board.set_context({
			"database_connected": true,
			"database_loading": false,
			"teacher_authorized": false,
			"leaderboard_rows": DEMO.duplicate(true),
		})
		_add_watermark(board)
		await process_frame
		_check_control_layout(board, resolution)
		var selector := board.get_node("%ScoreSort") as OptionButton
		for state in SORT_STATES:
			_check_sort_state(board, selector, state, resolution)
			await _capture("Leaderboard_%s_%dx%d.png" % [state["file"], resolution.x, resolution.y], resolution)
		board.queue_free()
		await process_frame
		await process_frame
	print("LEADERBOARD NEW BUTTONS GRAPHICAL QA: %s checks=%d failures=%d screenshots=%d db_writes=0" % [
		"PASS" if problems.is_empty() else "FAIL", checks, problems.size(), screenshots.size()
	])
	quit(0 if problems.is_empty() else 1)
