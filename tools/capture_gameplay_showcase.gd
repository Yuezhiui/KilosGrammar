extends SceneTree

# Generates authentic still frames using the existing, unmodified mini-game
# scenes. Run with Godot's graphical renderer (do not use --headless):
# Godot --path . --rendering-method gl_compatibility --script res://tools/capture_gameplay_showcase.gd

const SCENES := [
	{"name": "Catch the Word", "filename": "catch_the_word.png", "path": "res://ui/minigames/catch_the_word/catch_word.tscn"},
	{"name": "Balloon Popping", "filename": "balloon_popping.png", "path": "res://ui/minigames/balloon_popping/balloon_popping.tscn"},
	{"name": "Human Plane", "filename": "human_plane.png", "path": "res://ui/minigames/human_plane/human_plane.tscn"},
]

const SCREEN_SIZE := Vector2i(1280, 720)
const OUTPUT_DIR := "res://showcase/screens"


func _initialize() -> void:
	call_deferred("_capture_all")


func _capture_all() -> void:
	root.size = SCREEN_SIZE
	DisplayServer.window_set_size(SCREEN_SIZE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var successes := 0
	for data in SCENES:
		var packed: PackedScene = load(String(data["path"]))
		if packed == null:
			push_error("Could not load: " + String(data["path"]))
			continue
		var game := packed.instantiate() as Control
		if game == null:
			push_error("Not a Control: " + String(data["path"]))
			continue
		root.add_child(game)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game.set_context({
			"activity": data["name"],
			"topic": "Noun",
			"game_style": "Noun",
			"game_mode": "Activity",
			"difficulty": "Normal",
			"student_name": "SHOWCASE",
			"demo_mode": true,
		})
		# Allow Godot's real renderer and game simulation to build a presentable frame.
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		var output := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(String(data["filename"])))
		var error := picture.save_png(output)
		if error == OK:
			successes += 1
			print("CAPTURED ", output, " (", picture.get_width(), "x", picture.get_height(), ")")
		else:
			push_error("Capture save failed: %s error=%d" % [output, error])
		root.remove_child(game)
		game.queue_free()
		await process_frame
	if successes == SCENES.size():
		print("PASS  captured 3 authentic KilosGrammar gameplay screens")
		quit(0)
	else:
		push_error("Captured only %d/%d scenes" % [successes, SCENES.size()])
		quit(1)
