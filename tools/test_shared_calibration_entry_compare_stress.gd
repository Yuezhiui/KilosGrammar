extends SceneTree

## Real calibration.tscn for BOTH Play and Tutorial entry sources, with the
## same PoseService and real source-shaped unique timestamps. Never starts a
## camera process: the service is marked active with an OFFLINE observation
## before set_context, and all script processing is manually stepped.
## godot --headless --path . --script res://tools/test_shared_calibration_entry_compare_stress.gd
const SCENE := "res://ui/vision/calibration/calibration.tscn"
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const ID := 203
var pose: Node
var failures: Array[String] = []
var checks := 0
var timestamp := 1000.0
var captures: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(30.0).timeout
	_assert(false, "Shared-calibration test exceeded no-device watchdog")
	quit(1)


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	_assert(pose != null, "Single production PoseService is available")
	if pose == null:
		_finish()
		return
	var scene := load(SCENE) as PackedScene
	_assert(scene != null, "Play and Tutorial use one real calibration.tscn")
	if scene == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	for size in SIZES:
		root.size = size
		root.content_scale_size = Vector2i(1280, 720)
		for activity in ACTIVITIES:
			for source in ["play", "tutorial"]:
				await _compare_calibration(scene, activity, source, size)
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _compare_calibration(scene: PackedScene, activity: String,
		source: String, dimensions: Vector2i) -> void:
	# This is a NO-CAMERA simulation; the fixture impersonates the strict raw
	# SOLO packet envelope only after checking that nothing started a worker.
	# Never pass the test runner PID to stop_camera() during cleanup.
	pose.stop_camera()
	pose.set("active", true)
	pose.set("_ever_tracked", false)
	pose.set("current_status", {"state": "loading", "pose": false,
		"camera": true, "people": 0, "lock_state": "waiting"})
	pose.set("player_x", -1.0)
	var prefix := "%s / %s / %s" % [dimensions, activity, source]
	var screen := scene.instantiate() as Control
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.set_process(false)
	screen.set_context({"entry_source": source, "guided_tutorial": source == "tutorial",
		"activity": activity, "game_mode": "Seconds", "camera_requested": true,
		"keyboard_mode": false, "student_name": "SIMULATED QA ONLY"})
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(target: String, data: Dictionary) -> void:
		routes.append({"route": target, "data": data.duplicate(true)}))
	_assert(pose.worker_pid == -1 and pose.peer == null,
		prefix + " warmup is simulated: no webcam/worker/UDP listener launched")
	screen.call("_process", 3.01)
	_assert(int(screen.get("live_step")) == 0 and routes.is_empty(),
		prefix + " intro/warmup status cannot credit calibration samples")
	screen.call("_continue_flow", true)
	screen.call("_continue_flow", false)
	_assert(routes.is_empty(), prefix + " neither Continue nor Skip bypasses real poses")
	_assert(screen.call("_capture_order") == (["CENTER"] if activity == "Human Plane"
		else (["LEFT", "CENTER", "RIGHT"] if activity == "Balloon Popping" else ["CENTER", "RIGHT", "LEFT"])),
		prefix + " same calibration scene uses activity-specific real hold order")
	# Authenticated, current-session raw occupancy is required to release the
	# SUCCESS overlay. A bare fake 'people=1' status must not bypass that gate.
	pose.set("peer", PacketPeerUDP.new())
	pose.set("worker_pid", OS.get_process_id())
	pose.set("session_token", "simulated-calibration-%s-%s" % [activity, source])
	pose.set("_last_occupancy_packet_ms", Time.get_ticks_msec())
	if activity == "Human Plane":
		for frame in range(8):
			_push_packet(screen, 0.50, 0.0, 0.43)
		_assert(int(screen.get("live_step")) == 1 and
			bool((pose.get("plane_calibration") as Dictionary).get("neutral_only", false)),
			prefix + " full verified 3-second neutral T-pose hold completes Human Plane")
	else:
		var positions := [0.20, 0.50, 0.80] if activity == "Balloon Popping" else [0.50, 0.80, 0.20]
		for zone_x in positions:
			for raised in ([false, true] if activity == "Balloon Popping" else [false]):
				for frame in range(34):
					_push_packet(screen, zone_x, zone_x, 0.1, raised)
		_assert(int(screen.get("live_step")) == 3 and
			bool((pose.get("calibration") as Dictionary).get("valid", false)),
			prefix + " actual three floor holds complete non-plane calibration")
	_assert(bool(screen.get("transition_queued")),
		prefix + " completed real hold automatically schedules shared gameplay handoff")
	# SUCCESS is a separate 3s safety interval after genuine holds. The
	# timestamped synthetic SOLO packet remains current during this step.
	pose.set("_last_occupancy_packet_ms", Time.get_ticks_msec())
	screen.call("_process", 3.01)
	# Auto handoff may have already emitted gameplay; this must be idempotent.
	screen.call("_continue_flow", false)
	_assert(routes.size() == 1 and String(routes[0].get("route", "")) == "gameplay",
		prefix + " accepted live calibration routes directly into gameplay")
	if not routes.is_empty():
		var data: Dictionary = routes[0]["data"]
		_assert(String(data.get("entry_source", "")) == source and
			bool(data.get("guided_tutorial", false)) == (source == "tutorial"),
			prefix + " original Play/Tutorial identity survives calibration unchanged")
		_assert(bool(data.get("camera_live", false)) and
			bool(data.get("calibration_measured", false)) and
			bool(data.get("start_countdown", false)) and
			not bool(data.get("keyboard_mode", true)),
			prefix + " shared handoff uses real camera/countdown, never keyboard fallback")
		if activity == "Human Plane":
			_assert(bool(data.get("calibration_neutral_only", false)) and
				not data.has("calibration_left") and
				not data.has("calibration_right"),
				prefix + " Human Plane never fabricates side measurements")
		else:
			_assert(data.has("calibration_left") and data.has("calibration_right"),
				prefix + " Catch/Balloon retain actual real LEFT/RIGHT bounds")
		var key := "%s|%s" % [dimensions, activity]
		if source == "play":
			captures[key] = {
				"center": float(data.get("calibration_center", -1.0)),
				"left": float(data.get("calibration_left", -1.0)),
				"right": float(data.get("calibration_right", -1.0)),
			}
		else:
			var earlier: Dictionary = captures.get(key, {})
			_assert(absf(float(data.get("calibration_center", 0.0)) -
				float(earlier.get("center", -1.0))) < 0.01,
				prefix + " Tutorial and Play use same neutral/center calibration algorithm")
			if activity != "Human Plane":
				_assert(absf(float(data.get("calibration_left", 0.0)) -
					float(earlier.get("left", -1.0))) < 0.01 and
					absf(float(data.get("calibration_right", 0.0)) -
					float(earlier.get("right", -1.0))) < 0.01,
					prefix + " Tutorial and Play have matching physical zone bounds")
	# Never let the real camera shutdown helper kill the test runner: the PID
	# above merely models a live process for fresh-occupancy authorization.
	pose.set("worker_pid", -1)
	pose.set("peer", null)
	screen.queue_free()
	await process_frame
	await process_frame
	pose.stop_camera()


func _push_packet(screen: Control, body_x: float, plane_x: float, delta: float, raised: bool = false) -> void:
	pose.set("active", true)
	pose.set("current_status", {"state": "tracking", "pose": true,
		"camera": true, "camera_phase": "tracking", "people": 1, "lock_state": "locked",
		"token": String(pose.get("session_token")),
		"camera_frame_age_ms": 20, "plane_steering": plane_x,
		"plane_steering_valid": true, "plane_neutral_valid": true,
		"plane_t_pose_valid": true, "plane_bank_valid": true, "plane_bank": plane_x,
		"hand_observation_valid": true, "hand_up": raised,
		"both_hands_down": not raised, "both_hands_up": raised,
		"x": body_x})
	pose.set("player_x", body_x)
	pose.set("last_pose_ms", Time.get_ticks_msec())
	pose.set("_last_occupancy_packet_ms", Time.get_ticks_msec())
	var source: Dictionary = pose.get("current_status")
	pose.call("_record_fresh_calibration_pose", source, timestamp)
	pose.set("packet_sequence", int(pose.get("packet_sequence")) + 1)
	timestamp += delta
	screen.call("_process", delta)


func _assert(success: bool, description: String) -> void:
	checks += 1
	if not success:
		failures.append(description)
		printerr("CALIBRATION FLOW DIFFERENCE: ", description)


func _finish() -> void:
	print("PLAY/TUTORIAL SHARED LIVE CALIBRATION: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
