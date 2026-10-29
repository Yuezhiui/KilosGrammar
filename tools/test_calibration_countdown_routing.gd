extends SceneTree

# Godot --headless --path . --script res://tools/test_calibration_countdown_routing.gd
# Exercise actual menu and calibration routes with test-only synthetic tracking,
# never granting keyboard/skip fallback or opening physical webcam hardware.
var failures: Array[String] = []
var checks := 0
var source_when := 1000.0
const DT := 0.15


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var app := (load("res://ui/main_menu/main_menu.tscn") as PackedScene).instantiate() as Control
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
	print("CALIBRATION COUNTDOWN ROUTING: %s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
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
	_bind_source_auth_camera(pose, "menu-play-calibration")
	activity.call("_go_next")
	await process_frame
	_check(_route(app) == "calibration", "Normal Play enters full-screen calibration")
	_check(bool((app.get("session_state") as Dictionary).get("camera_requested", false)), "Camera play requests capture")
	var calibration := app.get("active_panel") as Control
	_check(calibration.get_node_or_null("TutorialStage") is Control, "Calibration is an editor-authored full-screen stage")
	_check(calibration.get_node_or_null("TutorialStage/Navigation/BackButton") is Button,
		"Calibration Back control is author-edited under Navigation")
	calibration.call("_continue_flow", false)
	await process_frame
	_check(_route(app) == "calibration", "Premature Continue cannot bypass unmeasured camera holds")
	await _complete_live_calibration(calibration, pose, "Catch the Word")
	await process_frame
	_check(_route(app) == "gameplay", "Actual source-verified SOLO 3x3s + success opens gameplay")
	if _route(app) != "gameplay":
		pose.worker_pid = -1
		return
	var game := app.get("active_panel") as Control
	_check(not bool((game.get("context") as Dictionary).get("guided_tutorial", false)), "Normal Play stays unguided")
	_check(String(game.get("guided_stage")) == "countdown", "Normal Play begins countdown immediately")
	_check(not _has_legacy_spotlight_field(game), "Normal Play has no deleted Spotlight dependency")
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
	pose.worker_pid = -1 # Subsequent route may call stop_camera; never kill this Godot PID.
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
	pose.worker_pid = -1
	pose.stop_camera()
	_bind_source_auth_camera(pose, "menu-keyboard-bypass")
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
	# Old suite wrote set_calibration and then called Continue: that bypassed
	# genuine physical SOLO holds. Invalid keyboard remains disabled even if
	# a source provides one otherwise valid pose.
	_send_source_packet(calibration, pose, 0.50, 1, true)
	calibration.call("_continue_flow", false)
	await process_frame
	_check(_route(app) == "calibration", "One live pose plus stale keyboard cannot bypass full capture")
	await _complete_live_calibration(calibration, pose, "Balloon Popping")
	await process_frame
	_check(_route(app) == "gameplay", "Only three genuine bilateral down/up 3s zones authorize Balloon gameplay")
	if _route(app) != "gameplay":
		pose.worker_pid = -1
		return
	var wrapper := app.get("active_panel") as Control
	_check(String(wrapper.get("guided_stage")) == "countdown", "Camera-only normal Play gets one 3-2-1")
	_check(not _has_legacy_spotlight_field(wrapper), "Normal Play avoids deleted Spotlight API")
	_check(bool((wrapper.get("context") as Dictionary).get("camera_live", false))
		and not bool((wrapper.get("context") as Dictionary).get("keyboard_mode", true)),
		"Keyboard mode forcibly disabled; game receives live tracking")
	pose.worker_pid = -1
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


func _bind_source_auth_camera(pose: Node, session: String) -> void:
	# Live source authentication and solo-box presence, but NO webcam/Python,
	# PostgreSQL, or worker process. NEVER let stop_camera kill this test PID.
	pose.worker_pid = -1
	pose.stop_camera()
	var peer := PacketPeerUDP.new()
	_check(peer.bind(0, "127.0.0.1") == OK,
		"bound inert localhost-only camera source for " + session)
	pose.peer = peer
	pose.worker_pid = OS.get_process_id()
	pose.session_token = session
	pose.active = true


func _complete_live_calibration(calibration: Control, pose: Node, activity: String) -> void:
	calibration.set_process(false)
	calibration._process(3.01)
	# The production intro posts a deferred keyboard-focus transfer to the
	# authored Back button. Flush it while the scene is still mounted, rather
	# than letting a synthetic instantaneous 18s capture free the scene first.
	await process_frame
	_check(not bool(calibration.intro_running) and int(calibration.live_step) == 0,
		activity + ": independent 3-second intro never grants physical hold time")
	var zones: Array = ["CENTER", "RIGHT", "LEFT"]
	var x_by_zone := {"LEFT": 0.20, "CENTER": 0.50, "RIGHT": 0.80}
	_check(calibration.call("_capture_order") == zones,
		activity + ": current real source-floor calibration order")
	_check(is_equal_approx(float(calibration.call("_hold_seconds")), 3.0),
		activity + ": every real bilateral/body hold requires three seconds")
	# Missing or multiple people cannot advance even with a fake remembered x.
	for count in [0, 2]:
		_send_source_packet(calibration, pose, 0.50, count, false)
	_check(int(calibration.live_step) == 0 and calibration.live_samples.is_empty(),
		activity + ": zero/two source persons cannot start physical calibration")
	for index in range(zones.size()):
		var x := float(x_by_zone[zones[index]])
		var phases := 2 if activity == "Balloon Popping" else 1
		for phase in range(phases):
			if activity == "Balloon Popping":
				# A full-length SOLO stream with only an either-hand shooting
				# signal is still invalid for BOTH-wrist calibration.
				for i in range(24):
					_send_source_packet(calibration, pose, x, 1, true, phase == 1, true, true)
				_check(int(calibration.live_step) == index
					and int(calibration.balloon_pose_phase) == phase
					and is_zero_approx(float(calibration.live_timer))
					and calibration.live_samples.is_empty(),
					activity + ": %s phase %d rejects 3.6s of one-hand SOLO spoof" % [zones[index], phase])
				# Even a packet claiming both hands lifted/lowered is
				# insufficient without verified landmark visibility.
				for i in range(24):
					_send_source_packet(calibration, pose, x, 1, true, phase == 1, false, false)
				_check(int(calibration.live_step) == index
					and int(calibration.balloon_pose_phase) == phase
					and is_zero_approx(float(calibration.live_timer))
					and calibration.live_samples.is_empty(),
					activity + ": %s phase %d rejects 3.6s with unobserved wrists" % [zones[index], phase])
			# This is a real per-phase source-clock hold: 19 observations
			# cover only 2.7s and cannot grant any stage, even at >8 frames.
			for i in range(19):
				_send_source_packet(calibration, pose, x, 1, true, phase == 1)
			_check(int(calibration.live_step) == index
				and (activity != "Balloon Popping" or int(calibration.balloon_pose_phase) == phase),
				activity + ": %s phase %d not captured before 3 seconds" % [zones[index], phase])
			for i in range(6):
				_send_source_packet(calibration, pose, x, 1, true, phase == 1)
				if int(calibration.live_step) > index or (activity == "Balloon Popping"
						and int(calibration.balloon_pose_phase) != phase):
					break
			_check(int(calibration.live_step) == index + (1 if phase == phases - 1 else 0),
				activity + ": %s phase %d advances only on genuine 3s source hold" % [zones[index], phase])
	_check(bool(pose.calibration.get("valid", false)) and bool(calibration.success_running),
		activity + ": measured physical SOLO captures reach separate SUCCESS screen")
	_check(not bool(calibration.passing_to_ready), activity + ": no early GO before success")
	for i in range(32):
		if not is_instance_valid(calibration) or calibration.is_queued_for_deletion():
			break
		_send_source_packet(calibration, pose, 0.50, 1, true, false)
		if bool(calibration.passing_to_ready):
			break
	_check(bool(calibration.passing_to_ready),
		activity + ": only full 3-second fresh raw SOLO success releases gameplay")


func _send_source_packet(calibration: Control, pose: Node, x: float, people: int,
		valid: bool, raised: bool = false, wrists_observed: bool = true,
		one_hand_only: bool = false) -> void:
	source_when += DT
	var solo := people == 1 and valid
	var balloon := String(calibration.context.get("activity", "")) == "Balloon Popping"
	var packet := {
		"token": pose.session_token, "kind": "pose",
		"camera": true, "camera_phase": "tracking", "state": "tracking",
		"people": people, "pose": solo,
		"lock_state": "locked" if solo else "lost",
		"camera_frame_age_ms": 20, "fps": 8.0,
		"x": x if solo else -1.0,
		"hand_observation_valid": solo and wrists_observed,
		"hand_up": solo and (raised or one_hand_only),
		"both_hands_down": solo and balloon and not raised and not one_hand_only,
		"both_hands_up": solo and balloon and raised and not one_hand_only,
	}
	pose._apply_pose_packet(packet, Time.get_ticks_msec())
	if solo:
		pose.player_x = x
		pose._record_fresh_calibration_pose(packet, source_when)
	calibration._process(DT)


func _has_legacy_spotlight_field(wrapper: Control) -> bool:
	for property in wrapper.get_property_list():
		if String(property.get("name", "")) == "spotlight_overlay":
			return true
	return false


func _route(app: Control) -> String:
	return String(app.get("current_route"))


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("FAIL calibration countdown routing: ", description)
