extends SceneTree

# Godot --headless --path . --script res://tools/test_catch_unique_session_words.gd
# Covers complete-wave uniqueness, difficulty, pause snapshot, and exhaustion.

const CATCH_SCENE := preload("res://ui/minigames/catch_word.tscn")
const GRAMMAR_BANK := preload("res://ui/minigames/grammar_bank.gd")
const TOPICS := ["Noun", "Verb", "Adjective"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]

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


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	await _test_real_bank()
	await _test_small_pool_exhaustion()
	await _test_cross_category_collisions()
	await _test_long_words_fit()
	if failures.is_empty():
		print("PASS Catch unique session words: %d checks, %d topics x %d difficulties + exhaustion/resume" % [checks, TOPICS.size(), DIFFICULTIES.size()])
		quit(0)
	else:
		for failure in failures:
			push_error("CATCH UNIQUE WORDS: " + failure)
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
			# Restoring a saved round must choose the next words, never repeat a
			# previously displayed distractor or correct choice.
			game.set_context(snapshot)
			game.set_process(false)
			_check(game.falling_tiles.size() == 3 and not game.round_finished,
				label + ": resumed session has no fresh question")
			for tile in game.falling_tiles:
				var key := String(tile["word"]).strip_edges().to_lower()
				_check(not shown.has(key), label + ": resume repeated word " + key)
			# A full restart discards word history and begins a new round.
			game.set_context({"topic": topic, "difficulty": difficulty, "game_mode": "Seconds"})
			game.set_process(false)
			_check(not game.round_finished and game.used_session_words.size() == 3 and game.wave_index == 1,
				label + ": fresh round did not reset word history")
			# Go beyond short samples and consume the entire difficulty pool.
			# This catches duplicates that only emerge near the final words.
			var full_round_words: Dictionary = {}
			var completed_waves := 0
			while not game.round_finished and completed_waves < 250:
				_check(game.falling_tiles.size() == 3,
					label + ": real pool yielded a partial wave before exhaustion")
				for tile in game.falling_tiles:
					var key := String(tile["word"]).strip_edges().to_lower()
					_check(not full_round_words.has(key), label + ": repeated after %d waves: %s" % [completed_waves, key])
					full_round_words[key] = true
				_next_wave(game)
				completed_waves += 1
				if completed_waves % 10 == 0:
					await process_frame
					game.set_process(false)
			_check(completed_waves >= 60 and completed_waves < 250 and game.round_finished
				and game.finish_reason == "word_pool_exhausted",
				label + ": full difficulty pool did not complete cleanly")
			_check(full_round_words.size() == game.used_session_words.size(),
				label + ": full-pool history does not contain exactly the shown words")
			host.queue_free()
			await process_frame


func _test_small_pool_exhaustion() -> void:
	var host := _new_host()
	var game := _new_game(host)
	game.grammar_bank = LimitedBank.new()
	game.set_context({"topic": "Noun", "difficulty": "Hard", "game_mode": "Seconds"})
	game.set_process(false)
	_check(game.falling_tiles.size() == 3, "small bank first wave incomplete")
	_next_wave(game)
	_check(game.falling_tiles.size() == 3 and not game.round_finished,
		"small bank second wave incomplete")
	game.score = 250
	_next_wave(game)
	_check(game.round_finished and game.finish_reason == "word_pool_exhausted",
		"pool depletion did not finish the session normally")
	_check(game.falling_tiles.is_empty() and game.wave_index == 2 and game.used_session_words.size() == 6,
		"pool exhaustion spawned an incomplete or repeated wave")
	var payload: Dictionary = game.get_context()
	_check(int(payload["score"]) == 250 and String(payload["completion_reason"]) == "word_pool_exhausted",
		"pool exhaustion lost score/completion payload")
	host.queue_free()
	await process_frame


func _test_cross_category_collisions() -> void:
	var host := _new_host()
	var game := _new_game(host)
	game.grammar_bank = OverlappingBank.new()
	game.set_context({"topic": "Noun", "difficulty": "Easy", "game_mode": "Seconds"})
	game.set_process(false)
	var observed: Dictionary = {}
	for wave in range(3):
		if game.round_finished:
			break
		for tile in game.falling_tiles:
			var word := String(tile["word"]).to_lower()
			_check(not observed.has(word), "same word shown as correct/wrong or across waves: " + word)
			observed[word] = true
		_next_wave(game)
	_check(game.round_finished and game.finish_reason == "word_pool_exhausted",
		"overlapping word pool did not terminate instead of duplicating")
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


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
