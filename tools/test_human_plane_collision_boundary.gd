extends SceneTree

# Dedicated offline full-3D Human Plane collision-boundary regression.
# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_collision_boundary.gd
# All test movements are synthetic editor-authored Control geometry. No
# webcam, live pose service, database, or external score saving.
const GAME := preload("res://ui/minigames/human_plane/human_plane.tscn")
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport in VIEWPORTS:
		for mode in ["Seconds", "Lives"]:
			await _verify(viewport, mode)
	print("HUMAN PLANE COLLISION BOUNDARY: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _verify(dimensions: Vector2i, mode: String) -> void:
	root.size = dimensions
	root.content_scale_size = Vector2i(1280, 720)
	var game := GAME.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity": "Human Plane", "topic": "Noun", "game_mode": mode, "difficulty": "Normal"})
	await process_frame
	await process_frame
	game.set_process(false)
	var prefix := "%dx%d/%s" % [dimensions.x, dimensions.y, mode]
	var progress := float(game.call("_progress_for_answer_line"))
	var hitbox := game.get_node("PlaneRig/Hitbox") as Control
	var rects: Array[Rect2] = []
	for lane in range(3):
		var rect := game.call("_gate_visible_rect", lane, progress) as Rect2
		rects.append(rect)
		_check(rect.size.x > hitbox.size.x * 2.0 and rect.size.y > 0.0,
			prefix + " lane%d retains readable editor-authored visible ring bounds" % lane)
		_place_hitbox_at_x(game, rect.get_center().x)
		_check(int(game.call("_lane_hit_at_answer_line")) == lane,
			prefix + " lane%d safely centered selects exactly that ring" % lane)
		var grazing_center := rect.get_center().x + rect.size.x * 0.41
		_place_hitbox_at_x(game, grazing_center)
		_check(_overlap_count(grazing_center, hitbox.size.x, rects) >= 1,
			prefix + " lane%d off-center still physically touches a ring" % lane)
		_check(int(game.call("_lane_hit_at_answer_line")) == -1,
			prefix + " lane%d outer-edge graze cannot select ring" % lane)

	for pair in range(2):
		var left: Rect2 = rects[pair]
		var right: Rect2 = rects[pair + 1]
		_check(left.get_center().x < right.get_center().x,
			prefix + " authentic left-to-right editor-authored ring order " + str(pair))
		# Actual default adjacent PNGs leave ~14px between frames. The 44px
		# pilot collision hitbox straddles BOTH despite a thin visual gap.
		var boundary_x := (left.end.x + right.position.x) * 0.5
		_place_hitbox_at_x(game, boundary_x)
		_check(_overlap_count(boundary_x, hitbox.size.x, rects) == 2,
			prefix + " actual narrow separation overlaps TWO ring frames at pair " + str(pair))
		_check(int(game.call("_lane_hit_at_answer_line")) == -1,
			prefix + " equal two-ring contact cannot prefer either ring " + str(pair))
		var option_data := (game.get("round_data") as Dictionary).duplicate(true)
		option_data["valid_indices"] = [pair, pair + 1]
		game.set("round_data", option_data)
		_check(int(game.call("_lane_hit_at_answer_line")) == -1,
			prefix + " equal contact remains neutral even if TWO words are correct")
		# A clear 80/20 majority receives the dominant lane whichever word
		# is correct. A 52/48 near-tie remains a miss regardless of ordering.
		for dominant in [pair, pair + 1]:
			var strong_x := _paired_straddle_x(left, right, hitbox.size.x,
				dominant == pair, 0.80)
			_check(is_finite(strong_x), prefix + " real 80/20 two-ring overlap exists")
			if is_finite(strong_x):
				_place_hitbox_at_x(game, strong_x)
				for correct_lane in [pair, pair + 1]:
					option_data["valid_indices"] = [correct_lane]
					game.set("round_data", option_data)
					_check(int(game.call("_lane_hit_at_answer_line")) == dominant,
						prefix + " 80/20 lane%d wins independently of word%d" % [dominant, correct_lane])
		var tie_x := _paired_straddle_x(left, right, hitbox.size.x, true, 0.52)
		_check(is_finite(tie_x), prefix + " real 52/48 two-ring overlap exists")
		if is_finite(tie_x):
			_place_hitbox_at_x(game, tie_x)
			_check(int(game.call("_lane_hit_at_answer_line")) == -1,
				prefix + " 52/48 near-tie remains neutral")

	# Camera/body movement must still be pose-gated. A fresh but *very late*
	# calibrated movement packet just before the line cannot jump from the
	# boundary into a neighboring ring in a single physics step.
	var between_x := (rects[0].end.x + rects[1].position.x) * 0.5
	_place_hitbox_at_x(game, between_x)
	game.set_airplane_pose_active(false)
	var held := float(game.get("plane_x_norm"))
	game.set_body_x(-1.0)
	game.call("_update_plane_motion", 0.5)
	_check(is_equal_approx(float(game.get("plane_x_norm")), held),
		prefix + " no fresh locked student means no lateral movement or phantom hit")
	game.set_airplane_pose_active(true)
	game.set_body_x(-1.0)
	game.call("_update_plane_motion", 0.001)
	_check(float(game.get("plane_x_norm")) < held,
		prefix + " fresh late pose input moves smoothly toward target, not teleport")
	_check(int(game.call("_lane_hit_at_answer_line")) == -1,
		prefix + " too-late pre-crossing pose sample stays in safe dead zone")
	game.set_airplane_pose_active(false)

	# Make an actual editor-authored widened gap, which overlaps neither ring.
	var start_center := game.get_node("FlightPaths/GateStartCenter") as Control
	var end_center := game.get_node("FlightPaths/GateEndCenter") as Control
	var start_original := start_center.position
	var end_original := end_center.position
	start_center.position.x += 150.0
	end_center.position.x += 150.0
	progress = float(game.call("_progress_for_answer_line"))
	var shifted := game.call("_gate_visible_rect", 1, progress) as Rect2
	var wide_gap_x := (rects[0].end.x + shifted.position.x) * 0.5
	_place_hitbox_at_x(game, wide_gap_x)
	_check(shifted.position.x - rects[0].end.x > hitbox.size.x,
		prefix + " moving native gate guides creates a physically empty gap")
	_check(int(game.call("_lane_hit_at_answer_line")) == -1,
		prefix + " fully empty gap cannot accidentally select a wrong ring")
	start_center.position = start_original
	end_center.position = end_original

	# Move neighboring authored markers so two rendered rings OVERLAP at
	# exactly the same location. A centered pilot then still gets a miss.
	var shift_x := rects[0].get_center().x - rects[1].get_center().x
	start_center.position.x += shift_x
	end_center.position.x += shift_x
	progress = float(game.call("_progress_for_answer_line"))
	var moved_center := game.call("_gate_visible_rect", 1, progress) as Rect2
	_place_hitbox_at_x(game, rects[0].get_center().x)
	_check(absf(moved_center.get_center().x - rects[0].get_center().x) < 1.0,
		prefix + " editor can deliberately overlap two ring centers")
	_check(int(game.call("_lane_hit_at_answer_line")) == -1,
		prefix + " perfectly centered in two overlapping rings is ambiguous MISS")
	start_center.position = start_original
	end_center.position = end_original

	# Selection must remain based on 3D flight's one authoritative crossing;
	# correct answer and speed are earned ONLY when unambiguously centered.
	game.call("_start_wave")
	var data: Dictionary = (game.get("round_data") as Dictionary).duplicate(true)
	data["valid_indices"] = [0]  # Left correct, center wrong.
	game.set("round_data", data)
	_place_hitbox_at_x(game, rects[0].get_center().x)
	game.call("_resolve_at_answer_line")
	_check(int(game.get("selected_lane")) == 0 and bool(game.get("selected_was_correct")),
		prefix + " centered left true correct answer scores once")
	_check(int(game.get("score")) == 100 and int(game.get("correct_count")) == 1,
		prefix + " one clear correct ring grants exactly +100")
	_check(int(game.get("speed_boost_count")) == 1 and
		is_equal_approx(float(game.get("speed_multiplier")), 1.14),
		prefix + " +14% permanent speed is granted ONLY for genuine correct ring")
	game.call("_resolve_at_answer_line")
	_check(int(game.get("score")) == 100 and int(game.get("speed_boost_count")) == 1,
		prefix + " repeated late answer crossing cannot double-score")

	var boundary := (rects[0].end.x + rects[1].position.x) * 0.5
	for correct_lane in [0, 1]:
		game.call("_start_wave")
		data = (game.get("round_data") as Dictionary).duplicate(true)
		data["valid_indices"] = [correct_lane]  # Both answer orderings!
		game.set("round_data", data)
		_place_hitbox_at_x(game, boundary)
		game.call("_resolve_at_answer_line")
		_check(int(game.get("selected_lane")) == -1 and not bool(game.get("selected_was_correct")),
			prefix + " wrong/correct ordering %d yields an unambiguous MISS" % correct_lane)
		_check(int(game.get("score")) == 100 and int(game.get("speed_boost_count")) == 1,
			prefix + " ambiguous miss never deducts points or grants speed")
		_check(is_equal_approx(float(game.get("speed_multiplier")), 1.14),
			prefix + " miss cannot remove previously earned speed")
		# Changing pose position AFTER gate resolves can never rewrite the answer.
		_place_hitbox_at_x(game, rects[correct_lane].get_center().x)
		game.call("_resolve_at_answer_line")
		_check(int(game.get("selected_lane")) == -1 and int(game.get("score")) == 100,
			prefix + " late movement toward correct ring cannot retroactively score")

	_check(int(game.get("lives")) == 1,
		prefix + " two missed ambiguous rings use existing heart-loss policy")
	game.call("_start_wave")
	data = (game.get("round_data") as Dictionary).duplicate(true)
	data["valid_indices"] = [0]
	game.set("round_data", data)
	_place_hitbox_at_x(game, rects[2].get_center().x)
	game.call("_resolve_at_answer_line")
	_check(int(game.get("selected_lane")) == 2 and not bool(game.get("selected_was_correct")),
		prefix + " clearly centered wrong ring is counted as wrong, not an ambiguous miss")
	_check(int(game.get("score")) == 100 and is_equal_approx(float(game.get("speed_multiplier")), 1.14),
		prefix + " wrong ring loses neither score nor accumulated +14% speed")
	game.queue_free()
	await process_frame
	await process_frame


func _place_hitbox_at_x(game: Control, screen_x: float) -> void:
	var left := game.get_node("FlightPaths/PlaneLeftLimit") as Control
	var right := game.get_node("FlightPaths/PlaneRightLimit") as Control
	var plane := game.get_node("PlaneRig") as Control
	var hitbox := plane.get_node("Hitbox") as Control
	var authored_offset := float(game.get("_plane_authored_offset_x"))
	var hitbox_offset := hitbox.get_rect().get_center().x - plane.size.x * 0.5
	var min_x := left.get_rect().get_center().x
	var max_x := right.get_rect().get_center().x
	game.set("plane_x_norm", (screen_x - min_x - authored_offset - hitbox_offset) / (max_x - min_x))
	_check(absf(float(game.call("_plane_center_x")) + hitbox_offset - screen_x) < 1.0,
		"actual authored Hitbox center matches requested screen-space X")


func _overlap_count(center: float, body_width: float, rects: Array[Rect2]) -> int:
	var touched := 0
	for rect in rects:
		if minf(center + body_width * 0.5, rect.end.x) > maxf(center - body_width * 0.5, rect.position.x):
			touched += 1
	return touched


func _paired_straddle_x(left: Rect2, right: Rect2, width: float,
		prefer_left: bool, desired_ratio: float) -> float:
	var between := (left.end.x + right.position.x) * 0.5
	var best_x := NAN
	var best_delta := INF
	for step in range(-240, 241):
		var x := between + float(step) * 0.25
		var left_touch := maxf(minf(x + width * 0.5, left.end.x) - maxf(x - width * 0.5, left.position.x), 0.0)
		var right_touch := maxf(minf(x + width * 0.5, right.end.x) - maxf(x - width * 0.5, right.position.x), 0.0)
		if left_touch <= 0.0 or right_touch <= 0.0:
			continue
		var preferred := left_touch if prefer_left else right_touch
		var other := right_touch if prefer_left else left_touch
		if desired_ratio > 0.55 and preferred < width * 0.5:
			continue
		var deviation := absf(preferred / (preferred + other) - desired_ratio)
		if deviation < best_delta:
			best_delta = deviation
			best_x = x
	return best_x if best_delta <= 0.045 else NAN


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("COLLISION BOUNDARY FAIL: ", label)
