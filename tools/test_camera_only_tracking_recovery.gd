extends SceneTree

# No physical webcam is opened. Injects simulated service states into the
# autoload to validate gameplay freeze/resume and editor-authored feedback.
const WRAPPER := "res://ui/play/gameplay.tscn"
const SELECTION := "res://ui/play/play_activity.tscn"
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
	service.call("stop_camera")
	for failure in failures:
		printerr("FAIL CAMERA RECOVERY: ", failure)
	print("CAMERA-ONLY TRACKING RECOVERY: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


func _check_game(activity: String, service: Node) -> void:
	# Deliberately emulate a valid service sample without touching a webcam.
	service.set("active", true)
	service.set("current_status", {"state": "tracking", "pose": true})
	service.set("player_x", 0.5)
	service.set("last_pose_ms", Time.get_ticks_msec())
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
		wrapper.queue_free()
		await process_frame
		return
	var notice_rect := notice.get_global_rect()
	_check(notice_rect.position.x >= 0.0 and notice_rect.position.y >= 0.0
		and notice_rect.end.x <= root.size.x and notice_rect.end.y <= root.size.y,
		activity + ": tracking instruction stays inside the viewport")
	wrapper.call("_process", 0.02)
	_check(bool(wrapper.get("last_pose_valid")), activity + ": accepts valid calibrated pose")

	# Remove pose temporarily; neither keyboard fallback nor a second
	# calibration is allowed to make gameplay proceed.
	service.set("player_x", -1.0)
	service.set("current_status", {"state": "lost", "pose": false})
	wrapper.call("_process", 0.71)
	_check(notice.visible, activity + ": clear return-to-camera instruction appears")
	_check(game.process_mode == Node.PROCESS_MODE_DISABLED,
		activity + ": gameplay freezes instead of unfairly consuming time/lives")
	_check(bool((service.get("calibration") as Dictionary).get("valid", false)),
		activity + ": valid calibration survives loss of pose")

	service.set("current_status", {"state": "tracking", "pose": true})
	service.set("player_x", 0.65)
	service.set("last_pose_ms", Time.get_ticks_msec())
	wrapper.call("_process", 0.02)
	_check(not notice.visible, activity + ": notice disappears when player returns")
	_check(game.process_mode == Node.PROCESS_MODE_INHERIT,
		activity + ": gameplay automatically resumes without another calibration")
	_check(bool(wrapper.get("last_pose_valid")), activity + ": fresh pose drives movement again")
	_check(bool((service.get("calibration") as Dictionary).get("valid", false)),
		activity + ": saved calibration remains valid")
	_check_no_keyboard_steering(game, activity)

	wrapper.queue_free()
	await process_frame
	await process_frame
	service.call("stop_camera")


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
