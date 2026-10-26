extends SceneTree

## Single-authoring-scene 3D cloud-flight contract (no webcam or database).
## Godot --headless --path . --script res://tools/test_human_plane_cloud_flight.gd
const VIEW := "res://ui/minigames/human_plane_3d_view.tscn"
const GAME := "res://ui/minigames/human_plane.tscn"
const GLTF := "res://Components/Gameplay/Human Plane/3D/Skybox/StylizeClouds/scene.gltf"
const BIN := "res://Components/Gameplay/Human Plane/3D/Skybox/StylizeClouds/scene.bin"
const LICENSE := "res://Components/Gameplay/Human Plane/3D/Skybox/StylizeClouds/license.txt"
const SKY := "res://Components/Gameplay/Human Plane/3D/Skybox/sky_panorama.png"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const LANES := ["Left", "Center", "Right"]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in [VIEW, GAME, GLTF, BIN, LICENSE, SKY]:
		_check(FileAccess.file_exists(path), "User cloud asset, license, scene or PNG exists: " + path)
	var model_text := FileAccess.get_file_as_string(GLTF)
	var json: Variant = JSON.parse_string(model_text)
	_check(json is Dictionary, "Supplied stylize_clouds glTF is well-formed JSON")
	if json is Dictionary:
		_check((json.get("buffers", []) as Array).size() > 0 and
			String((json.get("buffers", []) as Array)[0].get("uri", "")) == "scene.bin",
			"Cloud glTF references preserved source binary, not a regenerated approximation")
		_check((json.get("meshes", []) as Array).size() >= 3 and
			(json.get("materials", []) as Array).size() >= 1,
			"Imported cloud includes original source geometry and material")
	var scene_text := FileAccess.get_file_as_string(VIEW)
	_check(not scene_text.is_empty(), "Main 3D .tscn source is readable")
	_check(not scene_text.contains("CloudCluster.tscn") and
		not scene_text.contains("human_plane_3d_ring.tscn"),
			"Single 3D .tscn serializes clouds and portrait portals directly, not nested PackedScenes")
	_check(scene_text.contains(GLTF),
		"All inspector-editable clouds are based on the provided imported stylize_clouds scene.gltf")
	_check(scene_text.contains("CloudProps") and scene_text.contains("CapsuleMesh") and
		scene_text.contains("MeshInstance3D"),
		"Cloud mesh and portrait portal geometry are directly inspector-editable in the authored 3D scene")
	_check(FileAccess.get_file_as_string(GAME).contains("human_plane_3d_view.tscn"),
		"Gameplay wrapper retains the one dedicated 3D scene")
	var packed := load(VIEW) as PackedScene
	_check(packed != null, "Complete inlined 3D cloud world is loadable")
	if packed == null:
		_finish()
		return
	for size in SIZES:
		await _check_world(packed, size)
	_finish()


func _check_world(scene: PackedScene, dimensions: Vector2i) -> void:
	root.size = dimensions
	root.content_scale_size = dimensions
	var view := scene.instantiate() as SubViewportContainer
	_check(view != null, "%s 3D world instantiates" % dimensions)
	if view == null:
		return
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_process(false)
	var id := str(dimensions)
	var world := view.get_node_or_null("Viewport3D/FlightWorld") as Node3D
	var camera := view.get_node_or_null("Viewport3D/FlightWorld/Camera3D") as Camera3D
	var viewport := view.get_node_or_null("Viewport3D") as SubViewport
	_check(world != null and camera != null and viewport != null and not viewport.disable_3d,
		id + " real Camera3D and SubViewport remain part of the authorable world")
	if world == null:
		view.queue_free()
		await process_frame
		return
	var env := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var lighting := env.environment if env != null else null
	var sky := lighting.sky if lighting != null else null
	var panorama := sky.sky_material as PanoramaSkyMaterial if sky != null else null
	_check(lighting != null and lighting.background_mode == Environment.BG_SKY and
		panorama != null and panorama.panorama != null and panorama.panorama.resource_path == SKY,
		id + " authored panoramic skybox remains available behind real GLTF clouds")
	for hidden in ["Terrain", "Scenery"]:
		var legacy := world.get_node_or_null(hidden) as Node3D
		_check(legacy == null or not legacy.is_visible_in_tree(),
			id + " old mountains/grass/road/forest do not render: " + hidden)
	var props := world.get_node_or_null("CloudFlight/CloudProps") as Node3D
	_check(props != null and props.is_visible_in_tree() and props.get_child_count() >= 3,
		id + " several independent model-based cloud props visible in the editor scene")
	if props != null:
		var unique: Dictionary = {}
		var authored := 0
		var original_meshes := 0
		for prop in props.get_children():
			if not (prop is Node3D):
				continue
			var node := prop as Node3D
			unique[str(node.position)] = true
			if node.owner != null:
				authored += 1
			var meshes: Array[MeshInstance3D] = []
			_collect_meshes(node, meshes)
			for mesh_node in meshes:
				if mesh_node.mesh != null and mesh_node.mesh.get_surface_count() > 0:
					var surface_material := mesh_node.get_active_material(0)
					if surface_material != null:
						original_meshes += 1
		_check(unique.size() >= 3 and authored >= 3 and original_meshes >= 3,
			id + " cloud placements are independent, serialized, with real glTF-backed mesh materials")
		if props.get_child_count() >= 2:
			var first := props.get_child(0) as Node3D
			var second := props.get_child(1) as Node3D
			var unchanged := second.transform
			first.position += Vector3(1.5, 0.0, 0.0)
			_check(second.transform.is_equal_approx(unchanged),
				id + " Godot editor transform changes to one cloud do not mutate a neighbor")
	var rig := world.get_node_or_null("PlayerRig") as Node3D
	var plane := world.get_node_or_null("PlayerRig/RedPlane") as Node3D
	_check(rig != null and rig.scale.is_equal_approx(Vector3.ONE) and plane != null,
		id + " flight rig/RedPlane hierarchy remains accessible directly")
	_check(world.get_node_or_null("PlayerRig/RedPlaneImportNormalization") == null,
		id + " 3D plane has no hidden scale normalization parent")
	if plane != null:
		var parts: Array[MeshInstance3D] = []
		_collect_meshes(plane, parts)
		_check(parts.size() >= 20 and plane.scale.length() > 150.0,
			id + " enlarged, skinned FBX airplane retains original meshes and authored scale")
	for group_name in ["CurrentRings", "UpcomingRings"]:
		var group := world.get_node_or_null(group_name) as Node3D
		_check(group != null and group.get_child_count() == 3,
			id + " all three " + group_name + " portrait portals live in one 3D scene")
		if group == null:
			continue
		for lane_id in range(LANES.size()):
			var ring := group.get_node_or_null("Gate" + LANES[lane_id]) as Node3D
			var geometry := ring.get_node_or_null("FrameLeft") as MeshInstance3D if ring != null else null
			var word := ring.get_node_or_null("WordLabel") as Label3D if ring != null else null
			_check(ring != null and ring.owner != null and geometry != null and
				geometry.mesh is CapsuleMesh and ring.has_node("WordPlaque") and word != null and
				absf(ring.position.x - (lane_id - 1) * 6.0) < 0.08,
				id + " portrait portal and WordLabel editor-owned geometry " + group_name + "/" + LANES[lane_id])
	view.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(view), id + " full cloud and portal scene tears down cleanly")


func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_collect_meshes(child, result)


func _check(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		failures.append(reason)
		printerr("CLOUD FLIGHT FAIL: ", reason)


func _finish() -> void:
	print("HUMAN PLANE INLINE GLTF CLOUD QA: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
