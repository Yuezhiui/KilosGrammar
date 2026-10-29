extends SceneTree

# Godot 4.7 --headless --path . --script res://tools/test_human_plane_visual_gate_depth.gd
# Also run with OpenGL to save real renderer screenshots at two resolutions.
# Verifies authored scene/gate depth with three-position, wide-arm body motion.
const SCENE := preload("res://ui/minigames/human_plane/human_plane.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]
const STEP := 1.0 / 60.0

var issues: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dimensions in SIZES:
		for level in DIFFICULTIES:
			for mode in MODES:
				await _exercise(dimensions, level, mode)
	print("HUMAN PLANE DEPTH/GATE/BODY: %s (%d assertions, %d failures)" %
		["PASS" if issues.is_empty() else "FAIL", checks, issues.size()])
	quit(0 if issues.is_empty() else 1)


func _exercise(dimensions: Vector2i, level: String, mode: String) -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(dimensions)
		root.content_scale_size = dimensions
	root.size = dimensions
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"difficulty":level, "topic":"Noun", "game_mode":mode, "activity":"Human Plane"})
	await process_frame
	await process_frame
	game.set_process(false)
	var title := "%s/%s/%s" % [dimensions, level, mode]
	var hybrid := game.get_node_or_null("HybridFlight3D") as Node2D
	_check(hybrid != null and bool(hybrid.get("hybrid_enabled"))
		and bool(hybrid.get("draw_3d_gates"))
		and not (game.get_node("PlaneRig/PlaneArtwork") as TextureRect).visible,
		title + " native 3D airplane and TorusMesh gates load by default")
	if hybrid != null:
		hybrid.set("hybrid_enabled", true)
		hybrid.set("draw_3d_gates", true)
		hybrid.call("_process", 0.0)
	_check(hybrid != null and bool(hybrid.get("hybrid_enabled"))
		and bool(hybrid.get("draw_3d_gates")),
		title + " native 3D gate/airplane renderer can be explicitly enabled")
	if hybrid != null:
		var viewport := hybrid.get_node_or_null("RenderViewport") as SubViewport
		var camera := hybrid.get_node_or_null("RenderViewport/FlightWorld3D/Camera") as Camera3D
		_check(viewport != null and camera != null and not viewport.transparent_bg
			and viewport.own_world_3d and camera.projection == Camera3D.PROJECTION_PERSPECTIVE,
			title + " genuinely composited perspective 3D sky scene exists")
		var before_words := (game.get("round_data") as Dictionary).duplicate(true)
		hybrid.set("hybrid_enabled", false)
		hybrid.call("_process", 0.0)
		_check(_fully_opaque_trio(game.get("_gate_nodes") as Array[Control])
			and (game.get_node("PlaneRig/PlaneArtwork") as TextureRect).visible,
			title + " original 2D aircraft and solid PNG gates restore when hybrid disabled")
		hybrid.set("hybrid_enabled", true)
		hybrid.set("draw_3d_gates", false)
		hybrid.call("_process", 0.0)
		_check(_fully_opaque_trio(game.get("_gate_nodes") as Array[Control])
			and not (game.get_node("PlaneRig/PlaneArtwork") as TextureRect).visible,
			title + " fallback gate PNGs work independently of native 3D airplane")
		hybrid.set("draw_3d_gates", true)
		hybrid.call("_process", 0.0)
		_check(_fully_opaque_trio(game.get("_gate_nodes") as Array[Control])
			and (game.get("round_data") as Dictionary) == before_words
			and int(game.get("attempts")) == 0 and int(game.get("score")) == 0,
			title + " native TorusMesh gates restore without changing words, hits or score")
	var current := game.get_node("MovingGates") as Control
	var incoming := game.get_node("UpcomingGates") as Control
	var airplane := game.get_node("PlaneRig") as Control
	_check(current.z_index < airplane.z_index, title + " approaching artwork rendered behind plane")
	_check(incoming.z_index < airplane.z_index, title + " horizon artwork rendered behind plane")
	_check(int(game.get("lives")) == 3, title + " three hearts")
	_check(float(game.get("time_remaining")) >= 59.0 if mode == "Seconds"
		else is_zero_approx(float(game.get("time_remaining"))), title + " correct timer mode")
	var config: Dictionary = game.DIFFICULTY_CONFIG[level]
	var speed := float(config["gate_speed"])
	_check(speed <= 0.35, title + " gates approach slowly")
	if level == "Normal":
		_check(speed > float(game.DIFFICULTY_CONFIG["Easy"]["gate_speed"]), title + " normal progression")
	if level == "Hard":
		_check(speed > float(game.DIFFICULTY_CONFIG["Normal"]["gate_speed"]), title + " hard progression")
	# Center T-pose calibration precedes proportional signed arm-bank steering.
	game.call("set_airplane_pose_active", true)
	game.call("set_body_x", 0.40)
	var x_before := float(game.get("plane_x_norm"))
	for _i in range(30):
		game.call("_update_plane_motion", STEP)
	var x_right := float(game.get("plane_x_norm"))
	# 40% arm bank requests 40% of the .82/s cap, not full-speed .82/s.
	_check(x_right > x_before + 0.10 and x_right <= x_before + 0.40 * 0.82 * 0.5 + 0.001,
		title + " right arm bank advances smoothly at capped velocity")
	game.call("set_body_x", 0.0)
	for _i in range(48):
		game.call("_update_plane_motion", STEP)
	var x_neutral := float(game.get("plane_x_norm"))
	_check(absf(x_neutral - x_right) < 0.04,
		title + " neutral T-pose brakes and holds current position")
	for _i in range(15):
		game.call("_update_plane_motion", STEP)
	_check(absf(float(game.get("plane_x_norm")) - x_neutral) < 0.002,
		title + " sustained neutral T-pose holds its flight path")
	game.call("set_body_x", -0.40)
	for _i in range(30):
		game.call("_update_plane_motion", STEP)
	_check(float(game.get("plane_x_norm")) < x_neutral - 0.10,
		title + " left arm bank smoothly sends airplane left")
	game.call("set_airplane_pose_active", false)
	var lost_x := float(game.get("plane_x_norm"))
	for _i in range(30):
		game.call("_update_plane_motion", STEP)
	_check(is_equal_approx(float(game.get("plane_x_norm")), lost_x),
		title + " lowering arms freezes instantly")
	game.call("set_airplane_pose_active", true)
	# Position, collision, and painting must agree after motion easing.
	for p in [0.1, 0.33, 0.58, 0.9]:
		game.set("gate_progress", p)
		game.call("_sync_visuals")
		var gate: Control = (game.get("_gate_nodes") as Array)[1]
		var predicted: Rect2 = game.call("_gate_rect", 1, p)
		# The hitbox remains on its editor-authored lane, while its *painted*
		# wooden word plaque follows the actual TorusMesh projection. Compare
		# against the real 3D projection, not the obsolete unprojected hitbox.
		var visible_rect: Rect2 = game.call("_gate_visible_rect_with_offsets", 1, p,
			game.get("_authored_gate_rect_offsets"), game.get("_gate_nodes"))
		var projected: Vector2 = hybrid.call("gate_screen_center", 1, p, visible_rect,
			false, game.get("_authored_gate_rect_offsets"), game.get("_gate_nodes"))
		var expected_center := predicted.get_center() + projected - visible_rect.get_center()
		_check(gate.get_rect().size.is_equal_approx(predicted.size) and
			gate.get_rect().get_center().distance_to(expected_center) < 1.5 and
			visible_rect.has_area(),
			title + " editable collision lane intact and 2D plaque matches projected torus at %.2f" % p)
	_check(float(game.call("_gate_y", 0.3)) < float(game.call("_gate_y", 0.6)),
		title + " eased path still approaches monotonically")
	var answer_p := float(game.call("_progress_for_answer_line"))
	_check(answer_p > 0.0 and answer_p < 1.0 and
		absf(float(game.call("_gate_y", answer_p)) - float(game.call("_answer_line_y"))) < 1.0,
		title + " easing keeps answer collision aligned to painted gate")
	for progress in [answer_p, minf(answer_p + 0.19, 1.0)]:
		game.set("gate_progress", progress)
		game.call("_sync_visuals")
		_check(_fully_opaque_trio(game.get("_gate_nodes") as Array[Control]),
			title + " all three volumetric 3D gates and editor word plaques stay solid at %.2f" % progress)
		_check(current.visible and not incoming.visible and _ring_pool_count(hybrid) == 6,
			title + " current real ring trio survives scoring depth with fixed six-ring pool at %.2f" % progress)
	# Restore the active motion and drive the real two-wave handoff.
	game.set("gate_progress", 0.0)
	game.call("_sync_visuals")
	var first_words: Dictionary = (game.get("round_data") as Dictionary).duplicate(true)
	var first_gate: Control = (game.get("_gate_nodes") as Array)[1]
	var before_gate_center := first_gate.get_rect().get_center().y
	game.call("_update_gate_wave", 0.08 / speed)
	game.call("_sync_visuals")
	_check(first_gate.get_rect().get_center().y > before_gate_center,
		title + " gates continue moving continuously")
	var prefetch_step := (float(game.GATE_PREFETCH_AT) + 0.04 - float(game.get("gate_progress"))) / speed
	game.call("_update_gate_wave", prefetch_step)
	game.call("_sync_visuals")
	_check(not (game.get("next_round_data") as Dictionary).is_empty(),
		title + " next wave preloads before current passes")
	_check(incoming.visible and current.visible and
		_fully_opaque_trio(game.get("_gate_nodes") as Array[Control]) and
		_fully_opaque_trio(game.get("_upcoming_gate_nodes") as Array[Control], true) and
		_ring_pool_count(hybrid) == 6,
		title + " six real bounded torus rings with two genuine opaque vocabulary trios, no ghosts")
	var incoming_gate: Control = (game.get("_upcoming_gate_nodes") as Array)[1]
	var queued_rect: Rect2 = game.call("_gate_rect_with_offsets", 1,
		float(game.get("next_gate_progress")), game.get("_upcoming_rect_offsets"))
	_check(queued_rect.size.y < first_gate.get_rect().size.y,
		title + " visible incoming trio keeps its authored earlier flight depth")
	var outgoing_group := first_gate.get_parent() as Control
	var incoming_group := incoming_gate.get_parent() as Control
	var queued_id := incoming_gate.get_instance_id()
	if DisplayServer.get_name() != "headless" and level == "Normal" and mode == "Seconds":
		await _capture(game, dimensions, "approach")
	var approach_data := (game.get("next_round_data") as Dictionary).duplicate(true)
	var completed := false
	var incoming_pos := Vector2.ZERO
	for _step in range(450):
		game.call("_update_gate_wave", STEP)
		game.call("_sync_visuals")
		if int(game.get("waves_completed")) >= 1:
			completed = true
			incoming_pos = incoming_gate.position
			break
	_check(completed, title + " passes current wave and hands off")
	if completed and not bool(game.get("finished")):
		_check(int(game.get("attempts")) == 1, title + " scores only once")
		_check((game.get("round_data") as Dictionary).get("options", []) ==
			approach_data.get("options", []), title + " prefetched unique options promoted")
		_check((game.get("round_data") as Dictionary).get("options", []) !=
			first_words.get("options", []), title + " different incoming word set")
		_check(incoming_gate.get_instance_id() == queued_id and
			(game.get("_gate_nodes") as Array)[1] == incoming_gate,
			title + " actual prefetched editor gate becomes active without re-creation")
		_check(incoming_group.visible and not outgoing_group.visible and
			_fully_opaque_trio(game.get("_gate_nodes") as Array[Control]) and
			_ring_pool_count(hybrid) == 6,
			title + " atomic handoff promotes prefetched real trio, reusing all six ring instances")
		game.call("_update_gate_wave", STEP)
		game.call("_sync_visuals")
		_check(incoming_gate.position.distance_to(incoming_pos) < dimensions.y * 0.03,
			title + " handoff has no image position pop")
		_check(_fully_opaque_trio(game.get("_gate_nodes") as Array[Control])
			and not outgoing_group.visible,
			title + " outgoing trio remains hidden and incoming gate does not alpha-fade")
		_check(float(game.get("gate_progress")) < answer_p,
			title + " student has time to steer before next answer")
		# Check the corrected 3D crossing presentation on an ACTUAL answer-line
		# event: the outgoing labels/wooden plaques disappear, but the matching
		# TorusMesh rings persist through the camera with their source node IDs.
		var valid_lanes: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
		_check(not valid_lanes.is_empty(), title + " promoted authentic wave contains a correct grammar lane")
		if not valid_lanes.is_empty():
			var chosen := int(valid_lanes[0])
			var scored_centers: PackedFloat32Array = game.call("_normalized_scoring_lane_centers", answer_p)
			game.set("plane_x_norm", float(scored_centers[chosen]))
			_check(int(game.call("_lane_hit_at_answer_line")) == chosen,
				title + " real airplane hitbox enters the correct torus")
			var before_score := int(game.get("score"))
			var before_attempts := int(game.get("attempts"))
			game.set("gate_progress", minf(answer_p + 0.03, 0.97))
			game.call("_resolve_at_answer_line")
			game.call("_sync_visuals")
			_check(int(game.get("score")) == before_score + 100 and
				int(game.get("attempts")) == before_attempts + 1 and
				bool(game.get("selected_was_correct")) and
				_fully_opaque_trio(game.get("_gate_nodes") as Array[Control]),
				title + " +100 correct collision, outgoing 2D word labels hidden while 3D torus remains")
			game.call("_resolve_at_answer_line")
			_check(int(game.get("score")) == before_score + 100 and
				int(game.get("attempts")) == before_attempts + 1,
				title + " no double score when outgoing ring remains in 3D")
		if DisplayServer.get_name() != "headless" and level == "Normal" and mode == "Seconds":
			await _capture(game, dimensions, "handoff")
	elif completed:
		_check(false, title + " game unexpectedly finished during first handoff")
	game.queue_free()
	await process_frame
	await process_frame


func _capture(game: Control, dimensions: Vector2i, phase: String) -> void:
	game.call("_sync_visuals")
	for _i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var file := "user://human_plane_depth_%dx%d_%s.png" % [dimensions.x, dimensions.y, phase]
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(file))
	_check(error == OK, "renderer screenshot created: " + file)
	print("HUMAN PLANE SCREENSHOT: " + ProjectSettings.globalize_path(file))


func _check(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		issues.append(reason)
		printerr("HUMAN PLANE DEPTH FAIL: " + reason)


func _ring_pool_count(hybrid: Node2D) -> int:
	if hybrid == null:
		return 0
	var pools: Array = hybrid.get("_ring_pools")
	if pools.size() != 2:
		return 0
	var ids := {}
	for pool in pools:
		if not pool is Array or (pool as Array).size() != 3:
			return 0
		for instance in pool:
			var gate := instance as Node3D
			if gate == null or ids.has(gate.get_instance_id()):
				return 0
			var ring := gate.get_node_or_null("Ring") as MeshInstance3D
			if ring == null or not (ring.mesh is TorusMesh):
				return 0
			ids[gate.get_instance_id()] = true
	return ids.size()


func _fully_opaque_trio(gates: Array[Control], upcoming: bool = false) -> bool:
	if gates.size() != 3:
		return false
	var group := gates[0].get_parent() as Control
	var game := group.get_parent() as Control if group != null else null
	if game == null or not group.visible:
		return false
	var hybrid := game.get_node_or_null("HybridFlight3D") as Node2D
	var using_3d: bool = hybrid != null and bool(hybrid.get("hybrid_enabled")) and bool(hybrid.get("draw_3d_gates"))
	var data: Dictionary = game.get("next_round_data") if upcoming else game.get("round_data")
	var options: Array = data.get("options", [])
	var valid: Array = data.get("valid_indices", [])
	if options.size() != 3 or valid.is_empty():
		return false
	var seen := {}
	var bank: Script = game.get("grammar_bank") as Script
	for i in range(3):
		var word := String(options[i]).strip_edges().to_lower()
		if (word.is_empty() or seen.has(word) or bank == null or
				bool(bank.call("is_matching", word, String(game.get("topic")))) != (i in valid)):
			return false
		seen[word] = true
	var progress := float(game.get("next_gate_progress")) if upcoming else float(game.get("gate_progress"))
	var resolved: bool = not upcoming and bool(game.get("gate_resolved"))
	var passage_alpha := float(game.call("_gate_passage_alpha", progress)) if resolved else 1.0
	if hybrid != null:
		hybrid.call("_process", 0.0)
	if using_3d:
		var overlay := hybrid.get_node_or_null("OverlayTexture") as TextureRect
		if overlay == null or not overlay.visible or overlay.texture == null or _ring_pool_count(hybrid) != 6:
			return false
	var pools: Array = hybrid.get("_ring_pools") if hybrid != null else []
	var group_index := 0 if group == game.get_node("MovingGates") else 1
	for i in range(3):
		var gate := gates[i]
		if not gate.visible or absf(gate.modulate.a - passage_alpha) > 0.002:
			return false
		var artwork := gate.get_node_or_null("GateArtwork") as TextureRect
		var word := gate.get_node_or_null("WordLabel") as Label
		var plate := gate.get_node_or_null("WordPlate") as CanvasItem
		if (artwork == null or artwork.texture == null or artwork.visible == using_3d or word == null or plate == null or
				word.visible == resolved or plate.visible == resolved or word.modulate.a < 0.999 or
				word.text != String(options[i]).to_upper()):
			return false
		if using_3d:
			var ring3d := (pools[group_index] as Array)[i] as Node3D
			if ring3d == null or ring3d.visible != (passage_alpha > 0.001):
				return false
			if not ring3d.visible:
				continue
			var mesh := ring3d.get_node_or_null("Ring") as MeshInstance3D
			if (mesh == null or not mesh.visible or not (mesh.mesh is TorusMesh) or
					not (mesh.material_override is StandardMaterial3D) or
					absf((mesh.material_override as StandardMaterial3D).albedo_color.a - passage_alpha) > 0.002 or
					ring3d.scale.x <= 0.0 or ring3d.scale.y <= 0.0):
				return false
	return true
