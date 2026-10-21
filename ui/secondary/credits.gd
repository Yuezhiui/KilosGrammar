extends Control

signal requested(target: String, payload: Dictionary)

var _context: Dictionary = {}


func _ready() -> void:
	%BackButton.pressed.connect(_request_main)
	# ScrollContainer defaults to FOCUS_NONE: allow Tab/keyboard users to
	# reach and scroll the preserved credits list without using a mouse.
	var credits_scroll := get_node_or_null("CreditsPanel/PanelContent/Body/CreditsScroll") as ScrollContainer
	if credits_scroll != null:
		credits_scroll.focus_mode = Control.FOCUS_ALL
	%BackButton.grab_focus()
	resized.connect(_adapt_layout)
	call_deferred("_adapt_layout")


func _adapt_layout() -> void:
	var panel := get_node_or_null("CreditsPanel") as Control
	var stack := get_node_or_null("CreditsPanel/PanelContent/Body/CreditsScroll/ScrollCenter/CreditsStack") as Control
	if panel == null or stack == null:
		return
	var compact := size.x < 1050.0
	panel.anchor_left = 0.035 if compact else 0.15
	panel.anchor_right = 0.965 if compact else 0.85
	panel.anchor_top = 0.025 if compact else 0.08
	panel.anchor_bottom = 0.95 if compact else 0.88
	stack.custom_minimum_size.x = minf(610.0, maxf(0.0, size.x - 140.0))
	var home := get_node_or_null("BackButton") as Button
	if home != null:
		# Keep the entire home button inside the compact viewport, rather
		# than allowing its bottom edge to fall past 500px-height windows.
		home.anchor_top = 0.87 if size.y <= 560.0 else 0.905
		home.anchor_bottom = home.anchor_top
		home.offset_top = 0.0
		home.offset_bottom = 50.0


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)


func _request_main() -> void:
	requested.emit("main", _context.duplicate(true))
