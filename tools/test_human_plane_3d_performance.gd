extends SceneTree

## Real OpenGL3 performance/lifecycle probe, completely offline.
## Windows / Godot 4.7.2:
## godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
##   --script res://tools/test_human_plane_3d_performance.gd
## Optional user args after --: --seconds=10 --cycles=12 --warmup=90
## Does not enter the camera, PostgreSQL or gameplay wrapper routes.

const GAME := preload("res://ui/minigames/human_plane.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const CONTEXT := {
	"activity": "Human Plane", "topic": "Noun", "difficulty": "Normal",
	"game_mode": "Seconds", "camera_live": false
}

var failures: Array[String] = []
var warnings: Array[String] = []
var seconds := 10.0
var cycles := 12
var warmup := 90


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("A display-backed OpenGL3 renderer is required; headless timings are invalid")
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			seconds = clampf(argument.trim_prefix("--seconds=").to_float(), 1.0, 60.0)
		elif argument.begins_with("--cycles="):
			cycles = clampi(int(argument.trim_prefix("--cycles=")), 4, 100)
		elif argument.begins_with("--warmup="):
			warmup = clampi(int(argument.trim_prefix("--warmup=")), 3, 300)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("PERF|environment|os|", OS.get_name())
	print("PERF|environment|gpu|", RenderingServer.get_video_adapter_name())
	print("PERF|environment|renderer|", RenderingServer.get_current_rendering_driver_name())
	print("PERF|environment|display|", DisplayServer.get_name())
	print("PERF|environment|vsync|disabled")
	print("PERF|environment|seconds_per_size|%.2f" % seconds)
	for dimensions in SIZES:
		await _profile_resolution(dimensions)
	await _profile_lifecycle()
	for failure in failures:
		printerr("PERF|FAIL|", failure)
	for warning in warnings:
		print("PERF|WARN|", warning)
	print("PERF|result|%s|failures=%d|warnings=%d" % [
		"PASS" if failures.is_empty() else "FAIL", failures.size(), warnings.size()])
	quit(0 if failures.is_empty() else 1)


func _set_resolution(dimensions: Vector2i) -> void:
	DisplayServer.window_set_size(dimensions)
	root.content_scale_size = dimensions
	root.size = dimensions


func _mount() -> Control:
	var game := GAME.instantiate() as Control
	if game == null:
		_fail("Human Plane scene failed to instantiate")
		return null
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", CONTEXT)
	return game


func _profile_resolution(dimensions: Vector2i) -> void:
	_set_resolution(dimensions)
	var game := _mount()
	if game == null:
		return
	for _i in range(warmup):
		await RenderingServer.frame_post_draw
	# Hold the quiz state but retain continuous 3D scenery/plane presentation.
	game.set_process(false)
	game.set("gate_progress", float(game.call("_progress_for_answer_line")) * 0.58)
	game.call("_sync_visuals")
	var world := game.get_node_or_null("WorldView3D/Viewport3D/FlightWorld") as Node3D
	var rings := game.get_node_or_null("WorldView3D/Viewport3D/FlightWorld/CurrentRings") as Node3D
	if world == null or rings == null or not rings.visible:
		_fail("%s: 3D world or live ring trio missing" % dimensions)
		game.queue_free()
		await process_frame
		return
	var scene_stats := {"nodes": 0, "mesh_nodes": 0, "multimesh_nodes": 0,
		"multimesh_instances": 0, "visible_mesh_nodes": 0,
		"scene_triangle_budget": 0, "multimesh_triangle_budget": 0}
	_count_renderers(world, scene_stats)
	var key := "%dx%d" % [dimensions.x, dimensions.y]
	print("PERF|%s|scene_nodes|%d" % [key, _count_nodes(game)])
	for stat_name in scene_stats:
		print("PERF|%s|%s|%s" % [key, stat_name, scene_stats[stat_name]])
	if int(scene_stats["multimesh_nodes"]) == 0:
		warnings.append("%s: no MultiMeshInstance3D was mounted during capture" % key)
	# These are render-frame intervals, not GPU execution times. Uncapped mode
	# exposes bottlenecks otherwise hidden behind 16.7 ms VSync pacing.
	var wall_ms: Array[float] = []
	var process_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var triangles: Array[float] = []
	var objects: Array[float] = []
	var begin := Time.get_ticks_usec()
	var previous := begin
	while float(Time.get_ticks_usec() - begin) * 0.000001 < seconds:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		wall_ms.append(float(now - previous) * 0.001)
		previous = now
		process_ms.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		draw_calls.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		triangles.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		objects.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
	_log_samples(key, "frame_interval_ms", wall_ms)
	_log_samples(key, "process_cpu_ms", process_ms)
	_log_samples(key, "draw_calls_per_frame", draw_calls)
	_log_samples(key, "primitives_per_frame", triangles)
	_log_samples(key, "rendered_objects_per_frame", objects)
	print("PERF|%s|frames|%d" % [key, wall_ms.size()])
	print("PERF|%s|observed_fps|%.2f" % [key, 1000.0 / maxf(_average(wall_ms), 0.001)])
	print("PERF|%s|after_sample_object_count|%d" % [key,
		int(Performance.get_monitor(Performance.OBJECT_COUNT))])
	var video_memory := float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	print("PERF|%s|reported_video_memory_mib|%.3f" % [key, video_memory / 1048576.0])
	if video_memory <= 0.0:
		warnings.append("%s: renderer did not expose GPU video memory; zero is not a measured allocation" % key)
	game.queue_free()
	await process_frame
	await process_frame
	if is_instance_valid(game):
		_fail("%s: game not freed after graphical sample" % key)


func _profile_lifecycle() -> void:
	_set_resolution(SIZES[0])
	var base_root_count := root.get_child_count()
	var objects_after_warmup := -1
	var nodes_after_warmup := -1
	var orphans_after_warmup := -1
	var max_live_nodes := 0
	for cycle in range(cycles):
		var game := _mount()
		if game == null:
			return
		await process_frame
		await RenderingServer.frame_post_draw
		game.set_process(false)
		max_live_nodes = maxi(max_live_nodes, _count_nodes(game))
		var voice := game.get_node_or_null("HumanPlaneVoicePlayer") as AudioStreamPlayer
		if voice == null:
			_fail("Lifecycle cycle %d: feedback audio player absent" % cycle)
		else:
			game.call("_play_voice_feedback", true)
			if voice.stream == null:
				_fail("Lifecycle cycle %d: correct clip not loaded" % cycle)
			await RenderingServer.frame_post_draw
			game.call("_play_voice_feedback", false)
			if voice.stream == null:
				_fail("Lifecycle cycle %d: wrong clip not loaded" % cycle)
		game.call("_pause")
		if voice != null and (voice.playing or voice.stream != null):
			_fail("Lifecycle cycle %d: pause did not stop and release active audio" % cycle)
		game.call("_resume")
		game.call("_play_voice_feedback", false, true)
		if voice != null and voice.stream == null:
			_fail("Lifecycle cycle %d: missed clip not loaded" % cycle)
		game.queue_free()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		if is_instance_valid(game) or root.get_child_count() != base_root_count:
			_fail("Lifecycle cycle %d: mounted scene/node leaked" % cycle)
		var current_objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		var current_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var current_orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		print("PERF|lifecycle|%d|objects=%d|nodes=%d|orphans=%d" % [
			cycle, current_objects, current_nodes, current_orphans])
		if cycle == 2:
			objects_after_warmup = current_objects
			nodes_after_warmup = current_nodes
			orphans_after_warmup = current_orphans
		if cycle == cycles - 1 and objects_after_warmup >= 0:
			print("PERF|lifecycle|object_growth_after_warmup|%d" % (current_objects - objects_after_warmup))
			print("PERF|lifecycle|node_growth_after_warmup|%d" % (current_nodes - nodes_after_warmup))
			print("PERF|lifecycle|orphan_growth_after_warmup|%d" % (current_orphans - orphans_after_warmup))
			if current_nodes > nodes_after_warmup + 3:
				_fail("Lifecycle nodes rose after warmup: %d -> %d" % [nodes_after_warmup, current_nodes])
			if current_orphans > orphans_after_warmup + 3:
				_fail("Lifecycle orphan nodes rose after warmup: %d -> %d" % [orphans_after_warmup, current_orphans])
			if current_objects > objects_after_warmup + maxi(200, objects_after_warmup / 5):
				warnings.append("Object count may be growing: %d -> %d; caches/driver resources need inspection" %
					[objects_after_warmup, current_objects])
	print("PERF|lifecycle|max_mounted_node_count|%d" % max_live_nodes)


func _count_nodes(node: Node) -> int:
	var amount := 1
	for child in node.get_children():
		amount += _count_nodes(child)
	return amount


func _count_renderers(node: Node, stats: Dictionary) -> void:
	stats["nodes"] += 1
	if node is MeshInstance3D:
		stats["mesh_nodes"] += 1
		if (node as MeshInstance3D).visible:
			stats["visible_mesh_nodes"] += 1
		stats["scene_triangle_budget"] += _mesh_triangles((node as MeshInstance3D).mesh)
	if node is MultiMeshInstance3D:
		stats["multimesh_nodes"] += 1
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm != null:
			var active_instances := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			stats["multimesh_instances"] += active_instances
			var triangle_count := _mesh_triangles(mm.mesh) * active_instances
			stats["multimesh_triangle_budget"] += triangle_count
			stats["scene_triangle_budget"] += triangle_count
	for child in node.get_children():
		_count_renderers(child, stats)


func _mesh_triangles(mesh: Mesh) -> int:
	# Geometry budget across all scene nodes before culling, including instances.
	# Actual rendered triangles need a GPU-side visibility-aware profiler; the
	# Performance monitor below reports vertices/indices in all render passes.
	if mesh == null:
		return 0
	var count := 0
	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		if arrays.size() <= Mesh.ARRAY_INDEX:
			continue
		var indexed: Variant = arrays[Mesh.ARRAY_INDEX]
		var vertex_data: Variant = arrays[Mesh.ARRAY_VERTEX]
		var index_size := (indexed as PackedInt32Array).size() if indexed is PackedInt32Array else 0
		var vertex_size := (vertex_data as PackedVector3Array).size() if vertex_data is PackedVector3Array else 0
		count += int((index_size if index_size > 0 else vertex_size) / 3)
	return count


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for value in values:
		sum += value
	return sum / float(values.size())


func _log_samples(key: String, field: String, values: Array[float]) -> void:
	if values.is_empty():
		_fail("%s: %s has no captured frames" % [key, field])
		return
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var p95: float = sorted[clampi(int(ceil(sorted.size() * 0.95)) - 1, 0, sorted.size() - 1)]
	print("PERF|%s|%s|avg=%.3f|p95=%.3f|min=%.3f|max=%.3f|count=%d" % [
		key, field, _average(values), p95, sorted[0], sorted[sorted.size() - 1], values.size()])


func _fail(message: String) -> void:
	failures.append(message)
	printerr("PERF|FAIL|", message)
