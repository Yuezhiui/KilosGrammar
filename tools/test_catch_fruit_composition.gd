extends SceneTree

# THREE small unlabelled half apples; their seam-extended lower red pixels sit
# BEHIND the original wicker rim. Body/basket positions stay editor-authored.
# Falling word apples are separate, still full-size and clearly labelled.
const SCENE := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const HALF := preload("res://Components/Gameplay/Catch the Word/Items/APPLE HALF SEAMLESS.png")
const SIZES := [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]
const CHARACTERS := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const WORDS := ["APPLE", "GARDEN", "TEACHER"]
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for resolution in SIZES:
		root.size = resolution
		root.content_scale_size = resolution
		for character in CHARACTERS:
			await _case(resolution, character)
	for failure in failures:
		push_error(failure)
	print("FRUIT COMPOSITION: %s checks=%d failures=%d animal_viewports=15" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _case(resolution: Vector2i, character: String) -> void:
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity":"Catch the Word", "topic":"Noun",
		"game_mode":"Seconds", "catch_character":character, "catch_map":"City"})
	game.set_process(false)
	await process_frame
	var group := game.get_node(character) as Node2D
	var body := group.get_node("Body") as Sprite2D
	var basket := group.get_node("Basket") as Sprite2D
	var layer := game.get_node("CollectedWords") as Node2D
	var basket_size := game._basket_visual_size() as Vector2
	var basket_center := game._basket_local_center() as Vector2
	var rim_y: float = basket_center.y - basket_size.y * 0.5
	var width: float = basket_size.x * game.caught_half_apple_basket_width_ratio
	var height: float = width * HALF.get_height() / HALF.get_width()
	var tag := "%s %s" % [resolution, character]
	_check(body.texture != null and basket.texture != null and
		basket.texture.resource_path.ends_with(character.to_upper() + " BASKET.png"),
		tag + " original independent character body and wicker basket are retained")
	_check(body.z_index == 0 and basket.z_index == 2 and layer.z_index == 1,
		tag + " editor-authored Body0, collected fruit1, wicker2 masks the seam")
	_check(game._basket_rect().has_area(), tag + " authored collision basket remains active")
	for count in range(4):
		game.collected_words.clear()
		for index in range(count):
			game.collected_words.append(WORDS[index])
		game._refresh_collected_words()
		_check(layer.get_child_count() == count,
			tag + " %d collected fruits never duplicate or go missing" % count)
		var centers: Array[float] = []
		for index in range(count):
			var apple := layer.get_child(index) as TextureRect
			_check(apple != null, tag + " each gathered fruit is TextureRect")
			if apple == null:
				continue
			_check(apple.texture == HALF and apple.material is ShaderMaterial and
				(apple.material as ShaderMaterial).shader == game.CAUGHT_APPLE_FRONT_CLIP and
				apple.texture.resource_path.ends_with("/APPLE HALF SEAMLESS.png"),
				tag + " original-top half-apple with foreground-only clip")
			_check(apple.get_child_count() == 0,
				tag + " collected fruit contains NO redundant text/word overlay")
			_check(absf(apple.size.x - width) < 0.05 and absf(apple.size.y - height) < 0.05,
				tag + " three equally sized, small fruits relative to selected basket")
			var visible_bottom: float = apple.position.y + apple.size.y * game.HALF_APPLE_PAINTED_HEIGHT_RATIO
			_check(absf(visible_bottom - rim_y - game.collected_apple_placement_offset.y) < 4.0,
				tag + " lower visible red fruit aligns with wicker basket lip")
			var local_x_center := apple.position.x + apple.size.x * 0.5
			centers.append(local_x_center)
			_check(local_x_center >= basket_center.x - basket_size.x * 0.5 and
				local_x_center <= basket_center.x + basket_size.x * 0.5,
				tag + " fruit sits inside selected basket horizontal opening")
		if centers.size() == 3:
			_check(absf((centers[1] - centers[0]) - (centers[2] - centers[1])) < 0.1,
				tag + " three collected fruits spaced equally across basket")
	var falling := game._create_tile_node("NOUN", Color.WHITE) as Control
	var falling_art := falling.get_node("AppleSprite") as TextureRect
	var falling_label := falling.get_node("WordLabel") as Label
	_check(falling_art.texture == game.gameplay_apple_texture and
		falling_art.texture != HALF and
		falling_label.text == "NOUN" and falling_label.visible and falling_art.material == null,
		tag + " full-size falling gameplay word-apple art (including configured skin) retains labels and no half-apple mask")
	falling.free()
	game.queue_free()
	await process_frame

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
