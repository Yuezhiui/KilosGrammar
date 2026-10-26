extends SceneTree

# Human Plane 3D motion, moving cloud props and repeated-mount regression.
# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_3d_motion_performance.gd
# No hardware camera, database, wrapper or destructive services.
const GAME := preload("res://ui/minigames/human_plane.tscn")
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const LANES := ["Left", "Center", "Right"]
const FRAME_RATES := [30, 60]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for resolution in RESOLUTIONS:
		var samples: Array[float] = []
		for fps in FRAME_RATES:
			samples.append(await _test_motion(resolution, fps))
		if samples.size() == 2 and is_finite(samples[0]) and is_finite(samples[1]):
			_check(absf(samples[0] - samples[1]) <= 0.8,
				"%s 3D ring travels equivalent distance after 1 s at 30 and 60 FPS" % resolution)
	await _test_lifecycle()
	print("HUMAN PLANE 3D MOTION/PERFORMANCE: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_motion(dimensions: Vector2i, fps: int) -> float:
	root.content_scale_size = dimensions
	root.size = dimensions
	var name := "%dx%d/%dfps" % [dimensions.x, dimensions.y, fps]
	var game := GAME.instantiate() as Control
	if game == null:
		_check(false, name + " instantiates 3D scene")
		return NAN
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {"activity": "Human Plane", "topic": "Noun",
		"difficulty": "Normal", "game_mode": "Seconds", "camera_live": false})
	# The project now runs full 3D only. The former 2.5D scene selector and
	# set_environment_view() API were intentionally removed.
	await process_frame
	await process_frame
	game.set_process(false)
	var view := game.get_node_or_null("WorldView3D") as SubViewportContainer
	var world := game.get_node_or_null("WorldView3D/Viewport3D/FlightWorld") as Node3D
	var ring_group := world.get_node_or_null("CurrentRings") as Node3D if world != null else null
	var cloud_props := world.get_node_or_null("CloudFlight/CloudProps") as Node3D if world != null else null
	_check(view != null and ring_group != null and cloud_props != null,
		name + " scene includes moving ring trio and separately authored clouds")
	if view == null or ring_group == null or cloud_props == null:
		game.queue_free()
		await process_frame
		return NAN
	view.set_process(false)
	# Startup may have advanced the first wave before the test gains control.
	# Invalidate the previous visual timeline and start from deterministic p=0.
	view.call("sync_flight", 0.5, {}, 0.0, {}, 0.0, false, -1, false,
		false, false, 0.5, false)
	game.call("_start_wave")
	game.call("_sync_visuals")
	_check(ring_group.get_child_count() == 3, name + " uses three retained ring instances")
	_check(cloud_props.get_child_count() >= 6,
		name + " cloud scene retains multiple independent cloud props")
	var terrain := world.get_node_or_null("Terrain") as Node3D
	var scenery := world.get_node_or_null("Scenery") as Node3D
	_check(terrain == null or not terrain.is_visible_in_tree(),
		name + " ground/road/mountain branch remains visually disabled")
	_check(scenery == null or not scenery.is_visible_in_tree(),
		name + " forest/grass branch remains visually disabled")
	var colors: Array[Color] = []
	for lane in LANES:
		var ring := ring_group.get_node_or_null("Gate" + lane) as Node3D
		var mesh := ring.get_node_or_null("FrameLeft") as MeshInstance3D if ring != null else null
		var material := mesh.material_override as StandardMaterial3D if mesh != null else null
		if material != null:
			colors.append(material.albedo_color)
	_check(colors.size() == 3, name + " portal colors use editable independent materials")
	if colors.size() == 3:
		_check(colors[0].is_equal_approx(Color("#bda1f7")) and
			colors[1].is_equal_approx(Color("#91e9bb")) and
			colors[2].is_equal_approx(Color("#9bc9ff")),
			name + " shows contrasting lilac, mint and sky child-friendly portals simultaneously")

	var center := ring_group.get_node_or_null("GateCenter") as Node3D
	var dt := 1.0 / float(fps)
	var fraction_before_answer := minf(0.20, float(game.call("_progress_for_answer_line")) * 0.70)
	var old_z := center.position.z
	var min_z := old_z
	var max_step := 0.0
	for frame_number in range(fps):
		# Drive identical authoritative progress at 30/60 fps. This isolates
		# visual interpolation from random quiz generation and wave scoring.
		game.set("gate_progress", fraction_before_answer * float(frame_number + 1) / float(fps))
		game.call("_sync_visuals")
		view.call("_process", dt)
		var z_now := center.position.z
		max_step = maxf(max_step, absf(z_now - old_z))
		_check(z_now >= old_z - 0.015,
			name + " ring never reverses a frame while approaching (%.3f -> %.3f)" % [old_z, z_now])
		min_z = minf(min_z, z_now)
		old_z = z_now
	_check(old_z > min_z + 1.5, name + " ring approaches smoothly over one second")
	_check(max_step < 1.6, name + " ring advances without visible single-frame teleport")
	var before_pause := center.position
	var scenery_before := cloud_props.get_child_count()
	game.call("_pause")
	_check(absf(center.position.z - before_pause.z) <= 0.75,
		name + " pause does not jerk ring backward when interpolation stops")
	var after_pause := center.position
	for _step in range(fps / 2):
		game.call("_process", dt)
		view.call("_process", dt)
	_check(center.position.is_equal_approx(after_pause), name + " paused ring freezes precisely")
	_check(cloud_props.get_child_count() == scenery_before,
		name + " clouds animate without creating new nodes every frame")
	game.call("_resume")
	game.call("_update_gate_wave", dt)
	game.call("_sync_visuals")
	view.call("_process", dt)
	_check(center.position.z >= before_pause.z and center.position.z - before_pause.z < 1.6,
		name + " ring resumes smoothly without pause jump")
	var result := old_z
	game.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(game), name + " world releases cleanly on scene exit")
	return result


func _test_lifecycle() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var base_children := root.get_child_count()
	var after_warmup := -1
	for cycle in range(12):
		var game := GAME.instantiate() as Control
		root.add_child(game)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game.call("set_context", {"activity": "Human Plane", "topic": "Noun",
			"difficulty": "Easy", "game_mode": "Seconds", "camera_live": false})
		await process_frame
		await process_frame
		game.set_process(false)
		if cycle % 2 == 0:
			game.call("_pause")
		game.queue_free()
		await process_frame
		await process_frame
		_check(not is_instance_valid(game) and root.get_child_count() == base_children,
			"mount/unmount %d leaves no game-world nodes or voice players" % cycle)
		var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		if cycle == 3:
			after_warmup = objects
		if cycle >= 4 and after_warmup >= 0:
			_check(objects <= after_warmup + 180,
				"mount/unmount %d object count stays bounded (baseline %d, now %d)" %
				[cycle, after_warmup, objects])


func _walk(node: Node, found: Array[Node]) -> void:
	found.append(node)
	for child in node.get_children():
		_walk(child, found)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("HUMAN PLANE 3D MOTION/PERFORMANCE FAIL: ", message)
