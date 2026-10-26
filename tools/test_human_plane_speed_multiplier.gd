extends SceneTree

# Run without camera or database:
# Godot --headless --path . --script res://tools/test_human_plane_speed_multiplier.gd
const GAME := preload("res://ui/minigames/human_plane.tscn")
const VIEW := preload("res://ui/minigames/human_plane_3d_view.tscn")
const MODEL_PATH := "res://Components/Gameplay/Human Plane/3D/red-plane/2b69a53022ec45b396ce8015291cc9ea.fbx"
const PBR_PATH := "res://Components/Gameplay/Human Plane/3D/red-plane/red_plane_pbr.tres"
const MODES := ["Seconds", "Lives"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const SPEEDS := {"Easy": 0.20, "Normal": 0.27, "Hard": 0.34}

var checked := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var model := load(MODEL_PATH) as PackedScene
	_expect(model != null, "original red-plane FBX imported as PackedScene")
	if model:
		var aircraft := model.instantiate() as Node3D
		root.add_child(aircraft)
		var mesh_count := _count_meshes(aircraft)
		_expect(mesh_count == 22, "all 22 original red FBX meshes imported intact")
		aircraft.queue_free()
		await process_frame
	var pbr := load(PBR_PATH) as StandardMaterial3D
	_expect(pbr != null and pbr.albedo_texture != null and pbr.normal_texture != null
		and pbr.metallic_texture != null and pbr.roughness_texture != null
		and pbr.ao_texture != null and pbr.ao_enabled and pbr.normal_enabled,
		"RED PLANE material references all five original source PBR maps")
	for mode in MODES:
		for difficulty in DIFFICULTIES:
			await _check_round(mode, difficulty)
	if "--capture" in OS.get_cmdline_user_args():
		await _capture_real_3d()
	print("HUMAN PLANE SPEED BOOST: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checked, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _capture_real_3d() -> void:
	if DisplayServer.get_name() == "headless":
		_expect(false, "GPU capture must use OpenGL window, not headless")
		return
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(dimensions)
		root.content_scale_size = dimensions
		root.size = dimensions
		var scene := VIEW.instantiate() as SubViewportContainer
		root.add_child(scene)
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var red := scene.get_node("Viewport3D/FlightWorld/PlayerRig/RedPlane") as Node3D
		var parts := _first_meshes(red, 80)
		_expect(parts.size() == 22, "full3D scene retains all imported FBX submeshes")
		for part in parts:
			_expect(part.skin == null and part.skeleton.is_empty(),
				"FBX mesh has no corrupt bone-binding: " + part.name)
			for surface in range(part.mesh.get_surface_count()):
				var material := part.get_active_material(surface) as StandardMaterial3D
				_expect(material != null and material.albedo_texture != null
					and material.metallic_texture != null and material.roughness_texture != null
					and material.ao_enabled and material.ao_texture != null,
					"FBX surface has full PBR without replacing original mesh: " + part.name)
		scene.set_speed_multiplier(2.2)
		scene.sync_flight(0.5,
			{"options": ["APPLE", "TEACHER", "DOG"], "valid_indices": [1]},
			0.50, {}, 0.0, false, -1, false, false, false, 0.70, true)
		for _frame in range(8):
			await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		_expect(capture != null and capture.get_size() == dimensions,
			"standalone RED FBX 3D GPU screenshot at %s" % dimensions)
		if capture != null:
			var red_pixels := 0
			for y in range(int(dimensions.y * 0.56), int(dimensions.y * 0.86), 4):
				for x in range(int(dimensions.x * 0.30), int(dimensions.x * 0.70), 4):
					var pixel := capture.get_pixel(x, y)
					if pixel.r > 0.44 and pixel.r > pixel.g * 1.6 and pixel.r > pixel.b * 1.6:
						red_pixels += 1
			_expect(red_pixels >= 22, "real red aircraft is visibly rendered on GPU (%s): %d sampled red pixels" % [dimensions, red_pixels])
			var path := "user://_qa_human_plane_red_plane_3d_%dx%d.png" % [dimensions.x, dimensions.y]
			_expect(capture.save_png(path) == OK,
				"saved standalone 3D screenshot at " + path)
			print("RED PLANE 3D GPU: ", ProjectSettings.globalize_path(path))
		scene.queue_free()
		await process_frame
		await process_frame


func _check_round(mode: String, difficulty: String) -> void:
	var label := "%s/%s" % [mode, difficulty]
	var game := GAME.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The A/B experiment defaults to 2.5D. This suite deliberately exercises
	# the true 3D renderer speed path, leaving the default selection untouched.
	if game.has_method("set_environment_view"):
		game.call("set_environment_view", 1)
	game.set_context({"activity": "Human Plane", "topic": "Noun",
		"game_mode": mode, "difficulty": difficulty, "score": 240})
	await process_frame
	await process_frame
	game.set_process(false)
	var base := float(SPEEDS[difficulty])
	_expect(is_equal_approx(float(game.get("speed_multiplier")), 1.0), label + " starts at x1.0")
	_expect(int(game.get("speed_boost_count")) == 0, label + " no boost until correct")
	var view := game.get_node("WorldView3D") as SubViewportContainer
	_expect(view != null and view.has_method("set_speed_multiplier"), label + " 3D viewer has boost API")
	game.call("_start_wave")
	game.call("_advance_gate_step", 0.1)
	_expect(absf(float(game.get("gate_progress")) - base * 0.1) < 0.0001,
		label + " base gate speed matches difficulty")
	game.call("_start_wave")

	for count in range(1, 7):
		var valid: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
		_expect(not valid.is_empty(), label + " next wave has correct option " + str(count))
		if valid.is_empty():
			break
		_place_at_lane(game, int(valid[0]))
		var old_score := int(game.get("score"))
		game.call("_resolve_at_answer_line")
		var multiplier := 1.0 + float(count) * 0.14
		_expect(is_equal_approx(float(game.get("speed_multiplier")), multiplier),
			label + " cumulative uncapped boost number " + str(count))
		_expect(int(game.get("speed_boost_count")) == count, label + " boost counter persists")
		_expect(int(game.get("score")) == old_score + 100,
			label + " +100 points independently from speed")
		_expect(float(view.get("speed_multiplier")) >= multiplier,
			label + " scenery renderer matches earned speed")
		game.call("_resolve_at_answer_line")
		_expect(is_equal_approx(float(game.get("speed_multiplier")), multiplier),
			label + " idempotent collision awards speed only once")
		game.call("_start_wave")
		game.call("_advance_gate_step", 0.1)
		_expect(absf(float(game.get("gate_progress")) - base * multiplier * 0.1) < 0.0001,
			label + " actual gate movement accelerated after correct answer")
		game.call("_start_wave")

	var earned := float(game.get("speed_multiplier"))
	var points := int(game.get("score"))
	var valid_indices: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
	var wrong := -1
	for i in range(3):
		if i not in valid_indices:
			wrong = i
			break
	_expect(wrong >= 0, label + " test word bank provides invalid answer")
	if wrong >= 0:
		_place_at_lane(game, wrong)
		game.call("_resolve_at_answer_line")
		_expect(int(game.get("score")) == points, label + " wrong answer does not subtract points")
		_expect(float(game.get("speed_multiplier")) == earned,
			label + " wrong answer never reduces accumulated boost")
		_expect(int(game.get("streak")) == 0, label + " streak resets separately from boost")
		game.call("_start_wave")
		game.set("plane_x_norm", -10.0)
		points = int(game.get("score"))
		game.call("_resolve_at_answer_line")
		_expect(int(game.get("score")) == points, label + " missed ring no point deduction")
		_expect(float(game.get("speed_multiplier")) == earned,
			label + " missed ring never reduces boost")
		game.call("_start_wave")
		game.call("_advance_gate_step", 0.1)
		_expect(absf(float(game.get("gate_progress")) - base * earned * 0.1) < 0.0001,
			label + " boosted movement resumes at earned speed after a miss")
	var saved: Dictionary = game.get_context()
	_expect(is_equal_approx(float(saved.get("plane_speed_multiplier", 0.0)), earned),
		label + " pause/results payload preserves current speed")
	_expect(int(saved.get("plane_speed_boosts", -1)) == 6,
		label + " pause/results payload preserves boost counter")
	game.queue_free()
	await process_frame
	await process_frame
	var resumed := GAME.instantiate() as Control
	root.add_child(resumed)
	resumed.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resumed.set_context(saved)
	await process_frame
	await process_frame
	resumed.set_process(false)
	_expect(is_equal_approx(float(resumed.get("speed_multiplier")), earned),
		label + " resumed round retains earned speed despite reset streak")
	_expect(int(resumed.get("speed_boost_count")) == 6,
		label + " resumed round retains independent boost count")
	resumed.queue_free()
	await process_frame
	await process_frame


func _count_meshes(node: Node) -> int:
	var total := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		total += _count_meshes(child)
	return total


func _first_meshes(node: Node, limit: int) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		if result.size() >= limit:
			break
		result.append_array(_first_meshes(child, limit - result.size()))
	return result


func _place_at_lane(game: Control, lane: int) -> void:
	var progress: float = game.call("_progress_for_answer_line")
	var rect: Rect2 = game.call("_gate_visible_rect", lane, progress)
	var left: Control = game.get_node("FlightPaths/PlaneLeftLimit")
	var right: Control = game.get_node("FlightPaths/PlaneRightLimit")
	var plane: Control = game.get_node("PlaneRig")
	var box: Control = game.get_node("PlaneRig/Hitbox")
	var offset := box.get_rect().get_center().x - plane.size.x * 0.5
	var left_x := left.get_rect().get_center().x
	var right_x := right.get_rect().get_center().x
	game.set("plane_x_norm", (rect.get_center().x - offset -
		float(game.get("_plane_authored_offset_x")) - left_x) / (right_x - left_x))


func _expect(ok: bool, description: String) -> void:
	checked += 1
	if not ok:
		failures.append(description)
		printerr("SPEED BOOST FAIL: ", description)
