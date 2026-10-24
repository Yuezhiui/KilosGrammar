extends Node
## Local webcam/YOLO bridge. The student chooses camera play before it starts.
## Calibrated LEFT/CENTER/RIGHT values survive temporary sensor interruptions.

signal status_updated(data: Dictionary)
signal preview_updated(texture: Texture2D)

const DEFAULT_MODEL := "yolo26n-pose.pt"
const LOST_AFTER_MS := 1750
const WORKER_STALL_MS := 5500
const WORKER_BOOT_TIMEOUT_MS := 120000
const RESTART_DELAY_MS := 1400
const RESTART_EXIT_TIMEOUT_MS := 4500
const MAX_AUTOMATIC_RESTARTS := 2
const POSITION_SMOOTHING_MS := 110.0
const MAX_STATUS_PACKET := 8192
# Gesture control must expire faster than the general-purpose body calibration.
# Without this independent freshness limit, a frozen/occluded camera could keep
# an arm gesture active for nearly two seconds after the final real pose.
const GESTURE_STALE_MS := 650

var peer: PacketPeerUDP
var worker_pid := -1
var active := false
var session_token := ""
var current_status: Dictionary = {"state": "off", "pose": false, "detail": "Camera is off."}
var last_pose_ms := 0
var packet_sequence := 0
var player_x := -1.0  # [0, 1] mirrored camera position; -1 means NO pose.
var calibration: Dictionary = {}
var preview_texture: ImageTexture

var camera_index := 0
var skeleton_visual_offset := Vector2.ZERO
var skeleton_visual_scale := Vector2.ONE
var _last_packet_ms := 0
var _launch_ms := 0
var _ever_tracked := false
var _worker_was_tracking := false
var _automatic_restarts := 0
var _restart_pending := false
var _restart_at_ms := 0
var _restart_deadline_ms := 0
var _smoothed_x := -1.0


func start_camera(index: int = 0) -> bool:
	if active:
		return true
	stop_camera()
	camera_index = index
	_automatic_restarts = 0
	_ever_tracked = false
	return _launch_worker()


func set_skeleton_visual_transform(offset: Vector2, size_scale: Vector2) -> void:
	# Visual-only: never modify student keypoints or calibration measurements.
	# These settings come from the editor-authored SkeletonPlacement rectangle.
	if is_finite(offset.x) and is_finite(offset.y) and is_finite(size_scale.x) \
			and is_finite(size_scale.y) and size_scale.x > 0.0 and size_scale.y > 0.0:
		skeleton_visual_offset = offset
		skeleton_visual_scale = size_scale


func _launch_worker(recovering: bool = false) -> bool:
	_worker_was_tracking = false
	peer = PacketPeerUDP.new()
	var error := peer.bind(0, "127.0.0.1")
	if error != OK:
		peer = null
		active = false
		_set_status({"state": "error", "pose": false, "detail": "Cannot start the local camera connection."})
		return false
	session_token = Crypto.new().generate_random_bytes(16).hex_encode()
	# An exported Windows EXE cannot directly execute a Python file packaged
	# only inside a .pck. The release ships an external worker next to the EXE.
	var worker := OS.get_executable_path().get_base_dir().path_join("ui/vision/pose_worker.py")
	if not FileAccess.file_exists(worker):
		worker = ProjectSettings.globalize_path("res://ui/vision/pose_worker.py")
	if not FileAccess.file_exists(worker):
		_close_transport()
		active = false
		_set_status({"state": "error", "pose": false,
			"detail": "Offline camera worker is missing from the installation. Ask the teacher to reinstall KilosGrammar."})
		return false
	var model_dir := ProjectSettings.globalize_path("user://pose_models")
	DirAccess.make_dir_recursive_absolute(model_dir)
	# School computers must work without an Internet connection. Find the
	# pretrained pose weights bundled beside the released EXE before looking
	# for an already-cached development copy. Never trigger an online download.
	var model_path := OS.get_executable_path().get_base_dir().path_join("runtime/models/yolo26n-pose.pt")
	if not FileAccess.file_exists(model_path):
		model_path = model_dir.path_join(DEFAULT_MODEL)
	if not FileAccess.file_exists(model_path):
		_close_transport()
		active = false
		_set_status({"state": "error", "pose": false,
			"detail": "Offline pose model is missing. Ask the teacher to install the KilosGrammar camera package."})
		return false
	var python := _choose_python()
	if python.is_empty():
		_close_transport()
		active = false
		_set_status({"state": "error", "pose": false, "detail": "Python was not found. Ask the teacher for help."})
		return false
	var arguments := PackedStringArray([
		"-u", worker, "--port", str(peer.get_local_port()),
		"--token", session_token, "--camera", str(camera_index),
		"--model", model_path, "--weights-dir", model_dir,
		"--bones-offset-x", str(skeleton_visual_offset.x),
		"--bones-offset-y", str(skeleton_visual_offset.y),
		"--bones-scale-x", str(skeleton_visual_scale.x),
		"--bones-scale-y", str(skeleton_visual_scale.y)
	])
	if python.to_lower().get_file() in ["py", "py.exe"]:
		arguments.insert(0, "-3.11")
	if recovering:
		arguments.append("--recovery")
	worker_pid = OS.create_process(python, arguments, false)
	if worker_pid <= 0:
		_close_transport()
		active = false
		worker_pid = -1
		_set_status({"state": "error", "pose": false, "detail": "Could not start the camera helper. Ask the teacher for help."})
		return false
	active = true
	player_x = -1.0
	_smoothed_x = -1.0
	preview_texture = null
	var now := Time.get_ticks_msec()
	last_pose_ms = 0
	_last_packet_ms = now
	_launch_ms = now
	set_process(true)
	_set_status({"state": "loading", "pose": false, "lock_state": "waiting", "detail": "Starting camera. Stand inside the CENTER box."})
	return true


func _close_transport() -> void:
	if peer != null:
		peer.close()
		peer = null
	session_token = ""


func stop_camera() -> void:
	_restart_pending = false
	if worker_pid > 0 and OS.is_process_running(worker_pid):
		OS.kill(worker_pid)
	worker_pid = -1
	_close_transport()
	active = false
	player_x = -1.0
	_smoothed_x = -1.0
	calibration.clear()
	preview_texture = null
	packet_sequence = 0
	last_pose_ms = 0
	set_process(false)
	_set_status({"state": "off", "pose": false, "detail": "Camera is off."})


func _exit_tree() -> void:
	stop_camera()


func _process(_delta: float) -> void:
	if not active:
		return
	var now := Time.get_ticks_msec()
	if _restart_pending:
		_continue_restart(now)
		return
	if peer == null:
		return
	# Process the latest camera preview and all pose/status packets in this batch.
	var newest_preview := PackedByteArray()
	for _i in range(mini(peer.get_available_packet_count(), 32)):
		var bytes := peer.get_packet()
		if bytes.is_empty():
			continue
		if bytes[0] == 1:
			if bytes.size() <= 60000:
				newest_preview = bytes.slice(1)
			continue
		if bytes.size() > MAX_STATUS_PACKET:
			continue
		var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if data is Dictionary:
			_apply_pose_packet(data, now)
	if not newest_preview.is_empty():
		var picture := Image.new()
		if picture.load_jpg_from_buffer(newest_preview) == OK:
			if preview_texture == null or Vector2i(preview_texture.get_size()) != picture.get_size():
				preview_texture = ImageTexture.create_from_image(picture)
			else:
				preview_texture.update(picture)
			preview_updated.emit(preview_texture)
	# Never let the last measured location masquerade as a live student.
	if player_x >= 0.0 and now - last_pose_ms > LOST_AFTER_MS:
		player_x = -1.0
		_set_status({"state": "stale", "pose": false, "lock_state": "occluded",
			"detail": "We lost sight of you. Step back into the camera view."})
	if worker_pid <= 0 or not OS.is_process_running(worker_pid):
		var recoverable := bool(current_status.get("recoverable", false))
		if _ever_tracked and (String(current_status.get("state", "")) != "error" or recoverable):
			_schedule_restart(now)
		else:
			_fail_camera("Camera helper stopped. Ask the teacher to restart camera.")
		return
	if now - _last_packet_ms > WORKER_STALL_MS and _worker_was_tracking:
		_schedule_restart(now)
	elif now - _launch_ms > WORKER_BOOT_TIMEOUT_MS and not _worker_was_tracking:
		_fail_camera("Camera setup timed out. Ask the teacher to retry camera.")


func _apply_pose_packet(data: Dictionary, now: int) -> void:
	if String(data.get("token", "")) != session_token or String(data.get("kind", "")) != "pose":
		return
	_last_packet_ms = now
	var valid := String(data.get("state", "")) == "tracking" and bool(data.get("pose", false))
	var measurement: Variant = data.get("x", -1.0)
	valid = valid and (measurement is float or measurement is int)
	if valid:
		var measured_x := float(measurement)
		valid = measured_x >= 0.0 and measured_x <= 1.0
		if valid:
			var elapsed := maxi(now - last_pose_ms, 16)
			if _smoothed_x < 0.0 or elapsed > LOST_AFTER_MS:
				_smoothed_x = measured_x
			else:
				var alpha := 1.0 - exp(-float(elapsed) / POSITION_SMOOTHING_MS)
				_smoothed_x = lerpf(_smoothed_x, measured_x, clampf(alpha, 0.0, 1.0))
			player_x = clampf(_smoothed_x, 0.0, 1.0)
			last_pose_ms = now
			packet_sequence += 1
			_ever_tracked = true
			_worker_was_tracking = true
	if not valid:
		player_x = -1.0
	current_status = data.duplicate()
	if not valid:
		current_status["pose"] = false
		current_status["hand_up"] = false
		current_status["hand_observation_valid"] = false
		current_status["airplane_pose"] = false
		current_status["wing_roll"] = 0.0
	status_updated.emit(current_status.duplicate())


func _schedule_restart(now: int) -> void:
	if _restart_pending:
		return
	player_x = -1.0
	preview_texture = null
	if not _ever_tracked or _automatic_restarts >= MAX_AUTOMATIC_RESTARTS:
		_fail_camera("Camera connection interrupted. Ask the teacher to restart camera.")
		return
	_automatic_restarts += 1
	_restart_pending = true
	_restart_at_ms = now + RESTART_DELAY_MS
	_restart_deadline_ms = now + RESTART_EXIT_TIMEOUT_MS
	if worker_pid > 0 and OS.is_process_running(worker_pid):
		OS.kill(worker_pid)
	_set_status({"state": "recovering", "pose": false, "lock_state": "lost",
		"detail": "Reconnecting camera. Please stand alone in the CENTER box."})


func _continue_restart(now: int) -> void:
	# Never open a second webcam process while the first still holds the device.
	if worker_pid > 0 and OS.is_process_running(worker_pid):
		if now >= _restart_deadline_ms:
			_fail_camera("Camera is busy. Ask the teacher to restart camera.")
		return
	if now < _restart_at_ms:
		return
	_restart_pending = false
	worker_pid = -1
	_close_transport()
	# Keep the student's actual LEFT/CENTER/RIGHT readings and packet sequence.
	_launch_worker(true)


func _fail_camera(message: String) -> void:
	_restart_pending = false
	if worker_pid > 0 and OS.is_process_running(worker_pid):
		OS.kill(worker_pid)
	worker_pid = -1
	_close_transport()
	active = false
	player_x = -1.0
	preview_texture = null
	set_process(false)
	_set_status({"state": "error", "pose": false, "detail": message})


func has_valid_pose() -> bool:
	return active and player_x >= 0.0 and bool(current_status.get("pose", false)) \
		and String(current_status.get("state", "")) == "tracking" \
		and Time.get_ticks_msec() - last_pose_ms <= LOST_AFTER_MS


func has_fresh_gesture_pose() -> bool:
	## Calibration is position-only: students can drop/raise their arms without
	## redoing Center/Right/Left. A gesture requires a NEW valid student packet.
	return has_valid_pose() and bool(calibration.get("valid", false)) \
		and Time.get_ticks_msec() - last_pose_ms <= GESTURE_STALE_MS


func has_hand_raised() -> bool:
	## Either student's left OR right hand, never a bystander or stale packet.
	return has_fresh_gesture_pose() and bool(current_status.get("hand_up", false))


func has_valid_hand_observation() -> bool:
	## A valid torso alone cannot prove both hands are DOWN. Ignore packets
	## with occluded wrists or an unsettled player-lock release latch.
	return has_fresh_gesture_pose() and bool(current_status.get("hand_observation_valid", false))


func has_airplane_pose() -> bool:
	## Both arms extended and verified by the Python COCO keypoint detector.
	return has_fresh_gesture_pose() and bool(current_status.get("airplane_pose", false))


func airplane_wing_roll() -> float:
	## Legacy packet compatibility only. Human Plane now steers by the same
	## three measured LEFT/CENTER/RIGHT body positions as Catch the Word;
	## has_airplane_pose() simply enables or freezes aircraft movement.
	if not has_airplane_pose():
		return 0.0
	var value: Variant = current_status.get("wing_roll", 0.0)
	if not (value is float or value is int) or not is_finite(float(value)):
		return 0.0
	return clampf(float(value), -1.0, 1.0)


func set_calibration(left: float, center: float, right: float) -> bool:
	if not (left >= 0.0 and right <= 1.0 and right - left >= 0.18):
		return false
	if center <= left + 0.06 or center >= right - 0.06:
		return false
	calibration = {"left": left, "center": center, "right": right, "valid": true}
	return true


func set_center_calibration(center: float) -> bool:
	## Deprecated compatibility helper for old test fixtures. It synthesizes
	## side bounds and must NEVER be used for live gameplay. All three games,
	## including Human Plane, now require real left/center/right measurements.
	if not is_finite(center) or center < 0.14 or center > 0.86:
		return false
	var span := minf(0.25, minf(center, 1.0 - center) - 0.02)
	if span < 0.12 or not set_calibration(center - span, center, center + span):
		return false
	calibration["center_only"] = true
	return true


func normalized_body_x() -> float:
	if not has_valid_pose() or not bool(calibration.get("valid", false)):
		return 0.0
	var left := float(calibration["left"])
	var center := float(calibration["center"])
	var right := float(calibration["right"])
	# Neutral at the student's measured CENTER even for asymmetric side steps.
	if player_x <= center:
		return clampf((player_x - center) / (center - left), -1.0, 0.0)
	return clampf((player_x - center) / (right - center), 0.0, 1.0)


func _set_status(value: Dictionary) -> void:
	current_status = value
	status_updated.emit(value.duplicate())


func _choose_python() -> String:
	# The published game must run without Python preinstalled globally or an
	# Internet-based package installation. Prefer its packaged isolated runtime.
	var bundled := OS.get_executable_path().get_base_dir().path_join("database/.venv/Scripts/python.exe")
	if FileAccess.file_exists(bundled):
		return bundled
	var custom := OS.get_environment("KILOSGRAMMAR_PYTHON").strip_edges()
	if not custom.is_empty() and FileAccess.file_exists(custom):
		return custom
	# The source database/.venv may contain only psycopg (no YOLO/torch).
	# Do not accidentally use it when running the Godot editor on this PC.
	var existing := "C:/Espressif/tools/python/python.exe"
	if FileAccess.file_exists(existing):
		return existing
	var programs := OS.get_environment("LOCALAPPDATA") + "/Programs/Python/Python311/python.exe"
	if FileAccess.file_exists(programs):
		return programs
	return "py.exe" if OS.has_feature("windows") else "python3"
