extends SceneTree

# Godot --headless --path . --script res://tools/test_calibration_countdown_routing.gd
# Exercise actual menu and calibration routes with test-only synthetic tracking,
# never granting keyboard/skip fallback or opening physical webcam hardware.
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app := (load("res://main_menu.tscn") as PackedScene).instantiate() as Control
	# Substitute only the local service initializer before _ready: otherwise
	# a synthetic test student could enter a REAL registration request when a
	# teacher's PostgreSQL server happens to be online.
	app.set_script(load("res://tools/test_calibration_countdown_offline_menu.gd"))
	root.add_child(app)
	var pose := root.get_node("PoseService")
	pose.stop_camera()
	pose.set_process(false) # No synthetic test may launch/poll a webcam worker.
	await _test_normal_play(app, pose)
	await _test_camera_only_gate(app, pose)
	await _test_back_to_main(app, pose)
	app.call("_return_to_main")
	await process_frame
	pose.stop_camera()
	pose.set_process(true)
	await app.call("prepare_for_shutdown")
	app.queue_free()
	await process_frame
	print("CALIBRATION COUNTDOWN ROUTING: %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_normal_play(app: Control, pose: Node) -> void:
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	_check(_route(app) == "student_setup", "Normal Play opens student setup")
	var setup := app.get("active_panel") as Control
	_fill_setup(setup)
	setup.call("_continue")
	await process_frame
	_check(_route(app) == "play_activity", "Normal Play opens game selection")
	var activity := app.get("active_panel") as Control
	activity.call("_select_activity", "Catch the Word")
	pose.set("active", true)
	pose.set("calibration", {"left": 0.20, "center": 0.50, "right": 0.80, "valid": true})
	# A measured live calibration is valid only while fresh pose tracking remains
	# available. Mock that explicitly instead of bypassing the safety gate.
	pose.set("player_x", 0.50)
	pose.set("current_status", {"state": "tracking", "pose": true})
	pose.set("last_pose_ms", Time.get_ticks_msec())
	activity.call("_go_next")
	await process_frame
	_check(_route(app) == "calibration", "Normal Play enters full-screen calibration")
	_check(bool((app.get("session_state") as Dictionary).get("camera_requested", false)), "Camera play requests capture")
	var calibration := app.get("active_panel") as Control
	_check(calibration.get_node_or_null("TutorialStage") is Control, "Calibration is an editor-authored full-screen stage")
	_check(calibration.get_node_or_null("TutorialStage/BackButton") is Button, "Calibration Back control exists")
	calibration.call("_continue_flow", false)
	await process_frame
	_check(_route(app) == "gameplay", "Measured normal calibration auto-enters gameplay")
	var game := app.get("active_panel") as Control
	_check(not bool((game.get("context") as Dictionary).get("guided_tutorial", false)), "Normal Play has no guided overlay flag")
	_check(String(game.get("guided_stage")) == "countdown", "Normal Play begins countdown immediately")
	_check(game.get("spotlight_overlay") == null, "Normal Play does not show Spotlight")
	await process_frame
	var round := game.get("active_game") as Control
	_check(round != null and round.process_mode == Node.PROCESS_MODE_DISABLED, "Normal game is frozen before GO")
	var countdown := game.get("countdown_panel") as Control
	_check(countdown != null and countdown.get_node_or_null("CountdownNumber") is Label, "Shared countdown is scene authored")
	if countdown != null:
		_check((countdown.get_node("CountdownNumber") as Label).text == "3", "Normal countdown starts at 3")
		var before_time := float(round.get("time_remaining"))
		var before_score := int(round.get("score"))
		var before_lives := int(round.get("lives"))
		await create_timer(0.16).timeout
		_check(is_equal_approx(float(round.get("time_remaining")), before_time), "Normal countdown holds the timer")
		_check(int(round.get("score")) == before_score and int(round.get("lives")) == before_lives, "Normal countdown protects score and lives")
		for _tick in 3:
			game.call("_on_countdown_tick")
		_check(round.process_mode == Node.PROCESS_MODE_INHERIT and game.get("countdown_panel") == null, "Normal round begins only after countdown")
	# Calibration BACK keeps student/setup context and returns to Choose
	# Activity, without forcing the teacher back to the title screen.
	pose.set("active", true)
	app.call("_on_panel_requested", "calibration", {"camera_requested": true, "keyboard_mode": false})
	await process_frame
	calibration = app.get("active_panel") as Control
	calibration.call("_go_back")
	await process_frame
	_check(_route(app) == "play_activity", "Calibration Back returns to Choose Activity as labeled")
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	var fresh_form := app.get("active_panel") as Control
	_fill_setup(fresh_form)
	fresh_form.call("_continue")
	await process_frame
	_check(_route(app) == "play_activity", "Teacher can restart setup to choose another game")
	var selection := app.get("active_panel") as Control
	selection.call("_select_activity", "Human Plane")
	selection.call("_go_back")
	await process_frame
	_check(_route(app) == "student_setup", "Teacher can return to and edit the preserved setup")
	_check(String((app.get("active_panel") as Control).get("_student_id_edit").text) == "STD-TEST", "Returning to setup keeps the student record")
	app.call("_return_to_main")
	await process_frame


func _test_camera_only_gate(app: Control, pose: Node) -> void:
	# Even an obsolete keyboard payload must not unlock gameplay without live
	# tracked calibration. The only non-game action is teacher Back to Main.
	pose.stop_camera()
	pose.set("active", true)
	pose.set("player_x", -1.0)
	pose.set("current_status", {"state": "waiting", "pose": false})
	app.call("_on_panel_requested", "calibration", {
		"camera_requested": false, "keyboard_mode": true,
		"activity": "Balloon Popping", "game_mode": "Seconds"
	})
	await process_frame
	_check(_route(app) == "calibration", "Stale keyboard entry remains in real calibration scene")
	var calibration := app.get("active_panel") as Control
	_check(calibration.get_node_or_null("TutorialStage/SkipButton") == null
		and calibration.get_node_or_null("TutorialStage/RetryButton") == null
		and calibration.get_node_or_null("TutorialStage/DemoButton") == null,
		"Skip, Reset, Stop controls are absent")
	calibration.call("_continue_flow", true)
	calibration.call("_continue_flow", false)
	await process_frame
	_check(_route(app) == "calibration", "No-camera and stale keyboard fallback cannot bypass three holds")
	pose.set("player_x", 0.50)
	pose.set("current_status", {"state": "tracking", "pose": true})
	pose.set("last_pose_ms", Time.get_ticks_msec())
	_check(bool(pose.call("set_calibration", 0.20, 0.50, 0.80)), "PoseService validates synthetic position triplet")
	calibration.call("_continue_flow", false)
	await process_frame
	_check(_route(app) == "gameplay", "Only real-valid live camera calibration can enter gameplay")
	var wrapper := app.get("active_panel") as Control
	_check(String(wrapper.get("guided_stage")) == "countdown", "Camera-only normal Play gets one 3-2-1")
	_check(wrapper.get("spotlight_overlay") == null, "Normal Play avoids guided Spotlight")
	_check(bool((wrapper.get("context") as Dictionary).get("camera_live", false))
		and not bool((wrapper.get("context") as Dictionary).get("keyboard_mode", true)),
		"Keyboard mode forcibly disabled; game receives live tracking")
	app.call("_return_to_main")
	await process_frame


func _test_back_to_main(app: Control, pose: Node) -> void:
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	var setup := app.get("active_panel") as Control
	_fill_setup(setup)
	setup.call("_continue")
	await process_frame
	var selection := app.get("active_panel") as Control
	selection.call("_select_activity", "Human Plane")
	pose.set("active", true)
	app.call("_on_panel_requested", "calibration", {"camera_requested": true, "keyboard_mode": false})
	await process_frame
	_check(_route(app) == "calibration", "Teacher opens camera calibration")
	app.call("_on_panel_requested", "main", {})
	await process_frame
	_check(_route(app) == "main" and app.get("active_panel") == null, "Back to Main cancels calibration scene")
	_check(not bool(pose.get("active")), "Back to Main stops camera tracking")
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	_check(_route(app) == "student_setup", "Teacher can start a new game after cancellation")
	var form := app.get("active_panel") as Control
	_check(not bool((form.get("context") as Dictionary).get("guided_tutorial", false)), "Fresh normal Play is not guided")


func _fill_setup(setup: Control) -> void:
	(setup.get("_student_id_edit") as LineEdit).text = "STD-TEST"
	(setup.get("_name_edit") as LineEdit).text = "Student Test"
	(setup.get("_grade_edit") as LineEdit).text = "Grade 2"
	setup.call("_select_style", "Noun")
	setup.call("_select_mode", "Seconds")
	setup.call("_select_difficulty", "Easy")


func _route(app: Control) -> String:
	return String(app.get("current_route"))


func _check(ok: bool, description: String) -> void:
	if not ok:
		failures.append(description)
		printerr("FAIL calibration countdown routing: ", description)
