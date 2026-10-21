extends SceneTree

## Integration smoke check: real Python process and loopback status transport.
## This opens the camera only after this explicit test is invoked. No frames
## are saved or displayed; a camera-unavailable machine may report ERROR.
var states: Array[String] = []
var preview_frames := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := root.get_node("PoseService")
	service.status_updated.connect(_status)
	service.preview_updated.connect(_frame)
	if not service.start_camera():
		printerr("POSE LAUNCH: Could not start Python worker: ", service.current_status)
		quit(1)
		return
	var elapsed := 0.0
	var tracking_started := -1.0
	while elapsed < 15.0:
		await create_timer(0.25).timeout
		elapsed += 0.25
		var state := String(service.current_status.get("state", ""))
		if state == "tracking" and tracking_started < 0.0:
			tracking_started = elapsed
		if state == "error" or (state == "tracking" and preview_frames > 0 and tracking_started >= 0.0 and elapsed - tracking_started >= 4.0):
			break
	var current: Dictionary = service.current_status.duplicate(true)
	service.stop_camera()
	print("POSE LAUNCH: states=", states, ", preview_frames=", preview_frames,
		", pose_fps=", float(current.get("fps", 0.0)),
		", camera_fps=", float(current.get("camera_fps", 0.0)),
		", device=", String(current.get("device", "")),
		", final_status=", String(current.get("state", "")), ", detail=", String(current.get("detail", "")))
	# A reachable Python worker is useful even when Windows has no camera
	# access; error text must identify the external hardware dependency.
	var reached_worker := states.has("error") or states.has("tracking")
	if not reached_worker:
		printerr("FAIL: No response from local Python worker")
	elif String(current.get("state", "")) == "tracking" and preview_frames == 0:
		printerr("FAIL: Camera reported open but sent no usable preview image")
		reached_worker = false
	quit(0 if reached_worker else 1)


func _status(data: Dictionary) -> void:
	var state := String(data.get("state", ""))
	if states.is_empty() or states.back() != state:
		states.append(state)


func _frame(_texture: Texture2D) -> void:
	preview_frames += 1
