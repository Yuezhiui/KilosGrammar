extends "res://tools/test_single_neutral_calibration_20261102.gd"

# Nov 2 migration of the historic bilateral-consumer fixture.
# The SOLO calibration deliberately requires fresh torso packets, NOT
# both wrists DOWN then UP. Re-run the source-verified safety matrix with
# alternating raised/unraised hands to prove the retired wrist gate is gone.
# Human Plane retains independent T-pose tests in the calibration suite.
var _wrist_up_next := false

func _packet(screen: Control, x: float, people := 1, fresh_pose := true, wrist_valid := false) -> void:
    if people == 1 and fresh_pose:
        _wrist_up_next = not _wrist_up_next
        super._packet(screen, x, people, fresh_pose, _wrist_up_next)
    else:
        super._packet(screen, x, people, fresh_pose, wrist_valid)

func _case(activity: String, guided: bool, x: float) -> void:
    var tag := "%s guided=%s x=%.2f" % [activity, guided, x]
    _setup_pose("bilateral-migrated-" + tag)
    var screen := scene.instantiate() as Control
    root.add_child(screen)
    screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    screen.set_context({"activity": activity, "guided_tutorial": guided,
        "player_mode": "Single Player", "camera_requested": false,
        "topic": "Noun", "game_mode": "Seconds", "difficulty": "Easy"})
    screen.set_process(false)
    var routes: Array[Dictionary] = []
    screen.requested.connect(func(target: String, payload: Dictionary) -> void:
        routes.append({"target": target, "payload": payload.duplicate(true)}))
    var stage := screen.get_node("TutorialStage") as Control
    var intro := stage.get_node_or_null("IntroOverlay") as Control
    var neutral := stage.get_node_or_null("NeutralInstruction") as Label
    var success := stage.get_node_or_null("SuccessOverlay") as Control
    _check(screen._capture_order() == ["NEUTRAL"] and screen._single_neutral_body_mode(),
        tag + " requires exactly one neutral torso hold")
    _check(stage.get_node_or_null("Directions") == null
        and stage.get_node_or_null("PoseGuides") == null,
        tag + " obsolete multi-pose nodes absent from single calibration")
    _check(intro != null and neutral != null and success != null,
        tag + " editor-authored introduction, guidance and success exist")
    screen._process(3.01)
    _check(neutral != null and neutral.visible and neutral.text.contains("HOLD STILL"),
        tag + " English neutral guidance shown after intro")
    for people in [0, 2]:
        _packet(screen, x, people)
        _check(screen.live_step == 0 and routes.is_empty(),
            tag + " missing or multiple people cannot advance")
    for i in range(27):
        _packet(screen, x, 1, true, false)
    _check(screen.live_step == 0 and screen.live_timer < 3.0,
        tag + " three second minimum applies with alternating wrist evidence")
    var before: float = screen.live_timer
    screen._process(0.20)
    _check(is_equal_approx(screen.live_timer, before),
        tag + " stale image cannot earn hold time")
    for i in range(7):
        _packet(screen, x, 1, true, false)
    _check(screen.live_step == 1 and success.visible and screen.success_running,
        tag + " fresh torso-only packets pass without bilateral hands")
    _check(bool(pose.calibration.get("neutral_only", false))
        and not pose.calibration.has("left") and not pose.calibration.has("right"),
        tag + " calibration stores only measured neutral center")
    screen._continue_flow()
    _check(routes.is_empty(), tag + " success delay cannot be skipped")
    for i in range(34):
        _packet(screen, x, 1, true, false)
    _check(routes.size() == 1 and routes[0]["target"] == "gameplay",
        tag + " routes once after completed success")
    if routes.size() == 1:
        var payload: Dictionary = routes[0]["payload"]
        _check(bool(payload.get("calibration_neutral_only", false))
            and bool(payload.get("start_countdown", false))
            and bool(payload.get("calibration_measured", false))
            and payload.get("guided_tutorial", false) == guided,
            tag + " passes measured neutral and countdown")
    screen.queue_free()
    await process_frame
    pose.worker_pid = -1
    pose.stop_camera()
