extends SceneTree

# Visual QA for the redesigned Game Over UI. Run with the real Godot renderer:
# Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/capture_results_redesign_20261029.gd
# Does not alter gameplay scenes, student records, or any database.

const RESULTS: PackedScene = preload("res://ui/secondary/results/results.tscn")
const OUTPUT := "res://showcase/results_redesign"
const CASES := [
    {"size": Vector2i(1280, 720), "activity": "Balloon Popping", "mode": "Seconds", "score": 280},
    {"size": Vector2i(1600, 900), "activity": "Catch the Word", "mode": "Lives", "score": 1200},
    {"size": Vector2i(1920, 1080), "activity": "Human Plane", "mode": "Seconds", "score": 700},
]


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("Results visual capture needs the graphical Godot renderer.")
        quit(1)
        return
    var output_dir := ProjectSettings.globalize_path(OUTPUT)
    var mk := DirAccess.make_dir_recursive_absolute(output_dir)
    if mk != OK:
        push_error("Cannot make results capture directory: %s" % output_dir)
        quit(1)
        return
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    for c in CASES:
        var physical: Vector2i = c["size"]
        DisplayServer.window_set_size(physical)
        root.size = physical
        root.content_scale_size = physical
        await process_frame
        await process_frame
        var ui := RESULTS.instantiate() as Control
        root.add_child(ui)
        ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        ui.set_context({
            "activity": c["activity"], "score": c["score"],
            "student_id": "qq", "student_name": "qq", "grade": "Grade 4",
            "game_style": "Noun", "topic": "Noun",
            "game_mode": c["mode"], "difficulty": "Easy",
            "round_completed": true, "score_saved": true, "database_connected": true
        })
        await create_timer(0.2).timeout
        await RenderingServer.frame_post_draw
        var picture := root.get_texture().get_image()
        var slug: String = String(c["activity"]).to_lower().replace(" ", "_")
        var filepath := output_dir.path_join("%s_%dx%d.png" % [slug, physical.x, physical.y])
        var err := picture.save_png(filepath)
        print("RESULTS_PREVIEW %s (%s)" % [filepath, "PASS" if err == OK else str(err)])
        ui.queue_free()
        await process_frame
    quit(0)
