extends SceneTree

# Legacy test filename retained for runners. The airplane follows three
# stationary, measured arm/torso roll targets (LEFT / CENTER / RIGHT) while
# the same locked student's fresh steering packet is eligible. This tests
# post-calibration flight smoothing, without opening a webcam.
const PLANE_SCENE := preload("res://ui/minigames/human_plane/human_plane.tscn")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		for fps in [30, 60]:
			await _check_flight(resolution, fps)
	print("HUMAN PLANE STATIONARY ROLL FLIGHT: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check_flight(resolution: Vector2i, fps: int) -> void:
	root.size = resolution
	var plane := PLANE_SCENE.instantiate() as Control
	root.add_child(plane)
	plane.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plane.set_context({"activity": "Human Plane", "topic": "Noun",
		"game_mode": "Lives", "difficulty": "Easy"})
	await process_frame
	await process_frame
	plane.set_process(false)
	var prefix := "%dx%d / %dfps" % [resolution.x, resolution.y, fps]
	var dt := 1.0 / float(fps)
	var left_limit := (plane.get_node("FlightPaths/PlaneLeftLimit") as Control).get_rect().get_center().x
	var right_limit := (plane.get_node("FlightPaths/PlaneRightLimit") as Control).get_rect().get_center().x
	var authored_offset := float(plane.get("_plane_authored_offset_x"))
	_check(left_limit < right_limit, prefix + " editor flight limits ordered")
	plane.call("set_airplane_pose_active", true)
	plane.call("set_body_x", -1.0)
	var previous := float(plane.get("plane_x_norm"))
	for i in range(int(fps * 2.0)):
		plane.call("_update_plane_motion", dt)
		var next := float(plane.get("plane_x_norm"))
		_check(next <= previous + 0.00001, prefix + " measured LEFT roll glides smoothly frame " + str(i))
		previous = next
	_check(previous <= 0.03, prefix + " measured LEFT roll reaches authored path end")
	_check(absf(float(plane.call("_plane_center_x")) - (left_limit + authored_offset)) < 34.0 * float(resolution.x) / 1280.0,
		prefix + " plane reaches LEFT authored flight marker")

	# Holding the same body position remains clamped to editor path limits.
	for i in range(fps / 2):
		plane.call("_update_plane_motion", dt)
		_check(float(plane.get("plane_x_norm")) >= 0.0, prefix + " left boundary prevents off-path movement")

	# Wing-roll moves to measured RIGHT: airplane smoothly crosses the whole path.
	plane.call("set_body_x", 1.0)
	for i in range(int(fps * 2.5)):
		plane.call("_update_plane_motion", dt)
	var right_x := float(plane.get("plane_x_norm"))
	_check(right_x >= 0.97, prefix + " measured RIGHT roll reaches far RIGHT")
	_check(absf(float(plane.call("_plane_center_x")) - (right_limit + authored_offset)) < 34.0 * float(resolution.x) / 1280.0,
		prefix + " rendered plane reaches RIGHT authored flight marker")

	# The student's neutral arm/torso roll returns to calibrated CENTER.
	plane.call("set_body_x", 0.0)
	var initial := float(plane.get("plane_x_norm"))
	plane.call("_update_plane_motion", dt)
	var first := float(plane.get("plane_x_norm"))
	_check(first < initial and first > 0.5, prefix + " measured CENTER glides toward midpoint without teleporting")
	for i in range(int(fps * 2.5)):
		plane.call("_update_plane_motion", dt)
	_check(absf(float(plane.get("plane_x_norm")) - 0.5) < 0.007,
		prefix + " measured CENTER smoothly returns to CENTER")

	# Lost tracking/ambiguous roll freezes; an eligible fresh sample resumes.
	var frozen := float(plane.get("plane_x_norm"))
	plane.call("set_airplane_pose_active", false)
	plane.call("set_body_x", 1.0)
	plane.call("_update_plane_motion", 2.0)
	_check(is_equal_approx(float(plane.get("plane_x_norm")), frozen),
		prefix + " camera loss freezes current X even over large delta")
	plane.call("set_airplane_pose_active", true)
	_check(is_equal_approx(float(plane.get("plane_x_norm")), frozen),
		prefix + " camera reacquisition never teleports into another lane")
	plane.call("set_body_x", -1.0)
	plane.call("_update_plane_motion", dt)
	_check(float(plane.get("plane_x_norm")) < frozen,
		prefix + " fresh LEFT roll observation resumes flight without a restart")

	_check(int(plane.get("lives")) == 3, prefix + " Hearts/Lives unchanged")
	plane.queue_free()
	await process_frame
	await process_frame


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("HUMAN PLANE BODY FAIL: ", label)
