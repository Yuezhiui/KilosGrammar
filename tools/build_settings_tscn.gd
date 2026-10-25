extends SceneTree

const FONT := preload("res://assets/fonts/TitanOne-Regular.ttf")
const TITLE_FONT_PATH := "res://assets/fonts/Comic Lemon.otf"
const BACKDROP_SCENE := preload("res://ui/shared/lexi_reference_backdrop.tscn")
const SETTINGS_ART := "res://Components/Settings/Redesign/"
const CLASSROOM_ART := "res://Components/Shared/Redesign/classroom_bg.png"
const OUT_PATH := "res://ui/secondary/settings.tscn"

const INK := Color("#474660")
const INK_DARK := Color("#152557")
const CREAM := Color("#FDE4B9")
const MINT := Color("#20C57A")
const MINT_LABEL := Color("#C5F1D9")
const GREEN := Color("#00886B")
const YELLOW := Color("#FFC23D")
const BLUE := Color("#7BC9EF")
const RED := Color("#FF4F66")

var _title_font: Font
var _slider_knob: Texture2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_title_font = _load_title_font()
	_slider_knob = _make_slider_knob()

	var root_node := Control.new()
	root_node.name = "Settings"
	root_node.layout_mode = 3
	root_node.anchors_preset = Control.PRESET_FULL_RECT
	root_node.anchor_right = 1.0
	root_node.anchor_bottom = 1.0
	root_node.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root_node.grow_vertical = Control.GROW_DIRECTION_BOTH
	root_node.theme = load("res://ui/secondary/secondary_theme.tres")

	# 1. Backdrop
	var backdrop := BACKDROP_SCENE.instantiate() as Control
	backdrop.name = "LexiReferenceBackdrop"
	backdrop.anchors_preset = Control.PRESET_FULL_RECT
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	backdrop.grow_vertical = Control.GROW_DIRECTION_BOTH
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_node.add_child(backdrop)

	var classroom_tex := _art_texture(CLASSROOM_ART)
	if classroom_tex != null:
		var classroom_bg := TextureRect.new()
		classroom_bg.name = "ClassroomArtwork"
		classroom_bg.texture = classroom_tex
		classroom_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		classroom_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		classroom_bg.anchors_preset = Control.PRESET_FULL_RECT
		classroom_bg.anchor_right = 1.0
		classroom_bg.anchor_bottom = 1.0
		classroom_bg.grow_horizontal = Control.GROW_DIRECTION_BOTH
		classroom_bg.grow_vertical = Control.GROW_DIRECTION_BOTH
		classroom_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root_node.add_child(classroom_bg)

	# 2. Main Stage
	var main_stage := Control.new()
	main_stage.name = "MainStage"
	main_stage.anchors_preset = Control.PRESET_FULL_RECT
	main_stage.anchor_right = 1.0
	main_stage.anchor_bottom = 1.0
	main_stage.grow_horizontal = Control.GROW_DIRECTION_BOTH
	main_stage.grow_vertical = Control.GROW_DIRECTION_BOTH
	main_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_node.add_child(main_stage)

	# 3. Settings Card (centered on 1280x720)
	var settings_card := Control.new()
	settings_card.name = "SettingsCard"
	settings_card.position = Vector2(115, 126)
	settings_card.size = Vector2(1050, 504)
	settings_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_stage.add_child(settings_card)

	var panel_art := _art_texture(SETTINGS_ART + "panel_main.png")
	if panel_art != null:
		var board_art := NinePatchRect.new()
		board_art.name = "BoardArtwork"
		board_art.texture = panel_art
		board_art.set_patch_margin(SIDE_LEFT, 74)
		board_art.set_patch_margin(SIDE_RIGHT, 74)
		board_art.set_patch_margin(SIDE_TOP, 64)
		board_art.set_patch_margin(SIDE_BOTTOM, 64)
		board_art.anchors_preset = Control.PRESET_FULL_RECT
		board_art.anchor_right = 1.0
		board_art.anchor_bottom = 1.0
		board_art.grow_horizontal = Control.GROW_DIRECTION_BOTH
		board_art.grow_vertical = Control.GROW_DIRECTION_BOTH
		board_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		settings_card.add_child(board_art)

	var card_padding := MarginContainer.new()
	card_padding.name = "CardPadding"
	card_padding.anchors_preset = Control.PRESET_FULL_RECT
	card_padding.anchor_right = 1.0
	card_padding.anchor_bottom = 1.0
	card_padding.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card_padding.grow_vertical = Control.GROW_DIRECTION_BOTH
	card_padding.add_theme_constant_override("margin_left", 36)
	card_padding.add_theme_constant_override("margin_right", 36)
	card_padding.add_theme_constant_override("margin_top", 44)
	card_padding.add_theme_constant_override("margin_bottom", 26)
	settings_card.add_child(card_padding)

	var board_layout := HBoxContainer.new()
	board_layout.name = "BoardLayout"
	board_layout.add_theme_constant_override("separation", 16)
	card_padding.add_child(board_layout)

	# Sidebar (Panel is a Control, NOT a Container, allowing free mouse drag-and-drop)
	var sidebar_panel := Panel.new()
	sidebar_panel.name = "SidebarPanel"
	sidebar_panel.custom_minimum_size = Vector2(216, 0)
	sidebar_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var sidebar_art := _art_texture(SETTINGS_ART + "panel_sidebar.png")
	if sidebar_art != null:
		var sidebar_style := StyleBoxTexture.new()
		sidebar_style.texture = sidebar_art
		sidebar_style.texture_margin_left = 32
		sidebar_style.texture_margin_right = 32
		sidebar_style.texture_margin_top = 44
		sidebar_style.texture_margin_bottom = 44
		sidebar_panel.add_theme_stylebox_override("panel", sidebar_style)
	board_layout.add_child(sidebar_panel)

	# Direct children of Panel (free 2D drag-and-drop enabled)
	var y_offset := 22.0
	for tab_name in ["settings", "controls", "camera"]:
		var sidebar_button := _tab_button("")
		sidebar_button.name = "Sidebar" + tab_name.capitalize() + "Tab"
		sidebar_button.position = Vector2(10, y_offset)
		sidebar_button.size = Vector2(196, 66)
		sidebar_button.custom_minimum_size = Vector2(196, 66)
		sidebar_button.tooltip_text = tab_name.capitalize()
		sidebar_panel.add_child(sidebar_button)
		_apply_art_tab(sidebar_button, tab_name, tab_name == "settings")
		y_offset += 66.0 + 18.0

	# Content Stack
	var content_stack := VBoxContainer.new()
	content_stack.name = "ContentStack"
	content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_stack.add_theme_constant_override("separation", 8)
	board_layout.add_child(content_stack)

	# Section Heading
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
	heading_margin.name = "HeadingMargin"
	heading_margin.add_theme_constant_override("margin_left", 14)
	heading_margin.add_theme_constant_override("margin_right", 14)
	heading_panel.add_child(heading_margin)

	var heading_row := HBoxContainer.new()
	heading_row.name = "HeadingRow"
	heading_row.add_theme_constant_override("separation", 10)
	heading_margin.add_child(heading_row)

	var heading_icon := _icon_rect("icon_sound.png", 34)
	heading_icon.name = "HeadingIcon"
	heading_row.add_child(heading_icon)

	var card_heading := _label("AUDIO & DISPLAY", 20, INK_DARK, HORIZONTAL_ALIGNMENT_LEFT)
	card_heading.name = "HeadingLabel"
	card_heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading_row.add_child(card_heading)

	var scroll_hint := _label("SCROLL DOWN ↓", 11, INK_DARK, HORIZONTAL_ALIGNMENT_RIGHT)
	scroll_hint.name = "ScrollHint"
	scroll_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	scroll_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	scroll_hint.custom_minimum_size.x = 130
	scroll_hint.clip_text = true
	scroll_hint.size_flags_horizontal = Control.SIZE_SHRINK_END
	scroll_hint.modulate.a = 0.78
	scroll_hint.visible = false
	heading_row.add_child(scroll_hint)

	# Pages Host & Scroll
	var page_host := Control.new()
	page_host.name = "PageHost"
	page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_stack.add_child(page_host)

	var page_scroll := ScrollContainer.new()
	page_scroll.name = "PageScroll"
	page_scroll.anchors_preset = Control.PRESET_FULL_RECT
	page_scroll.anchor_right = 1.0
	page_scroll.anchor_bottom = 1.0
	page_scroll.grow_horizontal = Control.GROW_DIRECTION_BOTH
	page_scroll.grow_vertical = Control.GROW_DIRECTION_BOTH
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	page_scroll.follow_focus = true
	page_host.add_child(page_scroll)

	# Build 3 Pages
	_build_settings_page_to(page_scroll)
	_build_controls_page_to(page_scroll)
	_build_camera_page_to(page_scroll)

	# Title Plaque
	var artwork_title := _art_texture(SETTINGS_ART + "title_settings.png")
	if artwork_title != null:
		var title_image := TextureRect.new()
		title_image.name = "SettingsTitle"
		title_image.texture = artwork_title
		title_image.z_index = 2
		title_image.position = Vector2(367, 43)
		title_image.size = Vector2(546, 146)
		title_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		title_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		title_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		main_stage.add_child(title_image)

	# Home Button
	var home_button := Button.new()
	home_button.name = "BackButton"
	home_button.unique_name_in_owner = true
	home_button.custom_minimum_size = Vector2(184, 56)
	home_button.position = Vector2(115, 642)
	home_button.size = Vector2(184, 56)
	home_button.tooltip_text = "Return to main menu"
	home_button.focus_mode = Control.FOCUS_ALL
	home_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	home_button.z_index = 2
	_apply_full_art_button(home_button, "button_home.png")
	main_stage.add_child(home_button)

	root_node.set_script(load("res://ui/secondary/settings.gd"))

	# Set recursive owner to root_node so everything is saved to .tscn
	_set_owner_recursive(root_node, root_node)

	var packed := PackedScene.new()
	var pack_err := packed.pack(root_node)
	if pack_err != OK:
		push_error("Failed to pack scene: %s" % pack_err)
		quit(1)
		return

	var save_err := ResourceSaver.save(packed, OUT_PATH)
	if save_err != OK:
		push_error("Failed to save scene: %s" % save_err)
		quit(1)
		return

	print("SUCCESS: Generated %s with all child nodes editable!" % OUT_PATH)
	quit(0)


func _set_owner_recursive(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_set_owner_recursive(child, scene_root)


func _build_settings_page_to(page_scroll: ScrollContainer) -> void:
	var page := VBoxContainer.new()
	page.name = "SettingsPage"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	page.add_theme_constant_override("separation", 10)
	page.visible = true
	page_scroll.add_child(page)

	# Audio card
	var audio_fields := _add_settings_group(page, "AUDIO")
	var vol_slider := _slider("VolumeSlider")
	var vol_val := _value_label("VolumeValue")
	audio_fields.add_child(_slider_row("MASTER VOLUME", vol_slider, vol_val, "icon_sound.png"))

	var mus_slider := _slider("MusicSlider")
	var mus_val := _value_label("MusicValue")
	audio_fields.add_child(_slider_row("MUSIC", mus_slider, mus_val, "icon_music.png"))

	var sfx_slider := _slider("EffectsSlider")
	var sfx_val := _value_label("EffectsValue")
	audio_fields.add_child(_slider_row("EFFECTS", sfx_slider, sfx_val, "icon_star.png"))

	var mute_check := _toggle("MuteCheck")
	audio_fields.add_child(_toggle_row("MUTE ALL AUDIO", "Master bus mute", mute_check, "icon_muted.png"))

	# Display card
	var disp_fields := _add_settings_group(page, "DISPLAY", "icon_screen.png")
	var full_check := _toggle("FullscreenCheck")
	disp_fields.add_child(_toggle_row("FULLSCREEN", "Switch between windowed and fullscreen", full_check, "icon_fullscreen.png"))


func _build_controls_page_to(page_scroll: ScrollContainer) -> void:
	var page := VBoxContainer.new()
	page.name = "ControlsPage"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	page.add_theme_constant_override("separation", 10)
	page.visible = false
	page_scroll.add_child(page)

	var card := PanelContainer.new()
	card.name = "ControlsCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := _flat_style(Color("#DEF0FC"), 16)
	card_style.border_color = Color("#CCE5F9")
	card_style.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", card_style)
	page.add_child(card)

	var inset := MarginContainer.new()
	inset.name = "ControlsMargin"
	inset.add_theme_constant_override("margin_left", 16)
	inset.add_theme_constant_override("margin_right", 16)
	inset.add_theme_constant_override("margin_top", 14)
	inset.add_theme_constant_override("margin_bottom", 14)
	card.add_child(inset)

	var box := VBoxContainer.new()
	box.name = "ControlsBox"
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


func _build_camera_page_to(page_scroll: ScrollContainer) -> void:
	var page := VBoxContainer.new()
	page.name = "CameraPage"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	page.add_theme_constant_override("separation", 10)
	page.visible = false
	page_scroll.add_child(page)

	var card := PanelContainer.new()
	card.name = "CameraCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var card_style := _flat_style(Color("#DEF0FC"), 16)
	card_style.border_color = Color("#CCE5F9")
	card_style.set_border_width_all(2)
	card.add_theme_stylebox_override("panel", card_style)
	page.add_child(card)

	var inset := MarginContainer.new()
	inset.name = "CameraMargin"
	inset.add_theme_constant_override("margin_left", 16)
	inset.add_theme_constant_override("margin_right", 16)
	inset.add_theme_constant_override("margin_top", 14)
	inset.add_theme_constant_override("margin_bottom", 14)
	card.add_child(inset)

	var box := VBoxContainer.new()
	box.name = "CameraBox"
	box.add_theme_constant_override("separation", 10)
	inset.add_child(box)

	box.add_child(_section_label("CAMERA STATUS"))
	box.add_child(_status_banner("CAMERA & TRACKING: NOT CONNECTED", "Settings does not open a live camera device or report fake detection.", RED))
	box.add_child(_separator(0.28))

	var lane_title := _label("3-LANE PLAYER CALIBRATION PREVIEW", 14, INK_DARK, HORIZONTAL_ALIGNMENT_CENTER)
	lane_title.name = "LaneTitle"
	lane_title.modulate.a = 0.88
	box.add_child(lane_title)

	var lanes := HBoxContainer.new()
	lanes.name = "LanesBox"
	lanes.add_theme_constant_override("separation", 10)
	box.add_child(lanes)
	lanes.add_child(_lane_chip("<  LEFT", BLUE))
	lanes.add_child(_lane_chip("CENTER", MINT))
	lanes.add_child(_lane_chip("RIGHT  >", YELLOW))
	box.add_child(_separator(0.28))
	box.add_child(_info_row("CALIBRATION", "Physical calibration maps real movement to the LEFT / CENTER / RIGHT zones.", GREEN))


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
	tile.name = "Tile" + filename.get_basename().capitalize()
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
	margin.name = "TileMargin"
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	tile.add_child(margin)
	margin.add_child(icon)
	return tile


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
	title_row.name = "GroupTitleRow"
	title_row.add_theme_constant_override("separation", 8)
	rows.add_child(title_row)

	if not icon_filename.is_empty():
		title_row.add_child(_icon_rect(icon_filename, 24))

	var title_lbl := _label(title, 17, INK_DARK, HORIZONTAL_ALIGNMENT_LEFT)
	title_lbl.name = "GroupTitle"
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


func _slider_row(label_text: String, slider: HSlider, value_label: Label, icon_filename: String = "") -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Slider" + label_text.replace(" ", "").capitalize() + "Row"
	panel.custom_minimum_size.y = 48
	panel.add_theme_stylebox_override("panel", _soft_row_style())
	var margin := MarginContainer.new()
	margin.name = "RowMargin"
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.name = "RowHBox"
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	if not icon_filename.is_empty():
		row.add_child(_icon_tile(icon_filename))
	var label := _label(label_text, 14, INK_DARK, HORIZONTAL_ALIGNMENT_LEFT)
	label.name = "RowLabel"
	label.custom_minimum_size.x = 160
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	row.add_child(slider)
	var badge := PanelContainer.new()
	badge.name = "ValueBadge"
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
	margin.name = "RowMargin"
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.name = "RowHBox"
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	if not icon_filename.is_empty():
		row.add_child(_icon_tile(icon_filename))
	var text_box := VBoxContainer.new()
	text_box.name = "TextBox"
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 1)
	row.add_child(text_box)
	var title_lbl := _label(label_text, 15, INK_DARK, HORIZONTAL_ALIGNMENT_LEFT)
	title_lbl.name = "ToggleTitle"
	text_box.add_child(title_lbl)
	if not hint_text.is_empty():
		var hint := _label(hint_text, 12, Color("#63738E"), HORIZONTAL_ALIGNMENT_LEFT)
		hint.name = "ToggleHint"
		text_box.add_child(hint)
	row.add_child(toggle)
	return panel


func _soft_row_style() -> StyleBoxFlat:
	return _flat_style(Color.TRANSPARENT, 0)


func _info_row(title_text: String, detail_text: String, accent: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "InfoRow" + title_text.replace(" ", "").replace("/", "").capitalize()
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 12)
	var marker := PanelContainer.new()
	marker.name = "Marker"
	marker.custom_minimum_size = Vector2(6, 0)
	marker.add_theme_stylebox_override("panel", _flat_style(accent, 3))
	row.add_child(marker)
	var text_box := VBoxContainer.new()
	text_box.name = "TextBox"
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	row.add_child(text_box)
	var lbl := _label(title_text, 13, INK_DARK, HORIZONTAL_ALIGNMENT_LEFT)
	lbl.name = "Title"
	text_box.add_child(lbl)
	var detail := _label(detail_text, 11, INK_DARK, HORIZONTAL_ALIGNMENT_LEFT)
	detail.name = "Detail"
	detail.modulate.a = 0.74
	text_box.add_child(detail)
	return row


func _status_banner(title_text: String, detail_text: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "StatusBanner"
	var style := _flat_style(Color(INK_DARK.r, INK_DARK.g, INK_DARK.b, 0.92), 12)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = accent
	panel.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.name = "BannerMargin"
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.name = "BannerBox"
	box.add_theme_constant_override("separation", 2)
	margin.add_child(box)
	var title_lbl := _label(title_text, 12, accent, HORIZONTAL_ALIGNMENT_CENTER)
	title_lbl.name = "BannerTitle"
	box.add_child(title_lbl)
	var detail := _label(detail_text, 11, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	detail.name = "BannerDetail"
	detail.modulate.a = 0.82
	box.add_child(detail)
	return panel


func _lane_chip(text_value: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Chip" + text_value.replace(" ", "").replace("<", "Left").replace(">", "Right").capitalize()
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
	label.name = "ChipLabel"
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
	label.name = "SectionTitle"
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
	separator.name = "Separator"
	var line := StyleBoxFlat.new()
	line.bg_color = Color(INK_DARK.r, INK_DARK.g, INK_DARK.b, alpha)
	line.content_margin_top = 1
	line.content_margin_bottom = 1
	separator.add_theme_stylebox_override("separator", line)
	return separator


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


func _load_title_font() -> Font:
	var comic_font := FontFile.new()
	var error := comic_font.load_dynamic_font(TITLE_FONT_PATH)
	if error == OK:
		return comic_font
	return FONT
