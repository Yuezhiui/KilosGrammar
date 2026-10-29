extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_calibration_success_latched_raw_solo.gd
# Regression for a REAL completed sequence entering success and then dropping
# pose while YOLO still reports exactly one person. Test packets go through the
# production PoseService source protocol, no webcam, DB, or network calls.

const SCENE := "res://ui/vision/calibration/calibration.tscn"
const DT := 0.15
var pose: Node
var packed: PackedScene
var source_clock := 500.0
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node("PoseService")
	pose.stop_camera()
	pose.set_process(false)
	packed = load(SCENE) as PackedScene
	_assert(packed != null, "Calibration scene loads")
	if packed == null:
		_finish()
		return
	for activity in ["Catch the Word", "Balloon Popping", "Human Plane"]:
		for guided in [false, true]:
			await _case(activity, guided)
	pose.worker_pid = -1
	pose.stop_camera()
	_finish()


func _case(activity: String, guided: bool) -> void:
	var label := "%s %s" % [activity, "Tutorial" if guided else "Play"]
	pose.worker_pid = -1
	pose.stop_camera()
	pose.peer = PacketPeerUDP.new()
	_assert(pose.peer.bind(0, "127.0.0.1") == OK, label + ": synthetic local receiver")
	pose.worker_pid = OS.get_process_id()
	pose.session_token = "latched-" + label
	pose.active = true
	var screen := packed.instantiate() as Control
	root.add_child(screen)
	screen.set_process(false)
	var voice := screen.get_node_or_null("CalibrationVoice") as Node
	_assert(voice != null and voice.get_node_or_null("PromptPlayer") is AudioStreamPlayer,
		label + ": one optional stage narration player exists")
	var requests: Array[Dictionary] = []
	screen.requested.connect(func(route: String, payload: Dictionary) -> void:
		requests.append({"route": route, "payload": payload}))
	screen.set_context({
		"activity": activity, "guided_tutorial": guided,
		"entry_source": "tutorial" if guided else "play",
		"game_mode": "Seconds", "camera_requested": false,
		"keyboard_mode": false, "difficulty": "Easy", "topic": "Noun"
	})
	screen._process(3.0)
	_assert(not screen.intro_running and int(screen.live_step) == 0,
		label + ": introduction requires its own 3 seconds before holds")
	if voice != null:
		var heard_stages := (voice.get("_played_stages") as Dictionary).size()
		screen._set_stage_instruction()
		screen._set_stage_instruction()
		_assert(heard_stages == 1 and (voice.get("_played_stages") as Dictionary).size() == heard_stages,
			label + ": intro announces first pose once, repeated refresh stays silent")
	# Balloon's newest physical calibration is LEFT -> CENTER -> RIGHT,
	# with two genuinely bilateral, source-fresh three-second holds per zone.
	var zones: Array = ([0.5] if activity == "Human Plane" else
		[0.2, 0.5, 0.8] if activity == "Balloon Popping" else [0.5, 0.8, 0.2])
	var completed_holds := 0
	for zone in zones:
		var stages := 1 if activity != "Balloon Popping" else 2
		var zone_index := int(screen.live_step)
		for phase in range(stages):
			if activity == "Balloon Popping":
				_assert(int(screen.balloon_pose_phase) == phase
					and int(screen.live_step) == zone_index,
					label + ": starts bilateral phase %d in required floor zone" % phase)
				# Deliberately claim aggregate hand_up for >3 seconds without
				# verified bilateral wrists: this is NOT evidence for either
				# BOTH DOWN or BOTH UP, so no hold can progress.
				for _invalid in range(24):
					_send_packet(screen, float(zone), 1, true, activity, true)
				_assert(int(screen.live_step) == zone_index
					and int(screen.balloon_pose_phase) == phase,
					label + ": aggregate one-hand signal never satisfies bilateral phase")
			for packet in range(36):
				_send_packet(screen, float(zone), 1, true, activity, phase == 1,
					activity == "Balloon Popping" and phase == 0,
					activity == "Balloon Popping" and phase == 1)
				if screen.success_running or int(screen.live_step) > zone_index \
						or int(screen.balloon_pose_phase) != phase:
					break
			completed_holds += 1
			_assert(int(screen.live_step) == zone_index + (1 if phase == stages - 1 else 0)
				and (activity != "Balloon Popping" or int(screen.balloon_pose_phase) == 1 - phase),
				label + ": completed precisely one new live three-second hold")
	_assert(completed_holds == (1 if activity == "Human Plane" else
		6 if activity == "Balloon Popping" else 3),
		label + ": correct number of fresh physical hold phases")
	_assert(screen.success_running and screen.transition_queued
		and bool(pose.calibration.get("valid", false)) and requests.is_empty(),
		label + ": actual source-verified holds open the success screen, no early game")
	if voice != null:
		var recorded := voice.get("_played_stages") as Dictionary
		_assert(recorded.has(activity + ":success"),
			label + ": completed authentic holds announce success stage exactly once")
	var completed_stage: int = int(screen.live_step)
	var finished_points: Dictionary = screen.measured_points.duplicate(true)
	_assert(completed_stage == (1 if activity == "Human Plane" else 3)
		and not finished_points.is_empty(), label + ": floor/T-pose measurements captured")
	# The student moves and wrists/torso drop; YOLO still observes one real
	# person. This has NO trusted keypoint pose, but its raw occupancy is fresh.
	for tick in range(9):
		_send_packet(screen, 0.93, 1, false, activity)
	_assert(pose.fresh_camera_population() == 1 and not pose.has_valid_pose(),
		label + ": authenticated raw SOLO may exist without bones")
	_assert(screen.success_running and int(screen.live_step) == completed_stage
		and screen.measured_points == finished_points
		and bool(pose.calibration.get("valid", false)) and requests.is_empty(),
		label + ": movement/missing joints never erase completed measured holds")
	if voice != null:
		_assert((voice.get("_played_stages") as Dictionary).has(activity + ":success"),
			label + ": pose flicker never re-announces calibration success")
	var elapsed_before_invalid: float = float(screen.success_elapsed)
	_send_packet(screen, 0.50, 2, false, activity)
	_assert(pose.fresh_camera_population() == 2,
		label + ": real raw crowd count is available without skeletons")
	_assert(screen.success_running and screen.success_elapsed <= elapsed_before_invalid + 0.001
		and requests.is_empty() and screen.measured_points == finished_points,
		label + ": 2+ people freeze success, do not restart or route")
	_send_packet(screen, 0.50, 0, false, activity)
	_assert(pose.fresh_camera_population() == 0 and requests.is_empty()
		and screen.measured_points == finished_points,
		label + ": zero people freeze success but preserve real holds")
	# A total camera disconnect or source age expiry must likewise stop progress.
	pose.set("_last_occupancy_packet_ms", Time.get_ticks_msec() - int(pose.OCCUPANCY_STALE_MS) - 100)
	var old_elapsed: float = float(screen.success_elapsed)
	screen._process(3.5)
	_assert(pose.fresh_camera_population() == -1 and requests.is_empty()
		and screen.success_running and screen.measured_points == finished_points
		and is_equal_approx(float(screen.success_elapsed), old_elapsed),
		label + ": stale camera cannot authorize GO or clear completed holds")
	# Transport session restart during success must demand a NEW packet from
	# the current session, while preserving the finished physical measurement.
	pose.session_token = "reconnected-" + label
	screen._process(DT)
	_assert(requests.is_empty() and screen.measured_points == finished_points
		and screen.success_running,
		label + ": camera transport restart pauses the success handoff")
	for tick in range(24):
		_send_packet(screen, 0.80, 1, false, activity)
		if requests.size() == 1:
			break
	_assert(requests.size() == 1 and String(requests[0].get("route", "")) == "gameplay",
		label + ": new authenticated SOLO presence completes success once")
	if requests.size() == 1:
		var payload := requests[0]["payload"] as Dictionary
		_assert(bool(payload.get("calibration_measured", false))
			and bool(payload.get("start_countdown", false))
			and bool(payload.get("guided_tutorial", false)) == guided
			and not bool(payload.get("keyboard_mode", true)),
			label + ": authentic completed calibration routes Play/Tutorial 3-2-1 GO")
	for tick in range(10):
		_send_packet(screen, 0.80, 1, false, activity)
	_assert(requests.size() == 1, label + ": gameplay route emitted exactly once")
	pose.worker_pid = -1
	screen.queue_free()
	await process_frame
	await process_frame
	pose.stop_camera()


func _send_packet(screen: Control, x: float, people: int, pose_valid: bool,
		activity: String, hand_up := false, both_hands_down := false,
		both_hands_up := false) -> void:
	source_clock += DT
	var data: Dictionary = {
		"token": pose.session_token, "kind": "pose", "camera": true,
		"camera_phase": "tracking", "state": "tracking", "people": people,
		"pose": pose_valid, "lock_state": "locked" if pose_valid else "pending",
		"camera_frame_age_ms": 20, "fps": 8.0,
		"x": x if pose_valid else -1.0,
		"hand_observation_valid": pose_valid, "hand_up": hand_up,
		"both_hands_down": pose_valid and both_hands_down,
		"both_hands_up": pose_valid and both_hands_up,
		"plane_t_pose_valid": activity == "Human Plane" and pose_valid,
		"plane_steering_valid": activity == "Human Plane" and pose_valid,
		"plane_neutral_valid": activity == "Human Plane" and pose_valid,
		"plane_steering": 0.0
	}
	pose._apply_pose_packet(data, Time.get_ticks_msec())
	if pose_valid:
		pose._record_fresh_calibration_pose(data, source_clock)
	screen._process(DT)


func _assert(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("SUCCESS LATCH RED/REGRESSION: ", message)


func _finish() -> void:
	print("SUCCESS LATCH CAMERA QA: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()
	])
	quit(0 if failures.is_empty() else 1)
