extends SceneTree

const SCENE := preload("res://ui/minigames/catch_word.tscn")
const NAMES := ["Boy", "Girl", "Grandma", "Grandpa"]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for name in NAMES:
		var body_path: String = "res://WordCatcherCharacters/%s BODY.png" % String(name).to_upper()
		var basket_path: String = "res://WordCatcherCharacters/%s BASKET.png" % String(name).to_upper()
		for path in [body_path, basket_path]:
			var img := Image.load_from_file(path)
			_check(not img.is_empty(), str(path) + " missing")
			if not img.is_empty():
				print("ORIGINAL ", path, " dimensions=", img.get_size(), " alpha=", img.get_used_rect())
		var game := SCENE.instantiate() as Control
		root.add_child(game)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game.call("set_context", {"activity":"Catch the Word", "topic":"Noun", "game_mode":"Seconds", "catch_character":name, "catch_map":"City"})
		game.set_process(false)
		await process_frame
		var rig := game.get_node("CharacterRig") as Node2D
		var body := rig.get_node("Body") as Sprite2D
		var basket := rig.get_node("Basket") as Sprite2D
		var layer := rig.get_node("CollectedWords") as Node2D
		var actual_body: String = body.texture.resource_path if body.texture else ""
		var actual_basket: String = basket.texture.resource_path if basket.texture else ""
		print(name, " selected=", actual_body, " | ", actual_basket)
		_check(actual_body == body_path, name + " NOT using original body")
		_check(actual_basket == basket_path, name + " NOT using original basket")
		var body_rect := _sprite_rect(body)
		var basket_rect := _sprite_rect(basket)
		print(name, " body_rect=", body_rect, " basket_rect=", basket_rect)
		_check(body_rect.position.y < basket_rect.position.y, name + " body not behind basket")
		_check(body_rect.end.y > 720.0, name + " lower body not hidden below viewport")
		_check(body.z_index < layer.z_index and layer.z_index < basket.z_index, name + " incorrect layer order")
		for cycle in range(3):
			for count in range(4):
				var words: Array = game.get("collected_words")
				words.clear()
				for index in range(count):
					words.append(["APPLE", "GARDEN", "TEACHER"][index])
				game.call("_refresh_collected_words")
				var live := 0
				for child in layer.get_children():
					if child.is_queued_for_deletion() or not child is TextureRect:
						continue
					live += 1
					var rect := Rect2(rig.global_position + child.position, child.size)
					var red_top := rect.position.y + rect.size.y * 0.20
					_check(red_top >= body_rect.position.y + body_rect.size.y * 0.29, name + " fruit overlaps approximate face")
					_check(rect.intersects(basket_rect), name + " fruit misses basket")
				_check(live == count and live <= 3, name + " stale fruit after cycle " + str(cycle))
		game.call("_reset_round_geometry")
		var words_after: Array = game.get("collected_words")
		words_after.clear()
		game.call("_refresh_collected_words")
		_check(layer.get_child_count() == 0, name + " restart left fruit")
		root.remove_child(game)
		game.queue_free()
		await process_frame
	for issue in failures:
		push_error(issue)
	print("ORIGINAL REVERT TEST: ", "PASS" if failures.is_empty() else str(failures.size()) + " FAILURES")
	quit(0 if failures.is_empty() else 1)

func _sprite_rect(sprite: Sprite2D) -> Rect2:
	var bounds := sprite.get_rect()
	return Rect2(sprite.global_position + bounds.position * sprite.global_scale, bounds.size * sprite.global_scale)

func _check(ok: bool, issue: String) -> void:
	if not ok:
		failures.append(issue)
