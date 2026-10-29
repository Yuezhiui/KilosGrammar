extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_calibration_prewarm_bridge.gd
# Starts the real OFFLINE pose model and CUDA warmup with --prewarm, but NEVER
# starts a webcam, YOLO camera tracker, gameplay screen, or database connection.
# The authenticated start_camera command is sent ONLY to a fake localhost port.
# A measured cold CUDA model load/warmup on this Windows PC is ~30 seconds,
# which exceeds the former 25-second TEST watchdog even when the worker works.
# This timeout verifies eventual readiness, not a launch-speed SLA. The READY
# latency is printed independently; menu/form prewarming hides that cost.
const PREWARM_TIMEOUT_MS := 60000
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pose := root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload resolves")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	var model_dir := ProjectSettings.globalize_path("user://pose_models")
	var model_path := model_dir.path_join("yolo26n-pose.pt")
	var bundled := OS.get_executable_path().get_base_dir().path_join("runtime/models/yolo26n-pose.pt")
	if not FileAccess.file_exists(model_path) and not FileAccess.file_exists(bundled):
		print("CALIBRATION PREWARM: SKIP — no preinstalled local YOLO26n weights")
		_finish()
		return
	var actual_weights := model_path if FileAccess.file_exists(model_path) else bundled
	_check(FileAccess.get_file_as_bytes(actual_weights).size() > 7000000,
		"genuine existing offline YOLO26n weights available (7+ MB)")
	var warm_started := Time.get_ticks_msec()
	var created := bool(pose.call("prewarm_camera_model"))
	_check(created, "prewarm launches a genuine local worker process")
	if not created:
		pose.stop_camera()
		_finish()
		return
	var worker_pid := int(pose.get("worker_pid"))
	_check(worker_pid > 0 and OS.is_process_running(worker_pid),
		"prewarming Python worker is running in isolation")
	_check(bool(pose.call("is_model_prestarting")) and not bool(pose.get("active")),
		"worker model starts with webcam access OFF")
	_check(pose.get("preview_texture") == null and int(pose.get("packet_sequence")) == 0,
		"no real webcam frame or fake locked student during prewarm")

	var deadline := Time.get_ticks_msec() + PREWARM_TIMEOUT_MS
	var ready := false
	var observed_states: Array[String] = []
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var status: Dictionary = pose.get("current_status")
		var state := String(status.get("state", ""))
		if observed_states.is_empty() or observed_states.back() != state:
			observed_states.append(state)
		if state == "ready" and bool(status.get("model_ready", false)):
			ready = true
			break
		if state == "error" or worker_pid <= 0 or not OS.is_process_running(worker_pid):
			break
	_check(ready, "real YOLO model sends READY UDP status within bounded startup: %s" % [observed_states])
	if ready:
		print("PREWARM MODEL READY LATENCY: %d ms; webcam still closed" %
			[Time.get_ticks_msec() - warm_started])
		_check(int(pose.get("_model_control_port")) >= 1024,
			"READY carries a usable authenticated local control port")
		var saved_token := String(pose.get("session_token"))
		_check(bool(pose.call("prewarm_camera_model")) and
			int(pose.get("worker_pid")) == worker_pid and
			String(pose.get("session_token")) == saved_token,
			"repeat prewarm is idempotent and never reloads/reopens camera")
		_check(not bool(pose.get("active")) and bool(pose.call("is_model_prestarting")),
			"READY maintains CAMERA OFF until teacher enters calibration")
		_check(pose.get("preview_texture") == null and int(pose.get("packet_sequence")) == 0,
			"prewarm never performs camera capture or player enrollment")
		await _test_mock_start_command(pose)

	# Explicitly stop only the worker started by this test. Closing prewarm
	# never opens a real camera, and does not affect other system processes.
	pose.stop_camera()
	for _i in range(30):
		if not OS.is_process_running(worker_pid):
			break
		await process_frame
	_check(not OS.is_process_running(worker_pid),
		"stopping model prewarm terminates the owned Python worker")
	_check(not bool(pose.get("active")) and not bool(pose.call("is_model_prestarting")) and
		int(pose.get("worker_pid")) == -1,
		"stopped worker clears camera/prewarm process state")

	# Simulate worker failure without launching any replacement subprocess.
	var receiver := PacketPeerUDP.new()
	_check(receiver.bind(0, "127.0.0.1") == OK,
		"mock failed worker can be represented by an isolated local socket")
	pose.set("peer", receiver)
	pose.set("session_token", "mock-prewarm-failed-session")
	pose.set("_model_prestarting", true)
	pose.set("active", false)
	pose.set("worker_pid", -1)
	pose.set("_last_packet_ms", Time.get_ticks_msec())
	pose.call("_process", 0.016)
	_check(String((pose.get("current_status") as Dictionary).get("state", "")) == "error",
		"failed prewarm worker reports error without auto-opening camera")
	_check(not bool(pose.call("is_model_prestarting")) and not bool(pose.get("active")),
		"failed prewarm exits safely and can be explicitly retried")
	pose.stop_camera()
	var restarted := bool(pose.call("prewarm_camera_model"))
	_check(restarted, "prewarm can be restarted cleanly after synthetic worker failure")
	if restarted:
		var second_worker := int(pose.get("worker_pid"))
		_check(second_worker > 0 and second_worker != worker_pid,
			"recovered prewarm creates a distinct owned Python worker process")
		var retry_deadline := Time.get_ticks_msec() + PREWARM_TIMEOUT_MS
		var retry_ready := false
		while Time.get_ticks_msec() < retry_deadline:
			await process_frame
			var retry_status: Dictionary = pose.get("current_status")
			if String(retry_status.get("state", "")) == "ready" and bool(retry_status.get("model_ready", false)):
				retry_ready = true
				break
			if String(retry_status.get("state", "")) == "error" or not OS.is_process_running(second_worker):
				break
		_check(retry_ready and not bool(pose.get("active")),
			"failed model worker safely recovers to READY with camera still OFF")
		pose.stop_camera()
		_check(not OS.is_process_running(second_worker),
			"recovered worker also shuts down without orphan processes")
	_finish()


func _test_mock_start_command(pose: Node) -> void:
	var mock := PacketPeerUDP.new()
	var error := mock.bind(0, "127.0.0.1")
	_check(error == OK, "mock start control socket binds on localhost")
	if error != OK:
		return
	var real_port := int(pose.get("_model_control_port"))
	var authorized_session := String(pose.get("session_token"))
	pose.set_process(false)
	pose.set("_model_control_port", mock.get_local_port())
	pose.set("_camera_start_requested", true)
	pose.set("_camera_start_sent_ms", 0)
	pose.call("_request_warm_camera_start")
	var payload := {}
	for _i in range(8):
		if mock.get_available_packet_count() > 0:
			var parsed: Variant = JSON.parse_string(mock.get_packet().get_string_from_utf8())
			if parsed is Dictionary:
				payload = parsed
			break
		await process_frame
	_check(String(payload.get("command", "")) == "start_camera" and
		String(payload.get("token", "")) == authorized_session,
		"warm-camera trigger sends signed start command to MOCK port only")
	_check(not bool(pose.get("active")), "mock command cannot enable actual camera state")
	# Restore all flags BEFORE resuming the service: the real port must never
	# receive the test's command or start an actual camera.
	pose.set("_camera_start_requested", false)
	pose.set("_camera_start_sent_ms", 0)
	pose.set("_model_control_port", real_port)
	mock.close()
	pose.set_process(true)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("CALIBRATION PREWARM FAIL: ", description)


func _finish() -> void:
	print("CALIBRATION PREWARM: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
