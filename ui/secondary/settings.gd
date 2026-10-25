extends Control

signal requested(target: String, payload: Dictionary)

const FONT := preload("res://assets/fonts/TitanOne-Regular.ttf")
const TITLE_FONT_PATH := "res://assets/fonts/Comic Lemon.otf"
const BACKDROP_SCENE := preload("res://ui/shared/lexi_reference_backdrop.tscn")
const SETTINGS_ART := "res://Components/Settings/Redesign/"
const CLASSROOM_ART := "res://Components/Shared/Redesign/classroom_bg.png"

const INK := Color("#474660")
const INK_DARK := Color("#152557")
const CREAM := Color("#FDE4B9")
const MINT := Color("#20C57A")
const MINT_LABEL := Color("#C5F1D9")
const GREEN := Color("#00886B")
const YELLOW := Color("#FFC23D")
const BLUE := Color("#7BC9EF")
const RED := Color("#FF4F66")

const MASTER_BUS := "Master"
const MUSIC_BUS := "KilosMusic"
const EFFECTS_BUS := "KilosSFX"
const SETTINGS_FILE := "user://kilos_settings.cfg"
const WINDOWED_SIZE := Vector2i(1600, 900)
# The main panel already owns one shared hover/click sound router and watches
# routed screens. Settings supplies its matching animation ONLY, so there is
# never a second audio player/signal for the same button event.
const HOVER_SCALE := 0.15
const HOVER_TILT_DEGREES := 3.0

var _context: Dictionary = {}
var _active_tab := "settings"
var _button_feedback_tweens: Dictionary = {}

var _classroom_bg: TextureRect
var _main_stage: Control
var _settings_card: Control
var _board_art: NinePatchRect
var _title_image: TextureRect
var _sidebar_panel: Control
var _sidebar_buttons: Dictionary = {}
var _sidebar_authored_size := Vector2.ZERO
var _sidebar_authored_button_rects: Dictionary = {}
var _home_button: Button
var _card_heading: Label
var _heading_icon: TextureRect
var _scroll_hint: Label
var _page_host: Control
var _page_scroll: ScrollContainer
var _pages: Dictionary = {}

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
	_bind_or_build_ui()
	_connect_controls()
	_restore_preferences()
	_sync_from_system()
	_switch_tab("settings")
	_remove_native_tooltips(self)
	_register_button_feedback()
	resized.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")
	if is_instance_valid(_volume_slider):
		_volume_slider.call_deferred("grab_focus")


func _remove_native_tooltips(branch: Node) -> void:
	# Native Control tooltip_text is the dark popup obscuring CAMERA in the
	# editor-authored sidebar. Do not make a replacement tooltip. Remove
	# old inherited/fallback tooltips for the entire Settings subtree.
	if branch is Control:
		(branch as Control).tooltip_text = ""
	for child in branch.get_children():
		_remove_native_tooltips(child)


func _register_button_feedback() -> void:
	# The four editor-authored navigation buttons retain their exact rects.
	# Checkbox-sized switches receive the same (gentler) interactive polish;
	# sliders must NEVER scale while a student is dragging their value.
	for button in _sidebar_buttons.values():
		_bind_button_feedback(button as BaseButton)
	_bind_button_feedback(_home_button)
	_bind_button_feedback(_mute_check)
	_bind_button_feedback(_fullscreen_check)


func _bind_button_feedback(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	button.set_meta("settings_home_rotation", button.rotation)
	button.set_meta("settings_home_z_index", button.z_index)
	var entered := _animate_button_hover.bind(button)
	var exited := _animate_button_exit.bind(button)
	var down := _animate_button_press.bind(button)
	var up := _animate_button_release.bind(button)
	var refresh := _refresh_button_pivot.bind(button)
	if not button.mouse_entered.is_connected(entered):
		button.mouse_entered.connect(entered)
	if not button.mouse_exited.is_connected(exited):
		button.mouse_exited.connect(exited)
	if not button.button_down.is_connected(down):
		button.button_down.connect(down)
	if not button.button_up.is_connected(up):
		button.button_up.connect(up)
	if not button.resized.is_connected(refresh):
		button.resized.connect(refresh)
	_refresh_button_pivot(button)


func _refresh_button_pivot(button: BaseButton) -> void:
	if is_instance_valid(button):
		button.pivot_offset = button.size * 0.5


func _kill_button_feedback_tween(button: BaseButton) -> void:
	var old: Tween = _button_feedback_tweens.get(button)
	if old != null and old.is_valid():
		old.kill()
	_button_feedback_tweens.erase(button)


func _animate_button_hover(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled or not button.is_visible_in_tree():
		return
	_kill_button_feedback_tween(button)
	button.z_index = maxi(int(button.get_meta("settings_home_z_index", 0)), 12)
	var ratio := clampf(128.0 / maxf(button.size.x, 1.0), 0.45, 1.0)
	var bump := 1.0 + HOVER_SCALE * ratio
	var angle := float([-1.0, 1.0].pick_random()) * deg_to_rad(HOVER_TILT_DEGREES * ratio)
	var home_angle := float(button.get_meta("settings_home_rotation", 0.0))
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_button_feedback_tweens[button] = tween
	tween.tween_property(button, "scale:x", bump, 0.20)
	tween.tween_property(button, "scale:y", bump, 0.30)
	tween.tween_property(button, "rotation", home_angle + angle, 0.10)
	tween.tween_property(button, "rotation", home_angle, 0.10).set_delay(0.10)


func _animate_button_exit(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	_kill_button_feedback_tween(button)
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_button_feedback_tweens[button] = tween
	tween.tween_property(button, "scale", Vector2.ONE, 0.25)
	tween.tween_property(button, "rotation", float(button.get_meta("settings_home_rotation", 0.0)), 0.14)
	await tween.finished
	if is_instance_valid(button):
		button.z_index = int(button.get_meta("settings_home_z_index", 0))
	_button_feedback_tweens.erase(button)


func _animate_button_press(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.disabled:
		return
	_kill_button_feedback_tween(button)
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_button_feedback_tweens[button] = tween
	tween.tween_property(button, "scale", Vector2(0.94, 0.90), 0.055)


func _animate_button_release(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	if button.get_global_rect().has_point(get_viewport().get_mouse_position()):
		_animate_button_hover(button)
	else:
		_animate_button_exit(button)


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)


func _bind_or_build_ui() -> void:
	_main_stage = get_node_or_null("MainStage") as Control
	if _main_stage != null:
		_classroom_bg = get_node_or_null("ClassroomArtwork") as TextureRect
		_settings_card = _main_stage.get_node_or_null("SettingsCard") as Control
		if _settings_card != null:
			_board_art = _settings_card.get_node_or_null("BoardArtwork") as NinePatchRect
			# The scene's transparent, editor-draggable sidebar panel is a
			# Control, not a container. Bind the authored node instead of silently
			# skipping responsive sidebar positioning and hover geometry.
			_sidebar_panel = _settings_card.find_child("SidebarPanel", true, false) as Control
			if _sidebar_panel != null:
				_sidebar_authored_size = _sidebar_panel.size
		_title_image = _main_stage.get_node_or_null("SettingsTitle") as TextureRect
		_home_button = _main_stage.get_node_or_null("BackButton") as Button
		if _home_button != null and not _home_button.pressed.is_connected(_request_main):
			_home_button.pressed.connect(_request_main)

		_card_heading = find_child("HeadingLabel", true, false) as Label
		_heading_icon = find_child("HeadingIcon", true, false) as TextureRect
		_scroll_hint = find_child("ScrollHint", true, false) as Label
		_page_host = find_child("PageHost", true, false) as Control
		_page_scroll = find_child("PageScroll", true, false) as ScrollContainer

		for tab_name in ["settings", "controls", "camera"]:
			var btn := find_child("Sidebar" + tab_name.capitalize() + "Tab", true, false) as Button
			if btn != null:
				_sidebar_buttons[tab_name] = btn
				_sidebar_authored_button_rects[tab_name] = btn.get_rect()
				if not btn.pressed.is_connected(_switch_tab):
					btn.pressed.connect(_switch_tab.bind(tab_name))
			var page := find_child(tab_name.capitalize() + "Page", true, false) as Control
			if page != null:
				_pages[tab_name] = page

		_volume_slider = find_child("VolumeSlider", true, false) as HSlider
		_music_slider = find_child("MusicSlider", true, false) as HSlider
		_effects_slider = find_child("EffectsSlider", true, false) as HSlider
		_volume_value = find_child("VolumeValue", true, false) as Label
		_music_value = find_child("MusicValue", true, false) as Label
		_effects_value = find_child("EffectsValue", true, false) as Label
		_mute_check = find_child("MuteCheck", true, false) as CheckButton
		_fullscreen_check = find_child("FullscreenCheck", true, false) as CheckButton
	else:
		_build_ui()


func _build_ui() -> void:
	# 1. Base backdrop and classroom art
	var backdrop := BACKDROP_SCENE.instantiate() as Control
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var classroom := _art_texture(CLASSROOM_ART)
	if classroom != null:
		_classroom_bg = TextureRect.new()
		_classroom_bg.name = "ClassroomArtwork"
		_classroom_bg.texture = classroom
		_classroom_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_classroom_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		_classroom_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_classroom_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_classroom_bg)

	# 2. Main Stage container
	_main_stage = Control.new()
	_main_stage.name = "MainStage"
	_main_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_main_stage)

	# 3. Wooden Board Card
	_settings_card = Control.new()
	_settings_card.name = "SettingsCard"
	_settings_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_stage.add_child(_settings_card)

	var panel_art := _art_texture(SETTINGS_ART + "panel_main.png")
	if panel_art != null:
		_board_art = NinePatchRect.new()
		_board_art.name = "BoardArtwork"
		_board_art.texture = panel_art
		_board_art.set_patch_margin(SIDE_LEFT, 74)
		_board_art.set_patch_margin(SIDE_RIGHT, 74)
		_board_art.set_patch_margin(SIDE_TOP, 64)
		_board_art.set_patch_margin(SIDE_BOTTOM, 64)
		_board_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_board_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_settings_card.add_child(_board_art)
	else:
		var fallback_card := Panel.new()
		fallback_card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback_card.add_theme_stylebox_override("panel", _card_style())
		_settings_card.add_child(fallback_card)

	# Inner board padding & layout
	var card_padding := MarginContainer.new()
	card_padding.name = "CardPadding"
	card_padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_padding.add_theme_constant_override("margin_left", 34)
	card_padding.add_theme_constant_override("margin_right", 34)
	card_padding.add_theme_constant_override("margin_top", 32)
	card_padding.add_theme_constant_override("margin_bottom", 28)
	_settings_card.add_child(card_padding)

	var board_layout := HBoxContainer.new()
	board_layout.name = "BoardLayout"
	board_layout.add_theme_constant_override("separation", 16)
	card_padding.add_child(board_layout)

	# Left Sidebar
	_sidebar_panel = Panel.new()
	_sidebar_panel.name = "SidebarPanel"
	_sidebar_panel.custom_minimum_size = Vector2(216, 0)
	_sidebar_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var sidebar_art := _art_texture(SETTINGS_ART + "panel_sidebar.png")
	if sidebar_art != null:
		var sidebar_style := StyleBoxTexture.new()
		sidebar_style.texture = sidebar_art
		sidebar_style.texture_margin_left = 32
		sidebar_style.texture_margin_right = 32
		sidebar_style.texture_margin_top = 44
		sidebar_style.texture_margin_bottom = 44
		sidebar_style.content_margin_left = 0
		sidebar_style.content_margin_right = 0
		sidebar_style.content_margin_top = 0
		sidebar_style.content_margin_bottom = 0
		_sidebar_panel.add_theme_stylebox_override("panel", sidebar_style)
	else:
		_sidebar_panel.add_theme_stylebox_override("panel", _flat_style(Color("#FFF4DD"), 20))
	board_layout.add_child(_sidebar_panel)

	var y_offset := 22.0
	for tab_name in ["settings", "controls", "camera"]:
		var sidebar_button := _tab_button("")
		sidebar_button.name = "Sidebar" + tab_name.capitalize() + "Tab"
		sidebar_button.position = Vector2(10, y_offset)
		sidebar_button.size = Vector2(196, 66)
		sidebar_button.custom_minimum_size = Vector2(196, 66)
		sidebar_button.tooltip_text = ""
		sidebar_button.pressed.connect(_switch_tab.bind(tab_name))
		_sidebar_panel.add_child(sidebar_button)
		_sidebar_buttons[tab_name] = sidebar_button
		_apply_art_tab(sidebar_button, tab_name, tab_name == "settings")
		y_offset += 66.0 + 18.0

	# Right Content Stack
	var content_stack := VBoxContainer.new()
	content_stack.name = "ContentStack"
	content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_stack.add_theme_constant_override("separation", 8)
	board_layout.add_child(content_stack)

	# Section Heading (Light blue pill bar)
	var heading_panel := PanelContainer.new()
	heading_panel.name = "SectionHeading"
	heading_panel.custom_minimum_size.y = 48
	var heading_style := StyleBoxFlat.new()
	heading_style.bg_color = Color("#C2E6FF")
	heading_style.border_color = Color("#9ED2F6")
	heading_style.set_border_width_all(2)
	heading_style.set_corner_radius_all(16)
	heading_panel.add_theme_stylebox_override("panel", heading_style)
	content_stack.add_child(heading_panel)

	var heading_margin := MarginContainer.new()
	heading_margin.add_theme_constant_override("margin_left", 14)
	heading_margin.add_theme_constant_override("margin_right", 14)
	heading_panel.add_child(heading_margin)

	var heading_row := HBoxContainer.new()
	heading_row.add_theme_constant_override("separation", 10)
	heading_margin.add_child(heading_row)

	_heading_icon = _icon_rect("icon_sound.png", 34)
	_heading_icon.name = "HeadingIcon"
	heading_row.add_child(_heading_icon)

	_card_heading = _label("AUDIO & DISPLAY", 20, INK_DARK, HORIZONTAL_ALIGNMENT_LEFT)
	_card_heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading_row.add_child(_card_heading)

	_scroll_hint = _label("SCROLL DOWN ↓", 11, INK_DARK, HORIZONTAL_ALIGNMENT_RIGHT)
	_scroll_hint.name = "ScrollHint"
	_scroll_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_scroll_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_scroll_hint.custom_minimum_size.x = 130
	_scroll_hint.clip_text = true
	_scroll_hint.size_flags_horizontal = Control.SIZE_SHRINK_END
	_scroll_hint.modulate.a = 0.78
	_scroll_hint.visible = false
	heading_row.add_child(_scroll_hint)

	# Pages Host & Scroll
	_page_host = Control.new()
	_page_host.name = "PageHost"
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_stack.add_child(_page_host)

	_page_scroll = ScrollContainer.new()
	_page_scroll.name = "PageScroll"
	_page_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_page_scroll.follow_focus = true
	_page_host.add_child(_page_scroll)

	_build_settings_page()
	_build_controls_page()
	_build_camera_page()

	# 4. Settings Title Plaque (Centered on upper wooden rail of the board)
	var artwork_title := _art_texture(SETTINGS_ART + "title_settings.png")
	if artwork_title != null:
		_title_image = TextureRect.new()
		_title_image.name = "SettingsTitle"
		_title_image.texture = artwork_title
		_title_image.z_index = 2
		_title_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_title_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_title_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_main_stage.add_child(_title_image)
	else:
		var fallback_title := _label("SETTINGS", 38, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
		fallback_title.name = "SettingsTitle"
		fallback_title.add_theme_font_override("font", _title_font)
		fallback_title.add_theme_color_override("font_outline_color", INK)
		fallback_title.add_theme_constant_override("outline_size", 6)
		fallback_title.z_index = 2
		_main_stage.add_child(fallback_title)

	# 5. Bottom-Left Home Button
	_home_button = Button.new()
	_home_button.name = "BackButton"
	_home_button.unique_name_in_owner = true
	_home_button.custom_minimum_size = Vector2(184, 56)
	_home_button.tooltip_text = ""
	_home_button.focus_mode = Control.FOCUS_ALL
	_home_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_home_button.z_index = 2
	_home_button.pressed.connect(_request_main)
	_apply_full_art_button(_home_button, "button_home.png")
	_main_stage.add_child(_home_button)


func _art_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _apply_full_art_button(button: Button, filename: String) -> void:
	var texture := _art_texture(SETTINGS_ART + filename)
	if texture == null:
		return
	button.add_theme_stylebox_override("normal", _sprite_style(texture, Color.WHITE))
	button.add_theme_stylebox_override("hover", _sprite_style(texture, Color(1.12, 1.12, 1.12)))
	button.add_theme_stylebox_override("pressed", _sprite_style(texture, Color(0.85, 0.88, 0.94)))
	button.add_theme_stylebox_override("hover_pressed", _sprite_style(texture, Color(0.88, 0.92, 0.98)))
	button.add_theme_stylebox_override("disabled", _sprite_style(texture, Color(0.66, 0.66, 0.66)))
	button.add_theme_stylebox_override("focus", _focus_style(16))
	button.add_theme_color_override("font_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_hover_pressed_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_disabled_color", Color.TRANSPARENT)


func _sprite_style(texture: Texture2D, tint: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.modulate_color = tint
	return style


func _apply_art_tab(button: Button, tab_name: String, active: bool) -> void:
	var filename := "tab_%s_%s.png" % [tab_name, "green" if active else "cream"]
	_apply_full_art_button(button, filename)
	button.text = ""


func _icon_rect(filename: String, dimension: float) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(dimension, dimension)
	icon.texture = _art_texture(SETTINGS_ART + filename)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _icon_tile(filename: String) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(40, 40)
	var style := _flat_style(Color("#FFF8EC"), 10)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color("#EADCC8")
	tile.add_theme_stylebox_override("panel", style)
	var icon := _icon_rect(filename, 28)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	tile.add_child(margin)
	margin.add_child(icon)
	return tile


func _build_settings_page() -> void:
	var page := _new_page("SettingsPage")
	_pages["settings"] = page

	# 1. AUDIO Section Card
	var audio_card := _add_settings_group(page, "AUDIO")
	_volume_slider = _slider("VolumeSlider")
	_volume_value = _value_label("VolumeValue")
	audio_card.add_child(_slider_row("MASTER VOLUME", _volume_slider, _volume_value, "icon_sound.png"))

	_music_slider = _slider("MusicSlider")
	_music_value = _value_label("MusicValue")
	audio_card.add_child(_slider_row("MUSIC", _music_slider, _music_value, "icon_music.png"))

	_effects_slider = _slider("EffectsSlider")
	_effects_value = _value_label("EffectsValue")
	audio_card.add_child(_slider_row("EFFECTS", _effects_slider, _effects_value, "icon_star.png"))

	_mute_check = _toggle("MuteCheck")
	audio_card.add_child(_toggle_row("MUTE ALL AUDIO", "Master bus mute", _mute_check, "icon_muted.png"))

	# 2. DISPLAY Section Card
	var display_card := _add_settings_group(page, "DISPLAY", "icon_screen.png")
	_fullscreen_check = _toggle("FullscreenCheck")
	display_card.add_child(_toggle_row("FULLSCREEN", "Switch between windowed and fullscreen", _fullscreen_check, "icon_fullscreen.png"))


func _add_settings_group(page: VBoxContainer, title: String, icon_filename: String = "") -> VBoxContainer:
	var card := PanelContainer.new()
	card.name = title.capitalize() + "Group"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := _flat_style(Color("#DEF0FC"), 16)
	card_style.border_color = Color("#CCE5F9")
	card_style.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", card_style)
	page.add_child(card)

	var inset := MarginContainer.new()
	inset.name = "GroupInset"
	inset.add_theme_constant_override("margin_left", 14)
	inset.add_theme_constant_override("margin_right", 14)
	inset.add_theme_constant_override("margin_top", 10)
	inset.add_theme_constant_override("margin_bottom", 10)
	card.add_child(inset)

	var rows := VBoxContainer.new()
	rows.name = "GroupRows"
	rows.add_theme_constant_override("separation", 4)
	inset.add_child(rows)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	rows.add_child(title_row)

	if not icon_filename.is_empty():
		title_row.add_child(_icon_rect(icon_filename, 24))

	var title_lbl := _label(title, 17, INK_DARK, HORIZONTAL_ALIGNMENT_LEFT)
	title_lbl.custom_minimum_size.y = 26
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(title_lbl)

	var inner_card := PanelContainer.new()
	inner_card.name = "GroupBody"
	inner_card.add_theme_stylebox_override("panel", _flat_style(Color.TRANSPARENT, 0))
	rows.add_child(inner_card)

	var inner_margin := MarginContainer.new()
	inner_margin.name = "GroupBodyMargin"
	inner_margin.add_theme_constant_override("margin_left", 0)
	inner_margin.add_theme_constant_override("margin_right", 0)
	inner_margin.add_theme_constant_override("margin_top", 2)
	inner_margin.add_theme_constant_override("margin_bottom", 2)
	inner_card.add_child(inner_margin)

	var fields := VBoxContainer.new()
	fields.name = "GroupFields"
	fields.add_theme_constant_override("separation", 2)
	inner_margin.add_child(fields)
	return fields


func _build_controls_page() -> void:
	var page := _new_page("ControlsPage")
	_pages["controls"] = page

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := _flat_style(Color("#DEF0FC"), 16)
	card_style.border_color = Color("#CCE5F9")
	card_style.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", card_style)
	page.add_child(card)

	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_left", 16)
	inset.add_theme_constant_override("margin_right", 16)
	inset.add_theme_constant_override("margin_top", 14)
	inset.add_theme_constant_override("margin_bottom", 14)
	card.add_child(inset)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	inset.add_child(box)

	box.add_child(_section_label("CONTROL GUIDE"))
	box.add_child(_info_row("MENU NAVIGATION", "Mouse / touch, or Tab + Enter / Space to navigate menus.", MINT))
	box.add_child(_separator(0.25))
	box.add_child(_info_row("KEYBOARD MINIGAMES", "A / D or Arrow Keys to move left and right. Space / Enter to fire.", BLUE))
	box.add_child(_separator(0.25))
	box.add_child(_info_row("PAUSE / RESUME", "Press ESC or click the in-game Pause button anytime.", YELLOW))
	box.add_child(_separator(0.35))
	box.add_child(_status_banner("BODY TRACKING: PREVIEW ONLY", "Webcam pose tracking will be calibrated in a future milestone.", RED))


func _build_camera_page() -> void:
	var page := _new_page("CameraPage")
	_pages["camera"] = page

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := _flat_style(Color("#DEF0FC"), 16)
	card_style.border_color = Color("#CCE5F9")
	card_style.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", card_style)
	page.add_child(card)

	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_left", 16)
	inset.add_theme_constant_override("margin_right", 16)
	inset.add_theme_constant_override("margin_top", 14)
	inset.add_theme_constant_override("margin_bottom", 14)
	card.add_child(inset)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	inset.add_child(box)

	box.add_child(_section_label("CAMERA STATUS"))
	box.add_child(_status_banner("CAMERA & TRACKING: NOT CONNECTED", "Settings does not open a live camera device or report fake detection.", RED))
	box.add_child(_separator(0.28))

	var lane_title := _label("3-LANE PLAYER CALIBRATION PREVIEW", 14, INK_DARK, HORIZONTAL_ALIGNMENT_CENTER)
	lane_title.modulate.a = 0.88
	box.add_child(lane_title)

	var lanes := HBoxContainer.new()
	lanes.add_theme_constant_override("separation", 10)
	box.add_child(lanes)
	lanes.add_child(_lane_chip("<  LEFT", BLUE))
	lanes.add_child(_lane_chip("CENTER", MINT))
	lanes.add_child(_lane_chip("RIGHT  >", YELLOW))
	box.add_child(_separator(0.28))
	box.add_child(_info_row("CALIBRATION", "Physical calibration maps real movement to the LEFT / CENTER / RIGHT zones.", GREEN))


func _new_page(node_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = node_name
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	page.add_theme_constant_override("separation", 10)
	page.visible = false
	_page_scroll.add_child(page)
	return page


func _connect_controls() -> void:
	if is_instance_valid(_volume_slider) and not _volume_slider.value_changed.is_connected(_on_master_volume_changed):
		_volume_slider.value_changed.connect(_on_master_volume_changed)
	if is_instance_valid(_music_slider) and not _music_slider.value_changed.is_connected(_on_music_volume_changed):
		_music_slider.value_changed.connect(_on_music_volume_changed)
	if is_instance_valid(_effects_slider) and not _effects_slider.value_changed.is_connected(_on_effects_volume_changed):
		_effects_slider.value_changed.connect(_on_effects_volume_changed)
	if is_instance_valid(_mute_check) and not _mute_check.toggled.is_connected(_on_mute_toggled):
		_mute_check.toggled.connect(_on_mute_toggled)
	if is_instance_valid(_fullscreen_check) and not _fullscreen_check.toggled.is_connected(_on_fullscreen_toggled):
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

	sync_fullscreen_state()


func sync_fullscreen_state() -> void:
	# Keep Settings in sync if the player pressed F11/Alt+Enter while it was
	# open, without firing the CheckButton's toggled signal a second time.
	if not is_instance_valid(_fullscreen_check):
		return
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
		slider.tooltip_text = ""
	else:
		slider.set_value_no_signal(0.0)
		value_label.text = "N/A"
		slider.tooltip_text = ""


func _on_master_volume_changed(value: float) -> void:
	_set_bus_volume(MASTER_BUS, value, _volume_value)


func _on_music_volume_changed(value: float) -> void:
	_set_bus_volume(MUSIC_BUS, value, _music_value)


func _on_effects_volume_changed(value: float) -> void:
	_set_bus_volume(EFFECTS_BUS, value, _effects_value)


func _set_bus_volume(bus_name: String, value: float, value_label: Label) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		value_label.text = "N/A"
		return
	var linear := clampf(value / 100.0, 0.0001, 1.0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))
	value_label.text = "%d%%" % int(round(value))
	_save_preferences()


func _on_mute_toggled(enabled: bool) -> void:
	var bus_index := AudioServer.get_bus_index(MASTER_BUS)
	if bus_index >= 0:
		AudioServer.set_bus_mute(bus_index, enabled)
	_update_toggle_text(_mute_check)
	_save_preferences()


func _on_fullscreen_toggled(enabled: bool) -> void:
	apply_display_mode(enabled)
	_update_toggle_text(_fullscreen_check)
	_save_preferences()


func _restore_preferences() -> void:
	# Opening Settings must not unexpectedly switch the running game back to
	# windowed mode because of an older saved preference.
	restore_saved_preferences(false)


static func toggle_fullscreen() -> bool:
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE)
	# F11 and Alt+Enter toggle the ACTUAL current mode, even when the last
	# saved state was windowed and this launch started fullscreen.
	var current := DisplayServer.window_get_mode()
	var was_full := current == DisplayServer.WINDOW_MODE_FULLSCREEN or current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	var new_full := not was_full
	apply_display_mode(new_full)
	config.set_value("display", "fullscreen", new_full)
	var error := config.save(SETTINGS_FILE)
	if error != OK:
		push_warning("Unable to save fullscreen preference: %s" % error)
	return new_full


static func apply_display_mode(fullscreen: bool) -> void:
	# Only this shared settings helper owns display transitions. Opening a
	# Tutorial, Play, Calibration or Settings panel must never change modes.
	# The fullscreen frame uses the monitor's native physical resolution
	# (1920x1080 on the classroom display); the editable window is 1600x900.
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	DisplayServer.window_set_size(WINDOWED_SIZE)
	# Center the smaller window without moving it off the current display.
	var screen := DisplayServer.window_get_current_screen()
	var screen_position := DisplayServer.screen_get_position(screen)
	var screen_size := DisplayServer.screen_get_size(screen)
	var actual_window := DisplayServer.window_get_size()
	DisplayServer.window_set_position(screen_position + (screen_size - actual_window) / 2)


static func restore_saved_preferences(apply_display: bool = true) -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_FILE) != OK:
		return
	for bus_name in [MASTER_BUS, MUSIC_BUS, EFFECTS_BUS]:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0 and config.has_section_key("audio", bus_name):
			var percent := clampf(float(config.get_value("audio", bus_name)), 0.0, 100.0)
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(percent / 100.0, 0.0001)))
	var master_index := AudioServer.get_bus_index(MASTER_BUS)
	if master_index >= 0 and config.has_section_key("audio", "mute"):
		AudioServer.set_bus_mute(master_index, bool(config.get_value("audio", "mute")))
	if apply_display and config.has_section_key("display", "fullscreen"):
		var enabled := bool(config.get_value("display", "fullscreen"))
		apply_display_mode(enabled)


func _save_preferences() -> void:
	var config := ConfigFile.new()
	for bus_name in [MASTER_BUS, MUSIC_BUS, EFFECTS_BUS]:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
			config.set_value("audio", bus_name, clampf(db_to_linear(AudioServer.get_bus_volume_db(index)) * 100.0, 0.0, 100.0))
	var master_index := AudioServer.get_bus_index(MASTER_BUS)
	if master_index >= 0:
		config.set_value("audio", "mute", AudioServer.is_bus_mute(master_index))
	var is_fullscreen := _fullscreen_check.button_pressed if is_instance_valid(_fullscreen_check) else (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	config.set_value("display", "fullscreen", is_fullscreen)
	var error := config.save(SETTINGS_FILE)
	if error != OK:
		push_warning("Unable to save audio/display preferences: %s" % error)


func _update_toggle_text(toggle: CheckButton) -> void:
	toggle.text = ""
	toggle.tooltip_text = ""


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
	var heading_icons := {
		"settings": "icon_sound.png",
		"controls": "icon_controls.png",
		"camera": "icon_camera.png"
	}
	if is_instance_valid(_heading_icon):
		_heading_icon.texture = _art_texture(SETTINGS_ART + String(heading_icons.get(tab_name, "icon_settings.png")))
	for key in _pages:
		var page: Control = _pages[key]
		page.visible = key == tab_name
	_page_scroll.scroll_vertical = 0
	for key in _sidebar_buttons:
		var sidebar_button: Button = _sidebar_buttons[key]
		_apply_art_tab(sidebar_button, key, key == tab_name)


func _apply_responsive_layout() -> void:
	if not is_instance_valid(_settings_card) or not is_instance_valid(_main_stage):
		return

	var vp := size
	if vp.x < 1.0 or vp.y < 1.0:
		vp = get_viewport_rect().size
	if vp.x < 1.0 or vp.y < 1.0:
		vp = Vector2(1280, 720)

	var compact := vp.x < 1050.0 or vp.y <= 600.0

	# 1. Main Board Size & Positioning
	var board_w := minf(vp.x * (0.94 if compact else 0.85), 1050.0)
	var board_h := clampf(vp.y * (0.74 if compact else 0.70), 340.0, 505.0)
	var board_x := (vp.x - board_w) * 0.5
	# Ensure board leaves room for title above and Home button below
	var board_y := clampf(vp.y * 0.175, 75.0, 126.0)

	_settings_card.position = Vector2(board_x, board_y)
	_settings_card.size = Vector2(board_w, board_h)

	# 2. Title Plaque Positioning (overlapping upper board rail)
	if is_instance_valid(_title_image):
		var title_w := minf(board_w * (0.48 if compact else 0.52), 530.0)
		var title_h := title_w * (398.0 / 1482.0)
		var title_x := (vp.x - title_w) * 0.5
		var title_y := maxf(board_y - title_h * 0.60, 12.0)
		_title_image.position = Vector2(title_x, title_y)
		_title_image.size = Vector2(title_w, title_h)

	# 3. Sidebar Panel Sizing
	if is_instance_valid(_sidebar_panel):
		var sidebar_w := 160.0 if compact else 216.0
		_sidebar_panel.custom_minimum_size.x = sidebar_w
		# The authored side panel is a transparent hit/layout parent. Its old
		# height could extend below the board at 875x500, despite the buttons
		# themselves being visible. Bound it to the actual editor board rect.
		var available_h := maxf(0.0, _settings_card.size.y - _sidebar_panel.position.y - 8.0)
		var authored_h := _sidebar_authored_size.y if _sidebar_authored_size.y > 0.0 else available_h
		_sidebar_panel.size = Vector2(sidebar_w, minf(authored_h, available_h))
		for tab_btn: Button in _sidebar_buttons.values():
			tab_btn.custom_minimum_size = Vector2(sidebar_w - 20.0, 48.0 if compact else 66.0)
		if compact:
			var y_off := 16.0
			for tab_key in ["settings", "controls", "camera"]:
				if _sidebar_buttons.has(tab_key):
					var tab_btn: Button = _sidebar_buttons[tab_key]
					tab_btn.position = Vector2(10.0, y_off)
					tab_btn.size = Vector2(sidebar_w - 20.0, 48.0)
					y_off += 48.0 + 14.0
		else:
			# Restore whatever designers placed in the .tscn. Compact mode
			# must not permanently overwrite drag-edited desktop tab geometry.
			for tab_key in _sidebar_authored_button_rects:
				if _sidebar_buttons.has(tab_key):
					var authored: Rect2 = _sidebar_authored_button_rects[tab_key]
					var tab_btn: Button = _sidebar_buttons[tab_key]
					tab_btn.position = authored.position
					tab_btn.size = authored.size

	# 4. Home Button Positioning
	if is_instance_valid(_home_button):
		var home_w := 148.0 if compact else 184.0
		var home_h := 46.0 if compact else 56.0
		_home_button.custom_minimum_size = Vector2(home_w, home_h)
		if _home_button.offset_top < 150.0:
			var home_x := vp.x - home_w - (16.0 if compact else 58.0)
			var home_y := 16.0 if compact else 28.0
			_home_button.position = Vector2(home_x, home_y)
			_home_button.size = Vector2(home_w, home_h)
		else:
			var home_x := maxf(board_x, 16.0)
			var home_y := minf(board_y + board_h + 12.0, vp.y - home_h - 10.0)
			_home_button.position = Vector2(home_x, home_y)
			_home_button.size = Vector2(home_w, home_h)

	# 5. Card Padding
	var card_padding := _settings_card.get_node_or_null("CardPadding") as MarginContainer
	if card_padding != null:
		card_padding.add_theme_constant_override("margin_left", 20 if compact else 36)
		card_padding.add_theme_constant_override("margin_right", 20 if compact else 36)
		card_padding.add_theme_constant_override("margin_top", 24 if compact else 44)
		card_padding.add_theme_constant_override("margin_bottom", 78 if compact else 26)

	# 6. Scroll Hint
	if is_instance_valid(_scroll_hint):
		_scroll_hint.visible = compact


func _slider_row(label_text: String, slider: HSlider, value_label: Label, icon_filename: String = "") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Slider" + label_text.replace(" ", "").capitalize() + "Row"
	panel.custom_minimum_size.y = 48
	panel.add_theme_stylebox_override("panel", _soft_row_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	if not icon_filename.is_empty():
		row.add_child(_icon_tile(icon_filename))
	var label := _label(label_text, 14, INK_DARK, HORIZONTAL_ALIGNMENT_LEFT)
	label.custom_minimum_size.x = 160
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	row.add_child(slider)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(68, 30)
	var badge_style := _flat_style(Color.WHITE, 8)
	badge_style.border_width_left = 1
	badge_style.border_width_top = 1
	badge_style.border_width_right = 1
	badge_style.border_width_bottom = 1
	badge_style.border_color = Color("#CCE2F3")
	badge.add_theme_stylebox_override("panel", badge_style)
	badge.add_child(value_label)
	row.add_child(badge)
	return panel


func _toggle_row(label_text: String, hint_text: String, toggle: CheckButton, icon_filename: String = "") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Toggle" + label_text.replace(" ", "").capitalize() + "Row"
	panel.custom_minimum_size.y = 52
	panel.add_theme_stylebox_override("panel", _soft_row_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	if not icon_filename.is_empty():
		row.add_child(_icon_tile(icon_filename))
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 1)
	row.add_child(text_box)
	text_box.add_child(_label(label_text, 15, INK_DARK, HORIZONTAL_ALIGNMENT_LEFT))
	if not hint_text.is_empty():
		var hint := _label(hint_text, 12, Color("#63738E"), HORIZONTAL_ALIGNMENT_LEFT)
		text_box.add_child(hint)
	row.add_child(toggle)
	return panel


func _soft_row_style() -> StyleBoxFlat:
	return _flat_style(Color.TRANSPARENT, 0)


func _info_row(title_text: String, detail_text: String, accent: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 12)
	var marker := PanelContainer.new()
	marker.custom_minimum_size = Vector2(6, 0)
	marker.add_theme_stylebox_override("panel", _flat_style(accent, 3))
	row.add_child(marker)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	row.add_child(text_box)
	text_box.add_child(_label(title_text, 13, INK_DARK, HORIZONTAL_ALIGNMENT_LEFT))
	var detail := _label(detail_text, 11, INK_DARK, HORIZONTAL_ALIGNMENT_LEFT)
	detail.modulate.a = 0.74
	text_box.add_child(detail)
	return row


func _status_banner(title_text: String, detail_text: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := _flat_style(Color(INK_DARK.r, INK_DARK.g, INK_DARK.b, 0.92), 12)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = accent
	panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)
	box.add_child(_label(title_text, 12, accent, HORIZONTAL_ALIGNMENT_CENTER))
	var detail := _label(detail_text, 11, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	detail.modulate.a = 0.82
	box.add_child(detail)
	return panel


func _lane_chip(text_value: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 44
	var style := _flat_style(Color(accent.r, accent.g, accent.b, 0.18), 12)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = accent
	panel.add_theme_stylebox_override("panel", style)
	var label := _label(text_value, 12, INK_DARK, HORIZONTAL_ALIGNMENT_CENTER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


func _slider(node_name: String) -> HSlider:
	var slider := HSlider.new()
	slider.name = node_name
	slider.unique_name_in_owner = true
	slider.custom_minimum_size = Vector2(200, 28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = 100.0

	var track := StyleBoxFlat.new()
	track.bg_color = Color("#D4E5F5")
	track.corner_radius_top_left = 6
	track.corner_radius_top_right = 6
	track.corner_radius_bottom_left = 6
	track.corner_radius_bottom_right = 6
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)

	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color("#20C57A")
	slider.add_theme_stylebox_override("grabber_area", fill)

	var fill_hover := fill.duplicate() as StyleBoxFlat
	fill_hover.bg_color = Color("#20C57A").lightened(0.08)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hover)

	slider.add_theme_icon_override("grabber", _slider_knob)
	slider.add_theme_icon_override("grabber_highlight", _slider_knob)
	slider.add_theme_icon_override("grabber_disabled", _slider_knob)
	return slider


func _value_label(node_name: String) -> Label:
	var label := _label("100%", 14, INK_DARK, HORIZONTAL_ALIGNMENT_CENTER)
	label.name = node_name
	label.unique_name_in_owner = true
	label.custom_minimum_size = Vector2(62, 28)
	label.size_flags_horizontal = Control.SIZE_SHRINK_END
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _toggle(node_name: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.name = node_name
	toggle.unique_name_in_owner = true
	toggle.custom_minimum_size = Vector2(84, 36)
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var on_tex := _art_texture(SETTINGS_ART + "toggle_on.png")
	var off_tex := _art_texture(SETTINGS_ART + "toggle_off.png")
	if on_tex != null and off_tex != null:
		toggle.add_theme_icon_override("checked", on_tex)
		toggle.add_theme_icon_override("unchecked", off_tex)
		toggle.add_theme_icon_override("checked_disabled", on_tex)
		toggle.add_theme_icon_override("unchecked_disabled", off_tex)

	toggle.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	toggle.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	toggle.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	toggle.add_theme_stylebox_override("hover_pressed", StyleBoxEmpty.new())
	toggle.add_theme_stylebox_override("focus", _focus_style(16))
	toggle.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	toggle.add_theme_constant_override("check_v_offset", 0)
	toggle.text = ""
	return toggle


func _tab_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(190, 56)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_stylebox_override("focus", _focus_style(16))
	return button


func _section_label(text_value: String) -> Label:
	var label := _label(text_value, 15, INK_DARK, HORIZONTAL_ALIGNMENT_LEFT)
	label.custom_minimum_size.y = 22
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
	line.bg_color = Color(INK_DARK.r, INK_DARK.g, INK_DARK.b, alpha)
	line.content_margin_top = 1
	line.content_margin_bottom = 1
	separator.add_theme_stylebox_override("separator", line)
	return separator


func _card_style() -> StyleBoxFlat:
	var style := _flat_style(Color("#FFF4DD"), 24)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color("#D4B07B")
	style.shadow_color = Color(0.12, 0.10, 0.16, 0.35)
	style.shadow_size = 8
	style.shadow_offset = Vector2(4, 6)
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
	var knob_tex := _art_texture(SETTINGS_ART + "slider_knob_green_28.png")
	if knob_tex != null:
		return knob_tex
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var center := Vector2(11.5, 11.5)
	for y in range(24):
		for x in range(24):
			var d := Vector2(float(x), float(y)).distance_to(center)
			if d <= 11.0:
				if d >= 8.5:
					image.set_pixel(x, y, Color("#148A54"))
				else:
					image.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(image)


func _request_main() -> void:
	requested.emit("main", _context.duplicate(true))


func _load_title_font() -> Font:
	var comic_font := FontFile.new()
	var error := comic_font.load_dynamic_font(TITLE_FONT_PATH)
	if error == OK:
		return comic_font
	return FONT
