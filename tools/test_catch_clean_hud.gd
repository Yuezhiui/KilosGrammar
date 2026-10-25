extends SceneTree

# Headless regression for the objective-free Catch HUD with one recorded voice player.
# Godot 4.7.2 --headless --path . --script res://tools/test_catch_clean_hud.gd
# Runs 80 real scene configurations: two windows, five topics, two modes,
# four original characters. Each configuration catches both types of fruit
# through _update_tiles() and then resets its scene.

const SCENE_PATH := "res://ui/minigames/catch_word.tscn"
const SOURCE_PATH := "res://ui/minigames/catch_word.gd"
const ART := "res://ui/minigames/catch_hud/generated/"
const HEART_ART := ART + "replacement/"
const OLD_APPLE := "res://Components/Apple.png"
const NEW_APPLE := ART + "character/word_apple.png"
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const MODES := ["Seconds", "Lives"]
const CHARACTERS := ["Boy", "Girl", "Grandma", "Grandpa"]
const WINDOWS := [Vector2i(1280, 720), Vector2i(875, 500)]
const REMOVED := ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]
const HUD_ART := {
    "TitlePlaque": "title_board.png",
    "TimerPlaque": "timer_badge.png",
    "PausePlaque": "pause_badge.png",
    "ScorePlaque": "score_board.png"
}
const APPLE_SIZE := Vector2(106.0, 109.0)

var checks := 0
var scenarios := 0
var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var original_size := root.size
    var source := FileAccess.get_file_as_string(SOURCE_PATH).to_lower()
    _check(not source.is_empty(), "Catch gameplay source can be read")
    for token in ["tts_speak(", "_play_sound(", "play_sfx(", "sfx_player"]:
        _check(not source.contains(token), "Catch uses recorded feedback without obsolete audio code: " + token)
    _check(source.contains("catchvoiceplayer"), "Catch code creates the approved recorded voice player")
    var packed := load(SCENE_PATH) as PackedScene
    _check(packed != null, "Catch scene resource loads")
    if packed != null:
        var authored := packed.instantiate()
        _check(authored != null and authored.get_script() != null, "Catch gameplay script compiled")
        if authored != null:
            for removed in REMOVED:
                _check(authored.get_node_or_null("HUDLayer/HUD/" + removed) == null,
                    "Editor scene omits deleted control " + removed)
            _check(_count_audio(authored) == 0, "Editor scene has no audio playback nodes")
            authored.free()
        for physical in WINDOWS:
            await _verify_window(packed, physical)
    root.size = original_size
    # AudioStreamPlayer and MP3 playback cleanup is handed off to the audio
    # server; allow deferred scene frees and an audio processing pass before
    # the one-shot headless SceneTree exits.
    for cleanup_frame in range(4):
        await process_frame
    await create_timer(0.15).timeout
    if failures.is_empty() and scenarios == 80:
        print("PASS clean Catch HUD: %d checks across %d real window/topic/mode/character scenarios" %
            [checks, scenarios])
        quit(0)
    else:
        for failure in failures.slice(0, 35):
            push_error("CLEAN CATCH HUD QA: " + failure)
        if failures.size() > 35:
            print("... %d further failures suppressed" % (failures.size() - 35))
        print("FAIL clean Catch HUD: %d failures, %d checks, %d scenarios" %
            [failures.size(), checks, scenarios])
        quit(1)


func _verify_window(packed: PackedScene, physical: Vector2i) -> void:
    root.size = physical
    await process_frame
    await process_frame
    var original_children := root.get_child_count()
    var host := Control.new()
    host.name = "CleanHUDHost"
    host.size = Vector2(physical)
    root.add_child(host)
    var game := packed.instantiate() as Control
    _check(game != null and game.get_script() != null,
        "%s: loaded scene has an attached compiled script" % physical)
    if game == null or game.get_script() == null:
        host.queue_free()
        await process_frame
        return
    host.add_child(game)
    game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    await process_frame
    await process_frame
    game.set_process(false)
    var hud := game.get_node_or_null("HUDLayer/HUD") as Control
    var number := game.get_node_or_null("ScoreDrawLayer/ScoreBottomContainer/ScoreNumber") as Label
    var prompt := game.get_node_or_null("HUDLayer/HUD/PromptLabel") as Label
    var apples := game.get_node_or_null("CollectedWords") as Node2D
    _check(hud != null and number != null and prompt != null and apples != null,
        "%s: required HUD and basket nodes exist" % physical)
    if hud == null or number == null or prompt == null or apples == null:
        host.queue_free()
        await process_frame
        return
    for topic in TOPICS:
        for mode in MODES:
            for character in CHARACTERS:
                var ctx := {"topic": topic, "game_mode": mode, "difficulty": "Normal",
                    "catch_character": character, "catch_map": "City"}
                game.set_context(ctx)
                await process_frame
                game.set_process(false)
                scenarios += 1
                var label := "%s/%s/%s/%s" % [physical, topic, mode, character]
                _check(game.topic == topic and game.game_mode == mode
                    and game.selected_character == character, label + ": context selects correct mode/topic/original character")
                _verify_hud(game, hud, prompt, number, physical, topic, mode, label)
                await _verify_catches_and_retry(game, ctx, mode, label)
    host.queue_free()
    await process_frame
    await process_frame
    _check(root.get_child_count() == original_children,
        "%s: no orphan scene root nodes after all configurations" % physical)


func _verify_hud(game: Control, hud: Control, prompt: Label, number: Label,
        physical: Vector2i, topic: String, mode: String, label: String) -> void:
    for removed in REMOVED:
        _check(hud.get_node_or_null(removed) == null,
            label + ": deleted HUD element is absent: " + removed)
    var voice := game.get_node_or_null("CatchVoicePlayer") as AudioStreamPlayer
    _check(voice != null and _count_audio(game) == 1,
        label + ": only the approved CatchVoicePlayer audio node exists")
    var title := hud.get_node_or_null("TitlePlaque") as TextureRect
    var timer := hud.get_node_or_null("TimerPlaque") as TextureRect
    var lives := hud.get_node_or_null("LivesPlaque") as TextureRect
    var pause := hud.get_node_or_null("PausePlaque") as TextureRect
    var score := game.get_node_or_null("ScoreDrawLayer/ScorePlaque") as TextureRect
    if title == null or timer == null or lives == null or pause == null or score == null:
        _fail(label + ": essential title/mode/pause/score plaques are missing")
        return
    for name in HUD_ART:
        var plaque := game.get_node_or_null("ScoreDrawLayer/ScorePlaque") as TextureRect if name == "ScorePlaque" else hud.get_node_or_null(String(name)) as TextureRect
        _check(plaque != null and plaque.texture != null
            and plaque.texture.resource_path == ART + String(HUD_ART[name]),
            label + ": authentic PNG for " + String(name))
    _check(title.is_visible_in_tree() and pause.is_visible_in_tree()
        and score.is_visible_in_tree(), label + ": title, pause, score visibly remain")
    _check(timer.is_visible_in_tree() == (mode == "Seconds")
        and lives.is_visible_in_tree() == (mode == "Lives"),
        label + ": only the selected timer or static-lives meter displays")
    if mode == "Lives":
        _check(lives.texture != null and lives.texture.resource_path == HEART_ART + "lives_state_3.png",
            label + ": initial full-lives PNG")
    var timer_value := hud.get_node_or_null("TimeLabel") as Label
    _check(timer_value != null and timer_value.is_visible_in_tree() == (mode == "Seconds"),
        label + ": live timer text only in Seconds mode")
    var article := "AN" if topic in ["Adjective", "Adverb"] else "A"
    var question := "WHICH WORD IS %s %s?" % [article, topic.to_upper()]
    _check(prompt.is_visible_in_tree() and prompt.text == question,
        label + ": grammar question remains on the title plaque")
    var font := prompt.get_theme_font("font")
    var font_size := prompt.get_theme_font_size("font_size")
    _check(font != null and font.get_string_size(prompt.text,
        HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= prompt.size.x - 2.0,
        label + ": question glyphs fit without clipping")
    _check(title.get_global_rect().encloses(prompt.get_global_rect().grow(-0.5)),
        label + ": grammar question stays within title board")
    _check(number.is_visible_in_tree() and number.text == "0"
        and score.get_global_rect().encloses(number.get_global_rect().grow(-0.5)),
        label + ": score zero appears inside original score plaque")
    for hidden in ["TitleLabel", "TitleTheLabel", "TitleWordLabel", "ScoreLabel"]:
        var old_label := hud.get_node_or_null(hidden) as Label
        _check(old_label == null or not old_label.is_visible_in_tree(),
            label + ": baked text is not duplicated by " + hidden)
    var hearts_box := hud.get_node_or_null("HeartsBox") as HBoxContainer
    _check(hearts_box == null or not hearts_box.is_visible_in_tree(),
        label + ": no legacy heart sprites overlay the static heart bitmap")
    var visible_labels: Array[Label] = []
    _collect_visible_labels(hud, visible_labels)
    # The numeric score is on the gameplay canvas, while the other labels
    # remain on the higher HUD canvas.
    if number.is_visible_in_tree():
        visible_labels.append(number)
    _check(visible_labels.size() == (3 if mode == "Seconds" else 2),
        "%s: only question, score%s remain visible (found %d)" %
        [label, ", timer" if mode == "Seconds" else "", visible_labels.size()])
    var bounds := Rect2(Vector2.ZERO, hud.get_viewport_rect().size)
    var projected := Vector2(float(physical.x) / bounds.size.x,
        float(physical.y) / bounds.size.y)
    for control in [title, pause, score, timer if mode == "Seconds" else lives, prompt, number]:
        var rect: Rect2 = control.get_global_rect()
        _check(bounds.encloses(rect.grow(-0.3)),
            label + ": " + control.name + " stays inside logical window")
        _check(Rect2(Vector2.ZERO, Vector2(physical)).encloses(
            Rect2(rect.position * projected, rect.size * projected).grow(-0.25)),
            label + ": " + control.name + " stays inside actual screen")
    _check(not title.get_global_rect().intersects(pause.get_global_rect())
        and not title.get_global_rect().intersects(
            timer.get_global_rect() if mode == "Seconds" else lives.get_global_rect()),
        label + ": question board clears top-right controls")
    _check(not score.get_global_rect().intersects(pause.get_global_rect()),
        label + ": score avoids pause button")


func _verify_catches_and_retry(game: Control, ctx: Dictionary,
        mode: String, label: String) -> void:
    var apples := game.get_node("CollectedWords") as Node2D
    var original_voice := game.get_node_or_null("CatchVoicePlayer") as AudioStreamPlayer
    _check(original_voice != null and _count_audio(game) == 1,
        label + ": one voice player is allocated at start, not per catch")
    game._pause()
    var before_pause: Array = game.falling_tiles.duplicate(true)
    game._process(0.35)
    _check(game.falling_tiles == before_pause, label + ": pause freezes falling words")
    game._resume()
    game.set_process(false)
    _check(game.falling_tiles.size() == 3,
        label + ": live starting wave contains three apples")
    if String(game.get("wave_phase")) == "reading":
        game._update_spawning(float(game.spawn_interval) + 0.02)
    _check(String(game.get("wave_phase")) == "falling",
        label + ": starting wave enters active falling state")
    _make_collision(game, true, label)
    _check(game.score >= 100 and game.attempts == 1
        and game.correct_count == 1 and game.collected_words.size() == 1,
        label + ": real correct-apple collision awards score and one catch")
    _check(apples.get_child_count() == 1, label + ": basket paints exactly one apple")
    if apples.get_child_count() == 1:
        var fruit := apples.get_child(0) as TextureRect
        _check(fruit != null and fruit.texture != null
            and fruit.texture.resource_path == OLD_APPLE
            and fruit.get_child_count() > 0 and fruit.get_child(0) is Label,
            label + ": caught fruit uses ORIGINAL apple and word")
    var score_after_correct: int = game.score
    _check(String(game.get("wave_phase")) == "clearing",
        label + ": first catch resolves the wave")
    game._update_spawning(float(game.WAVE_CLEAR_SECONDS) + 0.02)
    await process_frame
    game.set_process(false)
    _check(game.falling_tiles.size() == 3,
        label + ": next wave spawns exactly three new apples")
    if String(game.get("wave_phase")) == "reading":
        game._update_spawning(float(game.spawn_interval) + 0.02)
    _make_collision(game, false, label)
    _check(game.attempts == 2 and game.correct_count == 1
        and game.score == score_after_correct and game.streak == 0,
        label + ": real wrong-apple collision resets streak without extra score")
    _check(game.lives == (2 if mode == "Lives" else 3),
        label + ": wrong catch changes lives only in Lives mode")
    if mode == "Lives":
        var hearts := game.get_node("HUDLayer/HUD/LivesPlaque") as TextureRect
        _check(hearts.texture != null
            and hearts.texture.resource_path == HEART_ART + "lives_state_2.png",
            label + ": wrong catch swaps to exactly two-heart static image")
    _check(_count_audio(game) == 1 and game.get_node_or_null("CatchVoicePlayer") is AudioStreamPlayer,
        label + ": fruit catches reuse the single recorded voice player")
    _check(original_voice != null and game.get_node_or_null("CatchVoicePlayer") == original_voice
        and original_voice.stream != null,
        label + ": both answer outcomes use recorded stream on the same persistent player")
    game.set_context(ctx)
    await process_frame
    game.set_process(false)
    _check(original_voice != null and game.get_node_or_null("CatchVoicePlayer") == original_voice
        and _count_audio(game) == 1 and not original_voice.playing,
        label + ": retry stops the previous voice and preserves exactly one player")
    _check(game.score == 0 and game.attempts == 0 and game.correct_count == 0
        and game.streak == 0 and game.lives == 3 and game.collected_words.is_empty(),
        label + ": restarting clears gameplay counters and restores lives")
    _check(apples.get_child_count() == 0,
        label + ": restarting removes collected fruit and word labels")
    _check(_count_transients(game) == 0, label + ": restarting removes transient visual effects")
    _check(game.falling_tiles.size() == 3,
        label + ": restarted round has exactly three synchronized apples")
    var has_match := false
    for tile in game.falling_tiles:
        if bool(tile["matching"]) and not bool(tile.get("passed_line", false)):
            has_match = true
    _check(has_match, label + ": new round starts with at least one catchable correct apple")


func _make_collision(game: Control, matching: bool, label: String) -> void:
    var index := -1
    for candidate in range(game.falling_tiles.size()):
        if bool(game.falling_tiles[candidate].get("matching", false)) == matching:
            index = candidate
            break
    if index < 0:
        _fail(label + ": wave is missing the " + ("correct" if matching else "wrong") + " apple")
        return
    var tile: Dictionary = game.falling_tiles[index]
    _check(bool(tile["matching"]) == matching,
        label + ": spawned apple has requested grammar correctness")
    var rendered := tile.get("node") as Control
    var texture := rendered.get_node_or_null("AppleSprite") as TextureRect if rendered != null else null
    _check(texture != null and texture.texture != null
        and texture.texture.resource_path == NEW_APPLE,
        label + ": falling target displays glossy apple artwork")
    game.basket_x = float(tile["pos"].x)
    game.basket_velocity = 0.0
    game._sync_character_position()
    var basket: Rect2 = game.call("_basket_rect")
    tile["pos"] = basket.get_center()
    tile["passed_line"] = false
    game.falling_tiles[index] = tile
    game._update_tiles(0.02)


func _collect_visible_labels(node: Node, labels: Array[Label]) -> void:
    if node is Label and node.is_visible_in_tree():
        labels.append(node as Label)
    for child in node.get_children():
        _collect_visible_labels(child, labels)


func _count_audio(node: Node) -> int:
    var result := 1 if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D else 0
    for child in node.get_children():
        result += _count_audio(child)
    return result


func _count_transients(node: Node) -> int:
    var result := 1 if node.is_in_group("catch_transient_effect") and not node.is_queued_for_deletion() else 0
    for child in node.get_children():
        result += _count_transients(child)
    return result


func _check(valid: bool, detail: String) -> void:
    checks += 1
    if not valid:
        _fail(detail)


func _fail(detail: String) -> void:
    failures.append(detail)
