extends SceneTree

## True 2D pseudo-perspective Human Plane visual/geometry contract.
## Native Godot UI renders original plane and ARC/answer PNGs; never a 3D
## Viewport or synthetic collision gate. Camera/DB are not used.
## Run headless: godot --headless --path . --script res://tools/test_human_plane_2d_arc_screen_stress.gd
## GPU captures: godot --path . --rendering-method gl_compatibility --script res://tools/test_human_plane_2d_arc_screen_stress.gd -- --capture
const SCENE := "res://ui/minigames/human_plane/human_plane.tscn"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const LANES := ["Left", "Center", "Right"]
const PROGRESS := [0.0, 0.15, 0.35, 0.55, 0.78, 1.0]
var capture := false
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(25.0).timeout
	_check(false, "Pseudo-3D ARC capture/test exceeded timeout")
	quit(1)


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	_check(packed != null, "Actual Human Plane standalone 2D scene loads")
	if packed == null:
		_finish()
		return
	var scene_text := FileAccess.get_file_as_string(SCENE)
	_check(not scene_text.contains("human_plane_3d_view.tscn") and
		not scene_text.contains("SubViewport"),
		"ARC-first uses native Godot 2D artwork, not old 3D render target")
	for size in SIZES:
		for iteration in range(2):
			await _check_scene(packed, size, iteration)
	_finish()


func _check_scene(packed: PackedScene, dims: Vector2i, repetition: int) -> void:
	root.size = dims
	root.content_scale_size = Vector2i(1280, 720)
	var label := "%s/repetition%d" % [dims, repetition]
	var game := packed.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_process(false)
	game.set_context({"activity": "Human Plane", "game_mode": "Seconds",
		"topic": "Noun", "difficulty": "Normal", "keyboard_mode": false})
	await process_frame
	_check(game.get_node_or_null("WorldView3D") == null and
		game.get_node_or_null("FlightBackground") is TextureRect,
		label + " screen has original 2D panorama, never a 3D SubViewport")
	var background := game.get_node_or_null("FlightBackground") as TextureRect
	_check(background != null and background.is_visible_in_tree() and background.texture != null,
		label + " native background texture fills the 2D flight area")
	var plane := game.get_node_or_null("PlaneRig/PlaneArtwork") as TextureRect
	var rig := game.get_node_or_null("PlaneRig") as Control
	var hitbox := game.get_node_or_null("PlaneRig/Hitbox") as Control
	_check(plane != null and plane.texture != null and plane.is_visible_in_tree() and
		rig != null and hitbox != null,
		label + " original red airplane PNG and authoritative hitbox survive")
	var moving := game.get_node_or_null("MovingGates") as Control
	var upcoming := game.get_node_or_null("UpcomingGates") as Control
	_check(moving != null and upcoming != null,
		label + " current and upcoming ARC trios remain separately editable")
	if moving == null or upcoming == null:
		game.queue_free()
		await process_frame
		return
	var previous_areas := [0.0, 0.0, 0.0]
	for position in PROGRESS:
		var rects: Array[Rect2] = []
		for lane_id in range(3):
			var name: String = LANES[lane_id]
			var gate := moving.get_node_or_null("Gate" + name) as Control
			var next_gate := upcoming.get_node_or_null("Gate" + name) as Control
			var art := gate.get_node_or_null("GateArtwork") as TextureRect if gate != null else null
			var text := gate.get_node_or_null("WordLabel") as Label if gate != null else null
			var next_art := next_gate.get_node_or_null("GateArtwork") as TextureRect if next_gate != null else null
			_check(art != null and art.texture != null and next_art != null and
				next_art.texture != null and text != null,
				label + " editor ARC PNGs and answer text intact on " + name)
			var drawn: Rect2 = game.call("_gate_visible_rect", lane_id, position)
			_check(drawn.has_area() and is_finite(drawn.position.x) and
				drawn.size.x > 1 and drawn.size.y > 1,
				label + " visible actual gate PNG has positive bounds through flight " + name)
			var area: float = drawn.get_area()
			_check(area + 0.001 >= float(previous_areas[lane_id]),
				label + " ARC perspective grows smoothly approaching viewer " + name)
			if text != null:
				var long_answer := "EXTRAORDINARY"
				var max_text_width := drawn.size.x * 0.70
				var fitted: Dictionary = game.call("_gate_word_fit", long_answer,
					max_text_width, 22)
				_check(int(fitted.get("font_size", 0)) >= 8 and
					float(fitted.get("scale_x", 0.0)) > 0.0 and
					float(fitted.get("rendered_width", INF)) <= maxf(1.0, max_text_width * 0.88 + 0.1),
					label + " long answer remains fitted within native ARC word plaque " + name)
			previous_areas[lane_id] = area
			rects.append(drawn)
		_check(rects[0].get_center().x < rects[1].get_center().x and
			rects[1].get_center().x < rects[2].get_center().x,
			label + " left/center/right projection order remains stable at " + str(position))
	var center_x := float(game.get("plane_x_norm"))
	game.call("set_airplane_pose_active", false)
	game.call("set_body_x", 1.0)
	game.call("_update_plane_motion", 0.8)
	_check(is_equal_approx(center_x, float(game.get("plane_x_norm"))),
		label + " uncalibrated input cannot move the ARC game score hitbox")
	game.call("set_airplane_pose_active", true)
	game.call("set_body_x", 1.0)
	game.call("_update_plane_motion", 0.1)
	_check(float(game.get("plane_x_norm")) > center_x,
		label + " fresh teacher-authorized steering visibly moves plane horizontally")
	var frozen := float(game.get("plane_x_norm"))
	game.call("set_airplane_pose_active", false)
	game.call("_update_plane_motion", 0.6)
	_check(is_equal_approx(float(game.get("plane_x_norm")), frozen),
		label + " lost pose freezes actual collision-plane x")
	var original_score: int = int(game.get("score"))
	game.call("_sync_visuals")
	_check(int(game.get("score")) == original_score,
		label + " drawing 2D gate sprites cannot register an arbitrary score")
	if capture and repetition == 0 and DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		_check(frame != null and frame.get_width() == dims.x and frame.get_height() == dims.y,
			label + " 2D scene GPU framebuffer matches selected physical resolution")
		if frame != null:
			var path := "user://_qa_plane_2d_arc_%dx%d.png" % [dims.x, dims.y]
			_check(frame.save_png(path) == OK, label + " screenshot captures 2D ARC flight sprites")
			print("2D ARC SCREENSHOT: ", ProjectSettings.globalize_path(path))
	game.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(game), label + " 2D scene tears down without retaining gameplay")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("2D ARC QA FAIL: ", message)


func _finish() -> void:
	print("HUMAN PLANE TRUE 2D ARC SCREEN QA: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
