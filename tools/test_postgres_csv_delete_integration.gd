extends SceneTree

## Deliberately runs real editor-authored UI with a NO-SOCKET fake service.
## NEVER connects to PostgreSQL or calls the real local HTTP endpoint.
## godot --headless --path . --script res://tools/test_postgres_csv_delete_integration.gd
const MENU_PATH := "res://tools/test_postgres_csv_delete_menu_fixture.gd"
const SAMPLE_XLSX := "res://docs/examples/KilosGrammar_DEMO_8_Students_Grades_1_to_4_20261102.xlsx"
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
	IMPORT_PATH = qa_storage.path_join("qa_postgres_xlsx_delete_import.xlsx")
	LEGACY_IMPORT_PATH = qa_storage.path_join("qa_postgres_xlsx_delete_legacy_import.xlsx")
	EXPORT_PATH = qa_storage.path_join("qa_postgres_xlsx_delete_export.xlsx")
	FILTERED_PATH = qa_storage.path_join("qa_postgres_csv_delete_filtered.csv")
	STALE_EXPORT_PATH = qa_storage.path_join("qa_postgres_xlsx_delete_stale_export.xlsx")
	STALE_IMPORT_PATH = qa_storage.path_join("qa_postgres_xlsx_delete_stale_import.xlsx")
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
	_check(_find(board, ["SaveCsvDialog"]) == null,
		"Unused filtered Save CSV dialog was deleted")
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
	_check(board.has_method("set_minigame_filter") and board.has_method("_validate_import_xlsx"),
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
	_check(_find(board, ["DownloadButton", "SaveCsvDialog"]) == null,
		"Filtered local CSV download and dialog absent; genuine XLSX-only main controls remain")
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
	var button := _find(board, ["ExportCsvButton"]) as Button
	var chooser := _find(board, ["ExportDatabaseCsvDialog"]) as FileDialog
	_check(button != null and chooser != null, "Original Export button and Save dialog retained")
	if button == null or chooser == null:
		return
	var original_mutations: int = client.call("mutation_count")
	var before: int = client.call("count", "export_data_xlsx")
	_check(chooser.filters.size() == 1 and String(chooser.filters[0]).contains("*.xlsx"),
		"Unchanged Export button opens XLSX-only file picker")
	button.pressed.emit()
	_check(chooser.visible, "Authorized export opens picker")
	chooser.canceled.emit()
	chooser.hide()
	_check(int(client.call("count", "export_data_xlsx")) == before
		and client.call("mutation_count") == original_mutations,
		"Canceled export cannot contact backend or change data")
	chooser.file_selected.emit(ProjectSettings.globalize_path(EXPORT_PATH))
	_check(int(client.call("count", "export_data_xlsx")) == before + 1,
		"Selecting XLSX destination requests guarded report from fake backend")
	_check(not FileAccess.file_exists(EXPORT_PATH), "No Excel workbook written before backend succeeds")
	_check(client.call("reply", "export_data_xlsx", {
		"ok": false, "status": 403, "error": "admin_authorization_required",
		"message": "Teacher permission missing", "data": null,
	}), "Mock backend can deny export despite selected destination")
	_check(not FileAccess.file_exists(EXPORT_PATH), "Denied export leaves no XLSX file")
	var notice := _find(board, ["EmptyNotice"]) as AcceptDialog
	_check(notice != null and notice.dialog_text.contains("failed"),
		"Denied Excel export cannot show false success")
	button.pressed.emit()
	chooser.file_selected.emit(ProjectSettings.globalize_path(EXPORT_PATH))
	var raw := FileAccess.get_file_as_bytes(SAMPLE_XLSX)
	_check(raw.size() > 100 and raw[0] == 80 and raw[1] == 75,
		"Actual grade-tab sample workbook is OOXML ZIP")
	_check(client.call("reply", "export_data_xlsx", {
		"ok": true, "status": 200,
		"data": {"xlsx_base64": Marshalls.raw_to_base64(raw), "students": 8, "scores": 8},
	}), "Mock server XLSX response reaches real MainMenu save callback")
	_check(FileAccess.file_exists(EXPORT_PATH), "Export writes only after valid server response")
	if FileAccess.file_exists(EXPORT_PATH):
		_check(FileAccess.get_file_as_bytes(EXPORT_PATH) == raw,
			"All original four-grade worksheet bytes are preserved through export")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(EXPORT_PATH))
	_check(not notice.dialog_text.contains("failed") and notice.dialog_text.contains("saved"),
		"Successful workbook export displays actual server-acknowledged result")
	_check(client.call("mutation_count") == original_mutations,
		"Excel export remains read-only with zero backend mutations")


func _test_import() -> void:
	var button := _find(board, ["ImportCsvButton"]) as Button
	var picker := _find(board, ["ImportCsvDialog"]) as FileDialog
	var review := _find(board, ["ImportReviewDialog"]) as ConfirmationDialog
	_check(button != null and picker != null and review != null,
		"Three original import UI controls still exist")
	if button == null or picker == null or review == null:
		return
	_check(picker.filters.size() == 1 and String(picker.filters[0]).contains("*.xlsx"),
		"Original Import button exclusively opens XLSX")
	var before: int = client.call("count", "import_data_xlsx")
	button.pressed.emit()
	_check(picker.visible, "Teacher sees Open Excel workbook dialog")
	picker.canceled.emit()
	picker.hide()
	_check(int(client.call("count", "import_data_xlsx")) == before,
		"Cancel picker cannot import")
	_check(not review.visible and String(board.get("_pending_import_path")).is_empty(),
		"Cancel picker leaves no import path")
	var chosen := ProjectSettings.globalize_path(SAMPLE_XLSX)
	_check(String(board.call("_validate_import_xlsx", chosen)).is_empty(),
		"Real grade-separated 8-student XLSX passes local ZIP preflight")
	button.pressed.emit()
	picker.file_selected.emit(chosen)
	picker.hide()
	_check(review.visible and review.dialog_text.contains(chosen.get_file()),
		"Selected actual XLSX filename appears in second consent")
	_check(int(client.call("count", "import_data_xlsx")) == before,
		"Selection without explicit confirmation cannot send workbook")
	review.canceled.emit()
	review.hide()
	_check(int(client.call("count", "import_data_xlsx")) == before
		and String(board.get("_pending_import_path")).is_empty(),
		"Cancel review clears workbook path without mutation")
	button.pressed.emit()
	picker.file_selected.emit(chosen)
	picker.hide()
	_approve_import_review(board, chosen)
	_check(int(client.call("count", "import_data_xlsx")) == before + 1,
		"Confirmed workbook dispatches one API import request")
	var pending: Dictionary = client.call("find_pending", "import_data_xlsx")
	var args: Dictionary = pending.get("args", {})
	var raw: PackedByteArray = Marshalls.base64_to_raw(String(args.get("xlsx_base64", "")))
	_check(raw == FileAccess.get_file_as_bytes(SAMPLE_XLSX),
		"Actual grade-tab workbook bytes passed unchanged to mock server")
	_check(_count_rows() == 1, "Before API reply existing saved scores stay unchanged")
	_check(client.call("reply", "import_data_xlsx", {
		"ok": false, "status": 400, "error": "invalid_xlsx",
		"message": "Unsafe workbook rejected", "data": null,
	}), "Mock server can reject unsafe workbook")
	_check(_count_rows() == 1, "Rejected Excel import does not alter ranks")
	var notice := _find(board, ["EmptyNotice"]) as AcceptDialog
	_check(notice != null and notice.dialog_text.contains("failed"),
		"Rejected import displays failure instead of success")
	button.pressed.emit()
	picker.file_selected.emit(chosen)
	picker.hide()
	_approve_import_review(board, chosen)
	_check(client.call("reply", "import_data_xlsx", {
		"ok": false, "status": 409, "error": "student_exists",
		"message": "Duplicate student identity", "data": null,
	}), "Existing student conflicts remain guarded")
	_check(_count_rows() == 1, "Duplicate-rejected workbook keeps original leaderboard")
	button.pressed.emit()
	picker.file_selected.emit(chosen)
	picker.hide()
	_approve_import_review(board, chosen)
	var fetches: int = client.call("count", "get_leaderboard")
	_check(client.call("reply", "import_data_xlsx", {
		"ok": true, "status": 200,
		"data": {"students_created": 8, "scores_imported": 8},
	}), "Authorized workbook import response accepted")
	_check(int(client.call("count", "get_leaderboard")) == fetches + 1,
		"Successful workbook import refreshes authoritative rankings")
	_check(not notice.dialog_text.contains("failed") and notice.dialog_text.contains("Excel imported"),
		"Success notice only after backend confirms import")
	before = int(client.call("count", "import_data_xlsx"))
	button.pressed.emit()
	picker.file_selected.emit(ProjectSettings.globalize_path(qa_storage.path_join("missing.xlsx")))
	picker.hide()
	_check(int(client.call("count", "import_data_xlsx")) == before
		and not review.visible and String(board.get("_pending_import_path")).is_empty(),
		"Missing selected workbook cannot stage approval or dispatch")


func _test_legacy_import() -> void:
	# Retain hostile/malformed-file and authorization probes. Legacy 7-column
	# XLSX parsing is covered by database/tests/test_grade_xlsx_import_20261102.py.
	var button := _find(board, ["ImportCsvButton"]) as Button
	var picker := _find(board, ["ImportCsvDialog"]) as FileDialog
	var review := _find(board, ["ImportReviewDialog"]) as ConfirmationDialog
	_check(button != null and picker != null and review != null,
		"Legacy and current XLSX use existing safe import controls")
	var before := int(client.call("count", "import_data_xlsx"))
	var bad := FileAccess.open(LEGACY_IMPORT_PATH, FileAccess.WRITE)
	_check(bad != null, "Test-only malformed XLSX can be written in isolated user directory")
	if bad != null:
		bad.store_string(LEGACY_CSV)
		bad.close()
	var chosen := ProjectSettings.globalize_path(LEGACY_IMPORT_PATH)
	_check(not String(board.call("_validate_import_xlsx", chosen)).is_empty(),
		"Renaming raw CSV as XLSX cannot bypass ZIP signature validation")
	button.pressed.emit()
	picker.file_selected.emit(chosen)
	picker.hide()
	_check(not review.visible and int(client.call("count", "import_data_xlsx")) == before,
		"Invalid XLSX never reaches approval or server")
	DirAccess.remove_absolute(chosen)
	_check(not String(board.call("_validate_import_xlsx", chosen)).is_empty(),
		"Deleted XLSX file cannot be silently accepted")
	var good := ProjectSettings.globalize_path(SAMPLE_XLSX)
	board.set_context({"database_connected": true, "teacher_authorized": false})
	button.pressed.emit()
	picker.file_selected.emit(good)
	picker.hide()
	_check(int(client.call("count", "import_data_xlsx")) == before
		and not review.visible and String(board.get("_pending_import_path")).is_empty(),
		"Unauthorized workbook selection never stages or imports")
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
	_authorize_mock_teacher()
	var export_button := _find(board, ["ExportCsvButton"]) as Button
	var export_picker := _find(board, ["ExportDatabaseCsvDialog"]) as FileDialog
	var import_button := _find(board, ["ImportCsvButton"]) as Button
	var import_picker := _find(board, ["ImportCsvDialog"]) as FileDialog
	_check(export_button != null and export_picker != null
		and import_button != null and import_picker != null,
		"Stale-response test uses same three original actions")
	if export_button == null or export_picker == null or import_button == null or import_picker == null:
		return
	export_button.pressed.emit()
	export_picker.file_selected.emit(ProjectSettings.globalize_path(STALE_EXPORT_PATH))
	export_picker.hide()
	_check(not (client.call("find_pending", "export_data_xlsx") as Dictionary).is_empty(),
		"Excel export may remain pending when teacher navigates")
	app.call("_return_to_main")
	await process_frame
	var initial_fetches := int(client.call("count", "get_leaderboard"))
	var raw := FileAccess.get_file_as_bytes(SAMPLE_XLSX)
	_check(client.call("reply", "export_data_xlsx", {
		"ok": true, "status": 200,
		"data": {"xlsx_base64": Marshalls.raw_to_base64(raw), "students": 8, "scores": 8},
	}), "Late XLSX export acknowledgment arrives after leaving scene")
	_check(not FileAccess.file_exists(STALE_EXPORT_PATH),
		"Abandoned export must not write XLSX file")
	_check(String(app.get("current_route")) == "main"
		and int(client.call("count", "get_leaderboard")) == initial_fetches,
		"Late export cannot reopen leaderboard or trigger fetch")
	(app.get_node("MainLayer/LeftMenu/Leaderboard") as Button).pressed.emit()
	await process_frame
	board = app.get("active_panel") as Control
	_authorize_mock_teacher()
	import_button = _find(board, ["ImportCsvButton"]) as Button
	import_picker = _find(board, ["ImportCsvDialog"]) as FileDialog
	var chosen := ProjectSettings.globalize_path(SAMPLE_XLSX)
	import_button.pressed.emit()
	import_picker.file_selected.emit(chosen)
	import_picker.hide()
	_approve_import_review(board, chosen)
	_check(not (client.call("find_pending", "import_data_xlsx") as Dictionary).is_empty(),
		"Authorized workbook import may be pending at scene navigation")
	app.call("_return_to_main")
	await process_frame
	initial_fetches = int(client.call("count", "get_leaderboard"))
	_check(client.call("reply", "import_data_xlsx", {
		"ok": true, "status": 200,
		"data": {"students_created": 8, "scores_imported": 8},
	}), "Import response may arrive after closing its Leaderboard")
	_check(String(app.get("current_route")) == "main"
		and app.get("active_panel") == null,
		"Stale import success cannot restore abandoned screen")
	_check(int(client.call("count", "get_leaderboard")) == initial_fetches,
		"Stale import cannot fetch or overwrite unrelated screen")


func _count_rows() -> int:
	var container := board.get_node_or_null("%ScoreRows") as VBoxContainer
	return container.get_child_count() if container != null else -1


func _approve_import_review(parent: Control, chosen_path: String) -> void:
	var review := _find(parent, ["ImportReviewDialog"]) as ConfirmationDialog
	_check(review != null, "Separate XLSX approval dialog exists")
	if review == null:
		return
	var before := int(client.call("count", "import_data_xlsx"))
	_check(review.visible and review.dialog_text.contains(chosen_path.get_file()),
		"Review shows selected XLSX filename")
	_check(String(parent.get("_pending_import_path")) == chosen_path,
		"Review holds correct XLSX path before approval")
	_check(int(client.call("count", "import_data_xlsx")) == before,
		"No workbook bytes sent before confirmation")
	review.confirmed.emit()
	review.hide()
	_check(int(client.call("count", "import_data_xlsx")) == before + 1,
		"Confirm sends exactly one guarded XLSX request")
	_check(String(parent.get("_pending_import_path")).is_empty() and not review.visible,
		"Accepted workbook clears staged path")


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
