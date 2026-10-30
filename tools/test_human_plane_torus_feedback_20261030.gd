extends SceneTree

# Native-3D stress: torus is a REAL constant world-size circle, not a
# per-frame squeezed 2D ellipse. Camera + plane fly forward to stationary
# rings; same authored pools recycle for endless unique grammar waves.
# Check both modes at all classroom resolutions without real camera/DB.
const SCENE := preload("res://ui/minigames/human_plane/human_plane.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var failures: Array[String] = []
var checks := 0
var captures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for size in SIZES:
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(size)
		root.content_scale_size = size
		root.size = size
		for mode in ["Seconds", "Lives"]:
			await _exercise(size, mode)
	print("HUMAN PLANE TORUS +100/+0: %s checks=%d failures=%d native_captures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), captures])
	quit(0 if failures.is_empty() else 1)


func _exercise(size: Vector2i, mode: String) -> void:
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity":"Human Plane", "topic":"Noun", "difficulty":"Normal",
		"game_mode":mode})
	for _frame in range(3):
		await process_frame
	game.set_process(false)
	game.set_airplane_pose_active(true)
	var hybrid := game.get_node("HybridFlight3D") as Node2D
	var camera := hybrid.get_node("RenderViewport/FlightWorld3D/Camera") as Camera3D
	var aircraft := hybrid.get_node("RenderViewport/FlightWorld3D/PlaneAnchor") as Node3D
	var score := game.get_node("HUDLayer/HUD/ScoreNumber") as Label
	var floater := game.get_node("ScoreFeedbackLayer/FloatingScore") as Label
	_check(game.get_node_or_null("HUDLayer/HUD/ScoreBottomContainer") == null and
		score != null and floater != null, "Catch score direct path and editor feedback")
	var meshes: Array = hybrid.get("_ring_pools")[0]
	var initial_world: Array[Vector3] = []
	var initial_scale: Array[Vector3] = []
	var initial_camera_z := 0.0
	var prior_camera_z := 999999.0
	for progress in [0.0, 0.10, 0.25, 0.42, 0.57, 0.72, 0.88, 0.98]:
		game.set("gate_progress", progress)
		game.set("gate_resolved", false)
		game.call("_sync_visuals")
		hybrid.call("_process", 0.016)
		if is_zero_approx(progress):
			initial_camera_z = camera.global_position.z
		for lane in range(3):
			var ring := meshes[lane] as Node3D
			var mesh := ring.get_node("Ring") as MeshInstance3D
			_check(ring.visible and mesh.mesh is TorusMesh,
				"%s/%s p%.2f lane%d real TorusMesh visible" % [size, mode, progress, lane])
			_check(absf(ring.scale.x - ring.scale.y) < 0.0001 and
				absf(ring.scale.x - ring.scale.z) < 0.0001 and ring.scale.x > 0.01,
				"%s/%s p%.2f lane%d torus never squeezes/stretch-axes" % [size, mode, progress, lane])
			if is_zero_approx(progress):
				initial_world.append(ring.global_position)
				initial_scale.append(ring.scale)
			else:
				_check(ring.global_position.distance_to(initial_world[lane]) < 0.002
					and ring.scale.is_equal_approx(initial_scale[lane]),
					"%s/%s p%.2f lane%d target stays fixed in WORLD as plane flies" % [size, mode, progress, lane])
		_check(camera.global_position.z <= prior_camera_z + 0.001,
			"%s/%s p%.2f camera travels forward, never backward within wave" % [size, mode, progress])
		_check(absf((camera.global_position.z - aircraft.global_position.z) - float(hybrid.airplane_camera_distance)) < 0.1,
			"%s/%s p%.2f airplane stays at authored forward camera clearance" % [size, mode, progress])
		prior_camera_z = camera.global_position.z
		if progress in [0.25, 0.57, 0.88] and DisplayServer.get_name() != "headless":
			await _capture(size, mode, progress)
	_check(camera.global_position.z < initial_camera_z - 20.0,
		"%s/%s camera physically flies forward more than 20 world units per gate" % [size, mode])
	# Rewind test-only progress before genuine scoring, to test the same
	# authoritative geometry and floating feedback at the correct answer.
	game.set("gate_progress", 0.0)
	game.call("_start_wave")
	var correct: int = int((game.round_data.get("valid_indices", [0]) as Array)[0])
	var centers: PackedFloat32Array = game.call("_normalized_scoring_lane_centers",
		float(game.call("_progress_for_answer_line")))
	var achievable := centers.size() == 3
	if achievable:
		game.set("plane_x_norm", centers[correct])
		achievable = int(hybrid.call("physical_lane_at_answer_line")) == correct
	_check(achievable, "%s/%s correct lane center clears actual 3D airplane and torus hitboxes" % [size, mode])
	var score_start: int = game.score
	game.call("_resolve_at_answer_line")
	_check(game.score == score_start + 100 and floater.visible and floater.text == "+100"
		and floater.get_theme_font_size("font_size") == 28,
		"%s/%s correct portal awards exactly 100 and starts Catch-style +100 tween" % [size, mode])
	_check(floater.get_theme_color("font_color").g > 0.8,
		"%s/%s green +100 feedback" % [size, mode])
	_check(absf(floater.position.x + floater.size.x * 0.5 - float(game.call("_plane_center_x"))) < 10.0,
		"%s/%s green +100 originates above the ACTUAL scoring pilot, not stale center" % [size, mode])
	if DisplayServer.get_name() != "headless":
		await _capture_feedback(size, mode, "plus100")
	game.call("_start_wave")
	game.set("plane_x_norm", -10.0)
	var lives_before: int = game.lives
	game.call("_resolve_at_answer_line")
	_check(game.score == score_start + 100 and floater.visible and floater.text == "+0",
		"%s/%s miss awards no points, real +0 pop instead of silent miss" % [size, mode])
	_check(floater.position.x >= -0.01 and floater.position.x + floater.size.x <= game.size.x + 0.01,
		"%s/%s +0 remains visibly inside screen even on off-lane miss" % [size, mode])
	_check(game.lives == (lives_before - 1 if mode == "Lives" else lives_before),
		"%s/%s single miss respects Lives-only heart penalty" % [size, mode])
	_check(score.text == str(game.score), "%s/%s Catch direct score remains synchronized" % [size, mode])
	if DisplayServer.get_name() != "headless":
		await _capture_feedback(size, mode, "plus0")
	# Real endless wave stress: two pre-authored 3D TorusMesh trios are
	# recycled, with continuous FORWARD camera progress and no new ring nodes.
	var initial_ids := {}
	for group in hybrid.get("_ring_pools"):
		for unit in group:
			initial_ids[(unit as Node3D).get_instance_id()] = true
	_check(initial_ids.size() == 6, "exactly six pooled torus instances are authoritative")
	game.call("_start_wave")
	var last_z: float = camera.global_position.z
	for cycle in range(4):
		var before_wave: int = int(game.waves_completed)
		var valid: Array = game.round_data.get("valid_indices", [])
		if valid.is_empty():
			_check(false, "endless wave %d generated no real answer" % cycle)
			break
		var lane := int(valid[0])
		var reachable := centers.size() == 3
		if reachable:
			game.plane_x_norm = centers[lane]
			reachable = int(hybrid.call("physical_lane_at_answer_line")) == lane
		_check(reachable, "endless wave %d airplane genuinely fits physical hole" % cycle)
		for tick in range(460):
			game.call("_update_gate_wave", 1.0 / 60.0)
			game.call("_sync_visuals")
			hybrid.call("_process", 0.0)
			if camera.global_position.z > last_z + 0.2:
				_check(false, "endless wave %d must never rewind the forward camera" % cycle)
				break
			last_z = camera.global_position.z
			if int(game.waves_completed) > before_wave:
				break
		_check(int(game.waves_completed) == before_wave + 1,
			"endless wave %d hands off next gate trio without respawn gap" % cycle)
		_check(int(game.attempts) == before_wave + 3,
			"endless wave %d scores precisely once after previous two QA attempts" % cycle)
		var seen_ids := {}
		for group in hybrid.get("_ring_pools"):
			for unit in group:
				seen_ids[(unit as Node3D).get_instance_id()] = true
		_check(seen_ids == initial_ids,
			"endless wave %d reuses precisely the same six native ring instances" % cycle)
	game.queue_free()
	await process_frame
	await process_frame


func _capture(size: Vector2i, mode: String, progress: float) -> void:
	for _i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://showcase/qa_human_plane_oct30/torus_fixed_%dx%d_%s_p%03d.png" % [
		size.x, size.y, mode.to_lower(), roundi(progress * 100.0)]
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	_check(result == OK, "Native torus GIF keyframe " + path)
	if result == OK:
		captures += 1
		print("TORUS NATIVE ", path)


func _capture_feedback(size: Vector2i, mode: String, variant: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://showcase/qa_human_plane_oct30/torus_feedback_%dx%d_%s_%s.png" % [
		size.x, size.y, mode.to_lower(), variant]
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	_check(result == OK, "Actual GPU Catch-style animated " + variant)
	if result == OK:
		captures += 1
		print("TORUS FEEDBACK NATIVE ", path)


func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("TORUS/POINTS FAIL: ", description)
