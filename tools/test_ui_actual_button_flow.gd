extends SceneTree

# Focused native Button.pressed route test; synthetic pose state keeps the
# real webcam closed. Gameplay/results are injected only after route testing.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(app: Control, route: String, label: String) -> void:
	var actual := String(app.get("current_route"))
	if actual != route:
		failures.append("%s expected %s got %s" % [label, route, actual])
	else:
		print("PASS ", label, " -> ", route)

func _press(button: Button, label: String) -> void:
	if button == null or button.disabled:
		failures.append("Inaccessible button: " + label)
		return
	button.pressed.emit()
	await process_frame

func _button_by_text(node: Node, fragment: String) -> Button:
	if node is Button and String((node as Button).text).contains(fragment):
		return node as Button
	for child in node.get_children():
		var found := _button_by_text(child, fragment)
		if found:
			return found
	return null

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app := (load("res://main_menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(app)
	await create_timer(1.35).timeout
	await _press(app.get_node("MainLayer/CenterMenu/Play") as Button, "Main Play")
	_check(app, "student_setup", "Main Play")
	var student: Control = app.get("active_panel")
	(student.get("_student_id_edit") as LineEdit).text = "2026-01427"
	(student.get("_name_edit") as LineEdit).text = "Test Student"
	(student.get("_grade_edit") as LineEdit).text = "Grade 5"
	await _press(student.get("_style_buttons")["Noun"] as Button, "Student Noun")
	await _press(student.get("_mode_buttons")["Seconds"] as Button, "Student Seconds")
	await _press(student.get("_difficulty_buttons")["Easy"] as Button, "Student Easy")
	await _press(student.get("_continue_button") as Button, "Student Continue")
	_check(app, "play_activity", "Student Continue")
	var state: Dictionary = app.get("session_state")
	for key in ["game_style", "game_mode", "difficulty"]:
		var expected: String = {"game_style":"Noun", "game_mode":"Seconds", "difficulty":"Easy"}[key]
		if state.get(key) != expected:
			failures.append("Selected %s lost: %s" % [key, state.get(key)])
	var activity: Control = app.get("active_panel")
	await _press(activity.get("activity_buttons")["Catch the Word"] as Button, "Catch activity")
	if activity.has_method("_play_keyboard_now") or activity.get_node_or_null("LayoutMargins/Content/Footer/PlayKeyboardButton") != null:
		failures.append("Game Selection still offers a keyboard shortcut")
	var pose := root.get_node("PoseService")
	# Mark a synthetic camera session active before Next to prevent opening
	# hardware. This state never completes a calibration measurement.
	pose.active = true
	pose.player_x = -1.0
	pose.current_status = {"state": "waiting", "pose": false}
	await _press(activity.get("next_button") as Button, "Game Selection Next")
	_check(app, "calibration", "Game Selection Next -> camera-only calibration")
	var calibration_state := (app.get("session_state") as Dictionary).duplicate(true)
	if bool(calibration_state.get("keyboard_mode", true)) or not bool(calibration_state.get("camera_requested", false)):
		failures.append("Game Selection did not carry camera-only setup")
	var calibration := app.get("active_panel") as Control
	if calibration.get_node_or_null("TutorialStage/SkipButton") != null or _button_by_text(calibration, "SKIP") != null:
		failures.append("Calibration still has a SKIP shortcut")
	await _press(calibration.get_node_or_null("TutorialStage/IntroOverlay/IntroBackButton") as Button, "Calibration Back to Main")
	_check(app, "main", "Calibration Back")
	# Later pause/results tests use an explicit router injection. It is NOT a
	# calibration completion, synthetic success signal, or keyboard bypass.
	calibration_state["start_countdown"] = false
	calibration_state["guided_tutorial"] = false
	calibration_state["keyboard_mode"] = false
	app.call("_on_panel_requested", "gameplay", calibration_state)
	await process_frame
	_check(app, "gameplay", "Explicit isolated gameplay fixture")
	if String(app.get("current_route")) == "gameplay":
		var game: Control = app.get("active_panel")
		if String(game.get("guided_stage")) == "countdown":
			await create_timer(3.5).timeout
			_check(app, "gameplay", "Calibration automatic countdown")
		game.call("_pause")
		await process_frame
		_check(app, "pause", "Catch Pause")
		if String(app.get("current_route")) == "pause":
			await _press((app.get("active_panel") as Control).get("resume_button") as Button, "Pause Resume")
			_check(app, "gameplay", "Resume")
			(app.get("active_panel") as Control).call("_pause")
			await process_frame
			_check(app, "pause", "Second Pause")
			await _press(_button_by_text(app.get("active_panel") as Control, "RESULTS"), "Pause View Results")
			_check(app, "results", "Pause Results")
	if String(app.get("current_route")) == "results":
		await _press((app.get("active_panel") as Control).get_node("%RetryButton") as Button, "Results Retry")
		_check(app, "student_setup", "Retry")
		var after_retry: Dictionary = app.get("session_state")
		if after_retry.has("score"):
			failures.append("Retry retained score")
		app.call("_on_panel_requested", "results", {"score":100})
		await process_frame
		await _press((app.get("active_panel") as Control).get_node("%MainButton") as Button, "Results Main")
		_check(app, "main", "Main")
	await _finish(app)

func _finish(app: Control) -> void:
	# Drain active audio before releasing scene-owned streams and nodes.
	var players: Array[AudioStreamPlayer] = []
	var pending: Array[Node] = [app]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is AudioStreamPlayer:
			players.append(node as AudioStreamPlayer)
		for child in node.get_children():
			pending.append(child)
	for player in players:
		player.stop()
		player.stream = null
	app.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.5).timeout
	if failures.is_empty():
		print("PASS actual native button flow (tested reachable stages)")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
