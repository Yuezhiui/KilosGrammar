extends SceneTree

# Classroom readability regression. Real Catch scene and dynamically spawned
# apples, no webcam, Python backend, PostgreSQL or physical player input.
# Godot --headless --path . --script res://tools/test_catch_classroom_readability_20261102.gd
const GAME := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const ANIMALS := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const SPEEDS := {"Easy": 96.0, "Normal": 102.0, "Hard": 109.0}
const CAPS := {"Easy": 1.12, "Normal": 1.13, "Hard": 1.14}
const MODES := ["Seconds", "Lives"]
const DESIGN := Vector2(1280, 720)

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for difficulty in SPEEDS.keys():
		for mode in MODES:
			for animal in ANIMALS:
				await _case(difficulty, mode, animal)
	for issue in failures.slice(0, 30):
		printerr("CATCH CLASSROOM QA: ", issue)
	print("CATCH CLASSROOM READABILITY 20261102: %s %d checks, %d failures" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _case(difficulty: String, mode: String, animal: String) -> void:
	var tag := "%s/%s/%s" % [difficulty, mode, animal]
	var holder := Control.new()
	holder.size = DESIGN
	root.add_child(holder)
	var game := GAME.instantiate() as Control
	holder.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	game.set_process(false)
	var fixed_positions: Dictionary = {}
	for candidate in ANIMALS:
		fixed_positions[candidate] = {
			"body": (game.get_node(candidate + "/Body") as Sprite2D).position,
			"basket": (game.get_node(candidate + "/Basket") as Sprite2D).position
		}
	game.set_context({
		"topic": TOPICS[(ANIMALS.find(animal) + SPEEDS.keys().find(difficulty)) % TOPICS.size()],
		"difficulty": difficulty,
		"game_mode": mode,
		"catch_character": animal,
		"catch_map": "City"
	})
	game.set_process(false)
	_check(game.APPLE_SIZE.x >= 155.0 and game.APPLE_SIZE.y >= 160.0,
		tag + " bigger Inspector-authored falling apples")
	_check(game.falling_word_font_size >= 24,
		tag + " bigger Inspector-authored text")
	_check(game.lives == 3 and game.LIVES_ROUND_HEARTS == 3,
		tag + " three hearts retained")
	_check((game.time_remaining == 60.0 and game.is_seconds_mode) if mode == "Seconds"
		else (game.time_remaining == 0.0 and game.is_lives_mode),
		tag + " 60s and Lives mode behavior retained")
	_check(is_equal_approx(game.base_fall_speed, SPEEDS[difficulty]),
		tag + " slow tier start speed")
	_check(game.falling_tiles.size() == 3 and game.wave_phase == "falling",
		tag + " one correct + two distractors falling immediately")
	if game.falling_tiles.size() == 3:
		var columns: Array[float] = []
		for tile in game.falling_tiles:
			columns.append(Vector2(tile["pos"]).x)
			_check(absf(float(tile["speed"]) - SPEEDS[difficulty]) < 0.01,
				tag + " synced initial speed")
			var node := tile["node"] as Control
			var sprite := node.get_node("AppleSprite") as TextureRect
			var word := node.get_node("WordLabel") as Label
			_check(sprite.size == game.APPLE_SIZE and node.size == game.APPLE_SIZE,
				tag + " actual apple artwork larger, not just collision")
			_check(word.size.x >= game.APPLE_SIZE.x - 1 and
				word.get_theme_font_size("font_size") >= 20 and
				word.get_theme_font_size("font_size") <= game.falling_word_font_size,
				tag + " word renders using fitting, larger font")
			_check(word.text == String(tile["word"]).to_upper(),
				tag + " grammar vocabulary unchanged")
			_check(word.get_theme_constant("outline_size") >= 5,
				tag + " text has clear high-contrast outline")
		columns.sort()
		_check(columns[1] - columns[0] > game.APPLE_SIZE.x + 35.0
			and columns[2] - columns[1] > game.APPLE_SIZE.x + 35.0,
			tag + " bigger apples do not overlap")
		_check(columns[1] - columns[0] >= game.APPLE_SIZE.x +
			game._basket_rect().size.x + game.APPLE_SPACING_MARGIN,
			tag + " neighboring choices cannot both hit the basket")
		_check(columns[2] + game.APPLE_SIZE.x / 2.0 + 8.0 <= game.score_plaque.position.x,
			tag + " right apple does not cover score plaque")
		var before_y: float = game.falling_tiles[0]["pos"].y
		game._update_tiles(0.5)
		_check(absf(float(game.falling_tiles[0]["pos"].y) - before_y -
			SPEEDS[difficulty] * 0.5) < 0.15,
			tag + " falling movement uses slower speed")
	# Very long approved vocabulary, including Hard grammar words, must be
	# wrapped at legible size without changing or truncating the answer text.
	var long_node: Control = game._create_tile_node("MICROORGANISM", Color.WHITE)
	var long_word := long_node.get_node("WordLabel") as Label
	_check(long_word.text == "MICROORGANISM" and
		long_word.get_theme_font_size("font_size") >= 20 and
		long_word.autowrap_mode == TextServer.AUTOWRAP_ARBITRARY,
		tag + " hard vocabulary wraps legibly rather than shrinking")
	long_node.queue_free()
	game.correct_count = 10
	var progressed: float = game._correct_answer_wave_speed()
	_check(progressed > game.base_fall_speed and
		progressed <= game.base_fall_speed * CAPS[difficulty] + 0.001,
		tag + " mild, bounded correct-answer speed progression")
	game.correct_count = 0
	for candidate in ANIMALS:
		_check((game.get_node(candidate + "/Body") as Sprite2D).position ==
			fixed_positions[candidate]["body"] and
			(game.get_node(candidate + "/Basket") as Sprite2D).position ==
			fixed_positions[candidate]["basket"],
			tag + " original cropped animal artwork untouched: " + candidate)
	_check(is_instance_valid(game.tutorial_layer) and
		is_instance_valid(game.tutorial_narration) and
		game.CATCH_TUTORIAL_STEPS.size() == 6,
		tag + " tutorial and voice remain authored")
	game._stop_voice_feedback()
	game._clear_falling_tiles()
	holder.queue_free()
	await process_frame


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
