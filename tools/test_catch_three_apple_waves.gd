extends SceneTree

# Behavioral QA for the immediate-falling three-apple wave mechanic.
# Run: Godot --headless --path . --script res://tools/test_catch_three_apple_waves.gd
# Use actual Catch gameplay logic and scene textures, with controlled time
# steps for deterministic catch/miss/restart assertions.

const SCENE := preload("res://ui/minigames/catch_word.tscn")
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const CHARACTERS := ["Boy", "Girl", "Grandma", "Grandpa"]
const MODES := ["Seconds", "Lives"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const APPLE_TEXTURE := "res://ui/minigames/catch_hud/generated/character/word_apple.png"
const COLLECTED_TEXTURE := "res://Components/Apple.png"
const STATES := {
    "Easy": {"speed": 105.0},
    "Normal": {"speed": 185.0},
    "Hard": {"speed": 245.0}
}
const TICK := 0.025
const IMMEDIATE_TICK := 0.05

var checks := 0
var cases := 0
var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var saved_size := root.size
    root.size = Vector2i(1280, 720)
    await process_frame
    for difficulty in DIFFICULTIES:
        for mode in MODES:
            for character in CHARACTERS:
                for topic in TOPICS:
                    await _run_case(topic, character, mode, difficulty)
    root.size = saved_size
    # Deferred node/audio-server cleanup needs several ticks after the last
    # recorded cue before a one-shot headless test terminates.
    for cleanup_frame in range(4):
        await process_frame
    await create_timer(0.15).timeout
    if failures.is_empty() and cases == 120:
        print("PASS Catch three-apple waves: %d checks across %d topic/character/mode/difficulty cases" % [checks, cases])
        quit(0)
    else:
        for error in failures.slice(0, 45):
            push_error("THREE APPLE WAVE QA: " + error)
        if failures.size() > 45:
            print("... %d other errors suppressed" % (failures.size() - 45))
        print("FAIL Catch three-apple waves: %d failures from %d checks and %d cases" % [failures.size(), checks, cases])
        quit(1)


func _run_case(topic: String, character: String, mode: String, difficulty: String) -> void:
    var ctx := {
        "topic": topic, "catch_character": character, "catch_map": "Forest",
        "game_mode": mode, "difficulty": difficulty
    }
    var label := "%s/%s/%s/%s" % [topic, character, mode, difficulty]
    var host := Control.new()
    host.size = Vector2(1280, 720)
    root.add_child(host)
    var game := SCENE.instantiate() as Control
    _check(game != null and game.get_script() != null, label + ": gameplay script compiles and attaches")
    if game == null or game.get_script() == null:
        host.queue_free()
        await process_frame
        return
    host.add_child(game)
    game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    await process_frame
    await process_frame
    game.set_process(false)
    game.set_context(ctx)
    await process_frame
    game.set_process(false)
    cases += 1
    _check(game.topic == topic and game.difficulty == difficulty
        and game.selected_character == character and game.game_mode == mode,
        label + ": exact contextual selections apply")
    _check(game.get("wave_phase") != null and game.get("wave_index") != null,
        label + ": state machine exposes wave_phase and wave_index")
    _check(absf(float(game.get("base_fall_speed")) - float(STATES[difficulty]["speed"])) <= 0.01,
        label + ": correct difficulty starting fall speed")
    if not _wait_for_three(game, label + " initial"):
        host.queue_free()
        await process_frame
        return

    var initial_wave := int(game.get("wave_index"))
    var initial_speed := _wave_speed(game)
    _check(initial_wave >= 1, label + ": first wave registered")
    _check(String(game.get("wave_phase")) == "falling",
        label + ": initial apples fall immediately without a reading/freeze phase")
    # All three must move on the first gameplay tick, rather than pausing for
    # any of the former Easy/Normal/Hard reading durations.
    var y_before: Array[float] = _all_y(game)
    var x_before: Array[float] = _all_x(game)
    _step(game, IMMEDIATE_TICK)
    _check(game.falling_tiles.size() == 3,
        label + ": all three remain during the first falling tick")
    if game.falling_tiles.size() == 3:
        var y_after: Array[float] = _all_y(game)
        var x_after: Array[float] = _all_x(game)
        var expected_delta := initial_speed * IMMEDIATE_TICK
        for i in range(3):
            _check(absf((y_after[i] - y_before[i]) - expected_delta) <= 0.15,
                label + ": lane %d moves at synchronized speed on FIRST tick" % i)
            _check(absf(x_after[i] - x_before[i]) <= 0.01,
                label + ": lane %d stays horizontally aligned while falling" % i)
        _check(absf(y_after[0] - y_after[1]) <= 0.01 and
            absf(y_after[1] - y_after[2]) <= 0.01,
            label + ": all three apples remain on one horizontal row")
    game._pause()
    var frozen_y := _tile_y(game)
    var frozen_timer := float(game.time_remaining)
    _step(game, 0.35)
    _check(absf(_tile_y(game) - frozen_y) <= 0.01 and
        absf(float(game.time_remaining) - frozen_timer) <= 0.01,
        label + ": paused wave and timer remain frozen")
    game._resume()
    game.set_process(false)
    var falling_y := _tile_y(game)
    _step(game, 0.03)
    _check(_tile_y(game) > falling_y,
        label + ": synchronized wave moves immediately after genuine unpause")

    # Actual collision with one of the three visual apples. Alternate
    # correct/wrong across scenarios to cover both responses and hearts.
    var should_catch_correct := ((TOPICS.find(topic) + CHARACTERS.find(character)
        + MODES.find(mode) + DIFFICULTIES.find(difficulty)) % 2 == 0)
    var before_lives: int = game.lives
    var before_score: int = game.score
    _force_collision(game, should_catch_correct, label)
    _check(game.attempts == 1,
        label + ": exactly one catch counts, regardless of three apples")
    _check(game.correct_count == (1 if should_catch_correct else 0),
        label + ": correct counter matches selected apple")
    _check((game.score > before_score) == should_catch_correct,
        label + ": only a correct apple earns score")
    _check(game.lives == (before_lives - 1 if mode == "Lives" and not should_catch_correct else before_lives),
        label + ": wrong fruit costs one heart only in Lives mode")
    if should_catch_correct:
        _check(game.collected_words.size() == 1,
            label + ": caught correct word appears exactly once in basket")
        var basket_words := game.get_node("CollectedWords") as Node2D
        _check(basket_words.get_child_count() == 1 and
            (basket_words.get_child(0) as TextureRect).texture.resource_path == COLLECTED_TEXTURE,
            label + ": original basket apple stays in use")
    _check(String(game.get("wave_phase")) == "clearing",
        label + ": one collision resolves wave and starts clearing")
    var before_second_attempt: int = game.attempts
    var before_second_score: int = game.score
    var before_second_lives: int = game.lives
    _force_collision_of_remaining(game)
    _check(game.attempts == before_second_attempt and game.score == before_second_score
        and game.lives == before_second_lives,
        label + ": remaining two apples cannot score or damage twice")

    # Next wave follows automatically, and speed rises gradually.
    if not _wait_for_wave_after(game, initial_wave, 3.0):
        _fail(label + ": next complete wave failed after one-apple catch")
        host.queue_free()
        await process_frame
        return
    _verify_wave(game, label + " wave2")
    _check(_wave_speed(game) > initial_speed,
        label + ": progressive fall speed increases between waves")
    var wave_two := int(game.get("wave_index"))
    var wave_two_speed := _wave_speed(game)

    # Simulate all three falling out of reach; this must resolve/skip
    # rather than leaving a frozen, permanently unanswered wave.
    if String(game.get("wave_phase")) != "falling":
        _fail(label + ": second wave should already be falling immediately after spawn")
    else:
        var attempts_before_skip: int = game.attempts
        var points_before_skip: int = game.score
        var lives_before_skip: int = game.lives
        var field: Rect2 = game.call("_game_rect")
        for i in range(game.falling_tiles.size()):
            var tile: Dictionary = game.falling_tiles[i]
            tile["pos"] = Vector2(tile["pos"].x, field.end.y + float(game.APPLE_SIZE.y) + 12.0)
            tile["passed_line"] = true
            game.falling_tiles[i] = tile
        _step(game, 0.02)
        _check(game.attempts == attempts_before_skip + 1 and game.score == points_before_skip,
            label + ": all-missed wave records one missed question but awards no points")
        _check(game.lives == (lives_before_skip - 1 if mode == "Lives" else lives_before_skip),
            label + ": skipped answer deducts one life only in Lives mode")
        _check(String(game.get("wave_phase")) == "clearing",
            label + ": three missed apples resolve wave immediately")
        if not _wait_for_wave_after(game, wave_two, 3.0):
            _fail(label + ": all-missed wave never times out into a new wave")
        else:
            _verify_wave(game, label + " wave3")
            _check(_wave_speed(game) > wave_two_speed,
                label + ": speed increases again after skipped wave")

    # Reset must release every old apple and tween, restore lives and start
    # again with exactly three synced word apples and no stale score.
    game.set_context(ctx)
    await process_frame
    game.set_process(false)
    _check(game.score == 0 and game.attempts == 0 and game.correct_count == 0
        and game.lives == 3 and game.collected_words.is_empty(),
        label + ": retry resets score, attempts, lives, and collected words")
    _check(game.get_node("CollectedWords").get_child_count() == 0,
        label + ": retry removes basket word sprites")
    _check(_count_transients(game) == 0,
        label + ": retry clears all old transient catch effects")
    _check(int(game.get("wave_index")) == initial_wave,
        label + ": retry resets wave progression to first wave")
    _check(absf(_wave_speed(game) - initial_speed) <= 0.01,
        label + ": retry resets speed progression")
    _verify_wave(game, label + " restart")
    host.queue_free()
    await process_frame
    await process_frame


func _verify_wave(game: Control, label: String) -> void:
    _check(game.falling_tiles.size() == 3,
        label + ": exactly three falling apples in the wave")
    if game.falling_tiles.size() != 3:
        return
    var matching := 0
    var x_positions: Array[float] = []
    var ys: Array[float] = []
    var speeds: Array[float] = []
    var words: Array[String] = []
    for tile in game.falling_tiles:
        if bool(tile.get("matching", false)):
            matching += 1
        x_positions.append(float(tile["pos"].x))
        ys.append(float(tile["pos"].y))
        speeds.append(float(tile["speed"]))
        words.append(String(tile["word"]).to_upper())
        var node := tile.get("node") as Control
        var art := node.get_node_or_null("AppleSprite") as TextureRect if node != null else null
        var word := node.get_node_or_null("WordLabel") as Label if node != null else null
        _check(node != null and art != null and word != null and
            art.texture != null and art.texture.resource_path == APPLE_TEXTURE
            and word.text == String(tile["word"]).to_upper(),
            label + ": real glossy apple sprite and readable grammar word")
    _check(matching == 1, label + ": precisely one correct and two wrong words")
    x_positions.sort()
    var field: Rect2 = game.call("_game_rect")
    var apple_size: Vector2 = game.APPLE_SIZE
    var first_center: float = field.position.x + apple_size.x * 0.5 + 84.0
    _check(x_positions[0] >= first_center + 45.0,
        "%s: trio shifted noticeably right of old start lane (left %.1f, previous %.1f)" %
        [label, x_positions[0], first_center])
    # The old lane formation's center was left-heavy (old first center + last
    # safe center, divided by two). A clear positive shift is required, but
    # forcing the group beyond field center would conflict with score safety.
    var last_safe_center := minf(field.end.x - apple_size.x * 0.5 - 12.0,
        game.score_plaque.position.x - apple_size.x * 0.5 - game.APPLE_SPACING_MARGIN)
    var old_group_center := (first_center + last_safe_center) * 0.5
    _check((x_positions[0] + x_positions[1] + x_positions[2]) / 3.0 >=
        old_group_center + 25.0,
        label + ": trio shifted right of previous lane formation")
    _check(x_positions[1] - x_positions[0] >= 220.0 and
        x_positions[2] - x_positions[1] >= 220.0,
        label + ": three distinct safe lanes with space for the basket")
    _check(x_positions[2] + apple_size.x * 0.5 + 9.0 <=
        game.score_plaque.position.x,
        label + ": rightmost apple never passes behind the bottom score plaque")
    _check(ys[0] <= field.position.y + apple_size.y * 0.5 + 12.0 and
        ys[0] >= -apple_size.y * 1.5,
        "%s: all apples enter at top edge, not centered over the playfield (Y %.1f, top %.1f)" %
        [label, ys[0], field.position.y])
    _check(absf(ys[0] - ys[1]) < 1.0 and absf(ys[1] - ys[2]) < 1.0,
        label + ": apples begin at the same height")
    _check(absf(speeds[0] - speeds[1]) < 0.01 and absf(speeds[1] - speeds[2]) < 0.01,
        label + ": all three apples share synchronized descent speed")
    _check(words[0] != words[1] and words[1] != words[2] and words[0] != words[2],
        label + ": distractors and correct word are individually distinguishable")


func _wait_for_three(game: Control, label: String) -> bool:
    if game.falling_tiles.size() == 3:
        _verify_wave(game, label)
        return true
    for i in range(80):
        _step(game, TICK)
        if game.falling_tiles.size() == 3:
            _verify_wave(game, label)
            return true
    _fail(label + ": never formed exactly three apples")
    return false


func _wait_for_phase(game: Control, phase: String, max_seconds: float) -> bool:
    for i in range(int(ceil(max_seconds / TICK))):
        if String(game.get("wave_phase")) == phase:
            return true
        _step(game, TICK)
    return String(game.get("wave_phase")) == phase


func _wait_for_wave_after(game: Control, prior_index: int, max_seconds: float) -> bool:
    for i in range(int(ceil(max_seconds / TICK))):
        if int(game.get("wave_index")) > prior_index and game.falling_tiles.size() == 3:
            return true
        _step(game, TICK)
    return int(game.get("wave_index")) > prior_index and game.falling_tiles.size() == 3


func _force_collision(game: Control, matching: bool, label: String) -> void:
    var index := -1
    for i in range(game.falling_tiles.size()):
        if bool(game.falling_tiles[i]["matching"]) == matching:
            index = i
            break
    if index < 0:
        _fail(label + ": matching=%s apple is absent before collision" % matching)
        return
    var tile: Dictionary = game.falling_tiles[index]
    game.basket_x = float(tile["pos"].x)
    game.basket_velocity = 0.0
    game._sync_character_position()
    var hitbox: Rect2 = game.call("_basket_rect")
    tile["pos"] = hitbox.get_center()
    tile["passed_line"] = false
    game.falling_tiles[index] = tile
    _step(game, 0.01)


func _force_collision_of_remaining(game: Control) -> void:
    if game.falling_tiles.is_empty():
        return
    var tile: Dictionary = game.falling_tiles[0]
    game.basket_x = float(tile["pos"].x)
    game.basket_velocity = 0.0
    game._sync_character_position()
    tile["pos"] = game.call("_basket_rect").get_center()
    tile["passed_line"] = false
    game.falling_tiles[0] = tile
    _step(game, 0.01)


func _tile_y(game: Control) -> float:
    if game.falling_tiles.is_empty():
        return -9999.0
    return float(game.falling_tiles[0]["pos"].y)


func _all_y(game: Control) -> Array[float]:
    var values: Array[float] = []
    for tile in game.falling_tiles:
        values.append(float(Vector2(tile["pos"]).y))
    return values


func _all_x(game: Control) -> Array[float]:
    var values: Array[float] = []
    for tile in game.falling_tiles:
        values.append(float(Vector2(tile["pos"]).x))
    return values


func _wave_speed(game: Control) -> float:
    if game.falling_tiles.size() == 3:
        return float(game.falling_tiles[0]["speed"])
    return float(game.get("wave_speed"))


func _step(game: Control, delta: float) -> void:
    game._process(delta)
    game.set_process(false)


func _count_transients(node: Node) -> int:
    var total := 1 if node.is_in_group("catch_transient_effect") and not node.is_queued_for_deletion() else 0
    for child in node.get_children():
        total += _count_transients(child)
    return total


func _check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        _fail(message)


func _fail(message: String) -> void:
    failures.append(message)
