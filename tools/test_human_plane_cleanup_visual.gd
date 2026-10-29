extends SceneTree

# Capture a genuine graphical Godot viewport without editing the user's scene.
# Godot --path . --rendering-method gl_compatibility --script res://tools/test_human_plane_cleanup_visual.gd
const SCENE := preload("res://ui/minigames/human_plane/human_plane.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Graphical renderer required for visual QA")
		quit(1)
		return
	for dims in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(dims)
		root.content_scale_size = dims
		root.size = dims
		for mode in ["Seconds", "Lives"]:
			var game := SCENE.instantiate() as Control
			root.add_child(game)
			game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			game.set_context({"activity": "Human Plane", "topic": "Noun", "difficulty": "Normal", "game_mode": mode})
			for _i in range(5):
				await process_frame
			game.set_process(false)
			game.call("_sync_visuals")
			for _i in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			var file := "user://_qa_human_cleanup_%dx%d_%s.png" % [dims.x, dims.y, mode.to_lower()]
			var err := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(file))
			print("VISUAL:", file, " status=", err)
			game.queue_free()
			await process_frame
			await process_frame
	quit(0)
