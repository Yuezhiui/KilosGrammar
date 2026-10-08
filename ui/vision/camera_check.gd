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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()

func set_context(value: Dictionary) -> void:
	context = value.duplicate(true)

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_bottom", 42)
	add_child(margin)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(PANEL, 28, 8))
	margin.add_child(card)
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
	var badge := _label("PREVIEW MODE • CAMERA STATUS: NOT LIVE", 15, RED, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(badge)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(content)

	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(590, 330)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.add_theme_stylebox_override("panel", _panel_style(INK, 22, 5))
	content.add_child(preview)
	var preview_pad := MarginContainer.new()
	preview_pad.add_theme_constant_override("margin_left", 26)
	preview_pad.add_theme_constant_override("margin_right", 26)
	preview_pad.add_theme_constant_override("margin_top", 34)
	preview_pad.add_theme_constant_override("margin_bottom", 30)
	preview.add_child(preview_pad)
	var preview_box := VBoxContainer.new()
	preview_box.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_box.add_theme_constant_override("separation", 12)
	preview_pad.add_child(preview_box)
	preview_box.add_child(_label("▣", 66, CREAM, HORIZONTAL_ALIGNMENT_CENTER))
	preview_box.add_child(_label("CAMERA PREVIEW PLACEHOLDER", 22, CREAM, HORIZONTAL_ALIGNMENT_CENTER))
	preview_box.add_child(_label("No camera image or pose data is being read on this screen yet.", 14, CREAM, HORIZONTAL_ALIGNMENT_CENTER))
	var frame_hint := _label("When CV is connected: keep your head, hands, and feet inside the frame.", 13, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	frame_hint.modulate.a = 0.72
	preview_box.add_child(frame_hint)

	var checklist := VBoxContainer.new()
	checklist.custom_minimum_size = Vector2(360, 0)
	checklist.add_theme_constant_override("separation", 10)
	content.add_child(checklist)
	checklist.add_child(_status_card("1", "CAMERA FEED", "NOT CONNECTED", RED))
	checklist.add_child(_status_card("2", "BODY POSE", "NOT CONNECTED", RED))
	checklist.add_child(_status_card("3", "PLAY AREA", "UI PREVIEW", YELLOW))
	info_label = _label("You can continue in Preview Mode to explore calibration and movement practice.", 13, INK, HORIZONTAL_ALIGNMENT_CENTER)
	checklist.add_child(info_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var back := _button("BACK", INK, 150)
	back.pressed.connect(_go_back)
	actions.add_child(back)
	var refresh := _button("CHECK UI STATUS", BLUE, 205)
	refresh.pressed.connect(_refresh_preview_status)
	actions.add_child(refresh)
	var skip := _button("SKIP SETUP", YELLOW, 170)
	skip.pressed.connect(_skip_setup)
	actions.add_child(skip)
	var continue_button := _button("CONTINUE IN PREVIEW", MINT, 245)
	continue_button.pressed.connect(_request.bind("calibration", {"preview_mode": true, "camera_live": false}))
	actions.add_child(continue_button)
	continue_button.call_deferred("grab_focus")

func _refresh_preview_status() -> void:
	refresh_count += 1
	var messages := [
		"Still Preview Mode: no camera connector is available yet.",
		"UI check complete. Camera and pose statuses remain NOT CONNECTED.",
		"Preview is ready for navigation. No live detection was performed."
	]
	info_label.text = messages[(refresh_count - 1) % messages.size()]

func _skip_setup() -> void:
	var entry_source := String(context.get("entry_source", "tutorial"))
	var target := "tutorial_practice" if entry_source == "tutorial" else "ready"
	requested.emit(target, {"preview_mode": true, "camera_live": false, "setup_skipped": true, "from_calibration": false})

func _go_back() -> void:
	var entry_source := String(context.get("entry_source", "tutorial"))
	var target := "tutorial_home" if entry_source == "tutorial" else "play_difficulty"
	requested.emit(target, {})

func _status_card(number: String, title: String, status: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 76)
	panel.add_theme_stylebox_override("panel", _panel_style(color, 17, 3))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var number_label := _label(number, 24, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	number_label.custom_minimum_size = Vector2(46, 0)
	number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(number_label)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
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
