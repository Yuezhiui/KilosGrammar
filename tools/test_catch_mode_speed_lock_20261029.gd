extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_catch_mode_speed_lock_20261029.gd
# Real Catch scene, spawned falling tiles, and collision resolution are used.
# The correct/correct/correct/wrong/correct sequence is exercised separately
# for five grammar topics, three difficulties, and both end-of-round modes.
const SCENE := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]
const BASE_SPEED := {"Easy": 105.0, "Normal": 185.0, "Hard": 245.0}
const FIRST_GAIN := {"Easy": 0.05, "Normal": 0.07, "Hard": 0.09}
const CAPS := {"Easy": 1.25, "Normal": 1.35, "Hard": 1.45}
const EPS := 0.025

var failures: Array[String] = []
var assertions := 0
var scenarios := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for topic in TOPICS:
		for difficulty in DIFFICULTIES:
			for mode in MODES:
				await _scenario(topic, difficulty, mode)
	for issue in failures.slice(0, 35):
		push_error("CATCH MODE/SPEED: " + issue)
	if failures.size() > 35:
		print("... ", failures.size() - 35, " additional failures")
	print("CATCH MODE SPEED LOCK 20261029: ", "PASS" if failures.is_empty() else "FAIL",
		" (", assertions, " assertions, ", scenarios, " topic/difficulty/mode scenarios, ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)


func _scenario(topic: String, difficulty: String, mode: String) -> void:
	var tag := "%s/%s/%s" % [topic, difficulty, mode]
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var game := SCENE.instantiate() as Control
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	game.set_process(false)
	# Deliberately pass stale results without a snapshot marker. Fresh means
	# reset, including speed and hearts, regardless of previous mode's totals.
	var fresh := {"topic": topic, "difficulty": difficulty, "game_mode": mode,
		"catch_character": "Bear", "catch_map": "City", "score": 4700,
		"correct": 47, "lives": 1, "time_remaining": 19.0,
		"catch_wave_index": 44}
	game.set_context(fresh)
	game.set_process(false)
	scenarios += 1
	_check(game.score == 0 and game.correct_count == 0 and game.attempts == 0,
		tag + ": fresh round incorrectly inherited scores or speed progress")
	_check(game.lives == 3, tag + ": fresh round starts with exactly three hearts")
	_check(game.wave_index == 1, tag + ": fresh round restarts wave sequence")
	_check(not game.round_finished and game.falling_tiles.size() == 3,
		tag + ": first complete wave immediately spawns")
	_check(_speed_is(game, float(BASE_SPEED[difficulty])), tag + ": initial apples use difficulty base speed")
	_check(game.is_seconds_mode == (mode == "Seconds") and game.is_lives_mode == (mode == "Lives"),
		tag + ": mode flag mismatch")
	_check(game.timer_plaque.visible == (mode == "Seconds") and game.time_label.visible == (mode == "Seconds"),
		tag + ": timer display does not match mode")
	_check(game.lives_plaque.visible == (mode == "Lives"), tag + ": hearts display does not match mode")
	_check(is_equal_approx(game.time_remaining, 60.0 if mode == "Seconds" else 0.0),
		tag + ": fresh mode clock is not 60s or disabled")
	if mode == "Lives":
		game._update_timer(1000.0)
		_check(not game.round_finished and game.time_remaining == 0.0,
			tag + ": Lives must not run a hidden timer")
	else:
		game._update_timer(0.5)
		_check(is_equal_approx(game.time_remaining, 59.5), tag + ": Seconds clock must count down")
	var previous_speed := float(BASE_SPEED[difficulty])
	for answer_index in range(3):
		_check(_hit_spawned_tile(game, true), tag + ": correct %d should collide with spawned apple" % (answer_index + 1))
		_check(game.score == (answer_index + 1) * 100 and game.correct_count == answer_index + 1,
			tag + ": each correct grants exactly 100 points")
		_check(game.lives == 3, tag + ": correct answer must not cost a heart")
		_check(game.wave_phase == "clearing", tag + ": correct catch resolves current wave")
		_check(_next_wave(game), tag + ": next wave spawns after correct answer")
		var next_speed: float = game.wave_speed
		_check(_speed_is(game, next_speed), tag + ": three next-wave apples use new speed")
		_check(next_speed > previous_speed, tag + ": correct answer must permanently increase speed")
		_check(next_speed < float(BASE_SPEED[difficulty]) * float(CAPS[difficulty]) + EPS,
			tag + ": correct answer exceeded difficulty speed cap")
		if answer_index == 0:
			_check(absf(next_speed / float(BASE_SPEED[difficulty]) - (1.0 + float(FIRST_GAIN[difficulty]))) < 0.0001,
				tag + ": first correct boost must be 5/7/9 percent")
		previous_speed = next_speed
	# Pause is the actual saved-game path. Its snapshot must preserve score,
	# correct count, mode clock/hearts and the accumulated speed progression.
	game._pause()
	var saved: Dictionary = game.get_context()
	_check(not game.round_running and saved["correct"] == 3 and saved["score"] == 300,
		tag + ": pause snapshot includes the three real catches")
	_check(saved.has("catch_collected_words") and saved["catch_collected_words"].size() == 3,
		tag + ": pause snapshot contains its collected words")
	# Many elapsed/missed waves must not affect acceleration on restore.
	saved["catch_wave_index"] = 50
	game.set_context(saved)
	game.set_process(false)
	_check(game.correct_count == 3 and game.score == 300 and game.lives == 3,
		tag + ": resume retains three corrects and starting lives")
	_check(game.wave_index == 51, tag + ": resume retained wave history")
	_check(absf(game.wave_speed - previous_speed) < EPS and _speed_is(game, previous_speed),
		tag + ": resume keeps correct-derived speed even with high wave index")
	_check(is_equal_approx(game.time_remaining, 0.0) if mode == "Lives" else game.time_remaining > 0.0 and game.time_remaining < 60.0,
		tag + ": resume respects its mode clock")
	# A wrong answer breaks streak but does not decrease speed; only Lives loses
	# one heart. Use a real wrong falling tile placed into the real hitbox.
	_check(_hit_spawned_tile(game, false), tag + ": wrong answer should collide with spawned apple")
	_check(game.score == 300 and game.correct_count == 3 and game.streak == 0,
		tag + ": wrong answer must award zero points and reset streak")
	_check(game.lives == (2 if mode == "Lives" else 3),
		tag + ": wrong answer changes hearts only in Lives")
	_check(_next_wave(game), tag + ": next wave spawns after wrong answer")
	_check(absf(game.wave_speed - previous_speed) < EPS and _speed_is(game, previous_speed),
		tag + ": wrong answer must neither boost nor reset speed")
	# Fourth correct after the wrong proves boost is permanent and independent
	# of streak. Exactly 400 points and a strictly higher next wave speed.
	_check(_hit_spawned_tile(game, true), tag + ": fourth correct should collide")
	_check(game.score == 400 and game.correct_count == 4 and game.streak == 1,
		tag + ": fourth correct is +100 even after broken streak")
	_check(_next_wave(game), tag + ": next wave spawns after fourth correct")
	_check(game.wave_speed > previous_speed and _speed_is(game, game.wave_speed),
		tag + ": correct after wrong keeps growing the permanent speed boost")
	var fourth_speed: float = game.wave_speed
	# A missed correct target also must not change the speed counter.
	game._resolve_wave(false)
	_check(game.score == 400 and game.correct_count == 4, tag + ": missed correct cannot change score")
	_check(game.lives == (1 if mode == "Lives" else 3), tag + ": missed wave heart contract")
	_check(_next_wave(game), tag + ": next wave spawns after missed correct")
	_check(absf(game.wave_speed - fourth_speed) < EPS and _speed_is(game, fourth_speed),
		tag + ": missed correct must keep permanent speed unchanged")
	if mode == "Lives":
		_check(_hit_spawned_tile(game, false), tag + ": third mistake should collide")
		_check(game.round_finished and game.finish_reason == "lives_empty" and game.lives == 0,
			tag + ": third lost heart must end Lives immediately")
		_check(game.score == 400 and game.time_remaining == 0.0,
			tag + ": Lives final score survives without any timer")
	else:
		_check(_hit_spawned_tile(game, false), tag + ": later Seconds wrong should collide")
		_check(game.lives == 3 and not game.round_finished,
			tag + ": Seconds mistakes must not end round or decrement hearts")
		game._update_timer(61.0)
		_check(game.round_finished and game.finish_reason == "time_up" and game.time_remaining == 0.0,
			tag + ": Seconds must finish when 60-second countdown reaches zero")
		_check(game.score == 400, tag + ": Seconds final score survives time-up")
	var result: Dictionary = game.get_context()
	_check(result["correct"] == 4 and result["score"] == 400 and result["completion_reason"] == ("time_up" if mode == "Seconds" else "lives_empty"),
		tag + ": final results payload records score and proper end reason")
	# Restart from the finished round, with the saved payload's high totals but
	# without a resume marker. Only the current context's chosen mode remains.
	game.set_context({"topic": topic, "difficulty": difficulty, "game_mode": mode,
		"catch_character": "Bear", "score": 400, "correct": 4,
		"catch_wave_index": 99, "lives": 0, "time_remaining": 0.0})
	game.set_process(false)
	_check(not game.round_finished and game.score == 0 and game.correct_count == 0
		and game.lives == 3 and game.wave_index == 1,
		tag + ": restarting clears score, speed progress and restores three hearts")
	_check(_speed_is(game, float(BASE_SPEED[difficulty])) and absf(game.wave_speed - float(BASE_SPEED[difficulty])) < EPS,
		tag + ": restarting resets wave speed to difficulty base")
	_check(game.time_remaining == (60.0 if mode == "Seconds" else 0.0),
		tag + ": restarting resets the applicable mode clock")
	# Artificial 100-correct stress bound (NOT a claim of 100 physical catches).
	game.correct_count = 100
	var expected_limit: float = float(BASE_SPEED[difficulty]) * float(CAPS[difficulty])
	var bounded: float = game._correct_answer_wave_speed()
	_check(bounded <= expected_limit + EPS and bounded >= expected_limit - EPS,
		tag + ": 100-correct calculation smoothly approaches bounded difficulty limit")
	host.queue_free()
	await process_frame


func _hit_spawned_tile(game: Control, matching: bool) -> bool:
	if game.round_finished or game.wave_phase != "falling" or game.falling_tiles.size() != 3:
		return false
	for index in range(game.falling_tiles.size()):
		var tile: Dictionary = game.falling_tiles[index]
		if bool(tile["matching"]) == matching:
			var position: Vector2 = game._basket_rect().get_center()
			tile["pos"] = position
			game.falling_tiles[index] = tile
			game._sync_tile_node(tile)
			game._process(0.01)
			game.set_process(false)
			return game.wave_phase == "clearing" or game.round_finished
	return false


func _next_wave(game: Control) -> bool:
	if game.round_finished or game.wave_phase != "clearing":
		return false
	game._update_spawning(game.WAVE_CLEAR_SECONDS + 0.01)
	game.set_process(false)
	return game.wave_phase == "falling" and game.falling_tiles.size() == 3


func _speed_is(game: Control, expected: float) -> bool:
	if game.falling_tiles.size() != 3:
		return false
	for tile in game.falling_tiles:
		if absf(float(tile["speed"]) - expected) > EPS:
			return false
	return true


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
