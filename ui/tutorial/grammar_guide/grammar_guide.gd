extends Control

signal requested(target: String, payload: Dictionary)

# Every visual, text label, source PNG, position, and card belongs to the
# editor-authored grammar_guide.tscn. Do not generate cards at runtime.
const ART := preload("res://ui/tutorial/tutorial_theme.gd")
const DESIGN_SIZE := Vector2(1280.0, 720.0)

var context: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var stage := get_node_or_null("TutorialStage") as Control
	if stage == null:
		push_error("Explore Grammar requires an editor-authored TutorialStage.")
		return
	var scroll := stage.get_node_or_null("GrammarCardScroll") as ScrollContainer
	var grid := stage.get_node_or_null("GrammarCardScroll/GridContainer") as GridContainer
	var back := stage.get_node_or_null("BackButton") as Button
	if scroll == null or grid == null or grid.get_child_count() != 5:
		push_error("Explore Grammar requires exactly five editable topic cards in its ScrollContainer.")
		return
	if back == null:
		push_error("Explore Grammar requires its editor-authored BackButton.")
		return
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.pressed.connect(_request.bind("tutorial_home", {}))
	var artwork := back.get_node_or_null("Artwork") as TextureRect
	if artwork != null:
		back.mouse_entered.connect(func() -> void: _update_back_visual(back, artwork))
		back.mouse_exited.connect(func() -> void: _update_back_visual(back, artwork))
		back.focus_entered.connect(func() -> void: _update_back_visual(back, artwork))
		back.focus_exited.connect(func() -> void: _update_back_visual(back, artwork))
		back.button_down.connect(func() -> void: artwork.modulate = Color(0.88, 0.88, 0.88))
		back.button_up.connect(func() -> void: _update_back_visual(back, artwork))
	# The router's ButtonSoundWiring already applies the title screen's hover
	# and click SFX to all descendant Buttons. Never add a second audio source.
	resized.connect(_fit_stage)
	_fit_stage()
	back.call_deferred("grab_focus")


func _update_back_visual(button: BaseButton, artwork: TextureRect) -> void:
	if is_instance_valid(button) and is_instance_valid(artwork):
		artwork.modulate = Color(1.08, 1.08, 1.08) if button.is_hovered() or button.has_focus() else Color.WHITE


func _fit_stage() -> void:
	ART.fit(self, $TutorialStage, DESIGN_SIZE)


func set_context(value: Dictionary) -> void:
	context = value.duplicate(true)


func _request(target: String, payload: Dictionary) -> void:
	requested.emit(target, payload.duplicate(true))
