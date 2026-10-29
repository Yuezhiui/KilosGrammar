extends Control

signal requested(target: String, payload: Dictionary)

## The pause artwork, button hitboxes and individual PNGs are completely
## editor-authored in pause.tscn. Only responsive stage scaling, signal
## wiring and immutable navigation payloads are handled by this script.
const DESIGN_SIZE := Vector2(1280.0, 720.0)
const BUTTON_TARGETS := {
	"ResumeButton": "gameplay",
	"RestartButton": "restart",
	"ChangeSetupButton": "last_play",
	"ResultsButton": "results",
	"MainMenuButton": "main",
}

var context: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var stage := get_node_or_null("PauseStage") as Control
	var card := get_node_or_null("PauseStage/PauseCard") as Control
	if stage == null or card == null:
		push_error("Pause redesign: editor-authored PauseStage/PauseCard missing.")
		return
	for button_name in BUTTON_TARGETS:
		var button := card.get_node_or_null(button_name) as Button
		if button == null:
			push_error("Pause redesign missing native Button: " + button_name)
			continue
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_request.bind(BUTTON_TARGETS[button_name]))
	# Existing GlobalButtonHover autoload owns the single hover/press tween.
	# Existing router ButtonSounds owns the single hover/focus/click audio.
	# Never add local tweens, AudioStreamPlayers, or duplicate watchers here.
	resized.connect(_fit_stage)
	_fit_stage()
	var resume := card.get_node_or_null("ResumeButton") as Button
	if resume != null:
		resume.call_deferred("grab_focus")


func _fit_stage() -> void:
	var stage := get_node_or_null("PauseStage") as Control
	if stage == null:
		return
	var target := size
	if target.x <= 0.0 or target.y <= 0.0:
		target = get_viewport_rect().size
	var ratio := maxf(0.01, minf(target.x / DESIGN_SIZE.x, target.y / DESIGN_SIZE.y))
	stage.scale = Vector2.ONE * ratio
	stage.position = (target - DESIGN_SIZE * ratio) * 0.5


func set_context(new_context: Dictionary) -> void:
	context = new_context.duplicate(true)


func _request(route: String) -> void:
	requested.emit(route, context.duplicate(true))


# Retain existing named API for caller-side compatibility.
func _resume() -> void: _request("gameplay")
func _restart() -> void: _request("restart")
func _change_setup() -> void: _request("last_play")
func _results() -> void: _request("results")
func _main_menu() -> void: _request("main")
