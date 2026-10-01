@tool
extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var s: Vector2 = size
	if s.x <= 0.0 or s.y <= 0.0:
		return

	draw_colored_polygon(PackedVector2Array([
		Vector2(5, 3),
		Vector2(s.x * 0.68, 3),
		Vector2(4, s.y * 0.63)
	]), Color(1.0, 0.98, 0.90, 0.16))

	draw_colored_polygon(PackedVector2Array([
		Vector2(s.x, s.y),
		Vector2(s.x * 0.48, s.y),
		Vector2(s.x, s.y * 0.58)
	]), Color(0.18, 0.14, 0.22, 0.10))

	draw_circle(Vector2(s.x * 0.20, s.y * 0.18), minf(s.x, s.y) * 0.075, Color(1.0, 0.98, 0.90, 0.17))
	draw_arc(Vector2(s.x * 0.24, s.y * 0.24), minf(s.x, s.y) * 0.16, PI, PI * 1.55, 18, Color(1.0, 0.98, 0.90, 0.22), 3.0, true)
