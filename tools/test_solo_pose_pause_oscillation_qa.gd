extends SceneTree

## Diagnostic headless reproduction of a moving SOLO child whose webcam sees
## exactly one person but YOLO occasionally loses pose confidence for 1 frame.
## Does not touch actual webcam/DB, production scripts or editor-authored art.
## godot --headless --path . --script res://tools/test_solo_pose_pause_oscillation_qa.gd

const GAMEPLAY_SCENE := "res://ui/play/gameplay/gameplay.tscn"
const CALIBRATION_SCENE := "res://ui/vision/calibration/calibration.tscn"
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const FRAME_DT := 1.0 / 60.0

var pose: Node
var checks := 0
var failures: Array[String] = []
var source_time := 2000.0
var gameplay: PackedScene
var calibration_scene: PackedScene


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(30.0).timeout
	_check(false, "solo intermittent-pose regression watchdog 30s")
	_finish()


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	gameplay = load(GAMEPLAY_SCENE) as PackedScene
	calibration_scene = load(CALIBRATION_SCENE) as PackedScene
	if pose == null or gameplay == null or calibration_scene == null:
		_check(false, "real autoload and both production scenes load")
		_finish()
		return
	for activity in ACTIVITIES:
		await _gameplay_stress(activity)
		await _calibration_stress(activity)
	pose.worker_pid = -1
	pose.stop_camera()
	_finish()


func _new_live_camera() -> void:
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(false)
	var udp := PacketPeerUDP.new()
	_check(udp.bind(0, "127.0.0.1") == OK,
		"mock tracked camera uses a real localhost UDP receiver")
	pose.peer = udp
	pose.worker_pid = OS.get_process_id()
	pose.set("active", true)
	pose.set("session_token", "qa-one-student-warm-camera")
	pose.set("_ever_tracked", true)
	pose.set("calibration", {"valid": true, "left": 0.2,
		"center": 0.5, "right": 0.8})
	pose.set("plane_calibration", {"valid": true, "center": 0.5,
		"mode": "plane_stationary", "neutral_only": true,
		"sensitivity": 0.2, "deadzone": 0.02,
		"camera_center_x": 0.5})
	_live_packet(1, true, 0.5)


func _live_packet(people: int, pose_ok: bool, body_x: float) -> void:
	var now := Time.get_ticks_msec()
	var observed: Dictionary = {"kind": "pose", "token": pose.session_token,
		"state": "tracking", "camera": true, "camera_phase": "tracking",
		"people": people, "pose": pose_ok, "lock_state":
		("locked" if people == 1 and pose_ok else "waiting"),
		"x": body_x, "camera_frame_age_ms": 20,
		"fps": 20.0, "plane_steering_valid": pose_ok,
		"plane_neutral_valid": pose_ok,
		"plane_steering": body_x,
		"hand_observation_valid": pose_ok}
	pose.call("_apply_pose_packet", observed, now)
	if people == 1 and pose_ok:
		source_time += 0.05
		pose.call("_record_fresh_calibration_pose", observed, source_time)


func _gameplay_stress(activity: String) -> void:
	_new_live_camera()
	var wrapper := gameplay.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_process(false)
	wrapper.call("set_context", {"activity": activity,
		"game_mode": "Seconds", "topic": "Noun", "difficulty": "Easy",
		"camera_live": true, "calibration_measured": true,
		"calibration_live": true, "start_countdown": false,
		"keyboard_mode": false})
	var game := wrapper.get("active_game") as Control
	if game == null:
		_check(false, activity + " / live minigame scene mounts")
		pose.worker_pid = -1 # Failure cleanup also avoids OS.kill(current PID).
		wrapper.queue_free()
		await process_frame
		return
	wrapper.call("_process", FRAME_DT)
	_check(not bool(wrapper.get("tracking_suspended")) and
		game.process_mode != Node.PROCESS_MODE_DISABLED,
		activity + " / initial valid SOLO resumes live minigame")
	# At 20 FPS camera + 60 FPS rendering, one YOLO packet may briefly fail
	# confidence despite a continuously visible person (people=1).  Two-frame
	# reacquisition/absence is far shorter than PoseService's 1750ms grace.
	var transitions := 0
	var prior := bool(wrapper.get("tracking_suspended"))
	for frame in range(84):
		var dip := frame % 14 == 5
		if frame % 3 == 0 or dip:
			var x := 0.46 + 0.035 * sin(float(frame) * 0.15)
			_live_packet(1, not dip, x)
		wrapper.call("_process", FRAME_DT)
		if dip:
			_check(game.process_mode != Node.PROCESS_MODE_DISABLED \
				and not bool(wrapper.get("last_pose_valid")),
				activity + " / one person keeps round PLAYING but forbids stale steering")
		var suspended := bool(wrapper.get("tracking_suspended"))
		if suspended != prior:
			transitions += 1
		prior = suspended
	print("SOLO OSCILLATION TRACE %s: single-person 20fps, 60fps render, short dip transitions=%d" %
		[activity, transitions])
	_check(transitions <= 2,
		activity + " / single visible moving person has no rapid PAUSE/PLAY oscillation (%d toggles)" % transitions)
	# An explicit zero or crowd observation must freeze immediately (safety).
	for people in [0, 2, 3]:
		_live_packet(1, true, 0.5)
		wrapper.call("_process", FRAME_DT)
		_live_packet(people, false, 0.5)
		wrapper.call("_process", FRAME_DT)
		_check(bool(wrapper.get("tracking_suspended")) and
			game.process_mode == Node.PROCESS_MODE_DISABLED,
			activity + " / people=%d immediately suspends score/lives/timer" % people)
		_live_packet(1, true, 0.48)
		wrapper.call("_process", FRAME_DT)
		_check(not bool(wrapper.get("tracking_suspended")) and
			game.process_mode != Node.PROCESS_MODE_DISABLED,
			activity + " / safe SOLO return resumes existing round after people=%d" % people)
	# A >5s disappeared person must not ask for a second physical calibration.
	_live_packet(0, false, 0.5)
	for _i in range(330):
		wrapper.call("_process", FRAME_DT)
	_check(bool(wrapper.get("tracking_suspended")) and
		bool(pose.calibration.get("valid", false)),
		activity + " / >5s missing keeps completed calibration and paused round")
	_live_packet(1, true, 0.48)
	wrapper.call("_process", FRAME_DT)
	_check(not bool(wrapper.get("tracking_suspended")) and
		bool(pose.calibration.get("valid", false)),
		activity + " / returning SOLO resumes without recalibration or scene replacement")
	pose.worker_pid = -1 # Real wrapper _exit_tree calls stop_camera(): never kill this Godot PID!
	wrapper.queue_free()
	await process_frame
	await process_frame


func _calibration_stress(activity: String) -> void:
	_new_live_camera()
	var screen := calibration_scene.instantiate() as Control
	root.add_child(screen)
	screen.set_process(false)
	screen.call("set_context", {"activity": activity, "camera_requested": true})
	screen.call("_process", 3.01)
	_check(not bool(screen.get("intro_running")),
		activity + " / calibration intro completed before hold observations")
	var sample_delta := 0.05
	for frame in range(22):
		var dip := frame in [4, 11, 18]
		var samples_before := (screen.get("live_samples") as Array).size()
		var hold_time_before := float(screen.get("live_timer"))
		_live_packet(1, not dip, 0.5 + 0.01 * sin(float(frame) * 0.3))
		screen.call("_process", sample_delta)
		if dip:
			_check((screen.get("live_samples") as Array).size() == samples_before \
				and is_equal_approx(float(screen.get("live_timer")), hold_time_before),
				activity + " / invalid solo source earns no sample or hold seconds")
	var samples := (screen.get("live_samples") as Array).size()
	print("CALIBRATION SOLO TRACE %s: 22 frames, 3 short solo confidence dips, retained=%d" %
		[activity, samples])
	_check(samples >= 16,
		activity + " / transient confidence dips with one person do not reset every calibration hold (retained=%d)" % samples)
	# Lower inference than render FPS is NOT a pose failure. Repeated UI
	# redraws must never count as new samples or reset a hold before 700ms.
	var before_idle := (screen.get("live_samples") as Array).size()
	for _render in range(15):
		screen.call("_process", FRAME_DT)
	_check((screen.get("live_samples") as Array).size() == before_idle and
		int(screen.get("live_step")) == 0,
		activity + " / 250ms without an inference packet earns no phantom samples")
	_live_packet(2, false, 0.5)
	screen.call("_process", 0.05)
	_check((screen.get("live_samples") as Array).is_empty(),
		activity + " / two people reset current calibration hold for safety")
	_live_packet(1, true, 0.50)
	screen.call("_process", 0.05)
	_live_packet(0, false, 0.50)
	screen.call("_process", 0.05)
	_check((screen.get("live_samples") as Array).is_empty(),
		activity + " / zero people reset current calibration hold for safety")
	pose.worker_pid = -1 # _exit_tree must never OS.kill the mock current process.
	screen.queue_free()
	await process_frame
	await process_frame


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		printerr("SOLO CAMERA OSCILLATION QA FAIL: ", detail)


func _finish() -> void:
	if pose != null:
		pose.worker_pid = -1
		pose.stop_camera()
	print("SOLO CAMERA OSCILLATION QA: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
