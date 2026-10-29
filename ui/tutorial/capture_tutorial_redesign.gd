extends SceneTree

# Real Godot frame captures for the current tutorial and camera screens.
# Match the project's native 1280x720 canvas_items stretch. Borderless QA avoids
# Windows work-area clamping of the requested 1920x1080 capture dimensions.
const OUTPUT := "res://showcase/ui_redesign_m1"
const DIMENSIONS := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const SCREENS := {
	"tutorial_home": "res://ui/tutorial/tutorial_home.tscn",
	"grammar_guide": "res://ui/tutorial/grammar_guide/grammar_guide.tscn",
	"calibration": "res://ui/vision/calibration/calibration.tscn"
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Tutorial visual QA requires the graphical renderer")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var captures := 0
	var failures := 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	for size in DIMENSIONS:
		DisplayServer.window_set_size(size)
		root.size = size
		root.content_scale_size = Vector2i(1280, 720)
		await process_frame
		print("TUTORIAL_QA_WINDOW requested=", size, " physical=", DisplayServer.window_get_size(), " logical=", root.content_scale_size)
		for id in SCREENS:
			var scene := load(SCREENS[id]) as PackedScene
			if scene == null:
				failures += 1
				continue
			var screen := scene.instantiate() as Control
			root.add_child(screen)
			screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			if screen.has_method("set_context"):
				screen.call("set_context", {"entry_source": "tutorial", "preview_mode": true, "camera_live": false, "name": "TEST STUDENT"})
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var file_name := "%s_%dx%d.png" % [id, size.x, size.y]
			var target := ProjectSettings.globalize_path(OUTPUT.path_join(file_name))
			var frame := root.get_texture().get_image()
			if frame.get_size() != size:
				push_error("Tutorial capture size mismatch: requested=%s actual=%s" % [size, frame.get_size()])
				failures += 1
			var err := frame.save_png(target)
			if err == OK:
				captures += 1
				print("CAPTURED ", target)
			else:
				failures += 1
			screen.queue_free()
			await process_frame
	print("TUTORIAL REDESIGN: %d captures, %d failures" % [captures, failures])
	quit(0 if failures == 0 and captures == SCREENS.size() * DIMENSIONS.size() else 1)
