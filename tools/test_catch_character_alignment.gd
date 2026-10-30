extends SceneTree

# Gameplay must preserve each editor-authored Body/Basket transform and use
# those SAME nodes for rendering and the dynamically positioned basket hitbox.
const SCENE := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const CHARACTERS := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const MAPS := ["City", "Forest", "Mountain"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const DELTA_BODY := Vector2(8.0, -9.0)
const DELTA_BASKET := Vector2(11.0, -7.0)
const HALF_APPLE := "res://Components/Gameplay/Catch the Word/Items/APPLE HALF SEAMLESS.png"
const FRONT_CLIP := "res://ui/minigames/catch_the_word/caught_apple_above_rim.gdshader"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	root.add_child(viewport)
	for resolution in RESOLUTIONS:
		viewport.size = resolution
		await process_frame
		for character in CHARACTERS:
			for map_name in MAPS:
				await _check_variant(viewport, resolution, character, map_name)
	viewport.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("CATCH CHARACTER ALIGNMENT: ", "PASS (45 editable character/map/resolution cases)" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _check_variant(viewport: SubViewport, resolution: Vector2i, character: String, map_name: String) -> void:
	var tag := "%s/%s/%dx%d" % [character, map_name, resolution.x, resolution.y]
	var factor := float(resolution.y) / 720.0
	# This separate unmounted instance is the saved .tscn author's positions,
	# not a baseline copied from the game after runtime selected a character.
	var authored := SCENE.instantiate() as Control
	var authored_group := authored.get_node(character) as Node2D
	var authored_body := authored_group.get_node("Body") as Sprite2D
	var authored_basket := authored_group.get_node("Basket") as Sprite2D
	var original_body_position := authored_body.position
	var original_basket_position := authored_basket.position
	var original_body_scale := authored_body.scale
	var original_basket_scale := authored_basket.scale
	var original_body_region := authored_body.region_rect
	var original_basket_region := authored_basket.region_rect
	var original_group_position := authored_group.position
	var original_layer_offset := (authored.get_node("CollectedWords") as Node2D).position - authored_group.position
	_check(authored_body.owner == authored and authored_basket.owner == authored, tag + " original variants are not editable in saved scene")
	_check(authored_body.region_enabled and authored_basket.region_enabled, tag + " original alpha crops not editor-authored")
	_check(original_body_scale.x > 0.0 and original_body_scale.y > 0.0 and original_basket_scale.x > 0.0 and original_basket_scale.y > 0.0, tag + " invalid authored scale")
	authored.free()

	var game := SCENE.instantiate() as Control
	viewport.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	game.set_context({
		"activity": "Catch the Word", "topic": "Noun", "game_mode": "Seconds",
		"catch_character": character, "catch_map": map_name, "keyboard_mode": true
	})
	game.set_process(false)
	game.call("_on_resized")
	await process_frame
	var group := game.get_node(character) as Node2D
	var body := game.get("body_sprite") as Sprite2D
	var basket := game.get("basket_sprite") as Sprite2D
	var layer := game.get_node("CollectedWords") as Node2D
	_check(body == group.get_node("Body") and basket == group.get_node("Basket"), tag + " active sprites differ from editable selected variant")
	_check(body.owner == game and basket.owner == game, tag + " active sprites have no scene owner")
	_check(body.texture != null and body.texture.resource_path == ("res://Components/Gameplay/Catch the Word/Characters/%s BODY.png" % character.to_upper()), tag + " wrong original body texture")
	_check(basket.texture != null and basket.texture.resource_path == ("res://Components/Gameplay/Catch the Word/Characters/%s BASKET.png" % character.to_upper()), tag + " wrong original basket texture")
	_check(_near_vec(body.position, original_body_position) and _near_vec(basket.position, original_basket_position), tag + " runtime overwrote editor-authored Body/Basket positions")
	_check(_near_vec(body.scale, original_body_scale) and _near_vec(basket.scale, original_basket_scale), tag + " runtime overwrote editor-authored sprite scales")
	_check(body.region_rect == original_body_region and basket.region_rect == original_basket_region, tag + " runtime overwrote editor-authored alpha crop")
	_check(_near_vec(group.position, original_group_position * factor), tag + " runtime overwrote scaled editor character group position")
	_check(_near_vec(layer.position - group.position, original_layer_offset * factor), tag + " runtime detached scaled collected-word marker")
	var frame := Rect2(Vector2.ZERO, Vector2(resolution))
	var rect_body := _screen_rect(body)
	var rect_basket := _screen_rect(basket)
	# All five animal lower halves are deliberately below the viewport.
	# Preserve the visible face/torso and basket opening at the editor baseline.
	_check(_bust_visible(frame, rect_body) and _basket_top_visible(frame, rect_basket),
		tag + " selected visible face/hands/basket lip leaves viewport: " + str(rect_body) + " / " + str(rect_basket))
	_check(rect_basket.intersects(rect_body), tag + " basket not aligned to body")
	_check(body.z_index + group.z_index < layer.z_index and layer.z_index < basket.z_index + group.z_index, tag + " collected words are not between body and basket")
	# Dragging either sprite in Godot's 2D editor must have an actual effect.
	# After runtime geometry sync, those authored offsets must still drive
	# visible geometry and the basket's collision region.
	var previous_body := rect_body
	var previous_basket := rect_basket
	var hitbox_before := game.call("_basket_rect") as Rect2
	body.position += DELTA_BODY
	basket.position += DELTA_BASKET
	game.call("_sync_character_position")
	var moved_body := _screen_rect(body)
	var moved_basket := _screen_rect(basket)
	var hitbox_after := game.call("_basket_rect") as Rect2
	_check(_near_vec(moved_body.position - previous_body.position, DELTA_BODY * factor), tag + " dragged Body does not visibly move with scaled editor offset")
	_check(_near_vec(moved_basket.position - previous_basket.position, DELTA_BASKET * factor), tag + " dragged Basket does not visibly move with scaled editor offset")
	_check(_near_vec(hitbox_after.get_center() - hitbox_before.get_center(), DELTA_BASKET * factor), tag + " basket collision does not follow scaled editor Basket transform")
	body.position = original_body_position
	basket.position = original_basket_position
	game.call("_reset_round_geometry")
	_check(_near_vec(body.position, original_body_position) and _near_vec(basket.position, original_basket_position), tag + " reset damaged authored sprite offsets")
	for count in range(4):
		var words: Array = game.get("collected_words")
		words.clear()
		for index in range(count):
			words.append(["APPLE", "GARDEN", "TEACHER"][index])
		game.call("_refresh_collected_words")
		var apples := 0
		for child in layer.get_children():
			if child.is_queued_for_deletion() or not child is TextureRect:
				continue
			apples += 1
			var apple := child as TextureRect
			var apple_rect := apple.get_global_rect()
			var basket_rect := _screen_rect(basket)
			_check(apple_rect.position.y < basket_rect.end.y + 10.0 * factor
				and apple_rect.end.y > basket_rect.position.y - 85.0 * factor,
				tag + " collected word vertically misses scaled basket")
			_check(apple_rect.position.x >= basket_rect.position.x - 45.0 * factor
				and apple_rect.end.x <= basket_rect.end.x + 45.0 * factor,
				tag + " collected word horizontally misses scaled basket")
			var lip := apple.material as ShaderMaterial
			_check(apple.get_child_count() == 0
				and apple.texture != null and apple.texture.resource_path == HALF_APPLE
				and lip != null and lip.shader != null and lip.shader.resource_path == FRONT_CLIP,
				tag + " seamless apple must remain unlabelled with current wicker-lip shader")
		_check(apples == count and apples <= 3, tag + " expected %d collected words, got %d" % [count, apples])
	print(tag, " selected_body=", rect_body, " basket=", rect_basket)
	game.queue_free()
	await process_frame


func _near_vec(value: Vector2, expected: Vector2) -> bool:
	return value.distance_to(expected) <= 1.0


func _screen_rect(sprite: Sprite2D) -> Rect2:
	var local := sprite.get_rect()
	var transform := sprite.get_global_transform()
	var corners := [
		transform * local.position,
		transform * Vector2(local.end.x, local.position.y),
		transform * local.end,
		transform * Vector2(local.position.x, local.end.y)
	]
	var minimum: Vector2 = corners[0]
	var maximum: Vector2 = corners[0]
	for corner in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


func _bust_visible(frame: Rect2, rect: Rect2) -> bool:
	var displayed := (minf(rect.end.y, frame.end.y) - maxf(rect.position.y, frame.position.y)) / maxf(rect.size.y, 1.0)
	return rect.has_area() and rect.position.x >= -1.0 and rect.end.x <= frame.end.x + 1.0 \
		and rect.position.y >= -1.0 and rect.position.y < frame.size.y * 0.65 \
		and rect.end.y >= frame.end.y - 1.0 and rect.end.y < frame.end.y + frame.size.y * 0.2 \
		and displayed >= 0.72


func _basket_top_visible(frame: Rect2, rect: Rect2) -> bool:
	# Observed authored crop: at 720p current opaque baskets extend
	# 0.6px (Cat), 1.1px (Panda), 5.2px (Lion) below the screen.
	# Preserve the basket lip and hands; do not permit side/top clipping.
	var displayed := (minf(rect.end.y, frame.end.y) - maxf(rect.position.y, frame.position.y)) / maxf(rect.size.y, 1.0)
	return rect.has_area() and rect.position.x >= -1.0 and rect.end.x <= frame.end.x + 1.0 \
		and rect.position.y >= frame.size.y * 0.60 and rect.position.y < frame.end.y - rect.size.y * 0.20 \
		and rect.end.y <= frame.end.y + frame.size.y * 0.012 and displayed >= 0.93


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
