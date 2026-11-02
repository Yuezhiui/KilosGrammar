extends SceneTree

# Godot 4.7.2 headless synthetic-source regression; NO camera, UDP, DB or Git.
# Run: Godot --headless --path . --script res://tools/test_calibration_success_no_loop_20261028.gd
# Preserves a 3-second intro, ONE source-measured 3-second neutral standing
# hold, and a 3-second latched success screen before Play/Tutorial GO.

const CALIBRATION_PATH := "res://ui/vision/calibration/calibration.tscn"
const GAMEPLAY_PATH := "res://ui/play/gameplay/gameplay.tscn"
const INTRO := 3.0
const HOLD := 3.0
const SUCCESS := 3.0

var pose: Node
var failures: Array[String] = []
var checks := 0
var source_clock := 1000.0
var cases := 0
var calibration_scene: PackedScene
var gameplay_scene: PackedScene


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService is available")
	if pose == null:
		_finish()
		return
	# All tests mutate only synthetic autoload properties. Never call start_camera.
	pose.set("worker_pid", -1)
	pose.stop_camera()
	pose.set_process(false)
	# Resolve scripts AFTER the project has mounted its PoseService autoload.
	calibration_scene = load(CALIBRATION_PATH) as PackedScene
	gameplay_scene = load(GAMEPLAY_PATH) as PackedScene
	_check(calibration_scene != null and gameplay_scene != null,
		"Calibration and gameplay PackedScenes resolve after autoload initialization")
	if calibration_scene == null or gameplay_scene == null:
		_finish()
		return
	await _case("play_wrist_and_motion", false, "wrists")
	await _case("tutorial_low_conf_solo", true, "low_conf")
	await _case("play_zero_people", false, "zero")
	await _case("tutorial_two_people", true, "crowd")
	await _case("play_stale_source", false, "stale")
	await _case("tutorial_disconnected_source", true, "disconnect")
	await _case("play_new_camera_session", false, "session")
	pose.set("worker_pid", -1)
	pose.stop_camera()
	_finish()


func _case(name: String, guided: bool, interruption: String) -> void:
	cases += 1
	# Pretend a trusted camera process already exists. set_context will not
	# launch Python, YOLO, a physical camera, or a background worker.
	pose.set("worker_pid", -1)
	pose.stop_camera()
	var peer := PacketPeerUDP.new()
	_check(peer.bind(0, "127.0.0.1") == OK,
		name + ": loopback-only synthetic receiver ready (never starts worker)")
	pose.set("peer", peer)
	pose.set("worker_pid", OS.get_process_id())
	pose.set("session_token", "no-loop-20261028-" + name)
	pose.set("active", true)
	pose.set("current_status", {"state": "loading", "pose": false, "camera": true,
		"people": -1, "detail": "Synthetic camera is warming."})
	var screen := calibration_scene.instantiate() as Control
	_check(screen != null and screen.get_script() != null, name + ": calibration script loads")
	if screen == null:
		return
	if not screen.has_method("set_context"):
		_check(false, name + ": calibration compiled with routed gameplay script")
		screen.free()
		return
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.set_context({"activity": "Catch the Word", "topic": "Noun",
		"game_mode": "Seconds", "difficulty": "Easy", "catch_character": "Bear",
		"guided_tutorial": guided, "camera_requested": false,
		"student_name": "SYNTHETIC STUDENT", "student_id": "QA-NOLOOP"})
	screen.set_process(false)
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target": target, "payload": payload.duplicate(true)}))
	var stage := screen.get_node("TutorialStage") as Control
	var overlay := stage.get_node("SuccessOverlay") as Control
	var camera_texture := _fake_texture()
	screen._on_live_preview(camera_texture)
	_check(bool(screen.intro_running) and screen.live_step == 0 and not overlay.visible,
		name + ": new round begins in real intro, never recycled success")
	screen._process(INTRO - 0.02)
	_check(screen.intro_running and screen.live_step == 0,
		name + ": cannot earn calibration time before full 3-second intro")
	screen._process(0.03)
	_check(not screen.intro_running and screen.live_step == 0,
		name + ": intro completes independently of actual pose holds")
	# One 3-second neutral torso hold. The raw wrist state is deliberately
	# unavailable, and 8+ strictly increasing source frames are still required.
	for i in range(29):
		_frame(screen, 0.50, 0.10, false)
	_check(screen.live_step == 0, name + ": 2.8 seconds cannot complete the neutral hold")
	for i in range(4):
		_frame(screen, 0.50, 0.10, false)
	_check(screen.live_step == 1, name + ": 3s plus live samples completes ONE neutral hold")
	var points := (screen.measured_points as Dictionary).duplicate(true)
	_check(points.has("center") and points.has("neutral_noise")
		and not points.has("right") and not points.has("left"),
		name + ": only measured neutral center/noise survive final hold")
	_check(bool(pose.calibration.get("valid", false)) and screen.live_step == 1
		and String(pose.calibration.get("mode", "")) == "neutral_body",
		name + ": genuine one-hold neutral body is saved without fake boundaries")
	_check(bool(screen.success_running) and overlay.visible and routes.is_empty(),
		name + ": CALIBRATION SUCCESS shows before any route")
	_check(not screen.passing_to_ready and screen.success_elapsed < SUCCESS,
		name + ": success is not an immediate or bypassed GO")
	# Initial success interval with both hands visible. Progress should not
	# depend on staying in CENTER, nor on a new LEFT/RIGHT stationary hold.
	for i in range(12):
		_frame(screen, 0.45 if i % 2 else 0.65, 0.10)
	_check(screen.live_step == 1 and routes.is_empty(),
		name + ": moving to play position does not restart calibration")
	# Deliver a _genuine_ new inference observation with either solo wrist
	# occlusion, low torso confidence, zero/two people, expired source or camera
	# loss. That may block GO but may not erase authenticated completed holds.
	match interruption:
		"wrists":
			for i in range(8):
				_frame(screen, 0.25 if i % 2 else 0.75, 0.10, false)
		"low_conf":
			for i in range(4):
				_invalid_frame(screen, 1, true, false, 20, 0.10)
		"zero":
			_invalid_frame(screen, 0, true, false, 20, 0.15)
		"crowd":
			_invalid_frame(screen, 2, true, false, 20, 0.15)
		"stale":
			_invalid_frame(screen, 1, true, true, 1800, 0.15)
		"disconnect":
			pose.set("active", false)
			pose.set("current_status", {"state": "off", "pose": false, "people": -1,
				"camera": false, "detail": "Synthetic source disconnected."})
			screen._process(0.15)
		"session":
			pose.set("session_token", "no-loop-reconnected-" + name)
			# A new physical camera worker supplies a new lock epoch. The test
			# substitutes that handshake without starting an actual worker;
			# keeping the old epoch/session token would reject ALL genuine
			# replacement-session poses even after the camera is reconnected.
			pose.set("_bound_player_epoch", -1)
			pose.set("_bound_player_session", "")
			screen._process(0.15)
	_check(screen.live_step == 1 and screen.measured_points == points,
		"%s: RED: authenticated neutral measurement must NEVER reset after success on %s" % [name, interruption])
	_check(bool(pose.calibration.get("valid", false)),
		"%s: RED: completed calibration remains valid after %s" % [name, interruption])
	_check(screen.success_running and overlay.visible,
		"%s: RED: success remains latched (can pause), never restarts neutral hold" % name)
	var live_texture := stage.get_node("CameraArea/LiveCameraInset") as TextureRect
	_check(live_texture != null and live_texture.texture == camera_texture,
		name + ": fresh-camera preview cache survives moving, missing joints or worker recovery")
	_check(routes.is_empty(), name + ": no unsafe or duplicate gameplay routes during disturbance")
	# Never allow stale/zero/crowd/disconnected to reach GO when success time
	# elapses. Reissue real solo packets before resuming the remaining interval.
	if interruption not in ["wrists", "low_conf"]:
		screen._process(SUCCESS + 0.2)
		_check(routes.is_empty(), name + ": never GO without fresh, unambiguous solo pose")
		_check(screen.live_step == 1 and screen.measured_points == points,
			name + ": long invalid-source delay freezes success instead of recapturing")
	# A recovering source earns only verified fresh packets, never time during
	# absence. At most a single route may be emitted by any repeated _process.
	for i in range(40):
		_frame(screen, 0.60 if i % 2 else 0.42, 0.10)
	_check(routes.size() == 1,
		"%s: exactly ONE route after live solo returns (found %d)" % [name, routes.size()])
	if routes.size() == 1:
		var route := routes[0]
		var payload: Dictionary = route["payload"]
		_check(route["target"] == "gameplay", name + ": target is real shared gameplay wrapper")
		_check(bool(payload.get("start_countdown", false)) and bool(payload.get("camera_live", false))
			and bool(payload.get("calibration_measured", false)),
			name + ": route retains live camera and 3-2-1 gate")
		_check(bool(payload.get("guided_tutorial", not guided)) == guided,
			name + ": Guided/Play flag preserved for DIRECT shared countdown")
		_check(not bool(payload.get("keyboard_mode", true)) and
			not bool(payload.get("calibration_skipped", true)),
			name + ": never bypass physical calibration with keyboard/demo")
		_check(bool(payload.get("calibration_neutral_only", false))
			and is_equal_approx(float(payload.get("calibration_center", -1.0)), 0.50)
			and not payload.has("calibration_left") and not payload.has("calibration_right"),
			name + ": payload carries measured neutral center without guessed floor bounds")
		await _assert_wrapper_route(name, guided, payload)
	for i in range(8):
		_frame(screen, 0.5, 0.10)
		screen._continue_flow()
	_check(routes.size() == 1, name + ": repeated post-success callbacks cannot duplicate gameplay route")
	screen.queue_free()
	await process_frame
	# Routing owns the live camera once passing_to_ready becomes true; never
	# stop an actual worker here because this QA never launched one.
	pose.set("worker_pid", -1)
	pose.stop_camera()


func _assert_wrapper_route(tag: String, guided: bool, payload: Dictionary) -> void:
	var wrapper := gameplay_scene.instantiate() as Control
	_check(wrapper != null and wrapper.get_script() != null, tag + ": shared gameplay script loads")
	if wrapper == null:
		return
	root.add_child(wrapper)
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrapper.set_context(payload)
	await process_frame
	await process_frame
	var mini := wrapper.get("active_game") as Control
	_check(mini != null and mini.process_mode == Node.PROCESS_MODE_DISABLED,
		tag + ": direct 3-2-1 freezes gameplay/timer/scoring until GO")
	_check(bool(wrapper.get("_countdown_requires_locked_pose")),
		tag + ": source safety remains mandatory even after calibration is measured")
	_check(not _has_legacy_spotlight_field(wrapper)
		and wrapper.get_node_or_null("GuidedSpotlight") == null,
		tag + ": removed Spotlight feature is not instantiated")
	var game_phase: String = String(wrapper.get("guided_stage"))
	if guided:
		_check(game_phase == "tutorial"
			and bool(mini.call("is_tutorial_active"))
			and not is_instance_valid(wrapper.get("countdown_panel")),
			tag + ": Guided Tutorial renders interactive minigame explanation BEFORE 3-2-1")
		wrapper.call("_complete_countdown_start")
		_check(String(wrapper.get("guided_stage")) == "tutorial"
			and mini.process_mode == Node.PROCESS_MODE_DISABLED,
			tag + ": no GO or countdown bypass while guided explanation is active")
		mini.call("skip_guided_tutorial")
		await process_frame
		await process_frame
	else:
		_check(game_phase == "countdown",
			tag + ": ordinary Play starts from verified calibration at countdown")
	_check(String(wrapper.get("guided_stage")) == "countdown" and
		is_instance_valid(wrapper.get("countdown_panel")),
		tag + ": explanation ends before countdown; normal Play enters countdown directly")
	# Before GO artificially expire source; with no newly observed solo student
	# it MUST hold at 1, despite old success/round measurements.
	pose.set("current_status", {"state": "tracking", "pose": false, "camera": true,
		"camera_phase": "tracking", "people": 0, "camera_frame_age_ms": 15,
		"lock_state": "lost"})
	pose.set("player_x", -1.0)
	wrapper.call("_complete_countdown_start")
	_check(String(wrapper.get("guided_stage")) == "countdown" and
		bool(wrapper.get("_countdown_waiting_for_pose")),
		tag + ": 3-2-1 freezes at GO without fresh solo source")
	_check(mini != null and mini.process_mode == Node.PROCESS_MODE_DISABLED,
		tag + ": no minigame processing while source absent")
	_packet(0.50, true)
	wrapper.call("_complete_countdown_start")
	# Production _clear_countdown_ui() resets its stage to blank AFTER a
	# successful single GO, whereas "countdown" means still frozen.
	_check(String(wrapper.get("guided_stage")) == "" and
		mini != null and mini.process_mode == Node.PROCESS_MODE_INHERIT,
		tag + ": exactly one genuine GO after returning solo source")
	wrapper.call("_complete_countdown_start")
	_check(String(wrapper.get("guided_stage")) == "" and
		mini != null and mini.process_mode == Node.PROCESS_MODE_INHERIT,
		tag + ": duplicate GO callback is inert")
	# Never let synthetic worker_pid=self survive into gameplay._exit_tree().
	pose.set("worker_pid", -1)
	wrapper.queue_free()
	await process_frame
	await process_frame


func _frame(calibration: Control, x: float, delta: float, wrists: bool = true) -> void:
	_packet(x, wrists, delta)
	calibration._process(delta)


func _packet(x: float, wrists: bool, delta: float = 0.10) -> void:
	pose.set("active", true)
	var fresh := {"state": "tracking", "pose": true, "camera": true,
		"camera_phase": "tracking", "people": 1, "foreground_people": 1,
		"foreground_ambiguous": false, "occupancy_verified": true,
		"player_lock_epoch": 1, "lock_state": "locked",
		"token": String(pose.session_token), "kind": "pose", "when": source_clock + delta,
		"camera_frame_age_ms": 20, "fps": 10.0, "x": x, "pose_conf": 0.98,
		"hand_observation_valid": wrists, "hand_up": false}
	source_clock += delta
	pose.call("_apply_pose_packet", fresh, Time.get_ticks_msec())
	# Render can be smoothed independently; stable source torso X remains exact.
	pose.set("player_x", x)
	pose.call("_record_fresh_calibration_pose", fresh, source_clock)


func _invalid_frame(calibration: Control, people: int, camera: bool,
		pose_ok: bool, source_age: int, delta: float) -> void:
	var bad := {"state": "tracking", "pose": pose_ok, "camera": camera,
		"camera_phase": "tracking", "people": people, "foreground_people": people,
		"foreground_ambiguous": people != 1,
		"occupancy_verified": people == 1, "player_lock_epoch": 1,
		"token": String(pose.session_token), "kind": "pose", "when": source_clock + delta,
		"lock_state": "locked" if people == 1 else "lost",
		"camera_frame_age_ms": source_age, "fps": 10.0,
		"x": 0.52 if pose_ok else -1.0, "pose_conf": 0.03,
		"hand_observation_valid": false, "hand_up": false}
	pose.set("active", camera)
	source_clock += delta
	pose.call("_apply_pose_packet", bad, Time.get_ticks_msec())
	# Invalid observations may NEVER be recorded as a new valid hold sample.
	pose.call("_record_fresh_calibration_pose", bad, source_clock)
	calibration._process(delta)


func _fake_texture() -> Texture2D:
	var image := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.22, 0.45, 0.66, 1.0))
	return ImageTexture.create_from_image(image)


func _has_legacy_spotlight_field(wrapper: Control) -> bool:
	for property in wrapper.get_property_list():
		if String(property.get("name", "")) == "spotlight_overlay":
			return true
	return false


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("CALIBRATION SUCCESS LOOP RED: ", label)


func _finish() -> void:
	for label in failures.slice(0, mini(failures.size(), 50)):
		push_error("CALIBRATION SUCCESS LOOP QA: " + label)
	if failures.size() > 50:
		print("... suppressed ", failures.size() - 50, " other failures")
	print("CALIBRATION SUCCESS NO-LOOP: %s checks=%d failures=%d cases=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), cases])
	quit(0 if failures.is_empty() else 1)
