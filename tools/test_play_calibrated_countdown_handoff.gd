extends SceneTree

# Play-only Catch handoff: synthetic real-ID calibration, no webcam or DB.
# Godot --headless --path . --script res://tools/test_play_calibrated_countdown_handoff.gd
const TRACK_ID := 217
const OTHER_ID := 218

var checks := 0
var failures: Array[String] = []
var pose: Node


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(20.0).timeout
	failures.append("Test did not finish in 20 seconds")
	_finish()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload exists")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	pose.session_token = ""
	_set_student(TRACK_ID, 0.5)
	_check(bool(pose.set_calibration(0.2, 0.5, 0.8, TRACK_ID)),
		"Three-position calibration binds the original student")
	var wrapper := (load("res://ui/play/gameplay/gameplay.tscn") as PackedScene).instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrapper.set_context({"activity": "Catch the Word", "camera_live": true,
		"calibration_live": true, "calibration_measured": true,
		"start_countdown": true, "guided_tutorial": false, "entry_source": "play",
		"topic": "Noun", "difficulty": "Easy", "game_mode": "Seconds"})
	await process_frame
	await process_frame
	var game := wrapper.get("active_game") as Control
	_check(game != null and game.process_mode == Node.PROCESS_MODE_DISABLED,
		"Actual Catch scene is paused until countdown completes")
	if game == null:
		wrapper.queue_free()
		await process_frame
		_cleanup()
		return
	_check(bool(wrapper.get("_countdown_requires_locked_pose")),
		"Play countdown requires the calibrated student's track")
	for _tick in range(2):
		wrapper.call("_on_countdown_tick")
	_check(int(wrapper.get("countdown_value")) == 1,
		"3-2-1 countdown reaches final second")
	_set_student(OTHER_ID, 0.72, 2)
	wrapper.call("_on_countdown_tick")
	_check(String(wrapper.get("guided_stage")) == "countdown" and
		bool(wrapper.get("_countdown_waiting_for_pose")) and
		game.process_mode == Node.PROCESS_MODE_DISABLED,
		"Two detected students cannot release the game at GO")
	var countdown := wrapper.get("countdown_panel") as Control
	var hint := countdown.get_node_or_null("MovementHint") as Label
	_check(hint != null and hint.text.contains("TRACKING PAUSED"),
		"Player sees why countdown cannot start")
	var before_time := float(game.get("time_remaining"))
	await process_frame
	_check(is_equal_approx(float(game.get("time_remaining")), before_time),
		"Invalid handoff does not consume round time")
	_set_student(OTHER_ID, 0.80)
	wrapper.call("_process", 0.016)
	_check(String(wrapper.get("guided_stage")) == "" and
		game.process_mode == Node.PROCESS_MODE_INHERIT and
		not bool(wrapper.get("_countdown_waiting_for_pose")),
		"Fresh SOLO tracker after crowd releases the same waiting game")
	_check(bool(game.get("body_input_active")),
		"Fresh SOLO pose controls Catch after GO regardless of temporary ID")
	var initial_x := float(game.get("basket_x"))
	game.call("_process", 0.25)
	_check(float(game.get("basket_x")) > initial_x + 1.0,
		"Catch basket moves right from freshly recovered SOLO pose")
	wrapper.queue_free()
	await process_frame
	await process_frame
	await _check_worker_restart_keeps_round()
	_cleanup()


func _check_worker_restart_keeps_round() -> void:
	pose.session_token = "test_camera_session_original"
	_set_student(TRACK_ID, 0.5)
	pose.set_calibration(0.2, 0.5, 0.8, TRACK_ID)
	var wrapper := (load("res://ui/play/gameplay/gameplay.tscn") as PackedScene).instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({"activity": "Catch the Word", "camera_live": true,
		"calibration_measured": true, "start_countdown": true,
		"entry_source": "play", "guided_tutorial": false,
		"student_id": "SYNTHETIC-ONLY", "topic": "Noun", "game_mode": "Seconds",
		"score": 999})
	await process_frame
	var requests: Array[Dictionary] = []
	wrapper.requested.connect(func(route: String, payload: Dictionary) -> void:
		requests.append({"route": route, "payload": payload.duplicate(true)}))
	for _tick in range(3):
		wrapper.call("_on_countdown_tick")
	var game := wrapper.get("active_game") as Control
	_check(game != null and game.process_mode == Node.PROCESS_MODE_INHERIT,
		"One live solo player starts the existing 3-2-1 game")
	pose.session_token = "test_camera_session_restarted"
	_set_student(OTHER_ID, 0.5, 0)
	wrapper.call("_process", 0.016)
	_check(game.process_mode == Node.PROCESS_MODE_DISABLED
		and bool(wrapper.get("tracking_suspended")),
		"Worker restart freezes same round while camera sees no child")
	_set_student(OTHER_ID, 0.65)
	wrapper.call("_process", 0.016)
	_check(game.process_mode == Node.PROCESS_MODE_INHERIT
		and not bool(wrapper.get("tracking_suspended"))
		and requests.is_empty(),
		"Fresh solo post-restart resumes SAME game without recalibration route")
	_check(bool(pose.calibration.get("valid", false))
		and is_equal_approx(float(pose.calibration.get("left", -1)), 0.2)
		and is_equal_approx(float(pose.calibration.get("center", -1)), 0.5)
		and is_equal_approx(float(pose.calibration.get("right", -1)), 0.8)
		and not pose.calibration.has("locked_id"),
		"Worker restart keeps once-per-round positions but no stale ByteTrack ID")
	wrapper.queue_free()
	await process_frame
	await process_frame


func _set_student(student_id: int, x: float, count: int = 1) -> void:
	pose.active = true
	pose.player_x = x if count == 1 else -1.0
	pose.last_pose_ms = Time.get_ticks_msec()
	pose.set("_last_packet_ms", Time.get_ticks_msec())
	pose.set("_ever_tracked", true)
	pose.current_status = {"state": "tracking", "pose": count == 1, "camera": true,
		"people": count, "lock_state": "locked" if count == 1 else "lost",
		"locked_id": student_id, "camera_frame_age_ms": 20,
		"x": x if count == 1 else -1.0, "hand_observation_valid": count == 1}


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("FAIL PLAY COUNTDOWN HANDOFF: ", description)


func _cleanup() -> void:
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _finish() -> void:
	print("PLAY COUNTDOWN HANDOFF: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
