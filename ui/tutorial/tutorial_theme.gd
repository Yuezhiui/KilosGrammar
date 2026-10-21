## Editable native controls over the project's supplied classroom illustration.
## Both background art and input hitboxes scale to the same 1120x640 stage.
extends RefCounted

const FONT: Font = preload("res://assets/fonts/TitanOne-Regular.ttf")
const BOARD := Vector2(1120.0, 640.0)
const CLASSROOM := "res://ui/redesign/assets/tutorial/bg_classroom.png"
const TUTORIAL_ART := "res://ui/redesign/assets/tutorial/"
const CREAM := Color("#FFF0CA")
const PAPER := Color("#FFF4D8")
const INK := Color("#423C54")
const TEAL := Color("#0D8174")
const GREEN := Color("#128A6E")
const BLUE := Color("#4488C9")
const YELLOW := Color("#F6B744")
const PURPLE := Color("#8161B5")
const RED := Color("#D85B68")

static func prepare(root: Control, heading: String, description: String, badge: String) -> Control:
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var background := TextureRect.new()
	background.name = "ClassroomArtwork"
	background.texture = load(CLASSROOM) as Texture2D if ResourceLoader.exists(CLASSROOM) else null
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var stage := Control.new()
	stage.name = "TutorialStage"
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stage)
	stage.size = BOARD
	panel(stage, Rect2(28, 21, 1064, 598), PAPER, 30, 0.95)
	# A slim accent rail gives the six screens a consistent reference-style header.
	panel(stage, Rect2(52, 40, 8, 95), TEAL, 4, 1.0)
	label(stage, heading, Rect2(79, 43, 890, 54), 33, INK, HORIZONTAL_ALIGNMENT_LEFT)
	label(stage, description, Rect2(80, 103, 942, 49), 17, Color("#675A60"), HORIZONTAL_ALIGNMENT_LEFT)
	if not badge.is_empty():
		panel(stage, Rect2(806, 42, 246, 36), TEAL, 16)
		label(stage, badge, Rect2(821, 46, 216, 27), 13, Color.WHITE)
	root.resized.connect(func() -> void: fit(root, stage))
	fit(root, stage)
	return stage

static func fit(root: Control, stage: Control, design_size: Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(stage):
		return
	var target_size := design_size
	if target_size == Vector2.ZERO:
		target_size = stage.size if stage.size.x > 100.0 and stage.size.y > 100.0 else BOARD
	var viewport := root.size
	if viewport.x < 1.0 or viewport.y < 1.0:
		viewport = root.get_viewport_rect().size
	if viewport.x < 1.0 or viewport.y < 1.0:
		viewport = Vector2(1280.0, 720.0)
	var ratio := maxf(0.01, minf(viewport.x / target_size.x, viewport.y / target_size.y))
	stage.set_anchors_preset(Control.PRESET_TOP_LEFT)
	stage.scale = Vector2.ONE * ratio
	stage.position = (viewport - target_size * ratio) * 0.5

static func panel(parent: Control, rect: Rect2, color: Color, radius: int = 19, opacity: float = 1.0) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, opacity)
	style.set_corner_radius_all(radius)
	style.border_color = Color("#71614F", 0.15)
	style.set_border_width_all(2)
	style.shadow_color = Color("#2B2936", 0.13)
	style.shadow_size = 4
	style.shadow_offset = Vector2(2, 4)
	node.add_theme_stylebox_override("panel", style)
	parent.add_child(node)
	return node

static func label(parent: Control, value: String, rect: Rect2, font_size: int = 18, color: Color = INK, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var node := Label.new()
	node.text = value
	node.position = rect.position
	node.size = rect.size
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.horizontal_alignment = alignment
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.clip_text = false
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func button(parent: Control, value: String, rect: Rect2, color: Color = GREEN, font_size: int = 18) -> Button:
	var node := Button.new()
	node.text = value
	node.position = rect.position
	node.size = rect.size
	node.focus_mode = Control.FOCUS_ALL
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", font_size)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		node.add_theme_color_override(state, Color.WHITE if color != YELLOW else INK)
	node.add_theme_stylebox_override("normal", _button_box(color))
	node.add_theme_stylebox_override("hover", _button_box(color.lightened(0.10)))
	node.add_theme_stylebox_override("pressed", _button_box(color.darkened(0.12)))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("#FFF8CF")
	focus.set_border_width_all(4)
	focus.set_corner_radius_all(17)
	node.add_theme_stylebox_override("focus", focus)
	parent.add_child(node)
	return node

static func artwork_button(parent: Control, value: String, rect: Rect2, file: String, fallback: Color) -> Button:
	if not ResourceLoader.exists(file):
		return button(parent, value, rect, fallback)
	var texture := load(file) as Texture2D
	if texture == null:
		return button(parent, value, rect, fallback)
	# Baked art must keep its actual proportions. StyleBoxTexture stretches
	# letters and icons to the button hitbox, so paint an independent
	# aspect-preserving TextureRect beneath a transparent native Button.
	var art := TextureRect.new()
	art.name = "ButtonArtwork_" + value.replace(" ", "_")
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = rect.position
	art.size = rect.size
	parent.add_child(art)
	var node := button(parent, value, rect, fallback)
	for state in ["normal", "hover", "pressed", "disabled"]:
		node.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		node.add_theme_color_override(state, Color.TRANSPARENT)
	node.mouse_entered.connect(func() -> void: art.modulate = Color(1.10, 1.10, 1.10))
	node.mouse_exited.connect(func() -> void: art.modulate = Color.WHITE)
	node.button_down.connect(func() -> void: art.modulate = Color(0.88, 0.88, 0.88))
	node.button_up.connect(func() -> void: art.modulate = Color.WHITE)
	return node

static func _button_box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(17)
	style.shadow_color = Color("#333044", 0.22)
	style.shadow_size = 4
	style.shadow_offset = Vector2(2, 4)
	return style

static func icon(parent: Control, filename: String, rect: Rect2) -> TextureRect:
	var node := TextureRect.new()
	node.name = "ReferenceIcon"
	if ResourceLoader.exists(filename):
		node.texture = load(filename) as Texture2D
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node
