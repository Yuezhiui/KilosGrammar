extends Control

signal requested(target: String, payload: Dictionary)

const TITLE_FONT := preload("res://assets/fonts/TitanOne-Regular.ttf")
const CREAM := Color("#F7E6BD")
const INK := Color("#494463")
const MINT := Color("#00886B")
const RED := Color("#FF4F66")
const YELLOW := Color("#FFC23D")
const BLUE := Color("#7BC9EF")
const PURPLE := Color("#C171CF")
const PANEL := Color("#F7E6BDF2")
const LANE_NAMES := ["LEFT", "CENTER", "RIGHT"]
const LANE_COLORS := [PURPLE, MINT, BLUE]
const DEMO_SEQUENCE := [1, 0, 1, 2]

var context: Dictionary = {}
var demo_index := -1
var lane_panels: Array[PanelContainer] = []
var lane_labels: Array[Label] = []
var lane_hints: Array[Label] = []
var instruction_label: Label
var progress_label: Label
var demo_button: Button
var player_label: Label
var outer_margin: MarginContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	resized.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")

func set_context(value: Dictionary) -> void:
	context = value.duplicate(true)
	_refresh_player_label()

func _build_ui() -> void:
	outer_margin = MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(outer_margin)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(PANEL, 28, 8))
	outer_margin.add_child(card)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 40)
	pad.add_theme_constant_override("margin_right", 40)
	pad.add_theme_constant_override("margin_top", 24)
	pad.add_theme_constant_override("margin_bottom", 24)
	card.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 11)
	pad.add_child(column)
	column.add_child(_label("CALIBRATION PREVIEW", 34, INK, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_label("TRACKING NOT CONNECTED  •  DEMO ONLY", 14, RED, HORIZONTAL_ALIGNMENT_CENTER))
	player_label = _label("PLAYER: DEMO PREVIEW", 14, INK, HORIZONTAL_ALIGNMENT_CENTER)
	player_label.modulate.a = 0.78
	column.add_child(player_label)
	column.add_child(_label("Each player will get LEFT, CENTER, and RIGHT movement zones after camera integration. This screen only previews that flow.", 14, INK, HORIZONTAL_ALIGNMENT_CENTER))

	var lane_row := HBoxContainer.new()
	lane_row.add_theme_constant_override("separation", 14)
	lane_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(lane_row)
	for i in range(3):
		var lane := PanelContainer.new()
		lane.custom_minimum_size = Vector2(0, 220)
		lane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lane.add_theme_stylebox_override("panel", _lane_style(LANE_COLORS[i], false))
		lane_row.add_child(lane)
		lane_panels.append(lane)
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 8)
		lane.add_child(box)
		var symbol: String = ["←", "●", "→"][i]
		box.add_child(_label(symbol, 52, CREAM, HORIZONTAL_ALIGNMENT_CENTER))
		var lane_label := _label(LANE_NAMES[i], 22, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
		lane_labels.append(lane_label)
		box.add_child(lane_label)
		var lane_hint_text: String = ["Player moves left", "Player starts here", "Player moves right"][i]
		var lane_hint := _label(lane_hint_text, 12, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
		lane_hints.append(lane_hint)
		box.add_child(lane_hint)

	instruction_label = _label("Start in CENTER. Press TEST STEP to preview a per-player calibration sequence.", 15, INK, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(instruction_label)
	progress_label = _label("Calibration status: NOT MEASURED  •  Demo step 0 / 4", 13, INK, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(progress_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var back := _button("BACK", INK, 130)
	back.pressed.connect(_request.bind("camera_check", {"preview_mode": true, "camera_live": false}))
	actions.add_child(back)
	demo_button = _button("TEST STEP • DEMO", YELLOW, 180)
	demo_button.pressed.connect(_run_demo_step)
	actions.add_child(demo_button)
	var retry := _button("RETRY CALIBRATION", BLUE, 190)
	retry.tooltip_text = "Reset the UI-only calibration preview"
	retry.pressed.connect(_retry_calibration)
	actions.add_child(retry)
	var skip := _button("SKIP", RED, 115)
	skip.pressed.connect(_continue_flow.bind(true))
	actions.add_child(skip)
	var continue_button := _button("CONTINUE", MINT, 160)
	continue_button.pressed.connect(_continue_flow.bind(false))
	actions.add_child(continue_button)
	demo_button.call_deferred("grab_focus")

func _run_demo_step() -> void:
	demo_index = (demo_index + 1) % DEMO_SEQUENCE.size()
	var active_index: int = DEMO_SEQUENCE[demo_index]
	for i in range(lane_panels.size()):
		lane_panels[i].add_theme_stylebox_override("panel", _lane_style(LANE_COLORS[i], i == active_index))
		lane_labels[i].text = ("★ " if i == active_index else "") + LANE_NAMES[i]
		lane_hints[i].text = "DEMO PLAYER HERE" if i == active_index else ["Player moves left", "Player starts here", "Player moves right"][i]
	instruction_label.text = "DEMO STEP: Move to %s. The highlighted lane is UI animation only." % LANE_NAMES[active_index]
	progress_label.text = "Calibration status: NOT MEASURED  •  Demo step %d / %d" % [demo_index + 1, DEMO_SEQUENCE.size()]
	if demo_index == DEMO_SEQUENCE.size() - 1:
		instruction_label.text = "Preview complete. No camera data, pose, or lane measurements were captured."
		demo_button.text = "REPLAY DEMO"

func _retry_calibration() -> void:
	demo_index = -1
	for i in range(lane_panels.size()):
		lane_panels[i].add_theme_stylebox_override("panel", _lane_style(LANE_COLORS[i], false))
		lane_labels[i].text = LANE_NAMES[i]
		lane_hints[i].text = ["Player moves left", "Player starts here", "Player moves right"][i]
	instruction_label.text = "Calibration preview reset. Start in CENTER and press TEST STEP when ready."
	progress_label.text = "Calibration status: NOT MEASURED  •  Demo step 0 / 4"
	demo_button.text = "TEST STEP • DEMO"
	demo_button.grab_focus()

func _continue_flow(skipped: bool) -> void:
	var entry_source := String(context.get("entry_source", "play"))
	var target := "tutorial_practice" if entry_source == "tutorial" else "ready"
	requested.emit(target, {
		"preview_mode": true,
		"camera_live": false,
		"calibration_live": false,
		"from_calibration": true,
		"calibration_skipped": skipped,
		"calibration_previewed": demo_index >= 0
	})

func _request(target: String, payload: Dictionary) -> void:
	requested.emit(target, payload)

func _refresh_player_label() -> void:
	if not is_instance_valid(player_label):
		return
	var display_name := "DEMO PREVIEW"
	for key in ["name", "student_name", "player_name"]:
		var candidate := String(context.get(key, "")).strip_edges()
		if not candidate.is_empty():
			display_name = candidate.to_upper()
			break
	player_label.text = "PLAYER: " + display_name + "  •  LANES ARE NOT MEASURED"

func _apply_responsive_layout() -> void:
	if not is_instance_valid(outer_margin):
		return
	var horizontal_margin := int(clampf(size.x * 0.055, 52.0, 112.0))
	var vertical_margin := int(clampf(size.y * 0.050, 30.0, 62.0))
	outer_margin.add_theme_constant_override("margin_left", horizontal_margin)
	outer_margin.add_theme_constant_override("margin_right", horizontal_margin)
	outer_margin.add_theme_constant_override("margin_top", vertical_margin)
	outer_margin.add_theme_constant_override("margin_bottom", vertical_margin)
	var lane_height := clampf(size.y * 0.29, 195.0, 305.0)
	for lane in lane_panels:
		lane.custom_minimum_size.y = lane_height

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
