extends SceneTree

# Synthetic Play/Tutorial routing regression. The database is replaced with a
# local mock before any registration/score operation, and PoseService is put in
# a synthetic active state before calibration so this test never opens a webcam.
const MOCK_DATABASE := preload("res://tools/play_route_mock_database.gd")

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var pose := root.get_node_or_null("PoseService")
	_expect(pose != null, "PoseService autoload is available")
	if pose == null:
		_finish(null)
		return
	pose.stop_camera()

	var app := (load("res://ui/main_menu/main_menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(app)
	await process_frame
	var mock := await _install_mock_database(app)
	if mock == null:
		await _finish(app)
		return

	await _test_verified_existing_student(app, mock, pose)
	await _test_new_student_registration_and_save(app, mock)
	await _test_registration_conflict_recovery(app, mock)
	await _test_registration_timeout_offline_play(app, mock)
	await _test_results_retry_leaderboard_retention_and_explicit_delete(app, mock)
	await _test_human_plane_restart_recalibrates_after_lock_change(app, mock, pose)
	await _test_tutorial_never_registers_or_saves(app, mock, pose)
	await _finish(app)


func _install_mock_database(app: Control) -> Node:
	var real_client := app.get("database_client") as Node
	if is_instance_valid(real_client):
		var finished := Callable(app, "_on_database_request_finished")
		if real_client.has_signal("request_finished") and real_client.is_connected("request_finished", finished):
			real_client.disconnect("request_finished", finished)
		var lifecycle := Callable(app, "_on_database_local_service_status_changed")
		if real_client.has_signal("local_service_status_changed") and real_client.is_connected("local_service_status_changed", lifecycle):
			real_client.disconnect("local_service_status_changed", lifecycle)
		real_client.queue_free()
		await process_frame
	var mock := MOCK_DATABASE.new() as Node
	app.add_child(mock)
	app.set("database_client", mock)
	mock.connect("request_finished", Callable(app, "_on_database_request_finished"))
	mock.connect("local_service_status_changed", Callable(app, "_on_database_local_service_status_changed"))
	app.set("database_online", true)
	return mock


func _test_verified_existing_student(app: Control, mock: Node, pose: Node) -> void:
	mock.call("reset_calls")
	mock.set("registration_mode", "success")
	app.call("_return_to_main")
	await process_frame
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	var form := app.get("active_panel") as Control
	_expect(String(app.get("current_route")) == "student_setup", "Normal Play opens Student Setup")
	var id_edit := form.get("_student_id_edit") as LineEdit
	id_edit.text = "EXIST-001"
	form.call("apply_lookup_result", {
		"lookup_confirmed": true,
		"student_id": "EXIST-001",
		"student_name": "Existing Student",
		"grade_section": "Grade 4 - A",
	})
	_choose_setup(form)
	form.call("_continue")
	await process_frame
	_expect(String(app.get("current_route")) == "play_activity",
		"Verified existing student proceeds directly to activity selection")
	_expect((mock.get("register_calls") as Array).is_empty(),
		"Verified existing student is not registered again")
	_expect(bool((app.get("session_state") as Dictionary).get("student_lookup_connected", false)),
		"Verified lookup state survives Student Setup Continue")

	_set_synthetic_camera(pose)
	var chooser := app.get("active_panel") as Control
	(chooser.get("activity_buttons")["Catch the Word"] as Button).pressed.emit()
	(chooser.get("next_button") as Button).pressed.emit()
	await process_frame
	_expect(String(app.get("current_route")) == "calibration",
		"Normal Play selected activity enters the shared calibration scene")
	_expect(String((app.get("active_panel") as Control).get_script().resource_path) == "res://ui/vision/calibration/calibration.gd",
		"Normal Play uses the production shared calibration script")
	_expect(bool((app.get("session_state") as Dictionary).get("camera_requested", false)),
		"Normal Play carries an explicit camera request into calibration")
	_expect(int(pose.get("worker_pid")) <= 0,
		"Headless Play route never launches a physical camera/model worker")


func _test_new_student_registration_and_save(app: Control, mock: Node) -> void:
	mock.call("reset_calls")
	mock.set("registration_mode", "success")
	app.call("_return_to_main")
	await process_frame
	app.set("database_online", true)
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	var form := app.get("active_panel") as Control
	_fill_new_student(form, "NEW-001", "New Student", "Grade 5 - B")
	form.call("_continue")
	_expect(String(app.get("current_route")) == "student_setup",
		"New online student waits only for the asynchronous registration result")
	await process_frame
	await process_frame
	_expect(String(app.get("current_route")) == "play_activity",
		"Successful registration resumes normal Play navigation")
	_expect((mock.get("register_calls") as Array).size() == 1,
		"Normal Play registers a new student exactly once")
	_expect(bool((app.get("session_state") as Dictionary).get("student_lookup_connected", false)),
		"Successful registration marks the Play identity as verified")

	var state := app.get("session_state") as Dictionary
	state["activity"] = "Catch the Word"
	app.set("session_state", state)
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {
		"round_completed": true,
		"score": 240,
		"activity": "Catch the Word",
	})
	await process_frame
	await process_frame
	_expect((mock.get("complete_calls") as Array).size() == 1,
		"Verified normal Play saves one actually completed round")
	_expect(bool((app.get("session_state") as Dictionary).get("score_saved", false)),
		"Successful mock completion is reflected as a saved score")


func _test_registration_conflict_recovery(app: Control, mock: Node) -> void:
	mock.call("reset_calls")
	mock.set("registration_mode", "conflict")
	app.call("_return_to_main")
	await process_frame
	app.set("database_online", true)
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	var form := app.get("active_panel") as Control
	_fill_new_student(form, "EXIST-002", "Typed Name", "Grade 3 - C")
	form.call("_continue")
	await process_frame
	await process_frame
	_expect(String(app.get("current_route")) == "student_setup",
		"Existing-ID conflict stays on Student Setup for correction/lookup")
	var status := form.get("_database_status") as Label
	_expect(status != null and status.text.contains("ALREADY REGISTERED"),
		"Existing-ID conflict explains that lookup is required")
	_expect(not bool(app.get("database_registration_pending")),
		"Conflict clears the pending gate so the user can retry")

	form.call("apply_lookup_result", {
		"lookup_confirmed": true,
		"student_id": "EXIST-002",
		"student_name": "Typed Name",
		"grade_section": "Grade 3 - C",
	})
	form.call("_continue")
	await process_frame
	_expect(String(app.get("current_route")) == "play_activity",
		"Verified lookup recovers from an existing-ID registration conflict")
	_expect((mock.get("register_calls") as Array).size() == 1,
		"Conflict recovery does not issue a second redundant registration")


func _test_registration_timeout_offline_play(app: Control, mock: Node) -> void:
	mock.call("reset_calls")
	mock.set("registration_mode", "hold")
	app.call("_return_to_main")
	await process_frame
	app.set("database_online", true)
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	var form := app.get("active_panel") as Control
	_fill_new_student(form, "SLOW-001", "Slow Database", "Grade 6 - D")
	form.call("_continue")
	_expect(bool(app.get("database_registration_pending")),
		"No-response mock creates a pending registration without freezing the process")
	await create_timer(2.0).timeout
	await process_frame
	_expect(String(app.get("current_route")) == "play_activity",
		"Real registration watchdog releases Play to the offline-valid activity route")
	_expect(not bool(app.get("database_registration_pending")),
		"Timed-out registration gate is cleared")
	_expect(not (mock.get("cancelled_requests") as Array).is_empty(),
		"Timed-out mock registration request is cancelled")
	_expect(not bool((app.get("session_state") as Dictionary).get("student_lookup_connected", true)),
		"Timed-out identity remains unverified for persistence safety")
	var delayed_info := ((mock.get("register_calls") as Array)[0]["info"] as Dictionary).duplicate(true)
	app.call("_on_database_request_finished", delayed_info, {
		"ok": true,
		"data": {"student": {"student_id": "SLOW-001"}},
		"error": "",
	})
	await process_frame
	_expect(String(app.get("current_route")) == "play_activity"
		and not bool((app.get("session_state") as Dictionary).get("student_lookup_connected", true)),
		"Late registration success cannot verify or reroute a timed-out offline Play session")

	var before_saves := (mock.get("complete_calls") as Array).size()
	var state := app.get("session_state") as Dictionary
	state["activity"] = "Catch the Word"
	app.set("session_state", state)
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {
		"round_completed": true,
		"score": 180,
		"activity": "Catch the Word",
	})
	await process_frame
	_expect((mock.get("complete_calls") as Array).size() == before_saves,
		"Offline/unverified Play never writes a score under an unverified student ID")


func _test_results_retry_leaderboard_retention_and_explicit_delete(app: Control, mock: Node) -> void:
	mock.call("reset_calls")
	mock.set("registration_mode", "success")
	mock.set("completion_mode", "hold")
	app.call("_return_to_main")
	await process_frame
	app.set("database_online", true)
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	var form := app.get("active_panel") as Control
	_fill_new_student(form, "KEEP-001", "Persistent Student", "Grade 5 - Keep")
	form.call("_continue")
	await process_frame
	await process_frame
	_expect(String(app.get("current_route")) == "play_activity",
		"Persistent Play student finishes asynchronous registration before selection")
	var registration_count := (mock.get("register_calls") as Array).size()
	var state := app.get("session_state") as Dictionary
	state["activity"] = "Catch the Word"
	app.set("session_state", state)
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {
		"round_completed": true,
		"score": 420,
		"activity": "Catch the Word",
	})
	await process_frame
	_expect((mock.get("complete_calls") as Array).size() == 1,
		"Completed verified Play issues exactly one persistence write")
	_expect((mock.get("persisted_scores") as Dictionary).size() == 1,
		"Completed Play data exists independently of its delayed UI callback")
	var results := app.get("active_panel") as Control
	var retry := results.get_node_or_null("%RetryButton") as Button
	_expect(retry != null, "Results exposes its real Retry control")
	if retry != null:
		retry.pressed.emit()
		await process_frame
	_expect(String(app.get("current_route")) == "student_setup",
		"Results Retry returns through real Student Setup routing")
	_expect(bool((app.get("session_state") as Dictionary).get("student_lookup_connected", false)),
		"Results Retry preserves the verified Play identity")
	var retry_form := app.get("active_panel") as Control
	retry_form.call("_continue")
	await process_frame
	_expect(String(app.get("current_route")) == "play_activity",
		"Verified Results Retry proceeds without another registration")
	_expect((mock.get("register_calls") as Array).size() == registration_count,
		"Results Retry does not re-register the same verified student")
	mock.call("release_held_completions")
	await process_frame
	await process_frame
	_expect((mock.get("persisted_scores") as Dictionary).size() == 1,
		"Late completed-score callback cannot clean up persisted Play data")
	app.call("_return_to_main")
	await process_frame
	_expect((mock.get("persisted_scores") as Dictionary).size() == 1,
		"Returning to Main Menu never cleans up a completed Play score")

	app.call("_on_panel_requested", "leaderboard", {})
	await process_frame
	await process_frame
	_expect(String(app.get("current_route")) == "leaderboard",
		"Play data can be reopened through the real Leaderboard route")
	var board := app.get("active_panel") as Control
	var board_context := board.get("_context") as Dictionary
	var rows: Array = board_context.get("leaderboard_rows", [])
	_expect(rows.size() == 1 and String((rows[0] as Dictionary).get("student_id", "")) == "KEEP-001"
		and int((rows[0] as Dictionary).get("score", -1)) == 420,
		"Leaderboard returns the persisted completed Play record after Retry/navigation")
	_expect((mock.get("delete_calls") as Array).is_empty(),
		"Normal Play, Results Retry and Leaderboard viewing never invoke data deletion")

	app.call("_on_database_delete_all_requested", "DELETE ALL DATA")
	await process_frame
	await process_frame
	await process_frame
	_expect((mock.get("delete_calls") as Array).size() == 1,
		"Only the explicit teacher delete confirmation invokes delete-all")
	_expect((mock.get("persisted_scores") as Dictionary).is_empty(),
		"Explicit teacher delete removes the persisted mock score")
	board = app.get("active_panel") as Control
	board_context = board.get("_context") as Dictionary
	rows = board_context.get("leaderboard_rows", [])
	_expect(rows.is_empty(), "Leaderboard refreshes empty only after explicit teacher deletion")


func _test_human_plane_restart_recalibrates_after_lock_change(app: Control, mock: Node, pose: Node) -> void:
	mock.call("reset_calls")
	app.call("_return_to_main")
	await process_frame
	app.set("database_online", true)
	_set_synthetic_plane_camera(pose, 11)
	var verified_state := {
		"entry_source": "play",
		"guided_tutorial": false,
		"student_id": "PLANE-001",
		"student_name": "Plane Student",
		"grade_section": "Grade 4 - Flight",
		"student_lookup_connected": true,
		"database_connected": true,
		"activity": "Human Plane",
		"game_style": "Noun",
		"topic": "Noun",
		"game_mode": "Seconds",
		"difficulty": "Easy",
		"camera_live": true,
		"camera_requested": true,
		"calibration_live": true,
		"calibration_measured": true,
	}
	app.set("session_state", verified_state.duplicate(true))
	app.call("_on_panel_requested", "gameplay", {"start_countdown": true})
	await process_frame
	app.call("_on_panel_requested", "pause", {})
	await process_frame
	var pause := app.get("active_panel") as Control
	# Even a valid fresh SOLO camera pose does not bypass calibration on a
	# teacher-initiated NEW round. In-game absence recovery is separate.
	_set_synthetic_plane_camera(pose, 11)
	pause.call("_restart")
	await process_frame
	_expect(String(app.get("current_route")) == "calibration",
		"Human Plane teacher Restart always opens fresh calibration for a NEW round")
	_expect(bool((app.get("session_state") as Dictionary).get("student_lookup_connected", false)),
		"Human Plane Restart preserves verified Play save eligibility")
	_expect(not bool((pose.get("calibration") as Dictionary).get("valid", false)),
		"Teacher Restart invalidates the previous round's neutral calibration")
	var calibration := app.get("active_panel") as Control
	calibration.call("_continue_flow", false)
	await process_frame
	_expect(String(app.get("current_route")) == "calibration",
		"New round cannot bypass required neutral hold with old camera pose")
	# Simulate an independently completed fresh calibration before the next
	# teacher Restart scenario. No camera or live score database is used.
	_set_synthetic_plane_camera(pose, 22)
	app.call("_on_panel_requested", "gameplay", {"start_countdown": true,
		"calibration_live": true, "calibration_measured": true})
	await process_frame
	app.call("_on_panel_requested", "pause", {})
	await process_frame
	pause = app.get("active_panel") as Control
	pause.call("_restart")
	await process_frame
	_expect(String(app.get("current_route")) == "calibration",
		"Second teacher Restart again requires a NEW physical neutral hold despite tracker ID")
	_expect(bool((app.get("session_state") as Dictionary).get("student_lookup_connected", false)),
		"Repeated Human Plane Restart preserves verified database identity")
	calibration = app.get("active_panel") as Control
	calibration.call("_continue_flow", false)
	await process_frame
	_expect(String(app.get("current_route")) == "calibration",
		"Another new round cannot bypass physical neutral calibration")
	_expect((mock.get("register_calls") as Array).is_empty()
		and (mock.get("complete_calls") as Array).is_empty(),
		"Teacher Restart performs no extra student registration or score write")


func _test_tutorial_never_registers_or_saves(app: Control, mock: Node, pose: Node) -> void:
	mock.call("reset_calls")
	mock.set("registration_mode", "success")
	app.call("_return_to_main")
	await process_frame
	app.set("database_online", true)
	app.call("_on_panel_requested", "tutorial_home", {})
	await process_frame
	var tutorial := app.get("active_panel") as Control
	(tutorial.get_node("TutorialStage/StartButton") as Button).pressed.emit()
	await process_frame
	var chooser := app.get("active_panel") as Control
	(chooser.get("activity_buttons")["Human Plane"] as Button).pressed.emit()
	(chooser.get("next_button") as Button).pressed.emit()
	await process_frame
	var form := app.get("active_panel") as Control
	_fill_new_student(form, "TUTORIAL-001", "Practice Student", "Grade 2 - E")
	_set_synthetic_camera(pose)
	form.call("_continue")
	await process_frame
	_expect(String(app.get("current_route")) == "calibration",
		"Tutorial reaches the same shared calibration route after setup")
	_expect(String((app.get("active_panel") as Control).get_script().resource_path) == "res://ui/vision/calibration/calibration.gd",
		"Tutorial and Play share the exact calibration implementation")
	_expect((mock.get("register_calls") as Array).is_empty(),
		"Tutorial never registers a student")
	_expect(String((app.get("session_state") as Dictionary).get("entry_source", "")) == "tutorial",
		"Tutorial entry source remains practice-only through calibration")

	var state := app.get("session_state") as Dictionary
	state["activity"] = "Human Plane"
	app.set("session_state", state)
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", {
		"round_completed": true,
		"score": 999,
		"activity": "Human Plane",
	})
	await process_frame
	_expect((mock.get("complete_calls") as Array).is_empty(),
		"Tutorial completed rounds never call score persistence")
	_expect(not bool((app.get("session_state") as Dictionary).get("score_saved", false)),
		"Tutorial results remain explicitly unsaved")
	_expect((mock.get("delete_calls") as Array).is_empty()
		and (mock.get("persisted_scores") as Dictionary).is_empty(),
		"Tutorial never invokes database cleanup/delete or creates persistent score data")
	app.call("_return_to_main")
	await process_frame
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	var fresh_play := app.get("session_state") as Dictionary
	_expect(String(fresh_play.get("entry_source", "")) == "play"
		and not bool(fresh_play.get("guided_tutorial", false)),
		"Fresh Main Menu Play clears Tutorial practice-only routing state")
	var fresh_form := app.get("active_panel") as Control
	_expect((fresh_form.get("_student_id_edit") as LineEdit).text.is_empty()
		and (fresh_form.get("_name_edit") as LineEdit).text.is_empty()
		and (fresh_form.get("_grade_edit") as LineEdit).text.is_empty(),
		"Fresh Play after Tutorial does not inherit Tutorial student fields")


func _fill_new_student(form: Control, student_id: String, student_name: String, grade: String) -> void:
	(form.get("_student_id_edit") as LineEdit).text = student_id
	(form.get("_name_edit") as LineEdit).text = student_name
	(form.get("_grade_edit") as LineEdit).text = grade
	_choose_setup(form)


func _choose_setup(form: Control) -> void:
	form.call("_select_style", "Noun")
	form.call("_select_mode", "Seconds")
	form.call("_select_difficulty", "Easy")


func _set_synthetic_camera(pose: Node) -> void:
	pose.active = true
	pose.set_process(false)
	pose.worker_pid = -1
	pose.player_x = 0.5
	pose.last_pose_ms = Time.get_ticks_msec()
	pose.current_status = {"state": "tracking", "pose": true, "camera": true}


func _set_synthetic_plane_camera(pose: Node, locked_id: int) -> void:
	pose.active = true
	pose.set_process(false)
	pose.worker_pid = -1
	pose.player_x = 0.5
	pose.last_pose_ms = Time.get_ticks_msec()
	pose.set("_last_packet_ms", Time.get_ticks_msec())
	pose.set("_ever_tracked", true)
	pose.current_status = {
		"state": "tracking",
		"pose": true,
		"camera": true,
		"people": 1,
		"camera_frame_age_ms": 20,
		"lock_state": "locked",
		"physical_track_id": locked_id,
		"plane_steering_valid": true,
		"plane_steering": 0.5,
		"hand_observation_valid": true,
	}
	pose.calibration = {
		"valid": true,
		"mode": "plane_stationary",
		"center": 0.5,
	}
	pose.plane_calibration = {
		"valid": true,
		"mode": "plane_stationary",
		"center": 0.5,
		"steering_mode": "centered_torso_x_one_wrist",
		"sensitivity": 0.2,
		"deadzone": 0.02,
		"neutral_noise": 0.0,
		"neutral_only": true,
		"camera_center_x": 0.5,
	}


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("PLAY ROUTE FAIL: ", message)


func _finish(app: Control) -> void:
	var pose := root.get_node_or_null("PoseService")
	if pose != null:
		pose.stop_camera()
	if is_instance_valid(app):
		app.call("_return_to_main")
		await process_frame
		# Completed mock Play scores may have triggered Results' low-score
		# encouragement MP3. Drain the same audio players as the real Quit path
		# while this menu still owns them, before freeing the test scene.
		await app.call("prepare_for_shutdown")
		_expect(bool(app.get("_shutdown_audio_drain_complete")),
			"Play persistence fixture drains audio before exit")
		app.queue_free()
		await process_frame
		await process_frame
	print("PLAY NAVIGATION/PERSISTENCE: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
