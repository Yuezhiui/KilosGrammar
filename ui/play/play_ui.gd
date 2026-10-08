extends RefCounted

const TITLE_FONT: Font = preload("res://assets/fonts/TitanOne-Regular.ttf")

const CREAM := Color("#F7E6BD")
const MINT := Color("#00886B")
const INK := Color("#494463")
const GREEN := Color("#69BE9A")
const RED := Color("#FF4F66")
const YELLOW := Color("#FFC23D")
const BLUE := Color("#7BC9EF")
const PURPLE := Color("#C171CF")
const ORANGE := Color("#F4985F")
const DEEP_BLUE := Color("#5AA0D7")
const WHITE := Color("#FFFDF7")


static func make_panel(color: Color, radius: int = 24, shadow: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(CREAM, 0.5)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	style.content_margin_left = 20.0
	style.content_margin_top = 16.0
	style.content_margin_right = 20.0
	style.content_margin_bottom = 16.0
	if shadow:
		style.shadow_color = Color("#2A2437A0")
		style.shadow_size = 5
		style.shadow_offset = Vector2(7, 9)
	return style


static func make_button_style(color: Color, focused: bool = false, pressed: bool = false) -> StyleBoxFlat:
	var style := make_panel(color, 14, not pressed)
	style.content_margin_left = 18.0
	style.content_margin_top = 12.0
	style.content_margin_right = 18.0
	style.content_margin_bottom = 12.0
	if focused:
		style.border_width_left = 4
		style.border_width_top = 4
		style.border_width_right = 4
		style.border_width_bottom = 4
		style.border_color = CREAM
	if pressed:
		style.shadow_size = 1
		style.shadow_offset = Vector2(0, 2)
	return style


static func style_button(button: Button, color: Color = INK, font_size: int = 24) -> void:
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", TITLE_FONT)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", WHITE)
	button.add_theme_color_override("font_pressed_color", WHITE)
	button.add_theme_color_override("font_focus_color", CREAM)
	button.add_theme_color_override("font_disabled_color", Color(CREAM, 0.45))
	button.add_theme_stylebox_override("normal", make_button_style(color))
	button.add_theme_stylebox_override("hover", make_button_style(color.lightened(0.10), true))
	button.add_theme_stylebox_override("focus", make_button_style(color.lightened(0.06), true))
	button.add_theme_stylebox_override("pressed", make_button_style(color.darkened(0.08), true, true))
	var disabled_style := make_button_style(Color(color, 0.36))
	disabled_style.border_color = Color(CREAM, 0.20)
	button.add_theme_stylebox_override("disabled", disabled_style)


static func style_selection_button(button: Button, color: Color) -> void:
	style_button(button, color, 24)
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0, 152)
	button.add_theme_stylebox_override("pressed", make_button_style(color.darkened(0.12), true, true))


static func make_label(text_value: String, font_size: int, color: Color = CREAM) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font", TITLE_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func make_body_label(text_value: String, font_size: int = 18, color: Color = CREAM) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func make_screen_column(root: Control, margin_size: int = 48) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", margin_size)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_right", margin_size)
	margin.add_theme_constant_override("margin_bottom", 30)
	root.add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)
	return column


static func add_title(column: VBoxContainer, kicker: String, title: String, subtitle: String) -> void:
	var kicker_label := make_label(kicker.to_upper(), 18, Color(CREAM, 0.78))
	kicker_label.custom_minimum_size.y = 24
	column.add_child(kicker_label)

	var title_label := make_label(title.to_upper(), 42)
	title_label.custom_minimum_size.y = 54
	column.add_child(title_label)

	var subtitle_label := make_body_label(subtitle, 18, Color(CREAM, 0.90))
	subtitle_label.custom_minimum_size.y = 38
	column.add_child(subtitle_label)


static func add_footer(column: VBoxContainer, back_text: String = "BACK", next_text: String = "NEXT") -> Array[Button]:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	column.add_child(footer)

	var back := Button.new()
	back.text = back_text
	back.custom_minimum_size = Vector2(190, 56)
	style_button(back, INK, 22)
	footer.add_child(back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	var next := Button.new()
	next.text = next_text
	next.custom_minimum_size = Vector2(230, 56)
	style_button(next, GREEN, 22)
	footer.add_child(next)
	return [back, next]


static func make_summary_chip(text_value: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", make_panel(Color(INK, 0.92), 12, false))
	var label := make_body_label(text_value, 16)
	label.custom_minimum_size = Vector2(0, 34)
	chip.add_child(label)
	return chip
