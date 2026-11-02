extends SceneTree

# Scene-only layout/behavior regression. No service, camera, or file writes.
const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const SIZES := [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]
const ROWS := [
	{"student_id":"ID-09","student_name":"Eve","grade_section":"Grade 4 - Ruby","game_style":"Noun","game_mode":"Seconds","difficulty":"Easy","score":9},
	{"student_id":"ID-02","student_name":"Ana","grade_section":"Grade 2 - Orchid","game_style":"Verb","game_mode":"Lives","difficulty":"Hard","score":81},
	{"student_id":"ID-11","student_name":"Bea","grade_section":"Grade 3 - Jade","game_style":"Adverb","game_mode":"Seconds","difficulty":"Normal","score":42},
]
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("NEW LEADERBOARD BUTTONS FAIL: ", why)

func _option(sort: OptionButton, name: String) -> bool:
	for i in sort.item_count:
		if sort.get_item_text(i).strip_edges().to_upper() == name or (name == "STUDENT ID" and sort.get_item_text(i).strip_edges().to_upper() == "STUDENT ID A-Z"):
			sort.select(i)
			return true
	return false

func _run() -> void:
	for resolution in SIZES:
		root.size = resolution
		root.content_scale_size = resolution
		var board := BOARD.instantiate() as Control
		root.add_child(board)
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		board.set_context({"leaderboard_rows":ROWS,"database_connected":true,"teacher_authorized":true})
		await process_frame
		var tag := str(resolution)
		var grade := board.get_node_or_null("%GradeLevelFilter") as OptionButton
		var section := board.get_node_or_null("%SectionFilter") as OptionButton
		var search := board.get_node_or_null("%StudentSearch") as LineEdit
		var sort := board.get_node_or_null("%ScoreSort") as OptionButton
		_check(grade != null and section != null and not grade.is_visible_in_tree() and not section.is_visible_in_tree(),tag+" removed grade/section row remains hidden")
		_check(search != null and sort != null and search.is_visible_in_tree() and sort.is_visible_in_tree(),tag+" search and artwork sort visible")
		_check(search.size.x >= 220.0 and sort.size.x >= 180.0,tag+" search/sort use available horizontal space")
		_check(sort.item_count >= 5,tag+" five authored sorting choices")
		_check(sort.get_theme_stylebox("normal") is StyleBoxTexture,tag+" sort control retains texture skin")
		for name in ["SCORE","HIGHEST SCORE","LOWEST SCORE","STUDENT ID","GRADE LEVEL"]:
			_check(_option(sort,name),tag+" named sort choice "+name)
			board.call("_on_filter_changed")
			var visible: Array = board.get("_visible_rows")
			_check(visible.size() == 3,tag+" sort keeps all three records "+name)
			if visible.size() == 3:
				var expected := "ID-09" if name == "LOWEST SCORE" else "ID-02"
				_check(str(visible[0].get("student_id")) == expected,tag+" true data ordering "+name)
		search.text = "ID-11"
		board.call("_on_filter_changed")
		_check((board.get("_visible_rows") as Array).size() == 1,tag+" text search remains functional")
		var events := [0,0,0]
		board.database_import_xlsx_requested.connect(func(_path: String): events[0] += 1)
		board.database_export_xlsx_requested.connect(func(_path: String): events[1] += 1)
		board.database_delete_all_requested.connect(func(_phrase: String): events[2] += 1)
		for node in ["ImportCsvButton","ExportCsvButton","DeleteAllButton"]:
			var action := board.get_node_or_null("%"+node) as Button
			_check(action != null,tag+" existing management action "+node)
			if action != null:
				var art := action.get_theme_stylebox("normal") as StyleBoxTexture
				_check(art != null and art.texture != null,tag+" editor-authored replacement texture "+node)
		var incoming := board.get_node("%ImportCsvDialog") as FileDialog
		var outgoing := board.get_node("%ExportDatabaseCsvDialog") as FileDialog
		_check(incoming.filters.size() == 1 and String(incoming.filters[0]).contains("*.xlsx") and outgoing.filters.size() == 1 and String(outgoing.filters[0]).contains("*.xlsx"),tag+" original buttons retain XLSX-only dialogs")
		board.call("_on_final_delete_pressed")
		_check(events == [0,0,0],tag+" direct delete cannot bypass two-stage protection")
		board.queue_free()
		await process_frame
	print("NEW LEADERBOARD BUTTONS: %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(0 if failures == 0 else 1)
