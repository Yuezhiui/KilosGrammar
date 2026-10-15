extends SceneTree

# Revert acceptance regression for Catch the Word. Test ONLY; no source edits.
# Godot 4.7.2: --headless --path . --script res://tools/test_catch_revert_hud.gd
# Expected final: OLD four character sprites and original collected basket
# apples, NEW falling word-apple PNG and baked-art HUD, three exact static
# heart-panel PNGs (1/2/3 lives), with no objective plaque or feedback UI.

const SCENE := "res://ui/minigames/catch_word.tscn"
const ART := "res://ui/minigames/catch_hud/generated/"
const OLD_CHAR := "res://WordCatcherCharacters/"
const OLD_BASKET_APPLE := "res://Components/Apple.png"
const NEW_FALLING_APPLE := ART + "character/word_apple.png"
const HEART_STATE_DIR := ART + "replacement/"
const HEART_STATE_PATHS := {
	1: "res://ui/minigames/catch_hud/generated/replacement/lives_state_1.png",
	2: "res://ui/minigames/catch_hud/generated/replacement/lives_state_2.png",
	3: "res://ui/minigames/catch_hud/generated/replacement/lives_state_3.png",
}
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const CHARACTERS := ["Boy", "Girl", "Grandma", "Grandpa"]
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(875, 500)]
const PLAQUES := {
	"TitlePlaque": "title_board.png",
	"TimerPlaque": "timer_badge.png",
	"ScorePlaque": "score_board.png",
	"PausePlaque": "pause_badge.png",
}
var failures: Array[String] = []
var checks := 0
var situations := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_size := root.size
	var packed := load(SCENE) as PackedScene
	_check(packed != null, "Catch game scene can load")
	for name in PLAQUES.values():
		var file := ART + String(name)
		_check(_is_png(file), "provided HUD PNG exists/loads: " + file)
	_check(_is_png(NEW_FALLING_APPLE), "provided falling word apple PNG exists")
	_check(_is_png(OLD_BASKET_APPLE), "original basket Apple.png exists")
	for amount in [3, 2, 1]:
		_check(_is_png(String(HEART_STATE_PATHS[amount])),
			"static heart state %d image is present and importable at EXACT path %s" %
			[amount, HEART_STATE_PATHS[amount]])
	if packed != null:
		for physical_size in VIEWPORTS:
			await _verify_viewport(packed, physical_size)
	root.size = original_size
	if failures.is_empty():
		print("PASS  Catch reverted HUD: %d checks across %d topic/mode/viewport states" %
			[checks, situations])
		quit(0)
	else:
		for i in range(mini(failures.size(), 35)):
			push_error("REVERT HUD QA: " + failures[i])
		if failures.size() > 35:
			print("... %d additional failures suppressed; first 35 shown" % (failures.size() - 35))
		print("FAIL  Catch reverted HUD: %d failures in %d checks over %d topic/mode/viewport states" %
			[failures.size(), checks, situations])
		quit(1)


func _is_png(file: String) -> bool:
	if not FileAccess.file_exists(file) or not ResourceLoader.exists(file):
		return false
	var texture := load(file) as Texture2D
	return texture != null and texture.get_width() >= 16 and texture.get_height() >= 16


func _verify_viewport(packed: PackedScene, physical_size: Vector2i) -> void:
	root.size = physical_size
	await process_frame
	await process_frame
	var initial_count := root.get_child_count()
	var host := Control.new()
	host.name = "RevertHUDHost"
	host.size = Vector2(physical_size)
	root.add_child(host)
	var game := packed.instantiate() as Control
	if game == null or game.get_script() == null:
		_fail("%s: game scene or script could not instantiate" % physical_size)
		host.queue_free()
		await process_frame
		return
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	game.set_process(false)

	var hud := game.get_node_or_null("HUDLayer/HUD") as Control
	var body := game.get_node_or_null("CharacterRig/Body") as Sprite2D
	var basket := game.get_node_or_null("CharacterRig/Basket") as Sprite2D
	var numeric := game.get_node_or_null("HUDLayer/HUD/ScoreBottomContainer/ScoreNumber") as Label
	var time_label := game.get_node_or_null("HUDLayer/HUD/TimeLabel") as Label
	var timer := game.get_node_or_null("HUDLayer/HUD/TimerPlaque") as TextureRect
	var heart_box := game.get_node_or_null("HUDLayer/HUD/HeartsBox") as HBoxContainer
	var hearts_plaque := game.get_node_or_null("HUDLayer/HUD/LivesPlaque") as TextureRect
	if hud == null or body == null or basket == null \
			or numeric == null or time_label == null \
			or timer == null or hearts_plaque == null:
		_fail("%s: required HUD/character nodes missing" % physical_size)
		host.queue_free()
		await process_frame
		return
	for node_name in PLAQUES:
		var plaque := hud.get_node_or_null(String(node_name)) as TextureRect
		_check(plaque != null and plaque.texture != null
			and plaque.texture.resource_path == ART + String(PLAQUES[node_name]),
			"%s: %s loads NEW supplied PNG" % [physical_size, node_name])
	for absent_name in ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]:
		_check(not hud.has_node(absent_name),
			"%s: %s removed from authored/runtime HUD" % [physical_size, absent_name])
	_check_falling_and_basket_apples(game, physical_size)
	_check(bool(game.get("using_reference_pngs")),
		"%s: new HUD art is active" % physical_size)
	for character_name in CHARACTERS:
		game.call("set_context", {
			"activity": "Catch the Word",
			"topic": "Noun",
			"game_mode": "Seconds",
			"catch_character": character_name,
			"catch_map": "City",
			"difficulty": "Normal",
		})
		game.set_process(false)
		await process_frame
		var expected_body: String = OLD_CHAR + String(character_name).to_upper() + " BODY.png"
		var expected_basket: String = OLD_CHAR + String(character_name).to_upper() + " BASKET.png"
		_check(body.texture != null and body.texture.resource_path == expected_body,
			"%s %s: reverted original BODY (got %s)" %
			[physical_size, character_name, _texture_path(body.texture)])
		_check(basket.texture != null and basket.texture.resource_path == expected_basket,
			"%s %s: reverted original BASKET (got %s)" %
			[physical_size, character_name, _texture_path(basket.texture)])
		# Older script revisions exposed this flag. The revert may remove it
		# altogether; texture resource paths above are the authoritative proof.
		var generated_character_flag = game.get("using_reference_character")
		_check(generated_character_flag == null or generated_character_flag == false,
			"%s %s: generated character path disabled or removed" % [physical_size, character_name])

	for mode in ["Seconds", "Lives"]:
		var heart_paths: Dictionary = {}
		for topic in TOPICS:
			game.call("set_context", {
				"activity": "Catch the Word",
				"topic": topic,
				"game_mode": mode,
				"catch_character": "Girl",
				"catch_map": "City",
				"difficulty": "Normal",
				"lives": 3,
				"time_remaining": 42.0,
				"score": 18,
			})
			game.set_process(false)
			await process_frame
			situations += 1
			var label := "%s %s %s" % [physical_size, mode, topic]
			_verify_no_duplicate_labels(hud, numeric, label)
			_verify_mode(game, hud, timer, time_label, hearts_plaque, heart_box,
				mode, heart_paths, label)
			for absent_name in ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]:
				_check(not hud.has_node(absent_name),
					label + ": removed " + absent_name + " stays absent")
			_check_visible_bounds(hud, physical_size, label)
		if mode == "Lives":
			_check(heart_paths.size() == 3,
				"%s: 3/2/1 lives each has a distinct static panel PNG (got %s)" %
				[physical_size, heart_paths])

	host.queue_free()
	await process_frame
	await process_frame
	_check(root.get_child_count() == initial_count,
		"%s: no leaked HUD scene children" % physical_size)


func _verify_no_duplicate_labels(hud: Control, score: Label, label: String) -> void:
	for heading_name in ["TitleLabel", "TitleTheLabel", "TitleWordLabel", "ScoreLabel"]:
		var heading := hud.get_node_or_null(heading_name) as Label
		_check(heading == null or not heading.is_visible_in_tree(),
			"%s: baked %s heading not duplicated" % [label, heading_name])
	var texts: Array[Label] = []
	_find_labels(hud, texts)
	var score_count := 0
	var extra_heading_count := 0
	for node in texts:
		if not node.is_visible_in_tree():
			continue
		var value := node.text.strip_edges().to_upper().replace(" ", "")
		if value.begins_with("SCORE") or value in ["CATCH", "THE", "WORD", "CATCHTHEWORD"]:
			extra_heading_count += 1
		if node == score:
			score_count += 1
	_check(extra_heading_count == 0,
		"%s: no visible dynamic SCORE or CATCH THE WORD heading" % label)
	_check(score_count == 1 and score.text == "18",
		"%s: exactly one live numeric score label, value 18" % label)


func _find_labels(node: Node, found: Array[Label]) -> void:
	if node is Label:
		found.append(node as Label)
	for child in node.get_children():
		_find_labels(child, found)


func _check_falling_and_basket_apples(game: Control, physical_size: Vector2i) -> void:
	# These are deliberately DIFFERENT assets. The separately generated
	# image is for falling word tiles, not fruit collected in old baskets.
	var falling_texture: Texture2D = game.get("gameplay_apple_texture") as Texture2D
	_check(_texture_path(falling_texture) == NEW_FALLING_APPLE,
		"%s: falling tile texture is exact provided PNG %s (actual %s)" %
		[physical_size, NEW_FALLING_APPLE, _texture_path(falling_texture)])
	var falling := game.call("_create_tile_node", "TEST", Color.WHITE) as Control
	if falling != null:
		var sprite := falling.get_node_or_null("AppleSprite") as TextureRect
		_check(sprite != null and _texture_path(sprite.texture) == NEW_FALLING_APPLE,
			"%s: real falling-word AppleSprite displays supplied PNG (actual %s)" %
			[physical_size, _texture_path(sprite.texture) if sprite != null else "missing"])
		falling.queue_free()
	else:
		_fail("%s: unable to create falling-word AppleSprite for visual asset check" %
			physical_size)
	var caught_layer := game.get_node_or_null("CharacterRig/CollectedWords") as Node2D
	if caught_layer == null:
		_fail("%s: collected-word apple layer missing" % physical_size)
		return
	var collected: Array = game.get("collected_words")
	collected.clear()
	for word in ["APPLE", "RIVER", "FRIEND"]:
		collected.append(word)
	game.call("_refresh_collected_words")
	_check(caught_layer.get_child_count() == 3,
		"%s: exactly three original apples displayed in basket" % physical_size)
	for index in range(caught_layer.get_child_count()):
		var apple := caught_layer.get_child(index) as TextureRect
		_check(apple != null and _texture_path(apple.texture) == OLD_BASKET_APPLE,
			"%s: caught apple %d MUST use original Components/Apple.png (actual %s)" %
			[physical_size, index + 1, _texture_path(apple.texture) if apple != null else "missing"])
		_check(apple != null and apple.get_child_count() > 0
			and apple.get_child(0) is Label,
			"%s: caught apple %d still has editable word label" %
			[physical_size, index + 1])
	collected.clear()
	game.call("_refresh_collected_words")


func _verify_mode(game: Control, hud: Control, timer: TextureRect, time_label: Label,
		lives_plaque: TextureRect, hearts: HBoxContainer, mode: String,
		found: Dictionary, label: String) -> void:
	if mode == "Seconds":
		_check(timer.is_visible_in_tree() and time_label.is_visible_in_tree()
			and time_label.text == "42s",
			label + ": Seconds mode shows only live timer PNG/countdown")
		_check(not lives_plaque.is_visible_in_tree(),
			label + ": static lives panel hidden in Seconds mode")
		_check(_count_legacy_heart_icons(hearts) == 0,
			label + ": no individual heart icons visible in Seconds mode")
		return
	_check(not timer.is_visible_in_tree() and not time_label.is_visible_in_tree(),
		label + ": Seconds timer fully hidden in Lives mode")
	for amount in [3, 2, 1]:
		game.set("lives", amount)
		game.call("_refresh_hud")
		var choices: Array[TextureRect] = []
		_find_visible_lives_panels(hud, choices)
		var path := _texture_path(choices[0].texture) if choices.size() > 0 else ""
		var expected: String = HEART_STATE_PATHS[amount]
		_check(choices.size() == 1 and path == expected,
			"%s: lives=%d uses EXACT static %s (got %d visible lives panels; first %s)" %
			[label, amount, expected, choices.size(), path])
		_check(_count_legacy_heart_icons(hearts) == 0,
			"%s: lives=%d has no overlaid HeartRed/HeartBlack sprites" % [label, amount])
		if not path.is_empty():
			found[amount] = path
		var badge := choices[0] as TextureRect if choices.size() > 0 else null
		if badge != null:
			_check(badge.is_visible_in_tree() and badge.texture != null,
				"%s: lives=%d static heart bitmap visible" % [label, amount])
	_check(found.has(3) and found.has(2) and found.has(1)
		and found.get(3, "") == HEART_STATE_PATHS[3]
		and found.get(2, "") == HEART_STATE_PATHS[2]
		and found.get(1, "") == HEART_STATE_PATHS[1],
		label + ": 3/2/1 each switch to their exact independently supplied panel")


func _find_visible_lives_panels(node: Node, found: Array[TextureRect]) -> void:
	if node is TextureRect:
		var texture_rect := node as TextureRect
		var path := _texture_path(texture_rect.texture).to_lower()
		var filename := path.get_file()
		if texture_rect.is_visible_in_tree() and path.ends_with(".png") \
				and ("heart" in filename or "lives" in filename):
			found.append(texture_rect)
	for child in node.get_children():
		_find_visible_lives_panels(child, found)


func _count_legacy_heart_icons(hearts: HBoxContainer) -> int:
	if hearts == null or not hearts.is_visible_in_tree():
		return 0
	var count := 0
	for node in hearts.get_children():
		if node is TextureRect and node.is_visible_in_tree():
			var path := _texture_path((node as TextureRect).texture)
			if path.ends_with("/HeartRed.png") or path.ends_with("/HeartBlack.png"):
				count += 1
	return count


func _check_visible_bounds(hud: Control, physical: Vector2i, label: String) -> void:
	# In canvas_items stretch mode, get_global_rect is in logical coordinates
	# even at an 875x500 physical editor window. Check logical full viewport.
	var logical := hud.get_viewport_rect().size
	var field := Rect2(Vector2.ZERO, logical)
	var physical_projection := Vector2(float(physical.x) / logical.x,
		float(physical.y) / logical.y)
	_check(logical.x > 0.0 and logical.y > 0.0,
		label + ": valid logical viewport")
	var names := ["TitlePlaque", "TimerPlaque", "LivesPlaque",
		"PausePlaque", "ScorePlaque", "ScoreBottomContainer"]
	for name in names:
		var control := hud.get_node_or_null(name) as Control
		if control == null or not control.is_visible_in_tree():
			continue
		var actual := control.get_global_rect()
		_check(field.encloses(actual.grow(-0.5)),
			"%s: %s fits logical viewport %s (got %s)" %
			[label, name, logical, actual])
		var projected := Rect2(actual.position * physical_projection,
			actual.size * physical_projection)
		_check(Rect2(Vector2.ZERO, Vector2(physical)).encloses(projected.grow(-0.25)),
			"%s: %s stays on physical display %s" % [label, name, physical])


func _texture_path(texture: Texture2D) -> String:
	return texture.resource_path if texture != null else ""


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		_fail(label)


func _fail(label: String) -> void:
	failures.append(label)
