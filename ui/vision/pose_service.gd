extends Node
## Session-only webcam/YOLO bridge. Nothing starts until START CAMERA is pressed.
## Frames and pose values never leave the local device or persist to disk.

signal status_updated(data: Dictionary)
signal preview_updated(texture: Texture2D)

const DEFAULT_MODEL := "yolo26n-pose.pt"
const LOST_AFTER_MS := 1750
const MAX_STATUS_PACKET := 8192

var peer: PacketPeerUDP
var worker_pid := -1
var active := false
var session_token := ""
var current_status: Dictionary = {"state": "off", "detail": "Camera is off."}
var last_pose_ms := 0
var packet_sequence := 0
var player_x := -1.0
var calibration: Dictionary = {}
var preview_texture: ImageTexture


func start_camera(camera_index: int = 0) -> bool:
	if active:
		return true
	stop_camera()
	peer = PacketPeerUDP.new()
	var error := peer.bind(0, "127.0.0.1")
	if error != OK:
		_set_status({"state": "error", "detail": "Cannot bind local pose socket: %s" % error})
		return false
	var token_bytes := Crypto.new().generate_random_bytes(16)
	session_token = token_bytes.hex_encode()
	var worker := ProjectSettings.globalize_path("res://ui/vision/pose_worker.py")
	var model_dir := ProjectSettings.globalize_path("user://pose_models")
	DirAccess.make_dir_recursive_absolute(model_dir)
	var python := _choose_python()
	if python.is_empty():
		peer.close()
		peer = null
		_set_status({"state": "error", "detail": "Python not found. See ui/vision/README.md"})
		return false
	var arguments := PackedStringArray([
		"-u", worker, "--port", str(peer.get_local_port()),
		"--token", session_token, "--camera", str(camera_index),
		"--model", DEFAULT_MODEL, "--weights-dir", model_dir
	])
	if python.to_lower().get_file() in ["py", "py.exe"]:
		arguments.insert(0, "-3.11")
	worker_pid = OS.create_process(python, arguments, false)
	if worker_pid <= 0:
		peer.close()
		peer = null
		_set_status({"state": "error", "detail": "Could not launch Python YOLO worker: " + python})
		return false
	active = true
	calibration.clear()
	preview_texture = null
	packet_sequence = 0
	last_pose_ms = Time.get_ticks_msec()
	set_process(true)
	_set_status({"state": "loading", "detail": "Starting webcam and loading YOLO26n..."})
	return true


func stop_camera() -> void:
	if worker_pid > 0 and OS.is_process_running(worker_pid):
		OS.kill(worker_pid)
	worker_pid = -1
	if peer != null:
		peer.close()
		peer = null
	active = false
	session_token = ""
	player_x = -1.0
	calibration.clear()
	preview_texture = null
	packet_sequence = 0
	set_process(false)
	_set_status({"state": "off", "detail": "Camera is off."})


func _exit_tree() -> void:
	stop_camera()


func _process(_delta: float) -> void:
	if not active or peer == null:
		return
	# Drop queued preview packets except the newest, avoiding renderer backlogs.
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
		if data is Dictionary and String(data.get("token", "")) == session_token and data.get("kind") == "pose":
			current_status = data
			if String(data.get("state", "")) == "tracking":
				last_pose_ms = Time.get_ticks_msec()
				player_x = clampf(float(data.get("x", -1.0)), 0.0, 1.0) if bool(data.get("pose", false)) else -1.0
				packet_sequence += 1
			status_updated.emit(current_status.duplicate())
	if not newest_preview.is_empty():
		var picture := Image.new()
		if picture.load_jpg_from_buffer(newest_preview) == OK:
			if preview_texture == null:
				preview_texture = ImageTexture.create_from_image(picture)
			else:
				preview_texture.update(picture)
			preview_updated.emit(preview_texture)
	if String(current_status.get("state", "")) == "tracking" and Time.get_ticks_msec() - last_pose_ms > LOST_AFTER_MS:
		player_x = -1.0
		_set_status({"state": "stale", "detail": "Pose feed interrupted; player controls suspended."})
	if worker_pid > 0 and not OS.is_process_running(worker_pid):
		active = false
		player_x = -1.0
		if String(current_status.get("state", "")) != "error":
			_set_status({"state": "error", "detail": "Pose worker exited. Check Python dependencies and camera permissions."})
		if peer != null:
			peer.close()
			peer = null
		worker_pid = -1
		set_process(false)


func has_valid_pose() -> bool:
	return active and player_x >= 0.0 and String(current_status.get("state", "")) == "tracking" and Time.get_ticks_msec() - last_pose_ms <= LOST_AFTER_MS


func set_calibration(left: float, center: float, right: float) -> bool:
	# A minimum 18% camera width range and distinct neutral center are required.
	if not (left >= 0.0 and right <= 1.0 and right - left >= 0.18):
		return false
	if center <= left + 0.06 or center >= right - 0.06:
		return false
	calibration = {"left": left, "center": center, "right": right, "valid": true}
	return true


func normalized_body_x() -> float:
	if not has_valid_pose() or not bool(calibration.get("valid", false)):
		return 0.0
	var left := float(calibration["left"])
	var right := float(calibration["right"])
	return clampf((player_x - left) / (right - left) * 2.0 - 1.0, -1.0, 1.0)


func _set_status(value: Dictionary) -> void:
	current_status = value
	status_updated.emit(value.duplicate())


func _choose_python() -> String:
	var custom := OS.get_environment("KILOSGRAMMAR_PYTHON").strip_edges()
	if not custom.is_empty() and FileAccess.file_exists(custom):
		return custom
	# Prefer the pre-existing project machine environment with Ultralytics.
	var existing := "C:/Espressif/tools/python/python.exe"
	if FileAccess.file_exists(existing):
		return existing
	var programs := OS.get_environment("LOCALAPPDATA") + "/Programs/Python/Python311/python.exe"
	if FileAccess.file_exists(programs):
		return programs
	return "py.exe" if OS.has_feature("windows") else "python3"
