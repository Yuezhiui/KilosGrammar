extends SceneTree

## Offline one-locked-student, center-only Human Plane QA. Uses distinct
## worker-shaped source packets; never fabricates calibration or opens webcam.
## Godot --headless --path . --script res://tools/test_calibration_stationary_wing_roll.gd
const PATH := "res://ui/vision/calibration.tscn"
const STUDENT_ID := 7
const STEP_SECONDS := 0.40
var checks := 0
var errors: Array[String] = []
var pose: Node
var screen: Control
var timestamp := 100.0
var handoffs: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "Real PoseService is registered")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	pose.set("active", true)
	screen = (load(PATH) as PackedScene).instantiate() as Control
	_check(screen != null and screen.get_script() != null, "Real calibration script loads")
	if screen == null or screen.get_script() == null:
		_finish()
		return
	var constants: Dictionary = screen.get_script().get_script_constant_map()
	_check(int(constants.get("REQUIRED_SAMPLES", 0)) >= 8,
		"Single neutral hold requires at least eight unique real worker detections")
	_check(float(constants.get("PLANE_HOLD_SECONDS", 0.0)) >= 2.5 and
		float(constants.get("PLANE_HOLD_SECONDS", 0.0)) <= 3.0,
		"Short neutral-only hold lasts 2.5–3.0 physical seconds")
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.set_process(false)
	screen.set_context({"activity": "Human Plane", "game_mode": "Seconds", "keyboard_mode": false})
	screen.requested.connect(func(target: String, payload: Dictionary) -> void:
		handoffs.append({"route": target, "data": payload.duplicate(true)}))
	_check(screen.call("_capture_order") == ["CENTER"],
		"Human Plane calibrates only a single CENTER pose with both wrists")
	screen.call("_process", 2.5)
	_check(not bool(screen.get("intro_running")), "Camera intro cannot count as a neutral hold")
	screen.call("_continue_flow", true)
	screen.call("_continue_flow", false)
	_check(handoffs.is_empty(), "No bypass via skip/manual Continue before live calibration")

	_source_packet(0.50, -1, false)
	_check((screen.get("live_samples") as Array).is_empty(),
		"Bystander/unverified track never counts as a neutral pose")
	for i in range(4):
		_source_packet(0.50, STUDENT_ID)
	_check(int(screen.get("live_step")) == 0 and
		(screen.get("live_samples") as Array).size() == 4,
		"Four genuine observations remain an incomplete hold")
	pose.call("_record_fresh_calibration_pose", _state(0.50, STUDENT_ID, true), timestamp - STEP_SECONDS)
	screen.call("_process", 0.01)
	_check((screen.get("live_samples") as Array).size() == 4,
		"A duplicated source timestamp cannot increase the real packet count")
	_source_packet(0.50, STUDENT_ID + 1)
	_check(int(screen.get("live_step")) == 0 and
		(screen.get("measured_points") as Dictionary).is_empty(),
		"New student ID discards previous neutral measurement")
	_source_packet(0.50, STUDENT_ID, true, false)
	_check((screen.get("live_samples") as Array).is_empty(),
		"One visible wrist cannot count toward initial neutral calibration")
	for i in range(7):
		_source_packet(0.502 if i % 2 else 0.498, STUDENT_ID)
	_check(int(screen.get("live_step")) == 0 and
		not bool(pose.plane_calibration.get("valid", false)),
		"Seven distinct 2.5 Hz source frames cannot complete the one-shot calibration")
	_source_packet(0.50, STUDENT_ID)
	_check(int(screen.get("live_step")) == 1 and
		bool(pose.plane_calibration.get("valid", false)),
		"Eight distinct neutral frames over 2.8 seconds unlock steering")
	var saved: Dictionary = pose.plane_calibration
	_check(String(saved.get("mode", "")) == "plane_stationary" and
		bool(saved.get("neutral_only", false)) and
		int(saved.get("locked_id", -1)) == STUDENT_ID,
		"Only one verified student and real neutral pose are stored")
	_check(saved.has("center") and saved.has("neutral_noise") and
		saved.has("sensitivity") and saved.has("deadzone") and
		not saved.has("left") and not saved.has("right"),
		"Neutral-only calibration does not fabricate LEFT or RIGHT measurements")
	_check(absf(float(saved.get("camera_center_x", -1)) - 0.5) < 0.01 and
		absf(float(saved.get("center", -1)) - 0.5) < 0.01,
		"Student remained at the same real floor position")
	_check(bool(screen.get("transition_queued")),
		"Neutral completion automatically queues gameplay rather than waiting for a button")
	for pair in [[0.5, 0.0], [0.72, 1.0], [0.28, -1.0]]:
		_pose_state(float(pair[0]), STUDENT_ID, true, false)
		_check(bool(pose.call("has_stationary_plane_pose")),
			"Fresh same-student torso with one visible wrist authorizes steering")
		_check(absf(float(pose.call("normalized_plane_steering")) - float(pair[1])) < 0.08,
			"Center-relative body movement steers left/center/right with one wrist")
	_pose_state(0.72, STUDENT_ID + 1, true)
	_check(not bool(pose.call("has_stationary_plane_pose")) and
		is_zero_approx(float(pose.call("normalized_plane_steering"))),
		"Another student cannot control the locked student's airplane")
	_pose_state(0.72, STUDENT_ID, false)
	_check(not bool(pose.call("has_stationary_plane_pose")),
		"Occluded or unreliable wrist/shoulder detection freezes input")
	_pose_state(0.72, STUDENT_ID, true)
	pose.set("last_pose_ms", Time.get_ticks_msec() - int(pose.GESTURE_STALE_MS) - 50)
	_check(not bool(pose.call("has_stationary_plane_pose")) and
		is_zero_approx(float(pose.call("normalized_plane_steering"))),
		"Stale neutral-calibrated student pose cannot produce ghost steering")
	_pose_state(0.50, STUDENT_ID, true)
	screen.call("_continue_flow", false)
	_check(handoffs.size() == 1 and String(handoffs[0].get("route", "")) == "gameplay",
		"Completed neutral calibration enters shared gameplay")
	if not handoffs.is_empty():
		var payload: Dictionary = handoffs[0]["data"]
		_check(bool(payload.get("calibration_neutral_only", false)) and
			bool(payload.get("calibration_stationary", false)) and
			String(payload.get("plane_steering_mode", "")) == "centered_torso_x_one_wrist" and
			not bool(payload.get("keyboard_mode", true)),
			"Gameplay receives only authentic neutral hand-pose provenance")
	screen.queue_free()
	await process_frame
	await process_frame
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _source_packet(raw: float, identity: int, valid: bool = true,
		both_wrists: bool = true) -> void:
	var source := _state(raw, identity, valid, both_wrists)
	_pose_state(raw, identity, valid, both_wrists)
	pose.call("_record_fresh_calibration_pose", source, timestamp)
	timestamp += STEP_SECONDS
	screen.call("_process", STEP_SECONDS)


func _pose_state(raw: float, identity: int, valid: bool,
		both_wrists: bool = true) -> void:
	pose.set("active", true)
	pose.set("player_x", raw)
	pose.set("last_pose_ms", Time.get_ticks_msec())
	pose.set("current_status", _state(raw, identity, valid, both_wrists))


func _state(raw: float, identity: int, valid: bool,
		both_wrists: bool = true) -> Dictionary:
	return {"state": "tracking", "pose": true, "x": raw,
		"lock_state": "locked" if valid and identity >= 0 else "waiting",
		"locked_id": identity, "plane_steering": raw,
		"plane_steering_valid": valid,
		"plane_neutral_valid": valid and both_wrists, "fps": 2.5}


func _check(condition: bool, why: String) -> void:
	checks += 1
	if not condition:
		errors.append(why)
		printerr("NEUTRAL CALIBRATION FAIL: ", why)


func _finish() -> void:
	print("HUMAN PLANE SINGLE NEUTRAL CALIBRATION: %s checks=%d failures=%d" % [
		"PASS" if errors.is_empty() else "FAIL", checks, errors.size()])
	quit(0 if errors.is_empty() else 1)
