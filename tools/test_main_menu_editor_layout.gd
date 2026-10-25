extends SceneTree

## Original layout and animation timings with replacement editable PNGs.
var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	if not condition:
		errors.append(label)
		printerr("FAIL main menu editor layout: " + label)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var menu := (load("res://main_menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	# Original intro plays a staggered 1.12-second button/logo animation
	# before settling at the positions saved in main_menu.tscn.
	var play_intro := menu.get_node("MainLayer/CenterMenu/Play") as Button
	_check(play_intro.modulate.a < 1.0, "Original button entrance/fade starts on opening")
	await create_timer(1.55).timeout
	_check(menu.get("intro_done") == true, "Original intro finishes")
	var background := menu.get_node("Background") as TextureRect
	_check(background != null and background.texture != null, "Background has its own artwork")
	_check(background.get_script() == null, "Background has no procedural drawing script")
	_check(background.anchor_right == 1.0 and background.anchor_bottom == 1.0,
		"Background stays fixed and full-window")
	var original_texture := background.texture
	# Swap with an artwork image that is actually used by the current menu;
	# do not retain an orphan prototype PNG solely for this test.
	background.texture = load("res://Components/Main Panel/Original/green-play.png") as Texture2D
	_check(background.texture != original_texture, "Background texture can be swapped in the Inspector")
	background.texture = original_texture
	_check(not (menu.get_node("FallTimer") as Timer).is_stopped(),
		"Original floating grammar-card timer runs")
	_check(menu.get_node("FallingLayer").get_child_count() > 1,
		"Original floating grammar-card animation begins")

	var logo := menu.get_node("MainLayer/LogoGroup/Kilos") as TextureRect
	_check(logo.texture.resource_path.ends_with("KILOS GRAMMAR.png"), "New KILOS logo preserved")
	var letters := ["GrammarG", "GrammarR1", "GrammarA1", "GrammarM1",
		"GrammarM2", "GrammarA2", "GrammarR2"]
	for name in letters:
		var tile := menu.get_node("MainLayer/LogoGroup/" + name) as TextureRect
		_check(tile != null and tile.texture != null and tile.visible,
			"Independent editor-draggable tile " + name)
		_check(tile.size.is_equal_approx(Vector2(120, 120)),
			"Original GRAMMAR tile size preserved: " + name)
	var navigations := {
		"Tutorial": "MainLayer/CenterMenu/Tutorial",
		"Play": "MainLayer/CenterMenu/Play",
		"Quit": "MainLayer/CenterMenu/Quit",
		"Leaderboard": "MainLayer/LeftMenu/Leaderboard",
		"Settings": "MainLayer/LeftMenu/Settings",
		"Credits": "MainLayer/LeftMenu/Credits"
	}
	for name in navigations:
		var button := menu.get_node(navigations[name]) as Button
		_check(button != null and button.is_visible_in_tree(), "Visible draggable " + name + " button")
		var expected_size := Vector2(225, 55) if name in ["Leaderboard", "Settings", "Credits"] else Vector2(340, 72)
		_check(button.size.is_equal_approx(expected_size),
			"Original button dimensions preserved: " + name)
		_check(button.text == "", "No duplicate text overlays the painted " + name + " button")
		_check(button.get_theme_stylebox("normal") is StyleBoxTexture,
			"Button image is editable through Inspector: " + name)

	var board := menu.get_node("MainLayer/LeftMenu") as Control
	_check(board.position.is_equal_approx(Vector2(44, 474)),
		"Original left menu position preserved after entrance animation")
	_check((menu.get_node("MainLayer/CenterMenu") as Control).position.is_equal_approx(Vector2(470, 435)),
		"Original center menu position preserved after entrance animation")
	var original_pos := board.position
	board.position += Vector2(23, -12)
	await process_frame
	_check(board.position.distance_to(original_pos + Vector2(23, -12)) < 0.01,
		"Editor-selected navigation group stays where moved, not script-reset")
	board.position = original_pos
	var play := menu.get_node(navigations["Play"]) as Button
	var play_pos := play.position
	play.position += Vector2(12, 6)
	await process_frame
	_check(play.position.distance_to(play_pos + Vector2(12, 6)) < 0.01,
		"Editor drag changes real button location")
	play.position = play_pos
	for resolution in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = resolution
		menu.size = Vector2(resolution)
		await process_frame
		_check(background.get_global_rect().size.is_equal_approx(Vector2(resolution)),
			"Fixed background fills " + str(resolution))
		for name in navigations:
			var control := menu.get_node(navigations[name]) as Button
			var rect := control.get_global_rect()
			_check(rect.position.x >= -1.0 and rect.position.y >= -1.0
				and rect.end.x <= resolution.x + 1.0 and rect.end.y <= resolution.y + 1.0,
					"%s remains within %s" % [name, resolution])

	# Real navigation is retained, not just visuals.
	(menu.get_node(navigations["Leaderboard"]) as Button).pressed.emit()
	await process_frame
	_check(String(menu.get("current_route")) == "leaderboard", "Leaderboard button opens its live panel")
	menu.call("_return_to_main")
	await process_frame
	_check(String(menu.get("current_route")) == "main", "Back from Leaderboard returns to new Main Menu")
	(menu.get_node(navigations["Play"]) as Button).pressed.emit()
	await process_frame
	_check(String(menu.get("current_route")) == "student_setup", "Play button opens student setup")
	menu.call("_return_to_main")
	await process_frame
	(menu.get_node("FallTimer") as Timer).stop()
	menu.queue_free()
	await process_frame
	if errors.is_empty():
		print("PASS original button dimensions/placement/animations with new drag-and-drop PNG skin and navigation")
	quit(0 if errors.is_empty() else 1)
