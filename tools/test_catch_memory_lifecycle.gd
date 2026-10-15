extends SceneTree

const SCENE := preload("res://ui/minigames/catch_word.tscn")
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const CHARACTERS := ["Boy", "Girl", "Grandma", "Grandpa"]
var failures: Array[String] = []
var checked := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for character in CHARACTERS:
		for topic in TOPICS:
			for difficulty in ["Easy", "Normal", "Hard"]:
				for mode in ["Seconds", "Lives"]:
					await _case(character, topic, difficulty, mode)
	if failures.is_empty():
		print("PASS lifecycle %d combinations: catches, restart, pause, bounded children" % checked)
		quit(0)
	else:
		for failure in failures.slice(0, 45):
			push_error(failure)
		print("FAIL lifecycle: %d failures across %d combinations" % [failures.size(), checked])
		quit(1)

func _case(character: String, topic: String, difficulty: String, mode: String) -> void:
	var label := "%s/%s/%s/%s" % [character, topic, difficulty, mode]
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var game := SCENE.instantiate() as Control
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	game.set_process(false)
	var ctx := {"topic": topic, "difficulty": difficulty, "game_mode": mode, "catch_character": character}
	game.set_context(ctx)
	await process_frame
	game.set_process(false)
	checked += 1
	if game.selected_character != character or game.topic != topic or game.game_mode != mode:
		failures.append(label + " context mismatch")
	_assert_wave(game, label + " initial")
	var baseline := game.get_child_count()
	for retry in range(3):
		game._clear_falling_tiles()
		await process_frame
		for n in range(8):
			game._handle_catch({"word": "TEST", "matching": true})
			if game.collected_words.size() > 3 or game.collected_word_layer.get_child_count() > 3:
				failures.append(label + " basket exceeds three items")
		if game.correct_count != 8 or game.attempts != 8:
			failures.append(label + " catch counters mismatch")
		game._pause()
		var score_before: int = game.score
		var tiles_before: Array = game.falling_tiles.duplicate(true)
		game._process(0.4)
		if game.score != score_before or game.falling_tiles != tiles_before:
			failures.append(label + " pause changed score/tiles")
		game._resume()
		if not game.round_running:
			failures.append(label + " resume failed")
		game.set_context(ctx)
		await process_frame
		game.set_process(false)
		_assert_wave(game, label + " retry %d" % retry)
		if game.score != 0 or game.attempts != 0 or game.correct_count != 0 or not game.collected_words.is_empty():
			failures.append(label + " retry retained score/attempts/collected")
		if game.collected_word_layer.get_child_count() != 0:
			failures.append(label + " retry retained basket children")
		if game.falling_word_layer.get_child_count() != game.falling_tiles.size():
			failures.append(label + " retry retained stale wave sprites")
		# set_context() must immediately dispose any old transient effects.
		for child in game.get_children():
			if child.is_in_group("catch_transient_effect") and not child.is_queued_for_deletion():
				failures.append(label + " retry retained active transient effect")
	# Verify natural tween cleanup in both game modes, without delaying all
	# 120 configurations for an identical timer implementation.
	if character == "Boy" and topic == "Noun" and difficulty == "Easy":
		game._handle_catch({"word": "TEST", "matching": true})
		await create_timer(1.35).timeout
	await process_frame
	if game.get_child_count() > baseline + 2:
		failures.append(label + " transient effect nodes leaked: %d baseline %d" % [game.get_child_count(), baseline])
	host.queue_free()
	await process_frame


func _assert_wave(game: Control, label: String) -> void:
	var tiles: Array = game.falling_tiles
	if tiles.size() != 3:
		failures.append("%s: expected 3 synchronized apple choices, got %d" % [label, tiles.size()])
		return
	if game.wave_phase != "reading":
		failures.append(label + " new wave is not in the reading phase")
	var matching := 0
	var lanes: Dictionary = {}
	var words: Dictionary = {}
	var start_y := Vector2(tiles[0]["pos"]).y
	var speed := float(tiles[0]["speed"])
	for tile in tiles:
		if bool(tile["matching"]):
			matching += 1
		var lane := int(tile.get("lane", -1))
		if lane not in [0, 1, 2] or lanes.has(lane):
			failures.append(label + " duplicate/invalid wave lane")
		lanes[lane] = true
		var word := String(tile.get("word", "")).to_lower()
		if word.is_empty() or words.has(word):
			failures.append(label + " duplicate/empty word")
		words[word] = true
		if absf(Vector2(tile["pos"]).y - start_y) > 1.0 or absf(float(tile["speed"]) - speed) > 0.01:
			failures.append(label + " wave apples are not synchronized")
	if matching != 1:
		failures.append(label + " wave must have exactly one correct choice")
