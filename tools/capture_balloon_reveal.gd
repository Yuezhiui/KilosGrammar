extends SceneTree

# Real graphical frame-sequence QA for new balloon waves rising from beneath
# the foreground counter. No gameplay/editor source modifications.
# Run WITHOUT --headless:
# Godot --path . --script res://tools/capture_balloon_reveal.gd

const SCENE: PackedScene = preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const OUTPUT := "res://showcase/balloon_asset_review/fixed"
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const FRAME_TIMES := [0.0, 0.08, 0.18, 0.32, 0.49, 0.68, 0.91, 1.30]
const MAX_STEP_FRACTION := 0.55

var checks := 0
var captures := 0
var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("Reveal visual capture requires graphical Godot.")
        quit(1)
        return
    if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) != OK:
        push_error("Cannot create " + OUTPUT)
        quit(1)
        return
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    for requested in SIZES:
        DisplayServer.window_set_size(requested)
        root.size = requested
        root.content_scale_size = requested
        await process_frame
        await process_frame
        await _capture_reveal(requested)

    for i in range(4):
        await process_frame
    if failures.is_empty() and captures == SIZES.size() * FRAME_TIMES.size():
        print("PASS BALLOON_REVEAL %d checks, %d GUI frames, 3 resolutions; stages start hidden, rise progressively and reach final height" %
            [checks, captures])
        quit(0)
    else:
        for issue in failures:
            push_error("BALLOON_REVEAL_QA: " + issue)
        print("FAIL BALLOON_REVEAL %d issues, %d checks, %d GUI frames" % [failures.size(), checks, captures])
        quit(1)


func _capture_reveal(resolution: Vector2i) -> void:
    var game := SCENE.instantiate() as Control
    if game == null or game.get_script() == null:
        failures.append("%s: cannot instantiate Balloon scene" % resolution)
        return
    root.add_child(game)
    game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    game.set_context({
        "activity": "Balloon Popping", "topic": "Noun", "game_style": "Noun",
        "game_mode": "Seconds", "difficulty": "Normal",
        "hearts": 3, "lives": 3, "time_remaining": 60.0,
        "student_name": "REVEAL_QA", "camera_live": false
    })
    game.set_process(false)
    game.set_physics_process(false)
    var slots: Array = game.balloons
    var initial_y: float = float(game.call("_balloon_hidden_y"))
    var target_y: float = float(game.call("_balloon_y"))
    var travel := absf(initial_y - target_y)
    var previous_y: Array[float] = []
    var intermediate_steps := [0, 0, 0]
    _check(slots.size() == 3, "%s: three balloon slots before rise" % resolution)
    if slots.size() != 3:
        game.queue_free()
        await process_frame
        return
    for lane in range(3):
        var node := slots[lane] as Area2D
        previous_y.append(node.position.y)
        _check(absf(node.position.y - initial_y) < 0.6,
            "%s: balloon lane%d initial y=%.2f matches hidden y=%.2f before first draw" %
                [resolution, lane, node.position.y, initial_y])
        _check(node.visible, "%s: new balloon node %d is instantiated and masked by counter" %
            [resolution, lane])
    print("BALLOON_REVEAL_BEGIN %s hidden_y=%.2f exposed_y=%.2f travel=%.2f foreground=%s" %
        [resolution, initial_y, target_y, travel, (game.get_node("ForegroundCounter") as TextureRect).get_global_rect()])

    var previous_t := 0.0
    for frame_index in range(FRAME_TIMES.size()):
        var frame_t: float = FRAME_TIMES[frame_index]
        if frame_index > 0:
            await create_timer(frame_t - previous_t).timeout
        await RenderingServer.frame_post_draw
        var positions: Array[float] = []
        for lane in range(3):
            var target := slots[lane] as Area2D
            positions.append(target.position.y)
            var rise_distance: float = initial_y - target.position.y
            _check(rise_distance >= -3.0 and rise_distance <= travel + 65.0,
                "%s frame%d lane%d: position %.2f stays in valid reveal band" %
                    [resolution, frame_index, lane, target.position.y])
            if frame_index > 0:
                var step: float = absf(previous_y[lane] - target.position.y)
                _check(step <= travel * MAX_STEP_FRACTION + 8.0,
                    "%s frame%d lane%d: no one-frame teleport, y step=%.2f of %.2f total" %
                        [resolution, frame_index, lane, step, travel])
                _check(target.position.y <= previous_y[lane] + 2.0,
                    "%s frame%d lane%d: continuous reveal never jumps back downward, y %.2f -> %.2f" %
                        [resolution, frame_index, lane, previous_y[lane], target.position.y])
                if rise_distance > travel * 0.12 and rise_distance < travel * 0.88:
                    intermediate_steps[lane] += 1
            previous_y[lane] = target.position.y
        _check(absf(positions[0] - positions[1]) < 5.0 and absf(positions[1] - positions[2]) < 5.0,
            "%s frame%d: all lanes rise together, positions=%s" % [resolution, frame_index, positions])
        var frame := root.get_texture().get_image()
        _check(frame.get_size() == resolution,
            "%s frame%d: saved pixels really match physical viewport" % [resolution, frame_index])
        var screenshot := OUTPUT.path_join("balloon_reveal_%dx%d_%02d.png" %
            [resolution.x, resolution.y, frame_index])
        if frame.save_png(ProjectSettings.globalize_path(screenshot)) == OK:
            captures += 1
        else:
            failures.append("%s frame%d: image PNG save failed" % [resolution, frame_index])
        print("BALLOON_REVEAL_FRAME %s frame=%d elapsed_requested=%.3f y=%s file=%s" %
            [resolution, frame_index, frame_t, positions, screenshot])
        previous_t = frame_t

    for lane in range(3):
        _check(intermediate_steps[lane] >= 1,
            "%s lane%d: observed intermediate visible rise without hidden->exposed teleport" %
            [resolution, lane])
        _check(absf(previous_y[lane] - target_y) < 6.0,
            "%s lane%d: reached exposed y=%.2f (expected %.2f)" %
            [resolution, lane, previous_y[lane], target_y])
    game.queue_free()
    await process_frame
    await process_frame


func _check(ok: bool, description: String) -> void:
    checks += 1
    if not ok:
        failures.append(description)
