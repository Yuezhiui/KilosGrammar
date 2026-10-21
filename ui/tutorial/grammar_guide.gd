extends Control

signal requested(target: String, payload: Dictionary)

const TITLE_FONT := preload("res://assets/fonts/TitanOne-Regular.ttf")
const CREAM := Color("#F7E6BD")
const INK := Color("#494463")
const RED := Color("#FF4F66")
const PANEL := Color("#F7E6BDF2")
const ART := preload("res://ui/tutorial/tutorial_theme.gd")
const ENTRIES := [
	["NOUN", "Names a person, place, thing, or idea.", "teacher • park • pencil", Color("#69BE9A")],
	["PRONOUN", "Takes the place of a noun.", "I • she • they", Color("#C171CF")],
	["VERB", "Shows an action or state.", "run • learn • is", Color("#FF4F66")],
	["ADJECTIVE", "Describes a noun or pronoun.", "bright • kind • small", Color("#FFC23D")],
	["ADVERB", "Tells how, when, or where.", "quickly • today • here", Color("#7BC9EF")],
	["PREPOSITION", "Shows position or relationship.", "under • beside • into", Color("#F4985F")],
	["CONJUNCTION", "Connects words or ideas.", "and • but • because", Color("#5AA0D7")],
	["INTERJECTION", "Shows a sudden feeling.", "wow! • hey! • hooray!", Color("#8E78C6")]
]

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
	var scroll := stage.get_node_or_null("GrammarCardScroll") as ScrollContainer
	if scroll != null:
		var grid := scroll.get_node_or_null("GridContainer") as GridContainer
		if grid != null and grid.get_child_count() == 0:
			_populate_cards(grid)
	var back := stage.get_node_or_null("BackButton") as Button
	if back:
		back.pressed.connect(_request.bind("tutorial_home", {}))
		back.call_deferred("grab_focus")
	resized.connect(func() -> void: ART.fit(self, stage))
	ART.fit(self, stage)

func _populate_cards(grid: GridContainer) -> void:
	for index in range(ENTRIES.size()):
		var item: Array = ENTRIES[index]
		var active := index < 5
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(462, 143)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#FFFDF4") if active else Color("#EAE6E1")
		style.set_corner_radius_all(20)
		style.set_border_width_all(2)
		style.border_color = item[3]
		card.add_theme_stylebox_override("panel", style)
		grid.add_child(card)
		var visual := Control.new()
		visual.custom_minimum_size = Vector2(458, 139)
		card.add_child(visual)
		var key := String(item[0]).to_lower()
		var icon_path := "res://ui/redesign/assets/student/topic_" + key + ".png"
		ART.icon(visual, icon_path, Rect2(12, 22, 91, 92))
		ART.label(visual, item[0], Rect2(110, 12, 335, 38), 19, ART.INK, HORIZONTAL_ALIGNMENT_LEFT)
		ART.label(visual, item[1], Rect2(110, 47, 328, 42), 13, ART.INK, HORIZONTAL_ALIGNMENT_LEFT)
		ART.label(visual, "Try: " + String(item[2]), Rect2(110, 95, 337, 33), 12, Color("#675D5A"), HORIZONTAL_ALIGNMENT_LEFT)

func set_context(value: Dictionary) -> void:
	context = value.duplicate(true)


func _build_redesign() -> void:
	var stage := ART.prepare(self, "EXPLORE GRAMMAR!", "Eight parts of speech make up our grammar map. The game currently practices five.", "GRAMMAR GUIDE")
	ART.label(stage, "Scroll the cards to discover meanings and examples.", Rect2(85, 154, 946, 28), 15, ART.INK)
	var scroll := ScrollContainer.new()
	scroll.name = "GrammarCardScroll"
	scroll.position = Vector2(78, 183)
	scroll.size = Vector2(968, 335)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.focus_mode = Control.FOCUS_ALL
	stage.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 15)
	grid.add_theme_constant_override("v_separation", 13)
	scroll.add_child(grid)
	for index in range(ENTRIES.size()):
		var item: Array = ENTRIES[index]
		var active := index < 5
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(462, 143)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#FFFDF4") if active else Color("#EAE6E1")
		style.set_corner_radius_all(20)
		style.set_border_width_all(2)
		style.border_color = item[3]
		card.add_theme_stylebox_override("panel", style)
		grid.add_child(card)
		var visual := Control.new()
		visual.custom_minimum_size = Vector2(458, 139)
		card.add_child(visual)
		var key := String(item[0]).to_lower()
		var icon_path := "res://ui/redesign/assets/student/topic_" + key + ".png"
		ART.icon(visual, icon_path, Rect2(12, 22, 91, 92))
		ART.label(visual, item[0], Rect2(110, 12, 335, 38), 19, ART.INK, HORIZONTAL_ALIGNMENT_LEFT)
		ART.label(visual, item[1], Rect2(110, 47, 328, 42), 13, ART.INK, HORIZONTAL_ALIGNMENT_LEFT)
		ART.label(visual, "Try: " + String(item[2]), Rect2(110, 95, 337, 33), 12, Color("#675D5A"), HORIZONTAL_ALIGNMENT_LEFT)
	ART.label(stage, "Tip: Use your mouse wheel or focus this list and press Arrow Down.", Rect2(82, 525, 762, 27), 13, ART.INK, HORIZONTAL_ALIGNMENT_LEFT)
	var back := ART.button(stage, "BACK TO TUTORIAL", Rect2(789, 537, 260, 60), ART.RED, 16)
	back.pressed.connect(_request.bind("tutorial_home", {}))
	back.call_deferred("grab_focus")

func _build_ui() -> void:
	outer_margin = MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(outer_margin)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(PANEL, 28, 8))
	outer_margin.add_child(card)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 34)
	pad.add_theme_constant_override("margin_right", 34)
	pad.add_theme_constant_override("margin_top", 22)
	pad.add_theme_constant_override("margin_bottom", 22)
	card.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	pad.add_child(column)
	column.add_child(_label("GRAMMAR GUIDE", 34, INK, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_label("Meet the eight parts of speech. The current game focuses on Noun, Verb, Adjective, Adverb, and Pronoun.", 15, INK, HORIZONTAL_ALIGNMENT_CENTER))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for entry in ENTRIES:
		grid.add_child(_grammar_card(entry[0], entry[1], entry[2], entry[3]))
	var back := _button("BACK TO TUTORIAL", RED)
	back.pressed.connect(_request.bind("tutorial_home", {}))
	column.add_child(back)
	back.call_deferred("grab_focus")

func _grammar_card(title: String, meaning: String, examples: String, color: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 122)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _panel_style(color, 18, 4))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	card.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	pad.add_child(box)
	box.add_child(_label(title, 20, CREAM, HORIZONTAL_ALIGNMENT_LEFT))
	box.add_child(_label(meaning, 13, CREAM, HORIZONTAL_ALIGNMENT_LEFT))
	var example := _label("Examples: " + examples, 12, CREAM, HORIZONTAL_ALIGNMENT_LEFT)
	example.modulate.a = 0.86
	box.add_child(example)
	return card

func _request(target: String, payload: Dictionary) -> void:
	requested.emit(target, payload)

func _apply_responsive_layout() -> void:
	if not is_instance_valid(outer_margin):
		return
	var horizontal_margin := int(clampf(size.x * 0.060, 58.0, 118.0))
	var vertical_margin := int(clampf(size.y * 0.045, 30.0, 58.0))
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

func _button(text_value: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(260, 50)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", TITLE_FONT)
	button.add_theme_font_size_override("font_size", 15)
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
	style.shadow_color = Color(INK.r, INK.g, INK.b, 0.32)
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
