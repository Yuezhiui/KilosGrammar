extends Control

signal requested(target: String, payload: Dictionary)

const ART := preload("res://ui/tutorial/tutorial_theme.gd")
const DESIGN_SIZE := Vector2(1280.0, 720.0)

var context: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	# All art, labels, buttons, sizes and local positions live in the .tscn.
	# Only the stage's whole-screen letterboxing is computed at runtime.
	var stage := get_node_or_null("TutorialStage") as Control
	if stage == null:
		push_error("Tutorial Home requires its editor-authored TutorialStage.")
		return

	var start := stage.get_node_or_null("StartButton") as Button
	var grammar := stage.get_node_or_null("GrammarButton") as Button
	var back := stage.get_node_or_null("BackButton") as Button
	_bind_button(start, func() -> void:
		_request("play_activity", {
			"entry_source": "tutorial",
			"guided_tutorial": true,
			"fresh_setup": true
		})
	)
	_bind_button(grammar, func() -> void: _request("grammar_guide", {}))
	_bind_button(back, func() -> void: _request("main", {}))

	resized.connect(_fit_stage)
	_fit_stage()
	if start != null:
		start.call_deferred("grab_focus")


func _bind_button(button: Button, action: Callable) -> void:
	if button == null:
		push_error("Tutorial Home is missing an editor-authored navigation button.")
		return
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	# Artwork travels with the native button when users move it in the editor.
	var artwork := button.get_node_or_null("Artwork") as TextureRect
	if artwork == null:
		push_error("Tutorial Home button %s is missing its Artwork child." % button.name)
		return
	button.mouse_entered.connect(func() -> void: artwork.modulate = Color(1.10, 1.10, 1.10))
	button.mouse_exited.connect(func() -> void: artwork.modulate = Color.WHITE)
	button.focus_entered.connect(func() -> void: artwork.modulate = Color(1.10, 1.10, 1.10))
	button.focus_exited.connect(func() -> void: artwork.modulate = Color.WHITE)
	button.button_down.connect(func() -> void: artwork.modulate = Color(0.86, 0.86, 0.86))
	button.button_up.connect(func() -> void:
		artwork.modulate = Color(1.10, 1.10, 1.10) if button.has_focus() or button.is_hovered() else Color.WHITE
	)


func _fit_stage() -> void:
	ART.fit(self, $TutorialStage, DESIGN_SIZE)


func set_context(value: Dictionary) -> void:
	context = value.duplicate(true)


func _request(target: String, payload: Dictionary) -> void:
	requested.emit(target, payload)
