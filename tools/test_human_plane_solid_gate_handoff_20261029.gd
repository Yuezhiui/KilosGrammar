extends SceneTree

# Repro: 2D Human Plane gates fade/shrink into overlapping ghost trios at a
# wave boundary. Verifies the actual editor-authored PNGs and quiz lifecycle.
# No camera, YOLO, PostgreSQL, writes, or synthetic production pose packets.
const GAME := preload("res://ui/minigames/human_plane/human_plane.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const LANES := ["Left", "Center", "Right"]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dimensions in SIZES:
		await _check_viewport(dimensions)
	print("HUMAN PLANE OPAQUE GATE/HANDOFF: %s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check_viewport(dimensions: Vector2i) -> void:
	root.size = dimensions
	root.content_scale_size = Vector2i(1280, 720)
	var tag := str(dimensions)
	var game := GAME.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"topic": "Noun", "difficulty": "Normal", "game_mode": "Seconds",
		"camera_live": false, "keyboard_mode": false})
	await process_frame
	await process_frame
	game.set_process(false)
	var current := game.get_node("MovingGates") as Control
	var upcoming := game.get_node("UpcomingGates") as Control
	var plane := game.get_node("PlaneRig") as Control
	var original_plane_y := plane.position.y
	var original_time: float = float(game.time_remaining)
	_check(game.started and game.running and game.lives == 3 and game.time_remaining > 59.0,
		tag + " starts with unchanged 60 seconds and three hearts")
	_check(game.get_node_or_null("WorldView3D") == null and
		game.get_node("FlightBackground") is TextureRect,
		tag + " uses editable native 2D gates and original background")
	for group in [current, upcoming]:
		for lane in LANES:
			var gate := group.get_node("Gate" + lane) as Control
			var art := gate.get_node("GateArtwork") as TextureRect
			var label := gate.get_node("WordLabel") as Label
			_check(art.texture != null and label != null and
				not art.texture.resource_path.is_empty(),
				tag + " authored native PNG and word label " + group.name + "/" + lane)
	for progress in [0.0, 0.25, 0.6, 0.9, 1.0]:
		var bounds: Array[Rect2] = []
		for lane in range(3):
			var rect: Rect2 = game._gate_visible_rect(lane, progress)
			bounds.append(rect)
			_check(rect.has_area() and rect.size.x >= 100.0 and rect.size.y >= 100.0,
				tag + " lane %d legible dimensions throughout progress %.2f" % [lane, progress])
		for lane in range(2):
			_check(bounds[lane].end.x < bounds[lane+1].position.x - 6.0,
				tag + " distant/current gates don't cross or overlap lane %d at %.2f" %
				[lane, progress])
	var starting_rect: Rect2 = game._gate_visible_rect(1, 0.0)
	var near_rect: Rect2 = game._gate_visible_rect(1, 1.0)
	_check(near_rect.size.x >= starting_rect.size.x and near_rect.size.y >= starting_rect.size.y,
		tag + " approaching answer gate never shrinks")
	_check(current.visible and not upcoming.visible, tag + " begins with one visible set")
	var initial: Array = (game.round_data.get("options", []) as Array).duplicate()
	var correct_lane := int(game.round_data.get("valid_indices", [0])[0])
	var selectable := false
	for step in range(401):
		game.plane_x_norm = float(step) / 400.0
		if int(game._lane_hit_at_answer_line()) == correct_lane:
			selectable = true
			break
	_check(selectable, tag + " real answer-line collision remains selectable for correct gate")
	var speed := float(game.DIFFICULTY_CONFIG[game.difficulty]["gate_speed"])
	game._update_gate_wave((game.GATE_PREFETCH_AT + 0.025) / speed)
	game._sync_visuals()
	var prefetched := (game.next_round_data.get("options", []) as Array).duplicate()
	_check(prefetched.size() == 3 and initial.size() == 3,
		tag + " prefetch keeps three queued answers")
	for word in prefetched:
		_check(word not in initial, tag + " prefetch reserves unique answer " + str(word))
	_check(current.visible and not upcoming.visible,
		tag + " upcoming words prefetch without visible second trio or ghost")
	_check(_opaque_trio(game._gate_nodes) and current.modulate.a >= 0.999,
		tag + " active gate PNGs and word plaques stay fully opaque while approaching")
	var line_p: float = game._progress_for_answer_line()
	game.gate_progress = minf(0.99, line_p + 0.08)
	game._sync_visuals()
	_check(_opaque_trio(game._gate_nodes),
		tag + " current gates do not dissolve immediately after scoring line")
	_check(not upcoming.visible,
		tag + " prefetched gates remain hidden even after score crossing")

	# The same next trio becomes the active scene without a third ghost copy.
	var old_group := game._gate_nodes[0].get_parent() as Control
	var queued_group := game._upcoming_gate_nodes[0].get_parent() as Control
	var queued_gate_id: int = (game._upcoming_gate_nodes[1] as Control).get_instance_id()
	if selectable and game.gate_resolved:
		_check(game.selected_lane == correct_lane and game.selected_was_correct and
			game.score == 100 and game.lives == 3,
			tag + " real passage scores the correct gate")
		game._resolve_at_answer_line()
		_check(game.score == 100 and game.attempts == 1,
			tag + " duplicate answer-line event has no scoring effect")
	game.gate_progress = 0.76
	game._update_gate_wave((1.02 - game.gate_progress) / speed)
	game._sync_visuals()
	_check(game.waves_completed == 1 and game.attempts == 1,
		tag + " passage resolves scoring exactly once")
	_check(game.score == 100 and game.lives == 3,
		tag + " correct portal awards unchanged 100 points and preserves hearts")
	_check(game.round_data.get("options", []) == prefetched,
		tag + " queued prefetch is promoted as next question")
	_check(game._gate_nodes[1].get_instance_id() == queued_gate_id,
		tag + " queued inspector-authored gate reused without duplicate creation")
	_check(game._gate_nodes[0].get_parent() == queued_group and
		game._upcoming_gate_nodes[0].get_parent() == old_group,
		tag + " gate scene groups swap identities exactly once")
	_check(queued_group.visible and not old_group.visible and
		_opaque_trio(game._gate_nodes),
		tag + " old trio hidden atomically; newly promoted trio fully opaque")
	_check(game.time_remaining >= original_time - 0.02 and game.lives == 3 and
		is_equal_approx(plane.position.y, original_plane_y),
		tag + " direct gate wave check leaves HUD countdown and airplane intact")
	for extra in range(1, 5):
		# Repeat both buffer identities at increasing earned speeds to catch
		# a stale retired gate accidentally reappearing after reuse.
		var previous_group := game._gate_nodes[0].get_parent() as Control
		var next_group := game._upcoming_gate_nodes[0].get_parent() as Control
		var previous_attempts: int = game.attempts
		var previous_score: int = game.score
		var correct: int = int(game.round_data.get("valid_indices", [0])[0])
		var reached := false
		for sample in range(401):
			game.plane_x_norm = float(sample) / 400.0
			if int(game._lane_hit_at_answer_line()) == correct:
				reached = true
				break
		_check(reached, tag + " wave %d authoritative answer remains reachable" % extra)
		if not reached:
			break
		var flight_speed: float = float(game.DIFFICULTY_CONFIG[game.difficulty]["gate_speed"]) * float(game.speed_multiplier)
		game._update_gate_wave((1.02 - game.gate_progress) / flight_speed)
		game._sync_visuals()
		_check(game.attempts == previous_attempts + 1 and game.score == previous_score + 100,
			tag + " wave %d resolves once and awards the right answer" % extra)
		_check(game.waves_completed == extra + 1 and game.lives == 3,
			tag + " wave %d keeps correct wave count and hearts" % extra)
		_check(not previous_group.visible and next_group.visible and
			game._gate_nodes[0].get_parent() == next_group and
			_opaque_trio(game._gate_nodes),
			tag + " wave %d swaps buffered trio exactly once, without ghost" % extra)
		_check(game._upcoming_gate_nodes[0].get_parent() == previous_group and
			not game._upcoming_gate_nodes[0].get_parent().visible,
			tag + " wave %d old trio remains hidden in standby" % extra)
		_check((game.used_round_words as Dictionary).size() >= (extra + 2) * 3,
			tag + " wave %d vocabulary still prevents repeated answers" % extra)
	game.queue_free()
	await process_frame
	await process_frame


func _opaque_trio(nodes: Array[Control]) -> bool:
	for gate in nodes:
		if gate.modulate.a < 0.999 or not gate.visible or not gate.get_node("WordLabel").visible:
			return false
	return true


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("OPAQUE GATE FAIL: ", message)
