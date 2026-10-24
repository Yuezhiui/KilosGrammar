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
const GAME_STYLES := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const GAME_MODES := ["Seconds", "Lives", "Quiz", "Activity"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]

var context: Dictionary = {}
var activity_buttons: Dictionary = {}
var next_button: Button
var selected_title: Label
var selected_badge: Label
var selected_copy: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Every visible control and texture is authored in play_activity.tscn.
	# Repositioning or replacing them in the editor never affects navigation.
	var button_nodes := {
		"Catch the Word": "LayoutMargins/Content/GameRow/GameOptions/GameOptionsContent/CatchWordButton",
		"Human Plane": "LayoutMargins/Content/GameRow/GameOptions/GameOptionsContent/HumanPlaneButton",
		"Balloon Popping": "LayoutMargins/Content/GameRow/GameOptions/GameOptionsContent/BalloonPoppingButton"
	}
	var group := ButtonGroup.new()
	for activity in button_nodes:
		var button := get_node_or_null(button_nodes[activity]) as Button
		if button == null:
			push_error("Game Selection is missing its editor-authored button for: " + activity)
			return
		button.button_group = group
		button.pressed.connect(_select_activity.bind(activity))
		activity_buttons[activity] = button
	selected_badge = get_node_or_null("LayoutMargins/Content/GameRow/GameDetail/DetailContent/SelectedBadge") as Label
	selected_title = get_node_or_null("LayoutMargins/Content/GameRow/GameDetail/DetailContent/SelectedTitle") as Label
	selected_copy = get_node_or_null("LayoutMargins/Content/GameRow/GameDetail/DetailContent/SelectedDescription") as Label
	var back_button := get_node_or_null("LayoutMargins/Content/Footer/BackButton") as Button
	next_button = get_node_or_null("LayoutMargins/Content/Footer/NextButton") as Button
	if back_button == null or next_button == null or selected_badge == null or selected_title == null or selected_copy == null:
		push_error("Game Selection has missing required editor-authored controls.")
		return
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
	if bool(context.get("guided_tutorial", false)):
		next_button.text = "NEXT: STUDENT SETUP"
	else:
		next_button.text = "NEXT: AUTO CALIBRATION" if _has_complete_teacher_setup() else "NEXT: TOPIC"
	if selected_title and ACTIVITIES.has(selected):
		selected_title.text = selected.to_upper()
		selected_badge.text = "%s • PLAYABLE" % String(ACTIVITY_HINTS[selected])
		selected_copy.text = String(ACTIVITY_COPY[selected])
	elif selected_title:
		selected_title.text = "SELECT A GAME"
		selected_badge.text = "CAMERA PLAY"
		selected_copy.text = "Choose one of the game concepts on the left."


func _focus_default() -> void:
	var selected := String(context.get("activity", ACTIVITIES[0]))
	var button: Button = activity_buttons.get(selected, activity_buttons[ACTIVITIES[0]])
	button.grab_focus()


func _go_back() -> void:
	requested.emit("tutorial_home" if bool(context.get("guided_tutorial", false)) else "student_setup", context.duplicate(true))


func _go_next() -> void:
	if next_button.disabled:
		return
	if bool(context.get("guided_tutorial", false)):
		var guided_payload := context.duplicate(true)
		guided_payload["entry_source"] = "tutorial"
		guided_payload["student_setup_prefill"] = false
		requested.emit("student_setup", guided_payload)
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
