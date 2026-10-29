extends SceneTree

# Isolated GET READY scene QA. No gameplay, webcam, database, or student data.
# Graphical screenshots: godot --path . --rendering-method gl_compatibility --script res://tools/test_guided_countdown_visual_20261030.gd -- --capture
# Headless layout/timer: godot --headless --path . --script res://tools/test_guided_countdown_visual_20261030.gd

const SCENE := preload("res://ui/play/gameplay/guided_countdown.tscn")
const CLASSROOM := "res://Components/Gameplay/Calibration/BACKGROUND.png"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const OUTPUT := "res://showcase/qa_guided_countdown_20261030"

var failures: Array[String] = []
var checks := 0
var captures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var capture := OS.get_cmdline_user_args().has("--capture")
	if capture and DisplayServer.get_name() == "headless":
		_fail("Graphical --capture requested on a headless display")
		_finish()
		return
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for dimensions in SIZES:
		root.size = dimensions
		root.content_scale_size = dimensions
		if capture:
			DisplayServer.window_set_size(dimensions)
		await process_frame
		await process_frame
		await _check_scene(dimensions, capture)
	_finish()


func _check_scene(dimensions: Vector2i, capture: bool) -> void:
	var scene := SCENE.instantiate() as Control
	_expect(scene != null, "%s scene instantiates" % dimensions)
	if scene == null:
		return
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var bg := scene.get_node_or_null("ClassroomBackground") as TextureRect
	var dim := scene.get_node_or_null("DimBackdrop") as ColorRect
	var title := scene.get_node_or_null("GetReadyTitle") as Label
	var count := scene.get_node_or_null("CountdownNumber") as Label
	var hint := scene.get_node_or_null("MovementHint") as Label
	var timer := scene.get_node_or_null("CountdownTimer") as Timer
	_expect(bg != null and bg.owner == scene, "%s editor-authored classroom" % dimensions)
	_expect(dim != null and dim.owner == scene, "%s editor-authored dimmer" % dimensions)
	_expect(title != null and count != null and hint != null and timer != null,
		"%s original labels and timer present" % dimensions)
	if bg != null and dim != null:
		_expect(bg.texture != null and bg.texture.resource_path == CLASSROOM,
			"%s same image resource as calibration" % dimensions)
		_expect(bg.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
			"%s classroom covers viewport without distortion" % dimensions)
		_expect(bg.size.is_equal_approx(Vector2(dimensions)) and dim.size.is_equal_approx(Vector2(dimensions)),
			"%s both background and overlay fill screen" % dimensions)
		_expect(dim.color.is_equal_approx(Color(0, 0, 0, 0.1)),
			"%s overlay is exactly 10%% black" % dimensions)
		_expect(scene.get_child(0) == bg and scene.get_child(1) == dim,
			"%s background then dimmer then countdown UI" % dimensions)
	if title != null and count != null and hint != null:
		_expect(title.text == "GET READY!" and count.text == "3" and not hint.text.is_empty(),
			"%s initial GET READY and 3 and movement hint" % dimensions)
		for node in [title, count, hint]:
			var bounds: Rect2 = (node as Control).get_global_rect()
			_expect(absf(bounds.get_center().x - float(dimensions.x) / 2.0) < 1.0,
				"%s %s stays horizontally centered" % [dimensions, node.name])
			_expect(bounds.position.y >= 0 and bounds.end.y <= dimensions.y,
				"%s %s remains on screen" % [dimensions, node.name])
	if timer != null and count != null:
		_expect(is_equal_approx(timer.wait_time, 1.0) and not timer.one_shot,
			"%s timer remains one-second repeating" % dimensions)
	if capture:
		await RenderingServer.frame_post_draw
		var pixels := root.get_texture().get_image()
		_expect(pixels.get_size() == dimensions,
			"%s actual screenshot dimensions" % dimensions)
		var target := ProjectSettings.globalize_path(OUTPUT.path_join("get_ready_%dx%d.png" % [dimensions.x, dimensions.y]))
		if pixels.save_png(target) == OK:
			captures += 1
			print("CAPTURED ", target)
		else:
			_fail("Cannot save %s" % target)
	if timer != null and count != null:
		timer.start()
		await timer.timeout
		count.text = "2"
		_expect(count.text == "2", "%s tick changes 3 to 2" % dimensions)
		await timer.timeout
		count.text = "1"
		_expect(count.text == "1", "%s tick changes 2 to 1" % dimensions)
		timer.stop()
	scene.queue_free()
	await process_frame


func _expect(valid: bool, label: String) -> void:
	checks += 1
	if not valid:
		_fail(label)


func _fail(message: String) -> void:
	failures.append(message)


func _finish() -> void:
	for failure in failures:
		push_error("GET READY QA FAIL: " + failure)
	print("GET READY QA: %d checks, %d errors, %d captures" % [checks, failures.size(), captures])
	if failures.is_empty():
		print("PASS GET READY scene across 1280x720, 1600x900 and 1920x1080")
	quit(0 if failures.is_empty() else 1)
