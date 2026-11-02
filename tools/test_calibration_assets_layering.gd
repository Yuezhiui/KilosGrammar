extends SceneTree

# Read-only layout and original-art fidelity QA. Never mounts multiplayer
# calibration: its _ready may open the physical camera.
const BASE := "res://Components/Gameplay/Calibration/Original UI/"
const SINGLE := "res://ui/vision/calibration/calibration.tscn"
const MULTI := "res://ui/vision/calibration/multiplayer_calibration.tscn"
const HUMAN := "res://ui/vision/calibration/human_plane_calibration.tscn"
const ASSETS := {
    "calibration.png": [Vector2i(2170, 725), "CD6CD645873052826D5625DAF9CA9239DF0EEAA970EB6E58922B9D14F198CA34"],
    "Player1.png": [Vector2i(1527, 564), "F3F21A57DE7505BB842A0C4D8E38F4D33ED732F241966D9BD79BA320621C1D21"],
    "Player2.png": [Vector2i(1527, 564), "E4BDCC241DF1E02E131BC6E6AA90D09C69FE7BDFE723A12ED281BF1EDE40B496"]
}
const SIZES := [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
    call_deferred("_run")

func _check(ok: bool, message: String) -> void:
    checks += 1
    if not ok:
        failures.append(message)
        printerr("CALIB ASSETS FAIL: ", message)

func _asset(file: String) -> void:
    var path := BASE + file
    var data := FileAccess.get_file_as_bytes(path)
    var img := Image.new()
    var decoded := img.load_png_from_buffer(data) if not data.is_empty() else FAILED
    _check(decoded == OK and img.get_size() == ASSETS[file][0],
        file + " exact original source PNG pixel dimensions")
    _check(FileAccess.get_sha256(path).to_upper() == ASSETS[file][1],
        file + " exact original source SHA256")
    _check(FileAccess.file_exists(path + ".import"), file + " Godot import metadata exists")

func _texture(node: TextureRect, file: String, tag: String) -> void:
    _check(node != null and node.texture != null and node.texture.resource_path == BASE + file,
        tag + " genuine original PNG, no substitute texture")
    if node == null or node.texture == null:
        return
    _check(node.texture.get_size().is_equal_approx(Vector2(ASSETS[file][0])),
        tag + " original texture resolution retained")
    var wanted: float = float(ASSETS[file][0].x) / float(ASSETS[file][0].y)
    var actual: float = node.size.x / node.size.y
    _check(absf(wanted - actual) < 0.02 and node.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
        tag + " proportional authored rectangle and aspect-preserving stretch")

func _run() -> void:
    var pose := root.get_node_or_null("PoseService")
    _check(pose != null and not pose.active, "no camera or tracking worker started")
    for file in ASSETS:
        _asset(file)
    var single := load(SINGLE) as PackedScene
    var multi := load(MULTI) as PackedScene
    var human := load(HUMAN) as PackedScene
    _check(single != null and multi != null and human != null, "all three real scenes parse")
    if single == null or multi == null or human == null:
        _finish()
        return
    for dimensions in SIZES:
        var ratio := float(dimensions.x) / 1280.0
        var a := single.instantiate() as Control
        var stage := a.get_node("TutorialStage") as Control
        var head := stage.get_node_or_null("ArtCalibrationHeader") as TextureRect
        var plate := stage.get_node_or_null("ArtPlayerOne") as TextureRect
        _texture(head, "calibration.png", str(dimensions)+" single heading")
        _texture(plate, "Player1.png", str(dimensions)+" single P1")
        _check(stage.get_node_or_null("HeaderPlaque") == null
            and stage.get_node_or_null("HeaderTitle") == null
            and stage.get_node_or_null("HeaderSubtitle") == null
            and stage.get_node_or_null("PlayerOnePlaque") == null
            and stage.get_node_or_null("PlayerOneName") == null,
            "single has no duplicate recreated header or player label")
        var camera := stage.get_node("CameraArea/LiveCameraInset") as TextureRect
        var skeleton := stage.get_node("CameraArea/SkeletonPlacement") as Control
        _check(camera.position.distance_to(skeleton.position) <= 1.01
            and camera.size.is_equal_approx(skeleton.size),
            str(dimensions)+" single camera and skeleton alignment camera="+str(camera.get_rect())+" skeleton="+str(skeleton.get_rect()))
        _check(not head.get_rect().intersects(camera.get_rect()),
            str(dimensions)+" single header clears camera preview heading="+str(head.get_rect())+" camera="+str(camera.get_rect()))
        _check(not plate.get_rect().intersects(camera.get_rect()),
            str(dimensions)+" single original player nameplate clears camera preview; plate="
                + str(plate.get_rect()) + " preview=" + str(camera.get_rect()))
        _check(stage.size.is_equal_approx(Vector2(1280,720))
            and head.get_rect().end.x <= 1280 and plate.get_rect().end.y <= 720,
            str(dimensions)+" single original art remains within scalable 1280x720 stage")
        a.free()
        var m := multi.instantiate() as Control
        var s := m.get_node("Stage") as Control
        m.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
        m.size = dimensions
        m.stage = s
        m._fit_stage()
        _check(s.scale.is_equal_approx(Vector2.ONE * ratio)
            and s.size.is_equal_approx(Vector2(1280,720)),
            str(dimensions)+" multi scales uniformly without distortion")
        _texture(s.get_node_or_null("ArtCalibrationHeader") as TextureRect,
            "calibration.png", str(dimensions)+" multi heading")
        _check(s.get_node_or_null("Header") == null and s.get_node_or_null("Subtitle") == null
            and s.get_node_or_null("WoodenHeaderBoard") == null,
            "multiplayer has no duplicate heading plaque or labels")
        var left := s.get_node("PlayerOne") as Control
        var right := s.get_node("PlayerTwo") as Control
        var first := left.get_node("LiveCamera") as TextureRect
        var second := right.get_node("LiveCamera") as TextureRect
        _texture(left.get_node_or_null("NamePlate") as TextureRect,
            "Player1.png", str(dimensions)+" multi P1")
        _texture(right.get_node_or_null("NamePlate") as TextureRect,
            "Player2.png", str(dimensions)+" multi P2")
        _check(left.get_node_or_null("Name") == null and right.get_node_or_null("Name") == null,
            "multiplayer has no duplicate player name labels")
        var one := Rect2(left.position + first.position, first.size)
        var two := Rect2(right.position + second.position, second.size)
        _check(first != second and not one.intersects(two)
            and Rect2(Vector2.ZERO,Vector2(1280,720)).encloses(one)
            and Rect2(Vector2.ZERO,Vector2(1280,720)).encloses(two),
            str(dimensions)+" two independent visible camera viewport regions, no overlaps")
        _check(not (left.position + (left.get_node("NamePlate") as Control).position).y < 0
            and not (right.position + (right.get_node("NamePlate") as Control).position).y < 0,
            str(dimensions)+" both nameplates remain inside stage")
        m.free()
        var h := human.instantiate() as Control
        var guide := h.get_node_or_null("TutorialStage/PoseGuides/PoseGuidePlaneCenter") as TextureRect
        _check(guide != null and guide.texture != null
            and guide.texture.resource_path.ends_with("PLANE T POSE.png"),
            str(dimensions)+" Human Plane original T-pose stays intact")
        h.free()
    _check(pose != null and not pose.active and pose.worker_pid <= 0,
        "verification never started hardware camera or worker")
    _finish()

func _finish() -> void:
    print("CALIB ASSET/LAYERING: %s checks=%d failures=%d" % [
        "PASS" if failures.is_empty() else "FAIL",checks,failures.size()])
    quit(0 if failures.is_empty() else 1)
