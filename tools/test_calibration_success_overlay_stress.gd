extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_calibration_success_overlay_stress.gd
# Independent synthetic source packets exercise the editor-authored success
# screen and its 3-second SOLO gate. No real camera, database or gameplay starts.

const CALIBRATION_PATH := "res://ui/vision/calibration/calibration.tscn"
const CLOCK_STEP := 0.15
var pose: Node
var scene: PackedScene
var source_clock := 1000.0
var checked := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_expect(pose != null, "PoseService autoload")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	scene = load(CALIBRATION_PATH) as PackedScene
	_expect(scene != null, "Calibration scene loads with PoseService initialized")
	if scene == null:
		_finish()
		return
	for activity in ["Catch the Word", "Balloon Popping", "Human Plane"]:
		for guided in [false, true]:
			await _exercise_success(activity, guided)
	pose.worker_pid = -1
	pose.stop_camera()
	_finish()


func _exercise_success(activity: String, guided: bool) -> void:
	var label := activity + (" Tutorial" if guided else " Play")
	pose.worker_pid = -1
	pose.stop_camera()
	pose.peer = PacketPeerUDP.new()
	_expect(pose.peer.bind(0, "127.0.0.1") == OK, label + ": mock UDP receiver")
	pose.worker_pid = OS.get_process_id() # Mock alive only; disarm before teardown.
	pose.session_token = "success-overlay-" + activity + ("-tutorial" if guided else "-play")
	pose.active = true
	var screen := scene.instantiate() as Control
	root.add_child(screen)
	screen.set_process(false)
	var stage := screen.get_node("TutorialStage") as Control
	var intro := stage.get_node("IntroOverlay") as ColorRect
	var success := stage.get_node("SuccessOverlay") as ColorRect
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target": target, "payload": payload}))
	var settings := {
		"activity": activity, "guided_tutorial": guided,
		"entry_source": "tutorial" if guided else "play",
		"camera_requested": false, "keyboard_mode": false,
		"game_mode": "Seconds", "topic": "Noun", "difficulty": "Easy",
	}
	screen.set_context(settings)
	_expect(intro.visible and not success.visible, label + ": intro only starts visible")
	for removed in ["IntroBackButton", "IntroHeading", "IntroDescription", "IntroCountdown"]:
		_expect(intro.get_node_or_null(removed) == null, label + ": " + removed + " removed")
	_expect(intro.get_node_or_null("ArtIntroTitle") is Label, label + ": authored intro title intact")
	_expect(success.get_node_or_null("SuccessTitle") is Label
		and success.get_node_or_null("SuccessSubtitle") is Label,
		label + ": editable bilingual success title and subtitle")
	_expect(is_equal_approx(intro.color.a, success.color.a), label + ": same darkening")
	screen._process(2.99)
	_expect(screen.intro_running and not success.visible, label + ": full intro 3s")
	screen._process(0.01)
	_expect(not screen.intro_running and not intro.visible, label + ": intro ends")
	_complete_physical_holds(screen, activity)
	_expect(screen.success_running and success.visible, label + ": verified holds display success")
	_expect(screen.transition_queued and routes.is_empty(), label + ": waits before gameplay")
	_check_success_exclusivity(stage, success, label)
	screen._continue_flow(false) # Old callers must not skip success.
	_expect(routes.is_empty(), label + ": manual Continue blocked during success")
	for n in range(18):
		_send_packet(screen, 0.5, 1, activity)
	_expect(success.visible and routes.is_empty(), label + ": success remains for 2.7s" +
		" (elapsed=%.2f queued=%s shown=%s routes=%d)" % [
			float(screen.success_elapsed), str(screen.transition_queued), str(success.visible), routes.size()])
	var saved_points: Dictionary = screen.measured_points.duplicate(true)
	var saved_elapsed: float = float(screen.success_elapsed)
	# Genuine zero/crowd source packets freeze authenticated SUCCESS, but
	# NEVER discard completed physical holds or return the student to CENTER.
	_send_packet(screen, 0.5, 2, activity)
	_expect(screen.success_running and success.visible and routes.is_empty()
		and screen.measured_points == saved_points
		and bool(pose.calibration.get("valid", false))
		and is_equal_approx(float(screen.success_elapsed), saved_elapsed),
		label + ": raw 2+ people FREEZE success, preserving all measured holds")
	_send_packet(screen, 0.5, 0, activity)
	_expect(screen.success_running and success.visible and routes.is_empty()
		and screen.measured_points == saved_points
		and is_equal_approx(float(screen.success_elapsed), saved_elapsed),
		label + ": raw 0 people FREEZE success without restarting calibration")
	# Any long stale-data interval must also preserve holds without GO.
	pose._last_occupancy_packet_ms = Time.get_ticks_msec() - int(pose.OCCUPANCY_STALE_MS) - 100
	screen._process(3.5)
	_expect(routes.is_empty() and screen.success_running and success.visible
		and screen.measured_points == saved_points
		and is_equal_approx(float(screen.success_elapsed), saved_elapsed),
		label + ": stale source blocks GO but never reopens CENTER")
	if activity == "Balloon Popping" and not guided:
		pose.session_token = "replacement-live-camera-session"
		screen._process(CLOCK_STEP)
		_expect(screen.success_running and success.visible
			and screen.measured_points == saved_points and routes.is_empty(),
			label + ": camera reconnect cannot invalidate completed six gesture holds")
	# The existing screen can be repurposed for a Retry with a new student:
	# only an EXPLICIT new-round reset cancels the physical measurements.
	if activity == "Catch the Word" and not guided:
		var retry := settings.duplicate(true)
		retry["new_round"] = true
		screen.set_context(retry)
		_expect(not screen.success_running and not success.visible and routes.is_empty()
			and int(screen.live_step) == 0 and screen.measured_points.is_empty(),
			label + ": explicit NEW ROUND alone discards old captures")
		_complete_physical_holds(screen, activity)
		_expect(screen.success_running and success.visible, label + ": retry collects new holds")
	# After any freeze, the raw YOLO solo count from NEW authenticated source
	# frames resumes the remaining success timer WITHOUT redoing prior holds.
	var before_route := maxi(0, floori((3.0 - float(screen.success_elapsed) - 0.15) / CLOCK_STEP))
	for n in range(before_route):
		_send_packet(screen, 0.5, 1, activity, false, false)
	_expect(routes.is_empty() and success.visible,
		label + ": real solo success cannot hand off before full 3 seconds")
	for n in range(4):
		_send_packet(screen, 0.5, 1, activity, false, false)
	_expect(routes.size() == 1 and String(routes[0].get("target", "")) == "gameplay",
		label + ": one automatic handoff after authenticated SOLO and 3s success")
	if routes.size() == 1:
		var payload := routes[0].get("payload", {}) as Dictionary
		_expect(bool(payload.get("calibration_measured", false))
			and bool(payload.get("start_countdown", false))
			and bool(payload.get("guided_tutorial", false)) == guided
			and not bool(payload.get("keyboard_mode", true)),
			label + ": Play/Tutorial routes retain shared count-in and live tracking")
	for n in range(4):
		_send_packet(screen, 0.5, 1, activity, false, false)
	_expect(routes.size() == 1, label + ": no duplicate gameplay requests")
	pose.worker_pid = -1
	screen.queue_free()
	await process_frame
	await process_frame
	pose.stop_camera()


func _complete_physical_holds(screen: Control, activity: String) -> void:
	if activity == "Human Plane":
		for n in range(36):
			_send_packet(screen, 0.5, 1, activity)
			if screen.plane_demo_running:
				break
		_expect(screen.plane_demo_running, "Human Plane physical CENTER T-pose initiates side demo")
		for n in range(15):
			_send_packet(screen, 0.5, 1, activity)
			if screen.success_running:
				break
	elif activity == "Balloon Popping":
		# The user now requires CENTER -> RIGHT -> LEFT, with a fresh physical
		# BOTH HANDS DOWN 3s hold followed by BOTH HANDS UP 3s at EACH zone.
		# No camera/pose frames are forged by the UI; every observation goes
		# through the real PoseService source-frame queue.
		for zone_index in range(3):
			var x: float = [0.5, 0.8, 0.2][zone_index]
			var zone: String = ["CENTER", "RIGHT", "LEFT"][zone_index]
			for phase in range(2):
				_expect(int(screen.live_step) == zone_index
					and int(screen.balloon_pose_phase) == phase,
					"Balloon " + zone + ": stage starts in proper CENTER-RIGHT-LEFT order")
				# EITHER-hand gameplay field is deliberately true for a full
				# 3.6s, while actual bilateral evidence is FALSE. This must
				# never be accepted as the UP or the DOWN calibration gesture.
				for n in range(24):
					_send_packet(screen, x, 1, activity, true, true, true)
				_expect(int(screen.live_step) == zone_index
					and int(screen.balloon_pose_phase) == phase
					and is_zero_approx(float(screen.live_timer)),
					"Balloon " + zone + ": aggregate one-hand UP cannot fake bilateral hold")
				# The 3-second HOLD is real: 2.85s of correct source frames
				# plus 19 distinct observations still cannot finish a phase.
				for n in range(19):
					_send_packet(screen, x, 1, activity, phase == 1)
				_expect(int(screen.live_step) == zone_index
					and int(screen.balloon_pose_phase) == phase,
					"Balloon " + zone + ": 2.85s genuine BOTH-hand hold is insufficient")
				for n in range(4):
					_send_packet(screen, x, 1, activity, phase == 1)
				_expect(int(screen.live_step) == zone_index + (1 if phase == 1 else 0)
					and int(screen.balloon_pose_phase) == (0 if phase == 1 else 1),
					"Balloon " + zone + ": complete 3s/8+ bilateral samples advance one stage")
				if zone_index != 2 or phase == 0:
					_expect(not bool(pose.calibration.get("valid", false)),
						"Balloon " + zone + ": no early successful calibration")
		_expect(int(screen.live_step) == 3 and bool(screen.success_running),
			"Balloon: six true bilateral three-second holds lead to SUCCESS")
	else:
		var zones := [0.5, 0.8, 0.2]
		for zone_index in range(zones.size()):
			var x := float(zones[zone_index])
			for n in range(36):
				_send_packet(screen, x, 1, activity)
				if screen.success_running or int(screen.live_step) > zone_index:
					break


func _send_packet(screen: Control, x: float, people: int, activity: String,
		raised := false, pose_valid := true, only_one_hand := false) -> void:
	source_clock += CLOCK_STEP
	var joints := people == 1 and pose_valid
	var balloon := activity == "Balloon Popping"
	var packet: Dictionary = {
		"token": pose.session_token, "kind": "pose",
		"camera": true, "camera_phase": "tracking",
		"state": "tracking", "people": people, "pose": joints,
		"lock_state": "locked" if joints else ("pending" if people == 1 else "lost"),
		"camera_frame_age_ms": 20, "fps": 8.0, "x": x if joints else -1.0,
		"hand_observation_valid": joints, "hand_up": raised if joints else false,
		"both_hands_down": balloon and joints and not raised and not only_one_hand,
		"both_hands_up": balloon and joints and raised and not only_one_hand,
		"plane_t_pose_valid": activity == "Human Plane" and joints,
		"plane_steering_valid": activity == "Human Plane" and joints,
		"plane_neutral_valid": activity == "Human Plane" and joints,
		"plane_steering": 0.0,
	}
	pose._apply_pose_packet(packet, Time.get_ticks_msec())
	if joints:
		pose._record_fresh_calibration_pose(packet, source_clock)
	screen._process(CLOCK_STEP)


func _check_success_exclusivity(stage: Control, success: ColorRect, label: String) -> void:
	var dimmer := stage.get_parent().get_node_or_null("ClassroomDimmer") as ColorRect
	if dimmer != null:
		var darkness := 1.0 - (1.0 - dimmer.color.a) * (1.0 - success.color.a)
		_expect(darkness >= 0.60 and darkness <= 0.70, label + ": success background is 60–70% dark")
	for child in stage.get_children():
		if child is Control and child != success:
			_expect(not child.visible, label + ": no stage art, camera, digits, or Back behind success: " + child.name)


func _expect(ok: bool, detail: String) -> void:
	checked += 1
	if not ok:
		failures.append(detail)
		printerr("CALIBRATION SUCCESS STRESS FAIL: ", detail)


func _finish() -> void:
	print("CALIBRATION SUCCESS STRESS: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checked, failures.size()
	])
	quit(0 if failures.is_empty() else 1)
