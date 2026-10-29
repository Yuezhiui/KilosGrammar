extends SceneTree

# Regression for restoring ORIGINAL transparent WordCatcherCharacters artwork
# across repeated character selections and round resets. Neither the entire
# body nor any basket pixel can be cropped below the game viewport.
const SCENE := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const NAMES := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const MAPS := ["City", "Forest", "Mountain"]
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_alpha: Dictionary = {}
	for name in NAMES:
		var pair := {}
		for suffix in ["BODY", "BASKET"]:
			var path: String = "res://Components/Gameplay/Catch the Word/Characters/%s %s.png" % [name.to_upper(), suffix]
			var png_bytes := FileAccess.get_file_as_bytes(path)
			_check(not png_bytes.is_empty(), path + " original PNG bytes missing")
			if png_bytes.is_empty():
				continue
			var image := Image.new()
			# Inspect the actual source PNG alpha through a byte buffer rather
			# than asking Godot to treat a raw res:// image as an exportable Image.
			var load_result := image.load_png_from_buffer(png_bytes)
			_check(load_result == OK and not image.is_empty(), path + " original source PNG missing")
			if load_result != OK or image.is_empty():
				continue
			var pixels := image.get_used_rect()
			_check(pixels.size.x > 0 and pixels.size.y > 0, path + " contains no opaque artwork")
			_check(pixels.position.x >= 0 and pixels.position.y >= 0 and pixels.end.x <= image.get_width() and pixels.end.y <= image.get_height(), path + " alpha bbox invalid")
			pair[suffix] = {"path": path, "region": Rect2(Vector2(pixels.position), Vector2(pixels.size))}
		original_alpha[name] = pair

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.disable_3d = true
	root.add_child(viewport)
	var game := SCENE.instantiate() as Control
	viewport.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	_check(not game.has_node("CharacterRig"), "legacy parent removed")
	var layer := game.get_node("CollectedWords") as Node2D
	var frame := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var original_transforms: Dictionary = {}
	for name in NAMES:
		var group := game.get_node(name) as Node2D
		var body := group.get_node("Body") as Sprite2D
		var basket := group.get_node("Basket") as Sprite2D
		original_transforms[name] = {
			"body_position": body.position, "basket_position": basket.position,
			"body_scale": body.scale, "basket_scale": basket.scale,
			"group_position": group.position
		}
		_check(body.owner == game and basket.owner == game, name + " original pair not authored in Godot scene")
		_check(group.owner == game and group.get_parent() == game, name + " variant group not editable")

	# Switch characters in ONE live game, then revisit Boy: selecting another
	# variant must never silently keep displaying the default Boy sprite.
	for cycle in range(2):
		for index in range(NAMES.size()):
			var name: String = NAMES[index]
			var map_name: String = MAPS[(index + cycle) % MAPS.size()]
			game.set_context({
				"activity": "Catch the Word", "topic": "Noun", "game_mode": "Seconds",
				"catch_character": name, "catch_map": map_name, "keyboard_mode": true
			})
			game.set_process(false)
			game.call("_on_resized")
			await process_frame
			var tag := "%s cycle=%d" % [name, cycle]
			var group := game.get_node(name) as Node2D
			var body := game.get("body_sprite") as Sprite2D
			var basket := game.get("basket_sprite") as Sprite2D
			_check(game.get("selected_character") == name, tag + " selection reverted to another character")
			_check(body == group.get_node("Body") and basket == group.get_node("Basket"), tag + " selected sprite pointers are stale")
			if not original_alpha.has(name) or not (original_alpha[name] as Dictionary).has("BODY") or not (original_alpha[name] as Dictionary).has("BASKET"):
				_check(false, tag + " original asset could not be inspected")
				continue
			var alpha := original_alpha[name] as Dictionary
			_check(body.texture != null and body.texture.resource_path == alpha["BODY"]["path"], tag + " not showing ORIGINAL body PNG")
			_check(basket.texture != null and basket.texture.resource_path == alpha["BASKET"]["path"], tag + " not showing ORIGINAL basket PNG")
			# The authored region must contain EVERY nontransparent pixel of the
			# original image; smaller region rectangles silently cut off legs.
			_check(body.region_enabled and body.region_rect == alpha["BODY"]["region"], tag + " body region crops original PNG alpha/feet")
			_check(basket.region_enabled and basket.region_rect == alpha["BASKET"]["region"], tag + " basket region crops original PNG hands")
			var expected: Dictionary = original_transforms[name]
			_check(_near(body.position, expected["body_position"]) and _near(basket.position, expected["basket_position"]), tag + " runtime changed editor-authored body/basket offsets")
			_check(_near(body.scale, expected["body_scale"]) and _near(basket.scale, expected["basket_scale"]), tag + " runtime changed editor-authored Body/Basket scales")
			_check(_near(group.position, expected["group_position"]), tag + " runtime changed editor-authored group position")
			var body_rect := _screen_rect(body)
			var basket_rect := _screen_rect(basket)
			_check(_inside(frame, body_rect), tag + " ENTIRE original body/legs clipped: " + str(body_rect))
			_check(_inside(frame, basket_rect), tag + " ENTIRE original basket clipped: " + str(basket_rect))
			_check(body_rect.end.y >= frame.end.y * 0.80 and body_rect.end.y <= frame.end.y - 4.0, tag + " original feet not fully framed near bottom")
			_check(body_rect.position.y < basket_rect.position.y, tag + " body not behind basket")
			_check(basket_rect.intersects(body_rect), tag + " original body and basket separated")
			_check(absf(basket_rect.get_center().x - body_rect.get_center().x) <= body_rect.size.x * 0.24, tag + " basket off-center from character")
			_check(body.z_index + group.z_index < layer.z_index and layer.z_index < basket.z_index + group.z_index, tag + " incorrect body/collected words/basket layering")
			for other in NAMES:
				if other == name:
					continue
				var other_node := game.get_node(other) as Node2D
				_check(not other_node.visible, tag + " old " + other + " still visible")
			for count in range(4):
				var words: Array = game.get("collected_words")
				words.clear()
				for n in range(count):
					words.append(["APPLE", "GARDEN", "TEACHER"][n])
				game.call("_refresh_collected_words")
				var live := 0
				for child in layer.get_children():
					if child.is_queued_for_deletion() or not child is TextureRect:
						continue
					live += 1
					var rect := (child as TextureRect).get_global_rect()
					_check(rect.get_center().y > body_rect.position.y + body_rect.size.y * 0.30, tag + " collected fruit obscures face")
					_check(rect.position.y < basket_rect.end.y + 10 and rect.end.y > basket_rect.position.y - 85, tag + " collected fruit misses basket")
					_check(rect.position.x >= basket_rect.position.x - 45 and rect.end.x <= basket_rect.end.x + 45, tag + " collected fruit outside basket horizontally")
				_check(live == count and live <= 3, tag + " stale fruit when basket count=" + str(count))
			game.call("_reset_round_geometry")
			var words_after: Array = game.get("collected_words")
			words_after.clear()
			game.call("_refresh_collected_words")
			_check(layer.get_child_count() == 0, tag + " reset left collected fruit behind")
			_check(_near(body.position, expected["body_position"]) and _near(basket.position, expected["basket_position"]), tag + " reset moved original sprites")
			print(tag, " original_body=", body_rect, " original_basket=", basket_rect)
	game.queue_free()
	viewport.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("CATCH ORIGINAL CHARACTER REVERT: ", "PASS (8 selections and resets)" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)


func _near(value: Vector2, expected: Vector2) -> bool:
	return value.distance_to(expected) < 0.75


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


func _inside(frame: Rect2, rect: Rect2) -> bool:
	return rect.size.x > 0.0 and rect.size.y > 0.0 and rect.position.x >= frame.position.x - 1.0 and rect.position.y >= frame.position.y - 1.0 and rect.end.x <= frame.end.x + 1.0 and rect.end.y <= frame.end.y + 1.0


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
