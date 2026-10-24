extends SceneTree

# Godot 4.7 --headless --path . --script res://tools/test_human_plane_body_steering.gd
# Integration-free synthetic calibrated X samples; the production wrapper
# verifies fresh BOTH-ARMS-WIDE poses before calling these methods.
const PLANE_SCENE := preload("res://ui/minigames/human_plane.tscn")
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]
const FRAME_RATES := [30, 60]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dimensions in RESOLUTIONS:
		for difficulty in DIFFICULTIES:
			for mode in MODES:
				for fps in FRAME_RATES:
					await _test_steering(dimensions, difficulty, mode, fps)
	print("HUMAN PLANE BODY STEERING: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_steering(dimensions: Vector2i, difficulty: String, mode: String, fps: int) -> void:
	root.size = dimensions
	var game := PLANE_SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity": "Human Plane", "topic": "Noun",
		"difficulty": difficulty, "game_mode": mode})
	await process_frame
	await process_frame
	game.set_process(false)
	var label := "%dx%d/%s/%s/%dfps" % [dimensions.x, dimensions.y, difficulty, mode, fps]
	var dt := 1.0 / float(fps)
	var left_marker := game.get_node("FlightPaths/PlaneLeftLimit") as Control
	var right_marker := game.get_node("FlightPaths/PlaneRightLimit") as Control
	var offset := float(game.get("_plane_authored_offset_x"))
	var left_bound := left_marker.get_rect().get_center().x + offset
	var right_bound := right_marker.get_rect().get_center().x + offset
	_check(left_bound < right_bound, label + " full authored left-to-right route")
	_check(game.has_method("set_body_x") and game.has_method("set_airplane_pose_active"),
		label + " public body-X / wide-arm APIs available")
	_check(not bool(game.get("airplane_pose_active")), label + " starts safely without arms")
	_check(int(game.get("lives")) == 3, label + " three-heart allowance")
	_check(float(game.get("time_remaining")) > 59.0 if mode == "Seconds" else
		is_zero_approx(float(game.get("time_remaining"))), label + " mode timer unaffected")
	_check(is_equal_approx(float(game.get("plane_x_norm")), 0.5), label + " initial center")

	# Old callers cannot enable angle control, change eligibility or steer.
	game.call("set_wing_steering", 1.0, true)
	game.call("set_body_x", 1.0)
	game.call("_update_plane_motion", 2.0)
	_check(not bool(game.get("airplane_pose_active")) and
		is_equal_approx(float(game.get("plane_x_norm")), 0.5),
		label + " legacy gyro and arms-down body X cannot move aircraft")
	game.call("set_airplane_pose_active", true)
	game.call("_update_plane_motion", 0.2)
	_check(is_equal_approx(float(game.get("plane_x_norm")), 0.5),
		label + " arm raise alone cannot replay stale right input")
	game.call("set_body_x", INF)
	game.call("_update_plane_motion", dt)
	_check(is_equal_approx(float(game.get("plane_x_norm")), 0.5),
		label + " invalid tracking coordinate ignored")

	# Real full-range calibrated input, using exactly the authored path markers.
	game.call("set_body_x", 1.0)
	var first := float(game.get("plane_x_norm"))
	game.call("_update_plane_motion", dt)
	var moved := float(game.get("plane_x_norm"))
	_check(moved > first and moved - first < game.BODY_MAX_TRAVEL_PER_SECOND * dt + 0.0001,
		label + " first frame moves right smoothly without snapping")
	for _i in range(2 * fps):
		game.call("_update_plane_motion", dt)
	_check(float(game.get("plane_x_norm")) > 0.995,
		label + " calibrated far RIGHT reaches full authored limit")
	_check(absf(float(game.call("_plane_center_x")) - right_bound) < 1.0,
		label + " visible airplane equals authored RIGHT marker")

	game.call("set_body_x", -1.0)
	var before_reverse := float(game.get("plane_x_norm"))
	game.call("_update_plane_motion", dt)
	_check(float(game.get("plane_x_norm")) < before_reverse and
		before_reverse - float(game.get("plane_x_norm")) < game.BODY_MAX_TRAVEL_PER_SECOND * dt + 0.0001,
		label + " instant reversal follows new body X without overshoot")
	for _i in range(2 * fps):
		game.call("_update_plane_motion", dt)
	_check(float(game.get("plane_x_norm")) < 0.005,
		label + " calibrated far LEFT reaches full authored limit")
	_check(absf(float(game.call("_plane_center_x")) - left_bound) < 1.0,
		label + " visible airplane equals authored LEFT marker")

	# Centering happens ONLY if calibrated body X is at zero, never from
	# level arms or from waiting after the last sample.
	game.call("set_body_x", 0.0)
	for _i in range(2 * fps):
		game.call("_update_plane_motion", dt)
	_check(absf(float(game.get("plane_x_norm")) - 0.5) < 0.006,
		label + " calibrated CENTER steers to middle without wobble")
	game.call("set_body_x", 0.7)
	for _i in range(fps):
		game.call("_update_plane_motion", dt)
	var off_center := float(game.get("plane_x_norm"))
	for _i in range(fps):
		game.call("_update_plane_motion", dt)
	_check(off_center > 0.80 and absf(float(game.get("plane_x_norm")) - off_center) < 0.005,
		label + " standing still off-center never auto-centers")

	# Small frame-to-frame YOLO position noise should not shake the plane.
	var jitter_low := float(game.get("plane_x_norm"))
	var jitter_high := jitter_low
	for n in range(2 * fps):
		game.call("set_body_x", 0.7 + (0.022 if n % 2 == 0 else -0.022))
		game.call("_update_plane_motion", dt)
		jitter_low = minf(jitter_low, float(game.get("plane_x_norm")))
		jitter_high = maxf(jitter_high, float(game.get("plane_x_norm")))
	_check(jitter_high - jitter_low < 0.045,
		label + " noisy position measurements remain visually stable")

	# Lowering either arm, temporarily losing tracking and raising both
	# again need no recalibration, stored velocity, or old-camera jump.
	game.call("set_body_x", -1.0)
	game.call("_update_plane_motion", dt)
	game.call("set_airplane_pose_active", false)
	var frozen := float(game.get("plane_x_norm"))
	game.call("set_body_x", 1.0)
	game.call("_update_plane_motion", 6.0)
	game.call("set_airplane_pose_active", false)
	game.call("set_wing_steering", -1.0, true)
	game.call("_update_plane_motion", 1.0)
	_check(is_equal_approx(float(game.get("plane_x_norm")), frozen),
		label + " arms lowered/lost pose freezes exact X with no legacy drift")
	_check(is_equal_approx(float(game.get("target_x_norm")), frozen),
		label + " old target cleared when pose lost")
	game.call("set_airplane_pose_active", true)
	game.call("_update_plane_motion", 0.5)
	_check(is_equal_approx(float(game.get("plane_x_norm")), frozen),
		label + " arms re-raised safely wait for next body sample")
	game.call("set_body_x", -1.0)
	game.call("_update_plane_motion", dt)
	_check(float(game.get("plane_x_norm")) < frozen,
		label + " fresh raised-arm sample immediately resumes leftward")

	# A hitch must not teleport across lanes, even while arms remain wide.
	game.call("set_body_x", 1.0)
	var pre_hitch := float(game.get("plane_x_norm"))
	game.call("_update_plane_motion", 4.0)
	_check(float(game.get("plane_x_norm")) - pre_hitch <=
		game.BODY_MAX_TRAVEL_PER_SECOND * game.BODY_MAX_MOTION_STEP + 0.0001,
		label + " long frame step distance capped")

	# Pause/resume retains target, hearts and gate progression consistently.
	var old_progress := float(game.get("gate_progress"))
	var old_time := float(game.get("time_remaining"))
	game.call("_pause")
	var pause_x := float(game.get("plane_x_norm"))
	game.call("set_body_x", -1.0)
	game.call("_process", 1.0)
	game.call("_update_plane_motion", dt)
	_check(is_equal_approx(float(game.get("plane_x_norm")), pause_x),
		label + " pause freezes aircraft and ignores incoming position")
	_check(is_equal_approx(float(game.get("gate_progress")), old_progress) and
		is_equal_approx(float(game.get("time_remaining")), old_time),
		label + " pause keeps gates and remaining time frozen")
	game.call("_resume")
	game.call("_update_plane_motion", dt)
	_check(is_equal_approx(float(game.get("plane_x_norm")), pause_x),
		label + " resume has no phantom pre-pause movement")
	game.call("set_body_x", -1.0)
	game.call("_update_plane_motion", dt)
	_check(float(game.get("plane_x_norm")) < pause_x,
		label + " fresh position after resume immediately steers")
	_check(int(game.get("lives")) == 3 and int(game.get("attempts")) == 0,
		label + " steering never affects collision attempts or hearts")
	_check((game.get("round_data") as Dictionary).get("options", []).size() == 3,
		label + " editor-authored gate wave remains loaded")
	game.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("HUMAN PLANE BODY FAIL: ", label)
