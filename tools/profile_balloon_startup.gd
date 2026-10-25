extends SceneTree

# Measure scene resource parsing, PackedScene instantiation, runtime _ready()
# including raw PNG decoding, and a warm repeated mount.
# Godot --headless --path . --script res://tools/profile_balloon_startup.gd
const SCENE_PATH := "res://ui/minigames/balloon_popping.tscn"
const ART_PATHS := [
    "res://Components/Gameplay/Balloon Popping/Background/0826b13c-250f-42e1-9398-a83d2922a1d8.png",
    "res://Components/Gameplay/Balloon Popping/Background/95ae2a22-302d-48f7-9b5f-e12b0104c822.png",
    "res://Components/Gameplay/Balloon Popping/Balloons/purple.png",
    "res://Components/Gameplay/Balloon Popping/Balloons/green.png",
    "res://Components/Gameplay/Balloon Popping/Balloons/blue.png"
]


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var start_us := Time.get_ticks_usec()
    var scene := ResourceLoader.load(SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
    var cold_ms := _ms(start_us)
    if scene == null:
        push_error("PROFILE: Failed to load PackedScene")
        quit(2)
        return
    var scene_file := FileAccess.open(SCENE_PATH, FileAccess.READ)
    print("PROFILE balloon parse_load_first_cache_reuse_ms=%.2f scene_bytes=%d" % [
        cold_ms, scene_file.get_length() if scene_file != null else -1])
    var warm_start := Time.get_ticks_usec()
    var warm_resource := ResourceLoader.load(SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REUSE)
    print("PROFILE balloon load_cached_ms=%.2f valid=%s" % [_ms(warm_start), warm_resource != null])

    for trial in range(3):
        var instantiate_start := Time.get_ticks_usec()
        var game := scene.instantiate() as Control
        var instantiate_ms := _ms(instantiate_start)
        if game == null:
            push_error("PROFILE: instantiate() returned null")
            quit(2)
            return
        var enter_start := Time.get_ticks_usec()
        root.add_child(game)
        game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        var ready_ms := _ms(enter_start)
        game.set_process(false)
        game.set_physics_process(false)
        var backdrop := game.get_node_or_null("BoothBackdrop") as TextureRect
        var counter := game.get_node_or_null("ForegroundCounter") as TextureRect
        print("PROFILE balloon mount_trial=%d instantiate_ms=%.2f ready_and_art_binding_ms=%.2f total_ms=%.2f backdrop=%s counter=%s" %
            [trial + 1, instantiate_ms, ready_ms, instantiate_ms + ready_ms,
            str(backdrop.texture.get_size()) if backdrop != null and backdrop.texture != null else "MISSING",
            str(counter.texture.get_size()) if counter != null and counter.texture != null else "MISSING"])
        game.queue_free()
        await process_frame
        await process_frame

    var ignored_start := Time.get_ticks_usec()
    var fresh_resource := ResourceLoader.load(SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
    print("PROFILE balloon load_forced_uncached_again_ms=%.2f valid=%s" % [
        _ms(ignored_start), fresh_resource != null])

    # Isolate PNG decoding: raw Image.load and ImageTexture.create_from_image.
    for path in ART_PATHS:
        var image := Image.new()
        var path_abs := ProjectSettings.globalize_path(path)
        var raw_start := Time.get_ticks_usec()
        var err := image.load(path_abs)
        var decode_ms := _ms(raw_start)
        var texture_start := Time.get_ticks_usec()
        var texture := ImageTexture.create_from_image(image) if err == OK else null
        print("PROFILE png path=%s decode_ms=%.2f gpu_image_ms=%.2f size=%s" % [
            path, decode_ms, _ms(texture_start),
            str(image.get_size()) if texture != null else "error"])
    for i in range(4):
        await process_frame
    await create_timer(0.10).timeout
    quit(0)


func _ms(since_us: int) -> float:
    return float(Time.get_ticks_usec() - since_us) / 1000.0
