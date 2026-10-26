extends SceneTree
const OUT := "res://showcase/ui_redesign_20261016/window_intro_qa"
func _initialize() -> void:
    call_deferred("_run")
func _run() -> void:
    var graphical := DisplayServer.get_name() != "headless"
    print("WINDOW_PROBE initial_mode=", DisplayServer.window_get_mode(), " physical=", DisplayServer.window_get_size(), " logical=", root.content_scale_size, " config_mode=", ProjectSettings.get_setting("display/window/size/mode"))
    var cfg := ConfigFile.new()
    var cfgpath := ProjectSettings.globalize_path("user://kilos_settings.cfg")
    var status := cfg.load(cfgpath)
    print("WINDOW_PROBE prefs_path=",cfgpath," status=",status," fullscreen_key=",cfg.get_value("display","fullscreen","ABSENT"))
    if graphical:
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
    var packed := load("res://main_menu.tscn") as PackedScene
    var app := packed.instantiate() as Control
    root.add_child(app)
    await process_frame
    print("WINDOW_PROBE after_ready_mode=",DisplayServer.window_get_mode()," window=",DisplayServer.window_get_size()," app=",app.size," root=",root.size)
    var failures: Array[String] = []
    if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
        failures.append("Main did not enforce fullscreen after ready")
    if app.get("grammar_tiles").size() != 7:
        failures.append("Expected seven original GRAMMAR tile controls")
    if not (app.get("logo_group") as Control).visible:
        failures.append("Original Kilos logo group hidden")
    if (app.get("falling_layer") as Control).modulate.a < 0.95:
        failures.append("Falling words unexpectedly translucent")
    var tile := (app.get("grammar_tiles") as Array)[0] as Control
    var tile_start := tile.position
    if graphical:
        for i in range(3):
            await create_timer([0.20,1.4,4.5][i]).timeout
            await RenderingServer.frame_post_draw
            var filename := OUT.path_join(["main_early.png","main_mid.png","main_late.png"][i])
            root.get_texture().get_image().save_png(ProjectSettings.globalize_path(filename))
            print("WINDOW_PROBE CAPTURE ",filename," mode=",DisplayServer.window_get_mode()," app=",app.size," falling=",app.get_node("FallingLayer").get_child_count())
    if tile.position.distance_to(tile_start) < 0.05:
        failures.append("GRAMMAR tile did not animate")
    if app.get_node("FallingLayer").get_child_count() <= 1:
        failures.append("Falling words did not spawn")
    for nodepath in ["MainLayer/LeftMenu/Leaderboard", "MainLayer/LeftMenu/Settings", "MainLayer/CenterMenu/Tutorial", "MainLayer/CenterMenu/Play", "MainLayer/CenterMenu/Quit"]:
        var control := app.get_node_or_null(nodepath) as Control
        if control == null or not control.is_visible_in_tree():
            failures.append("Missing visible main button " + nodepath)
    var music := app.get("title_music_player") as AudioStreamPlayer
    if music != null:
        music.stop()
        music.stream = null
    app.queue_free()
    await process_frame
    await create_timer(0.5).timeout
    for issue in failures:
        push_error("WINDOW_PROBE_FAIL " + issue)
    print("WINDOW_PROBE RESULT ", "PASS" if failures.is_empty() else "FAIL", " issues=", failures.size())
    quit(0 if failures.is_empty() else 1)
