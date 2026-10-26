extends SceneTree

# Offline score, input, lifecycle regression for the 3D Human Plane conversion.
# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_3d_interactions.gd
# Uses synthetic input only. Never starts PoseService, cameras, gameplay wrapper or DB.
const SCENE := preload("res://ui/minigames/human_plane.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const POINTS := 100

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dimensions in SIZES:
		await _exercise_game(dimensions)
	print("HUMAN PLANE 3D INTERACTIONS: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _exercise_game(dimensions: Vector2i) -> void:
	root.content_scale_size = dimensions
	root.size = dimensions
	var label := "%dx%d" % [dimensions.x, dimensions.y]
	var game := SCENE.instantiate() as Control
	_check(game != null, label + " creates routable Human Plane scene")
	if game == null:
		return
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {"activity": "Human Plane", "topic": "Noun",
		"difficulty": "Normal", "game_mode": "Seconds", "camera_live": false})
	# Full 3D is the only remaining playable renderer, with no 2.5D selector.
	await process_frame
	await process_frame
	game.set_process(false)
	_check(bool(game.get("started")) and bool(game.get("running")), label + " running offline")
	_check(int(game.get("lives")) == 3 and float(game.get("time_remaining")) > 59.0,
		label + " three hearts and 60-second timer preserved")
	_check(game.has_method("_lane_hit_at_answer_line"), label + " preserves real three-lane hit test")
	_check(game.has_method("_resolve_at_answer_line"), label + " preserves authoritative score resolver")
	var world := game.get_node_or_null("WorldView3D/Viewport3D/FlightWorld") as Node3D
	var model := world.get_node_or_null("PlayerRig") as Node3D if world != null else null
	var front_ring := world.get_node_or_null("CurrentRings/GateCenter") as Node3D if world != null else null
	var landscape := world.get_node_or_null("CloudFlight/CloudProps/Cloud01") as Node3D if world != null else null
	var voice := game.get_node_or_null("HumanPlaneVoicePlayer") as AudioStreamPlayer
	_check(voice != null, label + " reuses Catch voice with one persistent AudioStreamPlayer")
	if voice != null:
		_check(voice.bus == ("KilosSFX" if AudioServer.get_bus_index("KilosSFX") >= 0 else "Master"),
			label + " voice uses the game's normal effects bus")
	_check(model != null and front_ring != null and landscape != null,
		label + " 3D plane, forward rings, and cloud scenery are present")
	if front_ring != null:
		var initial_ring_z := front_ring.position.z
		game.call("_update_gate_wave", 0.5)
		game.call("_sync_visuals")
		_check(front_ring.position.z > initial_ring_z + 0.1,
			label + " real 3D torus advances toward player with the scoring clock")
		game.call("_start_wave")

	# Resolve a correct gate using its actual collision range rather than guessing
	# pixel coordinates; this catches geometry that disagrees with scoring.
	if game.has_method("_lane_hit_at_answer_line") and game.has_method("_resolve_at_answer_line"):
		game.call("_start_wave")
		var round: Dictionary = game.get("round_data")
		var valid: Array = round.get("valid_indices", [])
		_check((round.get("options", []) as Array).size() == 3 and not valid.is_empty(),
			label + " 3D gate trio has three answers with a correct lane")
		if not valid.is_empty():
			var correct_lane := int(valid[0])
			var found_correct := _select_lane(game, correct_lane)
			_check(found_correct, label + " 3D correct ring has reachable collision interval")
			if found_correct:
				var previous_score := int(game.get("score"))
				game.call("_resolve_at_answer_line")
				_check(_has_voice_cue(voice, game.VOICE_CORRECT),
					label + " correct gate plays a positive Catch the Word voice recording")
				_check(bool(game.get("selected_was_correct")) and int(game.get("selected_lane")) == correct_lane,
					label + " chosen 3D ring is the scored answer")
				_check(int(game.get("score")) == previous_score + POINTS,
					label + " correct gate grants exactly 100 points")
				_check(int(game.get("attempts")) == 1 and int(game.get("correct_count")) == 1,
					label + " score tracks one correct attempt")
				game.call("_resolve_at_answer_line")
				_check(int(game.get("score")) == previous_score + POINTS and int(game.get("attempts")) == 1,
					label + " duplicate gate resolution awards no extra points")
				var payload: Dictionary = game.call("get_context")
				_check(int(payload.get("score", -1)) == int(game.get("score")) and
					int(payload.get("correct", -1)) == 1,
					label + " gameplay results export updated score and correct count")
		game.call("_start_wave")
		round = game.get("round_data")
		valid = round.get("valid_indices", [])
		var invalid_lane := -1
		for lane in range(3):
			if lane not in valid:
				invalid_lane = lane
				break
		_check(invalid_lane >= 0, label + " presents at least one wrong answer")
		if invalid_lane >= 0 and _select_lane(game, invalid_lane):
			var before := int(game.get("score"))
			var lives_before := int(game.get("lives"))
			game.call("_resolve_at_answer_line")
			_check(_has_voice_cue(voice, game.VOICE_WRONG),
				label + " wrong gate plays a negative Catch voice recording")
			_check(not bool(game.get("selected_was_correct")) and int(game.get("selected_lane")) == invalid_lane,
				label + " wrong ring collision is recorded")
			_check(int(game.get("score")) == before and
				int(game.get("lives")) == lives_before - 1,
				label + " wrong ring keeps points while using one heart")
			game.call("_resolve_at_answer_line")
			_check(int(game.get("score")) == before and int(game.get("lives")) == lives_before - 1,
				label + " duplicate wrong ring cannot charge points/life again")
		game.call("_start_wave")
		game.set("plane_x_norm", -10.0)
		_check(int(game.call("_lane_hit_at_answer_line")) == -1,
			label + " offscreen airplane tests an actual missed gate")
		var before_miss := int(game.get("score"))
		var lives_before_miss := int(game.get("lives"))
		game.call("_resolve_at_answer_line")
		_check(_has_voice_cue(voice, [game.VOICE_MISSED]),
			label + " missed gate uses the dedicated Catch voice cue")
		_check(int(game.get("score")) == before_miss and
			int(game.get("lives")) == lives_before_miss - 1,
			label + " missed gates preserve points and consume one heart")
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == before_miss and
			int(game.get("lives")) == lives_before_miss - 1,
			label + " duplicate missed gate does not charge points/life again")

	# Offline direct game input checks a fresh measured direction, with no
	# camera calibration or fake enrollment. Real lock/pose eligibility belongs
	# to PoseService and the gameplay wrapper, not this scene-level test.
	var pose_methods := game.has_method("set_body_x") and game.has_method("set_airplane_pose_active")
	_check(pose_methods, label + " PoseService public steering contract survives 3D conversion")
	if pose_methods:
		game.set("plane_x_norm", 0.5)
		game.set("target_x_norm", 0.5)
		game.call("set_airplane_pose_active", false)
		game.call("set_body_x", 1.0)
		game.call("_update_plane_motion", 0.2)
		_check(is_equal_approx(float(game.get("plane_x_norm")), 0.5),
			label + " tracking without airplane pose cannot steer")
		game.call("set_airplane_pose_active", true)
		game.call("set_body_x", 1.0)
		for _step in range(45):
			game.call("_update_plane_motion", 1.0 / 60.0)
		var moved := float(game.get("plane_x_norm"))
		_check(moved > 0.85, label + " live pose can move the 3D player into right lane")
		game.call("_sync_visuals")
		if model != null:
			_check(model.position.x > 1.0 and model.position.x <= 12.0,
				label + " rendered 3D plane follows calibrated rightward arm-roll target")
		game.call("set_airplane_pose_active", false)
		game.call("set_body_x", -1.0)
		game.call("_update_plane_motion", 1.0)
		_check(is_equal_approx(float(game.get("plane_x_norm")), moved),
			label + " lost tracking freezes last player position")
		game.call("set_airplane_pose_active", true)
		game.call("_update_plane_motion", 1.0 / 60.0)
		_check(is_equal_approx(float(game.get("plane_x_norm")), moved),
				label + " restored lock waits for fresh steering sample")
		game.call("set_airplane_pose_active", false)

	# Keyboard steering is an explicit debug-only opt-in. Normal camera gameplay
		# must never allow a stray D key to bypass the tracked student requirement.
	game.set("plane_x_norm", 0.5)
	game.set("target_x_norm", 0.5)
	game.call("_resume")
	var key := InputEventKey.new()
	key.keycode = KEY_D
	key.physical_keycode = KEY_D
	key.pressed = true
	if game.has_method("_unhandled_key_input"):
		game.call("_unhandled_key_input", key)
	game.call("_process", 1.0 / 60.0)
	_check(is_equal_approx(float(game.get("plane_x_norm")), 0.5),
		label + " keyboard cannot control live airplane by default")
	var debug_property := false
	for property in game.get_property_list():
		if String(property.get("name", "")) == "allow_keyboard_debug":
			debug_property = true
	_check(debug_property, label + " exports editor-toggleable keyboard debug fallback")
	if debug_property:
		game.set("allow_keyboard_debug", true)
	# Try the real key event and regular UI navigation action together, allowing
	# an editor to exercise the fallback with either mapped control.
	Input.action_press("ui_right")
	if game.has_method("_unhandled_key_input"):
		game.call("_unhandled_key_input", key)
	for _frame in range(24):
		game.call("_process", 1.0 / 60.0)
	Input.action_release("ui_right")
	key.pressed = false
	if game.has_method("_unhandled_key_input"):
		game.call("_unhandled_key_input", key)
	_check(float(game.get("plane_x_norm")) > 0.54,
		label + " explicitly enabled keyboard debug steers right without a camera")

	var last_score := int(game.get("score"))
	var last_progress := float(game.get("gate_progress"))
	var old_x := float(game.get("plane_x_norm"))
	game.call("_pause")
	if voice != null:
		_check(voice.stream == null and not voice.playing,
			label + " pause stops active voice playback and releases its stream")
	game.call("_process", 0.5)
	var scenery_z := landscape.position.z if landscape != null else 0.0
	for _i in range(6):
		await process_frame
	if landscape != null:
		_check(absf(landscape.position.z - scenery_z) < 0.0001,
			label + " 3D landscape halts with paused gameplay")
	_check(int(game.get("score")) == last_score and
		is_equal_approx(float(game.get("gate_progress")), last_progress) and
		is_equal_approx(float(game.get("plane_x_norm")), old_x),
		label + " 3D world, score and player freeze when paused")
	game.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(game), label + " player, gates and input release cleanly on exit")
	_check(not is_instance_valid(voice), label + " voice player is freed with game scene")


func _has_voice_cue(player: AudioStreamPlayer, allowed_names: Array) -> bool:
	if player == null or player.stream == null:
		return false
	var resource_path := String(player.stream.resource_path)
	return resource_path.begins_with("res://assets/audio/catch_voice/") and resource_path.get_file() in allowed_names


func _select_lane(game: Control, lane: int) -> bool:
	for sample in range(301):
		game.set("plane_x_norm", float(sample) / 300.0)
		if int(game.call("_lane_hit_at_answer_line")) == lane:
			return true
	return false


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("HUMAN PLANE 3D INTERACTIONS FAIL: ", description)
