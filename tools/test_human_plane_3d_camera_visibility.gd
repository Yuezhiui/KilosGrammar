extends SceneTree

# Camera-frustum + GPU A/B visibility QA for the REAL skinned-FBX-derived
# RedPlane in WorldView3D. Never modifies the game, FBX, camera, or database.
#
# Geometry-only (no hardware):
#   godot --headless --path . --script res://tools/test_human_plane_3d_camera_visibility.gd
# Actual GPU (the GPU mode also checks identical geometry):
#   godot --path . --rendering-method gl_compatibility --script res://tools/test_human_plane_3d_camera_visibility.gd
#
# Source PNGs user://_qa_human_plane_3d_camera_<size>_<phase>_<lane>.png
# are genuine renderer frames. We compare them to the SAME fixed scene with
# ONLY RedPlane.visibility disabled; red rocks, road, gates and sky are thus
# excluded from the airplane visibility proof.
const VIEW := preload("res://ui/minigames/human_plane_3d_view.tscn")
const GAME_SCENE := preload("res://ui/minigames/human_plane.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
# Computed from editor-authored GateEndCenter positions and PlaneLeft/Right
# limits in HumanPlane.tscn, not arbitrary steering points.
var scored_positions: Array[float] = []
var gate_screen_x: Array[float] = []
const PROGRESS := [0.10, 0.35, 0.52]
const WORDS := {"options": ["APPLE", "TEACHER", "DOG"]}
const MIN_PROJECTED_WIDTH_PX := 18.0
const MIN_PROJECTED_HEIGHT_PX := 10.0
# Hard failures should only mean the geometry is genuinely unrecognizable or
# badly oversized. Exact preferred art direction is deliberately advisory;
# it belongs to the scene's editor-authored scale/camera, not a brittle test.
const MIN_IDENTIFIABLE_WINGSPAN_RATIO := 0.08
const MAX_UNOBSTRUCTED_WINGSPAN_RATIO := 0.50
const PREFERRED_WINGSPAN_RATIO := 0.10
const MIN_CHANGED_PIXEL_SAMPLES := 24
const MIN_RED_PIXEL_SAMPLES := 12

var checks := 0
var failures: Array[String] = []
var gpu := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	gpu = DisplayServer.get_name() != "headless"
	for dimensions in SIZES:
		await _check_resolution(dimensions)
	print("HUMAN PLANE 3D CAMERA VISIBILITY: %s (%d checks, %d failures; %s)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size(),
		"real GPU red-plane pixel diff" if gpu else "headless camera-frustum geometry"])
	quit(0 if failures.is_empty() else 1)


func _read_actual_authored_gate_lanes() -> void:
	scored_positions.clear()
	gate_screen_x.clear()
	var game := GAME_SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {"activity": "Human Plane", "topic": "Noun",
		"difficulty": "Normal", "game_mode": "Seconds",
		"camera_live": false, "keyboard_mode": false})
	await process_frame
	game.set_process(false)
	var ends: Array[Control] = [
		game.get_node("FlightPaths/GateEndLeft") as Control,
		game.get_node("FlightPaths/GateEndCenter") as Control,
		game.get_node("FlightPaths/GateEndRight") as Control,
	]
	var left_limit := game.get_node("FlightPaths/PlaneLeftLimit") as Control
	var right_limit := game.get_node("FlightPaths/PlaneRightLimit") as Control
	var start := left_limit.anchor_left
	var stop := right_limit.anchor_left
	_check(stop > start, "2D editor-authored plane travel endpoints remain ordered")
	for end in ends:
		var authored_center := (end.anchor_left + end.anchor_right) * 0.5
		gate_screen_x.append(authored_center)
		scored_positions.append((authored_center - start) / (stop - start))
	_check(absf(gate_screen_x[0] - 0.22) < 0.001 and
		absf(gate_screen_x[1] - 0.50) < 0.001 and
		absf(gate_screen_x[2] - 0.78) < 0.001,
		"actual GateEnd authored centers are x=.22/.50/.78")
	_check(absf(scored_positions[0] - 0.18539326) < 0.001 and
		absf(scored_positions[1] - 0.5) < 0.001 and
		absf(scored_positions[2] - 0.81460674) < 0.001,
		"original outer GateEnd CONTROL anchor centers give raw .1854/.5/.8146")
	# The original GateEnd Control anchors are intentionally broader than the
	# true drawn/swinging gate sprite. HumanPlane._lane_hit_at_answer_line()
	# collides with _gate_visible_rect() plus the plane's authored hitbox offset.
	# Thus a .22 outer-box anchor center IS NOT the authoritative score target.
	# Read and verify the exact exported runtime scoring centers instead.
	var progress := float(game.call("_progress_for_answer_line"))
	var true_scored: PackedFloat32Array = game.call(
		"_normalized_scoring_lane_centers", progress)
	_check(true_scored.size() == 3,
		"parent derives 3 exact answer-lane centers from rendered gate sprites")
	if true_scored.size() == 3:
		for i in range(3):
			var normalized := float(true_scored[i])
			game.set("plane_x_norm", normalized)
			_check(int(game.call("_lane_hit_at_answer_line")) == i,
				"real 2D scoring hitbox selects lane %d at renderer target normalized %.6f" %
				[i, normalized])
		scored_positions.clear()
		for raw in true_scored:
			scored_positions.append(float(raw))
		print("PLANE CAMERA SOURCE: actual score sprite/hitbox body norms = ", scored_positions)
	game.queue_free()
	await process_frame


func _check_resolution(dimensions: Vector2i) -> void:
	if gpu:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(dimensions)
	root.size = dimensions
	root.content_scale_size = dimensions
	await _read_actual_authored_gate_lanes()
	if scored_positions.size() != 3:
		return
	var view := VIEW.instantiate() as SubViewportContainer
	_check(view != null, "%s actual 3D scene instantiates" % dimensions)
	if view == null:
		return
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	view.set_process(false)  # No background foliage movement between GPU A/B shots.
	# Parent HumanPlane._sync_visuals() explicitly sends CURRENT scoring centers
	# to this renderer before sync_flight. Reproduce that same production bridge;
	# a standalone view with 1280-default fallback centers is not the integration.
	view.call("set_scoring_lane_centers", PackedFloat32Array(scored_positions))
	var sub := view.get_node_or_null("Viewport3D") as SubViewport
	var camera := view.get_node_or_null("Viewport3D/FlightWorld/Camera3D") as Camera3D
	var rig := view.get_node_or_null("Viewport3D/FlightWorld/PlayerRig") as Node3D
	var plane := view.get_node_or_null("Viewport3D/FlightWorld/PlayerRig/RedPlane") as Node3D
	_check(sub != null and camera != null and rig != null and plane != null,
		"%s exact real camera/RedPlane/player rig path exists" % dimensions)
	if sub == null or camera == null or rig == null or plane == null:
		view.queue_free()
		await process_frame
		return
	if gpu:
		sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# Parent SubViewportContainer.stretch=true owns subviewport sizing.
		# Never assign sub.size manually: Godot warns and ignores it.
		for _i in range(4):
			await process_frame
	_check(camera.current and not sub.disable_3d, "%s active native Camera3D renders 3D world" % dimensions)
	var parts: Array[MeshInstance3D] = []
	_collect_meshes(plane, parts)
	_check(parts.size() >= 20, "%s real RedPlane FBX retains at least 20 original meshes" % dimensions)
	var material_count := 0
	for part in parts:
		if part.mesh != null and part.mesh.get_surface_count() > 0 and part.get_active_material(0) != null:
			material_count += 1
	_check(material_count >= 20,
		"%s original plane FBX meshes have rendering materials (count=%d)" %
		[dimensions, material_count])

	for index in range(scored_positions.size()):
		var pose_x: float = scored_positions[index]
		for j in range(PROGRESS.size()):
			var progress: float = PROGRESS[j]
			var label := "%dx%d x=%.2f progress=%.2f" % [
				dimensions.x, dimensions.y, pose_x, progress]
			view.call("sync_flight", pose_x, WORDS, progress, {}, 0.0,
				false, -1, false, false, true, 0.55, true)
			var ring_center: Node3D = view.get_node(
				"Viewport3D/FlightWorld/CurrentRings/Gate" +
				["Left", "Center", "Right"][index]) as Node3D
			var expected_x: float = float([-6.0, 0.0, 6.0][index])
			_check(absf(ring_center.position.x - expected_x) <= 0.02,
				label + " actual 3D target gate center matches expected lane world X")
			_check(absf(rig.position.x - expected_x) <= 0.25,
				label + " ACTUAL scored sprite/Hitbox center aligns aircraft with 3D ring X=%s, got %s" %
				[str(expected_x), str(rig.position.x)])
			var bounds := _source_mesh_bounds(parts)
			_check(bounds.size.length() > 0.00001,
				label + " actual FBX nonzero world mesh bounds")
			var project := _project_bounds(camera, bounds, dimensions)
			var screen: Rect2 = project["screen"]
			var all_front: bool = project["all_front"]
			_check(all_front, label + " no aircraft corners behind active camera")
			_check(screen.has_area() and
				screen.size.x >= MIN_PROJECTED_WIDTH_PX and
				screen.size.y >= MIN_PROJECTED_HEIGHT_PX,
				label + " projected aircraft is large enough to identify, bbox=" + str(screen))
			var apparent_width_ratio := screen.size.x / float(dimensions.x)
			_check(apparent_width_ratio >= MIN_IDENTIFIABLE_WINGSPAN_RATIO and
				apparent_width_ratio <= MAX_UNOBSTRUCTED_WINGSPAN_RATIO,
				label + " enlarged airplane is identifiable (8%-50% viewport); got %.2f%%" %
				[apparent_width_ratio * 100.0])
			if apparent_width_ratio < PREFERRED_WINGSPAN_RATIO:
				print("PLANE CAMERA ART-DIRECTION ADVISORY ", label,
					" plane occupies only %.2f%% of viewport width; consider target >= 10%%" %
					[apparent_width_ratio * 100.0])
			var inset := Rect2(Vector2(4, 4), Vector2(dimensions) - Vector2(8, 8))
			_check(inset.encloses(screen),
				label + " entire projected aircraft stays inside 4px screen margin, bbox=" + str(screen))
			var word_rects := _word_screen_boxes(camera, view, dimensions)
			for word_index in range(word_rects.size()):
				var word_box: Rect2 = word_rects[word_index]
				var intersection := screen.intersection(word_box)
				var fractional_occlusion := intersection.get_area() / maxf(word_box.get_area(), 1.0)
				_check(fractional_occlusion <= 0.18,
					label + " plane projected bounds do not obscure lane %d word (%.1f%%)" %
					[word_index, fractional_occlusion * 100.0])
			if gpu:
				await _check_gpu_visibility(sub, plane, screen, word_rects,
					dimensions, index, j, label)
	view.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(view), "%s 3D world/camera/render-target teardown" % dimensions)


func _source_mesh_bounds(parts: Array[MeshInstance3D]) -> AABB:
	var total := AABB()
	var first := true
	for part in parts:
		if part.mesh == null:
			continue
		var box := part.global_transform * part.mesh.get_aabb()
		if first:
			total = box
			first = false
		else:
			total = total.merge(box)
	return total


func _project_bounds(camera: Camera3D, bounds: AABB, dimensions: Vector2i) -> Dictionary:
	# Camera3D.unproject_position() uses the SubViewport pixel scale; if the
	# viewport has not yet resized, compensate from actual camera viewport.
	var actual := Vector2(camera.get_viewport().size)
	var normalize := Vector2(dimensions) / actual
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var all_front := true
	for x in [0.0, 1.0]:
		for y in [0.0, 1.0]:
			for z in [0.0, 1.0]:
				var vertex := bounds.position + bounds.size * Vector3(x, y, z)
				if camera.is_position_behind(vertex):
					all_front = false
					continue
				var pixel := camera.unproject_position(vertex) * normalize
				lo = lo.min(pixel)
				hi = hi.max(pixel)
	if not is_finite(lo.x) or not is_finite(hi.x):
		return {"screen": Rect2(), "all_front": false}
	return {"screen": Rect2(lo, hi - lo), "all_front": all_front}


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


func _word_screen_boxes(camera: Camera3D, view: Node, dimensions: Vector2i) -> Array[Rect2]:
	var projected: Array[Rect2] = []
	var viewport_scale := Vector2(dimensions) / Vector2(camera.get_viewport().size)
	for lane in ["Left", "Center", "Right"]:
		var path: String = "Viewport3D/FlightWorld/CurrentRings/Gate" + lane + "/WordLabel"
		var word := view.get_node_or_null(path) as Label3D
		if word == null or word.font == null or word.text.is_empty():
			projected.append(Rect2())
			continue
		var glyph_px := word.font.get_string_size(word.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, word.font_size)
		var half_w := 0.5 * (glyph_px.x + 2.0 * word.outline_size) * word.pixel_size
		var half_h := 0.5 * (glyph_px.y + 2.0 * word.outline_size) * word.pixel_size
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for u in [-1.0, 1.0]:
			for v in [-1.0, 1.0]:
				var p := word.global_transform * Vector3(u * half_w, v * half_h, 0)
				var pixel := camera.unproject_position(p) * viewport_scale
				lo = lo.min(pixel)
				hi = hi.max(pixel)
		projected.append(Rect2(lo, hi - lo))
	return projected


func _check_gpu_visibility(sub: SubViewport, plane: Node3D, projected: Rect2,
		word_rects: Array[Rect2],
		dimensions: Vector2i, pos_index: int, depth_index: int, label: String) -> void:
	plane.visible = true
	for _i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var with_plane := sub.get_texture().get_image()
	plane.visible = false
	for _i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var without_plane := sub.get_texture().get_image()
	plane.visible = true
	_check(with_plane != null and without_plane != null and
		with_plane.get_size() == dimensions and without_plane.get_size() == dimensions,
		label + " both A/B real GPU captures are exact viewport size")
	if (with_plane == null or without_plane == null or
			with_plane.get_size() != dimensions or without_plane.get_size() != dimensions):
		return
	var area := projected.grow(12.0)
	var min_x := maxi(0, int(floor(area.position.x)))
	var min_y := maxi(0, int(floor(area.position.y)))
	var max_x := mini(dimensions.x - 1, int(ceil(area.end.x)))
	var max_y := mini(dimensions.y - 1, int(ceil(area.end.y)))
	var changed := 0
	var changed_red := 0
	# Negative control: capture *two* hidden-plane frames to prove background
	# motion/sky/glow cannot spuriously make the aircraft A/B pixel test pass.
	plane.visible = false
	for _i in range(2):
		await process_frame
	await RenderingServer.frame_post_draw
	var second_background := sub.get_texture().get_image()
	plane.visible = true
	var unstable_background := 0
	for y in range(min_y, max_y + 1, 2):
		for x in range(min_x, max_x + 1, 2):
			var plane_color := with_plane.get_pixel(x, y)
			var background_color := without_plane.get_pixel(x, y)
			var delta := absf(plane_color.r - background_color.r) + \
				absf(plane_color.g - background_color.g) + absf(plane_color.b - background_color.b)
			if delta > 0.22:
				changed += 1
				if (plane_color.r > plane_color.g * 1.25 and
						plane_color.r > plane_color.b * 1.25 and plane_color.r > 0.25):
					changed_red += 1
			var bg1 := background_color
			var bg2 := second_background.get_pixel(x, y)
			if absf(bg1.r - bg2.r) + absf(bg1.g - bg2.g) + absf(bg1.b - bg2.b) > 0.22:
				unstable_background += 1
	_check(unstable_background <= 3,
		label + " negative control proves same non-airplane scene is static: " + str(unstable_background))
	_check(changed >= MIN_CHANGED_PIXEL_SAMPLES,
		label + " actual RedPlane toggling changes real pixels in projected ROI: " + str(changed))
	_check(changed_red >= MIN_RED_PIXEL_SAMPLES,
		label + " visible diff contains red source-FBX pixels: " + str(changed_red))
	# Supplemental pixel-level check: the genuine plane must not paint red over
	# the projected THREE active WordLabel3D regions.
	for word_index in range(word_rects.size()):
		var word_box: Rect2 = word_rects[word_index]
		if not word_box.has_area():
			continue
		var sx := maxi(0, int(floor(word_box.position.x)))
		var sy := maxi(0, int(floor(word_box.position.y)))
		var ex := mini(dimensions.x, int(ceil(word_box.end.x)))
		var ey := mini(dimensions.y, int(ceil(word_box.end.y)))
		var red_occlusions := 0
		var samples := 0
		for y in range(sy, ey, 3):
			for x in range(sx, ex, 3):
				samples += 1
				var color := with_plane.get_pixel(x, y)
				var no_plane := without_plane.get_pixel(x, y)
				var delta := absf(color.r - no_plane.r) + absf(color.g - no_plane.g) + absf(color.b - no_plane.b)
				if delta > 0.22 and color.r > color.g * 1.25 and color.r > color.b * 1.25:
					red_occlusions += 1
		_check(red_occlusions <= maxi(2, roundi(float(samples) * 0.02)),
			label + " rendered RedPlane doesn't paint over 3D ring word %d (%d/%d red samples)" %
			[word_index, red_occlusions, samples])
	print("PLANE CAMERA GPU ", label, " projected=", projected,
		" changed_2px_samples=", changed, " red_samples=", changed_red)
	# Nine representative screenshots, spread over camera steering + progress.
	if depth_index == pos_index:
		var phase: String = ["far", "mid", "near"][depth_index]
		var lane: String = ["left", "center", "right"][pos_index]
		var output := "user://_qa_human_plane_3d_camera_%dx%d_%s_%s.png" % [
			dimensions.x, dimensions.y, phase, lane]
		_check(with_plane.save_png(ProjectSettings.globalize_path(output)) == OK,
			label + " saved actual source-FBX on-camera GPU screenshot " + output)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("PLANE CAMERA VISIBILITY FAIL: ", description)
