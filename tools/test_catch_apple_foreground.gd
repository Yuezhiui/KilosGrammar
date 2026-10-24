extends SceneTree

# Godot 4.7.2: --headless --path . --script res://tools/test_catch_apple_foreground.gd
# Actual Catch scene, not mock nodes; no webcam/PNG edits. The default 2D
# canvas inherits parent z values, so assert the COMPLETE effective z chain.

const SCENE := preload("res://ui/minigames/catch_word.tscn")
const CHARACTERS := ["Boy", "Girl", "Grandma", "Grandpa"]
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const PARTS := ["Body", "Basket"]
const EPSILON := 2.0
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := SCENE.instantiate() as Control
	var authored_rig := scene.get_node_or_null("CharacterRig") as Node2D
	_check(authored_rig != null and authored_rig.position.y >= 450.0,
		"CharacterRig has its actual saved editor baseline (never silently parsed as y=0)")
	scene.free()
	for size in SIZES:
		root.size = size
		root.content_scale_size = size
		for character in CHARACTERS:
			await _verify_case(size, character)
	_finish()


func _verify_case(size: Vector2i, character: String) -> void:
	var tag := "%s / %s" % [size, character]
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"catch_character": character, "catch_map": "City",
		"game_mode": "Seconds", "topic": "Noun", "difficulty": "Normal"})
	game.set_process(false)
	await process_frame
	game.set_process(false)

	var bg := game.get_node("Background") as CanvasItem
	var falling := game.get_node("FallingWordLayer") as Node2D
	var rig := game.get_node("CharacterRig") as Node2D
	var body := game.body_sprite as Sprite2D
	var basket := game.basket_sprite as Sprite2D
	var caught := game.get_node("CharacterRig/CollectedWords") as Node2D
	var score := game.score_draw_layer as Control
	var hud := game.get_node("HUDLayer") as CanvasLayer
	_check(rig.z_index == 0 and falling.z_index == 1, tag + ": avatar uses gameplay layer 0; falling apples layer 1")
	_check(score != null and _effective_z(score) < _effective_z(body),
		tag + ": score plaque is BEHIND avatar, not above player")
	_check(_effective_z(bg) < _effective_z(score), tag + ": background remains behind score and avatar")
	_check(_effective_z(body) < _effective_z(caught)
		and _effective_z(caught) < _effective_z(basket)
		and _effective_z(basket) < _effective_z(falling),
		tag + ": full draw order background < score < body < caught < basket < falling")
	_check(hud.layer >= 20 and score.get_parent() == game
		and game.score_plaque.get_parent() == score,
		tag + ": normal HUD stays high; ONLY score sits behind avatar")
	_check(body.get_parent() == basket.get_parent()
		and (body.get_parent() == rig or body.get_parent().get_parent() == rig)
		and body.owner == game and basket.owner == game,
		tag + ": active Body/Basket are independent editor-authored sprites")
	_check(game.falling_tiles.size() == 3 and falling.get_child_count() == 3,
		tag + ": actual wave spawned three native falling apple nodes")

	for tile in game.falling_tiles:
		var node := tile.get("node") as Control
		_check(node != null and node.get_parent() == falling, tag + ": apple owns falling gameplay layer")
		if node == null:
			continue
		var art := node.get_node_or_null("AppleSprite") as TextureRect
		var label := node.get_node_or_null("WordLabel") as Label
		_check(art != null and art.texture == game.gameplay_apple_texture and art.visible,
			tag + ": real spawned AppleSprite is textured, visible, and not an empty placeholder")
		_check(label != null and label.is_visible_in_tree() and label.text.strip_edges() != "",
			tag + ": apple label is visible with its grammar word")
		_check(_effective_z(node) > _effective_z(basket)
			and (art == null or _effective_z(art) > _effective_z(basket))
			and (label == null or _effective_z(label) > _effective_z(basket)),
			tag + ": BOTH apple image and label render in front of avatar and basket")

	var screen := Rect2(Vector2.ZERO, Vector2(size))
	var scale_factor := minf(float(size.x) / 1280.0, float(size.y) / 720.0)
	_check(rig.scale.is_equal_approx(game.character_editor_scale * scale_factor),
		tag + ": responsive root scaling preserves editor-authored sprite sizes")
	_check_clipping(body, basket, screen, tag + ": at initial position")
	_check_hitbox(game, basket, tag + ": initial position")
	for side in [-1.0, 1.0]:
		game.set_body_x(side)
		game._update_basket(2.0)
		game._sync_character_position()
		_check_clipping(body, basket, screen, tag + ": camera steering %s" % side)
		_check_hitbox(game, basket, tag + ": camera steering %s" % side)
	game.clear_body_input()

	# Check keys individually: pressing left AND right together would cancel
	# the old input axis and falsely pass an inactive-keyboard regression.
	for keyboard_action in ["ui_left", "ui_right"]:
		var before_x := rig.position.x
		Input.action_press(keyboard_action)
		game._update_basket(0.2)
		game._sync_character_position()
		Input.action_release(keyboard_action)
		_check(absf(rig.position.x - before_x) < 0.01,
			tag + ": keyboard action %s cannot steer the character" % keyboard_action)
	var source_text := FileAccess.get_file_as_string("res://ui/minigames/catch_word.gd")
	_check(not source_text.contains("Input.get_axis(")
		and not source_text.contains("Input.is_key_pressed(KEY_A)")
		and not source_text.contains("Input.is_key_pressed(KEY_D)"),
		tag + ": Catch source contains no active physical A/D or arrow steering")
	_check(not game.body_input_active, tag + ": clearing camera input stays cleared")

	game._reset_round_geometry()
	game._on_resized()
	_check_clipping(body, basket, screen, tag + ": after reset and resize")
	_check_hitbox(game, basket, tag + ": after reset and resize")

	# Real apples keep the correct relative z when moving downward into the
	# avatar's actual screen-space image, with HUD on CanvasLayer 20 over them.
	for tile in game.falling_tiles:
		var apple := tile.get("node") as Control
		if apple == null:
			continue
		var img := apple.get_node("AppleSprite") as TextureRect
		var pos := basket.global_position
		apple.position = pos - game.APPLE_SIZE * 0.5
		_check(_effective_z(apple) > _effective_z(body)
			and _effective_z(img) > _effective_z(basket),
			tag + ": apple still foreground at the avatar's actual basket position")
	_check(_effective_z(game.get_node("HUDLayer/HUD/PauseButton") as CanvasItem)
		<= _effective_z(falling) and hud.layer > 0,
		tag + ": HUD remains on its separate top CanvasLayer, not mistakenly reparented with falling apples")

	game.queue_free()
	await process_frame


func _check_clipping(body: Sprite2D, basket: Sprite2D, screen: Rect2, tag: String) -> void:
	for item in [body, basket]:
		var rect := _sprite_rect(item)
		_check(screen.grow(EPSILON).encloses(rect),
			"%s: %s visually inside screen (%s)" % [tag, item.name, rect])


func _check_hitbox(game: Control, basket: Sprite2D, tag: String) -> void:
	var visual := _sprite_rect(basket)
	var hitbox := game._basket_rect() as Rect2
	_check(hitbox.has_area() and absf(hitbox.get_center().x - visual.get_center().x) < EPSILON
		and absf(hitbox.get_center().y - (visual.get_center().y - visual.size.y * 0.05)) < EPSILON,
		tag + ": responsive world hitbox aligned with rendered basket")


func _sprite_rect(sprite: Sprite2D) -> Rect2:
	var r := sprite.get_rect()
	var xform := sprite.get_global_transform_with_canvas()
	var rect := Rect2(xform * r.position, Vector2.ZERO)
	for corner in [r.position + Vector2(r.size.x, 0), r.position + r.size,
		r.position + Vector2(0, r.size.y)]:
		rect = rect.expand(xform * corner)
	return rect.abs()


func _effective_z(item: CanvasItem) -> int:
	var z := item.z_index
	var part := item
	while part.z_as_relative and part.get_parent() is CanvasItem:
		part = part.get_parent() as CanvasItem
		z += part.z_index
	return z


func _check(ok: bool, why: String) -> void:
	checks += 1
	if not ok:
		failures.append(why)


func _finish() -> void:
	for issue in failures:
		printerr("FAIL Catch apples foreground: ", issue)
	print("%s Catch apple foreground, HUD and steering: %d checks, %d failures (%d characters x %d resolutions)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size(), CHARACTERS.size(), SIZES.size()])
	quit(0 if failures.is_empty() else 1)
