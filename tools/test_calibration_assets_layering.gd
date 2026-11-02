extends SceneTree

# Historical calibration artwork QA migrated after the Nov 2 scene redesign.
# Tests true authored images and layout, not removed CENTER/RIGHT/LEFT art.
# No camera start, worker/DB/file writes, gameplay or Git.
# Godot 4.7.2 --headless --path . --script res://tools/test_calibration_assets_layering.gd

const SINGLE := "res://ui/vision/calibration/calibration.tscn"
const HUMAN := "res://ui/vision/calibration/human_plane_calibration.tscn"
const MULTI := "res://ui/vision/calibration/multiplayer_calibration.tscn"
const ROOT_ART := "res://Components/Gameplay/Calibration/"
const PLAIN_PLAQUE := "res://Components/Gameplay/Balloon Popping/Art/reference/prompt_blank.png"
const NUMBERS := ["1.png", "2.png", "3.png"]
const SIZES := [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]
const DESIGN := Vector2(1280,720)
const ORIGINAL_ART := [
    "1.png","2.png","3.png","ARROW.png","BACK.png","BACKGROUND.png",
    "BORDER.png","MOVE TO HIGHLIGHTED AREA.png","STARS.png",
    "STAY IN THE CENTER.png","STAY OF THE LEFT.png","STAY ON THE RIGHT.png",
    "STEP 1.png","STEP 2.png","STEP 3.png",
    "Pose Guides/DEFAULT.png","Pose Guides/BALOON POP.png",
    "Pose Guides/PLANE T POSE.png","Pose Guides/PLANE GOING TO LEFT.png",
    "Pose Guides/PLANE GOING TO RIGHT.png"
]
var checks := 0
var failures: Array[String] = []
var scenes: Dictionary = {}
var pose: Node


func _initialize() -> void:
    call_deferred("_run")


func _check(valid: bool, detail: String) -> void:
    checks += 1
    if not valid:
        failures.append(detail)
        printerr("CALIB_ASSETS FAIL: ", detail)


func _run() -> void:
    pose = root.get_node_or_null("PoseService")
    _check(pose != null and not bool(pose.active),
        "PoseService present but real camera remains off")
    if pose == null:
        _finish()
        return
    for path in [SINGLE, HUMAN, MULTI]:
        var packed := load(path) as PackedScene
        _check(packed != null, "Real editor-authored scene parses: " + path)
        if packed != null:
            scenes[path] = packed
    if scenes.size() != 3:
        _finish()
        return
    for asset in ORIGINAL_ART:
        var path: String = ROOT_ART + asset
        var data := FileAccess.get_file_as_bytes(path)
        var decoded := Image.new()
        var result := decoded.load_png_from_buffer(data) if data.size() > 0 else FAILED
        _check(FileAccess.file_exists(path) and FileAccess.file_exists(path + ".import")
            and result == OK and decoded.get_width() > 0 and decoded.get_height() > 0,
            "Original PNG and import pair remains authentic: " + asset)
    _check(FileAccess.get_sha256(ROOT_ART + "STARS.png").to_upper()
            == "E7616EE74CDE8FB894CAA9497216B2C69B43D1425DD050CB18A9846867C93359",
        "Original STARS.png SHA-256 is intact and never replaced with a fake")
    _check(FileAccess.file_exists(PLAIN_PLAQUE)
        and FileAccess.file_exists(PLAIN_PLAQUE + ".import"),
        "Reusable empty gold plaque is genuine imported artwork")
    var former_size := root.size
    var former_scale_size := root.content_scale_size
    for dimensions in SIZES:
        root.size = dimensions
        root.content_scale_size = dimensions
        await process_frame
        await _check_single(dimensions)
        await _check_human(dimensions)
        _check_multiplayer_static(dimensions)
    root.size = former_size
    root.content_scale_size = former_scale_size
    _check(not bool(pose.active) and pose.worker_pid <= 0,
        "No hardware camera or worker was ever launched")
    _finish()


func _scene_with_context(path: String, activity: String) -> Control:
    var control := (scenes[path] as PackedScene).instantiate() as Control
    control.context = {"activity":activity,"player_mode":"Single Player"}
    root.add_child(control)
    control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    control.set_process(false)
    return control


func _check_single(dimensions: Vector2i) -> void:
    var tag := str(dimensions) + " SINGLE"
    var view := _scene_with_context(SINGLE, "Catch the Word")
    var stage := view.get_node("TutorialStage") as Control
    var intro := stage.get_node("IntroOverlay") as ColorRect
    var success := stage.get_node("SuccessOverlay") as ColorRect
    var camera := stage.get_node("CameraArea/LiveCameraInset") as TextureRect
    var skeleton := stage.get_node("CameraArea/SkeletonPlacement") as ReferenceRect
    var frame := stage.get_node("CameraArea/ArtCameraFrame") as TextureRect
    var background := view.get_node("ClassroomBackground") as TextureRect
    var heading := stage.get_node("HeaderPlaque") as TextureRect
    var title := stage.get_node("HeaderTitle") as Label
    var subtitle := stage.get_node("HeaderSubtitle") as Label
    var p1_badge := stage.get_node("PlayerOnePlaque") as TextureRect
    var p1_label := stage.get_node("PlayerOneName") as Label
    var neutral := stage.get_node("NeutralInstruction") as Label
    var digits := stage.get_node("CountdownArtwork") as Control
    var back := stage.get_node("Navigation/BackButton") as Button
    var back_art := stage.get_node("Navigation/BackButton/Artwork") as TextureRect

    _check(_scaled_stage(stage,dimensions) and _bounds(view,dimensions),
        tag + " full screen and original 1280x720 authored stage scale uniformly")
    _check(_file(background) == ROOT_ART + "BACKGROUND.png"
        and _file(frame) == ROOT_ART + "BORDER.png"
        and _file(back_art) == "res://Components/Game Chooser/back button.png",
        tag + " original background, wooden frame and Back image preserved")
    _check(_file(heading) == PLAIN_PLAQUE and _file(p1_badge) == PLAIN_PLAQUE
        and title.text == "CALIBRATION" and subtitle.text == "STAY INSIDE THE SQUARE"
        and p1_label.text == "PLAYER ONE",
        tag + " genuine blank illustrated plaques with independent editable English text")
    _check(_contain(heading.get_rect(),title.get_rect())
        and _contain(heading.get_rect(),subtitle.get_rect())
        and _contain(p1_badge.get_rect(),p1_label.get_rect()),
        tag + " header and player-one text remain inside independent authored plaques")
    _check(camera.size.x > 600 and camera.size.y > 250
        and camera.position.is_equal_approx(skeleton.position)
        and camera.size.is_equal_approx(skeleton.size)
        and _bounds(camera, dimensions) and camera.get_child_count() == 0,
        tag + " single live camera aligned with skeleton and free of unowned child overlays")
    _check(frame.get_index() > camera.get_index() and frame.material is ShaderMaterial
        and _contain(frame.get_rect(),camera.get_rect()),
        tag + " transparent imported BORDER.png surrounds, not replaces, camera preview")
    _check(neutral.get_rect().end.y <= camera.get_rect().position.y + 2.0
        and p1_badge.get_rect().position.y >= camera.get_rect().end.y - 2.0
        and not neutral.get_rect().intersects(camera.get_rect()),
        tag + " neutral prompt/nameplate cannot occlude camera preview; neutral="
            + str(neutral.get_rect()) + " camera=" + str(camera.get_rect())
            + " nameplate=" + str(p1_badge.get_rect()))
    _check(intro.visible and intro.get_node("ArtIntroTitle").text == "CALIBRATION"
        and intro.color.a >= 0.65 and not camera.is_visible_in_tree()
        and not success.visible, tag + " original dark intro covers all premature art")
    for child in stage.get_children():
        if child is Control and child != intro:
            _check(not (child as Control).visible,
                tag + " intro keeps sibling hidden: " + child.name)
    view._process(2.99)
    _check(view.intro_running and intro.visible and view.live_step == 0
        and not neutral.is_visible_in_tree(),tag+" intro exactly 3s, no early pose hold")
    view._process(0.01)
    _check(not view.intro_running and not intro.visible and view._capture_order() == ["NEUTRAL"]
        and neutral.visible and neutral.text.contains("HOLD STILL FOR 3 SECONDS")
        and not success.visible, tag + " one neutral hold replaces old left/right stages")
    for old in ["PoseGuides","Directions","ArtStep1","ArtStep2","ArtStep3",
            "ArtArrowCenter","PoseGuideDefault","PoseGuideBalloonRaise"]:
        _check(stage.get_node_or_null(old) == null,
            tag + " obsolete art node absent from single scene: " + old)
    for i in range(3):
        var art := digits.get_node("ArtCountdown%d" % (i+1)) as TextureRect
        _check(_file(art) == ROOT_ART+NUMBERS[i] and art.owner == view,
            tag + " genuine editor-authored wooden countdown " + NUMBERS[i])
        _check(_contain(camera.get_rect(),art.get_rect())
            and art.get_index() == i,tag+" countdown intentionally inside camera, not outside")
    _check(back.owner == view and back_art.owner == view and not back.disabled,
        tag + " independent authored Back control survives redesign")
    # Synthetic preview: never call PoseService.start_camera or connect a worker.
    var fake := Image.create(64,48,false,Image.FORMAT_RGBA8)
    fake.fill(Color(0.14,0.32,0.55))
    var pixels := fake.get_data()
    var tex := ImageTexture.create_from_image(fake)
    pose.active = true
    view._on_live_preview(tex)
    _check(camera.texture == tex and camera.visible
        and fake.get_data() == pixels,tag+" live feed draws original bytes, no art baked into camera")
    pose.active = false
    view._on_live_preview(null)
    _check(not camera.visible,tag+" no stale preview after feed ends")
    view.queue_free()
    await process_frame


func _check_human(dimensions: Vector2i) -> void:
    var tag := str(dimensions) + " HUMAN PLANE"
    var view := _scene_with_context(HUMAN, "Human Plane")
    var stage := view.get_node("TutorialStage") as Control
    var intro := stage.get_node("IntroOverlay") as ColorRect
    var neutral := stage.get_node("NeutralInstruction") as Label
    var guides := stage.get_node("PoseGuides") as Control
    _check(_scaled_stage(stage,dimensions), tag + " scene authored stage scale preserved")
    _check(intro.visible and view.intro_running and not neutral.is_visible_in_tree(),
        tag + " fresh Human Plane entry preserves 3s intro and no neutral-body override")
    view._process(2.99)
    _check(view.intro_running and view.live_step == 0,
        tag + " T-pose cannot complete during introduction")
    view._process(0.01)
    var center := guides.get_node("PoseGuidePlaneCenter") as TextureRect
    _check(not intro.visible and center.visible
        and view._capture_order() == ["CENTER"]
        and _file(center) == ROOT_ART + "Pose Guides/PLANE T POSE.png",
        tag + " original Human Plane T-pose and center protocol unchanged")
    for side in ["Left","Right"]:
        var guide := guides.get_node("PoseGuidePlane" + side) as TextureRect
        _check(_file(guide) == ROOT_ART + "Pose Guides/PLANE GOING TO " + side.to_upper() + ".png",
            tag+" original independent side demo preserved: "+side)
    view.plane_demo_running = true
    view.plane_demo_elapsed = 0.0
    view._sync_reference_art()
    _check((guides.get_node("PoseGuidePlaneLeft") as TextureRect).visible
        and not (guides.get_node("PoseGuidePlaneRight") as TextureRect).visible,
        tag+" left T-pose demonstration image selected")
    view.plane_demo_elapsed = 3.1
    view._sync_reference_art()
    _check((guides.get_node("PoseGuidePlaneRight") as TextureRect).visible
        and not (guides.get_node("PoseGuidePlaneLeft") as TextureRect).visible,
        tag+" right T-pose demonstration image selected")
    view.queue_free()
    await process_frame


func _check_multiplayer_static(dimensions: Vector2i) -> void:
    var tag := str(dimensions) + " MULTIPLAYER"
    # Do NOT add this scene to the tree! Multiplayer._ready() starts a webcam.
    # Inspect its actual PackedScene's native controls offline instead.
    var view := (scenes[MULTI] as PackedScene).instantiate() as Control
    var stage := view.get_node("Stage") as Control
    view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
    view.size = dimensions
    view.stage = stage
    view._fit_stage()  # Pure design-space scale; no PoseService calls.
    _check(_scaled_stage(stage,dimensions),tag+" 1280 design auto-scales with no camera")
    var board := stage.get_node("WoodenHeaderBoard") as NinePatchRect
    var title := stage.get_node("Header") as Label
    var subtitle := stage.get_node("Subtitle") as Label
    _check(String(board.texture.resource_path) == PLAIN_PLAQUE
        and title.text == "CALIBRATION" and subtitle.text == "STAY INSIDE THE SQUARE"
        and _contain(board.get_rect(),title.get_rect()),
        tag+" true imported blank gold board plus independent editable header text")
    var one := stage.get_node("PlayerOne") as Control
    var two := stage.get_node("PlayerTwo") as Control
    _check(one.get_rect().end.x < two.get_rect().position.x,
        tag+" two independent non-overlapping player zones")
    var prev: Array[TextureRect] = []
    for index in range(2):
        var player: Control = one if index==0 else two
        var label_text := "PLAYER ONE" if index==0 else "PLAYER TWO"
        var video := player.get_node("LiveCamera") as TextureRect
        var frame := player.get_node("WoodenFrame") as TextureRect
        var plate := player.get_node("NamePlate") as NinePatchRect
        var name := player.get_node("Name") as Label
        var digit := player.get_node("CountdownArt") as TextureRect
        var ready := player.get_node("ReadyPlate") as Panel
        var text_count := player.get_node("Countdown") as Label
        var status := player.get_node("Status") as Label
        _check(_file(frame) == ROOT_ART+"BORDER.png"
            and frame.material is ShaderMaterial and _contain(frame.get_rect(),video.get_rect())
            and video.get_child_count() == 0,
            tag+" "+label_text+" live preview behind authentic wooden frame")
        _check(String(plate.texture.resource_path) == PLAIN_PLAQUE
            and _contain(plate.get_rect(),name.get_rect()) and name.text==label_text,
            tag+" "+label_text+" own genuine nameplate with independently authored text")
        _check(_file(digit) == ROOT_ART+"3.png"
            and _contain(video.get_rect(),digit.get_rect()) and not text_count.visible,
            tag+" "+label_text+" illustrated wooden countdown (not stacked text)")
        _check(not ready.visible and status.text=="STAND COMFORTABLY"
            and status.get_rect().position.y >= video.get_rect().end.y,
            tag+" "+label_text+" independent readiness, no accidental covering of camera")
        _check(plate.get_rect().position.y >= video.get_rect().end.y
            and _contain(Rect2(Vector2.ZERO,player.size).grow(70),video.get_rect()),
            tag+" "+label_text+" camera/name controls retain safe local geometry")
        prev.append(video)
    var left_rect := Rect2(one.position+prev[0].position,prev[0].size)
    var right_rect := Rect2(two.position+prev[1].position,prev[1].size)
    _check(not left_rect.intersects(right_rect)
        and _contain(Rect2(Vector2.ZERO,DESIGN),left_rect)
        and _contain(Rect2(Vector2.ZERO,DESIGN),right_rect),
        tag+" two physical camera-panel windows never overlap or leave display")
    var back := stage.get_node("BackButton/BackArt") as TextureRect
    _check(_file(back) == ROOT_ART+"BACK.png" and back.owner == view,
        tag+" real original calibration Back art (not generated) persists")
    view.free()


func _file(texture: TextureRect) -> String:
    return String(texture.texture.resource_path) if texture != null and texture.texture != null else ""


func _contain(a: Rect2,b: Rect2) -> bool:
    return a.position.x <= b.position.x+1.0 and a.position.y <= b.position.y+1.0 \
        and a.end.x+1.0 >= b.end.x and a.end.y+1.0 >= b.end.y


func _bounds(item: Control,dimensions: Vector2i) -> bool:
    var r := item.get_global_rect()
    return r.has_area() and r.position.x>=-2.0 and r.position.y>=-2.0 \
        and r.end.x<=float(dimensions.x)+2.0 and r.end.y<=float(dimensions.y)+2.0


func _scaled_stage(stage: Control,dimensions: Vector2i) -> bool:
    var ratio := minf(float(dimensions.x)/DESIGN.x,float(dimensions.y)/DESIGN.y)
    return stage.size.is_equal_approx(DESIGN) \
        and stage.scale.is_equal_approx(Vector2.ONE*ratio)


func _finish() -> void:
    print("CALIB ASSET/LAYERING: %s checks=%d failures=%d sizes=%s renderer=%s" % [
        "PASS" if failures.is_empty() else "FAIL",
        checks,failures.size(),SIZES,DisplayServer.get_name()])
    quit(0 if failures.is_empty() else 1)
