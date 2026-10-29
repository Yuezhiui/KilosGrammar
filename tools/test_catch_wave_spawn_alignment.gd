extends SceneTree

# Top-edge and viewport-alignment QA for immediately falling three-apple
# waves. Real scene transforms, scoreboard and apple graphics are inspected.
# Run Godot --headless --path . --script res://tools/test_catch_wave_spawn_alignment.gd
const SCENE := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const RESOLUTIONS := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1600, 900)]
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const CHARACTERS := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const MODES := ["Seconds", "Lives"]

var checked := 0
var cases := 0
var errors: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var original_size := root.size
    for resolution in RESOLUTIONS:
        root.size = resolution
        await process_frame
        await process_frame
        for topic in TOPICS:
            for character in CHARACTERS:
                for mode in MODES:
                    await _case(resolution, topic, character, mode)
    root.size = original_size
    # Permit engine deferred deletes and recorded-voice playback cleanup to
    # complete after the final scene exits before ending the test process.
    for cleanup_frame in range(4):
        await process_frame
    await create_timer(0.15).timeout
    if errors.is_empty() and cases == RESOLUTIONS.size() * TOPICS.size() * CHARACTERS.size() * MODES.size():
        print("PASS Catch wave alignment: %d assertions in %d viewport/topic/character/mode cases" % [checked, cases])
        quit(0)
    else:
        for item in errors.slice(0, 30):
            push_error("WAVE ALIGNMENT QA: " + item)
        if errors.size() > 30:
            print("... %d additional failures suppressed" % (errors.size() - 30))
        print("FAIL Catch wave alignment: %d failures of %d checks across %d cases" % [errors.size(), checked, cases])
        quit(1)


func _case(resolution: Vector2i, topic: String, character: String, mode: String) -> void:
    var host := Control.new()
    host.name = "AlignmentHost"
    host.size = Vector2(resolution)
    root.add_child(host)
    var game := SCENE.instantiate() as Control
    var context := {"topic": topic, "catch_character": character,
        "game_mode": mode, "difficulty": "Normal"}
    var name := "%s/%s/%s/%s" % [resolution, topic, character, mode]
    _check(game != null and game.get_script() != null, name + ": gameplay scene loads")
    if game == null or game.get_script() == null:
        host.queue_free()
        await process_frame
        return
    host.add_child(game)
    game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    await process_frame
    game.set_process(false)
    game.set_context(context)
    await process_frame
    game.set_process(false)
    cases += 1
    _check(game.topic == topic and game.selected_character == character and game.game_mode == mode,
        name + ": context selection correct")
    _verify_formation(game, resolution, name + " first")
    _check(String(game.wave_phase) == "falling",
        name + ": wave is falling from the moment it spawns")

    # The very first tick moves every apple equally, without entering a
    # reading pause. None of the three options is allowed to blink or jump.
    var before: Array[Vector2] = _tile_positions(game)
    game._process(0.05)
    game.set_process(false)
    var after: Array[Vector2] = _tile_positions(game)
    _check(after.size() == 3 and before.size() == 3,
        name + ": all three apples remain visible for the first fall tick")
    if before.size() == 3 and after.size() == 3:
        for i in range(3):
            _check(after[i].y - before[i].y > 0.05 and absf(after[i].x - before[i].x) <= 0.01,
                "%s: apple %d moves down immediately without horizontal drift" % [name, i])
        _check(absf(after[0].y - after[1].y) <= 0.01 and
            absf(after[1].y - after[2].y) <= 0.01,
            name + ": three apples stay at identical Y through the first tick")

    # Force a legitimate correct-apple catch and verify the NEXT wave starts
    # at the same top row with the same viewport-safe lane geometry.
    for i in range(game.falling_tiles.size()):
        var tile: Dictionary = game.falling_tiles[i]
        if bool(tile.get("matching", false)):
            game.basket_x = float(Vector2(tile["pos"]).x)
            game.basket_velocity = 0.0
            game._sync_character_position()
            tile["pos"] = Rect2(game._basket_rect()).get_center()
            tile["passed_line"] = false
            game.falling_tiles[i] = tile
            break
    game._process(0.01)
    game.set_process(false)
    _check(game.correct_count == 1 and game.attempts == 1 and game.score >= 100,
        name + ": first-wave correct catch scores exactly once")
    _check(String(game.wave_phase) == "clearing",
        name + ": first-wave catch resolves before new formation")
    game._update_spawning(float(game.WAVE_CLEAR_SECONDS) + 0.05)
    _check(int(game.wave_index) == 2,
        name + ": next synchronized wave automatically arrives")
    _verify_formation(game, resolution, name + " after catch")
    game.set_context(context)
    await process_frame
    game.set_process(false)
    _check(game.score == 0 and game.attempts == 0 and game.correct_count == 0
        and int(game.wave_index) == 1,
        name + ": retry resets scoring and wave progression")
    _verify_formation(game, resolution, name + " retry")
    host.queue_free()
    await process_frame


func _verify_formation(game: Control, resolution: Vector2i, name: String) -> void:
    _check(game.falling_tiles.size() == 3,
        name + ": exactly three synchronized apples")
    if game.falling_tiles.size() != 3:
        return
    var score := game.get_node("ScoreDrawLayer/ScorePlaque") as Control
    # Godot uses a 1280-wide logical CanvasItem coordinate system even when
    # the physical Window is 875 pixels wide (canvas_items stretch).
    # Compare PHYSICAL screen rectangles after applying final_transform;
    # comparing raw get_global_rect() to root.size gives false failures.
    var score_rect := _screen_rect(score)
    var left_to_right: Array[float] = []
    var ys: Array[float] = []
    var matching := 0
    var speeds: Array[float] = []
    for tile in game.falling_tiles:
        var pos: Vector2 = tile["pos"]
        var apple := tile["node"] as Control
        var rect: Rect2 = _screen_rect(apple)
        var score_height_y := score_rect.position.y + score_rect.size.y * 0.5
        # Any apple crossing the scoreboard's vertical region must have
        # horizontal clearance throughout its fall (same X every frame).
        var projected_at_score := Rect2(
            Vector2(rect.position.x, score_height_y - rect.size.y * 0.5),
            rect.size)
        _check(not projected_at_score.intersects(score_rect.grow(4.0)),
            "%s: lane x=%.1f never crosses SCORE panel x=%.1f..%.1f" %
            [name, pos.x, score_rect.position.x, score_rect.end.x])
        _check(rect.position.x >= -0.75 and rect.end.x <= float(resolution.x) + 0.75,
            "%s: apple remains horizontally in actual %dpx viewport, rect=%s" %
            [name, resolution.x, rect])
        left_to_right.append(pos.x)
        ys.append(pos.y)
        speeds.append(float(tile["speed"]))
        if bool(tile.get("matching", false)):
            matching += 1
    left_to_right.sort()
    _check(left_to_right[0] < left_to_right[1] and left_to_right[1] < left_to_right[2],
        name + ": three lanes are distinct and ordered")
    _check(matching == 1, name + ": exactly one correct answer in each wave")
    _check(absf(ys[0] - ys[1]) < 0.01 and absf(ys[1] - ys[2]) < 0.01,
        name + ": all wave apples spawn at identical heights")
    _check(absf(speeds[0] - speeds[1]) < 0.01 and absf(speeds[1] - speeds[2]) < 0.01,
        name + ": all wave apples fall at identical speed")
    _check(ys[0] <= float(resolution.y) * 0.05,
        "%s: apple starts at top viewport edge, not centered (spawn Y %.1f)" %
        [name, ys[0]])
    _check(String(game.wave_phase) == "falling",
        name + ": new wave moves immediately rather than entering reading phase")


func _tile_positions(game: Control) -> Array[Vector2]:
    var result: Array[Vector2] = []
    for tile in game.falling_tiles:
        result.append(Vector2(tile["pos"]))
    return result


func _screen_rect(control: Control) -> Rect2:
    var logical: Rect2 = control.get_global_rect()
    var transform: Transform2D = control.get_viewport().get_final_transform()
    var first: Vector2 = transform * logical.position
    var last: Vector2 = transform * logical.end
    return Rect2(first, last - first)


func _check(valid: bool, description: String) -> void:
    checked += 1
    if not valid:
        errors.append(description)
