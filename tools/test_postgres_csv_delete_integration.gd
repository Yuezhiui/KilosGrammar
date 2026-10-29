extends SceneTree

## Deliberately runs real editor-authored UI with a NO-SOCKET fake service.
## NEVER connects to PostgreSQL or calls the real local HTTP endpoint.
## godot --headless --path . --script res://tools/test_postgres_csv_delete_integration.gd
const MENU_PATH := "res://tools/test_postgres_csv_delete_menu_fixture.gd"
const VALID_CSV := "student_id,student_name,grade_section,minigame,game_style,game_mode,difficulty,score\r\n\"ID-1\",\"Ada, \"\"Quoted\"\"\",\"Grade 5\",\"Catch the Word\",\"Noun\",\"Seconds\",\"Easy\",\"7\"\r\n"
const LEGACY_CSV := "student_id,student_name,grade_section,game_style,game_mode,difficulty,score\r\n\"LEG-1\",\"Bea, \"\"Legacy\"\"\",\"Grade 5\",\"Noun\",\"Seconds\",\"Easy\",\"4\"\r\n"
## Every QA CSV file and recovery event stays under a fresh test-only folder;
## never overwrite a historical QA export or the live classroom outbox.
var IMPORT_PATH := ""
var LEGACY_IMPORT_PATH := ""
var EXPORT_PATH := ""
var FILTERED_PATH := ""
var STALE_EXPORT_PATH := ""
var STALE_IMPORT_PATH := ""
var qa_storage := ""
var failures: Array[String] = []
var checks := 0
var app: Control
var client: Node
var board: Control


func _initialize() -> void:
	qa_storage = "user://test_recovery_csv_integration_%d_%d" % [
		OS.get_process_id(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("kilos/recovery_test_directory", qa_storage)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(qa_storage)) != OK:
		push_error("Could not create isolated QA CSV/recovery directory")
		quit(1)
		return
	IMPORT_PATH = qa_storage.path_join("qa_postgres_csv_delete_import.csv")
	LEGACY_IMPORT_PATH = qa_storage.path_join("qa_postgres_csv_delete_legacy_import.csv")
	EXPORT_PATH = qa_storage.path_join("qa_postgres_csv_delete_export.csv")
	FILTERED_PATH = qa_storage.path_join("qa_postgres_csv_delete_filtered.csv")
	STALE_EXPORT_PATH = qa_storage.path_join("qa_postgres_csv_delete_stale_export.csv")
	STALE_IMPORT_PATH = qa_storage.path_join("qa_postgres_csv_delete_stale_import.csv")
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://ui/main_menu/main_menu.tscn") as PackedScene
	_check(packed != null, "Existing real Main Menu scene loads")
	if packed == null:
		quit(1)
		return
	app = packed.instantiate() as Control
	var test_script := load(MENU_PATH) as Script
	_check(test_script != null and test_script.can_instantiate(),
		"Test-only Main Menu subclass loads with autoloads present")
	if test_script == null or not test_script.can_instantiate():
		app.free()
		quit(1)
		return
	app.set_script(test_script)
	root.add_child(app)
	await process_frame
	client = app.get("database_client") as Node
	_check(is_instance_valid(client), "Injected database transport is an in-memory mock")
	if not is_instance_valid(client):
		await _finish()
		return
	_check(client.get_child_count() == 0, "Mock contains no HTTPRequest, subprocess, or SQL engine")
	_check(client.call("reply", "health", {"ok": true, "status": 200,
		"data": {"database": "connected"}}, "startup"), "Mock local health starts online")
	(app.get_node("MainLayer/LeftMenu/Leaderboard") as Button).pressed.emit()
	await process_frame
	board = app.get("active_panel") as Control
	_check(board != null and String(app.get("current_route")) == "leaderboard",
		"Native leaderboard scene opens for teacher")
	if board == null:
		await _finish()
		return
	_check(client.call("reply", "get_leaderboard", {
		"ok": true, "status": 200, "data": {"leaderboard": [{
			"student_id": "ID-1", "student_name": "Ada, \"Quoted\"",
			"grade_section": "Grade 5", "minigame": "Catch the Word", "game_style": "Noun",
			"game_mode": "Seconds", "difficulty": "Easy", "score": 7,
		}]},
	}, "leaderboard"), "Leaderboard fixtures are provided only via mock response")
	_check((board.get_node("%ScoreRows") as VBoxContainer).get_child_count() == 1,
		"One previously saved row is shown before CSV/delete interaction")
	_check(_find(board, ["SaveCsvDialog"]) is FileDialog,
		"Existing editor-authored Save CSV file dialog remains")
	_check(_find(board, ["ImportCsvDialog", "OpenCsvDialog"]) is FileDialog,
		"Import uses a native editor-authored Open CSV FileDialog")
	_check(_find(board, ["ImportButton", "ImportCsvButton"]) is Button,
		"Import CSV button is editor-authored")
	_check(_find(board, ["ExportButton", "ExportCsvButton"]) is Button,
		"Export CSV button is editor-authored")
	_check(_find(board, ["DeleteAllButton", "DeleteAllDataButton"]) is Button,
		"Delete All Data button is editor-authored")
	var blocked_imports: int = client.call("count", "import_data_csv")
	var blocked_deletes: int = client.call("count", "request_delete_all_challenge")
	(_find(board, ["ImportCsvButton"]) as Button).pressed.emit()
	(_find(board, ["DeleteAllButton"]) as Button).pressed.emit()
	_check(int(client.call("count", "import_data_csv")) == blocked_imports
		and int(client.call("count", "request_delete_all_challenge")) == blocked_deletes,
		"Untrusted leaderboard context cannot trigger CSV import or destructive challenge")
	# Fake local admin capability via transport; only the Main Menu may
	# propagate that into teacher_authorized UI context. This tests actual
	# host wiring rather than forcibly injecting auth into the child panel.
	_authorize_mock_teacher()
	await _test_minigame_display_and_filters()
	await _test_export()
	await _test_import()
	await _test_legacy_import()
	await _test_delete()
	await _test_stale_callbacks()
	await _finish()


func _test_minigame_display_and_filters() -> void:
	_check(_find(board, ["MinigameFilter", "DownloadButton", "TransferStatusPanel", "TransferStatus"]) == null,
		"unused hidden selector/download/status nodes removed from the editor-authored leaderboard")
	for old_node in ["FiltersToggle", "FiltersArt", "MoreFiltersPanel", "CloseMoreFilters"]:
		_check(board.find_child(old_node, true, false) == null,
			"removed FILTERS/popover cannot be reopened: " + old_node)
	_check(board.has_method("set_minigame_filter") and board.has_method("request_filtered_csv_export"),
		"hidden minigame and CSV preserve explicit non-popover host APIs")
	var expected := ["ALL MINIGAMES", "CATCH THE WORD", "BALLOON POPPING", "HUMAN PLANE"]
	_check(not board.has_node("MinigameFilter") and board.has_method("set_minigame_filter"),
		"script-only minigame selection retains host filtering without a hidden native OptionButton")
	var same_topic: Array = []
	for spec in [
		{"minigame": "Catch the Word", "score": 11},
		{"minigame": "Balloon Popping", "score": 12},
		{"minigame": "Human Plane", "score": 13},
		{"minigame": "Legacy", "score": 14},
	]:
		same_topic.append({
			"student_id": "SAME-STUDENT", "student_name": "One Student", "grade_section": "Grade 5",
			"minigame": spec["minigame"], "game_style": "Noun", "game_mode": "Seconds",
			"difficulty": "Easy", "score": spec["score"],
		})
	app.call("_load_database_leaderboard")
	_check(client.call("reply", "get_leaderboard", {
		"ok": true, "status": 200, "data": {"leaderboard": same_topic},
	}, "leaderboard"), "Server-backed ranking may contain same student, topic, mode and difficulty across four minigames")
	_check(_count_rows() == 4, "Leaderboard does not collapse scores that differ only by minigame")
	var rows := board.get_node("%ScoreRows") as VBoxContainer
	var visible_styles: Array[String] = []
	for row in rows.get_children():
		var style_cell := row.get_node("GameStyle") as Label
		visible_styles.append(style_cell.text)
		_check(style_cell.tooltip_text.contains("Grammar topic: Noun"),
			"Ranking cell tooltip distinguishes minigame name from grammar topic")
	_check(visible_styles.has("CATCH / NOUN") and visible_styles.has("POP / NOUN")
		and visible_styles.has("PLANE / NOUN") and visible_styles.has("NOUN")
		and not visible_styles.has("LEGACY / NOUN"),
		"Same topic retains four independent records; legacy rank displays topic only without misleading prefix")
	for index in range(1, expected.size()):
		_check(bool(board.call("set_minigame_filter", expected[index])),
			"public API sets hidden minigame filter " + expected[index])
		_check(_count_rows() == 1,
			"Minigame filter '%s' selects exactly its backend row" % expected[index])
		if _count_rows() == 1:
			var row_style := (rows.get_child(0).get_node("GameStyle") as Label).text
			var starts := ["", "CATCH", "POP", "PLANE"]
			_check(row_style.begins_with(starts[index] + " / "),
				"Filtered record displays its accurate activity: " + expected[index])
	_check(bool(board.call("set_minigame_filter", "Legacy")) and _count_rows() == 1,
		"Historical Legacy records remain queryable through compatibility host API without a visible menu option")
	if _count_rows() == 1:
		var historic_style := (rows.get_child(0).get_node("GameStyle") as Label).text
		_check(historic_style == "NOUN", "Historical score retains grammar topic alone, with no Legacy prefix")
	# The older green Download button saves a display extract; its header must
	# not be confused with the server's canonical full backup field names.
	var local_save := _find(board, ["SaveCsvDialog"]) as FileDialog
	_check(_find(board, ["DownloadButton"]) == null and local_save != null,
		"filtered CSV host API retains SaveCsvDialog, with unused DownloadButton physically removed")
	if local_save != null:
		board.call("request_filtered_csv_export")
		_check(local_save.visible, "Filtered Download launches its native SaveCsvDialog")
		local_save.file_selected.emit(ProjectSettings.globalize_path(FILTERED_PATH))
		local_save.hide()
		_check(FileAccess.file_exists(FILTERED_PATH), "Filtered CSV is created for selected Legacy rank only")
		if FileAccess.file_exists(FILTERED_PATH):
			var filtered := FileAccess.get_file_as_string(FILTERED_PATH)
			_check(filtered.begins_with("STUDENT ID,NAME,GRADE,MINIGAME,GAME STYLE,GAME MODE,DIFFICULTY,SCORE\r\n")
				and filtered.contains("\"Legacy\",\"Noun\"")
				and filtered.count("\r\n") == 2,
				"Filtered CSV has eight display columns and one Legacy record, distinct from canonical full export")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FILTERED_PATH))
	_check(bool(board.call("set_minigame_filter", "ALL MINIGAMES")),
		"public API resets hidden minigame filter")
	_check(_count_rows() == 4, "Restoring ALL MINIGAMES shows all four independent scores")
	_check(board.find_child("MinigameFilter", true, false) == null
		and board.find_child("DownloadButton", true, false) == null,
		"hidden controls remain absent after host requests; no FILTERS popover returns")
	# Restore a predictable single, fully identified live minigame ranking for
	# the existing export/import/delete safety checks.
	_authorize_mock_teacher()


func _test_export() -> void:
	var export_button := _find(board, ["ExportCsvButton"]) as Button
	var chooser := _find(board, ["ExportDatabaseCsvDialog"]) as FileDialog
	if export_button == null or chooser == null:
		return
	var initial_mutations: int = client.call("mutation_count")
	var initial_exports: int = client.call("count", "export_data_csv")
	export_button.pressed.emit()
	_check(chooser.visible, "Export button displays native Save FileDialog")
	chooser.canceled.emit()
	chooser.hide()
	_check(int(client.call("mutation_count")) == initial_mutations,
		"Cancel Export never inserts/deletes records")
	_check(not FileAccess.file_exists(EXPORT_PATH),
		"Cancelled Export does not create a misleading file")
	export_button.pressed.emit()
	chooser.file_selected.emit(ProjectSettings.globalize_path(EXPORT_PATH))
	chooser.hide()
	_check(int(client.call("count", "export_data_csv")) > initial_exports,
		"Selecting an export destination requests complete backend-authorized CSV")
	_check(not FileAccess.file_exists(EXPORT_PATH),
		"No saved CSV is claimed before backend acknowledges the export")
	_check(client.call("reply", "export_data_csv", {
		"ok": false, "status": 403, "error": "admin_authorization_required",
		"message": "Teacher permission missing", "data": null,
	}), "Backend may reject export without a local teacher authorization token")
	_check(not FileAccess.file_exists(EXPORT_PATH),
		"Rejected unauthorized export leaves no CSV file behind")
	var denied_status := _find(board, ["EmptyNotice"]) as AcceptDialog
	_check(denied_status != null and denied_status.dialog_text.contains("failed"),
		"Denied export does not claim saved CSV success")
	export_button.pressed.emit()
	chooser.file_selected.emit(ProjectSettings.globalize_path(EXPORT_PATH))
	chooser.hide()
	var response := {"ok": true, "status": 200,
		"data": {"csv": VALID_CSV, "students": 1, "scores": 1}}
	_check(client.call("reply", "export_data_csv", response),
		"Server-generated CSV reply reaches the real export callback")
	_check(FileAccess.file_exists(EXPORT_PATH),
		"CSV file is created only after a successful export response")
	if FileAccess.file_exists(EXPORT_PATH):
		var text_csv := FileAccess.get_file_as_string(EXPORT_PATH)
		_check(text_csv == VALID_CSV,
			"Backend full export preserves eight canonical fields, comma quoting, escaped quotes and CRLF")
		_check(text_csv.begins_with("student_id,student_name,grade_section,minigame,game_style,game_mode,difficulty,score\r\n")
			and text_csv.contains("\"Catch the Word\",\"Noun\""),
			"Full backup CSV includes minigame as FOURTH column, not filtered legacy layout")
		_check(text_csv.contains("\"Ada, \"\"Quoted\"\"\""),
			"Quoted student name is not corrupted by export")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(EXPORT_PATH))
	var transfer_status := _find(board, ["EmptyNotice"]) as AcceptDialog
	_check(transfer_status != null and transfer_status.dialog_text.contains("saved: 1 students, 1 scores"),
		"Export success is explicitly displayed only after confirmed backend response")


func _test_import() -> void:
	var button := _find(board, ["ImportButton", "ImportCsvButton"]) as Button
	var picker := _find(board, ["ImportCsvDialog", "OpenCsvDialog"]) as FileDialog
	var review := _find(board, ["ImportReviewDialog"]) as ConfirmationDialog
	_check(review != null, "Second import approval is an editor-authored ConfirmationDialog")
	if button == null or picker == null or review == null:
		return
	var initial_mutations: int = client.call("mutation_count")
	button.pressed.emit()
	_check(picker.visible, "Import shows native Open CSV FileDialog")
	picker.canceled.emit()
	picker.hide()
	_check(int(client.call("mutation_count")) == initial_mutations,
		"Cancel Import never calls a write endpoint")
	_check(not review.visible and String(board.get("_pending_import_path")).is_empty(),
		"Canceling CSV picker cannot open/stage second import approval")
	var file := FileAccess.open(IMPORT_PATH, FileAccess.WRITE)
	_check(file != null, "Isolated QA CSV fixture can be created outside project files")
	if file == null:
		return
	file.store_string(VALID_CSV)
	file.close()
	var local_validation := String(board.call("_validate_import_csv", ProjectSettings.globalize_path(IMPORT_PATH)))
	_check(local_validation.is_empty(), "Valid quoted CSV passes native import prevalidation: " + local_validation)
	var badfile := FileAccess.open(IMPORT_PATH, FileAccess.WRITE)
	if badfile != null:
		badfile.store_string("student_id,student_id,grade_section,minigame,game_style,game_mode,difficulty,score\r\n")
		badfile.store_string("ID-1,Ada,Grade 5,Catch the Word,Noun,Seconds,Easy,7\r\n")
		badfile.close()
		var writes_before: int = client.call("count", "import_data_csv")
		button.pressed.emit()
		picker.file_selected.emit(ProjectSettings.globalize_path(IMPORT_PATH))
		picker.hide()
		_check(int(client.call("count", "import_data_csv")) == writes_before,
			"Malformed/duplicate-column CSV is rejected locally before sending any write")
		_check(not review.visible and String(board.get("_pending_import_path")).is_empty(),
			"Malformed CSV cannot reach second import approval")
		var restored_file := FileAccess.open(IMPORT_PATH, FileAccess.WRITE)
		if restored_file != null:
			restored_file.store_string(VALID_CSV)
			restored_file.close()
	_check(String(board.call("_validate_import_csv", ProjectSettings.globalize_path(IMPORT_PATH))).is_empty(),
		"Eight-column canonical CSV is accepted after rejecting malformed input")
	# Even after choosing a valid file, the import is only *staged* until the
	# teacher explicitly approves the separate ConfirmationDialog.
	var before_cancel: int = client.call("count", "import_data_csv")
	button.pressed.emit()
	picker.file_selected.emit(ProjectSettings.globalize_path(IMPORT_PATH))
	picker.hide()
	_check(review.visible and review.dialog_text.contains(IMPORT_PATH.get_file()),
		"Valid CSV selection displays final review with exact filename")
	_check(int(client.call("count", "import_data_csv")) == before_cancel,
		"Choosing valid CSV without approving review sends no import request")
	review.canceled.emit()
	review.hide()
	_check(int(client.call("count", "import_data_csv")) == before_cancel
		and not review.visible and String(board.get("_pending_import_path")).is_empty(),
		"Cancel second import confirmation clears staged path without mutation")
	button.pressed.emit()
	picker.file_selected.emit(ProjectSettings.globalize_path(IMPORT_PATH))
	picker.hide()
	_approve_import_review(board, ProjectSettings.globalize_path(IMPORT_PATH))
	_check(int(client.call("count", "import_data_csv")) >= 1,
		"Import sends selected UTF-8 CSV to server validation endpoint")
	var pending: Dictionary = client.call("find_pending", "import_data_csv")
	_check(String(pending.get("args", {}).get("csv", "")) == VALID_CSV,
		"Eight-column import passes exact selected bytes, minigame, and quoted fields")
	_check(_count_rows() == 1,
		"Before import confirmation old backend scores remain unchanged")
	_check(client.call("reply", "import_data_csv", {
		"ok": false, "status": 400, "error": "invalid_csv",
		"message": "CSV row has an invalid score", "data": null,
	}), "Malformed CSV response is delivered")
	_check(_count_rows() == 1,
		"Rejected malformed CSV never replaces previously saved scores")
	var status := _find(board, ["EmptyNotice"]) as AcceptDialog
	_check(status != null and status.dialog_text.contains("failed"),
		"Malformed CSV response displays a failure, never a success message")
	button.pressed.emit()
	picker.file_selected.emit(ProjectSettings.globalize_path(IMPORT_PATH))
	picker.hide()
	_approve_import_review(board, ProjectSettings.globalize_path(IMPORT_PATH))
	_check(client.call("reply", "import_data_csv", {
		"ok": false, "status": 409, "error": "duplicate_record",
		"message": "Duplicated student identity", "data": null,
	}), "Duplicate record rejection is delivered")
	_check(_count_rows() == 1,
		"Duplicate-rejected CSV does not change leaderboard")
	_check(status.dialog_text.contains("failed") and not status.dialog_text.contains("CSV imported"),
		"Duplicate records cannot result in a misleading import-success status")
	button.pressed.emit()
	picker.file_selected.emit(ProjectSettings.globalize_path(IMPORT_PATH))
	picker.hide()
	_approve_import_review(board, ProjectSettings.globalize_path(IMPORT_PATH))
	var fetches: int = client.call("count", "get_leaderboard")
	_check(client.call("reply", "import_data_csv", {
		"ok": true, "status": 200, "data": {"students": 1, "scores": 1},
	}), "Valid import confirmation is delivered")
	_check(int(client.call("count", "get_leaderboard")) == fetches + 1,
		"Successful import refreshes authoritative leaderboard from server")
	_check(status.dialog_text.contains("CSV imported"), "Only successful API import shows import-success notice")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(IMPORT_PATH))
	# In-flight import results must not navigate back into the abandoned screen.
	var count_before_missing: int = client.call("count", "import_data_csv")
	button.pressed.emit()
	picker.file_selected.emit(ProjectSettings.globalize_path(IMPORT_PATH))
	picker.hide()
	_check(int(client.call("count", "import_data_csv")) == count_before_missing,
		"Missing input cannot dispatch a new server write or crash the callback")
	_check(not review.visible and String(board.get("_pending_import_path")).is_empty(),
		"Missing import file cannot stage a second approval or retain a dangerous path")


func _test_legacy_import() -> void:
	# Seven-column backups remain valid and are explicitly labeled Legacy by
	# the server; they must NEVER be silently assigned a current minigame.
	var button := _find(board, ["ImportCsvButton"]) as Button
	var picker := _find(board, ["ImportCsvDialog"]) as FileDialog
	var review := _find(board, ["ImportReviewDialog"]) as ConfirmationDialog
	_check(button != null and picker != null and review != null,
		"Original seven-column backup uses the same three native import controls")
	if button == null or picker == null or review == null:
		return
	var file := FileAccess.open(LEGACY_IMPORT_PATH, FileAccess.WRITE)
	_check(file != null, "Legacy CSV fixture can be written under isolated user:// path")
	if file == null:
		return
	file.store_string(LEGACY_CSV)
	file.close()
	var source_path := ProjectSettings.globalize_path(LEGACY_IMPORT_PATH)
	_check(String(board.call("_validate_import_csv", source_path)).is_empty(),
		"Real leaderboard accepts exact seven-column pre-minigame backup format")
	var count_before: int = client.call("count", "import_data_csv")
	button.pressed.emit()
	picker.file_selected.emit(source_path)
	picker.hide()
	_check(review.visible and review.dialog_text.contains(LEGACY_IMPORT_PATH.get_file()),
		"Legacy import also presents explicit filename review before any write")
	_check(int(client.call("count", "import_data_csv")) == count_before,
		"Seven-column file selection alone does not issue a DB write")
	review.canceled.emit()
	review.hide()
	_check(int(client.call("count", "import_data_csv")) == count_before
		and String(board.get("_pending_import_path")).is_empty(),
		"Canceling Legacy import review leaves database untouched and forgets path")
	button.pressed.emit()
	picker.file_selected.emit(source_path)
	picker.hide()
	_approve_import_review(board, source_path)
	var pending: Dictionary = client.call("find_pending", "import_data_csv")
	var submitted := String(pending.get("args", {}).get("csv", ""))
	_check(submitted == LEGACY_CSV and not submitted.contains("minigame"),
		"Approved legacy import sends ORIGINAL seven fields unchanged, never forges a minigame")
	_check(submitted.contains("\"Bea, \"\"Legacy\"\"\""),
		"Legacy import preserves commas and escaped quotes in student names")
	var fetches_before: int = client.call("count", "get_leaderboard")
	_check(client.call("reply", "import_data_csv", {
		"ok": true, "status": 200,
		"data": {"students_created": 1, "scores_imported": 1, "legacy_rows": 1},
	}), "Backend acknowledgment of correctly labeled Legacy import is delivered")
	_check(int(client.call("count", "get_leaderboard")) == fetches_before + 1,
		"Legacy import success re-queries server instead of fabricating local scores")
	_check(client.call("reply", "get_leaderboard", {
		"ok": true, "status": 200, "data": {"leaderboard": [{
			"student_id": "LEG-1", "student_name": "Bea, \"Legacy\"",
			"grade_section": "Grade 5", "minigame": "Legacy", "game_style": "Noun",
			"game_mode": "Seconds", "difficulty": "Easy", "score": 4,
		}]},
	}, "leaderboard"), "Server-supplied Legacy minigame record reaches native leaderboard")
	_check(_count_rows() == 1
		and (board.get_node("%ScoreRows").get_child(0).get_node("GameStyle") as Label).text == "NOUN",
		"Post-import historical score is still present while visible style omits misleading Legacy prefix")
	var raw_records: Array = board.get("_all_rows")
	_check(raw_records.size() == 1 and raw_records[0].get("minigame") == "Legacy"
		and raw_records[0].get("game_style") == "Noun" and int(raw_records[0].get("score", -1)) == 4,
		"Historical backend record retains original Legacy minigame, Noun topic, and score without rewriting data")
	var minigame_filter := _find(board, ["MinigameFilter"]) as OptionButton
	if minigame_filter != null:
		_check(minigame_filter.item_count == 4, "Historical Legacy not exposed in native MinigameFilter options")
		_check(bool(board.call("set_minigame_filter", "Legacy")) and _count_rows() == 1,
			"Historical seven-column backup rank is still retrievable through Legacy compatibility API")
		minigame_filter.select(1)
		minigame_filter.item_selected.emit(1)
		_check(_count_rows() == 0,
			"Legacy score is never misclassified as Catch the Word")
		minigame_filter.select(0)
		minigame_filter.item_selected.emit(0)
	DirAccess.remove_absolute(source_path)
	_authorize_mock_teacher()


func _test_delete() -> void:
	var button := _find(board, ["DeleteAllButton", "DeleteAllDataButton"]) as Button
	if button == null:
		return
	_authorize_mock_teacher()
	var first := _find(board, ["DeleteFirstOverlay"]) as Control
	var first_cancel := _delete_first_button(first, "CANCEL")
	var first_continue := _delete_first_button(first, "SHOW FINAL CONFIRMATION")
	_check(first != null and first_cancel != null and first_continue != null,
		"Delete All has a custom, editor-authored first overlay with two native buttons")
	_check(_find(board, ["DeleteFirstWarning"]) == null,
		"Obsolete Godot ConfirmationDialog is physically removed")
	if first == null or first_cancel == null or first_continue == null:
		return
	var overlay := _find(board, ["DeleteFinalOverlay"]) as Control
	var final_button := _find(board, ["FinalDeleteButton"]) as Button
	var cancel_button := _find(board, ["FinalCancelButton"]) as Button
	var confirmation_input := _find(board, ["TypedConfirmationEdit"]) as LineEdit
	_check(overlay != null and final_button != null and cancel_button != null
		and confirmation_input != null,
		"Second confirmation overlay, typed phrase and Cancel/Delete buttons are editor-authored")
	if overlay == null or final_button == null or cancel_button == null or confirmation_input == null:
		return
	var before: int = client.call("count", "delete_all_data")
	button.pressed.emit()
	_check(first.visible and not overlay.visible,
		"Delete All first opens the custom warning only; does not execute deletion")
	_check(int(client.call("count", "delete_all_data")) == before,
		"Opening Delete All cannot delete records")
	first_cancel.pressed.emit()
	_check(int(client.call("count", "delete_all_data")) == before
		and _count_rows() == 1 and not first.visible and not overlay.visible,
		"First-stage Cancel closes warning without altering saved results")
	button.pressed.emit()
	first_continue.pressed.emit()
	await process_frame
	_check(not first.visible and overlay.visible,
		"First-stage native continue button switches to a separate final destructive overlay")
	confirmation_input.text = "DELETE ALL DAT"
	confirmation_input.text_changed.emit(confirmation_input.text)
	final_button.pressed.emit()
	_check(int(client.call("count", "delete_all_data")) == before,
		"Wrong typed deletion phrase cannot trigger mutation")
	_check(final_button.disabled, "Delete confirmation action remains disabled for incorrect phrase")
	cancel_button.pressed.emit()
	_check(not overlay.visible and int(client.call("count", "delete_all_data")) == before,
		"Cancel from final overlay revokes confirmation and keeps data intact")
	_check(confirmation_input.text.is_empty() and final_button.disabled,
		"Final-stage Cancel clears typed confirmation and disabled state")
	button.pressed.emit()
	first_continue.pressed.emit()
	await process_frame
	_check(confirmation_input.text.is_empty() and final_button.disabled,
		"Reopened confirmation never retains previously typed content")
	confirmation_input.text = "DELETE ALL DATA"
	confirmation_input.text_changed.emit(confirmation_input.text)
	_check(not final_button.disabled, "Exact DELETE ALL DATA phrase enables final confirmation")
	final_button.pressed.emit()
	var challenge_req: Dictionary = client.call("find_pending", "request_delete_all_challenge")
	_check(not challenge_req.is_empty(), "Confirmed deletion first fetches one-time challenge")
	_check(int(client.call("count", "delete_all_data")) == before,
		"Typed phrase alone cannot delete before nonce arrives")
	_check(client.call("reply", "request_delete_all_challenge", {
		"ok": false, "status": 403, "error": "unauthorized", "data": null,
	}), "Unauthorized challenge is rejected")
	_check(int(client.call("count", "delete_all_data")) == before,
		"Unauthorized challenge never issues destructive endpoint call")
	button.pressed.emit()
	first_continue.pressed.emit()
	await process_frame
	confirmation_input.text = "DELETE ALL DATA"
	confirmation_input.text_changed.emit(confirmation_input.text)
	final_button.pressed.emit()
	_check(client.call("reply", "request_delete_all_challenge", {
		"ok": true, "status": 200,
		"data": {"challenge": "QA-ONLY-NONCE", "confirmation_phrase": "DELETE ALL DATA"},
	}), "Server returns fresh one-time challenge nonce")
	var delete_req: Dictionary = client.call("find_pending", "delete_all_data")
	_check(not delete_req.is_empty(), "Delete requires both typed phrase and server challenge")
	var args: Dictionary = delete_req.get("args", {})
	_check(String(args.get("confirmation", "")) == "DELETE ALL DATA"
		and String(args.get("nonce", "")) == "QA-ONLY-NONCE",
		"Delete posts exact confirmation phrase plus matching nonce, no shortcuts")
	_check(client.call("reply", "delete_all_data", {
		"ok": false, "status": 503, "error": "database_unavailable", "data": null,
	}), "Failed deletion can return from the backend")
	_check(_count_rows() == 1, "Failed deletion preserves existing scores and no false success")
	var status := _find(board, ["EmptyNotice"]) as AcceptDialog
	_check(status != null and status.dialog_text.contains("failed"),
		"Failed deletion displays failure rather than a destructive success")
	var before_fetches: int = client.call("count", "get_leaderboard")
	button.pressed.emit()
	first_continue.pressed.emit()
	await process_frame
	confirmation_input.text = "DELETE ALL DATA"
	confirmation_input.text_changed.emit(confirmation_input.text)
	final_button.pressed.emit()
	client.call("reply", "request_delete_all_challenge", {
		"ok": true, "status": 200,
		"data": {"challenge": "QA-ONLY-NONCE-2", "confirmation_phrase": "DELETE ALL DATA"},
	})
	_check(client.call("reply", "delete_all_data", {
		"ok": true, "status": 200, "data": {"students_deleted": 1, "scores_deleted": 1},
	}), "Confirmed backend delete response is received")
	_check(int(client.call("count", "get_leaderboard")) == before_fetches + 1,
		"Only confirmed deletion refreshes leaderboard state")
	var success_overlay := _find(board, ["DeleteSuccessOverlay"]) as Control
	var success_message := _find(board, ["SuccessMessage"]) as Label
	var success_okay := _find(board, ["SuccessOkayButton"]) as Button
	_check(success_overlay != null and success_overlay.visible and success_message != null
		and success_message.text.contains("Deleted 1 student profiles and 1 saved scores")
		and success_okay != null and not status.visible,
		"Confirmed backend deletion shows wood-board success with actual counts, not old dark notice")
	if success_okay != null:
		success_okay.pressed.emit()
		_check(not success_overlay.visible and not status.visible,
			"Custom green OK dismisses completed-delete art without opening the old dialog")
	_check(int(client.call("mutation_count")) >= 1,
		"Mock observes endpoint intent without altering any PostgreSQL tables")


func _test_stale_callbacks() -> void:
	# A response to a management request is allowed to arrive after navigation,
	# but must never resurrect a previous screen or write a CSV after route exit.
	_authorize_mock_teacher()
	var export_button := _find(board, ["ExportCsvButton"]) as Button
	var export_picker := _find(board, ["ExportDatabaseCsvDialog"]) as FileDialog
	var import_button := _find(board, ["ImportCsvButton"]) as Button
	var import_picker := _find(board, ["ImportCsvDialog"]) as FileDialog
	if export_button == null or export_picker == null or import_button == null or import_picker == null:
		return
	export_button.pressed.emit()
	export_picker.file_selected.emit(ProjectSettings.globalize_path(STALE_EXPORT_PATH))
	export_picker.hide()
	_check(not (client.call("find_pending", "export_data_csv") as Dictionary).is_empty(),
		"Export request may be outstanding while teacher navigates away")
	# Explicitly return to Main, simulating Back without any file write.
	app.call("_return_to_main")
	await process_frame
	var initial_fetches: int = client.call("count", "get_leaderboard")
	_check(client.call("reply", "export_data_csv", {
		"ok": true, "status": 200,
		"data": {"csv": VALID_CSV, "students": 1, "scores": 1},
	}), "Late authorized export reply can arrive after leaving Leaderboard")
	_check(not FileAccess.file_exists(STALE_EXPORT_PATH),
		"Stale export response does not write an unattended file after navigation")
	_check(String(app.get("current_route")) == "main",
		"Stale export response cannot change current route")
	_check(int(client.call("count", "get_leaderboard")) == initial_fetches,
		"Stale export does not trigger an unrelated leaderboard refresh")
	# Navigate back for a pending import, then abandon it before the reply.
	(app.get_node("MainLayer/LeftMenu/Leaderboard") as Button).pressed.emit()
	await process_frame
	board = app.get("active_panel") as Control
	_authorize_mock_teacher()
	import_button = _find(board, ["ImportCsvButton"]) as Button
	import_picker = _find(board, ["ImportCsvDialog"]) as FileDialog
	var file := FileAccess.open(STALE_IMPORT_PATH, FileAccess.WRITE)
	if file == null:
		_check(false, "Isolated stale-import CSV can be opened")
		return
	file.store_string(VALID_CSV)
	file.close()
	import_button.pressed.emit()
	import_picker.file_selected.emit(ProjectSettings.globalize_path(STALE_IMPORT_PATH))
	import_picker.hide()
	_approve_import_review(board, ProjectSettings.globalize_path(STALE_IMPORT_PATH))
	_check(not (client.call("find_pending", "import_data_csv") as Dictionary).is_empty(),
		"Import validation may still be in flight when teacher leaves the scene")
	app.call("_return_to_main")
	await process_frame
	initial_fetches = client.call("count", "get_leaderboard")
	_check(client.call("reply", "import_data_csv", {
		"ok": true, "status": 200,
		"data": {"students_created": 1, "scores_imported": 1},
	}), "Backend may finish import after the old panel was abandoned")
	_check(String(app.get("current_route")) == "main"
		and app.get("active_panel") == null,
		"Stale import callback cannot restore abandoned Leaderboard or claim UI success")
	_check(int(client.call("count", "get_leaderboard")) == initial_fetches,
		"Stale import response cannot fetch/replace rankings in a different screen")


func _count_rows() -> int:
	var container := board.get_node_or_null("%ScoreRows") as VBoxContainer
	return container.get_child_count() if container != null else -1


func _approve_import_review(parent: Control, chosen_path: String) -> void:
	## Exercise the native Confirmed signal rather than calling production
	## import methods or backend mock endpoints directly. Real teacher action
	## cannot send CSV until this visible second dialog is explicitly accepted.
	var review := _find(parent, ["ImportReviewDialog"]) as ConfirmationDialog
	_check(review != null, "Import confirmation dialog exists before acceptance")
	if review == null:
		return
	var writes_before: int = client.call("count", "import_data_csv")
	_check(review.visible and review.dialog_text.contains(chosen_path.get_file()),
		"Teacher sees exact selected filename in the second CSV confirmation")
	_check(String(parent.get("_pending_import_path")) == chosen_path,
		"Review stages exact selected CSV path without dispatching request")
	_check(int(client.call("count", "import_data_csv")) == writes_before,
		"No API import request happens before second confirmation is accepted")
	review.confirmed.emit()
	review.hide()
	_check(int(client.call("count", "import_data_csv")) == writes_before + 1,
		"Clicking confirmed review is the single trigger for import API validation")
	_check(String(parent.get("_pending_import_path")).is_empty() and not review.visible,
		"Accepted import clears staged path and closes second confirmation")


func _authorize_mock_teacher() -> void:
	if not is_instance_valid(board):
		return
	client.set("admin_available", true)
	app.call("_load_database_leaderboard")
	_check(client.call("reply", "get_leaderboard", {
		"ok": true, "status": 200,
		"data": {"leaderboard": [{"student_id": "ID-1",
			"student_name": "Ada, \"Quoted\"", "grade_section": "Grade 5",
			"minigame": "Catch the Word", "game_style": "Noun", "game_mode": "Seconds",
			"difficulty": "Easy", "score": 7}]},
	}, "leaderboard"), "Admin mock authorizes Main Menu to reload real leaderboard rows")
	_check(bool(board.get("_context").get("teacher_authorized", false)),
		"Main Menu propagates only locally verified admin capability into leaderboard")


func _find(parent: Node, alternatives: Array[String]) -> Node:
	for name in alternatives:
		var node := parent.find_child(name, true, false)
		if node != null:
			return node
	return null


func _delete_first_button(overlay: Control, caption: String) -> Button:
	if overlay == null:
		return null
	# Captions are baked into the user-supplied original PNG button artwork;
	# the native Godot buttons intentionally have no text overlay.
	var node_name := "FirstCancelButton" if caption == "CANCEL" else "FirstContinueButton"
	return overlay.find_child(node_name, true, false) as Button


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("CSV / DELETE QA: FAIL ", description)


func _finish() -> void:
	for filename in [IMPORT_PATH, LEGACY_IMPORT_PATH, EXPORT_PATH, FILTERED_PATH, STALE_EXPORT_PATH, STALE_IMPORT_PATH]:
		if FileAccess.file_exists(filename):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(filename))
	if is_instance_valid(app):
		app.call("_return_to_main")
		app.queue_free()
		await process_frame
		await process_frame
	print("POSTGRES CSV DELETE QA: ", "PASS" if failures.is_empty() else "FAIL",
		" (%d assertions, %d failures)" % [checks, failures.size()])
	ProjectSettings.set_setting("kilos/recovery_test_directory", "")
	quit(0 if failures.is_empty() else 1)
