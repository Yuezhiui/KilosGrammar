extends SceneTree
## Read-only DEMO 8-column fixture -> actual native Leaderboard panel.
## No MainMenu, local API, camera, PostgreSQL, class data, or destructive calls.

const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const SAMPLE := "res://docs/examples/kilosgrammar_demo_scores_20261030.csv"
const CSV_FIELDS := [
	"student_id", "student_name", "grade_section", "minigame", "game_style",
	"game_mode", "difficulty", "score"]
var checks := 0
var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var ui := BOARD.instantiate() as Control
	root.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	_check(ui.has_method("_validate_import_csv"), "Native leaderboard has import validator")
	var filename := ProjectSettings.globalize_path(SAMPLE)
	_check(FileAccess.file_exists(SAMPLE), "Checked-in demo canonical CSV exists")
	if not FileAccess.file_exists(SAMPLE):
		_finish(ui)
		return
	var validation := String(ui.call("_validate_import_csv", filename))
	_check(validation.is_empty(), "Real Godot Import CSV prevalidation accepts exact game fixture: " + validation)

	var file := FileAccess.open(SAMPLE, FileAccess.READ)
	_check(file != null, "Sample fixture opens read-only")
	if file == null:
		_finish(ui)
		return
	_check(file.get_csv_line() == PackedStringArray(CSV_FIELDS), "Exact canonical eight-column import header")
	var rows: Array[Dictionary] = []
	var no_score := 0
	var found_game: Dictionary = {}
	var expected_student: Dictionary = {}
	while not file.eof_reached():
		var fields := file.get_csv_line()
		if fields.size() == 1 and fields[0] == "":
			continue
		_check(fields.size() == CSV_FIELDS.size(), "Each demo CSV line has 8 columns")
		if fields.size() != CSV_FIELDS.size():
			continue
		if not expected_student.has(fields[0]):
			expected_student[fields[0]] = true
		if fields[7].is_empty():
			no_score += 1
			continue
		found_game[String(fields[3])] = true
		rows.append({
			"student_id": fields[0], "student_name": fields[1], "grade_section": fields[2],
			"minigame": fields[3], "game_style": fields[4],
			"game_mode": fields[5], "difficulty": fields[6], "score": int(fields[7]),
		})
	file.close()
	_check(expected_student.size() == 7 and no_score == 1 and rows.size() == 18,
		"Real game sample contains 7 fake profiles, 1 profile-only, 18 scores")
	_check(found_game.size() == 3, "Score rows use all three real minigames")

	ui.set_context({"database_connected": true, "database_loading": false, "leaderboard_rows": rows})
	var container := ui.get_node("%ScoreRows") as VBoxContainer
	_check(container.get_child_count() == 18, "Native leaderboard renders 18 scored rows")
	var sorted: Array = ui.get("_all_rows")
	_check(sorted.size() == 18 and int(sorted[0].get("score", -1)) == 600,
		"Native sorting places 600-point score first, no invented 19th score")
	_check((container.get_child(0).get_node("Score") as Label).text == "600",
		"Native score row shows 600 exactly")
	for game in ["Catch the Word", "Balloon Popping", "Human Plane"]:
		_check(bool(ui.call("set_minigame_filter", game)), "Host accepts real " + game + " filter")
		_check(container.get_child_count() == 6, "Host filtering leaves six " + game + " scores")
	_check(bool(ui.call("set_minigame_filter", "ALL MINIGAMES")), "Reset all minigames")
	_check(container.get_child_count() == 18, "Reset restores all 18 scored rows")
	var styles := ui.get_node("%StyleFilter") as OptionButton
	styles.select(1) # NOUN
	styles.item_selected.emit(1)
	_check(container.get_child_count() == 4, "Native NOUN filter yields four demo scores")
	styles.select(0)
	styles.item_selected.emit(0)
	_check(container.get_child_count() == 18, "ALL STYLES restores all scores")

	# Historical profile-only rows are visible in full CSV backups, not rankings.
	ui.set_context({"database_connected": true, "database_loading": false, "leaderboard_rows": []})
	_check(container.get_child_count() == 0 and
		(ui.get_node("%EmptyMessage") as Label).text == "No completed scores saved yet",
		"Live leaderboard communicates honest empty-score state without fabricating a profile rank")
	_finish(ui)


func _check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		errors.append(message)
		printerr("DEMO LEADERBOARD QA FAIL: ", message)


func _finish(ui: Control) -> void:
	ui.queue_free()
	print("DEMO CSV LEADERBOARD UI: %s (%d checks, %d failures)" % [
		"PASS" if errors.is_empty() else "FAIL", checks, errors.size()])
	quit(0 if errors.is_empty() else 1)
