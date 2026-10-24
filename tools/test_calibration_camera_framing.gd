extends SceneTree

## Inspect live-video display without opening a webcam or loading YOLO.
## The authored DEFAULT scales live video to the manually edited camera
## rectangle, without internal aspect-ratio bars; teachers can change
## position/size/stretch mode in the Inspector with no GDScript override.
## No hardware or YOLO is required.
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _run() -> void:
	var scene := load("res://ui/vision/calibration.tscn") as PackedScene
	_check(scene != null, "Calibration scene can load after PoseService autoload")
	if scene == null:
		quit(1)
		return
	for viewport in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport
		var screen := scene.instantiate() as Control
		root.add_child(screen)
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		screen.set_process(false)
		var camera := screen.get_node("TutorialStage/LiveCameraInset") as TextureRect
		var backing := screen.get_node("TutorialStage/CameraBlackBacking") as ColorRect
		var art := screen.get_node("TutorialStage/ArtCameraFrame") as TextureRect
		_check(camera != null and camera.owner == screen, "Camera is editor-authored at %s" % viewport)
		_check(backing.owner == screen and art.owner == screen,
			"Camera backing and decorative border remain independent scene-authored UI at %s" % viewport)
		_check(backing.get_node_or_null("CameraAmbientFill") == null,
			"No extra webcam image or gray peripheral fill remains at %s" % viewport)
		_check(backing.get_child_count() == 0 and backing.color == Color.BLACK,
			"Camera background is plain editable black, never a ghost image at %s" % viewport)
		_check(camera.get_child_count() == 0,
			"No camera overlay or manual layout is forced by child nodes at %s" % viewport)
		var authored_mode := camera.stretch_mode
		_check(authored_mode == TextureRect.STRETCH_SCALE,
			"Camera defaults to Scale: the webcam fills all of the LiveCameraInset rect at %s" % viewport)
		# Use Keep Aspect Centered for this specific full-frame check, but do
		# NOT require it in the scene: teachers may select a different mode.
		camera.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		for shape in [Vector2i(640, 480), Vector2i(640, 360)]:
			var image := Image.create(shape.x, shape.y, false, Image.FORMAT_RGB8)
			image.fill(Color.BLACK)
			image.set_pixel(0, 0, Color.YELLOW)
			image.set_pixel(shape.x - 1, shape.y - 1, Color.GREEN)
			camera.texture = ImageTexture.create_from_image(image)
			camera.visible = true
			await process_frame
			var rect := camera.get_global_rect()
			var scale := minf(rect.size.x / float(shape.x), rect.size.y / float(shape.y))
			var fitted := Rect2(rect.position + (rect.size - Vector2(shape) * scale) * 0.5,
				Vector2(shape) * scale)
			_check(rect.encloses(fitted), "Entire %s frame is contained at %s" % [shape, viewport])
			_check(fitted.size.x > 0 and fitted.size.y > 0 and camera.texture.get_size() == Vector2(shape),
				"Original full camera texture is untouched and visible at %s" % viewport)
			_check(is_equal_approx(fitted.size.x / fitted.size.y, float(shape.x) / shape.y),
				"Video preserves its native %s aspect ratio at %s" % [shape, viewport])
		camera.stretch_mode = authored_mode
		var baseline_position := camera.position
		var baseline_size := camera.size
		var baseline_image := Image.create(640, 480, false, Image.FORMAT_RGB8)
		baseline_image.fill(Color.DIM_GRAY)
		screen.set("intro_running", false)
		screen.call("_on_live_preview", ImageTexture.create_from_image(baseline_image))
		await process_frame
		_check(backing.get_child_count() == 0,
			"Incoming preview does not create duplicate blurry webcam background at %s" % viewport)
		_check(camera.stretch_mode == authored_mode and camera.position.is_equal_approx(baseline_position)
			and camera.size.is_equal_approx(baseline_size),
			"Live video honors every authored camera setting at %s" % viewport)
		# Pretend the teacher changed these fields in the scene Inspector.
		# The runtime preview callback must not overwrite any of them.
		var manually_edited_position := camera.position + Vector2(8.0, 6.0)
		var manually_edited_size := camera.size + Vector2(18.0, 10.0)
		camera.position = manually_edited_position
		camera.size = manually_edited_size
		camera.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var manual_image := Image.create(640, 480, false, Image.FORMAT_RGB8)
		manual_image.fill(Color.DIM_GRAY)
		screen.call("_on_live_preview", ImageTexture.create_from_image(manual_image))
		await process_frame
		_check(camera.position.is_equal_approx(manually_edited_position),
			"Incoming frames never reset a manually edited camera position at %s" % viewport)
		_check(camera.size.is_equal_approx(manually_edited_size),
			"Incoming frames never reset a manually edited camera size at %s" % viewport)
		_check(camera.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
			"The teacher's manually selected camera crop/stretch mode persists at %s" % viewport)
		_check(backing.get_global_rect().has_area(),
			"Independent black backdrop remains editable at %s" % viewport)
		camera.texture = null
		camera.visible = false
		screen.queue_free()
		await process_frame
	if failures.is_empty():
		print("PASS calibration camera full-frame display: %d checks at 1280/1920, both 4:3 and 16:9" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
