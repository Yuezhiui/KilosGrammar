extends SceneTree

# Safe illustrated-scene screenshots. Disable the scenes' scripts BEFORE
# mounting: this renders editor-authored art without starting the webcam,
# Python inference, PostgreSQL, or manipulating an existing student session.
# Run with: godot --path . --rendering-method gl_compatibility
#            --script res://tools/capture_calibration_redesign_20261102.gd

const OUTPUT := "res://showcase/calibration-redesign-20261102"
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const SCENES := {
	"single": "res://ui/vision/calibration/calibration.tscn",
	"multiplayer": "res://ui/vision/calibration/multiplayer_calibration.tscn",
	"human_plane_legacy": "res://ui/vision/calibration/human_plane_calibration.tscn",
}

var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Screenshots require a graphical renderer; no webcam started.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for viewport_size in SIZES:
		DisplayServer.window_set_size(viewport_size)
		root.size = viewport_size
		root.content_scale_size = viewport_size
		await process_frame
		for key in SCENES:
			var packed := load(SCENES[key]) as PackedScene
			if packed == null:
				errors.append("Cannot load " + SCENES[key])
				continue
			var panel := packed.instantiate() as Control
			if panel == null:
				errors.append("Cannot instantiate " + SCENES[key])
				continue
			# Disabling BEFORE _ready guarantees no camera autostart.
			panel.set_script(null)
			root.add_child(panel)
			panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var design := panel.get_node_or_null("TutorialStage") as Control
			if design == null:
				design = panel.get_node_or_null("Stage") as Control
			if design != null:
				var factor := minf(float(viewport_size.x) / 1280.0, float(viewport_size.y) / 720.0)
				design.scale = Vector2.ONE * factor
				design.position = (Vector2(viewport_size) - Vector2(1280.0, 720.0) * factor) * 0.5
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var dest := ProjectSettings.globalize_path(
				OUTPUT.path_join("%s_%dx%d.png" % [key, viewport_size.x, viewport_size.y]))
			if image.save_png(dest) != OK:
				errors.append("Cannot save " + dest)
			else:
				print("CAPTURED ", dest)
			root.remove_child(panel)
			panel.queue_free()
			await process_frame
	if errors.is_empty():
		print("CALIBRATION VISUAL CAPTURE: PASS")
		quit(0)
	else:
		for error in errors:
			printerr(error)
		quit(1)
