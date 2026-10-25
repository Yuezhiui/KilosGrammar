extends SceneTree

# Isolated scene-authoring and filtering regression. No database or HTTP calls.
# Graphical capture: set CAPTURE_LEADERBOARD_MINIGAME=1 and run without --headless.
const LEADERBOARD := preload("res://ui/secondary/leaderboard.tscn")
const CANONICAL8 := "student_id,student_name,grade_section,minigame,game_style,game_mode,difficulty,score\r\n"
const LEGACY7 := "student_id,student_name,grade_section,game_style,game_mode,difficulty,score\r\n"

var issues: Array[String] = []
var checks := 0
var files: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var panel := LEADERBOARD.instantiate() as Control
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame

	var minigame := panel.get_node_or_null("%MinigameFilter") as OptionButton
	var style := panel.get_node_or_null("%StyleFilter") as OptionButton
	var mode := panel.get_node_or_null("%ModeFilter") as OptionButton
	var difficulty := panel.get_node_or_null("%DifficultyFilter") as OptionButton
	var rows := panel.get_node_or_null("%ScoreRows") as VBoxContainer
	_check(minigame == null and panel.get_node_or_null("%DownloadButton") == null
		and panel.has_method("set_minigame_filter"),
		"unused MinigameFilter/DownloadButton removed; host filter API remains")
	if rows == null:
		panel.queue_free()
		quit(1)
		return
	_check(bool(panel.call("set_minigame_filter", "ALL MINIGAMES")),
		"public host selection has default ALL even without hidden OptionButton")
	for obsolete in ["FiltersToggle", "FiltersArt", "MoreFiltersPanel", "CloseMoreFilters"]:
		_check(panel.find_child(obsolete, true, false) == null, "obsolete FILTERS/popover removed from authored UI: " + obsolete)
	_check(panel.find_child("MinigameFilter", true, false) == null
		and panel.find_child("DownloadButton", true, false) == null,
		"advanced minigame/Download controls no longer exist or intercept clicks")
	_check(panel.has_method("request_filtered_csv_export"),
		"hidden filtered CSV continues to work through public host API")
	_check(panel.has_method("set_transfer_status") and panel.has_method("set_transfer_pending"),
		"status host API survives removal of transfer panel")
	for selector in [style, mode, difficulty]:
		_check(selector.item_count > 1 and selector.is_visible_in_tree(), "original grammar/mode/difficulty filters preserved")
	_check(panel.get_node_or_null("%ImportCsvButton") is Button and panel.get_node_or_null("%ExportCsvButton") is Button and panel.get_node_or_null("%DeleteAllButton") is Button, "three visible authorized database actions preserved")

	var records := [
		{"student_id": "ID-1", "student_name": "One", "grade_section": "Grade 5", "minigame": "Catch the Word", "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 19},
		{"student_id": "ID-1", "student_name": "One", "grade_section": "Grade 5", "minigame": "Balloon Popping", "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 18},
		{"student_id": "ID-1", "student_name": "One", "grade_section": "Grade 5", "minigame": "Human Plane", "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 17},
		{"student_id": "ID-1", "student_name": "One", "grade_section": "Grade 5", "minigame": "Legacy", "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 16},
		{"student_id": "ID-2", "student_name": "Two", "grade_section": "Grade 4", "minigame": "Balloon Popping", "game_style": "Adjective", "game_mode": "Lives", "difficulty": "Hard", "score": 25},
	]
	panel.set_context({"leaderboard_rows": records, "database_connected": true})
	_check(rows.get_child_count() == 5, "different minigame scores coexist for same student, topic, mode and difficulty")
	_check((rows.get_child(0).get_node("StudentId") as Label).text == "ID-2", "scores retain original descending order")
	var displayed: Array[String] = []
	for index in range(rows.get_child_count()):
		var cell := rows.get_child(index).get_node_or_null("GameStyle") as Label
		_check(cell != null, "record retains scene-authored GameStyle label")
		if cell != null:
			displayed.append(cell.text)
			_check(cell.tooltip_text.contains("Grammar topic: "), "row tooltip contains unabridged grammar topic")
			var font := cell.get_theme_font("font") as Font
			var rendered_size := font.get_string_size(cell.text, HORIZONTAL_ALIGNMENT_LEFT, -1, cell.get_theme_font_size("font_size")).x
			_check(rendered_size <= cell.size.x, "abbreviated minigame/topic fits in %d px cell: %s" % [int(cell.size.x), cell.text])
	_check(displayed.has("CATCH / NOUN") and displayed.has("POP / NOUN") and displayed.has("PLANE / NOUN")
		and displayed.has("NOUN") and displayed.has("POP / ADJ") and not displayed.has("LEGACY / NOUN"),
		"all five original scores render; historical grammar-only entry has no misleading Legacy prefix")
	var legacy_displayed := false
	for item in rows.get_children():
		if (item.get_node("Score") as Label).text == "16":
			legacy_displayed = true
			var historic := item.get_node("GameStyle") as Label
			_check(historic.text == "NOUN" and historic.tooltip_text.contains("Grammar topic: Noun")
				and not historic.tooltip_text.to_upper().contains("LEGACY"),
				"historical row keeps Noun topic but does not expose internal Legacy classification")
	_check(legacy_displayed, "historical record score 16 is not removed by visual cleanup")
	var original_rows: Array = panel.get("_all_rows")
	_check(original_rows.size() == 5 and original_rows.any(func(item: Dictionary) -> bool:
		return item.get("minigame") == "Legacy" and int(item.get("score", -1)) == 16),
		"historical backend score and exact Legacy source metadata survive presentation cleanup")
	_check((rows.get_child(1).get_node("GameStyle") as Label).tooltip_text.contains("Catch the Word"), "full minigame name available via tooltip")

	for item in [
		{"name": "CATCH THE WORD", "expected": 1, "code": "CATCH / NOUN"},
		{"name": "BALLOON POPPING", "expected": 2, "code": "POP /"},
		{"name": "HUMAN PLANE", "expected": 1, "code": "PLANE / NOUN"},
	]:
		_check(bool(panel.call("set_minigame_filter", item["name"])), "public filter API accepts active minigame name")
		_check(rows.get_child_count() == item["expected"], "filter %s shows only matching backend minigame rows" % item["name"])
		if rows.get_child_count() > 0:
			_check((rows.get_child(0).get_node("GameStyle") as Label).text.begins_with(item["code"]), "visible result matches selected minigame")
	_check(bool(panel.call("set_minigame_filter", "Legacy")),
		"internal API still supports querying historical records despite removing Legacy menu option")
	_check(rows.get_child_count() == 1 and (rows.get_child(0).get_node("GameStyle") as Label).text == "NOUN",
		"Legacy compatibility selection returns only old record without misleading label")

	_check(bool(panel.call("set_minigame_filter", "BALLOON POPPING")), "public minigame filter sets Balloon Popping")
	style.select(1)
	style.item_selected.emit(1)
	_check(rows.get_child_count() == 1 and (rows.get_child(0).get_node("GameStyle") as Label).text == "POP / NOUN", "minigame + topic filters intersect")
	mode.select(2)
	mode.item_selected.emit(2)
	_check(rows.get_child_count() == 0, "minigame + style + mode can produce zero real records")
	_check((panel.get_node("%EmptyMessage") as Label).text == "No scores match these filters", "zero-match state is clear and no scores are invented")
	mode.select(0)
	mode.item_selected.emit(0)
	difficulty.select(1)
	difficulty.item_selected.emit(1)
	_check(rows.get_child_count() == 1, "difficulty composes with minigame and grammar topic")

	var csv_path := _make_csv("filtered", "")
	panel.call("_write_csv", csv_path)
	var csv_text := FileAccess.get_file_as_string(csv_path)
	_check(csv_text.begins_with("STUDENT ID,NAME,GRADE,MINIGAME,GAME STYLE,GAME MODE,DIFFICULTY,SCORE\r\n"), "filtered CSV explicitly has eight display headers including MINIGAME")
	_check(csv_text.contains("\"Balloon Popping\"") and csv_text.contains("\"Noun\""), "filtered CSV includes unabridged minigame and grammar topic")
	_check(not csv_text.contains("Catch the Word") and not csv_text.contains("Human Plane"), "filtered CSV excludes other minigame records")
	_check(not csv_text.begins_with(CANONICAL8), "filtered Download CSV stays distinct from backend canonical 8-column backup")

	_check(String(panel.call("_validate_import_csv", csv_path)) != "", "local filtered CSV intentionally fails full-database import preflight")
	var canonical_path := _make_csv("canonical", CANONICAL8 + "ID-3,Three,Grade 4,Human Plane,Verb,Seconds,Easy,3\r\n")
	var legacy_path := _make_csv("legacy", LEGACY7 + "ID-4,Four,Grade 3,Verb,Seconds,Easy,4\r\n")
	_check(String(panel.call("_validate_import_csv", canonical_path)).is_empty(), "backend 8-column canonical CSV preflight accepted")
	_check(String(panel.call("_validate_import_csv", legacy_path)).is_empty(), "backend legacy 7-column CSV preflight still accepted")
	var hostile_path := _make_csv("formula", CANONICAL8 + "ID-5,=HYPERLINK(1),Grade 4,Catch the Word,Noun,Seconds,Easy,3\r\n")
	_check(not String(panel.call("_validate_import_csv", hostile_path)).is_empty(), "CSV injection preflight remains active")

	_check(bool(panel.call("set_minigame_filter", "ALL MINIGAMES")), "public minigame filter resets to all")
	style.select(0)
	style.item_selected.emit(0)
	difficulty.select(0)
	difficulty.item_selected.emit(0)
	if OS.get_environment("CAPTURE_LEADERBOARD_MINIGAME") == "1" and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var screenshot := ProjectSettings.globalize_path("res://ui/secondary/_review_leaderboard_minigame.png")
		_check(root.get_texture().get_image().save_png(screenshot) == OK, "graphical 1280px screenshot captured")
		print("MINIGAME SCREENSHOT ", screenshot)

	for path in files:
		DirAccess.remove_absolute(path)
	panel.queue_free()
	await process_frame
	if issues.is_empty():
		print("PASS leaderboard minigame filter: %d assertions" % checks)
		quit(0)
	else:
		for issue in issues:
			push_error("LEADERBOARD MINIGAME FAIL: " + issue)
		print("FAIL leaderboard minigame filter: %d failures / %d assertions" % [issues.size(), checks])
		quit(1)


func _make_csv(id: String, contents: String) -> String:
	var path := ProjectSettings.globalize_path("user://_lb_minigame_%s_%d.csv" % [id, Time.get_ticks_usec()])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(contents)
		f.close()
	files.append(path)
	return path


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		issues.append(label)
