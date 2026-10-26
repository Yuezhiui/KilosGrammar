extends SceneTree

# Focused presentation-only 3D geometry and constant-velocity ring regression.
# Godot --headless --path . --script res://tools/test_human_plane_3d_scale_flow.gd
# Does not activate webcam, alter scores, or touch databases.
const VIEW: PackedScene = preload("res://ui/minigames/human_plane_3d_view.tscn")
const GAME: PackedScene = preload("res://ui/minigames/human_plane.tscn")
const OPTIONS := ["LONGER WORDS", "FLOWER", "RUN"]
const CAPTURE_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var checked := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var view := VIEW.instantiate() as SubViewportContainer
	var authored_camera := view.get_node("Viewport3D/FlightWorld/Camera3D") as Camera3D
	var authored_aim := authored_camera.transform.basis
	root.add_child(view)
	_check(authored_camera.transform.basis.is_equal_approx(authored_aim),
		"Camera3D startup retains its editor-authored aim without runtime override")
	view.set_process(false)
	var world := view.get_node("Viewport3D/FlightWorld") as Node3D
	var player_rig := world.get_node("PlayerRig") as Node3D
	var plane := player_rig.get_node("RedPlane") as Node3D
	var center := world.get_node("CurrentRings/GateCenter") as Node3D
	var frame_left := center.get_node("FrameLeft") as MeshInstance3D
	var frame_right := center.get_node("FrameRight") as MeshInstance3D
	var top := center.get_node("FrameTop") as MeshInstance3D
	var bottom := center.get_node("FrameBottom") as MeshInstance3D
	_check(frame_left.mesh is CapsuleMesh and frame_right.mesh is CapsuleMesh \
			and top.mesh is CapsuleMesh and bottom.mesh is CapsuleMesh,
			"answer gates use four real, editor-authored 3D portrait-frame edges")
	_check(player_rig.scale.is_equal_approx(Vector3.ONE),
		"user-authored PlayerRig scale remains exactly 1.00")
	_check(is_equal_approx(absf(plane.scale.x), 100.0) and
		is_equal_approx(absf(plane.scale.y), 100.0) and
		is_equal_approx(absf(plane.scale.z), 100.0),
		"original artist RedPlane node stays at user-requested 100 scale")
	_check(player_rig.get_node_or_null("RedPlaneImportNormalization") == null,
		"RedPlane has no hidden parent scale normalization or multiplied editor transform")
	# The FBX import itself owns native unit normalization; the editor tree
	# exposes precisely the requested 100x RedPlane and 1x PlayerRig.
	var source_scale_width := _mesh_bounds_width(plane, player_rig)
	var visible_world_width := _mesh_bounds_width(plane)
	print("RED_PLANE_BOUNDS|rig_local_width=", source_scale_width,
		"|visible_world_width=", visible_world_width,
		"|parent_scale=", player_rig.scale,
		"|red_plane_scale=", plane.scale)
	_check(source_scale_width > 1.0,
		"authentic normalized FBX model has a measurable positive wingspan")
	_check(absf(visible_world_width -
			source_scale_width * player_rig.global_basis.get_scale().x) < 0.002,
		"final visible FBX wingspan respects the editor-authored PlayerRig scale")
	if frame_left != null and frame_right != null:
		var portal_width := absf(frame_right.position.x - frame_left.position.x)
		var portal_height := absf(top.position.y - bottom.position.y)
		var ratio: float = visible_world_width / portal_width
		_check(ratio >= 0.55 and ratio <= 0.85,
				"enlarged red plane occupies 55–85% of the portrait portal width")
		_check(absf(portal_width / portal_height - 9.0 / 16.0) < 0.06,
				"portal authored 9:16 silhouette fits three flight lanes")
		_check(portal_width > visible_world_width,
				"real rectangular portal retains an aircraft-sized clear passage")
	var mountains := world.get_node("Terrain/Mountains") as Node3D
	_check(mountains.get_child_count() == 24, "24 user-authored NATURE mountains preserved")
	_check(not mountains.is_visible_in_tree(),
		"retained NATURE mountains do not render into new cloud flight scene")
	var terrain := world.get_node_or_null("Terrain") as Node3D
	var woodland := world.get_node_or_null("Scenery") as Node3D
	_check(terrain == null or not terrain.is_visible_in_tree(),
		"old grass and road are disabled from rendered cloud environment")
	_check(woodland == null or not woodland.is_visible_in_tree(),
		"old woodland and GPU grass assets are not rendered")
	var clouds := world.get_node_or_null("CloudFlight/CloudProps") as Node3D
	_check(clouds != null and clouds.get_child_count() >= 6,
		"editor-authored 3D low-poly clouds replace visible old scenery")
	_check(absf(player_rig.position.z - 7.9) < 0.2,
		"pilot Z stays at authoritative ring crossing depth")
	var authored_y: float = player_rig.position.y
	view._process(1.0 / 60.0)
	_check(absf(player_rig.position.y - authored_y) < 0.08,
		"render animation preserves editor-authored rig height")
	# These norms are actual scored centers measured from the moving artwork
	# and student hitbox, NOT the nominal 2D lane guide rectangles.
	var centers := PackedFloat32Array([0.3267854, 0.4938553, 0.6600475])
	view.set_scoring_lane_centers(centers)
	for index in range(3):
		view.sync_flight(centers[index], {"options": OPTIONS}, 0.50, {}, 0.0,
			false, -1, false, false, false, 0.50, false)
		_check(absf(player_rig.position.x - (float(index) - 1.0) * 6.0) < 0.03,
			"runtime-authoritative hitbox center maps to correct 3D ring lane " + str(index))
	view.set_scoring_lane_centers(PackedFloat32Array([0.7, 0.5, 0.3]))
	view.sync_flight(centers[0], {"options": OPTIONS}, 0.50, {}, 0.0,
		false, -1, false, false, false, 0.50, false)
	_check(absf(player_rig.position.x + 6.0) < 0.03,
		"invalid reordered scoring anchors are rejected without losing the valid mapping")
	view.sync_flight(centers[1], {"options": OPTIONS}, 0.50, {}, 0.0,
		false, -1, false, false, false, 0.50, false)
	for lane in ["Left", "Center", "Right"]:
		var torus_node := world.get_node("CurrentRings/Gate" + lane) as Node3D
		_check(torus_node != null, lane + " ring is editor-authored")
	var progress_values := [0.36, 0.40, 0.44, 0.48, 0.50, 0.52, 0.56, 0.60]
	var positions: Array[float] = []
	for progress in progress_values:
		view.sync_flight(0.5, {"options": OPTIONS}, float(progress), {}, 0.0,
			float(progress) >= 0.50, 1, float(progress) >= 0.50, false, false, 0.5, true)
		positions.append(center.position.z)
	for i in range(1, positions.size()):
		var step_z := positions[i] - positions[i - 1]
		var step_progress: float = progress_values[i] - progress_values[i - 1]
		_check(step_z >= 0.0, "ring never reverses toward crossing " + str(i))
		_check(absf(step_z / step_progress - 59.8) < 0.3,
			"constant Z velocity before/after crossing " + str(i))
	_check(absf(positions[4] - 7.9) <= 0.01,
		"ring crosses exactly at the authoritative 3D answer line")
	var plane_position: Vector3 = (world.get_node("PlayerRig") as Node3D).position
	view.sync_flight(0.5, {"options": OPTIONS}, 0.60, {}, 0.0, true, 1, true,
		false, true, 0.5, true)
	var paused_z := center.position.z
	view._process(0.2)
	_check(is_equal_approx(center.position.z, paused_z), "pausing freezes exact ring depth")
	_check(is_equal_approx(world.get_node("PlayerRig").position.x, plane_position.x),
		"pausing preserves calibrated plane position")
	var label := center.get_node("WordLabel") as Label3D
	_check(label != null and label.text == OPTIONS[1],
		"grammar label still matches authoritative lane word")
	if label != null:
			_check(label.pixel_size >= 0.006 and label.font_size >= 64,
				"long grammar words retain a legible font on the high-contrast plaque")
	# A round may have a different gameplay-authoritative crossing fraction:
	# the same linear pass-through velocity must hold for each.
	for crossing_fraction in [0.35, 0.65]:
		view.sync_flight(0.5, {}, 0.0, {}, 0.0, false, -1, false,
			false, false, crossing_fraction, true)
		var z_samples: Array[float] = []
		for offset in [-0.06, -0.02, 0.02, 0.06]:
			var progress: float = crossing_fraction + offset
			view.sync_flight(0.5, {"options": OPTIONS}, progress, {}, 0.0,
				progress >= crossing_fraction, 1, progress >= crossing_fraction,
				false, false, crossing_fraction, true)
			z_samples.append(center.position.z)
		var expected_slope: float = (7.9 - (-22.0)) / crossing_fraction
		var approach_slope: float = (z_samples[1] - z_samples[0]) / 0.04
		var crossing_slope: float = (z_samples[2] - z_samples[1]) / 0.04
		var exit_slope: float = (z_samples[3] - z_samples[2]) / 0.04
		_check(absf(approach_slope - expected_slope) < 0.25,
			"constant approach velocity at crossing fraction " + str(crossing_fraction))
		_check(absf(crossing_slope - approach_slope) < 0.25,
			"constant velocity through crossing fraction " + str(crossing_fraction))
		_check(absf(exit_slope - approach_slope) < 0.25,
			"no ring slowdown after crossing fraction " + str(crossing_fraction))
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_preview(view)
	view.queue_free()
	await process_frame
	await _check_parent_scorer_integration()
	print("HUMAN PLANE 3D SCALE/FLOW: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checked, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check_parent_scorer_integration() -> void:
	for dimensions in CAPTURE_SIZES:
		root.size = dimensions
		root.content_scale_size = dimensions
		var game := GAME.instantiate() as Control
		root.add_child(game)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game.call("set_context", {"activity": "Human Plane", "topic": "Noun",
			"difficulty": "Normal", "game_mode": "Seconds", "camera_live": false})
		await process_frame
		await process_frame
		game.set_process(false)
		var view := game.get_node("WorldView3D") as SubViewportContainer
		var crossing: float = game.call("_progress_for_answer_line")
		var expected: PackedFloat32Array = game.call("_normalized_scoring_lane_centers", crossing)
		_check(expected.size() == 3,
			str(dimensions) + " parent derives three authored scoring anchors")
		if expected.size() == 3:
			for lane in range(3):
				var norm: float = expected[lane]
				game.set("plane_x_norm", norm)
				game.call("_sync_visuals")
				var rig := view.get_node("Viewport3D/FlightWorld/PlayerRig") as Node3D
				var target_x := (float(lane) - 1.0) * 6.0
				_check(absf(rig.position.x - target_x) <= 0.04,
					str(dimensions) + " parent-derived scored body center aligns to ring " +
					str(lane) + ", normalized=" + str(norm))
				_check(int(game.call("_lane_hit_at_answer_line")) == lane,
					str(dimensions) + " scorer resolves same lane that 3D pilot visibly occupies " +
					str(lane))
		game.queue_free()
		await process_frame
		await process_frame


func _capture_preview(view: SubViewportContainer) -> void:
	var camera := view.get_node("Viewport3D/FlightWorld/Camera3D") as Camera3D
	var plane := view.get_node("Viewport3D/FlightWorld/PlayerRig/RedPlane") as Node3D
	var world := view.get_node("Viewport3D/FlightWorld") as Node3D
	var centers := PackedFloat32Array([0.3267854, 0.4938553, 0.6600475])
	view.set_scoring_lane_centers(centers)
	for screen_dimensions in CAPTURE_SIZES:
		root.size = screen_dimensions
		root.content_scale_size = screen_dimensions
		# SubViewportContainer stretch owns the child viewport pixel size.
		# Let the editor-authored full-rect anchors follow the root dimensions.
		view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for phase in ["distant", "crossing"]:
			var progress := 0.06 if phase == "distant" else 0.47
			view.sync_flight(0.5, {"options": OPTIONS}, progress, {}, 0.0,
				false, -1, false, false, false, 0.5, true)
			await process_frame
			await RenderingServer.frame_post_draw
			var plane_bounds := _screen_bounds_of_meshes(plane, camera)
			print("PROJECTED_PLANE|", screen_dimensions, "|", phase,
				"|pixel_rect=", plane_bounds,
				"|camera=", camera.global_position,
				"|plane_origin=", plane.global_position,
				"|fov=", camera.fov)
			_check(plane_bounds.size.x >= float(screen_dimensions.x) * 0.035,
				"airplane stays at least 3.5% screen width at " + str(screen_dimensions)
				+ " during " + phase)
			_check(plane_bounds.size.x <= float(screen_dimensions.x) * 0.11,
				"airplane stays below 11% screen width and does not obscure rings at "
				+ str(screen_dimensions) + " during " + phase)
			_check(plane_bounds.position.x > float(screen_dimensions.x) * 0.25 and
				plane_bounds.end.x < float(screen_dimensions.x) * 0.75,
				"airplane is centered clear of side HUD at " + str(screen_dimensions))
			_check(plane_bounds.position.y > float(screen_dimensions.y) * 0.69 and
				plane_bounds.end.y < float(screen_dimensions.y) * 0.90,
				"airplane is below the answer words and above bottom HUD at " +
				str(screen_dimensions) + " during " + phase)
			for lane in range(3):
				view.sync_flight(centers[lane], {"options": OPTIONS}, 0.50, {}, 0.0,
					false, -1, false, false, false, 0.50, false)
				var scored_ring := world.get_node(
					"CurrentRings/Gate" + ["Left", "Center", "Right"][lane]) as Node3D
				var pixel_plane := camera.unproject_position(plane.global_position)
				var pixel_ring := camera.unproject_position(scored_ring.global_position)
				_check(absf(pixel_plane.x - pixel_ring.x) < 4.0,
					"accepted hitbox lane " + str(lane) +
					" projects plane into corresponding 3D ring at " + str(screen_dimensions))
				_check(pixel_plane.x > 0.0 and pixel_plane.x < screen_dimensions.x,
					"accepted hitbox lane " + str(lane) + " stays onscreen at " +
					str(screen_dimensions))
			for steering in [0.0, 1.0]:
				view.sync_flight(steering, {"options": OPTIONS}, progress, {}, 0.0,
					false, -1, false, false, false, 0.5, false)
				var side_rect := _screen_bounds_of_meshes(plane, camera)
				_check(side_rect.position.x >= 0.0 and
					side_rect.end.x <= float(screen_dimensions.x),
					"plane remains on screen at extreme steering " + str(steering)
					+ " / " + str(screen_dimensions))
			view.sync_flight(0.5, {"options": OPTIONS}, progress, {}, 0.0,
				false, -1, false, false, false, 0.5, false)
			var image_out := (view.get_node("Viewport3D") as SubViewport).get_texture().get_image()
			var save_path := "user://_qa_scale_flow_%dx%d_%s.png" % [
				screen_dimensions.x, screen_dimensions.y, phase]
			_check(image_out.save_png(save_path) == OK,
				"captured actual GPU 3D image " + save_path)
			print("SCALE_FLOW_SCREENSHOT ", ProjectSettings.globalize_path(save_path))


func _screen_bounds_of_meshes(node: Node3D, camera: Camera3D) -> Rect2:
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var todo: Array[Node] = [node]
	while not todo.is_empty():
		var current: Node = todo.pop_back()
		if current is MeshInstance3D:
			var part := current as MeshInstance3D
			if part.mesh != null:
				var bounds := part.mesh.get_aabb()
				for x in [bounds.position.x, bounds.end.x]:
					for y in [bounds.position.y, bounds.end.y]:
						for z in [bounds.position.z, bounds.end.z]:
							var vertex: Vector3 = part.global_transform * Vector3(x, y, z)
							if camera.is_position_behind(vertex):
								continue
							var pixel := camera.unproject_position(vertex)
							minimum = minimum.min(pixel)
							maximum = maximum.max(pixel)
		for child in current.get_children():
			todo.append(child)
	return Rect2(minimum, maximum - minimum)


func _check(ok: bool, text_to_log: String) -> void:
	checked += 1
	if not ok:
		failures.append(text_to_log)
		printerr("HUMAN PLANE 3D SCALE/FLOW FAIL: ", text_to_log)


func _mesh_bounds_width(node: Node3D, reference_space: Node3D = null) -> float:
	var bounds_x := Vector2(INF, -INF)
	var todo: Array[Node] = [node]
	while not todo.is_empty():
		var current: Node = todo.pop_back()
		if current is MeshInstance3D:
			var item := current as MeshInstance3D
			if item.mesh != null:
				var bounds := item.mesh.get_aabb()
				for x in [bounds.position.x, bounds.end.x]:
					for y in [bounds.position.y, bounds.end.y]:
						for z in [bounds.position.z, bounds.end.z]:
							var point: Vector3 = item.global_transform * Vector3(x, y, z)
							if reference_space != null:
								point = reference_space.to_local(point)
							bounds_x.x = minf(bounds_x.x, point.x)
							bounds_x.y = maxf(bounds_x.y, point.x)
		for child in current.get_children():
			todo.append(child)
	return bounds_x.y - bounds_x.x
