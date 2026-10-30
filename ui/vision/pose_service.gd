extends Node
## Local webcam/YOLO bridge. The student chooses camera play before it starts.
## Calibrated LEFT/CENTER/RIGHT values survive temporary sensor interruptions.

signal status_updated(data: Dictionary)
signal preview_updated(texture: Texture2D)

const DEFAULT_MODEL := "yolo26n-pose.pt"
const LOST_AFTER_MS := 1750
const WORKER_STALL_MS := 5500
# A driver can block inside VideoCapture.open(), even after the model is warm.
# Bound the camera-only startup; a child taking time to enter view is allowed.
const WORKER_BOOT_TIMEOUT_MS := 30000
const PREWARM_MODEL_TIMEOUT_MS := 60000
const RESTART_DELAY_MS := 1400
const RESTART_EXIT_TIMEOUT_MS := 4500
const MAX_AUTOMATIC_RESTARTS := 2
const POSITION_SMOOTHING_MS := 110.0
const MAX_STATUS_PACKET := 8192
# Gesture control must expire faster than the general-purpose body calibration.
# Without this independent freshness limit, a frozen/occluded camera could keep
# an arm gesture active for nearly two seconds after the final real pose.
const GESTURE_STALE_MS := 650
# Raw YOLO person-count presence is independent of pose confidence/lock state.
# A slow but genuinely fresh inference may arrive every 0.5-1 seconds; allow
# only a tightly bounded source-to-current age, never an unlimited UI grace.
const OCCUPANCY_STALE_MS := 1200
const PREVIEW_STALE_MS := 1400
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
# Timestamp of the last ACCEPTED real camera inference count, separate from
# worker warmup/heartbeat/preview statuses and from the last usable torso.
var _last_occupancy_packet_ms := 0
# A foreground-only occupancy report is distinct from the raw YOLO count.
# Raw people remains available for classroom diagnostics.
var _last_foreground_packet_ms := 0
var _bound_player_epoch := -1
var _bound_player_session := ""
var _launch_ms := 0
var _ever_tracked := false
var _worker_was_tracking := false
var _worker_was_streaming := false
var _automatic_restarts := 0
var _restart_pending := false
var _restart_at_ms := 0
var _restart_deadline_ms := 0
var _smoothed_x := -1.0
var _latest_worker_packet_time := -1.0
var first_camera_preview_ms := -1
var first_valid_pose_ms := -1
var _last_preview_ms := 0
# Source times are from Python's single monotonic clock. Compare ONLY source
# frames against one another; never against Godot's different clock origin.
var _last_preview_source_time := -1.0
var _preview_invalidated_source_time := -1.0
var _preview_source_age_ms := 0.0
var _preview_contains_solo_skeleton := false
var _model_prestarting := false
var _model_control_port := 0
var _camera_start_requested := false
var _camera_start_sent_ms := 0
var _camera_start_first_sent_ms := 0
var _prewarm_started_ms := 0
# Once the child completes calibration, the three physical camera positions
# belong to the current GAME ROUND, not to a temporary YOLO/ByteTrack ID.
# The worker may re-enroll a fresh stable solo person after any absence.


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
		_camera_start_first_sent_ms = 0
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
	_worker_was_streaming = false
	# A restarted worker cannot replay an old source-frame hold. Retain
	# cumulative IDs/actual calibrated range but discard stale UDP history.
	_recent_pose_samples.clear()
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
	_camera_start_first_sent_ms = 0
	player_x = -1.0
	_smoothed_x = -1.0
	_clear_live_preview()
	var now := Time.get_ticks_msec()
	last_pose_ms = 0
	_last_occupancy_packet_ms = 0
	_last_foreground_packet_ms = 0
	_latest_worker_packet_time = -1.0
	_last_preview_source_time = -1.0
	_preview_invalidated_source_time = -1.0
	first_camera_preview_ms = -1
	first_valid_pose_ms = -1
	_last_packet_ms = now
	_launch_ms = now
	_prewarm_started_ms = now if prewarm_only else 0
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
	# Calibration adjusts the editor-authored SkeletonPlacement AFTER model
	# prewarming starts. Include its latest visual-only transform here so the
	# warmed process does not keep the stale CLI transform from Student Setup.
	var request := {
		"command": "start_camera", "token": session_token,
		"bones_offset": [skeleton_visual_offset.x, skeleton_visual_offset.y],
		"bones_scale": [skeleton_visual_scale.x, skeleton_visual_scale.y],
	}
	if peer.put_packet(JSON.stringify(request).to_utf8_buffer()) == OK:
		if _camera_start_first_sent_ms <= 0:
			_camera_start_first_sent_ms = now
		_camera_start_sent_ms = now


func _close_transport() -> void:
	if peer != null:
		peer.close()
		peer = null
	session_token = ""


func _clear_live_preview() -> void:
	## Also notify connected calibration/preview screens. Clearing only this
	## reference previously left an obsolete skeleton inside their TextureRect
	## forever if the camera stopped sending frames.
	_last_preview_ms = 0
	_preview_source_age_ms = 0.0
	_preview_contains_solo_skeleton = false
	if preview_texture != null:
		preview_texture = null
		preview_updated.emit(null)


func _decode_preview_packet(bytes: PackedByteArray) -> Dictionary:
	## Legacy local/test JPEGs have no frame metadata. The current Python
	## worker uses 0x02 and a short source timestamp / inference / people / age header.
	if bytes.is_empty():
		return {}
	if bytes[0] == 1 and bytes.size() <= 60000:
			return {"jpg": bytes.slice(1), "source": -1.0,
				"inferred": false, "people": -1, "foreground_people": -1,
				"source_age_ms": 0.0}
	if bytes[0] != 2 or bytes.size() > 60064:
		return {}
	var end := bytes.find(59, 1) # ASCII semicolon before JPEG binary bytes
	if end < 2 or end > 64:
		return {}
	var fields := bytes.slice(1, end).get_string_from_ascii().split(",")
	if fields.size() != 5 or not fields[0].is_valid_float() \
			or not fields[1].is_valid_int() or not fields[2].is_valid_int() \
			or not fields[3].is_valid_int() or not fields[4].is_valid_int():
		return {}
	var source := fields[0].to_float()
	var inferred := fields[1].to_int()
	var people := fields[2].to_int()
	var source_age_ms := fields[3].to_int()
	var foreground_people := fields[4].to_int()
	if not is_finite(source) or source < 0.0 \
			or inferred < 0 or inferred > 1 or people < -1 or people > 12 \
			or foreground_people < -1 or foreground_people > people \
			or source_age_ms < 0 or source_age_ms > 650 \
			or (inferred == 1 and people < 0):
		return {}
	return {"jpg": bytes.slice(end + 1), "source": source,
			"inferred": inferred == 1, "people": people,
			"foreground_people": foreground_people,
		"source_age_ms": float(source_age_ms)}


func _expire_preview(now: int) -> void:
	## A stalled camera provides no replacement JPEG. The last bones are never
	## evidence of the student's *current* position after a long video gap.
	if preview_texture != null and _last_preview_ms > 0 \
			and float(now - _last_preview_ms) + _preview_source_age_ms > float(PREVIEW_STALE_MS):
		_clear_live_preview()


func refresh_calibration_preview() -> bool:
	## Scene rebind for Results -> Retry and calibration's delayed introduction.
	## A new TextureRect can subscribe AFTER the latest JPEG was delivered.
	## Re-emit ONLY the current live frame; never redisplay a stale skeleton
	## from a finished round, disconnected worker or previous camera session.
	var now := Time.get_ticks_msec()
	var age := float(now - _last_preview_ms) + _preview_source_age_ms
	if active and not _restart_pending and peer != null \
			and worker_pid > 0 and OS.is_process_running(worker_pid) \
			and preview_texture != null and _last_preview_ms > 0 \
			and age >= 0.0 and age <= float(PREVIEW_STALE_MS):
		preview_updated.emit(preview_texture)
		return true
	var had_preview := preview_texture != null
	_clear_live_preview()
	# A newly connected calibration scene may have a designer/old TextureRect
	# reference even when the service cache is already empty.
	if not had_preview:
		preview_updated.emit(null)
	return false


func begin_new_round_tracking() -> void:
	## Explicit NEW round only (Retry/Play Again). Do not call on a temporary
	## camera absence in an unfinished round. Unlike stop_camera(), this keeps
	## the still-live worker, socket, session token and preview stream running
	## while requiring brand-new CENTER/RIGHT/LEFT (or plane-neutral) holds.
	## Never create a second webcam process while one is already healthy.
	calibration.clear()
	plane_calibration.clear()
	_recent_pose_samples.clear()
	_bound_player_epoch = -1
	_bound_player_session = ""
	# IMPORTANT: Preserve these monotonically increasing source IDs while a
	# healthy worker stays alive. The newly mounted authored calibration scene
	# snapshots last_fresh_sample_id BEFORE calling this reset. Rewinding IDs
	# to zero would prevent its first new 8 real frames from being recognized
	# until their IDs exceed the previous round's old counter.
	player_x = -1.0
	_smoothed_x = -1.0
	last_pose_ms = 0
	_last_occupancy_packet_ms = 0
	_last_foreground_packet_ms = 0
	first_valid_pose_ms = -1
	var snapshot := current_status.duplicate(true)
	snapshot["pose"] = false
	snapshot["hand_up"] = false
	snapshot["raised"] = false
	snapshot["hand_observation_valid"] = false
	snapshot["both_hands_up"] = false
	snapshot["both_hands_down"] = false
	snapshot["airplane_pose"] = false
	snapshot["wing_roll"] = 0.0
	snapshot["plane_steering_valid"] = false
	snapshot["plane_neutral_valid"] = false
	snapshot["detail"] = "New round • stand alone and hold still for calibration."
	_set_status(snapshot)
	# A picture from the previous session may still be cached. Leave a
	# genuinely fresh live webcam picture to be rebound by the new scene,
	# but immediately withdraw stale bones even when no JPEG arrives.
	_expire_preview(Time.get_ticks_msec())


func stop_camera() -> void:
	_restart_pending = false
	_model_prestarting = false
	_model_control_port = 0
	_camera_start_requested = false
	_camera_start_sent_ms = 0
	_camera_start_first_sent_ms = 0
	_prewarm_started_ms = 0
	if worker_pid > 0 and OS.is_process_running(worker_pid):
		OS.kill(worker_pid)
	worker_pid = -1
	_close_transport()
	active = false
	player_x = -1.0
	_smoothed_x = -1.0
	calibration.clear()
	plane_calibration.clear()
	_clear_live_preview()
	packet_sequence = 0
	latest_pose_sample_id = 0
	_recent_pose_samples.clear()
	_bound_player_epoch = -1
	_bound_player_session = ""
	last_pose_ms = 0
	_last_occupancy_packet_ms = 0
	_last_foreground_packet_ms = 0
	_latest_worker_packet_time = -1.0
	_last_preview_source_time = -1.0
	_preview_invalidated_source_time = -1.0
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
	var newest_preview: Dictionary = {}
	var newest_preview_source := _last_preview_source_time
	var latest_pose := {}
	var newest_worker_time := _latest_worker_packet_time
	var previous_source_sample_id := latest_pose_sample_id
	var camera_start_acknowledged := false
	for _i in range(mini(peer.get_available_packet_count(), MAX_UDP_PACKETS_PER_FRAME)):
		var bytes := peer.get_packet()
		if bytes.is_empty():
			continue
		if bytes[0] == 1 or bytes[0] == 2:
			var candidate := _decode_preview_packet(bytes)
			if candidate.is_empty():
				continue
			var source := float(candidate["source"])
			if source >= 0.0:
				if source <= newest_preview_source:
					continue
				newest_preview_source = source
			elif newest_preview_source >= 0.0:
				# A late startup JPEG without source metadata must not erase a
				# newer, source-ordered live YOLO preview during warmup handoff.
				continue
			newest_preview = candidate
			continue
		if bytes.size() > MAX_STATUS_PACKET:
			continue
		var data: Variant = JSON.parse_string(bytes.get_string_from_utf8())
		if data is Dictionary and String(data.get("token", "")) == session_token \
				and String(data.get("kind", "")) == "pose":
			var raw_when: Variant = data.get("when", null)
			if not (raw_when is float or raw_when is int):
				continue
			var packet_when := float(raw_when)
			# Strictly newer monotonic source frames only. A duplicate UDP packet
			# must never refresh a stale pose or earn extra calibration samples.
			if is_finite(packet_when) and packet_when >= 0.0 \
					and packet_when > newest_worker_time:
				# The worker can ACK an authorized start and immediately send
				# newer camera-opening statuses in one frame. Preserve that ACK
				# even when only the latest packet is rendered below.
				if _model_prestarting and _camera_start_requested \
						and bool(data.get("camera", false)) \
						and String(data.get("state", "")) in ["loading", "tracking", "recovering"]:
					camera_start_acknowledged = true
				# Only the actual worker's camera=true protocol is granted
				# authority to enroll/move a student. Unlocked/aged/malformed
				# tracking reports immediately revoke pose permission, even if
				# they deceptively contain pose=true.
				if bool(data.get("camera", false)) and String(data.get("state", "")) == "tracking" \
						and bool(data.get("pose", false)) and not _trusted_live_tracking_packet(data):
					data["pose"] = false
					data["lock_state"] = "ambiguous"
				_record_fresh_calibration_pose(data, packet_when)
				latest_pose = data
				newest_worker_time = packet_when
	if camera_start_acknowledged and _model_prestarting and _camera_start_requested:
		# Camera-start permission was actually received. The watchdog's
		# camera-open clock starts at this handshake, while a cold YOLO model
		# is free to finish warming behind the live preview.
		_launch_ms = now
		_model_prestarting = false
		_camera_start_requested = false
	if not latest_pose.is_empty():
		_latest_worker_packet_time = newest_worker_time
		if _model_prestarting:
			var supplied_port := int(latest_pose.get("control_port", 0))
			if supplied_port >= 1024 and supplied_port <= 65535:
				_model_control_port = supplied_port
			if _camera_start_requested and String(latest_pose.get("state", "")) in ["tracking", "recovering", "loading"] \
					and bool(latest_pose.get("camera", false)):
				# Explicit camera start was acknowledged. Native webcam timeout
				# begins NOW, not when the teacher clicked while YOLO was warming.
				_launch_ms = now
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
		var source := float(newest_preview["source"])
		# The current worker tags its JPEGs. Reject an old SOLO skeleton
		# arriving after a newer detected crowd, empty frame or camera stall.
		# Raw camera JPEGs and actual newer YOLO detections can still restore
		# the view; no old pose or student count is inferred from pixels.
		var safe_preview := source < 0.0 or (source > _last_preview_source_time
			and (not bool(newest_preview["inferred"])
			or int(newest_preview["foreground_people"]) != 1
			or (source > _preview_invalidated_source_time
			and not bool(current_status.get("foreground_ambiguous", true)))))
		if safe_preview:
			var picture := Image.new()
			if picture.load_jpg_from_buffer(newest_preview["jpg"]) == OK:
				if first_camera_preview_ms < 0:
					first_camera_preview_ms = now - _launch_ms
				if preview_texture == null or Vector2i(preview_texture.get_size()) != picture.get_size():
					preview_texture = ImageTexture.create_from_image(picture)
				else:
					preview_texture.update(picture)
				_last_preview_ms = now
				_preview_source_age_ms = float(newest_preview["source_age_ms"])
				_preview_contains_solo_skeleton = bool(newest_preview["inferred"]) \
					and int(newest_preview["foreground_people"]) == 1
				if source >= 0.0:
					_last_preview_source_time = source
				preview_updated.emit(preview_texture)
	_expire_preview(now)
	# Never let the last measured location masquerade as a live student.
	if player_x >= 0.0 and _live_capture_total_age_ms(now) > float(LOST_AFTER_MS):
		player_x = -1.0
		_smoothed_x = -1.0
		_set_status({"state": "stale", "pose": false, "lock_state": "occluded",
			"detail": "Waiting for a fresh camera pose. Stay within the camera view."})
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
	match _camera_watchdog_status(now):
		"stream_stalled":
			_schedule_restart(now)
		"prewarm_stalled":
			_fail_camera("Offline pose model took too long to prepare. Retry camera setup.")
		"camera_stalled":
			# Native VideoCapture can hang inside a Windows driver. Terminate
			# only our own worker PID and retry with a single process at a time;
			# _continue_restart waits for release, with a hard exit deadline.
			_schedule_restart(now, true)


func _camera_watchdog_status(now: int) -> String:
	## Pure safety gate so headless tests can verify a stuck model or camera
	## without ever creating a real webcam/helper process.
	if (now - _last_packet_ms > WORKER_STALL_MS and _worker_was_tracking) \
			or (_worker_was_streaming and now - _last_packet_ms > 20000):
		return "stream_stalled"
	if _model_prestarting:
		if not bool(current_status.get("model_ready", false)):
			# A teacher may enter calibration while weights are still loading:
			# never mistake the ongoing model/CUDA warmup for a stuck webcam.
			var warm_started := _prewarm_started_ms if _prewarm_started_ms > 0 else _launch_ms
			return "prewarm_stalled" if now - warm_started > PREWARM_MODEL_TIMEOUT_MS else ""
		if not _camera_start_requested:
			return "" # Ready model can wait indefinitely for explicit permission.
		# Ready model, authenticated camera-start command in flight.
		var camera_start := _camera_start_first_sent_ms \
			if _camera_start_first_sent_ms > 0 else _launch_ms
		return "camera_stalled" if now - camera_start > WORKER_BOOT_TIMEOUT_MS else ""
	# A prepared process can wait indefinitely for camera permission, and a
	# successfully streaming camera can wait for the student to enter view.
	if now - _launch_ms > WORKER_BOOT_TIMEOUT_MS and not _worker_was_streaming \
			and not (_model_prestarting and not _camera_start_requested):
		return "camera_stalled"
	return ""


func _record_fresh_calibration_pose(data: Dictionary, packet_when: float) -> void:
	# Source timestamps, physical position and foreground identity must all
	# correspond to the same verified student. Distant spectators are diagnostic.
	if not active or String(data.get("state", "")) != "tracking" or not bool(data.get("pose", false)):
		return
	if data.has("camera") and (not bool(data.get("camera", false)) \
			or not _trusted_live_tracking_packet(data)):
		return
	# Old headless FIFO tests directly record synthetic source samples without
	# tracker metadata. Production packets from the real webcam ALWAYS contain
	# camera=true and are first enforced by _trusted_live_tracking_packet().
	if data.has("camera") and not _trusted_live_tracking_packet(data):
		return
	if data.has("lock_state") and String(data.get("lock_state", "")) != "locked":
		return
	var measured: Variant = data.get("x", -1.0)
	if not (measured is float or measured is int):
		return
	var x := float(measured)
	if not is_finite(x) or x < 0.0 or x > 1.0:
		return
	if not _has_fresh_source_frame(data):
		return
	if bool(data.get("camera", false)) and _bound_player_epoch < 0:
		_bind_player_epoch(data)
	# Defend the bounded sample history against duplicated/reordered source
	# timestamps even if a test/caller bypasses the UDP receiver.
	if not _recent_pose_samples.is_empty() \
			and packet_when <= float(_recent_pose_samples.back().get("when", -1.0)):
		return
	var pose_sample: Dictionary = {"x": x, "when": packet_when, "people": 1,
		"raw_people": _raw_camera_population(data)}
	# Genuine source-frame gesture observations belong with the same monotonic
	# physical packet as torso X. Calibration must not reuse a later/earlier
	# hand raise, or accept a fake gesture from rendering the last cached frame.
	pose_sample["hand_observation_valid"] = bool(data.get("hand_observation_valid", false))
	pose_sample["hand_up"] = bool(data.get("hand_up", false))
	# Keep strict physical bilateral wrist evidence on the SAME authenticated,
	# monotonic frame as torso X. Calibration must not infer both arms from the
	# aggregate (either-hand) gameplay trigger or a cached preview skeleton.
	pose_sample["both_hands_up"] = bool(data.get("both_hands_up", false))
	pose_sample["both_hands_down"] = bool(data.get("both_hands_down", false))
	# The Python worker additionally provides SAME-frame raw bilateral evidence
	# specifically for calibration. The gameplay `both_hands_*` flags remain
	# release-latched to prevent ghost shots after an occluded wrist. Forward
	# the independent readings without changing shooting behavior; only legacy
	# mock packets that omit all three keys use the old calibration fallback.
	if data.has("calibration_hand_observation_valid") \
			or data.has("calibration_both_hands_up") or data.has("calibration_both_hands_down"):
		pose_sample["calibration_hand_observation_valid"] = bool(data.get(
			"calibration_hand_observation_valid", false))
		pose_sample["calibration_both_hands_up"] = bool(data.get(
			"calibration_both_hands_up", false))
		pose_sample["calibration_both_hands_down"] = bool(data.get(
			"calibration_both_hands_down", false))
	pose_sample["plane_t_pose_valid"] = bool(data.get("plane_t_pose_valid", false))
	if bool(data.get("plane_bank_valid", false)):
		var raw_bank: Variant = data.get("plane_bank", null)
		if (raw_bank is int or raw_bank is float) and is_finite(float(raw_bank)) \
				and absf(float(raw_bank)) <= 1.0:
			pose_sample["plane_bank"] = float(raw_bank)
	# Keep source measurements before UI smoothing. A tracker identifier is
	# irrelevant to calibration or steering and is never stored on the sample.
	var raw_steering: Variant = data.get("plane_steering", null)
	if String(data.get("lock_state", "")) == "locked" \
			and bool(data.get("plane_steering_valid", false)) \
			and bool(data.get("plane_neutral_valid", false)) \
			and (raw_steering is float or raw_steering is int) \
			and is_finite(float(raw_steering)) and absf(float(raw_steering)) <= 1.0:
		pose_sample["plane_steering"] = float(raw_steering)
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
	# A real raw YOLO occupancy observation is accepted even if no keypoints
	# qualify for pose/gesture control (e.g. briefly hidden torso or the worker
	# rebuilding its solo pose lock). The caller already validated the session
	# token and monotonic source timestamp. Other status packets revoke this
	# authority immediately, rather than borrowing a previous person count.
	_last_occupancy_packet_ms = now if _is_raw_camera_occupancy_packet(data) else 0
	_last_foreground_packet_ms = now if _is_foreground_camera_occupancy_packet(data) else 0
	# A newer real observation of zero/two+ people, or an explicit camera
	# interruption, invalidates all older skeleton artwork immediately. The
	# pending fresh JPEG can repopulate the TextureRect on its own merits.
	var count := _foreground_camera_population(data)
	var unsafe_occupancy := String(data.get("state", "")) == "tracking" \
		and bool(data.get("camera", false)) and (
			count != 1 or bool(data.get("foreground_ambiguous", true)))
	var interrupted := String(data.get("state", "")) in ["recovering", "stale", "error", "off"]
	if unsafe_occupancy or interrupted:
		var invalid_source: Variant = data.get("camera_source_timestamp", null)
		if not (invalid_source is float or invalid_source is int) or not is_finite(float(invalid_source)):
			invalid_source = data.get("when", -1.0)
		if (invalid_source is float or invalid_source is int) and is_finite(float(invalid_source)):
			_preview_invalidated_source_time = maxf(_preview_invalidated_source_time, float(invalid_source))
		if interrupted or _preview_contains_solo_skeleton:
			_clear_live_preview()
	if bool(data.get("camera", false)) and String(data.get("camera_phase", "")) in [
			"streaming", "preview", "tracking"]:
		_worker_was_streaming = true
	var valid := String(data.get("state", "")) == "tracking" \
		and bool(data.get("camera", false)) and bool(data.get("pose", false)) \
		and _trusted_live_tracking_packet(data)
	var measurement: Variant = data.get("x", -1.0)
	valid = valid and (measurement is float or measurement is int)
	if valid:
		var measured_x := float(measurement)
		valid = is_finite(measured_x) and measured_x >= 0.0 and measured_x <= 1.0
		if valid:
			var elapsed := maxi(now - last_pose_ms, 16)
			if _smoothed_x < 0.0 or elapsed > LOST_AFTER_MS:
				_smoothed_x = measured_x
			else:
				var alpha := 1.0 - exp(-float(elapsed) / POSITION_SMOOTHING_MS)
				_smoothed_x = lerpf(_smoothed_x, measured_x, clampf(alpha, 0.0, 1.0))
			player_x = clampf(_smoothed_x, 0.0, 1.0)
			_bind_player_epoch(data)
			last_pose_ms = now
			if first_valid_pose_ms < 0:
				first_valid_pose_ms = now - _launch_ms
			packet_sequence += 1
			_ever_tracked = true
			_worker_was_tracking = true
	if not valid:
		player_x = -1.0
		# Starting from the last person's smoothed position would make a NEW
		# stable solo occupant appear to move from a stale/ghost body location.
		_smoothed_x = -1.0
	current_status = data.duplicate()
	if not valid:
		current_status["pose"] = false
		current_status["hand_up"] = false
		current_status["hand_observation_valid"] = false
		current_status["both_hands_up"] = false
		current_status["both_hands_down"] = false
		current_status["airplane_pose"] = false
		current_status["wing_roll"] = 0.0
		current_status["plane_steering_valid"] = false
		current_status["plane_neutral_valid"] = false
	# Never expose retired ID/epoch-based rerouting hints to a gameplay screen.
	current_status.erase("recalibration_required")
	current_status.erase("new_lock_id")
	current_status.erase("recalibration_reason")
	status_updated.emit(current_status.duplicate())


func requires_player_recalibration() -> bool:
	## Legacy routing compatibility. The new rule never repeats completed
	## calibration on YOLO ID changes, empty frames, crowds or worker restarts.
	return false


func clear_calibration_for_reentry() -> void:
	## Compatibility for a pre-game calibration reset. Never erase already
	## completed round measurements just because the worker was re-enrolled.
	if bool(calibration.get("valid", false)):
		return
	calibration.clear()
	plane_calibration.clear()
	_recent_pose_samples.clear()
	player_x = -1.0
	_smoothed_x = -1.0
	last_pose_ms = 0
	current_status = current_status.duplicate()
	current_status["pose"] = false
	current_status["detail"] = "Stand in CENTER for a fresh camera calibration."
	status_updated.emit(current_status.duplicate())


func _has_fresh_source_frame(data: Dictionary) -> bool:
	## Production packets carry capture-to-inference age. Reject malformed,
	## negative and stale ages rather than interpreting them as live motion.
	## Missing ages are accepted only for legacy synthetic callers.
	var raw_age: Variant = data.get("camera_frame_age_ms", 0)
	if not (raw_age is int or raw_age is float):
		return false
	var age := float(raw_age)
	return is_finite(age) and age >= 0.0 and age <= GESTURE_STALE_MS


func _live_capture_total_age_ms(now: int = -1) -> float:
	## camera_frame_age_ms is the real capture-to-inference latency reported
	## by Python, NOT Godot's packet arrival age. A nearly expired YOLO result
	## must not earn an additional full LOST_AFTER_MS or gesture grace on
	## receipt: the *combined* source age is the only safe freshness clock.
	var elapsed := maxi(0, (Time.get_ticks_msec() if now < 0 else now) - last_pose_ms)
	var source_age: Variant = current_status.get("camera_frame_age_ms", null)
	if not (source_age is int or source_age is float):
		return INF
	var age := float(source_age)
	if not is_finite(age) or age < 0.0:
		return INF
	return age + float(elapsed)


func _trusted_live_tracking_packet(data: Dictionary) -> bool:
	## Only the one foreground child selected by StudentLock may control a
	## round. Raw YOLO counts include distant spectators and are diagnostic.
	return String(data.get("lock_state", "")) == "locked" \
		and bool(data.get("camera", false)) and bool(data.get("pose", false)) \
		and _foreground_camera_population(data) == 1 \
		and not bool(data.get("foreground_ambiguous", true)) \
		and data.get("occupancy_verified", null) is bool \
		and bool(data.get("occupancy_verified", false)) \
		and _matches_player_epoch(data) \
		and data.has("camera_frame_age_ms") and _has_fresh_source_frame(data)


func _matches_player_epoch(data: Dictionary) -> bool:
	# Epoch attests to one continuous Python lock session. It is not a facial
	# identity; never infer identity from a raw count or an arbitrary ByteTrack ID.
	var source_epoch: Variant = data.get("player_lock_epoch", null)
	if not (source_epoch is int or source_epoch is float) \
			or not is_finite(float(source_epoch)) or float(source_epoch) < 1.0 \
			or floorf(float(source_epoch)) != float(source_epoch):
		return false
	if _bound_player_epoch < 0:
		return true
	return _bound_player_session == session_token \
		and _bound_player_epoch == int(source_epoch)


func _bind_player_epoch(data: Dictionary) -> void:
	if _bound_player_epoch >= 0:
		return
	if not _matches_player_epoch(data):
		return
	_bound_player_epoch = int(data["player_lock_epoch"])
	_bound_player_session = session_token


func _has_exactly_one_person(data: Dictionary) -> bool:
	return _foreground_camera_population(data) == 1 \
		and not bool(data.get("foreground_ambiguous", true))


func _raw_camera_population(data: Dictionary) -> int:
	# Counts originate from YOLO's current raw person boxes, NOT ByteTrack IDs
	# or the number of keypoint skeletons the detector could draw.
	var value: Variant = data.get("people", null)
	if not (value is int or value is float):
		return -1
	var number := float(value)
	if not is_finite(number) or number < 0.0 or number > 12.0 \
			or floorf(number) != number:
		return -1
	return int(number)


func _foreground_camera_population(data: Dictionary) -> int:
	# No fallback to raw people: a seated bystander can make people=2 while
	# only the standing child is eligible. Missing metadata is unsafe.
	var value: Variant = data.get("foreground_people", null)
	if not (value is int or value is float):
		return -1
	var number := float(value)
	var raw := _raw_camera_population(data)
	if not is_finite(number) or number < 0.0 or floorf(number) != number \
			or raw < 0 or number > float(raw):
		return -1
	return int(number)


func _is_foreground_camera_occupancy_packet(data: Dictionary) -> bool:
	return _is_raw_camera_occupancy_packet(data) \
		and _foreground_camera_population(data) >= 0 \
		and data.get("foreground_ambiguous", null) is bool \
		and data.get("occupancy_verified", null) is bool


func _is_raw_camera_occupancy_packet(data: Dictionary) -> bool:
	# This protocol is sent after a genuine YOLO predict() inference. Worker
	# warmup, preview, missing frames and inference error statuses cannot claim
	# an occupancy measurement even if they contain a stale people field.
	return String(data.get("state", "")) == "tracking" \
		and bool(data.get("camera", false)) \
		and String(data.get("camera_phase", "")) == "tracking" \
		and _raw_camera_population(data) >= 0 \
		and data.has("camera_frame_age_ms") and _has_fresh_source_frame(data)


func fresh_raw_camera_population() -> int:
	## Diagnostic only: includes every YOLO person box, distant or near.
	if not active or _restart_pending or peer == null or session_token.is_empty() \
			or worker_pid <= 0 or not OS.is_process_running(worker_pid) \
			or _last_occupancy_packet_ms <= 0 \
			or not _is_raw_camera_occupancy_packet(current_status):
		return -1
	var elapsed := Time.get_ticks_msec() - _last_occupancy_packet_ms
	if elapsed < 0 or not is_finite(float(elapsed)):
		return -1
	var source_age := float(current_status["camera_frame_age_ms"])
	if source_age + float(elapsed) > float(OCCUPANCY_STALE_MS):
		return -1
	return _raw_camera_population(current_status)


func fresh_camera_population() -> int:
	## Eligible foreground count, not raw detections. -1 means uncertain,
	## ambiguous or stale. A one-person report by itself never grants gesture
	## or movement; has_valid_pose also needs a verified active player.
	if fresh_raw_camera_population() < 0 or _last_foreground_packet_ms <= 0 \
			or not _is_foreground_camera_occupancy_packet(current_status) \
			or bool(current_status.get("foreground_ambiguous", true)):
		return -1
	return _foreground_camera_population(current_status)


func foreground_is_ambiguous() -> bool:
	## Show an immediate multi-player warning when two similarly near bodies
	## overlap, even if the detector only counted one foreground box.
	return fresh_raw_camera_population() >= 0 \
		and _is_foreground_camera_occupancy_packet(current_status) \
		and (bool(current_status.get("foreground_ambiguous", true)) \
		or _foreground_camera_population(current_status) > 1)


func has_fresh_solo_presence() -> bool:
	## A detector count alone is not movement permission or an identity match.
	return fresh_camera_population() == 1


func has_verified_foreground_player() -> bool:
	## Require an authenticated, stable selected student before advancing the
	## round. A new spectator cannot inherit a finished calibration by count.
	return fresh_camera_population() == 1 \
		and bool(current_status.get("occupancy_verified", false)) \
		and String(current_status.get("lock_state", "")) == "locked" \
		and _matches_player_epoch(current_status)


func _schedule_restart(now: int, allow_before_enrollment: bool = false) -> void:
	if _restart_pending:
		return
	player_x = -1.0
	_last_occupancy_packet_ms = 0
	_last_foreground_packet_ms = 0
	_clear_live_preview()
	if (not _ever_tracked and not allow_before_enrollment) \
			or _automatic_restarts >= MAX_AUTOMATIC_RESTARTS:
		_fail_camera("Camera connection interrupted. Ask the teacher to restart camera.")
		return
	_automatic_restarts += 1
	# Worker restart invalidates current pose/preview, NOT finished measured
	# floor positions. Any fresh, stable SOLO YOLO person can continue this round.
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
	_camera_start_first_sent_ms = 0
	_prewarm_started_ms = 0
	if worker_pid > 0 and OS.is_process_running(worker_pid):
		OS.kill(worker_pid)
	worker_pid = -1
	_close_transport()
	active = false
	player_x = -1.0
	_last_occupancy_packet_ms = 0
	_last_foreground_packet_ms = 0
	_clear_live_preview()
	set_process(false)
	_set_status({"state": "error", "pose": false, "detail": message})


func has_valid_pose() -> bool:
	return active and player_x >= 0.0 and bool(current_status.get("pose", false)) \
		and String(current_status.get("state", "")) == "tracking" \
		and _live_capture_total_age_ms() <= float(LOST_AFTER_MS) \
		and _trusted_live_tracking_packet(current_status)


func has_recent_missing_student_observation() -> bool:
	## A missing-student notice requires an actual fresh, zero-person YOLO
	## observation. A missing torso/hand while people==1 is NOT an absence;
	## an expired source or camera/transport restart is UNKNOWN, not empty.
	return fresh_camera_population() == 0


func has_fresh_gesture_pose() -> bool:
	## Calibration is position-only: students can drop/raise their arms without
	## redoing Center/Right/Left. A gesture requires a NEW valid student packet.
	return has_valid_pose() and bool(calibration.get("valid", false)) \
		and _live_capture_total_age_ms() <= float(GESTURE_STALE_MS)


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
	# locked_id is deprecated and ignored: initial calibration is body-based.
	if not is_finite(camera_center_x) \
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
		"steering_mode": "continuous_arm_bank",
		"sensitivity": sensitivity, "deadzone": deadzone,
		"neutral_noise": neutral_noise, "neutral_only": true,
			"camera_center_x": camera_center_x
	}
	# Existing gameplay routing checks calibration.valid, but steering here
	# never impersonates the other games' measured floor/position limits.
	calibration = plane_calibration.duplicate()
	return true


func has_stationary_plane_pose() -> bool:
	## Arm banking demands TWO fresh measured wrists and elbows (the Python
	## `plane_bank_valid` source key). Body/torso alone is insufficient: none
	## of the old calibrated torso-X samples can invent a banking gesture.
	if not has_valid_pose() or not bool(plane_calibration.get("valid", false)) \
			or _live_capture_total_age_ms() > float(GESTURE_STALE_MS) \
			or String(current_status.get("lock_state", "")) != "locked" \
			or not bool(current_status.get("plane_bank_valid", false)):
		return false
	var raw: Variant = current_status.get("plane_bank", null)
	return (raw is float or raw is int) and is_finite(float(raw)) \
		and absf(float(raw)) <= 1.0


func normalized_plane_steering() -> float:
	## Source is a normalized signed arm-tilt (-1 left, 0 level T, +1
	## right), NOT an absolute torso destination. HumanPlane smoothly
	## integrates this as movement VELOCITY (Catch-like sliding), so even a
	## maximal wrist tilt cannot teleport the plane to a remote gate.
	if not has_stationary_plane_pose():
		return 0.0
	return clampf(float(current_status.get("plane_bank", 0.0)), -1.0, 1.0)


func set_calibration(left: float, center: float, right: float,
		locked_id: int = -1) -> bool:
	if not (left >= 0.0 and right <= 1.0 and right - left >= 0.18):
		return false
	if center <= left + 0.06 or center >= right - 0.06:
		return false
	calibration = {"left": left, "center": center, "right": right, "valid": true}
	# No track ID or epoch registration: these positions belong to this round.
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
	current_status = value.duplicate()
	status_updated.emit(current_status.duplicate())


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
