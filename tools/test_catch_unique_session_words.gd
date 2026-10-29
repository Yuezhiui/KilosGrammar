extends SceneTree

# Godot --headless --path . --script res://tools/test_catch_unique_session_words.gd
# Covers complete-wave uniqueness, REAL GrammarBank tier/topic integrity,
# repeatable vocabulary cycles, pause/restart and strict mode-only endings.
# A word may recur in a NEW cycle, never twice in the same cycle.

const CATCH_SCENE := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const GRAMMAR_BANK := preload("res://ui/minigames/shared/grammar_bank.gd")
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]

class LimitedBank:
	extends RefCounted
	var matching_words := ["MatchA", "MatchB"]
	var wrong_words := ["WrongA", "WrongB", "WrongC", "WrongD"]

	func pick_word(_topic: String, matching: bool, _rng: RandomNumberGenerator,
			_difficulty: String = "Easy", excluded: Dictionary = {}) -> String:
		for candidate in matching_words if matching else wrong_words:
			if not excluded.has(String(candidate).to_lower()):
				return candidate
		return ""


class OverlappingBank:
	extends LimitedBank

	func _init() -> void:
		matching_words = ["Shared", "MatchB"]
		wrong_words = ["SHARED", "WrongB", "WrongC", "WrongD"]


var checks := 0
var failures: Array[String] = []
var cycle_cases := 0
var inspected_waves := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_real_bank()
	await _test_real_bank_cycles()
	await _test_small_pool_recycling()
	await _test_cross_category_collisions()
	await _test_long_words_fit()
	if failures.is_empty():
		print("PASS Catch unique session words: %d checks, %d topic/difficulty/mode real-bank cycle scenarios, %d inspected waves; pause/restart/tier/strict-end verified" % [checks, cycle_cases, inspected_waves])
		quit(0)
	else:
		for failure in failures.slice(0, 35):
			push_error("CATCH UNIQUE WORDS: " + failure)
		if failures.size() > 35:
			print("... %d additional failures" % (failures.size() - 35))
		print("FAIL Catch unique session words: %d failures across %d checks, %d scenarios and %d inspected waves" % [failures.size(), checks, cycle_cases, inspected_waves])
		quit(1)


func _test_real_bank() -> void:
	for topic in TOPICS:
		for difficulty in DIFFICULTIES:
			var host := _new_host()
			var game := _new_game(host)
			game.set_context({"topic": topic, "difficulty": difficulty, "game_mode": "Seconds"})
			game.set_process(false)
			var shown: Dictionary = {}
			var label := "%s/%s" % [topic, difficulty]
			_check(is_equal_approx(game.base_fall_speed, _expected_speed(difficulty)),
				label + ": initial speed differs from requested difficulty")
			for wave in range(10):
				_check(not game.round_finished, "%s: bank exhausted before 10 waves" % label)
				if game.round_finished:
					break
				_check(game.falling_tiles.size() == game.APPLES_PER_WAVE,
					"%s wave %d: no complete 3-apple set" % [label, wave])
				var matching_count := 0
				for tile in game.falling_tiles:
					var word := String(tile["word"])
					var normalized := word.strip_edges().to_lower()
					_check(not normalized.is_empty() and not shown.has(normalized),
						"%s wave %d: duplicate displayed word: %s" % [label, wave, word])
					shown[normalized] = true
					_check(bool(tile["matching"]) == GRAMMAR_BANK.is_matching(word, topic),
						"%s wave %d: incorrect grammar classification for %s" % [label, wave, word])
					_check(GRAMMAR_BANK._available_words(topic, bool(tile["matching"]), difficulty, {}).has(word),
						"%s wave %d: word outside selected difficulty tier: %s" % [label, wave, word])
					if bool(tile["matching"]):
						matching_count += 1
				_check(matching_count == 1, "%s wave %d: expected one correct apple" % [label, wave])
				_check(game.used_session_words.size() == shown.size(),
					"%s wave %d: history does not include all displayed apples" % [label, wave])
				if wave < 9:
					_next_wave(game)
			var snapshot: Dictionary = game.get_context()
			_check((snapshot.get("catch_used_words", []) as Array).size() == shown.size(),
				label + ": pause snapshot missing shown words")
			# Restoring a saved round must choose the next unused words within
			# this same vocabulary cycle, never replay the paused three apples.
			game.set_context(snapshot)
			game.set_process(false)
			_check(game.falling_tiles.size() == 3 and not game.round_finished,
				label + ": resumed session has no fresh question")
			_check(game.vocabulary_cycle == int(snapshot.get("catch_vocab_cycle", -1)),
				label + ": pause/resume unexpectedly reset vocabulary cycle")
			for tile in game.falling_tiles:
				var key := String(tile["word"]).strip_edges().to_lower()
				_check(not shown.has(key), label + ": resume repeated word " + key)
				_check(GRAMMAR_BANK._available_words(topic, bool(tile["matching"]), difficulty, {}).has(String(tile["word"])),
					label + ": resume changed difficulty tier")
			# A full restart discards word history and begins a new round.
			game.set_context({"topic": topic, "difficulty": difficulty, "game_mode": "Seconds"})
			game.set_process(false)
			_check(not game.round_finished and game.used_session_words.size() == 3
				and game.wave_index == 1 and game.vocabulary_cycle == 0,
				label + ": fresh round did not reset word history")
			host.queue_free()
			await process_frame


func _test_real_bank_cycles() -> void:
	for topic in TOPICS:
		for difficulty in DIFFICULTIES:
			for mode in MODES:
				var name := "%s/%s/%s full-bank cycles" % [topic, difficulty, mode]
				var host := _new_host()
				var game := _new_game(host)
				game.set_context({"topic": topic, "difficulty": difficulty, "game_mode": mode})
				game.set_process(false)
				cycle_cases += 1
				var results: Array[Dictionary] = []
				game.requested.connect(func(target: String, payload: Dictionary) -> void:
					if target == "results":
						results.append(payload.duplicate(true))
				)
				var per_cycle: Dictionary = {}
				var previous_wave: Dictionary = {}
				var cycle := 0
				var transitions := 0
				var waves := 0
				var fourth_cycle_seen := false
				# Three FULL pools, plus the first question of the fourth cycle.
				# These are real tier-matched GrammarBank words, NOT fake fixtures.
				while not fourth_cycle_seen and waves < 280:
					if game.round_finished or game.falling_tiles.size() != 3:
						_check(false, name + ": early Results or incomplete wave %d" % waves)
						break
					var current_cycle: int = game.vocabulary_cycle
					if current_cycle != cycle:
						_check(current_cycle == cycle + 1,
							name + ": vocabulary cycle index skipped at wave %d" % waves)
						transitions += 1
						per_cycle.clear()
						# The previous three words should not immediately recur if
						# a complete real 1-correct/2-wrong wave can avoid them.
						var eligible_correct := GRAMMAR_BANK._available_words(topic, true, difficulty, previous_wave)
						var eligible_wrong := GRAMMAR_BANK._available_words(topic, false, difficulty, previous_wave)
						if eligible_correct.size() >= 1 and eligible_wrong.size() >= 2:
							for tile in game.falling_tiles:
								_check(not previous_wave.has(_key(tile["word"])),
									name + ": immediate previous-wave repeat across cycle boundary")
						cycle = current_cycle
					var wave_words: Dictionary = {}
					var correct_count := 0
					for tile in game.falling_tiles:
						var word := String(tile["word"])
						var word_key := _key(word)
						var is_correct := bool(tile["matching"])
						_check(not word_key.is_empty() and not wave_words.has(word_key),
							name + ": same wave contains duplicate/blank word")
						_check(not per_cycle.has(word_key),
							name + ": repeated word within vocabulary cycle %d: %s" % [cycle, word])
						_check(GRAMMAR_BANK.is_matching(word, topic) == is_correct,
							name + ": invalid correct/distractor classification: " + word)
						_check(GRAMMAR_BANK._available_words(topic, is_correct, difficulty, {}).has(word),
							name + ": word outside real source topic/tier: " + word)
						wave_words[word_key] = true
						per_cycle[word_key] = true
						if is_correct:
							correct_count += 1
					_check(correct_count == 1 and wave_words.size() == 3,
						name + ": 1-correct/2-distractor contract was broken")
					_check(game.used_session_words.size() == per_cycle.size(),
						name + ": recorded vocabulary-cycle history is incomplete")
					_check(not game.round_finished and results.is_empty(),
						name + ": exhausted words caused premature Results")
					_check(game.game_mode == mode and game.topic == topic and game.difficulty == difficulty,
						name + ": source settings changed between cycles")
					_check(game.lives == 3 and game.time_remaining == (60.0 if mode == "Seconds" else 0.0),
						name + ": simulated wave selection should not spend hearts or timer")
					previous_wave = wave_words
					waves += 1
					inspected_waves += 1
					fourth_cycle_seen = current_cycle >= 3
					if not fourth_cycle_seen:
						_next_wave(game)
					if waves % 25 == 0:
						await process_frame
						game.set_process(false)
				_check(transitions >= 3 and fourth_cycle_seen and waves > 20,
					name + ": did not complete three full real-bank vocabulary cycles")
				_check(not game.round_finished and results.is_empty(),
					name + ": finite pool ended the round before timer/heart limit")
				# Real emitted Results events, not a manually assigned finish flag.
				# A wrong apple hits the real basket via the gameplay collision path.
				if mode == "Seconds":
					for attempt in range(3):
						_check(_catch_wrong_apple(game), name + ": cannot catch wrong apple in Seconds")
						_check(not game.round_finished and game.lives == 3 and results.is_empty(),
							name + ": Seconds mistake cost a heart or ended the game")
						_next_wave(game)
					game._update_timer(maxf(game.time_remaining - 0.01, 0.0))
					_check(not game.round_finished and game.time_remaining > 0.0 and results.is_empty(),
						name + ": Seconds ended before timer reached zero")
					game._update_timer(1.0)
					_check(game.round_finished and game.finish_reason == "time_up"
						and game.time_remaining == 0.0 and results.size() == 1,
						name + ": Seconds did not end exactly once at timer zero")
				else:
					game._update_timer(300.0)
					_check(not game.round_finished and game.time_remaining == 0.0,
						name + ": Lives incorrectly uses a timer")
					for attempt in range(3):
						_check(_catch_wrong_apple(game), name + ": cannot catch wrong apple in Lives")
						_check(game.lives == 2 - attempt,
							name + ": one wrong catch did not subtract exactly one heart")
						if attempt < 2:
							_check(not game.round_finished and results.is_empty(),
								name + ": Lives ended before three hearts were lost")
							_next_wave(game)
					_check(game.round_finished and game.finish_reason == "lives_empty"
						and results.size() == 1, name + ": Lives did not end exactly once at 0 hearts")
				if results.size() == 1:
					_check(results[0].get("completion_reason", "") == ("time_up" if mode == "Seconds" else "lives_empty")
						and int(results[0].get("lives", -1)) == (3 if mode == "Seconds" else 0),
						name + ": final Results payload has incorrect end condition")
				host.queue_free()
				await process_frame


func _test_small_pool_recycling() -> void:
	var host := _new_host()
	var game := _new_game(host)
	game.grammar_bank = LimitedBank.new()
	game.set_context({"topic": "Noun", "difficulty": "Hard", "game_mode": "Seconds"})
	game.set_process(false)
	_check(game.falling_tiles.size() == 3, "small bank first wave incomplete")
	var cycle_zero: Dictionary = {}
	for tile in game.falling_tiles:
		cycle_zero[_key(tile["word"])] = true
	_next_wave(game)
	_check(game.falling_tiles.size() == 3 and not game.round_finished,
		"small bank second wave incomplete")
	for tile in game.falling_tiles:
		var key := _key(tile["word"])
		_check(not cycle_zero.has(key), "small-bank duplicate inside the first cycle: " + key)
		cycle_zero[key] = true
	_check(cycle_zero.size() == 6 and game.used_session_words.size() == 6,
		"small bank did not show each eligible word exactly once in first cycle")
	game.score = 250
	_next_wave(game)
	_check(not game.round_finished and game.vocabulary_cycle == 1,
		"small-bank exhaustion must recycle vocabulary without ending Seconds")
	_check(game.falling_tiles.size() == 3 and game.wave_index == 3 and game.used_session_words.size() == 3,
		"small-bank cycle did not restart with exactly three valid apples")
	var new_wave: Dictionary = {}
	for tile in game.falling_tiles:
		var key := _key(tile["word"])
		_check(cycle_zero.has(key) and not new_wave.has(key),
			"recycled small-bank wave contains fabricated or duplicate option")
		new_wave[key] = true
	var payload: Dictionary = game.get_context()
	_check(int(payload["score"]) == 250 and String(payload["completion_reason"]) == ""
		and int(payload["catch_vocab_cycle"]) == 1
		and (payload["catch_used_words"] as Array).size() == 3,
		"recycling lost points, cycle history, or caused premature Results")
	game._update_timer(60.0)
	_check(game.round_finished and game.finish_reason == "time_up" and game.score == 250,
		"small-bank Seconds must finish only at timer zero with score preserved")
	host.queue_free()
	await process_frame


func _test_cross_category_collisions() -> void:
	var host := _new_host()
	var game := _new_game(host)
	game.grammar_bank = OverlappingBank.new()
	game.set_context({"topic": "Noun", "difficulty": "Easy", "game_mode": "Seconds"})
	game.set_process(false)
	var observed: Dictionary = {}
	var last_cycle := 0
	for wave in range(10):
		if game.vocabulary_cycle != last_cycle:
			_check(game.vocabulary_cycle == last_cycle + 1,
				"overlapping small bank cycle advanced by more than one")
			observed.clear()
			last_cycle = game.vocabulary_cycle
		var within_wave: Dictionary = {}
		var correct_count := 0
		for tile in game.falling_tiles:
			var word := _key(tile["word"])
			_check(not within_wave.has(word), "same case-insensitive word shown as both correct and wrong in a wave: " + word)
			_check(not observed.has(word), "same case-insensitive word reused within overlapping bank cycle: " + word)
			_check(word in ["shared", "matchb", "wrongb", "wrongc", "wrongd"],
				"overlapping fixture produced an invented option: " + word)
			if bool(tile["matching"]):
				correct_count += 1
			within_wave[word] = true
			observed[word] = true
		_check(correct_count == 1 and within_wave.size() == 3,
			"overlapping bank must preserve 1 matching and 2 distinct distractors")
		_check(not game.round_finished and game.falling_tiles.size() == 3,
			"overlapping bank must not prematurely finish Seconds")
		_next_wave(game)
	_check(game.vocabulary_cycle >= 2 and not game.round_finished,
		"overlapping small bank did not safely cycle for multiple rounds")
	game._update_timer(60.0)
	_check(game.round_finished and game.finish_reason == "time_up",
		"overlapping bank must finish Seconds only on timer zero")
	host.queue_free()
	await process_frame


func _test_long_words_fit() -> void:
	var host := _new_host()
	var game := _new_game(host)
	var long_word := "unpredictability"
	var apple: Control = game._create_tile_node(long_word, Color.WHITE)
	var label := apple.get_node("WordLabel") as Label
	var actual_size := label.get_theme_font_size("font_size")
	var actual_width := label.get_theme_font("font").get_string_size(
		label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, actual_size).x
	_check(actual_size < 16 and actual_width <= game.APPLE_SIZE.x - 14.0
		and label.clip_text and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		"hard long words are not centered and fitted inside the original 106px apple")
	host.queue_free()
	await process_frame


func _expected_speed(difficulty: String) -> float:
	match difficulty:
		"Hard":
			return 245.0
		"Normal":
			return 185.0
		_:
			return 105.0


func _new_host() -> Control:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	return host


func _new_game(host: Control) -> Control:
	var game := CATCH_SCENE.instantiate() as Control
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_process(false)
	return game


func _next_wave(game: Control) -> void:
	game._clear_falling_tiles()
	game._spawn_wave()


func _catch_wrong_apple(game: Control) -> bool:
	if game.round_finished or game.falling_tiles.size() != 3 or game.wave_phase != "falling":
		return false
	for index in range(game.falling_tiles.size()):
		var tile: Dictionary = game.falling_tiles[index]
		if not bool(tile["matching"]):
			tile["pos"] = game._basket_rect().get_center()
			game.falling_tiles[index] = tile
			game._sync_tile_node(tile)
			game._process(0.0001)
			game.set_process(false)
			return game.wave_phase == "clearing" or game.round_finished
	return false


func _key(word: Variant) -> String:
	return String(word).strip_edges().to_lower()


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
