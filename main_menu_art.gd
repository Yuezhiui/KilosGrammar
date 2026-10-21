@tool
extends Control

var animation_time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	animation_time += delta
	queue_redraw()


func _draw() -> void:
	var canvas_size: Vector2 = size
	draw_rect(Rect2(Vector2.ZERO, canvas_size), Color("00886bff"), true)
	_draw_cloud_accents(canvas_size)
	_draw_motion_paths(canvas_size)

	var star_color := Color("ffffffff")
	var warm_star_color := Color("ffe06aff")
	var book_color := Color("ffffffff")
	var dot_color := Color("47d6b7aa")
	var stars := [
		# Top band
		Vector3(0.08, 0.13, 25.0), Vector3(0.18, 0.16, 12.0),
		Vector3(0.28, 0.11, 15.0), Vector3(0.40, 0.12, 22.0),
		Vector3(0.50, 0.16, 13.0), Vector3(0.60, 0.10, 16.0),
		Vector3(0.73, 0.11, 18.0), Vector3(0.82, 0.17, 13.0),
		Vector3(0.90, 0.14, 23.0), Vector3(0.96, 0.34, 16.0),

		# Middle area - smaller stars around the title/menu instead of one empty gap.
		Vector3(0.13, 0.34, 12.0), Vector3(0.24, 0.42, 15.0),
		Vector3(0.34, 0.35, 11.0), Vector3(0.42, 0.47, 16.0),
		Vector3(0.51, 0.39, 12.0), Vector3(0.59, 0.49, 15.0),
		Vector3(0.67, 0.36, 11.0), Vector3(0.76, 0.46, 17.0),
		Vector3(0.86, 0.38, 12.0), Vector3(0.92, 0.53, 14.0),

		# Lower band
		Vector3(0.05, 0.66, 17.0), Vector3(0.16, 0.73, 11.0),
		Vector3(0.27, 0.67, 14.0), Vector3(0.38, 0.77, 12.0),
		Vector3(0.49, 0.69, 15.0), Vector3(0.62, 0.78, 13.0),
		Vector3(0.77, 0.72, 19.0), Vector3(0.86, 0.65, 12.0),
		Vector3(0.93, 0.78, 24.0), Vector3(0.10, 0.88, 12.0),
		Vector3(0.31, 0.89, 15.0), Vector3(0.47, 0.86, 11.0),
		Vector3(0.62, 0.91, 18.0), Vector3(0.79, 0.88, 13.0),
		Vector3(0.90, 0.90, 16.0)
	]
	for index in range(stars.size()):
		var item: Vector3 = stars[index]
		# Each star breathes from tiny -> full -> tiny with an offset phase,
		# so the background twinkles instead of pulsing all at once.
		var pulse := (sin(animation_time * 2.1 + float(index) * 0.83) + 1.0) * 0.5
		pulse = smoothstep(0.0, 1.0, pulse)
		var scale_value := lerpf(0.16, 1.0, pulse)
		var alpha := lerpf(0.28, 1.0, pulse)
		var base_color: Color = warm_star_color if index % 7 == 2 else star_color
		var animated_color := Color(base_color.r, base_color.g, base_color.b, base_color.a * alpha)
		_draw_soft_star(Vector2(canvas_size.x * item.x, canvas_size.y * item.y), item.z * scale_value, animated_color)

	var dots := [Vector2(0.04, 0.29), Vector2(0.22, 0.13), Vector2(0.51, 0.12), Vector2(0.96, 0.31), Vector2(0.08, 0.82), Vector2(0.54, 0.88)]
	for p: Vector2 in dots:
		var center := Vector2(canvas_size.x * p.x, canvas_size.y * p.y)
		draw_arc(center, 5.0, 0.0, TAU, 24, dot_color, 2.4, true)

	var books := [
		[Vector2(canvas_size.x * 0.07, canvas_size.y * 0.53), 0.72, -0.22, 0.0],
		[Vector2(canvas_size.x * 0.63, canvas_size.y * 0.10), 0.62, -0.16, 1.3],
		[Vector2(canvas_size.x * 0.91, canvas_size.y * 0.10), 0.70, 0.22, 2.5],
		[Vector2(canvas_size.x * 0.19, canvas_size.y * 0.88), 0.64, 0.20, 3.7],
		[Vector2(canvas_size.x * 0.90, canvas_size.y * 0.88), 0.68, 0.22, 4.9]
	]
	for book_data: Array in books:
		var center: Vector2 = book_data[0]
		var scale_value: float = book_data[1]
		var base_rotation: float = book_data[2]
		var phase: float = book_data[3]
		var float_y := sin(animation_time * 0.72 + phase) * 2.2
		var wobble := sin(animation_time * 0.48 + phase) * 0.025
		_draw_book(center + Vector2(0, float_y), scale_value, base_rotation + wobble, book_color)


func _draw_cloud_accents(canvas_size: Vector2) -> void:
	# Soft scalloped masses around the frame add the same depth as the reference
	# without turning the background into a static image. They stay behind every
	# falling word, logo tile and menu control.
	var cloud_a := Color("0a9b7b")
	var cloud_b := Color("10a987")
	var cloud_shadow := Color("067761")

	_draw_cloud_cluster(Vector2(-38.0, 116.0), [72.0, 92.0, 66.0], cloud_a)
	_draw_cloud_cluster(Vector2(canvas_size.x + 34.0, 282.0), [86.0, 110.0, 76.0], cloud_b)

	var floor_y := canvas_size.y + 20.0
	draw_rect(Rect2(0.0, canvas_size.y * 0.94, canvas_size.x, canvas_size.y * 0.12), cloud_shadow, true)
	_draw_cloud_cluster(Vector2(66.0, floor_y), [104.0, 82.0, 114.0, 88.0], cloud_b)
	_draw_cloud_cluster(Vector2(canvas_size.x * 0.24, floor_y + 8.0), [72.0, 92.0, 68.0], cloud_a)
	_draw_cloud_cluster(Vector2(canvas_size.x * 0.76, floor_y + 10.0), [80.0, 104.0, 76.0], cloud_a)
	_draw_cloud_cluster(Vector2(canvas_size.x - 72.0, floor_y), [118.0, 86.0, 108.0], cloud_b)


func _draw_cloud_cluster(origin: Vector2, radii: Array, color: Color) -> void:
	var cursor_x := origin.x
	for index in range(radii.size()):
		var radius: float = float(radii[index])
		var y_offset := sin(float(index) * 1.73) * radius * 0.18
		draw_circle(Vector2(cursor_x, origin.y + y_offset), radius, color)
		cursor_x += radius * 1.05


func _draw_motion_paths(canvas_size: Vector2) -> void:
	var path_color := Color("35cdb3a8")
	_draw_dashed_curve(
		Vector2(-25.0, canvas_size.y * 0.34),
		Vector2(canvas_size.x * 0.08, canvas_size.y * 0.19),
		Vector2(canvas_size.x * 0.23, canvas_size.y * 0.24),
		path_color
	)
	_draw_dashed_curve(
		Vector2(canvas_size.x * 0.72, canvas_size.y * 0.79),
		Vector2(canvas_size.x * 0.88, canvas_size.y * 0.65),
		Vector2(canvas_size.x + 28.0, canvas_size.y * 0.78),
		path_color
	)


func _draw_dashed_curve(start: Vector2, control: Vector2, finish: Vector2, color: Color) -> void:
	var previous := start
	for index in range(1, 31):
		var t := float(index) / 30.0
		var inverse := 1.0 - t
		var point := start * inverse * inverse + control * 2.0 * inverse * t + finish * t * t
		if index % 2 == 0:
			draw_line(previous, point, color, 3.5, true)
		previous = point


func _draw_soft_star(center: Vector2, radius: float, color: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius * 0.34, -radius * 0.34),
		center + Vector2(radius, 0),
		center + Vector2(radius * 0.34, radius * 0.34),
		center + Vector2(0, radius),
		center + Vector2(-radius * 0.34, radius * 0.34),
		center + Vector2(-radius, 0),
		center + Vector2(-radius * 0.34, -radius * 0.34)
	])
	draw_colored_polygon(points, color)


func _draw_book(center: Vector2, scale_value: float, rotation_value: float, color: Color) -> void:
	# Chunkier open-book silhouette with filled translucent pages, a center
	# spine, and small inner page marks. It stays decorative rather than
	# competing with the title.
	var left := PackedVector2Array([
		Vector2(-48, -29), Vector2(-30, -25), Vector2(-8, -17),
		Vector2(-3, 31), Vector2(-22, 23), Vector2(-43, 17)
	])
	var right := PackedVector2Array([
		Vector2(-3, -17), Vector2(19, -27), Vector2(42, -31),
		Vector2(47, 15), Vector2(24, 21), Vector2(1, 31)
	])
	for i in range(left.size()):
		left[i] = center + left[i].rotated(rotation_value) * scale_value
	for i in range(right.size()):
		right[i] = center + right[i].rotated(rotation_value) * scale_value
	var fill := Color(color.r, color.g, color.b, color.a * 0.16)
	draw_colored_polygon(left, fill)
	draw_colored_polygon(right, fill)
	draw_polyline(left, color, 5.0 * scale_value, true)
	draw_polyline(right, color, 5.0 * scale_value, true)

	var spine_top := center + Vector2(-5, -16).rotated(rotation_value) * scale_value
	var spine_bottom := center + Vector2(-1, 31).rotated(rotation_value) * scale_value
	draw_line(spine_top, spine_bottom, color, 4.0 * scale_value, true)

	for y in [-8.0, 2.0, 12.0]:
		var left_a := center + Vector2(-34, y).rotated(rotation_value) * scale_value
		var left_b := center + Vector2(-13, y + 5.0).rotated(rotation_value) * scale_value
		var right_a := center + Vector2(10, y + 3.0).rotated(rotation_value) * scale_value
		var right_b := center + Vector2(31, y - 2.0).rotated(rotation_value) * scale_value
		draw_line(left_a, left_b, Color(color.r, color.g, color.b, color.a * 0.55), 2.0 * scale_value, true)
		draw_line(right_a, right_b, Color(color.r, color.g, color.b, color.a * 0.55), 2.0 * scale_value, true)
