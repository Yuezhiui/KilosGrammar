extends SceneTree

# Godot 4.7 --headless --path . --script res://tools/test_human_plane_visual_gate_depth.gd
# Also run with OpenGL to save real renderer screenshots at two resolutions.
# Verifies authored scene/gate depth with three-position, wide-arm body motion.
const SCENE := preload("res://ui/minigames/human_plane.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]
const STEP := 1.0 / 60.0

var issues: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dimensions in SIZES:
		for level in DIFFICULTIES:
			for mode in MODES:
				await _exercise(dimensions, level, mode)
	print("HUMAN PLANE DEPTH/GATE/BODY: %s (%d assertions, %d failures)" %
		["PASS" if issues.is_empty() else "FAIL", checks, issues.size()])
	quit(0 if issues.is_empty() else 1)


func _exercise(dimensions: Vector2i, level: String, mode: String) -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(dimensions)
		root.content_scale_size = dimensions
	root.size = dimensions
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"difficulty":level, "topic":"Noun", "game_mode":mode, "activity":"Human Plane"})
	await process_frame
	await process_frame
	game.set_process(false)
	var title := "%s/%s/%s" % [dimensions, level, mode]
	var current := game.get_node("MovingGates") as Control
	var incoming := game.get_node("UpcomingGates") as Control
	var airplane := game.get_node("PlaneRig") as Control
	_check(current.z_index < airplane.z_index, title + " approaching artwork rendered behind plane")
	_check(incoming.z_index < airplane.z_index, title + " horizon artwork rendered behind plane")
	_check(int(game.get("lives")) == 3, title + " three hearts")
	_check(float(game.get("time_remaining")) >= 59.0 if mode == "Seconds"
		else is_zero_approx(float(game.get("time_remaining"))), title + " correct timer mode")
	var config: Dictionary = game.DIFFICULTY_CONFIG[level]
	var speed := float(config["gate_speed"])
	_check(speed <= 0.35, title + " gates approach slowly")
	if level == "Normal":
		_check(speed > float(game.DIFFICULTY_CONFIG["Easy"]["gate_speed"]), title + " normal progression")
	if level == "Hard":
		_check(speed > float(game.DIFFICULTY_CONFIG["Normal"]["gate_speed"]), title + " hard progression")
	# Students calibrate three actual positions as in Catch the Word.
	# Both arms wide ENABLES movement; only measured BODY x selects a lane.
	game.call("set_airplane_pose_active", true)
	game.call("set_body_x", 0.40)
	var x_before := float(game.get("plane_x_norm"))
	for _i in range(30):
		game.call("_update_plane_motion", STEP)
	var x_right := float(game.get("plane_x_norm"))
	_check(x_right > x_before + 0.07 and x_right < x_before + 0.27,
		title + " calibrated right body movement is proportional and smooth")
	game.call("set_body_x", 0.0)
	for _i in range(48):
		game.call("_update_plane_motion", STEP)
	var x_neutral := float(game.get("plane_x_norm"))
	_check(absf(x_neutral - 0.5) < absf(x_right - 0.5) * 0.1,
		title + " stepping back to measured CENTER recenters airplane")
	for _i in range(15):
		game.call("_update_plane_motion", STEP)
	_check(absf(float(game.get("plane_x_norm")) - 0.5) < 0.012,
		title + " calibrated CENTER position keeps middle flight path")
	game.call("set_body_x", -0.40)
	for _i in range(30):
		game.call("_update_plane_motion", STEP)
	_check(float(game.get("plane_x_norm")) < x_neutral - 0.04,
		title + " stepping left sends airplane left")
	game.call("set_airplane_pose_active", false)
	var lost_x := float(game.get("plane_x_norm"))
	for _i in range(30):
		game.call("_update_plane_motion", STEP)
	_check(is_equal_approx(float(game.get("plane_x_norm")), lost_x),
		title + " lowering arms freezes instantly")
	game.call("set_airplane_pose_active", true)
	# Position, collision, and painting must agree after motion easing.
	for p in [0.1, 0.33, 0.58, 0.9]:
		game.set("gate_progress", p)
		game.call("_sync_visuals")
		var gate: Control = (game.get("_gate_nodes") as Array)[1]
		var predicted: Rect2 = game.call("_gate_rect", 1, p)
		_check(gate.get_rect().is_equal_approx(predicted),
			title + " gate rectangle matches collision at %.2f" % p)
	_check(float(game.call("_gate_y", 0.3)) < float(game.call("_gate_y", 0.6)),
		title + " eased path still approaches monotonically")
	var answer_p := float(game.call("_progress_for_answer_line"))
	_check(answer_p > 0.0 and answer_p < 1.0 and
		absf(float(game.call("_gate_y", answer_p)) - float(game.call("_answer_line_y"))) < 1.0,
		title + " easing keeps answer collision aligned to painted gate")
	_check(float(game.call("_active_gate_opacity", answer_p)) > 0.95,
		title + " question remains readable through scoring line")
	_check(float(game.call("_active_gate_opacity", minf(answer_p + 0.19, 1.0))) < 0.04,
		title + " departing gates fade before covering airplane")
	_check(float(game.call("_distant_gate_opacity", 0.0)) >= 0.65 and
		float(game.call("_distant_gate_opacity", 0.0)) < 0.75 and
		float(game.call("_distant_gate_opacity", 0.30)) >= 0.99,
		title + " distance fades in incoming gates")
	# Restore the active motion and drive the real two-wave handoff.
	game.set("gate_progress", 0.0)
	game.call("_sync_visuals")
	var first_words: Dictionary = (game.get("round_data") as Dictionary).duplicate(true)
	var first_gate: Control = (game.get("_gate_nodes") as Array)[1]
	var before_gate_center := first_gate.get_rect().get_center().y
	game.call("_update_gate_wave", 0.08 / speed)
	game.call("_sync_visuals")
	_check(first_gate.get_rect().get_center().y > before_gate_center,
		title + " gates continue moving continuously")
	var prefetch_step := (float(game.GATE_PREFETCH_AT) + 0.04 - float(game.get("gate_progress"))) / speed
	game.call("_update_gate_wave", prefetch_step)
	game.call("_sync_visuals")
	_check(not (game.get("next_round_data") as Dictionary).is_empty(),
		title + " next wave preloads before current passes")
	_check(((game.get("_upcoming_gate_nodes") as Array)[1] as Control).visible,
		title + " authored horizon trio visible")
	var incoming_gate: Control = (game.get("_upcoming_gate_nodes") as Array)[1]
	_check(incoming_gate.get_rect().size.y < first_gate.get_rect().size.y,
		title + " upcoming trio smaller than approaching answers")
	if DisplayServer.get_name() != "headless" and level == "Normal" and mode == "Seconds":
		await _capture(game, dimensions, "approach")
	var approach_data := (game.get("next_round_data") as Dictionary).duplicate(true)
	var completed := false
	var incoming_pos := Vector2.ZERO
	for _step in range(450):
		game.call("_update_gate_wave", STEP)
		game.call("_sync_visuals")
		if int(game.get("waves_completed")) >= 1:
			completed = true
			incoming_pos = incoming_gate.position
			break
	_check(completed, title + " passes current wave and hands off")
	if completed and not bool(game.get("finished")):
		_check(int(game.get("attempts")) == 1, title + " scores only once")
		_check((game.get("round_data") as Dictionary).get("options", []) ==
			approach_data.get("options", []), title + " prefetched unique options promoted")
		_check((game.get("round_data") as Dictionary).get("options", []) !=
			first_words.get("options", []), title + " different incoming word set")
		var on_promoted_alpha := incoming_gate.modulate.a
		game.call("_update_gate_wave", STEP)
		game.call("_sync_visuals")
		_check(incoming_gate.position.distance_to(incoming_pos) < dimensions.y * 0.03,
			title + " handoff has no image position pop")
		_check(absf(incoming_gate.modulate.a - on_promoted_alpha) < 0.08,
			title + " handoff has no alpha pop")
		_check(float(game.get("gate_progress")) < answer_p,
			title + " student has time to steer before next answer")
		if DisplayServer.get_name() != "headless" and level == "Normal" and mode == "Seconds":
			await _capture(game, dimensions, "handoff")
	elif completed:
		_check(false, title + " game unexpectedly finished during first handoff")
	game.queue_free()
	await process_frame
	await process_frame


func _capture(game: Control, dimensions: Vector2i, phase: String) -> void:
	game.call("_sync_visuals")
	for _i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var file := "user://human_plane_depth_%dx%d_%s.png" % [dimensions.x, dimensions.y, phase]
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(file))
	_check(error == OK, "renderer screenshot created: " + file)
	print("HUMAN PLANE SCREENSHOT: " + ProjectSettings.globalize_path(file))


func _check(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		issues.append(reason)
		printerr("HUMAN PLANE DEPTH FAIL: " + reason)
