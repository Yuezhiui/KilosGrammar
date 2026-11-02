extends "res://tools/test_calibration_raw_bilateral_consumer_20261030.gd"

# The neutral screen no longer authors step PNG nodes; plane retains its
# independently draggable T-pose TextureRect in a distinct scene.
const PLANE_SCENE_PATH := "res://ui/vision/calibration/human_plane_calibration.tscn"

func _case(activity: String, guided: bool, x: float) -> void:
    await super._case(activity, guided, x)
    var probe := (load(PLANE_SCENE_PATH) as PackedScene).instantiate() as Control
    var guide := probe.get_node_or_null("TutorialStage/PoseGuides/PoseGuidePlaneCenter") as TextureRect
    _check(guide != null and guide.texture != null,
        activity + " plane T-pose guide is a real editable texture node")
    if guide != null:
        var original := guide.position
        var texture := guide.texture
        guide.position.x += 17.0
        probe.context = {"activity": "Human Plane", "player_mode": "Single Player"}
        probe._sync_reference_art()
        _check(guide.position == original + Vector2(17, 0) and guide.texture == texture,
            activity + " Human Plane sync does not overwrite teacher Inspector geometry")
    probe.free()
