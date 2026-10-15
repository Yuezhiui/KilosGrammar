extends SceneTree

const SCENE := preload("res://ui/minigames/catch_word.tscn")
const CHARACTERS := ["Boy", "Girl", "Grandma", "Grandpa"]
const MAPS := ["City", "Forest", "Mountain"]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for character in CHARACTERS:
		for map_name in MAPS:
			var game := SCENE.instantiate() as Control
			root.add_child(game)
			game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			game.call("set_context", {"activity": "Catch the Word", "topic": "Noun", "game_mode": "Seconds", "catch_character": character, "catch_map": map_name})
			game.set_process(false)
			await process_frame
			var rig := game.get_node("CharacterRig") as Node2D
			var body := game.get_node("CharacterRig/Body") as Sprite2D
			var basket := game.get_node("CharacterRig/Basket") as Sprite2D
			var body_rect := _visual_rect(rig, body)
			var basket_rect := _visual_rect(rig, basket)
			var tag := "%s/%s" % [character, map_name]
			_check(body.texture != null and basket.texture != null, tag + " textures missing")
			# Original 0.63-height framing intentionally puts head near y=395.
			_check(body_rect.position.y >= 350.0 and body_rect.position.y <= 430.0, tag + " original head framing drift: " + str(body_rect))
			_check(body_rect.end.y > 720.0, tag + " feet visible: " + str(body_rect))
			_check(basket_rect.position.y > body_rect.position.y + 90.0, tag + " basket above head")
			_check(basket_rect.position.y < 720.0 and basket_rect.end.y > 400.0, tag + " basket off screen")
			_check(basket_rect.position.x >= -5.0 and basket_rect.end.x <= 1285.0, tag + " basket horizontally clipped")
			var original_body := "res://WordCatcherCharacters/%s BODY.png" % character.to_upper()
			var original_basket := "res://WordCatcherCharacters/%s BASKET.png" % character.to_upper()
			_check(body.texture.resource_path == original_body and basket.texture.resource_path == original_basket, tag + " not original textures")
			var layer := game.get_node_or_null("CharacterRig/CollectedWords")
			if layer != null:
				for count in range(4):
					var words: Array = game.get("collected_words")
					words.clear()
					for index in range(count):
						words.append(["APPLE", "GARDEN", "TEACHER"][index])
					game.call("_refresh_collected_words")
					var apples := 0
					for child in layer.get_children():
						if child is TextureRect and child.name.begins_with("CaughtApple") and not child.is_queued_for_deletion():
							apples += 1
							var apple_rect := Rect2(rig.position + child.position, child.size)
							_check(apple_rect.position.y + apple_rect.size.y * 0.20 > body_rect.position.y + body_rect.size.y * 0.29, tag + " red apple overlaps head: " + str(apple_rect))
							_check(apple_rect.position.y < basket_rect.end.y and apple_rect.end.y > basket_rect.position.y - 85.0, tag + " apple misses basket: " + str(apple_rect))
							_check(apple_rect.position.x > basket_rect.position.x - 35.0 and apple_rect.end.x < basket_rect.end.x + 35.0, tag + " apple outside basket horizontally: " + str(apple_rect))
							_check(child.get_child_count() > 0 and child.get_child(0) is Label, tag + " apple word label missing")
					_check(apples == count and apples <= 3, tag + " expected " + str(count) + " basket apples, got " + str(apples))
			else:
				_check(false, tag + " collected word layer missing")
			print(tag, " body=", body_rect, " basket=", basket_rect)
			root.remove_child(game)
			game.queue_free()
			await process_frame
	if failures.is_empty():
		print("PASS: 12 character/map alignment cases")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _visual_rect(rig: Node2D, sprite: Sprite2D) -> Rect2:
	var local := sprite.get_rect()
	return Rect2(rig.position + sprite.position + local.position * sprite.scale, local.size * sprite.scale)

func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
