extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_pose_retry_stationary_preview_rebind.gd
# Two full synthetic rounds with the SAME stationary SOLO student and real
# authored calibration TextureRect. No webcam, Python worker or database.
const SCENE := "res://ui/vision/calibration/calibration.tscn"
const SESSION := "synthetic-worker-stationary-retry"
var service: Node
var sender: PacketPeerUDP
var checks := 0
var failures: Array[String] = []
var current_when := 100.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	service = root.get_node_or_null("PoseService")
	_check(service != null, "PoseService autoload loaded for stationary Retry")
	if service == null:
		_finish()
		return
	_start_synthetic_worker()
	await _verify_first_round_and_retry_rebind()
	await _verify_repeated_round_and_stale_clearing()
	await _verify_restart_with_no_ghost_bones()
	await _verify_results_stop_and_new_worker_stationary()
	# The mocked worker PID MUST NEVER reach Godot's stop_camera kill path.
	service.worker_pid = -1
	if sender != null:
		sender.close()
	service.stop_camera()
	_finish()


func _start_synthetic_worker() -> void:
	service.stop_camera()
	service.set_process(false)
	service.peer = PacketPeerUDP.new()
	_check(service.peer.bind(0, "127.0.0.1") == OK,
		"Loopback camera simulation binds without a physical webcam")
	sender = PacketPeerUDP.new()
	_check(sender.set_dest_address("127.0.0.1", service.peer.get_local_port()) == OK,
		"Loopback JPEG source uses only 127.0.0.1")
	service.worker_pid = OS.get_process_id() # Never kill; cleared at cleanup.
	service.active = true
	service.session_token = SESSION
	service._launch_ms = Time.get_ticks_msec()
	service._last_packet_ms = Time.get_ticks_msec()
	service._latest_worker_packet_time = -1.0
	service._worker_was_streaming = true
	service._worker_was_tracking = true
	service._ever_tracked = true


func _solo(x: float = 0.5, people: int = 1,
		state: String = "locked") -> Dictionary:
	return {
		"kind": "pose", "token": service.session_token, "state": "tracking",
		"camera": true, "camera_phase": "tracking", "pose": true,
		"lock_state": state, "locked_id": -1, "people": people,
		"camera_frame_age_ms": 24, "x": x,
		"plane_steering": x, "plane_steering_valid": true,
			# Catch's DEFAULT.png hold requires a genuinely observed lowered hand.
			# An unknown/raised wrist may never earn calibration progress.
			"plane_neutral_valid": true,
			"hand_observation_valid": true, "hand_up": false
	}


func _fake_jpeg() -> PackedByteArray:
	var picture := Image.create(48, 36, false, Image.FORMAT_RGB8)
	picture.fill(Color(0.14, 0.44, 0.19))
	var jpeg := PackedByteArray([1])
	jpeg.append_array(picture.save_jpg_to_buffer(0.85))
	return jpeg


func _deliver(status: Dictionary, include_preview: bool = true) -> void:
	current_when += 0.4
	status["when"] = current_when
	_check(sender.put_packet(JSON.stringify(status).to_utf8_buffer()) == OK,
		"Current solo source frame delivered from mocked worker")
	if include_preview:
		_check(sender.put_packet(_fake_jpeg()) == OK,
			"Current camera JPEG delivered without a physical webcam")
	await process_frame
	service._process(0.016)


func _mount_calibration() -> Control:
	var packed := load(SCENE) as PackedScene
	_check(packed != null, "Editor-authored calibration scene loads")
	if packed == null:
		return null
	var screen := packed.instantiate() as Control
	root.add_child(screen)
	screen.set_process(false) # No camera/menu/DB code runs automatically.
	screen.set("intro_running", false)
	screen.call("_finish_intro_only")
	return screen


func _mount_new_round_with_real_context() -> Control:
	## Exercise the actual router handoff used by Results -> Retry. The
	## calibration scene owns the call to begin_new_round_tracking() now.
	var packed := load(SCENE) as PackedScene
	if packed == null:
		return null
	var screen := packed.instantiate() as Control
	root.add_child(screen)
	screen.set_context({"activity": "Catch the Word", "student_name": "QA",
		"camera_requested": true, "keyboard_mode": false, "new_round": true})
	screen.set_process(false)
	return screen


func _unmount_calibration(screen: Control) -> void:
	if not is_instance_valid(screen):
		return
	screen.set("passing_to_ready", true) # Handoff must not stop mock worker.
	screen.queue_free()
	await process_frame


func _verify_first_round_and_retry_rebind() -> void:
	await _deliver(_solo(0.49))
	_check(service.preview_texture != null and service.has_valid_pose(),
		"First round displays fresh preview and stable stationary solo pose")
	var worker_before: int = service.worker_pid
	var token_before: String = service.session_token
	var peer_before: PacketPeerUDP = service.peer
	var first := _mount_calibration()
	if first == null:
		return
	var inset := first.get_node_or_null("TutorialStage/LiveCameraInset") as TextureRect
	_check(inset != null, "Real calibration preview TextureRect exists")
	if inset == null:
		await _unmount_calibration(first)
		return
	# The JPEG arrived BEFORE this new scene subscribed: a missing signal
	# replay previously left the Rectangle blank until another update.
	_check(service.refresh_calibration_preview(),
		"New scene replays current-session preview without waiting for exit/reentry")
	_check(inset.texture == service.preview_texture and inset.visible,
		"Actual new calibration TextureRect becomes visible from fresh cached JPEG")
	_check(service.set_calibration(0.18, 0.50, 0.82),
		"Stationary solo finishes initial round calibration")
	await _unmount_calibration(first)
	# New round with the SAME stationary person still in view. The old worker
	# is healthy, so no process/token/restart is required.
	var source_id_before: int = service.latest_pose_sample_id
	service.begin_new_round_tracking()
	_check(service.calibration.is_empty() and not service.has_valid_pose()
		and service.player_x < 0,
		"Retry explicitly starts new measurements and revokes old pose immediately")
	_check(service.worker_pid == worker_before and service.session_token == token_before
		and service.peer == peer_before and service.active,
		"Retry reuses the SAME live camera process, socket and token")
	_check(service.latest_pose_sample_id == source_id_before
		and service.get_pose_samples_after(0).is_empty(),
		"New round preserves monotonically increasing sample IDs, removes ONLY old frames")
	_check(not service._restart_pending and service._automatic_restarts == 0,
		"Retry never force-restarts a healthy camera process")
	_check(service.start_camera() and service.worker_pid == worker_before,
		"Calling start_camera during warm active stream is idempotent")
	var second := _mount_calibration()
	if second == null:
		return
	var second_inset := second.get_node_or_null("TutorialStage/LiveCameraInset") as TextureRect
	_check(second_inset != null and service.refresh_calibration_preview(),
		"Retry calibration can bind SAME live cached preview before next packet")
	_check(second_inset.texture == service.preview_texture and second_inset.visible,
		"Retry screen immediately shows camera pixels without moving the student")
	await _deliver(_solo(0.49))
	_check(service.has_valid_pose() and service.player_x > 0.0,
		"Fresh stationary solo packet resumes tracking without leaving frame")
	_check(service.latest_pose_sample_id > source_id_before
		and service.get_pose_samples_after(source_id_before).size() >= 1,
		"First fresh Retry sample is readable after the old scene's last source ID")
	_check(service.set_calibration(0.16, 0.49, 0.84),
		"Second round receives its OWN genuine calibration measurements")
	await _unmount_calibration(second)


func _verify_repeated_round_and_stale_clearing() -> void:
	var screen := _mount_new_round_with_real_context()
	if screen == null:
		_check(false, "Real Results -> Retry calibration could not mount")
		return
	_check(not service.has_valid_pose() and service.calibration.is_empty(),
		"Real Retry set_context begins third round without old measurements")
	# The editor-authored intro should not display bones before its countdown.
	var inset := screen.get_node_or_null("TutorialStage/LiveCameraInset") as TextureRect
	_check(inset != null and not inset.visible,
		"Retry intro hides preview until the actual countdown completes")
	screen.call("_process", 3.1)
	_check(not bool(screen.get("intro_running")) and inset.visible
		and inset.texture != null,
		"Real intro finish REBINDS live preview without waiting for movement")
	await _deliver(_solo(0.51))
	_check(service.has_valid_pose() and service.preview_texture != null,
		"Still-standing solo user appears normally in third round")
	var old_scene_sample_id: int = int(screen.get("last_fresh_sample_id"))
	_check(service.latest_pose_sample_id > old_scene_sample_id
		and not service.get_pose_samples_after(old_scene_sample_id).is_empty(),
		"Actual mounted Retry calibration sees new source ID instead of waiting for old count")
	# Four hundred milliseconds per fresh YOLO inference, repeated eight
	# DISTINCT source packets. Without the monotonic-ID fix this stage would
	# never reach the 3-second/8-frame requirement until the old counter was
	# surpassed, misleading the student into stepping away and re-entering.
	for i in range(9):
		await _deliver(_solo(0.51), false)
		screen.call("_process", 0.4)
	_check(int(screen.get("live_step")) >= 1 and
		(screen.get("measured_points") as Dictionary).has("center"),
		"Real third-round stationary CENTER hold completes with 8 fresh frames WITHOUT exit/reentry")
	_check(service.refresh_calibration_preview() and inset.texture != null,
		"Third round reconnects new view to same live worker stream")
	service._last_preview_ms = Time.get_ticks_msec() - 1800
	_check(not service.refresh_calibration_preview(),
		"Stale preview is NEVER replayed to newly mounted round")
	_check(inset.texture == null and not inset.visible
		and service.preview_texture == null,
		"Expired skeleton preview clears scene, cached texture and visibility")
	await _deliver(_solo(0.51))
	_check(inset.texture != null and inset.visible and service.has_valid_pose(),
		"Fresh new JPEG restores green-skeleton preview without person exiting")
	# A genuinely empty or crowded frame suspends both input and gesture, never
	# triggering fake bones from the previously cached picture.
	await _deliver(_solo(0.51, 2))
	_check(not service.has_valid_pose() and service.player_x == -1.0,
		"Two detected people pause gameplay despite an old cached solo preview")
	await _deliver(_solo(0.51, 0))
	_check(not service.has_valid_pose(),
		"Zero people pause input while waiting for real new solo YOLO packets")
	await _deliver(_solo(0.51, 1))
	_check(service.has_valid_pose(),
		"One fresh stable solo person resumes without camera or scene reset")
	await _unmount_calibration(screen)


func _verify_restart_with_no_ghost_bones() -> void:
	var saved: Dictionary = service.calibration.duplicate(true)
	# This test uses our own Godot PID only to satisfy the watchdog. Never let
	# PoseService._schedule_restart() issue OS.kill() against the test runner.
	service.worker_pid = -1
	service._schedule_restart(Time.get_ticks_msec())
	_check(service._restart_pending and service.preview_texture == null,
		"Recoverable worker restart immediately clears stale skeleton preview")
	_check(not service.refresh_calibration_preview(),
		"No old preview may be rebound while restart is pending")
	_check(service.calibration == saved,
		"Worker restart preserves completed round positions (if any)")
	# Do not physically execute scheduled OS.kill/launch_worker in this mock.
	service._restart_pending = false
	service._latest_worker_packet_time = -1.0
	service.session_token = "reconnected-stationary-camera"
	service._last_packet_ms = Time.get_ticks_msec()
	# Represent the just-reconnected worker as alive during the UDP exercise;
	# clear our mock PID before leaving this test.
	service.worker_pid = OS.get_process_id()
	var new_scene := _mount_calibration()
	if new_scene == null:
		return
	var inset := new_scene.get_node_or_null("TutorialStage/LiveCameraInset") as TextureRect
	_check(not service.refresh_calibration_preview() and inset.texture == null,
		"New scene stays blank until the restarted worker sends a real frame")
	await _deliver(_solo(0.52))
	_check(service.preview_texture != null and service.has_valid_pose(),
		"Reconnected worker accepts same stationary SOLO person without exiting")
	_check(inset.texture != null and inset.visible,
		"Reconnected camera repaints the actual scene with fresh JPEG")
	await _unmount_calibration(new_scene)


func _verify_results_stop_and_new_worker_stationary() -> void:
	# main_menu.gd sends stop_camera on entering Results. Unlike a reused
	# active worker, this destroys the previous token/socket/preview. A new
	# YOLO worker must stream the still-standing child on its FIRST solo pose;
	# no empty-camera ritual or ByteTrack ID registration is required.
	var previous_token: String = service.session_token
	service.worker_pid = -1 # Never kill the test runner.
	service.stop_camera()
	_check(not service.active and service.peer == null
		and service.preview_texture == null and service.calibration.is_empty(),
		"Results camera stop discards all old bones, worker state and round measurements")
	_check(not service.refresh_calibration_preview(),
		"Results stop cannot replay a dead worker's skeleton into new calibration")
	if sender != null:
		sender.close()
	_start_synthetic_worker()
	_check(service.active and service.session_token != previous_token,
		"New simulated camera worker is independent from Results' stopped stream")
	var screen := _mount_new_round_with_real_context()
	if screen == null:
		_check(false, "Retry calibration remount after Results stop must load")
		return
	var inset := screen.get_node_or_null("TutorialStage/LiveCameraInset") as TextureRect
	_check(not service.refresh_calibration_preview() and inset.texture == null,
		"New stopped-then-restarted camera remains blank before FIRST genuine JPEG")
	await _deliver(_solo(0.5))
	_check(service.has_valid_pose() and service.preview_texture != null,
		"First new YOLO frame reacquires stationary student without exiting scene")
	screen.call("_process", 3.1)
	_check(not bool(screen.get("intro_running")) and inset.texture != null and inset.visible,
		"Retry intro displays new worker's fresh bones without moving student")
	await _unmount_calibration(screen)
	service.worker_pid = -1 # Mock worker terminates; never kill this Godot process.
	_check(not service.refresh_calibration_preview()
		and service.preview_texture == null,
		"A dead worker cannot replay even a RECENT cached skeleton into next scene")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("RETRY STATIONARY PREVIEW FAIL: ", description)


func _finish() -> void:
	print("RETRY STATIONARY CAMERA PREVIEW: %s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
