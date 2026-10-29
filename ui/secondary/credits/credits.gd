extends Control

signal requested(target: String, payload: Dictionary)

# The updated Credits scene is entirely authored in Godot's 2D editor.
# Only the parent canvas is scaled for the current window: no script resets
# individual banner/board/button or label positions set in the Inspector.
const DESIGN_SIZE := Vector2(1280.0, 720.0)

var _context: Dictionary = {}


func _ready() -> void:
	%BackButton.pressed.connect(_request_main)
	# The HOME artwork must fill its editor-draggable Button. Godot's open
	# editor can resave child offsets when resizing; a stray child offset can
	# move the PNG to the opposite corner while leaving the hitbox behind.
	# Only normalize this child to the parent: BackButton itself remains
	# freely movable/resizable from the Credits .tscn.
	var home_art := %BackButton.get_node_or_null("Artwork") as TextureRect
	if home_art != null:
		home_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := $CreditsStage/CreditsScroll as ScrollContainer
	scroll.focus_mode = Control.FOCUS_ALL
	resized.connect(_adapt_layout)
	call_deferred("_adapt_layout")


func _adapt_layout() -> void:
	var stage := $CreditsStage as Control
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	stage.scale = Vector2.ONE * factor
	stage.position = (size - DESIGN_SIZE * factor) * 0.5


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)


func _request_main() -> void:
	requested.emit("main", _context.duplicate(true))
