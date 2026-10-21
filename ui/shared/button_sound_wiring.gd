extends Node

# One owner for button feedback across the title and all routed screens.
# Watching descendants also catches buttons created later (tabs, dialogs, HUD).
const HOVER_SOUND: AudioStream = preload("res://assets/audio/lexispell_intro/button_hover.wav")
const CLICK_SOUND: AudioStream = preload("res://assets/audio/lexispell_intro/button_click.wav")
const EFFECTS_BUS := "KilosSFX"
const HOVER_DB := -4.0
const CLICK_DB := -1.0
const HOVER_POINTER_ORIGIN := "kilos_button_sfx_pointer_origin"
var _navigation_frame := -1
var _last_hover_frame := -1


func _input(event: InputEvent) -> void:
	# Only focus changes resulting from keyboard/controller navigation have a
	# focus-hover sound. Programmatic grab_focus() and mouse-click focus stay
	# silent so an activation never creates a second sound.
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		for action in ["ui_focus_next", "ui_focus_prev", "ui_up", "ui_down", "ui_left", "ui_right"]:
			if event.is_action_pressed(action):
				_navigation_frame = Engine.get_process_frames()
				return
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		_navigation_frame = -1


func watch(root: Node) -> void:
	if root != null:
		_watch_branch(root)


func reset_hover_origin(root: Node) -> void:
	# A newly revealed screen can appear beneath a stationary mouse. That
	# is a layout change, not an intentional pointer hover.
	if root == null:
		return
	if root is BaseButton:
		(root as BaseButton).set_meta(HOVER_POINTER_ORIGIN, _cursor_at(root as BaseButton))
	for child in root.get_children():
		reset_hover_origin(child)


func _watch_branch(node: Node) -> void:
	if not node.child_entered_tree.is_connected(_watch_branch):
		node.child_entered_tree.connect(_watch_branch)
	if node is CanvasItem:
		var canvas := node as CanvasItem
		var visibility_callback := _on_visibility_changed.bind(canvas)
		if not canvas.visibility_changed.is_connected(visibility_callback):
			canvas.visibility_changed.connect(visibility_callback)
	if node is BaseButton:
		_watch_button(node as BaseButton)
	for child in node.get_children():
		_watch_branch(child)


func _on_visibility_changed(node: CanvasItem) -> void:
	# When a hidden tab/page reappears below a stationary cursor, discard the
	# previous pointer location before Godot synthesizes mouse_entered events.
	if node.is_visible_in_tree():
		reset_hover_origin(node)


func _watch_button(button: BaseButton) -> void:
	var hover_callback := _on_hover.bind(button)
	var down_callback := _on_down.bind(button)
	var focus_callback := _on_focus.bind(button)
	if not button.mouse_entered.is_connected(hover_callback):
		button.mouse_entered.connect(hover_callback)
		button.set_meta(HOVER_POINTER_ORIGIN, _cursor_at(button))
	if not button.button_down.is_connected(down_callback):
		button.button_down.connect(down_callback)
	if not button.focus_entered.is_connected(focus_callback):
		button.focus_entered.connect(focus_callback)


func _on_hover(button: BaseButton) -> void:
	if not _is_usable(button) or button.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	if _cursor_at(button).distance_squared_to(button.get_meta(HOVER_POINTER_ORIGIN, _cursor_at(button))) < 0.25:
		return
	_play_hover()


func _on_focus(button: BaseButton) -> void:
	if _navigation_frame == Engine.get_process_frames() and _is_usable(button):
		_play_hover()


func _play_hover() -> void:
	# A button can receive a mouse_entered and a keyboard focus_entered
	# in one UI frame. Let only one hover chime through for that transition.
	var frame := Engine.get_process_frames()
	if _last_hover_frame == frame:
		return
	_last_hover_frame = frame
	_play_sound(HOVER_SOUND, HOVER_DB)


func _on_down(button: BaseButton) -> void:
	# button_down is emitted for keyboard and mouse activation and precedes
	# pressed/navigation. Listening here also avoids a second toggle sound.
	if _is_usable(button):
		_play_sound(CLICK_SOUND, CLICK_DB)


func _is_usable(button: BaseButton) -> bool:
	if not is_instance_valid(button) or not button.is_inside_tree() or not button.is_visible_in_tree() or button.disabled:
		return false
	# Main intro fades controls to alpha zero while positioning them.
	var current: Node = button
	while current is CanvasItem:
		var canvas := current as CanvasItem
		if canvas.modulate.a <= 0.01 or canvas.self_modulate.a <= 0.01:
			return false
		current = current.get_parent()
	return true


func _cursor_at(_button: BaseButton) -> Vector2:
	# child_entered_tree can run before the new child has a viewport. Our
	# persistent router is already mounted in the main scene at that point.
	return get_viewport().get_mouse_position()


func _play_sound(stream: AudioStream, volume_db: float) -> void:
	var player := AudioStreamPlayer.new()
	player.name = "ButtonSound"
	player.stream = stream
	player.bus = EFFECTS_BUS
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
