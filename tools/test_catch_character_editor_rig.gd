extends SceneTree

# Godot 4.7: --headless --path . --script res://tools/test_catch_character_editor_rig.gd
# Focused contract: all FOUR Catch the Word body/basket pairs are independently
# editable in the Godot scene, and collision follows the actual chosen basket.
# No game/editor files are modified; perturbations affect scene instances only.

const SCENE_PATH := "res://ui/minigames/catch_word.tscn"
const CHARACTERS := ["Boy", "Girl", "Grandma", "Grandpa"]
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const EDIT_BODY_DELTA := Vector2(7.0, -8.0)
const EDIT_BASKET_DELTA := Vector2(13.0, -6.0)
const EDIT_RIG_DELTA := Vector2(23.0, -12.0)
const EPSILON := 1.5

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	_check(scene != null, "Catch the Word scene loads")
	if scene == null:
		_finish()
		return
	for viewport_size in VIEWPORTS:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		for selected in CHARACTERS:
			await _check_character(scene, viewport_size, selected)
	_finish()


func _check_character(scene: PackedScene, viewport_size: Vector2i, selected: String) -> void:
	var tag := "%s at %s" % [selected, viewport_size]
	var game := scene.instantiate() as Control
	_check(game != null, tag + ": scene is Control")
	if game == null:
		return
	var rig := game.get_node_or_null(selected) as Node2D
	_check(rig != null and rig.owner == game, tag + ": chosen root sibling is independently editor-authored")
	if rig == null:
		game.free()
		return

	var pair_sprites: Dictionary = {}
	var editor_snapshots: Dictionary = {}
	for name in CHARACTERS:
		var parent := game.get_node_or_null(name) as Node2D
		_check(parent != null and parent.owner == game and parent.get_parent() == game,
			tag + ": %s rig is a separately selectable editor node" % name)
		var body := parent.get_node_or_null("Body") as Sprite2D if parent != null else null
		var basket := parent.get_node_or_null("Basket") as Sprite2D if parent != null else null
		_check(body != null and basket != null, tag + ": %s has separate Body and Basket Sprite2D" % name)
		if body == null or basket == null:
			continue
		pair_sprites[name] = {"body": body, "basket": basket}
		_check(body.owner == game and basket.owner == game,
			tag + ": %s has BOTH sprites saved in .tscn, not generated at runtime" % name)
		_check(body.get_parent() == parent and basket.get_parent() == parent,
			tag + ": %s sprites share the corresponding editable rig" % name)
		_check(body.texture != null and basket.texture != null,
			tag + ": %s sprites have real assigned artwork in the editor" % name)
		if body.texture != null and basket.texture != null:
			var base: String = "res://WordCatcherCharacters/" + String(name).to_upper()
			_check(body.texture.resource_path == base + " BODY.png"
				and basket.texture.resource_path == base + " BASKET.png",
				tag + ": %s retains its ORIGINAL two art layers" % name)
		_check(body.region_enabled and basket.region_enabled and body.region_rect.has_area()
			and basket.region_rect.has_area(),
			tag + ": %s both source crop regions are editable" % name)
		_check(body.scale.x > 0.0 and body.scale.y > 0.0 and basket.scale.x > 0.0 and basket.scale.y > 0.0,
			tag + ": %s editor sprite scales are positive" % name)
		# Simulate the user's Inspector edit BEFORE Godot calls _ready().
		body.position += EDIT_BODY_DELTA
		basket.position += EDIT_BASKET_DELTA
		# Mutate only one pair's scale per run; this exposes calculations that
		# secretly reset the chosen body's/basket's authored scale.
		if name == selected:
			body.scale *= Vector2(0.98, 0.98)
			basket.scale *= Vector2(1.03, 1.03)
		editor_snapshots[name] = {"body": _snapshot(body), "basket": _snapshot(basket)}

	_check(pair_sprites.size() == 4, tag + ": all four editor-authored character variants exist")
	if pair_sprites.size() != 4:
		game.free()
		return
	var authored_rig_scale := rig.scale
	var authored_rig_position := rig.position + EDIT_RIG_DELTA
	rig.position = authored_rig_position
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {
		"activity": "Catch the Word", "catch_character": selected,
		"catch_map": "City", "topic": "Noun", "difficulty": "Easy", "game_mode": "Seconds"
	})
	game.set_process(false)
	await process_frame
	game.set_process(false)
	_check(String(game.get("selected_character")) == selected,
		tag + ": user-selected character survives set_context")
	_check(game.get("body_sprite") == pair_sprites[selected]["body"]
		and game.get("basket_sprite") == pair_sprites[selected]["basket"],
		tag + ": active runtime body/basket references follow selected editor pair")
	_check(rig.position.x >= 0 and absf(rig.position.x - authored_rig_position.x * (viewport_size.x / 1280.0)) < EPSILON,
		tag + ": editor rig starting X is honored, not replaced by a default left offset")
	_check(absf(rig.position.y - authored_rig_position.y * (viewport_size.y / 720.0)) < EPSILON,
		tag + ": editor rig Y remains visible and follows viewport scaling")
	var responsive_factor := minf(float(viewport_size.x) / 1280.0, float(viewport_size.y) / 720.0)
	_check(rig.scale.is_equal_approx(authored_rig_scale * responsive_factor),
		tag + ": selected root sibling scales responsively from EDITOR scale; individual sprites remain untouched")
	_check(_pair_visibility(pair_sprites, rig, selected),
		tag + ": only chosen Boy/Girl/Grandma/Grandpa is visible")
	_check_local_snapshots(pair_sprites, editor_snapshots, tag + ": after set_context")

	var active_body: Sprite2D = pair_sprites[selected]["body"]
	var active_basket: Sprite2D = pair_sprites[selected]["basket"]
	var collected := game.get_node_or_null("CollectedWords") as Node2D
	_check(collected != null and collected.owner == game,
		tag + ": independent collected-word layer stays editor-authored")
	if collected != null:
		_check(active_body.z_index + rig.z_index < collected.z_index and collected.z_index < active_basket.z_index + rig.z_index,
			tag + ": back body < caught fruit < foreground basket draw order")
	_check_clipping(active_body, active_basket, viewport_size, tag + ": initial framing")
	_check_collision_follows_basket(game, active_basket, tag)
	_check_collected_apples(game, rig, collected, active_basket, viewport_size, tag)
	_check(collected.position.distance_to(rig.position + Vector2(game.get("collected_editor_offset")) * responsive_factor) <= EPSILON, tag + ": root collected words follows edited root sibling")
	_check_steering_edges(game, active_body, active_basket, viewport_size, tag)
	_check_local_snapshots(pair_sprites, editor_snapshots, tag + ": after collider perturbation")

	# Reassigning character/context and resizing must never reset authored
	# coordinates/crops/scales. The root may move for gameplay, not its parts.
	game.call("_reset_round_geometry")
	game.call("_on_resized")
	game.call("_sync_character_position")
	_check(rig.scale.is_equal_approx(authored_rig_scale * responsive_factor),
		tag + ": reset + resize retain responsive root scale and authored base scale")
	_check_local_snapshots(pair_sprites, editor_snapshots, tag + ": after reset / resize / movement")
	_check_clipping(active_body, active_basket, viewport_size, tag + ": after resize")
	game.queue_free()
	await process_frame


func _check_collision_follows_basket(game: Control, basket: Sprite2D, tag: String) -> void:
	# Catch collision must be based on selected basket's current global
	# transform: moving its editor sprite without moving CharacterRig must
	# move the hitbox by precisely the same transformed displacement.
	var before := game.call("_basket_rect") as Rect2
	var visual := _global_sprite_rect(basket)
	_check(before.has_area() and visual.has_area(), tag + ": rendered basket + collision have nonzero area")
	var root_rig := game.get("character_group") as Node2D
	var local_center: Vector2 = root_rig.to_local(basket.global_position)
	var expected_world_center: Vector2 = root_rig.get_global_transform_with_canvas() * local_center
	_check(before.get_center().distance_to(expected_world_center - Vector2(0, visual.size.y * 0.05)) <= 2.0,
		tag + ": collider center includes the root-scale-adjusted editor Basket offset")
	_check(absf(before.get_center().x - visual.get_center().x) <= 2.0
		and absf(before.get_center().y - (visual.get_center().y - visual.size.y * 0.05)) <= 2.0,
		tag + ": collider is centered on selected actual basket artwork")
	# The runtime hitbox now uses *world* basket pixel size, not the unscaled
	# 1280x720 local artwork size. Detect a regression that silently keeps the
	# old hitbox when the CharacterRig grows at 1600/1920 or an artist scales
	# the chosen basket in the editor.
	var sprite_pixels: Vector2 = basket.region_rect.size if basket.region_enabled else basket.texture.get_size()
	var world_pixels: Vector2 = sprite_pixels * basket.get_global_transform_with_canvas().get_scale().abs()
	var expected_size := world_pixels * Vector2(float(game.get("basket_hitbox_width_ratio")),
		float(game.get("basket_hitbox_height_ratio")))
	_check(before.size.distance_to(expected_size) <= 2.0,
		tag + ": collision width/height derive from selected basket WORLD art and inspector ratios")
	_check(before.size.x < visual.size.x and before.size.y < visual.size.y,
		tag + ": catch opening is intentionally inside the visual basket")
	var original := basket.position
	var transformed_delta := (basket.get_parent() as Node2D).global_transform.basis_xform(Vector2(36, -19))
	basket.position += Vector2(36, -19)
	var moved := game.call("_basket_rect") as Rect2
	_check(moved.get_center().distance_to(before.get_center() + transformed_delta) <= 1.0,
		tag + ": moving ONLY Basket updates collision center (no stale constants)")
	var tile_at_rim := game.call("_tile_rect", {"pos": moved.get_center()}) as Rect2
	var tile_far := game.call("_tile_rect", {"pos": moved.get_center() + Vector2(moved.size.x + 150, 0)}) as Rect2
	_check(tile_at_rim.intersects(moved) and not tile_far.intersects(moved),
		tag + ": overlap uses live basket bounds, distant tiles do not register")
	basket.position = original
	var restored := game.call("_basket_rect") as Rect2
	_check(restored.get_center().distance_to(before.get_center()) <= 1.0,
		tag + ": restoring basket re-centers collision without code edits")


func _check_collected_apples(game: Control, rig: Node2D, layer: Node2D,
		basket: Sprite2D, viewport_size: Vector2i, tag: String) -> void:
	if layer == null:
		return
	var fruit: Array = game.get("collected_words")
	fruit.clear()
	fruit.append_array(["APPLE", "GARDEN", "TEACHER"])
	game.call("_refresh_collected_words")
	var basket_rect := _global_sprite_rect(basket)
	var viewport := Rect2(Vector2.ZERO, Vector2(viewport_size))
	var count := 0
	for child in layer.get_children():
		if not child is TextureRect or child.is_queued_for_deletion():
			continue
		count += 1
		var item := child as TextureRect
		var rect := item.get_global_rect()
		_check(rect.intersects(basket_rect.grow(1.0)),
			tag + ": collected apple overlaps the selected Basket, not legacy Boy")
		_check(viewport.grow(2.0).encloses(rect),
			tag + ": collected apple remains inside viewport after editor moves")
		_check(item.get_child_count() > 0 and item.get_child(0) is Label,
			tag + ": collected apple keeps its labeled grammar answer")
	_check(count == 3, tag + ": exactly three caught apples render, none duplicated")


func _check_steering_edges(game: Control, body: Sprite2D, basket: Sprite2D,
		viewport_size: Vector2i, tag: String) -> void:
	for side in [-1.0, 1.0]:
		game.call("set_body_x", side)
		game.call("_update_basket", 2.0)
		game.call("_sync_character_position")
		var rect: Rect2 = game.call("_basket_rect")
		var art := _global_sprite_rect(basket)
		_check(rect.get_center().distance_to(art.get_center() - Vector2(0.0, art.size.y * 0.05)) <= 2.0,
			"%s: %s edge collider remains aligned with visible basket" % [tag, "left" if side < 0 else "right"])
		_check_clipping(body, basket, viewport_size,
			"%s: %s edge steering" % [tag, "left" if side < 0 else "right"])
	game.call("clear_body_input")


func _check_clipping(body: Sprite2D, basket: Sprite2D, size: Vector2i, tag: String) -> void:
	# Region crop defines the intended visible artwork; do not assert on the
	# full uncropped source texture's transparent padding. User explicitly
	# requires the head, hands, basket and feet inside the game viewport.
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	for part in [{"name": "body", "sprite": body}, {"name": "basket", "sprite": basket}]:
		var rect := _global_sprite_rect(part["sprite"] as Sprite2D)
		_check(rect.has_area(), tag + ": %s has nonzero visual bounds" % part["name"])
		_check(screen.grow(EPSILON).encloses(rect),
			"%s: %s image is not clipped at any edge; rect %s vs screen %s" % [tag, part["name"], rect, screen])


func _global_sprite_rect(sprite: Sprite2D) -> Rect2:
	var r := sprite.get_rect()
	var transform := sprite.get_global_transform_with_canvas()
	var p := transform * r.position
	var bounds := Rect2(p, Vector2.ZERO)
	for corner in [r.position + Vector2(r.size.x, 0), r.position + r.size,
		r.position + Vector2(0, r.size.y)]:
		bounds = bounds.expand(transform * corner)
	return bounds.abs()


func _snapshot(sprite: Sprite2D) -> Dictionary:
	return {"position": sprite.position, "scale": sprite.scale,
		"rotation": sprite.rotation, "region_rect": sprite.region_rect,
		"offset": sprite.offset, "texture": sprite.texture}


func _check_local_snapshots(pairs: Dictionary, snapshots: Dictionary, tag: String) -> void:
	for name in CHARACTERS:
		for part in ["body", "basket"]:
			var sprite: Sprite2D = pairs[name][part]
			var saved: Dictionary = snapshots[name][part]
			_check(sprite.position.is_equal_approx(saved["position"])
				and sprite.scale.is_equal_approx(saved["scale"])
				and is_equal_approx(sprite.rotation, saved["rotation"])
				and sprite.region_rect == saved["region_rect"]
				and sprite.offset == saved["offset"] and sprite.texture == saved["texture"],
				"%s: %s/%s editor position/scale/crop/texture preserved" % [tag, name, part])


func _pair_visibility(pairs: Dictionary, rig: Node2D, selected: String) -> bool:
	var count := 0
	for name in CHARACTERS:
		var pair: Dictionary = pairs[name]
		var visible := bool((pair["body"] as Sprite2D).is_visible_in_tree()) and bool((pair["basket"] as Sprite2D).is_visible_in_tree())
		if visible:
			count += 1
		if visible != (name == selected):
			return false
	return count == 1 and rig.is_visible_in_tree() and rig == pairs[selected]["body"].get_parent()


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _finish() -> void:
	for message in failures:
		printerr("FAIL Catch character editor rig: ", message)
	print("%s Catch character editor rig: %d checks, %d failures across %d characters x %d viewports" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size(), CHARACTERS.size(), VIEWPORTS.size()])
	quit(0 if failures.is_empty() else 1)
