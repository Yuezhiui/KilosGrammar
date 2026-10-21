extends SceneTree

# Graphical native-pointer regression; former cat cursor is intentionally gone.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Native mouse-pointer graphical test requires a display")
		quit(1)
		return
	var menu := (load("res://main_menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(menu)
	await process_frame
	var success := true
	if menu.get_node_or_null("CursorCritter") != null or Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		success = false
	menu.call("_show_panel", "settings")
	await process_frame
	if menu.get_node_or_null("CursorCritter") != null or Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		success = false
	menu.call("_return_to_main")
	await process_frame
	if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
		success = false
	(menu.get_node("FallTimer") as Timer).stop()
	menu.queue_free()
	await process_frame
	print("NATIVE CURSOR GRAPHICAL: ", "PASS" if success else "FAIL")
	quit(0 if success else 1)
