extends SceneTree

# Focused actual-scene Balloon HUD regression, independent of physical camera.
# Godot --headless --path . --script res://tools/test_balloon_banner_only_20261029.gd

const SCENE: PackedScene = preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const BANK = preload("res://ui/minigames/shared/grammar_bank.gd")
const TOPICS := ["Noun", "Verb", "Adjective", "Adverb", "Pronoun"]
const PLURALS := ["NOUNS", "VERBS", "ADJECTIVES", "ADVERBS", "PRONOUNS"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]

var checks := 0
var cases := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Inspect the actual saved PackedScene before any gameplay script runs.
	var authored := SCENE.instantiate() as Control
	_check(authored != null, "Balloon scene can be instantiated")
	if authored == null:
		_finish()
		return
	_check(authored.has_node("HudLayer/ObjectivePanel"), "wood title remains editor authored")
	_check(authored.has_node("HudLayer/BannerTagline"), "tagline remains editor authored")
	_check(not authored.has_node("HudLayer/PromptLabel") and not authored.has_node("HudLayer/PromptPanel"),
		"obsolete prompt label and panel are absent from the saved scene")
	authored.free()

	for resolution in SIZES:
		var host := Control.new()
		host.name = "BalloonBannerViewport"
		host.size = Vector2(resolution)
		root.add_child(host)
		var game := SCENE.instantiate() as Control
		host.add_child(game)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		game._layout_scene()
		game.set_process(false)
		game.set_physics_process(false)
		_check(game.size.is_equal_approx(Vector2(resolution)),
			"Mounted Balloon game uses actual logical viewport " + str(resolution))
		for mode in MODES:
			for difficulty in DIFFICULTIES:
				for index in range(TOPICS.size()):
					var topic: String = TOPICS[index]
					game.set_context({"topic": topic, "difficulty": difficulty, "game_mode": mode})
					game.set_process(false)
					game.set_physics_process(false)
					_verify(game, mode, difficulty, topic, PLURALS[index], resolution)
					if difficulty == "Normal":
						game._start_new_round()
						game._start_new_round()
						_verify(game, mode, difficulty, topic, PLURALS[index], resolution)
						game._start_new_round()
						_verify(game, mode, difficulty, topic, PLURALS[index], resolution)
		host.queue_free()
		await process_frame
	for i in range(3):
		await process_frame
	await create_timer(0.7).timeout
	_finish()


func _verify(game: Control, mode: String, difficulty: String, topic: String,
		plural: String, resolution: Vector2i) -> void:
	cases += 1
	var tag := "%s/%s/%s/%s/r%d" % [resolution, mode, difficulty, topic, game.round_index]
	var hud := game.get_node("HudLayer") as Control
	var objective := hud.get_node("ObjectivePanel") as TextureRect
	var tagline := hud.get_node("BannerTagline") as Label
	var negative: bool = difficulty == "Hard" or (difficulty == "Normal" and game.round_index % 3 == 0)
	var expected := ("POP NOT %s!" if negative else "POP %s!") % plural
	_check(tagline.text == expected, tag + ": visible rule correctly says " + expected)
	_check(tagline.visible and objective.visible and objective.texture != null
		and objective.get_global_rect().encloses(tagline.get_global_rect()),
		tag + ": dynamic instruction lies within original wooden title")
	var font_size := tagline.get_theme_font_size("font_size")
	_check(font_size >= 11 and game.FONT.get_string_size(
		tagline.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x <= tagline.size.x - 4.0,
		tag + ": full topic instruction fits banner at readable font size")
	_check(not hud.has_node("PromptLabel") and not hud.has_node("PromptPanel")
		and hud.get_node_or_null("CarnivalPrompt") == null,
		tag + ": removed prompt remains absent after runtime setup")
	_check(game.round_active and not game.finishing and game.balloon_slots.size() == 3
		and game.valid_lanes.size() > 0 and game.valid_lanes.size() < 3,
		tag + ": game still has a valid playable three-balloon question")
	var matches: Array[String] = BANK._available_words(topic, true, difficulty, {})
	for lane in range(game.balloon_slots.size()):
		var balloon: Area2D = game.balloon_slots[lane]
		var word := String((balloon.get_node("WordLabel") as Label).text)
		var is_match := matches.has(word)
		_check(game.valid_lanes.has(lane) == (not is_match if negative else is_match),
			tag + ": balloon lane %d matches displayed positive/negative rule" % lane)
	_check(game.score == 0 and game.hearts == (3 if mode == "Lives" else 0)
		and game.time_remaining == (0.0 if mode == "Lives" else 60.0),
		tag + ": time/lives/score unaffected by prompt cleanup")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("PASS Balloon banner-only UI: %d checks / %d runtime cases" % [checks, cases])
		quit(0)
	else:
		for failure in failures.slice(0, 24):
			push_error("BALLOON BANNER QA: " + failure)
		print("FAIL Balloon banner-only UI: %d failures / %d checks / %d cases" %
			[failures.size(), checks, cases])
		quit(1)
