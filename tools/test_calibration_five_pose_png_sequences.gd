extends "res://tools/test_calibration_raw_bilateral_consumer_20261030.gd"

# Historical illustration test now confirms the single calibration has no
# directional pose assets, while the separate Human Plane scene owns T-pose art.
const PLANE_SCENE_PATH := "res://ui/vision/calibration/human_plane_calibration.tscn"

func _case(activity: String, guided: bool, x: float) -> void:
    await super._case(activity, guided, x)
    var neutral_scene := scene.instantiate() as Control
    var stage := neutral_scene.get_node("TutorialStage") as Control
    _check(stage.get_node_or_null("Directions") == null
        and stage.get_node_or_null("PoseGuides") == null,
        activity + " scene removes retired multi-pose illustrations")
    _check(stage.get_node_or_null("NeutralInstruction") is Label,
        activity + " retains separately editor-authored neutral guidance")
    neutral_scene.free()
    var plane := (load(PLANE_SCENE_PATH) as PackedScene).instantiate() as Control
    var guide := plane.get_node_or_null("TutorialStage/PoseGuides/PoseGuidePlaneCenter") as TextureRect
    _check(guide != null and guide.texture != null,
        activity + " legacy T-pose illustration retained in Human Plane scene")
    if guide != null and guide.texture != null:
        _check(ResourceLoader.exists(guide.texture.resource_path),
            activity + " T-pose texture resolves")
    plane.free()
