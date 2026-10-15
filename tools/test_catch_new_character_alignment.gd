extends SceneTree

const SCENE := preload("res://ui/minigames/catch_word.tscn")
const CHARACTERS := ["Boy", "Girl", "Grandma", "Grandpa"]
const MAPS := ["Forest", "City", "Mountain"]
const IMAGE_DIR := "res://ui/minigames/catch_hud/generated/character/"
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for character in CHARACTERS:
		var prefix: String = String(character).to_lower()
		for suffix in ["_body.png", "_basket_hands.png"]:
			var path: String = IMAGE_DIR + prefix + String(suffix)
			if not FileAccess.file_exists(path):
				print("PENDING PNG: ", path)
				continue
			var image := Image.load_from_file(path)
			print("PNG ", path, " size=", image.get_size(), " alpha_bbox=", image.get_used_rect())
	for character in CHARACTERS:
		for map_name in MAPS:
			var tag: String = String(character) + "/" + String(map_name)
			var game := SCENE.instantiate() as Control
			root.add_child(game)
			game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			game.call("set_context", {"activity":"Catch the Word", "topic":"Noun", "game_mode":"Seconds", "catch_character":character, "catch_map":map_name})
			game.set_process(false)
			await process_frame
			var rig := game.get_node("CharacterRig") as Node2D
			var body := rig.get_node("Body") as Sprite2D
			var basket := rig.get_node("Basket") as Sprite2D
			var fruit_layer := rig.get_node("CollectedWords") as Node2D
			var body_rect := _rect(body)
			var basket_rect := _rect(basket)
			print(tag, " body=", body_rect, " basket=", basket_rect, " scales=", body.scale, "/", basket.scale)
			check(body.texture != null and basket.texture != null, tag + " missing texture")
			check(body.z_index < fruit_layer.z_index and fruit_layer.z_index < basket.z_index, tag + " incorrect foreground layering")
			check(body_rect.position.y < 450 and body_rect.end.y > 700, tag + " body framing incorrect")
			check(basket_rect.position.y < 710 and basket_rect.end.y > 550, tag + " basket invisible")
			var words: Array = game.get("collected_words")
			words.clear()
			words.append_array(["APPLE", "GARDEN", "TEACHER"])
			game.call("_refresh_collected_words")
			await process_frame
			var live_count := 0
			for apple in fruit_layer.get_children():
				if apple.is_queued_for_deletion() or not apple is TextureRect:
					continue
				live_count += 1
				var apple_rect := Rect2(rig.global_position + apple.position, apple.size)
				check(apple_rect.position.y > body_rect.position.y + 90, tag + " fruit obscures face " + str(apple_rect))
				check(apple_rect.position.y < basket_rect.end.y and apple_rect.end.y > basket_rect.position.y - 70, tag + " fruit misses basket " + str(apple_rect))
				check(apple_rect.position.x >= basket_rect.position.x - 40 and apple_rect.end.x <= basket_rect.end.x + 40, tag + " fruit misses rim horizontally")
				check(apple.get_child_count() == 1 and apple.get_child(0) is Label, tag + " missing word label")
			check(live_count == 3, tag + " live collected apples=" + str(live_count))
			root.remove_child(game)
			game.queue_free()
			await process_frame
	if errors.is_empty():
		print("PASS: all 12 character/map layouts")
		quit(0)
	else:
		for error in errors:
			push_error(error)
		quit(1)

func _rect(sprite: Sprite2D) -> Rect2:
	var bounds := sprite.get_rect()
	return Rect2(sprite.global_position + bounds.position * sprite.global_scale, bounds.size * sprite.global_scale)

func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
