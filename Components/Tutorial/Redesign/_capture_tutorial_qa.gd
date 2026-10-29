extends SceneTree

# Temporary screenshot-only runner, no application router or camera.
const SIZE_OPTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const SCENES := {
	"home": "res://ui/tutorial/tutorial_home.tscn",
	"grammar": "res://ui/tutorial/grammar_guide/grammar_guide.tscn",
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output := ProjectSettings.globalize_path("res://Components/Tutorial/Redesign/QA")
	DirAccess.make_dir_recursive_absolute(output)
	var failures := 0
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	for size in SIZE_OPTIONS:
		DisplayServer.window_set_size(size)
		root.size = size
		root.content_scale_size = size
		await process_frame
		for name in SCENES:
			var packed := load(SCENES[name]) as PackedScene
			var scene := packed.instantiate() as Control
			root.add_child(scene)
			scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			await process_frame
			await process_frame
			var stage := scene.get_node_or_null("TutorialStage") as Control
			if stage != null:
				var rect := stage.get_global_rect()
				print("TUTORIAL GRAPHIC STAGE ", name, " ", size, " rect=", rect)
			if name == "grammar":
				var scroll := scene.get_node("TutorialStage/GrammarCardScroll") as ScrollContainer
				var grid := scroll.get_node("GridContainer") as GridContainer
				print("TUTORIAL GRAMMAR GRID count=", grid.get_child_count(),
					" scroll=", scroll.size, " grid=", grid.size)
				if grid.get_child_count() != 5:
					failures += 1
				for item in grid.get_children():
					print("TUTORIAL CARD ", item.name, " ", item.get_global_rect())
					var title := item.get_node_or_null("TopicName") as Label
					var badge := item.get_node_or_null("TopicBadge") as TextureRect
					if title == null or title.text not in ["NOUN", "PRONOUN", "VERB", "ADJECTIVE", "ADVERB"]:
						failures += 1
						if item.get_node_or_null("PanelArtwork") != null or badge == null or badge.texture == null:
						failures += 1
				var old := scroll.scroll_vertical
				scroll.scroll_vertical = 300
				await process_frame
				print("TUTORIAL SCROLL vertical old=", old, " now=", scroll.scroll_vertical)
				if scroll.scroll_vertical <= 0:
					failures += 1
				await RenderingServer.frame_post_draw
				var scrolled_file := output.path_join("grammar_scrolled_%dx%d.png" % [size.x, size.y])
				var scrolled_err := root.get_texture().get_image().save_png(scrolled_file)
				print("TUTORIAL SCROLLED SCREENSHOT ", scrolled_file, " saved=", scrolled_err)
				if scrolled_err != OK:
					failures += 1
				scroll.scroll_vertical = 0
				await process_frame
				var back := scene.get_node("TutorialStage/BackButton") as Button
				var routes: Array[String] = []
				scene.requested.connect(func(target: String, _payload: Dictionary) -> void: routes.append(target))
				back.pressed.emit()
				if routes != ["tutorial_home"]:
					failures += 1
			await RenderingServer.frame_post_draw
			var path := output.path_join("%s_%dx%d.png" % [name, size.x, size.y])
			var image := root.get_texture().get_image()
			var error := image.save_png(path)
			print("TUTORIAL SCREENSHOT ", path, " dimensions=", image.get_size(), " saved=", error)
			if error != OK or image.get_size() != size:
				failures += 1
			scene.queue_free()
			await process_frame
	print("TUTORIAL SCREENSHOT QA complete failures=", failures)
	quit(1 if failures > 0 else 0)
