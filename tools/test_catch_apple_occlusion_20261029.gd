extends SceneTree

# Focused five-animal Catch visual regression. Headless tests structural and
# gameplay contracts; graphical gl_compatibility run also renders a real alpha
# mask probe and screenshots at 1280, 1600 and 1920 in user://.
# Godot 4.7.2 --path . --rendering-method gl_compatibility \
#   --script res://tools/test_catch_apple_occlusion_20261029.gd

const GAME := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const CHARACTERS := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const WORDS := ["APPLE", "GARDEN", "TEACHER"]
const TOLERANCE := 0.02

var checks := 0
var failures: Array[String] = []
var screenshots := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var graphical := DisplayServer.get_name() != "headless"
	for dimensions in SIZES:
		root.size = dimensions
		root.content_scale_size = dimensions
		if graphical:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(dimensions)
		await process_frame
		for animal in CHARACTERS:
			await _case(dimensions, animal, graphical)
	if graphical:
		await _render_real_half_alpha()
	for problem in failures:
		push_error("CATCH APPLE OCCLUSION: " + problem)
	print("CATCH APPLE OCCLUSION: %s / %d checks / 15 character cases / %d screenshots" % [
		"PASS" if failures.is_empty() else "FAIL %d" % failures.size(), checks, screenshots])
	quit(0 if failures.is_empty() else 1)


func _case(dimensions: Vector2i, animal: String, graphical: bool) -> void:
	var tag := "%s %dx%d" % [animal, dimensions.x, dimensions.y]
	var game := GAME.instantiate() as Control
	_check(game != null, tag + " scene instantiates")
	if game == null:
		return
	var scene_authored: Dictionary = {}
	for name in CHARACTERS:
		var rig := game.get_node(name) as Node2D
		var body := rig.get_node("Body") as Sprite2D
		var basket := rig.get_node("Basket") as Sprite2D
		scene_authored[name] = {"body": body.position, "basket": basket.position,
			"body_scale": body.scale, "basket_scale": basket.scale}
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity": "Catch the Word", "topic": "Noun",
		"difficulty": "Normal", "game_mode": "Seconds",
		"catch_character": animal, "catch_map": "City"})
	game.set_process(false)
	await process_frame
	var rig := game.get_node(animal) as Node2D
	var basket := rig.get_node("Basket") as Sprite2D
	var body := rig.get_node("Body") as Sprite2D
	var layer := game.get_node("CollectedWords") as Node2D
	_check(body.z_index == 0 and basket.z_index == 2 and layer.z_index == 1,
		tag + " current Body0 Collected1 Basket2 z-order hides repaired lower seam")
	_check(basket.texture != null and basket.texture.resource_path.ends_with(animal.to_upper() + " BASKET.png"),
		tag + " unchanged original basket PNG")
	_check(game._basket_rect().has_area(), tag + " original basket collision stays active")
	var half := load("res://Components/Gameplay/Catch the Word/Items/APPLE HALF SEAMLESS.png") as Texture2D
	_check(half != null and half.get_size() == Vector2(307, 190), tag + " original 307x190 half artwork")
	var words: Array = game.collected_words
	words.clear()
	words.append_array(WORDS)
	game._refresh_collected_words()
	_check(layer.get_child_count() == 3, tag + " exactly three collected apples")
	var basket_size := game._basket_visual_size() as Vector2
	var apple_width: float = basket_size.x * game.caught_half_apple_basket_width_ratio
	var apple_size := Vector2(apple_width, apple_width * 190.0 / 307.0)
	var rim: float = game._basket_local_center().y - basket_size.y * 0.5
	var spacing: float = apple_width * game.caught_half_apple_spacing_ratio
	for index in range(3):
		var apple := layer.get_child(index) as TextureRect
		_check(apple != null, tag + " collected apple TextureRect")
		if apple == null:
			continue
		_check(apple.texture == half and apple.texture.resource_path.ends_with("APPLE HALF SEAMLESS.png"),
			tag + " derived seamless half PNG, source top preserved")
		# The Inspector allows exactly 0.28 basket width. Preserve the user's
		# maximum authored size rather than treating the permitted endpoint
		# as an artwork regression.
		_check(apple.size.distance_to(apple_size) < 0.05 and apple.size.x <= basket_size.x * 0.28 + 0.05
			and apple_width * (1.0 + 2.0 * game.caught_half_apple_spacing_ratio) <= basket_size.x + 0.05,
			tag + " three proportional half apples fit the unchanged basket")
		_check(apple.material is ShaderMaterial and apple.get_child_count() == 0 and
			(apple.material as ShaderMaterial).shader == game.CAUGHT_APPLE_FRONT_CLIP and
			apple.z_index + layer.z_index > basket.z_index,
			tag + " collected-only woodline shader over uniform; no word label")
		var clip_uv: float = float((apple.material as ShaderMaterial).get_shader_parameter("wicker_top_uv"))
		_check(clip_uv > 0.1 and clip_uv < 0.99,
			tag + " collected fruit foreground stops at real wood top, leaving basket fully visible")
		var expected: Vector2 = Vector2(game._basket_local_center().x + (index - 1) * spacing - apple_width * 0.5,
			rim - apple_size.y * game.HALF_APPLE_PAINTED_HEIGHT_RATIO) + game.collected_apple_placement_offset
		_check(apple.position.distance_to(expected) < 0.05,
			tag + " evenly spaced artwork meets wicker rim")
		_check(apple.get_global_rect().intersects(_sprite_rect(basket).grow(95.0)),
			tag + " actual half fruit overlaps selected basket region")
	var falling: Control = game._create_tile_node("FALLING", Color.WHITE) as Control
	var falling_sprite := falling.get_node_or_null("AppleSprite") as TextureRect
	_check(falling_sprite != null and falling_sprite.material == null and falling_sprite.texture != half
		and (falling.get_node_or_null("WordLabel") as Label).text == "FALLING",
		tag + " falling word apple has NO collected-apple clip material")
	falling.queue_free()
	# Never nudge even a temporary QA copy of the locked Basket. Collision
	# must instead remain centered on its original authored sprite position.
	var collision := game._basket_rect() as Rect2
	var authored_collision_center: Vector2 = Vector2(game.basket_x, game._character_baseline_y()) \
		+ Vector2(game._basket_world_offset()) - Vector2(0.0, game._basket_world_size().y * 0.05)
	_check(collision.has_area() and
		collision.get_center().distance_to(authored_collision_center) < 0.05,
		tag + " unchanged authored basket is the gameplay collision center")
	for name in CHARACTERS:
		var current := game.get_node(name) as Node2D
		var parts: Dictionary = scene_authored[name]
		_check((current.get_node("Body") as Sprite2D).position.is_equal_approx(parts["body"])
			and (current.get_node("Body") as Sprite2D).scale.is_equal_approx(parts["body_scale"])
			and (current.get_node("Basket") as Sprite2D).position.is_equal_approx(parts["basket"])
			and (current.get_node("Basket") as Sprite2D).scale.is_equal_approx(parts["basket_scale"]),
			tag + " every artist-authored Body/Basket transform unchanged")
	if graphical:
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		var path := "user://catch_apple_occlusion_%s_%dx%d.png" % [animal.to_lower(), dimensions.x, dimensions.y]
		_check(picture.get_size() == dimensions and picture.save_png(path) == OK,
			tag + " graphical screenshot recorded")
		print("SCREENSHOT: ", ProjectSettings.globalize_path(path))
		screenshots += 1
	game.queue_free()
	await process_frame


func _render_real_half_alpha() -> void:
	var source := load("res://Components/Gameplay/Catch the Word/Items/APPLE HALF.png") as Texture2D
	var image := source.get_image()
	_check(image.get_size() == Vector2i(307, 190), "Actual RGBA half apple image dimensions")
	_check(image.get_format() == Image.FORMAT_RGBA8, "Actual half apple is RGBA8")
	var transparent := 0
	var opaque := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var alpha := image.get_pixel(x, y).a
			if alpha < 0.02:
				transparent += 1
			elif alpha > 0.95:
				opaque += 1
	_check(transparent > 2000 and opaque > 2000, "Real half artwork has transparent outside and opaque fruit")
	var stage := SubViewport.new()
	stage.size = Vector2i(307, 190)
	stage.transparent_bg = true
	stage.disable_3d = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(stage)
	var apple := TextureRect.new()
	apple.texture = source
	apple.size = Vector2(307, 190)
	apple.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	apple.stretch_mode = TextureRect.STRETCH_SCALE
	stage.add_child(apple)
	await process_frame
	await RenderingServer.frame_post_draw
	var result := stage.get_texture().get_image()
	_check(result.get_size() == image.get_size(), "REAL GPU: half PNG rendered at native dimensions")
	_check(result.get_pixel(153, 95).a > 0.5, "REAL GPU: native half fruit painted at center")
	_check(result.get_pixel(0, 0).a < 0.02, "REAL GPU: transparent exterior remains transparent")
	stage.queue_free()
	await process_frame


func _sprite_rect(sprite: Sprite2D) -> Rect2:
	return Rect2(sprite.global_position + sprite.get_rect().position * sprite.global_scale,
		sprite.get_rect().size * sprite.global_scale)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
