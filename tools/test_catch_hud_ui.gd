extends SceneTree

# Headless regression for Catch the Word's generated PNG HUD.
# Godot 4.7.2: --headless --path . --script res://tools/test_catch_hud_ui.gd
# Covers all topics, modes, viewports, characters and map choices.

const SCENE_PATH := "res://ui/minigames/catch_word.tscn"
const GENERATED_HUD_DIR := "res://ui/minigames/catch_hud/generated/"
const REFERENCE_PNG_READY := "res://ui/minigames/catch_hud/generated/title_board.png"
const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
const TOPICS: Array[String] = ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const MODES: Array[String] = ["Seconds", "Lives"]
const PLAQUE_NAMES: Array[String] = [
	"TitlePlaque", "TimerPlaque",
	"LivesPlaque", "PausePlaque", "ScorePlaque",
]
const GENERATED_PLAQUES := {
	"TitlePlaque": "title_board.png",
	"TimerPlaque": "timer_badge.png",
	"LivesPlaque": "lives_badge.png",
	"PausePlaque": "pause_badge.png",
	"ScorePlaque": "score_board.png",
}
const STATIC_LIVES := {
	1: GENERATED_HUD_DIR + "replacement/lives_state_1.png",
	2: GENERATED_HUD_DIR + "replacement/lives_state_2.png",
	3: GENERATED_HUD_DIR + "replacement/lives_state_3.png",
}
const FALLING_APPLE := GENERATED_HUD_DIR + "character/word_apple.png"
const CAUGHT_APPLE := "res://Components/Apple.png"
const CHARACTERS: Array[String] = ["Boy", "Girl", "Grandma", "Grandpa"]
const MAPS: Array[String] = ["City", "Forest", "Mountain"]

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_size := root.size
	if not ResourceLoader.exists(SCENE_PATH):
		_fail("Catch the Word scene is missing")
		_finish(original_size)
		return
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Catch the Word scene is not a PackedScene")
		_finish(original_size)
		return

	_test_serialized_png_resources()
	for viewport_size in SIZES:
		await _test_viewport(packed, viewport_size)

	_finish(original_size)


func _test_viewport(packed: PackedScene, viewport_size: Vector2i) -> void:
	root.size = viewport_size
	await process_frame
	await process_frame
	var original_children := root.get_child_count()
	# In the app a minigame is mounted under the Gameplay Control wrapper;
	# a Control directly parented to the root Viewport does not stretch.
	var host := Control.new()
	host.name = "CatchHUDTestHost"
	host.size = Vector2(viewport_size)
	root.add_child(host)
	var game := packed.instantiate() as Control
	if game == null:
		_fail("%s: scene cannot instantiate as Control" % viewport_size)
		host.queue_free()
		return
	if game.get_script() == null:
		_fail("%s: Catch gameplay script failed to load" % viewport_size)
		host.queue_free()
		return

	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	game.set_process(false)

	var hud := game.get_node_or_null("HUDLayer/HUD") as Control
	_check(hud != null, "%s: HUD is a separate Control in a CanvasLayer" % viewport_size)
	_check(game.get_node_or_null("HUDLayer") is CanvasLayer, "%s: HUD is on its own CanvasLayer" % viewport_size)
	_check(game.get_node_or_null("Background") is TextureRect, "%s: background remains editable" % viewport_size)
	var character := game.get_node_or_null("CharacterRig") as Node2D
	var body := game.get_node_or_null("CharacterRig/Body") as Sprite2D
	var apples := game.get_node_or_null("CharacterRig/CollectedWords") as Node2D
	var basket := game.get_node_or_null("CharacterRig/Basket") as Sprite2D
	_check(character != null, "%s: separate CharacterRig exists" % viewport_size)
	_check(body != null and apples != null and basket != null, "%s: Body, CollectedWords, Basket are distinct scene nodes" % viewport_size)
	if body != null and apples != null and basket != null:
		_check(body != basket and body.get_parent() == character and apples.get_parent() == character and basket.get_parent() == character,
			"%s: Body, collected apples and Basket are independently editable siblings" % viewport_size)
		_check(body.texture != null and basket.texture != null, "%s: Body and Basket have their own sprite textures" % viewport_size)

	var plaques: Dictionary = {}
	var actual_reference_installed := _generated_pack_available()
	_check(bool(game.get("using_reference_pngs")) == actual_reference_installed,
		"%s: game switches to generated PNGs precisely when the full five-image pack is available" % viewport_size)
	for removed_name in ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]:
		_check(game.get_node_or_null("HUDLayer/HUD/" + removed_name) == null,
			"%s: removed %s has no HUD node" % [viewport_size, removed_name])
	var plaque_textures: Dictionary = {}
	for name in PLAQUE_NAMES:
		var node := game.get_node_or_null("ScoreDrawLayer/ScorePlaque") if name == "ScorePlaque" else game.get_node_or_null("HUDLayer/HUD/" + name)
		var plaque := node as TextureRect
		_check(plaque != null, "%s: runtime has %s TextureRect" % [viewport_size, name])
		if plaque != null:
			plaques[name] = plaque
			_check(plaque.texture != null, "%s: %s has an independent texture" % [viewport_size, name])
			_check(plaque.get_parent() == (game.score_draw_layer if name == "ScorePlaque" else hud),
				"%s: %s has the intended runtime parent" % [viewport_size, name])
			if plaque.texture != null:
				var path := plaque.texture.resource_path
				if actual_reference_installed:
					_assert_generated_png(path, "%s %s plaque" % [viewport_size, name])
					var expected_png: String = String(STATIC_LIVES[3]) if name == "LivesPlaque" else GENERATED_HUD_DIR + String(GENERATED_PLAQUES[name])
					_check(path == expected_png,
						"%s: %s uses the expected generated art file (got %s)" % [viewport_size, name, path])
					_check(plaque.stretch_mode == TextureRect.STRETCH_SCALE,
						"%s: %s scales the generated bitmap with its layout" % [viewport_size, name])
				else:
					_check(path.begins_with("res://ui/minigames/catch_hud/") and path.ends_with(".svg"),
						"%s: %s uses the temporary SVG fallback pending PNG pack (got %s)" % [viewport_size, name, path])
				_check(not plaque_textures.has(path), "%s: %s has its own HUD image" % [viewport_size, name])
				plaque_textures[path] = true

	var title := game.get_node_or_null("HUDLayer/HUD/TitleLabel") as Label
	var title_the := game.get_node_or_null("HUDLayer/HUD/TitleTheLabel") as Label
	var title_word := game.get_node_or_null("HUDLayer/HUD/TitleWordLabel") as Label
	var prompt := game.get_node_or_null("HUDLayer/HUD/PromptLabel") as Label
	var score := game.get_node_or_null("ScoreDrawLayer/ScoreBottomContainer/ScoreNumber") as Label
	var timer := game.get_node_or_null("HUDLayer/HUD/TimeLabel") as Label
	var hearts := game.get_node_or_null("HUDLayer/HUD/HeartsBox") as HBoxContainer
	var pause_button := game.get_node_or_null("HUDLayer/HUD/PauseButton") as Button

	# CATCH THE WORD and SCORE are already painted into the generated PNGs.
	# Old runtime title/score-title labels must not paint over those bitmap words.
	if hud != null:
		if actual_reference_installed:
			_check(_baked_labels_not_rendered(hud),
				"%s: no duplicate visible CATCH/THE/WORD/SCORE title text over PNG art" % viewport_size)
			_check(pause_button != null and pause_button.icon == null,
				"%s: generated pause bitmap has no duplicate vector pause symbol" % viewport_size)
	_check(prompt != null, "%s: grammar question remains on the wooden title" % viewport_size)
	_check(score != null, "%s: score has a visible numeric label" % viewport_size)
	_check(timer != null and hearts != null, "%s: seconds clock and lives hearts exist separately" % viewport_size)
	_check(pause_button != null, "%s: pause button exists" % viewport_size)

	if hud != null and prompt != null and score != null and timer != null and hearts != null and pause_button != null:
		for mode in MODES:
			for topic in TOPICS:
				var values := {
					"activity": "Catch the Word",
					"topic": topic,
					"game_style": topic,
					"game_mode": mode,
					"difficulty": "Normal",
					"score": 37,
					"lives": 2,
					"time_remaining": 42.0,
					"round_running": true, # Restore an elapsed Seconds clock from a paused snapshot.
					"catch_character": "Boy",
					"catch_map": "City",
				}
				game.call("set_context", values)
				game.set_process(false)
				await process_frame
				var test_name := "%s %s %s" % [viewport_size, mode, topic]
				_check_initial_wave(game, test_name)
				_check(String(game.get("topic")) == topic, "%s: chosen grammar topic is active" % test_name)
				_check(String(game.get("game_mode")) == mode, "%s: chosen mode is active" % test_name)
				var article := "AN" if topic in ["Adjective", "Adverb"] else "A"
				_check(prompt.text == "WHICH WORD IS %s %s?" % [article, topic.to_upper()],
					"%s: prompt reflects exact topic and article (got %s)" % [test_name, prompt.text])
				_check(prompt.is_visible_in_tree(), "%s: question remains visible" % test_name)
				_check_hud_question_fit(prompt, plaques.get("TitlePlaque") as TextureRect, test_name)
				for removed_name in ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]:
					_check(game.get_node_or_null("HUDLayer/HUD/" + removed_name) == null,
						"%s: %s remains absent after changing context" % [test_name, removed_name])
				if actual_reference_installed:
					_check(_baked_labels_not_rendered(hud), "%s: generated title and score remain unduplicated" % test_name)
				_check(score.text == "37" and score.is_visible_in_tree(), "%s: score display updates to 37" % test_name)
				for dynamic_score in [0, 108, 10000]:
					game.set("score", dynamic_score)
					game.call("_refresh_hud")
					_check(score.text == str(dynamic_score) and score.is_visible_in_tree(),
						"%s: scoreboard updates dynamically to %d (got %s)" % [test_name, dynamic_score, score.text])
				game.set("score", 37)
				game.call("_refresh_hud")
				_assert_frame(prompt, viewport_size, test_name + " prompt")
				var timer_plaque := plaques.get("TimerPlaque") as TextureRect
				var lives_plaque := plaques.get("LivesPlaque") as TextureRect
				if timer_plaque != null and lives_plaque != null:
					if mode == "Seconds":
						_check(timer.is_visible_in_tree() and timer.text == "42s",
							"%s: 42-second clock is visible" % test_name)
						_check(not hearts.is_visible_in_tree(), "%s: old individual hearts stay hidden" % test_name)
						_check(timer_plaque.visible and not lives_plaque.visible,
							"%s: blue timer plaque replaces static lives panel" % test_name)
					else:
						_check(not timer.visible, "%s: seconds clock is hidden" % test_name)
						_check(not hearts.is_visible_in_tree(),
							"%s: individual heart sprites are replaced by static state artwork" % test_name)
						_check(lives_plaque.visible and not timer_plaque.visible,
							"%s: static lives panel replaces blue timer plaque" % test_name)
						_check_static_lives_panel(game, hearts, lives_plaque, timer_plaque, timer, viewport_size, test_name)

				_assert_frame(score, viewport_size, test_name + " score")
				_assert_frame(pause_button, viewport_size, test_name + " pause button")
				_check(score.get_parent() == game.get_node_or_null("ScoreDrawLayer/ScoreBottomContainer"),
					"%s: exactly one numeric scoreboard node is used" % test_name)

				# Alignment is checked once per mode; topics only replace the words.
				if topic == TOPICS[0]:
					_check_mode_alignment(viewport_size, game.get_viewport_rect().size, mode, plaques,
						prompt, score, timer, hearts, pause_button)

		await _test_character_and_map_combinations(game, viewport_size, body, apples, basket)
		_test_pause_button(game, pause_button, viewport_size)

	host.queue_free()
	await process_frame
	await process_frame
	_check(root.get_child_count() == original_children,
		"%s: disposing Catch scene removes its HUD, hearts and score nodes" % viewport_size)


func _test_serialized_png_resources() -> void:
	# Editor-authored plaques may serialize as SVG placeholders; the runtime
	# swaps them for the actual generated PNG pack after all five are imported.
	# Validate the runtime textures above; source text is insufficient proof.
	var installed := 0
	for file_name in GENERATED_PLAQUES.values():
		var path := GENERATED_HUD_DIR + String(file_name)
		if FileAccess.file_exists(path):
			installed += 1
	_check(installed == 0 or installed == GENERATED_PLAQUES.size(),
		"generated plaque pack is complete (expected 0 or 5 files, found %d)" % installed)
	if installed == GENERATED_PLAQUES.size():
		for amount in [3, 2, 1]:
			_check(ResourceLoader.exists(String(STATIC_LIVES[amount])),
				"static %d-lives panel must be imported at exact replacement PNG path" % amount)
		_check(ResourceLoader.exists(FALLING_APPLE),
			"new glossy falling word apple imported")
		_check(ResourceLoader.exists(CAUGHT_APPLE),
			"original caught basket apple imported")
	if installed == 0:
		print("INFO  HUD PNG pack has not arrived; checking SVG fallback. Run test_catch_png_assets.gd for strict raster verification.")
	else:
		print("INFO  HUD PNG pack detected; verifying all five runtime textures and baked labels.")


func _generated_pack_available() -> bool:
	for file_name in GENERATED_PLAQUES.values():
		var path := GENERATED_HUD_DIR + String(file_name)
		if not FileAccess.file_exists(path) or not ResourceLoader.exists(path):
			return false
	return true


func _assert_generated_png(path: String, label: String) -> void:
	var valid_path := path.begins_with(GENERATED_HUD_DIR) and path.to_lower().ends_with(".png")
	_check(valid_path, "%s uses generated PNG texture (actual: %s)" % [label, path])
	if not valid_path:
		return
	_check(FileAccess.file_exists(path), "%s PNG exists on disk" % label)
	var png_file := FileAccess.open(path, FileAccess.READ)
	if png_file == null:
		_fail("%s PNG could not be opened: %s" % [label, path])
		return
	var header := png_file.get_buffer(8)
	png_file.close()
	var expected := PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10])
	_check(header == expected, "%s has genuine PNG file signature" % label)


func _baked_labels_not_rendered(node: Node) -> bool:
	if node is Label:
		var label := node as Label
		if label.is_visible_in_tree():
			var value := label.text.strip_edges().to_upper().replace(" ", "")
			if value in ["CATCH", "THE", "WORD", "CATCHTHEWORD"] or value.begins_with("SCORE"):
				return false
	for child in node.get_children():
		if not _baked_labels_not_rendered(child):
			return false
	return true


func _test_character_and_map_combinations(game: Control, viewport_size: Vector2i,
		body: Sprite2D, apples: Node2D, basket: Sprite2D) -> void:
	if body == null or apples == null or basket == null:
		return
	var backdrop := game.get_node_or_null("Background") as TextureRect
	var rig := game.get_node_or_null("CharacterRig") as Node2D
	var falling := game.get_node_or_null("FallingWordLayer") as Node2D
	if backdrop == null or rig == null or falling == null:
		_fail("%s: character/map layers are missing" % viewport_size)
		return

	for character_name in CHARACTERS:
		for map_name in MAPS:
			var ctx := "%s %s on %s" % [viewport_size, character_name, map_name]
			game.call("set_context", {
				"activity": "Catch the Word",
				"topic": "Noun",
				"game_mode": "Seconds",
				"difficulty": "Normal",
				"catch_character": character_name,
				"catch_map": map_name,
				"catch_collected_words": ["apple", "teacher", "river", "school"],
			})
			game.set_process(false)
			await process_frame
			await process_frame
			_check_initial_wave(game, ctx)

			_check(String(game.get("selected_character")) == character_name,
				"%s: requested character is selected" % ctx)
			_check(String(game.get("selected_map")) == map_name,
				"%s: requested map is selected" % ctx)
			_check(backdrop.texture != null and backdrop.texture.resource_path ==
				"res://WordCatcherMaps/%sMap.png" % map_name,
				"%s: correct separately editable PNG background loaded" % ctx)
			var expected_body := "res://WordCatcherCharacters/%s BODY.png" % character_name.to_upper()
			var expected_basket := "res://WordCatcherCharacters/%s BASKET.png" % character_name.to_upper()
			_check(body.texture != null and body.texture.resource_path == expected_body,
				"%s: original character BODY PNG loaded even if generated alternative exists" % ctx)
			_check(basket.texture != null and basket.texture.resource_path == expected_basket,
				"%s: original character BASKET PNG loaded even if generated alternative exists" % ctx)
			_check(body.texture != basket.texture, "%s: body and basket use different images" % ctx)
			_check(body.get_parent() == rig and apples.get_parent() == rig and basket.get_parent() == rig,
				"%s: rig keeps three independent layers" % ctx)
			_check(backdrop.z_index < body.z_index
				and body.z_index < apples.z_index
				and apples.z_index < basket.z_index,
				"%s: backdrop/body/caught apples/basket render in correct order" % ctx)
			_check(falling.z_index >= body.z_index, "%s: falling apples remain on gameplay layer" % ctx)
			# Original cropped character parts must maintain comparable
			# onscreen widths while remaining independently layered.
			var body_visible_width := body.region_rect.size.x * absf(body.get_global_transform().get_scale().x)
			var basket_visible_width := basket.region_rect.size.x * absf(basket.get_global_transform().get_scale().x)
			_check(body_visible_width > 1.0 and basket_visible_width > 1.0
				and basket_visible_width / body_visible_width > 0.75
				and basket_visible_width / body_visible_width < 1.65,
				"%s: body/basket onscreen proportions align (body %.1f, basket %.1f)" %
				[ctx, body_visible_width, basket_visible_width])
			_check(body.region_enabled and basket.region_enabled
				and body.region_rect.has_area() and basket.region_rect.has_area(),
				"%s: body and basket retain their independent cropped sprite regions" % ctx)
			_check(apples.get_child_count() == 3,
				"%s: collection displays no more than three caught apples" % ctx)
			if apples.get_child_count() == 3:
				for index in range(3):
					var apple := apples.get_child(index) as TextureRect
					_check(apple != null and apple.get_child_count() > 0
						and apple.get_child(0) is Label,
						"%s: caught apple %d retains its word text" % [ctx, index + 1])
					_check(apple != null and apple.texture != null
						and apple.texture.resource_path == CAUGHT_APPLE,
						"%s: caught apple %d uses ORIGINAL Components/Apple.png" % [ctx, index + 1])
			var glossy: Texture2D = game.get("gameplay_apple_texture") as Texture2D
			_check(glossy != null and glossy.resource_path == FALLING_APPLE,
				"%s: falling apples use generated glossy word_apple.png" % ctx)
			var demo_falling := game.call("_create_tile_node", "TEST", Color.WHITE) as Control
			_check(demo_falling != null, "%s: falling word apple can be created" % ctx)
			if demo_falling != null:
				var glossy_sprite := demo_falling.get_node_or_null("AppleSprite") as TextureRect
				_check(glossy_sprite != null and glossy_sprite.texture == glossy,
					"%s: actual falling sprite selects glossy PNG" % ctx)
				demo_falling.queue_free()
			var bottom_y := body.global_position.y + body.region_rect.size.y * body.scale.y * 0.5
			_check(bottom_y > float(viewport_size.y),
				"%s: lower body stays below viewport for half-body framing" % ctx)


func _check_mode_alignment(viewport_size: Vector2i, logical_viewport_size: Vector2,
		mode: String, plaques: Dictionary,
		prompt: Label,
		score: Label, timer: Label, hearts: HBoxContainer,
		pause_button: Button) -> void:
	var ctx := "%s %s" % [viewport_size, mode]
	for name in PLAQUE_NAMES:
		var plaque := plaques.get(name) as TextureRect
		if plaque != null and plaque.visible:
			_assert_frame(plaque, viewport_size, ctx + " " + name)
	if plaques.has("TitlePlaque"):
		var title_plaque := plaques["TitlePlaque"] as TextureRect
		# Godot's canvas_items stretch keeps 1280x720 logical coordinates when
		# the physical window is 1600x900 or 1920x1080. Compare against the
		# scene's drawing viewport, then the engine scales it to the window.
		var expected_scale := minf(logical_viewport_size.x / 1280.0, logical_viewport_size.y / 720.0)
		var actual_width := title_plaque.get_global_rect().size.x
		var design_width := 506.0 if ResourceLoader.exists(REFERENCE_PNG_READY) else 450.0
		_check(absf(actual_width / design_width - expected_scale) < 0.05,
			"%s: title HUD uses logical viewport scale (width %.1f; logical %s)" % [ctx, actual_width, logical_viewport_size])
	if plaques.has("TitlePlaque"):
		_assert_intersection(prompt, plaques["TitlePlaque"], ctx + " wooden-title question", 0.35)
	if plaques.has("ScorePlaque"):
		_assert_intersection(score, plaques["ScorePlaque"], ctx + " numeric score", 0.4)
	if plaques.has("PausePlaque"):
		_assert_intersection(pause_button, plaques["PausePlaque"], ctx + " pause button", 0.4)
	if mode == "Seconds" and plaques.has("TimerPlaque"):
		_assert_frame(timer, viewport_size, ctx + " countdown")
		_assert_intersection(timer, plaques["TimerPlaque"], ctx + " countdown", 0.4)
	if mode == "Lives" and plaques.has("LivesPlaque"):
		var state_plaque := plaques["LivesPlaque"] as TextureRect
		_assert_frame(state_plaque, viewport_size, ctx + " static lives panel")
		_check(not hearts.is_visible_in_tree(),
			ctx + ": dynamic heart strip hidden under supplied static panel")


func _check_initial_wave(game: Control, context_name: String) -> void:
	var tiles: Array = game.get("falling_tiles")
	_check(tiles.size() == 3,
		"%s: new context creates all three falling answer apples (actual %d)" % [context_name, tiles.size()])
	if tiles.size() != 3:
		return
	var first_y := float(Vector2((tiles[0] as Dictionary)["pos"]).y)
	var first_speed := float((tiles[0] as Dictionary)["speed"])
	var lanes: Dictionary = {}
	var correct := 0
	for index in range(tiles.size()):
		var tile := tiles[index] as Dictionary
		var lane := int(tile.get("lane", -1))
		_check(lane in [0, 1, 2] and not lanes.has(lane),
			"%s: apple %d owns a distinct lane 0-2 (got %d)" % [context_name, index, lane])
		lanes[lane] = true
		if bool(tile.get("matching", false)):
			correct += 1
		_check(absf(Vector2(tile["pos"]).y - first_y) <= 1.0,
			"%s: all apples share synchronized initial height" % context_name)
		_check(absf(float(tile["speed"]) - first_speed) <= 0.01,
			"%s: all apples share synchronized fall speed" % context_name)
		_check(not bool(tile.get("passed_line", false)),
			"%s: each initial answer is still catchable" % context_name)
	_check(correct == 1,
		"%s: answer wave contains one correct and two wrong choices (got %d correct)" % [context_name, correct])


func _test_pause_button(game: Control, pause_button: Button, viewport_size: Vector2i) -> void:
	var events: Array[String] = []
	game.connect("requested", func(target: String, _payload: Dictionary) -> void:
		events.append(target)
	)
	_check(pause_button.visible and not pause_button.disabled,
		"%s: pause button is visible and enabled" % viewport_size)
	pause_button.pressed.emit()
	_check(events.has("pause"), "%s: pressing pause emits the pause request" % viewport_size)
	_check(not bool(game.get("round_running")), "%s: pause freezes the round" % viewport_size)


func _assert_frame(node: Control, viewport_size: Vector2i, label: String) -> void:
	if node == null or not node.is_visible_in_tree():
		return
	var rect := node.get_global_rect()
	var screen := Rect2(Vector2.ZERO, Vector2(viewport_size))
	_check(rect.size.x >= 1.0 and rect.size.y >= 1.0
		and screen.encloses(rect.grow(-1.0)),
		"%s fits %s (actual: %s)" % [label, viewport_size, rect])


func _assert_intersection(control: Control, plaque: Control, label: String, minimum: float) -> void:
	if control == null or plaque == null:
		return
	if not control.is_visible_in_tree() or not plaque.is_visible_in_tree():
		return
	var rect := control.get_global_rect()
	var occupied := rect.intersection(plaque.get_global_rect()).get_area()
	_check(rect.get_area() > 0.0 and occupied >= rect.get_area() * minimum,
		"%s aligns with its plaque (control: %s, plaque: %s)" % [label, rect, plaque.get_global_rect()])


func _check_hud_question_fit(prompt: Label, title_plaque: TextureRect, context: String) -> void:
	var font := prompt.get_theme_font("font")
	var font_size := prompt.get_theme_font_size("font_size")
	var measured := font.get_string_size(prompt.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	_check(prompt.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
		and prompt.vertical_alignment == VERTICAL_ALIGNMENT_CENTER,
		context + ": prompt centered horizontally and vertically")
	_check(prompt.autowrap_mode == TextServer.AUTOWRAP_OFF
		and measured.x <= prompt.size.x + 2.0 and font.get_height(font_size) <= prompt.size.y + 2.0,
		"%s: prompt not clipped (text %.1fpx / label %.1fpx at font %d)" %
		[context, measured.x, prompt.size.x, font_size])
	if title_plaque != null:
		var panel := title_plaque.get_global_rect()
		var text_area := prompt.get_global_rect()
		_check(panel.encloses(text_area.grow(-1.0)), context + ": prompt fits within title plaque")
		_check(absf(panel.get_center().x - text_area.get_center().x) <= panel.size.x * 0.07,
			context + ": prompt visually centered in title plaque")


func _check_static_lives_panel(game: Control, hearts: HBoxContainer,
		plaque: TextureRect, timer_plaque: TextureRect, timer: Label,
		viewport: Vector2i, context: String) -> void:
	for amount in [3, 2, 1]:
		game.set("lives", amount)
		game.call("_refresh_hud")
		var texture_path := plaque.texture.resource_path if plaque.texture != null else ""
		_check(plaque.is_visible_in_tree() and texture_path == String(STATIC_LIVES[amount]),
			"%s: lives=%d selects EXACT static heart PNG (actual %s)" %
			[context, amount, texture_path])
		_check(not hearts.is_visible_in_tree(),
			"%s: lives=%d displays no dynamic HeartRed/HeartBlack overlays" % [context, amount])
		_check(not timer_plaque.is_visible_in_tree() and not timer.is_visible_in_tree(),
			"%s: lives=%d static panel replaces the entire timer UI" % [context, amount])
		_assert_frame(plaque, viewport, "%s lives=%d static heart panel" % [context, amount])
	game.set("lives", 2)
	game.call("_refresh_hud")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)


func _finish(original_size: Vector2i) -> void:
	root.size = original_size
	if failures.is_empty():
		print("PASS  Catch the Word HUD: %d checks, 5 topics x 2 modes x 3 viewports" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("CATCH HUD QA: " + failure)
		print("FAIL  Catch the Word HUD: %d failures in %d checks" % [failures.size(), checks])
		quit(1)
