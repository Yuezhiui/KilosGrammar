extends "res://tools/test_single_neutral_calibration_20261102.gd"

# Historic editable-guide regression. The old directional/raised-arm PNGs
# remain individual Inspector nodes, but the new SOLO neutral mode must never
# show them or move them. Human Plane's T-pose guide remains separate.
const PNGS := [
    "PoseGuideDefault", "PoseGuideRight", "PoseGuideLeft",
    "PoseGuideBalloonRaise", "PoseGuideBalloonRaiseRight",
    "PoseGuideBalloonRaiseLeft", "PoseGuidePlaneCenter",
    "PoseGuidePlaneLeft", "PoseGuidePlaneRight"
]

func _case(activity: String, guided: bool, x: float) -> void:
    await super._case(activity, guided, x)
    var probe := scene.instantiate() as Control
    root.add_child(probe)
    probe.set_process(false)
    probe.context = {"activity": activity, "player_mode": "Single Player"}
    probe.intro_running = false
    probe._finish_intro_only()
    var stage := probe.get_node("TutorialStage") as Control
    var guides := stage.get_node("PoseGuides") as Control
    var recorded := {}
    for name in PNGS:
        var item := guides.get_node(name) as TextureRect
        recorded[name] = [item.position, item.size, item.scale, item.texture]
    var shifted := guides.get_node("PoseGuideRight") as TextureRect
    shifted.position.x += 17.0
    recorded["PoseGuideRight"] = [shifted.position, shifted.size, shifted.scale, shifted.texture]
    probe._sync_reference_art()
    _check((stage.get_node("NeutralInstruction") as Label).visible,
        activity + " visible neutral instruction replaces old pose art")
    for name in PNGS:
        var item := guides.get_node(name) as TextureRect
        var authored: Array = recorded[name]
        _check(not item.visible and item.position == authored[0]
            and item.size == authored[1] and item.scale == authored[2]
            and item.texture == authored[3],
            activity + " hidden original guide keeps teacher-edited Inspector transform: " + name)
    probe.queue_free()
    await process_frame