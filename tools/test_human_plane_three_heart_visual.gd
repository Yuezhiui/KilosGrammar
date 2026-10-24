extends SceneTree

# Graphical-only screenshot QA (Godot 4.7.2).
# --rendering-method gl_compatibility --path . --script res://tools/test_human_plane_three_heart_visual.gd
# Temporary screenshots go into user://, NEVER the source art/assets folder.
const SCENE := preload("res://ui/minigames/human_plane.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Graphical display required for screenshot verification")
		quit(1)
		return
	for screen in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(screen)
		root.content_scale_size = screen
		root.size = screen
		for mode in ["Seconds", "Lives"]:
			var game := SCENE.instantiate() as Control
			root.add_child(game)
			game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			game.set_context({"activity": "Human Plane", "game_mode": mode,
				"topic": "Adjective", "difficulty": "Normal"})
			for _i in range(6):
				await process_frame
			game.set_process(false)
			game.set("gate_progress", 0.75)
			game.call("_sync_visuals")
			for _i in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			var file := "user://_qa_human_plane_3heart_%dx%d_%s.png" % [screen.x, screen.y, mode.to_lower()]
			var destination := ProjectSettings.globalize_path(file)
			var result := root.get_texture().get_image().save_png(destination)
			print("HUMAN PLANE HUD SCREENSHOT ", mode, " ", screen, " err=", result, " file=", destination)
			game.queue_free()
			await process_frame
			await process_frame
	quit(0)
