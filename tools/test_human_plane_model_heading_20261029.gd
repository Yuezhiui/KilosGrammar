extends SceneTree

## In-engine airplane heading and 720p/1080p compositing regression.
## Run with --headless for geometry/steering checks, or native OpenGL with
## -- --capture for real renderer screenshots saved outside the repository.
const GAME_SCENE := preload("res://ui/minigames/human_plane/human_plane.tscn")
const DIMENSIONS := [Vector2i(1280, 720), Vector2i(1920, 1080)]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dimensions in DIMENSIONS:
		await _check_dimensions(dimensions)
	print("HUMAN PLANE MODEL HEADING: %s checks=%d failures=%d gpu=%s" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size(), DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)


func _check_dimensions(dimensions: Vector2i) -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(dimensions)
	root.content_scale_size = dimensions
	root.size = dimensions
	var game := GAME_SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity": "Human Plane", "topic": "Noun",
		"difficulty": "Normal", "game_mode": "Seconds", "camera_live": false})
	for frame in range(3):
		await process_frame
	game.set_process(false)
	var hybrid := game.get_node("HybridFlight3D") as Node2D
	var viewport := hybrid.get_node("RenderViewport") as SubViewport
	var world := viewport.get_node("FlightWorld3D") as Node3D
	var camera := world.get_node("Camera") as Camera3D
	var anchor := world.get_node("PlaneAnchor") as Node3D
	var placement := anchor.get_node("PlaneModelPlacement") as Node3D
	var downloaded := placement.get_node("DownloadedCartoonPlane") as Node3D
	var tag := "%dx%d" % [dimensions.x, dimensions.y]
	_check(viewport.size == dimensions and camera.projection == Camera3D.PROJECTION_PERSPECTIVE,
		tag + " camera projection and native viewport match display")
	_check(_count_meshes(downloaded) == 22, tag + " original 22 GLTF meshes remain intact")
	_check(placement.position.is_equal_approx(Vector3.ZERO), tag + " pivot centered over the steering anchor")
	_check(placement.scale.is_equal_approx(Vector3.ONE), tag + " Inspector plane scale stays editable at 1")
	_check(is_zero_approx(placement.rotation_degrees.x) and is_zero_approx(placement.rotation_degrees.z)
		and absf(absf(placement.rotation_degrees.y) - 180.0) < 0.01,
		tag + " straight flight: level wings, yaw 180 from original nose-toward-camera glTF")
	_check((placement.global_basis * Vector3.BACK).normalized().dot(-camera.global_basis.z) > 0.999,
		tag + " imported aircraft nose axis now points away from camera toward the rings")
	var left_wing := _find_mesh_named(downloaded, "plane_left_wing_plane_0")
	var right_wing := _find_mesh_named(downloaded, "plane_right_wing_plane_0")
	var tail := _find_mesh_named(downloaded, "plane_tail_side_elevators_plane_0")
	var fuselage := _find_mesh_named(downloaded, "plane_fuselage_plane_0")
	_check(left_wing != null and right_wing != null and tail != null and fuselage != null,
		tag + " real wing, tail and fuselage mesh parts load with import transforms")
	if left_wing != null and right_wing != null and tail != null and fuselage != null:
		var left_center := _mesh_center_global(left_wing)
		var right_center := _mesh_center_global(right_wing)
		var tail_center := _mesh_center_global(tail)
		var body_center := _mesh_center_global(fuselage)
		_check(absf(left_center.y - right_center.y) < 0.03,
			tag + " wings remain level without roll")
		_check(absf(left_center.x + right_center.x - 2.0 * anchor.global_position.x) < 0.05,
			tag + " airplane wings are balanced left/right around the anchor")
		_check(tail_center.z > body_center.z + 0.1,
			tag + " aircraft tail is closer to camera than fuselage, so nose faces rings")
		_check(absf(body_center.x - anchor.global_position.x) < 0.06,
			tag + " fuselage is horizontally centered")
	var camera_before := camera.global_transform
	var left_anchor := anchor.global_position
	game.set_airplane_pose_active(true)
	game.set_body_x(0.8)
	for frame in range(30):
		game._update_plane_motion(1.0 / 60.0)
	game._sync_visuals()
	hybrid._process(0.0)
	var right_anchor := anchor.global_position
	_check(right_anchor.x > left_anchor.x + 0.02, tag + " real player steering changes plane X")
	_check(camera.global_transform.is_equal_approx(camera_before),
		tag + " camera stays independent and fixed during steering")
	_check(placement.position.is_equal_approx(Vector3.ZERO) and
		absf(absf(placement.rotation_degrees.y) - 180.0) < 0.01,
		tag + " renderer does not override authored plane placement")
	for lane in ["GateLeft", "GateCenter", "GateRight"]:
		var ring := world.get_node("Gates/" + lane + "/Ring") as MeshInstance3D
		_check(ring.mesh is TorusMesh and not (world.get_node("Sunlight") as DirectionalLight3D).shadow_enabled,
			tag + " original editable " + lane + " TorusMesh under shadow-disabled light")
	# Return to a centered approach composition for human visual inspection.
	game.set_body_x(0.0)
	game.plane_x_norm = 0.5
	game._sync_visuals()
	game.gate_progress = 0.55
	game._sync_visuals()
	hybrid._process(0.0)
	if DisplayServer.get_name() != "headless":
		for frame in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		_check(shot != null and not shot.is_empty() and shot.get_width() == dimensions.x and shot.get_height() == dimensions.y,
			tag + " native OpenGL rendered actual frame at requested size")
		if "--capture" in OS.get_cmdline_user_args() and shot != null and not shot.is_empty():
			var dest := "user://human_plane_model_heading_%dx%d.png" % [dimensions.x, dimensions.y]
			_check(shot.save_png(dest) == OK, tag + " saved native GPU screenshot")
			print("MODEL_HEADING_SCREENSHOT ", ProjectSettings.globalize_path(dest))
	game.queue_free()
	await process_frame
	await process_frame


func _find_mesh_named(node: Node, wanted: String) -> MeshInstance3D:
	if node.name == wanted and node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var mesh := _find_mesh_named(child, wanted)
		if mesh != null:
			return mesh
	return null


func _mesh_center_global(mesh_node: MeshInstance3D) -> Vector3:
	return mesh_node.global_transform * mesh_node.mesh.get_aabb().get_center()


func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D and (node as MeshInstance3D).mesh != null else 0
	for child in node.get_children():
		count += _count_meshes(child)
	return count


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("MODEL HEADING FAIL: " + label)
