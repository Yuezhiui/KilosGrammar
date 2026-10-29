extends SceneTree

# Godot --headless --path . --script res://tools/test_calibration_mode_countdown.gd
# End-to-end controller contract from authentic source-shaped camera calibration
# to gameplay. Synthetic source-fresh SOLO packets stay inside this test and
# NEVER open a webcam, start YOLO or contact the database.

const CALIBRATION_PATH := "res://ui/vision/calibration/calibration.tscn"
const GAMEPLAY_PATH := "res://ui/play/gameplay/gameplay.tscn"
const DT := 0.15
const ZONE_ORDER := ["CENTER", "RIGHT", "LEFT"]
const ZONE_X := {"CENTER": 0.50, "RIGHT": 0.80, "LEFT": 0.20}
const CASES := [
	{"mode": "Seconds", "guided": false},
	{"mode": "Lives", "guided": false},
	{"mode": "Seconds", "guided": true},
	{"mode": "Lives", "guided": true}
]

var checks := 0
var failures: Array[String] = []
var source_when := 6000.0
var fake_udp: PacketPeerUDP


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var service := root.get_node_or_null("PoseService")
	_expect(service != null, "PoseService autoload exists")
	if service == null:
		_finish()
		return
	service.stop_camera()
	service.set_process(false) # Do not launch or poll the real webcam in QA.
	# Runtime loading is intentional: calibration references the PoseService
	# autoload, which cannot be resolved by a preload at script parse time.
	var calibration_scene := load(CALIBRATION_PATH) as PackedScene
	var game_scene := load(GAMEPLAY_PATH) as PackedScene
	_expect(calibration_scene != null and game_scene != null, "actual scenes load")
	if calibration_scene == null or game_scene == null:
		_finish()
		return
	for test_case in CASES:
		await _check_case(calibration_scene, game_scene, test_case)
	service.stop_camera()
	service.set_process(true)
	_finish()


func _check_case(calibration_scene: PackedScene, game_scene: PackedScene, test_case: Dictionary) -> void:
	var guided := bool(test_case["guided"])
	var mode := String(test_case["mode"])
	var label := "%s / %s" % ["Guided" if guided else "Normal Play", mode]
	var service := root.get_node("PoseService")
	service.stop_camera()
	service.set_process(false)
	# Authenticated raw SOLO occupancy requires a live local UDP transport
	# and a running worker PID. A bound INERT test UDP port and this *test's*
	# process ID satisfy those checks without creating any camera subprocess.
	# The worker_pid is ALWAYS cleared before stop_camera (which can kill PIDs).
	fake_udp = PacketPeerUDP.new()
	_expect(fake_udp.bind(0, "127.0.0.1") == OK,
		label + ": inert local camera packet transport bound for QA")
	service.peer = fake_udp
	service.worker_pid = OS.get_process_id()
	service.session_token = "countdown-mode-test-" + mode + ("-guided" if guided else "-play")
	service.active = true
	var calibration := calibration_scene.instantiate() as Control
	root.add_child(calibration)
	calibration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	calibration.set_process(false)
	calibration.set_context({
		"activity": "Catch the Word", "game_mode": mode,
		"topic": "Noun", "difficulty": "Easy",
		"guided_tutorial": guided, "camera_requested": true, "keyboard_mode": true
	})
	calibration.call("_process", 3.01) # Authored 3-second intro earns ZERO hold credit.
	_expect(not bool(calibration.get("intro_running")) and int(calibration.get("live_step")) == 0,
		label + ": 3-second intro ends without earning fake camera hold time")
	var routes: Array[Dictionary] = []
	calibration.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target": target, "payload": payload}))
	for removed in ["SkipButton", "RetryButton", "DemoButton", "KeyboardButton"]:
		_expect(calibration.get_node_or_null("TutorialStage/" + removed) == null,
			label + ": removed action is not in scene: " + removed)
	calibration.call("_continue_flow", true)
	calibration.call("_continue_flow", false)
	_expect(routes.is_empty(), label + ": without a live pose neither skip nor continue can start gameplay")
	_expect(calibration.call("_capture_order") == ZONE_ORDER,
		label + ": Catch must complete CENTER -> RIGHT -> LEFT, not synthetic set_calibration")
	_expect(float(calibration.call("_hold_seconds")) == 3.0,
		label + ": each measured position requires genuine 3-second source-fresh hold")
	for zone in ZONE_ORDER:
		var x: float = ZONE_X[zone]
		if zone != "CENTER":
			# Crossing zones is not a stationary hold. An authentic camera
			# observation of one person with temporarily untrusted keypoints
			# retires the prior smoothed torso X without earning any sample.
			_observation(service, calibration, x, 1, false)
			_expect(int(calibration.get("live_step")) == ZONE_ORDER.find(zone),
				label + ": moving toward " + zone + " cannot earn a 3-second hold")
		for packet in range(19):
			_observation(service, calibration, x, 1)
		_expect(int(calibration.get("live_step")) == ZONE_ORDER.find(zone),
			label + ": " + zone + " cannot advance after 2.85s of SOLO measurements")
		for packet in range(4):
			_observation(service, calibration, x, 1)
		_expect(int(calibration.get("live_step")) == ZONE_ORDER.find(zone) + 1,
			label + ": " + zone + " progresses only after >=3s and >=8 fresh source packets")
	_expect(int(calibration.get("live_step")) == 3 and bool(service.calibration.get("valid", false))
		and bool(calibration.get("success_running")),
		label + ": real three-zone source capture latches success before gameplay routing")
	_expect(routes.is_empty(), label + ": no route until complete 3-second success display")
	# Missing or multiple raw persons freeze success, not redo the original
	# physical captures or auto-release a ghost student into gameplay.
	for people in [0, 2]:
		for packet in range(6):
			_observation(service, calibration, 0.20, people)
		_expect(routes.is_empty() and int(calibration.get("live_step")) == 3
			and bool(calibration.get("success_running")),
			label + ": raw people=%d freezes already-finished success" % people)
	for packet in range(23):
		_observation(service, calibration, 0.20, 1)
	_expect(routes.size() == 1 and String(routes[0].get("target", "")) == "gameplay",
		label + ": 3-second fresh raw SOLO releases saved calibration to shared game once")
	for packet in range(7):
		_observation(service, calibration, 0.20, 1)
	_expect(routes.size() == 1, label + ": continued fresh tracking never double-routes gameplay")
	if routes.is_empty():
		service.worker_pid = -1
		calibration.queue_free()
		await process_frame
		service.stop_camera()
		return
	var payload := routes[0]["payload"] as Dictionary
	_expect(bool(payload.get("start_countdown", false)), label + ": countdown explicitly requested")
	_expect(bool(payload.get("guided_tutorial", false)) == guided, label + ": guided flag round-trips")
	_expect(String(payload.get("game_mode", "")) == mode, label + ": selected game mode round-trips")
	_expect(bool(payload.get("camera_live", false)) and not bool(payload.get("keyboard_mode", true))
		and bool(payload.get("calibration_measured", false)) and not bool(payload.get("calibration_skipped", true)),
		label + ": live camera is preserved and stale keyboard/skip context rejected")
	calibration.queue_free()
	await process_frame

	var wrapper := game_scene.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context(payload)
	await process_frame
	await process_frame
	await process_frame
	var minigame := wrapper.get_node_or_null("ActiveMiniGame") as Control
	_expect(minigame != null, label + ": selected activity's real game is mounted")
	if minigame == null:
		# stop_camera() may kill worker_pid. NEVER leave the fake PID equal
		# to this Godot QA process on an early failure branch.
		service.worker_pid = -1
		wrapper.queue_free()
		await process_frame
		service.stop_camera()
		return
	_expect(minigame.process_mode == Node.PROCESS_MODE_DISABLED,
		label + ": gameplay score, timer and physics are frozen until 3-2-1 finishes")
	var mode_path := "HUDLayer/HUD/TimerPlaque" if mode == "Seconds" else "HUDLayer/HUD/LivesPlaque"
	var counter := minigame.get_node_or_null(mode_path) as CanvasItem
	_expect(counter != null and counter.is_visible_in_tree(),
		label + ": real game HUD exposes the selected Seconds/Lives counter")
	_expect(not _has_spotlight_property(wrapper)
		and wrapper.get_node_or_null("GuidedSpotlight") == null
		and wrapper.get_node_or_null("SpotlightOverlay") == null,
		label + ": removed Spotlight API and scene nodes stay absent")
	_expect(String(wrapper.get("guided_stage")) == "countdown",
		label + ": %s goes DIRECTLY to frozen 3-2-1" % ("Guided" if guided else "normal Play"))
	_expect(String(wrapper.get("guided_stage")) == "countdown",
		label + ": countdown is active immediately after authenticated calibration")
	var countdown := wrapper.get("countdown_panel") as Control
	_expect(countdown != null, label + ": actual scene-authored countdown overlay is mounted")
	if countdown != null:
		var number := countdown.get_node_or_null("CountdownNumber") as Label
		_expect(number != null and number.text == "3", label + ": countdown begins at 3")
		var score := int(minigame.get("score"))
		var seconds := float(minigame.get("time_remaining"))
		var lives := int(minigame.get("lives"))
		for expected_digit in ["2", "1"]:
			wrapper.call("_on_countdown_tick")
			_expect(number != null and number.text == expected_digit,
				label + ": countdown updates to " + expected_digit)
			_expect(minigame.process_mode == Node.PROCESS_MODE_DISABLED,
				label + ": gameplay remains frozen through " + expected_digit)
		_expect(int(minigame.get("score")) == score and is_equal_approx(float(minigame.get("time_remaining")), seconds)
			and int(minigame.get("lives")) == lives,
			label + ": count-in never spends time, lives or score")
		wrapper.call("_on_countdown_tick")
		_expect(minigame.process_mode == Node.PROCESS_MODE_INHERIT,
			label + ": gameplay unfreezes after the final countdown tick")
		_expect(wrapper.get("countdown_panel") == null,
			label + ": 3-2-1 scene is removed without recreating the minigame")
		for retry in range(2):
			wrapper.call("_on_countdown_tick")
		_expect(wrapper.get("countdown_panel") == null and
			minigame.process_mode == Node.PROCESS_MODE_INHERIT,
			label + ": late duplicate countdown timeouts never restart GO")
	service.worker_pid = -1 # NEVER kill our own synthetic test process.
	wrapper.queue_free()
	await process_frame
	await process_frame
	service.stop_camera()
	print("CALIBRATION COUNTDOWN CASE: ", label)


func _observation(service: Node, calibration: Control, x: float, people: int,
			pose_ok: bool = true) -> void:
	source_when += DT
	var packet := {
		"kind": "pose", "token": service.session_token, "when": source_when,
		"camera": true, "camera_phase": "tracking", "state": "tracking",
		"people": people, "pose": people == 1 and pose_ok,
		"lock_state": "locked" if pose_ok else "waiting",
		"camera_frame_age_ms": 20, "x": x, "fps": 8.0,
		"hand_observation_valid": true, "hand_up": false,
		"both_hands_up": false, "both_hands_down": true,
	}
	service.call("_apply_pose_packet", packet, Time.get_ticks_msec())
	service.call("_record_fresh_calibration_pose", packet, source_when)
	calibration.call("_process", DT)


func _expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)


func _has_spotlight_property(wrapper: Control) -> bool:
	for entry in wrapper.get_property_list():
		if String(entry.get("name", "")) == "spotlight_overlay":
			return true
	return false


func _finish() -> void:
	for failure in failures:
		printerr("FAIL calibration countdown: ", failure)
	print("%s calibration mode countdown: %d checks, %d failures" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
