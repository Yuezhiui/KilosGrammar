extends SceneTree

const SCENE := preload("res://ui/minigames/catch_word.tscn")
const SIZES := [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]
const CHARACTERS := ["Boy", "Girl", "Grandma", "Grandpa"]
const WORDS := ["APPLE", "GARDEN", "TEACHER"]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for resolution in SIZES:
		root.size = resolution
		for character in CHARACTERS:
			var game := SCENE.instantiate() as Control
			root.add_child(game)
			game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			game.call("set_context", {"activity":"Catch the Word", "topic":"Noun", "game_mode":"Seconds", "catch_character":character, "catch_map":"City"})
			game.set_process(false)
			await process_frame
			var rig := game.get_node("CharacterRig") as Node2D
			var body := rig.get_node("Body") as Sprite2D
			var basket := rig.get_node("Basket") as Sprite2D
			var layer := rig.get_node("CollectedWords") as Node2D
			var body_rect := _sprite_rect(body)
			var basket_rect := _sprite_rect(basket)
			var tag: String = "%s %s" % [resolution, character]
			print(tag, " BODY=", body_rect, " BASKET=", basket_rect, " scale=", body.scale, "/", basket.scale)
			_check(body.texture != null and basket.texture != null, tag + " missing sprite")
			_check(body.z_index < layer.z_index and layer.z_index < basket.z_index, tag + " incorrect layers")
			for count in range(4):
				var words: Array = game.get("collected_words")
				words.clear()
				for index in range(count):
					words.append(WORDS[index])
				game.call("_refresh_collected_words")
				var live := 0
				for child in layer.get_children():
					if child.is_queued_for_deletion() or not child is TextureRect:
						continue
					live += 1
					var rect := Rect2(rig.global_position + child.position, child.size)
					var label := child.get_child(0) as Label if child.get_child_count() > 0 else null
					print("  count=", count, " apple=", child.name, " rect=", rect, " label=", label.text if label else "MISSING")
					_check(label != null and not label.text.is_empty(), tag + " missing apple word")
					# The apple texture's upper ~20% is leaf/stem, not red fruit.
					# Compare the red body against the approximate head boundary.
					var head_bottom := body_rect.position.y + body_rect.size.y * 0.29
					var red_top := rect.position.y + rect.size.y * 0.20
					_check(red_top >= head_bottom, tag + " red fruit obscures head (red_top=" + str(red_top) + ", head_bottom=" + str(head_bottom) + ")")
					if label != null:
						var label_top := rect.position.y + label.position.y
						_check(label_top < basket_rect.position.y + basket_rect.size.y * 0.50, tag + " word too low behind basket rim")
					_check(rect.position.y < basket_rect.end.y and rect.end.y > basket_rect.position.y, tag + " fruit not overlapping basket")
					_check(rect.position.x > basket_rect.position.x - 30 and rect.end.x < basket_rect.end.x + 30, tag + " fruit outside basket width")
				_check(live == count, tag + " count " + str(count) + " has " + str(live) + " fruit")
			root.remove_child(game)
			game.queue_free()
			await process_frame
	for failure in failures:
		push_error(failure)
	print("FRUIT COMPOSITION: ", "PASS" if failures.is_empty() else "%d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _sprite_rect(sprite: Sprite2D) -> Rect2:
	var rect := sprite.get_rect()
	return Rect2(sprite.global_position + rect.position * sprite.global_scale, rect.size * sprite.global_scale)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
