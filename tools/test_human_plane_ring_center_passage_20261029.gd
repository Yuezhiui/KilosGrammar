extends SceneTree

## Inspect the actual 22-mesh airplane against each real TorusMesh at the
## score-crossing plane in Godot, including perspective and 2D guide placement.
## Native OpenGL: append -- --capture to save actual scene screenshots to user://.
const GAME_SCENE := preload("res://ui/minigames/human_plane/human_plane.tscn")
const DIMENSIONS := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const LANES := ["Left", "Center", "Right"]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dims in DIMENSIONS:
		await _exercise(dims)
	print("HUMAN PLANE RING CENTER PASSAGE: %s checks=%d failures=%d renderer=%s" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size(), DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)


func _exercise(dims: Vector2i) -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(dims)
	root.content_scale_size = dims
	root.size = dims
	var game := GAME_SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not game.has_method("set_context"):
		_assert(false, "%dx%d live HumanPlane game script failed to load; cannot validate torus passage" % [dims.x, dims.y])
		game.queue_free()
		await process_frame
		return
	game.set_context({"activity": "Human Plane", "topic": "Noun",
		"difficulty": "Normal", "game_mode": "Seconds", "camera_live": false})
	for frame in range(3):
		await process_frame
	game.set_process(false)
	var renderer := game.get_node("HybridFlight3D") as Node2D
	renderer.set_process(false)
	var viewport := renderer.get_node("RenderViewport") as SubViewport
	var world := viewport.get_node("FlightWorld3D") as Node3D
	var camera := world.get_node("Camera") as Camera3D
	var anchor := world.get_node("PlaneAnchor") as Node3D
	var placement := anchor.get_node("PlaneModelPlacement") as Node3D
	var original_placement := placement.transform
	var imported := placement.get_node("DownloadedCartoonPlane") as Node3D
	var label := "%dx%d" % [dims.x, dims.y]
	var progress := float(game.call("_progress_for_answer_line"))
	var original_camera := camera.global_transform
	var mesh_count := _count_meshes(imported)
	_assert(mesh_count == 22, label + " all original 22 glTF mesh parts are present")
	_assert(viewport.size == dims and camera.projection == Camera3D.PROJECTION_PERSPECTIVE,
		label + " native viewport and independent perspective camera")
	_assert((world.get_node("Sunlight") as DirectionalLight3D).shadow_enabled == false,
		label + " sunlight shadow rendering disabled for low-power GPUs")
	_assert(is_zero_approx(placement.rotation_degrees.x) and
		is_zero_approx(placement.rotation_degrees.z) and
		absf(absf(placement.rotation_degrees.y) - 180.0) < 0.01,
		label + " model nose points toward rings with wings level")
	_assert(imported.position.is_equal_approx(Vector3.ZERO), label + " glTF root not artificially moved")
	var normalized_lanes: PackedFloat32Array = game.call("_normalized_scoring_lane_centers", progress)
	_assert(normalized_lanes.size() == 3, label + " game supplies 3 real authored scoring lane positions")
	var max_errors: Array[float] = []
	for i in range(3):
		if normalized_lanes.size() != 3:
			break
		game.plane_x_norm = normalized_lanes[i]
		game.gate_progress = progress
		game.call("_sync_visuals")
		renderer.call("_process", 0.0)
		var ring := world.get_node("Gates/Gate" + LANES[i]) as Node3D
		var ring_mesh := ring.get_node("Ring") as MeshInstance3D
		var torus := ring_mesh.mesh as TorusMesh
		_assert(torus != null and ring.visible and torus.inner_radius > 0.0,
			label + " " + LANES[i] + " true visible torus at score crossing")
		if torus == null:
			continue
		var projected_pivot := camera.unproject_position(placement.global_position)
		var hole_center := camera.unproject_position(ring.global_position)
		var fuselage := _find_mesh(imported, "plane_fuselage_plane_0")
		_assert(fuselage != null, label + " " + LANES[i] + " actual fuselage mesh survives import")
		if fuselage == null:
			continue
		var fuselage_center := camera.unproject_position(fuselage.global_transform * fuselage.mesh.get_aabb().get_center())
		var pixels_per_unit := dims.y / (2.0 * tan(deg_to_rad(camera.fov) * 0.5) * float(renderer.get("airplane_camera_distance")))
		var ellipse_rx: float = torus.inner_radius * ring.scale.x * pixels_per_unit
		var ellipse_ry: float = torus.inner_radius * ring.scale.y * pixels_per_unit
		var dx := (fuselage_center.x - hole_center.x) / maxf(ellipse_rx, 0.01)
		var dy := (fuselage_center.y - hole_center.y) / maxf(ellipse_ry, 0.01)
		var norm_error := sqrt(dx * dx + dy * dy)
		max_errors.append(norm_error)
		var max_mesh_radius := _largest_mesh_radius(imported, ring.global_position,
			torus.inner_radius * ring.scale.x, torus.inner_radius * ring.scale.y)
		print("PASSAGE_GEOMETRY %s %s score_progress=%.4f camera_y=%.2f gate_y=%.2f pivot_y=%.2f fuselage_y=%.2f dx_px=%.2f dy_px=%.2f hole_radius=(%.2f,%.2f) radius_fraction=%.3f" %
			[label, LANES[i], progress, camera.global_position.y, hole_center.y,
			projected_pivot.y, fuselage_center.y, fuselage_center.x - hole_center.x,
			fuselage_center.y - hole_center.y, ellipse_rx, ellipse_ry, norm_error])
		print("PASSAGE_CLEARANCE %s %s conservative_3d_aabb_radius_fraction=%.3f" %
			[label, LANES[i], max_mesh_radius])
		_assert(norm_error < 0.22,
			label + " " + LANES[i] + " real fuselage center passes through INNER ring center (not below hole)")
		_assert(max_mesh_radius < 0.96,
			label + " " + LANES[i] + " ALL glTF mesh bounds fit inside real hollow torus, including wings")
		var span_z := _mesh_depth_span(imported)
		_assert(span_z.x < ring.global_position.z and ring.global_position.z < span_z.y,
			label + " " + LANES[i] + " torus crosses actual airplane nose/tail volume in 3D")
		_assert(absf(ring.global_position.z - placement.global_position.z) < 0.02,
			label + " " + LANES[i] + " physical ring depth crosses airplane placement at score line")
		_assert(absf(projected_pivot.x - hole_center.x) < ellipse_rx * 0.23,
			label + " " + LANES[i] + " lateral player steering aligns with selected ring")
		_assert(camera.global_transform.is_equal_approx(original_camera),
			label + " " + LANES[i] + " camera does not follow player bank or teleport")
		if i == 1 and DisplayServer.get_name() != "headless":
			await _capture(label, "crossing")
	if normalized_lanes.size() == 3:
		game.plane_x_norm = normalized_lanes[0]
		game.call("_sync_visuals")
		renderer.call("_process", 0.0)
		var start_x := anchor.global_position.x
		game.plane_x_norm = normalized_lanes[2]
		game.call("_sync_visuals")
		renderer.call("_process", 0.0)
		_assert(anchor.global_position.x > start_x + 0.05,
			label + " authentic player steering remains horizontal with model placement intact")
		_assert(placement.transform.is_equal_approx(original_placement),
			label + " editable authored local placement remains unchanged at runtime")
		if DisplayServer.get_name() != "headless":
			game.plane_x_norm = normalized_lanes[1]
			game.gate_progress = minf(progress + (1.0 - progress) * 0.24, 0.99)
			game.call("_sync_visuals")
			renderer.call("_process", 0.0)
			await _capture(label, "past")
	game.queue_free()
	await process_frame
	await process_frame


func _capture(label: String, moment: String) -> void:
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	_assert(shot != null and not shot.is_empty(), label + " actual OpenGL frame rendered " + moment)
	if "--capture" in OS.get_cmdline_user_args() and shot != null and not shot.is_empty():
		var dest := "user://human_plane_center_passage_%s_%s.png" % [label, moment]
		_assert(shot.save_png(dest) == OK, label + " captured " + moment)
		print("PASSAGE_GPU_SCREENSHOT ", ProjectSettings.globalize_path(dest))


func _find_mesh(node: Node, name: String) -> MeshInstance3D:
	if node.name == name and node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var result := _find_mesh(child, name)
		if result != null:
			return result
	return null


func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _count_meshes(child)
	return count


func _largest_mesh_radius(node: Node, hole_center: Vector3, radius_x: float, radius_y: float) -> float:
	var radius := 0.0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_node := node as MeshInstance3D
		var bounds := mesh_node.mesh.get_aabb()
		for corner in range(8):
			var world_corner := mesh_node.global_transform * bounds.get_endpoint(corner)
			var horizontal := (world_corner.x - hole_center.x) / radius_x
			var vertical := (world_corner.y - hole_center.y) / radius_y
			radius = maxf(radius, sqrt(horizontal * horizontal + vertical * vertical))
	for child in node.get_children():
		radius = maxf(radius, _largest_mesh_radius(child, hole_center, radius_x, radius_y))
	return radius


func _mesh_depth_span(node: Node) -> Vector2:
	var low := INF
	var high := -INF
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_node := node as MeshInstance3D
		var bounds := mesh_node.mesh.get_aabb()
		for corner in range(8):
			var world_corner := mesh_node.global_transform * bounds.get_endpoint(corner)
			low = minf(low, world_corner.z)
			high = maxf(high, world_corner.z)
	for child in node.get_children():
		var child_span := _mesh_depth_span(child)
		low = minf(low, child_span.x)
		high = maxf(high, child_span.y)
	return Vector2(low, high)


func _assert(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("RING CENTER FAIL: " + message)
