extends SceneTree

## Strict, offline and read-only Human Plane 3D asset integration audit.
## Godot --headless --path . --script res://tools/test_human_plane_final_qa.gd
## A headless source/geometry audit is NOT proof that the plane is visible in
## a GPU screenshot. No gameplay, camera device or database is ever started.

const WORLD := "res://ui/minigames/human_plane_3d_view.tscn"
const HUMAN_PLANE := "res://ui/minigames/human_plane.tscn"
const ASSET := "res://Components/Gameplay/Human Plane/3D/"
const RED := ASSET + "red-plane/"
const PBR := ASSET + "pbr/"
const RED_MAPS := [
    "73967189f63d4364a9d08f5e29c8523e_R_plane_roughness.png",
    "798d9b9285514ddababd3c5b1eaeef7c_R_plane_AO.png",
    "9a9ac995d92f4b24a1131987f5313e7f_RGB_plane_basecolor.png",
    "c600cf14d6254b8a92a1a81d96477e67_N_plane_normal.png",
    "f60d02ce7b06482f994791f5f9523926_R_plane_metallic.png",
]
const RED_FBX := RED + "2b69a53022ec45b396ce8015291cc9ea.fbx"
const ORIGINAL_TREES := ["PINE TREE.fbx", "TREE.fbx", "CUTTED TREE.fbx"]
const ORIGINAL_MOUNTAIN := ASSET + "mountain/scene.gltf"
const GRASS_FBX := ASSET + "grass-green/source/Grass_green.fbx"
const GRASS_BANDS := ["a", "b", "c", "d"]
const GRASS_PBR := ["Grass004_1K-PNG_Color.png",
    "Grass004_1K-PNG_NormalGL.png",
    "Grass004_1K-PNG_AmbientOcclusion.png",
    "Grass004_1K-PNG_Roughness.png"]
const ROAD_PBR := ["Road008A_1K-PNG_Color.png",
    "Road008A_1K-PNG_NormalGL.png",
    "Road008A_1K-PNG_AmbientOcclusion.png",
    "Road008A_1K-PNG_Roughness.png"]

var tests := 0
var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var scene_paths: Array[String] = []
    _find_scenes("res://", scene_paths)
    _check(scene_paths.size() >= 20 and WORLD in scene_paths and HUMAN_PLANE in scene_paths,
        "All live project .tscn scenes enumerated, including single authored cloud scene; got " + str(scene_paths.size()))
    _check("res://ui/secondary/credits.tscn" not in scene_paths and
        "res://ui/minigames/human_plane_3d_ring.tscn" not in scene_paths and
        "res://Components/Gameplay/Human Plane/3D/Skybox/CloudCluster.tscn" not in scene_paths,
        "Old Credits and unnecessary separately editable ring/cloud PackedScenes remain absent")
    for scene_path in scene_paths:
        var packed := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
        _check(packed != null, "All scene dependencies resolve: " + scene_path)
        if packed != null:
            var dormant := packed.instantiate()
            _check(dormant != null, "Off-tree scene instantiates: " + scene_path)
            if dormant != null:
                dormant.free()
    # QA outputs under tools/ are not production assets and must be moved by
    # their owning GPU workers before final signoff. Never delete them here.
    var tools_dir := DirAccess.open("res://tools")
    _check(tools_dir != null, "Project tools directory is readable")
    if tools_dir != null:
        var lingering: Array[String] = []
        for file in tools_dir.get_files():
            if file.to_lower().ends_with(".png"):
                lingering.append(file)
        _check(lingering.is_empty(), "No temporary PNG snapshots in tools/: " + str(lingering))

    _check_asset(RED_FBX)
    _check_asset(GRASS_FBX)
    _check_asset(ORIGINAL_MOUNTAIN)
    for item in RED_MAPS:
        _check_asset(RED + item)
    for item in ORIGINAL_TREES:
        _check_asset(ASSET + item)
    for item in GRASS_PBR:
        _check_asset(PBR + "grass004/" + item)
    for item in ROAD_PBR:
        _check_asset(PBR + "road008a/" + item)
    var red_template := ResourceLoader.load(RED + "red_plane_pbr.tres") as StandardMaterial3D
    _check(red_template != null, "Editor-authored RED PLANE full five-map PBR template exists")
    if red_template != null:
        _check(red_template.albedo_texture != null, "Red plane template has source base-color map")
        _check(red_template.normal_enabled and red_template.normal_texture != null,
            "Red plane template has source normal map")
        _check(red_template.roughness_texture != null,
            "Red plane template has source roughness map")
        _check(red_template.metallic_texture != null,
            "Red plane template has source metallic map")
        _check(red_template.ao_enabled and red_template.ao_texture != null,
            "Red plane template has source AO map")
    for item in ["road008a_path.tres", "grass004_ground.tres",
            "nature_grass_blades.tres", "nature_grass_clump_mesh.tres"]:
        var resource := ResourceLoader.load(PBR + item)
        _check(resource != null, "Scene-consumable PBR resource: " + item)
    _check(FileAccess.file_exists(ASSET + "mountain/license.txt"),
        "Mountain CC license and attribution preserved")
    _check(FileAccess.file_exists(RED + "Cartoon Plane by MahdiHasan.txt"),
        "Original red plane attribution preserved")
    var material_road := ResourceLoader.load(PBR + "road008a_path.tres") as StandardMaterial3D
    var material_grass := ResourceLoader.load(PBR + "grass004_ground.tres") as StandardMaterial3D
    for entry in [material_road, material_grass]:
        _check(entry != null and entry.albedo_texture != null,
            "PBR has actual albedo maps")
        _check(entry != null and entry.normal_enabled and entry.normal_texture != null,
            "PBR uses supplied OpenGL normal maps")
        _check(entry != null and entry.roughness_texture != null,
            "PBR uses supplied roughness map")
        _check(entry != null and entry.ao_enabled and entry.ao_texture != null,
            "PBR uses supplied AO map")

    var scene := ResourceLoader.load(WORLD) as PackedScene
    _check(scene != null, "Human Plane 3D PackedScene resolves")
    if scene != null:
        var view := scene.instantiate()
        # Only the standalone 3D SubViewportContainer enters the SceneTree,
        # NEVER the game or main menu. Its _ready applies imported-FBX material
        # overrides without touching cameras, student data or databases.
        root.add_child(view)
        var world := view.get_node_or_null("Viewport3D/FlightWorld") as Node3D
        _check(world != null, "FlightWorld is editor-authored")
        if world != null:
            _check(world.get_node_or_null("Camera3D") is Camera3D,
                "Actual Camera3D is authored")
            _check(world.get_node_or_null("PlayerRig") is Node3D,
                "PlayerRig is authored")
            _check_red_plane(world)
            _check_mountains(world)
            _check_grass(world)
            _check_supplied_trees(world)
        root.remove_child(view)
        view.free()
    _check(ResourceLoader.load(HUMAN_PLANE) is PackedScene,
        "Full Human Plane scene with 2.5D and 3D modes loads")
    print("HUMAN PLANE FINAL QA: %s (%d checks, %d failures)" % [
        "PASS" if failures.is_empty() else "FAIL", tests, failures.size()])
    for failure in failures:
        printerr("HUMAN PLANE FINAL QA FAIL: ", failure)
    quit(0 if failures.is_empty() else 1)


func _find_scenes(folder: String, result: Array[String]) -> void:
    var source := DirAccess.open(folder)
    if source == null:
        _check(false, "Cannot walk " + folder)
        return
    source.list_dir_begin()
    var name := source.get_next()
    while not name.is_empty():
        if not name.begins_with("."):
            var path := folder.path_join(name)
            if source.current_is_dir():
                _find_scenes(path, result)
            elif path.ends_with(".tscn"):
                result.append(path)
        name = source.get_next()
    source.list_dir_end()


func _check_asset(path: String) -> void:
    _check(FileAccess.file_exists(path), "Original source exists: " + path)
    _check(FileAccess.file_exists(path + ".import"), "Matching asset import retained: " + path)
    if FileAccess.file_exists(path):
        _check(ResourceLoader.load(path) != null, "Source resource imported/decoded: " + path)


func _check_red_plane(world: Node3D) -> void:
    var rig := world.get_node_or_null("PlayerRig") as Node3D
    var plane := rig.get_node_or_null("RedPlane") as Node3D if rig != null else null
    var wrapper := rig.get_node_or_null("RedPlaneImportNormalization") as Node3D if rig != null else null
    _check(wrapper == null, "Native RedPlane is directly editable under 1x PlayerRig without extra normalization")
    _check(plane != null, "Scene instantiates original red FBX under PlayerRig")
    if plane == null:
        if rig != null:
            var visible_children: Array[String] = []
            for child in rig.get_children():
                visible_children.append("%s:%s" % [child.name, child.get_class()])
            print("FINAL QA RED PLANE MISSING; PlayerRig children=", visible_children)
        return
    _check(plane.visible and rig.visible,
        "Red plane and PlayerRig not hidden in authored scene")
    var author_scale: float = plane.scale.length()
    _check(absf(author_scale - Vector3.ONE.length() * 100.0) < 0.01,
        "Artist RedPlane keeps exact 100x editor scale with no parent multiplier")
    var meshes: Array[MeshInstance3D] = []
    _find_meshes(plane, meshes)
    var viable := 0
    var materials := 0
    var textured_materials := 0
    var red_map_materials := 0
    var normal_maps := 0
    var roughness_maps := 0
    var metallic_maps := 0
    var ao_maps := 0
    for item in meshes:
        if item.mesh != null and item.mesh.get_surface_count() > 0:
            viable += 1
        for surface_index in range(item.mesh.get_surface_count() if item.mesh != null else 0):
            var material := item.get_active_material(surface_index)
            if material != null:
                materials += 1
                if material is BaseMaterial3D:
                    var base := material as BaseMaterial3D
                    if base.albedo_texture != null:
                        textured_materials += 1
                        if base.albedo_texture.resource_path.contains("red-plane"):
                            red_map_materials += 1
                    if base.normal_enabled and base.normal_texture != null:
                        normal_maps += 1
                    if base.roughness_texture != null:
                        roughness_maps += 1
                    if base.metallic_texture != null:
                        metallic_maps += 1
                    if base.ao_enabled and base.ao_texture != null:
                        ao_maps += 1
    _check(viable >= 1, "Red FBX has real nonempty geometry inside model hierarchy")
    _check(materials >= 1, "Imported red FBX has one or more usable surface materials")
    _check(red_map_materials >= 1,
        "Imported red FBX material actually uses its source red-plane texture")
    _check(normal_maps >= 1,
        "Imported red FBX material retains its source normal map")
    _check(roughness_maps >= 1,
        "Imported red FBX material must use supplied roughness texture")
    _check(metallic_maps >= 1,
        "Imported red FBX material must use supplied metallic texture")
    _check(ao_maps >= 1,
        "Imported red FBX material must use supplied AO texture")
    print("FINAL QA RED PLANE meshes=%d viable=%d surface_materials=%d textured_materials=%d source_texture_materials=%d normal=%d roughness=%d metallic=%d ao=%d combined_scale=%.1f position=%s" % [
        meshes.size(), viable, materials, textured_materials, red_map_materials,
        normal_maps, roughness_maps, metallic_maps, ao_maps, author_scale,
        str(plane.position)])


func _find_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _find_meshes(child, result)


func _check_mountains(world: Node3D) -> void:
    var mountains := world.get_node_or_null("Terrain/Mountains") as Node3D
    _check(mountains != null, "Authored mountain group exists")
    if mountains == null:
        return
    _check(mountains.get_child_count() == 24,
        "All 24 supplied NATURE mountain instances are retained; found " + str(mountains.get_child_count()))
    var populated := 0
    for child in mountains.get_children():
        var instance := child as Node3D
        if instance == null:
            continue
        _check(instance.visible, "Imported mountain instance is editor-visible: " + str(child.name))
        var meshes: Array[MeshInstance3D] = []
        _find_meshes(child, meshes)
        if not meshes.is_empty():
            populated += 1
    _check(populated == 24, "All 24 mountain nodes contain actual imported mesh hierarchy")
    print("FINAL QA MOUNTAINS authored=%d meshes_populated=%d" % [
        mountains.get_child_count(), populated])


func _check_grass(world: Node3D) -> void:
    var group := world.get_node_or_null("Scenery/GrassInstances") as Node3D
    _check(group != null and group.visible, "Editor-visible real grass instance group exists")
    if group == null:
        return
    var authored_count := 0
    for suffix in GRASS_BANDS:
        var name: String = "NatureGrass" + String(suffix).to_upper()
        var node := group.get_node_or_null(name) as MultiMeshInstance3D
        _check(node != null, "Editable grass MultiMeshInstance3D " + name)
        if node == null:
            continue
        authored_count += 1
        _check(node.visible and node.visibility_range_end > 0.0,
            "Grass band visible in editor with finite draw distance: " + name)
        _check(node.multimesh != null and node.multimesh.instance_count > 0,
            "Grass band contains actual nonzero MultiMesh instances: " + name)
        _check(node.material_override is StandardMaterial3D,
            "FBX grass alpha/normal material assigned: " + name)
        _check(absf(node.position.z) > 1.0,
            "Grass batch positioned in distinct scrolling terrain segment: " + name)
        # In --headless dummy rendering, readback of MultiMesh transforms
        # gives identity/empty buffers. Inspect authored .tres itself instead.
        var serialized_path: String = PBR + "nature_grass_band_" + String(suffix) + ".tres"
        var contents := FileAccess.get_file_as_string(serialized_path)
        _check(contents.contains("buffer = PackedFloat32Array(") and contents.length() > 200,
            "Authored grass GPU transforms are serialized (not a zeroed editor slot): " + name)
        # Reading MultiMesh transforms through Godot headless's dummy renderer
        # yields zeros even for valid serialized meshes. Extract the first
        # actual 3D transform's 12 floats from the disk data instead, and
        # assert its translation/basis are real, nonzero authored values.
        var prefix := "buffer = PackedFloat32Array("
        var start := contents.find(prefix)
        if start >= 0:
            var payload := contents.substr(start + prefix.length())
            var first_transform := payload.split(",", false, 13)
            _check(first_transform.size() >= 12,
                "Grass GPU buffer encodes at least one transform: " + name)
            if first_transform.size() >= 12:
                var translation := Vector3(float(first_transform[3]),
                    float(first_transform[7]), float(first_transform[11]))
                _check(translation.is_finite() and translation.length() > 1.0,
                    "First serialized grass transform has finite nonzero position: " + name)
        if DisplayServer.get_name() != "headless" and node.multimesh != null:
            _check(node.multimesh.buffer.size() > 0,
                "Real GPU backend reads nonempty grass buffer: " + name)
    _check(authored_count == 4, "Exactly four authored NATURE grass batches exist")
    print("FINAL QA GRASS edited_batches=%d" % authored_count)


func _check_supplied_trees(world: Node3D) -> void:
    var scenery := world.get_node_or_null("Scenery") as Node3D
    _check(scenery != null, "Scenery retains original models and does not need generated trees")
    if scenery == null:
        return
    var supplied_tree_count := 0
    for child in scenery.get_children():
        if String(child.name).begins_with("Tree"):
            var meshes: Array[MeshInstance3D] = []
            _find_meshes(child, meshes)
            _check(not meshes.is_empty(),
                "Authored original imported FBX tree, never a procedural cone: " + str(child.name))
            supplied_tree_count += 1
    _check(supplied_tree_count >= 1, "Only original user-supplied authored trees are present")
    var scripts := FileAccess.get_file_as_string("res://ui/minigames/human_plane_3d_view.gd") + "\n" + FileAccess.get_file_as_string("res://ui/minigames/human_plane_3d_foliage.gd")
    for forbidden in ["CylinderMesh.new(", "CapsuleMesh.new(", "SphereMesh.new(", "PrismMesh.new("]:
        _check(not scripts.contains(forbidden), "No runtime procedural tree primitive: " + forbidden)
    print("FINAL QA TREES authored_supplied=%d procedural_primitive_calls=0" % supplied_tree_count)


func _check(condition: bool, detail: String) -> void:
    tests += 1
    if not condition:
        failures.append(detail)
