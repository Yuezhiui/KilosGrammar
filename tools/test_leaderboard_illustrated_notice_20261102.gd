extends SceneTree

# UI-only: verifies editor-owned illustration, readable status and safe modal
# precedence. No file picker selection, network, database, or deletion writes.
const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("ILLUSTRATED NOTICE FAIL: ", description)

func _run() -> void:
	for viewport in SIZES:
		root.size = viewport
		root.content_scale_size = viewport
		var board := BOARD.instantiate() as Control
		root.add_child(board)
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		board.set_context({"leaderboard_rows": [], "database_connected": true,
			"teacher_authorized": true})
		await process_frame
		var overlay := board.get_node_or_null("%NoticeOverlay") as Control
		var message := board.get_node_or_null("%NoticeMessage") as Label
		var okay := board.get_node_or_null("%NoticeOkayButton") as Button
		_check(overlay != null and message != null and okay != null,
			str(viewport) + " notice controls are editor-authored")
		if overlay != null and message != null and okay != null:
			var art_found := false
			for item in overlay.find_children("*", "TextureRect", true, false):
				if item is TextureRect and (item as TextureRect).texture != null:
					art_found = true
					break
			_check(art_found, str(viewport) + " actual notice artwork texture in authored scene")
			_check(message.get_theme_font_size("font_size") >= 19,
				str(viewport) + " notice text remains large and readable")
			_check(not okay.disabled, str(viewport) + " OK dismissal action enabled")
			var dispatches := [0, 0, 0]
			board.database_import_xlsx_requested.connect(func(_path: String): dispatches[0] += 1)
			board.database_export_xlsx_requested.connect(func(_path: String): dispatches[1] += 1)
			board.database_delete_all_requested.connect(func(_phrase: String): dispatches[2] += 1)
			board.set_transfer_status("Database operation failed: disk not ready", false)
			_check(overlay.visible and message.text == "Database operation failed: disk not ready",
				str(viewport) + " exact backend diagnostic preserved in illustrated notice")
			okay.pressed.emit()
			_check(not overlay.visible, str(viewport) + " illustrated OK dismisses notice")
			board.call("_begin_delete_all")
			var first := board.get_node("%DeleteFirstOverlay") as Control
			_check(first.visible, str(viewport) + " original two-stage Delete warning still starts")
			board.set_transfer_status("Database operation failed: Local administrator authorization required")
			_check(not overlay.visible and String(board.get("_queued_transfer_notice")).contains("No student profiles or scores were deleted"),
				str(viewport) + " notice queues behind active destructive confirmation")
			board.call("_cancel_delete_all")
			_check(not first.visible and dispatches == [0, 0, 0],
				str(viewport) + " no import/export/delete dispatch from notice actions")
		board.queue_free()
		await process_frame
	print("ILLUSTRATED NOTICE: %s checks=%d failures=%d" % [
		"PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
