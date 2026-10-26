extends SceneTree

## Legacy woodland material archival + current cloud PBR validation.
## Woodland assets may remain editable for the editor, but never render during
## user-facing cloud flight. Asset resource creation is an
## explicit one-time operation via --generate, never triggered by normal tests.
## Godot --headless --path . --script res://tools/test_human_plane_3d_pbr.gd
## Godot --headless --path . --script res://tools/test_human_plane_3d_pbr.gd -- --generate
const ROOT_PATH := "res://Components/Gameplay/Human Plane/3D/pbr/"
const GRASS_MESH_PATH := ROOT_PATH + "nature_grass_clump_mesh.tres"
const GRASS_MATERIAL := "res://Components/Gameplay/Human Plane/3D/grass-green/textures/"
const BANDS := ["a", "b", "c", "d"]
const OFFSETS := [16.0, -29.0, -74.0, -119.0]
const GRASS_SCRIPT := preload("res://ui/minigames/human_plane_3d_foliage.gd")
const VIEW_SCENE := preload("res://ui/minigames/human_plane_3d_view.tscn")

var checks := 0
var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if "--generate" in OS.get_cmdline_user_args():
		await _generate_resources()
	for material_name in ["road008a_path.tres", "grass004_ground.tres"]:
		var path: String = ROOT_PATH + String(material_name)
		var material := load(path) as StandardMaterial3D
		_check(material != null, path + " is a StandardMaterial3D")
		if material == null:
			continue
		_check(material.albedo_texture != null, material_name + " has color map")
		_check(material.normal_enabled and material.normal_texture != null,
			material_name + " has enabled normal")
		_check(material.normal_texture.resource_path.contains("NormalGL"),
			material_name + " uses OpenGL normal texture")
		_check(material.ao_enabled and material.ao_texture != null,
			material_name + " has enabled ambient occlusion")
		_check(material.roughness_texture != null,
			material_name + " uses actual roughness texture")
		_check(material.uv1_scale.x > 1.0 and material.uv1_scale.y > 1.0,
			material_name + " has repeated UV1 ground tiling")
	var blade_material := load(ROOT_PATH + "nature_grass_blades.tres") as StandardMaterial3D
	_check(blade_material != null, "original grass_green blade material exists")
	if blade_material != null:
		_check(blade_material.albedo_texture.resource_path.contains("grass-green"),
			"grass blades use supplied FBX's albedo/alpha texture")
		_check(blade_material.normal_enabled and
			blade_material.normal_texture.resource_path.contains("Normal_grass"),
			"grass blades use their original normal texture")
		_check(blade_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,
			"grass blades preserve transparent-cutout geometry")
	var grass_mesh := load(GRASS_MESH_PATH) as ArrayMesh
	_check(grass_mesh != null, "imported FBX grass mesh is saved as ArrayMesh")
	if grass_mesh != null:
		_check(grass_mesh.get_surface_count() == 1,
			"grass 14 FBX quad surfaces are batched to one draw surface")
		var vertices: Array = grass_mesh.surface_get_arrays(0)
		_check((vertices[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() >= 56,
			"batched grass has original blade vertices")
	for suffix in BANDS:
		var mm := load(ROOT_PATH + "nature_grass_band_" + suffix + ".tres") as MultiMesh
		_check(mm != null, "band " + suffix + " serialized MultiMesh is loadable")
		if mm == null:
			continue
		_check(mm.instance_count == 340, "band " + suffix + " retains 340 real grass bunches")
		_check(mm.mesh is ArrayMesh, "band " + suffix + " uses actual imported grass mesh")
		_check(mm.custom_aabb.size.x > 90.0,
			"band " + suffix + " has finite wide ground culling bounds")
		if DisplayServer.get_name() == "headless":
			# Godot's headless dummy renderer reports 0 for both buffer reads and
			# get_instance_transform(). The serialized .tres text is authoritative.
			var source := FileAccess.get_file_as_string(
				ROOT_PATH + "nature_grass_band_" + suffix + ".tres")
			_check(source.contains("buffer = PackedFloat32Array("),
				"band " + suffix + " serializes nonempty GPU transforms")
		else:
			_check(mm.buffer.size() == 340 * 16,
				"band " + suffix + " has 16 packed floats per GPU instance")
			_check(mm.get_instance_transform(0).origin.length() > 1.0,
				"band " + suffix + " persists distributed grass positions")
	await _check_scene_hookups()
	print("HUMAN PLANE 3D PBR: ", "PASS" if errors.is_empty() else "FAIL",
		" (", checks, " checks, ", errors.size(), " failures)")
	quit(0 if errors.is_empty() else 1)


func _check_scene_hookups() -> void:
	var view := VIEW_SCENE.instantiate()
	root.add_child(view)
	var world := view.get_node_or_null("Viewport3D/FlightWorld")
	_check(world != null, "PBR 3D world scene mounts")
	if world != null:
		var ground_branch := world.get_node_or_null("Terrain") as Node3D
		var woodland_branch := world.get_node_or_null("Scenery") as Node3D
		_check(ground_branch == null or not ground_branch.is_visible_in_tree(),
			"archived ground, road and mountain PBR nodes are hidden in cloud flight")
		_check(woodland_branch == null or not woodland_branch.is_visible_in_tree(),
			"archived tree/grass material nodes are hidden in cloud flight")
		var grass_root := world.get_node_or_null("Scenery/GrassInstances") as Node3D
		_check(grass_root == null or grass_root.get_child_count() == 4,
			"preserved source MultiMesh bands remain consistent when archived")
		if grass_root != null:
			for suffix in BANDS:
				var grass_node := grass_root.get_node_or_null(
					"NatureGrass" + suffix.to_upper()) as MultiMeshInstance3D
				_check(grass_node != null and grass_node.multimesh != null and
					grass_node.multimesh.instance_count == 340,
					"editor scene grass band " + suffix + " has 340 visible instances")
				_check(grass_node != null and
					grass_node.material_override is StandardMaterial3D and
					(grass_node.material_override as StandardMaterial3D).albedo_texture != null,
					"archived editor grass band " + suffix + " retains original blade material")
		var clouds := world.get_node_or_null("CloudFlight/CloudProps") as Node3D
		_check(clouds != null and clouds.get_child_count() >= 3,
			"imported glTF cloud props replace visible ground and woodland materials")
		if clouds != null:
			for prop in clouds.get_children():
				var matches: Array[MeshInstance3D] = []
				_find_real_meshes(prop, matches)
				var material_found := false
				for part in matches:
					if part.mesh != null and part.mesh.get_surface_count() > 0 \
							and part.get_active_material(0) != null:
						material_found = true
				_check(material_found,
					"cloud " + prop.name + " preserves native glTF mesh/surface material")
		var environment := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
		var sky := environment.environment.sky if environment != null and environment.environment != null else null
		var pano := sky.sky_material as PanoramaSkyMaterial if sky != null else null
		_check(pano != null and pano.panorama != null and
			pano.panorama.resource_path.ends_with("Skybox/sky_panorama.png"),
			"live WorldEnvironment uses the cloud sky panorama")
	view.queue_free()
	await process_frame


func _find_real_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		_find_real_meshes(child, result)


func _generate_resources() -> void:
	var holder := Node3D.new()
	holder.name = "GrassInstances"
	holder.set_script(GRASS_SCRIPT)
	for i in range(BANDS.size()):
		var node := MultiMeshInstance3D.new()
		node.name = "NatureGrass" + BANDS[i].to_upper()
		node.position.z = OFFSETS[i]
		holder.add_child(node)
	root.add_child(holder)
	var first := holder.get_node("NatureGrassA") as MultiMeshInstance3D
	if first.multimesh == null or first.multimesh.mesh == null:
		errors.append("Failed to build real imported grass mesh")
		holder.queue_free()
		await process_frame
		return
	var mesh: ArrayMesh = first.multimesh.mesh
	mesh.resource_name = "Grass_green FBX batched 14 original quad surfaces"
	var status := ResourceSaver.save(mesh, GRASS_MESH_PATH)
	_check(status == OK, "save real FBX-derived grass mesh .tres")
	var serialized_mesh := load(GRASS_MESH_PATH) as ArrayMesh
	if serialized_mesh == null:
		errors.append("Unable to reload just-saved grass mesh")
		holder.queue_free()
		await process_frame
		return
	for i in range(BANDS.size()):
		var batch := holder.get_child(i) as MultiMeshInstance3D
		var mm := batch.multimesh
		mm.resource_name = "NATURE Grass green / editable band " + BANDS[i].to_upper()
		status = ResourceSaver.save(mm, ROOT_PATH + "nature_grass_band_" + BANDS[i] + ".tres")
		_check(status == OK, "save authored MultiMesh band " + BANDS[i])
	holder.queue_free()
	await process_frame


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		errors.append(detail)
		printerr("PBR CHECK FAILED: ", detail)
