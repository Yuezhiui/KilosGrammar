extends SceneTree

## The main menu must always use the system cursor, never a drawn cat.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)


func _run() -> void:
	var menu := (load("res://main_menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(menu)
	await process_frame
	_check(menu.get_node_or_null("CursorCritter") == null, "No custom cursor art should be instantiated")
	_check(menu.get("current_route") == "main", "Home is active")
	_check(Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "Normal OS pointer visible on Home")
	for route in ["settings", "credits", "tutorial_home", "leaderboard"]:
		menu.call("_show_panel", route)
		await process_frame
		_check(menu.get("current_route") == route, "Screen route loads: " + route)
		_check(menu.get_node_or_null("CursorCritter") == null, "No custom cursor on: " + route)
		_check(Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "Normal OS pointer on: " + route)
	menu.call("_return_to_main")
	await process_frame
	_check(Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "Returning Home keeps OS pointer")
	_check(menu.get_node_or_null("CursorCritter") == null, "Custom cursor remains absent")
	(menu.get_node("FallTimer") as Timer).stop()
	for audio_node in menu.find_children("*", "AudioStreamPlayer", true, false):
		(audio_node as AudioStreamPlayer).stop()
	menu.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS main menu uses native system pointer on all routes")
		quit(0)
	else:
		for issue in failures:
			push_error(issue)
		quit(1)
