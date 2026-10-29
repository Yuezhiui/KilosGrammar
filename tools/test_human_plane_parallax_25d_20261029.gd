extends SceneTree

# 2.5D Human Plane visual QA: two independently authored Parallax2D strips
# over the unchanged PNG runway; no 3D renderer, real camera, YOLO or DB.
# Native screenshots: --rendering-driver opengl3 -- --capture
const GAME := preload("res://ui/minigames/human_plane/human_plane.tscn")
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1920, 1080)]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var capture := OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	for dims: Vector2i in VIEWPORTS:
		root.size = dims
		root.content_scale_size = dims
		await process_frame
		var game := GAME.instantiate() as Control
		root.add_child(game)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game.set_context({"topic": "Noun", "difficulty": "Normal",
			"game_mode": "Seconds", "camera_live": false})
		await process_frame
		await process_frame
		game.set_process(false)
		var parallax := game.get_node_or_null("ParallaxVisuals") as Node2D
		var far := game.get_node_or_null("ParallaxVisuals/FarClouds") as Parallax2D
		var near := game.get_node_or_null("ParallaxVisuals/NearClouds") as Parallax2D
		var fixed_bg := game.get_node_or_null("FlightBackground") as TextureRect
		_check(parallax != null and far != null and near != null,
			str(dims) + " two editable native Parallax2D strips are present")
		if parallax == null or far == null or near == null:
			game.queue_free()
			await process_frame
			continue
		_check(fixed_bg != null and fixed_bg.texture != null and
			fixed_bg.texture.resource_path.ends_with("Human Plane/BACKGROUND.png") and
			fixed_bg.position.is_zero_approx(), str(dims) + " keeps original fixed painted background")
		_check(game.get_node_or_null("WorldView3D") == null and
			game.get_node_or_null("SubViewport3D") == null,
			str(dims) + " no 3D world/viewport/GPU-demanding scene")
		_check(far.z_index == 0 and near.z_index == 0 and parallax.z_index < 0 and
			fixed_bg.z_index < parallax.z_index,
			str(dims) + " clouds are above the background but below gates/aircraft")
		_check(far.scroll_scale.x < near.scroll_scale.x and
			far.repeat_size.x >= 1280.0 and near.repeat_size.x >= 1280.0 and
			far.ignore_camera_scroll and near.ignore_camera_scroll,
			str(dims) + " two depth factors and seamless looping are inspector-authored")
		var source_cloud: Texture2D = null
		for layer in [far, near]:
			_check(layer.get_child_count() >= 2, str(dims) + " independently editable sprite clouds")
			for child in layer.get_children():
				var sprite := child as Sprite2D
				_check(sprite != null and sprite.texture != null and sprite.owner == game,
					str(dims) + " manually placed native Sprite2D and texture")
				if sprite != null and sprite.texture != null:
					if source_cloud == null:
						source_cloud = sprite.texture
					_check(sprite.texture == source_cloud, str(dims) + " clouds reuse one low-memory PNG")
		_check(parallax.scale.is_equal_approx(Vector2(dims) / Vector2(1280, 720)),
			str(dims) + " whole visual canvas scales without overwriting sprite Inspector positions")
		var editor_position := (far.get_child(0) as Sprite2D).position
		var start_far := far.scroll_offset
		var start_near := near.scroll_offset
		var original_gate := (game._gate_nodes[1] as Control).get_rect()
		var original_plane := (game.get_node("PlaneRig") as Control).get_rect()
		var original_lives: int = int(game.lives)
		var original_score: int = int(game.score)
		game.started = true
		game.running = false
		game.airplane_pose_active = true
		game._process(0.4)
		_check(far.scroll_offset.is_equal_approx(start_far) and
			near.scroll_offset.is_equal_approx(start_near),
			str(dims) + " countdown/Spotlight does not animate clouds")
		game.running = true
		for _frame in range(120):
			game._process(1.0 / 60.0)
		var drift_far := absf(far.scroll_offset.x - start_far.x)
		var drift_near := absf(near.scroll_offset.x - start_near.x)
		_check(drift_far > 5.0 and drift_near > drift_far * 2.0,
			str(dims) + " near cloud layer travels noticeably faster than far")
		_check((far.get_child(0) as Sprite2D).position.is_equal_approx(editor_position),
			str(dims) + " animation never overwrites artist cloud layout")
		_check(original_lives == game.lives and original_score == game.score and
			game.time_remaining < 60.0 and game.time_remaining > 57.0,
			str(dims) + " true game 60s/3 hearts and scoring remain intact")
		var before_pause := far.scroll_offset
		var near_before_pause := near.scroll_offset
		game.paused = true
		game._process(1.0)
		_check(far.scroll_offset.is_equal_approx(before_pause) and
			near.scroll_offset.is_equal_approx(near_before_pause),
			str(dims) + " Pause freezes all scenery")
		game.paused = false
		game.airplane_pose_active = false
		game._process(1.0 / 60.0)
		_check(far.scroll_offset.is_equal_approx(before_pause) and
			near.scroll_offset.is_equal_approx(near_before_pause),
			str(dims) + " arms lowered/pose missing freezes scenery")
		game.airplane_pose_active = true
		game.finished = true
		game._process(1.0 / 60.0)
		_check(far.scroll_offset.is_equal_approx(before_pause) and
			near.scroll_offset.is_equal_approx(near_before_pause),
			str(dims) + " results freeze scenery")
		game.finished = false
		game.call("_sync_visuals")
		_check((game.get_node("PlaneRig") as Control).size.is_equal_approx(original_plane.size) and
			game._gate_nodes[1].size.x >= original_gate.size.x and
			game.get_node("HUDLayer/HUD") is Control,
			str(dims) + " PlaneRig, 2D gates, and original HUD are preserved")
		# Teachers can compare old/new art using a single Inspector toggle,
		# without deleting the cloud nodes or changing their authored geometry.
		parallax.call("reset_motion")
		parallax.set("parallax_enabled", false)
		game.running = true
		game.airplane_pose_active = true
		game._process(0.08)
		_check(far.scroll_offset.is_equal_approx(start_far) and
			near.scroll_offset.is_equal_approx(start_near),
			str(dims) + " inspector toggle disables parallax without changing game physics")
		parallax.set("parallax_enabled", true)
		game.call("_sync_visuals")
		if capture:
			await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			var path := "user://human_plane_25d_%dx%d.png" % [dims.x, dims.y]
			_check(img.save_png(path) == OK, str(dims) + " graphical preview saved")
			print("PARALLAX_25D_SCREENSHOT ", ProjectSettings.globalize_path(path))
		game.queue_free()
		await process_frame
		await process_frame
	print("HUMAN PLANE 2.5D PARALLAX: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, info: String) -> void:
	checks += 1
	if not ok:
		failures.append(info)
		printerr("2.5D PARALLAX FAIL: ", info)
