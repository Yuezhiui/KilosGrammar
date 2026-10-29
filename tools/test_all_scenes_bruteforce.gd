extends SceneTree

## Scene lifecycle smoke/stress test; strictly NO database sockets, camera
## calls, file dialogs being opened, or destructive backend signal handlers.
## All game scenes (including the one 2D Human Plane scene), 3 resolutions x 2 cycles,
## then routed UI tests only for safe, isolated screens.
## godot --headless --path . --script res://tools/test_all_scenes_bruteforce.gd

const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const CYCLES := 2
const SAFE_SCREENS := [
    "res://ui/secondary/results/results.tscn",
    "res://ui/tutorial/tutorial_home.tscn",
    "res://ui/secondary/leaderboard/leaderboard.tscn",
]
const REMOVED_LEADERBOARD_NODES := [
    "TransferStatusPanel", "TransferStatus", "DownloadButton",
    "MinigameFilter", "FiltersToggle", "FiltersArt", "MoreFiltersPanel", "CloseMoreFilters"
]

var checks := 0
var failures: Array[String] = []
var scene_paths: Array[String] = []
var instances := 0
var live_mounts := 0
var inspected_buttons := 0
var _base_size: Vector2i
var _base_content: Vector2i


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    _base_size = root.size
    _base_content = root.content_scale_size
    _scan("res://")
    scene_paths.sort()
    _check(scene_paths.size() >= 20,
        "All actual project PackedScenes scanned dynamically (found %d)" % scene_paths.size())
    _check("res://ui/minigames/human_plane/human_plane.tscn" in scene_paths
        and "res://ui/minigames/human_plane_3d_view.tscn" not in scene_paths,
        "One native 2D Human Plane scene replaces all obsolete 3D worlds")
    _check("res://ui/secondary/credits/credits.tscn" in scene_paths,
        "User-requested Credits scene is restored and individually editor-authorable")
    var packed: Dictionary = {}
    for path in scene_paths:
        var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
        _check(resource is PackedScene, "Scene resource parses: " + path)
        if resource is PackedScene:
            packed[path] = resource
            var scene := (resource as PackedScene).instantiate()
            _check(scene != null and scene.get_child_count() >= 0, "Scene constructs: " + path)
            if scene != null:
                _check(scene.get_script() == null or scene.get_script() is Script,
                    "Scene root script resource is linked: " + path)
                _check_scene_nodes(scene, path)
                scene.free()
    # Cycle every source scene as a deliberately unmounted, side-effect-free
    # editor-tree clone. Running arbitrary _ready() would start actual cameras,
    # audio, devices, gameplay timers, network health and destructive routing.
    for viewport in SIZES:
        root.size = viewport
        root.content_scale_size = Vector2i(1280, 720)
        for cycle in CYCLES:
            for path in scene_paths:
                var source := packed.get(path) as PackedScene
                if source == null:
                    continue
                var scene := source.instantiate()
                instances += 1
                _check(scene != null, "Brute cycle %d %s instantiates %s" % [cycle, viewport, path])
                if scene != null:
                    _check(scene.get_parent() == null,
                        "No unexpected parent during offline instantiation: " + path)
                    _validate_controls_offline(scene, path)
                    scene.free()
        await process_frame
        for path in SAFE_SCREENS:
            await _live_safe_screen(packed.get(path) as PackedScene, path, viewport)
        await _live_fake_main_menu(packed.get("res://ui/main_menu/main_menu.tscn") as PackedScene, viewport)
    root.size = _base_size
    root.content_scale_size = _base_content
    var leaked_hosts := root.find_children("BruteSceneHost", "", false, false)
    _check(leaked_hosts.is_empty(),
        "No test-spawned active screen remains after repeated unload/reload cycles")
    for reason in failures:
        printerr("ALL SCENES BRUTE QA FAIL: ", reason)
    print("ALL SCENES BRUTE QA: %s scenes=%d offline_instances=%d live_mounts=%d buttons=%d checks=%d failures=%d" % [
        "PASS" if failures.is_empty() else "FAIL", scene_paths.size(), instances, live_mounts,
        inspected_buttons, checks, failures.size()])
    quit(0 if failures.is_empty() else 1)


func _scan(folder: String) -> void:
    var dir := DirAccess.open(folder)
    if dir == null:
        _check(false, "Readable source directory " + folder)
        return
    dir.list_dir_begin()
    var name := dir.get_next()
    while not name.is_empty():
        if not name.begins_with("."):
            var path := folder.path_join(name)
            if dir.current_is_dir():
                _scan(path)
            elif name.ends_with(".tscn"):
                scene_paths.append(path)
        name = dir.get_next()
    dir.list_dir_end()


func _check_scene_nodes(scene: Node, path: String) -> void:
    _check(scene.name != "", "Scene root retains editor node name: " + path)
    if path.ends_with("ui/secondary/leaderboard.tscn"):
        for removed in REMOVED_LEADERBOARD_NODES:
            _check(scene.find_child(removed, true, false) == null,
                "Leaderboard physically removes unused control " + removed)
        for preserved in ["ImportCsvButton", "ExportCsvButton", "DeleteAllButton",
                "DeleteFirstOverlay", "DeleteFinalOverlay", "FinalCancelButton",
                "FirstCancelButton", "FirstContinueButton", "FinalDeleteButton"]:
            _check(scene.find_child(preserved, true, false) != null,
                "Leaderboard preserves active/confirmation control " + preserved)
        for method in ["set_transfer_status", "set_transfer_pending",
                "request_filtered_csv_export", "set_minigame_filter"]:
            _check(scene.has_method(method), "No removed UI breaks host callback " + method)


func _validate_controls_offline(node: Node, scene_path: String) -> void:
    if node is BaseButton:
        inspected_buttons += 1
        var button := node as BaseButton
        _check(button.get_class() != "" and not button.name.is_empty(),
            "Button class/node survives cleanup: %s/%s" % [scene_path, button.name])
        # Verify that all editor-authored image buttons decode. Native text
        # buttons with StyleBoxFlat and empty disabled art remain legal.
        if button is TextureButton:
            var tex := (button as TextureButton).texture_normal
            _check(tex != null and tex.get_size().x > 0 and tex.get_size().y > 0,
                "TextureButton image valid: %s/%s" % [scene_path, button.name])
        else:
            var skin := button.get_theme_stylebox("normal")
            if skin is StyleBoxTexture:
                var tex := (skin as StyleBoxTexture).texture
                _check(tex != null and tex.get_size().x > 0 and tex.get_size().y > 0,
                    "Button image valid: %s/%s" % [scene_path, button.name])
        if button.focus_mode == Control.FOCUS_ALL and button.visible and not button.disabled:
            _check(button.mouse_filter != Control.MOUSE_FILTER_IGNORE,
                "Focus/pointer-enabled authored button has usable mouse filter: %s/%s" % [
                    scene_path, button.name])
    for child in node.get_children():
        _validate_controls_offline(child, scene_path)


func _live_safe_screen(scene_resource: PackedScene, path: String, viewport: Vector2i) -> void:
    if scene_resource == null:
        _check(false, "Safe live screen resource exists: " + path)
        return
    var host := Control.new()
    host.name = "BruteSceneHost"
    host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_child(host)
    var scene := scene_resource.instantiate() as Control
    _check(scene != null, "Safe screen root is Control: " + path)
    if scene == null:
        host.queue_free()
        await process_frame
        return
    host.add_child(scene)
    scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    await process_frame
    if scene.has_method("set_context"):
        var context := {
            "activity": "Human Plane", "round_completed": false,
            "teacher_authorized": false, "database_connected": false,
            "leaderboard_rows": [], "student_name": "QA Student"
        }
        scene.call("set_context", context)
    await process_frame
    live_mounts += 1
    _check(scene.is_inside_tree() and scene.size.x > 0 and scene.size.y > 0,
        "Safe screen survives live _ready at %s: %s" % [viewport, path])
    _check(scene.get_viewport() == root, "Safe screen remains in isolated root viewport: " + path)
    if path.ends_with("results.tscn"):
        await _check_navigation(scene, "MainButton", "main")
        await _check_navigation(scene, "RetryButton", "student_setup")
    elif path.ends_with("tutorial_home.tscn"):
        await _check_navigation(scene, "TutorialStage/BackButton", "main")
        await _check_navigation(scene, "TutorialStage/GrammarButton", "grammar_guide")
    elif path.ends_with("leaderboard.tscn"):
        await _check_safe_leaderboard(scene)
    host.queue_free()
    await process_frame
    await process_frame
    _check(not is_instance_valid(host), "Safe live screen releases after scene close: " + path)


func _check_navigation(screen: Control, button_path: String, destination: String) -> void:
    var button := screen.get_node_or_null(button_path) as BaseButton
    # The image-led Results redesign keeps each button editor-authored under
    # ResultsStage. Unique scene names, not a root-only path, are its stable API.
    if button == null and screen.name == "Results" and button_path in ["MainButton", "RetryButton"]:
        button = screen.get_node_or_null("%" + button_path) as BaseButton
    _check(button != null, "Navigation button retained " + button_path)
    if button == null:
        return
    var routes: Array[String] = []
    if screen.has_signal("requested"):
        screen.connect("requested", func(target: String, _payload: Dictionary) -> void:
            routes.append(target))
        _check(button.focus_mode == Control.FOCUS_ALL and button.is_visible_in_tree()
            and not button.disabled, "Navigation button focusable/visible " + button_path)
        button.pressed.emit() # Locally routed only, NO Main Menu/DB host connected.
        _check(routes == [destination], "Navigation button emits expected destination " + destination)
    else:
        _check(false, "Safe screen missing navigation requested signal: " + button_path)


func _check_safe_leaderboard(board: Control) -> void:
    _check(board.has_method("set_transfer_status"), "Transfer status host method remains callable")
    var first := board.get_node_or_null("DeleteFirstOverlay") as Control
    var final := board.get_node_or_null("DeleteFinalOverlay") as Control
    var start := board.get_node_or_null("DeleteAllButton") as Button
    var advance := board.get_node_or_null("DeleteFirstOverlay/FirstContinueButton") as Button
    var first_cancel := board.get_node_or_null("DeleteFirstOverlay/FirstCancelButton") as Button
    var final_cancel := board.get_node_or_null("DeleteFinalOverlay/ConfirmPanel/FinalCancelButton") as Button
    var typed := board.get_node_or_null("DeleteFinalOverlay/ConfirmPanel/TypedConfirmationEdit") as LineEdit
    var permanent := board.get_node_or_null("DeleteFinalOverlay/ConfirmPanel/FinalDeleteButton") as Button
    _check(first != null and final != null and start != null
        and advance != null and first_cancel != null and final_cancel != null
        and typed != null and permanent != null, "Delete modal controls survive cleanup")
    if first == null or final == null or start == null or advance == null \
            or first_cancel == null or final_cancel == null or typed == null or permanent == null:
        return
    var requests: Array[String] = []
    board.database_delete_all_requested.connect(func(value: String) -> void: requests.append(value))
    _check(not first.visible and not final.visible and permanent.disabled, "Delete overlays start safely hidden")
    start.pressed.emit()
    _check(not first.visible and requests.is_empty(), "Untrusted teacher cannot begin destructive action")
    board.set_context({"teacher_authorized": true, "database_connected": true, "leaderboard_rows": []})
    start.pressed.emit()
    _check(first.visible and not final.visible, "Delete opens only first warning after test-only authorization")
    first_cancel.pressed.emit()
    _check(not first.visible and not final.visible and requests.is_empty(), "First cancel prevents destructive action")
    start.pressed.emit()
    advance.pressed.emit()
    _check(final.visible and not first.visible and permanent.disabled, "Second confirmation waits for exact phrase")
    typed.text = "DELETE ALL"
    typed.text_changed.emit(typed.text)
    _check(permanent.disabled, "Partial phrase never arms red permanent-delete button")
    # Escape is globally inert; it must never dismiss or submit a modal.
    var esc := InputEventKey.new()
    esc.keycode = KEY_ESCAPE
    esc.pressed = true
    # Exercise the actual scene's Escape input callback. In headless mode,
    # Window.push_input() can be consumed by a native AcceptDialog before this
    # mounted screen's _input; explicitly dispatch to the panel instead.
    board.call("_input", esc)
    await process_frame
    _check(not first.visible and final.visible and typed.text == "DELETE ALL"
        and permanent.disabled and requests.is_empty(),
        "Escape leaves delete modal and typed input intact, with no database signal")
    final_cancel.pressed.emit()
    _check(not final.visible and typed.text.is_empty() and permanent.disabled
        and requests.is_empty(), "Final cancel resets typed input/disabled red button")
    # No click on FinalDeleteButton is ever issued: this is a no-socket UI test.
    board.set_transfer_status("QA simulated import failed", false)
    _check(board.has_method("set_transfer_pending"), "Status API preserved without beige TransferStatusPanel")
    board.set_transfer_status("")
    _check(board.get_node_or_null("TransferStatusPanel") == null, "Beige status panel absent after status updates")


func _live_fake_main_menu(scene_resource: PackedScene, viewport: Vector2i) -> void:
    # The exact Main Menu uses an in-memory subclass from the existing
    # no-socket CSV QA suite: no PostgreSQL/HTTPRequest, intro, or title music.
    if scene_resource == null:
        _check(false, "Main Menu resource exists for simulated navigation")
        return
    var fake := load("res://tools/test_postgres_csv_delete_menu_fixture.gd") as Script
    _check(fake != null and fake.can_instantiate(),
        "No-socket Main Menu fixture is valid for safe navigation stress")
    if fake == null or not fake.can_instantiate():
        return
    var app := scene_resource.instantiate() as Control
    app.set_script(fake)
    root.add_child(app)
    await process_frame
    live_mounts += 1
    _check(app.get("database_client") != null
        and (app.get("database_client") as Node).get_child_count() == 0,
        "Main Menu launches an in-memory mock without HTTPRequest at %s" % viewport)
    for target in [
        {"node": "Tutorial", "path": "MainLayer/CenterMenu/Tutorial", "route": "tutorial_home"},
        {"node": "Leaderboard", "path": "MainLayer/LeftMenu/Leaderboard", "route": "leaderboard"},
        {"node": "Credits", "path": "MainLayer/LeftMenu/Credits", "route": "credits"},
    ]:
        var button := app.get_node_or_null(str(target["path"])) as Button
        _check(button != null and button.is_visible_in_tree() and not button.disabled
            and button.focus_mode == Control.FOCUS_ALL,
            "Main Menu %s remains keyboard-and-pointer accessible at %s" % [target["node"], viewport])
        if button == null:
            continue
        button.pressed.emit()
        await process_frame
        var routed: Control = app.get("active_panel") as Control
        _check(String(app.get("current_route")) == target["route"] and routed != null,
            "Main Menu %s button routes to %s at %s" % [
                target["node"], target["route"], viewport])
        app.call("_return_to_main")
        await process_frame
        await process_frame
        _check(String(app.get("current_route")) == "main",
            "Main Menu returns safely after %s route at %s" % [target["node"], viewport])
    app.queue_free()
    await process_frame
    await process_frame
    _check(not is_instance_valid(app), "Main Menu mock exits without leaked screen at %s" % viewport)


func _check(condition: bool, reason: String) -> void:
    checks += 1
    if not condition:
        failures.append(reason)
