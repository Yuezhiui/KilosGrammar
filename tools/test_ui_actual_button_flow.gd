extends SceneTree

# Focused native Button.pressed route test; no camera is fabricated.
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
	# UI regression stays hardware-independent. A separate live-camera
	# smoke test covers the new auto-calibration path; here use keyboard.
	await _press(activity.get("keyboard_button") as Button, "Activity Keyboard Play")
	var route := String(app.get("current_route"))
	if route == "play_topic":
		var topic: Control = app.get("active_panel")
		await _press(topic.get("topic_buttons")["Noun"] as Button, "Topic Noun")
		await _press(topic.get("next_button") as Button, "Topic Continue")
		route = String(app.get("current_route"))
	if route == "play_difficulty":
		var difficulty: Control = app.get("active_panel")
		await _press(difficulty.get("difficulty_buttons")["Easy"] as Button, "Difficulty Easy")
		await _press(difficulty.get("next_button") as Button, "Difficulty Continue")
		route = String(app.get("current_route"))
	if route == "camera_check":
		print("PASS native route reached camera_check; camera preview is not fabricated")
		# Navigate using the native skip control, not an artificial camera signal.
		var camera: Control = app.get("active_panel")
		var skip := _button_by_text(camera, "CONTINUE")
		if skip:
			await _press(skip, "Camera Skip")
		else:
			print("INFO Camera continue button not reachable; stopping before fake camera navigation")
			failures.append("Camera native Continue not found")
			await _finish(app)
			return
	if String(app.get("current_route")) == "calibration":
		var calibration: Control = app.get("active_panel")
		var continue_button := _button_by_text(calibration, "CONTINUE")
		if continue_button:
			await _press(continue_button, "Calibration Continue")
		else:
			failures.append("Calibration native Continue not found")
	if String(app.get("current_route")) == "ready":
		var ready: Control = app.get("active_panel")
		await _press(ready.get("start_button") as Button, "Ready Start")
		await create_timer(3.5).timeout
		_check(app, "gameplay", "Countdown")
	if String(app.get("current_route")) == "gameplay":
		var game: Control = app.get("active_panel")
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
