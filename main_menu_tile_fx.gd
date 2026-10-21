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

	# Control children are drawn over the PanelContainer, so the StyleBoxFlat's
	# rounded corners do not clip them. Clip just the translucent corner fills
	# to the tile face; clipping the parent itself would cut off its drop shadow.
	var face: PackedVector2Array = _tile_face_polygon()
	_draw_face_polygon(PackedVector2Array([
		Vector2(5, 3),
		Vector2(s.x * 0.68, 3),
		Vector2(4, s.y * 0.63)
	]), Color(1.0, 0.98, 0.90, 0.16), face)

	_draw_face_polygon(PackedVector2Array([
		Vector2(s.x, s.y),
		Vector2(s.x * 0.48, s.y),
		Vector2(s.x, s.y * 0.58)
	]), Color(0.18, 0.14, 0.22, 0.10), face)

	draw_circle(Vector2(s.x * 0.20, s.y * 0.18), minf(s.x, s.y) * 0.075, Color(1.0, 0.98, 0.90, 0.17))
	draw_arc(Vector2(s.x * 0.24, s.y * 0.24), minf(s.x, s.y) * 0.16, PI, PI * 1.55, 18, Color(1.0, 0.98, 0.90, 0.22), 3.0, true)


func _draw_face_polygon(points: PackedVector2Array, color: Color, face: PackedVector2Array) -> void:
	for intersection: PackedVector2Array in Geometry2D.intersect_polygons(points, face):
		if intersection.size() >= 3:
			draw_colored_polygon(intersection, color)


func _tile_face_polygon() -> PackedVector2Array:
	var panel: PanelContainer = get_parent() as PanelContainer
	if panel == null:
		return PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if style == null:
		return PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])

	# FX is laid out inside the panel's content margins. Convert the panel's
	# border-inset shape into FX-local coordinates for both logo and falling tiles.
	var border: int = maxi(maxi(style.border_width_left, style.border_width_top), maxi(style.border_width_right, style.border_width_bottom))
	var inset: float = maxf(2.0, float(border) + 1.0)
	var top_left: Vector2 = Vector2(inset, inset) - position
	var bottom_right: Vector2 = panel.size - Vector2(inset, inset) - position
	var max_radius: float = maxf(0.0, minf(bottom_right.x - top_left.x, bottom_right.y - top_left.y) * 0.5)
	var tl: float = minf(maxf(0.0, float(style.corner_radius_top_left) - inset), max_radius)
	var tr: float = minf(maxf(0.0, float(style.corner_radius_top_right) - inset), max_radius)
	var br: float = minf(maxf(0.0, float(style.corner_radius_bottom_right) - inset), max_radius)
	var bl: float = minf(maxf(0.0, float(style.corner_radius_bottom_left) - inset), max_radius)

	var outline := PackedVector2Array()
	outline.append_array(_corner(Vector2(top_left.x + tl, top_left.y + tl), tl, PI))
	outline.append_array(_corner(Vector2(bottom_right.x - tr, top_left.y + tr), tr, -PI * 0.5))
	outline.append_array(_corner(Vector2(bottom_right.x - br, bottom_right.y - br), br, 0.0))
	outline.append_array(_corner(Vector2(top_left.x + bl, bottom_right.y - bl), bl, PI * 0.5))
	return outline


func _corner(center: Vector2, radius: float, from_angle: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(9):
		var angle: float = from_angle + PI * 0.5 * float(index) / 8.0
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points
