extends SceneTree

# No physical webcam is opened. Uses authenticated synthetic camera packets,
# a localhost UDP receiver and mock PID for gameplay freeze/resume feedback.
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
		# The current Human Plane contract is ONE neutral, same locked student,
		# with fresh torso steering and one observed wrist. It no longer uses
		# old synthetic LEFT/CENTER/RIGHT side calibration for flight.
		var neutral := {"valid": true, "mode": "plane_stationary", "center": 0.5,
			"camera_center_x": 0.5, "locked_id": student_id,
			"sensitivity": 0.18, "deadzone": 0.018,
			"steering_mode": "centered_torso_x_one_wrist"}
		service.set("plane_calibration", neutral.duplicate(true))
		service.set("calibration", neutral.duplicate(true))
	else:
		service.set("plane_calibration", {})
		service.set("calibration", {"valid": true, "left": 0.2, "center": 0.5, "right": 0.8})
	var wrapper := (load(WRAPPER) as PackedScene).instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({
		"activity": activity, "camera_live": true, "keyboard_mode": false,
		"topic": "Noun", "game_mode": "Seconds", "difficulty": "Easy"
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
	wrapper.call("_process", 0.02)
	_check(bool(wrapper.get("last_pose_valid")), activity + ": accepts valid calibrated pose")

	# First real zero-person inference freezes the minigame immediately and
	# displays COME BACK without a grace delay.
	_send(service, activity, 0, false, -1)
	wrapper.call("_process", 0.71)
	_check(notice.visible and (notice.get_node("Title") as Label).text == "COME BACK INTO THE CAMERA!",
		activity + ": first fresh empty frame immediately shows Come Back")
	_check(game.process_mode == Node.PROCESS_MODE_DISABLED,
		activity + ": gameplay freezes instead of unfairly consuming time/lives")
	_check(bool((service.get("calibration") as Dictionary).get("valid", false)),
		activity + ": valid calibration survives loss of pose")
	# Subsequent fresh empty-camera observations keep the warning visible.
	_send(service, activity, 0, false, -1)
	wrapper.call("_process", 0.60)
	_check(notice.visible, activity + ": repeated fresh empty-camera observations show return instruction")
	_send(service, activity, 1, false, -1)
	wrapper.call("_process", 0.80)
	_check(not notice.visible and game.process_mode != Node.PROCESS_MODE_DISABLED \
		and not bool(wrapper.get("last_pose_valid")),
		activity + ": a single bystander with no usable pose keeps game playing without stale motion")
	_send(service, activity, 2, false, -1)
	wrapper.call("_process", 0.01)
	_check(notice.visible and (notice.get_node("Title") as Label).text == "ONLY ONE PLAYER!"
		and game.process_mode == Node.PROCESS_MODE_DISABLED,
		activity + ": two detected players display one-player-only instruction")

	_send(service, activity, 1, true, student_id, 0.65)
	wrapper.call("_process", 0.02)
	_check(not notice.visible, activity + ": notice disappears when player returns")
	_check(game.process_mode == Node.PROCESS_MODE_INHERIT,
		activity + ": gameplay automatically resumes without another calibration")
	_check(bool(wrapper.get("last_pose_valid")), activity + ": fresh pose drives movement again")
	_check(bool((service.get("calibration") as Dictionary).get("valid", false)),
		activity + ": saved calibration remains valid")
	_check_no_keyboard_steering(game, activity)

	service.worker_pid = -1 # Wrapper _exit_tree must not kill this Godot process.
	wrapper.queue_free()
	await process_frame
	await process_frame
	service.worker_pid = -1
	service.call("stop_camera")


func _send(service: Node, activity: String, people: int,
		valid: bool, student_id: int, x: float = 0.5) -> void:
	var packet := _locked_status(activity, student_id)
	packet.merge({"token": service.session_token, "kind": "pose",
		"camera_phase": "tracking", "state": "tracking", "people": people,
		"pose": valid, "lock_state": "locked" if valid and people == 1 else "waiting",
		"x": x if valid and people == 1 else -1.0,
		"plane_steering": x, "plane_steering_valid": valid and people == 1}, true)
	service.call("_apply_pose_packet", packet, Time.get_ticks_msec())


func _locked_status(activity: String, student_id: int) -> Dictionary:
	var sample := {"state": "tracking", "camera": true, "pose": true,
		"people": 1, "lock_state": "locked", "locked_id": student_id,
		"camera_frame_age_ms": 20, "x": 0.5, "camera_phase": "tracking"}
	if activity == "Human Plane":
		sample["plane_steering"] = 0.5
		sample["plane_steering_valid"] = true
	return sample


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
			game.set("target_x_norm", 0.5)
			game.set("plane_x_norm", 0.5)
			initial = 0.5
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
