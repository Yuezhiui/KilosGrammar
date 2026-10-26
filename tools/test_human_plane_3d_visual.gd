extends SceneTree

# Real GPU image capture; never touches camera, PoseService or a database.
# Godot 4.7.2 --path . --rendering-method gl_compatibility --script res://tools/test_human_plane_3d_visual.gd
# Output is in the Godot user:// folder for manual review at all three resolutions.
const SCENE := preload("res://ui/minigames/human_plane.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Visual QA requires a real graphical renderer")
		quit(1)
		return
	for dimensions in SIZES:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(dimensions)
		root.content_scale_size = dimensions
		root.size = dimensions
		var game := SCENE.instantiate() as Control
		root.add_child(game)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game.call("set_context", {"activity": "Human Plane", "topic": "Noun",
			"difficulty": "Normal", "game_mode": "Seconds", "camera_live": false})
		for _frame in range(5):
			await process_frame
		var world := game.get_node_or_null("WorldView3D/Viewport3D/FlightWorld") as Node3D
		var camera := world.get_node_or_null("Camera3D") as Camera3D if world != null else null
		var portal := world.get_node_or_null("CurrentRings/GateCenter") as Node3D if world != null else null
		var frame_left := portal.get_node_or_null("FrameLeft") as MeshInstance3D if portal != null else null
		var frame_right := portal.get_node_or_null("FrameRight") as MeshInstance3D if portal != null else null
		var frame_top := portal.get_node_or_null("FrameTop") as MeshInstance3D if portal != null else null
		var frame_bottom := portal.get_node_or_null("FrameBottom") as MeshInstance3D if portal != null else null
		var label_3d := portal.get_node_or_null("WordLabel") as Label3D if portal != null else null
		if camera == null or frame_left == null or frame_right == null or frame_top == null or frame_bottom == null or label_3d == null:
			failures.append("%dx%d 3D camera or native portrait portal frame/word is missing" % [dimensions.x, dimensions.y])
			game.queue_free()
			await process_frame
			continue
		if not (frame_left.mesh is CapsuleMesh and frame_top.mesh is CapsuleMesh):
			failures.append("%dx%d editor-authored 3D frames must use capsule geometry" % [dimensions.x, dimensions.y])
		else:
			var portal_width := frame_right.position.x - frame_left.position.x + 2.0 * (frame_left.mesh as CapsuleMesh).radius
			var portal_height := frame_top.position.y - frame_bottom.position.y + 2.0 * (frame_top.mesh as CapsuleMesh).radius
			if absf(portal_width / portal_height - 9.0 / 16.0) > 0.004:
				failures.append("%dx%d portrait portal is not 9:16 (got %.3f)" % [
					dimensions.x, dimensions.y, portal_width / portal_height])
		game.set_process(false)
		for phase in ["distant", "near"]:
			var progress := 0.0 if phase == "distant" else 0.92 * float(game.call("_progress_for_answer_line"))
			game.set("gate_progress", progress)
			game.call("_sync_visuals")
			for _frame in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			if screenshot == null or screenshot.is_empty() or screenshot.get_size() != dimensions:
				failures.append("%s %s screenshot is empty" % [dimensions, phase])
				continue
				var pixel_width := label_3d.font.get_string_size(
					label_3d.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_3d.font_size).x * label_3d.pixel_size
				var center := camera.unproject_position(label_3d.global_position)
				var right := camera.unproject_position(label_3d.global_position + Vector3(pixel_width * 0.5, 0.0, 0.0))
				if not Rect2(Vector2.ZERO, Vector2(dimensions)).has_point(center):
					failures.append("%s %s word plaque center is off screen at %s" % [dimensions, phase, center])
				if phase == "near" and absf(right.x - center.x) * 2.0 < 35.0:
					failures.append("%s %s rendered word projected narrower than 35px" % [dimensions, phase])
			var output := "user://_qa_human_plane_3d_%dx%d_%s.png" % [dimensions.x, dimensions.y, phase]
			var result := screenshot.save_png(ProjectSettings.globalize_path(output))
			if result != OK:
				failures.append("%s failed: %d" % [output, result])
			else:
				print("3D screenshot: ", ProjectSettings.globalize_path(output))
		game.queue_free()
		await process_frame
		await process_frame
	print("HUMAN PLANE 3D VISUAL: ", "PASS" if failures.is_empty() else "FAIL",
		" (6 planned captures across 3 resolutions; ", failures.size(), " failures)")
	for failure in failures:
		printerr("HUMAN PLANE 3D VISUAL FAIL: ", failure)
	quit(0 if failures.is_empty() else 1)
