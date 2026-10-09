extends Control

signal requested(target: String, payload: Dictionary)

const TITLE_FONT := preload("res://assets/fonts/TitanOne-Regular.ttf")
const CREAM := Color("#F7E6BD")
const INK := Color("#494463")
const MINT := Color("#00886B")
const RED := Color("#FF4F66")
const YELLOW := Color("#FFC23D")
const BLUE := Color("#7BC9EF")
const PANEL := Color("#F7E6BDF2")

var context: Dictionary = {}
var info_label: Label
var refresh_count := 0
var outer_margin: MarginContainer
var preview_panel: PanelContainer
var checklist: VBoxContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	resized.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")

func set_context(value: Dictionary) -> void:
	context = value.duplicate(true)

func _build_ui() -> void:
	outer_margin = MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(outer_margin)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(PANEL, 28, 8))
	outer_margin.add_child(card)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 36)
	pad.add_theme_constant_override("margin_right", 36)
	pad.add_theme_constant_override("margin_top", 24)
	pad.add_theme_constant_override("margin_bottom", 24)
	card.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)
	column.add_child(_label("CAMERA CHECK", 34, INK, HORIZONTAL_ALIGNMENT_CENTER))
	var badge := _label("PREVIEW MODE  •  TRACKING NOT CONNECTED", 15, RED, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(badge)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)

	var preview_column := VBoxContainer.new()
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_column.add_theme_constant_override("separation", 8)
	content.add_child(preview_column)
	var frame_caption := _label("CAMERA FRAME  •  16:9 PREVIEW", 13, INK, HORIZONTAL_ALIGNMENT_CENTER)
	frame_caption.modulate.a = 0.76
	preview_column.add_child(frame_caption)
	preview_panel = PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(590, 332)
	preview_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_panel.add_theme_stylebox_override("panel", _preview_style())
	preview_column.add_child(preview_panel)
	var preview_pad := MarginContainer.new()
	preview_pad.add_theme_constant_override("margin_left", 26)
	preview_pad.add_theme_constant_override("margin_right", 26)
	preview_pad.add_theme_constant_override("margin_top", 34)
	preview_pad.add_theme_constant_override("margin_bottom", 30)
	preview_panel.add_child(preview_pad)
	var preview_box := VBoxContainer.new()
	preview_box.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_box.add_theme_constant_override("separation", 12)
	preview_pad.add_child(preview_box)
	preview_box.add_child(_label("▣", 62, CREAM, HORIZONTAL_ALIGNMENT_CENTER))
	preview_box.add_child(_label("NO VIDEO FEED", 22, CREAM, HORIZONTAL_ALIGNMENT_CENTER))
	preview_box.add_child(_label("Camera and pose tracking are not connected yet.", 14, CREAM, HORIZONTAL_ALIGNMENT_CENTER))
	var frame_hint := _label("Future setup: keep your head, hands, and feet inside this frame.", 13, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	frame_hint.modulate.a = 0.72
	preview_box.add_child(frame_hint)

	checklist = VBoxContainer.new()
	checklist.custom_minimum_size = Vector2(360, 0)
	checklist.add_theme_constant_override("separation", 10)
	content.add_child(checklist)
	checklist.add_child(_label("SETUP STATUS", 17, INK, HORIZONTAL_ALIGNMENT_CENTER))
	checklist.add_child(_status_card("1", "CAMERA FEED", "NOT CONNECTED", RED))
	checklist.add_child(_status_card("2", "POSE TRACKING", "NOT CONNECTED", RED))
	checklist.add_child(_status_card("3", "3-LANE PLAYER VIEW", "DEMO PREVIEW", YELLOW))
	var note := _label("No image, skeleton, or player position is being detected on this screen.", 12, INK, HORIZONTAL_ALIGNMENT_CENTER)
	note.modulate.a = 0.72
	checklist.add_child(note)
	info_label = _label("Continue in Preview Mode to explore the calibration UI.", 13, INK, HORIZONTAL_ALIGNMENT_CENTER)
	checklist.add_child(info_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var back := _button("BACK", INK, 150)
	back.pressed.connect(_go_back)
	actions.add_child(back)
	var refresh := _button("CHECK STATUS", BLUE, 185)
	refresh.pressed.connect(_refresh_preview_status)
	actions.add_child(refresh)
	var skip := _button("SKIP SETUP", YELLOW, 165)
	skip.pressed.connect(_skip_setup)
	actions.add_child(skip)
	var continue_button := _button("CONTINUE IN PREVIEW", MINT, 235)
	continue_button.pressed.connect(_request.bind("calibration", {"preview_mode": true, "camera_live": false}))
	actions.add_child(continue_button)
	continue_button.call_deferred("grab_focus")

func _refresh_preview_status() -> void:
	refresh_count += 1
	var messages := [
		"Camera feed: NOT CONNECTED. Pose tracking: NOT CONNECTED.",
		"Status checked. This remains a UI-only preview with no live detection.",
		"Preview navigation is ready. No player position has been measured."
	]
	info_label.text = messages[(refresh_count - 1) % messages.size()]

func _skip_setup() -> void:
	var entry_source := String(context.get("entry_source", "tutorial"))
	var target := "tutorial_practice" if entry_source == "tutorial" else "ready"
	requested.emit(target, {"preview_mode": true, "camera_live": false, "setup_skipped": true, "from_calibration": false})

func _go_back() -> void:
	var entry_source := String(context.get("entry_source", "tutorial"))
	var target := "tutorial_home" if entry_source == "tutorial" else ("play_activity" if bool(context.get("setup_preview", false)) else "play_difficulty")
	requested.emit(target, {})

func _apply_responsive_layout() -> void:
	if not is_instance_valid(outer_margin) or not is_instance_valid(preview_panel) or not is_instance_valid(checklist):
		return
	var horizontal_margin := int(clampf(size.x * 0.055, 52.0, 110.0))
	var vertical_margin := int(clampf(size.y * 0.050, 30.0, 62.0))
	outer_margin.add_theme_constant_override("margin_left", horizontal_margin)
	outer_margin.add_theme_constant_override("margin_right", horizontal_margin)
	outer_margin.add_theme_constant_override("margin_top", vertical_margin)
	outer_margin.add_theme_constant_override("margin_bottom", vertical_margin)
	var preview_width := clampf(size.x * 0.46, 540.0, 900.0)
	var preview_height := preview_width * 9.0 / 16.0
	preview_panel.custom_minimum_size = Vector2(preview_width, preview_height)
	checklist.custom_minimum_size.x = clampf(size.x * 0.27, 330.0, 430.0)

func _status_card(number: String, title: String, status: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 76)
	panel.add_theme_stylebox_override("panel", _panel_style(color, 17, 3))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var number_label := _label(number, 24, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	number_label.custom_minimum_size = Vector2(46, 0)
	number_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(number_label)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	box.add_child(_label(title, 15, CREAM, HORIZONTAL_ALIGNMENT_LEFT))
	var status_label := _label(status, 12, CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	status_label.modulate.a = 0.82
	box.add_child(status_label)
	return panel

func _request(target: String, payload: Dictionary) -> void:
	requested.emit(target, payload)

func _label(text_value: String, font_size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font", TITLE_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _button(text_value: String, color: Color, width: float) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(width, 52)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", TITLE_FONT)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", CREAM)
	button.add_theme_stylebox_override("normal", _panel_style(color, 13, 4))
	button.add_theme_stylebox_override("hover", _panel_style(color.lightened(0.08), 13, 6))
	button.add_theme_stylebox_override("pressed", _panel_style(color.darkened(0.08), 13, 2))
	button.add_theme_stylebox_override("focus", _focus_style())
	return button

func _panel_style(color: Color, radius: int, shadow: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(INK.r, INK.g, INK.b, 0.34)
	style.shadow_size = shadow
	style.shadow_offset = Vector2(4, 6)
	return style

func _preview_style() -> StyleBoxFlat:
	var style := _panel_style(INK, 22, 5)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(CREAM.r, CREAM.g, CREAM.b, 0.52)
	return style

func _focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = CREAM
	style.corner_radius_top_left = 13
	style.corner_radius_top_right = 13
	style.corner_radius_bottom_left = 13
	style.corner_radius_bottom_right = 13
	return style
