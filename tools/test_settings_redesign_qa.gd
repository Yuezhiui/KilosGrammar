extends SceneTree
const SETTINGS := preload("res://ui/secondary/settings.tscn")
const PREFS := preload("res://ui/secondary/settings.gd")
const OUT := "user://_qa_settings_audio_only"
var failures: Array[String] = []
func _initialize() -> void:
    call_deferred("_run")
func _check(ok: bool, why: String) -> void:
    if not ok: failures.append(why)
func _run() -> void:
    var config_path := ProjectSettings.globalize_path("user://kilos_settings.cfg")
    var existed := FileAccess.file_exists(config_path)
    var original := FileAccess.get_file_as_bytes(config_path) if existed else PackedByteArray()
    var old_mode := DisplayServer.window_get_mode()
    var original_buses := {}
    for bus in ["Master", "KilosMusic", "KilosSFX"]:
        var index := AudioServer.get_bus_index(bus)
        if index >= 0: original_buses[bus] = [AudioServer.get_bus_volume_db(index), AudioServer.is_bus_mute(index)]
    var probe := ConfigFile.new()
    for bus in ["Master", "KilosMusic", "KilosSFX"]: probe.set_value("audio", bus, 37.0)
    probe.set_value("audio", "mute", true)
    probe.set_value("display", "fullscreen", false)
    _check(probe.save(config_path) == OK, "cannot write temporary QA preferences")
    PREFS.restore_saved_preferences()
    for bus in original_buses:
        var idx := AudioServer.get_bus_index(bus)
        _check(absf(db_to_linear(AudioServer.get_bus_volume_db(idx)) - 0.37) < 0.005, bus + " persisted volume")
    _check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "persisted mute")
    if DisplayServer.get_name() != "headless":
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
        for resolution in [Vector2i(875,500), Vector2i(1280,720), Vector2i(1920,1080)]:
            DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
            DisplayServer.window_set_size(resolution)
            root.size = resolution
            root.content_scale_size = resolution
            for tab in ["settings"]:
                var scene := SETTINGS.instantiate() as Control
                root.add_child(scene)
                scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
                await process_frame
                scene.call("_show_audio_display")
                await process_frame
                await RenderingServer.frame_post_draw
                _check(scene.get("_active_tab") == tab
                    and scene.find_child("SidebarPanel", true, false) == null
                    and scene.find_child("ControlsPage", true, false) == null
                    and scene.find_child("CameraPage", true, false) == null,
                    "only authored Audio & Display is present")
                var path := ProjectSettings.globalize_path(OUT.path_join("settings_%s_%dx%d.png" % [tab,resolution.x,resolution.y]))
                _check(root.get_texture().get_image().save_png(path) == OK, "capture " + path)
                print("CAPTURED ", path)
                root.remove_child(scene)
                scene.queue_free()
                await process_frame
    for bus in original_buses:
        var idx := AudioServer.get_bus_index(bus)
        AudioServer.set_bus_volume_db(idx, original_buses[bus][0])
        AudioServer.set_bus_mute(idx, original_buses[bus][1])
    DisplayServer.window_set_mode(old_mode)
    if existed:
        var file := FileAccess.open(config_path, FileAccess.WRITE)
        if file != null: file.store_buffer(original)
        else: failures.append("cannot restore original preferences")
    else:
        DirAccess.remove_absolute(config_path)
    if failures.is_empty():
        print("SETTINGS QA PASS")
        quit(0)
    else:
        for f in failures: push_error(f)
        quit(1)
