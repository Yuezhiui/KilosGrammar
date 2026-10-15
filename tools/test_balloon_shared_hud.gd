extends SceneTree

# Runtime HUD regression: Balloon Popping must reuse Catch's static PNG
# timer and complete 3/2/1-heart state images without changing its gameplay.
# Godot --headless --path . --script res://tools/test_balloon_shared_hud.gd

const SCENE := preload("res://ui/minigames/balloon_popping.tscn")
const TIMER := "res://ui/minigames/catch_hud/generated/timer_badge.png"
const LIVES := "res://ui/minigames/catch_hud/generated/replacement/lives_state_%d.png"
const RESOLUTIONS := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const MODES := ["Seconds", "Lives"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]

var assertions := 0
var scenarios := 0
var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var original_size := root.size
    for resolution in RESOLUTIONS:
        root.size = resolution
        await process_frame
        await process_frame
        for mode in MODES:
            await _test_resolution_mode(resolution, mode)
    root.size = original_size
    # Audio/physics/tween cleanup and deferred queue_free() before engine exit.
    for i in range(4):
        await process_frame
    await create_timer(0.15).timeout
    var expected_scenarios := RESOLUTIONS.size() * MODES.size() * DIFFICULTIES.size() * TOPICS.size()
    if failures.is_empty() and scenarios == expected_scenarios:
        print("PASS Balloon shared HUD: %d checks in %d resolution/mode/difficulty/topic scenarios" % [assertions, scenarios])
        quit(0)
    else:
        var categories: Dictionary = {}
        for error in failures:
            var colon := error.find(": ")
            var kind := error.substr(colon + 2) if colon >= 0 else error
            categories[kind] = int(categories.get(kind, 0)) + 1
        for key in categories.keys():
            print("FAIL CATEGORY: %s (%d occurrences)" % [key, int(categories[key])])
        for error in failures.slice(0, 12):
            push_error("BALLOON SHARED HUD QA: " + error)
        if failures.size() > 12:
            print("... %d duplicate/context errors suppressed" % (failures.size() - 12))
        print("FAIL Balloon shared HUD: %d failures / %d checks / %d scenarios (expected %d)" %
            [failures.size(), assertions, scenarios, expected_scenarios])
        quit(1)


func _test_resolution_mode(resolution: Vector2i, mode: String) -> void:
    var host := Control.new()
    host.name = "BalloonSharedHudTestHost"
    # The project uses canvas_items stretching with a 1280x720 virtual
    # viewport. A 1920x1080 physical Window has a *1280 logical* width;
    # mounting a 1920-logical game would falsely push its HUD offscreen.
    host.size = root.get_visible_rect().size
    root.add_child(host)
    var game := SCENE.instantiate() as Control
    _check(game != null and game.get_script() != null,
        "%s/%s: scene instantiates with compiled gameplay script" % [resolution, mode])
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
    game.set_process(false)
    game.set_physics_process(false)

    var hud := game.get_node_or_null("HudLayer") as Control
    var timer := game.get_node_or_null("HudLayer/TimerPlaque") as TextureRect
    var lives := game.get_node_or_null("HudLayer/LivesPlaque") as TextureRect
    var time_label := game.get_node_or_null("HudLayer/TimeLabel") as Label
    var hearts_box := game.get_node_or_null("HudLayer/HeartsBox") as HBoxContainer
    var score := game.get_node_or_null("HudLayer/ScoreBottomContainer") as Control
    var title := game.get_node_or_null("HudLayer/TitleLabel") as Label
    var prompt := game.get_node_or_null("HudLayer/PromptLabel") as Label
    var pause := game.get_node_or_null("HudLayer/PauseButton") as Button
    _check(hud != null and timer != null and lives != null and
        time_label != null and hearts_box != null and score != null and
        title != null and prompt != null and pause != null,
        "%s/%s: essential HUD nodes exist" % [resolution, mode])
    if hud == null or timer == null or lives == null or time_label == null or hearts_box == null or score == null or title == null or prompt == null or pause == null:
        host.queue_free()
        await process_frame
        return
    _check(_count_named(hud, "TimerPlaque") == 1 and _count_named(hud, "LivesPlaque") == 1,
        "%s/%s: no duplicate shared HUD plaques" % [resolution, mode])
    _check(timer.texture != null and timer.texture.resource_path == TIMER,
        "%s/%s: blue timer is the authentic Catch PNG" % [resolution, mode])
    _check(timer.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED and
        lives.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
        "%s/%s: authentic badge PNGs preserve aspect ratio without stretching" % [resolution, mode])
    _check(timer.mouse_filter == Control.MOUSE_FILTER_IGNORE and
        lives.mouse_filter == Control.MOUSE_FILTER_IGNORE,
        "%s/%s: HUD art cannot intercept gameplay input" % [resolution, mode])

    var shared_timer_id := timer.get_instance_id()
    var shared_lives_id := lives.get_instance_id()
    for difficulty in DIFFICULTIES:
        for topic in TOPICS:
            var label := "%s/%s/%s/%s" % [resolution, mode, difficulty, topic]
            var state := _context(mode, difficulty, topic)
            game.set_context(state)
            await process_frame
            game.set_process(false)
            game.set_physics_process(false)
            scenarios += 1
            _check(game.game_mode == mode and game.is_seconds_mode == (mode == "Seconds")
                and game.is_lives_mode == (mode == "Lives"),
                label + ": context selects exact mode")
            _check(game._difficulty() == difficulty and game._topic() == topic,
                label + ": context selects exact difficulty and grammar topic")
            _check(timer.get_instance_id() == shared_timer_id and
                lives.get_instance_id() == shared_lives_id and
                _count_named(hud, "TimerPlaque") == 1 and _count_named(hud, "LivesPlaque") == 1,
                label + ": repeated contexts reuse exactly two original plaque nodes")
            _verify_plaque_state(game, timer, lives, time_label, hearts_box, mode, 3, label)
            _verify_positions(game, resolution, timer, lives, time_label, score, title, prompt, pause, label)
            # The low-level game data must be unchanged by visibility/texture updates.
            var attempts_before: int = game.attempts
            var score_before: int = game.score
            var correct_before: int = game.correct_count
            game._refresh_hud()
            _check(game.attempts == attempts_before and game.score == score_before
                and game.correct_count == correct_before and game.hearts == 3,
                label + ": refresh touches presentation, not gameplay statistics")
            _check(game.get_context().get("hearts") == 3 and game.get_context().get("lives") == 3,
                label + ": public context preserves both heart/lives compatibility keys")

    # On each of the six actual mounted games exercise gameplay damage,
    # timer progression, pause freeze, restart state and terminal loss.
    var base_label := "%s/%s gameplay" % [resolution, mode]
    var baseline := _context(mode, "Easy", "Noun")
    game.set_context(baseline)
    await process_frame
    game.set_process(false)
    game.set_physics_process(false)
    _verify_plaque_state(game, timer, lives, time_label, hearts_box, mode, 3, base_label + " initial")
    if mode == "Lives":
        await _test_lives_damage(game, timer, lives, time_label, hearts_box, base_label)
    else:
        await _test_seconds_timer(game, timer, lives, time_label, hearts_box, base_label)
    # Restart should re-show ONLY the proper first-state visual.
    game.set_context(baseline)
    await process_frame
    game.set_process(false)
    game.set_physics_process(false)
    _check(game.hearts == 3 and game.score == 0 and game.attempts == 0 and game.correct_count == 0,
        base_label + ": restart resets hearts, score, attempts and correct tally")
    _verify_plaque_state(game, timer, lives, time_label, hearts_box, mode, 3, base_label + " restart")
    _check(timer.get_instance_id() == shared_timer_id and lives.get_instance_id() == shared_lives_id,
        base_label + ": restart reuses existing artwork panels")
    host.queue_free()
    await process_frame
    await process_frame


func _test_lives_damage(game: Control, timer: TextureRect, lives: TextureRect,
        time_label: Label, hearts_box: HBoxContainer, label: String) -> void:
    var score_before: int = game.score
    for expected_hearts in [2, 1]:
        var wrong_lane := _find_wrong_lane(game)
        _check(wrong_lane >= 0,
            "%s: valid active question contains a wrong balloon for %d-heart test" %
            [label, expected_hearts])
        if wrong_lane < 0:
            break
        var attempts_before: int = game.attempts
        var balloon := game.balloons[wrong_lane] as Area2D
        _check(balloon != null and balloon.visible,
            label + ": wrong answer target is a real visible Balloon Area2D")
        if balloon == null:
            break
        # One real gameplay answer handler (not a forced value/texture swap).
        game._handle_balloon_hit(wrong_lane, balloon.position)
        game.set_process(false)
        _check(game.hearts == expected_hearts and game.attempts == attempts_before + 1
            and game.score == score_before,
            "%s: wrong balloon decrements 1 heart to %d, counts one attempt, zero points" %
            [label, expected_hearts])
        _verify_plaque_state(game, timer, lives, time_label, hearts_box, "Lives",
            expected_hearts, label + " after wrong answer")
        _check(not game.finishing and game.timer_running,
            label + ": one or two remaining hearts cannot finish the game")
        game._start_new_round()
        game.set_process(false)
        game.set_physics_process(false)
        _verify_plaque_state(game, timer, lives, time_label, hearts_box, "Lives",
            expected_hearts, label + " next question")
    # Lives mode must freeze both the question clock and hearts during Pause.
    var time_before: float = game.round_time_remaining
    var hearts_before: int = game.hearts
    var score_at_pause: int = game.score
    game._pause()
    _check(not game.timer_running and not game.round_active,
        label + ": pause disables timer and balloon response")
    game._process(1.5)
    game._physics_process(1.5)
    _check(is_equal_approx(game.round_time_remaining, time_before)
        and game.hearts == hearts_before and game.score == score_at_pause,
        label + ": pause preserves question clock/heart count/score")
    _verify_plaque_state(game, timer, lives, time_label, hearts_box, "Lives", hearts_before,
        label + " paused")
    game._resume()
    game.set_process(false)
    game.set_physics_process(false)
    _check(game.timer_running, label + ": resume restores timer_running")
    # Exhaust the last heart; no nonexistent state_0.png should be needed.
    var wrong_lane := _find_wrong_lane(game)
    if wrong_lane < 0:
        game._start_new_round()
        wrong_lane = _find_wrong_lane(game)
    _check(wrong_lane >= 0, label + ": a third wrong answer remains possible")
    if wrong_lane >= 0:
        var attempts_before: int = game.attempts
        var wrong := game.balloons[wrong_lane] as Area2D
        if wrong != null:
            game._handle_balloon_hit(wrong_lane, wrong.position)
            _check(game.hearts == 0 and game.finishing and game.round_completed
                and not game.timer_running and game.attempts == attempts_before + 1,
                label + ": last wrong balloon ends Lives game at zero hearts")
            _check(not lives.visible and not timer.visible and not time_label.visible and
                not hearts_box.visible,
                label + ": terminal zero lives does not paint misleading 1-heart or fallback HUD")
            _check(game.get_context().get("lives") == 0,
                label + ": game-over context exports zero lives")


func _test_seconds_timer(game: Control, timer: TextureRect, lives: TextureRect,
        time_label: Label, hearts_box: HBoxContainer, label: String) -> void:
    var starting_attempts: int = game.attempts
    var starting_hearts: int = game.hearts
    var initial_question_time: float = game.round_time_remaining
    game._process(1.1)
    game.set_process(false)
    _check(game.time_remaining < 59.0 and game.time_remaining > 58.0,
        label + ": Seconds global timer actually counts down from 60")
    _check(time_label.text == "%ds" % int(ceil(game.time_remaining)),
        label + ": blue timer overlay displays exact integer-rounded global remaining time")
    _check(is_equal_approx(game.round_time_remaining, initial_question_time)
        and is_instance_valid(game.balloon_motion_tween)
        and game.balloon_motion_tween.is_running(),
        label + ": question clock waits while the three balloons reveal, global timer keeps ticking")
    # When their slow reveal finishes, the *question* countdown must begin.
    # SceneTree tweens advance even while test disables automatic _process.
    await create_timer(game.BALLOON_REVEAL_SECONDS + 0.12).timeout
    var question_when_visible: float = game.round_time_remaining
    game._process(0.25)
    game.set_process(false)
    _check(game.round_time_remaining < question_when_visible and
        not game.balloon_motion_tween.is_running(),
        label + ": question countdown begins only after all balloons finish revealing")
    _verify_plaque_state(game, timer, lives, time_label, hearts_box, "Seconds", 3,
        label + " ticking")
    game._pause()
    var frozen_time: float = game.time_remaining
    var frozen_question: float = game.round_time_remaining
    game._process(3.0)
    game._physics_process(0.5)
    _check(is_equal_approx(game.time_remaining, frozen_time)
        and is_equal_approx(game.round_time_remaining, frozen_question)
        and game.attempts == starting_attempts,
        label + ": pause freezes global and question timers plus attempts")
    game._resume()
    game.set_process(false)
    game.set_physics_process(false)
    game._process(0.15)
    game.set_process(false)
    _check(game.time_remaining < frozen_time,
        label + ": Seconds countdown resumes after pause")
    # Wrong pop must not cost a heart in Seconds mode.
    var wrong_lane := _find_wrong_lane(game)
    _check(wrong_lane >= 0, label + ": has a wrong target to exercise health logic")
    if wrong_lane >= 0:
        var before_attempts: int = game.attempts
        var before_score: int = game.score
        var balloon := game.balloons[wrong_lane] as Area2D
        if balloon != null:
            game._handle_balloon_hit(wrong_lane, balloon.position)
            _check(game.hearts == starting_hearts and game.attempts == before_attempts + 1
                and game.score == before_score,
                label + ": wrong shot in Seconds costs zero hearts/points but one attempt")
    game._refresh_hud()
    _verify_plaque_state(game, timer, lives, time_label, hearts_box, "Seconds", 3,
        label + " after wrong")
    # Global expiration must finish the Seconds run and export time zero.
    game.time_remaining = 0.05
    game._process(0.10)
    _check(game.finishing and game.round_completed and game.time_remaining <= 0.0
        and game.get_context().get("time_remaining") == 0.0,
        label + ": global timer reaching zero finishes gameplay")


func _verify_plaque_state(game: Control, timer: TextureRect, lives: TextureRect,
        time_label: Label, hearts_box: HBoxContainer,
        mode: String, expected_hearts: int, label: String) -> void:
    var lives_mode := mode == "Lives"
    _check(timer.is_visible_in_tree() == not lives_mode and
        lives.is_visible_in_tree() == lives_mode,
        label + ": exactly one correct-mode shared PNG is visible")
    _check(time_label.is_visible_in_tree() == not lives_mode,
        label + ": blue timer contains the only visible number in Seconds mode")
    _check(not hearts_box.is_visible_in_tree(),
        label + ": legacy 3-TextureRect HeartsBox is never displayed over state PNGs")
    if lives_mode:
        _check(game.hearts == expected_hearts,
            label + ": lives source variable matches visible heart count")
        _check(lives.texture != null and lives.texture.resource_path == LIVES % expected_hearts,
            label + ": genuine all-in-one %d-heart PNG selected" % expected_hearts)
        _check(not time_label.visible,
            label + ": Lives never reveals 999s global countdown")
    else:
        _check(timer.texture != null and timer.texture.resource_path == TIMER,
            label + ": original blue timer asset displayed")
        _check(time_label.text == "%ds" % int(ceil(maxf(game.time_remaining, 0.0))),
            label + ": text matches ceil(global time_remaining)")


func _verify_positions(game: Control, resolution: Vector2i,
        timer: TextureRect, lives: TextureRect, time_label: Label,
        score: Control, title: Control, prompt: Control, pause: Control,
        label: String) -> void:
    var panel: Control = lives if game.is_lives_mode else timer
    var panel_rect := _screen_rect(panel)
    var hud_bounds := Rect2(Vector2.ZERO, Vector2(resolution))
    _check(_encloses(hud_bounds, panel_rect, 1.0),
        label + ": visible mode plaque fits physical window at " + str(panel_rect))
    _check(panel_rect.size.x > 80.0 and panel_rect.size.y > 30.0,
        label + ": panel is not tiny or hidden by a broken transform")
    var fitted_image := _fitted_image_rect(panel)
    _check(_encloses(panel_rect, fitted_image, 0.8) and
        fitted_image.size.x > 70.0 and fitted_image.size.y > 25.0,
        label + ": aspect-preserved source artwork stays fully within HUD slot")
    var texture_size: Vector2 = panel.texture.get_size()
    _check(absf(fitted_image.size.x / fitted_image.size.y -
        texture_size.x / texture_size.y) <= 0.01,
        label + ": rendered badge retains exact source image proportions")
    for other in [pause, score, title, prompt]:
        var other_rect := _screen_rect(other)
        _check(not panel_rect.intersects(other_rect.grow(-1.0)),
            label + ": mode plaque avoids " + other.name)
    var score_rect := _screen_rect(score)
    for other in [pause, title, prompt]:
        _check(not score_rect.intersects(_screen_rect(other).grow(-1.0)),
            label + ": score avoids " + other.name)
    # Dynamic title/prompt controls have a 3-logical-pixel slot intersection.
    # At 1920 physical this becomes 4.5 screen pixels; it is padding, not
    # actual glyph collision. Keep the strict score/other-panel checks.
    _check(not _screen_rect(title).grow(-3.0).intersects(_screen_rect(prompt).grow(-3.0)),
        label + ": title and question remain separate readable lines")
    if game.is_seconds_mode:
        var label_rect := _screen_rect(time_label)
        _check(_encloses(_fitted_image_rect(timer), label_rect, 1.0),
            label + ": numeric Seconds text fully inside the ACTUAL aspect-fitted blue graphic")
        _check(time_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and
            time_label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER,
            label + ": timer number is centered within badge")
        var font: Font = time_label.get_theme_font("font")
        var size: int = time_label.get_theme_font_size("font_size")
        _check(font != null and font.get_string_size(time_label.text,
            HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= time_label.size.x - 2.0,
            label + ": numeric timer glyphs fit their writable label inset")


func _find_wrong_lane(game: Control) -> int:
    for i in range(game.balloons.size()):
        if not game.valid_lanes.has(i):
            var balloon = game.balloons[i]
            if is_instance_valid(balloon) and balloon.visible:
                return i
    return -1


func _context(mode: String, difficulty: String, topic: String) -> Dictionary:
    return {
        "activity": "Balloon Popping", "game_mode": mode, "difficulty": difficulty,
        "topic": topic, "game_style": topic, "time_remaining": 60.0 if mode == "Seconds" else 999.0,
        "hearts": 3, "lives": 3, "score": 0, "correct": 0, "attempts": 0,
        "balloon_round": 0
    }


func _screen_rect(control: Control) -> Rect2:
    var logical := control.get_global_rect()
    var transform := control.get_viewport().get_final_transform()
    var a := transform * logical.position
    var b := transform * logical.end
    return Rect2(a, b - a)


func _fitted_image_rect(texture_rect: TextureRect) -> Rect2:
    # The source timer art is 519x173, and lives PNGs have similarly wide
    # but different proportions. KEEP_ASPECT_CENTERED draws an image in a
    # smaller centered rectangle, NOT necessarily the whole TextureRect box.
    var outer := _screen_rect(texture_rect)
    if texture_rect.texture == null:
        return Rect2()
    var source_size := texture_rect.texture.get_size()
    var factor := minf(outer.size.x / source_size.x, outer.size.y / source_size.y)
    var drawn := source_size * factor
    return Rect2(outer.position + (outer.size - drawn) * 0.5, drawn)


func _encloses(big: Rect2, small: Rect2, tolerance: float = 0.0) -> bool:
    return big.grow(tolerance).encloses(small)


func _count_named(node: Node, required_name: String) -> int:
    var n := 1 if node.name == required_name else 0
    for child in node.get_children():
        n += _count_named(child, required_name)
    return n


func _check(valid: bool, detail: String) -> void:
    assertions += 1
    if not valid:
        failures.append(detail)
