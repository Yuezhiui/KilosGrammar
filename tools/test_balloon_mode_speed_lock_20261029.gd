extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_balloon_mode_speed_lock_20261029.gd
# Real Balloon scene, both modes and three difficulty tiers, no camera/DB.

const BALLOON: PackedScene = preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]
const BASE_SPEEDS := {"Easy": 52.0, "Normal": 98.0, "Hard": 154.0}
const CEILINGS := {"Easy": 1.25, "Normal": 1.35, "Hard": 1.45}

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for mode in MODES:
		for difficulty in DIFFICULTIES:
			await _exercise_mode(mode, difficulty)
			await _exercise_post_gain_wrong_and_timeout(mode, difficulty)
			await _exercise_global_mode_boundary(mode, difficulty)
	# One pending 0.62s next-round timer may outlive the scene under test.
	await create_timer(0.85).timeout
	for frame in range(3):
		await process_frame
	if failures.is_empty():
		print("PASS Balloon mode/speed lock: %d checks / 6 mode-difficulty scenarios" % checks)
		quit(0)
	else:
		for failure in failures.slice(0, 25):
			push_error("BALLOON MODE/SPEED: " + failure)
		print("FAIL Balloon mode/speed lock: %d failures / %d checks" % [failures.size(), checks])
		quit(1)


func _exercise_mode(mode: String, difficulty: String) -> void:
	var title := "%s/%s" % [mode, difficulty]
	var game := BALLOON.instantiate() as Control
	root.add_child(game)
	await process_frame
	# Intentionally pass hostile prior-run lengths: mode limits override them.
	game.set_context({
		"activity": "Balloon Popping", "topic": "Noun", "difficulty": difficulty,
		"game_mode": mode, "score": 0, "correct": 0, "attempts": 0,
		"time_remaining": 900.0, "hearts": 99, "lives": 99, "balloon_round": 0
	})
	game.set_process(false)
	game.set_physics_process(false)
	var is_seconds := mode == "Seconds"
	var ceiling: float = CEILINGS[difficulty]
	var base_speed: float = BASE_SPEEDS[difficulty]
	_check(game.is_seconds_mode == is_seconds and game.is_lives_mode != is_seconds,
		title + " selects only the requested mode")
	_check(game.round_active and game.timer_running and not game.finishing,
		title + " starts playable")
	_check(game.HAND_RAISE_RELOAD_MS == 1500 and game.HAND_RAISE_LOWER_CONFIRM_MS == 180,
		title + " preserves real 1.5s reload and lower debounce")
	_check(game.score == 0 and game._correct_award() == 100, title + " starts at 0 and awards +100")
	_check(is_equal_approx(game.balloon_float_speed, base_speed)
		and is_equal_approx(game.balloon_base_float_speed, base_speed)
		and is_equal_approx(game.balloon_speed_multiplier, 1.0),
		title + " starts with tier baseline and no boost")
	_check(game.time_remaining == (60.0 if is_seconds else 0.0),
		title + " overrides bogus 900-second incoming context")
	_check(game.hearts == (0 if is_seconds else 3),
		title + " disables hearts in Seconds or begins with exactly 3 Lives")
	_assert_mode_hud(game, is_seconds, title + " initial")

	var time_before: float = game.time_remaining
	game._process(0.5)
	game.set_process(false)
	_check(is_equal_approx(game.time_remaining, time_before - 0.5) if is_seconds
		else is_zero_approx(game.time_remaining),
		title + " counts actual seconds only in Seconds mode")

	# Incorrect balloon: loses only a Lives heart, no points/speed.
	var wrong_lane := _find_wrong_lane(game)
	_check(wrong_lane >= 0, title + " has a real wrong balloon")
	if wrong_lane >= 0:
		var balloon: Area2D = game.balloons[wrong_lane]
		balloon.position.y = game.UPPER_LINE_Y + 50.0
		game._handle_balloon_hit(wrong_lane, balloon.position)
		_check(game.attempts == 1 and game.score == 0 and game.correct_count == 0,
			title + " wrong hit never scores")
		_check(game.hearts == (0 if is_seconds else 2),
			title + " wrong hit deducts one only in Lives")
		_check(is_equal_approx(game.balloon_speed_multiplier, 1.0),
			title + " wrong hit cannot grant or remove speed")

	# Genuine gesture-created projectile misses: Lives loses another heart,
	# Seconds cannot lose any. The gesture path has a true 1500ms cooldown.
	_check(not game.set_hand_raise_state(false, true, 0), title + " initial hand low")
	_check(not game.set_hand_raise_state(false, true, 200), title + " down confirmed")
	_check(not game.set_hand_raise_state(true, true, 450), title + " up debounce")
	_check(game.set_hand_raise_state(true, true, 530), title + " valid raise fires a stone")
	_check(game.projectiles.size() == 1 and game.hand_raise_last_shot_ms == 530,
		title + " stone is real and shot timestamp retained")
	if not game.projectiles.is_empty():
		game._on_projectile_missed(game.projectiles[0])
	_check(game.attempts == 2 and game.score == 0 and game.correct_count == 0,
		title + " missed projectile counts one attempt and no score")
	_check(game.hearts == (0 if is_seconds else 1),
		title + " missed projectile deducts one only in Lives")
	_check(is_equal_approx(game.balloon_speed_multiplier, 1.0),
		title + " missed projectile leaves speed unchanged")
	game.set_hand_raise_state(false, true, 600)
	game.set_hand_raise_state(false, true, 800)
	_check(not game.set_hand_raise_state(true, true, 1949), title + " early rise starts")
	_check(not game.set_hand_raise_state(true, true, 2029),
		title + " 1499ms from previous shot cannot fire")
	_check(not game.set_hand_raise_state(true, true, 2050),
		title + " holding high after deadline cannot fire")
	game.set_hand_raise_state(false, true, 2100)
	game.set_hand_raise_state(false, true, 2280)
	_check(not game.set_hand_raise_state(true, true, 2350), title + " fresh rise waits")
	_check(game.set_hand_raise_state(true, true, 2430),
		title + " confirmed fresh rise after 1500ms can shoot")
	game._clear_projectiles()

	# Start additional questions without popping: changing round_index alone
	# must never confer a boost.
	game._start_new_round()
	game.set_process(false)
	game.set_physics_process(false)
	_check(is_equal_approx(game.balloon_speed_multiplier, 1.0),
		title + " round progression alone never increases ascent")

	# Eighteen actual valid pops demonstrate cumulative diminishing gains,
	# including multiple valid answers per Hard negative-prompt question.
	for pop_index in range(18):
		if not game.round_active or game.pending_valid_lanes.is_empty():
			game._start_new_round()
			game.set_process(false)
			game.set_physics_process(false)
		_check(game.round_active and not game.pending_valid_lanes.is_empty(),
			title + " still has a correct answer on pop %d" % (pop_index + 1))
		if not game.round_active or game.pending_valid_lanes.is_empty():
			break
		var lane: int = game.pending_valid_lanes[0]
		var valid_balloon: Area2D = game.balloons[lane]
		valid_balloon.position.y = game.UPPER_LINE_Y + 50.0
		var hit_position := valid_balloon.position
		var previous_multiplier: float = game.balloon_speed_multiplier
		var before_score: int = game.score
		game._handle_balloon_hit(lane, hit_position)
		var expected_multiplier := ceiling - (ceiling - 1.0) * pow(0.8, pop_index + 1)
		_check(game.score == before_score + 100 and game.correct_count == pop_index + 1,
			title + " valid pop %d adds exactly 100" % (pop_index + 1))
		_check(game.balloon_speed_multiplier > previous_multiplier
			and is_equal_approx(game.balloon_speed_multiplier, expected_multiplier)
			and game.balloon_speed_multiplier < ceiling + 0.00001,
			title + " boost %d diminishes towards bounded ceiling" % (pop_index + 1))
		_check(is_equal_approx(game.balloon_float_speed, base_speed * expected_multiplier),
			title + " ascent speed follows multiplier after pop %d" % (pop_index + 1))
		_check(game.score_bottom_number.text == str(game.score)
			and game.get_context().get("score") == game.score,
			title + " integer HUD/result score after pop %d" % (pop_index + 1))
		game._handle_balloon_hit(lane, hit_position)
		_check(game.score == before_score + 100
			and is_equal_approx(game.balloon_speed_multiplier, expected_multiplier),
			title + " duplicate pop %d never double-awards speed or points" % (pop_index + 1))

	_check(game.correct_count == 18 and game.score == 1800,
		title + " complete 18 correct actions pay 1800 points")
	_check(game.balloon_speed_multiplier > ceiling - 0.01,
		title + " long streak approaches the intended difficulty cap")

	# Verify actual motion in _process uses boosted speed, while launcher,
	# projectile and reveal baselines retain their independent tier settings.
	game._start_new_round()
	game.set_process(false)
	game.set_physics_process(false)
	if is_instance_valid(game.balloon_motion_tween):
		game.balloon_motion_tween.kill()
	game.balloon_floating = true
	var visible_balloon: Area2D = game.balloons[0]
	visible_balloon.position.y = 320.0
	var y_before: float = visible_balloon.position.y
	var speed_before: float = game.balloon_float_speed
	game._process(0.25)
	game.set_process(false)
	_check(is_equal_approx(y_before - visible_balloon.position.y, speed_before * 0.25),
		title + " real balloon ascends at boosted velocity")
	_check(game.projectile_speed == _projectile_speed(difficulty)
		and game.launcher_max_speed == _launcher_speed(difficulty),
		title + " shot and launcher speeds never receive the boost")

	# Pause/resume keeps the boost, score and mode boundary intact.
	var speed_on_pause: float = game.balloon_float_speed
	var score_on_pause: int = game.score
	var time_on_pause: float = game.time_remaining
	game._pause()
	game._process(4.0)
	_check(not game.timer_running and game.score == score_on_pause
		and game.time_remaining == time_on_pause and game.balloon_float_speed == speed_on_pause,
		title + " pause freezes time and retains permanent speed")
	game._resume()
	_check(game.timer_running and game.balloon_float_speed == speed_on_pause
		and game.score == score_on_pause and game.hearts == (0 if is_seconds else 1),
		title + " resume preserves speed, score and mode hearts")
	_assert_mode_hud(game, is_seconds, title + " resumed")

	# Terminal condition is exclusively the selected mode; score is preserved.
	if is_seconds:
		game.time_remaining = 0.1
		game._process(0.2)
		_check(game.finishing and not game.timer_running and game.time_remaining == 0.0
			and game.hearts == 0 and game.get_context().get("score") == 1800,
			title + " global 60s expiry finishes at zero with full score")
	else:
		# A fresh correct-position gesture can still shoot after prior cooldown;
		# missing it consumes the third heart, without altering earned speed.
		game.set_hand_raise_state(false, true, 3000)
		game.set_hand_raise_state(false, true, 3180)
		game.set_hand_raise_state(true, true, 4100)
		_check(game.set_hand_raise_state(true, true, 4180),
			title + " final legitimate hand-raise fires")
		if not game.projectiles.is_empty():
			game._on_projectile_missed(game.projectiles[0])
		_check(game.finishing and not game.timer_running and game.hearts == 0
			and game.get_context().get("lives") == 0 and game.get_context().get("score") == 1800,
			title + " third lost heart ends Lives with score intact")
	_check(is_equal_approx(game.balloon_float_speed, speed_on_pause),
		title + " finishing never erases earned boost")
	_assert_mode_hud(game, is_seconds, title + " finished")

	# A new Play/Tutorial session on the same screen must reset the boost,
	# lives and timer even after a previous result was already final.
	game.set_context({"game_mode": mode, "difficulty": difficulty, "score": 0,
		"correct": 0, "attempts": 0, "balloon_round": 0,
		"lives": 8, "hearts": 8, "time_remaining": 120.0})
	game.set_process(false)
	game.set_physics_process(false)
	_check(game.round_active and not game.finishing and game.score == 0
		and game.correct_count == 0 and game.attempts == 0,
		title + " fresh run fully restores playable scoring state")
	_check(is_equal_approx(game.balloon_speed_multiplier, 1.0)
		and is_equal_approx(game.balloon_float_speed, base_speed),
		title + " fresh run resets cumulative boost to baseline")
	_check(game.hearts == (0 if is_seconds else 3)
		and game.time_remaining == (60.0 if is_seconds else 0.0),
		title + " fresh run enforces exact mode limits")
	_assert_mode_hud(game, is_seconds, title + " restarted")
	game.queue_free()
	await process_frame


func _exercise_post_gain_wrong_and_timeout(mode: String, difficulty: String) -> void:
	var title := "%s/%s post-gain" % [mode, difficulty]
	var seconds := mode == "Seconds"
	var game := BALLOON.instantiate() as Control
	root.add_child(game)
	await process_frame
	game.set_context({"topic": "Noun", "difficulty": difficulty,
		"game_mode": mode, "score": 0, "correct": 0, "attempts": 0,
		"time_remaining": 60.0})
	game.set_process(false)
	game.set_physics_process(false)
	var valid_lane: int = game.pending_valid_lanes[0]
	var correct_target: Area2D = game.balloons[valid_lane]
	correct_target.position.y = game.UPPER_LINE_Y + 55.0
	game._handle_balloon_hit(valid_lane, correct_target.position)
	var boosted: float = game.balloon_float_speed
	_check(game.score == 100 and boosted > BASE_SPEEDS[difficulty],
		title + " awards a real correct hit and positive speed increase")

	# Lose a balloon after earning boost. Neither the score nor earned speed
	# is ever replaced by a streak-based or round-based calculation.
	game._start_new_round()
	game.set_process(false)
	game.set_physics_process(false)
	var wrong_lane: int = _find_wrong_lane(game)
	_check(wrong_lane >= 0, title + " has a wrong target after gaining speed")
	if wrong_lane >= 0:
		var wrong: Area2D = game.balloons[wrong_lane]
		wrong.position.y = game.UPPER_LINE_Y + 55.0
		game._handle_balloon_hit(wrong_lane, wrong.position)
	_check(game.score == 100 and is_equal_approx(game.balloon_float_speed, boosted)
		and game.hearts == (0 if seconds else 2),
		title + " wrong after correct keeps points and permanent speed")

	# Once the authored question timer reaches zero after balloon reveal,
	# advance to the next question and consume a Life only in Lives mode.
	game._start_new_round()
	game.set_process(false)
	game.set_physics_process(false)
	if is_instance_valid(game.balloon_motion_tween):
		game.balloon_motion_tween.kill()
	game.round_time_remaining = 0.01
	var seconds_before: float = game.time_remaining
	game._process(0.05)
	game.set_process(false)
	_check(game.next_round_pending and not game.round_active,
		title + " real question deadline schedules next round")
	_check(game.hearts == (0 if seconds else 1)
		and is_equal_approx(game.balloon_float_speed, boosted) and game.score == 100,
		title + " question timeout costs only Lives heart, keeps earned speed")
	_check(is_equal_approx(game.time_remaining, seconds_before - 0.05) if seconds
		else is_zero_approx(game.time_remaining),
		title + " question timeout does not start a global Lives countdown")
	game._start_new_round()
	game.set_process(false)
	game.set_physics_process(false)
	_check(game.round_active and is_equal_approx(game.balloon_float_speed, boosted),
		title + " next question retains earned speed after timeout")

	if not seconds:
		if is_instance_valid(game.balloon_motion_tween):
			game.balloon_motion_tween.kill()
		game.round_time_remaining = 0.01
		game._process(0.05)
		_check(game.finishing and game.hearts == 0 and game.score == 100
			and is_equal_approx(game.balloon_float_speed, boosted),
			title + " third lost heart through question timeout ends Lives")
	else:
		_check(not game.finishing and game.timer_running,
			title + " unanswered question does not end the 60-second run")
	game.queue_free()
	await process_frame


func _exercise_global_mode_boundary(mode: String, difficulty: String) -> void:
	var title := "%s/%s global deadline" % [mode, difficulty]
	var seconds := mode == "Seconds"
	var game := BALLOON.instantiate() as Control
	root.add_child(game)
	await process_frame
	game.set_context({"topic": "Noun", "difficulty": difficulty, "game_mode": mode,
		"time_remaining": 37.0, "lives": 10, "score": 0, "correct": 0})
	game.set_process(false)
	game.set_physics_process(false)
	_check(game.time_remaining == (60.0 if seconds else 0.0),
		title + " ignores stale/injected time values")
	if seconds:
		# The game clock is independent of balloon reveal, question timers,
		# individual misses and all three possible lives.
		game._process(59.999)
		game.set_process(false)
		_check(not game.finishing and game.time_remaining > 0.0
			and game.time_remaining < 0.002,
			title + " still runs immediately before 60 seconds")
		game._process(0.0011)
		_check(game.finishing and game.round_completed and game.time_remaining == 0.0
			and not game.timer_running and game.get_context().get("lives") == 0,
			title + " reaches Results on exactly the 60s boundary")
	else:
		# A long frame never creates a 60-second loss condition in Lives.
		game._process(60.001)
		game.set_process(false)
		_check(not game.finishing and game.hearts >= 2 and game.time_remaining == 0.0,
			title + " elapsed 60s cannot finish Lives")
		_check(not game.shared_timer_plaque.visible and not game.time_label.visible,
			title + " hidden timer stays hidden after real time progression")
	game.queue_free()
	await process_frame


func _assert_mode_hud(game: Control, seconds: bool, context_label: String) -> void:
	_check(game.shared_timer_plaque.visible == seconds
		and game.shared_lives_plaque.visible == (not seconds and game.hearts > 0)
		and game.time_label.visible == seconds,
		context_label + " HUD shows only mode-specific timer or hearts")
	_check(not game.hearts_box.visible and not game.hearts_label.visible,
		context_label + " legacy hearts UI always hidden")
	if seconds:
		_check(game.time_label.text.ends_with("s"), context_label + " timer has numeric seconds")
	else:
		_check(not game.time_label.visible and not game.shared_timer_plaque.visible,
			context_label + " Lives never displays 60s timer")


func _find_wrong_lane(game: Control) -> int:
	for lane in range(game.balloons.size()):
		if not game.pending_valid_lanes.has(lane) and is_instance_valid(game.balloons[lane]):
			return lane
	return -1


func _projectile_speed(difficulty: String) -> float:
	match difficulty:
		"Easy": return 950.0
		"Hard": return 1490.0
		_: return 1250.0


func _launcher_speed(difficulty: String) -> float:
	match difficulty:
		"Easy": return 540.0
		"Hard": return 920.0
		_: return 750.0


func _check(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures.append(detail)
