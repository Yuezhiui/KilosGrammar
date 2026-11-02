extends SceneTree

# Source-verified, camera-free QA for the new one-hold Catch/Balloon flow.
# No USB webcam, database, file writes, original asset moves or Git changes.
const SCENE_PATH := "res://ui/vision/calibration/calibration.tscn"
const DT := 0.10
var pose: Node
var scene: PackedScene
var now := 4200.0
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures.append(note)
		printerr("NEUTRAL QA FAIL: ", note)


func _run() -> void:
	pose = root.get_node("PoseService")
	scene = load(SCENE_PATH) as PackedScene
	_check(scene != null, "calibration scene loads after autoload initialization")
	if scene == null:
		quit(1)
		return
	pose.stop_camera()
	pose.set_process(false)
	for activity in ["Catch the Word", "Balloon Popping"]:
		for guided in [false, true]:
			for x in [0.08, 0.50, 0.92]:
				await _case(activity, guided, x)
	var plane := scene.instantiate() as Control
	plane.context = {"activity": "Human Plane", "player_mode": "Single Player"}
	_check(not plane._single_neutral_body_mode() and plane._capture_order() == ["CENTER"],
		"Human Plane retains its own CENTER T-pose rather than Catch/Balloon neutral")
	plane.free()
	pose.worker_pid = -1
	pose.stop_camera()
	print("SINGLE NEUTRAL CALIBRATION: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _setup_pose(token: String) -> void:
	pose.worker_pid = -1
	pose.stop_camera()
	pose.peer = PacketPeerUDP.new()
	_check(pose.peer.bind(0, "127.0.0.1") == OK, token + " fake receiver is local")
	pose.worker_pid = OS.get_process_id()
	pose.session_token = token
	pose.active = true


func _packet(screen: Control, x: float, people := 1, fresh_pose := true, wrist_valid := false) -> void:
	now += DT
	var valid := people == 1 and fresh_pose
	var packet := {"token": pose.session_token, "kind": "pose", "state": "tracking",
		"camera": true, "camera_phase": "tracking", "people": people,
		"foreground_people": people, "foreground_ambiguous": people != 1,
		"occupancy_verified": people == 1, "player_lock_epoch": 1,
		"pose": fresh_pose, "lock_state": "locked" if valid else "pending",
		"camera_frame_age_ms": 20, "fps": 10.0, "x": x if fresh_pose else -1.0,
		"hand_observation_valid": wrist_valid, "hand_up": wrist_valid,
		"both_hands_up": false, "both_hands_down": false,
		"calibration_hand_observation_valid": false,
		"calibration_both_hands_up": false, "calibration_both_hands_down": false,
		"pose_conf": 0.97 if valid else 0.04}
	pose._apply_pose_packet(packet, Time.get_ticks_msec())
	if valid:
		pose.player_x = x
		pose._record_fresh_calibration_pose(packet, now)
	screen._process(DT)


func _case(activity: String, guided: bool, x: float) -> void:
	var tag := "%s guided=%s x=%.2f" % [activity, guided, x]
	_setup_pose("neutral-" + tag)
	var screen := scene.instantiate() as Control
	_check(screen.has_method("set_context"), tag + " authored calibration script compiled")
	if not screen.has_method("set_context"):
		screen.free()
		return
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.set_context({"activity": activity, "guided_tutorial": guided,
		"player_mode": "Single Player", "camera_requested": false,
		"topic": "Noun", "game_mode": "Seconds", "difficulty": "Easy"})
	screen.set_process(false)
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target":target, "payload":payload.duplicate(true)}))
	var stage := screen.get_node("TutorialStage") as Control
	var neutral := stage.get_node("NeutralInstruction") as Label
	var intro := stage.get_node("IntroOverlay") as Control
	var success := stage.get_node("SuccessOverlay") as Control
	_check(screen._capture_order() == ["NEUTRAL"] and bool(screen._single_neutral_body_mode()),
		tag + " only neutral position is required")
	_check(intro.visible and not neutral.visible and not success.visible,
		tag + " intro keeps 3-second CALIBRATION screen")
	screen._process(2.99)
	_check(intro.visible and is_zero_approx(screen.live_timer),
		tag + " intro time never earns neutral hold")
	screen._process(0.01)
	_check(not intro.visible and neutral.visible and neutral.text.contains("STAND STILL"),
		tag + " editor-authored English instruction appears after intro")
	for path in [
			"Directions/ArtTitleCenter", "Directions/ArtTitleRight", "Directions/ArtTitleLeft",
			"Directions/ArtArrowCenter", "Directions/ArtArrowRight", "Directions/ArtArrowLeft",
			"Directions/ArtStep1", "Directions/ArtStep2", "Directions/ArtStep3",
			"PoseGuides/PoseGuideDefault", "PoseGuides/PoseGuideRight",
			"PoseGuides/PoseGuideLeft", "PoseGuides/PoseGuideBalloonRaise",
			"PoseGuides/PoseGuideBalloonRaiseRight", "PoseGuides/PoseGuideBalloonRaiseLeft"
	]:
		var art := stage.get_node(path) as Control
		_check(not art.visible, tag + " legacy guide remains hidden " + path)
	# Wrong camera occupancy, stale repeated packets and <3s never count.
	for people in [0, 2]:
		_packet(screen, x, people, true)
		_check(screen.live_step == 0 and screen.live_samples.is_empty() and routes.is_empty(),
			tag + " crowd/empty cannot advance")
	for i in range(27):
		_packet(screen, x, 1, true, false) # no wrists nor gesture proof
	_check(screen.live_step == 0 and screen.live_timer < 3.0 and routes.is_empty(),
		tag + " 2.6s neutral torso without wrist evidence is still pending")
	var timer_before: float = screen.live_timer
	screen._process(0.20)
	_check(is_equal_approx(float(screen.live_timer), timer_before),
		tag + " stale frames never credit hold time")
	# The next fresh frame follows a 200ms renderer gap, below the real limit.
	for i in range(7):
		_packet(screen, x, 1, true, false)
	_check(screen.live_step == 1 and success.visible and screen.success_running
		and routes.is_empty(), tag + " single real 3s neutral reaches success, not game")
	_check(String(pose.calibration.get("mode", "")) == "neutral_body"
		and bool(pose.calibration.get("neutral_only", false))
		and is_equal_approx(float(pose.calibration.get("center", -1)), x)
		and not pose.calibration.has("left") and not pose.calibration.has("right"),
		tag + " PoseService receives only measured center/noise")
	_check(screen.measured_points.has("center") and screen.measured_points.has("neutral_noise")
		and not screen.measured_points.has("left") and not screen.measured_points.has("right"),
		tag + " no invented physical left/right measurements")
	screen._continue_flow()
	_check(routes.is_empty(), tag + " success overlay cannot be skipped before 3s")
	for i in range(34):
		_packet(screen, x, 1, true, false) # new SOLO torso, no wrist or gesture
	_check(routes.size() == 1 and routes[0]["target"] == "gameplay",
		tag + " 3s success starts gameplay exactly once without needing new wrist poses")
	if routes.size() == 1:
		var payload: Dictionary = routes[0]["payload"]
		_check(bool(payload.get("calibration_neutral_only", false))
			and bool(payload.get("calibration_live", false)) and bool(payload.get("calibration_measured", false))
			and is_equal_approx(float(payload.get("calibration_center", -1.0)), x)
			and not payload.has("calibration_left") and not payload.has("calibration_right"),
			tag + " verified neutral-only payload without fabricated floor bounds")
		_check(bool(payload.get("start_countdown", false)) and payload.get("guided_tutorial", false) == guided,
			tag + " usual guided/play countdown route unchanged")
	screen.queue_free()
	await process_frame
	pose.worker_pid = -1
	pose.stop_camera()
