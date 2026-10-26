extends SceneTree

# Offline 3D scene / asset / responsive HUD regression.
# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_3d_world.gd
# This test does not initialize the gameplay wrapper, PoseService or database.
const PLANE_PATH := "res://ui/minigames/human_plane.tscn"
const SCREEN_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const LANES := 3

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ResourceLoader.exists(PLANE_PATH), "Human Plane scene file exists")
	if not ResourceLoader.exists(PLANE_PATH):
		_finish()
		return
	_check_scene_dependencies(PLANE_PATH)
	var packed := load(PLANE_PATH) as PackedScene
	_check(packed != null, "Human Plane is a loadable PackedScene")
	if packed == null:
		_finish()
		return
	for dimensions in SCREEN_SIZES:
		await _check_viewport(packed, dimensions)
	_finish()


func _check_viewport(packed: PackedScene, dimensions: Vector2i) -> void:
	root.content_scale_size = dimensions
	root.size = dimensions
	var game := packed.instantiate() as Control
	_check(game != null, "%s game remains a Control for gameplay routing" % dimensions)
	if game == null:
		return
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if game.has_method("set_context"):
		game.call("set_context", {"activity": "Human Plane", "topic": "Noun",
			"difficulty": "Normal", "game_mode": "Seconds", "camera_live": false})
	# Full 3D is the only playable renderer; inspect 9:16 portal geometry.
	await process_frame
	await process_frame
	game.set_process(false)

	var nodes: Array[Node] = []
	_walk(game, nodes)
	var worlds: Array[Node3D] = []
	var cameras: Array[Camera3D] = []
	var portal_frames: Array[Node3D] = []
	var labels: Array[Label3D] = []
	var subviewports: Array[SubViewport] = []
	for node in nodes:
		if node is Node3D:
			worlds.append(node)
		if node is Camera3D:
			cameras.append(node)
		if node is MeshInstance3D and node.name == "FrameLeft" \
					and (node as MeshInstance3D).mesh is CapsuleMesh:
			portal_frames.append(node)
		if node is Label3D:
			labels.append(node)
		if node is SubViewport:
			subviewports.append(node)
	var prefix := "%dx%d" % [dimensions.x, dimensions.y]
	var world_view := game.get_node_or_null("WorldView3D") as SubViewportContainer
	_check(world_view != null, prefix + " editor-authored WorldView3D container exists")
	if world_view != null:
		var actual_viewport := world_view.get_node_or_null("Viewport3D") as SubViewport
		_check(actual_viewport != null, prefix + " viewport renders a genuine 3D world")
		var world := world_view.get_node_or_null("Viewport3D/FlightWorld") as Node3D
		_check(world != null, prefix + " 3D flight world is attached to its SubViewport")
		_check(world_view.is_visible_in_tree(), prefix + " world view is visible behind the HUD")
		var old_gates := game.get_node_or_null("MovingGates") as CanvasItem
		var old_plane := game.get_node_or_null("PlaneRig") as CanvasItem
		# Retained 2D guides may still exist for the old collision contract, but
				# their sprites must not obscure the actual 3D portal/airplane render.
		var legacy_art_hidden := (old_gates == null or not old_gates.is_visible_in_tree() or
			old_gates.modulate.a <= 0.005) and (old_plane == null or
			not old_plane.is_visible_in_tree() or old_plane.modulate.a <= 0.005)
		var world_covers_legacy := world_view.z_index > maxi(
			old_gates.z_index if old_gates != null else -1,
			old_plane.z_index if old_plane != null else -1)
		_check(legacy_art_hidden or world_covers_legacy,
			prefix + " old 2D gate and plane graphics cannot cover the 3D game world")
		if actual_viewport != null:
			_check(not actual_viewport.disable_3d, prefix + " 3D rendering is enabled")
		if world != null:
			_check(world.get_node_or_null("Camera3D") is Camera3D,
				prefix + " real flight camera is part of the scene")
			var round_words: Array = (game.get("round_data") as Dictionary).get("options", [])
			for trio_path in ["CurrentRings", "UpcomingRings"]:
				var trio := world.get_node_or_null(trio_path) as Node3D
				_check(trio != null, prefix + " contains the " + trio_path + " 3D trio")
				if trio == null:
					continue
				var rings: Array[Node3D] = []
				for lane in ["Left", "Center", "Right"]:
					var ring := trio.get_node_or_null("Gate" + lane) as Node3D
					_check(ring != null, prefix + " contains " + trio_path + "/Gate" + lane)
					if ring == null:
						continue
					rings.append(ring)
					var parts: Array[Node] = []
					_walk(ring, parts)
					var portal_found := false
					var word_found := false
					for part in parts:
						if part is MeshInstance3D and part.name == "FrameLeft" \
								and (part as MeshInstance3D).mesh is CapsuleMesh:
							portal_found = true
						if part is Label3D and part.name == "WordLabel":
							word_found = true
					_check(portal_found and word_found and ring.has_node("WordPlaque"),
						prefix + " " + trio_path + "/Gate" + lane + " has native portrait portal and readable WordLabel")
					if trio_path == "CurrentRings" and round_words.size() == LANES:
						var label_3d := ring.get_node_or_null("WordLabel") as Label3D
						if label_3d != null:
							_check(label_3d.text == String(round_words[rings.size() - 1]).to_upper(),
									prefix + " real 3D portal displays its current grammar choice")
				if rings.size() == LANES:
					_check(rings[0].position.x < rings[1].position.x and
						rings[1].position.x < rings[2].position.x,
						prefix + " " + trio_path + " is ordered left / center / right in 3D space")
				if trio_path == "CurrentRings":
					var materials: Array[Material] = []
					for ring in rings:
						var portal_mesh := ring.get_node_or_null("FrameLeft") as MeshInstance3D
						if portal_mesh != null and portal_mesh.material_override != null:
							materials.append(portal_mesh.material_override)
					_check(materials.size() == LANES and
							materials[0] != materials[1] and materials[1] != materials[2] and
							materials[0] != materials[2],
								prefix + " independent portal materials preserve lane-specific colors")
	_check(not worlds.is_empty(), prefix + " contains a genuine Node3D world")
	_check(not cameras.is_empty(), prefix + " contains a Camera3D")
	var active_camera := false
	for camera in cameras:
		if camera.is_visible_in_tree() and camera.current:
			active_camera = true
	_check(active_camera, prefix + " has a visible active 3D camera")
	_check(portal_frames.size() >= LANES, prefix + " contains at least three 3D capsule-edged portal frames")
	var x_positions: Array[float] = []
	for frame in portal_frames:
		if frame.is_visible_in_tree():
			var world_x: float = (frame.get_parent() as Node3D).global_position.x
			var unique_lane := true
			for found_x in x_positions:
				if absf(found_x - world_x) < 0.05:
					unique_lane = false
			if unique_lane:
				x_positions.append(world_x)
	_check(x_positions.size() >= LANES, prefix + " portrait portals cover left, center and right lanes")
	var visible_word_count := 0
	for label in labels:
		if label.is_visible_in_tree() and not label.text.strip_edges().is_empty():
			visible_word_count += 1
	_check(visible_word_count >= LANES, prefix + " displays three grammar words inside the 3D world")
	if not subviewports.is_empty():
		var usable_view := false
		for view in subviewports:
			if view.size.x >= 320 and view.size.y >= 180 and not view.disable_3d:
				usable_view = true
		_check(usable_view, prefix + " has a properly sized enabled 3D SubViewport")
	_check(game.size.x >= dimensions.x - 1 and game.size.y >= dimensions.y - 1,
		prefix + " 3D game fills its requested screen resolution")

	var hud := game.get_node_or_null("HUDLayer/HUD") as Control
	_check(hud != null and hud.is_visible_in_tree(), prefix + " shared gameplay HUD is visible")
	if hud != null:
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		for hud_path in ["PromptLabel", "TimeLabel", "PauseButton", "ScoreBottomContainer/ScoreNumber"]:
			var hud_element := hud.get_node_or_null(hud_path) as Control
			_check(hud_element != null, prefix + " retains HUD/" + hud_path)
			if hud_element != null and hud_element.is_visible_in_tree():
				_check(bounds.encloses(hud_element.get_global_rect()),
					prefix + " keeps HUD/" + hud_path + " inside screen bounds")

	game.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(game), prefix + " 3D scene releases cleanly after gameplay")


func _walk(node: Node, found: Array[Node]) -> void:
	found.append(node)
	for child in node.get_children():
		_walk(child, found)


func _check_scene_dependencies(path: String) -> void:
	var source := FileAccess.get_file_as_string(path)
	_check(not source.is_empty(), "3D scene text is accessible to resource audit")
	if source.is_empty():
		return
	var expression := RegEx.new()
	_check(expression.compile('\\[ext_resource[^\\n]*path="(res://[^"]+)"') == OK,
		"resource-path audit compiles")
	for item in expression.search_all(source):
		var dependency := item.get_string(1)
		_check(ResourceLoader.exists(dependency) or FileAccess.file_exists(dependency),
			"3D scene dependency resolves: " + dependency)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("HUMAN PLANE 3D WORLD FAIL: ", message)


func _finish() -> void:
	print("HUMAN PLANE 3D WORLD: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
