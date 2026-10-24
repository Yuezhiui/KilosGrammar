extends SceneTree

# Real graphical viewport screenshot harness for the authored Human Plane art.
# Godot --path . --rendering-method gl_compatibility --script res://tools/test_human_plane_asset_visual.gd
# Output files are disposable and may be removed after visual inspection.
const SCENE := preload("res://ui/minigames/human_plane.tscn")
const OUTPUT := "res://Components/HumanPlaneAssets/_qa_visual_"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Graphical rendering required; do not treat headless as a screenshot PASS")
		quit(1)
		return
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(resolution)
		root.content_scale_size = resolution
		root.size = resolution
		var game := SCENE.instantiate() as Control
		root.add_child(game)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game.set_context({"activity": "Human Plane", "topic": "Adjective", "difficulty": "Hard", "game_mode": "Lives"})
		for _i in range(6):
			await process_frame
		game.set_process(false)
		# Check approaching gate and answer-line poses. Scene-authored gate art
		# has a transparent opening but opaque LEFT/CENTER/RIGHT footer, so gate
		# frame must be layered above the plane while the center reveals it.
		for progress in [0.75, 0.85]:
			game.set("gate_progress", progress)
			game.call("_sync_visuals")
			for _i in range(4):
				await process_frame
			await RenderingServer.frame_post_draw
			var path := OUTPUT + "%dx%d_p%02d.png" % [resolution.x, resolution.y, int(round(progress * 100.0))]
			var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			print("VISUAL HumanPlane ", resolution, " progress=", progress, " saved=", path, " error=", result)
		game.queue_free()
		await process_frame
		await process_frame
	quit(0)
