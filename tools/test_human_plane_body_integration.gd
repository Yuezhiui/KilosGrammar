extends SceneTree

# End-to-end offline neutral CENTER calibration -> PoseService -> gameplay
# wrapper -> actual Human Plane renderer. No webcam, DB, or real child data.
# Godot --headless --path . --script res://tools/test_human_plane_body_integration.gd
const CALIBRATION_SCENE := "res://ui/vision/calibration.tscn"
const GAMEPLAY_SCENE := "res://ui/play/gameplay.tscn"
const SESSION_TOKEN := "stationary-flight-wrapper-qa-only"
const STUDENT_ID := 31
const CAMERA_X := 0.50
const DT := 1.0 / 60.0
const NEUTRAL := CAMERA_X

var checks := 0
var failures: Array[String] = []
var pose: Node
var sample_when := 400.0
var finished := false


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(18.0).timeout
	if not finished:
		_check(false, "headless Human Plane integration exceeded 18 seconds")
		_finish()


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "Real PoseService singleton exists")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	pose.set("session_token", SESSION_TOKEN)
	pose.set("active", true)
	var payload := await _complete_stationary_calibration()
	if not payload.is_empty():
		await _test_live_wrapper(payload, "Seconds", Vector2i(1280, 720))
		await _test_live_wrapper(payload, "Lives", Vector2i(1920, 1080))
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _complete_stationary_calibration() -> Dictionary:
	var packed := load(CALIBRATION_SCENE) as PackedScene
	_check(packed != null, "Calibration scene loads")
	if packed == null:
		return {}
	var screen := packed.instantiate() as Control
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.set_process(false)
	screen.set_context({"activity": "Human Plane", "student_name": "OFFLINE QA",
		"game_mode": "Seconds", "difficulty": "Normal", "topic": "Noun"})
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(route: String, data: Dictionary) -> void:
		routes.append({"route": route, "data": data.duplicate(true)}))
	_set_pose(NEUTRAL, STUDENT_ID, true, true)
	screen.call("_process", 2.51)
	_check(int(screen.get("live_step")) == 0,
		"Intro cannot count as a student steering hold")
	screen.call("_continue_flow", false)
	_check(routes.is_empty(), "No gameplay before a verified neutral hand-pose hold")
	_check(screen.call("_capture_order") == ["CENTER"], "Human Plane measures neutral only")
	# One visible hand can steer after calibration, but cannot establish the
	# starting neutral. This packet must not contribute to the eight frames.
	_set_pose(NEUTRAL, STUDENT_ID, true, false)
	pose.call("_record_fresh_calibration_pose", pose.get("current_status"), sample_when)
	sample_when += 0.45
	screen.call("_process", 0.45)
	_check((screen.get("live_samples") as Array).is_empty(),
		"one-wrist center sample never contributes to enrollment")
	for packet in range(8):
		_set_pose(NEUTRAL + 0.001 * float(packet % 3 - 1), STUDENT_ID, true, true)
		var state: Dictionary = pose.get("current_status")
		pose.call("_record_fresh_calibration_pose", state, sample_when)
		sample_when += 0.45
		screen.call("_process", 0.45)
	_check(int(screen.get("live_step")) == 1,
		"Eight distinct source packets over >=2.5s complete the ONLY neutral hold")
	_check((screen.get("measured_points") as Dictionary).has("center") and
		(screen.get("measured_points") as Dictionary).has("neutral_noise") and
		not (screen.get("measured_points") as Dictionary).has("left"),
		"Only neutral arm/torso pose is measured; no left/right samples invented")
	_check(bool(pose.plane_calibration.get("valid", false)) and
		int(pose.plane_calibration.get("locked_id", -1)) == STUDENT_ID,
		"Only the original locked student's stationary calibration is valid")
	if not bool(pose.plane_calibration.get("valid", false)):
		# Subsequent checks must never dereference absent center keys or schedule
		# gameplay transitions from an incomplete calibration.
		screen.queue_free()
		await process_frame
		return {}
	_check(absf(float(pose.plane_calibration.get("camera_center_x", -1.0)) - CAMERA_X) < 0.01,
		"Camera floor x stays constant during the neutral hand-pose hold")
	_check(absf(float(pose.plane_calibration.get("center", -1.0)) - CAMERA_X) < 0.01,
		"Actual mirrored torso X provides the neutral position")
	_check(bool(pose.plane_calibration.get("neutral_only", false)),
		"Real PoseService calibration explicitly records single-neutral mode")
	_set_pose(NEUTRAL, STUDENT_ID, true, false)
	screen.call("_continue_flow", false)
	_check(routes.size() == 1 and String(routes[0].get("route", "")) == "gameplay",
		"Only completed real stationary calibration routes into gameplay")
	var payload: Dictionary = routes[0]["data"] if routes.size() == 1 else {}
	_check(bool(payload.get("calibration_stationary", false)) and
			String(payload.get("plane_steering_mode", "")) == "centered_torso_x_one_wrist" and
		bool(payload.get("calibration_neutral_only", false)) and
		not bool(payload.get("keyboard_mode", true)),
		"Gameplay is explicitly calibrated to neutral-centered torso movement")
	screen.queue_free()
	await process_frame
	await process_frame
	return payload


func _test_live_wrapper(payload: Dictionary, mode: String, dimensions: Vector2i) -> void:
	root.size = dimensions
	root.content_scale_size = dimensions
	var packed := load(GAMEPLAY_SCENE) as PackedScene
	_check(packed != null, "Gameplay wrapper is loadable")
	if packed == null:
		return
	var wrapper := packed.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var settings := payload.duplicate(true)
	settings["game_mode"] = mode
	settings["start_countdown"] = false
	settings["guided_tutorial"] = false
	settings["camera_live"] = true
	settings["activity"] = "Human Plane"
	wrapper.set_context(settings)
	await process_frame
	await process_frame
	wrapper.set_process(false)
	var game := wrapper.get("active_game") as Control
	_check(game != null, "Real Human Plane appears inside live gameplay wrapper")
	if game == null:
		wrapper.queue_free()
		await process_frame
		return
	game.set_process(false)
	var label := "%s/%s" % [mode, dimensions]
	_check(int(game.get("lives")) == 3, label + " retains three lives")
	_check(float(game.get("time_remaining")) > 59.0 if mode == "Seconds" else
		is_zero_approx(float(game.get("time_remaining"))), label + " timer mode remains correct")
	_check(bool(game.get("airplane_pose_active")) and
		bool(pose.call("has_stationary_plane_pose")),
		label + " active game accepts only the same newly verified student steering")
	var original_score := int(game.get("score"))
	await _drive(wrapper, game, NEUTRAL, STUDENT_ID, true, 45)
	_check(absf(float(game.get("plane_x_norm")) - 0.5) < 0.08,
		label + " centered torso holds the airplane in the middle")
	await _drive(wrapper, game, 0.72, STUDENT_ID, true, 70)
	var right_x := float(game.get("plane_x_norm"))
	_check(right_x > 0.85, label + " RIGHT torso movement steers with only one wrist")
	await _drive(wrapper, game, 0.28, STUDENT_ID, true, 90)
	var left_x := float(game.get("plane_x_norm"))
	_check(left_x < 0.15 and left_x < right_x - 0.5,
		label + " LEFT torso movement crosses flight path without gyro")
	await _drive(wrapper, game, NEUTRAL, STUDENT_ID, true, 60)
	_check(absf(float(game.get("plane_x_norm")) - 0.5) < 0.08,
		label + " student returns to CENTER with one visible wrist")
	await _drive(wrapper, game, NEUTRAL, STUDENT_ID, true, 5, true)
	_check(absf(float(game.get("plane_x_norm")) - 0.5) < 0.08,
		label + " changing from one to two visible wrists does not jump")
	var resting := float(game.get("plane_x_norm"))
	await _drive(wrapper, game, 0.72, STUDENT_ID + 1, true, 12)
	_check(not bool(game.get("airplane_pose_active")) and
		absf(float(game.get("plane_x_norm")) - resting) < 0.001,
		label + " other tracked student cannot command the airplane")
	await _drive(wrapper, game, 0.28, STUDENT_ID, false, 12)
	_check(not bool(game.get("airplane_pose_active")) and
		absf(float(game.get("plane_x_norm")) - resting) < 0.001,
		label + " occluded/unreliable joints freeze the current steering position")
	await _drive(wrapper, game, 0.28, STUDENT_ID, true, 65)
	_check(float(game.get("plane_x_norm")) < resting - 0.25,
		label + " fresh same-student lock resumes leftward input smoothly")
	_check(int(game.get("score")) == original_score and int(game.get("attempts")) == 0,
		label + " steering cannot award points before actual ring crossing")
	_check(game.has_method("_lane_hit_at_answer_line") and
		game.get_node_or_null("WorldView3D/Viewport3D/FlightWorld/CloudFlight/CloudProps") != null,
		label + " 3D cloud renderer and authoritative collision resolver both remain live")
	wrapper.call("preserve_camera_for_restart")
	wrapper.queue_free()
	await process_frame
	await process_frame
	pose.set("active", true)


func _drive(wrapper: Control, game: Control, value: float, student: int,
		valid: bool, frames: int, both_wrists: bool = false) -> void:
	for frame in range(frames):
		_set_pose(value, student, valid, both_wrists)
		wrapper.call("_process", DT)
		game.call("_update_plane_motion", DT)
		game.call("_sync_visuals")


func _set_pose(value: float, student: int, valid: bool = true,
		both_wrists: bool = false) -> void:
	pose.set("active", true)
	var source := {"kind": "pose", "token": SESSION_TOKEN, "state": "tracking",
		"pose": valid, "x": value, "lock_state": "locked" if valid else "occluded",
		"locked_id": student, "plane_steering_valid": valid,
		"plane_neutral_valid": valid and both_wrists,
		"plane_steering": value}
	pose.call("_apply_pose_packet", source, Time.get_ticks_msec())


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("STATIONARY BODY BRIDGE FAIL: ", message)


func _finish() -> void:
	if finished:
		return
	finished = true
	if is_instance_valid(pose):
		pose.stop_camera()
		pose.set_process(true)
	print("HUMAN PLANE STATIONARY WRAPPER INTEGRATION: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
