extends SceneTree

# Godot 4.7.2:
# --headless --path . --script res://tools/test_calibration_raw_bilateral_consumer_20261030.gd
#
# Uses the ACTUAL calibration Control and PoseService's source-pose FIFO.
# All source-shaped packets are synthetic, session-scoped and monotonically
# timestamped; no live camera, YOLO worker, school database or gameplay.
# Regression: the Balloon calibration-only observed wrists must be independent
# from gameplay's shooting release latch. Catch stays on the legacy contract.
const CALIBRATION_SCENE := "res://ui/vision/calibration/calibration.tscn"
const DT := 0.15

var pose: Node
var packed: PackedScene
var screen: Control
var source_clock := 3000.0
var checks := 0
var failures: Array[String] = []
var run_number := 0


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(20.0).timeout
	_check(false, "QA completed before watchdog without a blocked camera or route")
	_finish()


func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	packed = load(CALIBRATION_SCENE) as PackedScene
	_check(pose != null and packed != null, "Real PoseService and calibration scene available")
	if pose == null or packed == null:
		_finish()
		return
	await _test_raw_down_without_legacy()
	await _test_held_raw_up_resumes_after_wrist_occlusion()
	await _test_legacy_flags_cannot_override_explicit_raw_false()
	await _test_crowd_stale_one_hand_gates()
	await _test_catch_legacy_contract_unchanged()
	_finish()


func _prepare(activity: String) -> void:
	_safe_stop()
	pose.set_process(false)
	var peer := PacketPeerUDP.new()
	_check(peer.bind(0, "127.0.0.1") == OK, activity + " inert test transport bound")
	pose.peer = peer
	pose.worker_pid = OS.get_process_id() # Synthetic PID liveness; never spawn a camera.
	run_number += 1
	pose.session_token = "raw-bilateral-regression-%d" % run_number
	pose.active = true
	screen = packed.instantiate() as Control
	root.add_child(screen)
	screen.set_process(false)
	screen.set_context({"activity": activity, "camera_requested": false,
		"entry_source": "play", "game_mode": "Seconds", "keyboard_mode": false})
	screen.call("_process", 3.01)
	_check(not bool(screen.intro_running) and int(screen.live_step) == 0,
		activity + " intro is complete without crediting pose time")
	_check(not bool(pose.calibration.get("valid", false)),
		activity + " synthetic round starts without inherited calibration")


func _test_raw_down_without_legacy() -> void:
	_prepare("Balloon Popping")
	_check(screen.call("_capture_order") == ["CENTER", "RIGHT", "LEFT"],
		"Balloon raw evidence follows approved CENTER -> RIGHT -> LEFT order")
	# A genuine, selected SOLO camera frame contains BOTH observed lowered hands
	# while the shooting system's old observations are falsely unlatched.
	for _i in range(19):
		_frame(0.50, 1, true, false, true, false, false, false, false)
	_check(int(screen.live_step) == 0 and int(screen.balloon_pose_phase) == 0,
		"Raw BOTH DOWN does not finish before three physical seconds")
	var latest: Array[Dictionary] = pose.get_pose_samples_after(0)
	_check(not latest.is_empty() and latest.back().has("calibration_hand_observation_valid")
		and latest.back().has("calibration_both_hands_down"),
		"PoseService preserves calibration-only producer fields in source FIFO")
	for _i in range(5):
		_frame(0.50, 1, true, false, true, false, false, false, false)
	_check(int(screen.live_step) == 0 and int(screen.balloon_pose_phase) == 1
		and screen.measured_points.has("center"),
		"Observed raw BOTH DOWN completes CENTER even when legacy hand fields are false")
	await _dispose()


func _test_held_raw_up_resumes_after_wrist_occlusion() -> void:
	_prepare("Balloon Popping")
	# Establish the real DOWN phase with corroborating legacy fields to isolate
	# the shooting-latch regression during UP, not the earlier phase.
	for _i in range(24):
		_frame(0.50, 1, true, false, true, true, false, false, true)
	_check(int(screen.balloon_pose_phase) == 1 and int(screen.live_step) == 0,
		"Genuine CENTER BOTH DOWN starts UP phase without skipping a zone")
	# After an occlusion, the shot latch can still suppress all legacy keys,
	# although BOTH arms are visibly held UP in the same new SOLO source frame.
	for _i in range(8):
		_frame(0.50, 1, true, true, false, false, false, false, false)
	var held_timer: float = screen.live_timer
	var held_count: int = screen.live_samples.size()
	_check(held_count == 8 and held_timer >= 1.0 and held_timer < 3.0,
		"Raw held-UP frames earn eight fresh samples with shooting latch false")
	for _i in range(2):
		_frame(0.50, 1, false, false, false, false, false, false, false)
	_check(screen.live_samples.size() == held_count
		and is_equal_approx(screen.live_timer, held_timer)
		and int(screen.balloon_pose_phase) == 1,
		"Two fresh unobserved-wrist frames pause, not erase or credit, held UP")
	_frame(0.50, 1, true, true, false, false, false, false, false)
	_check(screen.live_samples.size() == held_count + 1
		and screen.live_timer <= held_timer + DT + 0.001,
		"Raw BOTH UP recovers while gameplay shot latch remains false; no hidden-time credit")
	for _i in range(16):
		_frame(0.50, 1, true, true, false, false, false, false, false)
	_check(int(screen.live_step) == 1 and int(screen.balloon_pose_phase) == 0
		and screen.measured_points.has("center"),
		"Full three seconds of genuine resumed BOTH UP advances only to RIGHT DOWN")
	await _dispose()


func _test_legacy_flags_cannot_override_explicit_raw_false() -> void:
	_prepare("Balloon Popping")
	# Explicitly INVALID raw bilateral input takes precedence over apparently
	# valid shooting-latched legacy input, for a whole would-be physical hold.
	for _i in range(24):
		_frame(0.50, 1, false, false, false, true, false, false, true)
	_check(int(screen.live_step) == 0 and int(screen.balloon_pose_phase) == 0
		and is_zero_approx(screen.live_timer) and screen.live_samples.is_empty(),
		"Legacy BOTH DOWN cannot forge 3.6 seconds when calibrated raw wrists are invalid")
	# Fresh positive down makes us enter UP, then spoof explicit raw false UP.
	for _i in range(24):
		_frame(0.50, 1, true, false, true, true, false, false, true)
	_check(int(screen.balloon_pose_phase) == 1, "Verified lower wrists reach UP phase")
	for _i in range(24):
		_frame(0.50, 1, false, false, false, true, true, true, false)
	_check(int(screen.live_step) == 0 and int(screen.balloon_pose_phase) == 1
		and is_zero_approx(screen.live_timer) and screen.live_samples.is_empty(),
		"Legacy BOTH UP cannot forge 3.6 seconds when calibrated raw wrists are invalid")
	await _dispose()


func _test_crowd_stale_one_hand_gates() -> void:
	_prepare("Balloon Popping")
	# Begin a valid hold before disrupting it. Population and source freshness
	# are mandatory even if both legacy/raw hands claim a valid gesture.
	for _i in range(8):
		_frame(0.50, 1, true, false, true, true, false, false, true)
	_check(screen.live_samples.size() == 8, "Eight fresh SOLO lower samples accumulate")
	for count in [2, 0]:
		_frame(0.50, count, true, false, true, true, false, false, true)
		_check(int(screen.live_step) == 0 and screen.live_samples.is_empty()
			and is_zero_approx(screen.live_timer),
			"Raw/legacy wrist claims cannot grant hold with people=%d" % count)
	for _i in range(8):
		_frame(0.50, 1, true, false, true, true, false, false, true)
	# Both wrists have valid confidence, but one is UP and one DOWN. The old
	# aggregate shooting flag must not count as either bilateral posture.
	_frame(0.50, 1, true, false, false, true, true, false, true)
	_check(int(screen.live_step) == 0 and screen.live_samples.is_empty()
		and is_zero_approx(screen.live_timer),
		"One raised and one lowered observed wrist resets a strict bilateral hold")
	for _i in range(8):
		_frame(0.50, 1, true, false, true, true, false, false, true)
	for _i in range(6):
		screen.call("_process", DT) # No source packet: old image cannot count again.
	_check(int(screen.live_step) == 0 and screen.live_samples.is_empty()
		and is_zero_approx(screen.live_timer),
		"Stale cached SOLO image resets the hold; no frame replay earns time")
	# An arbitrary packet from a different camera session must not be added.
	var accepted_before: int = pose.latest_pose_sample_id
	_frame(0.50, 1, true, false, true, true, false, false, true, "other-session")
	_check(int(pose.latest_pose_sample_id) == accepted_before
		and int(screen.live_step) == 0,
		"Foreign-session raw wrist claims cannot enter PoseService source FIFO")
	await _dispose()


func _test_catch_legacy_contract_unchanged() -> void:
	_prepare("Catch the Word")
	_check(screen.call("_capture_order") == ["CENTER", "RIGHT", "LEFT"],
		"Catch retained CENTER -> RIGHT -> LEFT")
	# Catch ignores calibration-only raw posture keys; use legacy reliable DOWN.
	for _i in range(24):
		_frame(0.50, 1, false, false, false, true, false, false, false)
	_check(int(screen.live_step) == 1 and screen.measured_points.has("center"),
		"Catch still counts legacy observed hands DOWN even when raw Balloon keys false")
	# At RIGHT, new raw DOWN must not overrule invalid legacy wrist observation.
	for _i in range(24):
		_frame(0.80, 1, true, false, true, false, false, false, false)
	_check(int(screen.live_step) == 1 and is_zero_approx(screen.live_timer),
		"Catch does not accept raw bilateral flags when legacy wrists are invalid")
	for _i in range(24):
		_frame(0.80, 1, true, false, true, true, true, false, false)
	_check(int(screen.live_step) == 1 and is_zero_approx(screen.live_timer),
		"Catch keeps rejecting legacy hand_up even when new raw BOTH DOWN is true")
	await _dispose()


func _frame(x: float, people: int, raw_observed: bool, raw_up: bool,
		raw_down: bool, legacy_observed: bool, legacy_up: bool,
		legacy_both_up: bool, legacy_both_down: bool,
		token_override: String = "") -> void:
	var solo := people == 1
	var packet: Dictionary = {
		"token": pose.session_token if token_override.is_empty() else token_override,
		"kind": "pose", "state": "tracking", "camera_phase": "tracking",
		"camera": true, "camera_frame_age_ms": 20, "fps": 8.0,
		"people": people, "pose": solo,
		"lock_state": "locked" if solo else "lost",
		"x": x,
		"calibration_hand_observation_valid": raw_observed,
		"calibration_both_hands_up": raw_up,
		"calibration_both_hands_down": raw_down,
		"hand_observation_valid": legacy_observed,
		"hand_up": legacy_up,
		"both_hands_up": legacy_both_up,
		"both_hands_down": legacy_both_down
	}
	pose.call("_apply_pose_packet", packet, Time.get_ticks_msec())
	if solo and token_override.is_empty():
		pose.player_x = x # Synthetic camera source X, without UI smoothing latency.
	source_clock += DT
	# The real PoseService receive loop records only packets that passed its
	# session-token check in _apply_pose_packet. Do not create a synthetic
	# false-positive by calling the internal FIFO recorder for a rejected token.
	if token_override.is_empty():
		pose.call("_record_fresh_calibration_pose", packet, source_clock)
	screen.call("_process", DT)


func _dispose() -> void:
	if is_instance_valid(screen):
		pose.worker_pid = -1 # No mock PID may ever be terminated as an OS process.
		screen.queue_free()
		await process_frame
		await process_frame
	screen = null
	_safe_stop()


func _safe_stop() -> void:
	if is_instance_valid(pose):
		pose.worker_pid = -1
		pose.stop_camera()


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("FAIL raw calibration consumer: ", description)


func _finish() -> void:
	_safe_stop()
	print("%s RAW BILATERAL CALIBRATION CONSUMER checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
