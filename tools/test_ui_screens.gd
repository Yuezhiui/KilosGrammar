extends SceneTree

# Run: Godot --headless --path . --script res://tools/test_ui_screens.gd
# Fast smoke test: load every current UI scene in the real main menu host.
const ROUTES := [
	"tutorial_home", "tutorial_practice", "tutorial_complete", "grammar_guide",
	"play_activity", "play_topic", "play_difficulty",
	"camera_check", "calibration", "ready", "gameplay", "pause",
	"results", "leaderboard", "settings", "credits"
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed: PackedScene = load("res://main_menu.tscn") as PackedScene
	if packed == null:
		push_error("Could not load original main menu")
		quit(1)
		return
	var app: Control = packed.instantiate() as Control
	root.add_child(app)
	# Allow the original 1.12-second intro coroutine to finish before teardown.
	await create_timer(1.35).timeout
	app.get_node("MainLayer/CenterMenu/Play").emit_signal("pressed")
	await process_frame
	_assert_route(app, "play_activity", "Main Panel Play button")
	app.call("_return_to_main")
	await process_frame
	for route in ROUTES:
		app.call("_on_panel_requested", route, {})
		await process_frame
		var panel: Control = app.get("active_panel") as Control
		if String(app.get("current_route")) != route:
			failures.append(route + " did not activate")
		elif panel == null or not is_instance_valid(panel):
			failures.append(route + " has no Control root")
		elif not panel.has_signal("requested"):
			failures.append(route + " has no navigation signal")
		else:
			print("PASS  ", route)

	# Verify the real control-to-control Play path, not just isolated scene loads.
	app.call("_on_panel_requested", "play_activity", {})
	await process_frame
	(app.get("active_panel") as Control).call("_go_next")
	await process_frame
	_assert_route(app, "play_topic", "Activity -> Topic")
	(app.get("active_panel") as Control).call("_go_next")
	await process_frame
	_assert_route(app, "play_difficulty", "Topic -> Difficulty")
	(app.get("active_panel") as Control).call("_go_next")
	await process_frame
	_assert_route(app, "camera_check", "Difficulty -> Camera")
	app.call("_on_panel_requested", "calibration", {"entry_source": "play"})
	await process_frame
	(app.get("active_panel") as Control).call("_continue_flow", false)
	await process_frame
	_assert_route(app, "ready", "Play Calibration -> Ready")
	app.call("_on_panel_requested", "gameplay", {"demo_mode": true})
	await process_frame
	var gameplay: Control = app.get("active_panel") as Control
	gameplay.call("_simulate_correct")
	gameplay.call("_simulate_wrong")
	gameplay.call("_finish_demo")
	await process_frame
	_assert_route(app, "results", "Gameplay -> Results")
	(app.get("active_panel") as Control).call("_request", "retry")
	await process_frame
	_assert_route(app, "ready", "Results -> Fresh Retry")
	var state: Dictionary = app.get("session_state")
	if state.has("score") or state.has("attempts"):
		failures.append("Retry retained old demo scores")

	app.call("_on_panel_requested", "tutorial_home", {})
	await process_frame
	app.call("_on_panel_requested", "camera_check", {"entry_source": "tutorial"})
	await process_frame
	app.call("_on_panel_requested", "calibration", {})
	await process_frame
	(app.get("active_panel") as Control).call("_continue_flow", false)
	await process_frame
	_assert_route(app, "tutorial_practice", "Tutorial Calibration -> Practice")
	(app.get("active_panel") as Control).call("_go_back")
	await process_frame
	_assert_route(app, "calibration", "Guided Practice Back -> Calibration")
	app.call("_on_panel_requested", "tutorial_home", {})
	await process_frame
	app.call("_on_panel_requested", "tutorial_practice", {"from_calibration": false})
	await process_frame
	(app.get("active_panel") as Control).call("_go_back")
	await process_frame
	_assert_route(app, "tutorial_home", "Direct Practice Back -> Tutorial Home")
	app.call("_on_panel_requested", "tutorial_practice", {"from_calibration": false})
	await process_frame
	(app.get("active_panel") as Control).call("_request", "tutorial_complete", {"tutorial_practiced": true})
	await process_frame
	_assert_route(app, "tutorial_complete", "Practice -> Tutorial Complete")
	app.call("_on_panel_requested", "camera_check", {"entry_source": "play"})
	await process_frame
	(app.get("active_panel") as Control).call("_go_back")
	await process_frame
	_assert_route(app, "play_difficulty", "Camera Back -> Difficulty")
	app.call("_return_to_main")
	await process_frame
	if String(app.get("current_route")) != "main":
		failures.append("Main panel was not restored")
	app.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS  all %d UI scenes loaded and returned to Main Panel" % ROUTES.size())
		quit(0)
	else:
		for failure in failures:
			push_error("FAIL  " + failure)
		quit(1)


func _assert_route(app: Control, expected: String, label: String) -> void:
	if String(app.get("current_route")) == expected:
		print("PASS  ", label)
	else:
		failures.append("%s expected %s but got %s" % [label, expected, String(app.get("current_route"))])
