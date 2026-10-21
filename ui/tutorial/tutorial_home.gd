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
const ART := preload("res://ui/tutorial/tutorial_theme.gd")
const SETTINGS_PREFS := preload("res://ui/secondary/settings.gd")

var context: Dictionary = {}
var outer_margin: MarginContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if DisplayServer.get_name() != "headless":
		SETTINGS_PREFS.restore_saved_preferences(true)
	var stage := get_node_or_null("TutorialStage") as Control
	if stage != null:
		_bind_scene_nodes(stage)
	else:
		_build_redesign()

func _bind_scene_nodes(stage: Control) -> void:
	var start := stage.get_node_or_null("StartButton") as Button
	var practice := stage.get_node_or_null("PracticeButton") as Button
	var grammar := stage.get_node_or_null("GrammarButton") as Button
	var back := stage.get_node_or_null("BackButton") as Button

	var art_guided := stage.get_node_or_null("ButtonArtwork_START_GUIDED_TUTORIAL") as TextureRect
	var art_move := stage.get_node_or_null("ButtonArtwork_MOVEMENT_PRACTICE") as TextureRect
	var art_gram := stage.get_node_or_null("ButtonArtwork_GRAMMAR_GUIDE") as TextureRect
	var art_back := stage.get_node_or_null("ButtonArtwork_BACK_TO_MAIN") as TextureRect

	_bind_button_interactive(start, art_guided, func() -> void: _request("camera_check", {"entry_source": "tutorial", "preview_mode": true, "camera_live": false}))
	_bind_button_interactive(practice, art_move, func() -> void: _request("tutorial_practice", {"entry_source": "tutorial", "preview_mode": true, "camera_live": false, "from_calibration": false}))
	_bind_button_interactive(grammar, art_gram, func() -> void: _request("grammar_guide", {}))
	_bind_button_interactive(back, art_back, func() -> void: _request("main", {}))

	if start:
		start.call_deferred("grab_focus")

	resized.connect(func() -> void: ART.fit(self, stage, Vector2(1280.0, 720.0)))
	ART.fit(self, stage, Vector2(1280.0, 720.0))

func _bind_button_interactive(btn: Button, art: TextureRect, on_pressed: Callable) -> void:
	if btn == null:
		return
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(on_pressed)
	if art != null:
		btn.mouse_entered.connect(func() -> void: art.modulate = Color(1.15, 1.15, 1.15))
		btn.mouse_exited.connect(func() -> void: art.modulate = Color.WHITE)
		btn.focus_entered.connect(func() -> void: art.modulate = Color(1.15, 1.15, 1.15))
		btn.focus_exited.connect(func() -> void: art.modulate = Color.WHITE)
		btn.button_down.connect(func() -> void: art.modulate = Color(0.85, 0.85, 0.85))
		btn.button_up.connect(func() -> void: art.modulate = Color(1.15, 1.15, 1.15) if btn.has_focus() or btn.is_hovered() else Color.WHITE)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			SETTINGS_PREFS.toggle_fullscreen()
			get_viewport().set_input_as_handled()

func set_context(value: Dictionary) -> void:
	context = value.duplicate(true)


func _build_redesign() -> void:
	var stage := ART.prepare(self, "", "", "")
	ART.icon(stage, ART.TUTORIAL_ART + "title_whole_body.png", Rect2(181, 20, 758, 160))
	# The three numbered cards and their lettering are already painted in the
	# supplied reference art. Keep them as one clean image, without text doubles.
	ART.icon(stage, ART.TUTORIAL_ART + "steps_three.png", Rect2(81, 174, 954, 239))
	ART.icon(stage, ART.TUTORIAL_ART + "camera_advisory.png", Rect2(161, 401, 798, 60))
	var start := ART.artwork_button(stage, "START GUIDED TUTORIAL", Rect2(145, 461, 384, 71), ART.TUTORIAL_ART + "button_guided.png", ART.GREEN)
	start.pressed.connect(_request.bind("camera_check", {"entry_source": "tutorial", "preview_mode": true, "camera_live": false}))
	var practice := ART.artwork_button(stage, "MOVEMENT PRACTICE", Rect2(591, 461, 384, 71), ART.TUTORIAL_ART + "button_movement.png", ART.BLUE)
	practice.pressed.connect(_request.bind("tutorial_practice", {"entry_source": "tutorial", "preview_mode": true, "camera_live": false, "from_calibration": false}))
	var grammar := ART.artwork_button(stage, "GRAMMAR GUIDE", Rect2(145, 537, 384, 69), ART.TUTORIAL_ART + "button_grammar.png", ART.PURPLE)
	grammar.pressed.connect(_request.bind("grammar_guide", {}))
	var back := ART.artwork_button(stage, "BACK TO MAIN", Rect2(591, 537, 384, 69), ART.TUTORIAL_ART + "button_back.png", ART.RED)
	back.pressed.connect(_request.bind("main", {}))
	start.call_deferred("grab_focus")

func _build_ui() -> void:
	outer_margin = MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(outer_margin)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(PANEL, 28, 8))
	outer_margin.add_child(card)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 48)
	pad.add_theme_constant_override("margin_right", 48)
	pad.add_theme_constant_override("margin_top", 34)
	pad.add_theme_constant_override("margin_bottom", 34)
	card.add_child(pad)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 16)
	pad.add_child(column)

	var eyebrow := _label("TUTORIAL PATH", 18, INK, HORIZONTAL_ALIGNMENT_CENTER)
	eyebrow.modulate.a = 0.78
	column.add_child(eyebrow)
	column.add_child(_label("LEARN WITH YOUR WHOLE BODY!", 38, INK, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_label("We’ll check the camera setup, practice LEFT • CENTER • RIGHT, then you can jump into the game.", 17, INK, HORIZONTAL_ALIGNMENT_CENTER))

	var path_row := HBoxContainer.new()
	path_row.alignment = BoxContainer.ALIGNMENT_CENTER
	path_row.add_theme_constant_override("separation", 10)
	column.add_child(path_row)
	_add_step(path_row, "1", "Camera", MINT)
	_add_arrow(path_row)
	_add_step(path_row, "2", "Calibrate", YELLOW)
	_add_arrow(path_row)
	_add_step(path_row, "3", "Practice", BLUE)

	var note := _label("Camera and body tracking are UI previews until computer-vision integration is connected.", 14, INK, HORIZONTAL_ALIGNMENT_CENTER)
	note.modulate.a = 0.78
	column.add_child(note)

	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 16)
	actions.add_theme_constant_override("v_separation", 14)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(actions)

	var start := _button("START GUIDED TUTORIAL", MINT, "Camera check → calibration → movement practice")
	start.pressed.connect(_request.bind("camera_check", {"entry_source": "tutorial", "preview_mode": true}))
	actions.add_child(start)
	var practice := _button("MOVEMENT PRACTICE", BLUE, "Try the movement demo directly")
	practice.pressed.connect(_request.bind("tutorial_practice", {"entry_source": "tutorial", "preview_mode": true, "from_calibration": false}))
	actions.add_child(practice)
	var grammar := _button("GRAMMAR GUIDE", PURPLE, "Meet the 8 parts of speech")
	grammar.pressed.connect(_request.bind("grammar_guide", {}))
	actions.add_child(grammar)
	var back := _button("BACK TO MAIN", RED, "Return to the main menu")
	back.pressed.connect(_request.bind("main", {}))
	actions.add_child(back)
	start.call_deferred("grab_focus")

func _add_step(row: HBoxContainer, number: String, title: String, color: Color) -> void:
	var step := PanelContainer.new()
	step.custom_minimum_size = Vector2(190, 72)
	step.add_theme_stylebox_override("panel", _panel_style(color, 18, 4))
	row.add_child(step)
	var label := _label(number + "  " + title.to_upper(), 18, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	step.add_child(label)

func _add_arrow(row: HBoxContainer) -> void:
	var arrow := _label("→", 28, INK, HORIZONTAL_ALIGNMENT_CENTER)
	arrow.custom_minimum_size = Vector2(34, 72)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(arrow)

func _request(target: String, payload: Dictionary) -> void:
	requested.emit(target, payload)

func _apply_responsive_layout() -> void:
	if not is_instance_valid(outer_margin):
		return
	var horizontal_margin := int(clampf(size.x * 0.072, 72.0, 138.0))
	var vertical_margin := int(clampf(size.y * 0.070, 44.0, 82.0))
	outer_margin.add_theme_constant_override("margin_left", horizontal_margin)
	outer_margin.add_theme_constant_override("margin_right", horizontal_margin)
	outer_margin.add_theme_constant_override("margin_top", vertical_margin)
	outer_margin.add_theme_constant_override("margin_bottom", vertical_margin)

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

func _button(text_value: String, color: Color, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(0, 64)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", TITLE_FONT)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", CREAM)
	button.add_theme_color_override("font_focus_color", CREAM)
	button.add_theme_stylebox_override("normal", _panel_style(color, 14, 4))
	button.add_theme_stylebox_override("hover", _panel_style(color.lightened(0.08), 14, 6))
	button.add_theme_stylebox_override("pressed", _panel_style(color.darkened(0.08), 14, 2))
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
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	return style
