extends SceneTree

## Isolated QA for the global BaseButton hover autoload. No database, camera,
## user preferences, student records, or production files are modified.
## godot --headless --path . --script res://tools/test_global_button_hover.gd
## godot --rendering-driver opengl3 --path . --script res://tools/test_global_button_hover.gd
const AUTOLOAD_SCRIPT := "res://ui/shared/global_button_hover.gd"
const LEADERBOARD := "res://ui/secondary/leaderboard.tscn"
const SETTINGS := "res://ui/secondary/settings.tscn"
const MAIN_SCENE := "res://main_menu.tscn"
const MOCK_MENU_SCRIPT := "res://tools/test_postgres_csv_delete_menu_fixture.gd"
const SAFE_SCENES := [
    ["res://ui/tutorial/tutorial_home.tscn", "StartButton"],
    ["res://ui/play/pause.tscn", "ResumeButton"],
    [LEADERBOARD, "ExportCsvButton"],
]

var failures: Array[String] = []
var checks := 0
var hover_router: Node


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    root.size = Vector2i(1280, 720)
    root.content_scale_size = Vector2i(1280, 720)
    await process_frame
    hover_router = _find_hover_router()
    _check(hover_router != null and hover_router.is_inside_tree(),
        "Global hover handler is registered as one live autoload")
    if hover_router == null:
        await _finish()
        return
    _audit_authored_scenes()
    await _test_live_button_state()
    await _test_reparent_and_scene_transition()
    await _test_existing_scenes()
    await _test_hover_during_paused_game()
    await _test_leaderboard_selected_art()
    await _test_settings_no_double_animation()
    await _test_main_menu_no_double_animation()
    await _finish()


func _find_hover_router() -> Node:
    var count := 0
    var found: Node
    for node in root.get_children():
        var script := node.get_script() as Script
        if script != null and script.resource_path == AUTOLOAD_SCRIPT:
            count += 1
            found = node
    _check(count == 1, "Exactly one global autoload script handles hover")
    return found


func _audit_authored_scenes() -> void:
    ## Read only .tscn source. Scenes with camera/vision/gameplay controls are
    ## audited structurally, not launched (which could access real equipment).
    var scenes: Array[String] = []
    _scan_tscn("res://", scenes)
    var pattern := RegEx.new()
    _check(pattern.compile('\\[node[^\\n]*type="(Button|TextureButton|CheckButton|CheckBox|OptionButton|MenuButton|LinkButton|BaseButton)"') == OK,
        "Scene-file BaseButton type matcher compiles")
    var count := 0
    var catalog: Dictionary = {}
    for path in scenes:
        var scene_text := FileAccess.get_file_as_string(path)
        for match_result in pattern.search_all(scene_text):
            count += 1
            var kind := match_result.get_string(1)
            catalog[kind] = int(catalog.get(kind, 0)) + 1
    _check(scenes.size() >= 20, "Audited all project .tscn files, including camera/vision and minigame screens")
    _check(count >= 65, "Project contains at least 65 authored BaseButton nodes under global watcher")
    for type_name in ["Button", "OptionButton", "CheckButton"]:
        _check(int(catalog.get(type_name, 0)) > 0,
            "Scene-wide audit includes native " + type_name + " controls")
    print("GLOBAL HOVER SCENE AUDIT: %d scenes, %d authored BaseButtons, types=%s" %
        [scenes.size(), count, str(catalog)])


func _scan_tscn(directory: String, results: Array[String]) -> void:
    var folder := DirAccess.open(directory)
    if folder == null:
        return
    folder.list_dir_begin()
    var entry := folder.get_next()
    while not entry.is_empty():
        if folder.current_is_dir():
            if entry not in [".", "..", ".godot", ".git"]:
                _scan_tscn(directory.path_join(entry), results)
        elif entry.ends_with(".tscn"):
            results.append(directory.path_join(entry))
        entry = folder.get_next()
    folder.list_dir_end()


func _test_live_button_state() -> void:
    var host := Control.new()
    host.name = "HoverQASyntheticScene"
    host.size = Vector2(1280, 720)
    host.mouse_filter = Control.MOUSE_FILTER_PASS
    root.add_child(host)

    var target := Button.new()
    target.name = "InteractiveHoverTarget"
    target.position = Vector2(135, 115)
    target.size = Vector2(190, 65)
    target.focus_mode = Control.FOCUS_ALL
    host.add_child(target)
    await process_frame
    await process_frame
    var home_scale: Vector2 = target.scale
    var home_rotation: float = target.rotation
    var home_z: int = target.z_index
    var home_pivot: Vector2 = target.pivot_offset
    var home_rect: Rect2 = target.get_rect()
    _check(_global_signal_count(target, "mouse_entered") == 1,
        "Newly inserted BaseButton receives exactly one global hover listener")
    _check(_global_signal_count(target, "mouse_exited") == 1,
        "Newly inserted BaseButton receives exactly one global exit listener")
    _check(_global_signal_count(target, "button_down") == 1,
        "Newly inserted BaseButton receives exactly one global press listener")
    _check(_global_signal_count(target, "button_up") == 1,
        "Newly inserted BaseButton receives exactly one global release listener")
    _check(target.pivot_offset.is_equal_approx(home_pivot),
        "Idle button keeps its scene-authored pivot; global hover must not shift responsive layout")

    _move_to(Vector2(8, 9))
    await process_frame
    _move_to(target.get_global_rect().get_center())
    await create_timer(0.27).timeout
    _check(target.pivot_offset.is_equal_approx(target.size * 0.5),
        "ACTIVE hover temporarily centers pivot for symmetrical scaling")
    _check(target.scale.x > home_scale.x + 0.01 and target.scale.x < home_scale.x * 1.23
        and target.scale.y > home_scale.y + 0.01,
        "Real viewport mouse-enter triggers bounded Main Menu-style enlargement")
    _check(target.z_index >= home_z, "Hovered button retains or increases visual draw order")
    _mouse_button(target.get_global_rect().get_center(), true)
    await create_timer(0.09).timeout
    _check(target.scale.x < home_scale.x * 1.02,
        "Real mouse-button-down squashes rather than compounds hover scale")
    _mouse_button(target.get_global_rect().get_center(), false)
    await create_timer(0.19).timeout
    _move_to(Vector2(8, 9))
    await create_timer(0.46).timeout
    _check(target.scale.is_equal_approx(home_scale),
        "Hover exit restores ORIGINAL button scale after pointer press/release")
    _check(is_equal_approx(target.rotation, home_rotation),
        "Hover exit restores exact authored button angle")
    _check(target.z_index == home_z, "Hover exit restores original draw order")
    _check(target.pivot_offset.is_equal_approx(home_pivot),
        "Hover exit restores original pivot after layout-compensated animation")
    _check(target.get_rect().is_equal_approx(home_rect),
        "Hover/press does not rewrite drag-and-drop scene-authored button rectangle")

    # New disabled and hidden controls must not animate even if signals are
    # synthesized by a moving parent or reused screen during a scene swap.
    var blocked := Button.new()
    blocked.name = "DisabledTarget"
    blocked.size = Vector2(160, 50)
    blocked.position = Vector2(380, 115)
    blocked.disabled = true
    host.add_child(blocked)
    var invisible := Button.new()
    invisible.name = "HiddenTarget"
    invisible.size = Vector2(160, 50)
    invisible.position = Vector2(570, 115)
    invisible.visible = false
    host.add_child(invisible)
    await process_frame
    _move_to(blocked.get_global_rect().get_center())
    blocked.mouse_entered.emit()
    invisible.mouse_entered.emit()
    blocked.button_down.emit()
    invisible.button_down.emit()
    await create_timer(0.28).timeout
    _check(blocked.scale.is_equal_approx(Vector2.ONE) and is_zero_approx(blocked.rotation),
        "Disabled BaseButton ignores both real pointer entry and synthetic press")
    _check(invisible.scale.is_equal_approx(Vector2.ONE) and is_zero_approx(invisible.rotation),
        "Hidden BaseButton ignores synthetic hover and press")
    _check(_global_signal_count(blocked, "mouse_entered") == 1
        and _global_signal_count(invisible, "mouse_entered") == 1,
        "Hidden/disabled buttons remain wired for later legitimate reuse")

    _move_to(Vector2(9, 9))
    target.grab_focus()
    await process_frame
    _check(target.has_focus() and target.scale.is_equal_approx(home_scale),
        "Keyboard/programmatic focus remains usable without phantom mouse-hover scaling")
    target.release_focus()
    _check(not target.has_focus(), "Native keyboard focus can leave hovered button")
    target.size = Vector2(240, 68)
    await process_frame
    _check(target.pivot_offset.is_equal_approx(home_pivot),
        "Resizing an IDLE button preserves original pivot and responsive layout")
    var resized_home_rect := target.get_rect()
    target.mouse_entered.emit()
    await create_timer(0.20).timeout
    _check(target.pivot_offset.is_equal_approx(target.size * 0.5),
        "Re-hover after resize centers pivot using CURRENT scene-authored dimensions")
    target.size = Vector2(255, 74)
    await process_frame
    _check(target.pivot_offset.is_equal_approx(target.size * 0.5),
        "Resizing an actively hovered button refreshes its temporary center pivot")
    target.mouse_exited.emit()
    await create_timer(0.45).timeout
    _check(target.pivot_offset.is_equal_approx(home_pivot)
        and target.scale.is_equal_approx(home_scale)
        and is_equal_approx(target.rotation, home_rotation),
        "Exit after interactive resize restores authored transform instead of stranding a center pivot")
    _check(target.position.distance_to(resized_home_rect.position) < 0.5,
        "Re-centered active pivot compensates position; no offset/drift after resize: expected=%s actual=%s" %
            [str(resized_home_rect.position), str(target.position)])

    host.queue_free()
    await process_frame
    await process_frame


func _test_reparent_and_scene_transition() -> void:
    var old_scene := Control.new()
    old_scene.name = "HoverTransitionOld"
    old_scene.size = Vector2(1280, 720)
    root.add_child(old_scene)
    var destination := Control.new()
    destination.name = "HoverTransitionNew"
    destination.size = Vector2(1280, 720)
    root.add_child(destination)
    var button := Button.new()
    button.name = "ReparentedButton"
    button.position = Vector2(150, 310)
    button.size = Vector2(185, 55)
    old_scene.add_child(button)
    await process_frame
    var prior_listeners := _global_signal_count(button, "mouse_entered")
    button.reparent(destination)
    await process_frame
    _check(_global_signal_count(button, "mouse_entered") == prior_listeners and prior_listeners == 1,
        "Reparenting reuses one handler; autoload never double-connects")
    _move_to(Vector2(9, 9))
    _move_to(button.get_global_rect().get_center())
    await create_timer(0.26).timeout
    _check(button.scale.x > 1.01, "Reparented BaseButton remains hover-responsive in new scene")
    destination.queue_free()
    await process_frame
    await process_frame
    _check(not is_instance_valid(button), "Freeing routed scene releases former hovered controls")
    var replacement := Button.new()
    replacement.name = "ReparentedButton"
    replacement.position = Vector2(150, 310)
    replacement.size = Vector2(185, 55)
    old_scene.add_child(replacement)
    await process_frame
    _check(_global_signal_count(replacement, "mouse_entered") == 1,
        "A same-name replacement scene button receives exactly one fresh listener")
    _move_to(Vector2(8, 9))
    replacement.mouse_entered.emit()
    await create_timer(0.26).timeout
    _check(replacement.scale.x > 1.01,
        "Replacement button animates after previous hovered scene was freed")
    replacement.mouse_exited.emit()
    await create_timer(0.45).timeout
    _check(replacement.scale.is_equal_approx(Vector2.ONE),
        "Replacement button resets after scene switching")
    old_scene.queue_free()
    await process_frame


func _test_existing_scenes() -> void:
    for item in SAFE_SCENES:
        var packed := load(item[0]) as PackedScene
        _check(packed != null, "Representative original scene loads: " + item[0])
        if packed == null:
            continue
        var scene := packed.instantiate() as Control
        root.add_child(scene)
        scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        await process_frame
        await process_frame
        var button := scene.find_child(item[1], true, false) as BaseButton
        _check(button != null, "Representative .tscn native button available: " + item[1])
        if button != null:
            _check(_global_signal_count(button, "mouse_entered") == 1,
                "Original " + item[0] + " has exactly one global hover hook")
            var original: Vector2 = button.scale
            button.mouse_entered.emit()
            await create_timer(0.29).timeout
            _check(button.scale.x > original.x + 0.005,
                "Original .tscn " + item[1] + " reacts to global hover")
            button.mouse_exited.emit()
            await create_timer(0.45).timeout
            _check(button.scale.is_equal_approx(original),
                "Original .tscn " + item[1] + " fully recovers authored scale")
        scene.queue_free()
        await process_frame
        await process_frame


func _test_hover_during_paused_game() -> void:
    ## Pause UI is required to stay interactive when gameplay is suspended.
    ## The autoload's own tween process must continue despite tree.paused.
    _check(hover_router.process_mode == Node.PROCESS_MODE_ALWAYS,
        "Global hover singleton is explicitly PROCESS_MODE_ALWAYS for paused gameplay")
    var scene := (load("res://ui/play/pause.tscn") as PackedScene).instantiate() as Control
    scene.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
    root.add_child(scene)
    scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    await process_frame
    await process_frame
    var resume := scene.find_child("ResumeButton", true, false) as BaseButton
    _check(resume != null, "Native Pause scene has a ResumeButton for stopped-game feedback")
    if resume == null:
        scene.queue_free()
        await process_frame
        return
    _check(_global_signal_count(resume, "mouse_entered") == 1,
        "ResumeButton retains exactly one global hover listener before pausing")
    var resting: Vector2 = resume.scale
    var authored_pivot: Vector2 = resume.pivot_offset
    paused = true
    resume.mouse_entered.emit()
    await create_timer(0.29, true).timeout
    _check(resume.scale.x > resting.x + 0.005,
        "Resume hover tween progresses while SceneTree.paused == true")
    _check(resume.pivot_offset.is_equal_approx(resume.size * 0.5),
        "Paused hover temporarily centers Resume pivot without breaking layout")
    resume.button_down.emit()
    await create_timer(0.10, true).timeout
    _check(resume.scale.x < resting.x * 1.02,
        "Resume press tween progresses while game is paused")
    resume.button_up.emit()
    resume.mouse_exited.emit()
    await create_timer(0.49, true).timeout
    _check(resume.scale.is_equal_approx(resting) and resume.pivot_offset.is_equal_approx(authored_pivot),
        "Paused Resume hover releases and restores original scale/pivot")
    paused = false
    _check(not paused, "Hover QA always resumes SceneTree before scene cleanup")
    scene.queue_free()
    await process_frame
    await process_frame


func _test_leaderboard_selected_art() -> void:
    var scene := (load(LEADERBOARD) as PackedScene).instantiate() as Control
    root.add_child(scene)
    scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    await process_frame
    var selectors := ["StyleFilter", "ModeFilter", "DifficultyFilter"]
    for selected in selectors:
        var dropdown := scene.get_node("%" + selected) as OptionButton
        _check(_global_signal_count(dropdown, "mouse_entered") == 1,
            "OptionButton " + selected + " receives one global hover")
        dropdown.select(1)
        dropdown.item_selected.emit(1)
        var selected_skin := dropdown.get_theme_stylebox("normal")
        var selected_icon := dropdown.get_theme_icon("arrow")
        _check(selected_skin is StyleBoxTexture,
            selected + " retains scene-authored selected-state PNG")
        dropdown.mouse_entered.emit()
        await create_timer(0.22).timeout
        _check(dropdown.scale.x > 1.0,
            selected + " hover animates independently of selected-state image")
        _check(dropdown.get_theme_stylebox("normal") == selected_skin
            and dropdown.get_theme_icon("arrow") == selected_icon,
            selected + " hover does not corrupt selected PNG, native arrow, or themed style")
        dropdown.mouse_exited.emit()
        await create_timer(0.45).timeout
        _check(dropdown.scale.is_equal_approx(Vector2.ONE),
            selected + " selected-state dropdown returns to 1x after hover")
        dropdown.select(0)
        dropdown.item_selected.emit(0)
    scene.queue_free()
    await process_frame


func _test_settings_no_double_animation() -> void:
    var scene := (load(SETTINGS) as PackedScene).instantiate() as Control
    root.add_child(scene)
    scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    await process_frame
    await process_frame
    for name in ["SidebarSettingsTab", "SidebarControlsTab", "SidebarCameraTab",
            "BackButton", "MuteCheck", "FullscreenCheck"]:
        var button := scene.find_child(name, true, false) as BaseButton
        _check(button != null, "Settings owns its original native feedback button: " + name)
        if button == null:
            continue
        _check(_signal_owner_count(button, "mouse_entered", scene) == 1,
            "Settings " + name + " retains exactly ONE own hover handler")
        _check(_global_signal_count(button, "mouse_entered") == 0,
            "Global handler skips Settings " + name + " to avoid competing tweens")
        button.mouse_entered.emit()
        await create_timer(0.24).timeout
        _check(button.scale.x > 1.01 and button.scale.x <= 1.18,
            "Settings original hover is bounded and not doubled: " + name)
        button.mouse_exited.emit()
        await create_timer(0.43).timeout
        _check(button.scale.is_equal_approx(Vector2.ONE),
            "Settings original hover fully resets with global router active: " + name)
    scene.queue_free()
    await process_frame
    await process_frame


func _test_main_menu_no_double_animation() -> void:
    ## The existing mock Main Menu subclass suppresses real DB service
    ## startup, and music; no live PostgreSQL or camera initialization.
    var packed := load(MAIN_SCENE) as PackedScene
    var fixture := load(MOCK_MENU_SCRIPT) as Script
    _check(packed != null and fixture != null and fixture.can_instantiate(),
        "Real Main Menu can be safely instantiated with existing no-socket fixture")
    if packed == null or fixture == null or not fixture.can_instantiate():
        return
    var app := packed.instantiate() as Control
    app.set_script(fixture)
    root.add_child(app)
    await process_frame
    await process_frame
    for path in ["MainLayer/LeftMenu/Leaderboard", "MainLayer/LeftMenu/Settings",
            "MainLayer/LeftMenu/Credits", "MainLayer/CenterMenu/Tutorial",
            "MainLayer/CenterMenu/Play", "MainLayer/CenterMenu/Quit"]:
        var button := app.get_node(path) as Button
        _check(_signal_method_count(button, "mouse_entered", app, "_hover_button") == 1,
            "Main Menu preserves exactly one local ANIMATION listener: " + path)
        if path.contains("LeftMenu/"):
            _check(_signal_method_count(button, "mouse_entered", app, "_show_tooltip") == 0,
                "Main Menu no longer connects description popups: " + path)
        _check(button.tooltip_text.is_empty(),
            "Main Menu button never shows a native hover label: " + path)
        _check(_global_signal_count(button, "mouse_entered") == 0,
            "Global hover excludes Main Menu own animated button: " + path)
    _check(app.get_node_or_null("MainLayer/Tooltip") == null,
        "Retired beige tooltip popup is completely absent from the editor scene")
    app.call("_return_to_main")
    app.queue_free()
    await process_frame
    await process_frame
    auto_accept_quit = true


func _global_signal_count(button: BaseButton, event: String) -> int:
    return _signal_owner_count(button, event, hover_router)


func _signal_owner_count(button: BaseButton, event: String, owner: Object) -> int:
    var total := 0
    if not is_instance_valid(button) or not is_instance_valid(owner):
        return 0
    for connection: Dictionary in button.get_signal_connection_list(event):
        var cb := connection.get("callable") as Callable
        if cb.is_valid() and cb.get_object() == owner:
            total += 1
    return total


func _signal_method_count(button: BaseButton, event: String, owner: Object, method_name: String) -> int:
    var total := 0
    for connection: Dictionary in button.get_signal_connection_list(event):
        var cb := connection.get("callable") as Callable
        if cb.is_valid() and cb.get_object() == owner and cb.get_method() == method_name:
            total += 1
    return total


func _move_to(where: Vector2) -> void:
    var event := InputEventMouseMotion.new()
    event.position = where
    event.global_position = where
    root.push_input(event, true)


func _mouse_button(where: Vector2, down: bool) -> void:
    var event := InputEventMouseButton.new()
    event.button_index = MOUSE_BUTTON_LEFT
    event.pressed = down
    event.position = where
    event.global_position = where
    root.push_input(event, true)


func _check(value: bool, label: String) -> void:
    checks += 1
    if not value:
        failures.append(label)
        printerr("GLOBAL HOVER QA FAIL: ", label)


func _finish() -> void:
    await process_frame
    print("GLOBAL BUTTON HOVER QA: %s (%d checks, %d failures)" %
        ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
    quit(0 if failures.is_empty() else 1)
