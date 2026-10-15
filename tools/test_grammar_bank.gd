extends SceneTree

const GrammarBank = preload("res://ui/minigames/grammar_bank.gd")
const TOPICS := ["Noun", "Verb", "Adjective", "Adverb", "Pronoun"]
const BANNED_AMBIGUOUS := ["run", "light", "play", "orange", "fast"]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_word_truth()
	_test_seed_determinism()
	_test_round_integrity()

	if failures.is_empty():
		print("PASS  grammar bank integrity and deterministic lane generation")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _test_word_truth() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 314159
	for topic in TOPICS:
		for _index in range(80):
			var matching := GrammarBank.pick_word(topic, true, rng)
			var nonmatching := GrammarBank.pick_word(topic, false, rng)
			_expect(GrammarBank.is_matching(matching, topic), "%s match mislabeled: %s" % [topic, matching])
			_expect(not GrammarBank.is_matching(nonmatching, topic), "%s distractor mislabeled: %s" % [topic, nonmatching])
			_expect(not BANNED_AMBIGUOUS.has(matching), "Ambiguous sample used: %s" % matching)
			_expect(not BANNED_AMBIGUOUS.has(nonmatching), "Ambiguous sample used: %s" % nonmatching)


func _test_seed_determinism() -> void:
	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 8675309
	second.seed = 8675309
	for topic in TOPICS:
		for difficulty in ["Easy", "Normal", "Hard"]:
			for _index in range(20):
				var a: Dictionary = GrammarBank.lane_round(topic, difficulty, first)
				var b: Dictionary = GrammarBank.lane_round(topic, difficulty, second)
				_expect(a == b, "Seeded output changed for %s/%s" % [topic, difficulty])


func _test_round_integrity() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261011
	var hard_two_correct_seen := false
	var lane_hits := [0, 0, 0]

	for topic in TOPICS:
		for difficulty in ["Easy", "Normal", "Hard"]:
			for _round_index in range(160):
				var round_data: Dictionary = GrammarBank.lane_round(topic, difficulty, rng)
				var options: Array[String] = round_data["options"]
				var valid_indices: Array[int] = round_data["valid_indices"]
				var unique_words := {}
				for word in options:
					unique_words[word] = true

				_expect(String(round_data["topic"]) == topic, "Topic changed in round: %s" % topic)
				_expect(not String(round_data["prompt"]).is_empty(), "Prompt missing for %s" % topic)
				_expect(options.size() == 3, "Round does not have three options for %s" % topic)
				_expect(unique_words.size() == 3, "Round contains duplicate options for %s: %s" % [topic, options])
				_expect(valid_indices.size() >= 1 and valid_indices.size() <= 2, "Invalid correct count for %s/%s" % [topic, difficulty])

				if difficulty == "Easy":
					_expect(valid_indices.size() == 1, "Easy round should have one clear answer")
				if difficulty == "Hard" and valid_indices.size() == 2:
					hard_two_correct_seen = true

				var actual_valid: Array[int] = []
				for option_index in range(options.size()):
					var word := options[option_index]
					_expect(not BANNED_AMBIGUOUS.has(word), "Ambiguous option used: %s" % word)
					if GrammarBank.is_matching(word, topic):
						actual_valid.append(option_index)
				_expect(actual_valid == valid_indices, "Declared answers do not match word truth for %s: %s vs %s" % [topic, valid_indices, actual_valid])

				if not valid_indices.is_empty():
					lane_hits[valid_indices[0]] += 1

	_expect(hard_two_correct_seen, "Hard difficulty never produced a two-correct round")
	for lane_index in range(3):
		_expect(lane_hits[lane_index] > 0, "Correct answer never appeared in lane %d" % lane_index)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
