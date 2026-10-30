extends SceneTree

# Offline native-3D Human Plane collision-boundary regression. Both airplane
# and each hollow torus have independent editor-authored CollisionShape3D.
# A student must have a fresh BOTH-ARMS pose and clear precisely one ring's
# *physical aperture* at the authoritative AnswerLine to earn any score.
# No live camera, database, network or saved student profile is accessed.
const GAME := preload("res://ui/minigames/human_plane/human_plane.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const MODES := ["Seconds", "Lives"]
const RING_NAMES := ["Left", "Center", "Right"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dims in SIZES:
		for mode in MODES:
			await _verify(dims, mode)
	print("HUMAN PLANE COLLISION BOUNDARY: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _verify(dims: Vector2i, mode: String) -> void:
	root.size = dims
	root.content_scale_size = Vector2i(1280, 720)
	var tag := "%dx%d/%s" % [dims.x, dims.y, mode]
	var game := GAME.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity":"Human Plane", "topic":"Noun",
		"difficulty":"Normal", "game_mode":mode})
	for i in range(3):
		await process_frame
	game.set_process(false)
	var renderer := game.get_node("HybridFlight3D") as Node2D
	renderer.set_process(false)
	var world := renderer.get_node("RenderViewport/FlightWorld3D") as Node3D
	var pilot := world.get_node("PlaneAnchor/PlanePassageHitbox/HitShape") as CollisionShape3D
	_check(pilot.shape is SphereShape3D and pilot.position.is_finite(),
		tag + " airplane owns an editor-authored physical collision sphere")
	var norm: PackedFloat32Array = game.call("_normalized_scoring_lane_centers",
		float(game.call("_progress_for_answer_line")))
	_check(norm.size() == 3, tag + " three distinct 3D physical lane centers")
	if norm.size() != 3:
		game.queue_free()
		await process_frame
		return
	for lane in range(3):
		var ring: Node3D = world.get_node("Gates/Gate" + RING_NAMES[lane])
		var mesh := ring.get_node("Ring") as MeshInstance3D
		var hit := ring.get_node("RingPassageHitbox/HitShape") as CollisionShape3D
		_check(hit.shape is CylinderShape3D and mesh.mesh is TorusMesh,
			tag + " lane%d has hollow TorusMesh plus separate 3D collision aperture" % lane)
		if hit.shape is CylinderShape3D and mesh.mesh is TorusMesh:
			_check((hit.shape as CylinderShape3D).radius <= (mesh.mesh as TorusMesh).inner_radius,
				tag + " lane%d scoring aperture never exceeds visible hole radius" % lane)
		_check(norm[lane] >= 0.0 and norm[lane] <= 1.0,
			tag + " lane%d remains reachable through calibrated body movement" % lane)
		if lane > 0:
			_check(norm[lane] > norm[lane - 1] + 0.06,
				tag + " lane%d has distinct nonoverlapping physical target" % lane)

	game.set_airplane_pose_active(true)
	for lane in range(3):
		game.plane_x_norm = norm[lane]
		_check(int(renderer.call("physical_lane_at_answer_line")) == lane,
			tag + " plane centered in physical hole %d chooses exactly that lane" % lane)
		game.plane_x_norm = norm[lane] + 0.007
		_check(int(renderer.call("physical_lane_at_answer_line")) == lane,
			tag + " lane%d near-center full wing clearance is eligible" % lane)
		game.plane_x_norm = norm[lane] + 0.03
		_check(int(renderer.call("physical_lane_at_answer_line")) == -1,
			tag + " lane%d wing contacting torus tube scores no portal" % lane)
	for pair in range(2):
		game.plane_x_norm = (norm[pair] + norm[pair + 1]) * 0.5
		_check(int(renderer.call("physical_lane_at_answer_line")) == -1,
			tag + " straddling adjacent tube exteriors %d/%d gives no free score" % [pair, pair + 1])

	# Moving the center gate guides in the Godot editor must move the actual
	# torus hitbox rather than leaving a stale pixel-sized scoring lane behind.
	var start := game.get_node("FlightPaths/GateStartCenter") as Control
	var finish := game.get_node("FlightPaths/GateEndCenter") as Control
	var start_original := start.position
	var finish_original := finish.position
	start.position.x += 70.0
	finish.position.x += 70.0
	var shifted: PackedFloat32Array = game.call("_normalized_scoring_lane_centers",
		float(game.call("_progress_for_answer_line")))
	_check(shifted.size() == 3 and shifted[1] > norm[1] + 0.04,
		tag + " editor moving center gate moves real physical target")
	if shifted.size() == 3:
		game.plane_x_norm = norm[1]
		_check(int(renderer.call("physical_lane_at_answer_line")) != 1,
			tag + " abandoned center position cannot score moved 3D torus")
		game.plane_x_norm = shifted[1]
		_check(int(renderer.call("physical_lane_at_answer_line")) == 1,
			tag + " steering to moved torus recovers unique center passage")
	start.position = start_original
	finish.position = finish_original

	# Two coincident hollow ring apertures are ambiguous; one plane cannot
	# select both even if the question marks both words as correct.
	var shift_x := float(game.call("_gate_visible_rect", 0,
		float(game.call("_progress_for_answer_line"))).get_center().x) - \
		float(game.call("_gate_visible_rect", 1,
		float(game.call("_progress_for_answer_line"))).get_center().x)
	start.position.x += shift_x
	finish.position.x += shift_x
	game.plane_x_norm = norm[0]
	_check(int(renderer.call("physical_lane_at_answer_line")) == -1,
		tag + " two perfectly overlapping physical rings are an ambiguous MISS")
	start.position = start_original
	finish.position = finish_original

	# Losing pose lock or lowering a hand freezes movement and prevents a
	# stale plane from rewarding a correct ring it can no longer steer toward.
	game.plane_x_norm = norm[1]
	game.set_airplane_pose_active(false)
	var frozen: float = float(game.plane_x_norm)
	game.set_body_x(-1.0)
	game.call("_update_plane_motion", 0.6)
	_check(is_equal_approx(game.plane_x_norm, frozen),
		tag + " missing tracked pose freezes the last physical airplane position")
	_check(int(renderer.call("physical_lane_at_answer_line")) == -1,
		tag + " absent both-arm pose can never earn points while centered")
	game.set_airplane_pose_active(true)

	# Three actual correct portal traversals award 100 each and boost speed
	# by this tier's diminishing earned increments, with no double callback.
	for lane in range(3):
		game.call("_start_wave")
		var wave: Dictionary = game.round_data.duplicate(true)
		wave["valid_indices"] = [lane]
		game.round_data = wave
		game.plane_x_norm = norm[lane]
		var before: int = int(game.score)
		var before_attempts: int = int(game.attempts)
		game.call("_resolve_at_answer_line")
		_check(game.selected_lane == lane and game.selected_was_correct and
			game.score == before + 100 and game.attempts == before_attempts + 1,
			tag + " lane%d correct 3D traversal awards +100 exactly once" % lane)
		game.call("_resolve_at_answer_line")
		_check(game.score == before + 100 and game.attempts == before_attempts + 1,
			tag + " lane%d second answer callback cannot double-pay" % lane)
		_check(game.lives == 3 and game.speed_boost_count == lane + 1,
			tag + " lane%d correct answer preserves lives and applies boost" % lane)
	var earned: float = game.speed_multiplier
	var expected_boost := 1.0 + 0.35 * (1.0 - pow(0.8, 3.0))
	_check(absf(earned - expected_boost) < 0.0001 and game.score == 300,
		tag + " Normal difficulty correct rings earn tier-correct diminishing boost and +300")

	for scenario in ["wrong", "miss"]:
		game.call("_start_wave")
		var wave: Dictionary = game.round_data.duplicate(true)
		wave["valid_indices"] = [0]
		game.round_data = wave
		game.plane_x_norm = norm[2] if scenario == "wrong" else -10.0
		var before: int = int(game.score)
		game.call("_resolve_at_answer_line")
		_check(game.score == before and not game.selected_was_correct and
			game.selected_lane == (2 if scenario == "wrong" else -1),
			tag + " %s grants +0 and records correct physical outcome" % scenario)
		_check(is_equal_approx(game.speed_multiplier, earned),
			tag + " %s cannot erase previously earned flight speed" % scenario)
		_check(game.lives == (3 if mode == "Seconds" else (2 if scenario == "wrong" else 1)),
			tag + " %s respects Seconds infinite hearts / Lives three hearts" % scenario)

	game.queue_free()
	await process_frame
	await process_frame


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
		printerr("COLLISION BOUNDARY FAIL: ", reason)
