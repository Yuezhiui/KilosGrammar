extends SceneTree

# Isolated foreground acceptance stress. No webcam/Python/DB/release writes.
# Godot 4.7.2 --headless --path . --script res://tools/test_foreground_camera_acceptance_20261030.gd
const CALIBRATION := "res://ui/vision/calibration/calibration.tscn"
const GAMEPLAY := "res://ui/play/gameplay/gameplay.tscn"
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]

var pose: Node
var transport: PacketPeerUDP
var checks := 0
var failures: Array[String] = []
var source_when := 1000.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	if not _check(pose != null, "PoseService autoload loads"):
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	transport = PacketPeerUDP.new()
	if not _check(transport.bind(0, "127.0.0.1") == OK, "synthetic loopback binds"):
		_finish()
		return
	pose.peer = transport
	# Test only: OS.is_process_running() must see a real PID. Clear it before
	# stop_camera() so teardown cannot terminate this Godot test process.
	pose.worker_pid = OS.get_process_id()
	pose.session_token = "foreground-acceptance-fixture"
	pose.active = true
	_send(2, 1, false, true, true, 1, 0.50)
	_check(pose.fresh_raw_camera_population() == 2, "raw two-person detection retained for diagnostics")
	_check(pose.fresh_camera_population() == 1 and pose.has_valid_pose(),
		"single safe foreground remains accepted with distant spectator")
	_check(pose.has_verified_foreground_player() and pose.has_fresh_solo_presence(),
		"verified lock authorizes the enrolled foreground student")
	var preview := PackedByteArray([2])
	preview.append_array("1000.123456,1,2,25,1;".to_ascii_buffer())
	preview.append_array(PackedByteArray([255, 216, 255, 217]))
	var decoded: Dictionary = pose.call("_decode_preview_packet", preview)
	_check(int(decoded.get("people", -1)) == 2 and
		int(decoded.get("foreground_people", -1)) == 1,
		"5-field JPEG preview preserves raw2 while drawing one foreground")
	var old_preview := PackedByteArray([2])
	old_preview.append_array("1000.123456,1,2,25;".to_ascii_buffer())
	old_preview.append_array(PackedByteArray([255, 216, 255, 217]))
	_check((pose.call("_decode_preview_packet", old_preview) as Dictionary).is_empty(),
		"obsolete four-field JPEG with no foreground count fails closed")
	var initial_epoch: int = int(pose.get("_bound_player_epoch"))
	_check(initial_epoch == 1, "first real foreground lock binds to this round")

	_send(2, 1, true, true, true, 1, 0.50)
	_check(pose.foreground_is_ambiguous() and pose.fresh_camera_population() == -1,
		"near overlapping person immediately marks foreground ambiguous")
	_check(not pose.has_valid_pose() and not pose.has_verified_foreground_player(),
		"ambiguous foreground cannot steer or keep a verified player")
	_send(2, 2, true, false, false, 1, 0.50)
	_check(not pose.has_valid_pose() and pose.foreground_is_ambiguous(),
		"two near people cannot impersonate selected player")
	_send(2, 0, false, false, false, 1, -1.0)
	_check(pose.fresh_camera_population() == 0 and pose.has_recent_missing_student_observation(),
		"no near person is missing even when two background people appear")
	_send(2, 1, false, false, false, 1, 0.52)
	_check(not pose.has_valid_pose() and int(pose.get("_bound_player_epoch")) == 1,
		"temporary low-confidence frame preserves original bound lock")
	_check(not pose.has_verified_foreground_player(),
		"foreground count alone never authenticates an occluded/unlocked passerby")
	_send(2, 1, false, true, true, 1, 0.52)
	_check(pose.has_valid_pose(), "same authenticated player resumes after transient occlusion")
	_send(2, 1, false, true, true, 2, 0.51)
	_check(not pose.has_valid_pose() and not pose.has_verified_foreground_player(),
		"different lock epoch cannot inherit current player's calibration")
	_send(2, 1, false, true, true, 1, 0.50)
	_check(pose.has_valid_pose(), "original epoch can still return")
	var malformed := _packet(2, 1, false, true, true, 1, 0.50)
	malformed.erase("foreground_people")
	pose.call("_apply_pose_packet", malformed, Time.get_ticks_msec())
	_check(pose.fresh_camera_population() == -1 and not pose.has_valid_pose(),
		"missing foreground metadata rejects source even if raw and pose look valid")
	malformed = _packet(2, 1, false, true, true, 1, 0.50)
	malformed["foreground_people"] = 1.5
	pose.call("_apply_pose_packet", malformed, Time.get_ticks_msec())
	_check(not pose.has_valid_pose() and pose.fresh_camera_population() == -1,
		"fractional foreground count fails closed")
	malformed = _packet(2, 1, false, true, true, 1, 0.50)
	malformed.erase("player_lock_epoch")
	pose.call("_apply_pose_packet", malformed, Time.get_ticks_msec())
	_check(not pose.has_valid_pose(), "missing player epoch never grants motion")
	malformed = _packet(2, 1, false, true, true, 1, 0.50)
	malformed.erase("occupancy_verified")
	pose.call("_apply_pose_packet", malformed, Time.get_ticks_msec())
	_check(not pose.has_valid_pose() and pose.fresh_camera_population() == -1,
		"missing occupancy verification does not allow foreground control")
	_send(2, 1, false, true, true, 1, 0.50)
	var samples_before: int = pose.latest_pose_sample_id
	for i in range(40):
		var packet := _packet(2, 1, i % 4 == 0, true, true, 1, 0.5)
		pose.call("_record_fresh_calibration_pose", packet, source_when)
		source_when += 0.04
	_check(pose.latest_pose_sample_id - samples_before == 30,
		"40 source frames with ten ambiguous overlaps earn only 30 genuine samples")

	await _test_calibration()
	for activity: String in ACTIVITIES:
		await _test_gameplay(activity)
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _packet(raw: int, foreground: int, ambiguous: bool,
		verified: bool, has_pose: bool, epoch: int, x: float) -> Dictionary:
	return {
		"token": pose.session_token, "kind": "pose", "when": source_when,
		"state": "tracking", "camera": true, "camera_phase": "tracking",
		"people": raw, "foreground_people": foreground,
		"foreground_ambiguous": ambiguous, "occupancy_verified": verified,
		"lock_state": "locked" if verified else "ambiguous" if ambiguous else "occluded",
		"player_lock_epoch": epoch, "locked_id": -1,
		"pose": has_pose, "x": x, "camera_frame_age_ms": 25,
		"hand_observation_valid": has_pose, "hand_up": false,
		"both_hands_down": has_pose, "both_hands_up": false,
		"calibration_hand_observation_valid": has_pose,
		"calibration_both_hands_down": has_pose, "calibration_both_hands_up": false,
		"plane_bank_valid": has_pose, "plane_bank": 0.0,
		"plane_steering_valid": has_pose, "plane_steering": 0.0,
		"plane_neutral_valid": has_pose, "plane_t_pose_valid": has_pose
	}


func _send(raw: int, foreground: int, ambiguous: bool,
		verified: bool, has_pose: bool, epoch: int, x: float,
		add_sample: bool = false) -> void:
	var packet := _packet(raw, foreground, ambiguous, verified, has_pose, epoch, x)
	source_when += 0.4
	pose.call("_apply_pose_packet", packet, Time.get_ticks_msec())
	if add_sample:
		pose.call("_record_fresh_calibration_pose", packet, source_when)


func _test_calibration() -> void:
	pose.begin_new_round_tracking()
	_send(2, 1, false, true, true, 1, 0.50)
	var calibration_scene := load(CALIBRATION) as PackedScene
	if not _check(calibration_scene != null, "real authored calibration loads after autoload"):
		return
	var view := calibration_scene.instantiate() as Control
	root.add_child(view)
	view.set_context({"activity": "Catch the Word"})
	view.set_process(false)
	view.intro_running = false
	view.call("_finish_intro_only")
	var zones := [0.50, 0.80, 0.20]
	for stage in range(zones.size()):
		var zone: float = zones[stage]
		# Foreground position is smoothed by the real production PoseService.
		# A child walking to RIGHT/LEFT can need settling frames before the
		# stationary 3-second/8-frame hold starts.
		for frame in range(32):
			if int(view.live_step) > stage:
				break
			_send(2, 1, false, true, true, 1, zone, true)
			view.call("_process", 0.41)
			if stage == 0 and frame == 3:
				_send(2, 1, true, false, true, 1, zone)
				view.call("_process", 0.016)
				_check(view.live_samples.is_empty() and is_zero_approx(view.live_timer),
					"near-player ambiguity immediately resets an unfinished calibration hold")
		_check(int(view.live_step) > stage,
			"3-second/8-fresh-frame hold completes foreground zone %s; step=%d timer=%s samples=%d" %
			[str(zone), int(view.live_step), str(view.live_timer), view.live_samples.size()])
	_check(bool(pose.calibration.get("valid", false)),
		"real Catch calibration accepts raw=2 when foreground=1 for all three positions")
	# Calibration exit normally closes the real child process. Synthetic
	# transport uses this test's PID; preserve its fake camera for gameplay QA.
	view.passing_to_ready = true
	view.queue_free()
	await process_frame


func _test_gameplay(activity: String) -> void:
	pose.begin_new_round_tracking()
	_send(2, 1, false, true, true, 1, 0.50)
	if activity == "Human Plane":
		_check(pose.set_stationary_plane_calibration(0.5, -1, 0.5, 0.01), "plane neutral calibrated")
	else:
		_check(pose.set_calibration(0.2, 0.5, 0.8), "three positions calibrated")
	var gameplay_scene := load(GAMEPLAY) as PackedScene
	if not _check(gameplay_scene != null, "real authored gameplay loads after autoload"):
		return
	var wrapper := gameplay_scene.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_process(false)
	wrapper.set_context({"activity": activity, "camera_live": true,
		"calibration_measured": true, "start_countdown": true,
		"guided_tutorial": false, "keyboard_mode": false,
		"game_mode": "Seconds", "difficulty": "Easy", "topic": "Noun"})
	await process_frame
	await process_frame
	for _i in range(3):
		wrapper.call("_on_countdown_tick")
	var game := wrapper.active_game as Control
	if not _check(game != null and game.process_mode != Node.PROCESS_MODE_DISABLED,
		activity + " enters live gameplay with foreground1/raw2"):
		wrapper.call("preserve_camera_for_restart")
		wrapper.queue_free()
		await process_frame
		return
	for i in range(48):
		_send(2, 1, false, true, true, 1, 0.5 + 0.03 * sin(float(i) * 0.1))
		wrapper.call("_process", 0.016)
		_check(not wrapper.tracking_suspended and game.process_mode != Node.PROCESS_MODE_DISABLED,
			activity + " continues with distant spectators, sample " + str(i))
	_send(2, 1, true, true, true, 1, 0.50)
	wrapper.call("_process", 0.016)
	_check(wrapper.tracking_suspended and game.process_mode == Node.PROCESS_MODE_DISABLED,
		activity + " immediately freezes on near ambiguity")
	_send(2, 1, false, true, true, 2, 0.50)
	wrapper.call("_process", 0.016)
	_check(wrapper.tracking_suspended, activity + " cannot auto-promote new lock epoch")
	_send(2, 1, false, true, true, 1, 0.50)
	wrapper.call("_process", 0.016)
	_check(not wrapper.tracking_suspended and game.process_mode != Node.PROCESS_MODE_DISABLED,
		activity + " resumes same verified foreground after ambiguity")
	wrapper.call("preserve_camera_for_restart")
	wrapper.queue_free()
	await process_frame
	await process_frame


func _check(ok: bool, description: String) -> bool:
	checks += 1
	if not ok:
		failures.append(description)
	return ok


func _finish() -> void:
	for reason: String in failures:
		printerr("FAIL foreground GDScript acceptance: ", reason)
	print("%s foreground GDScript acceptance: %d checks, %d failures" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
