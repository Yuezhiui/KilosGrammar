extends SceneTree

# Graphical-only QA: authentic main menu and student setup screenshots for the
# approved KilosGrammar UI redesign. Originals are not modified.
# Godot --path . --rendering-method gl_compatibility --script res://tools/capture_ui_redesign_m1.gd

const OUTPUT := "res://showcase/ui_redesign_m1"
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const SCENES := [
	{"key": "main", "path": "res://ui/main_menu/main_menu.tscn"},
	{"key": "student_setup", "path": "res://ui/student/setup/student_setup.tscn"},
]

var failures: Array[String] = []
var captures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("UI screenshot QA requires a graphical display")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for viewport_size in SIZES:
		DisplayServer.window_set_size(viewport_size)
		root.size = viewport_size
		root.content_scale_size = viewport_size
		await process_frame
		await process_frame
		for scene_data in SCENES:
			await _capture_scene(scene_data, viewport_size)
	if failures.is_empty():
		print("PASS UI_REDESIGN_CAPTURE: %d images" % captures)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _capture_scene(scene_data: Dictionary, viewport_size: Vector2i) -> void:
	var packed := load(String(scene_data["path"])) as PackedScene
	if packed == null:
		failures.append("Cannot load %s" % scene_data["path"])
		return
	var panel := packed.instantiate() as Control
	if panel == null:
		failures.append("Cannot instantiate %s" % scene_data["path"])
		return
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if panel.has_method("set_context"):
		panel.call("set_context", {"entry_source": "play", "demo_mode": true})
	# Allow MainMenu intro animation and asynchronous texture import/rendering.
	await create_timer(1.5 if String(scene_data["key"]) == "main" else 0.4).timeout
	await RenderingServer.frame_post_draw
	var pixels := root.get_texture().get_image()
	var name := "%s_%dx%d.png" % [scene_data["key"], viewport_size.x, viewport_size.y]
	var file_path := ProjectSettings.globalize_path(OUTPUT.path_join(name))
	var error := pixels.save_png(file_path)
	if error == OK:
		captures += 1
		print("CAPTURED ", file_path, " (", pixels.get_width(), "x", pixels.get_height(), ")")
	else:
		failures.append("Screenshot save error %d: %s" % [error, file_path])
	root.remove_child(panel)
	panel.queue_free()
	await process_frame
