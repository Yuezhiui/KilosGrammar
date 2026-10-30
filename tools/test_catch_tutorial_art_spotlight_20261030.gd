extends SceneTree

# Catch-only regression for authored artwork and a cutout that matches the
# visible target at three window sizes, including a live resize and routing.
const SCENE := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const WRAPPER_PATH := "res://ui/play/gameplay/gameplay.tscn"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("CATCH SPOTLIGHT FAIL: ", description)


func _near(a: Vector2, b: Vector2, tolerance := 1.0) -> bool:
	return a.distance_to(b) <= tolerance


func _target_for_step(game: Control, id: String) -> CanvasItem:
	match id:
		"movement":
			return game.basket_sprite
		"seconds":
			return game.timer_plaque
		"lives":
			return game.lives_plaque
		"score":
			return game.score_plaque
		"pause":
			return game.pause_plaque
		_:
			return game.prompt_label


func _verify_step(game: Control, label: String) -> void:
	var entry: Dictionary = game._tutorial_steps()[game.tutorial_step_index]
	var id := String(entry["id"])
	var target := _target_for_step(game, id)
	var focus := Rect2(game.tutorial_focus.position, game.tutorial_focus.size)
	var overlay := game.tutorial_overlay as Control
	var dim := game.tutorial_dim as ColorRect
	var target_size := Vector2.ZERO
	var target_offset := Vector2.ZERO
	if target is Control:
		target_size = (target as Control).size
	else:
		var sr := (target as Sprite2D).get_rect()
		target_offset = sr.position
		target_size = sr.size
	var target_to_overlay: Transform2D = overlay.get_global_transform_with_canvas().affine_inverse() * target.get_global_transform_with_canvas()
	var center: Vector2 = target_to_overlay * (target_offset + target_size * 0.5)
	_check(focus.has_point(center), label + " " + id + " cutout covers component center")
	_check(focus.has_area() and focus.position.x >= -0.5 and focus.position.y >= -0.5
		and focus.end.x <= overlay.size.x + 0.5 and focus.end.y <= overlay.size.y + 0.5,
		label + " " + id + " focus inside the actual overlay")
	_check(_near(dim.position, Vector2.ZERO) and _near(dim.size, overlay.size),
		label + " " + id + " shader viewport fills overlay")
	var uv: Vector4 = (dim.material as ShaderMaterial).get_shader_parameter("focus_rect")
	_check(_near(Vector2(uv.x, uv.y) * dim.size, focus.position, 0.35)
		and _near(Vector2(uv.z, uv.w) * dim.size, focus.size, 0.35),
		label + " " + id + " shader transparency equals yellow outline")
	_check(game.tutorial_counter.text == "STEP %d OF 5" % [game.tutorial_step_index + 1],
		label + " " + id + " exact Step x OF 5 text")
	for name in ["BackButton", "NextButton", "ReplayButton", "SkipButton"]:
		var button := game.tutorial_card.get_node(name) as Button
		_check(button.focus_mode == Control.FOCUS_ALL
			and button.mouse_filter == Control.MOUSE_FILTER_STOP,
			label + " " + name + " keeps keyboard activation and full hitbox")
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			_check(button.get_theme_stylebox(state) is StyleBoxEmpty,
				label + " " + name + " " + state + " has no native background")
		var art_name: String = String(name).replace("Button", "Art")
		var art := button.get_node(art_name) as TextureRect
		_check(art.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			label + " " + name + " PNG cannot swallow button input")
		var ring := button.get_node("KeyboardFocusRing") as Panel
		_check(ring.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			label + " " + name + " keyboard focus ring cannot swallow input")


func _case(resolution: Vector2i, mode: String) -> void:
	root.size = resolution
	root.content_scale_size = resolution
	await process_frame
	var game := SCENE.instantiate() as Control
	game.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity":"Catch the Word", "topic":"Noun", "difficulty":"Easy",
		"game_mode":mode, "guided_tutorial":true, "camera_live":false, "keyboard_mode":true})
	for i in range(3):
		await process_frame
	var tag := "%s %s" % [resolution, mode]
	_check(game.is_tutorial_active(), tag + " activates guide before gameplay")
	var card := game.tutorial_card as Panel
	_check((card.get_node("PanelArt") as TextureRect).texture != null
		and (card.get_node("TitleBanner") as TextureRect).texture != null,
		tag + " cream panel and yellow title art loaded")
	for path in ["BackButton/BackArt", "NextButton/NextArt", "ReplayButton/ReplayArt",
			"SkipButton/SkipArt"]:
		_check((card.get_node(path) as TextureRect).texture != null,
			tag + " image button " + path + " loaded")
	_check(not game.has_node("GuidedTutorialLayer/GuidedTutorial/TutorialArrow"),
		tag + " no directional tutorial arrow")
	game.tutorial_next.grab_focus()
	await process_frame
	var next_focus_ring := game.tutorial_next.get_node("KeyboardFocusRing") as Panel
	_check(root.gui_get_focus_owner() == game.tutorial_next and next_focus_ring.visible,
		tag + " keyboard focus on NEXT has visible yellow indication")
	game.tutorial_replay.grab_focus()
	await process_frame
	_check(not next_focus_ring.visible
		and (game.tutorial_replay.get_node("KeyboardFocusRing") as Panel).visible,
		tag + " keyboard focus transitions cleanly between PNG buttons")
	game.tutorial_replay.release_focus()
	await process_frame
	_check(not (game.tutorial_replay.get_node("KeyboardFocusRing") as Panel).visible,
		tag + " losing focus hides outline and native button remains transparent")
	_check(game.tutorial_back.disabled
		and game.tutorial_back_art.texture.resource_path.ends_with("back_disabled.png"),
		tag + " Back disabled state uses authored grey PNG")
	for index in range(5):
		_verify_step(game, tag)
		if index > 0:
			_check(not game.tutorial_back.disabled
				and game.tutorial_back_art.texture.resource_path.ends_with("back_enabled.png"),
				tag + " enabled Back uses authored blue PNG")
		if index < 4:
			game.tutorial_next_step()
	_check(game.tutorial_next.text == "START COUNTDOWN"
		and game.tutorial_start_label.visible, tag + " final guide has START COUNTDOWN")
	# Illustrator can edit these two exported values in the inspector. Both
	# actual pixel focus and shader hole must follow the adjustment together.
	for index in range(4):
		game.tutorial_previous_step()
	var original: Vector2 = game.tutorial_focus.position
	game.tutorial_focus_offset = Vector2(7.0, -3.0)
	game._refresh_tutorial_focus()
	_check(_near(game.tutorial_focus.position - original, Vector2(7.0, -3.0), 0.6),
		tag + " Inspector offset moves focus by exact authored amount")
	_verify_step(game, tag + " adjusted")
	var padded_from := Rect2(game.tutorial_focus.position, game.tutorial_focus.size)
	game.tutorial_focus_padding += Vector2(4.0, 6.0)
	game._refresh_tutorial_focus()
	var padded_to := Rect2(game.tutorial_focus.position, game.tutorial_focus.size)
	_check(_near(padded_to.position - padded_from.position, Vector2(-4.0, -6.0), 0.6)
		and _near(padded_to.size - padded_from.size, Vector2(8.0, 12.0), 0.6),
		tag + " Inspector padding expands the cutout on all sides")
	_verify_step(game, tag + " padded")
	game.queue_free()
	await process_frame


func _resize_case() -> void:
	root.size = SIZES[0]
	root.content_scale_size = SIZES[0]
	var game := SCENE.instantiate() as Control
	game.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"guided_tutorial":true, "game_mode":"Seconds", "topic":"Noun",
		"difficulty":"Easy"})
	for i in range(3):
		await process_frame
	for dims in SIZES:
		root.size = dims
		root.content_scale_size = dims
		for frame in range(4):
			await process_frame
		# Verify AFTER the HUD's normal resize handler, rather than correcting
		# focus manually inside the test.
		_verify_step(game, "live resize %s" % dims)
	game.queue_free()
	await process_frame


func _countdown_gate() -> void:
	root.size = SIZES[0]
	root.content_scale_size = SIZES[0]
	var wrapper_scene := load(WRAPPER_PATH) as PackedScene
	if wrapper_scene == null:
		_check(false, "gameplay router scene must load for before-countdown validation")
		return
	var wrapper := wrapper_scene.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({"activity":"Catch the Word", "game_mode":"Seconds",
		"topic":"Noun", "difficulty":"Easy", "guided_tutorial":true,
		"camera_live":false, "keyboard_mode":true, "start_countdown":true})
	for frame in range(4):
		await process_frame
	var game := wrapper.active_game as Control
	_check(game != null and game.is_tutorial_active() and wrapper.guided_stage == "tutorial"
		and wrapper.countdown_panel == null, "real gameplay router opens guide before 3-2-1")
	if game != null:
		for index in range(4):
			game.tutorial_next_step()
			_check(wrapper.guided_stage == "tutorial" and wrapper.countdown_panel == null,
				"real router remains on guide through step %d" % [index + 2])
		game.tutorial_next_step()
		for frame in range(3):
			await process_frame
		_check(wrapper.guided_stage == "countdown" and wrapper.countdown_panel != null
			and wrapper.countdown_value == 3, "3-2-1 begins only after final guide step")
	wrapper.queue_free()
	await process_frame


func _run() -> void:
	for dims in SIZES:
		for mode in ["Seconds", "Lives"]:
			await _case(dims, mode)
	await _resize_case()
	await _countdown_gate()
	print("CATCH ART + OVERLAY GEOMETRY: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
