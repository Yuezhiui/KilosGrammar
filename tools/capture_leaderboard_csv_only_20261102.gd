extends SceneTree

# Graphical-only QA; genuine authored scene with offline, unauthorized context.
# No DB client, camera, game router, network calls or project production writes.
const SCENE := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const OUTPUT := "res://showcase/leaderboard-csv-only-20261102"

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    if DisplayServer.get_name() == "headless":
        printerr("Graphical display is required")
        quit(1)
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    var errors := 0
    for size in SIZES:
        DisplayServer.window_set_size(size)
        root.size = size
        root.content_scale_size = size
        await process_frame
        var board := SCENE.instantiate() as Control
        board.set_context({"leaderboard_rows": [], "database_connected": false,
            "teacher_authorized": false})
        root.add_child(board)
        board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        for i in range(5):
            await process_frame
        await RenderingServer.frame_post_draw
        var dest := ProjectSettings.globalize_path(OUTPUT.path_join(
            "leaderboard_csv_only_%dx%d.png" % [size.x, size.y]))
        var result := root.get_texture().get_image().save_png(dest)
        if result != OK:
            errors += 1
            printerr("FAILED to capture ", dest)
        else:
            print("CAPTURED ", dest)
        for name in ["ImportCsvButton", "ExportCsvButton", "DeleteAllButton"]:
            var button := board.get_node_or_null(name) as Button
            print("VISUAL CONTROL ", size, " ", name, " rect=",
                button.get_global_rect() if button != null else "MISSING")
        for gone in ["PullOutStudentButton", "ExportGradeXlsxButton",
                "SelectedStudentLabel", "DatabaseStatusNote"]:
            if board.get_node_or_null(gone) != null:
                errors += 1
                printerr("OBSOLETE NODE STILL PRESENT: ", gone)
        board.queue_free()
        await process_frame
    print("LEADERBOARD CSV-ONLY GRAPHICAL CAPTURE: ", "PASS" if errors == 0 else "FAIL")
    quit(0 if errors == 0 else 1)
