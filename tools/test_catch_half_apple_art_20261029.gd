extends SceneTree

# Real Catch scene + supplied NEW half-apple artwork, no fake PNG or gameplay.
# Headless: Godot --headless --path . --script res://tools/test_catch_half_apple_art_20261029.gd
# Native: Godot --path . --rendering-method gl_compatibility --script res://tools/test_catch_half_apple_art_20261029.gd
const GAME := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const ORIGINAL_HALF := preload("res://Components/Gameplay/Catch the Word/Items/APPLE HALF.png")
const HALF := preload("res://Components/Gameplay/Catch the Word/Items/APPLE HALF SEAMLESS.png")
const ORIGINAL_FALLING := preload("res://Components/Gameplay/Catch the Word/Items/Apple.png")
const CHARACTERS := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const SIZES := [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]
const WORDS := ["APPLE", "RIVER", "TEACHER", "GARDEN"]

var checks := 0
var failures: Array[String] = []
var screenshots := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(HALF.get_size() == Vector2(307, 190), "seam-fixed 307x190 RGBA proportions remain")
	var source_pixels := ORIGINAL_HALF.get_image()
	var repaired_pixels := HALF.get_image()
	_check(source_pixels.get_pixel(150, 120).a > 0.95 and
		source_pixels.get_pixel(150, 170).a < 0.01 and
		source_pixels.get_pixel(0, 0).a < 0.01,
		"original user PNG is unchanged, including transparent lower gap")
	_check(repaired_pixels.get_pixel(150, 185).a > 0.95 and repaired_pixels.get_pixel(0, 0).a < 0.01,
		"derived image fills only the lower red seam; corners stay transparent")
	for dimensions in SIZES:
		root.size = dimensions
		root.content_scale_size = dimensions
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(dimensions)
		await process_frame
		for character in CHARACTERS:
			await _verify(dimensions, character)
	print("CATCH HALF APPLE ART 20261029: %s (%d checks, %d failures, 15 scene cases, %d screenshots)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), screenshots])
	quit(0 if failures.is_empty() else 1)


func _verify(dimensions: Vector2i, character: String) -> void:
	var tag := "%s %dx%d" % [character, dimensions.x, dimensions.y]
	var game := GAME.instantiate() as Control
	var original_marker := (game.get_node("CollectedApplePlacement") as Marker2D).position
	var original_layer := (game.get_node("CollectedWords") as Node2D).position
	var original_parts := {}
	for animal in CHARACTERS:
		var rig := game.get_node(animal) as Node2D
		var body := rig.get_node("Body") as Sprite2D
		var basket := rig.get_node("Basket") as Sprite2D
		original_parts[animal] = {"body_position":body.position, "body_scale":body.scale,
			"basket_position":basket.position, "basket_scale":basket.scale,
			"body_texture":body.texture, "basket_texture":basket.texture}
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity":"Catch the Word", "topic":"Noun", "difficulty":"Normal",
		"game_mode":"Seconds", "catch_character":character, "catch_map":"City"})
	game.set_process(false)
	await process_frame
	var rig := game.get_node(character) as Node2D
	var body := rig.get_node("Body") as Sprite2D
	var basket := rig.get_node("Basket") as Sprite2D
	var layer := game.get_node("CollectedWords") as Node2D
	var marker := game.get_node("CollectedApplePlacement") as Marker2D
	_check(body.z_index == 0 and basket.z_index == 2 and layer.z_index == 1,
		tag + " teacher-authored BODY 0 COLLECTED 1 BASKET 2 hides seam")
	_check(marker.position == original_marker and
		(original_marker - original_layer - Vector2(game.collected_apple_placement_offset)).length() < 0.1,
		tag + " teacher's saved marker offset preserved, not reset")
	_check(game.caught_half_apple_basket_width_ratio >= 0.14 and game.caught_half_apple_basket_width_ratio <= 0.28,
		tag + " small fruit size exposed to Inspector")
	_check(game._basket_rect().has_area(), tag + " original true basket hitbox remains")
	_check(layer.get_child_count() == 0, tag + " empty basket displays zero half apples")
	var initial_tiles: Array = game.falling_tiles
	var valid_falling: Dictionary = {}
	for tile in initial_tiles:
		if bool(tile.get("matching", false)):
			valid_falling = tile
			break
	_check(not valid_falling.is_empty(), tag + " genuine matching falling apple exists")
	if not valid_falling.is_empty():
		var old_score := int(game.score)
		var old_attempts := int(game.attempts)
		game._handle_catch(valid_falling)
		_check(int(game.score) == old_score + 100 and int(game.attempts) == old_attempts + 1
			and game.collected_words.size() == 1,
			tag + " genuine grammar match still awards exactly +100 and one caught apple")
	_check(layer.get_child_count() == 1, tag + " correct answer paints one new half apple")
	# First word stays in gameplay state. Force the remaining two *display*
	# entries to inspect all three visual slots without fabricating collisions.
	var words: Array = game.collected_words
	for count in [1, 2, 3, 4]:
		words.clear()
		for i in range(count):
			words.append(WORDS[i])
		game._refresh_collected_words()
		var expected := mini(count, 3)
		_check(layer.get_child_count() == expected,
			tag + " count=%d paints precisely %d half apples, never extra nodes" % [count,expected])
		var previous_x := -INF
		var basket_size: Vector2 = game._basket_visual_size()
		var center: Vector2 = game._basket_local_center()
		var rim_y := center.y - basket_size.y * 0.5
		var width := basket_size.x * float(game.caught_half_apple_basket_width_ratio)
		var visible_edge_ratio := float(game.HALF_APPLE_PAINTED_HEIGHT_RATIO)
		for index in range(expected):
			var apple := layer.get_child(index) as TextureRect
			_check(apple != null, tag + " actual unlabelled half-apple TextureRect child")
			if apple == null:
				continue
			_check(apple.name == "CaughtApple%d" % (index+1) and apple.get_child_count() == 0,
				tag + " no word label, UV-mask child or other decoration")
			_check(apple.texture == HALF and apple.material is ShaderMaterial and
				(apple.material as ShaderMaterial).shader == game.CAUGHT_APPLE_FRONT_CLIP,
				tag + " source-based half PNG with apple-only wicker-edge mask")
			_check(absf(apple.size.x-width) <= 0.025 and
				absf(apple.size.y-width*190.0/307.0) <= 0.025 and
				apple.size.x < basket_size.x * 0.29,
				tag + " original aspect ratio, consistent small size for all counts")
			_check(absf(apple.position.y + apple.size.y * visible_edge_ratio
				- rim_y - game.collected_apple_placement_offset.y) < 0.1,
				tag + " seam-filled red meets wicker rim plus authored marker offset")
			_check(apple.position.x > center.x - basket_size.x*0.44 and
				apple.position.x + apple.size.x < center.x + basket_size.x*0.44,
				tag + " each apple sits inside wicker opening and never overhangs side")
			if index > 0:
				_check(apple.position.x >= previous_x + apple.size.x - 0.05,
					tag + " ordered non-overlapping half apples allow Inspector spacing minimum")
			previous_x = apple.position.x
		if expected == 3:
			_check(float(game.score) == 100.0 and int(game.attempts) == 1,
				tag + " display refresh never mutates score or scoring attempts")
			var apples: Array = layer.get_children()
			_check(absf((apples[1] as Control).get_rect().get_center().x-center.x) < 0.25,
				tag + " center half apple aligned with selected basket center")
	# Test teacher-editable offset and independent Basket geometry responses.
	words.resize(3)
	game.collected_apple_placement_offset = Vector2(3, -4)
	game._refresh_collected_words()
	_check(layer.get_child_count() == 3 and
		absf((layer.get_child(1) as TextureRect).position.x + (layer.get_child(1) as TextureRect).size.x*0.5
			- game._basket_local_center().x - 3.0) < 0.25,
		tag + " editor placement marker offsets cluster independently")
	game.collected_apple_placement_offset = Vector2.ZERO
	game._refresh_collected_words()
	var old_hitbox := game._basket_rect() as Rect2
	basket.position.x += 8.0
	var new_hitbox := game._basket_rect() as Rect2
	game._refresh_collected_words()
	_check(absf(new_hitbox.get_center().x-old_hitbox.get_center().x) > 1.0 and
		absf((layer.get_child(1) as TextureRect).position.x + (layer.get_child(1) as TextureRect).size.x*0.5
			- game._basket_local_center().x) < 0.3,
		tag + " independently moved Basket moves collision AND half-apple cluster")
	basket.position.x -= 8.0
	game._refresh_collected_words()
	for animal in CHARACTERS:
		var current := game.get_node(animal) as Node2D
		var p: Dictionary = original_parts[animal]
		_check((current.get_node("Body") as Sprite2D).position.is_equal_approx(p["body_position"])
			and (current.get_node("Body") as Sprite2D).scale.is_equal_approx(p["body_scale"])
			and (current.get_node("Basket") as Sprite2D).position.is_equal_approx(p["basket_position"])
			and (current.get_node("Basket") as Sprite2D).scale.is_equal_approx(p["basket_scale"])
			and (current.get_node("Body") as Sprite2D).texture == p["body_texture"]
			and (current.get_node("Basket") as Sprite2D).texture == p["basket_texture"],
			tag + " original %s Body/Basket art, size and draggable position unchanged" % animal)
	var unmodified := game._create_tile_node("FALLING", Color.WHITE) as Control
	var sprite := unmodified.get_node("AppleSprite") as TextureRect
	_check(sprite.texture == game.gameplay_apple_texture and sprite.texture != HALF
		and sprite.material == null and unmodified.size == Vector2(106,109),
		tag + " falling real word apples remain full-size and unchanged")
	unmodified.queue_free()
	if DisplayServer.get_name() != "headless" and character in ["Lion", "Bear"]:
		game._clear_falling_tiles()
		game._clear_transient_effects()
		game._refresh_hud()
		for _j in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		var png := "user://catch_half_apple_%s_%dx%d.png" % [character.to_lower(),dimensions.x,dimensions.y]
		_check(picture.get_size() == dimensions and picture.save_png(png) == OK,
			tag + " native GPU captured entire gameplay with three small real half apples")
		print("HALF APPLE SCREENSHOT ", ProjectSettings.globalize_path(png))
		screenshots += 1
	game.queue_free()
	await process_frame


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("HALF APPLE QA FAIL: ", message)
