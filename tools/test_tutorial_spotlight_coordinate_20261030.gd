extends SceneTree

# Independently validate the actual shader opening AND yellow border against
# the live minigame target in display coordinates, not just in-viewport size.
# This is a camera/database-free visual coordinate regression.
const CASES := [
    {"activity": "Catch the Word", "scene": "res://ui/minigames/catch_the_word/catch_word.tscn"},
    {"activity": "Balloon Popping", "scene": "res://ui/minigames/balloon_popping/balloon_popping.tscn"},
]
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var checks := 0
var errors: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    for case in CASES:
        for mode in ["Seconds", "Lives"]:
            await _case(case, mode)
    for failure in errors:
        printerr("SPOTLIGHT COORDINATE FAIL: ", failure)
    print("SPOTLIGHT COORDINATE QA: %s checks=%d failures=%d" % [
        "PASS" if errors.is_empty() else "FAIL", checks, errors.size()])
    quit(0 if errors.is_empty() else 1)


func _case(config: Dictionary, mode: String) -> void:
    var source := load(String(config["scene"])) as PackedScene
    if source == null:
        _check(false, str(config["scene"]) + " can load")
        return
    var game := source.instantiate() as Control
    game.process_mode = Node.PROCESS_MODE_DISABLED
    root.size = SIZES[0]
    root.content_scale_size = SIZES[0]
    root.add_child(game)
    game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    game.call("set_context", {
        "activity": config["activity"], "topic": "Noun",
        "difficulty": "Easy", "game_mode": mode,
        "guided_tutorial": true, "camera_live": false,
        "keyboard_mode": true})
    await process_frame
    await process_frame
    _check(bool(game.call("is_tutorial_active")),
        "%s %s tutorial active" % [config["activity"], mode])
    for resolution in SIZES:
        root.content_scale_size = resolution
        root.size = resolution
        game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        # Exercise a resize on the SAME live tutorial scene, including the
        # HUD's deferred relayout and post-layout spotlight refresh.
        await process_frame
        await process_frame
        for step_index in range(game.call("_tutorial_steps").size()):
            var entry: Dictionary = game.call("_tutorial_steps")[step_index]
            var id := String(entry["id"])
            _check(_matching_target(game, String(config["activity"]), id, resolution),
                "%s %s step=%s at %s cutout+border+target agree" %
                [config["activity"], mode, id, resolution])
            if step_index + 1 < game.call("_tutorial_steps").size():
                game.call("tutorial_next_step")
        # Back across ALL steps to repeat the traversal at the next size.
        for i in range(game.call("_tutorial_steps").size() - 1):
            game.call("tutorial_previous_step")
    game.queue_free()
    await process_frame


func _matching_target(game: Control, activity: String, id: String, resolution: Vector2i) -> bool:
    var tutorial := game.get_node_or_null("GuidedTutorialLayer/GuidedTutorial") as Control
    var border := game.get_node_or_null("GuidedTutorialLayer/GuidedTutorial/FocusOutline") as Control
    var dim := game.get_node_or_null("GuidedTutorialLayer/GuidedTutorial/Dim") as ColorRect
    if tutorial == null or border == null or dim == null or not tutorial.visible:
        return false
    var target: CanvasItem = null
    if activity == "Catch the Word":
        match id:
            "prompt": target = game.get("prompt_label") as CanvasItem
            "movement": target = game.get("basket_sprite") as CanvasItem
            "seconds": target = game.get("timer_plaque") as CanvasItem
            "lives": target = game.get("lives_plaque") as CanvasItem
            "score": target = game.get("score_plaque") as CanvasItem
            "pause": target = game.get("pause_plaque") as CanvasItem
    else:
        match id:
            "prompt": target = game.get("carnival_objective_plaque") as CanvasItem
            "movement":
                var launcher := game.get("launcher") as Node2D
                if launcher != null:
                    target = launcher.get_node_or_null("TutorialFocusArea") as CanvasItem
            "seconds": target = game.get("shared_timer_plaque") as CanvasItem
            "lives": target = game.get("shared_lives_plaque") as CanvasItem
            "score": target = game.get("carnival_score_plaque") as CanvasItem
            "pause": target = game.get("pause_plaque") as CanvasItem
    if target == null:
        return false
    var border_rect := _screen_rect(border)
    var target_rect := _screen_rect(target)
    if not border_rect.has_area() or not target_rect.has_area():
        return false
    # Some artist-authored launchers intentionally sit partly BELOW the
    # viewport; compare only the visible portion of that original artwork.
    var visible_target := target_rect.intersection(Rect2(Vector2.ZERO, Vector2(resolution)))
    if not visible_target.has_area():
        return false
    # A few pixels of rounding and design padding are allowed, but a border
    # must cover the actual component and not spill far outside it.
    var max_padding := maxf(48.0, float(resolution.x) * 0.04)
    var border_encloses_target := border_rect.grow(2.0).encloses(visible_target)
    var not_oversized := border_rect.size.x <= visible_target.size.x + max_padding * 2.0 \
        and border_rect.size.y <= visible_target.size.y + max_padding * 2.0
    var dim_material := dim.material as ShaderMaterial
    if dim_material == null:
        return false
    var rect_param: Vector4 = dim_material.get_shader_parameter("focus_rect")
    var inv := dim.get_global_transform_with_canvas().affine_inverse()
    var local_begin := inv * border_rect.position
    var local_end := inv * border_rect.end
    var implied_uv := Rect2(local_begin / dim.size, (local_end - local_begin) / dim.size).abs()
    var actual_uv := Rect2(Vector2(rect_param.x, rect_param.y),
        Vector2(rect_param.z, rect_param.w))
    var hole_matches_border := implied_uv.position.distance_to(actual_uv.position) < 0.012 \
        and implied_uv.size.distance_to(actual_uv.size) < 0.012
    var inside_screen := Rect2(Vector2.ZERO, Vector2(resolution)).grow(2.0).encloses(border_rect)
    if not border_encloses_target or not not_oversized or not hole_matches_border or not inside_screen:
        printerr("VISUAL FOCUS ", activity, " ", id, " border=", border_rect,
            " target=", target_rect, " hole=", actual_uv, " expected_hole=", implied_uv)
    return border_encloses_target and not_oversized and hole_matches_border and inside_screen


func _screen_rect(item: CanvasItem) -> Rect2:
    var local := Rect2()
    if item is Control:
        local = Rect2(Vector2.ZERO, (item as Control).size)
    elif item is Sprite2D:
        local = (item as Sprite2D).get_rect()
    else:
        return local
    var xf := item.get_global_transform_with_canvas()
    var corners := [
        xf * local.position, xf * Vector2(local.end.x, local.position.y),
        xf * local.end, xf * Vector2(local.position.x, local.end.y)]
    var result := Rect2(corners[0], Vector2.ZERO)
    for corner in corners:
        result = result.expand(corner)
    return result.abs()


func _check(ok: bool, description: String) -> void:
    checks += 1
    if not ok:
        errors.append(description)
