## Draws source-art button graphics without stretching hand-painted words,
## icons or rounded corners. The parent remains a native Godot Button.
extends TextureRect

var button: Button
var normal: Texture2D
var hover: Texture2D
var pressed: Texture2D
var disabled_art: Texture2D
var _focus_outline: Panel


func configure(source_button: Button, normal_tex: Texture2D, hover_tex: Texture2D,
		pressed_tex: Texture2D, disabled_tex: Texture2D) -> void:
	button = source_button
	normal = normal_tex
	hover = hover_tex if hover_tex != null else normal
	pressed = pressed_tex if pressed_tex != null else normal
	disabled_art = disabled_tex if disabled_tex != null else normal
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	custom_minimum_size = Vector2.ZERO
	texture = normal
	if _focus_outline == null:
		_focus_outline = Panel.new()
		_focus_outline.name = "ArtFocusOutline"
		_focus_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var focus_style := StyleBoxFlat.new()
		focus_style.bg_color = Color.TRANSPARENT
		focus_style.border_color = Color("#FFF3AA")
		focus_style.set_border_width_all(3)
		focus_style.set_corner_radius_all(15)
		_focus_outline.add_theme_stylebox_override("panel", focus_style)
		add_child(_focus_outline)
		_focus_outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(true)
	_update_face()


func _process(_delta: float) -> void:
	# Godot does not emit a Button.disabled_changed signal. Checking this
	# lightweight state also handles programmatic pressed/focus transitions.
	_update_face()


func _update_face() -> void:
	if not is_instance_valid(button):
		set_process(false)
		return
	var next_texture := normal
	if button.disabled:
		next_texture = disabled_art
	elif button.is_pressed():
		next_texture = pressed
	elif button.is_hovered():
		next_texture = hover
	if texture != next_texture:
		texture = next_texture
	_focus_outline.visible = button.has_focus()
