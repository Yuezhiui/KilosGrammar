extends SceneTree

# Real scored crossing QA. Unlike layout tests this exercises the live
# transformed airplane sphere and each torus aperture during continuous
# flight, including pool handoffs and adversarial shape placement.
const GAME := preload("res://ui/minigames/human_plane/human_plane.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dimensions in SIZES:
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(dimensions)
		root.size = dimensions
		root.content_scale_size = dimensions
		for mode in ["Seconds", "Lives"]:
			await _exercise(dimensions, mode)
	print("LIVE PLANE + TORUS COLLISION: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _exercise(dimensions: Vector2i, mode: String) -> void:
	var label := "%s/%s" % [dimensions, mode]
	var game := GAME.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity": "Human Plane", "topic": "Noun",
		"difficulty": "Normal", "game_mode": mode})
	for _frame in range(3):
		await process_frame
	game.set_process(false)
	game.set_airplane_pose_active(true)
	var hybrid := game.get_node("HybridFlight3D") as Node2D
	hybrid.set_process(false)
	var score_progress := float(game.call("_progress_for_answer_line"))
	var centers: PackedFloat32Array = game.call("_normalized_scoring_lane_centers", score_progress)
	_check(centers.size() == 3, label + " all three reachable physical lanes")
	if centers.size() != 3:
		game.queue_free()
		await process_frame
		return
	# The collider intersection is a world-space passage, so being inside the
	# projected XY opening while the torus is still FAR away cannot score.
	game.plane_x_norm = centers[1]
	game.call("_start_wave")
	game.gate_progress = 0.0
	_check(int(hybrid.call("physical_lane_at_answer_line", true)) == -1,
		label + " early distant torus has no physical Z intersection")
	# Advance the physical camera toward the same stationary world-space
	# torus; teleports are not a flight and would incorrectly reset origin.
	for tick in range(1, 101):
		game.gate_progress = score_progress * float(tick) / 100.0
		hybrid.call("_process", 0.0)
	var crossing_lane: int = int(hybrid.call("physical_lane_at_answer_line", true))
	if crossing_lane != 1:
		var debug_plane := hybrid.get_node("RenderViewport/FlightWorld3D/PlaneAnchor/PlanePassageHitbox/HitShape") as CollisionShape3D
		var debug_ring := hybrid.get_node("RenderViewport/FlightWorld3D/Gates/GateCenter/RingPassageHitbox/HitShape") as CollisionShape3D
		print("CROSSING DEBUG ", label, " plane=", debug_plane.global_position,
			" ring=", debug_ring.global_position, " camera=",
			(hybrid.get_node("RenderViewport/FlightWorld3D/Camera") as Camera3D).global_position,
			" p=", game.gate_progress, " score_p=", score_progress)
	_check(crossing_lane == 1,
		label + " actual torus and airplane intersect at score depth")
	var first_active: Array[Control] = game.get("_gate_nodes")
	var pool_index := 0 if first_active[0].get_parent() == game.get_node("MovingGates") else 1
	var ring: Node3D = hybrid.get("_ring_pools")[pool_index][1]
	var aperture := ring.get_node("RingPassageHitbox/HitShape") as CollisionShape3D
	var original_shift := aperture.position
	aperture.position.x += 2.0
	_check(int(hybrid.call("physical_lane_at_answer_line", true)) == -1,
		label + " physically shifted aperture cannot award projected false +100")
	aperture.position = original_shift
	_check(int(hybrid.call("physical_lane_at_answer_line", true)) == 1,
		label + " restored editor collider again permits real passage")
	game.call("_start_wave")
	var initial_ids := {}
	for group in hybrid.get("_ring_pools"):
		for item in group:
			initial_ids[(item as Node3D).get_instance_id()] = true
	for cycle in range(5):
		var lane := cycle % 3
		var wave: Dictionary = game.round_data.duplicate(true)
		wave["valid_indices"] = [lane]
		game.round_data = wave
		game.plane_x_norm = centers[lane]
		game.target_x_norm = centers[lane]
		game.set_airplane_pose_active(true)
		var initial_score := int(game.score)
		var initial_attempts := int(game.attempts)
		var initial_completed := int(game.waves_completed)
		var saw_hit := false
		for _tick in range(430):
			game.call("_process", 1.0 / 60.0)
			hybrid.call("_process", 0.0)
			if game.gate_resolved and not saw_hit:
				saw_hit = true
				_check(int(game.selected_lane) == lane and int(game.score) == initial_score + 100
					and int(game.attempts) == initial_attempts + 1,
					label + " wave%d lane%d 3D crossing grants exactly +100" % [cycle, lane])
			if int(game.waves_completed) > initial_completed:
				break
		_check(saw_hit and int(game.waves_completed) == initial_completed + 1,
			label + " wave%d travels through and recycles next torus group" % cycle)
		_check(int(game.lives) == 3,
			label + " wave%d correct hit retains all three hearts" % cycle)
		_check(int(game.score) == (cycle + 1) * 100,
			label + " wave%d score increments once with no duplicate reward" % cycle)
	var final_ids := {}
	for group in hybrid.get("_ring_pools"):
		for item in group:
			final_ids[(item as Node3D).get_instance_id()] = true
	_check(final_ids == initial_ids and final_ids.size() == 6,
		label + " all waves recycle original six 3D rings")
	_check(game.time_remaining < 60.0 if mode == "Seconds" else game.time_remaining == 0.0,
		label + " correct collision leaves mode timer semantics unchanged")
	game.queue_free()
	await process_frame
	await process_frame


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("LIVE COLLISION FAIL: ", description)
