extends Control

var target_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	queue_redraw()

func _exit_tree() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _process(delta: float) -> void:
	target_position = get_viewport().get_mouse_position() - Vector2(13, 9)
	global_position = global_position.lerp(target_position, min(1.0, delta * 26.0))
	queue_redraw()

func _draw() -> void:
	var dark: Color = Color("#3f3855")
	var cream: Color = Color("#f7e6bd")
	draw_colored_polygon(PackedVector2Array([
		Vector2(8, 14), Vector2(10, 2), Vector2(16, 8),
		Vector2(23, 2), Vector2(25, 15)
	]), dark)
	draw_circle(Vector2(17, 18), 11.0, dark)
	draw_circle(Vector2(13, 17), 2.0, cream)
	draw_circle(Vector2(21, 17), 2.0, cream)
	draw_rect(Rect2(12, 27, 10, 37), dark, true)
	draw_circle(Vector2(17, 65), 5.0, dark)
	draw_line(Vector2(12, 40), Vector2(5, 50), dark, 4.0)
	draw_line(Vector2(22, 40), Vector2(29, 50), dark, 4.0)
