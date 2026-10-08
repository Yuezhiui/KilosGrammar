extends Control

signal requested(target: String, payload: Dictionary)

const UI = preload("res://ui/play/play_ui.gd")
const ACTIVITIES := ["Catch the Word", "Human Plane", "Balloon Popping"]
const ACTIVITY_COPY := {
	"Catch the Word": "Step toward the word that matches the grammar prompt.",
	"Human Plane": "Move left, center, or right to answer each challenge.",
	"Balloon Popping": "Reach toward the correct grammar balloon before time runs out."
}
const ACTIVITY_COLORS := [UI.GREEN, UI.BLUE, UI.PURPLE]

var context: Dictionary = {}
var activity_buttons: Dictionary = {}
var next_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := UI.make_screen_column(self)
	UI.add_title(column, "Play • Step 1 of 3", "Choose an Activity", "Pick the movement game you want to play.")

	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UI.make_panel(Color(UI.INK, 0.78), 26))
	column.add_child(card)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	card.add_child(grid)

	var group := ButtonGroup.new()
	for index in range(ACTIVITIES.size()):
		var activity: String = ACTIVITIES[index]
		var button := Button.new()
		button.text = "%s\n\n%s" % [activity.to_upper(), ACTIVITY_COPY[activity]]
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		UI.style_selection_button(button, ACTIVITY_COLORS[index])
		button.pressed.connect(_select_activity.bind(activity))
		grid.add_child(button)
		activity_buttons[activity] = button

	var footer: Array[Button] = UI.add_footer(column, "MAIN MENU", "NEXT: TOPIC")
	var back_button: Button = footer[0]
	next_button = footer[1]
	back_button.pressed.connect(_go_back)
	next_button.pressed.connect(_go_next)
	_refresh_selection()
	call_deferred("_focus_default")


func set_context(new_context: Dictionary) -> void:
	for key in new_context:
		context[key] = new_context[key]
	_refresh_selection()


func _select_activity(activity: String) -> void:
	context["activity"] = activity
	_refresh_selection()


func _refresh_selection() -> void:
	if next_button == null:
		return
	var selected := String(context.get("activity", ""))
	for activity in activity_buttons:
		var button: Button = activity_buttons[activity]
		button.set_pressed_no_signal(activity == selected)
	next_button.disabled = not ACTIVITIES.has(selected)


func _focus_default() -> void:
	var selected := String(context.get("activity", ACTIVITIES[0]))
	var button: Button = activity_buttons.get(selected, activity_buttons[ACTIVITIES[0]])
	button.grab_focus()


func _go_back() -> void:
	requested.emit("main", context.duplicate(true))


func _go_next() -> void:
	if next_button.disabled:
		return
	requested.emit("play_topic", context.duplicate(true))
