extends SceneTree

# Isolated UI-only regression. Never instantiate MainMenu, an HTTP client,
# PostgreSQL, or the Windows teacher setup process.
const SCENE := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("LEADERBOARD EDITOR DB SETUP FAIL: ", why)

func _run() -> void:
	for viewport in SIZES:
		root.size = viewport
		root.content_scale_size = viewport
		var board := SCENE.instantiate() as Control
		root.add_child(board)
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		var key := str(viewport)
		var setup := board.get_node_or_null("TableContent/DatabaseSetupButton") as Button
		_check(setup != null, key + " authored setup button exists in TableContent")
		_check(board.has_signal("database_setup_requested"), key + " exposes dedicated secure setup request signal")
		if setup == null or not board.has_signal("database_setup_requested"):
			board.queue_free()
			await process_frame
			continue
		var requests := [0]
		board.database_setup_requested.connect(func(): requests[0] += 1)
		board.set_context({"database_connected": false, "database_setup_required": true,
			"teacher_authorized": false, "leaderboard_rows": []})
		await process_frame
		_check(setup.is_visible_in_tree() and not setup.disabled,
			key + " offline setup-required offers enabled teacher action")
		_check(setup.text.to_upper().contains("SET UP") and setup.text.to_upper().contains("DATABASE"),
			key + " teacher sees meaningful local database setup caption")
		var logical := Rect2(Vector2.ZERO, Vector2(viewport))
		_check(logical.grow(2.0).encloses(setup.get_global_rect()), key + " setup button within viewport")
		var notice := board.get_node_or_null("%NoticeOverlay") as Control
		_check(notice != null and not notice.visible, key + " inactive notice does not cover setup button")
		setup.pressed.emit()
		_check(requests[0] == 1, key + " one legitimate teacher press emits exactly one setup request")
		board.set_context({"database_connected": false, "database_setup_required": false,
			"teacher_authorized": false, "leaderboard_rows": []})
		await process_frame
		_check(not setup.is_visible_in_tree(), key + " offline without setup-required hides action")
		setup.pressed.emit()
		_check(requests[0] == 1, key + " forged hidden press does not emit")
		board.set_context({"database_connected": true, "database_setup_required": true,
			"teacher_authorized": true, "leaderboard_rows": []})
		await process_frame
		_check(not setup.is_visible_in_tree(), key + " connected suppresses setup action")
		setup.pressed.emit()
		_check(requests[0] == 1, key + " connected synthetic press cannot invoke wizard")
		for name in ["ImportCsvButton", "ExportCsvButton", "DeleteAllButton"]:
			var action := board.get_node_or_null("%" + name) as Button
			_check(action != null and action.is_visible_in_tree(), key + " original management button intact: " + name)
		var importer := board.get_node_or_null("%ImportCsvDialog") as FileDialog
		var exporter := board.get_node_or_null("%ExportDatabaseCsvDialog") as FileDialog
		_check(importer != null and exporter != null and importer.filters.size() == 1
			and exporter.filters.size() == 1 and String(importer.filters[0]).contains("*.xlsx")
			and String(exporter.filters[0]).contains("*.xlsx"), key + " original XLSX-only native dialogs unchanged")
		board.queue_free()
		await process_frame
	print("LEADERBOARD EDITOR DB SETUP: %s checks=%d failures=%d backend_io=none" % [
		"PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
