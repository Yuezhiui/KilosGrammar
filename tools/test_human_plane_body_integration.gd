extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_body_integration.gd
# End-to-end synthetic camera test: genuine three-position calibration and the
# PoseService -> Gameplay -> Human Plane bridge. Never starts a camera/worker.
const CALIBRATION_SCENE := "res://ui/vision/calibration.tscn"
const GAMEPLAY_SCENE := "res://ui/play/gameplay.tscn"
const TOKEN := "plane-body-qa-only"
const CAMERA_X := {"CENTER": 0.5, "RIGHT": 0.8, "LEFT": 0.2}
const FIXED_FRAME := 0.05

var failures: Array[String] = []
var checks := 0
var service: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	service = root.get_node_or_null("PoseService")
	_check(service != null, "PoseService autoload is registered")
	if service == null:
		_finish()
		return
	service.stop_camera()
	service.set_process(false)
	service.active = true
	service.session_token = TOKEN
	service.calibration.clear()
	var payload := await _test_three_zone_calibration()
	if not payload.is_empty():
		await _test_bridge(payload, "Seconds", Vector2i(1280, 720))
		await _test_bridge(payload, "Lives", Vector2i(1920, 1080))
	service.stop_camera()
	service.set_process(true)
	_finish()


func _test_three_zone_calibration() -> Dictionary:
	var packed := load(CALIBRATION_SCENE) as PackedScene
	_check(packed != null, "real editor-authored calibration scene loads")
	if packed == null:
		return {}
	var screen := packed.instantiate() as Control
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var routes: Array[Dictionary] = []
	screen.requested.connect(func(route: String, data: Dictionary) -> void:
		routes.append({"route": route, "payload": data.duplicate(true)}))
	_emit_packet(0.5, true, true)
	screen.set_context({
		"activity": "Human Plane", "game_mode": "Seconds", "difficulty": "Normal",
		"game_style": "Noun", "topic": "Noun", "camera_requested": true,
		"student_id": "QA-ONLY", "student_name": "SYNTHETIC STUDENT"
	})
	screen.set_process(false)
	var order: Array = screen.call("_capture_order")
	_check(order == ["CENTER", "RIGHT", "LEFT"],
		"Human Plane requires actual CENTER, RIGHT and LEFT calibration holds")
	_check(int(screen.get("live_step")) == 0, "calibration starts at CENTER")
	# Do not let the 2.5s introduction count toward actual pose holds.
	screen.call("_process", 2.51)
	_check(int(screen.get("live_step")) == 0 and float(screen.get("live_timer")) < 0.05,
		"intro countdown does not credit its 2.5 seconds toward calibration")
	screen.call("_continue_flow", false)
	_check(routes.is_empty(), "cannot enter gameplay before all three measurements")
	for step in range(order.size()):
		var zone: String = String(order[step])
		for sample in range(33):
			_emit_packet(float(CAMERA_X[zone]), false, false)
			screen.call("_process", 0.1)
		_check(int(screen.get("live_step")) == step + 1,
			"%s completes exactly one real stationary 3-second hold" % zone)
		var points: Dictionary = screen.get("measured_points")
		_check(points.has(zone.to_lower()),
			"%s measurement stored independently" % zone)
		if points.has(zone.to_lower()):
			_check(absf(float(points[zone.to_lower()]) - float(CAMERA_X[zone])) < 0.035,
				"%s measured from student packets, without fabricated bounds" % zone)
		if step < order.size() - 1:
			_check(not bool((service.calibration as Dictionary).get("valid", false)),
				"partial calibration cannot satisfy a game-ready state")
	var values: Dictionary = service.calibration.duplicate(true)
	_check(bool(values.get("valid", false)) and not bool(values.get("center_only", false)),
		"all three independently sampled zones establish full calibration")
	_check(float(values.get("left", 99.0)) < float(values.get("center", -1.0))
		and float(values.get("center", 99.0)) < float(values.get("right", -1.0)),
		"calibration preserves physically ordered LEFT < CENTER < RIGHT")
	_check(is_equal_approx(float(values.get("left", -1.0)), 0.2)
		and is_equal_approx(float(values.get("center", -1.0)), 0.5)
		and is_equal_approx(float(values.get("right", -1.0)), 0.8),
		"calibration retains original left/center/right measurements")
	_emit_packet(0.5, false, true)
	screen.call("_continue_flow", false)
	_check(routes.size() == 1 and String(routes[0].get("route", "")) == "gameplay",
		"three-zone success routes once into gameplay")
	var payload: Dictionary = routes[0]["payload"] if routes.size() == 1 else {}
	_check(bool(payload.get("camera_live", false)) and bool(payload.get("calibration_measured", false))
		and not bool(payload.get("calibration_center_only", true)),
		"handoff declares genuinely measured live three-zone input")
	_check(payload.get("start_countdown", false) == true
		and payload.has("calibration_left") and payload.has("calibration_center")
		and payload.has("calibration_right"),
		"handoff preserves measured bounds and shared countdown route")
	screen.queue_free()
	await process_frame
	await process_frame
	_check(service.active, "successful calibration retains live camera ownership for gameplay")
	return payload


func _test_bridge(base_payload: Dictionary, mode: String, resolution: Vector2i) -> void:
	root.size = resolution
	service.active = true
	service.session_token = TOKEN
	_emit_packet(0.5, false, false)
	var packed := load(GAMEPLAY_SCENE) as PackedScene
	_check(packed != null, "gameplay wrapper loads at %s" % mode)
	if packed == null:
		return
	var wrapper := packed.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var data := base_payload.duplicate(true)
	data["game_mode"] = mode
	data["start_countdown"] = false # Isolate real-time pose bridge from visual countdown.
	data["guided_tutorial"] = false
	data["activity"] = "Human Plane"
	wrapper.set_context(data)
	await process_frame
	await process_frame
	wrapper.set_process(false)
	var plane := wrapper.get("active_game") as Control
	_check(is_instance_valid(plane), "wrapper mounts actual Human Plane for %s" % mode)
	if not is_instance_valid(plane):
		wrapper.queue_free()
		await process_frame
		return
	plane.set_process(false)
	var id := "%s/%dx%d" % [mode, resolution.x, resolution.y]
	var left_marker := plane.get_node("FlightPaths/PlaneLeftLimit") as Control
	var right_marker := plane.get_node("FlightPaths/PlaneRightLimit") as Control
	var left_x: float = left_marker.get_rect().get_center().x + float(plane.get("_plane_authored_offset_x"))
	var right_x: float = right_marker.get_rect().get_center().x + float(plane.get("_plane_authored_offset_x"))
	_check(left_x < right_x and plane.has_method("set_body_x"), id + " editable flight limits and body X API")
	_check(int(plane.get("lives")) == 3, id + " initializes exactly three hearts")
	_check(float(plane.get("time_remaining")) > 59.0 if mode == "Seconds"
		else is_zero_approx(float(plane.get("time_remaining"))), id + " correct Seconds/Lives timer")
	_check(plane.get_node_or_null("HUDLayer/HUD/ScoreBottomContainer/ScoreNumber") is Label
		and plane.get_node_or_null("HUDLayer/HUD/TimeLabel") is Label
		and plane.get_node_or_null("HUDLayer/HUD/PauseButton") is Button,
		id + " HUD retains score, timer and pause authored nodes")
	var options: Array = (plane.get("round_data") as Dictionary).get("options", [])
	_check(options.size() == 3 and plane.get_node_or_null("UpcomingGates/GateLeft") != null,
		id + " continuous authored gate trios survive pose bridge")

	# Isolate body movement from gate scoring: the wrapper and plane are both
	# manually stepped, with no real camera, timers or automatic scene input.
	_drive_pose(wrapper, plane, 0.5, false, 0.8, 10)
	_check(not bool(plane.get("airplane_pose_active")), id + " arms down initially deny flight")
	var resting_x := float(plane.get("plane_x_norm"))
	_drive_pose(wrapper, plane, 0.8, false, -1.0, 28)
	_check(absf(float(plane.get("plane_x_norm")) - resting_x) < 0.001,
		id + " moving RIGHT with lowered arms freezes plane at actual position")
	_drive_pose(wrapper, plane, 0.5, true, -1.0, 30)
	var center_x: float = float(plane.get("plane_x_norm"))
	_check(bool(plane.get("airplane_pose_active")) and absf(center_x - 0.5) < 0.10,
		id + " arms raised and CENTER pose steer to neutral")
	_check(absf(service.normalized_body_x()) < 0.015, id + " measured CENTER maps to normalized zero")
	# Different roll signs on the same body coordinates must never steer.
	_drive_pose(wrapper, plane, 0.5, true, 1.0, 18)
	var after_positive_roll := float(plane.get("plane_x_norm"))
	_drive_pose(wrapper, plane, 0.5, true, -1.0, 18)
	_check(absf(float(plane.get("plane_x_norm")) - after_positive_roll) < 0.05,
		id + " changing wing roll alone cannot steer the plane (no gyro)")
	var before_right := float(plane.get("plane_x_norm"))
	_drive_pose(wrapper, plane, 0.8, true, -1.0, 36)
	var right_position := float(plane.get("plane_x_norm"))
	_check(bool(plane.get("airplane_pose_active")) and right_position > 0.75
		and right_position > before_right + 0.25, id + " raised arms + body RIGHT traverse authored path")
	_check(service.normalized_body_x() > 0.98, id + " measured RIGHT maps to +1")
	_check(_within_flight_limits(plane, left_x, right_x), id + " RIGHT flight stays within editor limits")
	# Inverting roll while standing RIGHT must not send the airplane left.
	_drive_pose(wrapper, plane, 0.8, true, 1.0, 12)
	_check(float(plane.get("plane_x_norm")) >= right_position - 0.02,
		id + " positive wing roll cannot reverse rightward body command")
	_drive_pose(wrapper, plane, 0.2, true, 1.0, 48)
	var left_position := float(plane.get("plane_x_norm"))
	_check(left_position < 0.25 and left_position < right_position - 0.45,
		id + " raised arms + body LEFT traverse authored path regardless of roll")
	_check(service.normalized_body_x() < -0.98, id + " measured LEFT maps to -1")
	_check(_within_flight_limits(plane, left_x, right_x), id + " LEFT flight stays within editor limits")
	# Freeze on deliberately lowering hands even when the person walks.
	_drive_pose(wrapper, plane, 0.8, false, -1.0, 30)
	var frozen := float(plane.get("plane_x_norm"))
	_check(absf(frozen - left_position) < 0.001 and not bool(plane.get("airplane_pose_active")),
		id + " lowered arms preserve exact plane position despite walking")
	_drive_pose(wrapper, plane, 0.8, true, -1.0, 1)
	var resumed_x := float(plane.get("plane_x_norm"))
	_check(absf(resumed_x - frozen) < 0.15, id + " raising arms again never teleports across lanes")
	_drive_pose(wrapper, plane, 0.8, true, -1.0, 40)
	_check(float(plane.get("plane_x_norm")) > frozen + 0.35,
		id + " re-raised wide arms immediately restore body-controlled flight")
	# A stale gesture must freeze while a less strict torso pose remains valid.
	service.last_pose_ms = Time.get_ticks_msec() - (int(service.GESTURE_STALE_MS) + 50)
	_check(service.has_valid_pose() and not service.has_airplane_pose(),
		id + " freshness guard separates torso lock from stale wide-arm signal")
	wrapper.call("_process", FIXED_FRAME)
	var stale_x := float(plane.get("plane_x_norm"))
	plane.call("_update_plane_motion", 0.3)
	_check(absf(float(plane.get("plane_x_norm")) - stale_x) < 0.001
		and not bool(plane.get("airplane_pose_active")),
		id + " stale raised-arm packet cannot keep plane steering")
	# A true lost-lock packet suspends game after grace period.
	_emit_packet(-1.0, true, true, 1.0, false)
	wrapper.call("_process", 0.30)
	wrapper.call("_process", 0.40)
	_check(bool(wrapper.get("tracking_suspended")) and plane.process_mode == Node.PROCESS_MODE_DISABLED,
		id + " lost student pauses entire game after tracking grace")
	_check(bool(wrapper.tracking_notice.visible), id + " lost tracking displays guidance")
	var lost_x := float(plane.get("plane_x_norm"))
	_check(absf(lost_x - stale_x) < 0.001, id + " occlusion keeps prior plane position")
	_emit_packet(0.5, true, true, 1.0)
	wrapper.call("_process", FIXED_FRAME)
	_check(not bool(wrapper.get("tracking_suspended")) and plane.process_mode == Node.PROCESS_MODE_INHERIT,
		id + " reacquired pose resumes same minigame without restart")
	_check(bool(plane.get("airplane_pose_active")), id + " reacquired wide arms re-enable steering")
	_drive_pose(wrapper, plane, 0.2, true, 1.0, 35)
	_check(float(plane.get("plane_x_norm")) < lost_x - 0.15,
		id + " reacquisition accepts newly observed LEFT position")
	# Confirm the existing gate and HUD contracts after all synthetic steering.
	_check(int(plane.get("attempts")) == 0 and int(plane.get("correct_count")) == 0
		and (plane.get("round_data") as Dictionary).get("options", []) == options,
		id + " body bridge cannot accidentally score or regenerate word gates")
	_check(int(plane.get("lives")) == 3 and
		(plane.get_node("HUDLayer/HUD/ScoreBottomContainer/ScoreNumber") as Label).text == "0",
		id + " pose motion does not alter hearts or HUD score")
	var before_progress := float(plane.get("gate_progress"))
	plane.call("_update_gate_wave", 0.06)
	plane.call("_sync_visuals")
	_check(float(plane.get("gate_progress")) > before_progress, id + " continuous gate flight remains active after reacquire")
	wrapper.preserve_camera_for_restart()
	wrapper.queue_free()
	await process_frame
	await process_frame
	_check(service.active, id + " test wrapper cleanup keeps shared synthetic camera for next case")


func _drive_pose(wrapper: Control, game: Control, x: float, arms_open: bool,
		roll: float, frames: int) -> void:
	for index in range(frames):
		_emit_packet(x, arms_open, arms_open, roll)
		wrapper.call("_process", FIXED_FRAME)
		game.call("_update_plane_motion", FIXED_FRAME)
		game.call("_sync_visuals")


func _emit_packet(x: float, has_pose: bool, wide_arms: bool,
		roll: float = 0.0, pose_valid: bool = true) -> void:
	var valid := pose_valid and x >= 0.0 and x <= 1.0
	if valid:
		# Exercise the packet parser with deterministic measured coordinates,
		# without testing variable-rate inference smoothing a second time.
		service.set("_smoothed_x", x)
	service._apply_pose_packet({
		"kind": "pose", "token": TOKEN, "state": "tracking",
		"pose": valid, "x": x if valid else -1.0,
		"lock_state": "locked" if valid else "occluded",
		"hand_up": has_pose, "airplane_pose": wide_arms,
		"wing_roll": roll
	}, Time.get_ticks_msec())


func _within_flight_limits(game: Control, left: float, right: float) -> bool:
	var center: float = float(game.call("_plane_center_x"))
	return center >= left - 1.0 and center <= right + 1.0


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("FAIL body/pose integration: ", description)


func _finish() -> void:
	print("%s Human Plane 3-zone body integration: %d checks, %d failures" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
