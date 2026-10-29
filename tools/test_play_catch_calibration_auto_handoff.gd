extends SceneTree

## Reproduce the Play regression without opening a camera or connecting to DB:
## three real-position source-shaped holds must schedule the actual deferred
## Catch the Word handoff, preserve once-measured calibration, and keep body steering.
## Godot --headless --path . --script res://tools/test_play_catch_calibration_auto_handoff.gd
const CALIBRATION_SCENE := "res://ui/vision/calibration/calibration.tscn"
const GAMEPLAY_SCENE := "res://ui/play/gameplay/gameplay.tscn"
const STUDENT_ID := 271
const SOURCE_FRAME_INTERVAL := 0.11

var pose: Node
var screen: Control
var failures: Array[String] = []
var checks := 0
var packet_time := 1000.0
var handoffs: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(12.0).timeout
	_fail("Calibration-to-Catch regression test exceeded its no-device watchdog")
	_finish()


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	if pose == null:
		_fail("Production PoseService autoload exists")
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	# Fake in-memory tracking. set_context must not launch a webcam worker.
	pose.set("active", true)
	pose.set("player_x", -1.0)
	pose.set("current_status", {"state": "loading", "pose": false,
		"camera": true, "lock_state": "waiting"})
	var packed := load(CALIBRATION_SCENE) as PackedScene
	if packed == null:
		_fail("Production calibration scene loads")
		_finish()
		return
	screen = packed.instantiate() as Control
	root.add_child(screen)
	screen.set_process(false)
	screen.set_context({"entry_source": "play", "guided_tutorial": false,
		"activity": "Catch the Word", "camera_requested": true,
		"student_id": "QA-ONLY", "student_name": "SYNTHETIC CHILD"})
	screen.requested.connect(func(route: String, payload: Dictionary) -> void:
		handoffs.append({"route": route, "payload": payload.duplicate(true)}))
	_check(pose.worker_pid == -1 and pose.peer == null,
		"No camera worker, device or network connection opened")
	screen.call("_process", 3.01)
	_check(int(screen.get("live_step")) == 0,
		"Intro time cannot count toward the physical positions")
	for zone in [0.50, 0.80, 0.20]:
		for _frame in range(34):
			_push_pose(zone)
	_check(int(screen.get("live_step")) == 3,
		"CENTER, RIGHT and LEFT each finish 3 seconds and 8 fresh samples")
	var measured: Dictionary = pose.get("calibration")
	_check(bool(measured.get("valid", false)) and not measured.has("locked_id") and
		absf(float(measured.get("center", -1)) - 0.50) < 0.01 and
		absf(float(measured.get("right", -1)) - 0.80) < 0.01 and
		absf(float(measured.get("left", -1)) - 0.20) < 0.01,
		"Third stage saves all measured coordinates without registering a camera ID")
	_check(bool(screen.get("transition_queued")),
		"Completing the third stage schedules gameplay handoff automatically")
	_check(handoffs.is_empty(), "Handoff respects the short success delay")
	# Do not call _continue_flow manually. Exercise the production deferred timer
	# so accidentally unreachable set_calibration/advance code fails this test.
	# The production pose worker continues publishing tracked frames during
	# the two-second success animation. Keep our fake pose fresh as well.
	for _frame in range(8):
		await create_timer(0.30).timeout
		_set_player(0.20, STUDENT_ID)
	_check(handoffs.size() == 1, "Successful calibration automatically emits one gameplay route")
	if handoffs.size() == 1:
		var handoff: Dictionary = handoffs[0]
		var payload: Dictionary = handoff.get("payload", {})
		_check(String(handoff.get("route", "")) == "gameplay" and
			bool(payload.get("start_countdown", false)) and
			bool(payload.get("from_calibration", false)) and
			bool(payload.get("calibration_measured", false)) and
			bool(payload.get("camera_live", false)) and
			String(payload.get("entry_source", "")) == "play" and
			not bool(payload.get("guided_tutorial", true)),
			"Play-only Catch handoff requests gameplay countdown with live camera")
		_check(absf(float(payload.get("calibration_left", -1)) - 0.20) < 0.01 and
			absf(float(payload.get("calibration_center", -1)) - 0.50) < 0.01 and
			absf(float(payload.get("calibration_right", -1)) - 0.80) < 0.01,
			"Countdown receives real measured LEFT/CENTER/RIGHT positions")
	# Catch reads normalized_body_x() each frame. A new or missing ByteTrack ID
	# does not invalidate an already measured round when exactly ONE real fresh
	# stable person is present.
	_set_player(0.80, STUDENT_ID)
	_check(pose.has_valid_pose() and pose.normalized_body_x() > 0.95,
		"Fresh solo student can move Catch to the right")
	_set_player(0.20, STUDENT_ID)
	_check(pose.has_valid_pose() and pose.normalized_body_x() < -0.95,
		"Fresh solo student can move Catch to the left")
	_set_player(0.80, STUDENT_ID + 1)
	_check(pose.has_valid_pose() and pose.normalized_body_x() > 0.95 and
		not pose.calibration.has("locked_id"),
		"One fresh solo body with changed ByteTrack ID uses same original calibration")
	_set_player(0.50, STUDENT_ID)
	_check(pose.has_valid_pose() and absf(pose.normalized_body_x()) < 0.01,
		"One fresh solo person recovers centered gameplay movement")
	screen.queue_free()
	await process_frame
	_check(pose.active and bool((pose.get("calibration") as Dictionary).get("valid", false)),
		"Calibration screen releases camera ownership to gameplay")
	# Mount the real Catch wrapper using the emitted calibration payload. The
	# countdown must unfreeze gameplay with any fresh stable solo pose.
	if handoffs.size() == 1:
		var game_scene := load(GAMEPLAY_SCENE) as PackedScene
		if game_scene == null:
			_fail("Production gameplay wrapper scene loads")
		else:
			var game_wrapper := game_scene.instantiate() as Control
			root.add_child(game_wrapper)
			game_wrapper.call("set_context", handoffs[0]["payload"])
			var active_game := game_wrapper.get("active_game") as Control
			_check(active_game != null and
				active_game.process_mode == Node.PROCESS_MODE_DISABLED,
				"Play Catch stays paused during the initial 3-2-1 countdown")
			_check(is_instance_valid(active_game.get("score_bottom_number")),
				"Catch scene initializes its score label without a missing-node error")
			for _frame in range(23):
				await create_timer(0.15).timeout
				_set_player(0.50, STUDENT_ID)
			_check(String(game_wrapper.get("guided_stage")) == "" and
				active_game.process_mode == Node.PROCESS_MODE_INHERIT,
				"3-2-1 countdown completes and unfreezes Catch (stage=%s count=%d wait=%s live=%s calibrated=%s)" % [
					String(game_wrapper.get("guided_stage")), int(game_wrapper.get("countdown_value")),
					str(game_wrapper.get("_countdown_waiting_for_pose")), str(pose.has_valid_pose()),
					str((pose.get("calibration") as Dictionary).get("valid", false))])
			_set_player(0.80, STUDENT_ID)
			# Wrapper intentionally eases basket movement for display. Advance
			# several lightweight fake render frames with the same fresh pose.
			for _movement_frame in range(20):
				game_wrapper.call("_process", 0.016)
			_check(bool(active_game.get("body_input_active")) and
				float(active_game.get("body_target_normalized")) > 0.85,
					"Real Catch basket responds to one-person rightward movement (active=%s x=%.3f mode=%d)" % [
					str(active_game.get("body_input_active")),
					float(active_game.get("body_target_normalized")), active_game.process_mode])
			game_wrapper.queue_free()
			await process_frame
	_finish()


func _push_pose(x: float) -> void:
	_set_player(x, STUDENT_ID)
	var current: Dictionary = pose.get("current_status")
	pose.call("_record_fresh_calibration_pose", current, packet_time)
	pose.set("packet_sequence", int(pose.get("packet_sequence")) + 1)
	packet_time += SOURCE_FRAME_INTERVAL
	screen.call("_process", SOURCE_FRAME_INTERVAL)


func _set_player(x: float, id: int) -> void:
	pose.set("active", true)
	pose.set("player_x", x)
	pose.set("last_pose_ms", Time.get_ticks_msec())
	pose.set("_last_packet_ms", Time.get_ticks_msec())
	pose.set("current_status", {"state": "tracking", "pose": true,
		"camera": true, "people": 1, "lock_state": "locked", "physical_track_id": id,
		"x": x, "camera_frame_age_ms": 20, "fps": 10.0})


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		_fail(reason)


func _fail(reason: String) -> void:
	failures.append(reason)
	printerr("PLAY CATCH HANDOFF FAILED: ", reason)


func _finish() -> void:
	if pose != null:
		pose.stop_camera()
		pose.set_process(true)
	print("PLAY CATCH LIVE CALIBRATION HANDOFF: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
