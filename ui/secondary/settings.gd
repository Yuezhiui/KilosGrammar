extends Control

signal requested(target: String, payload: Dictionary)

const FONT := preload("res://assets/fonts/TitanOne-Regular.ttf")
const TITLE_FONT_PATH := "res://assets/fonts/Comic Lemon.otf"
const BACKDROP_SCENE := preload("res://ui/shared/lexi_reference_backdrop.tscn")
const INK := Color("#474660")
const INK_DARK := Color("#3F3A57")
const CREAM := Color("#FDE4B9")
const MINT := Color("#74AB8E")
const MINT_LABEL := Color("#C5F1D9")
const GREEN := Color("#00886B")
const YELLOW := Color("#FFC23D")
const BLUE := Color("#7BC9EF")
const RED := Color("#FF4F66")

const MASTER_BUS := "Master"
const MUSIC_BUS := "KilosMusic"
const EFFECTS_BUS := "KilosSFX"

var _context: Dictionary = {}
var _active_tab := "settings"

var _outer_margin: MarginContainer
var _settings_card: PanelContainer
var _screen_stack: VBoxContainer
var _tabs_row: HBoxContainer
var _page_host: Control
var _card_heading: Label
var _pages: Dictionary = {}
var _tab_buttons: Dictionary = {}

var _volume_slider: HSlider
var _music_slider: HSlider
var _effects_slider: HSlider
var _volume_value: Label
var _music_value: Label
var _effects_value: Label
var _mute_check: CheckButton
var _fullscreen_check: CheckButton
var _slider_knob: Texture2D
var _title_font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_title_font = _load_title_font()
	_slider_knob = _make_slider_knob()
	_build_ui()
	_connect_controls()
	_sync_from_system()
	_switch_tab("settings")
	resized.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")
	_volume_slider.call_deferred("grab_focus")


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)


func _build_ui() -> void:
	var backdrop := BACKDROP_SCENE.instantiate() as Control
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_outer_margin = MarginContainer.new()
	_outer_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_outer_margin)

	_screen_stack = VBoxContainer.new()
	_screen_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	_screen_stack.add_theme_constant_override("separation", 8)
	_outer_margin.add_child(_screen_stack)

	var title := RichTextLabel.new()
	title.name = "SettingsTitle"
	title.custom_minimum_size.y = 58
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "[center][wave amp=40.0 freq=4.0 connected=1]SETTINGS[/wave][/center]"
	title.add_theme_font_override("normal_font", _title_font)
	title.add_theme_font_size_override("normal_font_size", 36)
	title.add_theme_color_override("default_color", CREAM)
	title.add_theme_color_override("font_outline_color", INK)
	title.add_theme_color_override("font_shadow_color", Color(INK.r, INK.g, INK.b, 0.55))
	title.add_theme_constant_override("outline_size", 5)
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	_screen_stack.add_child(title)

	var card_center := CenterContainer.new()
	card_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_center.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_screen_stack.add_child(card_center)

	_settings_card = PanelContainer.new()
	_settings_card.name = "SettingsCard"
	_settings_card.add_theme_stylebox_override("panel", _card_style())
	card_center.add_child(_settings_card)

	var card_padding := MarginContainer.new()
	card_padding.add_theme_constant_override("margin_left", 30)
	card_padding.add_theme_constant_override("margin_right", 30)
	card_padding.add_theme_constant_override("margin_top", 18)
	card_padding.add_theme_constant_override("margin_bottom", 18)
	_settings_card.add_child(card_padding)

	var card_stack := VBoxContainer.new()
	card_stack.add_theme_constant_override("separation", 8)
	card_padding.add_child(card_stack)

	var section_heading := HBoxContainer.new()
	section_heading.add_theme_constant_override("separation", 8)
	card_stack.add_child(section_heading)
	var heading_mark := Label.new()
	heading_mark.text = "●"
	heading_mark.add_theme_font_override("font", FONT)
	heading_mark.add_theme_font_size_override("font_size", 12)
	heading_mark.add_theme_color_override("font_color", YELLOW)
	section_heading.add_child(heading_mark)
	_card_heading = _label("AUDIO & DISPLAY", 16, CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	section_heading.add_child(_card_heading)

	card_stack.add_child(_separator())

	_page_host = Control.new()
	_page_host.custom_minimum_size = Vector2(0, 276)
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_stack.add_child(_page_host)
	_build_settings_page()
	_build_controls_page()
	_build_camera_page()

	_tabs_row = HBoxContainer.new()
	_tabs_row.name = "TabsRow"
	_tabs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabs_row.add_theme_constant_override("separation", 10)
	_screen_stack.add_child(_tabs_row)
	for tab_name in ["settings", "controls", "camera"]:
		var tab_button := _tab_button(tab_name.to_upper())
		tab_button.name = tab_name.capitalize() + "Tab"
		tab_button.unique_name_in_owner = true
		tab_button.pressed.connect(_switch_tab.bind(tab_name))
		_tabs_row.add_child(tab_button)
		_tab_buttons[tab_name] = tab_button

	var bottom_row := HBoxContainer.new()
	bottom_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	bottom_row.custom_minimum_size.y = 42
	_screen_stack.add_child(bottom_row)
	var home := _button("⌂  HOME", INK, 132)
	home.name = "BackButton"
	home.unique_name_in_owner = true
	home.pressed.connect(_request_main)
	bottom_row.add_child(home)


func _build_settings_page() -> void:
	var page := _new_page("SettingsPage")
	_pages["settings"] = page

	page.add_child(_section_label("AUDIO"))
	_volume_slider = _slider("VolumeSlider")
	_volume_value = _value_label("VolumeValue")
	page.add_child(_slider_row("MASTER VOLUME", _volume_slider, _volume_value))
	page.add_child(_separator(0.20))

	_music_slider = _slider("MusicSlider")
	_music_value = _value_label("MusicValue")
	page.add_child(_slider_row("MUSIC", _music_slider, _music_value))
	page.add_child(_separator(0.20))

	_effects_slider = _slider("EffectsSlider")
	_effects_value = _value_label("EffectsValue")
	page.add_child(_slider_row("EFFECTS", _effects_slider, _effects_value))
	page.add_child(_separator(0.20))

	_mute_check = _toggle("MuteCheck")
	page.add_child(_toggle_row("MUTE ALL AUDIO", "Master bus mute", _mute_check))
	page.add_child(_separator(0.34))

	page.add_child(_section_label("DISPLAY"))
	_fullscreen_check = _toggle("FullscreenCheck")
	page.add_child(_toggle_row("FULLSCREEN", "Switch between windowed and fullscreen", _fullscreen_check))


func _build_controls_page() -> void:
	var page := _new_page("ControlsPage")
	_pages["controls"] = page
	page.add_child(_section_label("CONTROLS"))
	page.add_child(_info_row("MENU NAVIGATION", "Mouse / touch, or Tab + Enter / Space.", MINT))
	page.add_child(_separator(0.22))
	page.add_child(_info_row("MOVEMENT ACTIVITIES", "LEFT • CENTER • RIGHT body movement after tracking integration.", BLUE))
	page.add_child(_separator(0.22))
	page.add_child(_info_row("PAUSE / BACK", "Use ESC where supported, or the visible BACK / HOME buttons.", YELLOW))
	page.add_child(_separator(0.34))
	page.add_child(_status_banner("BODY TRACKING: NOT CONNECTED", "Movement controls shown here are instructional until camera/CV integration is connected.", RED))


func _build_camera_page() -> void:
	var page := _new_page("CameraPage")
	_pages["camera"] = page
	page.add_child(_section_label("CAMERA"))
	page.add_child(_status_banner("CAMERA & TRACKING: NOT CONNECTED", "Settings does not open a camera device or report fake detection.", RED))
	page.add_child(_separator(0.28))

	var lane_title := _label("3-LANE PLAYER PREVIEW", 14, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	lane_title.modulate.a = 0.84
	page.add_child(lane_title)
	var lanes := HBoxContainer.new()
	lanes.add_theme_constant_override("separation", 10)
	page.add_child(lanes)
	lanes.add_child(_lane_chip("←  LEFT", BLUE))
	lanes.add_child(_lane_chip("●  CENTER", MINT))
	lanes.add_child(_lane_chip("RIGHT  →", YELLOW))
	page.add_child(_separator(0.28))
	page.add_child(_info_row("CALIBRATION", "The camera-check and calibration screens are UI previews until CV integration is available.", GREEN))


func _new_page(node_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = node_name
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 4)
	page.visible = false
	_page_host.add_child(page)
	return page


func _connect_controls() -> void:
	_volume_slider.value_changed.connect(_on_master_volume_changed)
	_music_slider.value_changed.connect(_on_music_volume_changed)
	_effects_slider.value_changed.connect(_on_effects_volume_changed)
	_mute_check.toggled.connect(_on_mute_toggled)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)


func _sync_from_system() -> void:
	_sync_bus_slider(MASTER_BUS, _volume_slider, _volume_value)
	_sync_bus_slider(MUSIC_BUS, _music_slider, _music_value)
	_sync_bus_slider(EFFECTS_BUS, _effects_slider, _effects_value)

	var master_index := AudioServer.get_bus_index(MASTER_BUS)
	var master_available := master_index >= 0
	_mute_check.disabled = not master_available
	if master_available:
		_mute_check.set_pressed_no_signal(AudioServer.is_bus_mute(master_index))
		_update_toggle_text(_mute_check)
	else:
		_mute_check.text = "UNAVAILABLE"

	var mode := DisplayServer.window_get_mode()
	var fullscreen := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	_fullscreen_check.set_pressed_no_signal(fullscreen)
	_update_toggle_text(_fullscreen_check)


func _sync_bus_slider(bus_name: String, slider: HSlider, value_label: Label) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	var available := bus_index >= 0
	slider.editable = available
	slider.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE
	if available:
		var linear := db_to_linear(AudioServer.get_bus_volume_db(bus_index))
		var percent := clampf(linear * 100.0, 0.0, 100.0)
		slider.set_value_no_signal(percent)
		value_label.text = "%d%%" % int(round(percent))
		value_label.add_theme_color_override("font_color", CREAM)
		slider.tooltip_text = "%s volume" % bus_name
	else:
		slider.set_value_no_signal(0.0)
		value_label.text = "BUS PENDING"
		value_label.add_theme_color_override("font_color", Color(CREAM.r, CREAM.g, CREAM.b, 0.62))
		slider.tooltip_text = "%s audio bus is not available in this scene yet." % bus_name


func _on_master_volume_changed(value: float) -> void:
	_set_bus_volume(MASTER_BUS, value, _volume_value)


func _on_music_volume_changed(value: float) -> void:
	_set_bus_volume(MUSIC_BUS, value, _music_value)


func _on_effects_volume_changed(value: float) -> void:
	_set_bus_volume(EFFECTS_BUS, value, _effects_value)


func _set_bus_volume(bus_name: String, value: float, value_label: Label) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		value_label.text = "BUS PENDING"
		return
	var linear := clampf(value / 100.0, 0.0001, 1.0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))
	value_label.text = "%d%%" % int(round(value))


func _on_mute_toggled(enabled: bool) -> void:
	var bus_index := AudioServer.get_bus_index(MASTER_BUS)
	if bus_index >= 0:
		AudioServer.set_bus_mute(bus_index, enabled)
	_update_toggle_text(_mute_check)


func _on_fullscreen_toggled(enabled: bool) -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	_update_toggle_text(_fullscreen_check)


func _update_toggle_text(toggle: CheckButton) -> void:
	toggle.text = "ON" if toggle.button_pressed else "OFF"


func _switch_tab(tab_name: String) -> void:
	if not _pages.has(tab_name):
		return
	_active_tab = tab_name
	var headings := {
		"settings": "AUDIO & DISPLAY",
		"controls": "CONTROL GUIDE",
		"camera": "CAMERA STATUS"
	}
	_card_heading.text = headings.get(tab_name, "SETTINGS")
	for key in _pages:
		var page: Control = _pages[key]
		page.visible = key == tab_name
	for key in _tab_buttons:
		var button: Button = _tab_buttons[key]
		_apply_tab_style(button, key == tab_name)


func _apply_tab_style(button: Button, active: bool) -> void:
	var base := GREEN if active else INK_DARK
	button.add_theme_stylebox_override("normal", _button_style(base, 11, 2))
	button.add_theme_stylebox_override("hover", _button_style(MINT if not active else GREEN.lightened(0.05), 11, 3))
	button.add_theme_stylebox_override("pressed", _button_style(base.darkened(0.08), 11, 1))
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", CREAM)


func _apply_responsive_layout() -> void:
	if not is_instance_valid(_outer_margin) or not is_instance_valid(_settings_card):
		return
	var horizontal := int(clampf(size.x * 0.060, 56.0, 116.0))
	var vertical := int(clampf(size.y * 0.020, 10.0, 24.0))
	_outer_margin.add_theme_constant_override("margin_left", horizontal)
	_outer_margin.add_theme_constant_override("margin_right", horizontal)
	_outer_margin.add_theme_constant_override("margin_top", vertical)
	_outer_margin.add_theme_constant_override("margin_bottom", vertical)
	_settings_card.custom_minimum_size = Vector2(
		clampf(size.x * 0.50, 660.0, 820.0),
		clampf(size.y * 0.47, 350.0, 440.0)
	)


func _slider_row(label_text: String, slider: HSlider, value_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 34
	row.add_theme_constant_override("separation", 12)
	var label := _label(label_text, 13, CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	label.custom_minimum_size.x = 148
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	row.add_child(slider)
	row.add_child(value_label)
	return row


func _toggle_row(label_text: String, hint_text: String, toggle: CheckButton) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 36
	row.add_theme_constant_override("separation", 12)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 1)
	row.add_child(text_box)
	text_box.add_child(_label(label_text, 13, CREAM, HORIZONTAL_ALIGNMENT_LEFT))
	var hint := _label(hint_text, 10, CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	hint.modulate.a = 0.66
	text_box.add_child(hint)
	row.add_child(toggle)
	return row


func _info_row(title_text: String, detail_text: String, accent: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 50
	row.add_theme_constant_override("separation", 14)
	var marker := PanelContainer.new()
	marker.custom_minimum_size = Vector2(8, 0)
	marker.add_theme_stylebox_override("panel", _flat_style(accent, 4))
	row.add_child(marker)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	row.add_child(text_box)
	text_box.add_child(_label(title_text, 13, CREAM, HORIZONTAL_ALIGNMENT_LEFT))
	var detail := _label(detail_text, 11, CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	detail.modulate.a = 0.74
	text_box.add_child(detail)
	return row


func _status_banner(title_text: String, detail_text: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := _flat_style(Color(INK_DARK.r, INK_DARK.g, INK_DARK.b, 0.92), 14)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = accent
	panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	box.add_child(_label(title_text, 13, accent, HORIZONTAL_ALIGNMENT_CENTER))
	var detail := _label(detail_text, 11, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	detail.modulate.a = 0.78
	box.add_child(detail)
	return panel


func _lane_chip(text_value: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 50
	var style := _flat_style(Color(accent.r, accent.g, accent.b, 0.18), 13)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = accent
	panel.add_theme_stylebox_override("panel", style)
	var label := _label(text_value, 13, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _slider(node_name: String) -> HSlider:
	var slider := HSlider.new()
	slider.name = node_name
	slider.unique_name_in_owner = true
	slider.custom_minimum_size = Vector2(220, 30)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = 100.0
	var track := StyleBoxFlat.new()
	track.bg_color = Color(CREAM.r, CREAM.g, CREAM.b, 0.28)
	track.corner_radius_top_left = 4
	track.corner_radius_top_right = 4
	track.corner_radius_bottom_left = 4
	track.corner_radius_bottom_right = 4
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = MINT
	slider.add_theme_stylebox_override("grabber_area", fill)
	var fill_hover := fill.duplicate() as StyleBoxFlat
	fill_hover.bg_color = MINT.lightened(0.08)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hover)
	slider.add_theme_icon_override("grabber", _slider_knob)
	slider.add_theme_icon_override("grabber_highlight", _slider_knob)
	slider.add_theme_icon_override("grabber_disabled", _slider_knob)
	return slider


func _value_label(node_name: String) -> Label:
	var label := _label("100%", 12, CREAM, HORIZONTAL_ALIGNMENT_RIGHT)
	label.name = node_name
	label.unique_name_in_owner = true
	label.custom_minimum_size.x = 88
	label.size_flags_horizontal = Control.SIZE_SHRINK_END
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _toggle(node_name: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.name = node_name
	toggle.unique_name_in_owner = true
	toggle.text = "OFF"
	toggle.custom_minimum_size = Vector2(96, 34)
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.add_theme_font_override("font", FONT)
	toggle.add_theme_font_size_override("font_size", 12)
	toggle.add_theme_color_override("font_color", CREAM)
	toggle.add_theme_color_override("font_hover_color", YELLOW)
	toggle.add_theme_color_override("font_pressed_color", CREAM)
	toggle.add_theme_color_override("font_focus_color", CREAM)
	return toggle


func _tab_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(154, 40)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("focus", _focus_style(11))
	return button


func _button(text_value: String, color: Color, width: float) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(width, 40)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", CREAM)
	button.add_theme_stylebox_override("normal", _button_style(color, 12, 3))
	button.add_theme_stylebox_override("hover", _button_style(MINT, 12, 4))
	button.add_theme_stylebox_override("pressed", _button_style(color.darkened(0.08), 12, 1))
	button.add_theme_stylebox_override("focus", _focus_style(12))
	return button


func _section_label(text_value: String) -> Label:
	var label := _label(text_value, 13, MINT_LABEL, HORIZONTAL_ALIGNMENT_LEFT)
	label.custom_minimum_size.y = 20
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _label(text_value: String, font_size: int, color: Color, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = alignment
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _separator(alpha: float = 0.38) -> HSeparator:
	var separator := HSeparator.new()
	var line := StyleBoxFlat.new()
	line.bg_color = Color(CREAM.r, CREAM.g, CREAM.b, alpha)
	line.content_margin_top = 1
	line.content_margin_bottom = 1
	separator.add_theme_stylebox_override("separator", line)
	return separator


func _card_style() -> StyleBoxFlat:
	var style := _flat_style(INK, 24)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(CREAM.r, CREAM.g, CREAM.b, 0.46)
	style.shadow_color = Color(0.12, 0.10, 0.16, 0.48)
	style.shadow_size = 8
	style.shadow_offset = Vector2(7, 9)
	return style


func _button_style(color: Color, radius: int, shadow: int) -> StyleBoxFlat:
	var style := _flat_style(color, radius)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(CREAM.r, CREAM.g, CREAM.b, 0.44)
	style.shadow_color = Color(0.12, 0.10, 0.16, 0.35)
	style.shadow_size = shadow
	style.shadow_offset = Vector2(0, shadow + 1)
	return style


func _focus_style(radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = YELLOW
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.expand_margin_left = 2
	style.expand_margin_top = 2
	style.expand_margin_right = 2
	style.expand_margin_bottom = 2
	return style


func _flat_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _make_slider_knob() -> Texture2D:
	var image := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var center := Vector2(9.5, 9.5)
	for y in range(20):
		for x in range(20):
			if Vector2(float(x), float(y)).distance_to(center) <= 8.5:
				image.set_pixel(x, y, CREAM)
	return ImageTexture.create_from_image(image)


func _request_main() -> void:
	requested.emit("main", _context.duplicate(true))


func _load_title_font() -> Font:
	var comic_font := FontFile.new()
	var error := comic_font.load_dynamic_font(TITLE_FONT_PATH)
	if error == OK:
		return comic_font
	push_warning("Comic Lemon title font could not be loaded; using Titan One fallback.")
	return FONT
