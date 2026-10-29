extends SceneTree

# Godot --headless --path . --script res://tools/test_calibration_latency_retries.gd
# Runs actual calibration Control and PoseService on source-shaped synthetic
# frames. Human Plane uses a 3s center T-pose; Catch measures 3 floor zones.
# Balloon measures LEFT -> CENTER -> RIGHT with 3s both-DOWN then both-UP
# in each zone. Fresh source SOLO packets, not cached screenshot/hand_up.
# Never starts a camera, Python worker, or database connection.
const CALIBRATION_PATH := "res://ui/vision/calibration/calibration.tscn"
const LOCKED_STUDENT_ID := 203 # Legacy diagnostic only; not binding.
const HOLD_SECONDS := 3.0
var checks := 0
var failures: Array[String] = []
var pose: Node
var packed: PackedScene
var source_when := 1000.0


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(30.0).timeout
	_check(false, "no-device calibration regression finished within its watchdog")
	_finish()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService is available")
	if pose == null:
		_finish()
		return
	packed = load(CALIBRATION_PATH) as PackedScene
	_check(packed != null, "calibration PackedScene loads with PoseService autoload initialized")
	if packed == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	await _check_human_plane_neutral_and_retries()
	for activity in ["Catch the Word", "Balloon Popping"]:
		await _check_physical_holds_and_retries(activity)
	pose.stop_camera()
	_finish()


func _new_screen(activity: String) -> Control:
	pose.worker_pid = -1 # Prior test's mock PID is Godot itself.
	pose.stop_camera()
	pose.set_process(false)
	var fake_udp := PacketPeerUDP.new()
	_check(fake_udp.bind(0, "127.0.0.1") == OK,
		activity + " binds a synthetic loopback transport for source authentication")
	pose.peer = fake_udp
	pose.worker_pid = OS.get_process_id()
	pose.session_token = "latency-retries-source-" + activity.replace(" ", "-")
	pose.set("active", true)
	pose.set("player_x", -1.0)
	pose.set("current_status", {"state": "loading", "pose": false,
		"camera": true, "lock_state": "waiting"})
	var screen := packed.instantiate() as Control
	if screen == null:
		return null
	root.add_child(screen)
	screen.set_process(false)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.call("set_context", {"activity": activity, "topic": "Noun",
		"camera_requested": true, "game_mode": "Seconds", "keyboard_mode": false})
	_check(pose.worker_pid == OS.get_process_id() and pose.peer == fake_udp,
		activity + " has mock source liveness without launching a webcam worker")
	screen.call("_process", 3.01)
	_check(not bool(screen.get("intro_running")), activity + " intro finishes")
	_check(int(screen.get("live_step")) == 0 and is_zero_approx(float(screen.get("live_timer"))),
		activity + " intro never credits held pose time")
	for _i in range(8):
		screen.call("_process", 0.1)
	_check(int(screen.get("live_step")) == 0 and is_zero_approx(float(screen.get("live_timer"))),
		activity + " cannot accumulate hold time without new pose packets")
	return screen


func _release_screen(screen: Control) -> void:
	pose.worker_pid = -1 # NEVER terminate the Godot QA process at scene exit.
	if is_instance_valid(screen):
		screen.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(screen), "calibration scene releases cleanly")
	pose.stop_camera()


func _check_human_plane_neutral_and_retries() -> void:
	var screen := _new_screen("Human Plane")
	if screen == null:
		_check(false, "Human Plane real calibration screen instantiates")
		return
	var constants: Dictionary = screen.get_script().get_script_constant_map()
	_check(screen.call("_capture_order") == ["CENTER"],
		"Human Plane captures only one real centered neutral pose")
	_check(is_equal_approx(float(constants.get("PLANE_HOLD_SECONDS", -1)), 3.0) and
		int(constants.get("REQUIRED_SAMPLES", 0)) >= 8,
		"Human Plane requires 3.0 seconds and at least 8 distinct source T-poses")
	# A brief 8-Hz tracking delay cannot invalidate a genuinely continuous
	# neutral hold. Pose timestamps (not render ticks) establish its duration.
	for i in range(11):
		_frame(screen, 0.50 + (0.012 if i % 2 == 0 else -0.012), 0.125, true)
	var before_gap := float(screen.get("live_timer"))
	screen.call("_process", 0.45)
	source_when += 0.45
	_check(int(screen.get("live_step")) == 0 and
		float(screen.get("live_timer")) >= before_gap - 0.005,
		"Human Plane preserves neutral progress through a 450ms inference gap")
	for i in range(4):
		_frame(screen, 0.50 + (0.012 if i % 2 == 0 else -0.012), 0.125, true)
	_check(int(screen.get("live_step")) == 0 and
		float(screen.get("live_timer")) > 1.9,
		"Human Plane remains in center while neutral hold is below 3 seconds")
	# A gap longer than the 700ms freshness budget cancels only the active hold.
	screen.call("_process", 0.85)
	source_when += 0.85
	_check(int(screen.get("live_step")) == 0 and
		is_zero_approx(float(screen.get("live_timer"))) and
		(pose.get("plane_calibration") as Dictionary).is_empty(),
		"850ms stall restarts incomplete Human Plane neutral calibration")
	_frame(screen, 0.50, 0.125, true)
	var before_duplicate := (screen.get("live_samples") as Array).size()
	var source: Dictionary = pose.get("current_status")
	pose.call("_record_fresh_calibration_pose", source, source_when - 0.125)
	screen.call("_process", 0.125)
	_check((screen.get("live_samples") as Array).size() == before_duplicate,
		"Duplicate source timestamp cannot earn an extra neutral pose sample")
	for i in range(5):
		_frame(screen, 0.50 + (0.012 if i % 2 == 0 else -0.012), 0.125, true)
	pose.set("current_status", {"state": "stale", "pose": false,
		"detail": "Student temporarily occluded"})
	pose.set("player_x", -1.0)
	screen.call("_process", 0.10)
	_check(int(screen.get("live_step")) == 0 and
		is_zero_approx(float(screen.get("live_timer"))),
		"Student occlusion immediately invalidates partial Human Plane neutral hold")
	# 6 distinct fresh observations can span >=3.0 seconds yet still fail
	# the eight-source-frame minimum. The 8th packet completes the same hold.
	for i in range(6):
		_frame(screen, 0.50 + (0.012 if i % 2 == 0 else -0.012), 0.65, true)
	_check(int(screen.get("live_step")) == 0 and
		(screen.get("live_samples") as Array).size() == 6 and
		float(screen.get("live_timer")) >= 3.0 and
		(pose.get("plane_calibration") as Dictionary).is_empty(),
		"Human Plane refuses neutral calibration with only 6 distinct frames")
	_frame(screen, 0.50, 0.65, true)
	_check(int(screen.get("live_step")) == 0 and
		(screen.get("live_samples") as Array).size() == 7,
		"Seven distinct frames are still insufficient for the neutral hold")
	_frame(screen, 0.50, 0.65, true)
	var plane: Dictionary = pose.get("plane_calibration")
	var general: Dictionary = pose.get("calibration")
	_check(int(screen.get("live_step")) == 1 and bool(screen.get("transition_queued")),
		"Eighth fresh pose finishes Human Plane center and queues gameplay")
	_check(bool(plane.get("valid", false)) and
		String(plane.get("mode", "")) == "plane_stationary" and
		bool(plane.get("neutral_only", false)) and
		not plane.has("locked_id") and
		absf(float(plane.get("center", 0.0)) - 0.50) < 0.025,
		"One measured neutral center does not bind a registered tracking ID")
	_check(bool(general.get("valid", false)) and
		not general.has("left") and not general.has("right"),
		"Human Plane does not fabricate left/right floor measurements")
	await _release_screen(screen)


func _check_physical_holds_and_retries(activity: String) -> void:
	if activity == "Balloon Popping":
		await _check_balloon_bilateral_holds_and_retries()
		return
	var screen := _new_screen(activity)
	if screen == null:
		_check(false, activity + " real calibration screen instantiates")
		return
	var constants: Dictionary = screen.get_script().get_script_constant_map()
	_check(screen.call("_capture_order") == ["CENTER", "RIGHT", "LEFT"] and
		is_equal_approx(float(constants.get("HOLD_SECONDS", -1.0)), 3.0) and
		int(constants.get("REQUIRED_SAMPLES", 0)) >= 8,
		activity + " retains three physical positions, each 3s and 8 fresh packets")

	# CENTER: low-rate 8 Hz stream and normal jitter. A transient 450ms gap
	# remains below the 700ms permitted pause and should not erase progress.
	for i in range(11):
		_frame(screen, 0.5 + (0.014 if i % 2 == 0 else -0.014), 0.125)
	var before_gap := float(screen.get("live_timer"))
	screen.call("_process", 0.45)
	source_when += 0.45
	_check(float(screen.get("live_timer")) >= before_gap - 0.005 and
		int(screen.get("live_step")) == 0,
		activity + " 450ms inference delay retains current stable CENTER hold")
	for i in range(22):
		_frame(screen, 0.5 + (0.014 if i % 2 == 0 else -0.014), 0.125)
	_check(int(screen.get("live_step")) == 1 and
		(screen.get("measured_points") as Dictionary).has("center"),
		activity + " low-rate jittered CENTER hold reliably advances to RIGHT")

	# RIGHT: one dropped-packet burst > 700ms must restart THIS hold without
	# discarding CENTER measurements. Jitter under ~0.03 is acceptable.
	for i in range(6):
		_frame(screen, 0.80 + (0.015 if i % 2 == 0 else -0.015), 0.15)
	screen.call("_process", 0.85)
	source_when += 0.85
	_check(int(screen.get("live_step")) == 1 and is_zero_approx(float(screen.get("live_timer"))),
		activity + " 850ms inference stall cancels partial RIGHT hold for safety")
	_check((screen.get("measured_points") as Dictionary).has("center"),
		activity + " RIGHT retry preserves a successful CENTER measurement")
	for i in range(23):
		_frame(screen, 0.80 + (0.018 if i % 2 == 0 else -0.018), 0.15)
	_check(int(screen.get("live_step")) == 2 and
		(screen.get("measured_points") as Dictionary).has("right"),
		activity + " RIGHT succeeds without restarting the entire calibration")

	# LEFT: force pose loss mid-hold; previously measured stages survive.
	for i in range(7):
		_frame(screen, 0.20 + (0.012 if i % 2 == 0 else -0.012), 0.15)
	pose.set("current_status", {"state": "stale", "pose": false,
		"detail": "Student temporarily occluded"})
	pose.set("player_x", -1.0)
	screen.call("_process", 0.10)
	_check(int(screen.get("live_step")) == 2 and is_zero_approx(float(screen.get("live_timer"))),
		activity + " occlusion invalidates LEFT partial hold immediately")
	_check((screen.get("measured_points") as Dictionary).has("center") and
		(screen.get("measured_points") as Dictionary).has("right"),
		activity + " occlusion retains finished CENTER and RIGHT measurements")
	for i in range(25):
		_frame(screen, 0.20 + (0.018 if i % 2 == 0 else -0.018), 0.15)
	_check(int(screen.get("live_step")) == 3,
		activity + " LEFT recovers after occlusion and finishes all three holds")
	var calibration: Dictionary = pose.get("calibration")
	_check(bool(calibration.get("valid", false)) and
		float(calibration.get("left", 1.0)) < float(calibration.get("center", 0.0)) and
		float(calibration.get("center", 1.0)) < float(calibration.get("right", 0.0)) and
		not calibration.has("locked_id"),
		activity + " measured left/center/right without registering a tracking ID")
	_check(bool(screen.get("transition_queued")),
		activity + " successful calibration queues gameplay handoff")
	_check((pose.get("plane_calibration") as Dictionary).is_empty(),
		activity + " physical positions do not reuse Human Plane neutral calibration")
	await _release_screen(screen)


func _check_balloon_bilateral_holds_and_retries() -> void:
	var screen := _new_screen("Balloon Popping")
	if screen == null:
		_check(false, "Balloon retry scene instantiates")
		return
	var constants: Dictionary = screen.get_script().get_script_constant_map()
	_check(screen.call("_capture_order") == ["LEFT", "CENTER", "RIGHT"]
		and is_equal_approx(float(constants.get("HOLD_SECONDS", -1.0)), 3.0)
		and int(constants.get("REQUIRED_SAMPLES", 0)) >= 8,
		"Balloon uses LEFT-CENTER-RIGHT, six 3s bilateral holds / 8 real frames each")
	var routes: Array[String] = []
	screen.requested.connect(func(route: String, _payload: Dictionary) -> void:
		routes.append(route))
	# LEFT both DOWN: 8-Hz source frames with a natural 450ms inference pause
	# must retain earned samples, without granting time from just rendering.
	for i in range(11):
		_frame(screen, 0.20 + (0.014 if i % 2 == 0 else -0.014), 0.125)
	var before_gap := float(screen.live_timer)
	screen.call("_process", 0.45)
	source_when += 0.45
	_check(float(screen.live_timer) >= before_gap - 0.005
		and int(screen.live_step) == 0 and int(screen.balloon_pose_phase) == 0,
		"Balloon LEFT DOWN retains valid samples through 450ms inference gap")
	for i in range(22):
		_frame(screen, 0.20 + (0.014 if i % 2 == 0 else -0.014), 0.125)
	_check(int(screen.live_step) == 0 and int(screen.balloon_pose_phase) == 1
		and screen.measured_points.has("left"),
		"Balloon LEFT 3s BOTH DOWN captures authentic first floor location")
	# The second LEFT phase must NEVER accept a single hand. It also cannot
	# inherit the time/samples from the just-completed DOWN phase.
	for i in range(24):
		_frame(screen, 0.2, 0.15, false, true)
	_check(int(screen.live_step) == 0 and int(screen.balloon_pose_phase) == 1
		and is_zero_approx(float(screen.live_timer)),
		"Balloon 3.6s aggregate one-hand UP never proves both wrists raised")
	_complete_balloon_phase(screen, 0.2, 0, 1, "LEFT BOTH UP")
	# CENTER both DOWN: an 850ms true inference gap cancels ONLY the
	# current hold; LEFT's genuine floor measurement remains intact.
	for i in range(6):
		_frame(screen, 0.5 + (0.012 if i % 2 == 0 else -0.012), 0.15)
	screen.call("_process", 0.85)
	source_when += 0.85
	_check(int(screen.live_step) == 1 and int(screen.balloon_pose_phase) == 0
		and is_zero_approx(float(screen.live_timer)),
		"Balloon 850ms frame stall cancels incomplete CENTER DOWN hold")
	_check(screen.measured_points.has("left")
		and not screen.measured_points.has("center"),
		"Balloon CENTER retry preserves completed LEFT only")
	_complete_balloon_phase(screen, 0.5, 1, 0, "CENTER BOTH DOWN")
	_complete_balloon_phase(screen, 0.5, 1, 1, "CENTER BOTH UP")
	# RIGHT both DOWN: a genuinely missing pose/solo interruption cancels
	# the current hold, never the two previously verified positions.
	for i in range(7):
		_frame(screen, 0.8 + (0.012 if i % 2 == 0 else -0.012), 0.15)
	_frame(screen, 0.8, 0.15, false, false, 0)
	_check(int(screen.live_step) == 2 and int(screen.balloon_pose_phase) == 0
		and is_zero_approx(float(screen.live_timer)),
		"Balloon raw zero-person source cancels incomplete RIGHT DOWN hold")
	_check(screen.measured_points.has("left") and screen.measured_points.has("center")
		and not screen.measured_points.has("right"),
		"Balloon RIGHT pose loss preserves completed LEFT and CENTER")
	_complete_balloon_phase(screen, 0.8, 2, 0, "RIGHT BOTH DOWN")
	_complete_balloon_phase(screen, 0.8, 2, 1, "RIGHT BOTH UP")
	_check(int(screen.live_step) == 3 and bool(screen.success_running)
		and bool(screen.transition_queued) and routes.is_empty(),
		"Balloon all six real holds reach separate SUCCESS, no early gameplay")
	var bounds: Dictionary = pose.calibration
	_check(bool(bounds.get("valid", false)) and
		float(bounds.get("left", 1.0)) < float(bounds.get("center", 0.0)) and
		float(bounds.get("center", 1.0)) < float(bounds.get("right", 0.0)),
		"Balloon preserves authenticated LEFT CENTER RIGHT measurements")
	# Once SUCCESS is latched, 0/2+/stale source freezes its timer and
	# retains the measured bounds, even if hands/green skeleton disappear.
	var original: Dictionary = screen.measured_points.duplicate(true)
	var elapsed_before := float(screen.success_elapsed)
	for count in [0, 2]:
		_frame(screen, 0.8, 0.15, false, false, count)
		_check(screen.success_running and routes.is_empty()
			and screen.measured_points == original
			and is_equal_approx(float(screen.success_elapsed), elapsed_before),
			"Balloon %d raw persons freeze latched SUCCESS" % count)
	pose._last_occupancy_packet_ms = Time.get_ticks_msec() - int(pose.OCCUPANCY_STALE_MS) - 100
	screen.call("_process", 3.5)
	_check(screen.success_running and routes.is_empty()
		and screen.measured_points == original
		and is_equal_approx(float(screen.success_elapsed), elapsed_before),
		"Balloon 3.5s stale source cannot release GO or reopen calibration")
	for i in range(19):
		_frame(screen, 0.8, 0.15, false, false)
	_check(routes.is_empty() and screen.success_running,
		"Balloon restored raw SOLO cannot release GO before success 3s")
	for i in range(4):
		_frame(screen, 0.8, 0.15, false, false)
	_check(routes == ["gameplay"] and bool(screen.passing_to_ready),
		"Balloon restored fresh raw SOLO causes exactly one gameplay GO")
	for i in range(6):
		_frame(screen, 0.8, 0.15, false, false)
	_check(routes.size() == 1 and screen.measured_points == original,
		"Balloon success latch never routes twice or loses measured bounds")
	await _release_screen(screen)


func _complete_balloon_phase(screen: Control, x: float, zone_index: int,
		phase: int, label: String) -> void:
	_check(int(screen.live_step) == zone_index and int(screen.balloon_pose_phase) == phase,
		label + " starts only in expected zone and bilateral phase")
	# 19 new 150ms source packets cover 2.7s between first and last;
	# the whole 3s stage requires more than their sample count alone.
	for i in range(19):
		_frame(screen, x + (0.009 if i % 2 == 0 else -0.009), 0.15)
	_check(int(screen.live_step) == zone_index and int(screen.balloon_pose_phase) == phase,
		label + " refuses 2.85s even with 19 valid source packets")
	for i in range(4):
		_frame(screen, x + (0.009 if i % 2 == 0 else -0.009), 0.15)
		if int(screen.live_step) != zone_index or int(screen.balloon_pose_phase) != phase:
			# Never feed unused padding packets into the NEXT phase. That
			# would pre-credit it and turn a real 2.85s check into 3.15s.
			break
	_check(int(screen.live_step) == zone_index + (1 if phase == 1 else 0)
		and int(screen.balloon_pose_phase) == (0 if phase == 1 else 1),
		label + " advances exactly once after genuine 3s with BOTH wrists")


func _frame(screen: Control, x: float, dt: float, plane_mode: bool = false,
		one_hand_only: bool = false, people: int = 1, pose_valid: bool = true) -> void:
	pose.set("active", true)
	pose.set("player_x", x)
	pose.set("last_pose_ms", Time.get_ticks_msec())
	var activity := String(screen.context.get("activity", ""))
	var balloon := activity == "Balloon Popping"
	var raised := balloon and int(screen.balloon_pose_phase) == 1
	var is_solo_pose := people == 1 and pose_valid
	var packet: Dictionary = {"token": pose.session_token, "kind": "pose",
		"state": "tracking", "camera_phase": "tracking", "pose": is_solo_pose,
		"camera": true, "people": people,
		"lock_state": "locked" if is_solo_pose else "pending",
		"locked_id": LOCKED_STUDENT_ID, "x": x if is_solo_pose else -1.0,
		"camera_frame_age_ms": 20, "fps": 8.0,
		"hand_observation_valid": is_solo_pose,
		"hand_up": is_solo_pose and (raised or one_hand_only),
		"both_hands_up": is_solo_pose and balloon and raised and not one_hand_only,
		"both_hands_down": is_solo_pose and balloon and not raised and not one_hand_only,
		"plane_t_pose_valid": is_solo_pose and plane_mode,
		"plane_bank_valid": is_solo_pose and plane_mode, "plane_bank": 0.0}
	if plane_mode:
		packet["plane_steering"] = 0.5
		packet["plane_steering_valid"] = true
		packet["plane_neutral_valid"] = true
	pose._apply_pose_packet(packet, Time.get_ticks_msec())
	if is_solo_pose:
		pose.player_x = x # Physical source X, not the preview's smoothed drawing.
	source_when += dt
	if is_solo_pose:
		pose.call("_record_fresh_calibration_pose", packet, source_when)
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
