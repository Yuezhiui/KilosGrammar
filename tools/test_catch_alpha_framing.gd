extends SceneTree

# Pixel-grounded regression for all original Catch body/basket PNG assets.
# The artist-authored bust framing intentionally puts the lower BODY offscreen;
# visible face/torso and all opaque basket pixels must stay in the viewport.
# Godot 4.7.2 --path . --rendering-method gl_compatibility \
#   --script res://tools/test_catch_alpha_framing.gd
# Also runs headlessly.  The graphical run additionally exercises the native
# viewport/canvas transformation used by the Windows OpenGL presentation.

const SCENE := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const CHARACTERS := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const MAPS := ["City", "Forest", "Mountain"]
const SOURCE_ROOT := "res://Components/Gameplay/Catch the Word/Characters/"
const TOLERANCE := 1.5
const MIN_EDGE_CLEARANCE := 4.0

var checks := 0
var cases := 0
var failures: Array[String] = []
var alpha_cache: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("CATCH ALPHA RENDERER: ", DisplayServer.get_name())
	for resolution in RESOLUTIONS:
		root.size = resolution
		root.content_scale_size = resolution
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
		await process_frame
		await process_frame
		for character in CHARACTERS:
			for map_name in MAPS:
				await _case(resolution, character, map_name)
	if failures.is_empty():
		print("PASS Catch real PNG alpha framing: %d assertions across %d characters/maps/resolutions" % [checks, cases])
		quit(0)
	else:
		for error in failures:
			push_error("CATCH ALPHA QA: " + error)
		print("FAIL Catch real PNG alpha framing: %d failures, %d checks/%d cases" % [failures.size(), checks, cases])
		quit(1)


func _case(resolution: Vector2i, character: String, map_name: String) -> void:
	var tag := "%s/%s/%dx%d" % [character, map_name, resolution.x, resolution.y]
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({
		"activity": "Catch the Word",
		"topic": "Noun",
		"game_mode": "Seconds",
		"difficulty": "Easy",
		"catch_character": character,
		"catch_map": map_name
	})
	game.set_process(false)
	game._on_resized()
	await process_frame
	game.set_process(false)
	cases += 1

	var body: Sprite2D = game.body_sprite
	var basket: Sprite2D = game.basket_sprite
	var rig: Node2D = game.character_group
	var frame := Rect2(Vector2.ZERO, Vector2(resolution))
	var factor := float(resolution.y) / 720.0
	var authored_position: Vector2 = game.character_editor_transforms[character]["position"]
	_check(authored_position.y > 0.0 and rig.position.distance_to(authored_position * factor) <= TOLERANCE,
		tag + ": runtime changed the editor-authored baseline")
	_check(rig.scale.is_equal_approx(Vector2.ONE * factor),
		tag + ": root editor scaling is not proportional to viewport")
	_check(game.selected_map == map_name and game.background.texture.resource_path ==
		"res://Components/Gameplay/Catch the Word/Maps/%sMap.png" % map_name, tag + ": wrong map artwork")

	var group: Node2D = game.get_node(character) as Node2D
	var body_editor_pos := body.position
	var basket_editor_pos := basket.position
	var body_editor_scale := body.scale
	var basket_editor_scale := basket.scale
	var group_editor_pos := group.position
	var body_info := _actual_opaque_rect(body, "%s Body" % tag)
	var basket_info := _actual_opaque_rect(basket, "%s Basket" % tag)
	if body_info.is_empty() or basket_info.is_empty():
		game.queue_free()
		await process_frame
		return
	var body_rect: Rect2 = body_info["rect"]
	var basket_rect: Rect2 = basket_info["rect"]
	_check(_avatar_framed(frame, body_rect), tag + ": ORIGINAL face/torso clipped or moved outside authored bust framing: " + str(body_rect))
	_check(_inside(frame, basket_rect), tag + ": ORIGINAL opaque basket clipped: " + str(basket_rect))
	_check(body_rect.end.y >= frame.end.y - TOLERANCE and body_rect.end.y <= frame.end.y + frame.size.y * 0.18,
		tag + ": authored BODY crop no longer intersects bottom edge as expected")
	_check(frame.end.y - basket_rect.end.y >= -TOLERANCE,
		tag + ": opaque basket artwork overflows frame edge")
	_check(body_rect.intersects(basket_rect),
		tag + ": original body/basket artwork no longer overlaps naturally")
	_check(body.z_index + group.z_index == 0 and basket.z_index + group.z_index == 1
		and game.get_node("CollectedWords").z_index == 2,
		tag + ": approved Body 0 / Basket 1 / Collected Half Apples 2 layering changed")
	_check(body.texture.resource_path == SOURCE_ROOT + character.to_upper() + " BODY.png" and
		basket.texture.resource_path == SOURCE_ROOT + character.to_upper() + " BASKET.png",
		tag + ": selected artwork no longer uses ORIGINAL PNGs")
	_check(not body_info["source_cropped"] and not basket_info["source_cropped"],
		tag + ": scene Sprite2D region cuts off original opaque pixels")
	_check(game._basket_rect().has_area() and
		game._basket_rect().intersects(basket_rect),
		tag + ": actual collision shape is disconnected from basket image")

	# Camera/body tracking steers the selected root sibling, but must not reintroduce
	# opaque clipping or detach collision from the basket at either edge.
	for direction in [-1.0, 1.0]:
		game.set_body_x(direction)
		game._update_basket(2.0)
		game._sync_character_position()
		var steered_body: Rect2 = _actual_opaque_rect(body, tag + " steer body")["rect"]
		var steered_basket: Rect2 = _actual_opaque_rect(basket, tag + " steer basket")["rect"]
		_check(_avatar_framed(frame, steered_body), tag + ": steered face/torso clipped at %s" % direction)
		_check(_inside(frame, steered_basket), tag + ": steered opaque basket clipped at %s" % direction)
		_check(game._basket_rect().intersects(steered_basket),
			tag + ": steered basket collision misses the image")
		_check(absf(steered_body.end.y - body_rect.end.y) <= TOLERANCE and
			absf(steered_basket.end.y - basket_rect.end.y) <= TOLERANCE,
			tag + ": steering changed authored vertical placement")
	game.clear_body_input()
	game._reset_round_geometry()
	_check(body.position.is_equal_approx(body_editor_pos) and
		basket.position.is_equal_approx(basket_editor_pos) and
		body.scale.is_equal_approx(body_editor_scale) and
		basket.scale.is_equal_approx(basket_editor_scale) and
		group.position.is_equal_approx(group_editor_pos),
		tag + ": runtime overwrote artist-editable original transforms")
	print("ALPHA ", tag, " body_bottom=%.2f basket_bottom=%.2f frame=%d" %
		[body_rect.end.y, basket_rect.end.y, resolution.y])
	game.queue_free()
	await process_frame


func _actual_opaque_rect(sprite: Sprite2D, tag: String) -> Dictionary:
	var path := sprite.texture.resource_path
	if not alpha_cache.has(path):
		var img := Image.new()
		var result := img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
		_check(result == OK and not img.is_empty(), tag + ": unable to decode original PNG alpha")
		alpha_cache[path] = img
	var source: Image = alpha_cache[path]
	if source.is_empty():
		return {}
	var opaque := Rect2(source.get_used_rect())
	var region: Rect2 = sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, Vector2(source.get_size()))
	var crop := region.intersection(opaque)
	var full_local := sprite.get_rect()
	var alpha_local := Rect2(full_local.position + crop.position - region.position, crop.size)
	var alpha_world := _transform_rect(alpha_local, sprite.get_global_transform_with_canvas())
	return {"rect": alpha_world, "source_cropped": not region.encloses(opaque)}


func _transform_rect(local: Rect2, transform: Transform2D) -> Rect2:
	var a := transform * local.position
	var b := transform * local.end
	var c := transform * Vector2(local.end.x, local.position.y)
	var d := transform * Vector2(local.position.x, local.end.y)
	var minimum := a.min(b).min(c).min(d)
	var maximum := a.max(b).max(c).max(d)
	return Rect2(minimum, maximum - minimum)


func _inside(frame: Rect2, rect: Rect2) -> bool:
	return rect.has_area() and frame.grow(0.5).encloses(rect)


func _avatar_framed(frame: Rect2, rect: Rect2) -> bool:
	if not rect.has_area():
		return false
	var visible_ratio := (minf(rect.end.y, frame.end.y) - maxf(rect.position.y, frame.position.y)) / rect.size.y
	return rect.position.x >= frame.position.x - TOLERANCE and rect.end.x <= frame.end.x + TOLERANCE \
		and rect.position.y >= frame.position.y - TOLERANCE and rect.position.y <= frame.size.y * 0.64 \
		and rect.end.y >= frame.end.y - TOLERANCE and rect.end.y <= frame.end.y + frame.size.y * 0.18 \
		and visible_ratio >= 0.75


func _check(value: bool, reason: String) -> void:
	checks += 1
	if not value:
		failures.append(reason)
