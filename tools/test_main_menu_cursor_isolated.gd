extends SceneTree

## Regression: no separate mouse-art script remains in the main menu.
func _initialize() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var resource := load("res://ui/main_menu/main_menu.tscn") as PackedScene
	if resource == null:
		printerr("Cannot open Main Menu")
		quit(1)
		return
	var menu := resource.instantiate() as Control
	root.add_child(menu)
	await process_frame
	var no_custom := menu.get_node_or_null("CursorCritter") == null
	var os_pointer := Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE
	(menu.get_node("FallTimer") as Timer).stop()
	menu.queue_free()
	await process_frame
	if no_custom and os_pointer:
		print("PASS no custom cursor in main menu scene")
		quit(0)
	else:
		printerr("Custom cursor is present or OS pointer is hidden")
		quit(1)
