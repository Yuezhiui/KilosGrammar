extends SceneTree

## Non-destructive, camera-free UI regression tests. All exports are observed
## as signals; no file is written and no database request is executed.
const SCENE := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const DATA: Array[Dictionary] = [
	{"student_id": "ID-004", "student_name": "Alice Cruz", "grade_section": "Grade 4 - Ruby", "minigame": "Catch the Word", "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 24},
	{"student_id": "ID-004", "student_name": "Alice Cruz", "grade_section": "Grade 4 - Ruby", "minigame": "Human Plane", "game_style": "Verb", "game_mode": "Lives", "difficulty": "Hard", "score": 17},
	{"student_id": "ID-005", "student_name": "Bob Santos", "grade_section": "Grade 4 Section Jade", "minigame": "Balloon Popping", "game_style": "Verb", "game_mode": "Seconds", "difficulty": "Normal", "score": 38},
	{"student_id": "ID-006", "student_name": "Carla Cruz", "grade_section": "Grade 5 - Ruby", "minigame": "Catch the Word", "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Normal", "score": 55},
	{"student_id": "ID-007", "student_name": "Devon Ramos", "grade_section": "G6 - Section Mapagkalinga", "minigame": "Human Plane", "game_style": "Adverb", "game_mode": "Lives", "difficulty": "Hard", "score": 71},
	{"student_id": "ID-008", "student_name": "Eve Santos", "grade_section": "qq", "minigame": "Catch the Word", "game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy", "score": 4}
]

var total := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(yes: bool, context: String) -> void:
	total += 1
	if not yes:
		failures.append(context)


func _select_text(option: OptionButton, text: String) -> bool:
	for i in option.item_count:
		if option.get_item_text(i) == text:
			option.select(i)
			return true
	return false


func _rows(board: Control) -> Array:
	return board.get("_visible_rows")


func _click(at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	root.push_input(move, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = at
		event.global_position = at
		root.push_input(event, true)


func _check_filters(board: Control, size_key: String) -> void:
	var grade := board.get_node("%GradeLevelFilter") as OptionButton
	var section := board.get_node("%SectionFilter") as OptionButton
	var search := board.get_node("%StudentSearch") as LineEdit
	var sort := board.get_node("%ScoreSort") as OptionButton
	_check(grade.item_count == 4 and grade.get_item_text(1) == "Grade 4" and grade.get_item_text(2) == "Grade 5"
		and grade.get_item_text(3) == "Grade 6" or grade.item_count == 5,
		size_key + " grade options include saved grade values and unspecified")
	_check(_select_text(grade, "Grade 4"), size_key + " Grade 4 exists")
	board.call("_on_grade_changed")
	_check(_rows(board).size() == 3, size_key + " Grade 4 shows 3 matching score rows")
	_check(_select_text(section, "Ruby"), size_key + " Ruby section selectable")
	board.call("_on_filter_changed")
	_check(_rows(board).size() == 2, size_key + " Grade 4 Ruby includes only Alice's two scores")
	_check(_select_text(grade, "Grade 5"), size_key + " Grade 5 exists")
	board.call("_on_grade_changed")
	_check(section.selected == 0 and _rows(board).size() == 1,
		size_key + " changing grade resets unavailable section and shows Carla")
	_check(_select_text(grade, "All Grades"), size_key + " all-grades selectable")
	board.call("_on_grade_changed")
	search.text = "sAnToS"
	board.call("_on_filter_changed")
	_check(_rows(board).size() == 2, size_key + " search is case-insensitive across student names")
	search.text = "ID-004"
	board.call("_on_filter_changed")
	_check(_rows(board).size() == 2, size_key + " exact ID substring searches 2 scores")
	search.text = ""
	board.call("_on_filter_changed")
	sort.select(4)
	board.call("_on_filter_changed")
	_check(_rows(board).size() == 6 and str(_rows(board)[0].get("student_id")) == "ID-008",
		size_key + " lowest-score sorting displays minimum first")
	sort.select(0)
	board.call("_on_filter_changed")
	_check(str(_rows(board)[0].get("student_id")) == "ID-007",
		size_key + " highest-score sorting restores maximum first")
	sort.select(3)
	board.call("_on_filter_changed")
	_check(str(_rows(board)[0].get("student_id")) == "ID-005"
		and str(_rows(board)[2].get("student_id")) == "ID-004",
		size_key + " grade-and-section sorting groups Grade 4 Jade before Ruby")


func _check_signals(board: Control, size_key: String) -> void:
	var student_requests: Array = []
	var grade_requests: Array = []
	var canonical_csv: Array = []
	var deleted: Array = []
	board.database_export_student_requested.connect(func(sid: String, path: String) -> void:
		student_requests.append({"id": sid, "path": path}))
	board.database_export_grade_xlsx_requested.connect(func(path: String) -> void: grade_requests.append(path))
	board.database_export_csv_requested.connect(func(path: String) -> void: canonical_csv.append(path))
	board.database_delete_all_requested.connect(func(phrase: String) -> void: deleted.append(phrase))
	var pull_out := board.get_node("%PullOutStudentButton") as Button
	var xlsx := board.get_node("%ExportGradeXlsxButton") as Button
	_check(pull_out.disabled, size_key + " Pull-Out is disabled before selection")
	board.call("_select_student", "ID-004")
	_check(not pull_out.disabled and not xlsx.disabled,
		size_key + " teacher auth + selection unlock Pull-Out and grouped workbook")
	_check((board.get_node("%SelectedStudentLabel") as Label).text.contains("ID-004"),
		size_key + " selected exact student ID displayed")
	board.call("_choose_student_export")
	board.call("_on_student_export_file_selected", "user://student.csv")
	_check(student_requests.is_empty(), size_key + " rejects .csv path for Excel Pull-Out")
	board.call("_choose_student_export")
	board.call("_select_student", "ID-005")
	board.call("_on_student_export_file_selected", "user://stale.xlsx")
	_check(student_requests.is_empty(),
		size_key + " export chooser cannot silently switch to another student ID")
	board.call("_select_student", "ID-004")
	board.call("_choose_student_export")
	board.call("_on_student_export_file_selected", "user://student.xlsx")
	_check(student_requests.size() == 1 and student_requests[0]["id"] == "ID-004"
		and student_requests[0]["path"] == "user://student.xlsx",
		size_key + " Pull-Out emits exact ID/path, writes nothing locally")
	_check(pull_out.disabled and xlsx.disabled, size_key + " pending export locks both buttons")
	board.set_transfer_status("Simulated authorized export completed.", true)
	board.call("_on_grade_xlsx_file_selected", "user://multi.csv")
	_check(grade_requests.is_empty(), size_key + " rejects CSV as grouped-grade XLSX")
	board.call("_on_grade_xlsx_file_selected", "user://grades.xlsx")
	_check(grade_requests.size() == 1 and grade_requests[0] == "user://grades.xlsx",
		size_key + " grouped-grade export emits exact XLSX destination")
	board.set_transfer_status("Simulated authorized export completed.", true)
	board.call("_on_export_file_selected", "user://backup.csv")
	_check(canonical_csv.size() == 1 and canonical_csv[0] == "user://backup.csv",
		size_key + " existing full database CSV signal preserved")
	board.set_transfer_status("Simulated authorized export completed.", true)
	board.call("_on_final_delete_pressed")
	_check(deleted.is_empty(), size_key + " naked delete callback cannot bypass protected confirmation")
	var context: Dictionary = {"leaderboard_rows": DATA, "database_connected": true,
		"teacher_authorized": false}
	board.set_context(context)
	_check((board.get_node("%PullOutStudentButton") as Button).disabled
		and (board.get_node("%ExportGradeXlsxButton") as Button).disabled,
		size_key + " teacher authorization loss disables protected exports")
	board.call("_on_student_export_file_selected", "user://forbidden.xlsx")
	board.call("_on_grade_xlsx_file_selected", "user://forbidden.xlsx")
	_check(student_requests.size() == 1 and grade_requests.size() == 1,
		size_key + " invoking handlers directly cannot bypass teacher authorization")
	_check(deleted.is_empty(), size_key + " exports cannot mutate student profiles")
	board.set_context({"leaderboard_rows": [], "database_connected": true,
		"teacher_authorized": true})
	_check(not (board.get_node("%ExportGradeXlsxButton") as Button).disabled,
		size_key + " full XLSX export remains available for students with no saved scores")
	board.call("_on_grade_xlsx_file_selected", "user://empty_scoreboard.xlsx")
	_check(grade_requests.size() == 2,
		size_key + " teacher can request full roster XLSX despite empty scoreboard")


func _stress_filters(board: Control, size_key: String) -> void:
	var grade := board.get_node("%GradeLevelFilter") as OptionButton
	var search := board.get_node("%StudentSearch") as LineEdit
	var sort := board.get_node("%ScoreSort") as OptionButton
	for cycle in range(120):
		grade.select(0)
		board.call("_on_grade_changed")
		search.text = "id-004" if cycle % 2 == 0 else ""
		sort.select(cycle % 5)
		board.call("_on_filter_changed")
		_check(_rows(board).size() == (2 if cycle % 2 == 0 else 6),
			size_key + " stress refresh cycle %d respects exact teacher search" % cycle)
		board.call("_select_student", "ID-004")
		_check(String(board.get("_selected_student_id")) == "ID-004",
			size_key + " stress refresh cycle %d keeps eligible selection" % cycle)
	search.text = ""
	sort.select(0)
	board.call("_on_filter_changed")
	board.call("_select_student", "")


func _test_viewport(viewport: Vector2i) -> void:
	root.size = viewport
	root.content_scale_size = viewport
	var board := SCENE.instantiate() as Control
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	board.set_context({"leaderboard_rows": DATA, "database_connected": true,
		"teacher_authorized": true})
	await process_frame
	var key := str(viewport)
	for name in ["GradeLevelFilter", "SectionFilter", "StudentSearch", "ScoreSort",
		"SelectedStudentLabel", "PullOutStudentButton", "ExportGradeXlsxButton"]:
		var control := board.get_node_or_null("%" + name) as Control
		_check(control != null and control.is_visible_in_tree(), key + " visible control " + name)
		if control:
			var rect := control.get_global_rect()
			_check(rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= viewport.x
				and rect.end.y <= viewport.y,
				key + " layout control in viewport " + name)
	_check(_rows(board).size() == DATA.size(), key + " unfiltered all server rows displayed")
	var first_row := (board.get_node("%ScoreRows") as VBoxContainer).get_child(0)
	var name_cell := first_row.get_node("StudentName") as Label
	_click(name_cell.get_global_rect().get_center())
	await process_frame
	_check(String(board.get("_selected_student_id")) == "ID-007",
		key + " mouse click on a real editor-authored score row selects student ID")
	_check_filters(board, key)
	_stress_filters(board, key)
	_check_signals(board, key)
	board.queue_free()
	await process_frame
	await process_frame


func _run() -> void:
	for viewport in SIZES:
		await _test_viewport(viewport)
	for item in failures:
		printerr("TEACHER LEADERBOARD QA FAIL: ", item)
	print("TEACHER LEADERBOARD FILTER/EXPORT QA: %s checks=%d failures=%d backend_io=none" % [
		"PASS" if failures.is_empty() else "FAIL", total, failures.size()])
	quit(0 if failures.is_empty() else 1)
