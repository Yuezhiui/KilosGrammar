extends SceneTree

# End-to-end authenticated CENTER T-pose calibration -> PoseService -> wrapper
# -> actual continuous arm-bank steering. No webcam, DB, or real child data.
# Godot --headless --path . --script res://tools/test_human_plane_body_integration.gd
const CALIBRATION_SCENE := "res://ui/vision/calibration/calibration.tscn"
const GAMEPLAY_SCENE := "res://ui/play/gameplay/gameplay.tscn"
const SESSION_TOKEN := "stationary-flight-wrapper-qa-only"
# Tracker IDs are deliberately NOT a calibration identity key. One freshly
# tracked SOLO body and observed elbows/wrists are required for every input.
const STUDENT_ID := 31
const CAMERA_X := 0.50
const DT := 1.0 / 60.0
const NEUTRAL := 0.0 # signed arm bank, not a torso X destination

var checks := 0
var failures: Array[String] = []
var pose: Node
var sample_when := 400.0
var finished := false


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(18.0).timeout
	if not finished:
		_check(false, "headless Human Plane integration exceeded 18 seconds")
		_finish()


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "Real PoseService singleton exists")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	var peer := PacketPeerUDP.new()
	_check(peer.bind(0, "127.0.0.1") == OK,
		"Source-authenticated synthetic loopback transport is bound without webcam")
	pose.peer = peer
	pose.worker_pid = OS.get_process_id() # Test liveness only; never spawn a worker.
	pose.set("session_token", SESSION_TOKEN)
	pose.set("active", true)
	var payload := await _complete_stationary_calibration()
	if not payload.is_empty():
		await _test_live_wrapper(payload, "Seconds", Vector2i(1280, 720))
		await _test_live_wrapper(payload, "Lives", Vector2i(1920, 1080))
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _complete_stationary_calibration() -> Dictionary:
	var packed := load(CALIBRATION_SCENE) as PackedScene
	_check(packed != null, "Calibration scene loads")
	if packed == null:
		return {}
	var screen := packed.instantiate() as Control
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.set_process(false)
	screen.set_context({"activity": "Human Plane", "student_name": "OFFLINE QA",
		"game_mode": "Seconds", "difficulty": "Normal", "topic": "Noun"})
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(route: String, data: Dictionary) -> void:
		routes.append({"route": route, "data": data.duplicate(true)}))
	_set_pose(NEUTRAL, STUDENT_ID, true, true, true)
	screen.call("_process", 3.01)
	_check(int(screen.get("live_step")) == 0,
		"3-second intro cannot count as a student T-pose hold")
	screen.call("_continue_flow", false)
	_check(routes.is_empty(), "No gameplay before a verified neutral hand-pose hold")
	_check(screen.call("_capture_order") == ["CENTER"], "Human Plane measures neutral only")
	# One visible hand never establishes the initial full T-pose. The
	# calibration FIFO authenticates a source-fresh torso/arm sample.
	_set_pose(NEUTRAL, STUDENT_ID, true, false, true)
	pose.call("_record_fresh_calibration_pose", pose.get("current_status"), sample_when)
	sample_when += 0.45
	screen.call("_process", 0.45)
	_check((screen.get("live_samples") as Array).is_empty(),
		"one-wrist center sample cannot qualify as both-wrist T-pose enrollment")
	for packet in range(8):
		_set_pose(NEUTRAL + 0.001 * float(packet % 3 - 1), STUDENT_ID, true, true, true)
		var state: Dictionary = pose.get("current_status")
		pose.call("_record_fresh_calibration_pose", state, sample_when)
		sample_when += 0.45
		screen.call("_process", 0.45)
	_check(int(screen.get("live_step")) == 1,
		"Eight fresh SOLO T-pose packets over >=3 seconds complete ONLY physical CENTER hold")
	_check((screen.get("measured_points") as Dictionary).has("center") and
		(screen.get("measured_points") as Dictionary).has("neutral_noise") and
		not (screen.get("measured_points") as Dictionary).has("left") and
		not (screen.get("measured_points") as Dictionary).has("right"),
		"Only measured center and neutral arm variance persist; no invented side positions")
	_check(bool(pose.plane_calibration.get("valid", false)) and
		not pose.plane_calibration.has("locked_id") and
		String(pose.plane_calibration.get("steering_mode", "")) == "continuous_arm_bank",
		"Authenticated neutral calibration is ID-free, full two-wrist arm banking")
	if not bool(pose.plane_calibration.get("valid", false)):
		# Subsequent checks must never dereference absent center keys or schedule
		# gameplay transitions from an incomplete calibration.
		screen.queue_free()
		await process_frame
		return {}
	_check(absf(float(pose.plane_calibration.get("camera_center_x", -1.0)) - CAMERA_X) < 0.01,
		"Camera floor x stays constant during the neutral hand-pose hold")
	_check(absf(float(pose.plane_calibration.get("center", -1.0)) - CAMERA_X) < 0.01,
		"Actual centered camera torso X is retained independently of arm bank")
	_check(bool(pose.plane_calibration.get("neutral_only", false)),
		"Real PoseService calibration explicitly records single-neutral mode")
	_check(bool(screen.plane_demo_running) and not bool(screen.success_running),
		"LEFT and RIGHT are narrated visual demonstrations, not extra physical captures")
	var side_seconds := float(screen.get_script().get_script_constant_map()
		.get("PLANE_DEMO_SECONDS_PER_SIDE", -1.0))
	_check(side_seconds >= 2.1, "Each side demo stays visible for the complete ~1.97s narration")
	var stage := screen.get_node("TutorialStage") as Control
	_check((stage.get_node("PoseGuides/PoseGuidePlaneLeft") as Control).visible,
		"LEFT visual-only turn starts immediately after real CENTER")
	for _i in range(ceili(side_seconds / 0.15) + 1):
		_set_pose(NEUTRAL, STUDENT_ID, true, true, true)
		screen.call("_process", 0.15)
	_check((stage.get_node("PoseGuides/PoseGuidePlaneRight") as Control).visible
		and int(screen.live_step) == 1,
		"RIGHT cue follows LEFT after narration without another physical hold")
	for _i in range(ceili(side_seconds / 0.15) + 1):
		_set_pose(NEUTRAL, STUDENT_ID, true, true, true)
		screen.call("_process", 0.15)
	_check(bool(screen.success_running) and not bool(screen.plane_demo_running),
		"Both source-authorized visual demos lead to separate SUCCESS latch")
	screen.call("_continue_flow", false)
	_check(routes.is_empty(), "No gameplay skip before full 3-second SUCCESS")
	for _i in range(22):
		_set_pose(NEUTRAL, STUDENT_ID, true, true, true)
		screen.call("_process", 0.15)
	_check(routes.size() == 1 and String(routes[0].get("route", "")) == "gameplay",
		"Real full T-pose, both 2.2s demos and 3s SUCCESS route exactly once")
	var payload: Dictionary = routes[0]["data"] if routes.size() == 1 else {}
	_check(bool(payload.get("calibration_stationary", false)) and
			String(payload.get("plane_steering_mode", "")) == "continuous_arm_bank" and
		bool(payload.get("calibration_neutral_only", false)) and
		not payload.has("calibration_left") and not payload.has("calibration_right") and
		not bool(payload.get("keyboard_mode", true)),
		"Gameplay is explicitly calibrated to true two-wrist arm-bank movement")
	screen.queue_free()
	await process_frame
	await process_frame
	return payload


func _test_live_wrapper(payload: Dictionary, mode: String, dimensions: Vector2i) -> void:
	root.size = dimensions
	root.content_scale_size = dimensions
	var packed := load(GAMEPLAY_SCENE) as PackedScene
	_check(packed != null, "Gameplay wrapper is loadable")
	if packed == null:
		return
	var wrapper := packed.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var settings := payload.duplicate(true)
	settings["game_mode"] = mode
	settings["start_countdown"] = false
	settings["guided_tutorial"] = false
	settings["camera_live"] = true
	settings["activity"] = "Human Plane"
	wrapper.set_context(settings)
	await process_frame
	await process_frame
	wrapper.set_process(false)
	var game := wrapper.get("active_game") as Control
	_check(game != null, "Real Human Plane appears inside live gameplay wrapper")
	if game == null:
		wrapper.queue_free()
		await process_frame
		return
	game.set_process(false)
	var label := "%s/%s" % [mode, dimensions]
	_check(String(wrapper.guided_stage) == "countdown"
		and game.process_mode == Node.PROCESS_MODE_DISABLED,
		label + " even a completed calibration must pass a fresh frozen 3-2-1")
	for _i in range(3):
		wrapper.call("_on_countdown_tick")
	_check(String(wrapper.guided_stage) != "countdown" and wrapper.countdown_panel == null
		and game.process_mode == Node.PROCESS_MODE_INHERIT,
		label + " actual verified LIVE pose releases the separate countdown")
	wrapper.call("_process", DT) # First post-GO fresh arm bank, never a ghost input.
	_check(int(game.get("lives")) == 3, label + " retains three lives")
	_check(float(game.get("time_remaining")) > 59.0 if mode == "Seconds" else
		is_zero_approx(float(game.get("time_remaining"))), label + " timer mode remains correct")
	_check(bool(game.get("airplane_pose_active")) and
		bool(pose.call("has_stationary_plane_pose")),
		label + " active flight requires actual fresh two-wrist arm-bank observation")
	var original_score := int(game.get("score"))
	await _drive(wrapper, game, NEUTRAL, STUDENT_ID, true, 45)
	_check(absf(float(game.get("plane_x_norm")) - 0.5) < 0.08,
		label + " neutral bank holds the airplane at center")
	await _drive(wrapper, game, 0.95, STUDENT_ID, true, 70)
	var right_x := float(game.get("plane_x_norm"))
	_check(right_x > 0.85, label + " RIGHT full arm bank smoothly reaches outer gate")
	await _drive(wrapper, game, -0.95, STUDENT_ID, true, 90)
	var left_x := float(game.get("plane_x_norm"))
	_check(left_x < 0.15 and left_x < right_x - 0.5,
		label + " LEFT full arm bank crosses usable gate range smoothly")
	# A neutral bank means STOP where you are, not magically teleport back to
	# CENTER. Move back with rightward banking, then release both arms level.
	await _drive(wrapper, game, 0.95, STUDENT_ID, true, 40)
	_check(absf(float(game.get("plane_x_norm")) - 0.5) < 0.10,
		label + " opposite real arm-bank motion brings airplane back near center")
	await _drive(wrapper, game, NEUTRAL, STUDENT_ID, true, 30)
	var settled_x: float = game.plane_x_norm
	await _drive(wrapper, game, NEUTRAL, STUDENT_ID, true, 30)
	_check(absf(float(game.get("plane_x_norm")) - 0.5) < 0.08,
		label + " neutral arm bank can hold the regained central position")
	_check(absf(float(game.get("plane_x_norm")) - settled_x) < 0.015,
		label + " neutral bank smoothly decelerates, then stops without drifting")
	await _drive(wrapper, game, NEUTRAL, STUDENT_ID, true, 5)
	_check(absf(float(game.get("plane_x_norm")) - 0.5) < 0.08,
		label + " repeated neutral two-wrist samples do not introduce drift")
	var resting := float(game.get("plane_x_norm"))
	await _drive(wrapper, game, 0.95, STUDENT_ID, true, 12, false)
	_check(not bool(game.get("airplane_pose_active")) and
		absf(float(game.get("plane_x_norm")) - resting) < 0.001,
		label + " one hidden wrist freezes steering despite fresh torso")
	await _drive(wrapper, game, -0.95, STUDENT_ID, false, 12)
	_check(not bool(game.get("airplane_pose_active")) and
		absf(float(game.get("plane_x_norm")) - resting) < 0.001,
		label + " occluded/unreliable joints freeze the current steering position")
	await _drive(wrapper, game, -0.95, STUDENT_ID + 1, true, 65)
	_check(float(game.get("plane_x_norm")) < resting - 0.25,
		label + " fresh SOLO arm bank resumes despite tracker ID churn")
	_check(int(game.get("score")) == original_score and int(game.get("attempts")) == 0,
		label + " steering cannot award points before actual ring crossing")
	_check(game.has_method("_lane_hit_at_answer_line") and
		game.get_node_or_null("HybridFlight3D/RenderViewport/FlightWorld3D/Camera") is Camera3D and
		game.get_node_or_null("MovingGates/GateCenter/GateArtwork") is TextureRect,
		label + " true 3D sky, editable words and authoritative 2D collision remain live")
	wrapper.call("preserve_camera_for_restart")
	wrapper.queue_free()
	await process_frame
	await process_frame
	pose.set("active", true)


func _drive(wrapper: Control, game: Control, value: float, student: int,
		valid: bool, frames: int, both_wrists: bool = true) -> void:
	for frame in range(frames):
		_set_pose(value, student, valid, both_wrists)
		wrapper.call("_process", DT)
		game.call("_update_plane_motion", DT)
		game.call("_sync_visuals")


func _set_pose(value: float, student: int, valid: bool = true,
		both_wrists: bool = true, center_t_pose: bool = false) -> void:
	pose.set("active", true)
	var source := {"kind": "pose", "token": SESSION_TOKEN, "state": "tracking",
		"camera": true, "camera_phase": "tracking", "camera_frame_age_ms": 20,
		"people": 1, "pose": valid, "x": CAMERA_X,
		"lock_state": "locked" if valid else "occluded", "fps": 8.0,
		"locked_id": student, # Raw tracker IDs are transient and ignored by calibration.
		"plane_t_pose_valid": valid and both_wrists and center_t_pose,
		"plane_bank_valid": valid and both_wrists,
		"plane_bank": 0.0 if center_t_pose else value,
		"plane_steering_valid": valid and both_wrists,
		"plane_neutral_valid": valid and both_wrists,
		"plane_steering": 0.0 if center_t_pose else value}
	pose.call("_apply_pose_packet", source, Time.get_ticks_msec())


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("STATIONARY BODY BRIDGE FAIL: ", message)


func _finish() -> void:
	if finished:
		return
	finished = true
	if is_instance_valid(pose):
		pose.worker_pid = -1
		pose.stop_camera()
		pose.set_process(true)
	print("HUMAN PLANE STATIONARY WRAPPER INTEGRATION: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
