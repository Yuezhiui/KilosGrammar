extends SceneTree

# Real editor-authored flight/collision geometry, no webcam or pose packets.
# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_motion_collision.gd
const GAME := preload("res://ui/minigames/human_plane.tscn")
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
	var plane := game.get_node("WorldView3D/Viewport3D/FlightWorld/PlayerRig") as Node3D
	var renderer := game.get_node("WorldView3D") as SubViewportContainer
	var dt := 1.0 / float(fps)

	# One bounded pursuit covers most of an entire left-to-right change in
	# ~0.4 s; no movement may happen on an ineligible or stale student.
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
		_check(current >= previous - 0.00001 and current - previous <= dt * 3.0 + 0.00001,
			label + " rightward frame%d bounded and monotonic" % frame)
		game.call("_sync_visuals")
		_check(absf(plane.position.x - float(renderer.call("_render_x_from_body_norm", current))) < 0.02,
			label + " frame%d visible 3D plane follows exact scoring X" % frame)
		previous = current
	_check(previous > 0.93 and previous < 1.0,
		label + " reaches far-right lane smoothly in 0.4 seconds")
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
	_check(float(game.get("plane_x_norm")) < 0.05,
		label + " left lane reachable within 0.45s after new verified input")

	# Independently calculate intersection widths from the authored visible
	# ring rectangles and actual pilot width. The ambiguous ratio must not
	# depend on which word the grammar bank marked correct.
	var progress := float(game.call("_progress_for_answer_line"))
	var rects: Array[Rect2] = []
	for lane in range(3):
		rects.append(game.call("_gate_visible_rect", lane, progress) as Rect2)
	var hitbox := game.get_node("PlaneRig/Hitbox") as Control
	for pair in range(2):
		for winner in [pair, pair + 1]:
			var strong_x := _find_paired_x(rects[pair], rects[pair + 1],
				hitbox.size.x, winner == pair, 0.80)
			_check(is_finite(strong_x), label + " ring%d pair has an 80/20 straddle" % pair)
			if is_finite(strong_x):
				_place_hitbox_at_x(game, strong_x)
				_check(int(game.call("_lane_hit_at_answer_line")) == winner,
					label + " 80/20 overlap awards only dominant ring%d" % winner)
				for correct_lane in [pair, pair + 1]:
					var round_data: Dictionary = (game.get("round_data") as Dictionary).duplicate(true)
					round_data["valid_indices"] = [correct_lane]
					game.set("round_data", round_data)
					_check(int(game.call("_lane_hit_at_answer_line")) == winner,
						label + " winner independent of correct answer%d" % correct_lane)
		var close_x := _find_paired_x(rects[pair], rects[pair + 1],
			hitbox.size.x, true, 0.52)
		_check(is_finite(close_x), label + " ring%d pair has a near 52/48 straddle" % pair)
		if is_finite(close_x):
			_place_hitbox_at_x(game, close_x)
			_check(int(game.call("_lane_hit_at_answer_line")) == -1,
				label + " 52/48 split neutral, regardless of ring order")

	# One authoritative crossing earns +100/+14%; wrong and near-tie
	# crossings cannot deduct points or remove a previously earned boost.
	var win_x := _find_paired_x(rects[0], rects[1], hitbox.size.x, true, 0.80)
	if is_finite(win_x):
		game.call("_start_wave")
		var round_data: Dictionary = (game.get("round_data") as Dictionary).duplicate(true)
		round_data["valid_indices"] = [0]
		game.set("round_data", round_data)
		_place_hitbox_at_x(game, win_x)
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == 100 and int(game.get("speed_boost_count")) == 1,
			label + " 80/20 correct yields exactly +100 and one speed boost")
		game.call("_start_wave")
		round_data = (game.get("round_data") as Dictionary).duplicate(true)
		round_data["valid_indices"] = [1]
		game.set("round_data", round_data)
		_place_hitbox_at_x(game, win_x)
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == 100 and int(game.get("speed_boost_count")) == 1,
			label + " same 80/20 landing when wrong never deducts or boosts")
		_check(is_equal_approx(float(game.get("speed_multiplier")), 1.14),
			label + " wrong ring preserves earned cumulative +14 percent")
	game.queue_free()
	await process_frame
	await process_frame


func _find_paired_x(left: Rect2, right: Rect2, width: float,
		winner_is_left: bool, desired_ratio: float) -> float:
	var gap_center := (left.end.x + right.position.x) * 0.5
	var best_x := NAN
	var best_distance := INF
	for step in range(-240, 241):
		var x := gap_center + float(step) * 0.25
		var first := maxf(minf(x + width * 0.5, left.end.x) - maxf(x - width * 0.5, left.position.x), 0.0)
		var second := maxf(minf(x + width * 0.5, right.end.x) - maxf(x - width * 0.5, right.position.x), 0.0)
		if first <= 0.0 or second <= 0.0:
			continue
		var dominant := first if winner_is_left else second
		var other := second if winner_is_left else first
		if desired_ratio > 0.55 and (dominant < width * 0.50 or dominant <= other):
			continue
		var distance := absf(dominant / (dominant + other) - desired_ratio)
		if distance < best_distance:
			best_distance = distance
			best_x = x
	return best_x if best_distance <= 0.045 else NAN


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
