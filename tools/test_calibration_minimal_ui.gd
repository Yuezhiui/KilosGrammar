extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_calibration_minimal_ui.gd
# Post-prune contract: editor-authored five-PNG screen, 3-second dark intro,
# strict 3-second fresh-pose holds and shared Play/Tutorial handoff.
# No real camera, YOLO worker, database or keyboard/skip fallback.

const SCENE := "res://ui/vision/calibration/calibration.tscn"
const HOLD_DT := 0.15
const POSES := ["PoseGuides/PoseGuideDefault", "PoseGuides/PoseGuideBalloonRaise", "PoseGuides/PoseGuidePlaneCenter",
	"PoseGuides/PoseGuidePlaneLeft", "PoseGuides/PoseGuidePlaneRight"]
const ZONES := [0.50, 0.80, 0.20]

var failures: Array[String] = []
var checks := 0
var pose: Node
var packet_when := 400.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload is connected")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	var packed := load(SCENE) as PackedScene
	_check(packed != null, "Full-screen five-PNG scene parses")
	if packed == null:
		_finish()
		return
	for tutorial in [true, false]:
		await _run_case(packed, tutorial)
	pose.worker_pid = -1
	pose.stop_camera()
	_finish()


func _run_case(scene: PackedScene, tutorial: bool) -> void:
	var label := "Tutorial" if tutorial else "Play"
	pose.worker_pid = -1
	pose.stop_camera()
	pose.peer = PacketPeerUDP.new()
	_check(pose.peer.bind(0, "127.0.0.1") == OK, label + " test-only UDP receiver")
	pose.worker_pid = OS.get_process_id() # Mock liveness only; disarm before cleanup.
	pose.session_token = "minimal-five-png-" + label
	pose.active = true
	var screen := scene.instantiate() as Control
	root.add_child(screen)
	screen.set_process(false)
	var stage := screen.get_node_or_null("TutorialStage") as Control
	_check(stage != null, label + " stage editor-authored")
	if stage == null:
		pose.worker_pid = -1
		screen.queue_free()
		await process_frame
		return
	for removed in ["SkipButton", "RetryButton", "DemoButton", "KeyboardButton",
			"ContinueButton", "ArtGuideLeft", "ArtGuideCenter", "ArtGuideRight",
			"LeftCalibrationLane", "CenterCalibrationLane", "RightCalibrationLane"]:
		_check(stage.get_node_or_null(removed) == null,
			label + " obsolete node pruned: " + removed)
	for name in POSES:
		var art := stage.get_node_or_null(name) as TextureRect
		_check(art != null and art.owner == screen and art.texture != null,
			label + " authored pose guide retained: " + name)
	_check(stage.get_node_or_null("CameraArea/LiveCameraInset") is TextureRect
		and stage.get_node_or_null("CameraArea/SkeletonPlacement") is ReferenceRect,
		label + " camera and skeleton positions remain editor-editable")
	var back := stage.get_node_or_null("Navigation/BackButton") as Button
	var intro := stage.get_node_or_null("IntroOverlay") as ColorRect
	var success := stage.get_node_or_null("SuccessOverlay") as ColorRect
	_check(back != null and intro != null and success != null,
		label + " Back, Intro and Success overlays remain editor-authored")
	if back == null or intro == null or success == null:
		pose.worker_pid = -1
		screen.queue_free()
		await process_frame
		return
	var dimmer := screen.get_node_or_null("ClassroomDimmer") as ColorRect
	var darkness: float = 1.0 - (1.0 - dimmer.color.a) * (1.0 - intro.color.a)
	_check(darkness >= 0.60 and darkness <= 0.70, label + " CALIBRATION intro is 60-70% dark")
	_check(screen.intro_running and intro.visible, label + " intro starts before hold")
	for child in stage.get_children():
		if child is Control and child != intro:
			_check(not (child as Control).visible, label + " intro hides HUD and guides: " + child.name)
	for removed in ["IntroBackButton", "IntroHeading", "IntroDescription", "IntroCountdown"]:
		_check(intro.get_node_or_null(removed) == null, label + " obsolete intro control removed: " + removed)
	_check(intro.get_node_or_null("ArtIntroTitle") is Label
		and success.get_node_or_null("SuccessTitle") is Label
		and success.get_node_or_null("SuccessSubtitle") is Label,
		label + " intro title and success text are independently editor-authored")
	_check(is_equal_approx(success.color.a, intro.color.a)
		and not success.visible, label + " success initially hidden and uses intro darkness")
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target": target, "payload": payload}))
	screen.set_context({"activity": "Catch the Word", "entry_source": "tutorial" if tutorial else "play",
		"guided_tutorial": tutorial, "camera_requested": false, "keyboard_mode": true,
		"game_mode": "Seconds", "topic": "Noun", "difficulty": "Easy"})
	screen.call("_continue_flow")
	screen.call("_continue_flow", true)
	_check(routes.is_empty(), label + " neither skip nor fake direct continue bypasses calibration")
	screen.call("_process", 2.99)
	_check(screen.intro_running and routes.is_empty(), label + " 2.99s intro has not credited hold")
	screen.call("_process", 0.01)
	_check(not screen.intro_running and not intro.visible and back.visible,
		label + " intro ends at 3s and Back is usable")
	_check((stage.get_node("PoseGuides/PoseGuideDefault") as Control).visible,
		label + " default PNG replaces old neon on CENTER")
	for zone_index in range(ZONES.size()):
		for sample in range(36):
			_send_pose(float(ZONES[zone_index]), screen)
			if screen.live_step > zone_index:
				break
		_check(int(screen.live_step) == zone_index + 1,
			label + " authentic 3-second source packets complete zone %d (actual=%d, measured=%s, time=%.2f)" %
			[zone_index, int(screen.live_step), str(screen.measured_points), float(screen.live_timer)])
		if zone_index < ZONES.size() - 1:
				var next_guide := "PoseGuides/PoseGuideRight" if zone_index == 0 else "PoseGuides/PoseGuideLeft"
				_check((stage.get_node(next_guide) as Control).visible
					and not (stage.get_node("PoseGuides/PoseGuideDefault") as Control).visible,
					label + " next location uses its independently editable DEFAULT.png guide")
	_check(bool(pose.calibration.get("valid", false)) and bool(screen.transition_queued),
		label + " three physically measured zones yield valid calibration")
	_check(routes.is_empty() and screen.success_running and success.visible,
		label + " completed holds enter 3-second authored success screen")
	for child in stage.get_children():
		if child is Control and child != success:
			_check(not (child as Control).visible,
				label + " successful pose hides all guides, digits, camera, title and Back: " + child.name)
	_check(not bool(screen.context.get("keyboard_mode", true)), label + " keyboard input stays prohibited")
	screen.call("_continue_flow", true)
	_check(routes.is_empty(), label + " skip never bypasses completed calibration")
	screen.call("_continue_flow", false)
	_check(routes.is_empty(), label + " manual Continue cannot bypass 3-second success")
	# A completed real three-stage calibration is LATCHED. Fresh raw one-
	# person YOLO boxes (NOT newly visible wrists) can finish the success
	# countdown; expired source, raw 0 or 2+ must freeze without recapturing.
	for tick in range(18):
		_send_pose(0.20, screen)
	_check(routes.is_empty() and success.visible and screen.success_elapsed < 3.0,
		label + " 2.7 seconds of fresh SOLO data never route early")
	var measured_once: Dictionary = screen.measured_points.duplicate(true)
	var elapsed_before_freeze: float = float(screen.success_elapsed)
	pose._last_occupancy_packet_ms = Time.get_ticks_msec() - int(pose.OCCUPANCY_STALE_MS) - 100
	screen._process(HOLD_DT)
	_check(routes.is_empty() and success.visible and screen.success_running
			and screen.live_step == 3 and screen.measured_points == measured_once
			and bool(pose.calibration.get("valid", false))
			and is_equal_approx(float(screen.success_elapsed), elapsed_before_freeze),
			label + " expired raw source FREEZES success but retains actual measurements")
	# A current raw camera packet with zero people (Tutorial) or two (Play)
	# cannot authorize GO; neither erases finished CENTER/RIGHT/LEFT.
	_send_ambiguous_pose(0 if tutorial else 2, screen)
	_check(routes.is_empty() and success.visible and screen.live_step == 3
			and screen.measured_points == measured_once
			and is_equal_approx(float(screen.success_elapsed), elapsed_before_freeze),
			label + " authentic 0/2+ count freezes without recapturing successful holds")
	# The returning solo student may be physically moving; raw YOLO
	# occupancy is genuine and fresh even when pose/keypoints are absent.
	for tick in range(5):
		_send_raw_solo_without_pose(screen)
	_check(routes.size() == 1 and String(routes[0].get("target", "")) == "gameplay",
		label + " success resumes exactly once on raw SOLO, no second holds")
	if routes.size() == 1:
		var payload := routes[0]["payload"] as Dictionary
		_check(bool(payload.get("guided_tutorial", false)) == tutorial
			and bool(payload.get("calibration_measured", false))
			and bool(payload.get("start_countdown", false))
			and bool(payload.get("camera_live", false))
			and not bool(payload.get("keyboard_mode", true)),
			label + " preserves Play/Tutorial flags and count-in with no keyboard fallback")
	for tick in range(3):
		_send_raw_solo_without_pose(screen)
	_check(routes.size() == 1, label + " no duplicate gameplay transitions after success")
	# Do not leave the fake Godot PID bound to any camera teardown path.
	pose.worker_pid = -1
	screen.queue_free()
	await process_frame
	await process_frame
	pose.stop_camera()


func _send_pose(x: float, screen: Control) -> void:
	packet_when += HOLD_DT
	var packet: Dictionary = {"token": pose.session_token, "kind": "pose",
		"camera": true, "camera_phase": "tracking", "state": "tracking",
		"people": 1, "pose": true, "lock_state": "locked",
		"camera_frame_age_ms": 20, "fps": 8.0, "x": x,
		"hand_observation_valid": true, "hand_up": false}
	pose._apply_pose_packet(packet, Time.get_ticks_msec())
	pose._record_fresh_calibration_pose(packet, packet_when)
	screen._process(HOLD_DT)


func _send_ambiguous_pose(people: int, screen: Control) -> void:
	packet_when += HOLD_DT
	var packet: Dictionary = {"token": pose.session_token, "kind": "pose",
		"camera": true, "camera_phase": "tracking", "state": "tracking",
		"people": people, "pose": false, "lock_state": "crowded" if people > 1 else "lost",
		"camera_frame_age_ms": 20, "fps": 8.0, "x": -1.0,
		"hand_observation_valid": false, "hand_up": false}
	pose._apply_pose_packet(packet, Time.get_ticks_msec())
	pose._record_fresh_calibration_pose(packet, packet_when)
	screen._process(HOLD_DT)


func _send_raw_solo_without_pose(screen: Control) -> void:
	packet_when += HOLD_DT
	var packet: Dictionary = {"token": pose.session_token, "kind": "pose",
		"camera": true, "camera_phase": "tracking", "state": "tracking",
		"people": 1, "pose": false, "lock_state": "pending",
		"camera_frame_age_ms": 20, "fps": 8.0, "x": -1.0,
		"hand_observation_valid": false, "hand_up": false}
	pose._apply_pose_packet(packet, Time.get_ticks_msec())
	# No source-valid skeleton packet can enter the old 3s holds here.
	pose._record_fresh_calibration_pose(packet, packet_when)
	screen._process(HOLD_DT)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("CALIBRATION MINIMAL UI FAIL: ", description)


func _finish() -> void:
	print("CALIBRATION MINIMAL UI: %s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
