extends SceneTree

# Run: Godot_v4.7.2-stable_win64_console.exe --headless --path . \
#      --script res://tools/test_catch_sibling_hierarchy.gd
# The four scene-authored root characters and CollectedWords are siblings.
const SCENE := preload("res://ui/minigames/catch_word.tscn")
const CHARACTERS := ["Boy", "Girl", "Grandma", "Grandpa"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const EPS := 1.5

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for resolution in RESOLUTIONS:
		root.size = resolution
		root.content_scale_size = resolution
		for selected in CHARACTERS:
			await _check_character(resolution, selected)
	for failure in failures:
		push_error(failure)
	print("CATCH SIBLING HIERARCHY: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size(), " (", assertions, " assertions)")
	quit(0 if failures.is_empty() else 1)


func _check_character(resolution: Vector2i, selected: String) -> void:
	var tag := "%s %s" % [selected, resolution]
	var game := SCENE.instantiate() as Control
	_check(not game.has_node("CharacterRig"), tag + ": obsolete CharacterRig must be absent")
	var original_positions: Dictionary = {}
	var original_sprite_positions: Dictionary = {}
	var selected_group := game.get_node(selected) as Node2D
	var selected_body := selected_group.get_node("Body") as Sprite2D
	var selected_basket := selected_group.get_node("Basket") as Sprite2D
	for name in CHARACTERS:
		var group := game.get_node_or_null(name) as Node2D
		_check(group != null and group.get_parent() == game and group.owner == game,
			tag + ": " + name + " must be an editable root sibling")
		if group == null:
			continue
		original_positions[name] = group.position
		for sprite_name in ["Body", "Basket"]:
			var sprite := group.get_node_or_null(sprite_name) as Sprite2D
			_check(sprite != null and sprite.owner == game and sprite.get_parent() == group,
				tag + ": " + name + "/" + sprite_name + " is a scene-owned sprite")
			if sprite != null:
				original_sprite_positions[name + "/" + sprite_name] = sprite.position
	var collected := game.get_node_or_null("CollectedWords") as Node2D
	_check(collected != null and collected.get_parent() == game and collected.owner == game,
		tag + ": CollectedWords is a separate editable root sibling")
	var initial_collected_offset := collected.position - (game.get_node("Boy") as Node2D).position
	# An Inspector drag before _ready must be respected by hitboxes and fruits.
	var basket_drag := Vector2(12.0, -5.0)
	selected_basket.position += basket_drag
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"catch_character": selected, "catch_map": "City", "topic": "Noun", "difficulty": "Easy", "game_mode": "Seconds"})
	game.set_process(false)
	await process_frame
	game.set_process(false)
	_check(game.get("character_group") == selected_group and game.get("body_sprite") == selected_body
		and game.get("basket_sprite") == selected_basket, tag + ": selected character pointers")
	_check(selected_group.visible and selected_body.is_visible_in_tree() and selected_basket.is_visible_in_tree(),
		tag + ": selected character actually visible")
	_check(selected_basket.position.is_equal_approx(original_sprite_positions[selected + "/Basket"] + basket_drag),
		tag + ": selected basket retains editor drag")
	_check(selected_body.position.is_equal_approx(original_sprite_positions[selected + "/Body"]),
		tag + ": selected body keeps editor offset")
	for name in CHARACTERS:
		var group := game.get_node(name) as Node2D
		_check(group.visible == (name == selected), tag + ": visibility for " + name)
		if name != selected:
			_check(group.position.is_equal_approx(original_positions[name]), tag + ": inactive " + name + " position unchanged")
	_check(selected_group.position.distance_to(original_positions[selected] * Vector2(float(resolution.x) / 1280.0, float(resolution.y) / 720.0)) < EPS,
		tag + ": selected position follows its scene-authored start")
	_check(collected.position.distance_to(selected_group.position + initial_collected_offset * (float(resolution.x) / 1280.0)) < EPS,
		tag + ": independent collected layer tracks selected character")
	_check(selected_body.z_index + selected_group.z_index < collected.z_index
		and collected.z_index < selected_basket.z_index + selected_group.z_index,
		tag + ": fruit draws in front of body and behind basket")
	_check(_collision_center_near_sprite(game, selected_basket), tag + ": collision follows selected basket")

	var words: Array = game.get("collected_words")
	words.append_array(["apple", "school", "river"])
	game.call("_refresh_collected_words")
	_check(collected.get_child_count() == 3, tag + ": three caught apples appear in root layer")
	_check(_apples_overlap_basket(collected, selected_basket), tag + ": collected apples overlap selected basket")
	var origin_x := selected_group.position.x
	game.call("set_body_x", 1.0)
	game.call("_update_basket", 0.3)
	game.call("_sync_character_position")
	_check(selected_group.position.x > origin_x, tag + ": camera body position moves selected group")
	_check(collected.position.distance_to(selected_group.position + initial_collected_offset * (float(resolution.x) / 1280.0)) < EPS,
		tag + ": collected layer follows during horizontal movement")
	_check(_collision_center_near_sprite(game, selected_basket), tag + ": moving collision follows selected basket")
	_check(_apples_overlap_basket(collected, selected_basket), tag + ": apples stay with moving basket")
	for name in CHARACTERS:
		if name != selected:
			_check((game.get_node(name) as Node2D).position.is_equal_approx(original_positions[name]),
				tag + ": movement leaves inactive " + name + " at its editor position")
	# Switching variants on the same scene must also update the apple coordinate system.
	var next_character: String = CHARACTERS[(CHARACTERS.find(selected) + 1) % CHARACTERS.size()]
	game.set_context({"catch_character": next_character, "catch_map": "Forest", "topic": "Verb", "game_mode": "Lives"})
	game.set_process(false)
	var next_group := game.get_node(next_character) as Node2D
	var next_basket := next_group.get_node("Basket") as Sprite2D
	_check(game.get("character_group") == next_group and game.get("basket_sprite") == next_basket,
		tag + ": switching picks the new root variant")
	_check(not selected_group.visible and next_group.visible, tag + ": switching hides the previous variant")
	_check(collected.get_child_count() == 0, tag + ": new round clears previous fruits")
	_check(_collision_center_near_sprite(game, next_basket), tag + ": switched basket collision")
	words = game.get("collected_words")
	words.append("teacher")
	game.call("_refresh_collected_words")
	_check(_apples_overlap_basket(collected, next_basket), tag + ": switched basket receives collected apple")
	root.remove_child(game)
	game.free()
	await process_frame


func _collision_center_near_sprite(game: Control, sprite: Sprite2D) -> bool:
	var hitbox: Rect2 = game.call("_basket_rect")
	var visual := _sprite_rect(sprite)
	return hitbox.has_area() and visual.has_area() and absf(hitbox.get_center().x - visual.get_center().x) < EPS and absf(hitbox.get_center().y - visual.get_center().y) < visual.size.y * 0.1


func _apples_overlap_basket(layer: Node2D, basket: Sprite2D) -> bool:
	var basket_rect := _sprite_rect(basket)
	for child in layer.get_children():
		if not child is TextureRect:
			return false
		var apple := child as TextureRect
		if not apple.get_global_rect().intersects(basket_rect):
			return false
		if apple.get_child_count() != 1 or not apple.get_child(0) is Label:
			return false
	return layer.get_child_count() > 0


func _sprite_rect(sprite: Sprite2D) -> Rect2:
	var rect := sprite.get_rect()
	return Rect2(sprite.global_position + rect.position * sprite.global_scale, rect.size * sprite.global_scale)


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
