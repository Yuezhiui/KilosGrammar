extends SceneTree

# UI-only: verifies CSV-only action geometry and import/delete notices without
# connecting to PostgreSQL, accessing the network, or dispatching data changes.
const SCENE := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const GENERIC_DISCONNECT := "Connection lost. Any pending import/delete outcome is unknown; check saved records after reconnection."

var checks := 0
var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(result: bool, description: String) -> void:
	checks += 1
	if not result:
		errors.append(description)
		printerr("LEADERBOARD OFFLINE/LAYOUT FAILURE: ", description)


func _test_viewport(viewport: Vector2i) -> void:
	root.size = viewport
	root.content_scale_size = viewport
	var board := SCENE.instantiate() as Control
	board.set_context({"leaderboard_rows": [], "database_connected": false, "teacher_authorized": false})
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in range(3):
		await process_frame
	var key := str(viewport)
	var modal := board.get_node("%NoticeOverlay") as Control
	var table := board.get_node("TableContent") as Control
	var board_art := board.get_node("BoardArtwork") as Control
	var bottom_actions: Array[Control] = [
		board.get_node("%ImportCsvButton"), board.get_node("%ExportCsvButton"),
		board.get_node("%DeleteAllButton")]
	_check(board.get_node_or_null("%DatabaseStatusNote") == null
		and board.get_node_or_null("%SelectedStudentLabel") == null,
		key + " no obsolete offline footer or selected-student status row")

	board.set_context({"leaderboard_rows": [], "database_connected": false, "teacher_authorized": false})
	board.set_transfer_status(GENERIC_DISCONNECT)
	_check(not modal.visible, key + " initial offline never opens an unearned import/delete modal")
	_check((board.get_node("%EmptyMessage") as Label).text.contains("database unavailable"),
		key + " empty table explains current database availability without a bottom banner")
	_check(not board.get("_transfer_pending"), key + " initial health notice does not lock buttons")

	var art := board_art.get_global_rect()
	var table_rect := table.get_global_rect()
	var first_row := bottom_actions[0].get_global_rect()
	_check(first_row.position.y >= table_rect.end.y + 8.0 * viewport.x / 1280.0,
		key + " scroll area ends above management buttons")
	for control in bottom_actions:
		var rect: Rect2 = (control as Control).get_global_rect()
		_check(rect.position.x >= art.position.x + 8 and rect.end.x <= art.end.x - 8,
			key + " " + control.name + " stays horizontally inside panel")
		_check(rect.position.y > table_rect.end.y and rect.end.y <= art.end.y - 10.0,
			key + " " + control.name + " clears scoreboard and lower panel border")
	for first in range(bottom_actions.size()):
		for second in range(first + 1, bottom_actions.size()):
			_check(not bottom_actions[first].get_global_rect().intersects(bottom_actions[second].get_global_rect()),
				key + " CSV action buttons %s and %s do not overlap" % [
					bottom_actions[first].name, bottom_actions[second].name])

	board.set_context({"database_connected": true, "teacher_authorized": true})
	_check(not modal.visible, key + " reconnect leaves no stale offline popup")
	board.set("_last_management_action", "import")
	board.set_transfer_pending("Valid CSV import dispatched to backend")
	board.set_transfer_status(GENERIC_DISCONNECT)
	_check(modal.visible and modal.get_node("%NoticeMessage").text.contains("Excel import")
		and modal.get_node("%NoticeMessage").text.contains("outcome is unknown")
		and not modal.get_node("%NoticeMessage").text.contains("succeeded"),
		key + " interrupted in-flight import still warns that records need checking")
	_check(not board.get("_transfer_pending"), key + " interrupted import clears UI progress lock")
	modal.hide()
	board.set("_last_management_action", "delete")
	board.set_transfer_pending("Delete dispatched to backend")
	board.set_transfer_status(GENERIC_DISCONNECT)
	_check(modal.visible and modal.get_node("%NoticeMessage").text.contains("DELETE ALL DATA")
		and modal.get_node("%NoticeMessage").text.contains("outcome is unknown"),
		key + " interrupted in-flight deletion warns without asserting deletion")
	modal.hide()
	board.set("_last_management_action", "export")
	board.set_transfer_pending("CSV export requested")
	board.set_transfer_status(GENERIC_DISCONNECT)
	_check(not modal.visible, key + " interrupted read-only CSV export never falsely claims a write")
	board.queue_free()
	await process_frame


func _run() -> void:
	for viewport in VIEWPORTS:
		await _test_viewport(viewport)
	print("LEADERBOARD OFFLINE/LAYOUT: %s checks=%d failures=%d backend_io=none" % [
		"PASS" if errors.is_empty() else "FAIL", checks, errors.size()])
	quit(0 if errors.is_empty() else 1)
