extends SceneTree

# Historical CSV-only fixture migrated to XLSX-only *pickers*, preserving the
# same three authored CSV-icon buttons and protected Delete. No DB writes.
const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const VIEWPORTS := [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]
var checks := 0
var failures := 0

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, description: String) -> void:
    checks += 1
    if not ok:
        failures += 1
        printerr("XLSX THREE BUTTON QA FAIL: ", description)

func _run() -> void:
    for size in VIEWPORTS:
        root.size = size
        root.content_scale_size = size
        var panel := BOARD.instantiate() as Control
        panel.set_context({"database_connected": true, "teacher_authorized": true,
            "leaderboard_rows": [{"student_id":"QA-G2","student_name":"DEMO TEST",
            "grade_section":"Grade 2 - Orchid","minigame":"Catch the Word",
            "game_style":"Noun","game_mode":"Seconds","difficulty":"Easy","score":44}]})
        root.add_child(panel)
        panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        await process_frame
        await process_frame
        var key := str(size)
        for node in ["ImportCsvButton","ExportCsvButton","DeleteAllButton"]:
            _check(panel.get_node_or_null("%"+node) is Button,
                key+" original visible action retained "+node)
        for node in ["ExportGradeXlsxButton","PullOutStudentButton",
                "ExportStudentCsvDialog","ExportGradeXlsxDialog",
                "SelectedStudentLabel","DatabaseStatusNote","SaveCsvDialog"]:
            _check(panel.find_child(node,true,false) == null,
                key+" no extra export/selection/footer control "+node)
        var exporter := panel.get_node("%ExportDatabaseCsvDialog") as FileDialog
        var importer := panel.get_node("%ImportCsvDialog") as FileDialog
        _check(exporter.file_mode == FileDialog.FILE_MODE_SAVE_FILE and
            importer.file_mode == FileDialog.FILE_MODE_OPEN_FILE,
            key+" original buttons open correct save/open pickers")
        for dialog in [exporter, importer]:
            _check(dialog.filters.size() == 1 and
                String(dialog.filters[0]).contains("*.xlsx") and
                not String(dialog.filters[0]).contains("*.csv"),
                key+" picker exclusively XLSX")
        _check(panel.has_signal("database_import_xlsx_requested") and
            panel.has_signal("database_export_xlsx_requested") and
            panel.has_signal("database_delete_all_requested"),
            key+" XLSX import/export and guarded Delete signals")
        var exports: Array[String] = []
        var deletes: Array[String] = []
        panel.database_export_xlsx_requested.connect(func(path: String) -> void: exports.append(path))
        panel.database_delete_all_requested.connect(func(phrase: String) -> void: deletes.append(phrase))
        panel.call("_on_export_file_selected", "user://wrong.csv")
        _check(exports.is_empty(), key+" CSV export rejected")
        panel.set_transfer_status("")
        (panel.get_node("%EmptyNotice") as AcceptDialog).hide()
        panel.call("_on_export_file_selected", "user://fixture.xlsx")
        _check(exports == ["user://fixture.xlsx"], key+" XLSX export signal exactly once")
        panel.call("_on_export_file_selected", "user://repeat.xlsx")
        _check(exports.size() == 1, key+" pending request cannot be duplicated")
        panel.call("_on_final_delete_pressed")
        _check(deletes.is_empty(),key+" Delete cannot bypass two-stage confirmation")
        _check(panel.get_node_or_null("%GradeLevelFilter") is OptionButton and
            panel.get_node_or_null("%SectionFilter") is OptionButton and
            panel.get_node_or_null("%ScoreSort") != null,
            key+" grade/section/sort remain active")
        panel.queue_free()
        await process_frame
    print("XLSX THREE BUTTON SCENE: %s checks=%d failures=%d" %
        ["PASS" if failures == 0 else "FAIL",checks,failures])
    quit(0 if failures == 0 else 1)
