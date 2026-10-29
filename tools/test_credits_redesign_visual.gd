extends SceneTree

# Real GPU captures for the scene-authored Credits design. No live webcam,
# database or Main Menu launch. Screenshots go to Godot user:// outside repo.
const CREDITS_SCENE := "res://ui/secondary/credits/credits.tscn"
const VIEWPORT_SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Credits visual QA needs a real graphics renderer (opengl3).")
		quit(1)
		return
	for viewport_size in VIEWPORT_SIZES:
		root.size = viewport_size
		DisplayServer.window_set_size(viewport_size)
		var packed := load(CREDITS_SCENE) as PackedScene
		var scene := packed.instantiate() as Control
		root.add_child(scene)
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var stage := scene.get_node_or_null("CreditsStage") as Control
		var backdrop := scene.get_node_or_null("CreditsStage/ClassroomBackground") as TextureRect
		var board := scene.get_node_or_null("CreditsStage/WoodenBoard") as TextureRect
		var title := scene.get_node_or_null("CreditsStage/CreditsTitle") as TextureRect
		var scroll := scene.get_node_or_null("CreditsStage/CreditsScroll") as ScrollContainer
		var home := scene.get_node_or_null("CreditsStage/BackButton") as Button
		_check(stage != null and backdrop != null and board != null
			and title != null and scroll != null and home != null,
			"%s: independently editable banner, background, board, scroll and Home" % viewport_size)
		if stage != null and home != null:
			_check(home.get_global_rect().position.x >= 0.0 and
				home.get_global_rect().end.x <= viewport_size.x + 1.0
				and home.get_global_rect().end.y <= viewport_size.y + 1.0,
				"%s: Home remains on screen" % viewport_size)
		if scroll != null:
			var stack := scroll.get_node_or_null("ScrollCenter/CreditsStack") as VBoxContainer
			_check(stack != null and stack.get_node_or_null("KernelHeading") is Label
				and stack.get_node_or_null("Name11") is Label,
				"%s: individual editor-draggable names are in the scroll list" % viewport_size)
		var file := "user://_qa_credits_redesign_%dx%d.png" % [viewport_size.x, viewport_size.y]
		_check(root.get_texture().get_image().save_png(file) == OK,
			"%s: rendered screenshot saved" % viewport_size)
		print("CREDITS_VISUAL_CAPTURE=", ProjectSettings.globalize_path(file))
		scene.queue_free()
		await process_frame
	print("CREDITS GPU: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
		printerr("Credits visual fail: " + reason)
