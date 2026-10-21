## Attach to a screen-level Control and point stage_path at the logical 1280x720
## art/control canvas. Optional grid/scroller adapt smaller windows.
extends Control

const WIDGETS = preload("res://ui/redesign/shared/cartoon_widgets.gd")

@export var stage_path: NodePath
@export var reference_size := Vector2(1280.0, 720.0)
@export var compact_width := 900.0
@export var responsive_grid_path: NodePath
@export var scroll_path: NodePath
@export var compact_guidance_path: NodePath

var compact := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var stage := get_node_or_null(stage_path) as Control
	if stage:
		WIDGETS.fit_stage(stage, size, reference_size)
	var now_compact := size.x < compact_width
	var grid := get_node_or_null(responsive_grid_path) as GridContainer
	if grid:
		WIDGETS.columns(grid, size.x, compact_width)
	var guidance := get_node_or_null(compact_guidance_path) as Control
	if guidance:
		guidance.visible = now_compact
	compact = now_compact


func reveal_focused(control: Control) -> void:
	var scroller := get_node_or_null(scroll_path) as ScrollContainer
	if scroller and control and scroller.is_ancestor_of(control):
		scroller.ensure_control_visible(control)
