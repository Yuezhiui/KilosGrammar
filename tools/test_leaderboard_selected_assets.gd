extends SceneTree

## Historical regression migrated to shared wood, real native text and XLSX-only actions.
## No database server or destructive operations are called.
const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const SHARED := "res://Components/Leaderboard/SharedDropdown20261102/dropdown_base.png"
const CAPTURE_PATH := "res://ui/secondary/_review_selected_leaderboard.png"

var errors: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var panel := BOARD.instantiate() as Control
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	_check(panel.get_node_or_null("FiltersArt") == null
		and panel.get_node_or_null("FiltersToggle") == null
		and panel.get_node_or_null("MoreFiltersPanel") == null,
		"FILTERS art, button, and popover are entirely removed")
	_check(panel.has_method("set_minigame_filter") and panel.has_method("_validate_import_xlsx")
		and not panel.has_method("request_filtered_csv_export") and not panel.has_method("_write_csv"),
		"minigame API retained, obsolete CSV export removed, XLSX validator remains")
	_check(panel.find_child("MinigameFilter", true, false) == null
		and panel.find_child("DownloadButton", true, false) == null,
		"retired backend-only controls are physically removed and cannot intercept clicks")

	var groups := [
		["StyleFilter", ["ALL STYLES", "NOUN", "PRONOUN", "VERB", "ADJECTIVE", "ADVERB"]],
		["ModeFilter", ["ALL MODES", "SECONDS", "LIVES"]],
		["DifficultyFilter", ["ALL DIFFICULTIES", "EASY", "NORMAL", "HARD"]],
		["ScoreSort", ["SCORE", "HIGHEST SCORE", "LOWEST SCORE", "STUDENT ID A-Z", "GRADE LEVEL", "STUDENT NAME A-Z"]],
	]
	var shared_style: StyleBoxTexture
	var native_font := -1
	for group in groups:
		var selector := panel.get_node("%" + group[0]) as OptionButton
		var labels: Array = group[1]
		_check(selector != null and selector.item_count == labels.size(),
			group[0] + " has exactly the supported options")
		if selector == null:
			continue
		var original_skin := selector.get_theme_stylebox("normal") as StyleBoxTexture
		_check(original_skin != null and _asset_source(original_skin.texture) == SHARED,
			group[0] + " uses sole shared AtlasTexture wood PNG")
		if shared_style == null:
			shared_style = original_skin
		else:
			_check(original_skin == shared_style, group[0] + " reuses identical shared StyleBoxTexture")
		if native_font < 0:
			native_font = selector.get_theme_font_size("font_size")
		_check(selector.get_theme_font_size("font_size") == native_font and native_font >= 14,
			group[0] + " uses consistent readable Godot font")
		for index in labels.size():
			_check(selector.get_item_text(index).to_upper() == labels[index],
				"%s option %d has expected label" % [group[0], index])
			selector.select(index)
			selector.item_selected.emit(index)
			var skin := selector.get_theme_stylebox("normal") as StyleBoxTexture
			_check(skin == original_skin and _asset_source(skin.texture) == SHARED,
				"%s index %d keeps the single shared wood background" % [group[0], index])
			_check(selector.get_theme_color("font_color").a > 0.95 and selector.get_item_text(selector.selected).length() > 0,
				"%s index %d displays native selected caption" % [group[0], index])
			_check(selector.get_theme_icon("arrow").get_image().get_pixel(0, 0).a < 0.01,
				"%s index %d hides the native duplicate chevron" % [group[0], index])
		selector.select(0)
		selector.item_selected.emit(0)

	panel.set_context({"leaderboard_rows": [
		{"student_id":"A","student_name":"One","minigame":"Catch the Word","game_style":"Noun","game_mode":"Seconds","difficulty":"Easy","score":12},
		{"student_id":"B","student_name":"Two","minigame":"Human Plane","game_style":"Noun","game_mode":"Seconds","difficulty":"Easy","score":10},
		{"student_id":"C","student_name":"Three","minigame":"Human Plane","game_style":"Verb","game_mode":"Lives","difficulty":"Hard","score":16}
	], "database_connected":true})
	_check((panel.get_node("%ScoreRows") as VBoxContainer).get_child_count() == 3,
		"initial records render when backend supplies scores")
	_check(panel.set_minigame_filter("Human Plane"), "host can filter minigame by name")
	_check((panel.get_node("%ScoreRows") as VBoxContainer).get_child_count() == 2,
		"API minigame filter keeps only the requested records")
	_check(not panel.set_minigame_filter("Does not exist"),
		"unknown minigame filter is rejected")
	_check(panel.set_minigame_filter("ALL MINIGAMES"), "host can reset minigame selection")
	var importer := panel.get_node("%ImportCsvDialog") as FileDialog
	var exporter := panel.get_node("%ExportDatabaseCsvDialog") as FileDialog
	_check(importer.filters.size() == 1 and String(importer.filters[0]).contains("*.xlsx")
		and exporter.filters.size() == 1 and String(exporter.filters[0]).contains("*.xlsx"),
		"same import/export buttons exclusively use Excel workbooks")
	var imports: Array[String] = []
	var exports: Array[String] = []
	var deletes: Array[String] = []
	panel.database_import_xlsx_requested.connect(func(p: String): imports.append(p))
	panel.database_export_xlsx_requested.connect(func(p: String): exports.append(p))
	panel.database_delete_all_requested.connect(func(p: String): deletes.append(p))
	panel.call("_choose_import_xlsx")
	panel.call("_begin_delete_all")
	_check(imports.is_empty() and deletes.is_empty(), "unauthorized import/delete never dispatches")
	panel.set_context({"teacher_authorized": true, "database_connected": true})
	panel.call("_on_export_file_selected", "user://not_excel.csv")
	_check(exports.is_empty(), "CSV export filename rejected")
	panel.set_transfer_status("")
	panel.call("_on_export_file_selected", "user://safe_report.xlsx")
	_check(exports == ["user://safe_report.xlsx"] and imports.is_empty() and deletes.is_empty(),
		"authorized XLSX export emits exact one destination without mutation")
	panel.set_transfer_status("")
	if OS.get_environment("CAPTURE_LEADERBOARD_SELECTED") == "1" and DisplayServer.get_name() != "headless":
		panel.set_transfer_status("")
		for target in [["StyleFilter", 3], ["ModeFilter", 2], ["DifficultyFilter", 3]]:
			var selector := panel.get_node("%" + target[0]) as OptionButton
			selector.select(target[1])
			selector.item_selected.emit(target[1])
		_check((panel.get_node("%ScoreRows") as VBoxContainer).get_child_count() == 1,
			"combined selected art and filters show the one matching score")
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(CAPTURE_PATH)) == OK,
			"selected-art graphical screenshot created")
		print("LEADERBOARD CAPTURE: ", ProjectSettings.globalize_path(CAPTURE_PATH))
	for viewport in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = viewport
		root.content_scale_size = viewport
		await process_frame
		await process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport)).grow(3)
		for name in ["StyleFilter", "ModeFilter", "DifficultyFilter", "ScoreSort", "ImportCsvButton", "ExportCsvButton", "DeleteAllButton"]:
			var control := panel.get_node("%" + name) as Control
			_check(bounds.encloses(control.get_global_rect()),
				"%s stays inside %s viewport" % [name, viewport])
	panel.queue_free()
	await process_frame
	for failure in errors:
		printerr("LEADERBOARD SELECTED ASSETS FAIL: ", failure)
	print("LEADERBOARD SELECTED ASSETS: %s %d checks, %d failures" %
		["PASS" if errors.is_empty() else "FAIL", checks, errors.size()])
	quit(0 if errors.is_empty() else 1)

func _asset_source(texture: Texture2D) -> String:
	if texture is AtlasTexture:
		return (texture as AtlasTexture).atlas.resource_path
	return texture.resource_path if texture != null else ""

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		errors.append(description)
