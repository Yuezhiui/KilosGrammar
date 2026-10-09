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
const LANE_COLORS := [Color("#C171CF"), Color("#69BE9A"), Color("#7BC9EF")]
const LANE_NAMES := ["LEFT", "CENTER", "RIGHT"]

var context: Dictionary = {}
var demo_step := -1
var lane_panels: Array[PanelContainer] = []
var lane_labels: Array[Label] = []
var status_label: Label
var progress_label: Label
var try_button: Button
var outer_margin: MarginContainer

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
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 42)
	pad.add_theme_constant_override("margin_top", 26)
	pad.add_theme_constant_override("margin_bottom", 26)
	card.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)
	column.add_child(_label("MOVEMENT PRACTICE", 34, INK, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_label("Stand in CENTER. Step LEFT or RIGHT when the game asks. Return to CENTER before the next move.", 16, INK, HORIZONTAL_ALIGNMENT_CENTER))

	var status_row := HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.add_theme_constant_override("separation", 10)
	column.add_child(status_row)
	status_row.add_child(_status_chip("TRACKING: NOT CONNECTED", RED))
	status_row.add_child(_status_chip("INPUT: TRY MOVE DEMO", YELLOW))

	var lane_row := HBoxContainer.new()
	lane_row.add_theme_constant_override("separation", 14)
	lane_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(lane_row)
	for i in range(3):
		var lane := PanelContainer.new()
		lane.custom_minimum_size = Vector2(0, 230)
		lane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lane.add_theme_stylebox_override("panel", _lane_style(LANE_COLORS[i], false))
		lane_row.add_child(lane)
		lane_panels.append(lane)
		var lane_box := VBoxContainer.new()
		lane_box.alignment = BoxContainer.ALIGNMENT_CENTER
		lane_box.add_theme_constant_override("separation", 12)
		lane.add_child(lane_box)
		var arrow_text := "←" if i == 0 else ("●" if i == 1 else "→")
		lane_box.add_child(_label(arrow_text, 54, CREAM, HORIZONTAL_ALIGNMENT_CENTER))
		var lane_name := _label(LANE_NAMES[i], 24, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
		lane_labels.append(lane_name)
		lane_box.add_child(lane_name)
		var hint: String = ["Step this way", "Ready position", "Step this way"][i]
		lane_box.add_child(_label(hint, 13, CREAM, HORIZONTAL_ALIGNMENT_CENTER))

	status_label = _label("Press TRY MOVE to run a safe UI demonstration.", 16, INK, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(status_label)
	progress_label = _label("Practice progress: 0 / 3", 14, INK, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(progress_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	var back := _button("BACK", INK)
	back.pressed.connect(_go_back)
	actions.add_child(back)
	try_button = _button("TRY MOVE • DEMO", YELLOW)
	try_button.pressed.connect(_run_demo_step)
	actions.add_child(try_button)
	var ready := _button("FINISH TUTORIAL", MINT)
	ready.pressed.connect(_request.bind("tutorial_complete", {"tutorial_practiced": true, "preview_mode": true}))
	actions.add_child(ready)
	try_button.call_deferred("grab_focus")

func _run_demo_step() -> void:
	demo_step = (demo_step + 1) % 3
	var sequence := [1, 0, 2]
	var active_index: int = sequence[demo_step]
	for i in range(lane_panels.size()):
		lane_panels[i].add_theme_stylebox_override("panel", _lane_style(LANE_COLORS[i], i == active_index))
		lane_labels[i].text = ("★ " if i == active_index else "") + LANE_NAMES[i]
	status_label.text = "DEMO: Move to %s. Your real body position is not being read." % LANE_NAMES[active_index]
	progress_label.text = "Practice progress: %d / 3" % (demo_step + 1)
	if demo_step == 2:
		try_button.text = "REPLAY DEMO"

func _go_back() -> void:
	var back_route := "calibration" if bool(context.get("from_calibration", false)) else "tutorial_home"
	requested.emit(back_route, {"preview_mode": true})

func _apply_responsive_layout() -> void:
	if not is_instance_valid(outer_margin):
		return
	var horizontal_margin := int(clampf(size.x * 0.060, 56.0, 118.0))
	var vertical_margin := int(clampf(size.y * 0.052, 30.0, 64.0))
	outer_margin.add_theme_constant_override("margin_left", horizontal_margin)
	outer_margin.add_theme_constant_override("margin_right", horizontal_margin)
	outer_margin.add_theme_constant_override("margin_top", vertical_margin)
	outer_margin.add_theme_constant_override("margin_bottom", vertical_margin)
	var lane_height := clampf(size.y * 0.30, 205.0, 315.0)
	for lane in lane_panels:
		lane.custom_minimum_size.y = lane_height

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

func _button(text_value: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(190, 54)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", TITLE_FONT)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", CREAM)
	button.add_theme_stylebox_override("normal", _panel_style(color, 13, 4))
	button.add_theme_stylebox_override("hover", _panel_style(color.lightened(0.08), 13, 6))
	button.add_theme_stylebox_override("pressed", _panel_style(color.darkened(0.08), 13, 2))
	button.add_theme_stylebox_override("focus", _focus_style())
	return button

func _status_chip(text_value: String, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(250, 34)
	var style := _panel_style(color, 10, 2)
	style.shadow_offset = Vector2(2, 3)
	chip.add_theme_stylebox_override("panel", style)
	var label := _label(text_value, 12, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(label)
	return chip

func _lane_style(color: Color, active: bool) -> StyleBoxFlat:
	var style := _panel_style(color if active else color.darkened(0.05), 22, 8 if active else 4)
	style.border_width_left = 5 if active else 2
	style.border_width_top = 5 if active else 2
	style.border_width_right = 5 if active else 2
	style.border_width_bottom = 5 if active else 2
	style.border_color = CREAM if active else Color(CREAM.r, CREAM.g, CREAM.b, 0.5)
	return style

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
