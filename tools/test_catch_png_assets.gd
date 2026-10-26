extends SceneTree

# STRICT PNG asset gate for the reverted original characters and generated HUD.
# Godot --headless --path . --script res://tools/test_catch_png_assets.gd
# Original WordCatcher body/basket + caught Apple.png MUST remain selected;
# the generated word_apple.png is ONLY for falling apples. Static state PNGs
# replace the three legacy dynamic red/black heart TextureRects.

const SCENE_PATH := "res://ui/minigames/catch_word.tscn"
const DIR := "res://Components/Gameplay/Catch the Word/HUD/generated/"
const PLAQUES := {
	"TitlePlaque": "title_board.png",
	"TimerPlaque": "timer_badge.png",
	"LivesPlaque": "lives_badge.png",
	"PausePlaque": "pause_badge.png",
	"ScorePlaque": "score_board.png",
}
const FALLING_APPLE := "res://Components/Gameplay/Catch the Word/Characters/Generated/word_apple.png"
const CAUGHT_APPLE := "res://Components/Gameplay/Catch the Word/Items/Apple.png"
const ORIGINAL_CHAR_DIR := "res://Components/Gameplay/Catch the Word/Characters/"
const HEART_STATES := {
	1: DIR + "replacement/lives_state_1.png",
	2: DIR + "replacement/lives_state_2.png",
	3: DIR + "replacement/lives_state_3.png",
}
const CHARACTERS := ["Boy", "Girl", "Grandma", "Grandpa"]
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const MODES := ["Seconds", "Lives"]
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const PNG_HEADER := [137, 80, 78, 71, 13, 10, 26, 10]

var failures: Array[String] = []
var checked := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var previous_size := root.size
	for file_name in PLAQUES.values():
		_check_image(DIR + String(file_name))
	_check_image(FALLING_APPLE)
	_check_image(CAUGHT_APPLE)
	for character_name in CHARACTERS:
		_check_image(ORIGINAL_CHAR_DIR + String(character_name).to_upper() + " BODY.png")
		_check_image(ORIGINAL_CHAR_DIR + String(character_name).to_upper() + " BASKET.png")
	for lives_count in [3, 2, 1]:
		_check_image(String(HEART_STATES[lives_count]))
	if not failures.is_empty():
		_finish(previous_size)
		return

	var packed := load(SCENE_PATH) as PackedScene
	_check(packed != null, "Catch Word scene can load with PNG assets")
	if packed == null:
		_finish(previous_size)
		return
	for viewport_size in VIEWPORTS:
		await _verify_viewport(packed, viewport_size)
	_finish(previous_size)


func _check_image(path: String) -> void:
	_check(FileAccess.file_exists(path), "generated PNG exists: " + path)
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	_check(file != null, "generated PNG can be opened: " + path)
	if file == null:
		return
	var data := file.get_buffer(file.get_length())
	file.close()
	_check(data.size() >= 64 and data.slice(0, 8) == PackedByteArray(PNG_HEADER),
		"genuine PNG bytes and nonempty data: " + path)
	if data.size() < 64:
		return
	var raster := Image.new()
	var error := raster.load_png_from_buffer(data)
	_check(error == OK and raster.get_width() >= 100 and raster.get_height() >= 50,
		"generated PNG decodes at useful resolution: " + path)
	_check(ResourceLoader.exists(path), "Godot imports the PNG: " + path)


func _verify_viewport(packed: PackedScene, viewport_size: Vector2i) -> void:
	root.size = viewport_size
	await process_frame
	await process_frame
	var initial_children := root.get_child_count()
	var host := Control.new()
	host.size = Vector2(viewport_size)
	root.add_child(host)
	var game := packed.instantiate() as Control
	if game == null or game.get_script() == null:
		_fail("%s: PNG scene failed to instantiate with gameplay script" % viewport_size)
		host.queue_free()
		await process_frame
		return
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	game.set_process(false)

	var hud := game.get_node_or_null("HUDLayer/HUD") as Control
	_check(hud != null, "%s: HUD is a Control" % viewport_size)
	_check(bool(game.get("using_reference_pngs")),
		"%s: runtime reports generated bitmap HUD enabled" % viewport_size)
	if hud != null:
		for absent_name in ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]:
			_check(not hud.has_node(absent_name),
				"%s: removed %s is absent from the HUD" % [viewport_size, absent_name])
		for plaque_name in PLAQUES:
			var plaque := game.get_node_or_null("ScoreDrawLayer/ScorePlaque") as TextureRect if plaque_name == "ScorePlaque" else hud.get_node_or_null(String(plaque_name)) as TextureRect
			_check(plaque != null, "%s: distinct %s node exists" % [viewport_size, plaque_name])
			if plaque == null:
				continue
			var expected: String = String(HEART_STATES[3]) if plaque_name == "LivesPlaque" else DIR + String(PLAQUES[plaque_name])
			var actual := plaque.texture.resource_path if plaque.texture != null else ""
			_check(actual == expected,
				"%s: %s uses exact generated PNG, got %s" % [viewport_size, plaque_name, actual])
			_check(plaque.texture != null and plaque.texture.get_width() >= 100,
				"%s: %s has decoded raster texture" % [viewport_size, plaque_name])

		var numeric := game.get_node_or_null("ScoreDrawLayer/ScoreBottomContainer/ScoreNumber") as Label
		var visible_score_titles := 0
		var score_container := game.get_node_or_null("ScoreDrawLayer/ScoreBottomContainer")
		if score_container != null:
			for child in score_container.get_children():
				if child is Label and (child as Label).text.strip_edges().to_upper() == "SCORE":
					if (child as Label).is_visible_in_tree():
						visible_score_titles += 1
		for baked_name in ["TitleLabel", "TitleTheLabel", "TitleWordLabel", "ScoreLabel"]:
			var baked := hud.get_node_or_null(baked_name) as Label
			_check(baked == null or not baked.is_visible_in_tree(),
				"%s: %s cannot duplicate text baked into PNG" % [viewport_size, baked_name])
		_check(visible_score_titles == 0,
			"%s: old SCORE heading is absent or hidden under baked bitmap" % viewport_size)
		_check(numeric != null and numeric.is_visible_in_tree(),
			"%s: dynamic numeric score is visible" % viewport_size)
		var pause := hud.get_node_or_null("PauseButton") as Button
		_check(pause != null and pause.icon == null,
			"%s: no vector pause icon covers the PNG pause badge" % viewport_size)

		for topic in TOPICS:
			for mode in MODES:
				game.call("set_context", {
					"topic": topic,
					"game_mode": mode,
					"difficulty": "Normal",
					"catch_character": "Girl",
					"catch_map": "Forest",
					"score": 94,
					"lives": 2,
					"time_remaining": 29.0,
				})
				game.set_process(false)
				await process_frame
				var context := "%s %s %s" % [viewport_size, topic, mode]
				var topic_label := hud.get_node_or_null("PromptLabel") as Label
				var clock := hud.get_node_or_null("TimeLabel") as Label
				var hearts := hud.get_node_or_null("HeartsBox") as Control
				var time_plaque := hud.get_node_or_null("TimerPlaque") as TextureRect
				var life_plaque := hud.get_node_or_null("LivesPlaque") as TextureRect
				var article := "AN" if topic in ["Adjective", "Adverb"] else "A"
				_check(topic_label != null and topic_label.text == "WHICH WORD IS %s %s?" % [article, topic.to_upper()],
					context + ": exact grammar prompt")
				for absent_name in ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]:
					_check(not hud.has_node(absent_name),
						context + ": removed " + absent_name + " stays absent after context switch")
				if topic_label != null:
					_check_prompt_legibility(topic_label, hud.get_node_or_null("TitlePlaque") as Control, context)
				_check(numeric != null and numeric.text == "94",
					context + ": dynamic numeric score is updated")
				_check(clock != null and clock.is_visible_in_tree() == (mode == "Seconds"),
					context + ": timer visibility matches game mode")
				_check(hearts == null or not hearts.is_visible_in_tree(),
					context + ": legacy individual heart controls stay hidden in both modes")
				_check(time_plaque != null and time_plaque.is_visible_in_tree() == (mode == "Seconds"),
					context + ": timer PNG visibility matches mode")
				_check(life_plaque != null and life_plaque.is_visible_in_tree() == (mode == "Lives"),
					context + ": lives PNG visibility matches mode")
				if mode == "Lives":
					_check_static_heart_states(game, hearts, life_plaque, clock, time_plaque, context)
				for plaque_name in PLAQUES:
					var plaque := game.get_node_or_null("ScoreDrawLayer/ScorePlaque") as TextureRect if plaque_name == "ScorePlaque" else hud.get_node_or_null(String(plaque_name)) as TextureRect
					if plaque != null and plaque.is_visible_in_tree():
						var rect := plaque.get_global_rect()
						_check(rect.has_area() and Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(rect),
							"%s: %s stays within visible HUD bounds" % [context, plaque_name])

	# Character textures must be the ORIGINAL WordCatcherCharacters sprites,
	# even if obsolete generated character PNGs still exist on disk.
	for character_name in CHARACTERS:
		game.call("set_context", {
			"topic": "Noun",
			"game_mode": "Lives",
			"difficulty": "Normal",
			"catch_character": character_name,
			"catch_map": "City",
			"catch_collected_words": ["apple", "river", "friend"],
		})
		game.set_process(false)
		await process_frame
		await process_frame
		var ctx := "%s %s" % [viewport_size, character_name]
		var body := game.body_sprite as Sprite2D
		var basket := game.basket_sprite as Sprite2D
		var collected := game.get_node_or_null("CollectedWords") as Node2D
		var group := game.get_node_or_null(character_name) as Node2D
		var prefix: String = String(character_name).to_upper()
		_check(String(game.get("selected_character")) == character_name,
			ctx + ": requested character selected")
		_check(body != null and body.texture != null
			and body.texture.resource_path == ORIGINAL_CHAR_DIR + prefix + " BODY.png",
			ctx + ": ORIGINAL WordCatcher body selected in runtime")
		_check(basket != null and basket.texture != null
			and basket.texture.resource_path == ORIGINAL_CHAR_DIR + prefix + " BASKET.png",
			ctx + ": ORIGINAL WordCatcher basket selected in runtime")
		var apple_texture: Texture2D = game.get("gameplay_apple_texture") as Texture2D
		_check(apple_texture != null and apple_texture.resource_path == FALLING_APPLE,
			ctx + ": falling word apple uses generated glossy PNG")
		var spawned := game.call("_create_tile_node", "TEST", Color.WHITE) as Control
		_check(spawned != null, ctx + ": falling word tile can be created")
		if spawned != null:
			var falling_sprite := spawned.get_node_or_null("AppleSprite") as TextureRect
			_check(falling_sprite != null and falling_sprite.texture == apple_texture,
				ctx + ": falling word AppleSprite uses glossy PNG")
			spawned.queue_free()
		if body != null and basket != null and collected != null:
			var sprite_group := body.get_parent()
			_check(sprite_group == basket.get_parent()
				and sprite_group == group and collected.get_parent() == game,
				ctx + ": active body/basket are editor-authored children of selected root sibling")
			_check(body.is_visible_in_tree() and basket.is_visible_in_tree(),
				ctx + ": selected character body and basket are visible")
			_check(body.z_index + group.z_index < collected.z_index and collected.z_index < basket.z_index + group.z_index,
				ctx + ": body < collected apples < basket/hands draw order")
			var screen := Rect2(Vector2.ZERO, Vector2(viewport_size))
			for sprite in [body, basket]:
				var visual_rect := _sprite_visual_rect(sprite)
				_check(visual_rect.has_area() and screen.encloses(visual_rect.grow(-0.5)),
					"%s: active %s is fully inside %s (actual %s)" %
					[ctx, sprite.name, viewport_size, visual_rect])
			# The original cropped body/basket art must retain comparable
			# displayed widths, even though their source crop sizes differ.
			var body_width := body.region_rect.size.x * absf(body.get_global_transform().get_scale().x)
			var basket_width := basket.region_rect.size.x * absf(basket.get_global_transform().get_scale().x)
			_check(body_width > 1.0 and basket_width > 1.0
				and basket_width / body_width > 0.75
				and basket_width / body_width < 1.65,
				"%s: body/basket have comparable displayed width (%.1f vs %.1f)" %
				[ctx, body_width, basket_width])
			_check(collected.get_child_count() == 3,
				ctx + ": exactly three caught word apples are displayed")
			for child in collected.get_children():
				if child is TextureRect:
					var caught := child as TextureRect
					_check(caught.texture != null and caught.texture.resource_path == CAUGHT_APPLE,
						ctx + ": collected apple retains original Components/Gameplay/Catch the Word/Items/Apple.png")
					_check(caught.get_child_count() > 0 and caught.get_child(0) is Label,
						ctx + ": caught apple has editable word label")

	host.queue_free()
	await process_frame
	await process_frame
	_check(root.get_child_count() == initial_children, "%s: scene cleans up" % viewport_size)


func _sprite_visual_rect(sprite: Sprite2D) -> Rect2:
	# Region, offset, scale and the editor-authored parent group all contribute
	# to the actual screen bounds; the 1920x1080 character rig also scales.
	var local_rect := sprite.get_rect()
	var transform := sprite.get_global_transform()
	var min_corner := transform * local_rect.position
	var max_corner := min_corner
	for corner in [
		Vector2(local_rect.end.x, local_rect.position.y),
		local_rect.end,
		Vector2(local_rect.position.x, local_rect.end.y)
	]:
		var point: Vector2 = transform * corner
		min_corner = min_corner.min(point)
		max_corner = max_corner.max(point)
	return Rect2(min_corner, max_corner - min_corner)


func _check_prompt_legibility(label: Label, title_board: Control, context: String) -> void:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var text_size := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var line_height := font.get_height(font_size)
	_check(label.is_visible_in_tree(), context + ": grammar question visible")
	_check(label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
		and label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER,
		context + ": grammar question centered both horizontally and vertically")
	_check(label.autowrap_mode == TextServer.AUTOWRAP_OFF,
		context + ": question renders on one line without unplanned wrap")
	_check(text_size.x <= label.size.x + 2.0 and line_height <= label.size.y + 2.0,
		"%s: question fits label without clipping (text %s, available %s, font %d)" %
		[context, text_size, label.size, font_size])
	_check(label.size.x >= 1.0 and label.size.y >= 1.0,
		context + ": question label has nonzero dimensions")
	if title_board != null:
		var question := label.get_global_rect()
		var panel := title_board.get_global_rect()
		_check(panel.encloses(question.grow(-1.0)),
			context + ": grammar question stays within title board")
		_check(absf(question.get_center().x - panel.get_center().x) <= panel.size.x * 0.07,
			context + ": question centered over title board")


func _check_static_heart_states(game: Control, legacy_hearts: Control,
		plaque: TextureRect, clock: Label, timer_plaque: TextureRect, context: String) -> void:
	_check(plaque != null and plaque.is_visible_in_tree(),
		context + ": static lives panel visible in Lives mode")
	for amount in [3, 2, 1]:
		game.set("lives", amount)
		game.call("_refresh_hud")
		var actual := plaque.texture.resource_path if plaque != null and plaque.texture != null else ""
		_check(actual == String(HEART_STATES[amount]),
			"%s: lives=%d selects exact supplied static PNG (got %s)" % [context, amount, actual])
		_check(legacy_hearts == null or not legacy_hearts.is_visible_in_tree(),
			"%s: lives=%d contains no overlaid individual heart icons" % [context, amount])
		_check(plaque != null and plaque.is_visible_in_tree()
			and not clock.is_visible_in_tree() and not timer_plaque.is_visible_in_tree(),
			"%s: lives=%d panel replaces timer without duplicate mode UI" % [context, amount])
		if plaque != null:
			var rect := plaque.get_global_rect()
			_check(rect.has_area() and game.get_viewport_rect().has_point(rect.position)
				and game.get_viewport_rect().encloses(rect.grow(-0.5)),
				"%s: lives=%d static panel stays within visible viewport" % [context, amount])
	game.set("lives", 2)
	game.call("_refresh_hud")


func _check(condition: bool, message: String) -> void:
	checked += 1
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)


func _finish(previous_size: Vector2i) -> void:
	root.size = previous_size
	if failures.is_empty():
		print("PASS  Catch reverted PNG HUD: %d checks, original 4 characters, 3 static lives states, 30 topic/mode/viewport states" % checked)
		quit(0)
	else:
		for message in failures:
			push_error("PNG HUD QA: " + message)
		print("FAIL  Generated Catch HUD PNGs: %d failures in %d checks" % [failures.size(), checked])
		quit(1)
