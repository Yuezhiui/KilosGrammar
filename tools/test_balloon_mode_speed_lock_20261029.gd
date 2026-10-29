extends SceneTree

# Camera-free regression for real Balloon mode limits, difficulty pacing,
# one-second held gesture reload and bounded +100 score speed progression.
const GAME: PackedScene = preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const MODES := ["Seconds", "Lives"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const CAPS := {"Easy": 1.25, "Normal": 1.35, "Hard": 1.45}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var prior_speed := 0.0
    for difficulty in DIFFICULTIES:
        var speed_for_difficulty := 0.0
        for mode in MODES:
            var game := GAME.instantiate() as Control
            _check(game.get_script() != null, difficulty + "/" + mode + ": Balloon script is valid")
            root.add_child(game)
            await process_frame
            game.set_context({"topic": "Noun", "difficulty": difficulty, "game_mode": mode,
                "score": 0, "attempts": 0, "correct": 0, "hearts": 99,
                "time_remaining": 900.0})
            game.set_process(false)
            game.set_physics_process(false)
            var label: String = difficulty + "/" + mode
            var seconds: bool = mode == "Seconds"
            var base_speed: float = game.balloon_float_speed
            speed_for_difficulty = base_speed
            _check(game.round_active and game.timer_running and game.round_time_limit > 7.0,
                label + ": question deadline adapts to slower whole ascent")
            _check(game.time_remaining == (60.0 if seconds else 0.0) and
                game.hearts == (0 if seconds else 3), label + ": exact 60s or 3 hearts mode")
            _check(game.HAND_RAISE_RELOAD_MS == 1000,
                label + ": held hand repeats every second")
            _check(game.balloon_speed_multiplier == 1.0,
                label + ": new game begins with no speed boost")
            _check((game._balloon_hidden_y() - game.BALLOON_EXIT_Y) / base_speed < game.round_time_limit,
                label + ": natural top exit before path-aware timeout")
            var lives_before: int = game.hearts
            var wrong := _wrong_lane(game)
            _check(wrong >= 0, label + ": one wrong balloon is available")
            if wrong >= 0:
                var wrong_target := game.balloons[wrong] as Area2D
                wrong_target.position.y = game.UPPER_LINE_Y + 50.0
                game._handle_balloon_hit(wrong, wrong_target.position)
                _check(game.score == 0 and game.attempts == 1 and game.correct_count == 0,
                    label + ": wrong answer changes attempts, never score")
                _check(game.hearts == lives_before - (0 if seconds else 1),
                    label + ": wrong answer costs a heart only in Lives")
            var first_correct: int = game.pending_valid_lanes[0]
            var valid_target := game.balloons[first_correct] as Area2D
            valid_target.position.y = game.UPPER_LINE_Y + 55.0
            game._handle_balloon_hit(first_correct, valid_target.position)
            var boost_after_first: float = game.balloon_speed_multiplier
            _check(game.score == 100 and boost_after_first > 1.0 and
                is_equal_approx(game.balloon_float_speed, base_speed * boost_after_first),
                label + ": valid pop awards exactly 100 and increases ascent")
            game._handle_balloon_hit(first_correct, valid_target.position)
            _check(game.score == 100, label + ": duplicate hit cannot award twice")
            for i in range(17):
                if not game.round_active or game.pending_valid_lanes.is_empty():
                    game._start_new_round()
                if game.pending_valid_lanes.is_empty():
                    failures.append(label + ": question exhausted before 18 correct pops")
                    break
                var lane: int = game.pending_valid_lanes[0]
                var target := game.balloons[lane] as Area2D
                target.position.y = game.UPPER_LINE_Y + 45.0
                var score_before: int = game.score
                game._handle_balloon_hit(lane, target.position)
                _check(game.score == score_before + 100, label + ": each correct adds exactly 100")
            _check(game.balloon_speed_multiplier <= float(CAPS[difficulty]) + 0.00001 and
                game.balloon_speed_multiplier > 1.0,
                label + ": diminishing boost remains within tier cap")
            var boosted: float = game.balloon_float_speed
            game._start_new_round()
            game.set_process(false)
            var y_before: float = game.balloons[0].position.y
            game._process(0.25)
            game.set_process(false)
            _check(absf((y_before - game.balloons[0].position.y) - boosted * 0.25) < 0.1,
                label + ": fixed-time ascent uses earned speed from concealed start")
            var time_before: float = game.time_remaining
            game._pause()
            game._process(1.5)
            _check(game.balloon_float_speed == boosted and game.time_remaining == time_before,
                label + ": pause freezes clock and retains earned speed")
            game._resume()
            game.set_process(false)
            if seconds:
                game.time_remaining = 0.01
                game._process(0.1)
                _check(game.finishing and game.round_completed and game.get_context()["completion_reason"] == "time_up",
                    label + ": only global Seconds expiry records completion")
            else:
                game.hearts = 1
                game._on_question_timeout()
                _check(game.finishing and game.round_completed and game.get_context()["completion_reason"] == "lives_empty",
                    label + ": only final lost Lives heart records completion")
            game.set_context({"game_mode": mode, "difficulty": difficulty, "score": 0,
                "correct": 0, "attempts": 0, "balloon_round": 0})
            game.set_process(false)
            _check(game.round_active and not game.finishing and game.score == 0 and
                is_equal_approx(game.balloon_float_speed, base_speed) and
                is_equal_approx(game.balloon_speed_multiplier, 1.0),
                label + ": restart resets score and ascent boost")
            game.queue_free()
            await process_frame
        _check(speed_for_difficulty > prior_speed,
            difficulty + ": base ascent speed is strictly faster than prior difficulty")
        prior_speed = speed_for_difficulty
    await create_timer(0.85).timeout
    await process_frame
    for failure in failures.slice(0, 24):
        push_error("BALLOON MODE/SPEED: " + failure)
    print("BALLOON MODE/SPEED %s: %d checks / %d failures" %
        ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
    quit(0 if failures.is_empty() else 1)

func _wrong_lane(game: Control) -> int:
    for lane in range(game.balloons.size()):
        if not game.pending_valid_lanes.has(lane):
            return lane
    return -1

func _check(ok: bool, reason: String) -> void:
    checks += 1
    if not ok:
        failures.append(reason)
