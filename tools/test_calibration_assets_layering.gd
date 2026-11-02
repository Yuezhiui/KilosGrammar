extends SceneTree

# Historic CALIB art/layering QA, updated 2026-11-02 for SINGLE Catch/Balloon
# neutral-body calibration. Real .tscn and original PNG bytes, no camera worker,
# pose packets, filesystem mutation, game start, or database access.
# Godot --headless --path . --script res://tools/test_calibration_assets_layering.gd

const SCENE_PATH := "res://ui/vision/calibration/calibration.tscn"
const ART_ROOT := "res://Components/Gameplay/Calibration/"
const ORIGINAL_ART := [
    "1.png", "2.png", "3.png", "ARROW.png", "BACK.png",
    "BACKGROUND.png", "BORDER.png", "MOVE TO HIGHLIGHTED AREA.png",
    "STARS.png", "STAY IN THE CENTER.png", "STAY ON THE RIGHT.png",
    "STAY OF THE LEFT.png", "STEP 1.png", "STEP 2.png", "STEP 3.png"
]
const EDITOR_POSES := [
    "PoseGuideDefault", "PoseGuideRight", "PoseGuideLeft",
    "PoseGuideBalloonRaise", "PoseGuideBalloonRaiseRight",
    "PoseGuideBalloonRaiseLeft", "PoseGuidePlaneCenter",
    "PoseGuidePlaneLeft", "PoseGuidePlaneRight"
]
const DIRECTIONS := [
    "ArtArrowCenter", "ArtArrowRight", "ArtArrowLeft",
    "ArtTitleCenter", "ArtTitleRight", "ArtTitleLeft",
    "ArtStep1", "ArtStep2", "ArtStep3",
    "ArtMoveHintCenter", "ArtMoveHintRight", "ArtMoveHintLeft"
]
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const DESIGN := Vector2(1280, 720)
var checks := 0
var failures: Array[String] = []
var service: Node
var packed: PackedScene


func _initialize() -> void:
    call_deferred("_run")


func _check(ok: bool, note: String) -> void:
    checks += 1
    if not ok:
        failures.append(note)
        printerr("CALIB_ASSETS FAIL: ", note)


func _run() -> void:
    service = root.get_node_or_null("PoseService")
    _check(service != null, "PoseService autoload exists")
    if service == null:
        _finish()
        return
    _check(not bool(service.active), "real webcam is not active at test entry")
    packed = load(SCENE_PATH) as PackedScene
    _check(packed != null, "real editor-authored calibration.tscn loads and parses")
    if packed == null:
        _finish()
        return
    _check_original_pngs()
    var original_size := root.size
    var original_content_size := root.content_scale_size
    for screen_size in SIZES:
        root.size = screen_size
        root.content_scale_size = screen_size
        await process_frame
        await _check_size(screen_size)
    root.size = original_size
    root.content_scale_size = original_content_size
    _check(not bool(service.active), "QA never started real webcam or Python worker")
    _finish()


func _check_original_pngs() -> void:
    for name in ORIGINAL_ART:
        var original: String = ART_ROOT + name
        _check(FileAccess.file_exists(original), "restored original CALIB PNG retained: " + name)
        if FileAccess.file_exists(original):
            # Decode in memory rather than Image.load_from_file(res://), which
            # warns about export-time loader behavior. No bytes are written.
            var image_data := Image.new()
            var decoded := image_data.load_png_from_buffer(FileAccess.get_file_as_bytes(original))
            _check(decoded == OK and image_data.get_width() > 0
                and image_data.get_height() > 0,
                "original supplied PNG remains readable and unmodified: " + name)
    # STARS was restored to the source folder, but the current shipped scene
    # intentionally does not use it. Do not require an unrequested overlay.
    _check(FileAccess.file_exists(ART_ROOT + "STARS.png"),
        "restored STARS.png remains present; no replacement art required")


func _check_size(screen_size: Vector2i) -> void:
    var tag := str(screen_size)
    var view := packed.instantiate() as Control
    _check(view != null and view.has_method("set_context"), tag + " production scene and script instantiate")
    if view == null or not view.has_method("set_context"):
        if view != null:
            view.free()
        return
    root.add_child(view)
    view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    view.set_process(false)
    await process_frame

    var stage := view.get_node_or_null("TutorialStage") as Control
    var background := view.get_node_or_null("ClassroomBackground") as TextureRect
    var dimmer := view.get_node_or_null("ClassroomDimmer") as ColorRect
    var intro := view.get_node_or_null("TutorialStage/IntroOverlay") as ColorRect
    var success := view.get_node_or_null("TutorialStage/SuccessOverlay") as ColorRect
    var camera := view.get_node_or_null("TutorialStage/CameraArea/LiveCameraInset") as TextureRect
    var skeleton := view.get_node_or_null("TutorialStage/CameraArea/SkeletonPlacement") as ReferenceRect
    var camera_backing := view.get_node_or_null("TutorialStage/CameraArea/CameraBlackBacking") as ColorRect
    var wood_frame := view.get_node_or_null("TutorialStage/CameraArea/ArtCameraFrame") as TextureRect
    var neutral := view.get_node_or_null("TutorialStage/NeutralInstruction") as Label
    var guides := view.get_node_or_null("TutorialStage/PoseGuides") as Control
    var directions := view.get_node_or_null("TutorialStage/Directions") as Control
    var countdown := view.get_node_or_null("TutorialStage/CountdownArtwork") as Control
    var back := view.get_node_or_null("TutorialStage/Navigation/BackButton") as Button
    var back_art := view.get_node_or_null("TutorialStage/Navigation/BackButton/Artwork") as TextureRect
    var camera_status := view.get_node_or_null("TutorialStage/CameraFeedback/CameraUnavailableLabel") as Label

    _check(stage != null and background != null and dimmer != null
        and intro != null and success != null and camera != null
        and skeleton != null and camera_backing != null and wood_frame != null
        and neutral != null and guides != null and directions != null
        and countdown != null and back != null and back_art != null
        and camera_status != null,
        tag + " all current editor-authored UI nodes resolve")
    if stage == null or background == null or intro == null or camera == null             or guides == null or neutral == null or directions == null             or countdown == null or back == null or skeleton == null             or camera_status == null or success == null or wood_frame == null             or back_art == null or camera_backing == null or dimmer == null:
        view.queue_free()
        await process_frame
        return

    var expected_scale := minf(float(screen_size.x) / DESIGN.x, float(screen_size.y) / DESIGN.y)
    _check(stage.scale.is_equal_approx(Vector2.ONE * expected_scale)
        and stage.size.is_equal_approx(DESIGN),
        tag + " fixed 1280x720 editable design scales uniformly without local re-layout")
    _check(_near_rect(view.get_global_rect(), Rect2(Vector2.ZERO, Vector2(screen_size)))
        and _inside(stage.get_global_rect(), screen_size),
        tag + " full-screen root and scaled stage remain on display")
    _check(_near_rect(background.get_global_rect(), view.get_global_rect())
        and _near_rect(dimmer.get_global_rect(), view.get_global_rect()),
        tag + " classroom background and dimmer fill full screen")

    var media_nodes: Array[TextureRect] = [background, wood_frame, back_art]
    for name in EDITOR_POSES:
        var guide := guides.get_node_or_null(name) as TextureRect
        _check(guide != null and guide.owner == view and guide.texture != null
            and guide.mouse_filter == Control.MOUSE_FILTER_IGNORE,
            tag + " separately editable original PNG pose guide " + name)
        if guide != null:
            media_nodes.append(guide)
    for name in DIRECTIONS:
        var art := directions.get_node_or_null(name) as TextureRect
        _check(art != null and art.owner == view and art.texture != null
            and art.mouse_filter == Control.MOUSE_FILTER_IGNORE,
            tag + " separately editable original directional PNG " + name)
        if art != null:
            media_nodes.append(art)
    for i in range(1, 4):
        var digit := countdown.get_node_or_null("ArtCountdown%d" % i) as TextureRect
        _check(digit != null and digit.owner == view and digit.texture != null
            and digit.mouse_filter == Control.MOUSE_FILTER_IGNORE,
            tag + " independent countdown digit " + str(i))
        if digit != null:
            media_nodes.append(digit)

    var authored: Dictionary = {}
    for item in media_nodes:
        _check(item.owner == view and item.texture != null,
            tag + " authored TextureRect with real source " + item.name)
        if item.texture != null:
            var source_tex := item.texture
            if source_tex is AtlasTexture:
                source_tex = (source_tex as AtlasTexture).atlas
            var source_path := String(source_tex.resource_path)
            _check(source_path.to_lower().ends_with(".png")
                and FileAccess.file_exists(source_path),
                tag + " uses an original readable PNG, not fake composite: " + item.name)
        authored[item] = [item.position, item.size, item.scale, item.texture]
    _check(_texture_file(background) == ART_ROOT + "BACKGROUND.png"
        and _texture_file(wood_frame) == ART_ROOT + "BORDER.png"
        and _texture_file(back_art) == "res://Components/Game Chooser/back button.png",
        tag + " actual classroom, border and Back button artwork paths preserved")
    _check(_texture_file(guides.get_node("PoseGuidePlaneCenter") as TextureRect)
            == ART_ROOT + "Pose Guides/PLANE T POSE.png",
        tag + " original Human Plane center T-pose PNG remains attached")
    _check(_texture_file(directions.get_node("ArtTitleCenter") as TextureRect)
        == ART_ROOT + "STAY IN THE CENTER.png",
        tag + " retired direction art remains separately retained but not shown")

    _check(_inside(camera.get_global_rect(), screen_size)
        and camera.size.x > 640 and camera.size.y > 300
        and skeleton.position.is_equal_approx(camera.position)
        and skeleton.size.is_equal_approx(camera.size)
        and camera.get_child_count() == 0,
        tag + " live camera preview is editable, in-bounds, skeleton-aligned and unobscured by child overlays")
    _check(camera_backing.get_index() < camera.get_index()
        and camera.get_index() < skeleton.get_index()
        and skeleton.get_index() < wood_frame.get_index()
        and wood_frame.material is ShaderMaterial
        and wood_frame.mouse_filter == Control.MOUSE_FILTER_IGNORE,
        tag + " behind-camera backing, live texture, skeleton, and transparent wood frame have proper z-order")
    _check(back.owner == view and not back.disabled and back.mouse_filter == Control.MOUSE_FILTER_STOP
        and back_art.mouse_filter == Control.MOUSE_FILTER_IGNORE,
        tag + " editor-authored Back control retains usable hitbox, own PNG and pointer routing")

    # Opening intro is independent of the pose mode and hides every other
    # stage sibling. The 66% dimming cannot be replaced with invisible title.
    _check(view.intro_running and intro.is_visible_in_tree()
        and intro.get_node("ArtIntroTitle").text == "CALIBRATION"
        and intro.color.a >= 0.65 and not success.visible
        and not camera.is_visible_in_tree(),
        tag + " real styled 3-second CALIBRATION introduction remains intact")
    for child in stage.get_children():
        if child is Control and child != intro:
            _check(not (child as Control).visible,
                tag + " intro blocks premature camera/guide/action visibility: " + child.name)

    # The same 3-second intro applies to all three modes; never earn samples
    # or reveal cached art before the title closes.
    for activity in ["Catch the Word", "Balloon Popping", "Human Plane"]:
        view.context = {"activity": activity, "player_mode": "Single Player"}
        if view.intro_running:
            view._process(2.99)
        if view.intro_running:
            _check(view.intro_running and view.live_step == 0
                and not neutral.visible and not camera.visible,
                tag + " first 2.99s of intro never shows neutral/camera early")
            view._process(0.01)
        _check(not view.intro_running and not intro.visible and not success.visible,
            tag + " intro completes before calibration visuals: " + activity)
        view._set_stage_instruction()
        view._sync_reference_art()
        _check(view.live_step == 0 and is_zero_approx(view.live_timer),
            tag + " no camera source frames earn any hold time: " + activity)
        if activity == "Human Plane":
            _check(view._capture_order() == ["CENTER"]
                and not view._single_neutral_body_mode()
                and (guides.get_node("PoseGuidePlaneCenter") as TextureRect).visible
                and not neutral.visible,
                tag + " Human Plane retains physical CENTER T-pose, not neutral body shortcut")
            for name in EDITOR_POSES:
                var one := guides.get_node(name) as TextureRect
                _check(one.visible == (name == "PoseGuidePlaneCenter"),
                    tag + " T-pose shows only correct Human Plane center reference: " + name)
            # Side images remain demonstrations, not new calibration holds.
            view.plane_demo_running = true
            view.plane_demo_elapsed = 0.0
            view._sync_reference_art()
            _check((guides.get_node("PoseGuidePlaneLeft") as TextureRect).visible
                and not (guides.get_node("PoseGuidePlaneRight") as TextureRect).visible,
                tag + " Human Plane retains LEFT demonstration image")
            view.plane_demo_elapsed = 3.1
            view._sync_reference_art()
            _check((guides.get_node("PoseGuidePlaneRight") as TextureRect).visible
                and not (guides.get_node("PoseGuidePlaneLeft") as TextureRect).visible,
                tag + " Human Plane retains RIGHT demonstration image")
            view.plane_demo_running = false
            view.plane_demo_elapsed = 0.0
            view._sync_reference_art()
        else:
            _check(view._capture_order() == ["NEUTRAL"] and neutral.visible
                and neutral.text.contains("STAND STILL")
                and neutral.text.contains("3 SECONDS"),
                tag + " " + activity + " shows one editor-authored English neutral instruction")
            _check(_inside(neutral.get_global_rect(), screen_size)
                and not neutral.get_global_rect().intersects(camera.get_global_rect()),
                tag + " neutral prompt remains in frame and never covers live camera image")
            for name in EDITOR_POSES:
                _check(not (guides.get_node(name) as CanvasItem).visible,
                    tag + " obsolete pose art hidden for neutral mode: " + name)
            for name in DIRECTIONS:
                _check(not (directions.get_node(name) as CanvasItem).visible,
                    tag + " obsolete zone arrow/title/hint hidden for neutral mode: " + name)

    # A dummy preview tests actual camera texture ownership without launching
    # webcam hardware. Foreground camera warning MUST yield to valid feed.
    view.context = {"activity": "Catch the Word", "player_mode": "Single Player"}
    view._sync_reference_art()
    var synthetic := Image.create(640, 480, false, Image.FORMAT_RGBA8)
    synthetic.fill(Color(0.15, 0.38, 0.62, 1))
    var texture := ImageTexture.create_from_image(synthetic)
    var pixels := synthetic.get_data()
    service.active = true
    view._on_live_preview(texture)
    _check(camera.visible and camera.texture == texture
        and synthetic.get_data() == pixels and not camera_status.visible,
        tag + " original camera pixels preserved, no offline warning drawn over live preview")
    _check(_inside(camera.get_global_rect(), screen_size)
        and not neutral.get_global_rect().intersects(camera.get_global_rect()),
        tag + " camera remains unobscured by neutral prompt after preview update")
    service.active = false
    view._on_live_preview(null)
    _check(not camera.visible, tag + " missing feed hides camera rather than replaying stale image")

    # Stage/titles/pose artwork are editor-authored; switching modes and
    # updating the feed must not silently move, resize, or retexture them.
    for item in authored:
        var saved: Array = authored[item]
        _check(item.position.is_equal_approx(saved[0])
            and item.size.is_equal_approx(saved[1])
            and item.scale.is_equal_approx(saved[2])
            and item.texture == saved[3],
            tag + " asset transform and real PNG survive intro/mode swaps: " + item.name)
    view.queue_free()
    await process_frame
    await _check_fresh_plane_intro(screen_size)


func _check_fresh_plane_intro(screen_size: Vector2i) -> void:
    # Fresh Human Plane entry must retain its own entire intro and then show
    # its center T-pose. Switching activities on one already-open scene is not
    # a substitute for testing a new initial mount.
    var tag := str(screen_size)
    var plane := packed.instantiate() as Control
    root.add_child(plane)
    plane.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    plane.set_process(false)
    plane.context = {"activity": "Human Plane", "player_mode": "Single Player"}
    var intro := plane.get_node("TutorialStage/IntroOverlay") as ColorRect
    var guide := plane.get_node("TutorialStage/PoseGuides/PoseGuidePlaneCenter") as TextureRect
    var neutral := plane.get_node("TutorialStage/NeutralInstruction") as Label
    _check(intro.is_visible_in_tree() and not guide.is_visible_in_tree()
        and not neutral.is_visible_in_tree(),
        tag + " Human Plane fresh intro shows CALIBRATION only")
    plane._process(2.99)
    _check(plane.intro_running and intro.is_visible_in_tree()
        and not guide.is_visible_in_tree() and plane.live_step == 0,
        tag + " Human Plane intro lasts full 3s and cannot credit premature T-pose")
    plane._process(0.01)
    _check(not plane.intro_running and not intro.visible
        and guide.is_visible_in_tree() and not neutral.visible
        and plane._capture_order() == ["CENTER"],
        tag + " Human Plane restores original T-pose image immediately after intro")
    plane.queue_free()
    await process_frame


func _texture_file(item: TextureRect) -> String:
    if item == null or item.texture == null:
        return ""
    var actual: Texture2D = item.texture
    if actual is AtlasTexture:
        actual = (actual as AtlasTexture).atlas
    return String(actual.resource_path)


func _near_rect(a: Rect2, b: Rect2) -> bool:
    return a.position.distance_to(b.position) < 2.0         and a.size.distance_to(b.size) < 2.0


func _inside(rect: Rect2, limits: Vector2i) -> bool:
    return rect.has_area() and rect.position.x >= -2.0 and rect.position.y >= -2.0         and rect.end.x <= float(limits.x) + 2.0         and rect.end.y <= float(limits.y) + 2.0


func _finish() -> void:
    print("CALIB ASSET/LAYERING: %s checks=%d failures=%d resolutions=%s renderer=%s" % [
        "PASS" if failures.is_empty() else "FAIL",
        checks, failures.size(), SIZES, DisplayServer.get_name()])
    quit(0 if failures.is_empty() else 1)
