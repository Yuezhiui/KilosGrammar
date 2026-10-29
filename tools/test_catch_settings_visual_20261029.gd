extends SceneTree

## Real Catch basket-fruit and Settings/Credits HOME regression.
## Godot 4.7.2 --headless --path . --script res://tools/test_catch_settings_visual_20261029.gd
## For real GPU captures: --rendering-method gl_compatibility --rendering-driver opengl3
## --display-driver windows --path . --script res://tools/test_catch_settings_visual_20261029.gd -- --capture
## Only writes optional screenshots under Godot user://, never changes source scenes.
const CATCH := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const SETTINGS := preload("res://ui/secondary/settings/settings.tscn")
const CREDITS := preload("res://ui/secondary/credits/credits.tscn")
const FULL_APPLE := preload("res://Components/Gameplay/Catch the Word/Items/Apple.png")
const HALF_APPLE := preload("res://Components/Gameplay/Catch the Word/Items/APPLE HALF SEAMLESS.png")
const ORIGINAL_HALF_APPLE := preload("res://Components/Gameplay/Catch the Word/Items/APPLE HALF.png")
const HOME := preload("res://Components/Credits/Redesign/HOME.png")
const ANIMALS := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const WORDS := ["TEACHER", "GARDEN", "RIVER"]
const EXPECTED_HOME := Rect2(1027.0, 3.0, 220.0, 80.0)
var checks := 0
var failures: Array[String] = []
var captures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(HALF_APPLE.get_size() == Vector2(307, 190),
		"unmodified user-supplied half-apple source is 307×190, not full apple")
	_check(FULL_APPLE.resource_path.ends_with("/Apple.png") and
			HALF_APPLE.resource_path.ends_with("/APPLE HALF SEAMLESS.png") and
		FULL_APPLE != HALF_APPLE, "distinct source apple textures serve falling and caught purposes")
	var painted := ORIGINAL_HALF_APPLE.get_image()
	if painted != null:
		_check(painted.get_pixel(150, 30).a > 0.5 and painted.get_pixel(150, 185).a < 0.05,
			"half-apple PNG already has genuine transparent lower exterior, so no rectangle clipping needed")
	else:
		_check(false, "half-apple texture image loads for pixel verification")
	for dimensions in SIZES:
		root.content_scale_size = dimensions
		root.size = dimensions
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(dimensions)
		await process_frame
		for animal in ANIMALS:
			await _catch_case(dimensions, animal)
		await _settings_credits_case(dimensions)
	print("CATCH/SETTINGS VISUAL QA: %s checks=%d failures=%d catch_cases=%d layout_cases=%d gpu_captures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size(),
		ANIMALS.size() * SIZES.size(), SIZES.size(), captures])
	quit(0 if failures.is_empty() else 1)


func _catch_case(dimensions: Vector2i, animal: String) -> void:
	var tag := "%s %dx%d" % [animal, dimensions.x, dimensions.y]
	var game := CATCH.instantiate() as Control
	var edited_parts := {}
	for character in ANIMALS:
		var group := game.get_node(character) as Node2D
		edited_parts[character] = [group.get_node("Body").position,
			group.get_node("Body").scale, group.get_node("Basket").position,
			group.get_node("Basket").scale]
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity":"Catch the Word", "topic":"Noun", "difficulty":"Normal",
		"game_mode":"Seconds", "catch_character":animal, "catch_map":"City"})
	game.set_process(false)
	for frame in range(3):
		await process_frame
	_check(game.selected_character == animal and game.character_group == game.get_node(animal),
		tag + " requested animal chosen, correct original visual rig active")
	_check((game.character_group as Node2D).visible and game.basket_sprite == game.get_node(animal + "/Basket"),
		tag + " original artist-authored basket remains active")
	_check(game._basket_rect().has_area() and game._basket_visual_size().x > 80.0,
		tag + " selected basket has meaningful visual size and collision rectangle")
	_check(game.collected_word_layer.z_index > game.character_group.z_index - 2 and
		game.collected_word_layer.z_index >= game.character_group.z_index,
		tag + " collected fruit is in dedicated active, visible foreground layer")
	_check(HALF_APPLE.resource_path == String(game.HALF_APPLE_TEXTURE.resource_path) and
		FULL_APPLE.resource_path == String(game.APPLE_TEXTURE.resource_path),
		tag + " both supplied half and original whole fruit assets wired to game source")
	# Model what a correct basket catch actually leaves in state. The refresh is
	# game production code; no manually authored fake fruit nodes are used.
	var recovered: Array = game.collected_words
	recovered.clear()
	recovered.append_array(WORDS)
	game._refresh_collected_words()
	var layer := game.get_node("CollectedWords") as Node2D
	var marker := game.get_node("CollectedApplePlacement") as Marker2D
	var basket := game.get_node(animal + "/Basket") as Sprite2D
	var body := game.get_node(animal + "/Body") as Sprite2D
	_check(layer.get_child_count() == 3, tag + " exactly three real collected fruit nodes, no extras")
	_check(marker != null and marker.get_parent() == game and game.collected_apple_placement_offset.is_finite(),
		tag + " teacher-draggable saved placement marker controls the cluster")
	var basket_size: Vector2 = game._basket_visual_size()
	var rim_y: float = game._basket_local_center().y - basket_size.y * 0.5
	var expected_width := basket_size.x * float(game.caught_half_apple_basket_width_ratio)
	var cluster: Rect2
	var prior_end_x := -INF
	for i in range(layer.get_child_count()):
		var apple := layer.get_child(i) as TextureRect
		_check(apple != null and apple.name == "CaughtApple%d" % (i + 1),
			tag + " collected slot%d is a native TextureRect" % i)
		if apple == null:
			continue
		_check(apple.texture == HALF_APPLE and apple.material is ShaderMaterial and
			(apple.material as ShaderMaterial).shader == game.CAUGHT_APPLE_FRONT_CLIP,
			tag + " slot%d uses source half PNG with collected-only edge clip" % i)
		_check(apple.get_child_count() == 0 and not _contains_label(apple),
			tag + " slot%d has NO word label or text over the basket" % i)
		_check(apple.size.x > 0.0 and apple.size.x <= basket_size.x * 0.28 + 0.05 and
			absf(apple.size.x - expected_width) < 0.05,
			tag + " slot%d is a SMALL proportional apple for its character's wicker basket" % i)
		_check(absf(apple.size.y / apple.size.x - 190.0 / 307.0) < 0.001,
			tag + " slot%d maintains original half-apple aspect ratio" % i)
		var rect := Rect2(apple.position, apple.size)
		if i == 0:
			cluster = rect
		else:
			cluster = cluster.merge(rect)
		_check(apple.position.x >= prior_end_x - 1.0,
			tag + " slot%d is ordered left-to-right without excessive fruit overlap" % i)
		prior_end_x = apple.position.x + apple.size.x * 0.70
		var opaque_edge: float = apple.position.y + apple.size.y * game.HALF_APPLE_PAINTED_HEIGHT_RATIO
		var target_edge := rim_y + Vector2(game.collected_apple_placement_offset).y
		_check(absf(opaque_edge - target_edge) < 0.10,
			tag + " slot%d painted lower edge aligns selected basket rim + editor marker" % i)
		_check(apple.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			tag + " slot%d never intercepts camera/keyboard interaction" % i)
	_check(cluster.size.x < basket_size.x * 0.86 and
		absf(cluster.get_center().x - game._basket_local_center().x -
			Vector2(game.collected_apple_placement_offset).x) < basket_size.x * 0.03,
		tag + " entire half-apple trio neatly centered within real basket opening")
	_check(basket.texture.resource_path.ends_with(animal.to_upper() + " BASKET.png") and
		body.texture.resource_path.ends_with(animal.to_upper() + " BODY.png"),
		tag + " original independently editable body/basket PNGs unchanged")
	for character in ANIMALS:
		var rig := game.get_node(character) as Node2D
		var original: Array = edited_parts[character]
		_check(rig.get_node("Body").position.is_equal_approx(original[0]) and
			rig.get_node("Body").scale.is_equal_approx(original[1]) and
			rig.get_node("Basket").position.is_equal_approx(original[2]) and
			rig.get_node("Basket").scale.is_equal_approx(original[3]),
			tag + " " + character + " original artist Body/Basket local geometry preserved")
	# Actual falling-apple factory must independently create a full red
	# word-labeled apple (and continue awarding 100 for genuine correct catch).
	var falling := game._create_tile_node("TEACHER", Color.WHITE) as Control
	var sprite := falling.get_node_or_null("AppleSprite") as TextureRect
	var label := falling.get_node_or_null("WordLabel") as Label
	_check(sprite != null and sprite.texture == game.gameplay_apple_texture and
		sprite.texture != HALF_APPLE and sprite.material == null,
		tag + " falling apples retain their full-size generated apple artwork, unclipped")
	_check(label != null and label.text == "TEACHER" and
		label.visible and label.get_theme_font_size("font_size") >= 7,
		tag + " falling apple grammar word remains legible and actively labeled")
	_check(falling.size == Vector2(106, 109),
		tag + " original 106×109 falling apple gameplay/hitbox remains intact")
	falling.queue_free()
	var old_score := int(game.score)
	var old_attempts := int(game.attempts)
	var old_collected: Array = game.collected_words.duplicate()
	# Choose the actual source-generated correct falling apple, move the
	# authorized character's basket to its landing lane and advance real
	# falling physics until its source hitbox invokes _handle_catch().
	var real_correct_tile: Dictionary
	for tile in game.falling_tiles:
		if bool((tile as Dictionary).get("matching", false)):
			real_correct_tile = tile
			break
	_check(not real_correct_tile.is_empty() and game.falling_tiles.size() == 3,
		tag + " actual source GrammarBank created 1 true and 2 distractor falling apples")
	if not real_correct_tile.is_empty():
		game.basket_x = Vector2(real_correct_tile["pos"]).x - game._basket_world_offset().x
		game._sync_character_position()
		for tick in range(650):
			game._update_tiles(1.0 / 60.0)
			if int(game.attempts) > old_attempts:
				break
	_check(int(game.score) == old_score + 100 and int(game.attempts) == old_attempts + 1 and
		int(game.correct_count) > 0,
		tag + " real falling apple collides selected basket and awards exactly +100")
	# Production _process refreshes the score after _update_tiles; repeat that
	# real HUD step because this isolated SceneTree test deliberately pauses _process.
	game._refresh_hud()
	_check(game.score_bottom_number.text == str(game.score) and game.score_bottom_number.text == "100",
		tag + " earned +100 appears in native ScoreNumber HUD after real collision")
	_check(game.collected_words == old_collected and layer.get_child_count() == 3,
		tag + " collected display safely capped at 3 without allocating labels")
	if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args():
		# Actual native frame, no synthetic overlay or drawing.
		for frame in range(2):
			await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		var name := "user://qa_catch_half_%s_%dx%d.png" % [animal.to_lower(), dimensions.x, dimensions.y]
		_check(shot != null and not shot.is_empty() and shot.get_size() == dimensions and
			shot.save_png(name) == OK, tag + " screenshot from native real compositor")
		print("CATCH_VISUAL_CAPTURE ", ProjectSettings.globalize_path(name))
		captures += 1
	game.queue_free()
	await process_frame
	await process_frame


func _settings_credits_case(dimensions: Vector2i) -> void:
	var tag := "HOME %dx%d" % [dimensions.x, dimensions.y]
	var settings := SETTINGS.instantiate() as Control
	var credits := CREDITS.instantiate() as Control
	var saved_settings_home := settings.get_node("MainStage/BackButton") as Button
	var saved_credits_home := credits.get_node("CreditsStage/BackButton") as Button
	_check(saved_settings_home.get_rect().is_equal_approx(EXPECTED_HOME) and
		saved_credits_home.get_rect().is_equal_approx(EXPECTED_HOME),
		tag + " Settings and Credits use EXACT same editor-authored 1027,3 220×80 HOME geometry")
	var saved_art := saved_settings_home.get_node_or_null("Artwork") as TextureRect
	var credit_art := saved_credits_home.get_node_or_null("Artwork") as TextureRect
	_check(saved_art != null and credit_art != null and saved_art.texture == HOME and credit_art.texture == HOME,
		tag + " both screens use identical Credits HOME.png through teacher-editable Artwork node")
	_check(saved_art != null and credit_art != null and
		saved_art.mouse_filter == Control.MOUSE_FILTER_IGNORE and
		credit_art.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		tag + " HOME images do not block button hit targets")
	_check(saved_settings_home.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND and
		saved_credits_home.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND,
		tag + " HOME controls keep clickable cursor and native Button semantics")
	var source_rect := Rect2(saved_credits_home.position, saved_credits_home.size)
	var recorded_requests: Array[Dictionary] = []
	# Mount one page at a time because both pages fill the same window.
	root.add_child(credits)
	credits.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	credits.set_context({"qa_origin":"credits"})
	for frame in range(3):
		await process_frame
	_check((credits.get_node("CreditsStage/CreditsScroll") as ScrollContainer).visible and
		credits.get_node("CreditsStage/CreditsScroll/ScrollCenter/CreditsStack").get_child_count() > 3,
		tag + " Credits page still scrolls genuine names/attribution")
	var credit_rect := saved_credits_home.get_global_rect()
	var factor := minf(float(dimensions.x) / 1280.0, float(dimensions.y) / 720.0)
	var origin := (Vector2(dimensions) - Vector2(1280, 720) * factor) * 0.5
	var expected := Rect2(origin + source_rect.position * factor, source_rect.size * factor)
	_check(_near_rect(credit_rect, expected, 2.1),
		tag + " Credits runtime HOME scales design canvas with centered letterboxing")
	_check(saved_credits_home.visible and saved_credits_home.mouse_filter == Control.MOUSE_FILTER_STOP,
		tag + " Credits HOME remains an active hit target")
	credits.requested.connect(func(target: String, payload: Dictionary) -> void:
		recorded_requests.append({"target":target, "payload":payload}))
	saved_credits_home.pressed.emit()
	_check(recorded_requests.size() == 1 and recorded_requests[0].get("target") == "main" and
		(recorded_requests[0].get("payload", {}) as Dictionary).get("qa_origin") == "credits",
		tag + " real Credits HOME pressed signal requests main screen with context")
	if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args():
		await _capture("credits_home", dimensions)
	credits.queue_free()
	await process_frame
	root.add_child(settings)
	settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings.set_context({"qa_origin":"settings"})
	for frame in range(4):
		await process_frame
	# Layout uses a deferred sync in production; test the real final layout.
	settings.call("_apply_responsive_layout")
	await process_frame
	var settings_rect := saved_settings_home.get_global_rect()
	_check(_near_rect(settings_rect, credit_rect, 2.1),
		tag + " Settings HOME is exact same rendered size and screen position as Credits")
	_check(saved_settings_home.visible and not saved_settings_home.disabled and
		saved_settings_home.mouse_filter == Control.MOUSE_FILTER_STOP,
		tag + " Settings HOME remains active, clickable, and not disabled")
	_check(saved_art.texture == HOME and _near_rect(saved_art.get_global_rect(), settings_rect, 2.1),
		tag + " actual HOME.png artwork fills the Settings button hitbox")
	_check(settings._volume_slider is HSlider and settings._music_slider is HSlider and
		settings._effects_slider is HSlider and settings._fullscreen_check is CheckButton,
		tag + " all original three audio sliders and fullscreen toggle remain active")
	var active_controls := [settings._volume_slider, settings._music_slider,
		settings._effects_slider, settings._fullscreen_check]
	for control in active_controls:
		_check(control != null and control.is_inside_tree() and control.visible and
			 (control as Control).get_global_rect().has_area(),
			tag + " settings original control " + control.name + " still in active page layout")
	_check(settings._volume_slider.min_value < settings._volume_slider.max_value and
		settings._music_slider.min_value < settings._music_slider.max_value and
		settings._effects_slider.min_value < settings._effects_slider.max_value,
		tag + " real audio slider ranges remain actionable")
	recorded_requests.clear()
	settings.requested.connect(func(target: String, payload: Dictionary) -> void:
		recorded_requests.append({"target":target, "payload":payload}))
	saved_settings_home.pressed.emit()
	_check(recorded_requests.size() == 1 and recorded_requests[0].get("target") == "main" and
		(recorded_requests[0].get("payload", {}) as Dictionary).get("qa_origin") == "settings",
		tag + " Settings HOME pressed signal requests main with previous context")
	if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args():
		await _capture("settings_home", dimensions)
	settings.queue_free()
	await process_frame
	await process_frame


func _capture(kind: String, dimensions: Vector2i) -> void:
	for frame in range(2):
		await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	var name := "user://qa_%s_%dx%d.png" % [kind, dimensions.x, dimensions.y]
	_check(result != null and not result.is_empty() and result.get_size() == dimensions and
		result.save_png(name) == OK,
		kind + " actual native compositor capture " + str(dimensions))
	print("CATCH_SETTINGS_CAPTURE ", ProjectSettings.globalize_path(name))
	captures += 1


func _near_rect(a: Rect2, b: Rect2, tolerance: float) -> bool:
	return a.position.distance_to(b.position) < tolerance and a.size.distance_to(b.size) < tolerance


func _contains_label(node: Node) -> bool:
	if node is Label or node is RichTextLabel:
		return true
	for child in node.get_children():
		if _contains_label(child):
			return true
	return false


func _check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures.append(title)
		printerr("CATCH_SETTINGS_VISUAL_FAIL ", title)
