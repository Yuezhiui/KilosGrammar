extends SceneTree

# UI-only regression: no database requests, no file writes and no deletion.
const SCENE := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const BACKEND_ERROR := "Database operation failed: Local administrator authorization required"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("LEADERBOARD ADMIN NOTICE FAILED: ", label)


func _case(size: Vector2i) -> void:
	root.size = size
	root.content_scale_size = size
	var panel := SCENE.instantiate() as Control
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.set_context({"database_connected": true, "teacher_authorized": true})
	for index in range(3):
		await process_frame
	var tag := str(size)
	var modal := panel.get_node("%NoticeOverlay") as Control
	var label := panel.get_node("%NoticeMessage") as Label
	var okay := panel.get_node("%NoticeOkayButton") as Button
	_check(modal != null and label != null and okay != null,
		tag + " authored illustrated notice, message and dismiss control exist")
	if modal == null or label == null or okay == null:
		panel.queue_free()
		await process_frame
		return
	_check(label.get_theme_font_size("font_size") >= 19,
		tag + " illustrated notice keeps readable large text")
	_check(not okay.disabled, tag + " original accessible okay action remains enabled")
	var signals := {"imports": 0, "exports": 0, "deletions": 0}
	panel.database_import_xlsx_requested.connect(func(_path: String) -> void: signals["imports"] += 1)
	panel.database_export_xlsx_requested.connect(func(_path: String) -> void: signals["exports"] += 1)
	panel.database_delete_all_requested.connect(func(_phrase: String) -> void: signals["deletions"] += 1)

	# Pressing each real action is sufficient to set the status context.
	# No files are selected and no database mutations can be dispatched.
	(panel.get_node("%ImportCsvButton") as Button).pressed.emit()
	# Close the mocked file selector before simulating a backend response;
	# two simultaneous exclusive Windows dialogs are invalid UI state.
	(panel.get_node("%ImportCsvDialog") as FileDialog).hide()
	panel.set_transfer_status(BACKEND_ERROR, false)
	_check(label.text.contains("Excel import was blocked")
			and label.text.contains("No records were imported")
			and label.text.contains("administrator authorization"),
		tag + " rejected import explains authorization and zero import")
	modal.hide()

	(panel.get_node("%ExportCsvButton") as Button).pressed.emit()
	(panel.get_node("%ExportDatabaseCsvDialog") as FileDialog).hide()
	panel.set_transfer_status(BACKEND_ERROR, false)
	_check(label.text.contains("Full database Excel export was blocked")
			and label.text.contains("No workbook was created"),
		tag + " rejected full export explains authorization and no output")
	modal.hide()

	(panel.get_node("%DeleteAllButton") as Button).pressed.emit()
	var warning := panel.get_node("%DeleteFirstOverlay") as Control
	_check(warning.visible, tag + " protected delete still opens first warning stage")
	panel.set_transfer_status(BACKEND_ERROR, false)
	_check(not modal.visible and String(panel.get("_queued_transfer_notice")).contains("No student profiles or scores were deleted"),
		tag + " backend rejection is queued behind delete warning, not overlaid")
	(panel.get_node("%FirstCancelButton") as Button).pressed.emit()
	_check(not warning.visible and label.text.contains("DELETE ALL DATA was blocked")
			and label.text.contains("No student profiles or scores were deleted"),
		tag + " canceled delete warning shows readable authorization rejection")
	_check(not (panel.get_node("%DeleteFinalOverlay") as Control).visible,
		tag + " final destructive confirmation stayed closed")
	_check(signals == {"imports": 0, "exports": 0, "deletions": 0},
		tag + " no mock action dispatched any import/export/delete")
	modal.hide()

	panel.set_transfer_status("Database operation failed: disk not ready", false)
	_check(label.text == "Database operation failed: disk not ready",
		tag + " unrelated backend failure retains its exact original explanation")
	panel.queue_free()
	await process_frame


func _run() -> void:
	for size in SIZES:
		await _case(size)
	print("LEADERBOARD ADMIN NOTICE: %s checks=%d failures=%d renderer=%s" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)
