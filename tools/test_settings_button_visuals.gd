extends SceneTree

# Run with Godot 4.7.2:
#   Godot --headless --path . --script res://tools/test_settings_button_visuals.gd
# Checks real routed Settings controls at each supported QA viewport.
# Restores mixer values, window mode, and the original user settings file.
const MENU := "res://main_menu.tscn"
const HOVER_SOUND := preload("res://assets/audio/lexispell_intro/button_hover.wav")
const CLICK_SOUND := preload("res://assets/audio/lexispell_intro/button_click.wav")
const SETTINGS_FILE := "user://kilos_settings.cfg"
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const TABS := ["settings", "controls", "camera"]
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
			var sidebar := panel.find_child("SidebarPanel", true, false) as Control
			_check(sidebar != null and _fully_inside(sidebar.get_global_rect(), board.get_global_rect(), 2.0), "%s sidebar extends past board" % resolution)
			for tab_name in TABS:
				var sidebar_button := panel.find_child("Sidebar" + tab_name.capitalize() + "Tab", true, false) as Button
				_check_button(sidebar_button, viewport_rect, "%s sidebar/%s" % [resolution, tab_name], router)
				if sidebar_button != null and sidebar != null:
					_check(_fully_inside(sidebar_button.get_global_rect(), sidebar.get_global_rect(), 2.5), "%s sidebar/%s extends outside sidebar panel: %s" % [resolution, tab_name, sidebar_button.get_global_rect()])
			var home := panel.find_child("BackButton", true, false) as Button
			_check_button(home, viewport_rect, "%s Home" % resolution, router)

			for tab_name in TABS:
				var sidebar_button := panel.find_child("Sidebar" + tab_name.capitalize() + "Tab", true, false) as Button
				if sidebar_button != null:
					sidebar_button.pressed.emit()
					await process_frame
					_check(String(panel.get("_active_tab")) == tab_name, "%s %s sidebar press did not activate page" % [resolution, tab_name])
				for button_tab in TABS:
					_check_tab_art(panel, "Sidebar" + button_tab.capitalize() + "Tab", button_tab, tab_name, true, resolution)
				if tab_name != "settings":
					await _check_aux_page_reachability(panel, board, scroll, tab_name, resolution)
			panel.call("_switch_tab", "settings")
			await process_frame
			for node_name in ["MuteCheck", "FullscreenCheck"]:
				var toggle := panel.find_child(node_name, true, false) as CheckButton
				_check_button(toggle, viewport_rect, "%s %s" % [resolution, node_name], router, false)
				if toggle != null:
					scroll.ensure_control_visible(toggle)
					await process_frame
					_check(_fully_inside(toggle.get_global_rect(), scroll.get_global_rect(), 2.0), "%s %s clipped even after scrolling into view: toggle=%s scroll=%s" % [resolution, node_name, toggle.get_global_rect(), scroll.get_global_rect()])
					_check(_fully_inside(toggle.get_global_rect(), viewport_rect, 2.0), "%s %s clipped by viewport: %s" % [resolution, node_name, toggle.get_global_rect()])
					print("TOGGLE ", resolution, " ", node_name, " ", toggle.get_global_rect(), " scroll_y=", scroll.scroll_vertical)
			if resolution == SIZES[0]:
				_check_state_feedback(panel)
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


func _check_tab_art(panel: Control, node_name: String, button_tab: String, active_tab: String, sidebar: bool, size: Vector2i) -> void:
	var button := panel.find_child(node_name, true, false) as Button
	if button == null:
		return
	var style := button.get_theme_stylebox("normal") as StyleBoxTexture
	_check(style != null and style.texture != null, "%s %s missing sprite normal style" % [size, node_name])
	if style == null or style.texture == null:
		return
	var actual := style.texture.resource_path.get_file()
	var expected := ("tab_%s_%s.png" % [button_tab, "green" if button_tab == active_tab else "cream"]) if sidebar or button_tab == active_tab else "button_blank_purple.png"
	_check(actual == expected, "%s %s wrong sprite for selected=%s: %s expected %s" % [size, node_name, active_tab, actual, expected])
	if not sidebar:
		var overlay := button.get_node_or_null("FooterLightInk") as TextureRect
		_check(overlay != null and overlay.visible == (button_tab != active_tab), "%s %s footer lettering state incorrect" % [size, node_name])


func _check_state_feedback(panel: Control) -> void:
	# Compare the resources Godot actually draws, including texture and tint.
	# If hover/pressed share identical art with normal, pointer states are invisible.
	for node_name in ["SidebarSettingsTab", "SidebarControlsTab", "SidebarCameraTab", "SettingsTab", "ControlsTab", "CameraTab", "BackButton", "MuteCheck", "FullscreenCheck"]:
		var button := panel.find_child(node_name, true, false) as BaseButton
		if button == null:
			continue
		var normal := button.get_theme_stylebox("normal")
		var hover := button.get_theme_stylebox("hover")
		var pressed := button.get_theme_stylebox("pressed")
		_check(not _identical_style(normal, hover), node_name + " has no distinct hover artwork/color")
		_check(not _identical_style(normal, pressed), node_name + " has no distinct pressed artwork/color")
		_check(button.has_theme_stylebox_override("focus"), node_name + " lacks visible focus style override")


func _check_aux_page_reachability(panel: Control, board: Control, scroll: ScrollContainer, tab_name: String, size: Vector2i) -> void:
	var page := panel.find_child(tab_name.capitalize() + "Page", true, false) as VBoxContainer
	if page == null:
		failures.append("%s %s page is missing" % [size, tab_name])
		return
	var artwork := board.find_child("BoardArtwork", true, false) as NinePatchRect
	var rail_top := 0.0
	var rail_end := 0.0
	if artwork != null:
		rail_end = artwork.get_global_rect().end.y
		rail_top = rail_end - float(artwork.patch_margin_bottom)
	for position in ["initial", "end"]:
		if position == "end" and page.get_child_count() > 0:
			var last := page.get_child(page.get_child_count() - 1) as Control
			if last != null:
				scroll.ensure_control_visible(last)
				await process_frame
				var last_labels: Array[Label] = []
				_collect_labels(last, last_labels)
				if not last_labels.is_empty():
					var final_label: Label = last_labels.back()
					_check(_fully_inside(final_label.get_global_rect(), scroll.get_global_rect(), 2.0), "%s %s final label unreachable after scroll-to-end: label=%s scroll=%s" % [size, tab_name, final_label.get_global_rect(), scroll.get_global_rect()])
		var visible_labels: Array[Label] = []
		_collect_labels(page, visible_labels)
		var visible_count := 0
		var rail_overlap: Array[String] = []
		for label in visible_labels:
			if not label.is_visible_in_tree() or label.get_global_rect().size.y < 1.0:
				continue
			var visible_slice := label.get_global_rect().intersection(scroll.get_global_rect())
			if visible_slice.get_area() <= 1.0:
				continue
			visible_count += 1
			if artwork != null and size.y <= 600 and visible_slice.end.y > rail_top + 2.0 and visible_slice.position.y < rail_end - 2.0:
				rail_overlap.append("%s @ %s" % [label.name, visible_slice])
		_check(visible_count > 0, "%s %s %s scroll leaves no visible text" % [size, tab_name, position])
		_check(rail_overlap.is_empty(), "%s %s %s text extends beneath board lower rail y=%.1f..%.1f: %s" % [size, tab_name, position, rail_top, rail_end, ", ".join(rail_overlap)])
		print("PAGE ", size, " ", tab_name, " ", position, " visible_labels=", visible_count, " scroll_y=", scroll.scroll_vertical, " lower_rail_y=", rail_top, "..", rail_end)


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
	for node_name in ["SidebarSettingsTab", "ControlsTab", "BackButton", "MuteCheck", "FullscreenCheck"]:
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
	var mute := panel.find_child("MuteCheck", true, false) as CheckButton
	if mute != null:
		mute.button_pressed = true
		_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Mute CheckButton failed to mute Master")
		mute.button_pressed = false
		_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Mute CheckButton failed to unmute Master")
	var display := panel.find_child("FullscreenCheck", true, false) as CheckButton
	if display != null:
		_check(display.tooltip_text.is_empty(), "Fullscreen CheckButton must not show native dark popup")
	for entry in [["VolumeSlider", "VolumeValue", "Master", 100], ["MusicSlider", "MusicValue", "KilosMusic", 100], ["EffectsSlider", "EffectsValue", "KilosSFX", 100]]:
		var slider := panel.find_child(entry[0], true, false) as HSlider
		if slider != null:
			slider.value = 100.0
	print("MIXER verified Master=37%, KilosMusic=64%, KilosSFX=22%, mute toggles on/off")


func _clean_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		var player := node as AudioStreamPlayer
		player.stop()
		player.stream = null
	for child in node.get_children():
		_clean_audio(child)
