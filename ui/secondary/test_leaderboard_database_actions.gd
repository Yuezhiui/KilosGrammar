extends SceneTree

# Isolated UI/signal regression. No PostgreSQL call or database writes occur.
# Optional graphical capture: CAPTURE_LEADERBOARD_TRANSFER=1
const LEADERBOARD := preload("res://ui/secondary/leaderboard.tscn")
const CONFIRMATION := "DELETE ALL DATA"

var checks := 0
var issues: Array[String] = []
var imports: Array[String] = []
var exports: Array[String] = []
var deletions: Array[String] = []
var _files: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var board := LEADERBOARD.instantiate() as Control
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame

	var original := board.get_node("%DownloadButton") as Button
	var import_button := board.get_node_or_null("%ImportCsvButton") as Button
	var export_button := board.get_node_or_null("%ExportCsvButton") as Button
	var delete_button := board.get_node_or_null("%DeleteAllButton") as Button
	var imports_dialog := board.get_node_or_null("%ImportCsvDialog") as FileDialog
	var review_import := board.get_node_or_null("%ImportReviewDialog") as ConfirmationDialog
	var exports_dialog := board.get_node_or_null("%ExportDatabaseCsvDialog") as FileDialog
	var first_warning := board.get_node_or_null("%DeleteFirstWarning") as ConfirmationDialog
	var final_overlay := board.get_node_or_null("%DeleteFinalOverlay") as Control
	var edit := board.get_node_or_null("%TypedConfirmationEdit") as LineEdit
	var final_button := board.get_node_or_null("%FinalDeleteButton") as Button
	var cancel_button := board.get_node_or_null("%FinalCancelButton") as Button
	var status := board.get_node_or_null("%TransferStatus") as Label
	var filters := [board.get_node_or_null("%StyleFilter"), board.get_node_or_null("%ModeFilter"), board.get_node_or_null("%DifficultyFilter")]
	var new_buttons := [import_button, export_button, delete_button]
	for obsolete in ["FiltersToggle", "FiltersArt", "MoreFiltersPanel", "CloseMoreFilters"]:
		_check(board.find_child(obsolete, true, false) == null,
			"FILTERS and popover physically removed: " + obsolete)
	_check(not original.is_visible_in_tree() and board.has_method("request_filtered_csv_export"),
		"hidden filtered CSV remains accessible through explicit host API")
	for item in [import_button, export_button, delete_button]:
		_check(item is Button and item.is_visible_in_tree(), "permanent native action is visible")
		_check(item.focus_mode == Control.FOCUS_ALL, "action accessible by keyboard")
		_check(item.get_global_rect().size.x >= 44.0 and item.get_global_rect().size.y >= 44.0, "button large enough for classroom use")
	_check(not original.is_visible_in_tree(), "obsolete secondary Download CSV has no visible or clickable hitbox")
	for selector in filters:
		_check(selector is OptionButton and selector.item_count > 1, "existing leaderboard filter preserved")
	for i in range(new_buttons.size()):
		var action := new_buttons[i] as Button
		for j in range(i + 1, new_buttons.size()):
			_check(not action.get_global_rect().intersects((new_buttons[j] as Button).get_global_rect()), "new drag/drop action hitboxes do not overlap")
		_check(not original.is_visible_in_tree(), "new actions are not obscured by hidden filtered Download")
		var prior_position: Vector2 = action.position
		action.position += Vector2(5, 2)
		await process_frame
		_check(action.position.distance_to(prior_position + Vector2(5, 2)) < 0.5, "new action can be moved in the editor without runtime coordinates")
		action.position = prior_position
	_check((board.get_node("%SaveCsvDialog") as FileDialog).file_mode == FileDialog.FILE_MODE_SAVE_FILE, "legacy filtered Download uses Save File dialog")
	_check(imports_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE and imports_dialog.access == FileDialog.ACCESS_FILESYSTEM, "Import uses Windows-compatible filesystem open dialog")
	_check(review_import.ok_button_text == "CONFIRM IMPORT", "import requires a second deliberate confirmation")
	_check(exports_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE and exports_dialog.access == FileDialog.ACCESS_FILESYSTEM, "Full export uses Windows-compatible filesystem save dialog")
	_check(first_warning.dialog_text.contains("ALL student profiles") and first_warning.dialog_text.contains("ALL completed scores"), "stage-one warning explains both deletion scopes")
	_check(final_overlay.get_node("ConfirmPanel/WarningText").text.contains("ALL STUDENT PROFILES") and final_overlay.get_node("ConfirmPanel/WarningText").text.contains("ALL COMPLETED SCORES"), "stage-two warning repeats irreversible scope")
	_check(not final_overlay.visible and final_button.disabled, "delete overlay initially hidden and confirmation locked")

	board.database_import_csv_requested.connect(func(path: String) -> void: imports.append(path))
	board.database_export_csv_requested.connect(func(path: String) -> void: exports.append(path))
	board.database_delete_all_requested.connect(func(value: String) -> void: deletions.append(value))

	# No teacher verification -> import and deletion refuse to proceed.
	import_button.pressed.emit()
	delete_button.pressed.emit()
	_check(not imports_dialog.visible and not first_warning.visible, "teacher-only import and delete blocked without authority")
	_check(imports.is_empty() and deletions.is_empty(), "unauthorized actions emit no database request")
	first_warning.confirmed.emit()
	_check(not final_overlay.visible, "forged first-stage confirmation cannot bypass authorization")
	board.call("_on_final_delete_pressed")
	_check(deletions.is_empty(), "direct final callback cannot bypass two stages")

	board.set_context({"teacher_authorized": true, "database_connected": true})
	delete_button.pressed.emit()
	_check(first_warning.visible, "authorized delete opens stage-one warning")
	first_warning.canceled.emit()
	_check(not final_overlay.visible and deletions.is_empty(), "canceling stage one emits no delete")
	delete_button.pressed.emit()
	first_warning.confirmed.emit()
	_check(final_overlay.visible and final_button.disabled, "stage two requires typed text")
	if OS.get_environment("CAPTURE_LEADERBOARD_TRANSFER") == "1" and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var final_screenshot := ProjectSettings.globalize_path("res://ui/secondary/_leaderboard_delete_confirmation_review.png")
		_check(root.get_texture().get_image().save_png(final_screenshot) == OK, "typed delete overlay captured in graphical renderer")
		print("DELETE CONFIRMATION REVIEW SCREENSHOT: ", final_screenshot)
	edit.text = "DELETE ALL"
	edit.text_changed.emit(edit.text)
	_check(final_button.disabled, "partial typed confirmation cannot authorize deletion")
	board.call("_on_final_delete_pressed")
	_check(deletions.is_empty(), "direct callback refuses partial confirmation")
	cancel_button.pressed.emit()
	_check(not final_overlay.visible and edit.text.is_empty(), "cancel clears confirmation and closes overlay")
	board.call("_on_final_delete_pressed")
	_check(deletions.is_empty(), "post-cancel callback cannot delete")
	delete_button.pressed.emit()
	first_warning.confirmed.emit()
	edit.text = CONFIRMATION
	edit.text_changed.emit(edit.text)
	_check(not final_button.disabled, "exact phrase enables final button only after both stages")
	final_button.pressed.emit()
	_check(deletions == [CONFIRMATION], "one and only one delete signal emits exact confirmation string")
	_check(not final_overlay.visible and final_button.disabled, "successful dispatch resets confirmation")
	final_button.pressed.emit()
	_check(deletions.size() == 1, "double-click cannot duplicate a delete request")
	board.set_transfer_status("Backend rejected delete: teacher permissions required", false)
	_check(status.text.contains("Backend rejected") and not board.get("_transfer_pending"), "backend failure status clears pending state")

	var csv_header := "student_id,student_name,grade_section,game_style,game_mode,difficulty,score\n"
	var valid_file := _make_csv("valid", csv_header + "KG-01,Student A,Grade 2,Noun,Seconds,Easy,12\n")
	var bad_formula := _make_csv("formula", csv_header + "KG-02,\"=HYPERLINK(1)\",Grade 3,Noun,Seconds,Easy,10\n")
	var bad_columns := _make_csv("columns", csv_header + "KG-03,Student B\n")
	var bad_header := _make_csv("no_id", "student_name,student_id,grade_section,game_style,game_mode,difficulty,score\nStudent C,KG-05,Grade 5,Noun,Seconds,Easy,18\n")
	var fake_extension := _make_csv("extension", csv_header + "KG-04,Student D,Grade 4,Noun,Seconds,Easy,17\n", ".txt")
	var import_selected: String = valid_file
	_check(board.call("_validate_import_csv", valid_file) == "", "valid student CSV accepted for backend validation")
	for path in [bad_formula, bad_columns, bad_header, fake_extension]:
		_check(not String(board.call("_validate_import_csv", path)).is_empty(), "unsafe CSV rejected before backend")
	imports_dialog.file_selected.emit(bad_formula)
	imports_dialog.file_selected.emit(bad_columns)
	_check(imports.is_empty(), "bad CSV selections never emit an import request")
	imports_dialog.file_selected.emit(import_selected)
	_check(imports.is_empty() and review_import.visible, "valid CSV opens confirmation without dispatching import")
	review_import.canceled.emit()
	_check(imports.is_empty() and not review_import.visible, "canceling CSV review never emits a mutation")
	imports_dialog.file_selected.emit(import_selected)
	review_import.confirmed.emit()
	_check(imports == [valid_file] and board.get("_transfer_pending"), "teacher-confirmed CSV dispatched once as selected path")
	board.set_transfer_pending("Database checking imported rows...")
	_check(board.get("_transfer_pending") and status.text.contains("checking"), "intermediate import progress does not release pending lock")
	_check(import_button.disabled and export_button.disabled and delete_button.disabled, "all transfer buttons disabled throughout pending operation")
	board.set_context({"teacher_authorized": false, "database_connected": false})
	_check(board.get("_transfer_pending") and import_button.disabled and delete_button.disabled, "health/auth refresh cannot unlock pending operation")
	imports_dialog.file_selected.emit(import_selected)
	_check(imports.size() == 1, "pending transfer blocks double-import")
	board.set_transfer_status("Imported 1 student", true)
	_check(status.text == "Imported 1 student" and not board.get("_transfer_pending"), "import success status is shown")
	_check(not import_button.disabled and not export_button.disabled and not delete_button.disabled, "transfer buttons recover after completion")
	board.set_context({"teacher_authorized": false, "database_connected": true})
	imports_dialog.file_selected.emit(valid_file)
	_check(imports.size() == 1, "teacher loss revokes CSV import even if dialog was open")

	# Full export should be independent of the visible leaderboard filters.
	var export_path := ProjectSettings.globalize_path("user://leaderboard_full_export_qa.csv")
	export_button.pressed.emit()
	_check(exports_dialog.visible, "Export opens filesystem Save File dialog")
	exports_dialog.file_selected.emit(export_path)
	_check(exports == [export_path], "full export emits user path exactly once")
	_check(status.text.contains("ALL student profiles") and status.text.contains("completed scores"), "full export scope explicitly says ALL records")
	board.set_transfer_pending("Database assembling complete student backup...")
	_check(board.get("_transfer_pending"), "intermediate full export progress retains pending lock")
	_check(not FileAccess.file_exists(export_path), "UI export did not fabricate database output")
	board.set_transfer_status("Database unavailable: export failed", false)
	_check(status.text.contains("failed") and not board.get("_transfer_pending"), "failed export displays server error and unlocks UI")
	exports_dialog.file_selected.emit(ProjectSettings.globalize_path("user://bad_export.txt"))
	_check(exports.size() == 1, "bad extension never reaches backend export")

	var hostile := {"student_id": "=1+2", "student_name": "+CMD", "grade": "@bad",
		"game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 42}
	board.set_context({"leaderboard_rows": [hostile]})
	var old_csv := _make_csv("legacy", "")
	board.call("_write_csv", old_csv)
	var escaped := FileAccess.get_file_as_string(old_csv)
	_check(escaped.contains("\"'=1+2\"") and escaped.contains("\"'+CMD\"") and escaped.contains("\"'@bad\""), "original filtered Download CSV neutralizes Excel formula prefixes")
	_check((board.get("_visible_rows") as Array).size() == 1, "existing filters and row rendering remain functional")

	if OS.get_environment("CAPTURE_LEADERBOARD_TRANSFER") == "1" and DisplayServer.get_name() != "headless":
		board.set_context({"leaderboard_rows": [], "database_connected": true})
		board.set_transfer_status("Database tools available for teacher use.", true)
		await RenderingServer.frame_post_draw
		var screenshot := ProjectSettings.globalize_path("res://ui/secondary/_leaderboard_transfer_review.png")
		_check(root.get_texture().get_image().save_png(screenshot) == OK, "editor-authored action screenshot captured")
		print("LEADERBOARD REVIEW SCREENSHOT: ", screenshot)

	for filepath in _files:
		DirAccess.remove_absolute(filepath)
	board.queue_free()
	await process_frame
	if issues.is_empty():
		print("PASS leaderboard database actions: %d checks" % checks)
		quit(0)
	else:
		for issue in issues:
			push_error(issue)
		print("FAIL leaderboard database actions: %d failures / %d checks" % [issues.size(), checks])
		quit(1)


func _make_csv(name: String, contents: String, extension: String = ".csv") -> String:
	var path := ProjectSettings.globalize_path("user://_leaderboard_transfer_%s_%d%s" % [name, Time.get_ticks_usec(), extension])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(contents)
		f.close()
	_files.append(path)
	return path


func _check(passed: bool, description: String) -> void:
	checks += 1
	if not passed:
		issues.append(description)
