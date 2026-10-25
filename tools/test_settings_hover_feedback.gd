extends SceneTree

# Isolated, camera-free inspection of the REAL editor-authored Settings scene.
# Godot 4.7.2 --headless --path . --script res://tools/test_settings_hover_feedback.gd
# Does not click toggles, write preferences, use the database or start a camera.
const SETTINGS := "res://ui/secondary/settings.tscn"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load(SETTINGS) as PackedScene).instantiate() as Control
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	var sidebar := scene.find_child("SidebarPanel", true, false) as Control
	_check(sidebar != null and sidebar.self_modulate.a > 0.99,
		"editor-authored sidebar is a transparent Control, not a zero-alpha sound-blocking Panel")
	var buttons: Array[BaseButton] = []
	for name in ["SidebarSettingsTab", "SidebarControlsTab", "SidebarCameraTab",
			"BackButton", "MuteCheck", "FullscreenCheck"]:
		var button := scene.find_child(name, true, false) as BaseButton
		_check(button != null, name + " remains editor-authored")
		if button != null:
			buttons.append(button)
	_check(buttons.size() == 6, "all four navigation and two toggle buttons available")
	_check(_empty_tooltips(scene), "no Control in Settings creates dark native hover popups")
	for button in buttons:
		var label := button.name
		var home_z := button.z_index
		var home_rotation := button.rotation
		var home_rect := button.get_rect()
		_check(button.pivot_offset.is_equal_approx(button.size * 0.5), label + " scales around its center")
		for signal_name in ["mouse_entered", "mouse_exited", "button_down", "button_up"]:
			var matches := 0
			for connection: Dictionary in button.get_signal_connection_list(signal_name):
				if connection["callable"].get_object() == scene:
					matches += 1
			_check(matches == 1, label + " has one Settings " + signal_name + " animation handler")
		button.mouse_entered.emit()
		await create_timer(0.23).timeout
		_check(button.scale.x > 1.01 and button.scale.x <= 1.16,
			label + " performs the subtle Main Menu-style hover scale")
		_check(button.z_index > home_z, label + " renders above its siblings while hovered")
		button.mouse_exited.emit()
		await create_timer(0.42).timeout
		_check(button.scale.is_equal_approx(Vector2.ONE), label + " returns to original scale")
		_check(is_equal_approx(button.rotation, home_rotation), label + " returns to original angle")
		_check(button.z_index == home_z, label + " restores scene-authored draw order")
		_check(button.get_rect().is_equal_approx(home_rect), label + " original drag/drop rectangle unchanged")
		button.button_down.emit()
		await create_timer(0.12).timeout
		_check(button.scale.x < 0.96 and button.scale.y < 0.96,
			label + " has short press-squash feedback")
		button.button_up.emit()
		await create_timer(0.43).timeout
		# Synthetic activation is not under a real pointer, so exit state wins.
		button.mouse_exited.emit()
		await create_timer(0.36).timeout
		_check(button.scale.is_equal_approx(Vector2.ONE),
			label + " does not get stuck scaled after quick press and release")
	scene.queue_free()
	await process_frame
	await process_frame
	for error in failures:
		printerr("SETTINGS HOVER QA FAIL: ", error)
	print("SETTINGS HOVER QA: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _empty_tooltips(node: Node) -> bool:
	if node is Control and not (node as Control).tooltip_text.is_empty():
		return false
	for child in node.get_children():
		if not _empty_tooltips(child):
			return false
	return true


func _check(yes: bool, description: String) -> void:
	checks += 1
	if not yes:
		failures.append(description)
