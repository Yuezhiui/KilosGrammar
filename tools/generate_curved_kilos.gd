extends SceneTree

const OUTPUT_PATH := "res://Components/Main Panel/Generated/kilos_curved.png"
const CANVAS_SIZE := Vector2i(840, 320)
const WORD := "KILOS"
const FONT_SIZE := 224
const TITLE_FONT := preload("res://assets/fonts/TitanOne-Regular.ttf")

const FILL := Color("#4b445f")
const CREAM := Color("#ffe9bd")
const OUTER_EDGE := Color("#493f5d")
const DROP_SHADOW := Color("#725f78")

const DOT_SPACING := 11
const DOT_START_Y := 154
const ARCH_DROP := 27


func _initialize() -> void:
	_generate.call_deferred()


func _generate() -> void:
	var final_viewport := _make_viewport("CurvedKilosFinal")
	var mask_viewport := _make_viewport("CurvedKilosMask")

	_add_word(final_viewport, DROP_SHADOW, DROP_SHADOW, 33, Vector2(11, 16))
	_add_word(final_viewport, OUTER_EDGE, OUTER_EDGE, 31, Vector2.ZERO)
	_add_word(final_viewport, FILL, CREAM, 19, Vector2.ZERO)
	_add_word(mask_viewport, Color.WHITE, Color(0, 0, 0, 0), 0, Vector2.ZERO)

	await process_frame
	await process_frame

	var final_image := final_viewport.get_texture().get_image()
	var mask_image := mask_viewport.get_texture().get_image()
	if final_image == null or mask_image == null or final_image.is_empty() or mask_image.is_empty():
		push_error("KILOS render failed")
		quit(1)
		return

	final_image = _warp_arch(final_image)
	mask_image = _warp_arch(mask_image)
	_paint_halftone(final_image, mask_image)

	var destination_dir := ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir())
	var make_error := DirAccess.make_dir_recursive_absolute(destination_dir)
	if make_error != OK:
		push_error("Could not create image output folder: %s" % destination_dir)
		quit(1)
		return
	var err := final_image.save_png(OUTPUT_PATH)
	if err != OK:
		push_error("Could not save KILOS texture: %s" % error_string(err))
		quit(1)
		return

	print("Generated %s" % OUTPUT_PATH)
	quit()


func _make_viewport(viewport_name: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.size = CANVAS_SIZE
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	return viewport


func _add_word(viewport: SubViewport, fill_color: Color, outline_color: Color, outline_size: int, offset: Vector2) -> void:
	var label := Label.new()
	label.text = WORD
	label.position = Vector2(0, -6) + offset
	label.size = Vector2(CANVAS_SIZE.x, 286)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", TITLE_FONT)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", fill_color)
	label.add_theme_color_override("font_outline_color", outline_color)
	label.add_theme_constant_override("outline_size", outline_size)
	viewport.add_child(label)


func _warp_arch(source: Image) -> Image:
	var warped := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	warped.fill(Color(0, 0, 0, 0))
	var center := float(CANVAS_SIZE.x - 1) * 0.5
	for x in range(CANVAS_SIZE.x):
		var normalized := absf((float(x) - center) / center)
		var y_offset := int(round(float(ARCH_DROP) * pow(normalized, 1.7)))
		var copy_height := CANVAS_SIZE.y - y_offset
		warped.blit_rect(source, Rect2i(x, 0, 1, copy_height), Vector2i(x, y_offset))
	return warped


func _paint_halftone(image: Image, mask: Image) -> void:
	var row := 0
	var bottom := CANVAS_SIZE.y - 22
	for y in range(DOT_START_Y, bottom, DOT_SPACING):
		var x_offset := DOT_SPACING / 2 if row % 2 == 1 else 0
		var progress := clampf(float(y - DOT_START_Y) / float(bottom - DOT_START_Y), 0.0, 1.0)
		var radius := lerpf(1.0, 5.4, progress)
		for x in range(8 + x_offset, CANVAS_SIZE.x - 8, DOT_SPACING):
			if mask.get_pixel(x, y).a >= 0.52:
				_paint_dot(image, mask, x, y, radius)
		row += 1


func _paint_dot(image: Image, mask: Image, center_x: int, center_y: int, radius: float) -> void:
	var r := int(ceil(radius))
	for py in range(center_y - r, center_y + r + 1):
		if py < 0 or py >= CANVAS_SIZE.y:
			continue
		for px in range(center_x - r, center_x + r + 1):
			if px < 0 or px >= CANVAS_SIZE.x:
				continue
			var delta := Vector2(float(px - center_x), float(py - center_y))
			if delta.length_squared() > radius * radius:
				continue
			if mask.get_pixel(px, py).a >= 0.35:
				image.set_pixel(px, py, CREAM)
