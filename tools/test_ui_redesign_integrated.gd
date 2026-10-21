extends SceneTree

# Integrated 17-route redesign smoke and graphical captures.
# Headless: Godot --headless --path . --script res://tools/test_ui_redesign_integrated.gd
# Graphical: Godot --path . --rendering-method gl_compatibility --script res://tools/test_ui_redesign_integrated.gd
const ROUTES := ["tutorial_home", "tutorial_practice", "tutorial_complete", "grammar_guide", "student_setup", "play_activity", "play_topic", "play_difficulty", "camera_check", "calibration", "ready", "gameplay", "pause", "results", "leaderboard", "settings", "credits"]
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const OUTPUT := "res://showcase/ui_redesign_20261016/final"
var failures: Array[String] = []
var measured := 0
var captured := 0
var route_timings: Array[String] = []
var focus_issues: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://main_menu.tscn") as PackedScene
    if packed == null:
        push_error("Missing main_menu.tscn")
        quit(1)
        return
    var graphical := DisplayServer.get_name() != "headless"
    if graphical:
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    for viewport_size in SIZES:
        root.size = viewport_size
        root.content_scale_size = Vector2i(1280, 720)
        if graphical:
            DisplayServer.window_set_size(viewport_size)
        var app := packed.instantiate() as Control
        root.add_child(app)
        # Main Menu deliberately forces fullscreen in production. Override only
        # inside screenshot QA after _ready, then restore physical capture size.
        if graphical:
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
            # 1920x1080 decorated windows are constrained by the desktop work
            # area; borderless preserves exact capture dimensions in QA only.
            DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
            DisplayServer.window_set_size(viewport_size)
            await process_frame
            print("QA_WINDOW viewport=", viewport_size, " mode=", DisplayServer.window_get_mode(), " physical=", DisplayServer.window_get_size(), " logical=", root.content_scale_size)
        await create_timer(1.3).timeout
        if graphical:
            await _capture(viewport_size, "main")
        for route in ROUTES:
            var started := Time.get_ticks_msec()
            app.call("_on_panel_requested", route, {})
            await process_frame
            await process_frame
            var panel := app.get("active_panel") as Control
            if route == "gameplay":
                var game := panel.get("active_game") as Control if panel != null else null
                var baseline: float = game.call("_character_baseline_y") if game != null and game.has_method("_character_baseline_y") else -1.0
                print("GAMEPLAY_GEOMETRY viewport=", viewport_size, " root=", root.size, " content_scale=", root.content_scale_size, " app=", app.size, " wrapper=", panel.size if panel != null else Vector2.ZERO, " active_game=", game.size if game != null else Vector2.ZERO, " baseline=", baseline)
            if String(app.get("current_route")) != route or panel == null:
                failures.append("%s %s: route failed" % [viewport_size, route])
                continue
            if not panel.has_signal("requested"):
                failures.append("%s %s: missing navigation signal" % [viewport_size, route])
            var elapsed := Time.get_ticks_msec() - started
            if elapsed > 1500:
                failures.append("%s %s: slow navigation %dms" % [viewport_size, route, elapsed])
            route_timings.append("%s,%s,%d" % [str(viewport_size), route, elapsed])
            var focusable := _count_focusable(panel)
            if focusable == 0:
                focus_issues.append("%s %s: no visible keyboard-focusable control" % [viewport_size, route])
            measured += 1
            if graphical:
                await _capture(viewport_size, route)
        if graphical and viewport_size == Vector2i(875, 500):
            await _capture_populated_results(app, viewport_size)
        app.call("_return_to_main")
        var music := app.get("title_music_player") as AudioStreamPlayer
        if music != null:
            music.stop()
            music.stream = null
        app.queue_free()
        await process_frame
        await process_frame
        print("CHECK %s: 17 routes" % viewport_size)
    await create_timer(0.5).timeout
    print("TIMINGS viewport,route,load_ms")
    for item in route_timings:
        print("TIMING ", item)
    for issue in focus_issues:
        print("FOCUS_REVIEW ", issue)
    print("FOCUS_REVIEW_COUNT ", focus_issues.size())
    if failures.is_empty():
        print("PASS integrated UI: %d route/viewport checks; %d graphical captures" % [measured, captured])
        quit(0)
    else:
        for failure in failures:
            push_error(failure)
        print("FAIL integrated UI: %d failures / %d checks" % [failures.size(), measured])
        quit(1)

func _capture(viewport_size: Vector2i, key: String) -> void:
    await RenderingServer.frame_post_draw
    var img := root.get_texture().get_image()
    var path := ProjectSettings.globalize_path(OUTPUT.path_join("%s_%dx%d.png" % [key, viewport_size.x, viewport_size.y]))
    if img.get_width() != viewport_size.x or img.get_height() != viewport_size.y:
        failures.append("Screenshot dimension mismatch %s: actual %dx%d" % [key, img.get_width(), img.get_height()])
    var err := img.save_png(path)
    if err == OK:
        captured += 1
        print("CAPTURED ", path)
    else:
        failures.append("Cannot save %s: %d" % [path, err])



func _count_focusable(node: Node) -> int:
    var count := 0
    if node is Control:
        var control := node as Control
        if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and control.size.x > 0 and control.size.y > 0:
            count += 1
    for child in node.get_children():
        count += _count_focusable(child)
    return count

func _capture_populated_results(app: Control, viewport_size: Vector2i) -> void:
    var fixture := {"student_id": "KG-2026-001", "student_name": "Alex Rivera", "grade_section": "Grade 4 - Sampaguita", "game_mode": "Seconds", "difficulty": "Normal", "topic": "Noun", "game_style": "Noun", "activity": "Catch the Word", "score": 5000, "round_completed": true, "demo_mode": true}
    app.call("_on_panel_requested", "results", fixture)
    await process_frame
    await process_frame
    var panel := app.get("active_panel") as Control
    if panel == null or String(app.get("current_route")) != "results":
        failures.append("Populated Results failed to open")
        return
    var frame := Rect2(Vector2.ZERO, root.get_visible_rect().size)
    for control_name in ["RetryButton", "MainButton"]:
        var button := panel.find_child(control_name, true, false) as Button
        if button == null or not button.is_visible_in_tree():
            failures.append("Populated Results missing visible " + control_name)
        else:
            print("RESULTS_BUTTON_RECT ", control_name, " ", button.get_global_rect(), " viewport ", viewport_size)
            if not frame.encloses(button.get_global_rect().grow(-1.0)):
                failures.append("Populated Results offscreen button " + control_name)
    await _capture(viewport_size, "results_populated")
