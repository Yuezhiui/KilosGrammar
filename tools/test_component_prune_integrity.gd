extends SceneTree

## Read-only Components inventory and all-scene integrity after artist-led
## orphan pruning. NEVER delete files, mount game scenes, connect cameras/DB,
## write gameplay data or interpret an orphan candidate as automatic deletion.
## Godot --headless --path . --script res://tools/test_component_prune_integrity.gd
const COMPONENTS := "res://Components/"
const DATA_EXTENSIONS := [".tscn", ".tres", ".gd", ".godot", ".cfg", ".json", ".cs", ".py", ".gdshader", ".gltf"]
const RESOURCE_SUFFIXES := [
    ".png", ".jpg", ".jpeg", ".webp", ".svg", ".fbx", ".gltf", ".bin",
    ".tscn", ".tres", ".gd", ".gdshader", ".ogg", ".mp3",
    ".wav", ".ttf", ".otf", ".json", ".csv",
]

var checks := 0
var failures: Array[String] = []
var files: Array[String] = []
var scene_paths: Array[String] = []
var components_pngs: Array[String] = []
var referenced: Dictionary = {}
var dynamic_candidates: Array[String] = []
var orphan_candidates: Array[String] = []
var missing_refs: Dictionary = {}
var manifest_orphans: Array[String] = []
var suspicious_identifiers: Array[String] = []
var components_by_folder: Dictionary = {}
var candidate_by_folder: Dictionary = {}
var _direct_paths: Dictionary = {}
var _asset_name_refs: Dictionary = {}
var _dynamic_roots: Dictionary = {}
var _scan_count := 0
var _rendered := 0
var _texture_decodes := 0
var _serialized_dependencies := 0
var _plain_literal_refs := 0
var _pruned_while_running := 0


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    _walk("res://")
    files.sort()
    for path in files:
        if path.ends_with(".tscn"):
            scene_paths.append(path)
        if path.begins_with(COMPONENTS) and path.to_lower().ends_with(".png"):
            components_pngs.append(path)
        if path.begins_with(COMPONENTS) and path.ends_with(".png.import"):
            var png_source := path.trim_suffix(".import")
            if not FileAccess.file_exists(png_source):
                manifest_orphans.append(path)
                _fail("Stale .png.import sidecar without source PNG: " + path)
    _check(scene_paths.size() >= 20,
        "All current project scenes dynamically inventoried after 2D restoration (found %d)" % scene_paths.size())
    _check("res://ui/minigames/human_plane/human_plane.tscn" in scene_paths
        and "res://ui/minigames/human_plane_3d_view.tscn" not in scene_paths,
        "Human Plane retains one editable pure-2D PackedScene without a 3D world")
    _check("res://ui/secondary/credits/credits.tscn" in scene_paths,
        "Credits scene restored by explicit user request and kept in inventory")
    _check(not components_pngs.is_empty(),
        "Components contains independently stored and browsable source PNGs")

    # Audit only production text as retention evidence. Prior tests, docs,
    # generated reports and reference images do NOT make a PNG a runtime asset.
    for path in files:
        if not _is_production_text(path):
            continue
        var source := FileAccess.get_file_as_string(path)
        if source.is_empty():
            _fail("Empty production source: " + path)
            continue
        _scan_count += 1
        _inspect_explicit_resource_paths(path, source)
        if path.ends_with(".gltf"):
            _inspect_gltf_images(path, source)
        if path.ends_with(".tscn") or path.ends_with(".tres"):
            _inspect_serialized(path, source)

    for scene_path in scene_paths:
        # Instantiation is OFF-TREE: loading arbitrary _ready() could launch a
        # real camera, audio backend, server request or database action.
        var packed := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
        _check(packed != null, "PackedScene loads without broken dependency: " + scene_path)
        if packed == null:
            continue
        var instance := packed.instantiate()
        _check(instance != null, "Scene creates an offline tree: " + scene_path)
        if instance == null:
            continue
        _audit_scene_art(instance, scene_path)
        instance.free()

    for asset_path in components_pngs:
        # Another worker can prune an orphan during this read-only QA run.
        # Recheck sources from the inventory before asking Godot to load them.
        if not FileAccess.file_exists(asset_path):
            _pruned_while_running += 1
            continue
        var folder := _folder_key(asset_path)
        components_by_folder[folder] = int(components_by_folder.get(folder, 0)) + 1
        var asset := ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
        _check(asset != null, "Components source image is importable: " + asset_path)
        if asset != null:
            _texture_decodes += 1
            _check(asset.get_size().x > 0 and asset.get_size().y > 0,
                "Components PNG has nonzero dimensions: " + asset_path)
        if _direct_paths.has(asset_path):
            referenced[asset_path] = true
        elif _has_possible_dynamic_usage(asset_path):
            dynamic_candidates.append(asset_path)
        else:
            orphan_candidates.append(asset_path)
            candidate_by_folder[folder] = int(candidate_by_folder.get(folder, 0)) + 1

    # Orphans are candidates only, never proof of safe deletion: resource paths
    # can be composed at runtime from directory listings and filenames.
    orphan_candidates.sort()
    dynamic_candidates.sort()
    _check(missing_refs.is_empty(),
        "No missing literal res:// resource paths (found %d)" % missing_refs.size())
    _check(manifest_orphans.is_empty(),
        "No orphaned Components .png.import sidecars (found %d)" % manifest_orphans.size())
    _check(suspicious_identifiers.is_empty(),
        "No unresolved serialized ExtResource/SubResource IDs (found %d)" % suspicious_identifiers.size())
    _check(_rendered > 0 and _texture_decodes > 0,
        "PNG-backed UI verified, with %d renderable controls and %d PNG decodes" % [
            _rendered, _texture_decodes])
    print("COMPONENT AUDIT SUMMARY scenes=%d pngs=%d direct=%d maybe_dynamic=%d orphan_candidates=%d serialized_deps=%d literal_deps=%d renderables=%d changed_during_scan=%d checked=%d failures=%d" % [
        scene_paths.size(), components_pngs.size(), referenced.size(),
        dynamic_candidates.size(), orphan_candidates.size(), _serialized_dependencies,
        _plain_literal_refs, _rendered, _pruned_while_running, checks, failures.size()])
    print("COMPONENT AUDIT INVENTORY BY FOLDER ", JSON.stringify(components_by_folder))
    print("COMPONENT AUDIT CANDIDATES BY FOLDER ", JSON.stringify(candidate_by_folder))
    print("COMPONENT AUDIT MISSING ", JSON.stringify(missing_refs.keys()))
    print("COMPONENT AUDIT SERIALIZED IDS ", JSON.stringify(suspicious_identifiers))
    print("COMPONENT AUDIT ORPHAN IMPORTS ", JSON.stringify(manifest_orphans))
    # Print all potential orphans with exact paths for human cross-check by
    # the prime and the pruning workers. No mutation is authorized here.
    for candidate in orphan_candidates:
        print("COMPONENT AUDIT CANDIDATE ", candidate)
    for uncertain in dynamic_candidates:
        print("COMPONENT AUDIT DYNAMIC/NAME ", uncertain)
    for failure in failures:
        printerr("COMPONENT AUDIT FAIL: ", failure)
    print("COMPONENT PRUNE INTEGRITY: %s (%d checks, %d failures)" % [
        "PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
    quit(0 if failures.is_empty() else 1)


func _walk(folder: String) -> void:
    var directory := DirAccess.open(folder)
    if directory == null:
        _fail("Cannot open project resource directory: " + folder)
        return
    directory.list_dir_begin()
    var filename := directory.get_next()
    while not filename.is_empty():
        if not filename.begins_with("."):
            var path := folder.path_join(filename)
            if directory.current_is_dir():
                _walk(path)
            else:
                files.append(path)
        filename = directory.get_next()
    directory.list_dir_end()


func _is_production_text(path: String) -> bool:
    # Scripts under tools/ are QA/build pipelines, not production references.
    # Also ignore source text inside documentation and archived references.
    if path.begins_with("res://tools/") or path.begins_with("res://docs/") \
        or path.begins_with("res://showcase/"):
        return false
    if path.get_file().begins_with("test_"):
        return false
    # Historical extraction inventories are provenance records, not runtime
    # loads; pruning their 105 extracted variants should not be blocked.
    if path.ends_with("phase3_manifest.json") or path.ends_with("asset_manifest.json"):
        return false
    if path.ends_with(".tscn") or path.ends_with(".tres"):
        return true
    for ext in DATA_EXTENSIONS:
        if path.ends_with(ext):
            return true
    return false


func _inspect_explicit_resource_paths(owner: String, source: String) -> void:
    var literal := RegEx.new()
    literal.compile("res://[^\\\"'\\r\\n]+")
    for match_item in literal.search_all(source):
        var text_path := match_item.get_string()
        # Templates like "res://foo/%s.png" are dynamic. Treat as uncertain
        # rather than an invented missing resource.
        if text_path.contains("%") or text_path.contains("{") or text_path.contains("$") \
            or text_path.contains("..."):
            continue
        # Optional licensed soundtrack is local-only and deliberately ignored by Git.
        if text_path == "res://assets/audio/user_provided/wii_fit_user_settings.mp3":
            continue
        var lower := text_path.to_lower()
        var resource_literal := false
        for ext in RESOURCE_SUFFIXES:
            if lower.ends_with(ext):
                resource_literal = true
                break
        if resource_literal:
            _plain_literal_refs += 1
            _direct_paths[text_path] = true
            if not FileAccess.file_exists(text_path) and not ResourceLoader.exists(text_path):
                missing_refs[owner + " -> " + text_path] = true
                _fail("Missing literal resource " + owner + " -> " + text_path)
        elif text_path.begins_with(COMPONENTS) and text_path.ends_with("/"):
            _dynamic_roots[text_path] = true
        # Bare file names and path_join() arguments can denote runtime assets.
    var bare_names := RegEx.new()
    bare_names.compile("[A-Za-z0-9_][^\\\"'\\r\\n/]*\\.png")
    for item in bare_names.search_all(source):
        _asset_name_refs[item.get_string().to_lower()] = true


func _inspect_gltf_images(owner: String, source: String) -> void:
    # glTF references image files relative to its own directory, not via a
    # literal res:// URL. The metallic/normal PBR PNGs are genuine dependencies
    # of the Toy Plane model; never classify them as unused art.
    var parsed: Variant = JSON.parse_string(source)
    _check(parsed is Dictionary, "3D glTF JSON loads for image dependency audit: " + owner)
    if not parsed is Dictionary:
        return
    for image_data in (parsed as Dictionary).get("images", []):
        if not image_data is Dictionary:
            continue
        var uri := String((image_data as Dictionary).get("uri", ""))
        if uri.is_empty() or uri.begins_with("data:") or uri.contains("://"):
            continue
        var resolved := owner.get_base_dir().path_join(uri).simplify_path()
        _direct_paths[resolved] = true
        _check(FileAccess.file_exists(resolved),
            "3D glTF texture is retained with local source file: " + resolved)


func _inspect_serialized(owner: String, source: String) -> void:
    var external_ids: Dictionary = {}
    var sub_ids: Dictionary = {}
    for line in source.split("\n"):
        if line.begins_with("[ext_resource "):
            var id := _match_group(line, '(?:^|\\s)id="([^"]+)"')
            var target := _match_group(line, 'path="([^"]+)"')
            if id.is_empty():
                suspicious_identifiers.append(owner + " -> ext_resource missing ID")
            elif external_ids.has(id):
                suspicious_identifiers.append(owner + " -> duplicate ExtResource " + id)
            else:
                external_ids[id] = true
            if target.begins_with("res://"):
                _serialized_dependencies += 1
                _direct_paths[target] = true
                if not FileAccess.file_exists(target) and not ResourceLoader.exists(target):
                    missing_refs[owner + " -> " + target] = true
                    _fail("Unresolved ext_resource path " + owner + " -> " + target)
            else:
                suspicious_identifiers.append(owner + " -> ext_resource missing path " + id)
        elif line.begins_with("[sub_resource "):
            var id := _match_group(line, '(?:^|\\s)id="([^"]+)"')
            if id.is_empty() or sub_ids.has(id):
                suspicious_identifiers.append(owner + " -> duplicate or empty SubResource " + id)
            sub_ids[id] = true
    for id in _groups(source, 'ExtResource\\("([^"]+)"\\)'):
        if not external_ids.has(id):
            suspicious_identifiers.append(owner + " -> unknown ExtResource " + id)
    for id in _groups(source, 'SubResource\\("([^"]+)"\\)'):
        if not sub_ids.has(id):
            suspicious_identifiers.append(owner + " -> unknown SubResource " + id)


func _audit_scene_art(scene: Node, scene_path: String) -> void:
    for node in scene.find_children("*", "TextureRect", true, false):
        _inspect_texture((node as TextureRect).texture, scene_path + " -> " + str(node.name))
    for node in scene.find_children("*", "NinePatchRect", true, false):
        _inspect_texture((node as NinePatchRect).texture, scene_path + " -> " + str(node.name))
    for node in scene.find_children("*", "BaseButton", true, false):
        var button := node as BaseButton
        for state in ["normal", "hover", "pressed", "disabled", "focus"]:
            var style := button.get_theme_stylebox(state)
            if style is StyleBoxTexture:
                _inspect_texture((style as StyleBoxTexture).texture,
                    scene_path + " -> " + str(node.name) + ":" + state)
    _inspect_scene_root_art(scene, scene_path)


func _inspect_scene_root_art(scene: Node, scene_path: String) -> void:
    if scene is TextureRect:
        _inspect_texture((scene as TextureRect).texture, scene_path + " root")
    elif scene is NinePatchRect:
        _inspect_texture((scene as NinePatchRect).texture, scene_path + " root")


func _inspect_texture(texture: Texture2D, source: String) -> void:
    if texture == null:
        return
    var current := texture
    if current is AtlasTexture:
        current = (current as AtlasTexture).atlas
    _check(current != null and current.get_size().x > 0 and current.get_size().y > 0,
        "PNG-backed UI/control texture has nonzero size: " + source)
    if current == null:
        return
    _rendered += 1
    var source_path := current.resource_path
    if source_path.begins_with("res://"):
        _direct_paths[source_path] = true
        _check(FileAccess.file_exists(source_path) or ResourceLoader.exists(source_path),
            "PNG-backed UI source still exists: " + source_path)


func _has_possible_dynamic_usage(asset_path: String) -> bool:
    var lowercase_path := asset_path.to_lower()
    for folder in _dynamic_roots:
        if lowercase_path.begins_with(String(folder).to_lower()):
            return true
    return _asset_name_refs.has(asset_path.get_file().to_lower())


func _folder_key(path: String) -> String:
    var relative := path.trim_prefix(COMPONENTS)
    return relative.get_base_dir()


func _match_group(source: String, pattern: String) -> String:
    var regex := RegEx.new()
    if regex.compile(pattern) != OK:
        return ""
    var result := regex.search(source)
    return result.get_string(1) if result != null else ""


func _groups(source: String, pattern: String) -> Array[String]:
    var regex := RegEx.new()
    var result: Array[String] = []
    if regex.compile(pattern) != OK:
        return result
    for item in regex.search_all(source):
        result.append(item.get_string(1))
    return result


func _check(accepted: bool, description: String) -> void:
    checks += 1
    if not accepted:
        failures.append(description)


func _fail(description: String) -> void:
    _check(false, description)
