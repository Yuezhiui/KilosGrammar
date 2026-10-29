extends SceneTree

# Once-per-round calibration / unlimited same-round recovery. Synthetic,
# authenticated, freshly decoded camera packets only: NO webcam, YOLO process
# or live database. Run with Godot --headless --path . --script res://tools/test_gameplay_long_absence_recalibration.gd
const GAMEPLAY := "res://ui/play/gameplay/gameplay.tscn"
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const ABSENCES := [5.0, 15.0, 60.0]
var pose: Node
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(35.0).timeout
	_check(false, "Recovery fixture exceeded 35s watchdog")
	_finish()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload exists")
	if pose == null:
		_finish()
		return
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(false)
	for activity in ACTIVITIES:
		for tutorial in [false, true]:
			await _test_round(activity, tutorial)
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _test_round(activity: String, tutorial: bool) -> void:
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(false)
	var udp := PacketPeerUDP.new()
	_check(udp.bind(0, "127.0.0.1") == OK,
		_ctx(activity, tutorial, "mock localhost UDP camera receiver binds"))
	pose.peer = udp
	pose.worker_pid = OS.get_process_id()
	pose.session_token = "synthetic-initial-worker"
	pose.active = true
	_send_pose(true, 1, 71, 0.5, 1)
	if activity == "Human Plane":
		_check(bool(pose.set_stationary_plane_calibration(0.5, 71, 0.5, 0.01)),
			_ctx(activity, tutorial, "initial single neutral calibration succeeds"))
	else:
		_check(bool(pose.set_calibration(0.2, 0.5, 0.8, 71)),
			_ctx(activity, tutorial, "initial three-hold calibration succeeds"))
	var calibrated_before: Dictionary = pose.calibration.duplicate(true)
	var wrapper := (load(GAMEPLAY) as PackedScene).instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({
		"activity": activity, "camera_live": true, "keyboard_mode": false,
		"guided_tutorial": tutorial, "entry_source": "tutorial" if tutorial else "play",
		"calibration_measured": true, "start_countdown": true,
		"topic": "Noun", "game_mode": "Seconds", "difficulty": "Easy",
		"student_id": "SYNTHETIC-STUDENT", "student_lookup_connected": not tutorial,
		"database_connected": not tutorial,
	})
	await process_frame
	await process_frame
	var game := wrapper.get("active_game") as Control
	_check(game != null, _ctx(activity, tutorial, "real minigame mounted"))
	if game == null:
		pose.worker_pid = -1
		wrapper.queue_free()
		await process_frame
		return
	var notice := wrapper.get_node_or_null("TrackingNoticeLayer/TrackingNotice") as Control
	var title := notice.get_node_or_null("Title") as Label
	_check(bool(wrapper.get("_countdown_requires_locked_pose")),
		_ctx(activity, tutorial, "camera countdown requires fresh SOLO pose"))
	var routes: Array[String] = []
	wrapper.requested.connect(func(route: String, _data: Dictionary) -> void: routes.append(route))
	if tutorial:
		wrapper.call("_on_spotlight_finished")
	await process_frame
	# Countdown must not advance without one trusted live person.
	_send_pose(false, 2, 71)
	wrapper.call("_process", 0.016)
	var timer := wrapper.get("countdown_timer") as Timer
	_check(timer != null and timer.is_stopped() and game.process_mode == Node.PROCESS_MODE_DISABLED,
		_ctx(activity, tutorial, "two people pause 3-2-1 and entire game"))
	var current_count := int(wrapper.get("countdown_value"))
	wrapper.call("_process", 60.0)
	_check(timer != null and timer.is_stopped()
		and int(wrapper.get("countdown_value")) == current_count,
		_ctx(activity, tutorial, "60s of a crowd cannot advance pre-round countdown"))
	var hint := (wrapper.get("countdown_panel") as Control).get_node("MovementHint") as Label
	_check(hint.text == "ONLY ONE PLAYER!",
		_ctx(activity, tutorial, "two-person countdown shows matching hold instruction"))
	_send_pose(false, 0, 71)
	wrapper.call("_process", 60.0)
	_check(timer != null and timer.is_stopped()
		and int(wrapper.get("countdown_value")) == current_count
		and hint.text == "COME BACK INTO THE CAMERA!",
		_ctx(activity, tutorial, "60s empty camera cannot consume pre-round 3-2-1"))
	_send_pose(true, 1, 71, 0.5, 1)
	wrapper.call("_process", 0.016)
	_check(timer != null and not timer.is_stopped(),
		_ctx(activity, tutorial, "single fresh player resumes 3-2-1"))
	for _tick in range(2):
		wrapper.call("_on_countdown_tick")
	_send_pose(false, 2, 71)
	wrapper.call("_on_countdown_tick")
	_check(String(wrapper.get("guided_stage")) == "countdown"
		and bool(wrapper.get("_countdown_waiting_for_pose"))
		and game.process_mode == Node.PROCESS_MODE_DISABLED,
		_ctx(activity, tutorial, "2+ detected at GO cannot release countdown or gameplay"))
	_send_pose(true, 1, 71, 0.5, 1)
	wrapper.call("_process", 0.016)
	_check(String(wrapper.get("guided_stage")) == ""
		and game.process_mode == Node.PROCESS_MODE_INHERIT,
		_ctx(activity, tutorial, "GO releases original game once"))
	# Stop the minigame's own processing only for deterministic fixture
	# inspection: its process_mode still reflects whether game would tick.
	game.set_process(false)
	var initial_score := _score(game)
	var initial_lives := _lives(game)
	var initial_time := _remaining(game)
	var token_before := String(pose.session_token)
	# For each 5, 15, and 60s absence test both 0 and 2+ people, including
	# ByteTrack numeric ID churn and an entire worker-token replacement.
	for seconds: float in ABSENCES:
		for count in [0, 2, 3]:
			_send_pose(false, count, 71)
			wrapper.call("_process", seconds)
			_check(bool(wrapper.get("tracking_suspended"))
				and game.process_mode == Node.PROCESS_MODE_DISABLED,
				_ctx(activity, tutorial, "%ss / %d people freeze game immediately" % [seconds, count]))
			_check(notice.visible and title.text == (
				"COME BACK INTO THE CAMERA!" if count == 0 else "ONLY ONE PLAYER!"),
				_ctx(activity, tutorial, "%ss / %d people show correct overlay" % [seconds, count]))
			_check(not bool(wrapper.get("last_pose_valid"))
				and is_equal_approx(_score(game), initial_score)
				and is_equal_approx(_lives(game), initial_lives)
				and is_equal_approx(_remaining(game), initial_time),
				_ctx(activity, tutorial, "%ss / %d people clear steering and preserve round stats" % [seconds, count]))
			if activity == "Human Plane":
				_check(not bool(game.get("airplane_pose_active"))
					and is_zero_approx(float(game.get("_bank_input")))
					and is_zero_approx(float(game.get("_bank_velocity"))),
					_ctx(activity, tutorial, "absence revokes arm bank and ghost velocity"))
			# Even pose=true is not authoritative in a crowded frame.
			_send_pose(true, 2, 99, 0.84, 4)
			wrapper.call("_process", 0.016)
			_check(game.process_mode == Node.PROCESS_MODE_DISABLED and notice.visible,
				_ctx(activity, tutorial, "crowded pose cannot bypass freeze"))
			# Simulate worker restart after the longest gap. Neither the replaced
			# session token nor its newly assigned numeric tracker requires CALIB.
			if seconds >= 60.0:
				pose.session_token = "new-worker-session"
				_send_pose(false, 0, 99)
				wrapper.call("_process", 0.016)
				_check(game.process_mode == Node.PROCESS_MODE_DISABLED,
					_ctx(activity, tutorial, "worker restart remains frozen without fresh pose"))
			_send_pose(true, 1, 71 if seconds == 5.0 else 99,
				0.74, 5 if seconds >= 15.0 else 1)
			wrapper.call("_process", 0.016)
			_check(not bool(wrapper.get("tracking_suspended"))
				and game.process_mode == Node.PROCESS_MODE_INHERIT
				and not notice.visible,
				_ctx(activity, tutorial, "%ss / %d people return fresh solo resumes SAME round" % [seconds, count]))
			if activity == "Human Plane":
				var recovered_x := float(game.get("plane_x_norm"))
				var signed_bank := float(pose.normalized_plane_steering())
				_check(bool(wrapper.get("last_pose_valid"))
					and bool(game.get("airplane_pose_active"))
					and pose.has_stationary_plane_pose()
					and signed_bank > 0.0
					and is_equal_approx(float(game.get("_bank_input")), signed_bank)
					and is_equal_approx(float(game.get("target_x_norm")), recovered_x),
					_ctx(activity, tutorial, "fresh wrist bank arms signed velocity without teleport"))
				game.call("_update_plane_motion", 0.1)
				_check(float(game.get("plane_x_norm")) > recovered_x
					and float(game.get("plane_x_norm")) - recovered_x < 0.1,
					_ctx(activity, tutorial, "fresh right arm bank moves smoothly, not to torso target"))
			else:
				_check(bool(wrapper.get("last_pose_valid"))
					and is_equal_approx(float(wrapper.get("smooth_x")), float(pose.normalized_body_x())),
					_ctx(activity, tutorial, "recovered body x starts from fresh pose, not stale steering"))
			_check(pose.calibration == calibrated_before and routes.is_empty()
				and is_equal_approx(_score(game), initial_score)
				and is_equal_approx(_lives(game), initial_lives)
				and is_equal_approx(_remaining(game), initial_time),
				_ctx(activity, tutorial, "same round, calibration, score/lives/time unchanged; NO route"))
	_check(pose.active and String(pose.session_token) != token_before and routes.is_empty(),
		_ctx(activity, tutorial, "worker restart cannot automatically route to calibration"))
	pose.worker_pid = -1 # NEVER let wrapper _exit_tree kill mock Godot worker PID.
	wrapper.queue_free()
	await process_frame
	await process_frame


func _send_pose(present: bool, people: int, id: int,
		x: float = 0.5, epoch: int = 1) -> void:
	pose.call("_apply_pose_packet", {
		"token": String(pose.session_token), "kind": "pose",
		"state": "tracking", "camera": true, "camera_phase": "tracking",
		"pose": present, "people": people, "x": x if present else -1.0,
		"locked_id": id if present else -1, "lock_state": "locked" if present else "lost",
		"camera_frame_age_ms": 30, "tracking_epoch": epoch,
		"plane_bank_valid": present and people == 1,
		"plane_bank": clampf((x - 0.5) * 2.0, -1.0, 1.0),
		"hand_observation_valid": present,
	}, Time.get_ticks_msec())


func _score(game: Control) -> float:
	return float(game.get("score")) if game.get("score") != null else 0.0


func _lives(game: Control) -> float:
	return float(game.get("lives")) if game.get("lives") != null else 0.0


func _remaining(game: Control) -> float:
	return float(game.get("time_remaining")) if game.get("time_remaining") != null else 0.0


func _ctx(activity: String, tutorial: bool, detail: String) -> String:
	return ("%s %s: %s" % [activity, "Tutorial" if tutorial else "Play", detail])


func _check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures.append(name)
		printerr("FAIL SAME-ROUND CAMERA RECOVERY: ", name)


func _finish() -> void:
	print("GAMEPLAY SAME-ROUND CAMERA RECOVERY: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
