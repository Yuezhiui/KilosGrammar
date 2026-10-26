extends SceneTree

## Full-3D Human Plane pose/visible-ring hitbox QA. Camera/DB/device-free.
## Godot --headless --path . --script res://tools/test_human_plane_pose_hitbox_qa.gd
## Godot --path . --rendering-method gl_compatibility --rendering-driver opengl3
##       --script res://tools/test_human_plane_pose_hitbox_qa.gd -- --gpu
##
## Only the existing game state machine makes scoring decisions. This test
## builds an independent geometric oracle from the authorable collision sprites,
## never monkeypatches hit/scoring code, and never launches PoseService.

const GAME := preload("res://ui/minigames/human_plane.tscn")
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const MODES := ["Seconds", "Lives"]
const SOURCE_RING_X := [-6.0, 0.0, 6.0]
const MIN_COVERAGE := 0.70
const SAFE_CENTER_FRACTION := 0.30
const DOMINANT_MIN_COVERAGE := 0.50
const DOMINANT_MIN_LEAD := 0.20
const BOOST := 0.14
const POINTS := 100

var checks := 0
var failures: Array[String] = []
var pose: Node
var tested_hitboxes := 0
var ambiguous_positions := 0
var _last_context := ""


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    pose = root.get_node_or_null("PoseService")
    _expect(pose != null, "Real PoseService autoload is present without starting webcam")
    if pose == null:
        _finish()
        return
    var original_size := root.size
    var original_content := root.content_scale_size
    pose.stop_camera()
    pose.set_process(false)
    for dimensions in VIEWPORTS:
        root.size = dimensions
        root.content_scale_size = Vector2i(1280, 720)
        for mode in MODES:
            await _test_game(dimensions, mode)
    if "--gpu" in OS.get_cmdline_user_args():
        await _check_visible_gpu()
    pose.stop_camera()
    pose.set_process(false)
    root.size = original_size
    root.content_scale_size = original_content
    _finish()


func _test_game(dimensions: Vector2i, mode: String) -> void:
    var label := "%dx%d/%s" % [dimensions.x, dimensions.y, mode]
    _last_context = label
    var game := GAME.instantiate() as Control
    _expect(game != null, label + " real game scene instantiates")
    if game == null:
        return
    root.add_child(game)
    game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    game.set_context({"activity":"Human Plane", "topic":"Noun",
        "difficulty":"Normal", "game_mode":mode, "score":340,
        "correct":2, "plane_speed_boosts":2, "total":20})
    await process_frame
    await process_frame
    game.set_process(false)
    var world := game.get_node_or_null("WorldView3D") as SubViewportContainer
    _expect(world != null and world.has_method("sync_flight"),
        label + " live full3D world renderer is installed")
    if world != null:
        _check_camera_and_world(game, world, label)
    _check_pose_authority(game, label)
    _check_lanes_and_hitboxes(game, label)
    _check_score_and_boost(game, world, label)
    game.queue_free()
    await process_frame
    await process_frame


func _check_pose_authority(game: Control, label: String) -> void:
    # Collision/flight scene unit test: the single neutral calibration and
    # unique-player lock live in PoseService, verified separately by
    # test_calibration_stationary_wing_roll and test_human_plane_body_integration.
    # Never fabricate camera left/right bounds in this hitbox test.
    game.set("plane_x_norm", 0.5)
    game.set("target_x_norm", 0.5)
    game.call("set_airplane_pose_active", false)
    game.call("set_body_x", 1.0)
    game.call("_update_plane_motion", 0.1)
    _expect(is_equal_approx(float(game.get("plane_x_norm")), 0.5),
        label + " unverified pose cannot steer the score-authoritative hitbox")
    game.call("set_airplane_pose_active", true)
    game.call("_update_plane_motion", 0.1)
    _expect(is_equal_approx(float(game.get("plane_x_norm")), 0.5),
        label + " player reacquisition cannot replay a stale steering command")
    game.call("set_body_x", 1.0)
    game.call("_update_plane_motion", 0.1)
    var stepped := float(game.get("plane_x_norm"))
    var constants: Dictionary = game.get_script().get_script_constant_map()
    var max_travel: float = float(constants.get("BODY_MAX_TRAVEL_PER_SECOND", 2.8))
    var max_step: float = float(constants.get("BODY_MAX_MOTION_STEP", 0.1))
    _expect(stepped > 0.5 and stepped <= 0.5 + max_travel * minf(0.1, max_step) + 0.001,
        label + " small hand-bank move follows authored speed limit without teleportation")
    game.call("set_airplane_pose_active", false)
    game.call("set_body_x", -1.0)
    game.call("_update_plane_motion", 0.6)
    _expect(is_equal_approx(float(game.get("plane_x_norm")), stepped),
        label + " occlusion/player lock loss freezes airplane at exact x")
    game.call("set_airplane_pose_active", true)
    game.call("_update_plane_motion", 0.4)
    _expect(is_equal_approx(float(game.get("plane_x_norm")), stepped),
        label + " restoring eligibility still requires a NEW steering command")
    game.call("set_body_x", -1.0)
    game.call("_update_plane_motion", 0.1)
    _expect(float(game.get("plane_x_norm")) < stepped,
        label + " fresh LEFT wrist-bank value glides left without phantom momentum")
    var parked := float(game.get("plane_x_norm"))
    game.set("paused", true)
    game.call("set_body_x", 1.0)
    game.call("_update_plane_motion", 0.3)
    _expect(is_equal_approx(float(game.get("plane_x_norm")), parked),
        label + " Pause blocks steering and preserves physical 3D hitbox")
    game.set("paused", false)
    game.call("set_airplane_pose_active", false)
func _check_lanes_and_hitboxes(game: Control, label: String) -> void:
    # Collision uses editable invisible GateArtwork/PlaneRig guides, while the
    # visible pilot is a 3D imported FBX. Scan fine-grained physical positions.
    var progress := float(game.call("_progress_for_answer_line"))
    var centers: Array[float] = []
    var expected_norms: Array[float] = []
    var source_world_x: Array[float] = []
    var world := game.get_node_or_null("WorldView3D") as SubViewportContainer
    var pilot3d := world.get_node_or_null("Viewport3D/FlightWorld/PlayerRig") as Node3D if world != null else null
    var current_rings := world.get_node_or_null("Viewport3D/FlightWorld/CurrentRings") as Node3D if world != null else null
    _expect(world != null and world.has_method("_render_x_from_body_norm"),
        label + " 3D renderer has monotone scored-lane-aware body→world mapper")
    var first_world_x := -9.5
    var last_world_x := 9.5
    if world != null and pilot3d != null:
        var example := {"options":["APPLE","TEACHER","DOG"],"valid_indices":[1]}
        world.call("sync_flight", 0.0, example, 0.40, {}, 0.0, false,
            -1, false, false, false, 0.70, true)
        first_world_x = pilot3d.position.x
        world.call("sync_flight", 1.0, example, 0.40, {}, 0.0, false,
            -1, false, false, false, 0.70, true)
        last_world_x = pilot3d.position.x
        _expect(last_world_x > first_world_x + 0.1,
            label + " actual render player rig has real nonzero lateral steering span")
    for lane in range(3):
        var gate: Rect2 = game.call("_gate_visible_rect", lane, progress)
        centers.append(gate.get_center().x)
        var norm := _norm_for_pilot_center(game, gate.get_center().x)
        expected_norms.append(norm)
        _expect(norm >= -0.02 and norm <= 1.02,
            label + " ring %d reachable from calibrated flight boundaries (norm=%.3f)" % [lane,norm])
        game.set("plane_x_norm", norm)
        _expect(int(game.call("_lane_hit_at_answer_line")) == lane,
            label + " exact visual ring %d center selects ONLY that ring" % lane)
        var visible_x := float(SOURCE_RING_X[lane])
        if current_rings != null and current_rings.get_child_count() > lane:
            var ring := current_rings.get_child(lane) as Node3D
            if ring != null:
                visible_x = ring.position.x
        source_world_x.append(visible_x)
        var world_norm: float = _body_norm_for_world_x(world, visible_x)
        game.set("plane_x_norm", world_norm)
        var projected_hit := int(game.call("_lane_hit_at_answer_line"))
        _expect(projected_hit == lane,
            label + " physical 3D ring %d world-center x aligns with scored hitbox (%.3f => %d)"
            % [lane,world_norm,projected_hit])
    var required_world: Array[float] = []
    for norm in expected_norms:
        required_world.append(float(world.call("_render_x_from_body_norm", norm))
            if world != null and world.has_method("_render_x_from_body_norm")
            else lerpf(first_world_x,last_world_x,norm))
    print("POSE HITBOX alignment %s AUTHOR_2D_NORMS=%s 3D_VISIBLE_RING_X=%s REQUIRED_WORLD_RING_X=%s WORLD_PILOT_SPAN=(%.3f,%.3f)" % [
        label,str(expected_norms),str(source_world_x),str(required_world),
        first_world_x,last_world_x])
    # Test what a student SEEING the plane halfway between physical torus
    # centers would receive. Midpoints must not snap into an adjacent answer.
    for i in range(2):
        var between_world := (source_world_x[i] + source_world_x[i+1]) * 0.5
        var between_norm: float = _body_norm_for_world_x(world, between_world)
        game.set("plane_x_norm", between_norm)
        _expect(int(game.call("_lane_hit_at_answer_line")) == -1,
            label + " world-space BETWEEN visible 3D rings %d/%d is an ambiguous MISS (x=%.3f)" %
            [i,i+1,between_norm])
    if world != null:
        # Restore the scene's authored current gameplay state before other
        # assertions; the presentation-only test calls never resolve scores.
        game.call("_sync_visuals")


    for i in range(2):
        var midpoint := (centers[i] + centers[i+1]) * 0.5
        game.set("plane_x_norm", _norm_for_pilot_center(game, midpoint))
        _expect(int(game.call("_lane_hit_at_answer_line")) == -1,
            label + " two adjacent rings' midpoint is ambiguous MISS, never first-match")
        var left: Rect2 = game.call("_gate_visible_rect", i, progress)
        var right: Rect2 = game.call("_gate_visible_rect", i + 1, progress)
        var hit_width := (game.get_node("PlaneRig/Hitbox") as Control).size.x
        for selected in [i, i + 1]:
            var landing := _paired_straddle_x(left, right, hit_width, selected == i, 0.80)
            _expect(is_finite(landing), label + " real 80/20 straddle between lanes %d/%d" % [i,i+1])
            if is_finite(landing):
                game.set("plane_x_norm", _norm_for_pilot_center(game, landing))
                for correct_lane in [i, i + 1]:
                    var data: Dictionary = (game.get("round_data") as Dictionary).duplicate(true)
                    data["valid_indices"] = [correct_lane]
                    game.set("round_data", data)
                    _expect(int(game.call("_lane_hit_at_answer_line")) == selected,
                        label + " 80/20 dominant lane %d independent of correct word %d" % [selected,correct_lane])
        var ambiguous := _paired_straddle_x(left, right, hit_width, true, 0.52)
        _expect(is_finite(ambiguous), label + " near-equal 52/48 split physically exists")
        if is_finite(ambiguous):
            game.set("plane_x_norm", _norm_for_pilot_center(game, ambiguous))
            _expect(int(game.call("_lane_hit_at_answer_line")) == -1,
                label + " 52/48 borderline contact remains a miss")
    # A separate independent overlap/coverage oracle catches accidental
    # left-to-right tie breaks and answer correctness influencing collision.
    var disagreements := 0
    var near_edges := 0
    for step in range(201):
        var norm := float(step) / 200.0
        game.set("plane_x_norm", norm)
        var actual := int(game.call("_lane_hit_at_answer_line"))
        var expected := _independent_hit_oracle(game, progress)
        tested_hitboxes += 1
        if expected == -1:
            near_edges += 1
        if actual != expected:
            disagreements += 1
            if disagreements <= 5:
                printerr("HITBOX ORACLE MISMATCH ",label," norm=",norm,
                    " authoritative=",actual," expected=",expected)
    _expect(disagreements == 0,
        label + " 201 sampled intermediate/edge body x values agree with dominant-overlap oracle")
    _expect(near_edges > 5,
        label + " visible safe windows do not incorrectly fill all three-lane gaps")
    print("POSE HITBOX geometry %s centers=%s total_sweep=201 outside_safe=%d" %
        [label,str(centers),near_edges])


func _body_norm_for_world_x(world: SubViewportContainer, target: float) -> float:
    # Renderer uses monotone nonlinear 3-anchor mapping plus tanh tails.
    # Invert its ACTUAL mapping with a bounded binary search, not obsolete
    # linear travel endpoints (those manufactured false scorer failures).
    if world == null or not world.has_method("_render_x_from_body_norm"):
        return 0.5
    var lower := 0.0
    var upper := 1.0
    for _iteration in range(32):
        var middle := (lower + upper) * 0.5
        var mapped := float(world.call("_render_x_from_body_norm", middle))
        if mapped < target:
            lower = middle
        else:
            upper = middle
    return (lower + upper) * 0.5


func _norm_for_pilot_center(game: Control, x: float) -> float:
    var left := game.get_node("FlightPaths/PlaneLeftLimit") as Control
    var right := game.get_node("FlightPaths/PlaneRightLimit") as Control
    var rig := game.get_node("PlaneRig") as Control
    var hitbox := game.get_node("PlaneRig/Hitbox") as Control
    var hitbox_offset := hitbox.get_rect().get_center().x - rig.size.x * 0.5
    var left_x := left.get_rect().get_center().x
    var right_x := right.get_rect().get_center().x
    return (x - hitbox_offset - float(game.get("_plane_authored_offset_x")) - left_x) / (right_x - left_x)


func _independent_hit_oracle(game: Control, progress: float) -> int:
    var plane := float(game.call("_plane_center_x"))
    var rig := game.get_node("PlaneRig") as Control
    var hitbox := game.get_node("PlaneRig/Hitbox") as Control
    var half := hitbox.size.x * 0.5
    plane += hitbox.get_rect().get_center().x - rig.size.x * 0.5
    if not is_finite(plane) or half <= 0.0:
        return -1
    var left := plane - half
    var right := plane + half
    var contacts: Array[int] = []
    var overlaps: Array[float] = []
    var rects: Array[Rect2] = []
    for lane in range(3):
        var r := game.call("_gate_visible_rect", lane, progress) as Rect2
        var width := minf(right,r.end.x) - maxf(left,r.position.x)
        if r.size.x > 0.0 and width > 0.0:
            contacts.append(lane)
            overlaps.append(width)
            rects.append(r)
    if contacts.is_empty():
        return -1
    var best := 0
    for index in range(1, contacts.size()):
        if overlaps[index] > overlaps[best]:
            best = index
    if contacts.size() >= 2:
        var runner_up := 0.0
        var sum_width := 0.0
        for index in range(contacts.size()):
            sum_width += overlaps[index]
            if index != best:
                runner_up = maxf(runner_up, overlaps[index])
        if overlaps[best] < half * 2.0 * DOMINANT_MIN_COVERAGE or \
                overlaps[best] - runner_up < sum_width * DOMINANT_MIN_LEAD:
            ambiguous_positions += 1
            return -1
        return contacts[best]
    if overlaps[best] < 2.0 * half * MIN_COVERAGE:
        return -1
    var safe_radius := minf(rects[best].size.x * SAFE_CENTER_FRACTION,
        rects[best].size.x * 0.5 - half)
    if safe_radius <= 0.0 or absf(plane - rects[best].get_center().x) > safe_radius:
        return -1
    return contacts[best]


func _paired_straddle_x(left: Rect2, right: Rect2, width: float,
        prefer_left: bool, desired_ratio: float) -> float:
    var between := (left.end.x + right.position.x) * 0.5
    var best_x := NAN
    var best_distance := INF
    for step in range(-240, 241):
        var x := between + float(step) * 0.25
        var l := maxf(minf(x + width * 0.5, left.end.x) - maxf(x - width * 0.5, left.position.x), 0.0)
        var r := maxf(minf(x + width * 0.5, right.end.x) - maxf(x - width * 0.5, right.position.x), 0.0)
        if l <= 0.0 or r <= 0.0:
            continue
        var preferred := l if prefer_left else r
        var other := r if prefer_left else l
        if desired_ratio > 0.55 and preferred < width * 0.5:
            continue
        var deviation := absf(preferred / (preferred + other) - desired_ratio)
        if deviation < best_distance:
            best_distance = deviation
            best_x = x
    return best_x if best_distance <= 0.045 else NAN


func _check_score_and_boost(game: Control, world: SubViewportContainer, label: String) -> void:
    game.call("_start_wave")
    var baseline := int(game.get("score"))
    var initial_multiplier := float(game.get("speed_multiplier"))
    _expect(baseline == 340 and absf(initial_multiplier - 1.28) < 0.0001,
        label + " restored 340 score and two earned speed boosts remain nonnegative")
    var first_correct: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
    _expect(not first_correct.is_empty(), label + " real grammar wave has at least one correct ring")
    if first_correct.is_empty():
        return
    _place_at_lane(game,int(first_correct[0]))
    game.call("_resolve_at_answer_line")
    var earned := initial_multiplier + BOOST
    _expect(int(game.get("score")) == baseline + POINTS,
        label + " exact correct hit adds 100 without rounding errors")
    _expect(absf(float(game.get("speed_multiplier")) - earned) < 0.0001,
        label + " a correct ring adds 14% cumulative speed")
    _expect(int(game.get("speed_boost_count")) == 3,
        label + " correct hit counts third lifetime boost despite earlier score")
    var after_correct := int(game.get("score"))
    var after_boost := float(game.get("speed_multiplier"))
    game.call("_resolve_at_answer_line")
    _expect(int(game.get("score")) == after_correct and
        is_equal_approx(float(game.get("speed_multiplier")), after_boost),
        label + " repeated collision callback never awards twice")
    game.call("_start_wave")
    var answer_progress := float(game.call("_progress_for_answer_line"))
    var left_rect: Rect2 = game.call("_gate_visible_rect", 0, answer_progress)
    var center_rect: Rect2 = game.call("_gate_visible_rect", 1, answer_progress)
    game.set("plane_x_norm", _norm_for_pilot_center(game,
        (left_rect.get_center().x + center_rect.get_center().x) * 0.5))
    _expect(int(game.call("_lane_hit_at_answer_line")) == -1,
        label + " adjacent-ring midpoint counts as a MISS, not a guessed correct answer")
    var before_lives := int(game.get("lives"))
    game.call("_resolve_at_answer_line")
    _expect(int(game.get("selected_lane")) == -1 and not bool(game.get("selected_was_correct")),
        label + " ambiguous collision cannot select either adjacent answer")
    _expect(int(game.get("score")) == after_correct and int(game.get("score")) >= 0,
        label + " ambiguous/missed rings subtract ZERO points")
    _expect(int(game.get("lives")) == maxi(before_lives-1,0),
        label + " ambiguous miss loses exactly one heart (not points)")
    _expect(is_equal_approx(float(game.get("speed_multiplier")), after_boost),
        label + " misses never remove earned cumulative flight speed")
    game.call("_start_wave")
    var valid: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
    var wrong := -1
    for lane in range(3):
        if lane not in valid:
            wrong = lane
            break
    _expect(wrong >= 0, label + " grammar wave offers at least one wrong answer")
    if wrong >= 0:
        _place_at_lane(game, wrong)
        _expect(int(game.call("_lane_hit_at_answer_line")) == wrong,
            label + " a centered WRONG lane is geometrically selectable")
        before_lives = int(game.get("lives"))
        game.call("_resolve_at_answer_line")
        _expect(int(game.get("score")) == after_correct and int(game.get("score")) >= 0,
            label + " wrong answer subtracts ZERO previously earned score")
        _expect(int(game.get("lives")) == maxi(before_lives-1,0),
            label + " wrong answer costs one heart only")
        _expect(is_equal_approx(float(game.get("speed_multiplier")), after_boost),
            label + " wrong answer does not erase speed bonus or slowdown through ring")
        _expect(int(game.get("streak")) == 0,
            label + " error resets streak, not score or cumulative boost")
    var speed_before := float(game.get("speed_multiplier"))
    var old_speed := float(world.get("speed_multiplier")) if world != null else 0.0
    game.call("_start_wave")
    game.call("_advance_gate_step", 0.1)
    var progressed := float(game.get("gate_progress"))
    var normal := float((game.get("DIFFICULTY_CONFIG") as Dictionary).get("Normal", {}).get("gate_speed", 0.27))
    _expect(absf(progressed - normal * speed_before * 0.1) < 0.001,
        label + " correct speed remains effective after miss+wrong, no torus slowdown")
    if world != null:
        _expect(float(world.get("speed_multiplier")) >= speed_before - 0.0001,
            label + " 3D scenery/ring speed keeps cumulative correctness boost")
        _expect(float(world.get("speed_multiplier")) >= old_speed - 0.0001,
            label + " rendering speed never decreases after miss or wrong")
    var payload: Dictionary = game.call("get_context")
    _expect(int(payload.get("score", -1)) == after_correct and
        absf(float(payload.get("plane_speed_multiplier",0.0))-speed_before)<0.0001,
        label + " results/pause persistence retains score and bonus across crossings")


func _place_at_lane(game: Control, lane: int) -> void:
    var progress := float(game.call("_progress_for_answer_line"))
    var rect: Rect2 = game.call("_gate_visible_rect",lane,progress)
    game.set("plane_x_norm", _norm_for_pilot_center(game,rect.get_center().x))


func _check_camera_and_world(game: Control, world: SubViewportContainer, label: String) -> void:
    var camera := world.get_node_or_null("Viewport3D/FlightWorld/Camera3D") as Camera3D
    var rig := world.get_node_or_null("Viewport3D/FlightWorld/PlayerRig") as Node3D
    var plane := world.get_node_or_null("Viewport3D/FlightWorld/PlayerRig/RedPlane") as Node3D
    var rings := world.get_node_or_null("Viewport3D/FlightWorld/CurrentRings") as Node3D
    _expect(camera != null and camera.current and camera.fov >= 40.0,
        label + " full3D scene camera is active with readable projection FOV")
    _expect(rig != null and rig.visible and plane != null and plane.visible,
        label + " actual RED artist FBX present and not editor-hidden in PlayerRig")
    _expect(rings != null and rings.get_child_count() == 3,
        label + " real 3D scene retains three torus answer lanes")
    if camera == null or rig == null or plane == null:
        return
    var meshes: Array[MeshInstance3D] = []
    _walk_meshes(plane,meshes)
    _expect(meshes.size() == 22, label + " intact source RED FBX has 22 visible geometry parts")
    # CPU camera-frustum projection, not a claim about on-screen pixels. This
    # detects common editor issues: invisible rig, wrong camera, plane behind
    # observer or imported parts reduced to subpixel projected bounds.
    var projected_min := Vector2(INF,INF)
    var projected_max := Vector2(-INF,-INF)
    var projected_points := 0
    var viewport_size := (world.get_node("Viewport3D") as SubViewport).size
    for part in meshes:
        if part.mesh == null or not part.visible:
            continue
        var bounds := part.mesh.get_aabb()
        for px in [bounds.position.x,bounds.end.x]:
            for py in [bounds.position.y,bounds.end.y]:
                for pz in [bounds.position.z,bounds.end.z]:
                    var position3 := part.to_global(Vector3(px,py,pz))
                    if camera.is_position_behind(position3):
                        continue
                    var point2 := camera.unproject_position(position3)
                    if not point2.is_finite():
                        continue
                    projected_min = projected_min.min(point2)
                    projected_max = projected_max.max(point2)
                    projected_points += 1
    var rect := Rect2(projected_min,projected_max-projected_min)
    print("POSE HITBOX camera %s projected_RED=%s samples=%d viewport=%s" %
        [label,rect,projected_points,viewport_size])
    _expect(projected_points > 5, label + " camera sees source FBX vertices in front of lens")
    _expect(rect.size.x >= 28.0 and rect.size.y >= 12.0,
        label + " RED plane is at least human-readable pixels in the camera projection")
    _expect(rect.position.x < viewport_size.x and rect.end.x > 0.0
        and rect.position.y < viewport_size.y and rect.end.y > 0.0,
        label + " RED plane projection intersects actual game viewport")


func _walk_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _walk_meshes(child,result)


func _check_visible_gpu() -> void:
    # Separate optional visible OpenGL validation; no device/webcam or files in
    # project directories. Actual capture resides in Godot user:// if requested.
    _expect(DisplayServer.get_name() != "headless",
        "Optional --gpu validation requires real OpenGL window, not headless")
    if DisplayServer.get_name() == "headless":
        return
    for dimensions in VIEWPORTS:
        DisplayServer.window_set_size(dimensions)
        root.size = dimensions
        root.content_scale_size = dimensions
        var view := load("res://ui/minigames/human_plane_3d_view.tscn").instantiate() as SubViewportContainer
        root.add_child(view)
        view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        view.sync_flight(0.5, {"options":["APPLE","TEACHER","DOG"],"valid_indices":[1]},
            0.42, {}, 0.0, false, -1, false, false, false, 0.70, true)
        for i in range(8):
            await process_frame
        await RenderingServer.frame_post_draw
        var picture := root.get_texture().get_image()
        _expect(picture != null, "Real GPU capture generated at " + str(dimensions))
        if picture != null:
            var bright_red := 0
            for y in range(int(dimensions.y*0.55),int(dimensions.y*0.88),4):
                for x in range(int(dimensions.x*0.24),int(dimensions.x*0.76),4):
                    var c := picture.get_pixel(x,y)
                    if c.r > 0.43 and c.r > c.g*1.6 and c.r > c.b*1.6:
                        bright_red += 1
            _expect(bright_red > 18,
                "True GPU RED aircraft present (not invisible), red sample=%d at %s" % [bright_red,dimensions])
            # user:// is explicitly outside the workspace; avoid test PNG
            # clutter and do not write back into production resources.
            var path := "user://human_plane_pose_hitbox_%dx%d.png" % [dimensions.x,dimensions.y]
            _expect(picture.save_png(path) == OK, "GPU screenshot saved to " + path)
            print("POSE HITBOX GPU capture ",ProjectSettings.globalize_path(path))
        view.queue_free()
        await process_frame
        await process_frame
        # The student reports invisibility in the ACTUAL gameplay composition,
        # not merely in a standalone 3D scene. Compare two adjacent, otherwise
        # frozen full-game GPU frames with the original source FBX toggled
        # visible/invisible. This isolates airplane pixels from red HUD artwork
        # and guards against a CanvasLayer or scene visibility overlay hiding it.
        var game := GAME.instantiate() as Control
        root.add_child(game)
        game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        game.set_context({"activity":"Human Plane", "topic":"Noun",
            "difficulty":"Normal", "game_mode":"Seconds"})
        await process_frame
        await process_frame
        game.set_process(false)
        var full_view := game.get_node_or_null("WorldView3D") as SubViewportContainer
        var full_plane := game.get_node_or_null(
            "WorldView3D/Viewport3D/FlightWorld/PlayerRig/RedPlane") as Node3D
        _expect(full_view != null and full_plane != null,
            "Actual Human Plane gameplay scene retains full3D view and source FBX at " + str(dimensions))
        if full_view != null and full_plane != null:
            full_view.set_process(false)
            game.set("plane_x_norm", 0.5)
            game.call("_sync_visuals")
            for _frame in range(5):
                await process_frame
            await RenderingServer.frame_post_draw
            var showing := root.get_texture().get_image()
            _expect(showing != null and showing.get_size() == dimensions,
                "Full gameplay GPU screenshot has expected resolution " + str(dimensions))
            if showing != null:
                var bright_with := _count_aircraft_red_pixels(showing, dimensions)
                full_plane.visible = false
                for _frame in range(4):
                    await process_frame
                await RenderingServer.frame_post_draw
                var hidden := root.get_texture().get_image()
                var bright_without := _count_aircraft_red_pixels(hidden, dimensions)
                _expect(bright_with >= bright_without + 12,
                    "Original RED FBX is visibly composited in REAL gameplay, delta red pixels=%d at %s" %
                    [bright_with - bright_without, dimensions])
                _expect(showing.save_png("user://human_plane_pose_hitbox_full_%dx%d.png" %
                    [dimensions.x,dimensions.y]) == OK,
                    "Full game screenshot archived in Godot user:// at " + str(dimensions))
                print("POSE HITBOX FULL GAME GPU red with=",bright_with,
                    " without_FBX=",bright_without, " ", dimensions)
                full_plane.visible = true
        game.queue_free()
        await process_frame
        await process_frame


func _count_aircraft_red_pixels(image: Image, dimensions: Vector2i) -> int:
    if image == null:
        return 0
    var count := 0
    for y in range(int(dimensions.y*0.53), int(dimensions.y*0.90), 3):
        for x in range(int(dimensions.x*0.24), int(dimensions.x*0.76), 3):
            var c := image.get_pixel(x,y)
            if c.r > 0.43 and c.r > c.g*1.6 and c.r > c.b*1.6:
                count += 1
    return count


func _expect(ok: bool, description: String) -> void:
    checks += 1
    if not ok:
        failures.append(description)
        printerr("HUMAN PLANE POSE/HITBOX QA FAIL: ",description)


func _finish() -> void:
    for failure in failures:
        print("POSE HITBOX ERROR ",failure)
    print("HUMAN PLANE POSE/HITBOX QA: %s checks=%d failures=%d sampled_body_positions=%d ambiguous_samples=%d" %
        ["PASS" if failures.is_empty() else "FAIL",checks,failures.size(),tested_hitboxes,ambiguous_positions])
    quit(0 if failures.is_empty() else 1)
