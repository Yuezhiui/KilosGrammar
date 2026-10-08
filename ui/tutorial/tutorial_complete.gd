extends Control

signal requested(target: String, payload: Dictionary)

const FONT := preload("res://assets/fonts/TitanOne-Regular.ttf")
const INK := Color("#494463")
const CREAM := Color("#F7E6BD")
const MINT := Color("#69BE9A")
const BLUE := Color("#7BC9EF")
const YELLOW := Color("#FFC23D")
const RED := Color("#FF4F66")

var context: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 125)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 58)
	add_child(margin)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(Color("#F7E6BDF2"), 28))
	margin.add_child(card)
	var pad := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		pad.add_theme_constant_override(side, 48)
	for side in ["margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, 30)
	card.add_child(pad)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 18)
	pad.add_child(column)
	column.add_child(_label("★  NICE WORK!  ★", 30, Color("#00886B")))
	column.add_child(_label("TUTORIAL PREVIEW FINISHED", 37, INK))
	column.add_child(_label("You explored the LEFT, CENTER, and RIGHT movement tutorial.", 18, INK))

	var status := PanelContainer.new()
	status.add_theme_stylebox_override("panel", _style(Color("#494463"), 18))
	column.add_child(status)
	var status_label := _label("UI DEMONSTRATION ONLY\nYour body movements have not been verified.\nReal calibration and motion tracking will be available after the camera/YOLO integration.", 16, CREAM)
	status_label.custom_minimum_size.y = 110
	status.add_child(status_label)

	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 16)
	actions.add_theme_constant_override("v_separation", 14)
	column.add_child(actions)
	var play := _button("GO TO PLAY", MINT)
	play.pressed.connect(_request.bind("play_activity", {"entry_source": "play"}))
	actions.add_child(play)
	var again := _button("PRACTICE AGAIN", BLUE)
	again.pressed.connect(_request.bind("tutorial_practice", {"entry_source": "tutorial", "from_calibration": false}))
	actions.add_child(again)
	var guide := _button("GRAMMAR GUIDE", YELLOW)
	guide.pressed.connect(_request.bind("grammar_guide", {}))
	actions.add_child(guide)
	var home := _button("MAIN MENU", RED)
	home.pressed.connect(_request.bind("main", {}))
	actions.add_child(home)
	play.call_deferred("grab_focus")


func set_context(value: Dictionary) -> void:
	context = value.duplicate(true)


func _request(target: String, payload: Dictionary) -> void:
	requested.emit(target, payload)


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _button(value: String, color: Color) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(340, 57)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", CREAM)
	button.add_theme_stylebox_override("normal", _style(color, 13))
	button.add_theme_stylebox_override("hover", _style(color.lightened(0.08), 13))
	button.add_theme_stylebox_override("pressed", _style(color.darkened(0.08), 13))
	button.add_theme_stylebox_override("focus", _focus_style())
	return button


func _style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(INK.r, INK.g, INK.b, 0.34)
	style.shadow_size = 5
	style.shadow_offset = Vector2(4, 6)
	return style


func _focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
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
