extends SceneTree

const GrammarBank = preload("res://ui/minigames/shared/grammar_bank.gd")
const TOPICS := ["Noun", "Verb", "Adjective", "Adverb", "Pronoun"]
const EXPANDED_TOPICS := ["Noun", "Verb", "Adjective"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const BANNED_AMBIGUOUS := ["run", "light", "play", "orange", "fast"]
const ORIGINAL_BANK := {
	"Noun": ["apple", "teacher", "pencil", "rabbit", "river", "basket", "garden", "window", "kitten", "doctor", "mountain", "notebook", "library"],
	"Verb": ["arrives", "listens", "sleeps", "belongs", "exists", "appears", "becomes", "needs", "waits", "knows", "remembers", "agrees"],
	"Adjective": ["cheerful", "careful", "noisy", "sleepy", "wooden", "helpful", "curious", "gentle", "hungry", "friendly", "brave", "tiny"],
	"Adverb": ["carefully", "quietly", "gently", "happily", "softly", "safely", "patiently", "bravely", "neatly", "politely", "slowly", "warmly"],
	"Pronoun": ["he", "she", "they", "we", "you", "it", "them", "us", "him", "ours", "theirs", "hers"],
}

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_inventory_and_classification()
	_test_difficulty_pools()
	_test_word_truth()
	_test_seed_determinism()
	_test_round_integrity()
	_test_history_and_exhaustion()
	if failures.is_empty():
		print("PASS  grammar bank: +600 distinct words, tiers, matching, seeded rounds, no-repeat exhaustion")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _test_inventory_and_classification() -> void:
	var owner := {}
	for topic in TOPICS:
		var bank: Array = GrammarBank.WORD_BANK[topic]
		var seen := {}
		var expected_size: int = ORIGINAL_BANK[topic].size()
		if EXPANDED_TOPICS.has(topic):
			expected_size += 200
		else:
			_expect(bank.size() >= ORIGINAL_BANK[topic].size() + 24, "%s needs at least 24 additional words for 12 non-repeating waves" % topic)
			expected_size = bank.size()
		_expect(bank.size() == expected_size, "%s size: expected %d, got %d" % [topic, expected_size, bank.size()])
		for original_word in ORIGINAL_BANK[topic]:
			_expect(bank.has(original_word), "%s lost original word: %s" % [topic, original_word])
		if not EXPANDED_TOPICS.has(topic):
			_expect(bank.slice(0, ORIGINAL_BANK[topic].size()) == ORIGINAL_BANK[topic], "%s original legacy words were moved or changed" % topic)
		for word_value in bank:
			var word := String(word_value)
			_expect(word == word.strip_edges().to_lower() and not word.is_empty(), "%s unnormalized word: %s" % [topic, word])
			_expect(not seen.has(word), "%s duplicate word: %s" % [topic, word])
			_expect(not owner.has(word), "Word occurs in two grammar categories: %s (%s/%s)" % [word, str(owner.get(word, "")), topic])
			_expect(not BANNED_AMBIGUOUS.has(word), "Ambiguous sample used: %s" % word)
			_expect(GrammarBank.is_matching(word, topic), "%s mislabeled: %s" % [topic, word])
			seen[word] = true
			owner[word] = topic
	_expect(owner.size() >= 709, "Expected at least 709 globally unique words, found %d" % owner.size())


func _test_difficulty_pools() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261023
	for topic in EXPANDED_TOPICS:
		var ranges: Dictionary = GrammarBank.TIER_RANGES[topic]
		var bank: Array = GrammarBank.WORD_BANK[topic]
		var original_count: int = ORIGINAL_BANK[topic].size()
		_expect((ranges["Easy"] as Vector2i) == Vector2i(0, original_count + 65), "%s Easy tier boundaries invalid" % topic)
		_expect((ranges["Normal"] as Vector2i) == Vector2i(original_count + 65, original_count + 130), "%s Normal tier boundaries invalid" % topic)
		_expect((ranges["Hard"] as Vector2i) == Vector2i(original_count + 130, original_count + 200), "%s Hard tier boundaries invalid" % topic)
		var tier_owners := {}
		for difficulty in DIFFICULTIES:
			var bounds: Vector2i = ranges[difficulty]
			for index in range(bounds.x, bounds.y):
				var word := String(bank[index])
				_expect(not tier_owners.has(word), "%s appears in multiple %s tiers" % [word, topic])
				tier_owners[word] = difficulty
			for _index in range(75):
				var picked := GrammarBank.pick_word(topic, true, rng, difficulty)
				_expect(tier_owners.get(picked) == difficulty, "%s/%s returned outside tier: %s" % [topic, difficulty, picked])
		_expect(tier_owners.size() == bank.size(), "%s tier ranges do not cover every word" % topic)
		var medium_rng := RandomNumberGenerator.new()
		medium_rng.seed = 123456
		for _index in range(20):
			var medium := GrammarBank.pick_word(topic, true, medium_rng, "medium")
			_expect(tier_owners.get(medium) == "Normal", "'medium' should alias Normal for %s" % topic)
	for topic in ["Adverb", "Pronoun"]:
		_expect(not GrammarBank.TIER_RANGES.has(topic), "%s should retain its original undivided word pool" % topic)


func _test_word_truth() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 314159
	for topic in TOPICS:
		for difficulty in DIFFICULTIES:
			for _index in range(35):
				var matching := GrammarBank.pick_word(topic, true, rng, difficulty)
				var nonmatching := GrammarBank.pick_word(topic, false, rng, difficulty)
				_expect(GrammarBank.is_matching(matching, topic), "%s/%s match mislabeled: %s" % [topic, difficulty, matching])
				_expect(not GrammarBank.is_matching(nonmatching, topic), "%s/%s distractor mislabeled: %s" % [topic, difficulty, nonmatching])
			_expect(GrammarBank.is_matching("  " + String(GrammarBank.WORD_BANK[topic][0]).to_upper() + "  ", topic), "%s case-insensitive match broken" % topic)


func _test_seed_determinism() -> void:
	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 8675309
	second.seed = 8675309
	for topic in TOPICS:
		for difficulty in DIFFICULTIES:
			for _index in range(15):
				var a: Dictionary = GrammarBank.lane_round(topic, difficulty, first)
				var b: Dictionary = GrammarBank.lane_round(topic, difficulty, second)
				_expect(a == b, "Seeded output changed for %s/%s" % [topic, difficulty])


func _test_round_integrity() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261011
	var hard_two_correct_seen := false
	var lane_hits := [0, 0, 0]
	for topic in TOPICS:
		for difficulty in DIFFICULTIES:
			for _round_index in range(90):
				var round_data: Dictionary = GrammarBank.lane_round(topic, difficulty, rng)
				var options: Array[String] = round_data["options"]
				var valid_indices: Array[int] = round_data["valid_indices"]
				var unique_words := {}
				for word in options:
					unique_words[word] = true
				_expect(String(round_data["topic"]) == topic, "Topic changed in %s round" % topic)
				_expect(not String(round_data["prompt"]).is_empty(), "Prompt missing for %s" % topic)
				_expect(options.size() == 3, "Round does not have three options for %s/%s" % [topic, difficulty])
				_expect(unique_words.size() == 3, "Round contains duplicate options for %s: %s" % [topic, options])
				_expect(valid_indices.size() >= 1 and valid_indices.size() <= 2, "Invalid correct count for %s/%s" % [topic, difficulty])
				if difficulty == "Easy":
					_expect(valid_indices.size() == 1, "Easy round should have one clear answer")
				if difficulty == "Hard" and valid_indices.size() == 2:
					hard_two_correct_seen = true
				var actual_valid: Array[int] = []
				for option_index in range(options.size()):
					var word := options[option_index]
					if EXPANDED_TOPICS.has(topic) and difficulty != "Easy":
						var grade_matches := false
						for candidate_topic in EXPANDED_TOPICS:
							var grade_window: Vector2i = GrammarBank.TIER_RANGES[candidate_topic][difficulty]
							var grade_pool: Array = GrammarBank.WORD_BANK[candidate_topic].slice(grade_window.x, grade_window.y)
							if grade_pool.has(word):
								grade_matches = true
						_expect(grade_matches, "Inappropriate difficulty distractor in %s/%s: %s" % [topic, difficulty, word])
					if GrammarBank.is_matching(word, topic):
						actual_valid.append(option_index)
				_expect(actual_valid == valid_indices, "Declared answers do not match truth for %s: %s vs %s" % [topic, valid_indices, actual_valid])
				if not valid_indices.is_empty():
					lane_hits[valid_indices[0]] += 1
	_expect(hard_two_correct_seen, "Hard difficulty never produced a two-correct round")
	for lane_index in range(3):
		_expect(lane_hits[lane_index] > 0, "Correct answer never appeared in lane %d" % lane_index)


func _test_history_and_exhaustion() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 222222
	for topic in TOPICS:
		for difficulty in DIFFICULTIES:
			var history := {}
			var emitted := 0
			for round_index in range(225):
				var previous_size := history.size()
				var round_data: Dictionary = GrammarBank.lane_round(topic, difficulty, rng, history)
				_expect(history.size() == previous_size, "lane_round mutated exclusion dictionary")
				var options: Array[String] = round_data["options"]
				if options.is_empty():
					if topic == "Adverb" or topic == "Pronoun":
						_expect(round_index >= 12, "%s/%s exhausted before 12 complete waves: %d" % [topic, difficulty, round_index])
					_expect((round_data["valid_indices"] as Array).is_empty(), "Empty round must not expose valid indices")
					break
				_expect(options.size() == 3, "History round returned partially filled options")
				for word in options:
					_expect(not history.has(word), "Repeat within %s/%s history: %s" % [topic, difficulty, word])
					history[word] = true
					emitted += 1
				_expect(round_index < 224, "%s/%s never exhausted" % [topic, difficulty])
			_expect(emitted >= 3, "%s/%s never generated a round" % [topic, difficulty])
			var after_exhaustion: Dictionary = GrammarBank.lane_round(topic, difficulty, rng, history)
			_expect((after_exhaustion["options"] as Array).is_empty(), "%s/%s repeats after exhaustion" % [topic, difficulty])
			# Every eligible true answer excluded (uppercase/whitespace keys) => empty.
			var matching_excluded := {}
			var candidate_pool: Array = GrammarBank.WORD_BANK[topic]
			if GrammarBank.TIER_RANGES.has(topic):
				var bounds: Vector2i = GrammarBank.TIER_RANGES[topic][difficulty]
				candidate_pool = candidate_pool.slice(bounds.x, bounds.y)
			for word_value in candidate_pool:
				matching_excluded["  " + String(word_value).to_upper() + "  "] = true
			_expect(GrammarBank.pick_word(topic, true, rng, difficulty, matching_excluded).is_empty(), "Matching exclusion case normalization failed: %s/%s" % [topic, difficulty])
			# Also confirm nonmatching exhaustion and fully exhausted lane round.
			var all_excluded := {}
			for every_topic in TOPICS:
				for word_value in GrammarBank.WORD_BANK[every_topic]:
					all_excluded[String(word_value).to_upper()] = true
			_expect(GrammarBank.pick_word(topic, false, rng, difficulty, all_excluded).is_empty(), "Distractor exhaustion produced a word")
			var empty_data: Dictionary = GrammarBank.lane_round(topic, difficulty, rng, all_excluded)
			_expect((empty_data["options"] as Array).is_empty(), "Fully exhausted lane round repeated a word")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
