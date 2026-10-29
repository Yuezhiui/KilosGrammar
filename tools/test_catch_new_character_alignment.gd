extends SceneTree

# All five editor-authored animal pairs must retain their intended bust crop,
# visible face/torso and fully visible basket, on every gameplay background.
# Collected fruit is now original APPLE HALF.png with NO word labels.
const SCENE := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const CHARACTERS := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const MAPS := ["Forest", "City", "Mountain"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const EPS := 1.5
const HALF_APPLE := "res://Components/Gameplay/Catch the Word/Items/APPLE HALF.png"

var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for resolution in RESOLUTIONS:
		var viewport := SubViewport.new()
		viewport.size = resolution
		viewport.disable_3d = true
		root.add_child(viewport)
		for character in CHARACTERS:
			for map_name in MAPS:
				await _check_game(viewport, resolution, character, map_name)
		viewport.queue_free()
		await process_frame
	for error in errors:
		push_error(error)
	print("CATCH NEW CHARACTER ALIGNMENT: ", "PASS (%d layouts)" % (RESOLUTIONS.size() * CHARACTERS.size() * MAPS.size()) if errors.is_empty() else "FAIL (%d)" % errors.size())
	quit(0 if errors.is_empty() else 1)


func _check_game(viewport: SubViewport, resolution: Vector2i, character: String, map_name: String) -> void:
	var tag := "%s/%s/%dx%d" % [character, map_name, resolution.x, resolution.y]
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
	check(group != null and body != null and basket != null, tag + " selected sprites/group are missing")
	if group == null or body == null or basket == null:
		game.queue_free()
		await process_frame
		return
	check(game.get("selected_character") == character, tag + " incorrect active variant")
	check(game.get("selected_map") == map_name, tag + " incorrect active map")
	check(body == group.get_node("Body") and basket == group.get_node("Basket"), tag + " active sprite pointers do not match selected scene nodes")
	check(group.owner == game and group.get_parent() == game, tag + " character group not owned by editable scene")
	check(body.owner == game and basket.owner == game, tag + " body/basket are not editor-authored")
	check(body.is_visible_in_tree() and basket.is_visible_in_tree(), tag + " selected sprites hidden")
	for other in CHARACTERS:
		if other == character:
			continue
		var other_group := game.get_node(other) as Node2D
		check(not other_group.visible, tag + " inactive " + other + " group is visible")
	var original_body := "res://Components/Gameplay/Catch the Word/Characters/%s BODY.png" % character.to_upper()
	var original_basket := "res://Components/Gameplay/Catch the Word/Characters/%s BASKET.png" % character.to_upper()
	check(body.texture != null and body.texture.resource_path == original_body, tag + " body is not its ORIGINAL PNG")
	check(basket.texture != null and basket.texture.resource_path == original_basket, tag + " basket is not its ORIGINAL PNG")
	check(body.region_enabled and basket.region_enabled, tag + " alpha crop must remain scene-authored")
	var body_rect := _screen_rect(body)
	var basket_rect := _screen_rect(basket)
	var bounds := Rect2(Vector2.ZERO, Vector2(resolution))
	check(_avatar_framed(bounds, body_rect), tag + " face/torso clipped or wrong authored bust framing: " + str(body_rect))
	check(_inside(bounds, basket_rect), tag + " basket clipped: " + str(basket_rect))
	check(body_rect.size.y >= float(resolution.y) * 0.25, tag + " body too small to see completely")
	check(body_rect.end.y >= float(resolution.y) * 0.67, tag + " body floats above the playfield")
	check(basket_rect.intersects(body_rect), tag + " basket misses selected body")
	check(absf(basket_rect.get_center().x - body_rect.get_center().x) <= body_rect.size.x * 0.24, tag + " basket not centered on selected body")
	check(basket_rect.get_center().y > body_rect.position.y + body_rect.size.y * 0.38 and basket_rect.get_center().y < body_rect.end.y, tag + " basket is not held around torso")
	check(body.z_index + group.z_index == 0 and basket.z_index + group.z_index == 1 and layer.z_index == 2,
		tag + " incorrect approved Body 0 / Basket 1 / Collected Apples 2 draw order")
	var title := game.get_node("HUDLayer/HUD/TitlePlaque") as TextureRect
	var pause := game.get_node("HUDLayer/HUD/PausePlaque") as TextureRect
	check(not body_rect.intersects(title.get_global_rect()) and not basket_rect.intersects(title.get_global_rect()), tag + " character obscures title")
	check(not body_rect.intersects(pause.get_global_rect()) and not basket_rect.intersects(pause.get_global_rect()), tag + " character obscures Pause")
	var words: Array = game.get("collected_words")
	words.clear()
	words.append_array(["APPLE", "GARDEN", "TEACHER"])
	game.call("_refresh_collected_words")
	await process_frame
	var count := 0
	for child in layer.get_children():
		if not child is TextureRect or child.is_queued_for_deletion():
			continue
		count += 1
		var apple := child as TextureRect
		var apple_rect := apple.get_global_rect()
		check(apple_rect.get_center().y > body_rect.position.y + body_rect.size.y * 0.30, tag + " collected fruit overlaps face")
		check(apple_rect.position.y < basket_rect.end.y + 10 and apple_rect.end.y > basket_rect.position.y - 80, tag + " collected fruit not in basket zone")
		check(apple_rect.position.x >= basket_rect.position.x - 45 and apple_rect.end.x <= basket_rect.end.x + 45, tag + " collected fruit misses basket horizontally")
		check(apple.texture != null and apple.texture.resource_path == HALF_APPLE,
			tag + " collected fruit does not use actual APPLE HALF.png")
		check(apple.get_child_count() == 0 and apple.material == null,
			tag + " collected half-apple has a prohibited word label or old clipping shader")
		check(apple_rect.size.x >= basket_rect.size.x * 0.12
			and apple_rect.size.x <= basket_rect.size.x * 0.30,
			tag + " collected half-apple is not small relative to basket")
	check(count == 3, tag + " should display exactly three collected apples; got " + str(count))
	print(tag, " body=", body_rect, " basket=", basket_rect)
	game.queue_free()
	await process_frame


func _screen_rect(sprite: Sprite2D) -> Rect2:
	var local := sprite.get_rect()
	var transform := sprite.get_global_transform()
	var points := [
		transform * local.position,
		transform * Vector2(local.end.x, local.position.y),
		transform * local.end,
		transform * Vector2(local.position.x, local.end.y)
	]
	var minimum: Vector2 = points[0]
	var maximum: Vector2 = points[0]
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return Rect2(minimum, maximum - minimum)


func _inside(frame: Rect2, value: Rect2) -> bool:
	return value.size.x > 0.0 and value.size.y > 0.0 and value.position.x >= frame.position.x - EPS and value.position.y >= frame.position.y - EPS and value.end.x <= frame.end.x + EPS and value.end.y <= frame.end.y + EPS


func _avatar_framed(frame: Rect2, value: Rect2) -> bool:
	# Saved animal BODY images extend ~12.5% past bottom of frame; the visible
	# head, face and torso are intentionally in-frame in all native screenshots.
	var visible_ratio := (minf(value.end.y, frame.end.y) - maxf(value.position.y, frame.position.y)) / maxf(value.size.y, 0.001)
	return value.size.x > 0.0 and value.size.y > frame.size.y * 0.25 \
		and value.position.x >= frame.position.x - EPS and value.end.x <= frame.end.x + EPS \
		and value.position.y >= frame.position.y - EPS and value.position.y <= frame.size.y * 0.64 \
		and value.end.y >= frame.end.y - EPS and value.end.y <= frame.end.y + frame.size.y * 0.18 \
		and visible_ratio >= 0.75


func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
