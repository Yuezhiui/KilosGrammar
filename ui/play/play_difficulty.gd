extends Control

signal requested(target: String, payload: Dictionary)

const UI = preload("res://ui/play/play_ui.gd")
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const DIFFICULTY_COPY := {
	"Easy": "UI preview preset\nRelaxed pacing",
	"Normal": "UI preview preset\nBalanced pacing",
	"Hard": "UI preview preset\nFast pacing"
}
const DIFFICULTY_COLORS := [UI.GREEN, UI.YELLOW, UI.RED]
const ART := "res://Components/Student Setup/Redesign/"

var context: Dictionary = {}
var difficulty_buttons: Dictionary = {}
var next_button: Button
var context_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var clean_backdrop := ColorRect.new()
	clean_backdrop.color = Color("087e75")
	clean_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clean_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clean_backdrop)
	var background := TextureRect.new()
	background.name = "SetupArtworkBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = load(ART + "setup_main_panel.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var column := UI.make_compact_screen_column(self)
	UI.add_compact_title(column, "Play • Step 3 of 3", "Choose Difficulty", "Choose a pacing preset for the interface preview.")

	context_label = UI.make_body_label("", 15, Color(UI.CREAM, 0.76))
	context_label.custom_minimum_size.y = 26
	column.add_child(context_label)

	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UI.make_panel(Color(UI.INK, 0.78), 26))
	column.add_child(card)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", 14)
	card.add_child(grid)

	var group := ButtonGroup.new()
	for index in range(DIFFICULTIES.size()):
		var difficulty: String = DIFFICULTIES[index]
		var button := Button.new()
		button.text = "%s\n\n%s" % [difficulty.to_upper(), DIFFICULTY_COPY[difficulty]]
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		UI.style_compact_selection_button(button, DIFFICULTY_COLORS[index], 20)
		var image := load(ART + "difficulty_%s.png" % difficulty.to_lower()) as Texture2D
		if image:
			var art := TextureRect.new()
			art.name = "OriginalButtonArt"
			art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			art.texture = image
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(art)
			var image_style := StyleBoxEmpty.new()
			for state in ["normal", "hover", "pressed", "focus", "disabled"]:
				button.add_theme_stylebox_override(state, image_style)
			button.tooltip_text = button.text.replace("\n", " ")
			for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color", "font_outline_color"]:
				button.add_theme_color_override(state, Color.TRANSPARENT)
		button.custom_minimum_size.y = 132 if get_viewport_rect().size.x < 1000.0 else 172
		button.pressed.connect(_select_difficulty.bind(difficulty))
		grid.add_child(button)
		difficulty_buttons[difficulty] = button

	var footer: Array[Button] = UI.add_compact_footer(column, "BACK", "NEXT: CAMERA CHECK")
	footer[0].pressed.connect(_go_back)
	next_button = footer[1]
	next_button.pressed.connect(_go_next)
	_refresh_selection()
	call_deferred("_focus_default")


func set_context(new_context: Dictionary) -> void:
	for key in new_context:
		context[key] = new_context[key]
	_refresh_selection()


func _select_difficulty(difficulty: String) -> void:
	context["difficulty"] = difficulty
	_refresh_selection()


func _refresh_selection() -> void:
	if next_button == null:
		return
	var selected := String(context.get("difficulty", ""))
	for difficulty in difficulty_buttons:
		var button: Button = difficulty_buttons[difficulty]
		button.set_pressed_no_signal(difficulty == selected)
	next_button.disabled = not DIFFICULTIES.has(selected)
	if context_label:
		context_label.text = "%s  •  %s" % [
			String(context.get("activity", "Activity")),
			String(context.get("topic", "Topic"))
		]


func _focus_default() -> void:
	var selected := String(context.get("difficulty", DIFFICULTIES[0]))
	var button: Button = difficulty_buttons.get(selected, difficulty_buttons[DIFFICULTIES[0]])
	button.grab_focus()


func _go_back() -> void:
	requested.emit("play_topic", context.duplicate(true))


func _go_next() -> void:
	if next_button.disabled:
		return
	requested.emit("camera_check", context.duplicate(true))
