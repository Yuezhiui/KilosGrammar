extends SceneTree

const SETTINGS_SCENE := preload("res://ui/secondary/settings.tscn")
const OUT_DIR := "user://_qa_settings_audio_only"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var res := Vector2i(1280, 720)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(res)
	root.size = res
	root.content_scale_size = res
	var global_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(global_dir)

	for tab in ["settings"]:
		var scene := SETTINGS_SCENE.instantiate() as Control
		root.add_child(scene)
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await create_timer(0.1).timeout
		scene.call("_show_audio_display")
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var out_path := global_dir.path_join("new_settings_%s_1280x720.png" % tab)
		img.save_png(out_path)
		print("CAPTURED: ", out_path)
		root.remove_child(scene)
		scene.queue_free()
		await process_frame

	quit(0)
