extends SceneTree

# No physical webcam is opened. Use source-fresh, epoch-bound foreground
# packets and a localhost mock transport to prove that spectators/pose loss
# NEVER globally pause a live round, while invalid inputs cannot steer.
const WRAPPER := "res://ui/play/gameplay/gameplay.tscn"
const SELECTION := "res://ui/play/activity/play_activity.tscn"
const GAMES := ["Catch the Word", "Balloon Popping", "Human Plane"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := root.get_node_or_null("PoseService")
	_check(service != null, "Live pose autoload exists")
	if service == null:
		quit(1)
		return
		# The worker must not auto-restart during synthetic pose-packet injection.
		# This test never opens the real webcam or launches Python.
	service.set_process(false)
	var selection := (load(SELECTION) as PackedScene).instantiate() as Control
	_check(selection.get_node_or_null("LayoutMargins/Content/Footer/PlayKeyboardButton") == null,
		"Game selection has no keyboard fallback button")
	_check(selection.get_node_or_null("LayoutMargins/Content/GameRow/GameDetail/DetailContent/KeyboardHint") == null,
		"Game selection has no keyboard instructions")
	selection.free()
	for viewport_size in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = viewport_size
		await process_frame
		for activity in GAMES:
			await _check_game(activity, service)
	service.worker_pid = -1
	service.call("stop_camera")
	service.set_process(true)
	for failure in failures:
		printerr("FAIL CAMERA RECOVERY: ", failure)
	print("CAMERA-ONLY TRACKING RECOVERY: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


func _check_game(activity: String, service: Node) -> void:
	# Strict camera occupancy requires a live authenticated localhost transport.
	service.worker_pid = -1
	service.stop_camera()
	var udp := PacketPeerUDP.new()
	_check(udp.bind(0, "127.0.0.1") == OK, "localhost mock camera socket binds")
	service.peer = udp
	service.worker_pid = OS.get_process_id()
	service.session_token = "recovery-mock-session"
	service.active = true
	var student_id := 71
	_send(service, activity, 1, true, student_id, 0.5)
	if activity == "Human Plane":
		# Human Plane now uses ONE neutral hold + fresh two-wrist bank input;
		# a historical torso-only packet cannot authorize steering.
		_check(bool(service.set_stationary_plane_calibration(0.5, -1, 0.5, 0.01)),
			activity + ": authentic stationary neutral calibration accepted")
	else:
		_check(bool(service.set_calibration(0.2, 0.5, 0.8)),
			activity + ": measured body calibration accepted")
	var saved_calibration: Dictionary = service.calibration.duplicate(true)
	var wrapper := (load(WRAPPER) as PackedScene).instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_process(false) # Tick the wrapper manually for deterministic QA.
	wrapper.set_context({
		"activity": activity, "camera_live": true, "keyboard_mode": false,
		"topic": "Noun", "game_mode": "Seconds", "difficulty": "Easy",
		"calibration_measured": true, "start_countdown": true
	})
	await process_frame
	await process_frame
	var game := wrapper.get_node_or_null("ActiveMiniGame") as Control
	var notice := wrapper.get_node_or_null("TrackingNoticeLayer/TrackingNotice") as Control
	_check(game != null, activity + ": actual game scene is present")
	_check(notice != null and not notice.visible, activity + ": notice exists but begins hidden")
	if game == null or notice == null:
		service.worker_pid = -1 # Even failure cleanup must not kill Godot itself.
		wrapper.queue_free()
		await process_frame
		return
	var notice_rect := notice.get_global_rect()
	_check(notice_rect.position.x >= 0.0 and notice_rect.position.y >= 0.0
		and notice_rect.end.x <= root.size.x and notice_rect.end.y <= root.size.y,
		activity + ": tracking instruction stays inside the viewport")
	# A camera Play must complete its 3-2-1 with a VERIFIED measured pose
	# before these runtime presence rules apply. Do not inspect a frozen
	# pre-GO game as if a spectator had automatically paused it.
	for _count in range(3):
		wrapper.call("_on_countdown_tick")
	_check(String(wrapper.guided_stage) == "" and game.process_mode == Node.PROCESS_MODE_INHERIT,
		activity + ": authenticated camera GO starts actual gameplay")
	game.set_process(false)
	wrapper.call("_process", 0.02)
	_check(bool(wrapper.get("last_pose_valid")), activity + ": accepts verified fresh calibrated pose")
	_check(_has_steering_authority(game, activity),
		activity + ": verified foreground player has active camera input")
	var initial_scene_id: int = game.get_instance_id()
	var original_time: float = float(game.get("time_remaining"))
	var original_score: int = int(game.get("score"))

	# An actual empty source frame immediately revokes that player's input,
	# but never freezes the shared game, changes screens or shows an
	# obstructing ONE PLAYER notice.
	_send(service, activity, 0, false, -1)
	wrapper.call("_process", 0.02)
	_check(_no_global_pause(wrapper, game, notice),
		activity + ": empty frame does not pause/interrupt live gameplay")
	_check(not bool(wrapper.get("last_pose_valid")) and _input_revoked(game, activity),
		activity + ": lost player immediately loses steering/gesture authority")
	_check(service.calibration == saved_calibration,
		activity + ": saved calibration survives genuine empty frame")
	# Simulate real ticking of the still-enabled minigame rather than
	# trusting process_mode or a hidden pause widget alone.
	game.call("_process", 0.10)
	_check(float(game.get("time_remaining")) < original_time and
		int(game.get("score")) == original_score,
		activity + ": game clock advances without ghost points while pose absent")
	_send(service, activity, 0, false, -1)
	wrapper.call("_process", 0.02)
	_check(_no_global_pause(wrapper, game, notice) and _input_revoked(game, activity),
		activity + ": repeated missing frames keep game running without stale movement")

	_send(service, activity, 1, false, -1)
	wrapper.call("_process", 0.02)
	_check(_no_global_pause(wrapper, game, notice) and _input_revoked(game, activity),
		activity + ": one unverified bystander cannot steer or pause game")
	# Two raw people are normal when one is a distant spectator: one
	# epoch-bound foreground child remains eligible for steering.
	_send(service, activity, 2, true, student_id, 0.65, 1)
	wrapper.call("_process", 0.02)
	_check(_no_global_pause(wrapper, game, notice) and
		bool(wrapper.get("last_pose_valid")) and _has_steering_authority(game, activity),
		activity + ": remote spectator does not interrupt verified foreground child")
	# Two similarly near people are ambiguous. Neither a visitor's raw
	# pose nor a retained steering command may control the student.
	_send(service, activity, 2, false, -1, 0.65, 2, true)
	wrapper.call("_process", 0.02)
	_check(_no_global_pause(wrapper, game, notice) and _input_revoked(game, activity),
		activity + ": ambiguous extra person causes NO global pause and NO ghost steering")
	_check(not bool(wrapper.get("last_pose_valid")) and not service.has_valid_pose(),
		activity + ": two overlapping people revoke authoritative motion")

	_send(service, activity, 1, true, student_id, 0.65)
	wrapper.call("_process", 0.02)
	_check(_no_global_pause(wrapper, game, notice) and
		wrapper.active_game.get_instance_id() == initial_scene_id,
		activity + ": same scene runs without replaying calibration after crowd exits")
	_check(bool(wrapper.get("last_pose_valid")) and _has_steering_authority(game, activity),
		activity + ": original epoch's fresh pose restores movement authority")
	if activity == "Human Plane":
		_check(absf(float(game._bank_input)) > 0.05,
			activity + ": refreshed two-wrist bank data supplies actual signed steering")
	_check(service.calibration == saved_calibration,
		activity + ": saved calibration remains valid after crowd exits")
	_check_no_keyboard_steering(game, activity)

	service.worker_pid = -1 # Wrapper _exit_tree must not kill this Godot process.
	wrapper.queue_free()
	await process_frame
	await process_frame
	service.worker_pid = -1
	service.call("stop_camera")


func _send(service: Node, activity: String, people: int,
		valid: bool, student_id: int, x: float = 0.5,
		foreground: int = -1, ambiguous: bool = false) -> void:
	var near_count := people if foreground < 0 else foreground
	var eligible := valid and near_count == 1 and not ambiguous
	var packet := _locked_status(activity, student_id)
	packet.merge({"token": service.session_token, "kind": "pose",
		"camera": true, "camera_phase": "tracking", "state": "tracking",
		"camera_frame_age_ms": 20, "people": people,
		"foreground_people": near_count, "foreground_ambiguous": ambiguous,
		"occupancy_verified": eligible, "player_lock_epoch": 1,
		"pose": eligible, "lock_state": "locked" if eligible else "ambiguous" if ambiguous else "waiting",
		"x": x if eligible else -1.0,
		"plane_bank": clampf((x - 0.5) * 4.0, -1.0, 1.0),
		"plane_bank_valid": eligible, "plane_t_pose_valid": eligible,
		"plane_steering_valid": eligible, "plane_neutral_valid": eligible,
		"hand_observation_valid": eligible, "hand_up": false}, true)
	service.call("_apply_pose_packet", packet, Time.get_ticks_msec())


func _locked_status(activity: String, student_id: int) -> Dictionary:
	var sample := {"state": "tracking", "camera": true, "pose": true,
		"people": 1, "foreground_people": 1, "foreground_ambiguous": false,
		"occupancy_verified": true, "player_lock_epoch": 1,
		"lock_state": "locked", "locked_id": student_id,
		"camera_frame_age_ms": 20, "x": 0.5, "camera_phase": "tracking"}
	if activity == "Human Plane":
		sample["plane_bank"] = 0.0
		sample["plane_bank_valid"] = true
	return sample


func _no_global_pause(wrapper: Control, game: Control, notice: Control) -> bool:
	return not notice.visible and game.process_mode != Node.PROCESS_MODE_DISABLED \
		and not bool(wrapper.tracking_suspended) and String(wrapper.guided_stage) == ""


func _input_revoked(game: Control, activity: String) -> bool:
	match activity:
		"Catch the Word":
			return not bool(game.body_input_active)
		"Balloon Popping":
			return not bool(game.hand_raise_tracking_valid) \
				and is_zero_approx(float(game.body_target_timer)) \
				and is_zero_approx(float(game.launcher_velocity))
		"Human Plane":
			return not bool(game.airplane_pose_active) \
				and is_zero_approx(float(game._bank_input)) \
				and is_zero_approx(float(game._bank_velocity))
	return false


func _has_steering_authority(game: Control, activity: String) -> bool:
	match activity:
		"Catch the Word":
			return bool(game.body_input_active)
		"Balloon Popping":
			return float(game.body_target_timer) > 0.0
		"Human Plane":
			# Centered T-pose (bank=0) is still VERIFIED camera authority.
			# Separate assertions check nonzero steering after tilted input.
			return bool(game.airplane_pose_active)
	return false


func _check_no_keyboard_steering(game: Control, activity: String) -> void:
	# This is only an input regression test; none of the student games may
	# consume Arrow / A / D steering after removal of keyboard movement.
	var initial: float
	match activity:
		"Catch the Word":
			game.call("clear_body_input")
			game.set("basket_velocity", 0.0)
			initial = float(game.get("basket_x"))
		"Balloon Popping":
			game.set("body_target_timer", 0.0)
			game.set("launcher_velocity", 0.0)
			initial = float(game.get("launcher_x"))
		"Human Plane":
			# Keyboard must be isolated from previously requested camera bank.
			# The prior live pose can leave a real velocity that would move the
			# aircraft even without keyboard input; explicitly release it first.
			game.call("set_airplane_pose_active", false)
			initial = float(game.get("plane_x_norm"))
	Input.action_press("ui_right")
	match activity:
		"Catch the Word":
			game.call("_update_basket", 0.5)
		"Balloon Popping":
			game.call("_update_launcher", 0.5)
		"Human Plane":
			game.call("_update_plane_motion", 0.5)
	Input.action_release("ui_right")
	var after: float
	match activity:
		"Catch the Word":
			after = float(game.get("basket_x"))
		"Balloon Popping":
			after = float(game.get("launcher_x"))
		"Human Plane":
			after = float(game.get("plane_x_norm"))
	_check(is_equal_approx(initial, after), activity + ": Right-arrow no longer moves the student")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
