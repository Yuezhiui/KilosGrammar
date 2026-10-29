extends SceneTree

# Regression: lower only the collected RED word apples, not the user's fixed
# five animal rigs or their independently authored Body/Basket transforms.
# Run with Godot 4.7.2 --headless --path . --script res://tools/test_catch_collected_apple_placement_20261029.gd
const GAME = preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const CHARACTERS := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const EPSILON := 0.3

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for size in SIZES:
		root.size = size
		root.content_scale_size = size
		for kind in CHARACTERS:
			await _verify(size, kind)
	_finish()


func _verify(size: Vector2i, kind: String) -> void:
	var tag := "%s at %s" % [kind, size]
	var game := GAME.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity": "Catch the Word", "catch_character": kind,
		"topic": "Noun", "game_mode": "Seconds", "catch_map": "City"})
	game.set_process(false)
	await process_frame
	var layer := game.get_node("CollectedWords") as Node2D
	var marker := game.get_node("CollectedApplePlacement") as Marker2D
	var root_poses: Dictionary = {}
	for name in CHARACTERS:
		var rig := game.get_node(name) as Node2D
		root_poses[name] = {"position": rig.position, "scale": rig.scale,
			"body_position": (rig.get_node("Body") as Sprite2D).position,
			"body_scale": (rig.get_node("Body") as Sprite2D).scale,
			"basket_position": (rig.get_node("Basket") as Sprite2D).position,
			"basket_scale": (rig.get_node("Basket") as Sprite2D).scale}
	var editor_delta: Vector2 = marker.position - layer.position
	_check(marker.get_parent() == game and layer.get_parent() == game,
		tag + ": editable marker and layer are scene-authored siblings")
	_check(Vector2(game.collected_apple_placement_offset).is_finite() and
		Vector2(game.collected_apple_placement_offset).length() < 100.0,
		tag + ": marker displacement read from editor without hardcoded coordinates")
	var words: Array = game.collected_words
	words.clear()
	words.append_array(["APPLE", "TEACHER", "RIVER"])
	game.collected_apple_placement_offset = Vector2.ZERO
	game._refresh_collected_words()
	var previous: Dictionary = {}
	for apple in layer.get_children():
		previous[apple.name] = {"position": apple.position, "size": apple.size}
	_check(previous.size() == 3, tag + ": baseline has exactly three half apples")
	var shift := Vector2(13, -9)
	game.collected_apple_placement_offset = shift
	game._refresh_collected_words()
	_check(layer.get_child_count() == 3, tag + ": refreshing never duplicates apples")
	var basket_size := game._basket_visual_size() as Vector2
	var width: float = basket_size.x * game.caught_half_apple_basket_width_ratio
	var spacing: float = width * game.caught_half_apple_spacing_ratio
	var rim: float = game._basket_local_center().y - basket_size.y * 0.5
	for i in range(3):
		var apple := layer.get_child(i) as TextureRect
		var before: Dictionary = previous[apple.name]
		_check(apple.position.distance_to(Vector2(before["position"]) + shift) < EPSILON,
			tag + ": " + apple.name + " follows editable marker shift in X and Y")
		_check(apple.size.distance_to(Vector2(before["size"])) < EPSILON
			and apple.size.x <= basket_size.x * 0.28 + EPSILON
			and width * (1.0 + 2.0 * game.caught_half_apple_spacing_ratio) <= basket_size.x + EPSILON,
			tag + ": " + apple.name + " retains the valid Inspector max and still fits the basket")
		_check(apple.texture.resource_path.ends_with("APPLE HALF SEAMLESS.png") and
			apple.texture.get_size() == Vector2(307, 190) and apple.material is ShaderMaterial and
			(apple.material as ShaderMaterial).shader == game.CAUGHT_APPLE_FRONT_CLIP,
			tag + ": " + apple.name + " original half PNG, apple-only wicker clip")
		_check(apple.get_child_count() == 0, tag + ": " + apple.name + " unlabelled")
		var expected: Vector2 = Vector2(game._basket_local_center().x + (i - 1) * spacing - width * 0.5,
				rim - apple.size.y * game.HALF_APPLE_PAINTED_HEIGHT_RATIO) + shift
		_check(apple.position.distance_to(expected) < EPSILON,
			tag + ": " + apple.name + " evenly aligned to real wicker lip")
	var falling: Control = game._create_tile_node("TEACHER", Color.WHITE)
	_check((falling.get_node("WordLabel") as Label).text == "TEACHER" and
		(falling.get_node("AppleSprite") as TextureRect).texture != game.HALF_APPLE_TEXTURE,
		tag + ": falling apple retains full word-labelled gameplay art")
	falling.queue_free()
	for name in CHARACTERS:
		var rig := game.get_node(name) as Node2D
		var before: Dictionary = root_poses[name]
		_check(rig.position == before["position"] and rig.scale == before["scale"],
			tag + ": " + name + " root position and size unchanged")
		_check((rig.get_node("Body") as Sprite2D).position == before["body_position"]
			and (rig.get_node("Body") as Sprite2D).scale == before["body_scale"],
			tag + ": " + name + " body position and size unchanged")
		_check((rig.get_node("Basket") as Sprite2D).position == before["basket_position"]
			and (rig.get_node("Basket") as Sprite2D).scale == before["basket_scale"],
			tag + ": " + name + " basket and arms position and size unchanged")
	game.queue_free()
	await process_frame


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		printerr("COLLECTED APPLE PLACEMENT: ", detail)


func _finish() -> void:
	print("CATCH COLLECTED APPLE PLACEMENT: %s checks=%d failures=%d cases=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(),
		CHARACTERS.size() * SIZES.size()
	])
	quit(0 if failures.is_empty() else 1)
