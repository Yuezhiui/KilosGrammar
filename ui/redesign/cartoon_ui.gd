## Shared image-backed presentation helpers for the KilosGrammar UI redesign.
## Never replaces native Godot Buttons/LineEdits: the textures only draw them.
extends RefCounted

const STAGE_SIZE := Vector2(1280.0, 720.0)


static func load_art(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func image(parent: Node, art_path: String, rect: Rect2, name: String = "Art") -> TextureRect:
	var texture := load_art(art_path)
	if texture == null:
		return null
	var sprite := TextureRect.new()
	sprite.name = name
	sprite.texture = texture
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.position = rect.position
	sprite.size = rect.size
	parent.add_child(sprite)
	return sprite


static func background(parent: Node, art_path: String, name: String = "ArtBackground") -> TextureRect:
	var sprite := image(parent, art_path, Rect2(Vector2.ZERO, STAGE_SIZE), name)
	if sprite == null:
		return null
	sprite.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sprite


static func style_box(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	# These PNGs are complete painted buttons, including the center icon/text.
	# Nine-slicing would stretch lettering and add intrinsic margins that push
	# the third menu button below the viewport. Scale their complete pixels.
	style.texture_margin_left = 0.0
	style.texture_margin_right = 0.0
	style.texture_margin_top = 0.0
	style.texture_margin_bottom = 0.0
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return style


static func art_button(button: Button, normal_path: String, hover_path: String = "", pressed_path: String = "", baked_label: bool = true) -> bool:
	var normal := load_art(normal_path)
	if normal == null:
		return false
	var hover := load_art(hover_path)
	var pressed := load_art(pressed_path)
	var normal_style := style_box(normal)
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", style_box(hover if hover != null else normal))
	button.add_theme_stylebox_override("pressed", style_box(pressed if pressed != null else normal))
	button.add_theme_stylebox_override("disabled", normal_style)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.set_border_width_all(3)
	focus.border_color = Color("#FFF7B2A0")
	focus.set_corner_radius_all(41)
	button.add_theme_stylebox_override("focus", focus)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	if baked_label:
		# Preserve the original Button.text for navigation tests and assistive tools,
		# but avoid drawing native text on top of labels baked into supplied PNGs.
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
			button.add_theme_color_override(state, Color.TRANSPARENT)
	return true


static func fit_stage(stage: Control, viewport_size: Vector2) -> void:
	# The input controls share the same coordinate system as their art. This
	# scales their hitboxes with artwork while preserving each texture's ratio.
	var factor := minf(viewport_size.x / STAGE_SIZE.x, viewport_size.y / STAGE_SIZE.y)
	stage.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	stage.position = (viewport_size - STAGE_SIZE * factor) * 0.5
	stage.size = STAGE_SIZE
	stage.scale = Vector2.ONE * factor
