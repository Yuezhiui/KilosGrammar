extends SceneTree

## Native Godot scene and GPU regression for two fixed TorusMesh trios,
## actual camera-depth passage, unchanged source models and 2D gameplay HUD.
## Run --headless, or native OpenGL with -- --capture to save user:// frames.
const PLANE_SCENE := preload("res://ui/minigames/human_plane/human_plane.tscn")
const BALLOON_SCENE := preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const LANES := ["Left", "Center", "Right"]
const STEP := 1.0 / 60.0
var checks := 0
var failures: Array[String] = []
var gpu_checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var balloon := BALLOON_SCENE.instantiate() as Control
	root.add_child(balloon)
	await process_frame
	var balloon_title := balloon.get_node("HudLayer/ObjectivePanel") as TextureRect
	_check(balloon_title.texture != null and balloon_title.texture.resource_path.ends_with("/balloon_popping.png"),
		"Balloon Popping title panel remains editor authored")
	balloon.queue_free()
	await process_frame
	for dims in SIZES:
		for mode in ["Seconds", "Lives"]:
			await _exercise(dims, mode)
	print("HUMAN PLANE NATIVE TORUS: %s checks=%d failures=%d gpu_checks=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size(), gpu_checks])
	quit(0 if failures.is_empty() else 1)


func _exercise(dims: Vector2i, mode: String) -> void:
	var tag := "%dx%d/%s" % [dims.x, dims.y, mode]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(dims)
	root.content_scale_size = dims
	root.size = dims
	var game := PLANE_SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity":"Human Plane", "topic":"Noun", "difficulty":"Normal", "game_mode":mode})
	for frame in range(3):
		await process_frame
	game.set_process(false)
	var renderer := game.get_node("HybridFlight3D") as Node2D
	renderer.set_process(false)
	var viewport := renderer.get_node("RenderViewport") as SubViewport
	var world := viewport.get_node("FlightWorld3D") as Node3D
	var camera := world.get_node("Camera") as Camera3D
	var hud := game.get_node("HUDLayer/HUD") as Control
	var plane := world.get_node("PlaneAnchor") as Node3D
	var placement := plane.get_node("PlaneModelPlacement") as Node3D
	var downloaded := placement.get_node("DownloadedCartoonPlane") as Node3D
	_check(world.scene_file_path.ends_with("human_plane_flight_world_3d.tscn"), tag + " native independent Node3D world scene")
	_check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE and world.get_node("FlightEnvironment") is WorldEnvironment,
		tag + " perspective camera and genuine volumetric 3D environment")
	_check(world.get_node("FarClouds").get_child_count() >= 3 and world.get_node("NearClouds").get_child_count() >= 2,
		tag + " native clouds occupy independent parallax depths")
	_check(downloaded.scene_file_path.ends_with("cartoon_plane_1k.gltf") and _mesh_count(downloaded) == 22,
		tag + " all 22 original downloaded airplane meshes are instantiated")
	var original_placement := placement.transform
	_check(placement.scale.x > 0.0 and placement.scale.is_equal_approx(Vector3.ONE * placement.scale.x) and
		placement.position.is_equal_approx(Vector3.ZERO) and absf(absf(placement.rotation_degrees.y) - 180.0) < 0.01,
		tag + " teacher-authored centered, level forward airplane placement remains editable")
	_check(ResourceLoader.exists("res://assets/models/cartoon_plane/plane_basecolor_1024.png") and
		(load("res://assets/models/cartoon_plane/plane_basecolor_1024.png") as Texture2D).get_size() == Vector2(1024,1024),
		tag + " authentic optimized painted model texture preserved")
	_check(renderer.hybrid_enabled and renderer.draw_3d_gates and (renderer.get_node("OverlayTexture") as TextureRect).visible,
		tag + " native 3D renderer composited by default")
	_check(viewport.size == dims and viewport.msaa_3d == (Viewport.MSAA_4X if dims.y <= 720 else Viewport.MSAA_2X),
		tag + " viewport native resolution and adaptive GPU MSAA")
	_check(game.get_node_or_null("FlightBackground") == null and game.get_node_or_null("ParallaxVisuals") == null,
		tag + " retired flat visuals remain absent")
	_check(game.get_node_or_null("HUDLayer/HUD/FeedbackLabel") == null and
		game.get_node_or_null("HUDLayer/HUD/HumanPlaneTitlePanel") == null,
		tag + " duplicate debug/text HUD not reintroduced")
	_check((hud.get_node("TitlePlaque") as TextureRect).texture.resource_path.ends_with("/human_plane.png") and
		(hud.get_node("TitlePlaque") as TextureRect).visible,
		tag + " real supplied Human Plane title visible")
	_check((hud.get_node("TimerPlaque") as TextureRect).visible == (mode == "Seconds") and
		(hud.get_node("LivesPlaque") as TextureRect).visible == (mode == "Lives"),
		tag + " native 2D HUD obeys strict mode")
	_check(game.score == 0 and game.lives == 3 and (mode == "Lives" or game.time_remaining > 59),
		tag + " mode counters preserve score zero and three hearts")
	_check(game.get_node("PlaneRig/Hitbox") is Control and game.get_node("FlightPaths/GateEndCenter") is Control,
		tag + " 2D editor-authored collision and steering guides stay authoritative")
	_check(not (world.get_node("Sunlight") as DirectionalLight3D).shadow_enabled,
		tag + " lighting shadows disabled on classroom GPUs")

	var gates := world.get_node("Gates") as Node3D
	var pools: Array = renderer.get("_ring_pools")
	_check(pools.size() == 2 and gates.get_child_count() == 6, tag + " EXACT two pools of three native gate units")
	var recorded_ids := {}
	var resource_ids := {}
	var mesh_ids := {}
	for pool_index in range(2):
		for i in range(3):
			var ring := pools[pool_index][i] as Node3D
			var mesh := ring.get_node("Ring") as MeshInstance3D
			_check(mesh.mesh is TorusMesh and mesh.material_override is StandardMaterial3D,
				tag + " pool%d %s REAL TorusMesh and individual material" % [pool_index, LANES[i]])
			var torus := mesh.mesh as TorusMesh
			_check(torus.inner_radius >= 0.70 and torus.outer_radius > torus.inner_radius,
				tag + " pool%d %s authentic hollow ring" % [pool_index, LANES[i]])
			recorded_ids[ring.name] = ring.get_instance_id()
			mesh_ids[ring.name] = mesh.get_instance_id()
			resource_ids[ring.name] = mesh.mesh.get_instance_id()
	_check(recorded_ids.size() == 6 and mesh_ids.size() == 6,
		tag + " six unique reusable ring/mesh nodes without duplicate names")
	for i in range(3):
		_check((pools[0][i] as Node3D) == gates.get_node("Gate" + LANES[i]) and
			(pools[1][i] as Node3D) == gates.get_node("QueuedGate" + LANES[i]),
			tag + " " + LANES[i] + " authored gate plus fixed one-time queued instance")

	var score_p := float(game.call("_progress_for_answer_line"))
	_check(score_p > 0.0 and score_p < 0.98, tag + " source answer line permits physical passage to camera")
	var control_gates: Array = game.get("_gate_nodes")
	var offset_guides: Array[Rect2] = game.get("_authored_gate_rect_offsets")
	for fraction in [0.0, minf(0.42, score_p - 0.05), score_p]:
		game.gate_progress = fraction
		game.call("_sync_visuals")
		renderer.call("_process", 0.0)
		for i in range(3):
			var ring := pools[0][i] as Node3D
			var rect: Rect2 = game.call("_gate_visible_rect_with_offsets",
				i, fraction, offset_guides, control_gates)
			var expected: Vector2 = renderer.call("gate_screen_center",
				i, fraction, rect, false, offset_guides, control_gates)
			var screen_center := camera.unproject_position(ring.global_position)
			_check(ring.visible and rect.has_area() and screen_center.distance_to(expected) < 2.5,
				tag + " " + LANES[i] + " torus follows real 2D-authoritative screen Y/X at %.3f" % fraction)
			var physical_distance: float = renderer.call("_gate_distance", fraction, score_p)
			_check(absf(camera.global_position.z - ring.global_position.z - physical_distance) < 0.025 and
				ring.scale.x > 0.0 and ring.scale.y > 0.0,
				tag + " " + LANES[i] + " authentic projected camera depth at %.3f" % fraction)
			_check((control_gates[i] as Control).get_node("WordLabel").visible and
				(control_gates[i] as Control).get_node("WordPlate").visible,
				tag + " " + LANES[i] + " real vocabulary readable before score")
		if is_equal_approx(fraction, score_p):
			for i in range(3):
				var ring := pools[0][i] as Node3D
				_check(absf(ring.global_position.z - plane.global_position.z) < 0.02 and
					absf(ring.global_position.y - plane.global_position.y) < 0.035,
					tag + " " + LANES[i] + " ring reaches actual airplane 3D center and depth")

	# Source-authenticated successful scoring, including pooled incoming vocabulary.
	game.gate_progress = 0.0
	game.call("_sync_visuals")
	var valid: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
	_check(valid.size() > 0, tag + " genuine source GrammarBank answer available")
	if valid.is_empty():
		game.queue_free()
		await process_frame
		return
	var correct_lane := int(valid[0])
	_place_at_lane(game, correct_lane)
	_check(int(game.call("_lane_hit_at_answer_line")) == correct_lane,
		tag + " active player hitbox physically overlaps correct authentic option")
	var scored := false
	var seen_incoming := false
	var score_before := int(game.get("score"))
	for tick in range(900):
		game.call("_update_gate_wave", STEP)
		game.call("_sync_visuals")
		renderer.call("_process", 0.0)
		if not seen_incoming and not (game.get("next_round_data") as Dictionary).is_empty():
			seen_incoming = true
			var incoming: Array = game.get("_upcoming_gate_nodes")
			var next_words: Array = (game.get("next_round_data") as Dictionary).get("options", [])
			_check(next_words.size() == 3 and (incoming[0] as Control).get_parent().visible,
				tag + " genuine GrammarBank next trio already visible while original approaches")
			for i in range(3):
				_check((pools[1][i] as Node3D).visible and
					(incoming[i] as Control).get_node("WordLabel").visible and
					(incoming[i] as Control).get_node("WordPlate").visible and
					(incoming[i] as Control).get_node("WordLabel").text == String(next_words[i]).to_upper(),
					tag + " " + LANES[i] + " incoming TorusMesh and real vocabulary concurrently readable")
		if bool(game.get("gate_resolved")):
			scored = true
			break
	_check(seen_incoming and scored, tag + " real advancing gate triggers prefetch and scoring")
	if scored:
		_check(int(game.get("selected_lane")) == correct_lane and bool(game.get("selected_was_correct")) and
			int(game.get("score")) == score_before + 100 and int(game.get("attempts")) == 1,
			tag + " one source-authoritative +100 correct crossing")
		var outgoing: Array = game.get("_gate_nodes")
		var incoming: Array = game.get("_upcoming_gate_nodes")
		for i in range(3):
			var ring := pools[0][i] as Node3D
			var near_ring := pools[1][i] as Node3D
			_check(ring.visible and near_ring.visible,
				tag + " " + LANES[i] + " BOTH physical torus trios visible at scoring")
			_check(not (outgoing[i] as Control).get_node("WordLabel").visible and
				not (outgoing[i] as Control).get_node("WordPlate").visible and
				(incoming[i] as Control).get_node("WordLabel").visible and
				(incoming[i] as Control).get_node("WordPlate").visible,
				tag + " " + LANES[i] + " old plaques hide instantly, incoming words remain visible")
		# Inspect score location after a true hit; geometry snapshots may seek
		# exact fractions, but only the authentic collision awards points.
		game.gate_progress = score_p
		game.call("_sync_visuals")
		renderer.call("_process", 0.0)
		var hit_ring := pools[0][correct_lane] as Node3D
		var hole := ((hit_ring.get_node("Ring") as MeshInstance3D).mesh as TorusMesh).inner_radius
		var relative := hit_ring.global_position - plane.global_position
		_check(absf(relative.z) < 0.02 and absf(relative.y) < 0.035 and
			absf(relative.x) < hole * hit_ring.scale.x * 0.30,
			tag + " successfully scored ring physically centered on real airplane in 3D")
		_check(_largest_mesh_radius(downloaded, hit_ring.global_position,
			hit_ring.scale.x * hole, hit_ring.scale.y * hole) < 0.96,
			tag + " imported entire 22-mesh airplane fits inside real torus hole at collision")
		var passed := lerpf(score_p, 1.0, 0.45)
		game.gate_progress = passed
		game.call("_sync_visuals")
		renderer.call("_process", 0.0)
		for i in range(3):
			var ring := pools[0][i] as Node3D
			_check(ring.visible and ring.global_position.z > plane.global_position.z + 2.0 and
				absf(ring.global_position.y - plane.global_position.y) < 0.035,
				tag + " " + LANES[i] + " torus travels THROUGH airplane toward camera, fixed world Y")
		_check(is_equal_approx(float(game.call("_gate_passage_alpha", passed)), 1.0),
			tag + " torus remains opaque during early actual physical passage")
		var near_end := lerpf(score_p, 1.0, 0.986)
		game.gate_progress = near_end
		game.call("_sync_visuals")
		renderer.call("_process", 0.0)
		_check(float(renderer.call("_gate_distance", near_end, score_p)) < 0.22 and
			float(renderer.call("_gate_distance", 1.0, score_p)) <= camera.near * 1.10,
			tag + " passed torus moves into physical camera near-clip region before reuse")
		game.gate_progress = 1.0
		game.call("_sync_visuals")
		renderer.call("_process", 0.0)
		for i in range(3):
			_check(not (pools[0][i] as Node3D).visible and
				not (outgoing[i] as Control).get_node("WordLabel").visible,
				tag + " " + LANES[i] + " only outgoing ring exits view at complete camera passage")
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == score_before + 100 and int(game.get("attempts")) == 1,
			tag + " repeated collision callback cannot award +100 twice")
		# Advance actual wave boundary so the prefetched three rings become
		# active, preserving all six mesh/node identities.
		game.call("_update_gate_wave", STEP)
		game.call("_sync_visuals")
		renderer.call("_process", 0.0)
		_check(int(game.get("waves_completed")) == 1 and int(game.get("score")) == score_before + 100,
			tag + " one natural pool handoff preserves exact score")
		_check((game.get("_gate_nodes") as Array)[0] == incoming[0] and
			(pools[1][0] as Node3D).visible,
			tag + " previously visible next trio promoted, no node recreation")
		_check(placement.transform.is_equal_approx(original_placement),
			tag + " editable model placement not overridden by scoring or handoff")
		for pool in pools:
			for ring_node in pool:
				var ring := ring_node as Node3D
				var mesh := ring.get_node("Ring") as MeshInstance3D
				_check(ring.get_instance_id() == recorded_ids[ring.name] and
					mesh.get_instance_id() == mesh_ids[ring.name] and
					mesh.mesh.get_instance_id() == resource_ids[ring.name],
					tag + " reused " + ring.name + " node/mesh/resource identity fixed")
		_check(gates.get_child_count() == 6 and not bool(game.get("finished")),
			tag + " exactly six native rings remain bounded and game stays running")
	if DisplayServer.get_name() != "headless":
		for frame in range(3):
			await process_frame
		await RenderingServer.frame_post_draw
		var snapshot := root.get_texture().get_image()
		_check(snapshot != null and not snapshot.is_empty() and
			snapshot.get_size() == Vector2i(dims), tag + " real GPU frame composited at exact resolution")
		if "--capture" in OS.get_cmdline_user_args() and snapshot != null and not snapshot.is_empty():
			var filename := "user://_qa_human_plane_torus_%dx%d_%s.png" % [dims.x, dims.y, mode.to_lower()]
			_check(snapshot.save_png(filename) == OK, tag + " native GPU screenshot saved")
			print("NATIVE_TORUS_CAPTURE: " + ProjectSettings.globalize_path(filename))
			gpu_checks += 1
	game.queue_free()
	await process_frame
	await process_frame


func _place_at_lane(game: Control, lane: int) -> void:
	var at_line := float(game.call("_progress_for_answer_line"))
	var rect: Rect2 = game.call("_gate_visible_rect", lane, at_line)
	var left := game.get_node("FlightPaths/PlaneLeftLimit") as Control
	var right := game.get_node("FlightPaths/PlaneRightLimit") as Control
	var rig := game.get_node("PlaneRig") as Control
	var hitbox := game.get_node("PlaneRig/Hitbox") as Control
	var hitbox_offset := hitbox.get_rect().get_center().x - rig.size.x * 0.5
	game.set("plane_x_norm", (rect.get_center().x - hitbox_offset -
		float(game.get("_plane_authored_offset_x")) - left.get_rect().get_center().x) /
		(right.get_rect().get_center().x - left.get_rect().get_center().x))
	game.call("_sync_visuals")


func _largest_mesh_radius(node: Node, center: Vector3, radius_x: float, radius_y: float) -> float:
	var greatest := 0.0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_node := node as MeshInstance3D
		var bounds := mesh_node.mesh.get_aabb()
		for corner in range(8):
			var point := mesh_node.global_transform * bounds.get_endpoint(corner)
			var nx := (point.x - center.x) / radius_x
			var ny := (point.y - center.y) / radius_y
			greatest = maxf(greatest, sqrt(nx * nx + ny * ny))
	for child in node.get_children():
		greatest = maxf(greatest, _largest_mesh_radius(child, center, radius_x, radius_y))
	return greatest


func _mesh_count(parent: Node) -> int:
	var count := 1 if parent is MeshInstance3D and (parent as MeshInstance3D).mesh != null else 0
	for child in parent.get_children():
		count += _mesh_count(child)
	return count


func _check(ok: bool, title: String) -> void:
	checks += 1
	if not ok:
		failures.append(title)
		printerr("HUMAN PLANE TORUS FAIL: " + title)
