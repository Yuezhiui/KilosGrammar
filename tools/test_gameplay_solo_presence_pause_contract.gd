extends SceneTree

## User's new rule AFTER actual calibration and GO: one fresh YOLO person
## keeps the round PLAYING, even with NO pose, NO wrist, changing IDs, or
## another child replacing the first sole occupant. No webcam/DB/Git writes.
## Run: godot --headless --path . --script res://tools/test_gameplay_solo_presence_pause_contract.gd
const GAMEPLAY_PATH := "res://ui/play/gameplay/gameplay.tscn"
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const MODES := [false, true] # Play and Tutorial, AFTER their 3-2-1 has finished
const UPDATE_DELTA := 0.25

var pose: Node
var packed: PackedScene
var checks := 0
var failures: Array[String] = []
var finished := false


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(30.0).timeout
	if not finished:
		_check(false, "contract fixture exceeded 30s; cannot use a physical camera")
		_finish()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	packed = load(GAMEPLAY_PATH) as PackedScene
	if pose == null or packed == null:
		_check(false, "production PoseService and gameplay scene load")
		_finish()
		return
	for tutorial: bool in MODES:
		for activity: String in ACTIVITIES:
			await _exercise(activity, tutorial)
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _exercise(activity: String, tutorial: bool) -> void:
	var label := "%s %s" % [activity, "Tutorial" if tutorial else "Play"]
	pose.stop_camera()
	pose.set_process(false)
	# A synthetic *authenticated* live UDP service is needed to test the
	# production strict population gate. No Python worker/webcam is launched.
	var test_transport := PacketPeerUDP.new()
	_check(test_transport.bind(0, "127.0.0.1") == OK,
		label + " synthetic localhost status transport binds without camera")
	pose.set("peer", test_transport)
	# OS.is_process_running must see a live process. Never let stop_camera()
	# kill the test itself: clear this diagnostic PID before teardown.
	pose.set("worker_pid", OS.get_process_id())
	pose.session_token = "synthetic-solo-presence"
	pose.active = true
	_packet(1, true, "locked", 41, 0.50, 30)
	if activity == "Human Plane":
		_check(pose.set_stationary_plane_calibration(0.5, -1, 0.5, 0.01),
			label + " real neutral calibration recorded before game")
	else:
		_check(pose.set_calibration(0.2, 0.5, 0.8),
			label + " real three-point calibration recorded before game")
	var original_calibration: Dictionary = pose.calibration.duplicate(true)
	var wrapper := packed.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_process(false)
	var navigation: Array[String] = []
	wrapper.requested.connect(func(destination: String, _payload: Dictionary) -> void:
		navigation.append(destination))
	wrapper.set_context({"activity": activity,
		"entry_source": "tutorial" if tutorial else "play",
		"guided_tutorial": tutorial, "camera_live": true,
		"calibration_measured": true, "start_countdown": true,
		"keyboard_mode": false, "game_mode": "Seconds",
		"topic": "Noun", "difficulty": "Easy"})
	await process_frame
	await process_frame
	var game := wrapper.get("active_game") as Control
	if game == null:
		_check(false, label + " real game mounts")
		wrapper.queue_free()
		await process_frame
		return
	var game_id := game.get_instance_id()
	if tutorial:
		wrapper.call("_on_spotlight_finished")
	await process_frame
	# The newer presence-only contract starts AFTER the original calibration
	# and actual 3-2-1; a missing pose at GO is NOT authorized to skip that gate.
	for _tick in range(3):
		wrapper.call("_on_countdown_tick")
	_check(String(wrapper.guided_stage) == "" and
		game.process_mode == Node.PROCESS_MODE_INHERIT,
		label + " completed genuine calibrated countdown before presence policy")
	game.set_process(false) # manually tick time only when gameplay is running
	var notice := wrapper.get_node_or_null("TrackingNoticeLayer/TrackingNotice") as Control
	var title := notice.get_node_or_null("Title") as Label
	var initial_clock := float(game.get("time_remaining"))
	var initial_score := float(game.get("score"))
	var initial_lives := float(game.get("lives")) if game.get("lives") != null else -1.0
	var transitions := 0
	var prior_suspended := bool(wrapper.tracking_suspended)
	if activity == "Balloon Popping":
		# A valid body may have set launcher motion just before YOLO loses
		# its torso keypoints. Presence keeps the game running, but the last
		# launcher instruction must be revoked on the very first invalid frame.
		_packet(1, true, "locked", 41, 0.70, 25)
		wrapper.call("_process", 0.016)
		game.set("body_target_timer", 0.30)
		game.set("launcher_velocity", 240.0)
		_packet(1, false, "occluded", -1, 0.70, 25)
		wrapper.call("_process", 0.016)
		_check(float(game.get("body_target_timer")) == 0.0 \
			and float(game.get("launcher_velocity")) == 0.0,
			label + " stale launcher velocity/target cleared despite continuing round")
	# A present child may be poorly tracked for MANY seconds: still PLAYING and
	# ticking the round clock, but not driving the body or triggering gestures.
	for i in range(12):
		var x := 0.46 + 0.035 * sin(float(i) * 0.7)
		_packet(1, false, "waiting" if i % 2 == 0 else "lost", -1, x, 25)
		wrapper.call("_process", 1.0)
		transitions += 1 if bool(wrapper.tracking_suspended) != prior_suspended else 0
		prior_suspended = bool(wrapper.tracking_suspended)
		_check(_live_no_pause(wrapper, game, notice),
			label + " people=1 / pose=false retains PLAY and no pause notice at second %d" % (i + 1))
		_check(not bool(wrapper.last_pose_valid) and not pose.has_valid_pose(),
			label + " missing pose cannot reuse stale body movement at second %d" % (i + 1))
		if activity == "Human Plane":
			_check(not bool(game.get("airplane_pose_active")),
				label + " no wrist/pose disables airplane steering")
		elif activity == "Balloon Popping":
			_check(not bool(game.get("hand_raise_tracking_valid")),
				label + " no wrist/pose disables balloon shooting")
		_tick_game_when_enabled(game, 0.20)
	_check(transitions == 0, label + " 12s of pose=false never toggles PAUSE/PLAY (%d toggles)" % transitions)
	_check(initial_clock - float(game.get("time_remaining")) >= 2.35,
		label + " round Seconds clock advances during 12s visible-but-untracked solo")
	_check(float(game.get("score")) == initial_score and
		(float(game.get("lives")) if game.get("lives") != null else -1.0) == initial_lives,
		label + " poor pose alone does not add score or spend hearts")
	# Wrist invisibility is separate from a missing whole pose. Human Plane's
	# arm-steering gate must not silently become a timer/pause gate.
	_packet(1, true, "locked", 41, 0.61, 25, false)
	wrapper.call("_process", UPDATE_DELTA)
	_check(_live_no_pause(wrapper, game, notice),
		label + " no visible wrists / neutral pose gate does not suspend round")
	if activity == "Human Plane":
		_check(not bool(game.get("airplane_pose_active")) and not bool(wrapper.last_pose_valid),
			label + " missing wrist never arms airplane steering")
	_tick_game_when_enabled(game, 0.20)
	# First child leaves, second CHILD replaces them. Empty frame is safe
	# immediate pause; as soon as new sole occupant is detected, PLAY resumes
	# even without an ID, no healthy pose, or completion of a StudentLock latch.
	_packet(0, false, "lost", -1, -1.0, 25)
	wrapper.call("_process", UPDATE_DELTA)
	_check(_frozen(wrapper, game, notice), label + " zero people immediately freeze round")
	_check(title != null and title.text == "COME BACK INTO THE CAMERA!",
		label + " zero people show missing-person warning")
	_packet(1, false, "waiting", -1, 0.78, 25)
	wrapper.call("_process", UPDATE_DELTA)
	_check(_live_no_pause(wrapper, game, notice),
		label + " new solo passerby starts PLAY before tracker enrolls (no ID)")
	_packet(1, false, "lost", 9003, 0.80, 25)
	wrapper.call("_process", UPDATE_DELTA)
	_check(_live_no_pause(wrapper, game, notice),
		label + " different sole person's re-enrollment never freezes same round")
	_packet(1, true, "locked", 9003, 0.79, 25)
	wrapper.call("_process", UPDATE_DELTA)
	_check(_live_no_pause(wrapper, game, notice) and bool(wrapper.last_pose_valid),
		label + " fresh new-ID solo pose restores movement without restarting game")
	# Crowds are never afforded a pose-confidence grace period, including a
	# stale body-pose=true packet that pretends to come from one player.
	for count in [2, 3]:
		_packet(count, true, "ambiguous", 9003, 0.79, 25)
		wrapper.call("_process", 0.016)
		_check(_frozen(wrapper, game, notice),
			label + " %d people immediately freeze game, even if pose=true" % count)
		_check(title != null and title.text == "ONLY ONE PLAYER!",
			label + " %d people show multiple-person warning" % count)
		_packet(1, false, "waiting", -1, 0.51, 25)
		wrapper.call("_process", UPDATE_DELTA)
		_check(_live_no_pause(wrapper, game, notice),
			label + " exactly one person resumes after %d-person crowd, even pose=false" % count)
	# A zero/multiple count is not safe if it comes from an obsolete UDP frame;
	# unknown/stale UDP means freeze until a fresh *new* occupancy observation.
	_packet(1, false, "waiting", -1, 0.5, 25)
	pose.set("_last_packet_ms", Time.get_ticks_msec() - 1400)
	pose.set("_last_occupancy_packet_ms", Time.get_ticks_msec() - 1400)
	wrapper.call("_process", 0.016)
	_check(_frozen(wrapper, game, notice),
		label + " stale UDP arrival freezes even last count=1")
	_packet(1, false, "waiting", -1, 0.5, 1900)
	wrapper.call("_process", 0.016)
	_check(_frozen(wrapper, game, notice),
		label + " source frame age 1900ms cannot authorize stale count=1")
	_packet(1, false, "waiting", -1, 0.5, 25)
	wrapper.call("_process", 0.016)
	_check(_live_no_pause(wrapper, game, notice),
		label + " NEW valid one-person detection recovers after stale UDP")
	for unknown in [null, 1.5]:
		_packet(1, false, "waiting", -1, 0.5, 25)
		var data: Dictionary = pose.current_status.duplicate()
		data["people"] = unknown
		pose.set("current_status", data)
		wrapper.call("_process", 0.016)
		_check(_frozen(wrapper, game, notice),
			label + " unknown or fractional detected_count=%s cannot authorize PLAY" % str(unknown))
	# Godot JSON often yields 1.0 rather than int 1. It is EXACT one.
	_packet(1, false, "waiting", -1, 0.5, 25)
	var fractional: Dictionary = pose.current_status.duplicate()
	fractional["people"] = 1.0
	pose.set("current_status", fractional)
	wrapper.call("_process", 0.016)
	_check(_live_no_pause(wrapper, game, notice),
		label + " JSON float detected_count=1.0 is an exact SOLO observation")
	_check(wrapper.active_game.get_instance_id() == game_id and
		pose.calibration == original_calibration and navigation.is_empty(),
		label + " same scene/score/calibration survives substitution and recovery")
	wrapper.call("preserve_camera_for_restart")
	wrapper.queue_free()
	await process_frame
	await process_frame
	pose.set("worker_pid", -1)
	pose.stop_camera()


func _packet(people: int, has_pose: bool, lock_state: String, id: int,
		x: float, source_age_ms: int, valid_wrists: bool = true) -> void:
	var packet: Dictionary = {"token": String(pose.session_token),
		"kind": "pose", "state": "tracking", "camera": true,
		"camera_phase": "tracking", "people": people, "pose": has_pose,
		"lock_state": lock_state, "locked_id": id, "x": x,
		"camera_frame_age_ms": source_age_ms,
		"plane_steering": x, "plane_steering_valid": has_pose and valid_wrists,
		"plane_neutral_valid": has_pose and valid_wrists,
			"plane_bank": 0.35, "plane_bank_valid": has_pose and valid_wrists,
			"plane_t_pose_valid": has_pose and valid_wrists,
		"hand_observation_valid": has_pose and valid_wrists,
		"hand_up": false, "airplane_pose": false}
	pose.call("_apply_pose_packet", packet, Time.get_ticks_msec())


func _tick_game_when_enabled(game: Control, dt: float) -> void:
	# Manual minigame clock tick only if its process mode allows gameplay to run.
	# This distinguishes "hide the pause notice" from true game-time progress.
	if game.process_mode != Node.PROCESS_MODE_DISABLED:
		game.call("_process", dt)


func _live_no_pause(wrapper: Control, game: Control, notice: Control) -> bool:
	return game.process_mode != Node.PROCESS_MODE_DISABLED \
		and not bool(wrapper.tracking_suspended) and not notice.visible


func _frozen(wrapper: Control, game: Control, notice: Control) -> bool:
	return game.process_mode == Node.PROCESS_MODE_DISABLED and bool(wrapper.tracking_suspended) \
		and not bool(wrapper.last_pose_valid)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("SOLO PRESENCE CONTRACT FAIL: ", label)


func _finish() -> void:
	if finished:
		return
	finished = true
	if pose != null:
		pose.set("worker_pid", -1)
		pose.stop_camera()
	print("SOLO PRESENCE PLAY CONTRACT: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
