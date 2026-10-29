extends SceneTree

# Fully offline regression: NO physical webcam, worker, database, or fake pose
# packet is sent to PoseService. We only model its already-decoded statuses.
const GAMEPLAY_PATH := "res://ui/play/gameplay/gameplay.tscn"
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(12.0).timeout
	_check(false, "camera notice regression did not exit before watchdog")
	quit(1)


func _run() -> void:
	var pose := root.get_node("PoseService")
	# No process may be launched, and no worker transports are involved.
	pose.stop_camera()
	pose.set_process(false)
	pose.active = true
	# The self PID and local, unbound PacketPeerUDP model only the transport's
	# authenticated liveness. No actual webcam/Python/DB process is started.
	pose.session_token = "qa-camera-notice"
	pose.worker_pid = OS.get_process_id()
	pose.peer = PacketPeerUDP.new()
	pose.set("_restart_pending", false)
	pose.calibration = {"valid": true, "left": 0.20, "center": 0.50, "right": 0.80}
	_observation(pose, true, 1, "locked")
	var wrapper := (load(GAMEPLAY_PATH) as PackedScene).instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({"activity": "Catch the Word", "guided_tutorial": true,
		"camera_live": true, "calibration_measured": true,
		"game_mode": "Seconds", "topic": "Noun"})
	await process_frame
	await process_frame
	_check(String(wrapper.get("guided_stage")) == "countdown",
		"guided starts directly in 3-2-1, not live gameplay before GO")
	_check(wrapper.get("countdown_panel") is Control
		and (wrapper.get("active_game") as Control).process_mode == Node.PROCESS_MODE_DISABLED,
		"direct guided 3-2-1 freezes gameplay and owns a countdown panel")

	# Calibrated player is still in view, but their control/calibration may be
	# unavailable briefly after calibration. No 'come back' message is valid.
	pose.calibration.clear()
	wrapper.call("_process", 2.0)
	_check(not (wrapper.get("tracking_notice") as Control).visible,
		"calibration gap during countdown is not classified as missing player")
	for _i in range(3):
		wrapper.call("_on_countdown_tick")
	_check(String(wrapper.get("guided_stage")) == "countdown"
		and bool(wrapper.get("_countdown_waiting_for_pose"))
		and (wrapper.get("active_game") as Control).process_mode == Node.PROCESS_MODE_DISABLED,
		"countdown refuses GO with missing calibration, freezing score/timers")
	pose.calibration = {"valid": true, "left": 0.20, "center": 0.50, "right": 0.80}
	_observation(pose, true, 1, "locked")
	wrapper.call("_process", 0.016)
	_check(String(wrapper.get("guided_stage")) == ""
		and (wrapper.get("active_game") as Control).process_mode == Node.PROCESS_MODE_INHERIT,
		"restored calibrated single student completes GO exactly once")
	_check(not (wrapper.get("tracking_notice") as Control).visible
		and is_zero_approx(float(wrapper.get("confirmed_missing_student_seconds"))),
		"guided countdown cannot carry a false warning into live game")
	pose.calibration.clear()
	wrapper.call("_process", 1.5)
	_check(not (wrapper.get("tracking_notice") as Control).visible,
		"actual detected player with invalid calibration NEVER gets 'come back' warning")
	pose.calibration = {"valid": true, "left": 0.20, "center": 0.50, "right": 0.80}
	_observation(pose, true, 1, "locked")
	wrapper.call("_process", 0.016)
	_check(not (wrapper.get("tracking_notice") as Control).visible
		and not bool(wrapper.get("tracking_suspended")),
		"valid player pose restores motion without a warning")

	_observation(pose, false, 0, "occluded", "recovering")
	wrapper.call("_process", 3.0)
	_check(not (wrapper.get("tracking_notice") as Control).visible,
		"camera recovery/stall is not misreported as a missing player")
	_observation(pose, false, 1, "enrolling")
	wrapper.call("_process", 3.0)
	_check(not (wrapper.get("tracking_notice") as Control).visible,
		"visible student still enrolling must not be told to return into view")
	_observation(pose, false, 0, "waiting")
	wrapper.call("_process", 0.7)
	_check((wrapper.get("tracking_notice") as Control).visible
		and ((wrapper.get("tracking_notice") as Control).get_node("Title") as Label).text == "COME BACK INTO THE CAMERA!",
		"first fresh zero-person observation immediately shows return instruction")
	_observation(pose, false, 0, "waiting")
	wrapper.call("_process", 0.7)
	_check((wrapper.get("tracking_notice") as Control).visible,
		"repeated real no-person frames show the warning")
	_observation(pose, true, 1, "locked")
	wrapper.call("_process", 0.016)
	_check(not (wrapper.get("tracking_notice") as Control).visible
		and not bool(wrapper.get("tracking_suspended")),
		"returning locked student immediately clears notice and safely resumes")

	# Never let production stop_camera() attempt to kill this Godot PID.
	pose.worker_pid = -1
	pose.peer = null
	pose.active = false
	wrapper.queue_free()
	await process_frame
	print("TUTORIAL CAMERA NOTICE: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _observation(pose: Node, found: bool, people_count: int, lock: String,
		phase: String = "tracking") -> void:
	pose.call("_apply_pose_packet", {"token": pose.session_token,
		"kind": "pose", "state": phase, "camera_phase": phase,
		"camera": true, "pose": found, "people": people_count,
		"lock_state": lock, "camera_frame_age_ms": 20,
		"x": 0.5 if found else -1.0}, Time.get_ticks_msec())


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL tutorial camera notice: " + label)
