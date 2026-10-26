extends SceneTree

# Run: Godot --headless --path . --script res://tools/test_button_sound_routes.gd
# Exercises actual routed panels; verifies every BaseButton has one owner
# for hover, keyboard focus and activation sounds after dynamic construction.
const ROUTES := [
	"tutorial_home", "grammar_guide",
	"student_setup", "play_activity", "play_topic", "play_difficulty",
	"camera_check", "calibration", "gameplay", "pause",
	"results", "leaderboard", "settings"
]
var failures: Array[String] = []
var checked_buttons := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://main_menu.tscn") as PackedScene
	if packed == null:
		push_error("Cannot load main menu")
		quit(1)
		return
	var app := packed.instantiate() as Control
	root.add_child(app)
	await process_frame
	var router := app.get_node_or_null("ButtonSounds")
	if router == null:
		push_error("Missing shared ButtonSounds node")
		quit(1)
		return
	_check_branch(app.get_node("MainLayer/LeftMenu"), router, "main/left")
	_check_branch(app.get_node("MainLayer/CenterMenu"), router, "main/center")
	for route in ROUTES:
		app.call("_on_panel_requested", route, {})
		await process_frame
		var panel := app.get("active_panel") as Control
		if String(app.get("current_route")) != route or panel == null:
			failures.append("Navigation failed for %s" % route)
			continue
		var before := checked_buttons
		_check_branch(panel, router, route)
		if checked_buttons == before:
			failures.append("No buttons under %s" % route)
		if route == "settings":
			for tab in ["settings", "controls", "camera"]:
				panel.call("_switch_tab", tab)
				await process_frame
				_check_branch(panel, router, "settings/" + tab)
			var late := Button.new()
			late.name = "DynamicSoundProbe"
			panel.add_child(late)
			await process_frame
			_check_branch(late, router, "settings/dynamic")
			late.queue_free()
			await process_frame
		print("BUTTON_SOUNDS_ROUTE ", route, " checked=", checked_buttons - before)
	app.call("_return_to_main")
	await process_frame
	_check_branch(app.get_node("MainLayer/LeftMenu"), router, "main/returned")
	_check_branch(app.get_node("MainLayer/CenterMenu"), router, "main/returned")
	_clean_audio(app)
	app.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	for failure in failures:
		push_error(failure)
	print("BUTTON_SOUNDS_ROUTES: ", "PASS" if failures.is_empty() else "FAIL", " checked=", checked_buttons, " issues=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _check_branch(node: Node, router: Node, route: String) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		for signal_name in ["mouse_entered", "focus_entered", "button_down"]:
			var matches := 0
			for connection: Dictionary in button.get_signal_connection_list(signal_name):
				var callback: Callable = connection["callable"]
				if callback.get_object() == router:
					matches += 1
			if matches != 1:
				failures.append("%s/%s %s: expected one shared sound connection; got %d" % [route, button.name, signal_name, matches])
		checked_buttons += 1
	for child in node.get_children():
		_check_branch(child, router, route)


func _clean_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		var player := node as AudioStreamPlayer
		player.stop()
		player.stream = null
	for child in node.get_children():
		_clean_audio(child)
