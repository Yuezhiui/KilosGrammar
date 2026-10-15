extends SceneTree

# GUI-only Balloon HUD visual QA. Does not modify gameplay/editor scenes.
# Godot --path . --script res://tools/capture_balloon_shared_hud.gd
# Saves exact 875x500, 1280x720, 1920x1080 frames for Seconds and
# Lives (3/2/1 hearts), plus a nonzero-score frame per size.
# QA for unsqueezed Catch timer/hearts, raised score, and center cannon.

const SCENE: PackedScene = preload("res://ui/minigames/balloon_popping.tscn")
const OUTPUT := "res://showcase/balloon_asset_review/fixed"
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const HEART_IMAGES := {
    1: "res://ui/minigames/catch_hud/generated/replacement/lives_state_1.png",
    2: "res://ui/minigames/catch_hud/generated/replacement/lives_state_2.png",
    3: "res://ui/minigames/catch_hud/generated/replacement/lives_state_3.png",
}
const TIMER_IMAGE := "res://ui/minigames/catch_hud/generated/timer_badge.png"

var failures: Array[String] = []
var captures := 0


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("Balloon visual capture requires the graphical Godot renderer.")
        quit(1)
        return
    var output_dir := ProjectSettings.globalize_path(OUTPUT)
    var err := DirAccess.make_dir_recursive_absolute(output_dir)
    if err != OK:
        push_error("Cannot create QA output directory: %s (code %d)" % [output_dir, err])
        quit(1)
        return

    # Project defaults to a maximized window; override it so saved pixel sizes
    # match each requested viewport rather than the desktop's 1920x1080.
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    for physical in SIZES:
        DisplayServer.window_set_size(physical)
        root.size = physical
        root.content_scale_size = physical
        await process_frame
        await process_frame
        await _capture_case(physical, "Seconds", 3)
        for hearts in [3, 2, 1]:
            await _capture_case(physical, "Lives", hearts)
        await _capture_case(physical, "Seconds", 3, 135)

    print("BALLOON_HUD_CAPTURE: %d successful frames, backend=%s" % [captures, DisplayServer.get_name()])
    if failures.is_empty() and captures == SIZES.size() * 5:
        print("PASS Balloon shared HUD capture: Seconds + Lives 3/2/1 and 135 score at all 3 resolutions")
        quit(0)
    else:
        for failure in failures:
            push_error("BALLOON_HUD_QA: " + failure)
        quit(1)


func _capture_case(physical: Vector2i, mode: String, hearts: int, display_score: int = 0) -> void:
    var game := SCENE.instantiate() as Control
    if game == null or game.get_script() == null:
        failures.append("%s %s %d: scene/script missing" % [physical, mode, hearts])
        return
    root.add_child(game)
    game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    game.set_context({
        "activity": "Balloon Popping", "topic": "Noun", "game_style": "Noun",
        "game_mode": mode, "difficulty": "Normal", "lives": hearts,
        "time_remaining": 60.0, "score": display_score,
        "student_name": "QA", "camera_live": false
    })
    # Begin the real gameplay rise; pause only gameplay timers, not the Tween.
    # The slower 1.15s synchronized reveal needs more than the old 0.45s.
    await create_timer(0.45).timeout
    game.set_process(false)
    game.set_physics_process(false)
    await create_timer(0.90).timeout
    await RenderingServer.frame_post_draw

    var hud := game.get_node_or_null("HudLayer") as Control
    var timer := hud.get_node_or_null("TimerPlaque") as TextureRect if hud != null else null
    var lives := hud.get_node_or_null("LivesPlaque") as TextureRect if hud != null else null
    var old_hearts := hud.get_node_or_null("HeartsBox") as HBoxContainer if hud != null else null
    var time_label := hud.get_node_or_null("TimeLabel") as Label if hud != null else null
    var score := hud.get_node_or_null("ScoreBottomContainer") as Control if hud != null else null
    var score_num := hud.get_node_or_null("ScoreBottomContainer/ScoreNumber") as Label if hud != null else null
    var launcher := game.get_node_or_null("LauncherLayer/Launcher") as Node2D
    var objective := hud.get_node_or_null("ObjectivePanel") as TextureRect if hud != null else null
    var title_art := hud.get_node_or_null("CarnivalTitle") as TextureRect if hud != null else null
    var prompt_art := hud.get_node_or_null("CarnivalPrompt") as TextureRect if hud != null else null
    var score_art := hud.get_node_or_null("CarnivalScore") as TextureRect if hud != null else null
    var prompt_text := hud.get_node_or_null("PromptLabel") as Label if hud != null else null
    var stage := game.get_node_or_null("BalloonLayer") as Node2D
    var counter := game.get_node_or_null("ForegroundCounter") as TextureRect

    _check(hud != null and timer != null and lives != null and old_hearts != null and time_label != null,
        "%s %s %d: expected shared HUD controls exist" % [physical, mode, hearts])
    _check(score_num != null and score_num.text == str(display_score),
        "%s %s %d score=%d: dynamic score label shows requested digits" %
            [physical, mode, hearts, display_score])
    var key := "%s %s hearts=%d score=%d" % [physical, mode, hearts, display_score]
    _check(objective != null or (title_art != null and prompt_art != null),
        key + ": carnival title and blank prompt frame assets are present")
    _check(score_art != null and score_art.texture != null,
        key + ": red carnival score plaque texture exists")
    var frame := Rect2(Vector2.ZERO, Vector2(physical))
    var header: TextureRect = objective if objective != null else title_art
    for panel in [header, prompt_art, score_art]:
        if panel != null and panel.visible:
            _check(frame.encloses(panel.get_global_rect().grow(-1.0)),
                key + ": " + panel.name + " completely within viewport")
    if header != null and score_art != null:
        _check(not header.get_global_rect().intersects(score_art.get_global_rect()),
            key + ": carnival title/prompt frame avoids red score plaque")
    if objective != null and prompt_text != null:
        _check(objective.get_global_rect().encloses(prompt_text.get_global_rect()),
            key + ": changing grammar text sits inside carnival cream prompt panel")
    if score_art != null and score_num != null:
        _check(score_art.get_global_rect().encloses(score_num.get_global_rect()),
            key + ": changing score number sits inside red score plaque")
        var cream_text_center := (score_num.get_global_rect().get_center() - score_art.get_global_rect().position) / score_art.get_global_rect().size
        _check(absf(cream_text_center.x - 0.5) < 0.09 and absf(cream_text_center.y - 0.60) < 0.14,
            key + ": numeric score is centered in the cream inset, normalized center=" + str(cream_text_center))
    if stage != null and counter != null and hud != null:
        _check(stage.z_index < counter.z_index and counter.z_index < hud.z_index,
            key + ": balloons, counter, and HUD retain front-to-back order")
    if launcher != null:
        _check(absf(launcher.global_position.x - physical.x / 2.0) < 1.0,
            key + ": cannon begins at viewport center")
    if timer != null and lives != null:
        _check(timer.visible == (mode == "Seconds") and lives.visible == (mode == "Lives"),
            "%s %s %d: only matching mode plaque is visible" % [physical, mode, hearts])
        _check(old_hearts != null and not old_hearts.visible,
            "%s %s %d: legacy hearts stay hidden behind complete PNG panel" % [physical, mode, hearts])
        var expected: String = TIMER_IMAGE if mode == "Seconds" else String(HEART_IMAGES[hearts])
        var plaque: TextureRect = timer if mode == "Seconds" else lives
        _check(plaque.texture != null and plaque.texture.resource_path == expected,
            "%s %s %d: shared badge references requested PNG (got %s)" %
                [physical, mode, hearts, plaque.texture.resource_path if plaque.texture != null else "<none>"])
        _check(time_label != null and time_label.visible == (mode == "Seconds"),
            "%s %s %d: numeric timer appears only in Seconds" % [physical, mode, hearts])
        if plaque.is_visible_in_tree():
            _check(Rect2(Vector2.ZERO, game.size).intersects(plaque.get_global_rect()),
                "%s %s %d: badge is inside visible game frame" % [physical, mode, hearts])
            _check(frame.encloses(plaque.get_global_rect().grow(-1.0)),
                key + ": timer/heart badge not clipped by frame")
            if plaque.texture != null:
                var native_size := plaque.texture.get_size()
                var drawn_size := plaque.get_global_rect().size
                var source_ratio: float = native_size.x / native_size.y
                var rendered_ratio: float = drawn_size.x / drawn_size.y
                var distortion: float = absf(rendered_ratio / source_ratio - 1.0)
                _check(distortion < 0.04,
                    "%s: %s badge preserves source aspect ratio native=%.3f drawn=%.3f distortion=%.1f%%" %
                    [key, mode, source_ratio, rendered_ratio, distortion * 100.0])
                print("BALLOON_BADGE_ASPECT %s native=%s slot=%s native_ratio=%.4f drawn_ratio=%.4f distortion=%.1f%%" %
                    [key, native_size, drawn_size, source_ratio, rendered_ratio, distortion * 100.0])
            if score_art != null:
                _check(not score_art.get_global_rect().intersects(plaque.get_global_rect()),
                    key + ": score and time/heart panels stay separated")

    # Log geometry, including the existing launcher/score collision. This is
    # an observation, not an instruction to change authored layouts.
    if score != null and launcher != null and timer != null and lives != null:
        var active_badge: TextureRect = timer if mode == "Seconds" else lives
        print("BALLOON_GEOMETRY %s %s hearts=%d viewport=%s score=%s launcher=%s badge=%s" %
            [physical, mode, hearts, game.size, score.get_global_rect(),
            launcher.global_position, active_badge.get_global_rect()])

    var image := root.get_texture().get_image()
    var actual := Vector2i(image.get_width(), image.get_height())
    if actual != physical:
        failures.append("%s %s %d: actual capture %s differs from requested %s" %
            [physical, mode, hearts, actual, physical])
    var suffix := "seconds" if mode == "Seconds" else "lives_%d" % hearts
    if display_score > 0:
        suffix += "_score_%d" % display_score
    var path := OUTPUT.path_join("balloon_%dx%d_%s.png" % [physical.x, physical.y, suffix])
    var result := image.save_png(ProjectSettings.globalize_path(path))
    if result == OK:
        captures += 1
        print("BALLOON_CAPTURE %s actual=%s" % [ProjectSettings.globalize_path(path), actual])
    else:
        failures.append("Failed to save %s (error %d)" % [path, result])
    root.remove_child(game)
    game.queue_free()
    await process_frame
    await process_frame


func _check(ok: bool, description: String) -> void:
    if not ok:
        failures.append(description)
