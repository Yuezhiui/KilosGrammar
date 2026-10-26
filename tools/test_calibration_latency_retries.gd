extends SceneTree

# Godot --headless --path . --script res://tools/test_calibration_latency_retries.gd
# Runs actual calibration Control and PoseService autoload on synthetic frames.
# This never starts an actual camera, worker or database connection.
const CALIBRATION_PATH := "res://ui/vision/calibration.tscn"
var checks := 0
var failures: Array[String] = []
var pose: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService is available")
	if pose == null:
		_finish()
		return
	await _check_real_holds_and_retries()
	pose.stop_camera()
	_finish()


func _check_real_holds_and_retries() -> void:
	pose.stop_camera()
	pose.set_process(false)
	pose.set("active", true)
	pose.set("player_x", -1.0)
	pose.set("current_status", {"state": "loading", "pose": false})
	var packed := load(CALIBRATION_PATH) as PackedScene
	_check(packed != null, "calibration PackedScene loads with PoseService autoload initialized")
	if packed == null:
		return
	var screen := packed.instantiate() as Control
	_check(screen != null and screen.has_method("set_context"),
		"real calibrated screen script and methods compile")
	if screen == null or not screen.has_method("set_context"):
		if screen != null:
			screen.free()
		return
	root.add_child(screen)
	screen.set_process(false)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.call("set_context", {"activity": "Human Plane", "topic": "Noun",
		"camera_requested": true, "game_mode": "Seconds", "keyboard_mode": false})
	var constants: Dictionary = screen.get_script().get_script_constant_map()
	_check(constants.get("CAPTURE_ORDER", []) == ["CENTER", "RIGHT", "LEFT"],
		"physical calibration runs CENTER, then RIGHT, then LEFT")
	_check(float(constants.get("HOLD_SECONDS", -1.0)) >= 3.0,
		"each physical location needs a meaningful timed hold")
	screen.call("_process", float(constants.get("INTRO_SECONDS", 2.5)) + 0.01)
	_check(not bool(screen.get("intro_running")), "intro completes without crediting held pose time")
	_check(int(screen.get("live_step")) == 0 and is_zero_approx(float(screen.get("live_timer"))),
		"intro never advances a calibration stage on its own")
	for _i in range(8):
		screen.call("_process", 0.1)
	_check(int(screen.get("live_step")) == 0 and is_zero_approx(float(screen.get("live_timer"))),
		"no valid pose packets means no hidden countdown accumulation")

	# CENTER: low-rate 8 Hz stream and normal jitter. A transient 450ms gap
	# remains below the 700ms permitted pause and should not erase progress.
	for i in range(11):
		_frame(screen, 0.5 + (0.014 if i % 2 == 0 else -0.014), 0.125)
	var before_gap := float(screen.get("live_timer"))
	screen.call("_process", 0.45)
	_check(float(screen.get("live_timer")) >= before_gap - 0.005 and
		int(screen.get("live_step")) == 0,
		"450ms transient inference delay retains current stable CENTER hold")
	for i in range(22):
		_frame(screen, 0.5 + (0.014 if i % 2 == 0 else -0.014), 0.125)
	_check(int(screen.get("live_step")) == 1 and
		(screen.get("measured_points") as Dictionary).has("center"),
		"low-rate jittered CENTER hold reliably advances to RIGHT")

	# RIGHT: one dropped-packet burst > 700ms must restart THIS hold without
	# discarding CENTER measurements. Jitter under ~0.03 is acceptable.
	for i in range(6):
		_frame(screen, 0.80 + (0.015 if i % 2 == 0 else -0.015), 0.15)
	screen.call("_process", 0.85)
	_check(int(screen.get("live_step")) == 1 and is_zero_approx(float(screen.get("live_timer"))),
		"850ms inference stall cancels partial RIGHT hold for safety")
	_check((screen.get("measured_points") as Dictionary).has("center"),
		"RIGHT retry preserves a successful CENTER measurement")
	for i in range(23):
		_frame(screen, 0.80 + (0.018 if i % 2 == 0 else -0.018), 0.15)
	_check(int(screen.get("live_step")) == 2 and
		(screen.get("measured_points") as Dictionary).has("right"),
		"RIGHT succeeds after recovery without restarting the entire calibration")

	# LEFT: force pose loss mid-hold; previously measured stages survive.
	for i in range(7):
		_frame(screen, 0.20 + (0.012 if i % 2 == 0 else -0.012), 0.15)
	pose.set("current_status", {"state": "stale", "pose": false,
		"detail": "Student temporarily occluded"})
	pose.set("player_x", -1.0)
	screen.call("_process", 0.10)
	_check(int(screen.get("live_step")) == 2 and is_zero_approx(float(screen.get("live_timer"))),
		"lost student invalidates LEFT partial hold immediately (step=%d, timer=%.3f)" %
		[int(screen.get("live_step")), float(screen.get("live_timer"))])
	_check((screen.get("measured_points") as Dictionary).has("center") and
		(screen.get("measured_points") as Dictionary).has("right"),
		"occlusion retains finished CENTER and RIGHT measurements")
	for i in range(25):
		_frame(screen, 0.20 + (0.018 if i % 2 == 0 else -0.018), 0.15)
	_check(int(screen.get("live_step")) == 3,
		"LEFT recovers from temporary occlusion and finishes three real holds")
	var calibration: Dictionary = pose.get("calibration")
	_check(bool(calibration.get("valid", false)) and
		float(calibration.get("left", 1.0)) < float(calibration.get("center", 0.0)) and
		float(calibration.get("center", 1.0)) < float(calibration.get("right", 0.0)),
		"measured left/center/right define valid nonfabricated camera travel")
	_check(bool(screen.get("transition_queued")),
		"successful calibration queues automatic gameplay handoff")
	screen.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(screen), "calibration scene releases after retries")
	pose.stop_camera()


func _frame(screen: Control, x: float, dt: float) -> void:
	pose.set("active", true)
	pose.set("player_x", x)
	pose.set("last_pose_ms", Time.get_ticks_msec())
	pose.set("current_status", {"state": "tracking", "pose": true, "lock_state": "locked"})
	pose.set("packet_sequence", int(pose.get("packet_sequence")) + 1)
	screen.call("_process", dt)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("CALIBRATION LATENCY RETRIES FAIL: ", description)


func _finish() -> void:
	print("CALIBRATION LATENCY RETRIES: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
