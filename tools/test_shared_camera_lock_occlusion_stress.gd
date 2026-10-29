extends SceneTree

## Authenticated localhost PacketPeerUDP mock worker; NEVER opens a webcam,
## Python worker, or real database. The real gameplay wrapper must handle the
## new one-person occupancy rules in Play and Tutorial for every minigame.
## Nobody / two+ people pause; one fresh YOLO person keeps the SAME round
## running even when wrists/keypoints/enrollment are temporarily unavailable.
## Godot --headless --path . --script res://tools/test_shared_camera_lock_occlusion_stress.gd
const WRAPPER := "res://ui/play/gameplay/gameplay.tscn"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const TRACK_ID := 84
var pose: Node
var checks := 0
var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(30.0).timeout
	_expect(false, "Tracking stress test watchdog expired")
	quit(1)


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	_expect(pose != null, "Shared real PoseService singleton available")
	if pose == null:
		quit(1)
		return
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(false)
	var packed := load(WRAPPER) as PackedScene
	_expect(packed != null, "Game wrapper resource loads for Play and Tutorial")
	if packed == null:
		_finish()
		return
	for activity in ACTIVITIES:
		for size in SIZES:
			for tutorial in [false, true]:
				await _exercise(packed, activity, size, tutorial)
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _exercise(packed: PackedScene, activity: String, dims: Vector2i,
		tutorial: bool) -> void:
	root.size = dims
	root.content_scale_size = Vector2i(1280, 720)
	var name := "%s %s %s" % [activity, dims, "Tutorial" if tutorial else "Play"]
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(false)
	var udp := PacketPeerUDP.new()
	_expect(udp.bind(0, "127.0.0.1") == OK,
		name + " localhost UDP mock camera binds")
	pose.peer = udp
	pose.worker_pid = OS.get_process_id()
	pose.session_token = "shared-stress-mock-session"
	_set_observation(true, TRACK_ID, 1, "locked")
	pose.set("calibration", {"valid": true, "left": 0.2, "center": 0.5,
		"right": 0.8})
	pose.set("plane_calibration", {"valid": true, "mode": "plane_stationary",
		"center": 0.5, "sensitivity": 0.18, "deadzone": 0.018,
		"neutral_only": true, "camera_center_x": 0.5})
	if activity == "Human Plane":
		pose.set("calibration", (pose.get("plane_calibration") as Dictionary).duplicate(true))
	var wrapper := packed.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrapper.set_context({"activity": activity, "entry_source": "tutorial" if tutorial else "play",
			"guided_tutorial": tutorial, "camera_live": true, "start_countdown": true,
		"game_mode": "Seconds", "topic": "Noun", "keyboard_mode": false,
		"calibration_measured": true, "calibration_valid": true})
	await process_frame
	await process_frame
	var game := wrapper.get("active_game") as Control
	_expect(game != null, name + " mounts its real minigame scene")
	if game == null:
		pose.worker_pid = -1
		wrapper.queue_free()
		await process_frame
		return
	wrapper.set_process(false)
	game.set_process(false)
	_expect(String(wrapper.get("guided_stage")) == "countdown",
		name + " calibrated Play and Tutorial start at direct 3-2-1")
	_expect(wrapper.get("countdown_panel") is Control
		and game.process_mode == Node.PROCESS_MODE_DISABLED,
		name + " direct countdown freezes gameplay until GO")
	if String(wrapper.get("guided_stage")) == "countdown":
		# Tick only until GO and keep authenticated SOLO packets fresh for
		# the same measured camera; preserve occlusion checks after GO.
		for tick in range(5):
			if String(wrapper.get("guided_stage")) != "countdown":
				break
			_set_observation(true, TRACK_ID, 1, "locked")
			wrapper.call("_on_countdown_tick")
	_expect(String(wrapper.get("guided_stage")) == "" and game.process_mode == Node.PROCESS_MODE_INHERIT,
		name + " GO enables the same measured game without recalibration")
	_set_observation(true, TRACK_ID, 1, "locked")
	wrapper.call("_process", 1.0 / 60.0)
	_expect(not bool(wrapper.get("tracking_suspended")) and
		not (wrapper.get("tracking_notice") as Control).visible,
		name + " exactly one fresh person can play")
	_set_observation(false, -1, 1, "waiting")
	wrapper.call("_process", 12.0)
	_expect(not bool(wrapper.get("tracking_suspended")) and
		game.process_mode != Node.PROCESS_MODE_DISABLED and
		not bool(wrapper.get("last_pose_valid")) and
		not (wrapper.get("tracking_notice") as Control).visible,
		name + " 12s of fresh SOLO occupancy pose=false means PLAY, no ghost input")
	pose.set("_last_occupancy_packet_ms", Time.get_ticks_msec() - 2200)
	wrapper.call("_process", 0.016)
	_expect(bool(wrapper.get("tracking_suspended")) and
		game.process_mode == Node.PROCESS_MODE_DISABLED,
		name + " stale occupancy freezes even when cached raw people count is one")
	_set_observation(false, -1, 1, "waiting")
	wrapper.call("_process", 0.016)
	_expect(not bool(wrapper.get("tracking_suspended")) and
		game.process_mode != Node.PROCESS_MODE_DISABLED,
		name + " fresh single-person occupancy resumes despite pose=false")
	_set_observation(true, TRACK_ID, 1, "locked")
	wrapper.call("_process", 0.016)
	var score_before: int = int(game.get("score")) if _has_prop(game, "score") else 0
	var calibration_before: Dictionary = (pose.get("calibration") as Dictionary).duplicate(true)
	_set_observation(true, TRACK_ID, 2, "locked")
	wrapper.call("_process", 0.8)
	_expect(bool(wrapper.get("tracking_suspended")) and game.process_mode == Node.PROCESS_MODE_DISABLED,
		name + " two people pause gameplay even when initial player is detected")
	_set_observation(true, TRACK_ID + 1, 2, "locked")
	wrapper.call("_process", 0.7)
	var crowd_notice := wrapper.get("tracking_notice") as Control
	var crowd_title := crowd_notice.get_node_or_null("Title") as Label
	_expect(crowd_notice.visible and crowd_title != null and crowd_title.text == "ONLY ONE PLAYER!",
		name + " crowd displays ONLY ONE PLAYER rather than missing camera prompt")
	_expect(bool(wrapper.get("tracking_suspended")), name + " bystander tracker cannot unpause a crowd")
	_set_observation(true, TRACK_ID + 2, 3, "locked")
	wrapper.call("_process", 0.7)
	_expect(bool(wrapper.get("tracking_suspended")), name + " three people also pause the round")
	_set_observation(false, -1, 2, "occluded")
	wrapper.call("_process", 0.75)
	_expect(crowd_notice.visible and crowd_title != null and crowd_title.text == "ONLY ONE PLAYER!",
		name + " occluded student with two visible people shows crowd warning")
	_expect(bool(wrapper.get("tracking_suspended")),
		name + " lost/occluded student pauses real minigame after grace period")
	_set_observation(false, -1, 2, "recovering")
	wrapper.call("_process", 1.4)
	_expect(not (wrapper.get("tracking_notice") as Control).visible,
		name + " warmup/recovering status does not masquerade as student absence")
	# A genuine fresh YOLO observation of an empty frame is the only evidence
	# permitting the persistent return-to-camera message.
	for frame in range(2):
		_set_observation(false, -1, 0, "waiting")
		wrapper.call("_process", 0.7)
	_expect((wrapper.get("tracking_notice") as Control).visible,
		name + " repeated fresh zero-person packets trigger return guidance")
	_set_observation(true, TRACK_ID + 19, 1, "locked")
	wrapper.call("_process", 1.0 / 60.0)
	_expect(not bool(wrapper.get("tracking_suspended")) and
		game.process_mode != Node.PROCESS_MODE_DISABLED and
		not (wrapper.get("tracking_notice") as Control).visible,
		name + " one person resumes same round despite changing camera ID")
	_expect((pose.get("calibration") as Dictionary) == calibration_before,
		name + " first measured calibration is retained")
	if _has_prop(game, "score"):
		_expect(int(game.get("score")) == score_before,
			name + " tracking warnings/occlusion cannot generate phantom scores")
	for duration in [5.0, 15.0, 60.0]:
		_set_observation(false, -1, 0, "waiting")
		wrapper.call("_process", duration)
		_expect(bool(wrapper.get("tracking_suspended")) and
			game.process_mode == Node.PROCESS_MODE_DISABLED,
			name + " %ss camera rest freezes round" % duration)
		_set_observation(true, TRACK_ID + 23, 1, "locked")
		wrapper.call("_process", 1.0 / 60.0)
		_expect(not bool(wrapper.get("tracking_suspended")) and
			game.process_mode == Node.PROCESS_MODE_INHERIT,
			name + " %ss camera rest resumes without recalibration" % duration)
		_expect((pose.get("calibration") as Dictionary) == calibration_before,
			name + " %ss rest does not clear measured positions" % duration)
	wrapper.call("preserve_camera_for_restart")
	pose.worker_pid = -1 # Preserve route still must NEVER retain Godot PID.
	wrapper.queue_free()
	await process_frame
	await process_frame


func _set_observation(present: bool, locked_id: int, people: int, lock: String) -> void:
	pose.set("active", true)
	var when: int = Time.get_ticks_msec()
	var state := {"token": pose.session_token, "kind": "pose",
		"camera_phase": "tracking", "state": "tracking" if lock in ["locked", "waiting", "occluded"] else lock,
		"camera": true,
		# Match JSON.parse_string values from the real Python worker: a JSON
		# integer may arrive in Godot as numeric float 0.0/1.0/2.0.
		"pose": present, "people": float(people), "lock_state": lock,
		"camera_frame_age_ms": 20,
		"locked_id": locked_id, "x": 0.5 if present else -1.0,
		"plane_steering": 0.5, "plane_steering_valid": present,
		"plane_neutral_valid": present,
			"plane_bank": 0.35, "plane_bank_valid": present,
			"plane_t_pose_valid": present,
		"hand_observation_valid": present}
	pose.call("_apply_pose_packet", state, when)
	# Keep the measured calibration untouched by subsequent camera observations.


func _has_prop(instance: Object, property_name: String) -> bool:
	for entry in instance.get_property_list():
		if String(entry.get("name", "")) == property_name:
			return true
	return false


func _expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		errors.append(label)
		printerr("TRACKING SHARED FLOW FAIL: ", label)


func _finish() -> void:
	print("SHARED CAMERA LOCK/OCCLUSION STRESS: %s checks=%d failures=%d" % [
		"PASS" if errors.is_empty() else "FAIL", checks, errors.size()])
	quit(0 if errors.is_empty() else 1)
