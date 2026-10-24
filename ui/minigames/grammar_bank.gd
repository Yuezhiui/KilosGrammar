extends RefCounted

# Every new Noun/Verb/Adjective belongs to exactly one difficulty tier.
# Easy also contains the original examples, preserved for compatibility.
const TOPICS := ["Noun", "Verb", "Adjective", "Adverb", "Pronoun"]

const WORD_BANK := {
	"Noun": [
		# Easy — 13 original + 65 new
		"apple", "teacher", "pencil", "rabbit", "river", "basket",
		"garden", "window", "kitten", "doctor", "mountain", "notebook",
		"library", "backpack", "banana", "bicycle", "bookshelf", "butterfly",
		"camera", "candle", "carrot", "chalkboard", "chimney", "classroom",
		"coconut", "cookie", "cousin", "cupboard", "dolphin", "dragonfly",
		"elephant", "envelope", "farmer", "feather", "flashlight", "flowerpot",
		"fountain", "giraffe", "goalkeeper", "grandmother", "guitar", "handbag",
		"hedgehog", "helicopter", "helmet", "honeybee", "igloo", "island",
		"jacket", "jellyfish", "kangaroo", "keyboard", "ladder", "lantern",
		"mailbox", "magician", "necklace", "octopus", "painter", "pancake",
		"penguin", "playground", "pumpkin", "rainbow", "refrigerator", "scooter",
		"squirrel", "suitcase", "telescope", "astronaut", "baker", "dentist",
		"firefighter", "librarian", "musician", "puppy", "zookeeper", "alligator",
		# Normal — 65 new
		"acquaintance", "acrobat", "archaeologist", "archivist", "astronomer", "atlas",
		"aviary", "barrister", "botanist", "cathedral", "centrifuge", "chrysalis",
		"constellation", "continent", "corridor", "courthouse", "curator", "custodian",
		"decanter", "dermatologist", "diaphragm", "diplomat", "dispenser", "dormitory",
		"ecosystem", "embassy", "equator", "estuary", "excavator", "expedition",
		"falconer", "geologist", "geyser", "glacier", "habitat", "hemisphere",
		"historian", "horticulturist", "infirmary", "interpreter", "inventor", "laboratory",
		"lighthouse", "locomotive", "mammal", "manuscript", "mathematician", "meteorologist",
		"monastery", "observatory", "peninsula", "pharmacist", "physicist", "reservoir",
		"sanctuary", "satellite", "specimen", "terrarium", "thermometer", "volcano",
		"waterfall", "ambassador", "anthology", "ceremony", "tradition",
		# Hard — 70 new
		"abdomen", "accelerator", "amphitheater", "anemometer", "anthropologist", "aqueduct",
		"arboretum", "archipelago", "artifact", "asteroid", "atmosphere", "barometer",
		"bacterium", "biographer", "biosphere", "cartographer", "catalyst", "chronometer",
		"circumference", "civilization", "climatologist", "conservatory", "crustacean", "cryptographer",
		"cytoplasm", "debris", "depository", "descendant", "echolocation", "ecologist",
		"endoskeleton", "entomologist", "epidemiologist", "epidermis", "exoplanet", "fermentation",
		"fossilization", "geographer", "glaciologist", "gyroscope", "herbarium", "hydrosphere",
		"hypothesis", "ichthyologist", "incubation", "infrastructure", "ionosphere", "isotope",
		"jurisprudence", "kaleidoscope", "lithosphere", "metamorphosis", "microbiologist", "microorganism",
		"mitochondrion", "nebula", "neurologist", "nocturne", "oasis", "oceanographer",
		"ornithologist", "paleontologist", "photosynthesis", "planetarium", "precipitation", "quadrilateral",
		"seismograph", "spectrometer", "stalactite", "stalagmite",
	],
	"Verb": [
		# Easy — 12 original + 65 new
		"arrives", "listens", "sleeps", "belongs", "exists", "appears",
		"becomes", "needs", "waits", "knows", "remembers", "agrees",
		"applauds", "blinks", "bounces", "cuddles", "delivers", "describes",
		"discovers", "eats", "enjoys", "finishes", "glances", "greets",
		"hugs", "imagines", "kneels", "laughs", "learns", "nods",
		"obeys", "packs", "paints", "peeks", "prays", "promises",
		"recycles", "repairs", "replies", "rescues", "rinses", "roars",
		"scribbles", "shares", "sneezes", "sniffs", "solves", "spins",
		"stretches", "studies", "thanks", "tiptoes", "travels", "trembles",
		"tries", "visits", "wanders", "whispers", "wiggles", "wishes",
		"yawns", "yells", "zigzags", "zips", "climbs", "chats",
		"cleans", "cooks", "cries", "digs", "drifts", "drives",
		"escapes", "fetches", "finds", "follows", "hops",
		# Normal — 65 new
		"accompanies", "adapts", "admires", "advises", "announces", "apologizes",
		"appreciates", "assembles", "assists", "calculates", "celebrates", "clarifies",
		"collaborates", "compares", "complains", "concentrates", "confirms", "conquers",
		"contributes", "convinces", "coordinates", "demonstrates", "diagnoses", "discusses",
		"distinguishes", "distributes", "educates", "eliminates", "encourages", "estimates",
		"examines", "expands", "explains", "explores", "expresses", "forgives",
		"gathers", "identifies", "illustrates", "improves", "influences", "inspects",
		"interprets", "investigates", "maintains", "manages", "measures", "negotiates",
		"observes", "organizes", "participates", "performs", "persuades", "predicts",
		"prepares", "prevents", "protects", "recommends", "recovers", "researches",
		"responds", "summarizes", "translates", "volunteers", "accelerates",
		# Hard — 70 new
		"acclimatizes", "accumulates", "administers", "advocates", "allocates", "anticipates",
		"articulates", "assimilates", "authenticates", "categorizes", "characterizes", "compensates",
		"conceptualizes", "corroborates", "cultivates", "decentralizes", "deciphers", "deliberates",
		"delineates", "differentiates", "disseminates", "diversifies", "elucidates", "emancipates",
		"emulates", "enumerates", "epitomizes", "extrapolates", "formulates", "generalizes",
		"generates", "hypothesizes", "improvises", "incorporates", "infers", "innovates",
		"integrates", "interpolates", "justifies", "legitimizes", "mediates", "mitigates",
		"mobilizes", "modifies", "orchestrates", "optimizes", "originates", "paraphrases",
		"perseveres", "prioritizes", "quantifies", "reconciles", "reconstructs", "refines",
		"rehabilitates", "reinforces", "reiterates", "relinquishes", "reorganizes", "replicates",
		"scrutinizes", "simulates", "synthesizes", "systematizes", "transforms", "validates",
		"visualizes", "amalgamates", "calibrates", "contextualizes",
	],
	"Adjective": [
		# Easy — 12 original + 65 new
		"cheerful", "careful", "noisy", "sleepy", "wooden", "helpful",
		"curious", "gentle", "hungry", "friendly", "brave", "tiny",
		"adorable", "adventurous", "afraid", "amused", "angry", "anxious",
		"beautiful", "bitter", "bumpy", "busy", "chilly", "clumsy",
		"colorful", "comfortable", "confident", "cozy", "crooked", "dangerous",
		"delighted", "delicious", "different", "dizzy", "dusty", "eager",
		"enormous", "excited", "famous", "fluffy", "forgetful", "fragile",
		"frightened", "grateful", "healthy", "honest", "itchy", "joyful",
		"juicy", "lazy", "lonely", "lovely", "lucky", "messy",
		"nervous", "peaceful", "playful", "polite", "proud", "puzzled",
		"reliable", "salty", "shiny", "silly", "slippery", "spicy",
		"spotless", "stubborn", "surprised", "thankful", "thirsty", "worried",
		"youthful", "zesty", "gloomy", "breezy", "creamy",
		# Normal — 65 new
		"abundant", "accurate", "adaptable", "affectionate", "ambitious", "ancient",
		"apparent", "appropriate", "attentive", "authentic", "beneficial", "brilliant",
		"cautious", "compassionate", "complex", "considerate", "consistent", "courageous",
		"creative", "delicate", "dependable", "determined", "diligent", "distinctive",
		"dramatic", "efficient", "elegant", "energetic", "enthusiastic", "essential",
		"exceptional", "familiar", "fascinating", "flexible", "generous", "harmonious",
		"imaginative", "independent", "inventive", "knowledgeable", "logical", "magnificent",
		"mysterious", "nutritious", "optimistic", "persistent", "practical", "productive",
		"remarkable", "resourceful", "responsible", "sensitive", "significant", "spacious",
		"spectacular", "sophisticated", "thoughtful", "trustworthy", "versatile", "vibrant",
		"vigorous", "accessible", "affordable", "agreeable", "analytical",
		# Hard — 70 new
		"abstruse", "altruistic", "ambiguous", "amiable", "anomalous", "arduous",
		"astute", "audacious", "austere", "benevolent", "capricious", "circumspect",
		"clandestine", "coherent", "conscientious", "conspicuous", "contemplative", "cryptic",
		"cursory", "deferential", "discerning", "eclectic", "eloquent", "empirical",
		"enigmatic", "ephemeral", "equitable", "erudite", "esoteric", "exuberant",
		"fastidious", "formidable", "fortuitous", "gregarious", "impartial", "impeccable",
		"indelible", "industrious", "ingenious", "inquisitive", "intangible", "intricate",
		"judicious", "labyrinthine", "meticulous", "methodical", "multifaceted", "nuanced",
		"obsolete", "omnipresent", "ostentatious", "paradoxical", "perceptive", "pragmatic",
		"profound", "prolific", "resilient", "scrupulous", "serene", "steadfast",
		"subtle", "tenacious", "tentative", "ubiquitous", "unequivocal", "unorthodox",
		"unwavering", "vigilant", "whimsical", "auspicious",
	],
	"Adverb": [
		"carefully", "quietly", "gently", "happily", "softly", "safely",
		"patiently", "bravely", "neatly", "politely", "slowly", "warmly",
		"quickly", "eagerly", "brightly", "boldly", "calmly", "clearly",
		"closely", "correctly", "deeply", "easily", "faithfully", "firmly",
		"gracefully", "honestly", "loudly", "merrily", "openly", "perfectly",
		"proudly", "rapidly", "regularly", "secretly", "seriously", "sharply",
		"silently", "smoothly", "suddenly", "sweetly", "tenderly", "thoughtfully",
		"truly", "wisely", "willingly", "wonderfully", "urgently", "usually",
	],
	"Pronoun": [
		"he", "she", "they", "we", "you", "it",
		"them", "us", "him", "ours", "theirs", "hers",
		"what", "me", "myself", "yourself", "yourselves", "himself",
		"herself", "itself", "ourselves", "themselves", "who", "whom",
		"whoever", "whomever", "someone", "anyone", "everyone", "nobody",
		"somebody", "anybody", "everybody", "nothing", "something", "anything",
		"everything", "oneself", "others", "whichever", "whatever",
	],
}

# Half-open indices into WORD_BANK. Adverb and Pronoun preserve all their
# original examples and use one shared pool across difficulties.
const TIER_RANGES := {
	"Noun": {"Easy": Vector2i(0, 78), "Normal": Vector2i(78, 143), "Hard": Vector2i(143, 213)},
	"Verb": {"Easy": Vector2i(0, 77), "Normal": Vector2i(77, 142), "Hard": Vector2i(142, 212)},
	"Adjective": {"Easy": Vector2i(0, 77), "Normal": Vector2i(77, 142), "Hard": Vector2i(142, 212)},
}

const PROMPTS := {
	"Noun": "Choose a noun: a word that names a person, place, animal, or thing.",
	"Verb": "Choose a verb: a word that shows an action or state.",
	"Adjective": "Choose an adjective: a word that describes a noun.",
	"Adverb": "Choose an adverb: a word that tells how an action happens.",
	"Pronoun": "Choose a pronoun: a word that can take the place of a noun.",
}

# excluded is a history set {word: true}; keys are compared without case or edge whitespace.
# Callers should remember all displayed words, including incorrect choices.
# Empty string indicates the requested eligible difficulty pool has been exhausted.
static func pick_word(topic: String, matching: bool, rng: RandomNumberGenerator, difficulty: String = "Easy", excluded: Dictionary = {}) -> String:
	var canonical_topic := _topic_or_noun(topic)
	var normalized_excluded := _normalized_exclusions(excluded)
	var candidates := _available_words(canonical_topic, matching, difficulty, normalized_excluded)
	if candidates.is_empty():
		return ""
	return candidates[rng.randi_range(0, candidates.size() - 1)]

# If three fresh options are unavailable, return an empty round rather than
# silently reusing a word; game code may then finish/skip gracefully.
static func lane_round(topic: String, difficulty: String, rng: RandomNumberGenerator, excluded: Dictionary = {}) -> Dictionary:
	var canonical_topic := _topic_or_noun(topic)
	var normalized_excluded := _normalized_exclusions(excluded)
	var matches := _available_words(canonical_topic, true, difficulty, normalized_excluded)
	var distractors := _available_words(canonical_topic, false, difficulty, normalized_excluded)
	var empty_options: Array[String] = []
	var empty_valid_indices: Array[int] = []
	var empty_round := {
		"prompt": String(PROMPTS[canonical_topic]),
		"options": empty_options,
		"valid_indices": empty_valid_indices,
		"topic": canonical_topic,
	}

	# A normal round uses 1-2 matching words and 1-2 distractors.
	var minimum_matches := maxi(1, 3 - distractors.size())
	var maximum_matches := mini(2, matches.size())
	if minimum_matches > maximum_matches:
		return empty_round
	var correct_count := clampi(_correct_count_for_difficulty(difficulty, rng), minimum_matches, maximum_matches)
	var entries: Array[Dictionary] = []
	for _index in range(correct_count):
		var selected_index := rng.randi_range(0, matches.size() - 1)
		entries.append({"word": matches.pop_at(selected_index), "valid": true})
	for _index in range(3 - correct_count):
		var selected_index := rng.randi_range(0, distractors.size() - 1)
		entries.append({"word": distractors.pop_at(selected_index), "valid": false})
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

static func _topic_or_noun(topic: String) -> String:
	var canonical_topic := _canonical_topic(topic)
	if canonical_topic.is_empty():
		push_warning("Unsupported grammar topic '%s'; using Noun." % topic)
		return "Noun"
	return canonical_topic

static func _canonical_topic(topic: String) -> String:
	var normalized := topic.strip_edges().to_lower()
	for candidate in TOPICS:
		if candidate.to_lower() == normalized:
			return candidate
	return ""

static func _canonical_difficulty(difficulty: String) -> String:
	match difficulty.strip_edges().to_lower():
		"hard": return "Hard"
		"normal", "medium": return "Normal"
		_: return "Easy"

static func _normalized_exclusions(excluded: Dictionary) -> Dictionary:
	var normalized := {}
	for word in excluded.keys():
		normalized[String(word).strip_edges().to_lower()] = true
	return normalized

static func _available_words(topic: String, matching: bool, difficulty: String, excluded: Dictionary) -> Array[String]:
	var available: Array[String] = []
	for bank_topic in TOPICS:
		if (bank_topic == topic) != matching:
			continue
		# For the three expanded topics, Normal/Hard distractors must also be
		# grade-matched; small legacy Pronoun/Adverb pools would make Hard easy.
		if not matching and TIER_RANGES.has(topic) and _canonical_difficulty(difficulty) != "Easy" and not TIER_RANGES.has(bank_topic):
			continue
		var words: Array = WORD_BANK[bank_topic]
		if TIER_RANGES.has(bank_topic):
			var window: Vector2i = TIER_RANGES[bank_topic][_canonical_difficulty(difficulty)]
			for index in range(window.x, window.y):
				var word: String = String(words[index])
				if not excluded.has(word.to_lower()):
					available.append(word)
		else:
			for word_value in words:
				var word: String = String(word_value)
				if not excluded.has(word.to_lower()):
					available.append(word)
	return available

static func _correct_count_for_difficulty(difficulty: String, rng: RandomNumberGenerator) -> int:
	match difficulty.strip_edges().to_lower():
		"hard":
			return 2 if rng.randf() < 0.50 else 1
		"normal", "medium":
			return 2 if rng.randf() < 0.20 else 1
		_:	# Easy and unknown difficulty values keep the round unambiguous.
			return 1

static func _shuffle_entries(entries: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	for index in range(entries.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temporary := entries[index]
		entries[index] = entries[swap_index]
		entries[swap_index] = temporary
