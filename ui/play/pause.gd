extends Control

signal requested(target: String, payload: Dictionary)

const UI = preload("res://ui/play/play_ui.gd")

var context: Dictionary = {}
var summary_label: Label
var resume_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var card := get_node_or_null("PauseCard") as Control
	if card != null:
		_bind_scene_nodes(card)
	else:
		_build_ui()

func _bind_scene_nodes(card: Control) -> void:
	summary_label = card.get_node_or_null("SummaryLabel") as Label
	resume_button = card.get_node_or_null("ResumeButton") as Button
	if resume_button:
		resume_button.pressed.connect(_resume)
		resume_button.call_deferred("grab_focus")
	var restart := card.get_node_or_null("RestartButton") as Button
	if restart:
		restart.pressed.connect(_restart)
	var change := card.get_node_or_null("ChangeSetupButton") as Button
	if change:
		change.pressed.connect(_change_setup)
	var results := card.get_node_or_null("ResultsButton") as Button
	if results:
		results.pressed.connect(_results)
	var main_menu := card.get_node_or_null("MainMenuButton") as Button
	if main_menu:
		main_menu.pressed.connect(_main_menu)
	_refresh_summary()

func _build_ui() -> void:
	var clean_backdrop := ColorRect.new()
	clean_backdrop.color = Color("087e75")
	clean_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clean_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clean_backdrop)
	var background := TextureRect.new()
	background.name = "SetupArtworkBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = load("res://ui/redesign/assets/student/setup_main_panel.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var dimmer := ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.08, 0.07, 0.12, 0.58)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560, 450 if get_viewport_rect().size.y <= 550.0 else 560)
	card.add_theme_stylebox_override("panel", UI.make_panel(Color(UI.INK, 0.97), 30))
	center.add_child(card)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 6 if get_viewport_rect().size.y <= 550.0 else 14)
	card.add_child(content)

	var title := UI.make_label("PAUSED", 48, UI.CREAM)
	title.custom_minimum_size.y = 44 if get_viewport_rect().size.y <= 550.0 else 66
	content.add_child(title)

	summary_label = UI.make_body_label("", 18, Color(UI.CREAM, 0.78))
	summary_label.custom_minimum_size.y = 42 if get_viewport_rect().size.y <= 550.0 else 68
	content.add_child(summary_label)

	resume_button = _add_action(content, "RESUME", UI.GREEN, "_resume")
	_add_action(content, "RESTART ROUND", UI.YELLOW, "_restart")
	_add_action(content, "CHANGE SETUP", UI.BLUE, "_change_setup")
	_add_action(content, "VIEW RESULTS", UI.PURPLE, "_results")
	_add_action(content, "MAIN MENU", UI.RED, "_main_menu")
	_refresh_summary()
	call_deferred("_focus_resume")


func set_context(new_context: Dictionary) -> void:
	for key in new_context:
		context[key] = new_context[key]
	_refresh_summary()


func _add_action(parent: VBoxContainer, text_value: String, color: Color, method_name: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(420, 46 if get_viewport_rect().size.y <= 550.0 else 54)
	UI.style_button(button, color, 20)
	button.pressed.connect(Callable(self, method_name))
	parent.add_child(button)
	return button


func _refresh_summary() -> void:
	if summary_label == null:
		return
	summary_label.text = "%s\n%s • %s   |   Score %d" % [
		String(context.get("activity", "Activity")),
		String(context.get("topic", "Topic")),
		String(context.get("difficulty", "Difficulty")),
		int(context.get("score", 0))
	]


func _focus_resume() -> void:
	if resume_button:
		resume_button.grab_focus()


func _resume() -> void:
	requested.emit("gameplay", context.duplicate(true))


func _restart() -> void:
	# Restart means a fresh minigame, not Resume of the paused instance.
	requested.emit("restart", context.duplicate(true))


func _change_setup() -> void:
	requested.emit("last_play", context.duplicate(true))


func _results() -> void:
	requested.emit("results", context.duplicate(true))


func _main_menu() -> void:
	requested.emit("main", context.duplicate(true))
