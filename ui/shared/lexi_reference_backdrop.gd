extends Control

# KilosGrammar's original drawing of a subtle, repeating four-point-star
# backdrop inspired by the colors in the user's Lexispell UI reference.
# No image or shader assets are copied from the reference game.

const SAGE := Color("#57826C")
const STAR := Color("#74AB8E")
const CELL_SIZE := 94.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SAGE)
	var rows: int = int(ceil(size.y / CELL_SIZE)) + 1
	var columns: int = int(ceil(size.x / CELL_SIZE)) + 1
	for row in range(rows):
		for column in range(columns):
			var center := Vector2(
				float(column) * CELL_SIZE + (24.0 if row % 2 == 0 else 70.0),
				float(row) * CELL_SIZE + 22.0
			)
			var outer := 11.0 if (column + row) % 4 != 0 else 14.0
			var points := PackedVector2Array([
				center + Vector2(0, -outer),
				center + Vector2(4, -4),
				center + Vector2(outer, 0),
				center + Vector2(4, 4),
				center + Vector2(0, outer),
				center + Vector2(-4, 4),
				center + Vector2(-outer, 0),
				center + Vector2(-4, -4)
			])
			draw_colored_polygon(points, Color(STAR.r, STAR.g, STAR.b, 0.7))
