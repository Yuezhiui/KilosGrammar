extends SceneTree

# Godot 4.7.2: --headless --path . --script res://tools/test_catch_animal_migration_20261028.gd
# Exercises all five independently authored animal rigs, exact PNG crops,
# collision following Inspector basket edits, and shared KidsVoice feedback.

const SCENE := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const PRELOADER := preload("res://ui/play/gameplay/catch_asset_preloader.gd")
const CHARACTERS := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const ART_DIR := "res://Components/Gameplay/Catch the Word/Characters/"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var preloader := PRELOADER.new()
	root.add_child(preloader)
	for key in CHARACTERS:
		_check(PRELOADER.CHARACTERS.has(key), key + ": Ready preloader accepts character")
		_check(PRELOADER.CHARACTERS[key].size() == 2, key + ": Ready preloader has two sprites")
	await _exercise_preloader(preloader)
	for resolution in RESOLUTIONS:
		root.size = resolution
		root.content_scale_size = resolution
		await process_frame
		for selected in CHARACTERS:
			await _exercise_character(selected, resolution)
	preloader.queue_free()
	await process_frame
	for message in failures:
		push_error(message)
	print("CATCH FIVE ANIMALS: %s (%d assertions)" % ["PASS" if failures.is_empty() else "FAIL %d" % failures.size(), checks])
	quit(0 if failures.is_empty() else 1)


func _exercise_preloader(preloader: Node) -> void:
	for selected in CHARACTERS:
		preloader.prepare(selected, "City")
		var stats := preloader.get_preload_stats() as Dictionary
		_check(stats["character"] == selected and stats["map"] == "City",
			selected + ": preloader retains correct Ready selection")
		for frame in range(240):
			if bool(stats["complete"]):
				break
			await process_frame
			stats = preloader.get_preload_stats()
		_check(bool(stats["complete"]), selected + ": asynchronous preloader completes every selected artwork")
		_check(int(stats["pending"]) == 0 and int(stats["held"]) == int(stats["requested"]),
			selected + ": all requested art held with no pending requests")
	preloader.clear_selection()
	var after := preloader.get_preload_stats() as Dictionary
	_check(int(after["held"]) == 0 and int(after["requested"]) == 0,
		"Ready preloader releases selected art when leaving Catch")
	preloader.finish_pending_for_shutdown()


func _exercise_character(selected: String, resolution: Vector2i) -> void:
	var label := "%s/%dx%d" % [selected, resolution.x, resolution.y]
	var game := SCENE.instantiate() as Control
	_check(game != null, label + ": scene loads")
	if game == null:
		return
	var saved: Dictionary = {}
	for key in CHARACTERS:
		var rig := game.get_node_or_null(key) as Node2D
		_check(rig != null and rig.owner == game and rig.get_parent() == game,
			label + ": " + key + " rig is a directly editable scene child")
		if rig == null:
			continue
		var body := rig.get_node_or_null("Body") as Sprite2D
		var basket := rig.get_node_or_null("Basket") as Sprite2D
		_check(body != null and basket != null and body.owner == game and basket.owner == game,
			label + ": " + key + " has two independently authored sprites")
		if body == null or basket == null:
			continue
		_check(body.texture != null and body.texture.resource_path == ART_DIR + key.to_upper() + " BODY.png",
			label + ": " + key + " Body points to new PNG")
		_check(basket.texture != null and basket.texture.resource_path == ART_DIR + key.to_upper() + " BASKET.png",
			label + ": " + key + " Basket points to new PNG")
		_check(_crop_includes_alpha(body) and _crop_includes_alpha(basket),
			label + ": " + key + " crop includes all visible pixels")
		_check(_pair_shares_source_canvas(body, basket),
			label + ": " + key + " hands and basket align on original 941x1672 PNG canvas")
		saved[key] = {"body_position": body.position, "body_scale": body.scale,
			"basket_position": basket.position, "basket_scale": basket.scale,
			"rig_scale": rig.scale}
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"topic": "Noun", "game_mode": "Seconds", "difficulty": "Easy",
		"catch_character": selected, "catch_map": "City"})
	game.set_process(false)
	await process_frame
	game.set_process(false)
	_check(game.selected_character == selected, label + ": selection honored")
	for key in CHARACTERS:
		var rig := game.get_node(key) as Node2D
		_check(rig.visible == (key == selected), label + ": only selected rig is visible")
		if not saved.has(key):
			continue
		var body := rig.get_node("Body") as Sprite2D
		var basket := rig.get_node("Basket") as Sprite2D
		_check(body.position.is_equal_approx(saved[key]["body_position"])
			and body.scale.is_equal_approx(saved[key]["body_scale"])
			and basket.position.is_equal_approx(saved[key]["basket_position"])
			and basket.scale.is_equal_approx(saved[key]["basket_scale"]),
			label + ": " + key + " sprite Inspector transforms preserved")
	var active := game.get_node(selected) as Node2D
	var active_basket := active.get_node("Basket") as Sprite2D
	_check(game.body_sprite == active.get_node("Body") and game.basket_sprite == active_basket,
		label + ": collision and selected pointers use matching rig")
	_check(game._basket_rect().has_area(), label + ": basket has positive hitbox")
	var before := game._basket_rect() as Rect2
	active_basket.position.x += 12.0
	var after := game._basket_rect() as Rect2
	_check(absf(after.get_center().x - before.get_center().x - 12.0 * active.scale.x) < 1.0,
		label + ": basket hitbox follows Inspector sprite offset")
	_check(after.size.is_equal_approx(before.size), label + ": basket movement keeps hitbox dimensions")
	active_basket.position.x -= 12.0
	var voice_player := game.get_node_or_null("CatchVoicePlayer") as AudioStreamPlayer
	_check(voice_player != null and _count_audio_players(game) == 1,
		label + ": only one Catch voice player exists")
	if voice_player != null:
		game._speak_catch_feedback(true)
		_check(voice_player.stream != null and voice_player.stream.resource_path.begins_with("res://assets/audio/kids_voice/"),
			label + ": correct voice uses the 39 recorded kids clips")
		game._speak_catch_feedback(false, true)
		_check(voice_player.stream != null and voice_player.stream.resource_path.begins_with("res://assets/audio/kids_voice/"),
			label + ": missed voice uses kids coaching clips")
		game._stop_voice_feedback()
		_check(voice_player.stream == null and not voice_player.playing,
			label + ": paused/exiting scene stops voice playback")
	game.queue_free()
	await process_frame


func _crop_includes_alpha(sprite: Sprite2D) -> bool:
	if sprite.texture == null or not sprite.region_enabled:
		return false
	var data := FileAccess.get_file_as_bytes(sprite.texture.resource_path)
	var image_data := Image.new()
	if image_data.load_png_from_buffer(data) != OK:
		return false
	var opaque := Rect2(image_data.get_used_rect())
	return sprite.region_rect.encloses(opaque) and opaque.has_area()


func _count_audio_players(node: Node) -> int:
	var count := 1 if node is AudioStreamPlayer else 0
	for child in node.get_children():
		count += _count_audio_players(child)
	return count


func _pair_shares_source_canvas(body: Sprite2D, basket: Sprite2D) -> bool:
	# Each image is a transparent 941x1672 canvas. Sprite2D regions can crop
	# unused alpha, but the original pixel (0,0) must still map to the same
	# position for both layers or the animal's paws detach from the basket.
	var body_origin := body.position - body.region_rect.get_center() * body.scale
	var basket_origin := basket.position - basket.region_rect.get_center() * basket.scale
	# A teacher can nudge an Inspector-authored Basket by one viewport pixel.
	# Permit that visually negligible adjustment while still flagging real
	# source-canvas separation, cropped paws, and detached collision artwork.
	return body_origin.distance_to(basket_origin) <= 1.5


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
