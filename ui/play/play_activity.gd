extends Control

signal requested(target: String, payload: Dictionary)

const UI = preload("res://ui/play/play_ui.gd")
const ACTIVITIES := ["Catch the Word", "Human Plane", "Balloon Popping"]
const ACTIVITY_COPY := {
	"Catch the Word": "Catch falling words with a smoothly moving basket. Match the grammar target while avoiding incorrect words.",
	"Human Plane": "Glide an airplane smoothly between three answer gates. Fly through one of the correct grammar words at the collision line.",
	"Balloon Popping": "Aim at word balloons, launch a projectile, and pop a matching grammar answer. Wrong balloons cost a life."
}
const ACTIVITY_HINTS := {
	"Catch the Word": "WORD MATCHING",
	"Human Plane": "THREE-LANE CHOICE",
	"Balloon Popping": "TARGET SELECTION"
}
const ACTIVITY_COLORS := [UI.GREEN, UI.BLUE, UI.PURPLE]
const GAME_STYLES := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const GAME_MODES := ["Seconds", "Lives", "Quiz", "Activity"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]

var context: Dictionary = {}
var activity_buttons: Dictionary = {}
var next_button: Button
var keyboard_button: Button
var selected_title: Label
var selected_badge: Label
var selected_copy: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var clean_backdrop := ColorRect.new()
	clean_backdrop.color = Color("087e75")
	clean_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clean_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clean_backdrop)
	var backdrop := TextureRect.new()
	backdrop.name = "SetupArtworkBackground"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.texture = load("res://ui/redesign/assets/student/setup_main_panel.png")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var column := UI.make_compact_screen_column(self)
	UI.add_compact_title(column, "Play • Choose Game", "Choose an Activity", "Select your playable 2D game, then continue to the camera preview.")

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)

	var list_card := PanelContainer.new()
	list_card.custom_minimum_size.x = 430
	list_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_card.add_theme_stylebox_override("panel", UI.make_panel(Color(UI.INK, 0.84), 24))
	body.add_child(list_card)

	var list_content := VBoxContainer.new()
	list_content.add_theme_constant_override("separation", 10)
	list_card.add_child(list_content)

	var list_label := UI.make_label("GAME OPTIONS", 18, UI.CREAM)
	list_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	list_label.custom_minimum_size.y = 28
	list_content.add_child(list_label)

	var group := ButtonGroup.new()
	for index in range(ACTIVITIES.size()):
		var activity: String = ACTIVITIES[index]
		var button := Button.new()
		button.text = activity.to_upper()
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		UI.style_compact_selection_button(button, ACTIVITY_COLORS[index], 20)
		button.pressed.connect(_select_activity.bind(activity))
		list_content.add_child(button)
		activity_buttons[activity] = button

	var detail_card := PanelContainer.new()
	detail_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_card.add_theme_stylebox_override("panel", UI.make_panel(Color(UI.INK, 0.92), 24))
	body.add_child(detail_card)

	var detail_content := VBoxContainer.new()
	detail_content.alignment = BoxContainer.ALIGNMENT_CENTER
	detail_content.add_theme_constant_override("separation", 12)
	detail_card.add_child(detail_content)

	selected_badge = UI.make_label("KEYBOARD PLAYABLE", 15, UI.YELLOW)
	selected_badge.custom_minimum_size.y = 24
	detail_content.add_child(selected_badge)

	selected_title = UI.make_label("SELECT A GAME", 34, UI.CREAM)
	selected_title.custom_minimum_size.y = 52
	detail_content.add_child(selected_title)

	selected_copy = UI.make_body_label("Choose one of the game concepts on the left.", 18, Color(UI.CREAM, 0.88))
	selected_copy.custom_minimum_size = Vector2(0, 92)
	detail_content.add_child(selected_copy)

	var demo_note := UI.make_body_label("Keyboard controls work today; live camera/YOLO tracking and score saving come later.", 15, Color(UI.CREAM, 0.73))
	demo_note.custom_minimum_size.y = 42
	detail_content.add_child(demo_note)

	var footer: Array[Button] = UI.add_compact_footer(column, "BACK", "NEXT: TOPIC")
	var back_button: Button = footer[0]
	next_button = footer[1]
	keyboard_button = Button.new()
	keyboard_button.name = "PlayKeyboardButton"
	keyboard_button.text = "PLAY KEYBOARD NOW"
	keyboard_button.custom_minimum_size = Vector2(244, 48)
	UI.style_button(keyboard_button, UI.GREEN, 16)
	var footer_row := next_button.get_parent() as BoxContainer
	footer_row.add_child(keyboard_button)
	footer_row.move_child(keyboard_button, next_button.get_index())
	back_button.pressed.connect(_go_back)
	next_button.pressed.connect(_go_next)
	keyboard_button.pressed.connect(_play_keyboard_now)
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
	keyboard_button.disabled = not ACTIVITIES.has(selected) or not _has_complete_teacher_setup()
	next_button.text = "NEXT: AUTO CALIBRATION" if _has_complete_teacher_setup() else "NEXT: TOPIC"
	if selected_title and ACTIVITIES.has(selected):
		selected_title.text = selected.to_upper()
		selected_badge.text = "%s • PLAYABLE" % String(ACTIVITY_HINTS[selected])
		selected_copy.text = String(ACTIVITY_COPY[selected])
	elif selected_title:
		selected_title.text = "SELECT A GAME"
		selected_badge.text = "KEYBOARD PLAYABLE"
		selected_copy.text = "Choose one of the game concepts on the left."


func _focus_default() -> void:
	var selected := String(context.get("activity", ACTIVITIES[0]))
	var button: Button = activity_buttons.get(selected, activity_buttons[ACTIVITIES[0]])
	button.grab_focus()


func _go_back() -> void:
	requested.emit("student_setup", context.duplicate(true))


func _go_next() -> void:
	if next_button.disabled:
		return
	var game_style := _canonical_choice(String(context.get("game_style", "")), GAME_STYLES)
	var game_mode := _canonical_choice(String(context.get("game_mode", "")), GAME_MODES)
	var difficulty := _canonical_choice(String(context.get("difficulty", "")), DIFFICULTIES)
	if not game_style.is_empty() and not game_mode.is_empty() and not difficulty.is_empty():
		var payload := context.duplicate(true)
		payload["game_style"] = game_style
		payload["topic"] = game_style
		payload["game_mode"] = game_mode
		payload["difficulty"] = difficulty
		payload["keyboard_mode"] = false
		payload["camera_requested"] = true
		# The camera-based Play path starts YOLO in the calibration screen;
		# students no longer need to click CHECK CAMERA or CAPTURE each zone.
		requested.emit("calibration", payload)
		return
	requested.emit("play_topic", context.duplicate(true))


func _play_keyboard_now() -> void:
	if keyboard_button.disabled:
		return
	var payload := context.duplicate(true)
	payload["game_style"] = _canonical_choice(String(context.get("game_style", "")), GAME_STYLES)
	payload["topic"] = String(payload["game_style"])
	payload["game_mode"] = _canonical_choice(String(context.get("game_mode", "")), GAME_MODES)
	payload["difficulty"] = _canonical_choice(String(context.get("difficulty", "")), DIFFICULTIES)
	payload["keyboard_mode"] = true
	payload["demo_mode"] = true
	requested.emit("ready", payload)


func _has_complete_teacher_setup() -> bool:
	return (
		not _canonical_choice(String(context.get("game_style", "")), GAME_STYLES).is_empty()
		and not _canonical_choice(String(context.get("game_mode", "")), GAME_MODES).is_empty()
		and not _canonical_choice(String(context.get("difficulty", "")), DIFFICULTIES).is_empty()
	)


func _canonical_choice(value: String, choices: Array) -> String:
	var normalized := value.strip_edges().to_lower()
	for choice in choices:
		var candidate := String(choice)
		if candidate.to_lower() == normalized:
			return candidate
	if choices == GAME_MODES:
		match normalized:
			"seconds", "sec", "60s", "quiz":
				return "Seconds"
			"lives", "life", "3 lives", "activity":
				return "Lives"
	return ""
