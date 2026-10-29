extends SceneTree

# Real editor-authored flight/collision geometry, no webcam or pose packets.
# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_motion_collision.gd
const GAME := preload("res://ui/minigames/human_plane/human_plane.tscn")
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport_size in VIEWPORTS:
		for frame_rate in [30, 60]:
			await _exercise(viewport_size, frame_rate)
	print("HUMAN PLANE MOTION/COLLISION: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _exercise(viewport_size: Vector2i, fps: int) -> void:
	root.size = viewport_size
	root.content_scale_size = Vector2i(1280, 720)
	var label := "%dx%d/%dfps" % [viewport_size.x, viewport_size.y, fps]
	var game := GAME.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity": "Human Plane", "topic": "Noun", "game_mode": "Seconds",
		"difficulty": "Normal", "camera_live": false})
	await process_frame
	await process_frame
	game.set_process(false)
	var plane := game.get_node("PlaneRig") as Control
	_check(game.get_node_or_null("HybridFlight3D/RenderViewport/FlightWorld3D") is Node3D and
		game.get_node_or_null("FlightBackground") == null and
		game.get_node_or_null("ParallaxVisuals") == null,
		label + " native Node3D flight world replaces the retired painted background")
	var dt := 1.0 / float(fps)

	# Signed arm-bank drives capped velocity, with neutral T-pose holding X.
	game.set("plane_x_norm", 0.0)
	game.set("target_x_norm", 0.0)
	game.set_airplane_pose_active(false)
	game.set_body_x(1.0)
	game.call("_update_plane_motion", 0.5)
	_check(is_equal_approx(float(game.get("plane_x_norm")), 0.0),
		label + " invalid pose cannot steer")
	game.set_airplane_pose_active(true)
	game.call("_update_plane_motion", 0.5)
	_check(is_equal_approx(float(game.get("plane_x_norm")), 0.0),
		label + " pose reacquisition cannot replay invalid input")
	game.set_body_x(1.0)
	var previous := 0.0
	for frame in range(int(round(0.4 * fps))):
		game.call("_update_plane_motion", dt)
		var current := float(game.get("plane_x_norm"))
		_check(current >= previous - 0.00001 and current - previous <= dt * 0.82 + 0.00001,
			label + " rightward frame%d bounded and monotonic" % frame)
		game.call("_sync_visuals")
		_check(absf(plane.get_rect().get_center().x - float(game.call("_plane_center_x"))) < 0.02,
			label + " frame%d visible 2D plane follows exact scoring X" % frame)
		previous = current
	_check(previous > 0.20 and previous <= 0.4 * 0.82 + 0.00001,
		label + " right bank advances smoothly within 0.82 normalized units/s")
	game.set_body_x(0.0)
	for _frame in range(fps):
		game.call("_update_plane_motion", dt)
	# A smooth speed integrator BRAKES gradually rather than teleporting its
	# velocity to zero. Max carry distance is speed / response rate: .82 / 9.
	_check(absf(float(game.get("plane_x_norm")) - previous) < 0.10
		and absf(float(game.get("_bank_velocity"))) < 0.001,
		label + " neutral T-pose smoothly brakes to a complete stop")
	previous = float(game.get("plane_x_norm"))
	game.set_airplane_pose_active(false)
	game.set_body_x(-1.0)
	for _frame in range(fps):
		game.call("_update_plane_motion", dt)
	_check(is_equal_approx(float(game.get("plane_x_norm")), previous),
		label + " tracking loss holds position for one second")
	game.set_airplane_pose_active(true)
	game.call("_update_plane_motion", dt)
	_check(is_equal_approx(float(game.get("plane_x_norm")), previous),
		label + " old left target does not replay after tracking returns")
	game.set_body_x(-1.0)
	for _frame in range(int(round(0.45 * fps))):
		game.call("_update_plane_motion", dt)
	_check(float(game.get("plane_x_norm")) < previous - 0.20,
		label + " new verified left bank smoothly moves left")

		# The hidden source 2D scoring guides align with the projected 3D torus
		# rings. A gap between rings stays a MISS, never an adjacent winner.
	var progress := float(game.call("_progress_for_answer_line"))
	var rects: Array[Rect2] = []
	for lane in range(3):
		rects.append(game.call("_gate_visible_rect", lane, progress) as Rect2)
		_place_hitbox_at_x(game, rects[lane].get_center().x)
		_check(int(game.call("_lane_hit_at_answer_line")) == lane,
			label + " single visible 2D arc%d scores at its actual center" % lane)
	for pair in range(2):
		var gap_center := (rects[pair].end.x + rects[pair + 1].position.x) * 0.5
		_check(rects[pair].end.x < rects[pair + 1].position.x,
			label + " original 2D arcs remain visually separated at scoring")
		_place_hitbox_at_x(game, gap_center)
		_check(int(game.call("_lane_hit_at_answer_line")) == -1,
			label + " between arc%d and arc%d remains a miss" % [pair, pair + 1])

	# One authoritative crossing earns +100 and a difficulty-balanced permanent
	# correct-only speed boost; wrong and missed
	# crossings cannot deduct points or remove a previously earned boost.
	var win_x := rects[0].get_center().x
	if is_finite(win_x):
		game.call("_start_wave")
		var round_data: Dictionary = (game.get("round_data") as Dictionary).duplicate(true)
		round_data["valid_indices"] = [0]
		game.set("round_data", round_data)
		_place_hitbox_at_x(game, win_x)
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == 100 and int(game.get("speed_boost_count")) == 1,
			label + " correct 2D arc yields exactly +100 and one speed boost")
		game.call("_start_wave")
		round_data = (game.get("round_data") as Dictionary).duplicate(true)
		round_data["valid_indices"] = [1]
		game.set("round_data", round_data)
		_place_hitbox_at_x(game, win_x)
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == 100 and int(game.get("speed_boost_count")) == 1,
			label + " same visible arc landing when wrong never deducts or boosts")
		# Normal's first correct hit is +7%; the diminished gains toward the
		# 1.35x ceiling are earned only from *future* correct collisions.
		var expected_first_normal_boost := 1.0 + (1.35 - 1.0) * (1.0 - pow(0.8, 1.0))
		_check(is_equal_approx(float(game.get("speed_multiplier")), expected_first_normal_boost),
			label + " wrong ring preserves earned permanent +7 percent Normal boost")
	game.queue_free()
	await process_frame
	await process_frame


func _place_hitbox_at_x(game: Control, x: float) -> void:
	var left := game.get_node("FlightPaths/PlaneLeftLimit") as Control
	var right := game.get_node("FlightPaths/PlaneRightLimit") as Control
	var rig := game.get_node("PlaneRig") as Control
	var hitbox := rig.get_node("Hitbox") as Control
	var offset := float(game.get("_plane_authored_offset_x")) + hitbox.get_rect().get_center().x - rig.size.x * 0.5
	game.set("plane_x_norm", (x - left.get_rect().get_center().x - offset) /
		(right.get_rect().get_center().x - left.get_rect().get_center().x))


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("HUMAN PLANE MOTION/COLLISION FAIL: ", label)
