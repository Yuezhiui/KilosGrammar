extends SceneTree

# End-to-end navigation test. Synthetic fresh pose packets complete all three
# measured standing stages in the calibration UI without opening a webcam.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app := (load("res://main_menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(app)
	var service := root.get_node("PoseService")
	app.call("_on_panel_requested", "tutorial_home", {})
	await process_frame
	var tutorial := app.get("active_panel") as Control
	var start := tutorial.get_node_or_null("TutorialStage/StartButton") as Button
	_check(start != null, "Tutorial Start button is editor authored")
	if start == null:
		await _finish(app)
		return
	start.pressed.emit()
	await process_frame
	_check(_route(app) == "play_activity", "Guided Start opens Game Selection first")
	var select := app.get("active_panel") as Control
	_check(bool((select.get("context") as Dictionary).get("guided_tutorial", false)), "Game Selection receives guided flag")
	_check(not select.has_method("_play_keyboard_now")
		and select.get_node_or_null("LayoutMargins/Content/Footer/PlayKeyboardButton") == null,
		"Game Selection has no keyboard shortcut in guided or ordinary Play")
	_check(select.get_node_or_null("LayoutMargins/Content/GameRow/GameOptions/GameOptionsContent/CatchWordButton") is Button, "Game button is an editable scene node")
	(select.get("activity_buttons")["Catch the Word"] as Button).pressed.emit()
	(select.get("next_button") as Button).pressed.emit()
	await process_frame
	_check(_route(app) == "student_setup", "Game Selection opens teacher/student setup")
	var form := app.get("active_panel") as Control
	_check(String((form.get("context") as Dictionary).get("activity", "")) == "Catch the Word", "Selected game survives setup transition")
	(form.get("_student_id_edit") as LineEdit).text = "GUIDED-01"
	(form.get("_name_edit") as LineEdit).text = "Sample Student"
	(form.get("_grade_edit") as LineEdit).text = "Grade 2"
	form.call("_select_style", "Noun")
	form.call("_select_mode", "Seconds")
	form.call("_select_difficulty", "Easy")
	# Mark the test-only synthetic camera as active to prevent webcam startup.
	# Measurements themselves are supplied below as fresh pose packets.
	service.active = true
	service.set_process(false)
	service.current_status = {"state": "waiting", "pose": false}
	service.player_x = -1.0
	form.call("_continue")
	await process_frame
	_check(_route(app) == "calibration", "Teacher setup enters automatic calibration")
	var context: Dictionary = app.get("session_state")
	_check(bool(context.get("guided_tutorial", false)), "Guided flag survives teacher setup")
	_check(bool(context.get("camera_requested", false)), "Automatic camera request reaches calibration")
	_check(context.get("difficulty") == "Easy" and context.get("game_mode") == "Seconds", "Teacher selections survive calibration entry")
	var calib := app.get("active_panel") as Control
	_check(calib.get_node_or_null("TutorialStage/SkipButton") == null
		and not calib.has_method("_skip_calibration"),
		"Calibration has no skip/keyboard control")
	var routed: Array[Dictionary] = []
	calib.requested.connect(func(target: String, payload: Dictionary) -> void:
		routed.append({"target": target, "payload": payload}))
	# Finish the 2.5s intro, then earn each of the three holds with 10 fresh
	# samples spread over 3.2 simulated seconds. No _continue_flow skip call
	# or directly assigned calibration dictionary is used in this route.
	calib.set_process(false)
	calib.call("_process", 2.5)
	for stage_data in [
		{"x": 0.50, "step": 1},
		{"x": 0.82, "step": 2},
		{"x": 0.18, "step": 3}
	]:
		var x: float = float(stage_data["x"])
		for sample_index in range(10):
			service.player_x = x
			service.current_status = {"state": "tracking", "pose": true}
			service.last_pose_ms = Time.get_ticks_msec()
			service.packet_sequence += 1
			calib.call("_process", 0.32)
		_check(int(calib.get("live_step")) == int(stage_data["step"]),
			"Fresh poses completed calibrated standing position %d" % stage_data["step"])
	_check(bool(service.calibration.get("valid", false)),
		"All three synthetic measured positions produce a valid calibration")
	# Allow calibration's genuine deferred 2-second completion to run.
	# Synthetic tracking heartbeats stand in for continuing camera packets;
	# otherwise its 1750ms stale-pose guard correctly blocks handoff.
	for heartbeat in range(12):
		service.last_pose_ms = Time.get_ticks_msec()
		await create_timer(0.23).timeout
	await process_frame
	_check(_route(app) == "gameplay", "Measured guided calibration starts gameplay spotlight after automatic handoff")
	_check(not routed.is_empty() and bool((routed[0]["payload"] as Dictionary).get("guided_tutorial", false)), "Calibration signal forwards guided flag")
	_check(not routed.is_empty() and not bool((routed[0]["payload"] as Dictionary).get("keyboard_mode", true))
		and bool((routed[0]["payload"] as Dictionary).get("calibration_measured", false)),
		"Measured calibration preserves camera controls and never enables keyboard")
	if _route(app) != "gameplay":
		await _finish(app)
		return
	var game := app.get("active_panel") as Control
	_check(bool((game.get("context") as Dictionary).get("guided_tutorial", false)), "Gameplay receives guided flag for spotlight")
	_check(String(game.get("guided_stage")) == "tutorial", "Gameplay is gated until spotlight completes")
	_check((game.get("active_game") as Control).process_mode == Node.PROCESS_MODE_DISABLED, "Score and game timers remain frozen during spotlight")
	_check(game.get("spotlight_overlay") != null, "Spotlight is mounted before the only 3-2-1 countdown")
	var ready_scene := load("res://ui/play/ready.tscn") as PackedScene
	var ready := ready_scene.instantiate() as Control
	_check(ready.get_node_or_null("LayoutMargins/Content/Center/ReadyCard/ReadyCardContent/CountdownLabel") is Label, "Standard Play Ready countdown is editor authored")
	ready.free()
	if routed.size() == 1:
		var live_payload := routed[0]["payload"] as Dictionary
		_check(bool(live_payload.get("camera_live", false)) and bool(live_payload.get("from_calibration", false)),
			"Successful measured calibration retains live camera controls")
		_check(not bool(live_payload.get("calibration_skipped", true)),
			"Successful calibration does not report a skipped measurement")
	# Game Over retry must open an ordinary session with no inherited overlay.
	app.call("_on_panel_requested", "results", {"score": 10})
	await process_frame
	app.call("_on_panel_requested", "student_setup", {"guided_tutorial": true})
	await process_frame
	_check(not bool((app.get("session_state") as Dictionary).get("guided_tutorial", false)), "Results retry clears guided flag")
	app.call("_return_to_main")
	await process_frame
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	_check(not bool((app.get("session_state") as Dictionary).get("guided_tutorial", false)), "Fresh Play clears guided flag")
	await _finish(app)


func _route(app: Control) -> String:
	return String(app.get("current_route"))


func _check(good: bool, message: String) -> void:
	if not good:
		failures.append(message)
		printerr("FAIL guided routing: ", message)


func _finish(app: Control) -> void:
	app.call("_return_to_main")
	await process_frame
	app.queue_free()
	await process_frame
	await process_frame
	print("GUIDED ROUTING: ", "PASS" if failures.is_empty() else "FAIL", " (%d failures)" % failures.size())
	quit(0 if failures.is_empty() else 1)
