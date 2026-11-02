extends SceneTree

## UI/transport regression after removing XLSX, selected-student and footer UI.
## Uses synthetic data and isolated user:// CSVs. No database, webcam or Git.
## godot --headless --path . --script res://tools/test_leaderboard_csv_only_scene_20261102.gd
const BOARD_PATH := "res://ui/secondary/leaderboard/leaderboard.tscn"
const BOARD_SCRIPT := "res://ui/secondary/leaderboard/leaderboard.gd"
const MENU_PATH := "res://ui/main_menu/main_menu.tscn"
const MENU_HARNESS := "res://tools/test_play_router_harness_20261030.gd"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const FORBIDDEN_NODES := [
	"SelectedStudentLabel", "PullOutStudentButton", "ExportGradeXlsxButton",
	"ExportStudentCsvDialog", "ExportGradeXlsxDialog", "DatabaseStatusNote",
	"TransferStatus", "TransferStatusPanel"
]
const REQUIRED_DIALOGS := [
	"SaveCsvDialog", "ImportCsvDialog", "ImportReviewDialog",
	"ExportDatabaseCsvDialog", "EmptyNotice"
]
const DATA := [
	{"student_id": "QA-41", "student_name": "=Teacher, Test", "grade_section": "Grade 4 - Ruby",
		"minigame": "Catch the Word", "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 18},
	{"student_id": "QA-51", "student_name": "Classmate", "grade_section": "Grade 5 - Jade",
		"minigame": "Human Plane", "game_style": "Verb", "game_mode": "Lives", "difficulty": "Normal", "score": 11}
]
const CANONICAL_CSV := "student_id,student_name,grade_section,minigame,game_style,game_mode,difficulty,score\r\n" + \
	"QA-41,Teacher Test,Grade 4 - Ruby,Catch the Word,Noun,Seconds,Easy,18\r\n"
var checks := 0
var issues: Array[String] = []
var qa_dir := ""


func _initialize() -> void:
	qa_dir = "user://qa_leaderboard_csv_only_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		issues.append(description)


func _run() -> void:
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(qa_dir)) == OK,
		"isolated test CSV folder created")
	var scene_text := FileAccess.get_file_as_string(BOARD_PATH)
	var script_text := FileAccess.get_file_as_string(BOARD_SCRIPT)
	_check(not scene_text.is_empty() and not script_text.is_empty(), "actual scene and controller are readable")
	_check(not scene_text.to_lower().contains("xlsx"), "serialized scene contains zero XLSX references")
	_check(not script_text.to_lower().contains("xlsx"), "live leaderboard controller contains zero XLSX callbacks")
	for name in FORBIDDEN_NODES:
		_check(not scene_text.contains('node name="' + name + '"'),
			"serialized scene omits obsolete frontend node " + name)
	for viewport in SIZES:
		await _check_board(viewport)
	await _check_menu_wiring()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(qa_dir))
	for issue in issues:
		printerr("LEADERBOARD CSV-ONLY FAIL: ", issue)
	print("LEADERBOARD CSV-ONLY SCENE: %s checks=%d failures=%d sizes=%d" % [
		"PASS" if issues.is_empty() else "FAIL", checks, issues.size(), SIZES.size()])
	quit(0 if issues.is_empty() else 1)


func _check_board(viewport: Vector2i) -> void:
	root.size = viewport
	root.content_scale_size = viewport
	var packed := load(BOARD_PATH) as PackedScene
	_check(packed != null, str(viewport) + " scene loads")
	if packed == null:
		return
	var board := packed.instantiate() as Control
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	board.set_context({"leaderboard_rows": DATA, "database_connected": true, "teacher_authorized": true})
	await process_frame
	var key := str(viewport)
	for name in FORBIDDEN_NODES:
		_check(board.find_child(name, true, false) == null,
			key + " no editor- or runtime-created " + name)
	for name in REQUIRED_DIALOGS:
		_check(board.get_node_or_null("%" + name) != null, key + " CSV/notice dialog survives: " + name)
	for name in ["ImportCsvButton", "ExportCsvButton", "DeleteAllButton"]:
		var button := board.get_node_or_null("%" + name) as Button
		_check(button != null and button.is_visible_in_tree(),
			key + " editor-authored CSV/delete button remains visible: " + name)
	for name in ["GradeLevelFilter", "SectionFilter", "StudentSearch", "ScoreSort"]:
		_check(board.get_node_or_null("%" + name) != null, key + " grade/section filter survives: " + name)
	_check(not board.has_signal("database_export_student_requested")
		and not board.has_signal("database_export_grade_xlsx_requested"),
		key + " no XLSX export signals remain on real board")
	_check(board.has_signal("database_export_csv_requested")
		and board.has_signal("database_import_csv_requested")
		and board.has_signal("database_delete_all_requested"),
		key + " canonical CSV and protected delete signals survive")
	_check(not board.has_method("_choose_student_export")
		and not board.has_method("_on_student_export_file_selected")
		and not board.has_method("_choose_grade_xlsx_export")
		and not board.has_method("_on_grade_xlsx_file_selected"),
		key + " no stale XLSX callbacks remain")
	for spec in [
		{"dialog": "SaveCsvDialog", "callback": "_write_csv"},
		{"dialog": "ImportCsvDialog", "callback": "_on_import_file_selected"},
		{"dialog": "ExportDatabaseCsvDialog", "callback": "_on_export_file_selected"}
	]:
		var dialog := board.get_node_or_null("%" + spec["dialog"]) as FileDialog
		if dialog == null:
			continue
		_check(dialog.filters.size() == 1 and String(dialog.filters[0]).contains("*.csv"),
			key + " " + spec["dialog"] + " retains CSV-only file filter")
		var connections := dialog.file_selected.get_connections()
		_check(connections.size() == 1 and connections[0]["callable"].get_object() == board
			and String(connections[0]["callable"].get_method()) == spec["callback"],
			key + " " + spec["dialog"] + " has exactly one live CSV callback")

	var grade := board.get_node("%GradeLevelFilter") as OptionButton
	var section := board.get_node("%SectionFilter") as OptionButton
	var grade_4 := -1
	for i in grade.item_count:
		if grade.get_item_text(i) == "Grade 4":
			grade_4 = i
	_check(grade_4 >= 0, key + " Grade 4 option generated from real scores")
	if grade_4 >= 0:
		grade.select(grade_4)
		board.call("_on_grade_changed")
		_check(board.get("_visible_rows").size() == 1, key + " grade filters to matching student")
		var ruby_exists := false
		for i in section.item_count:
			if section.get_item_text(i) == "Ruby":
				section.select(i)
				ruby_exists = true
		board.call("_on_filter_changed")
		_check(ruby_exists and board.get("_visible_rows").size() == 1,
			key + " section filter retains matching Ruby score")

	var canonical_exports: Array[String] = []
	var canonical_imports: Array[String] = []
	var deletes: Array[String] = []
	board.database_export_csv_requested.connect(func(path: String) -> void: canonical_exports.append(path))
	board.database_import_csv_requested.connect(func(path: String) -> void: canonical_imports.append(path))
	board.database_delete_all_requested.connect(func(phrase: String) -> void: deletes.append(phrase))
	var export_target := qa_dir.path_join("filtered_%dx%d.csv" % [viewport.x, viewport.y])
	board.request_filtered_csv_export()
	var local_dialog := board.get_node("%SaveCsvDialog") as FileDialog
	_check(local_dialog.visible, key + " filtered CSV opens its original file chooser")
	local_dialog.file_selected.emit(ProjectSettings.globalize_path(export_target))
	_check(FileAccess.file_exists(export_target), key + " filtered CSV writes only to isolated QA file")
	if FileAccess.file_exists(export_target):
		var filtered := FileAccess.get_file_as_string(export_target)
		_check(filtered.begins_with("STUDENT ID,NAME,GRADE,MINIGAME,GAME STYLE,GAME MODE,DIFFICULTY,SCORE\r\n")
			and filtered.contains("'=Teacher, Test") and filtered.count("\r\n") == 2,
			key + " filtered CSV has 8 columns, 1 row, spreadsheet-formula protection")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(export_target))
	_check(canonical_exports.is_empty() and canonical_imports.is_empty() and deletes.is_empty(),
		key + " local filtered CSV never touches database action signals")
	(board.get_node("%EmptyNotice") as AcceptDialog).hide()

	board.call("_on_export_file_selected", qa_dir.path_join("wrong.xlsx"))
	_check(canonical_exports.is_empty(), key + " XLSX path rejected by canonical CSV export callback")
	board.set_transfer_status("")
	(board.get_node("%EmptyNotice") as AcceptDialog).hide()
	board.call("_on_export_file_selected", qa_dir.path_join("full.csv"))
	_check(canonical_exports.size() == 1 and canonical_exports[0].ends_with("full.csv")
		and not FileAccess.file_exists(qa_dir.path_join("full.csv")),
		key + " full CSV export delegates to backend without premature local file")
	_check(board.get("_transfer_pending"), key + " pending canonical CSV export locks double requests")
	board.call("_on_export_file_selected", qa_dir.path_join("duplicate.csv"))
	_check(canonical_exports.size() == 1, key + " pending state prevents duplicate CSV export")
	board.set_transfer_status("")
	(board.get_node("%EmptyNotice") as AcceptDialog).hide()

	var import_target := qa_dir.path_join("canonical_%dx%d.csv" % [viewport.x, viewport.y])
	var file := FileAccess.open(import_target, FileAccess.WRITE)
	_check(file != null, key + " isolated canonical CSV fixture created")
	if file != null:
		file.store_string(CANONICAL_CSV)
		file.close()
		_check(String(board.call("_validate_import_csv", import_target)).is_empty(),
			key + " canonical 8-column CSV validates before import")
		board.call("_on_import_file_selected", ProjectSettings.globalize_path(import_target))
		var review := board.get_node("%ImportReviewDialog") as ConfirmationDialog
		_check(review.visible and canonical_imports.is_empty(),
			key + " import review requires explicit confirmation")
		board.call("_cancel_import_csv")
		_check(canonical_imports.is_empty() and not review.visible,
			key + " cancel import never dispatches")
		board.call("_on_import_file_selected", ProjectSettings.globalize_path(import_target))
		board.call("_confirm_import_csv")
		_check(canonical_imports.size() == 1 and canonical_imports[0].ends_with(import_target.get_file()),
			key + " confirmed CSV import emits one backend request")
		board.set_transfer_status("")
		(board.get_node("%EmptyNotice") as AcceptDialog).hide()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(import_target))
	_check(deletes.is_empty(), key + " CSV operations cannot dispatch deletion")
	board.call("_on_final_delete_pressed")
	_check(deletes.is_empty(), key + " direct delete callback without modal is inert")
	board.set_context({"database_connected": true, "teacher_authorized": false, "leaderboard_rows": DATA})
	board.call("_begin_delete_all")
	_check(deletes.is_empty() and not (board.get_node("%DeleteFirstOverlay") as Control).visible,
		key + " unauthorized delete does not open warning or dispatch")
	board.queue_free()
	await process_frame
	await process_frame


func _check_menu_wiring() -> void:
	var menu_scene := load(MENU_PATH) as PackedScene
	var harness := load(MENU_HARNESS) as Script
	_check(menu_scene != null and harness != null and harness.can_instantiate(),
		"real main menu and isolated router harness load after autoloads")
	if menu_scene == null or harness == null or not harness.can_instantiate():
		return
	root.size = SIZES[0]
	root.content_scale_size = SIZES[0]
	var menu := menu_scene.instantiate() as Control
	menu.set_script(harness)
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	menu.call("_on_panel_requested", "leaderboard", {})
	await process_frame
	var board := menu.get("active_panel") as Control
	_check(board != null and String(menu.get("current_route")) == "leaderboard",
		"real MainMenu router opens CSV-only leaderboard")
	if board != null:
		for spec in [
			{"signal": "database_export_csv_requested", "handler": "_on_database_export_csv_requested"},
			{"signal": "database_import_csv_requested", "handler": "_on_database_import_csv_requested"},
			{"signal": "database_delete_all_requested", "handler": "_on_database_delete_all_requested"}
		]:
			var connections := (Signal(board, StringName(spec["signal"]))).get_connections()
			_check(connections.size() == 1 and connections[0]["callable"].get_object() == menu
				and String(connections[0]["callable"].get_method()) == spec["handler"],
				"MainMenu has one live " + spec["signal"] + " -> " + spec["handler"] + " connection")
		_check(not board.has_signal("database_export_grade_xlsx_requested")
			and not board.has_signal("database_export_student_requested"),
			"MainMenu cannot connect deleted XLSX signals")
	var menu_source := FileAccess.get_file_as_string("res://ui/main_menu/main_menu.gd")
	_check(not menu_source.contains("database_export_grade_xlsx_requested")
		and not menu_source.contains("database_export_student_requested"),
		"MainMenu source has no dangling XLSX response/request connections")
	menu.call("_return_to_main")
	await process_frame
	menu.queue_free()
	await process_frame
	await process_frame
