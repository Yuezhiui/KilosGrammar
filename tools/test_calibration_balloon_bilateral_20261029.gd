extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_calibration_balloon_bilateral_20261029.gd
# Source-shaped synthetic YOLO packets; no live webcam, worker, model or DB.
# Tests six physical Balloon phases and Human Plane's real T-pose latch.

const SCENE := "res://ui/vision/calibration/calibration.tscn"
const DT := 0.15
const BALLOON_ORDER := ["CENTER", "RIGHT", "LEFT"]
const ZONE_X := {"LEFT": 0.2, "CENTER": 0.5, "RIGHT": 0.8}

var pose: Node
var packed: PackedScene
var screen: Control
var source_when := 2000.0
var checks := 0
var failures: Array[String] = []
var fake_udp: PacketPeerUDP


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_assert(pose != null, "PoseService autoload available")
	packed = load(SCENE) as PackedScene
	_assert(packed != null, "Calibration scene loads")
	if pose == null or packed == null:
		_finish()
		return
	await _balloon_six_holds()
	await _plane_t_pose_without_torso_steering()
	_finish()


func _prepare(activity: String) -> void:
	_safe_stop()
	pose.set_process(false)
	fake_udp = PacketPeerUDP.new()
	_assert(fake_udp.bind(0, "127.0.0.1") == OK, "Mock local UDP port allocated")
	pose.peer = fake_udp
	pose.worker_pid = OS.get_process_id()
	pose.session_token = "bilateral-calibration-qa-" + activity.replace(" ", "-")
	pose.active = true
	screen = packed.instantiate() as Control
	root.add_child(screen)
	screen.set_process(false)
	screen.set_context({"activity": activity, "camera_requested": false,
		"game_mode": "Seconds", "topic": "Noun", "difficulty": "Easy"})
	_assert(bool(screen.intro_running), activity + " begins with calibration intro")
	screen.call("_process", 3.0)
	_assert(not bool(screen.intro_running), activity + " intro ends after three seconds")


func _balloon_six_holds() -> void:
	_prepare("Balloon Popping")
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target": target, "payload": payload}))
	_assert(screen.call("_capture_order") == BALLOON_ORDER, "Balloon uses CENTER -> RIGHT -> LEFT")
	_assert(screen.call("_hold_seconds") == 3.0, "Balloon phases each require 3 seconds")
	var stage := screen.get_node("TutorialStage") as Control
	var art_before: Dictionary = {}
	for name in ["PoseGuideLeft", "PoseGuideDefault", "PoseGuideRight",
		"PoseGuideBalloonRaiseLeft", "PoseGuideBalloonRaise", "PoseGuideBalloonRaiseRight",
			"PoseGuidePlaneCenter", "PoseGuidePlaneLeft", "PoseGuidePlaneRight"]:
		var control := stage.get_node("PoseGuides/" + name) as Control
		art_before[name] = control.get_rect()
	_assert(stage.get_node_or_null("PoseGuides/BalloonHandsInstruction") == null,
		"Retired overlapping BalloonHandsInstruction label absent")
	var back := stage.get_node_or_null("Navigation/BackButton") as Button
	_assert(back != null and back.visible and not back.disabled and back.owner == screen,
		"Current editor-authored teacher Back to Choose Activity remains available")
	var narrator := screen.get_node_or_null("CalibrationVoice") as Node
	_assert(narrator != null and ResourceLoader.exists(
		"res://assets/audio/calibration_voice/raise_both_hands.wav"),
		"Supplied VOICE1 raise_both_hands.wav is available to calibration")
	var steps := 0
	for zone in BALLOON_ORDER:
		var x: float = ZONE_X[zone]
		for phase in [0, 1]:
			var tag := "%s %s" % [zone, "DOWN" if phase == 0 else "BOTH UP"]
			_assert(int(screen.live_step) == steps / 2 and int(screen.balloon_pose_phase) == phase,
				tag + " starts at expected position and phase")
			var wanted_png := ("PoseGuide" + ("Left" if zone == "LEFT" else
				"Right" if zone == "RIGHT" else "Default")) if phase == 0 else (
				"PoseGuideBalloonRaise" + ("Left" if zone == "LEFT" else
				"Right" if zone == "RIGHT" else ""))
			_assert((stage.get_node("PoseGuides/" + wanted_png) as Control).visible,
				tag + " uses matching independently authored PNG guide")
			screen.call("_set_stage_instruction")
			_assert(String(screen.latest_instruction_text).contains(
					"RAISE BOTH HANDS" if phase == 1 else "KEEP BOTH HANDS DOWN"),
				tag + " still specifies physical TWO-wrist posture")
			if phase == 1 and narrator != null:
				var prompt_player := narrator.get_node("PromptPlayer") as AudioStreamPlayer
				_assert(narrator.get("_played_stages").has("Balloon Popping:%s:raised" % zone),
					tag + " one distinct narrated BOTH-UP phase")
				_assert(prompt_player.stream == narrator.call("_load_cue", "raise_both_hands"),
					tag + " uses the actual recorded bilateral raise clip")
			# A full 3+ seconds of either hand UP, while the other wrist is down,
			# never satisfies BOTH UP; neither may a single raised hand pass DOWN.
			for i in range(23):
				_observation(x, 1, true, false, false, true)
			_assert(int(screen.live_step) * 2 + int(screen.balloon_pose_phase) == steps,
				tag + " rejects 3.45s of single-hand raised observations")
			# Both wrists physically present but one cannot be classified:
			# renderer, stale hand_up, or partial occlusion cannot earn credit.
			for i in range(23):
				_observation(x, 1, false, false, false, false)
			_assert(int(screen.live_step) * 2 + int(screen.balloon_pose_phase) == steps,
				tag + " rejects 3.45s with unobserved hand landmarks")
			# Contradictory both-up and both-down booleans are invalid.
			for i in range(23):
				_observation(x, 1, true, true, true, true)
			_assert(int(screen.live_step) * 2 + int(screen.balloon_pose_phase) == steps,
				tag + " refuses contradictory simultaneous up/down source states")
			# No one or a bystander must cancel, never credit, active hold.
			for crowd in [0, 2]:
				for i in range(9):
					_observation(x, crowd, true, phase == 1, phase == 0, true)
				_assert(int(screen.live_step) * 2 + int(screen.balloon_pose_phase) == steps,
					tag + " rejects people=%d" % crowd)
			# No accepted source packet: repeatedly processing a frozen last
			# image must never satisfy any hold.
			for i in range(7):
				screen.call("_process", DT)
			_assert(int(screen.live_step) * 2 + int(screen.balloon_pose_phase) == steps,
				tag + " rejects static display frames without fresh YOLO packets")
			if steps == 0:
				# Two genuine missing-wrist packets pause the active hold. They do not
				# blink/reset its progress and cannot count as part of the 3 seconds.
				for i in range(8):
					_observation(x, 1, true, false, true, true)
				var before_count: int = screen.live_samples.size()
				var before_timer: float = screen.live_timer
				for i in range(2):
					_observation(x, 1, false, false, false, true)
				_assert(screen.live_samples.size() == before_count
					and is_equal_approx(screen.live_timer, before_timer),
					"Short fresh wrist occlusion retains previous 8 poses without credit")
				_observation(x, 1, true, false, true, true)
				_assert(screen.live_samples.size() == before_count + 1
					and screen.live_timer <= before_timer + DT + 0.001,
					"Reacquired both wrists resume same hold without counting hidden time")
				for i in range(3):
					_observation(x, 1, false, false, false, true)
				_assert(screen.live_samples.is_empty() and is_zero_approx(screen.live_timer),
					"Wrist occlusion beyond tolerance resets unsafe active hold")
			# Real fresh continuous bilateral observations: 2.85 seconds is
			# insufficient; after 3.0 seconds and >=8 packets advance once.
			for i in range(19):
				_observation(x, 1, true, phase == 1, phase == 0, true)
			_assert(int(screen.live_step) * 2 + int(screen.balloon_pose_phase) == steps,
				tag + " requires full 3 seconds even after 19 new valid packets")
			for i in range(4):
				_observation(x, 1, true, phase == 1, phase == 0, true)
			steps += 1
			_assert(int(screen.live_step) * 2 + int(screen.balloon_pose_phase) == steps,
				tag + " advances exactly one hold after continuous bilateral evidence")
			if steps < 6:
				_assert(not bool(pose.calibration.get("valid", false)),
					tag + " cannot finish whole calibration before all six holds")
	_assert(steps == 6 and int(screen.live_step) == 3 and int(screen.balloon_pose_phase) == 0,
		"Balloon completes all SIX real phases (18 seconds total)")
	_assert(bool(pose.calibration.get("valid", false)) and not pose.calibration.has("center_only"),
		"All three actual Balloon positions produce normal measured calibration")
	_assert((screen.measured_points as Dictionary).has("left")
		and (screen.measured_points as Dictionary).has("center")
		and (screen.measured_points as Dictionary).has("right"),
		"Balloon records three distinct physical locations, never synthetic ones")
	_assert(bool(screen.success_running), "Final bilateral hold starts success latch exactly once")
	for key in art_before:
		_assert((stage.get_node("PoseGuides/" + key) as Control).get_rect() == art_before[key],
			"Locked art geometry preserved for " + key)
	for i in range(18):
		_observation(0.8, 2, true, true, false, true)
	_assert(routes.is_empty() and bool(screen.success_running),
		"Crowded source freezes completed success without restarting LEFT")
	for i in range(23):
		_observation(0.8, 1, true, true, false, true)
	_assert(routes.size() == 1 and routes[0].target == "gameplay",
		"Fresh solo source releases success to game exactly once")
	for i in range(23):
		_observation(0.8, 1, true, true, false, true)
	_assert(routes.size() == 1, "Completed Balloon screen never emits duplicate gameplay")
	if routes.size() == 1:
		_assert(routes[0].payload.get("calibration_measured", false) == true
			and routes[0].payload.has("calibration_left")
			and routes[0].payload.has("calibration_center")
			and routes[0].payload.has("calibration_right"),
			"Balloon game receives all real location measurements")
	await _dispose()


func _plane_t_pose_without_torso_steering() -> void:
	_prepare("Human Plane")
	var back_routes: Array[String] = []
	screen.requested.connect(func(target: String, _payload: Dictionary) -> void:
		back_routes.append(target))
	var stage := screen.get_node("TutorialStage") as Control
	_assert(screen.call("_capture_order") == ["CENTER"], "Plane retains center-only neutral T-pose")
	_assert((stage.get_node("PoseGuides/PoseGuidePlaneCenter") as Control).visible,
		"Plane editor-authored T-pose guide is visible")
	for side in ["Left", "Right"]:
		var guide := stage.get_node_or_null("PoseGuides/PoseGuidePlane" + side) as TextureRect
		_assert(guide != null and guide.position == Vector2(262, 66)
			and guide.size == Vector2(767, 484) and not guide.visible,
			"Plane " + side + " guide is independent and shares center's exact geometry")
	for i in range(23):
		_observation(0.5, 1, true, false, false, true, false, false)
	_assert(int(screen.live_step) == 0, "Plane does not advance with arms not in T-pose")
	for i in range(19):
		_observation(0.5, 1, true, false, false, true, true, false)
	_assert(int(screen.live_step) == 0,
		"Plane needs full three seconds of source-fresh bilateral T-pose")
	for i in range(4):
		_observation(0.5, 1, true, false, false, true, true, false)
	_assert(int(screen.live_step) == 1 and bool(pose.plane_calibration.get("valid", false)),
		"Plane T-pose completes using real source arm bank even when torso steering unavailable")
	_assert(is_equal_approx(float(pose.plane_calibration.get("camera_center_x", -1.0)), 0.5),
		"Plane calibrates real centered torso X without fabricating lateral positions")
	_assert(screen.plane_demo_running and (stage.get_node("PoseGuides/PoseGuidePlaneLeft") as Control).visible,
		"After CENTER physical hold, LEFT guide starts visual-only demonstration")
	# Visual side illustrations remain up long enough to finish their 1.97s
	# cloned audio prompts. Read the real source constant, not the old 1s mock.
	var demo_duration := float(screen.get_script().get_script_constant_map().get(
		"PLANE_DEMO_SECONDS_PER_SIDE", 2.2))
	var demo_side_frames := ceili(demo_duration / DT)
	for i in range(demo_side_frames):
		_observation(0.5, 1, true, false, false, true, false)
	_assert((stage.get_node("PoseGuides/PoseGuidePlaneRight") as Control).visible
		and int(screen.live_step) == 1 and screen.measured_points.has("center"),
		"RIGHT guide follows LEFT; no extra physical plane hold requested")
	for i in range(demo_side_frames + 1):
		_observation(0.5, 1, true, false, false, true, false)
	_assert(bool(screen.success_running) and not bool(screen.plane_demo_running),
		"Visual side demonstration ends on existing verified SUCCESS latch")
	pose.worker_pid = -1
	(stage.get_node("Navigation/BackButton") as Button).pressed.emit()
	_assert(back_routes == ["play_activity"],
		"Current teacher Back returns to Choose Activity even during Plane success")
	await _dispose()


func _observation(x: float, people: int, wrists: bool, both_up: bool,
		both_down: bool, pose_ok: bool, t_pose := false, steer_available := true) -> void:
	source_when += DT
	var frame := {
		"token": pose.session_token, "kind": "pose", "camera": true,
		"camera_phase": "tracking", "state": "tracking", "people": people,
		"pose": pose_ok, "lock_state": "locked", "camera_frame_age_ms": 20,
		"x": x, "fps": 8.0, "hand_observation_valid": wrists,
		"hand_up": both_up or not both_down,
		"both_hands_up": both_up, "both_hands_down": both_down,
		"plane_t_pose_valid": t_pose,
		"plane_bank_valid": t_pose, "plane_bank": 0.01,
		"plane_steering_valid": steer_available,
		"plane_neutral_valid": steer_available,
		"plane_steering": 0.5}
	pose.call("_apply_pose_packet", frame, Time.get_ticks_msec())
	pose.call("_record_fresh_calibration_pose", frame, source_when)
	screen.call("_process", DT)


func _dispose() -> void:
	if is_instance_valid(screen):
		pose.worker_pid = -1
		screen.queue_free()
		await process_frame
		await process_frame
	screen = null
	_safe_stop()


func _safe_stop() -> void:
	if is_instance_valid(pose):
		pose.worker_pid = -1
		pose.stop_camera()


func _assert(value: bool, reason: String) -> void:
	checks += 1
	if not value:
		failures.append(reason)


func _finish() -> void:
	_safe_stop()
	for failure in failures:
		printerr("FAIL bilateral calibration: ", failure)
	print("%s bilateral calibration: %d checks, %d failures" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
