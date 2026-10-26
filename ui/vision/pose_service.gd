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
const MAX_UDP_PACKETS_PER_FRAME := 192
const MAX_RECENT_POSE_SAMPLES := 96

var peer: PacketPeerUDP
var worker_pid := -1
var active := false
var session_token := ""
var current_status: Dictionary = {"state": "off", "pose": false, "detail": "Camera is off."}
var last_pose_ms := 0
var packet_sequence := 0
# Only render the newest UDP body pose, but retain a short bounded history of
# distinct, actually detected student frames for calibration's 8-sample hold.
# Coalescing 8 packets into one render frame must not turn 8 samples into 1.
var latest_pose_sample_id := 0
var _recent_pose_samples: Array[Dictionary] = []
var player_x := -1.0  # [0, 1] mirrored camera position; -1 means NO pose.
var calibration: Dictionary = {}
# Separate center-relative Human Plane steering; other games retain measured
# left/center/right CAMERA positions and normalized_body_x().
var plane_calibration: Dictionary = {}
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
var _latest_worker_packet_time := -1.0
var first_camera_preview_ms := -1
var first_valid_pose_ms := -1
var _model_prestarting := false
var _model_control_port := 0
var _camera_start_requested := false
var _camera_start_sent_ms := 0


func is_model_prestarting() -> bool:
	return _model_prestarting and not active


func prewarm_camera_model() -> bool:
	## Explicit camera-game selection starts LOCAL model/CUDA warmup while the
	## teacher fills out student setup. This does NOT open the webcam; actual
	## camera access still requires proceeding to calibration.
	if active or (_model_prestarting and worker_pid > 0 and OS.is_process_running(worker_pid)):
		return true
	stop_camera()
	_automatic_restarts = 0
	_ever_tracked = false
	return _launch_worker(false, true)


func start_camera(index: int = 0) -> bool:
	if active:
		return true
	if _model_prestarting and worker_pid > 0 and OS.is_process_running(worker_pid) and peer != null:
		# Reuse the same Python/CUDA process and cached model. Opening another
		# worker here would reintroduce the measured ~6-second cold start.
		camera_index = index
		active = true
		_camera_start_requested = true
		_launch_ms = Time.get_ticks_msec()
		_camera_start_sent_ms = 0
		_request_warm_camera_start()
		_set_status({"state": "loading", "pose": false, "lock_state": "waiting",
			"detail": "Model readying • connecting the camera without reloading YOLO."})
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


func _launch_worker(recovering: bool = false, prewarm_only: bool = false) -> bool:
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
	if prewarm_only:
		arguments.append("--prewarm")
	worker_pid = OS.create_process(python, arguments, false)
	if worker_pid <= 0:
		_close_transport()
		active = false
		worker_pid = -1
		_set_status({"state": "error", "pose": false, "detail": "Could not start the camera helper. Ask the teacher for help."})
		return false
	active = not prewarm_only
	_model_prestarting = prewarm_only
	_model_control_port = 0
	_camera_start_requested = false
	_camera_start_sent_ms = 0
	player_x = -1.0
	_smoothed_x = -1.0
	preview_texture = null
	var now := Time.get_ticks_msec()
	last_pose_ms = 0
	_latest_worker_packet_time = -1.0
	first_camera_preview_ms = -1
	first_valid_pose_ms = -1
	_last_packet_ms = now
	_launch_ms = now
	set_process(true)
	_set_status({"state": "prewarming" if prewarm_only else "loading", "pose": false,
		"lock_state": "waiting", "detail": "Warming local YOLO model • webcam remains off."
		if prewarm_only else "Starting camera. Stand inside the CENTER box."})
	return true


func _request_warm_camera_start() -> void:
	if not _model_prestarting or not _camera_start_requested or peer == null \
			or _model_control_port < 1024:
		return
	var now := Time.get_ticks_msec()
	if _camera_start_sent_ms > 0 and now - _camera_start_sent_ms < 1200:
		return
	peer.set_dest_address("127.0.0.1", _model_control_port)
	var request := {"command": "start_camera", "token": session_token}
	if peer.put_packet(JSON.stringify(request).to_utf8_buffer()) == OK:
		_camera_start_sent_ms = now


func _close_transport() -> void:
	if peer != null:
		peer.close()
		peer = null
	session_token = ""


func stop_camera() -> void:
	_restart_pending = false
	_model_prestarting = false
	_model_control_port = 0
	_camera_start_requested = false
	_camera_start_sent_ms = 0
	if worker_pid > 0 and OS.is_process_running(worker_pid):
		OS.kill(worker_pid)
	worker_pid = -1
	_close_transport()
	active = false
	player_x = -1.0
	_smoothed_x = -1.0
	calibration.clear()
	plane_calibration.clear()
	preview_texture = null
	packet_sequence = 0
	latest_pose_sample_id = 0
	_recent_pose_samples.clear()
	last_pose_ms = 0
	_latest_worker_packet_time = -1.0
	first_camera_preview_ms = -1
	first_valid_pose_ms = -1
	set_process(false)
	_set_status({"state": "off", "pose": false, "detail": "Camera is off."})


func _exit_tree() -> void:
	stop_camera()


func _process(_delta: float) -> void:
	if not active and not _model_prestarting:
		return
	var now := Time.get_ticks_msec()
	if _restart_pending:
		_continue_restart(now)
		return
	if peer == null:
		return
	# When inference packets arrive faster than the UI can render, processing
	# every old state produces visible lag and unnecessary signal callbacks.
	# Drain the available local UDP batch, retaining just the newest preview
	# and freshest valid pose/status packet. Pose freshness is still enforced
	# by the worker timestamp and the normal lost-pose checks below.
	var newest_preview := PackedByteArray()
	var latest_pose := {}
	var newest_worker_time := _latest_worker_packet_time
	var previous_source_sample_id := latest_pose_sample_id
	for _i in range(mini(peer.get_available_packet_count(), MAX_UDP_PACKETS_PER_FRAME)):
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
		if data is Dictionary and String(data.get("token", "")) == session_token \
				and String(data.get("kind", "")) == "pose":
			var packet_when := float(data.get("when", -1.0))
			# Strictly newer monotonic source frames only. A duplicate UDP packet
			# must never refresh a stale pose or earn extra calibration samples.
			if is_finite(packet_when) and packet_when > newest_worker_time:
				_record_fresh_calibration_pose(data, packet_when)
				latest_pose = data
				newest_worker_time = packet_when
	if not latest_pose.is_empty():
		_latest_worker_packet_time = newest_worker_time
		if _model_prestarting:
			var supplied_port := int(latest_pose.get("control_port", 0))
			if supplied_port >= 1024 and supplied_port <= 65535:
				_model_control_port = supplied_port
			if _camera_start_requested and String(latest_pose.get("state", "")) in ["tracking", "recovering", "loading"] \
					and bool(latest_pose.get("camera", false)):
				_model_prestarting = false
				_camera_start_requested = false
		_apply_pose_packet(latest_pose, now)
		# One rendered latest pose is enough for responsive steering, but a
		# coalesced UDP batch may contain many unique, true YOLO observations.
		# Expose their cumulative packet count to the calibration hold logic.
		if bool(latest_pose.get("pose", false)):
			packet_sequence += maxi(latest_pose_sample_id - previous_source_sample_id - 1, 0)
	if _model_prestarting and _camera_start_requested:
		_request_warm_camera_start()
	if not newest_preview.is_empty():
		var picture := Image.new()
		if picture.load_jpg_from_buffer(newest_preview) == OK:
			if first_camera_preview_ms < 0:
				first_camera_preview_ms = now - _launch_ms
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
		if _model_prestarting and not _ever_tracked:
			_fail_camera("Pose model preload stopped. Camera setup can be retried.")
			return
		var recoverable := bool(current_status.get("recoverable", false))
		if _ever_tracked and (String(current_status.get("state", "")) != "error" or recoverable):
			_schedule_restart(now)
		elif recoverable:
			# A webcam read can transiently fail before the first StudentLock
			# enrollment. Retry only explicitly recoverable worker errors; do
			# not loop on missing model, camera permission or installation errors.
			_schedule_restart(now, true)
		else:
			_fail_camera("Camera helper stopped. Ask the teacher to restart camera.")
		return
	if now - _last_packet_ms > WORKER_STALL_MS and _worker_was_tracking:
		_schedule_restart(now)
	elif now - _launch_ms > WORKER_BOOT_TIMEOUT_MS and not _worker_was_tracking \
			and not (_model_prestarting and not _camera_start_requested):
		# A deliberately prewarmed model may wait while the teacher completes
		# student setup. That is NOT a camera startup failure; only apply the
		# timeout once calibration has explicitly requested the webcam.
		_fail_camera("Camera setup timed out. Ask the teacher to retry camera.")


func _record_fresh_calibration_pose(data: Dictionary, packet_when: float) -> void:
	# The worker marks pose=true only for its uniquely locked student. Exclude
	# loading/error/unlocked and out-of-range coordinates; the local token and
	# strictly increasing packet timestamp were checked by the UDP receiver.
	if not active or String(data.get("state", "")) != "tracking" or not bool(data.get("pose", false)):
		return
	var measured: Variant = data.get("x", -1.0)
	if not (measured is float or measured is int):
		return
	var x := float(measured)
	if not is_finite(x) or x < 0.0 or x > 1.0:
		return
	# Defend the bounded sample history against duplicated/reordered source
	# timestamps even if a test/caller bypasses the UDP receiver.
	if not _recent_pose_samples.is_empty() \
			and packet_when <= float(_recent_pose_samples.back().get("when", -1.0)):
		return
	var pose_sample: Dictionary = {"x": x, "when": packet_when}
	# These fields are present only when the worker selected a verified,
	# uniquely locked student. Keep source measurements before any UI smoothing.
	var raw_steering: Variant = data.get("plane_steering", null)
	var track_id := int(data.get("locked_id", -1))
	if String(data.get("lock_state", "")) == "locked" and track_id >= 0 \
			and bool(data.get("plane_steering_valid", false)) \
			and bool(data.get("plane_neutral_valid", false)) \
			and (raw_steering is float or raw_steering is int) \
			and is_finite(float(raw_steering)) and absf(float(raw_steering)) <= 1.0:
		pose_sample["plane_steering"] = float(raw_steering)
		pose_sample["locked_id"] = track_id
	latest_pose_sample_id += 1
	pose_sample["id"] = latest_pose_sample_id
	_recent_pose_samples.append(pose_sample)
	if _recent_pose_samples.size() > MAX_RECENT_POSE_SAMPLES:
		_recent_pose_samples.pop_front()


func get_pose_samples_after(last_id: int) -> Array[Dictionary]:
	# Read-only snapshot; callers cannot mutate the service's bounded history.
	var samples: Array[Dictionary] = []
	for entry: Dictionary in _recent_pose_samples:
		if int(entry["id"]) > last_id:
			samples.append(entry.duplicate())
	return samples


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
			if first_valid_pose_ms < 0:
				first_valid_pose_ms = now - _launch_ms
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
		current_status["plane_steering_valid"] = false
		current_status["plane_neutral_valid"] = false
	status_updated.emit(current_status.duplicate())


func _schedule_restart(now: int, allow_before_enrollment: bool = false) -> void:
	if _restart_pending:
		return
	player_x = -1.0
	preview_texture = null
	if (not _ever_tracked and not allow_before_enrollment) \
			or _automatic_restarts >= MAX_AUTOMATIC_RESTARTS:
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
	_model_prestarting = false
	_model_control_port = 0
	_camera_start_requested = false
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


func has_recent_missing_student_observation() -> bool:
	## A camera-notice prompt is appropriate only if a RECENT real inference
	## frame could not find the locked student. Loading/restarting/stalled
	## camera, ambiguous enrollment, invalid calibration or a missing wrist
	## are NOT evidence that the child left the camera.
	if not active or String(current_status.get("state", "")) != "tracking" \
			or not bool(current_status.get("camera", false)) \
			or bool(current_status.get("pose", false)) \
			or _last_packet_ms <= 0 \
			or Time.get_ticks_msec() - _last_packet_ms > 1000:
		return false
	# A failed StudentLock handshake / temporarily occluded wrist is not the
	# same as an empty camera frame. In particular, 'lost' can coexist with
	# other visible candidates. Only an explicit zero-person inference proves
	# that the camera currently sees nobody.
	return int(current_status.get("people", -1)) == 0


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
	## Legacy optional bank-angle diagnostic only. Human Plane steers by
	## normalized_plane_steering(), using its one measured center and live
	## torso X; this old pose flag does not gate flight movement.
	if not has_airplane_pose():
		return 0.0
	var value: Variant = current_status.get("wing_roll", 0.0)
	if not (value is float or value is int) or not is_finite(float(value)):
		return 0.0
	return clampf(float(value), -1.0, 1.0)


func set_stationary_plane_calibration(center: float, locked_id: int,
		camera_center_x: float, neutral_noise: float = 0.0) -> bool:
		## One REAL center position is measured with both wrists; gameplay uses
		## the same torso X while accepting either wrist. Symmetric gain and dead
		## zone are derived from neutral jitter, not invented side measurements.
	if locked_id < 0 or not is_finite(camera_center_x) \
			or camera_center_x < 0.28 or camera_center_x > 0.72:
		return false
	if not is_finite(center) or center < 0.28 or center > 0.72 \
			or absf(center - camera_center_x) > 0.065 \
			or not is_finite(neutral_noise) or neutral_noise < 0.0 or neutral_noise > 0.15:
		return false
	var deadzone := clampf(neutral_noise * 2.5 + 0.018, 0.018, 0.055)
	# Roughly 18-30% of camera width from the child's measured CENTER gives
	# full lateral steering. Widen it for an unusually noisy neutral stance.
	var sensitivity := clampf(0.18 + neutral_noise * 3.5, 0.18, 0.30)
	plane_calibration = {
		"valid": true, "mode": "plane_stationary", "center": center,
		"steering_mode": "centered_torso_x_one_wrist",
		"sensitivity": sensitivity, "deadzone": deadzone,
		"neutral_noise": neutral_noise, "neutral_only": true,
		"locked_id": locked_id, "camera_center_x": camera_center_x
	}
	# Existing gameplay routing checks calibration.valid, but steering here
	# never impersonates the other games' measured floor/position limits.
	calibration = plane_calibration.duplicate()
	return true


func has_stationary_plane_pose() -> bool:
	## A bystander, a frozen packet or a new ByteTrack ID cannot control a
	## plane calibrated by another locked track.
	if not has_valid_pose() or not bool(plane_calibration.get("valid", false)) \
			or Time.get_ticks_msec() - last_pose_ms > GESTURE_STALE_MS \
			or String(current_status.get("lock_state", "")) != "locked" \
			or int(current_status.get("locked_id", -1)) != int(plane_calibration.get("locked_id", -2)) \
			or not bool(current_status.get("plane_steering_valid", false)):
		return false
	var raw: Variant = current_status.get("plane_steering", null)
	return (raw is float or raw is int) and is_finite(float(raw)) \
		and float(raw) >= 0.0 and float(raw) <= 1.0


func normalized_plane_steering() -> float:
		## -1 far LEFT, zero at measured CENTER, +1 far RIGHT. The raw field is
		## mirrored camera torso X; side holds are unnecessary for Human Plane.
	if not has_stationary_plane_pose():
		return 0.0
	var raw := float(current_status["plane_steering"])
	var center := float(plane_calibration["center"])
	var centered := raw - center
	var magnitude := absf(centered)
	var deadzone := float(plane_calibration["deadzone"])
	if magnitude <= deadzone:
		return 0.0
	var full_scale := maxf(float(plane_calibration["sensitivity"]) - deadzone, 0.05)
	return signf(centered) * clampf((magnitude - deadzone) / full_scale, 0.0, 1.0)


func set_calibration(left: float, center: float, right: float) -> bool:
	if not (left >= 0.0 and right <= 1.0 and right - left >= 0.18):
		return false
	if center <= left + 0.06 or center >= right - 0.06:
		return false
	calibration = {"left": left, "center": center, "right": right, "valid": true}
	plane_calibration.clear()
	return true


func set_center_calibration(center: float) -> bool:
	## Deprecated compatibility helper for old test fixtures. It synthesizes
	## floor side bounds and must NEVER be used for live gameplay. Normal
	## physical-position games still require their real left/center/right holds.
	if not is_finite(center) or center < 0.14 or center > 0.86:
		return false
	var span := minf(0.25, minf(center, 1.0 - center) - 0.02)
	if span < 0.12 or not set_calibration(center - span, center, center + span):
		return false
	calibration["center_only"] = true
	return true


func normalized_body_x() -> float:
	if not has_valid_pose() or not bool(calibration.get("valid", false)) \
			or bool(calibration.get("mode", "") == "plane_stationary"):
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
