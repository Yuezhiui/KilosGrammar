extends SceneTree

# Native static UI captures of the *live* editor-authored Profile/Game setup.
# No MainMenu/database/pose worker is instantiated. Input field changes are
# synthetic and exist only in this temporary scene.

const SCENE := "res://ui/student/setup/student_setup.tscn"
const OUTPUT := "res://showcase/student_setup_original_components_20261102"
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Graphical renderer required for UI screenshots.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var original := load(SCENE) as PackedScene
	if original == null:
		printerr("Cannot load Student Setup scene.")
		quit(1)
		return
	for dimensions in SIZES:
		DisplayServer.window_set_size(dimensions)
		root.size = dimensions
		root.content_scale_size = dimensions
		await process_frame
		var scene := original.instantiate() as Control
		root.add_child(scene)
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		await _snap("%s_profile_%dx%d.png" % ["student", dimensions.x, dimensions.y])
		(scene.get("_student_id_edit") as LineEdit).text = "DEMO-001"
		(scene.get("_name_edit") as LineEdit).text = "Sample Student"
		(scene.get("_grade_edit") as LineEdit).text = "Grade 2 Apple"
		scene.set("_setup_phase", "game")
		scene.call("_show_setup_phase")
		scene.call("_select_style", "Noun")
		scene.call("_select_mode", "Seconds")
		scene.call("_select_difficulty", "Easy")
		scene.call("_select_player_mode", "Single Player")
		await process_frame
		await _snap("%s_game_%dx%d.png" % ["student", dimensions.x, dimensions.y])
		root.remove_child(scene)
		scene.queue_free()
		await process_frame
	print("PROFILE/GAME UI GRAPHICAL CAPTURE PASS")
	quit(0)

func _snap(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var dest := ProjectSettings.globalize_path(OUTPUT.path_join(filename))
	var status := root.get_texture().get_image().save_png(dest)
	if status != OK:
		printerr("Cannot save screenshot: " + dest)
	else:
		print("CAPTURED " + dest)
