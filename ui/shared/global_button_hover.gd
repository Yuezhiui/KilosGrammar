extends Node

# Main Menu's elastic button motion, shared by ALL routed .tscn screens and
# buttons created at runtime. Only the animation lives here; Main Menu's
# existing ButtonSounds node remains the single owner of hover/click audio.
# Neither a scene's authored layout nor its pressed/changed signals are edited.
const BOUND := &"kg_global_hover_bound"
const HOME_SCALE := &"kg_global_hover_scale"
const HOME_ROTATION := &"kg_global_hover_rotation"
const HOME_Z_INDEX := &"kg_global_hover_z"
const HOME_PIVOT := &"kg_global_hover_pivot"
const ACTIVE_TWEEN := &"kg_global_hover_tween"
const ACTIVE := &"kg_global_hover_active"


func _ready() -> void:
	# Pause's Resume/Main buttons must still animate while gameplay's
	# SceneTree.paused flag is true. No gameplay logic is processed here.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_node_added)
	_register_existing(get_tree().root)


func _register_existing(branch: Node) -> void:
	if branch is BaseButton:
		_node_added(branch)
	for child in branch.get_children():
		_register_existing(child)


func _node_added(node: Node) -> void:
	if node is BaseButton:
		# Main Menu and Settings finish configuring their own buttons in _ready.
		# Deferred binding allows them to retain the original local animation
		# while every other authored and runtime-created button gains feedback.
		call_deferred("_bind_button", weakref(node))


func _bind_button(reference: WeakRef) -> void:
	var button := reference.get_ref() as BaseButton
	if not is_instance_valid(button) or not button.is_inside_tree() or button.has_meta(BOUND):
		return
	if _uses_screen_specific_animation(button):
		return
	button.set_meta(BOUND, true)
	button.set_meta(HOME_SCALE, button.scale)
	button.set_meta(HOME_ROTATION, button.rotation)
	button.set_meta(HOME_Z_INDEX, button.z_index)
	button.set_meta(HOME_PIVOT, button.pivot_offset)
	button.set_meta(ACTIVE, false)
	button.mouse_entered.connect(_on_hover.bind(button))
	button.mouse_exited.connect(_on_exit.bind(button))
	button.button_down.connect(_on_press.bind(button))
	button.button_up.connect(_on_release.bind(button))
	button.resized.connect(_refresh_pivot.bind(button))
	button.visibility_changed.connect(_on_visibility_changed.bind(button))
	button.tree_exiting.connect(_on_tree_exiting.bind(button))
	_refresh_pivot(button)


func _uses_screen_specific_animation(button: BaseButton) -> bool:
	# These callbacks are already installed by their scene scripts. A second
	# tween on the same properties would cause jitter and oversized controls.
	if button.has_meta("home_rotation") or button.has_meta("settings_home_rotation"):
		return true
	# Main Menu's six buttons are authored under MainLayer and receive their
	# animation from main_menu.gd. A scene can also be opened independently.
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor.name == "MainLayer":
			return true
		ancestor = ancestor.get_parent()
	return false


func _refresh_pivot(button: BaseButton) -> void:
	# A changed pivot moves a pre-scaled Control even while idle. Never alter
	# authored pivot/position in the resting state: this preserves responsive
	# hitboxes in 1280, 1600 and 1920-wide scenes.
	if is_instance_valid(button) and bool(button.get_meta(ACTIVE, false)):
		_set_pivot_preserving_rect(button, button.size * 0.5)


func _set_pivot_preserving_rect(button: BaseButton, desired: Vector2) -> void:
	var change := desired - button.pivot_offset
	if change.length_squared() <= 0.000001:
		return
	# Godot rotates/scales around pivot. Compensate the authored Control
	# position so adding a center pivot does not teleport scaled artwork.
	# Use the *resting* transform, not tween's transient hover scale: otherwise
	# resizing midway through a bounce leaves subpixel position drift on exit.
	var resting_scale: Vector2 = button.get_meta(HOME_SCALE, button.scale)
	var resting_rotation: float = button.get_meta(HOME_ROTATION, button.rotation)
	button.position += (change * resting_scale).rotated(resting_rotation) - change
	button.pivot_offset = desired


func _begin_feedback(button: BaseButton) -> void:
	if bool(button.get_meta(ACTIVE, false)):
		return
	# Responsive screens can set their own scale AFTER this autoload binds.
	# Capture the current resting values at the instant interaction begins.
	button.set_meta(HOME_SCALE, button.scale)
	button.set_meta(HOME_ROTATION, button.rotation)
	button.set_meta(HOME_Z_INDEX, button.z_index)
	button.set_meta(HOME_PIVOT, button.pivot_offset)
	button.set_meta(ACTIVE, true)
	_set_pivot_preserving_rect(button, button.size * 0.5)


func _usable(button: BaseButton) -> bool:
	return is_instance_valid(button) and button.is_inside_tree() \
		and button.is_visible_in_tree() and not button.disabled \
		and button.mouse_filter != Control.MOUSE_FILTER_IGNORE \
		and button.size.x > 0.0 and button.size.y > 0.0


func _stop_tween(button: BaseButton) -> void:
	if not button.has_meta(ACTIVE_TWEEN):
		return
	var running: Tween = button.get_meta(ACTIVE_TWEEN) as Tween
	if running != null and running.is_valid():
		running.kill()
	button.remove_meta(ACTIVE_TWEEN)


func _on_hover(button: BaseButton) -> void:
	if not _usable(button):
		return
	_stop_tween(button)
	_begin_feedback(button)
	var scale_home: Vector2 = button.get_meta(HOME_SCALE, Vector2.ONE)
	var angle_home: float = button.get_meta(HOME_ROTATION, 0.0)
	var compact := button is OptionButton or button is CheckBox or button is CheckButton
	var ratio := clampf(128.0 / maxf(button.size.x, 1.0), 0.5, 1.0)
	var bump := 1.0 + (0.06 if compact else 0.20) * ratio
	var angle := deg_to_rad((1.0 if compact else 5.0) * ratio)
	# Deterministic alternating wobble avoids rotating into the edge of the
	# same scrollable panel on every hover and preserves authored rotations.
	var direction := 1.0 if (button.get_instance_id() % 2) == 0 else -1.0
	button.z_index = maxi(int(button.get_meta(HOME_Z_INDEX, 0)), 12)
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	button.set_meta(ACTIVE_TWEEN, tween)
	tween.tween_property(button, "scale:x", scale_home.x * bump, 0.20)
	tween.tween_property(button, "scale:y", scale_home.y * bump, 0.35)
	tween.tween_property(button, "rotation", angle_home + direction * angle, 0.10)
	tween.tween_property(button, "rotation", angle_home, 0.10).set_delay(0.10)


func _on_exit(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	_stop_tween(button)
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	button.set_meta(ACTIVE_TWEEN, tween)
	tween.tween_property(button, "scale", button.get_meta(HOME_SCALE, Vector2.ONE), 0.25)
	tween.tween_property(button, "rotation", button.get_meta(HOME_ROTATION, 0.0), 0.10)
	tween.chain().tween_callback(_finish_exit.bind(weakref(button)))


func _on_press(button: BaseButton) -> void:
	if not _usable(button):
		return
	_stop_tween(button)
	_begin_feedback(button)
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	button.set_meta(ACTIVE_TWEEN, tween)
	var home: Vector2 = button.get_meta(HOME_SCALE, Vector2.ONE)
	tween.tween_property(button, "scale", home * Vector2(0.94, 0.90), 0.055)


func _on_release(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	# The visual state follows pointer location, but never emits 'pressed':
	# navigation, toggles and native dropdown popups keep their own behavior.
	if _usable(button) and button.get_global_rect().has_point(get_viewport().get_mouse_position()):
		_on_hover(button)
	else:
		_on_exit(button)


func _on_visibility_changed(button: BaseButton) -> void:
	if is_instance_valid(button) and not button.is_visible_in_tree():
		_restore_immediately(button)


func _on_tree_exiting(button: BaseButton) -> void:
	if is_instance_valid(button):
		_restore_immediately(button)


func _restore_immediately(button: BaseButton) -> void:
	_stop_tween(button)
	button.scale = button.get_meta(HOME_SCALE, Vector2.ONE)
	button.rotation = button.get_meta(HOME_ROTATION, 0.0)
	button.z_index = int(button.get_meta(HOME_Z_INDEX, 0))
	_set_pivot_preserving_rect(button, button.get_meta(HOME_PIVOT, button.pivot_offset))
	button.set_meta(ACTIVE, false)


func _finish_exit(reference: WeakRef) -> void:
	var button := reference.get_ref() as BaseButton
	if is_instance_valid(button):
		button.z_index = int(button.get_meta(HOME_Z_INDEX, 0))
		_set_pivot_preserving_rect(button, button.get_meta(HOME_PIVOT, button.pivot_offset))
		button.set_meta(ACTIVE, false)
