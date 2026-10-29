extends SceneTree

# Run with Godot 4.7.2:
#   Godot --headless --path . --script res://tools/test_settings_button_visuals.gd
# Checks real routed Settings controls at each supported QA viewport.
# Restores mixer values, window mode, and the original user settings file.
const MENU := "res://ui/main_menu/main_menu.tscn"
const HOVER_SOUND := preload("res://assets/audio/lexispell_intro/button_hover.wav")
const CLICK_SOUND := preload("res://assets/audio/lexispell_intro/button_click.wav")
const SETTINGS_FILE := "user://kilos_settings.cfg"
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _run() -> void:
	var saved_file_exists := FileAccess.file_exists(SETTINGS_FILE)
	var saved_file := FileAccess.get_file_as_bytes(SETTINGS_FILE) if saved_file_exists else PackedByteArray()
	var saved_mode := DisplayServer.window_get_mode()
	var saved_window_size := DisplayServer.window_get_size()
	var saved_buses: Dictionary = {}
	for bus_name in ["Master", "KilosMusic", "KilosSFX"]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			saved_buses[bus_name] = [AudioServer.get_bus_volume_db(idx), AudioServer.is_bus_mute(idx)]

	# Resolve after the SceneTree registers autoloads such as PoseService.
	var app := (load(MENU) as PackedScene).instantiate() as Control
	if app == null or not app.has_method("_on_panel_requested"):
		push_error("Cannot instantiate scripted main menu; check concurrent Settings/main menu parse errors")
		if app != null:
			app.free()
		quit(1)
		return
	root.add_child(app)
	await process_frame
	app.call("_on_panel_requested", "settings", {})
	await process_frame
	var panel := app.get("active_panel") as Control
	var router := app.get_node_or_null("ButtonSounds")
	_check(panel != null and String(app.get("current_route")) == "settings", "Main menu did not mount its real Settings panel")
	_check(router != null, "Main menu did not mount shared ButtonSounds router")

	if panel != null:
		for resolution in SIZES:
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_size(resolution)
			root.content_scale_size = resolution
			root.size = resolution
			app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			await process_frame
			panel.call("_apply_responsive_layout")
			await process_frame
			await process_frame
			var viewport_rect := Rect2(Vector2.ZERO, Vector2(resolution))
			var board := panel.find_child("SettingsCard", true, false) as Control
			var scroll := panel.find_child("PageScroll", true, false) as ScrollContainer
			_check(board != null and scroll != null, "%s missing settings board or scroll" % resolution)
			if board == null or scroll == null:
				continue
			print("VIEWPORT ", resolution, " board=", board.get_global_rect(), " scroll=", scroll.get_global_rect())
			_check(_fully_inside(board.get_global_rect(), viewport_rect, 1.5), "%s board extends beyond viewport: %s" % [resolution, board.get_global_rect()])
			for obsolete in ["SidebarPanel", "SidebarSettingsTab", "SidebarControlsTab",
					"SidebarCameraTab", "ControlsPage", "CameraPage"]:
				_check(panel.find_child(obsolete, true, false) == null,
						"%s obsolete button/page not removed: %s" % [resolution, obsolete])
			_check((panel.find_child("SettingsPage", true, false) as Control).visible,
				"%s sole Audio & Display page stays visible" % resolution)
			var home := panel.find_child("BackButton", true, false) as Button
			_check_button(home, viewport_rect, "%s Home" % resolution, router)

			panel.call("_show_audio_display")
			await process_frame
			_check(panel.find_child("MuteCheck", true, false) == null, "%s obsolete mute switch still exists" % resolution)
			_check(panel.find_child("ToggleMuteallaudioRow", true, false) == null, "%s obsolete mute row still exists" % resolution)
			for node_name in ["FullscreenCheck"]:
				var toggle := panel.find_child(node_name, true, false) as CheckButton
				_check_button(toggle, viewport_rect, "%s %s" % [resolution, node_name], router, false)
				if toggle != null:
					scroll.ensure_control_visible(toggle)
					await process_frame
					_check(_fully_inside(toggle.get_global_rect(), scroll.get_global_rect(), 2.0), "%s %s clipped even after scrolling into view: toggle=%s scroll=%s" % [resolution, node_name, toggle.get_global_rect(), scroll.get_global_rect()])
					_check(_fully_inside(toggle.get_global_rect(), viewport_rect, 2.0), "%s %s clipped by viewport: %s" % [resolution, node_name, toggle.get_global_rect()])
					print("TOGGLE ", resolution, " ", node_name, " ", toggle.get_global_rect(), " scroll_y=", scroll.scroll_vertical)
			if resolution == SIZES[0]:
				await _check_state_feedback(panel)
				await _check_sound_routes(panel, router)
				_check_live_mixer(panel)
		var home_to_main := panel.find_child("BackButton", true, false) as Button
		if home_to_main != null:
			home_to_main.pressed.emit()
			await process_frame
			_check(String(app.get("current_route")) == "main", "Home press did not return to the main menu")

	_clean_audio(app)
	app.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	for bus_name in saved_buses:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, saved_buses[bus_name][0])
			AudioServer.set_bus_mute(idx, saved_buses[bus_name][1])
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(saved_mode)
		if saved_mode == DisplayServer.WINDOW_MODE_WINDOWED:
			DisplayServer.window_set_size(saved_window_size)
	if saved_file_exists:
		var f := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
		if f != null:
			f.store_buffer(saved_file)
		else:
			failures.append("Cannot restore original user settings file")
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	for failure in failures:
		push_error(failure)
	print("SETTINGS_BUTTON_VISUALS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _fully_inside(inner: Rect2, outer: Rect2, tolerance: float) -> bool:
	return inner.position.x >= outer.position.x - tolerance \
		and inner.position.y >= outer.position.y - tolerance \
		and inner.end.x <= outer.end.x + tolerance \
		and inner.end.y <= outer.end.y + tolerance


func _check_button(button: BaseButton, viewport_rect: Rect2, title: String, router: Node, test_bounds: bool = true) -> void:
	_check(button != null, title + " missing")
	if button == null:
		return
	_check(button.is_visible_in_tree() and not button.disabled, title + " hidden or disabled")
	_check(button.focus_mode == Control.FOCUS_ALL, title + " cannot receive keyboard focus")
	_check(button.tooltip_text.is_empty(), title + " opens an unwanted native black tooltip")
	if test_bounds:
		_check(_fully_inside(button.get_global_rect(), viewport_rect, 2.0), title + " clipped by viewport: " + str(button.get_global_rect()))
	print("BUTTON ", title, " ", button.get_global_rect(), " visible=", button.is_visible_in_tree())
	for signal_name in ["mouse_entered", "focus_entered", "button_down"]:
		var matches := 0
		for connection: Dictionary in button.get_signal_connection_list(signal_name):
			var callback: Callable = connection["callable"]
			if callback.get_object() == router:
				matches += 1
		_check(matches == 1, title + " %s expected one shared SFX callback, got %d" % [signal_name, matches])
	button.grab_focus()
	_check(button.get_viewport().gui_get_focus_owner() == button, title + " did not take focus")


func _check_state_feedback(panel: Control) -> void:
	# Settings HOME deliberately uses the exact Credits HOME.png TextureRect.
	# All HOME StyleBoxes are transparent (including focus); hover and pressed
	# feedback are animated changes to the actual Button transform, not separate
	# textures or native focus outlines. Test the real animation over time.
	for node_name in ["BackButton", "FullscreenCheck"]:
		var button := panel.find_child(node_name, true, false) as BaseButton
		if button == null:
			continue
		if node_name == "BackButton":
			var art := button.get_node_or_null("Artwork") as TextureRect
			_check(art != null and art.texture != null
				and art.texture.resource_path == "res://Components/Credits/Redesign/HOME.png",
				"HOME must display the exact Credits editor-editable TextureRect artwork")
			for state in ["normal", "hover", "pressed", "focus"]:
				_check(_clear_style(button.get_theme_stylebox(state)),
					"HOME " + state + " draws a native button frame or focus stroke over Credits PNG")
		else:
			var normal := button.get_theme_stylebox("normal")
			var hover := button.get_theme_stylebox("hover")
			var pressed := button.get_theme_stylebox("pressed")
			_check(not _identical_style(normal, hover), node_name + " has no distinct hover artwork/color")
			_check(not _identical_style(normal, pressed), node_name + " has no distinct pressed artwork/color")
			_check(button.has_theme_stylebox_override("focus"), node_name + " lacks focus style override")
		var rest_scale := button.scale
		button.mouse_entered.emit()
		await create_timer(0.33).timeout
		_check(button.scale.x >= rest_scale.x + 0.025 and button.scale.y >= rest_scale.y + 0.025,
			node_name + " hover feedback did not visibly enlarge button")
		button.mouse_exited.emit()
		await create_timer(0.33).timeout
		_check(button.scale.distance_to(Vector2.ONE) <= 0.02,
			node_name + " hover exit did not restore authored transform")
		button.button_down.emit()
		await create_timer(0.085).timeout
		_check(button.scale.x <= 0.97 and button.scale.y <= 0.93,
			node_name + " press did not visibly shrink button")
		button.button_up.emit()
		button.mouse_exited.emit()
		await create_timer(0.33).timeout
		_check(button.scale.distance_to(Vector2.ONE) <= 0.02,
			node_name + " button release did not restore authored transform")


func _clear_style(value: StyleBox) -> bool:
	# Credits and Settings use transparent StyleBoxEmpty, not StyleBoxFlat.
	if value is StyleBoxEmpty:
		return true
	if not value is StyleBoxFlat:
		return false
	var flat := value as StyleBoxFlat
	return flat.bg_color.a <= 0.001 and flat.border_width_left == 0 \
		and flat.border_width_top == 0 and flat.border_width_right == 0 \
		and flat.border_width_bottom == 0


func _collect_labels(node: Node, labels: Array[Label]) -> void:
	if node is Label:
		labels.append(node as Label)
	for child in node.get_children():
		_collect_labels(child, labels)


func _identical_style(a: StyleBox, b: StyleBox) -> bool:
	if a == null or b == null:
		return a == b
	if a == b:
		return true
	if a is StyleBoxTexture and b is StyleBoxTexture:
		var x := a as StyleBoxTexture
		var y := b as StyleBoxTexture
		return x.texture == y.texture and x.modulate_color == y.modulate_color
	if a is StyleBoxFlat and b is StyleBoxFlat:
		var x := a as StyleBoxFlat
		var y := b as StyleBoxFlat
		return x.bg_color == y.bg_color and x.border_color == y.border_color
	return false


func _check_sound_routes(panel: Control, router: Node) -> void:
	if router == null:
		return
	# Exercise actual dynamically constructed Settings controls with the
	# same stream player that the shared menu sound router uses.
	for node_name in ["BackButton", "FullscreenCheck"]:
		var button := panel.find_child(node_name, true, false) as BaseButton
		if button == null:
			continue
		button.set_meta("kilos_button_sfx_pointer_origin", Vector2(-10000, -10000))
		await process_frame
		var hover_before := _sound_players(router).size()
		button.mouse_entered.emit()
		var hovers := _sound_players(router)
		_check(hovers.size() == hover_before + 1, node_name + " did not play exactly one hover sound")
		if hovers.size() > hover_before:
			_check(hovers.back().stream == HOVER_SOUND and hovers.back().bus == "KilosSFX", node_name + " hover used wrong stream/bus")
		var click_before := _sound_players(router).size()
		button.button_down.emit()
		var clicks := _sound_players(router)
		_check(clicks.size() == click_before + 1, node_name + " did not play exactly one click sound")
		if clicks.size() > click_before:
			_check(clicks.back().stream == CLICK_SOUND and clicks.back().bus == "KilosSFX", node_name + " click used wrong stream/bus")


func _sound_players(router: Node) -> Array[AudioStreamPlayer]:
	var players: Array[AudioStreamPlayer] = []
	for child in router.get_children():
		if child is AudioStreamPlayer:
			players.append(child as AudioStreamPlayer)
	return players


func _check_live_mixer(panel: Control) -> void:
	for entry in [["VolumeSlider", "VolumeValue", "Master", 37], ["MusicSlider", "MusicValue", "KilosMusic", 64], ["EffectsSlider", "EffectsValue", "KilosSFX", 22]]:
		var slider := panel.find_child(entry[0], true, false) as HSlider
		var label := panel.find_child(entry[1], true, false) as Label
		var idx := AudioServer.get_bus_index(entry[2])
		_check(idx >= 0 and slider != null and slider.editable and label != null, "%s live mixer slider missing" % entry[2])
		if idx < 0 or slider == null or label == null:
			continue
		slider.value = entry[3]
		_check(absf(db_to_linear(AudioServer.get_bus_volume_db(idx)) - float(entry[3]) / 100.0) < 0.01, "%s slider did not alter actual bus" % entry[2])
		_check(label.text == "%d%%" % entry[3], "%s value pill stale: %s" % [entry[2], label.text])
	var master_slider := panel.find_child("VolumeSlider", true, false) as HSlider
	if master_slider != null:
		master_slider.value = 0.0
		_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Master slider 0% must silence Master")
		master_slider.value = 37.0
		_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Master slider above 0% must restore sound")
	var display := panel.find_child("FullscreenCheck", true, false) as CheckButton
	if display != null:
		_check(display.tooltip_text.is_empty(), "Fullscreen CheckButton must not show native dark popup")
	for entry in [["VolumeSlider", "VolumeValue", "Master", 100], ["MusicSlider", "MusicValue", "KilosMusic", 100], ["EffectsSlider", "EffectsValue", "KilosSFX", 100]]:
		var slider := panel.find_child(entry[0], true, false) as HSlider
		if slider != null:
			slider.value = 100.0
	print("MIXER verified Master=37%, KilosMusic=64%, KilosSFX=22%, Master 0% silence")


func _clean_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		var player := node as AudioStreamPlayer
		player.stop()
		player.stream = null
	for child in node.get_children():
		_clean_audio(child)
