extends SceneTree

# Synthetic, camera-free, database-free coverage of the seven columns and the
# Downloads-default native Windows CSV chooser. No files are read or written.
const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const HEADER_WIDTH_IN_PNG := 1227.0
const COLUMN_STARTS_IN_PNG := [32.0, 183.0, 543.0, 667.0, 827.0, 982.0]
const LABEL_NAMES := ["StudentId", "StudentName", "Grade", "GameStyle", "GameMode", "Difficulty"]
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	for viewport in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = viewport
		root.content_scale_size = viewport
		var board := BOARD.instantiate() as Control
		for node_name in ["SaveCsvDialog", "ImportCsvDialog", "ExportDatabaseCsvDialog"]:
			var authored := board.get_node(node_name) as FileDialog
			_check(authored.use_native_dialog, node_name + " opts into the OS-native picker in .tscn")
		root.add_child(board)
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		board.set_context({"database_connected": true, "leaderboard_rows": [
			{"student_id": "KG-042", "student_name": "SAMPLE STUDENT", "grade": "5 - ROSE",
			"minigame": "Catch the Word", "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 1660.0}
		]})
		await process_frame
		await process_frame
		var header := board.get_node("TableHeaderArt") as TextureRect
		var content := board.get_node("TableContent") as Control
		var rows := board.get_node("%ScoreRows") as VBoxContainer
		_check(rows.get_child_count() == 1, str(viewport) + " one data row drawn")
		if rows.get_child_count() == 1:
			var row := rows.get_child(0) as Control
			_check(row.get_global_rect().size.x <= content.get_global_rect().size.x + 2.0,
				str(viewport) + " row stays inside authored table viewport")
			var header_rect := header.get_global_rect()
			for index in LABEL_NAMES.size():
				var label := row.get_node(LABEL_NAMES[index]) as Label
				var expected: float = header_rect.position.x + header_rect.size.x * (float(COLUMN_STARTS_IN_PNG[index]) / HEADER_WIDTH_IN_PNG)
				_check(absf(label.get_global_rect().position.x - expected) <= 3.6 * float(viewport.x) / 1280.0,
					str(viewport) + " " + LABEL_NAMES[index] + " aligns to header caption start")
			var score := row.get_node("Score") as Label
			var expected_right := header_rect.position.x + header_rect.size.x * (1191.0 / HEADER_WIDTH_IN_PNG)
			_check(absf(score.get_global_rect().end.x - expected_right) <= 3.8 * float(viewport.x) / 1280.0,
				str(viewport) + " Score aligns to header caption right edge")
			_check(score.text == "1660", str(viewport) + " database score displays as a whole number without .0")
			var font := score.get_theme_font("font")
			var rendered_width := font.get_string_size(score.text, HORIZONTAL_ALIGNMENT_LEFT, -1, score.get_theme_font_size("font_size")).x
			_check(rendered_width <= score.size.x + 1.0, str(viewport) + " decimal score is not clipped")
		for node_name in ["SaveCsvDialog", "ImportCsvDialog", "ExportDatabaseCsvDialog"]:
			var dialog := board.get_node(node_name) as FileDialog
			_check(dialog.use_native_dialog == (OS.get_name() == "Windows" and DisplayServer.get_name() != "headless"),
				str(viewport) + " " + node_name + " uses native Windows picker in real graphics mode")
			_check(dialog.access == FileDialog.ACCESS_FILESYSTEM, str(viewport) + " " + node_name + " uses host filesystem")
			_check(dialog.file_mode == (FileDialog.FILE_MODE_OPEN_FILE if node_name == "ImportCsvDialog" else FileDialog.FILE_MODE_SAVE_FILE),
				str(viewport) + " " + node_name + " uses correct open/save mode")
			if DirAccess.dir_exists_absolute(downloads):
				_check(dialog.current_dir.replace("\\", "/") == downloads.replace("\\", "/"),
					str(viewport) + " " + node_name + " starts in actual Windows Downloads folder")
				dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
				board.call("_set_csv_start_directory", dialog)
				_check(dialog.current_dir.replace("\\", "/") == downloads.replace("\\", "/"),
					str(viewport) + " " + node_name + " resets Downloads on each new open")
		board.queue_free()
		await process_frame
	print("LEADERBOARD NATIVE DIALOG + ROW ALIGNMENT: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", reason)
