extends SceneTree

# Strict visual-transition regression for Balloon Popping. Unlike the older
# art test, this checks actual pixel occlusion, early collision availability,
# frame-to-frame easing, and all three reused balloon Area2D instances.
#
# Godot 4.7.2 --headless --path . --script res://tools/test_balloon_smooth_reveal.gd

const SCENE := preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const ART_PATHS := [
    "res://Components/Gameplay/Balloon Popping/Balloons/purple.png",
    "res://Components/Gameplay/Balloon Popping/Balloons/green.png",
    "res://Components/Gameplay/Balloon Popping/Balloons/blue.png"
]
const COUNTER_PATH := "res://Components/Gameplay/Balloon Popping/Background/95ae2a22-302d-48f7-9b5f-e12b0104c822.png"
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
    game.set_process(false)
    scenarios += 1
    var title := str(physical)
    await _check_reveal(game, slots, counter, title + " initial")

    # Repeated reset during flight must restart from the hidden counter.
    _fresh_round(game)
    game.set_process(false)
    game._process(0.085)
    var midpoint: float = (slots[1] as Area2D).position.y
    _check(midpoint < float(game._balloon_hidden_y()) - 0.5,
        title + ": pre-restart continuous ascent has progressed")
    _fresh_round(game)
    game.set_process(false)
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
    # The camera-free scene is stepped at fixed deltas so a tween, teleport,
    # pause drift, or invisible collision cannot masquerade as real flight.
    game.set_process(false)
    game.set_physics_process(false)
    var hidden_y: float = game._balloon_hidden_y()
    var exposed_y: float = game._balloon_hit_entry_y()
    var speed: float = game.balloon_float_speed
    _check(speed > 0.0 and (hidden_y - game.BALLOON_EXIT_Y) / speed < game.round_time_limit,
        title + ": continuous flight exits before path-aware question deadline")
    var previous_y: Array[float] = []
    var labels: Array[String] = []
    for lane in range(3):
        var balloon := slots[lane] as Area2D
        var sprite := balloon.get_node("Sprite") as Sprite2D
        var painted := sprite.texture.get_image()
        labels.append(String((balloon.get_node("WordLabel") as Label).text))
        previous_y.append(balloon.position.y)
        _check(balloon.visible and not balloon.monitoring and not balloon.monitorable,
            "%s lane %d: hidden target cannot collide" % [title, lane])
        _check(absf(balloon.position.y - hidden_y) < EPS,
            "%s lane %d: target starts exactly at hidden y" % [title, lane])
        _check(_exposed_pixels(sprite, painted, counter) <= 2,
            "%s lane %d: real painted balloon is fully masked by wood" % [title, lane])
    var question_start: float = game.round_time_remaining
    # Multiple frame sizes catch discontinuity and an unwanted tween that
    # silently steals control of the balloon position.
    for elapsed in [0.05, 0.08, 0.125, 0.20, 0.30, 0.60]:
        game._process(elapsed)
        game.set_process(false)
        for lane in range(3):
            var balloon := slots[lane] as Area2D
            var expected_y: float = previous_y[lane] - speed * elapsed
            _check(absf(balloon.position.y - expected_y) < EPS,
                "%s lane %d: no acceleration, slowdown, or jump in ascent (%.2f vs %.2f)" %
                [title, lane, balloon.position.y, expected_y])
            _check(String((balloon.get_node("WordLabel") as Label).text) == labels[lane],
                "%s lane %d: grammar word remains attached during ascent" % [title, lane])
            var should_hit: bool = balloon.position.y <= exposed_y and balloon.position.y > game.UPPER_LINE_Y
            _check(balloon.monitoring == should_hit and balloon.monitorable == should_hit,
                "%s lane %d: collisions activate only after counter emergence" % [title, lane])
            previous_y[lane] = balloon.position.y
    _check(game.round_time_remaining < question_start,
        title + ": question clock starts while balloon is still hidden")
    var y_before: float = (slots[0] as Area2D).position.y
    var seconds_before: float = game.time_remaining
    var question_before: float = game.round_time_remaining
    game._pause()
    game._process(0.5)
    game._physics_process(0.5)
    _check(absf((slots[0] as Area2D).position.y - y_before) < EPS and
        game.time_remaining == seconds_before and game.round_time_remaining == question_before,
        title + ": pause freezes ascent and both timers")
    game._resume()
    game.set_process(false)
    _check(game.round_active and game.timer_running,
        title + ": resume keeps same wave active")
    var remaining_flight: float = ((slots[0] as Area2D).position.y - game.BALLOON_EXIT_Y) / speed + 0.06
    game._process(remaining_flight)
    game.set_process(false)
    _check(not game.round_active and game.next_round_pending,
        title + ": top escape retires all targets and schedules next wave")
    _check(game.attempts == 0 and game.score == 0 and not game.round_completed,
        title + ": missed wave has no ghost shots, score or completed result")
    for lane in range(3):
        var balloon := slots[lane] as Area2D
        _check(not balloon.visible and not balloon.monitoring and not balloon.monitorable,
            "%s lane %d: escaped balloon is invisible and noncolliding" % [title, lane])
    game._on_next_round_delay_elapsed()
    game.set_process(false)
    _check(game.round_active and game.balloons.size() == 3,
        title + ": next wave appears automatically")
    for lane in range(3):
        _check(absf((slots[lane] as Area2D).position.y - hidden_y) < EPS,
            "%s lane %d: new wave always starts beneath counter" % [title, lane])
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
