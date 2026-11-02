extends SceneTree

## Graphical preview of the real editor-authored Leaderboard with its four
## shared-texture OptionButtons. All student rows are temporary mock records.
## No MainMenu, backend, HTTP requests, saved CSV or real database operations.
## godot --path . --script res://tools/capture_leaderboard_shared_dropdown_20261102.gd

const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const DROPDOWN_SOURCE := "res://Components/Leaderboard/SharedDropdown20261102/dropdown_base.png"
const OUTPUT := "res://showcase/leaderboard_shared_dropdown_20261102"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const SELECTOR_NAMES := ["StyleFilter", "ModeFilter", "DifficultyFilter", "ScoreSort"]
const LONG_SELECTED := ["ADJECTIVE", "SECONDS", "ALL DIFFICULTIES", "Student Name A-Z"]
const ROWS := [
	{"student_id":"DEMO-G1-01","student_name":"Demo Alice Maple","grade_section":"G1","minigame":"Catch the Word","game_style":"Noun","game_mode":"Seconds","difficulty":"Easy","score":12},
	{"student_id":"DEMO-G1-02","student_name":"Demo Ben Cedar","grade_section":"G1","minigame":"Balloon Popping","game_style":"Verb","game_mode":"Lives","difficulty":"Normal","score":17},
	{"student_id":"DEMO-G2-01","student_name":"Demo Cara Birch","grade_section":"G2","minigame":"Human Plane","game_style":"Adjective","game_mode":"Seconds","difficulty":"Easy","score":22},
	{"student_id":"DEMO-G2-02","student_name":"Demo Dino Aspen","grade_section":"G2","minigame":"Catch the Word","game_style":"Pronoun","game_mode":"Lives","difficulty":"Hard","score":27},
	{"student_id":"DEMO-G3-01","student_name":"Demo Ella Willow","grade_section":"G3","minigame":"Balloon Popping","game_style":"Adverb","game_mode":"Seconds","difficulty":"Normal","score":31},
	{"student_id":"DEMO-G3-02","student_name":"Demo Finn Elm","grade_section":"G3","minigame":"Human Plane","game_style":"Verb","game_mode":"Lives","difficulty":"Easy","score":36},
	{"student_id":"DEMO-G4-01","student_name":"Demo Gia Olive","grade_section":"G4","minigame":"Catch the Word","game_style":"Noun","game_mode":"Seconds","difficulty":"Hard","score":43},
	{"student_id":"DEMO-G4-02","student_name":"Demo Hugo Pine","grade_section":"G4","minigame":"Balloon Popping","game_style":"Pronoun","game_mode":"Lives","difficulty":"Normal","score":48},
]

var checks := 0
var failures: Array[String] = []
var screenshots: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("SHARED DROPDOWN QA FAIL: ", description)


func _source(style: StyleBoxTexture) -> String:
	if style == null or style.texture == null:
		return ""
	var texture := style.texture
	if texture is AtlasTexture:
		return (texture as AtlasTexture).atlas.resource_path
	return texture.resource_path


func _add_preview_mark(board: Control) -> void:
	var label := Label.new()
	label.name = "TemporaryDemoPreviewWatermark"
	label.text = "DEMO PREVIEW  •  NOT SAVED IN DATABASE"
	label.position = Vector2(22, 12)
	label.size = Vector2(425, 31)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 16)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.12, 0.2, 0.27, 0.9)
	background.set_content_margin_all(7)
	background.set_corner_radius_all(8)
	label.add_theme_stylebox_override("normal", background)
	board.add_child(label)


func _verify_four(board: Control, size: Vector2i, stage: String) -> void:
	var previous_right := -1.0
	for name in SELECTOR_NAMES:
		var selector := board.get_node("%" + name) as OptionButton
		var style := selector.get_theme_stylebox("normal") as StyleBoxTexture
		var bounds := selector.get_global_rect()
		var source := _source(style)
		var selected := selector.get_item_text(selector.selected)
		print("SHARED DROPDOWN RECT ", stage, " ", size, " ", name, " ", bounds, " selected=", selected)
		_check(selector.is_visible_in_tree() and not selector.disabled and selector.focus_mode == Control.FOCUS_ALL,
			"%s %s real interactive native selector" % [stage, name])
		_check(source == DROPDOWN_SOURCE, "%s %s renders the ONE shared dropdown PNG" % [stage, name])
		_check(selector.get_theme_color("font_color").a > 0.95,
			"%s %s renders native font caption (not baked PNG letters)" % [stage, name])
		_check(selector.text == selected.to_upper(),
			"%s %s selected native caption reflects real item" % [stage, name])
		_check(bounds.position.x > previous_right and bounds.position.y >= 0 and bounds.end.x <= size.x
			and bounds.end.y <= size.y, "%s %s nonoverlapping viewport hitbox" % [stage, name])
		_check(bounds.size.x >= size.x * 0.17 and bounds.size.y >= size.y * 0.06,
			"%s %s has a usable hitbox" % [stage, name])
		previous_right = bounds.end.x
	_check(not (board.get_node("%GradeLevelFilter") as Control).is_visible_in_tree()
		and not (board.get_node("%SectionFilter") as Control).is_visible_in_tree(),
		"%s hidden All Grades and All Sections controls remain invisible" % stage)
	var rows: Array = board.get("_visible_rows")
	_check(rows.size() >= 1 and rows.size() <= 8, "%s mock score rows render without DB" % stage)


func _select_named(button: OptionButton, title: String) -> bool:
	for index in button.item_count:
		if button.get_item_text(index).to_upper() == title.to_upper():
			button.select(index)
			button.item_selected.emit(index)
			return true
	return false


func _screenshot(name: String, size: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for _frame in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(not picture.is_empty() and picture.get_size() == size,
		"%s native screenshot pixel dimensions match requested viewport" % name)
	if picture.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(OUTPUT.path_join(name))
	var result := picture.save_png(absolute)
	_check(result == OK, "%s screenshot persisted to preview showcase" % name)
	if result == OK:
		screenshots.append(absolute)
		print("SHARED DROPDOWN SCREENSHOT: ", absolute)


func _run() -> void:
	var graphical := DisplayServer.get_name() != "headless"
	if graphical:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) == OK,
			"Screenshot output directory exists")
	for size in SIZES:
		if graphical:
			DisplayServer.window_set_size(size)
		root.size = size
		root.content_scale_size = size
		await process_frame
		var board := BOARD.instantiate() as Control
		root.add_child(board)
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		board.set_context({"database_connected":true,"database_loading":false,
			"teacher_authorized":false,"leaderboard_rows":ROWS.duplicate(true)})
		_add_preview_mark(board)
		await process_frame
		_verify_four(board, size, "Default")
		await _screenshot("Leaderboard_Shared_Default_%dx%d.png" % [size.x, size.y], size)
		for index in SELECTOR_NAMES.size():
			var selector := board.get_node("%" + SELECTOR_NAMES[index]) as OptionButton
			_check(_select_named(selector, LONG_SELECTED[index]), "Can select " + LONG_SELECTED[index])
		board.call("_on_filter_changed")
		_verify_four(board, size, "SelectedLong")
		await _screenshot("Leaderboard_Shared_SelectedLong_%dx%d.png" % [size.x, size.y], size)
		board.queue_free()
		await process_frame
		await process_frame
	_check(screenshots.size() == 6 or not graphical, "Six native screenshots generated or headless checks only")
	print("SHARED DROPDOWN QA %s checks=%d failures=%d screenshots=%d database_writes=0" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), screenshots.size()])
	quit(0 if failures.is_empty() else 1)
