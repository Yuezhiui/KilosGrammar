## Reusable image-backed Godot controls for all KilosGrammar redesigned screens.
## Art always comes from supplied PNGs; logic, hit areas, focus and text inputs
## remain native Godot controls. No screenshots or flattened buttons at runtime.
extends RefCounted

const ART_BASE := "res://ui/redesign/assets/"
const ASPECT_FACE = preload("res://ui/redesign/shared/aspect_button_face.gd")
const STAGE_DESIGN_SIZE := Vector2(1280.0, 720.0)
const CATEGORIES := ["main", "student", "shared", "game_over", "tutorial", "settings"]


static func art_path(category: String, sprite: String) -> String:
	if not category in CATEGORIES or sprite.is_empty() or sprite.contains("/") or sprite.contains("\\"):
		return ""
	return "%s%s/%s.png" % [ART_BASE, category, sprite]


static func art(category: String, sprite: String) -> Texture2D:
	var path := art_path(category, sprite)
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("Missing UI artwork: " + path)
		return null
	return load(path) as Texture2D


static func image(parent: Node, category: String, sprite: String, name: String = "Art") -> TextureRect:
	var tex := art(category, sprite)
	if tex == null:
		return null
	var view := TextureRect.new()
	view.name = name
	view.texture = tex
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.custom_minimum_size = tex.get_size()
	parent.add_child(view)
	return view


static func background(parent: Node, category: String, sprite: String) -> TextureRect:
	var view := image(parent, category, sprite, "ArtBackground")
	if view == null:
		return null
	view.custom_minimum_size = Vector2.ZERO
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	return view


static func skin_button(
	button: Button,
	category: String,
	sprite: String,
	hover: String = "",
	pressed: String = "",
	disabled: String = "",
	label_is_baked: bool = true
) -> bool:
	var normal_texture := art(category, sprite)
	if normal_texture == null:
		return false
	var hover_texture := art(category, hover) if not hover.is_empty() else null
	var pressed_texture := art(category, pressed) if not pressed.is_empty() else null
	var disabled_texture := art(category, disabled) if not disabled.is_empty() else null
	# StyleBoxTexture stretches X/Y independently when a Button's rectangle
	# differs from its sprite ratio (e.g. 533x198 art in a 348x78 slot).
	# An aspect-preserving TextureRect child avoids text/icon distortion.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var face = button.get_node_or_null("ArtButtonFace")
	if face == null:
		face = ASPECT_FACE.new()
		face.name = "ArtButtonFace"
		button.add_child(face)
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.configure(button, normal_texture, hover_texture, pressed_texture, disabled_texture)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	if label_is_baked:
		# Leave Button.text and tooltip usable for keyboard access. The exact
		# matching wording is already painted in the reference PNG.
		for key in ["font_color", "font_hover_color", "font_pressed_color",
				"font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
			button.add_theme_color_override(key, Color.TRANSPARENT)
	return true


static func button(
	parent: Node,
	category: String,
	sprite: String,
	caption: String,
	hover: String = "",
	pressed: String = "",
	disabled: String = ""
) -> Button:
	var tex := art(category, sprite)
	if tex == null:
		return null
	var result := Button.new()
	result.name = caption.replace(" ", "") + "Button"
	result.text = caption
	result.tooltip_text = caption
	# Source images are high-DPI exports, often 600-1300px wide. Native
	# minimums must be smaller so the controls fit narrow columns safely.
	var natural_size := tex.get_size()
	var factor := minf(1.0, 360.0 / maxf(natural_size.x, 1.0))
	result.custom_minimum_size = natural_size * factor
	result.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(result)
	skin_button(result, category, sprite, hover, pressed, disabled)
	return result


static func card(parent: Node, category: String, sprite: String, name: String = "Card") -> TextureRect:
	var panel := image(parent, category, sprite, name)
	if panel:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return panel


static func atlas_texture(source: Texture2D, rect: Rect2i) -> AtlasTexture:
	# For real source sheets copied into the project later, this provides a
	# native AtlasTexture without first rasterizing a new bitmap.
	if source == null or rect.size.x <= 0 or rect.size.y <= 0:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(rect)
	return atlas


static func fit_stage(stage: Control, viewport_size: Vector2,
		reference: Vector2 = STAGE_DESIGN_SIZE) -> float:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0 or reference.x <= 0.0 or reference.y <= 0.0:
		return 1.0
	var scale_factor := minf(viewport_size.x / reference.x, viewport_size.y / reference.y)
	stage.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	stage.size = reference
	stage.scale = Vector2.ONE * scale_factor
	stage.position = (viewport_size - reference * scale_factor) * 0.5
	return scale_factor


static func columns(grid: GridContainer, available_width: float,
		compact_breakpoint: float = 900.0, normal_columns: int = 2) -> void:
	# A GridContainer plus a parent ScrollContainer keeps compact screens fully
	# navigable instead of clipping the lower card.
	grid.columns = 1 if available_width < compact_breakpoint else maxi(normal_columns, 1)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func scrolling_root(parent: Control, name: String = "ScrollableContent") -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name
	parent.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return scroll
