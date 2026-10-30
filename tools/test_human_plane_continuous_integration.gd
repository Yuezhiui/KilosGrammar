extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_continuous_integration.gd
# Integration coverage for continuous, preloaded Human Plane gate trios.
# Intentionally uses scene nodes and existing game methods, never a camera.
const PLANE_SCENE := preload("res://ui/minigames/human_plane/human_plane.tscn")
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]
const STEP := 0.025
const MAX_STEPS := 520

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for mode in MODES:
		for difficulty in DIFFICULTIES:
			await _test_continuous_round(mode, difficulty, Vector2i(1280, 720))
	# Check that the editor-authored gate paths and overlap work in a larger viewport.
	await _test_continuous_round("Seconds", "Normal", Vector2i(1920, 1080))
	if failures.is_empty():
		print("PASS continuous Human Plane integration: %d checks, preloaded gate trios, scoring, no-repeat words, pause, 60s/3 hearts, pose steering (1280/1920)" % assertions)
		quit(0)
	else:
		for message in failures:
			printerr("FAIL continuous Human Plane integration: " + message)
		printerr("%d integration assertions; %d failures" % [assertions, failures.size()])
		quit(1)


func _new_game(mode: String, difficulty: String, resolution: Vector2i) -> Control:
	root.size = resolution
	var game := PLANE_SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Avoid relying on the OS webcam, PoseService, or random live inputs.
	game.call("set_context", {
		"activity": "Human Plane",
		"game_mode": mode,
		"game_style": "Noun",
		"topic": "Noun",
		"difficulty": difficulty,
		"guided_tutorial": false,
		"start_countdown": false
	})
	return game


func _test_continuous_round(mode: String, difficulty: String, resolution: Vector2i) -> void:
	var game := _new_game(mode, difficulty, resolution)
	await process_frame
	await process_frame
	game.set_process(false)
	var label := "%s/%s/%dx%d" % [mode, difficulty, resolution.x, resolution.y]
	_check(bool(game.get("started")) and bool(game.get("running")), label + " round starts")
	_check(int(game.get("lives")) == 3, label + " exactly three initial hearts")
	var seconds_mode := mode == "Seconds"
	var timer := float(game.get("time_remaining"))
	_check(timer > 59.0 and timer <= 60.0 if seconds_mode else is_zero_approx(timer), label + " seconds=60 / untimed lives")
	var initial_round: Dictionary = game.get("round_data")
	_check(initial_round.get("options", []).size() == 3, label + " first valid trio")
	if initial_round.get("options", []).size() != 3:
		await _dispose(game)
		return
	var current_words := _word_set(initial_round)
	_check(current_words.size() == 3, label + " unique words within first wave")
	var gate_nodes := _gate_controls(game)
	_check(gate_nodes.size() == 6, label + " six separately authored gate controls (two trios)")
	if gate_nodes.size() != 6:
		await _dispose(game)
		return

	# Physical pose must be required for horizontal steering. The camera bridge
	# calls set_airplane_pose_active(false) on arms-lowered or lost-tracking frames.
	_test_pose_steering(game, label)
	# The collision authority is now the physical airplane through an actual
	# 3D TorusMesh hole. Re-arm a synthetic, fresh both-arms pose after checking
	# the deliberate lost-tracking freeze above, before expecting real points.
	game.call("set_airplane_pose_active", true)
	var current_trio: Array[Control] = []
	var next_trio: Array[Control] = []
	for node in gate_nodes:
		if node.get_parent().name == "MovingGates":
			current_trio.append(node)
		else:
			next_trio.append(node)
	_check(current_trio.size() == 3 and next_trio.size() == 3, label + " original trio and independent next trio")
	if current_trio.size() != 3 or next_trio.size() != 3:
		await _dispose(game)
		return

	# Drive the scene deterministically via a fixed delta. The older
	# single-trio implementation leaves this entire pre-crossing view empty.
	# The current approved hybrid renders BOTH depth-separated gate trios
	# at full opacity. Require actual readable labels and separated projected
	# rings; merely lowering alpha could conceal a genuine overlap.
	var readable_preview_seen := false
	var next_seen_before_handoff := false
	var resolved := false
	var pre_handoff_next_positions: Dictionary = {}
	var handoff_occurred := false
	var shown_blank := false
	var caught_early := false
	var last_waves := int(game.get("waves_completed"))
	var attempts_on_first := int(game.get("attempts"))
	var hit_lane := int((initial_round["valid_indices"] as Array)[0])
	for tick in range(MAX_STEPS):
		# Align the real plane hitbox with the correct image gate at its answer line.
		if not caught_early and float(game.get("gate_progress")) < float(game.call("_progress_for_answer_line")):
			_aim_plane_at_lane(game, hit_lane)
			# Confirm the whole physical aircraft clears the real torus opening.
			_check(int((game.get_node("HybridFlight3D") as Node2D).call("physical_lane_at_answer_line")) == hit_lane,
				label + " real airplane clears correct 3D portal at first crossing")
			caught_early = true
		game.call("_update_gate_wave", STEP)
		game.call("_sync_visuals")
		var visible_now := _visible_gates(gate_nodes)
		var showing_next := _visible_gates(next_trio)
		if visible_now.is_empty() and not bool(game.get("finished")):
			shown_blank = true
		if int(game.get("waves_completed")) == last_waves and not showing_next.is_empty():
			next_seen_before_handoff = true
			readable_preview_seen = readable_preview_seen or _separated_readable_preview(game)
		if int(game.get("attempts")) > attempts_on_first:
			resolved = true
			# Resolve collisions are idempotent even while next gates are already visible.
			var before_attempts := int(game.get("attempts"))
			var before_score := int(game.get("score"))
			game.call("_resolve_at_answer_line")
			game.call("_resolve_at_answer_line")
			_check(int(game.get("attempts")) == before_attempts and int(game.get("score")) == before_score, label + " resolved gate cannot score again")
			attempts_on_first = 999999
		if int(game.get("waves_completed")) > last_waves:
			handoff_occurred = true
			for node in next_trio:
				pre_handoff_next_positions[node.get_instance_id()] = node.global_position
			# Full field should keep an incoming trio visible during handoff.
			_check(_visible_gates(gate_nodes).size() >= 3, label + " incoming gates remain present on wave handoff")
			break
		if bool(game.get("finished")):
			break
	_check(resolved, label + " first trio reaches the answer plane")
	_check(next_seen_before_handoff, label + " preloaded gate set is visible before previous wave completes")
	_check(readable_preview_seen, label + " incoming fully opaque trio is legible and depth-separated before handoff")
	_check(handoff_occurred, label + " first wave finishes without waiting for another spawn")
	_check(not shown_blank, label + " never renders a blank gate corridor")
	_check(int(game.get("attempts")) == 1, label + " one scored attempt per completed gate wave")
	_check(int(game.get("waves_completed")) == 1, label + " one completed gate wave after handoff")
	_check(int(game.get("correct_count")) == 1, label + " correct answer credited exactly once")
	_check(not bool(game.get("finished")), label + " still running after first handoff")

	# Advance one short frame after handoff. At least one of the same prefetched
	# controls must continue forward, without teleporting to a new spawn Y.
	if handoff_occurred:
		game.call("_update_gate_wave", STEP)
		game.call("_sync_visuals")
		var continuing := 0
		for node in next_trio:
			if node.visible and pre_handoff_next_positions.has(node.get_instance_id()):
				continuing += 1
				var previous: Vector2 = pre_handoff_next_positions[node.get_instance_id()]
				var displacement := node.global_position.distance_to(previous)
				_check(displacement < game.size.y * 0.15, label + " next gate advances without a teleport")
		_check(continuing == 3, label + " three prefetched gate instances remain visible after handoff")
		var next_round: Dictionary = game.get("round_data")
		var new_words := _word_set(next_round)
		_check(new_words.size() == 3 and new_words != current_words, label + " next question is already assigned")
		var has_repeat := false
		for word in new_words:
			if current_words.has(word):
				has_repeat = true
		_check(not has_repeat, label + " no duplicate option words across the first two waves")
		var used_words: Dictionary = game.get("used_round_words")
		_check(used_words.size() >= 6, label + " words from both waves are reserved")

	# A paused scene freezes BOTH trios, countdown and player motion. Resume
	# must pick up from the same in-flight state instead of resetting the gates.
	var before_progress := float(game.get("gate_progress"))
	var before_time := float(game.get("time_remaining"))
	var before_positions := _snapshot_positions(gate_nodes)
	game.call("_pause")
	game.call("_process", 3.0)
	_check(is_equal_approx(float(game.get("gate_progress")), before_progress), label + " pause freezes gate progress")
	_check(is_equal_approx(float(game.get("time_remaining")), before_time), label + " pause freezes 60-second timer")
	_check(_positions_unchanged(gate_nodes, before_positions), label + " pause freezes both gate trios")
	game.call("_resume")
	game.call("_process", 0.05)
	# A real resume clears the old camera/arm observation. This isolated
	# camera-free test must explicitly supply its next trusted BOTH-ARMS pose
	# before simulating correct physical torus crossings in later waves.
	game.call("set_airplane_pose_active", true)
	_check(float(game.get("gate_progress")) > before_progress or int(game.get("waves_completed")) > 1, label + " resume continues forward flight")
	if seconds_mode:
		_check(float(game.get("time_remaining")) < before_time, label + " resume continues remaining seconds")
	else:
		_check(is_zero_approx(float(game.get("time_remaining"))), label + " Lives mode has no countdown")
	_test_sustained_flight(game, gate_nodes, label)
	await _dispose(game)
	print("Checked continuous Human Plane " + label)


func _test_sustained_flight(game: Control, gates: Array[Control], label: String) -> void:
	# Successive handoffs must reuse the same two editor-authored trios without
	# a blank frame or repeated words. This catches a second-cycle recycle bug
	# that a single successful prefetch cannot expose.
	var accumulated_options: Dictionary = {}
	var saved_words: Dictionary = game.get("used_round_words")
	for word in saved_words:
		accumulated_options[word] = true
	for cycle in range(2):
		if bool(game.get("finished")):
			_check(false, label + " flight ended before repeated handoff %d" % cycle)
			return
		var completed := int(game.get("waves_completed"))
		var starting_attempts := int(game.get("attempts"))
		var starting_score := int(game.get("score"))
		var starting_correct := int(game.get("correct_count"))
		var active_data: Dictionary = game.get("round_data")
		var active_words := _word_set(active_data)
		_check(active_words.size() == 3, label + " cycle %d has three active options" % cycle)
		if active_words.size() != 3:
			return
		var answer_lane := int((active_data["valid_indices"] as Array)[0])
		var saw_readable_preview := false
		var saw_reserved := false
		var saw_blank := false
		var handed_off := false
		var upcoming_at_exit: Array = []
		var upcoming_positions := {}
		for tick in range(MAX_STEPS):
			# Keep a deterministic correct position on the active gate throughout
			# its approach; old incoming gates have no influence on scoring.
			if int(game.get("attempts")) == starting_attempts:
				_aim_plane_at_lane(game, answer_lane)
			game.call("_update_gate_wave", STEP)
			game.call("_sync_visuals")
			var visible := _visible_gates(gates)
			if visible.is_empty() and not bool(game.get("finished")):
				saw_blank = true
			var next_data: Dictionary = game.get("next_round_data")
			if not next_data.is_empty() and int(game.get("waves_completed")) == completed:
				var pending_nodes: Array = game.get("_upcoming_gate_nodes")
				if pending_nodes.size() == 3 and (pending_nodes[1] as Control).visible:
					saw_readable_preview = saw_readable_preview or _separated_readable_preview(game)
				var future_words := _word_set(next_data)
				var overlaps := false
				for word in future_words:
					if active_words.has(word):
						overlaps = true
					break
				if not overlaps and future_words.size() == 3:
					saw_reserved = true
			if int(game.get("waves_completed")) > completed:
				handed_off = true
				# Snapshot newly promoted nodes to verify the exact same three
				# instances remain in place on the following movement tick.
				upcoming_at_exit = game.get("_gate_nodes")
				for node in upcoming_at_exit:
					upcoming_positions[node.get_instance_id()] = node.global_position
				break
			if bool(game.get("finished")):
				break
		_check(saw_readable_preview, label + " cycle %d preloads readable fully opaque depth-separated gates" % cycle)
		_check(saw_reserved, label + " cycle %d has three unique incoming words" % cycle)
		_check(not saw_blank, label + " cycle %d never has an empty gate corridor" % cycle)
		_check(handed_off, label + " cycle %d promotes prefetched trio without delay" % cycle)
		if not handed_off:
			return
		_check(int(game.get("attempts")) == starting_attempts + 1, label + " cycle %d resolves the question exactly once" % cycle)
		_check(int(game.get("correct_count")) == starting_correct + 1, label + " cycle %d credited exactly one correct gate" % cycle)
		_check(int(game.get("score")) > starting_score, label + " cycle %d correct choice earns score" % cycle)
		_check(int(game.get("lives")) == 3, label + " cycle %d correct answers preserve three hearts" % cycle)
		var promoted_data: Dictionary = game.get("round_data")
		var promoted_words := _word_set(promoted_data)
		var seen_repeat := false
		for word in promoted_words:
			if accumulated_options.has(word):
				seen_repeat = true
			accumulated_options[word] = true
		_check(not seen_repeat, label + " cycle %d word set never repeats earlier waves" % cycle)
		game.call("_update_gate_wave", STEP)
		game.call("_sync_visuals")
		for node in upcoming_at_exit:
			_check(node.visible, label + " cycle %d same promoted gate stays visible" % cycle)
			_check(node.global_position.distance_to(upcoming_positions[node.get_instance_id()]) < game.size.y * 0.15,
				label + " cycle %d promoted gate advances without pop-in" % cycle)


func _aim_plane_at_lane(game: Control, answer_lane: int) -> void:
	var centers: PackedFloat32Array = game.call("_normalized_scoring_lane_centers",
		float(game.call("_progress_for_answer_line")))
	if centers.size() == 3:
		game.set("plane_x_norm", centers[answer_lane])


func _test_pose_steering(game: Control, label: String) -> void:
	var start_x := float(game.get("plane_x_norm"))
	game.call("set_airplane_pose_active", false)
	game.call("set_body_x", 1.0)
	game.call("_update_plane_motion", 0.4)
	_check(is_equal_approx(float(game.get("plane_x_norm")), start_x), label + " lowered arms block steering")
	game.call("set_airplane_pose_active", true)
	game.call("set_body_x", 1.0)
	game.call("_update_plane_motion", 0.075)
	var moved := float(game.get("plane_x_norm"))
	_check(moved > start_x + 0.001 and moved < 0.945, label + " valid airplane pose steers smoothly")
	game.call("set_airplane_pose_active", false)
	game.call("set_body_x", -1.0)
	game.call("_update_plane_motion", 0.8)
	_check(is_equal_approx(float(game.get("plane_x_norm")), moved), label + " lost airplane pose freezes exact X")
	game.call("set_airplane_pose_active", true)
	game.call("_update_plane_motion", 0.15)
	_check(is_equal_approx(float(game.get("plane_x_norm")), moved), label + " re-raised arms do not replay stale target")
	game.call("set_airplane_pose_active", false)


func _gate_controls(game: Control) -> Array[Control]:
	var found: Array[Control] = []
	var queue: Array[Node] = []
	for container_name in ["MovingGates", "UpcomingGates"]:
		var container := game.get_node_or_null(container_name)
		if container != null:
			queue.append(container)
	while not queue.is_empty():
		var item := queue.pop_front() as Node
		if item is Control and item.has_node("WordLabel") and item.has_node("GateArtwork"):
			found.append(item as Control)
		for child in item.get_children():
			queue.append(child)
	return found


func _separated_readable_preview(game: Control) -> bool:
	var front: Array[Control] = game.get("_gate_nodes")
	var incoming: Array[Control] = game.get("_upcoming_gate_nodes")
	if front.size() != 3 or incoming.size() != 3 or not incoming[0].get_parent().visible:
		return false
	for i in range(3):
		var label := incoming[i].get_node("WordLabel") as Label
		var plate := incoming[i].get_node("WordPlate") as Control
		if not incoming[i].is_visible_in_tree() or not label.visible or not plate.visible \
				or label.text.strip_edges().is_empty() or label.get_theme_font_size("font_size") < 20 \
				or incoming[i].modulate.a < 0.999:
			return false
		# Require separate projected depth planes, not two opaque sets
		# occupying the same ring position in a busy classroom view.
		var near_rect: Rect2 = game.call("_gate_visible_rect", i, float(game.gate_progress))
		var far_rect: Rect2 = game.call("_gate_visible_rect_with_offsets", i,
			float(game.next_gate_progress), game.get("_upcoming_rect_offsets"), incoming)
		if not near_rect.has_area() or not far_rect.has_area() \
				or far_rect.get_center().y >= near_rect.get_center().y - 10.0:
			return false
		for other in range(i + 1, 3):
			var other_plate := incoming[other].get_node("WordPlate") as Control
			if plate.get_global_rect().intersects(other_plate.get_global_rect()):
				return false
	return true


func _visible_gates(nodes: Array[Control]) -> Array[Control]:
	var found: Array[Control] = []
	for node in nodes:
		if is_instance_valid(node) and node.is_visible_in_tree():
			found.append(node)
	return found


func _word_set(round_info: Dictionary) -> Dictionary:
	var unique: Dictionary = {}
	for option in round_info.get("options", []):
		unique[String(option).strip_edges().to_lower()] = true
	return unique


func _gate_word_set(nodes: Array[Control]) -> Dictionary:
	var unique: Dictionary = {}
	for node in nodes:
		var word := (node.get_node("WordLabel") as Label).text.strip_edges().to_lower()
		if not word.is_empty():
			unique[word] = true
	return unique


func _snapshot_positions(nodes: Array[Control]) -> Dictionary:
	var result: Dictionary = {}
	for node in nodes:
		result[node.get_instance_id()] = {"pos": node.global_position, "visible": node.visible}
	return result


func _positions_unchanged(nodes: Array[Control], previous: Dictionary) -> bool:
	for node in nodes:
		var item: Dictionary = previous[node.get_instance_id()]
		if not node.global_position.is_equal_approx(item["pos"]) or node.visible != bool(item["visible"]):
			return false
	return true


func _dispose(game: Node) -> void:
	game.queue_free()
	await process_frame
	await process_frame


func _check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures.append(description)
