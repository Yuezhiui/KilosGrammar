extends SceneTree

# Regression coverage for gameplay input freezes and late collision callbacks.
# Run: Godot --headless --path . --script res://tools/test_gameplay_edge_cases.gd

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _balloon_pause_guard()
	await _balloon_end_of_question_guard()
	await _balloon_swept_low_fps_hit()
	await _balloon_delayed_question_survives_pause()
	await _plane_hitbox_alignment()
	await _plane_answer_gate_selection()
	await _catch_spawn_spacing_guard()
	await _catch_last_life_guard()
	await _balloon_negative_topics()
	if failures.is_empty():
		print("PASS gameplay edge cases: pause freeze, late collisions, swept low-FPS shots, delayed questions, airplane hitbox, three-apple waves, final life")
		quit(0)
	else:
		for failure in failures:
			push_error("GAMEPLAY EDGE CASE: " + failure)
		quit(1)


func _new_balloon() -> Control:
	var packed := load("res://ui/minigames/balloon_popping.tscn") as PackedScene
	var game := packed.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {"activity": "Balloon Popping", "game_style": "Noun", "topic": "Noun", "difficulty": "Easy"})
	return game


func _balloon_pause_guard() -> void:
	var game := _new_balloon()
	await process_frame
	game.call("_launch_projectile")
	var projectiles: Array = game.get("projectiles")
	if projectiles.is_empty():
		failures.append("Could not launch physics projectile before pause")
		await _dispose(game)
		return
	var projectile: Area2D = projectiles[0]
	game.call("_pause")
	var position_before: Vector2 = projectile.position
	var lives_before: int = int(game.get("hearts"))
	game.call("_physics_process", 0.15)
	if not projectile.position.is_equal_approx(position_before):
		failures.append("Balloon projectile moved after Pause")
	var balloons: Array = game.get("balloons")
	var valid: Array = game.get("valid_lanes")
	var wrong_lane := -1
	for i in range(balloons.size()):
		if not valid.has(i):
			wrong_lane = i
			break
	if wrong_lane >= 0:
		game.call("_on_projectile_area_entered", balloons[wrong_lane], projectile)
		if int(game.get("hearts")) != lives_before:
			failures.append("Paused balloon accepted a late collision and removed a heart")
	await _dispose(game)


func _balloon_end_of_question_guard() -> void:
	var game := _new_balloon()
	await process_frame
	var valid: Array = game.get("valid_lanes")
	for i in valid:
		game.call("_pop_balloon", int(i))
	var score_before: int = int(game.get("score"))
	var lives_before: int = int(game.get("hearts"))
	var remaining: Array = game.get("balloons")
	for lane in range(remaining.size()):
		if remaining[lane] != null and is_instance_valid(remaining[lane]):
			game.call("_pop_balloon", lane)
			break
	if int(game.get("score")) != score_before or int(game.get("hearts")) != lives_before:
		failures.append("Balloon counted extra answer after question already resolved")
	await _dispose(game)


func _balloon_swept_low_fps_hit() -> void:
	var game := _new_balloon()
	await process_frame
	# The user-approved 1.15s SINE reveal keeps all balloon collision disabled
	# until the full rise finishes. This is a test of *exposed* swept hits:
	# launching after only one frame now intentionally shoots at hidden art.
	var reveal_tween := game.get("balloon_motion_tween") as Tween
	var reveal_deadline := Time.get_ticks_msec() + 2400
	while is_instance_valid(reveal_tween) and reveal_tween.is_running() and Time.get_ticks_msec() < reveal_deadline:
		await process_frame
	if not is_instance_valid(reveal_tween) or reveal_tween.is_running():
		failures.append("Low-FPS balloon collision setup never completed its 1.15s entrance")
		await _dispose(game)
		return
	var valid: Array = game.get("valid_lanes")
	var balloons: Array = game.get("balloons")
	if valid.is_empty() or balloons.is_empty():
		failures.append("Low-FPS balloon collision setup has no valid target")
		await _dispose(game)
		return
	var target: Area2D = balloons[int(valid[0])]
	if not target.monitoring or not target.monitorable:
		failures.append("Low-FPS balloon collision setup never enabled exposed target collision")
		await _dispose(game)
		return
	game.set("launcher_x", target.position.x)
	game.call("_launch_projectile")
	if int(game.get("score")) != 0 or int(game.get("attempts")) != 0:
		failures.append("Balloon registered a hit at projectile launch instead of impact")
	# At 5 physics FPS the projectile can traverse the entire target between
	# samples; this single large step previously bypassed Area2D completely.
	game.call("_update_projectiles", 0.55)
	if int(game.get("correct_count")) != 1 or int(game.get("score")) <= 0 or int(game.get("attempts")) != 1:
		failures.append("Swept collision missed a valid balloon crossed at low FPS")
	var score_after: int = int(game.get("score"))
	game.call("_update_projectiles", 0.55)
	if int(game.get("score")) != score_after or int(game.get("attempts")) != 1:
		failures.append("Swept balloon collision registered the same projectile twice")
	await _dispose(game)


func _balloon_delayed_question_survives_pause() -> void:
	var game := _new_balloon()
	await process_frame
	var valid: Array = (game.get("valid_lanes") as Array).duplicate()
	for lane in valid:
		game.call("_pop_balloon", int(lane))
	var original_round: int = int(game.get("round_index"))
	if not bool(game.get("next_round_pending")):
		failures.append("Balloon failed to schedule next question before pause")
		await _dispose(game)
		return
	game.call("_pause")
	await create_timer(0.75).timeout
	if int(game.get("round_index")) != original_round:
		failures.append("Paused balloon unexpectedly started the next question")
	game.call("_resume")
	await process_frame
	if int(game.get("round_index")) != original_round + 1:
		failures.append("Balloon lost a pending next-question transition during pause")
	await create_timer(0.09).timeout
	if int(game.get("round_index")) != original_round + 1:
		failures.append("Balloon resumed the same delayed question transition twice")
	await _dispose(game)


func _dispose(game: Node) -> void:
	game.queue_free()
	await process_frame
	await process_frame


func _plane_hitbox_alignment() -> void:
	var packed := load("res://ui/minigames/human_plane.tscn") as PackedScene
	var game := packed.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {"activity": "Human Plane", "topic": "Noun", "difficulty": "Normal"})
	await process_frame
	await process_frame
	# The selectable gate must reach the actual airplane hitbox vertically,
	# not score at a separate floating line before touching the airplane.
	var line_y: float = game.call("_answer_line_y")
	var plane_y: float = game.call("_plane_y")
	var half_hitbox := 10.0 * game.size.y / 720.0
	if absf(line_y - plane_y) > half_hitbox + 1.0:
		failures.append("Plane gate answer line is %.1f px from the airplane hitbox" % absf(line_y - plane_y))
	await _dispose(game)


func _plane_answer_gate_selection() -> void:
	var packed := load("res://ui/minigames/human_plane.tscn") as PackedScene
	var game := packed.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {"activity": "Human Plane", "topic": "Noun", "difficulty": "Hard"})
	await process_frame
	await process_frame
	var data: Dictionary = game.get("round_data")
	var valid: Array = data.get("valid_indices", [])
	if valid.is_empty() or valid.size() > 2:
		failures.append("Human Plane did not offer 1ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ2 correct answers")
		await _dispose(game)
		return
	var chosen := int(valid[0])
	var progress: float = game.call("_progress_for_answer_line")
	var gate: Rect2 = game.call("_gate_rect", chosen, progress)
	game.set("plane_x_norm", gate.get_center().x / game.size.x)
	var selected: int = game.call("_lane_hit_at_answer_line")
	if selected != chosen:
		failures.append("Human Plane hitbox missed its centered correct answer gate")
	var original_score: int = int(game.get("score"))
	game.call("_resolve_at_answer_line")
	if int(game.get("correct_count")) != 1 or int(game.get("score")) <= original_score:
		failures.append("Human Plane failed to score the actual correct gate crossing")
	var scored_once: int = int(game.get("score"))
	game.call("_resolve_at_answer_line")
	if int(game.get("score")) != scored_once:
		failures.append("Human Plane awarded the same gate collision twice")
	await _dispose(game)


func _catch_last_life_guard() -> void:
	var packed := load("res://ui/minigames/catch_word.tscn") as PackedScene
	var game := packed.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {"activity": "Catch the Word", "topic": "Noun", "game_mode": "Lives", "difficulty": "Easy"})
	game.set_process(false)
	await process_frame
	var basket: Rect2 = game.call("_basket_rect")
	game.set("lives", 1)
	game.set("score", 0)
	game.set("correct_count", 0)
	# Resolve one real three-lane wave by choosing a wrong apple on the last
	# life; its correct sibling must never be processed after game-over.
	var tiles: Array = game.get("falling_tiles")
	if tiles.size() != 3 or String(game.get("wave_phase")) != "falling":
		failures.append("Catch final-life test did not start with a real immediately falling three-apple wave")
	else:
		var wrong_index := -1
		for index in range(tiles.size()):
			if not bool(tiles[index]["matching"]):
				wrong_index = index
				break
		if wrong_index < 0:
			failures.append("Catch final-life wave has no wrong apple")
		else:
			if (tiles[0]["pos"] as Vector2).y >= -53.0:
				failures.append("Catch final-life wave did not originate above the viewport")
			game.call("_update_tiles", 0.05)
			if String(game.get("wave_phase")) != "falling":
				failures.append("Catch final-life wave was not immediately falling")
			var wrong: Dictionary = tiles[wrong_index]
			wrong["pos"] = basket.get_center()
			tiles[wrong_index] = wrong
			game.call("_update_tiles", 0.0)
			if int(game.get("attempts")) != 1 or int(game.get("lives")) != 0 or not bool(game.get("round_finished")):
				failures.append("Catch final life did not end after exactly one wrong answer")
			if int(game.get("correct_count")) != 0 or int(game.get("score")) != 0:
				failures.append("Catch awarded points after the final life was already lost")
			game.call("_update_tiles", 0.0)
			game.call("_update_spawning", 2.0)
			if int(game.get("attempts")) != 1 or int(game.get("score")) != 0 \
					or not (game.get("falling_tiles") as Array).is_empty():
				failures.append("Catch final-life collision processed an orphaned tile after game-over")
	await _dispose(game)


func _catch_spawn_spacing_guard() -> void:
	var scene := load("res://ui/minigames/catch_word.tscn") as PackedScene
	for mode in ["Seconds", "Lives"]:
		for difficulty in ["Easy", "Normal", "Hard"]:
			for topic in ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]:
				var game := scene.instantiate() as Control
				root.add_child(game)
				game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				game.call("set_context", {
				"activity": "Catch the Word",
				"topic": topic,
				"game_mode": mode,
					"difficulty": difficulty
				})
				game.set_process(false)
				await process_frame
				(game.get("rng") as RandomNumberGenerator).seed = 260926
				var tag := "%s/%s/%s" % [topic, mode, difficulty]
				var previous_speed := 0.0
				var valid_waves := 0
				for step in range(12):
					var tiles: Array = game.get("falling_tiles")
					if tiles.size() != 3 or String(game.get("wave_phase")) != "falling":
						failures.append("Catch %s wave %d did not spawn exactly 3 immediately falling apples" % [tag, step])
						break
					var lane_ids := {}
					var words := {}
					var correct := 0
					var wrong := 0
					var same_y := true
					var same_speed := true
					var safe_lanes := true
					var initial_y: float = (tiles[0]["pos"] as Vector2).y
					if initial_y >= -53.0 or not is_zero_approx(float(game.get("spawn_interval"))):
						failures.append("Catch %s wave %d did not start above the screen without a reading pause" % [tag, step])
						break
					var speed := float(tiles[0]["speed"])
					var basket_rect: Rect2 = game.call("_basket_rect")
					var min_lane_distance := 106.0 + basket_rect.size.x + 12.0
					var chosen := -1
					for index in range(3):
						var tile: Dictionary = tiles[index]
						lane_ids[int(tile["lane"])] = true
						words[String(tile["word"]).to_lower()] = true
						if bool(tile["matching"]):
							correct += 1
							if step % 3 == 0:
								chosen = index
						else:
							wrong += 1
							if step % 3 == 1:
								chosen = index
						same_y = same_y and is_equal_approx((tile["pos"] as Vector2).y, initial_y)
						same_speed = same_speed and is_equal_approx(float(tile["speed"]), speed)
						for other_index in range(index + 1, 3):
							var other: Vector2 = tiles[other_index]["pos"]
							if absf((tile["pos"] as Vector2).x - other.x) < min_lane_distance:
								safe_lanes = false
					if lane_ids.size() != 3 or words.size() != 3 or correct != 1 or wrong != 2 \
							or not same_y or not same_speed or not safe_lanes:
						failures.append("Catch %s wave %d violates 1-correct/2-wrong, uniqueness, equal-speed or lane-spacing invariants" % [tag, step])
						break
					if speed + 0.01 < previous_speed or speed > float(game.get("base_fall_speed")) * 1.55 + 0.01:
						failures.append("Catch %s wave %d has non-progressive or unbounded speed %.1f" % [tag, step, speed])
						break
					previous_speed = speed
					var current_wave := int(game.get("wave_index"))
					game.call("_spawn_wave")
					if (game.get("falling_tiles") as Array).size() != 3 or int(game.get("wave_index")) != current_wave:
						failures.append("Catch %s wave %d accepted overlapping spawn calls" % [tag, step])
						break
					var attempts_before := int(game.get("attempts"))
					var score_before := int(game.get("score"))
					var lives_before := int(game.get("lives"))
					# There is no reading state: one immediate movement tick must
					# advance all 3 apples, without introducing a phantom collision.
					game.call("_update_tiles", 0.05)
					if int(game.get("attempts")) != attempts_before or String(game.get("wave_phase")) != "falling":
						failures.append("Catch %s wave %d resolved before reaching the basket" % [tag, step])
						break
					var moved_synchronously := true
					for tile in tiles:
						var moved_y := (tile["pos"] as Vector2).y
						if moved_y <= initial_y or not is_equal_approx(moved_y, initial_y + speed * 0.05):
							failures.append("Catch %s wave %d did not fall immediately at synchronized speed" % [tag, step])
							moved_synchronously = false
							break
					if not moved_synchronously:
						break
					if step % 3 == 2:
						game.call("_update_tiles", 10.0) # All three pass offscreen, one unanswered wave.
					else:
						var selected: Dictionary = tiles[chosen]
						selected["pos"] = basket_rect.get_center()
						tiles[chosen] = selected
						game.call("_update_tiles", 0.0)
					if int(game.get("attempts")) != attempts_before + 1 or String(game.get("wave_phase")) != "clearing":
						failures.append("Catch %s wave %d did not resolve exactly one answer into clearing" % [tag, step])
						break
					if step % 3 == 0 and int(game.get("score")) <= score_before:
						failures.append("Catch %s wave %d did not score the selected correct apple" % [tag, step])
						break
					if step % 3 != 0 and int(game.get("score")) != score_before:
						failures.append("Catch %s wave %d scored a wrong or skipped answer" % [tag, step])
						break
					if mode == "Lives" and int(game.get("lives")) != lives_before - (0 if step % 3 == 0 else 1):
						failures.append("Catch %s wave %d applied incorrect lives penalty" % [tag, step])
						break
					game.call("_update_tiles", 0.0)
					game.call("_spawn_wave")
					if int(game.get("attempts")) != attempts_before + 1 or int(game.get("wave_index")) != current_wave:
						failures.append("Catch %s wave %d double-resolved or spawned during clearing" % [tag, step])
						break
					# Reset lives as a test fixture: the stress test must span many waves.
					if mode == "Lives":
						game.set("lives", 3)
					game.call("_update_spawning", 0.76)
					if int(game.get("wave_index")) != current_wave + 1 or (game.get("falling_tiles") as Array).size() != 3:
						failures.append("Catch %s wave %d did not clear and advance to next three-apple wave" % [tag, step])
						break
					valid_waves += 1
					if step % 3 == 2:
						await process_frame
				if valid_waves != 12:
					failures.append("Catch %s exercised only %d of 12 complete waves" % [tag, valid_waves])
				await _dispose(game)


func _balloon_negative_topics() -> void:
	var packed := load("res://ui/minigames/balloon_popping.tscn") as PackedScene
	var bank := load("res://ui/minigames/grammar_bank.gd") as Script
	for topic in ["Noun", "Verb", "Adjective", "Adverb", "Pronoun"]:
		var game := packed.instantiate() as Control
		root.add_child(game)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game.call("set_context", {"activity": "Balloon Popping", "topic": topic, "game_style": topic, "difficulty": "Hard"})
		await process_frame
		var prompt: Label = game.get("prompt_label")
		var balloons: Array = game.get("balloons")
		var valid: Array = game.get("valid_lanes")
		if prompt == null or not prompt.text.contains("NOT ") or valid.size() < 1 or valid.size() > 2:
			failures.append("Hard Balloon Popping exclusion prompt missing for " + topic)
		else:
			for lane in range(balloons.size()):
				var balloon: Area2D = balloons[lane]
				var label_text := ""
				for node in balloon.get_children():
					if node is Label:
						label_text = String((node as Label).text)
				if label_text.is_empty() or valid.has(lane) == bool(bank.call("is_matching", label_text, topic)):
					failures.append("Incorrect negative-word classification for " + topic)
					break
		await _dispose(game)
