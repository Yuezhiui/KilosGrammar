extends SceneTree

# Godot --headless --path . --script res://tools/test_balloon_fixed_score_speed.gd
# Exercise the real hit handler in both modes and all difficulty tiers.

const GAME_SCENE: PackedScene = preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var speeds: Dictionary = {}
	for difficulty in DIFFICULTIES:
		for mode in MODES:
			var game := GAME_SCENE.instantiate() as Control
			root.add_child(game)
			await process_frame
			game.set_context({
				"activity": "Balloon Popping", "topic": "Noun",
				"difficulty": difficulty, "game_mode": mode,
				"score": 0, "correct": 0, "attempts": 0,
				"lives": 3, "time_remaining": 60.0
			})
			game.set_process(false)
			game.set_physics_process(false)
			var label := "%s/%s" % [difficulty, mode]
			_check(game.round_active and game.timer_running, label + " starts an active round")
			_check(game._correct_award() == 100, label + " award is always 100")
			if mode == "Seconds":
				speeds[difficulty] = [game.balloon_float_speed, game.projectile_speed,
					game.launcher_max_speed, game._balloon_hidden_y() - game.BALLOON_EXIT_Y,
					game.round_time_limit]
				_check((game._balloon_hidden_y() - game.BALLOON_EXIT_Y) / game.balloon_float_speed < game.round_time_limit,
					label + " entire continuous ascent completes before path-aware question cutoff")

			# A wrong balloon counts as an attempt, preserves score and penalizes
			# only Lives mode. No changes to those existing gameplay rules.
			var wrong_lane := _wrong_lane(game)
			_check(wrong_lane >= 0, label + " contains a wrong target")
			if wrong_lane >= 0:
				var wrong_balloon: Area2D = game.balloons[wrong_lane]
				wrong_balloon.position.y = game.UPPER_LINE_Y + 40.0
				game._handle_balloon_hit(wrong_lane, wrong_balloon.position)
				_check(game.score == 0 and game.correct_count == 0 and game.attempts == 1,
					label + " wrong target does not award points")
				_check(game.hearts == (2 if mode == "Lives" else 0),
					label + " wrong-hit hearts match game mode")

			# Three real correct pops must add exactly 100 apiece even when a
			# question has more than one correct balloon (Hard negative prompts).
			for pop_index in range(3):
				if game.pending_valid_lanes.is_empty():
					game._start_new_round()
					game.set_process(false)
					game.set_physics_process(false)
				_check(game.round_active and not game.pending_valid_lanes.is_empty(),
						label + " has a valid target for pop %d" % (pop_index + 1))
				if not game.round_active or game.pending_valid_lanes.is_empty():
					break
				var lane: int = game.pending_valid_lanes[0]
				var balloon: Area2D = game.balloons[lane]
				_check(is_instance_valid(balloon) and balloon.visible,
					label + " valid target is a visible balloon")
				if not is_instance_valid(balloon):
					break
				balloon.position.y = game.UPPER_LINE_Y + 40.0
				var hit_position := balloon.position
				var before_score: int = game.score
				var before_correct: int = game.correct_count
				var before_attempts: int = game.attempts
				var before_hearts: int = game.hearts
				game._handle_balloon_hit(lane, hit_position)
				_check(game.score == before_score + 100 and game.correct_count == before_correct + 1
					and game.attempts == before_attempts + 1,
					label + " correct pop %d awards exactly 100 and one attempt" % (pop_index + 1))
				_check(game.hearts == before_hearts,
					label + " correct pop does not consume hearts")
				_check(game.feedback_label.text.begins_with("+100"),
					label + " visible feedback shows +100")
				_check(game.score_bottom_number.text == str(game.score),
					label + " HUD displays whole-number score")
				_check(int(game.get_context().get("score", -1)) == game.score,
					label + " exported results match gameplay score")
				# A projectile callback repeated for the same popped balloon cannot
				# grant a second award.
				game._handle_balloon_hit(lane, hit_position)
				_check(game.score == before_score + 100 and game.correct_count == before_correct + 1
					and game.attempts == before_attempts + 1,
					label + " duplicate hit adds no extra score")

			game.queue_free()
			await process_frame

	_check(speeds.size() == DIFFICULTIES.size(), "all difficulty speed profiles collected")
	if speeds.size() == DIFFICULTIES.size():
		for speed_index in [0, 1, 2]:
			_check(speeds["Easy"][speed_index] < speeds["Normal"][speed_index]
				and speeds["Normal"][speed_index] < speeds["Hard"][speed_index],
				"balloon, projectile and launcher speeds increase with difficulty (%d)" % speed_index)
		_check(speeds["Easy"][3] == speeds["Normal"][3] and speeds["Normal"][3] == speeds["Hard"][3],
			"all difficulties ascend the same bottom-to-top route")
		_check(speeds["Easy"][4] > speeds["Normal"][4] and speeds["Normal"][4] > speeds["Hard"][4]
			and speeds["Hard"][4] > 7.0,
			"question timeout follows actual longer whole-path travel for each difficulty")

	# Let outstanding round-transition timers expire after their scenes are
	# freed, so transient callbacks do not remain alive at Godot shutdown.
	await create_timer(0.85).timeout
	for frame in range(3):
		await process_frame
	if failures.is_empty():
		print("PASS Balloon fixed +100 and speed: %d checks across 6 scenarios" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("BALLOON SCORE QA: " + failure)
		print("FAIL Balloon fixed +100 and speed: %d failures / %d checks" %
			[failures.size(), checks])
		quit(1)


func _wrong_lane(game: Control) -> int:
	for lane in range(game.balloons.size()):
		if not game.pending_valid_lanes.has(lane):
			return lane
	return -1


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
