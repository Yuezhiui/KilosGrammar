extends SceneTree

## Read-only projectwide asset integrity regression.
## Godot 4.7.2 --headless --path . --script res://tools/test_projectwide_orphan_integrity.gd
## Does not add scenes to the root or run _ready() (no camera, YOLO or DB).
## Lists suspicious candidates without deleting originals or import caches.

const IMAGE_SUFFIXES := [".png", ".jpg", ".jpeg", ".webp", ".svg"]
const OTHER_IMPORT_SUFFIXES := [".mp3", ".ogg", ".wav", ".ttf", ".otf"]
const TEXT_SUFFIXES := [".gd", ".tscn", ".tres", ".gltf", ".gdshader"]

var all_paths: Array[String] = []
var scene_paths: Array[String] = []
var resource_paths: Array[String] = []
var checked_imports := 0
var checked_uids := 0
var checked_scripts := 0
var checked_literals := 0
var checked_model_textures := 0
var checked_model_buffers := 0
var checks := 0
var failures: Array[String] = []
var uncertain_dynamic: Dictionary = {}
var seen_import_uids: Dictionary = {}


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    _walk("res://")
    all_paths.sort()
    var existence: Dictionary = {}
    for path in all_paths:
        existence[path] = true
    for path in all_paths:
        if path.ends_with(".import"):
            checked_imports += 1
            _check(existence.has(path.trim_suffix(".import")), "Stale import sidecar: " + path)
            _check_import_uid(path)
        elif path.ends_with(".uid"):
            checked_uids += 1
            _check(existence.has(path.trim_suffix(".uid")), "Stale script UID: " + path)
        elif _is_imported_asset(path):
            _check(existence.has(path + ".import"), "Missing source asset .import: " + path)
        if path.ends_with(".tscn"):
            scene_paths.append(path)
        elif path.ends_with(".tres"):
            resource_paths.append(path)
        elif path.ends_with(".gd") and _is_relevant_text(path):
            checked_scripts += 1
            var script_resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
            # Godot can return a Script object even after logging a parser
            # error; can_instantiate() distinguishes that from a valid class.
            _check(script_resource is Script and (script_resource as Script).can_instantiate(),
                "Failed production script parse: " + path)
        if _is_relevant_text(path):
            var source := FileAccess.get_file_as_string(path)
            _check(not source.is_empty(), "Cannot read source: " + path)
            if path.ends_with(".gltf"):
                _check_gltf(path, source, existence)
            else:
                _check_literals(path, source, existence)
    for scene_path in scene_paths:
        var loaded := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
        _check(loaded != null, "Failed scene load: " + scene_path)
        if loaded == null:
            continue
        var instance := loaded.instantiate()
        _check(instance != null, "Failed offline instantiate: " + scene_path)
        if instance != null:
            instance.free()  # Never enter SceneTree. _ready may open a camera/DB.
    for resource_path in resource_paths:
        var loaded := ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
        _check(loaded != null, "Failed serialized resource load: " + resource_path)
    _check(scene_paths.size() >= 20,
        "All project scenes discovered with optional inlined 3D cloud and ring geometry: " + str(scene_paths.size()))
    _check("res://ui/minigames/human_plane_3d_view.tscn" in scene_paths,
        "Authorable Human Plane world remains a real PackedScene")
    _check("res://ui/secondary/credits.tscn" in scene_paths,
        "Restored Credits is a valid source scene with dependencies")
    _check(checked_imports > 100, "Too few image/font/audio import sidecars: " + str(checked_imports))
    _check(checked_model_textures > 0, "No relative glTF textures checked")
    _check(checked_model_buffers > 0, "No relative glTF binary buffers checked")
    print("PROJECTWIDE ORPHAN QA files=%d scenes=%d tres=%d scripts=%d imports=%d uids=%d literals=%d gltf_textures=%d gltf_buffers=%d dynamic_paths=%d checks=%d failures=%d" % [
        all_paths.size(), scene_paths.size(), resource_paths.size(),
        checked_scripts, checked_imports, checked_uids, checked_literals, checked_model_textures,
        checked_model_buffers, uncertain_dynamic.size(), checks, failures.size()])
    var unresolved: Array = uncertain_dynamic.keys()
    unresolved.sort()
    for path in unresolved:
        print("PROJECTWIDE QA DYNAMIC (retained): ", path)
    for failure in failures:
        printerr("PROJECTWIDE QA FAILURE: ", failure)
    print("PROJECTWIDE ORPHAN INTEGRITY: ", "PASS" if failures.is_empty() else "FAIL")
    quit(0 if failures.is_empty() else 1)


func _walk(folder: String) -> void:
    var directory := DirAccess.open(folder)
    if directory == null:
        _check(false, "Directory cannot be read: " + folder)
        return
    directory.list_dir_begin()
    var name := directory.get_next()
    while not name.is_empty():
        if not name.begins_with("."):
            var path := folder.path_join(name)
            if directory.current_is_dir():
                _walk(path)
            else:
                all_paths.append(path)
        name = directory.get_next()
    directory.list_dir_end()


func _is_imported_asset(path: String) -> bool:
    # Temporary capture images are review artifacts, not sources that the
    # engine must import. Do not require their ephemeral import metadata.
    if path.begins_with("res://tools/") and (
        path.get_file().begins_with("_tmp_")
        or path.get_file().begins_with("_qa_")
        or path.get_file().begins_with("qa_")
        or path.get_file().begins_with("_review_")
    ):
        return false
    var lower := path.to_lower()
    for suffix in IMAGE_SUFFIXES + OTHER_IMPORT_SUFFIXES:
        if lower.ends_with(suffix):
            return true
    return false


func _is_relevant_text(path: String) -> bool:
    if path.begins_with("res://showcase/") or path.begins_with("res://docs/"):
        return false
    if path.begins_with("res://tools/") and not path.ends_with(".gltf"):
        return false
    # QA scripts contain optional screenshot *output* paths, which do not
    # have to exist until that test explicitly saves its image.
    if path.get_file().begins_with("test_"):
        return false
    var lower := path.to_lower()
    for extension in TEXT_SUFFIXES:
        if lower.ends_with(extension):
            return true
    return false


func _check_import_uid(path: String) -> void:
    var contents := FileAccess.get_file_as_string(path)
    _check(not contents.is_empty(), "Unreadable/empty import sidecar: " + path)
    var uid_marker := "uid=\""
    var start := contents.find(uid_marker)
    if start < 0:
        return  # Some imported Godot sources do not require stable UIDs.
    start += uid_marker.length()
    var ending := contents.find("\"", start)
    if ending < 0:
        _check(false, "Broken import UID: " + path)
        return
    var uid := contents.substr(start, ending - start)
    _check(uid.begins_with("uid://"), "Malformed resource UID in " + path)
    if seen_import_uids.has(uid):
        _check(false, "Duplicated image import UID " + uid + " in " + path + " and " + String(seen_import_uids[uid]))
    else:
        seen_import_uids[uid] = path


func _check_literals(owner: String, source: String, existence: Dictionary) -> void:
    var matcher := RegEx.new()
    # Path-only literals, including filenames containing spaces; "%s" means
    # runtime composition and stays an explicit retain/uncertain candidate.
    if matcher.compile('res://[^"\'\r\n]+') != OK:
        _check(false, "Unable to compile resource path scanner")
        return
    for found in matcher.search_all(source):
        var candidate := found.get_string()
        if candidate.contains("%") or candidate.contains("{") or candidate.contains("}") or candidate.contains("$") or candidate.contains("..."):
            uncertain_dynamic[candidate] = true
            continue
        # This optional soundtrack is intentionally local-only (commercial audio).
        if candidate == "res://assets/audio/user_provided/wii_fit_user_settings.mp3":
            continue
        if candidate.ends_with("/") or candidate.get_extension().is_empty():
            continue
        checked_literals += 1
        if not existence.has(candidate) and not ResourceLoader.exists(candidate):
            _check(false, "Missing literal " + owner + " -> " + candidate)


func _check_gltf(owner: String, source: String, existence: Dictionary) -> void:
    var parsed: Variant = JSON.parse_string(source)
    _check(parsed is Dictionary, "glTF JSON parse: " + owner)
    if not parsed is Dictionary:
        return
    var images: Variant = parsed.get("images", [])
    var buffers: Variant = parsed.get("buffers", [])
    for item in images if images is Array else []:
        if not item is Dictionary:
            continue
        var uri := String(item.get("uri", ""))
        if uri.is_empty() or uri.begins_with("data:") or uri.contains("://"):
            continue
        var expected := owner.get_base_dir().path_join(uri).simplify_path()
        checked_model_textures += 1
        _check(existence.has(expected), "Model texture missing: " + owner + " -> " + expected)
    for buffer in buffers if buffers is Array else []:
        if not buffer is Dictionary:
            continue
        var uri := String(buffer.get("uri", ""))
        if uri.is_empty() or uri.begins_with("data:") or uri.contains("://"):
            continue
        var expected := owner.get_base_dir().path_join(uri).simplify_path()
        checked_model_buffers += 1
        _check(existence.has(expected), "Model binary buffer missing: " + owner + " -> " + expected)


func _check(ok: bool, what: String) -> void:
    checks += 1
    if not ok:
        failures.append(what)
