extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_catch_vocab_cycle_20261029.gd
# Scene-level simulated correct catches of REAL spawned apples, never camera.
# Three-wave fairness, tier validity, cycle uniqueness, boundary adjacency,
# no early Results, pause/resume, and strictly mode-controlled endings.
const CATCH := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const BANK := preload("res://ui/minigames/shared/grammar_bank.gd")
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Lives", "Seconds"]

class CompactBank:
	extends RefCounted
	var correct_words: Array[String] = []
	var wrong_words: Array[String] = []

	func pick_word(_topic: String, matching: bool, rng: RandomNumberGenerator,
			_difficulty: String = "Easy", excluded: Dictionary = {}) -> String:
		var available: Array[String] = []
		for candidate in correct_words if matching else wrong_words:
			if not excluded.has(candidate.to_lower()):
				available.append(candidate)
		if available.is_empty():
			return ""
		return available[rng.randi_range(0, available.size() - 1)]

var cases := 0
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	# Every topic/tier/mode sees 5+ complete cycles of a reduced, REAL-word
	# pool. The reduced pool makes cycle boundaries reproducible and frequent.
	for topic in TOPICS:
		for difficulty in DIFFICULTIES:
			for mode in MODES:
				await _scenario(topic, difficulty, mode, true, 22)
	# Real unmodified GrammarBank produces 2+ complete cycles, even for Lives,
	# which formerly finished after exhausting all its available words.
	await _scenario("Pronoun", "Normal", "Lives", false, 145)
	await _scenario("Adverb", "Hard", "Lives", false, 165)
	await _scenario("Noun", "Easy", "Seconds", false, 175)
	for issue in failures.slice(0, 35):
		push_error("CATCH VOCAB CYCLE: " + issue)
	if failures.size() > 35:
		print("... %d more failures" % (failures.size() - 35))
	print("CATCH VOCAB CYCLE 20261029: %s (%d checks, %d scenarios, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, cases, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _scenario(topic: String, difficulty: String, mode: String,
		compact: bool, waves: int) -> void:
	var tag := "%s/%s/%s/%s" % [topic, difficulty, mode, "compact" if compact else "REAL"]
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var game := CATCH.instantiate() as Control
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	game.set_process(false)
	if compact:
		var bank := CompactBank.new()
		bank.correct_words.assign(BANK._available_words(topic, true, difficulty, {}).slice(0, 4))
		bank.wrong_words.assign(BANK._available_words(topic, false, difficulty, {}).slice(0, 8))
		_check(bank.correct_words.size() == 4 and bank.wrong_words.size() == 8,
			tag + ": test fixture contains genuine tier words")
		game.grammar_bank = bank
	game.set_context({"topic": topic, "difficulty": difficulty, "game_mode": mode,
		"catch_character": "Bear", "catch_map": "City"})
	game.set_process(false)
	cases += 1
	var results: Array[Dictionary] = []
	game.requested.connect(func(target: String, payload: Dictionary) -> void:
		if target == "results":
			results.append(payload.duplicate(true))
	)
	var last_cycle: int = int(game.vocabulary_cycle)
	var previous_wave: Dictionary = {}
	var in_cycle: Dictionary = {}
	var boundary_count := 0
	var previous_speed: float = game.wave_speed
	for step in range(waves):
		if game.round_finished or game.falling_tiles.size() != 3:
			_fail(tag + ": gameplay stopped or lost a complete wave at step %d" % step)
			break
		var cycle: int = game.vocabulary_cycle
		if cycle != last_cycle:
			_check(cycle == last_cycle + 1, tag + ": cycle count skipped after exhaustion")
			boundary_count += 1
			last_cycle = cycle
			in_cycle.clear()
			# Pool has 4+ correct and 8+ incorrect words; avoiding the last wave
			# across cycle boundaries is mathematically possible for this fixture.
			if compact:
				for tile in game.falling_tiles:
					_check(not previous_wave.has(_key(tile["word"])),
						tag + ": immediate previous-wave duplicate on cycle boundary")
		var matching_count := 0
		var same_wave: Dictionary = {}
		for tile in game.falling_tiles:
			var word := String(tile["word"])
			var key := _key(word)
			var matching := bool(tile["matching"])
			if matching:
				matching_count += 1
			_check(not key.is_empty() and not same_wave.has(key) and not in_cycle.has(key),
				tag + ": duplicate within active cycle on wave %d" % step)
			_check(BANK.is_matching(word, topic) == matching,
				tag + ": correct/distractor grammar classification on wave %d: %s" % [step, word])
			# WORD_BANK membership is insufficient for tier. Validate eligibility
			# using same _available_words contract as production's bank.
			_check(BANK._available_words(topic, matching, difficulty, {}).has(word),
				tag + ": wrong difficulty tier on wave %d: %s" % [step, word])
			same_wave[key] = true
			in_cycle[key] = true
		_check(matching_count == 1, tag + ": one matching + two distractors")
		previous_wave = same_wave
		_check(_hit_real_correct(game), tag + ": correct apple collision on wave %d" % step)
		_check(not game.round_finished and game.lives == 3 and game.score == (step + 1) * 100
			and game.correct_count == step + 1 and results.is_empty(),
			tag + ": early Results or score/lives corruption at step %d" % step)
		_check(game.wave_speed >= previous_speed - 0.01,
			tag + ": accumulated speed decreased on cycle boundary")
		previous_speed = game.wave_speed
		if game.round_finished:
			break
		_check(_next_wave(game), tag + ": cannot start next wave after correct answer")
		if step == 13:
			var saved: Dictionary = game.get_context()
			_check(saved["catch_vocab_cycle"] == game.vocabulary_cycle
				and saved["catch_last_wave_words"].size() == 3,
				tag + ": cycle boundary saved in context")
			# The snapshot contains the *currently displayed* next wave, not the
			# last scored wave. It is the true predecessor of the resumed question.
			previous_wave.clear()
			for word in saved["catch_last_wave_words"]:
				previous_wave[_key(word)] = true
			# A paused resume is allowed to replace the in-flight question, but
			# the 14 completed catches, speed and cycle progress must persist.
			game.set_context(saved)
			game.set_process(false)
			_check(game.score == (step + 1) * 100 and game.correct_count == step + 1
				and game.vocabulary_cycle >= int(saved["catch_vocab_cycle"])
				and game.vocabulary_cycle <= int(saved["catch_vocab_cycle"]) + 1,
				tag + ": resume keeps earned score and cycle index")
			# Snapshot already included the 3 in-flight apples; record the latest
			# post-resume question as the next entry in the duplicate oracle.
			in_cycle = game.used_session_words.duplicate()
			for tile in game.falling_tiles:
				in_cycle.erase(_key(tile["word"]))
		if step % 16 == 15:
			game._clear_transient_effects()
			await process_frame
			game.set_process(false)
	_check(boundary_count >= 2, tag + ": fewer than two vocabulary-cycle boundaries")
	_check(not game.round_finished and results.is_empty(),
		tag + ": game ended before timer=0 or hearts=0")
	if mode == "Lives":
		_check(game.time_remaining == 0.0 and game.lives == 3,
			tag + ": Lives has no timer and correct-only keeps three hearts")
		for lost in range(3):
			_check(_hit_real_wrong(game), tag + ": wrong apple catch for heart %d" % (lost + 1))
			_check(game.lives == 2 - lost, tag + ": exactly one heart lost")
			if lost < 2:
				_check(not game.round_finished and results.is_empty() and _next_wave(game),
					tag + ": Lives cannot finish while hearts remain")
		_check(game.round_finished and game.finish_reason == "lives_empty"
			and results.size() == 1, tag + ": Lives ends exactly once at 0 hearts")
	else:
		_check(game.lives == 3 and game.time_remaining > 0.0,
			tag + ": Seconds must have an active clock and inactive hearts")
		# The preceding real `_process()` collisions have consumed a fraction
		# of a second, so target ten milliseconds remaining rather than
		# subtracting a fixed 59.99 from an already-running clock.
		game._update_timer(maxf(game.time_remaining - 0.01, 0.0))
		_check(not game.round_finished and results.is_empty() and game.time_remaining > 0.0,
			tag + ": Seconds must not finish before timer reaches 0")
		game._update_timer(1.0)
		_check(game.round_finished and game.finish_reason == "time_up"
			and game.time_remaining == 0.0 and results.size() == 1,
			tag + ": Seconds ends exactly once when timer reaches zero")
	host.queue_free()
	await process_frame


func _hit_real_correct(game: Control) -> bool:
	return _hit_real_tile(game, true)


func _hit_real_wrong(game: Control) -> bool:
	return _hit_real_tile(game, false)


func _hit_real_tile(game: Control, matching: bool) -> bool:
	if game.round_finished or game.wave_phase != "falling":
		return false
	for i in range(game.falling_tiles.size()):
		var tile: Dictionary = game.falling_tiles[i]
		if bool(tile["matching"]) == matching:
			tile["pos"] = game._basket_rect().get_center()
			game.falling_tiles[i] = tile
			game._sync_tile_node(tile)
			game._process(0.0001)
			game.set_process(false)
			return game.wave_phase == "clearing" or game.round_finished
	return false


func _next_wave(game: Control) -> bool:
	if game.wave_phase != "clearing" or game.round_finished:
		return false
	game._update_spawning(game.WAVE_CLEAR_SECONDS + 0.01)
	game.set_process(false)
	return game.wave_phase == "falling" and game.falling_tiles.size() == 3


func _key(value: Variant) -> String:
	return String(value).strip_edges().to_lower()


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		_fail(description)


func _fail(description: String) -> void:
	failures.append(description)
