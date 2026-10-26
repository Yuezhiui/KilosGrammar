extends SceneTree

# Fully offline regression: NO physical webcam, worker, database, or fake pose
# packet is sent to PoseService. We only model its already-decoded statuses.
const GAMEPLAY_PATH := "res://ui/play/gameplay.tscn"
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
	pose.set_process(false)
	pose.active = true
	pose.player_x = 0.5
	pose.last_pose_ms = Time.get_ticks_msec()
	pose.set("_last_packet_ms", Time.get_ticks_msec())
	pose.calibration = {"valid": true, "left": 0.20, "center": 0.50, "right": 0.80}
	pose.current_status = _status(true, 1, "locked")
	var wrapper := (load(GAMEPLAY_PATH) as PackedScene).instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({"activity": "Catch the Word", "guided_tutorial": true,
		"camera_live": true, "game_mode": "Seconds", "topic": "Noun"})
	await process_frame
	await process_frame
	var overlay := wrapper.get("spotlight_overlay") as CanvasLayer
	_check(overlay != null and String(wrapper.get("guided_stage")) == "tutorial",
		"real tutorial spotlight mounted")
	if overlay != null:
		overlay.call("skip")
	await process_frame
	_check(String(wrapper.get("guided_stage")) == "countdown",
		"skipping dialogue goes to countdown, not directly to gameplay")

	# Calibrated player is still in view, but their control/calibration may be
	# unavailable briefly after the tutorial. No 'come back' message is valid.
	pose.calibration.clear()
	wrapper.call("_process", 2.0)
	_check(not (wrapper.get("tracking_notice") as Control).visible,
		"calibration gap during countdown is not classified as missing player")
	for _i in range(3):
		wrapper.call("_on_countdown_tick")
	_check(String(wrapper.get("guided_stage")) == "",
		"countdown clears guidance state")
	_check(not (wrapper.get("tracking_notice") as Control).visible
		and is_zero_approx(float(wrapper.get("confirmed_missing_student_seconds"))),
		"skipped tutorial cannot carry false warning into live game")
	wrapper.call("_process", 1.5)
	_check(not (wrapper.get("tracking_notice") as Control).visible,
		"actual detected player with invalid calibration NEVER gets 'come back' warning")
	pose.calibration = {"valid": true, "left": 0.20, "center": 0.50, "right": 0.80}
	wrapper.call("_process", 0.016)
	_check(not (wrapper.get("tracking_notice") as Control).visible
		and not bool(wrapper.get("tracking_suspended")),
		"valid player pose restores motion without a warning")

	pose.player_x = -1.0
	pose.current_status = {"state": "recovering", "camera": true, "pose": false,
		"people": 0, "lock_state": "occluded"}
	wrapper.call("_process", 3.0)
	_check(not (wrapper.get("tracking_notice") as Control).visible,
		"camera recovery/stall is not misreported as a missing player")
	pose.current_status = _status(false, 1, "enrolling")
	pose.set("_last_packet_ms", Time.get_ticks_msec())
	wrapper.call("_process", 3.0)
	_check(not (wrapper.get("tracking_notice") as Control).visible,
		"visible student still enrolling must not be told to return into view")
	pose.current_status = _status(false, 0, "waiting")
	pose.set("_last_packet_ms", Time.get_ticks_msec())
	wrapper.call("_process", 0.7)
	_check(not (wrapper.get("tracking_notice") as Control).visible,
		"first real missing-person observation has a nonflickering grace interval")
	pose.set("_last_packet_ms", Time.get_ticks_msec())
	wrapper.call("_process", 0.7)
	_check((wrapper.get("tracking_notice") as Control).visible,
		"repeated real no-person frames show the warning")
	pose.current_status = _status(true, 1, "locked")
	pose.player_x = 0.5
	pose.last_pose_ms = Time.get_ticks_msec()
	pose.set("_last_packet_ms", Time.get_ticks_msec())
	wrapper.call("_process", 0.016)
	_check(not (wrapper.get("tracking_notice") as Control).visible
		and not bool(wrapper.get("tracking_suspended")),
		"returning locked student immediately clears notice and safely resumes")

	pose.active = false
	wrapper.queue_free()
	await process_frame
	print("TUTORIAL CAMERA NOTICE: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _status(found: bool, people_count: int, lock: String) -> Dictionary:
	return {"state": "tracking", "camera": true, "pose": found,
		"people": people_count, "lock_state": lock}


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL tutorial camera notice: " + label)
