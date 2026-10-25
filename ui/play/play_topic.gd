extends Control

signal requested(target: String, payload: Dictionary)

const UI = preload("res://ui/play/play_ui.gd")
const TOPICS := ["Noun", "Verb", "Adjective", "Adverb", "Pronoun"]
const TOPIC_COLORS := [UI.GREEN, UI.RED, UI.YELLOW, UI.BLUE, UI.PURPLE]
const ART := "res://ui/redesign/assets/student/"

var context: Dictionary = {}
var topic_buttons: Dictionary = {}
var next_button: Button
var context_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_add_art_background()
	var column := UI.make_compact_screen_column(self)
	UI.add_compact_title(column, "Play • Step 2 of 3", "Choose a Grammar Topic", "Select the grammar focus for this UI demo.")

	context_label = UI.make_body_label("", 15, Color(UI.CREAM, 0.76))
	context_label.custom_minimum_size.y = 26
	column.add_child(context_label)

	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UI.make_panel(Color(UI.INK, 0.78), 26))
	column.add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	card.add_child(content)

	var grid := GridContainer.new()
	grid.columns = 3
	if get_viewport_rect().size.x < 1000.0:
		grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	content.add_child(grid)

	var group := ButtonGroup.new()
	for index in range(TOPICS.size()):
		var topic: String = TOPICS[index]
		var button := Button.new()
		button.text = topic.to_upper()
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.x = 0
		button.custom_minimum_size.y = 86 if get_viewport_rect().size.x < 1000.0 else 108
		UI.style_compact_selection_button(button, TOPIC_COLORS[index], 20)
		_style_art_button(button, "topic_%s.png" % topic.to_lower())
		button.pressed.connect(_select_topic.bind(topic))
		grid.add_child(button)
		topic_buttons[topic] = button

	var footer: Array[Button] = UI.add_compact_footer(column, "BACK", "NEXT: DIFFICULTY")
	footer[0].pressed.connect(_go_back)
	next_button = footer[1]
	next_button.pressed.connect(_go_next)
	_refresh_selection()
	call_deferred("_focus_default")


func _add_art_background() -> void:
	var clean_backdrop := ColorRect.new()
	clean_backdrop.color = Color("087e75")
	clean_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clean_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clean_backdrop)
	var art := TextureRect.new()
	art.name = "SetupArtworkBackground"
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.texture = load(ART + "setup_main_panel.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)


func _style_art_button(button: Button, filename: String) -> void:
	var texture := load(ART + filename) as Texture2D
	if texture == null:
		return
	button.tooltip_text = button.text
	var art := TextureRect.new()
	art.name = "OriginalButtonArt"
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(art)
	var style := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color", "font_outline_color"]:
		button.add_theme_color_override(state, Color.TRANSPARENT)


func set_context(new_context: Dictionary) -> void:
	for key in new_context:
		context[key] = new_context[key]
	_refresh_selection()


func _select_topic(topic: String) -> void:
	context["topic"] = topic
	_refresh_selection()


func _refresh_selection() -> void:
	if next_button == null:
		return
	var selected := String(context.get("topic", ""))
	for topic in topic_buttons:
		var button: Button = topic_buttons[topic]
		button.set_pressed_no_signal(topic == selected)
	next_button.disabled = not TOPICS.has(selected)
	if context_label:
		context_label.text = "Activity: %s" % String(context.get("activity", "Choose an activity first"))


func _focus_default() -> void:
	var selected := String(context.get("topic", TOPICS[0]))
	var button: Button = topic_buttons.get(selected, topic_buttons[TOPICS[0]])
	button.grab_focus()


func _go_back() -> void:
	requested.emit("play_activity", context.duplicate(true))


func _go_next() -> void:
	if next_button.disabled:
		return
	requested.emit("play_difficulty", context.duplicate(true))
