extends SceneTree
## Real-scene visual contract for the seam-only half-apple correction.
## No character positions, marker coordinates, physics or classroom data edits.
const GAME := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const SOURCE := preload("res://Components/Gameplay/Catch the Word/Items/APPLE HALF.png")
const FILLED := preload("res://Components/Gameplay/Catch the Word/Items/APPLE HALF SEAMLESS.png")
const ANIMALS := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const SIZES := [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]
var checked := 0
var failed: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var base := SOURCE.get_image()
	var fixed := FILLED.get_image()
	_check(base.get_size() == Vector2i(307, 190) and fixed.get_size() == base.get_size(),
		"seam-only image keeps original 307x190 proportions")
	for y in range(169):
		for x in range(307):
			if base.get_pixel(x, y) != fixed.get_pixel(x, y):
				_check(false, "original upper art changed at %d,%d" % [x,y])
				_finish()
				return
	_check(true, "every upper apple/stem/leaf pixel identical to original supplied PNG")
	_check(base.get_pixel(150, 185).a < 0.01 and fixed.get_pixel(150, 185).a > 0.95,
		"formerly transparent strip now has seamless red edge")
	for resolution in SIZES:
		root.size = resolution
		root.content_scale_size = resolution
		for animal in ANIMALS:
			await _case(resolution, animal)
	_finish()


func _case(size: Vector2i, animal: String) -> void:
	var tag := "%s %s" % [animal, size]
	var game := GAME.instantiate() as Control
	var original := {}
	for kind in ANIMALS:
		var root_rig := game.get_node(kind) as Node2D
		original[kind] = [
			root_rig.position, root_rig.scale,
			(root_rig.get_node("Body") as Sprite2D).position,
			(root_rig.get_node("Body") as Sprite2D).scale,
			(root_rig.get_node("Basket") as Sprite2D).position,
			(root_rig.get_node("Basket") as Sprite2D).scale
		]
	var marker := game.get_node("CollectedApplePlacement") as Marker2D
	var original_marker := marker.position
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity":"Catch the Word", "topic":"Noun",
		"game_mode":"Seconds", "difficulty":"Easy",
		"catch_character":animal, "catch_map":"City"})
	game.set_process(false)
	await process_frame
	var layer := game.get_node("CollectedWords") as Node2D
	var basket := (game.get_node(animal) as Node2D).get_node("Basket") as Sprite2D
	_check(layer.z_index < basket.z_index, tag + " wicker rim renders over collected fruit")
	var words: Array = game.collected_words
	words.clear()
	words.append_array(["apple","river","school"])
	game._refresh_collected_words()
	_check(layer.get_child_count() == 3, tag + " three evenly composed collected apples")
	var width: float = game._basket_visual_size().x * game.caught_half_apple_basket_width_ratio
	var spacing: float = width * game.caught_half_apple_spacing_ratio
	var rim: float = game._basket_local_center().y - game._basket_visual_size().y * 0.5
	for index in range(3):
		var fruit := layer.get_child(index) as TextureRect
		_check(fruit.texture == FILLED and fruit.material is ShaderMaterial
			and (fruit.material as ShaderMaterial).shader == game.CAUGHT_APPLE_FRONT_CLIP
			and fruit.z_index > (basket.z_index - layer.z_index),
			tag + " fruit %d uses original-top half-art with apple-only front rim masking" % index)
		var desired: Vector2 = Vector2(game._basket_local_center().x + (index - 1) * spacing - width * 0.5,
			rim - fruit.size.y * game.HALF_APPLE_PAINTED_HEIGHT_RATIO) + game.collected_apple_placement_offset
		_check(fruit.position.distance_to(desired) < 0.1,
			tag + " fruit %d aligns filled red bottom to rim without changing marker" % index)
		_check(absf(fruit.size.x - width) < 0.1, tag + " fruit %d preserves author-sized width" % index)
	_check(marker.position == original_marker, tag + " editor-authored apple placement untouched")
	var expected_scale: float = minf(float(size.x) / 1280.0, float(size.y) / 720.0)
	for kind in ANIMALS:
		var rig := game.get_node(kind) as Node2D
		var actual := [
			(rig.get_node("Body") as Sprite2D).position,
			(rig.get_node("Body") as Sprite2D).scale,
			(rig.get_node("Basket") as Sprite2D).position,
			(rig.get_node("Basket") as Sprite2D).scale
		]
		_check(actual == original[kind].slice(2, 6),
			tag + " %s Body/Basket authored local positions and scales intact" % kind)
		_check(rig.scale.is_equal_approx(original[kind][1] * expected_scale),
			tag + " %s root respects only intentional viewport scaling" % kind)
		if kind != animal:
			_check(rig.position == original[kind][0],
				tag + " inactive %s authored root position intact" % kind)
	game.queue_free()
	await process_frame


func _check(ok: bool, reason: String) -> void:
	checked += 1
	if not ok:
		failed.append(reason)


func _finish() -> void:
	print("CATCH APPLE SEAM QA: %s checks=%d failures=%d 15 animal/resolution cases" %
		["PASS" if failed.is_empty() else "FAIL", checked, failed.size()])
	for reason in failed:
		printerr("CATCH APPLE SEAM QA: ", reason)
	quit(0 if failed.is_empty() else 1)
