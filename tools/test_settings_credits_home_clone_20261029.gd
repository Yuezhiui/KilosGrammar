extends SceneTree

# Native editor-authored Settings HOME versus Credits HOME at 3 resolutions.
# Godot --headless --path . -s res://tools/test_settings_credits_home_clone_20261029.gd
# With a graphical Godot runner and CAPTURE_SETTINGS_CREDITS_HOME=1, also saves
# three actual viewport screenshots to the user's Godot user-data directory.
const SETTINGS := preload("res://ui/secondary/settings/settings.tscn")
const CREDITS := preload("res://ui/secondary/credits/credits.tscn")
const CREDIT_HOME := "res://Components/Credits/Redesign/HOME.png"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const BUTTON_STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for resolution in SIZES:
		root.size = resolution
		root.content_scale_size = resolution
		var settings := SETTINGS.instantiate() as Control
		var credits := CREDITS.instantiate() as Control
		_check(settings != null and credits != null, "Settings and Credits scenes instantiate")
		if settings == null or credits == null:
			continue
		root.add_child(settings)
		settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		credits.visible = false
		root.add_child(credits)
		credits.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		await process_frame

		var settings_stage := settings.get_node_or_null("MainStage") as Control
		var credits_stage := credits.get_node_or_null("CreditsStage") as Control
		var home := settings.get_node_or_null("MainStage/BackButton") as Button
		var credit_home := credits.get_node_or_null("CreditsStage/BackButton") as Button
		_check(settings_stage != null and credits_stage != null and home != null and credit_home != null,
			"Both native editor-authored Home buttons exist at %s" % resolution)
		if home == null or credit_home == null or settings_stage == null or credits_stage == null:
			settings.queue_free()
			credits.queue_free()
			await process_frame
			continue

		var credit_factor := minf(float(resolution.x) / 1280.0, float(resolution.y) / 720.0)
		var expected_position := (Vector2(resolution) - Vector2(1280, 720) * credit_factor) * 0.5 + Vector2(1027, 3) * credit_factor
		var expected_size := Vector2(220, 80) * credit_factor
		_check(_close(credit_home.get_global_rect().position, expected_position),
			"Credits authored HOME position is source-of-truth at %s" % resolution)
		_check(_close(credit_home.get_global_rect().size, expected_size),
			"Credits authored HOME hitbox is source-of-truth at %s" % resolution)
		_check(_close(home.get_global_rect().position, credit_home.get_global_rect().position),
			"Settings HOME EXACTLY shares Credits global position at %s" % resolution)
		_check(_close(home.get_global_rect().size, credit_home.get_global_rect().size),
			"Settings HOME EXACTLY shares Credits global size at %s" % resolution)
		_check(_close(home.get_global_rect().position, expected_position),
			"Settings HOME tracks authored 1280-design canvas at %s" % resolution)
		_check(_close(home.get_global_rect().size, expected_size),
			"Settings HOME scales properly at %s" % resolution)
		_check(home.get_global_rect().position.x >= 0.0 and home.get_global_rect().end.x <= float(resolution.x) + 1.0
			and home.get_global_rect().position.y >= 0.0 and home.get_global_rect().end.y <= float(resolution.y) + 1.0,
			"Settings HOME clickable rectangle fully fits viewport at %s" % resolution)

		var artwork := home.get_node_or_null("Artwork") as TextureRect
		var credit_art := credit_home.get_node_or_null("Artwork") as TextureRect
		_check(artwork != null and credit_art != null, "Both buttons have editor-owned Artwork children")
		if artwork != null and credit_art != null:
			_check(artwork.texture != null and artwork.texture.resource_path == CREDIT_HOME,
				"Settings Artwork.texture uses Credits real HOME.png")
			_check(artwork.texture == credit_art.texture,
				"Both scenes share the exact imported Credits HOME texture resource")
			_check(artwork.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"Artwork cannot intercept mouse button clicks")
			_check(artwork.stretch_mode == credit_art.stretch_mode
				and artwork.expand_mode == credit_art.expand_mode,
				"Artwork uses Credits same fit/stretch properties")
			_check(_close(artwork.get_global_rect().position, home.get_global_rect().position)
				and _close(artwork.get_global_rect().size, home.get_global_rect().size),
				"Settings artwork fills the same actual hitbox as Credits")
			_check(_close(credit_art.get_global_rect().position, credit_home.get_global_rect().position)
				and _close(credit_art.get_global_rect().size, credit_home.get_global_rect().size),
				"Credits reference Artwork fills its hitbox")

		for state in BUTTON_STATES:
			_check(home.get_theme_stylebox(state) is StyleBoxEmpty,
				"Settings HOME %s is transparent with no extra focus stroke" % state)
		_check(home.focus_mode == Control.FOCUS_ALL and home.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND,
			"Settings HOME keeps focusable native clickable button")
		_check(home.tooltip_text == "" and artwork != null and artwork.tooltip_text == "",
			"Home and artwork do not show native tooltips")
		_check(home.mouse_entered.get_connections().size() > 0
			and home.button_down.get_connections().size() > 0
			and home.button_up.get_connections().size() > 0,
			"Settings existing hover/click visual animation signals are bound")
		_check(settings.get_node_or_null("MainStage/SettingsCard/CardPadding") != null
			and settings.find_child("MusicSlider", true, false) != null
			and settings.find_child("VolumeSlider", true, false) != null,
			"Settings main audio/display form remains intact")

		var original_rect := home.get_global_rect()
		settings.call("_apply_responsive_layout")
		settings.call("_apply_responsive_layout")
		_check(_close(home.get_global_rect().position, original_rect.position)
			and _close(home.get_global_rect().size, original_rect.size),
			"Repeated resize updates do not drift HOME from Credits geometry")
		if resolution == Vector2i(1280, 720):
			var authored_rect := home.get_rect()
			home.mouse_entered.emit()
			await create_timer(0.23).timeout
			_check(home.scale.x > 1.01 and home.scale.x <= 1.16,
				"HOME retains existing hover enlargement on the new PNG")
			home.mouse_exited.emit()
			await create_timer(0.44).timeout
			_check(home.scale.is_equal_approx(Vector2.ONE) and home.get_rect().is_equal_approx(authored_rect),
				"HOME returns to the exact original hitbox after hover")
			home.button_down.emit()
			await create_timer(0.11).timeout
			_check(home.scale.x < 0.96 and home.scale.y < 0.96,
				"HOME retains original click-squash animation")
			home.button_up.emit()
			home.mouse_exited.emit()
			await create_timer(0.44).timeout
			_check(home.scale.is_equal_approx(Vector2.ONE),
				"HOME resets cleanly after a click")

		var routes: Array[Dictionary] = []
		settings.requested.connect(func(route: String, payload: Dictionary) -> void:
			routes.append({"route": route, "payload": payload.duplicate(true)})
		)
		settings.set_context({"return_id": "settings_home_probe"})
		home.pressed.emit()
		_check(routes.size() == 1 and routes[0].get("route") == "main",
			"Home preserves Back-to-main requested route")
		if routes.size() > 0:
			_check(routes[0]["payload"].get("return_id") == "settings_home_probe",
				"Home preserves existing settings navigation context")

		if OS.get_environment("CAPTURE_SETTINGS_CREDITS_HOME") == "1":
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var img := root.get_texture().get_image()
				var file_path := OS.get_user_data_dir().path_join("settings_home_%dx%d.png" % [resolution.x, resolution.y])
				_check(img.save_png(file_path) == OK, "Native Settings screenshot saved")
				print("NATIVE SCREENSHOT ", file_path)
			else:
				print("NOTE screenshots require native graphical Godot (not --headless)")
		if artwork != null:
			# Inspector-authored texture must remain the sole source of the icon.
			# Simulate choosing a new resource in the editor; responsive code
			# must never silently replace it with an old Settings PNG.
			var alternate := ImageTexture.create_from_image(Image.create_empty(2, 2, false, Image.FORMAT_RGBA8))
			artwork.texture = alternate
			settings.call("_apply_responsive_layout")
			_check(artwork.texture == alternate,
				"Changing Artwork.texture in Inspector survives responsive layout")

		settings.queue_free()
		credits.queue_free()
		await process_frame

	if failures.is_empty():
		print("PASS Settings/Credits HOME clone: %d assertions, 1280/1600/1920" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("SETTINGS HOME CLONE QA: " + failure)
		print("FAIL Settings/Credits HOME clone: %d errors / %d assertions" % [failures.size(), checks])
		quit(1)


func _close(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) <= 0.75


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
