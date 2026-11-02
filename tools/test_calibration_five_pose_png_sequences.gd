extends "res://tools/test_single_neutral_calibration_20261102.gd"

# Former five-pose illustration regression, adapted to the one-neutral-hold
# contract. All historical PNGs remain safely editable on the .tscn, but
# Catch/Balloon no longer display directional/hand-position guides. The
# inherited test actively verifies one authenticated 3s hold, crowd/stale
# rejection, intro/success/countdown and neutral-only payload.
const AUTHORED_GUIDES := [
    "PoseGuideDefault", "PoseGuideLeft", "PoseGuideRight",
    "PoseGuideBalloonRaise", "PoseGuideBalloonRaiseLeft",
    "PoseGuideBalloonRaiseRight", "PoseGuidePlaneCenter",
    "PoseGuidePlaneLeft", "PoseGuidePlaneRight"
]

func _case(activity: String, guided: bool, x: float) -> void:
    await super._case(activity, guided, x)
    var authored_scene := scene.instantiate() as Control
    var stage := authored_scene.get_node("TutorialStage") as Control
    var guides := stage.get_node("PoseGuides") as Control
    var paths := {}
    for name in AUTHORED_GUIDES:
        var sprite := guides.get_node_or_null(name) as TextureRect
        _check(sprite != null and sprite.texture != null,
            activity + " retained separately draggable original " + name)
        if sprite != null and sprite.texture != null:
            var path := sprite.texture.resource_path
            _check(path.to_lower().ends_with(".png") and ResourceLoader.exists(path),
                activity + " original guide PNG still available " + name)
            paths[path] = true
    _check(paths.size() == 5, activity + " old nine guide nodes retain exactly five original PNGs")
    var neutral := stage.get_node_or_null("NeutralInstruction") as Label
    _check(neutral != null and neutral.text.contains("STAND STILL")
        and neutral.text.contains("3 SECONDS"),
        activity + " new English neutral prompt is independent and editor-authored")
    authored_scene.free()