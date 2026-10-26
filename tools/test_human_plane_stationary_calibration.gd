extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_stationary_calibration.gd
# Offline packets for one locked student's CENTER calibration and left/right
# torso travel. Both wrists required only in calibration, one during flight.
# No webcam, DB or YOLO process.
const SCENE_PATH := "res://ui/vision/calibration.tscn"
const STUDENT_ID := 21
const CENTER_X := 0.50

var failures: Array[String] = []
var checks := 0
var pose: Node
var scene: PackedScene
var source_clock := 100.0
var finished := false


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(18.0).timeout
	if not finished:
		_check(false, "headless calibration timed out; expected exit within 18 seconds")
		_finish()


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload is ready")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	_reset_camera()
	scene = load(SCENE_PATH) as PackedScene
	if scene == null:
		_check(false, "calibration scene loads")
		_finish()
		return
	var screen := _screen("Human Plane")
	if screen == null:
		_finish()
		return
	var stage := screen.get_node_or_null("TutorialStage") as Control
	if stage == null:
		_check(false, "required TutorialStage exists")
		_finish()
		return
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(to: String, payload: Dictionary) -> void:
		routes.append({"to": to, "payload": payload}))
	_check(screen.call("_capture_order") == ["CENTER"], "one neutral hand pose only")
	_check(bool(screen.get("intro_running")), "intro still plays before hand calibration")
	screen.call("_process", 2.51)
	var title := stage.get_node_or_null("PlaneSteeringTitle") as Label
	var badge := stage.get_node_or_null("PlaneStepBadge") as Control
	var badge_label := stage.get_node_or_null("PlaneStepBadge/CenterOnlyLabel") as Label
	_check(title != null and title.visible and title.text.contains("HANDS"),
		"native scene instruction shows single BOTH-HANDS hold")
	_check(badge != null and badge.visible and badge_label != null
		and badge_label.text == "ONE POSE", "native badge shows ONE POSE")
	_check(not _node_visible(stage, "ArtStep1")
		and not _node_visible(stage, "ArtTitleRight")
		and not _node_visible(stage, "ArtTitleLeft"),
		"old three-stage floor art absent or hidden in Human Plane")
	_check(_node_visible(stage, "ArtGuideCenter")
		and not _node_visible(stage, "ArtGuideRight")
		and not _node_visible(stage, "ArtGuideLeft")
		and not _node_visible(stage, "CenterCalibrationLane"),
		"student stands in one yellow PARAMETERS.png center guide without duplicate green panel")
	screen.call("_continue_flow", false)
	_check(routes.is_empty(), "cannot skip neutral hold")

	# Eight REAL frames are compulsory even if their elapsed duration is long.
	for i in range(7):
		_packet(screen, CENTER_X, STUDENT_ID, 0.45)
	_check(int(screen.get("live_step")) == 0 and routes.is_empty(),
		"7 source observations over 2.5 seconds are insufficient")

	# Duplicate source timestamp cannot create an eighth unique observation.
	var previous_id := int(pose.get("latest_pose_sample_id"))
	var last_packet: Dictionary = _state(CENTER_X, STUDENT_ID)
	pose.call("_record_fresh_calibration_pose", last_packet, source_clock)
	_check(int(pose.get("latest_pose_sample_id")) == previous_id,
		"duplicate source timestamp rejected")

	# A bystander can't supply a missing eighth packet.
	_packet(screen, CENTER_X, -1, 0.45)
	_check(int(screen.get("live_step")) == 0 and routes.is_empty(),
		"ambiguous pose cannot complete the one-hold calibration")
	# With the SAME locked ID, one visible wrist must never complete the
	# initial center hold (but will be sufficient after calibration).
	_packet(screen, CENTER_X, STUDENT_ID, 0.38, false)
	_check(int(screen.get("live_step")) == 0
		and (screen.get("live_samples") as Array).is_empty(),
		"single wrist denied during the neutral enrollment hold")

	# Recovery requires a new uninterrupted neutral hold.
	for i in range(8):
		_packet(screen, CENTER_X + (float(i % 3) - 1.0) * 0.005,
			STUDENT_ID, 0.38)
	var measured: Dictionary = pose.get("plane_calibration") as Dictionary
	_check(int(screen.get("live_step")) == 1 and bool(measured.get("valid", false)),
		"one short valid hand hold calibrates without LEFT/RIGHT poses")
	if not bool(measured.get("valid", false)):
		# Never access absent center/sensitivity keys after a failed hold.
		_finish()
		return
	_check(bool((pose.get("calibration") as Dictionary).get("valid", false)),
		"existing gameplay route calibration.valid stays compatible")
	_check(String(measured.get("mode", "")) == "plane_stationary"
		and bool(measured.get("neutral_only", false)), "neutral-only steering metadata explicit")
	_check(not measured.has("left") and not measured.has("right"),
		"no invented LEFT/RIGHT calibration data")
	_check(is_equal_approx(float(measured.get("center", -1.0)), CENTER_X)
		and absf(float(measured.get("camera_center_x", -1.0)) - CENTER_X) < 0.01
		and absf(float(measured.get("neutral_noise", -1.0))) <= 0.01,
		"robust center and jitter measured from real torso observations")
	_check(String(measured.get("steering_mode", "")) == "centered_torso_x_one_wrist",
		"center-anchored torso mode stored in PoseService")
	_check(float(measured.get("sensitivity", 1.0)) >= 0.18
		and float(measured.get("sensitivity", 1.0)) <= 0.30,
		"symmetric sensitivity adapts to measured neutral jitter")
	_check(not _node_visible(stage, "PlaneStepBadge"),
		"single-pose badge clears immediately on completion")
	_check(bool(pose.call("has_stationary_plane_pose")), "verified center torso is eligible for flight")

	var center := float(measured.get("center", CENTER_X))
	var threshold := float(measured.get("sensitivity", 0.2))
	var deadzone := float(measured.get("deadzone", 0.025))
	_live_pose(center, STUDENT_ID, true)
	_check(is_zero_approx(float(pose.call("normalized_plane_steering"))),
		"measured center is neutral regardless of wrist banking")
	_live_pose(center + threshold, STUDENT_ID, true, false)
	_check(is_equal_approx(float(pose.call("normalized_plane_steering")), 1.0),
		"RIGHT torso translation with one wrist gives full right flight")
	_live_pose(center - threshold, STUDENT_ID, true, false)
	_check(is_equal_approx(float(pose.call("normalized_plane_steering")), -1.0),
		"LEFT torso translation with one wrist gives full left flight")
	_live_pose(center + deadzone * 0.6, STUDENT_ID, true, false)
	_check(is_zero_approx(float(pose.call("normalized_plane_steering"))),
		"center jitter dead zone prevents accidental plane drift")
	_live_pose(center + threshold * 0.7, STUDENT_ID, true, false)
	var right_partial := float(pose.call("normalized_plane_steering"))
	_live_pose(center - threshold * 0.7, STUDENT_ID, true, false)
	var left_partial := float(pose.call("normalized_plane_steering"))
	_check(right_partial > 0.4 and is_equal_approx(right_partial, -left_partial),
		"fast symmetric torso steering around measured center")
	_check(bool(pose.call("has_stationary_plane_pose"))
		and left_partial < -0.4,
		"one-wrist torso fallback works only after two-wrist calibration")
	_live_pose(center + threshold, STUDENT_ID, true)
	_check(is_equal_approx(float(pose.call("normalized_plane_steering")), 1.0),
		"switching one/two visible wrists does not jump at the right lane")
	_live_pose(center, STUDENT_ID, true, false)
	_check(is_zero_approx(float(pose.call("normalized_plane_steering"))),
		"returning to center restores neutral with only one wrist visible")
	_live_pose(center + threshold, STUDENT_ID + 1, true, false)
	_check(not bool(pose.call("has_stationary_plane_pose")),
		"re-enrolled bystander cannot fly")
	_live_pose(center + threshold, STUDENT_ID, false, false)
	_check(not bool(pose.call("has_stationary_plane_pose")),
		"no trustworthy wrist/torso freezes flight permission")
	_live_pose(center, STUDENT_ID, true, false)
	pose.set("last_pose_ms", Time.get_ticks_msec() - 700)
	_check(not bool(pose.call("has_stationary_plane_pose")),
		"source older than 650ms freezes flight")
	pose.set("last_pose_ms", Time.get_ticks_msec())
	# Preserve 2-second real handoff delay and verify automation rather than
	# manually calling _continue_flow(). Simulate a living locked student by
	# refreshing its current packet age while the navigation timer runs.
	for i in range(10):
		await create_timer(0.25).timeout
		pose.set("last_pose_ms", Time.get_ticks_msec())
	_check(routes.size() == 1 and routes[0]["to"] == "gameplay",
		"one verified hold automatically routes after the existing 2s handoff")
	if routes.size() == 1:
		var payload := routes[0]["payload"] as Dictionary
		_check(bool(payload.get("calibration_stationary", false))
			and bool(payload.get("calibration_neutral_only", false))
			and payload.get("plane_steering_mode", "") == "centered_torso_x_one_wrist",
			"route identifies centered torso movement with one wrist during flight")
		_check(not payload.has("calibration_left") and not payload.has("calibration_right"),
			"route contains no fabricated physical side measurements")
		_check(absf(float(payload.get("calibration_steering_sensitivity", -1)) - threshold) < 0.001,
			"route carries actual adaptive gain")
	screen.queue_free()
	await process_frame

	# Change identity *during* the hold: restart instead of swapping students.
	pose.stop_camera()
	_reset_camera()
	var switched := _screen("Human Plane")
	switched.call("_process", 2.51)
	for i in range(3):
		_packet(switched, CENTER_X, STUDENT_ID, 0.35)
	_packet(switched, CENTER_X, 44, 0.40)
	_check(int(switched.get("live_step")) == 0
		and (switched.get("measured_points") as Dictionary).is_empty()
		and int(switched.get("plane_locked_id")) == -1,
		"identity switch discards unfinished neutral measurements")
	switched.queue_free()
	await process_frame

	# Catch Word and Balloon Popping still walk CENTER > RIGHT > LEFT.
	for activity in ["Catch the Word", "Balloon Popping"]:
		pose.stop_camera()
		_reset_camera()
		var other := _screen(activity)
		other.call("_process", 2.51)
		_check(other.call("_capture_order") == ["CENTER", "RIGHT", "LEFT"],
			activity + ": retains the original three floor positions")
		for physical_x in [0.5, 0.8, 0.2]:
			for i in range(33):
				pose.set("player_x", physical_x)
				pose.set("last_pose_ms", Time.get_ticks_msec())
				pose.set("current_status", {"state": "tracking", "pose": true,
					"lock_state": "locked"})
				pose.set("packet_sequence", int(pose.get("packet_sequence")) + 1)
				other.call("_process", 0.1)
		_check(int(other.get("live_step")) == 3
			and bool((pose.get("calibration") as Dictionary).get("valid", false))
			and not (pose.get("calibration") as Dictionary).has("mode"),
			activity + ": retains three real physical measurements")
		_check((pose.get("plane_calibration") as Dictionary).is_empty(),
			activity + ": old calibration stays independent of flight steering")
		other.queue_free()
		await process_frame
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _screen(activity: String) -> Control:
	var screen := scene.instantiate() as Control
	if screen == null or screen.get_script() == null or not screen.has_method("set_context"):
		_check(false, "calibration.gd compiles and exposes set_context")
		return null
	root.add_child(screen)
	screen.set_context({"activity": activity, "camera_requested": true,
		"student_name": "TEST STUDENT"})
	screen.set_process(false)
	return screen


func _reset_camera() -> void:
	pose.set("active", true)
	pose.set("player_x", 0.5)
	pose.set("last_pose_ms", Time.get_ticks_msec())
	pose.set("current_status", _state(CENTER_X, STUDENT_ID))


func _packet(screen: Control, x: float, track_id: int, dt: float,
		both_wrists: bool = true) -> void:
	source_clock += dt
	var packet: Dictionary = _state(x, track_id, track_id >= 0, both_wrists)
	pose.call("_record_fresh_calibration_pose", packet, source_clock)
	_live_pose(x, track_id, track_id >= 0, both_wrists)
	screen.call("_process", dt)


func _state(x: float, track_id: int, valid: bool = true,
		both_wrists: bool = true) -> Dictionary:
	return {"state": "tracking", "pose": valid, "x": x,
		"lock_state": "locked" if valid and track_id >= 0 else "ambiguous",
		"locked_id": track_id, "plane_steering": x,
		"plane_steering_valid": valid and track_id >= 0,
		"plane_neutral_valid": valid and track_id >= 0 and both_wrists}


func _live_pose(x: float, track_id: int, valid: bool = true,
		both_wrists: bool = true) -> void:
	pose.set("player_x", x if valid else -1.0)
	pose.set("last_pose_ms", Time.get_ticks_msec())
	pose.set("current_status", _state(x, track_id, valid, both_wrists))


func _node_visible(parent: Node, path: String) -> bool:
	var node := parent.get_node_or_null(path) as CanvasItem
	return node != null and node.visible


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)


func _finish() -> void:
	if finished:
		return
	finished = true
	if is_instance_valid(pose):
		pose.stop_camera()
		pose.set_process(true)
	for reason in failures:
		printerr("FAIL single-hold plane calibration: ", reason)
	print("%s single-hold plane calibration: %d checks, %d failures" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
