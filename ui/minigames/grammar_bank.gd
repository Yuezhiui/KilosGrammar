extends RefCounted

const TOPICS := ["Noun", "Verb", "Adjective", "Adverb", "Pronoun"]

const WORD_BANK := {
	"Noun": [
		"apple", "teacher", "pencil", "rabbit", "river", "basket", "garden",
		"window", "kitten", "doctor", "mountain", "notebook", "library",
	],
	"Verb": [
		"arrives", "listens", "sleeps", "belongs", "exists", "appears",
		"becomes", "needs", "waits", "knows", "remembers", "agrees",
	],
	"Adjective": [
		"cheerful", "careful", "noisy", "sleepy", "wooden", "helpful",
		"curious", "gentle", "hungry", "friendly", "brave", "tiny",
	],
	"Adverb": [
		"carefully", "quietly", "gently", "happily", "softly", "safely",
		"patiently", "bravely", "neatly", "politely", "slowly", "warmly",
	],
	"Pronoun": [
		"he", "she", "they", "we", "you", "it",
		"them", "us", "him", "ours", "theirs", "hers",
	],
}

const PROMPTS := {
	"Noun": "Choose a noun: a word that names a person, place, animal, or thing.",
	"Verb": "Choose a verb: a word that shows an action or state.",
	"Adjective": "Choose an adjective: a word that describes a noun.",
	"Adverb": "Choose an adverb: a word that tells how an action happens.",
	"Pronoun": "Choose a pronoun: a word that can take the place of a noun.",
}


static func pick_word(topic: String, matching: bool, rng: RandomNumberGenerator) -> String:
	var canonical_topic := _canonical_topic(topic)
	if canonical_topic.is_empty():
		push_warning("Unsupported grammar topic '%s'; using Noun." % topic)
		canonical_topic = "Noun"

	var candidates: Array[String] = []
	if matching:
		for word in WORD_BANK[canonical_topic]:
			candidates.append(String(word))
	else:
		for other_topic in TOPICS:
			if other_topic == canonical_topic:
				continue
			for word in WORD_BANK[other_topic]:
				candidates.append(String(word))

	if candidates.is_empty():
		return ""
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func lane_round(topic: String, difficulty: String, rng: RandomNumberGenerator) -> Dictionary:
	var canonical_topic := _canonical_topic(topic)
	if canonical_topic.is_empty():
		push_warning("Unsupported grammar topic '%s'; using Noun." % topic)
		canonical_topic = "Noun"

	var correct_count := _correct_count_for_difficulty(difficulty, rng)
	var entries: Array[Dictionary] = []
	var used_words := {}

	for _index in range(correct_count):
		var word := _pick_unique_word(canonical_topic, true, rng, used_words)
		used_words[word] = true
		entries.append({"word": word, "valid": true})

	for _index in range(3 - correct_count):
		var word := _pick_unique_word(canonical_topic, false, rng, used_words)
		used_words[word] = true
		entries.append({"word": word, "valid": false})

	_shuffle_entries(entries, rng)

	var options: Array[String] = []
	var valid_indices: Array[int] = []
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		options.append(String(entry["word"]))
		if bool(entry["valid"]):
			valid_indices.append(index)

	return {
		"prompt": String(PROMPTS[canonical_topic]),
		"options": options,
		"valid_indices": valid_indices,
		"topic": canonical_topic,
	}


static func is_matching(word: String, topic: String) -> bool:
	var canonical_topic := _canonical_topic(topic)
	if canonical_topic.is_empty():
		return false
	return WORD_BANK[canonical_topic].has(word.strip_edges().to_lower())


static func _canonical_topic(topic: String) -> String:
	var normalized := topic.strip_edges().to_lower()
	for candidate in TOPICS:
		if candidate.to_lower() == normalized:
			return candidate
	return ""


static func _correct_count_for_difficulty(difficulty: String, rng: RandomNumberGenerator) -> int:
	match difficulty.strip_edges().to_lower():
		"hard":
			return 2 if rng.randf() < 0.50 else 1
		"normal", "medium":
			return 2 if rng.randf() < 0.20 else 1
		_:
			# Easy and unknown difficulty values keep the round unambiguous.
			return 1


static func _pick_unique_word(
	topic: String,
	matching: bool,
	rng: RandomNumberGenerator,
	used_words: Dictionary
) -> String:
	var candidates: Array[String] = []
	if matching:
		for word in WORD_BANK[topic]:
			var candidate := String(word)
			if not used_words.has(candidate):
				candidates.append(candidate)
	else:
		for other_topic in TOPICS:
			if other_topic == topic:
				continue
			for word in WORD_BANK[other_topic]:
				var candidate := String(word)
				if not used_words.has(candidate):
					candidates.append(candidate)

	if candidates.is_empty():
		return ""
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func _shuffle_entries(entries: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	for index in range(entries.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary := entries[index]
		entries[index] = entries[swap_index]
		entries[swap_index] = temporary
