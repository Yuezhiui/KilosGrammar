extends Control

signal requested(target: String, payload: Dictionary)
signal camera_model_prewarm_requested

const ACTIVITIES := ["Catch the Word", "Human Plane", "Balloon Popping"]
const SELECTED_ART_TINT := Color(1.09, 1.09, 1.09, 1.0)
const GAME_STYLES := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const GAME_MODES := ["Seconds", "Lives", "Quiz", "Activity"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const DEFAULT_PREVIEW := preload("res://Components/Game Chooser/select game default.png")
const PREVIEW_TEXTURES := {
	"Catch the Word": preload("res://Components/Game Chooser/catch the word.png"),
	"Human Plane": preload("res://Components/Game Chooser/human plane.png"),
	"Balloon Popping": preload("res://Components/Game Chooser/balloon popping.png")
}
const NEXT_ACTIVE_TEXTURE := preload("res://Components/Game Chooser/next student setup if already choose.png")
const ARTBOARD_SIZE := Vector2(1280.0, 720.0)

var context: Dictionary = {}
var activity_buttons: Dictionary = {}
var next_button: Button
var selected_preview: TextureRect
var next_artwork: TextureRect
var next_inactive_artwork: Texture2D
var artboard: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Every artwork and button remains scene-authored and editable in Godot.
	# Only the whole 1280x720 artboard scales to fit other 16:9 displays.
	artboard = get_node("LayoutMargins") as Control
	resized.connect(_fit_artboard)
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
	selected_preview = get_node_or_null("LayoutMargins/Content/GameRow/GameDetail/DetailContent/SelectedPreview") as TextureRect
	var back_button := get_node_or_null("LayoutMargins/Content/Footer/BackButton") as Button
	next_button = get_node_or_null("LayoutMargins/Content/Footer/NextButton") as Button
	if next_button:
		next_artwork = next_button.get_node_or_null("Artwork") as TextureRect
	if back_button == null or next_button == null or selected_preview == null or next_artwork == null:
		push_error("Game Selection has missing required editor-authored controls.")
		return
	# The editor-authored disabled atlas trims transparent source padding,
	# matching the green button's visible footprint without stretching either PNG.
	next_inactive_artwork = next_artwork.texture
	back_button.pressed.connect(_go_back)
	next_button.pressed.connect(_go_next)
	_fit_artboard()
	_refresh_selection()
	call_deferred("_focus_default")

func _fit_artboard() -> void:
	if not is_instance_valid(artboard):
		return
	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size
	var factor := minf(viewport_size.x / ARTBOARD_SIZE.x, viewport_size.y / ARTBOARD_SIZE.y)
	if factor <= 0.0:
		return
	artboard.scale = Vector2.ONE * factor
	artboard.position = (viewport_size - ARTBOARD_SIZE * factor) * 0.5


func set_context(new_context: Dictionary) -> void:
	for key in new_context:
		context[key] = new_context[key]
	_refresh_selection()


func _select_activity(activity: String) -> void:
	if not ACTIVITIES.has(activity):
		return
	context["activity"] = activity
	_refresh_selection()
	# Preload only the YOLO model as soon as a teacher selects camera play.
	# The parent owns the worker and camera consent; this scene never opens it.
	camera_model_prewarm_requested.emit()
	# Preserve keyboard/controller activation without adding a colored border:
	# the selected PNG tint and preview communicate the choice.
	var chosen_button := activity_buttons.get(activity) as Button
	if is_instance_valid(chosen_button):
		chosen_button.grab_focus()


func _refresh_selection() -> void:
	if next_button == null:
		return
	var selected := String(context.get("activity", ""))
	var has_selection := ACTIVITIES.has(selected)
	for activity in activity_buttons:
		var button: Button = activity_buttons[activity]
		var chosen: bool = activity == selected
		button.set_pressed_no_signal(chosen)
		# No outline/corner overlay, including while focused: preview and
		# slightly brighter original PNG are the selection indicator.
		var artwork := button.get_node_or_null("Artwork") as TextureRect
		if artwork:
			artwork.modulate = SELECTED_ART_TINT if chosen else Color.WHITE
	next_button.disabled = not has_selection
	next_artwork.texture = NEXT_ACTIVE_TEXTURE if has_selection else next_inactive_artwork
	selected_preview.texture = PREVIEW_TEXTURES[selected] if has_selection else DEFAULT_PREVIEW


func _focus_default() -> void:
	var selected := String(context.get("activity", ""))
	# Keyboard focus is not a chosen game. Selection happens only on activation.
	var button: Button = activity_buttons.get(selected, activity_buttons["Catch the Word"])
	if is_instance_valid(button):
		button.grab_focus()


func _go_back() -> void:
	requested.emit("tutorial_home" if bool(context.get("guided_tutorial", false)) else "student_setup", context.duplicate(true))


func _go_next() -> void:
	if not ACTIVITIES.has(String(context.get("activity", ""))) or next_button == null or next_button.disabled:
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
