extends Control

signal requested(target: String, payload: Dictionary)

const FONT := preload("res://assets/fonts/TitanOne-Regular.ttf")
const INK := Color("#494463")
const CREAM := Color("#F7E6BD")
const MINT := Color("#00886B")
const BLUE := Color("#7BC9EF")
const YELLOW := Color("#FFC23D")
const RED := Color("#FF4F66")
const ART := preload("res://ui/tutorial/tutorial_theme.gd")

var context: Dictionary = {}
var outer_margin: MarginContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var stage := get_node_or_null("TutorialStage") as Control
	if stage != null:
		_bind_scene_nodes(stage)
	else:
		_build_redesign()

func _bind_scene_nodes(stage: Control) -> void:
	var play := stage.get_node_or_null("PlayButton") as Button
	if play:
		play.pressed.connect(_request.bind("student_setup", {"entry_source": "play", "fresh_setup": true}))
		play.call_deferred("grab_focus")
	var again := stage.get_node_or_null("AgainButton") as Button
	if again:
		again.pressed.connect(_request.bind("tutorial_practice", {"entry_source": "tutorial", "preview_mode": true, "camera_live": false, "from_calibration": false}))
	var guide := stage.get_node_or_null("GuideButton") as Button
	if guide:
		guide.pressed.connect(_request.bind("grammar_guide", {}))
	var home := stage.get_node_or_null("HomeButton") as Button
	if home:
		home.pressed.connect(_request.bind("main", {}))
	resized.connect(func() -> void: ART.fit(self, stage))
	ART.fit(self, stage)


func _build_redesign() -> void:
	var stage := ART.prepare(self, "YOU FINISHED THE PREVIEW!", "You explored how the three movement lanes would work in the real game.", "NICE WORK!")
	ART.panel(stage, Rect2(102, 174, 915, 114), Color("#ECF9E8"), 23)
	ART.label(stage, "★  GREAT JOB EXPLORING!  ★", Rect2(138, 181, 837, 51), 29, ART.GREEN)
	ART.label(stage, "LEFT  •  CENTER  •  RIGHT", Rect2(138, 233, 837, 36), 19, ART.INK)
	ART.panel(stage, Rect2(103, 310, 914, 104), Color("#435C63"), 19)
	ART.label(stage, "PREVIEW FINISHED — NOT A TRACKING RESULT", Rect2(119, 321, 882, 35), 19, Color.WHITE)
	ART.label(stage, "Your body was not measured. Camera recognition and real player calibration are not connected.", Rect2(153, 362, 816, 46), 15, Color("#FFEFCA"))
	var play := ART.button(stage, "GO TO PLAY", Rect2(105, 438, 430, 60), ART.GREEN)
	play.pressed.connect(_request.bind("student_setup", {"entry_source": "play", "fresh_setup": true}))
	var again := ART.button(stage, "PRACTICE AGAIN", Rect2(568, 438, 430, 60), ART.BLUE)
	again.pressed.connect(_request.bind("tutorial_practice", {"entry_source": "tutorial", "preview_mode": true, "camera_live": false, "from_calibration": false}))
	var guide := ART.button(stage, "GRAMMAR GUIDE", Rect2(105, 520, 430, 60), ART.PURPLE)
	guide.pressed.connect(_request.bind("grammar_guide", {}))
	var home := ART.button(stage, "MAIN MENU", Rect2(568, 520, 430, 60), ART.RED)
	home.pressed.connect(_request.bind("main", {}))
	play.call_deferred("grab_focus")


func _legacy_ready() -> void:
	outer_margin = MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(outer_margin)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(Color("#F7E6BDF2"), 28))
	outer_margin.add_child(card)
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
	var status_label := _label("UI DEMONSTRATION ONLY\nYour body movements have not been verified.\nReal calibration and motion tracking will be available after camera/CV integration.", 16, CREAM)
	status_label.custom_minimum_size.y = 110
	status.add_child(status_label)

	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 16)
	actions.add_theme_constant_override("v_separation", 14)
	column.add_child(actions)
	var play := _button("GO TO PLAY", MINT)
	play.pressed.connect(_request.bind("student_setup", {"entry_source": "play", "fresh_setup": true}))
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
	resized.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")


func set_context(value: Dictionary) -> void:
	context = value.duplicate(true)


func _request(target: String, payload: Dictionary) -> void:
	requested.emit(target, payload)


func _apply_responsive_layout() -> void:
	if not is_instance_valid(outer_margin):
		return
	var horizontal_margin := int(clampf(size.x * 0.085, 86.0, 160.0))
	var vertical_margin := int(clampf(size.y * 0.065, 42.0, 76.0))
	outer_margin.add_theme_constant_override("margin_left", horizontal_margin)
	outer_margin.add_theme_constant_override("margin_right", horizontal_margin)
	outer_margin.add_theme_constant_override("margin_top", vertical_margin)
	outer_margin.add_theme_constant_override("margin_bottom", vertical_margin)


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
