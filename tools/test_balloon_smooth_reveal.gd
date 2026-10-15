extends SceneTree

# Strict visual-transition regression for Balloon Popping. Unlike the older
# art test, this checks actual pixel occlusion, early collision availability,
# frame-to-frame easing, and all three reused balloon Area2D instances.
#
# Godot 4.7.2 --headless --path . --script res://tools/test_balloon_smooth_reveal.gd

const SCENE := preload("res://ui/minigames/balloon_popping.tscn")
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const ART_PATHS := [
    "res://BalloonPoppingBalloons/purple.png",
    "res://BalloonPoppingBalloons/green.png",
    "res://BalloonPoppingBalloons/blue.png"
]
const COUNTER_PATH := "res://BalloonPoppingBackground/95ae2a22-302d-48f7-9b5f-e12b0104c822.png"
const LABELS: Array[String] = ["PURPLE", "GREEN", "BLUE"]
const EPS := 0.75

var checks := 0
var scenarios := 0
var failures: Array[String] = []
var image_counter: Image
var image_balloons: Array[Image] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    image_counter = Image.new()
    _check(image_counter.load(ProjectSettings.globalize_path(COUNTER_PATH)) == OK,
        "counter PNG loaded for real per-pixel masking assertions")
    for art_path in ART_PATHS:
        var image := Image.new()
        _check(image.load(ProjectSettings.globalize_path(art_path)) == OK,
            "original balloon artwork loaded: " + art_path)
        image_balloons.append(image)
    var original_size := root.size
    for physical in SIZES:
        root.size = physical
        await process_frame
        await process_frame
        await _scenario(physical)
    root.size = original_size
    for unused in range(3):
        await process_frame
    await create_timer(0.1).timeout
    if failures.is_empty() and scenarios == SIZES.size():
        print("PASS Balloon smooth reveal: %d checks across %d physical viewport sizes" %
            [checks, scenarios])
        quit(0)
    else:
        var category_counts: Dictionary = {}
        for failure in failures:
            var colon := failure.find(": ")
            var category := failure.substr(colon + 2) if colon >= 0 else failure
            category_counts[category] = int(category_counts.get(category, 0)) + 1
        for category in category_counts:
            print("FAIL CATEGORY: %s (%d)" % [category, category_counts[category]])
        for failure in failures.slice(0, 20):
            push_error("BALLOON REVEAL QA: " + failure)
        if failures.size() > 20:
            print("... %d additional failures suppressed" % (failures.size() - 20))
        print("FAIL Balloon smooth reveal: %d failures / %d checks / %d sizes" %
            [failures.size(), checks, scenarios])
        quit(1)


func _scenario(physical: Vector2i) -> void:
    var host := Control.new()
    host.name = "RevealTestHost"
    # Godot project uses canvas_items stretch; mount the same logical size
    # the production game uses, not the physical window pixel dimensions.
    host.size = root.get_visible_rect().size
    root.add_child(host)
    var game := SCENE.instantiate() as Control
    _check(game != null and game.get_script() != null, "%s: gameplay scene loads" % physical)
    if game == null or game.get_script() == null:
        if game != null:
            game.free()
        host.queue_free()
        await process_frame
        return
    host.add_child(game)
    game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    await process_frame
    await process_frame
    var slots: Array = game.balloon_slots
    var nodes_before: Array[int] = []
    for lane in range(3):
        nodes_before.append((slots[lane] as Area2D).get_instance_id())
    var counter := game.get_node("ForegroundCounter") as TextureRect
    var layer := game.get_node("BalloonLayer") as Node2D
    _check(counter.z_index > layer.z_index,
        "%s: counter is in front of all rising balloon sprites" % physical)

    # A reset recreates the question, but NEVER the 3 authored Area2D nodes.
    _fresh_round(game)
    scenarios += 1
    var title := str(physical)
    await _check_reveal(game, slots, counter, title + " initial")

    # Repeated context reset while a tween is in flight must kill the old
    # tween, reposition all balloons invisibly, and restart one clean rise.
    _fresh_round(game)
    await create_timer(0.085).timeout
    var midpoint: float = (slots[1] as Area2D).position.y
    # A 1.15-second sine ease-in-out intentionally advances only a few
    # pixels in the first 85ms. Do not mistake that smooth start for a stall.
    _check(midpoint < float(game._balloon_hidden_y()) - 0.5,
        title + ": pre-restart tween has actually progressed")
    _fresh_round(game)
    _check(game.balloons.size() == 3 and game.balloon_slots.size() == 3,
        title + ": restart does not duplicate active slots")
    for lane in range(3):
        var slot := slots[lane] as Area2D
        _check(slot.get_instance_id() == nodes_before[lane],
            "%s lane %d: restart reuses original Area2D node" % [title, lane])
    await _check_reveal(game, slots, counter, title + " restart")
    _check(game.get_node("BalloonLayer").get_child_count() == 3,
        title + ": no leaked/duplicated balloon scene instances after restarts")
    host.queue_free()
    await process_frame
    await process_frame


func _fresh_round(game: Control) -> void:
    # Use actual game-context route, not manually patching display nodes.
    game.set_context({
        "activity": "Balloon Popping", "game_mode": "Lives", "topic": "Noun",
        "difficulty": "Normal", "score": 0, "attempts": 0, "correct": 0,
        "hearts": 3, "lives": 3, "balloon_round": 0
    })


func _check_reveal(game: Control, slots: Array, counter: TextureRect, title: String) -> void:
    var hidden_y: float = game._balloon_hidden_y()
    var exposed_y: float = game._balloon_y()
    var distance: float = hidden_y - exposed_y
    _check(distance > 100.0, title + ": hidden and final points are well separated")
    var previous_y: Array[float] = []
    var label_text: Array[String] = []
    for lane in range(3):
        var balloon := slots[lane] as Area2D
        var sprite := balloon.get_node("Sprite") as Sprite2D
        label_text.append(String((balloon.get_node("WordLabel") as Label).text))
        previous_y.append(balloon.position.y)
        _check(balloon.visible, "%s lane %d: art is enabled for masked rise" % [title, lane])
        _check(absf(balloon.position.y - hidden_y) < 2.0,
            "%s lane %d: starts exactly at the hidden coordinate" % [title, lane])
        _check(_exposed_pixels(sprite, image_balloons[lane], counter) <= 2,
            "%s lane %d: initial full balloon is concealed by counter pixels" % [title, lane])
        _check(not balloon.monitoring and not balloon.monitorable,
            "%s lane %d: collision disabled before visible rise finishes" % [title, lane])

    # The start must feel like a continuous ascent, not a BACK ease-out
    # teleport (~50% of the travel in the first few animation frames).
    await create_timer(0.055).timeout
    for lane in range(3):
        var balloon := slots[lane] as Area2D
        var progress: float = (hidden_y - balloon.position.y) / distance
        _check(progress < 0.32,
            "%s lane %d: first 55ms do not teleport >32%% of full rise (actual %.1f%%)" %
            [title, lane, progress * 100.0])
        _check(balloon.position.y <= previous_y[lane] + EPS,
            "%s lane %d: initial movement goes upward only" % [title, lane])
        if balloon.position.y > exposed_y + 4.0:
            _check(not balloon.monitoring and not balloon.monitorable,
                "%s lane %d: cannot collide while emerging from behind counter" % [title, lane])
        previous_y[lane] = balloon.position.y

    # Sample both tween and early floating period. A BACK easing overshoot
    # must fail because it reverses direction at the end of its tween.
    for elapsed in [0.075, 0.075, 0.075, 0.075]:
        await create_timer(elapsed).timeout
        for lane in range(3):
            var balloon := slots[lane] as Area2D
            _check(balloon.position.y <= previous_y[lane] + EPS,
                "%s lane %d: rise does not overshoot and rebound downward" % [title, lane])
            if balloon.position.y > exposed_y + 4.0:
                _check(not balloon.monitoring and not balloon.monitorable,
                    "%s lane %d: half-exposed target still cannot collide" % [title, lane])
            previous_y[lane] = balloon.position.y

    # Pause while there is still vertical movement; all three targets must
    # freeze, along with both game timer fields, regardless of tween phase.
    var before_pause: Array[float] = []
    for lane in range(3):
        before_pause.append((slots[lane] as Area2D).position.y)
    var global_before: float = game.time_remaining
    var round_before: float = game.round_time_remaining
    game._pause()
    await create_timer(0.18).timeout
    for lane in range(3):
        _check(absf((slots[lane] as Area2D).position.y - before_pause[lane]) < EPS,
            "%s lane %d: pause freezes actual sprite motion" % [title, lane])
    _check(is_equal_approx(game.time_remaining, global_before)
        and is_equal_approx(game.round_time_remaining, round_before),
        title + ": pause freezes global/question clocks")
    game._resume()

    # A slow, smooth introduction can be >0.34 s. Wait out tween safely,
    # then ensure exactly one active target per lane and no erroneous word.
    # The production reveal lasts 1.15s. Earlier we sampled ~0.36s before
    # pause, so allow enough resumed time for the finished callback to run.
    await create_timer(1.05).timeout
    for lane in range(3):
        var balloon := slots[lane] as Area2D
        _check(balloon.visible and balloon.monitoring and balloon.monitorable,
            "%s lane %d: collisions enabled when ascent has finished" % [title, lane])
        _check(balloon.position.y < hidden_y - distance * 0.75,
            "%s lane %d: after resume balloon has reached exposed play area" % [title, lane])
        _check(String((balloon.get_node("WordLabel") as Label).text) == label_text[lane],
            "%s lane %d: correct word survives reveal and pause" % [title, lane])
    _check(game.score == 0 and game.attempts == 0,
        title + ": reveal and pause do not score or register ghost hits")


func _exposed_pixels(sprite: Sprite2D, sprite_image: Image, counter: TextureRect) -> int:
    # Check real artist-authored PNG alpha, *not* just that center Y is below
    # the foreground Control. The 1672x941 counter PNG has a transparent
    # upper region: being geometrically under its TextureRect is insufficient.
    var counter_rect := counter.get_global_rect()
    var size_pixels := sprite_image.get_size()
    var visible := 0
    if size_pixels.x < 1 or size_pixels.y < 1:
        return 9999
    for py in range(3, size_pixels.y, 7):
        for px in range(3, size_pixels.x, 7):
            if sprite_image.get_pixel(px, py).a < 0.30:
                continue
            var local := Vector2(px - float(size_pixels.x) * 0.5,
                py - float(size_pixels.y) * 0.5)
            var world := sprite.to_global(local)
            if world.x < 0.0 or world.x >= root.get_visible_rect().size.x or \
                    world.y < 0.0 or world.y >= root.get_visible_rect().size.y:
                continue
            var rel := (world - counter_rect.position) / counter_rect.size
            if rel.x < 0.0 or rel.x >= 1.0 or rel.y < 0.0 or rel.y >= 1.0:
                visible += 1
                continue
            var mask_x := clampi(int(rel.x * float(image_counter.get_width())),
                0, image_counter.get_width() - 1)
            var mask_y := clampi(int(rel.y * float(image_counter.get_height())),
                0, image_counter.get_height() - 1)
            if image_counter.get_pixel(mask_x, mask_y).a < 0.95:
                visible += 1
    return visible


func _check(condition: bool, detail: String) -> void:
    checks += 1
    if not condition:
        failures.append(detail)
