extends SceneTree

# Actual 2D-authoritative hits, native perspective positions, two pooled
# TorusMesh trios, and authentic GrammarBank prefetch across six full waves.
# Run: Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_torus_center_prefetch_20261029.gd
const GAME := preload("res://ui/minigames/human_plane/human_plane.tscn")
const LANES := ["Left", "Center", "Right"]
const STEP := 1.0 / 60.0
const CYCLES := 6

var assertions := 0
var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dims in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.content_scale_size = dims
		root.size = dims
		for mode in ["Seconds", "Lives"]:
			await _exercise(mode)
	print("HUMAN PLANE CENTER + PREFETCH: %s checks=%d failures=%d" %
		["PASS" if errors.is_empty() else "FAIL", assertions, errors.size()])
	quit(0 if errors.is_empty() else 1)


func _exercise(mode: String) -> void:
	var game := GAME.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity":"Human Plane", "topic":"Noun", "difficulty":"Normal", "game_mode":mode})
	await process_frame
	await process_frame
	await process_frame
	game.set_process(false)
	var renderer := game.get_node("HybridFlight3D")
	renderer.set_process(false)
	var gates := renderer.get_node("RenderViewport/FlightWorld3D/Gates") as Node3D
	var plane := renderer.get_node("RenderViewport/FlightWorld3D/PlaneAnchor") as Node3D
	var ring_ids := {}
	var mesh_ids := {}
	var resource_ids := {}
	var pool := renderer.get("_ring_pools") as Array
	var captured := false
	_check(pool.size() == 2 and gates.get_child_count() == 6,
		mode + " only two reusable trios, exactly six native ring units")
	for ring_set in pool:
		for ring in ring_set:
			var mesh := (ring as Node3D).get_node("Ring") as MeshInstance3D
			_check(mesh.mesh is TorusMesh and mesh.visible and mesh.material_override is StandardMaterial3D,
				mode + " six scene-authored TorusMesh node copies with materials")
			ring_ids[ring.name] = ring.get_instance_id()
			mesh_ids[ring.name] = mesh.get_instance_id()
			resource_ids[ring.name] = mesh.mesh.get_instance_id()
	for cycle in range(CYCLES):
		var round_data := (game.get("round_data") as Dictionary).duplicate(true)
		var options: Array = round_data.get("options", [])
		var valid: Array = round_data.get("valid_indices", [])
		_check(options.size() == 3 and valid.size() > 0 and options[0] != options[1]
			and options[1] != options[2] and options[0] != options[2],
			mode + " wave%d source GrammarBank provides three different real words" % cycle)
		if valid.is_empty():
			break
		var correct_lane := int(valid[0])
		_place_at_lane(game, correct_lane)
		_check(int(game.call("_lane_hit_at_answer_line")) == correct_lane,
			mode + " wave%d calibrated plane hitbox overlaps chosen correct torus" % cycle)
		var current_set: Array = game.get("_gate_nodes")
		var active_idx := 0 if (current_set[0] as Control).get_parent() == game.get_node("MovingGates") else 1
		var next_idx := 1 - active_idx
		var queued_visible := false
		var scored := false
		var passed := false
		var behind_view := false
		var previous_score := int(game.get("score"))
		var earlier_next_z := -999999.0
		for tick in range(900):
			game.call("_update_gate_wave", STEP)
			game.call("_sync_visuals")
			renderer.call("_process", 0.0)
			if not queued_visible and not (game.get("next_round_data") as Dictionary).is_empty():
				var incoming_words: Array = (game.get("next_round_data") as Dictionary).get("options", [])
				var incoming_gate_controls: Array = game.get("_upcoming_gate_nodes")
				var words_match := incoming_words.size() == 3
				for lane in range(3):
					var next_gate := pool[next_idx][lane] as Node3D
					var label := (incoming_gate_controls[lane] as Control).get_node("WordLabel") as Label
					words_match = words_match and next_gate.visible and label.visible
					words_match = words_match and label.text == String(incoming_words[lane]).to_upper()
				_check(words_match and (incoming_gate_controls[0] as Control).get_parent().visible,
					mode + " wave%d REAL next questions visible with three approaching rings" % cycle)
				_check((pool[next_idx][1] as Node3D).global_position.z <
					(pool[active_idx][1] as Node3D).global_position.z - 2.0,
					mode + " wave%d next torus is physically farther away (no overlapping ghost)" % cycle)
				earlier_next_z = (pool[next_idx][1] as Node3D).position.z
				queued_visible = true
			var progress := float(game.get("gate_progress"))
			var answer := float(game.call("_progress_for_answer_line"))
			if bool(game.get("gate_resolved")) and not scored:
				var ring := pool[active_idx][correct_lane] as Node3D
				var hole := ((ring.get_node("Ring") as MeshInstance3D).mesh as TorusMesh).inner_radius
				var relative := ring.global_position - plane.global_position
				_check(absf(relative.y) < 0.035 and absf(relative.x) < ring.scale.x * hole * 0.30,
					mode + " wave%d TRUE aircraft CENTER falls within torus opening at scoring" % cycle)
				_check(int(game.get("score")) == previous_score + 100 and
					int(game.get("attempts")) == cycle + 1 and
					int(game.get("selected_lane")) == correct_lane and bool(game.get("selected_was_correct")),
					mode + " wave%d original collision awards +100 exactly once" % cycle)
				var outgoing_clear := true
				var incoming_readable := true
				for lane in range(3):
					var leaving_gate := (game.get("_gate_nodes") as Array)[lane] as Control
					outgoing_clear = outgoing_clear and not (leaving_gate.get_node("WordLabel") as Label).visible
					outgoing_clear = outgoing_clear and not (leaving_gate.get_node("WordPlate") as CanvasItem).visible
					var entering_gate := (game.get("_upcoming_gate_nodes") as Array)[lane] as Control
					incoming_readable = incoming_readable and (entering_gate.get_node("WordLabel") as Label).visible
				_check(outgoing_clear and incoming_readable and (pool[active_idx][correct_lane] as Node3D).visible,
					mode + " wave%d old plaques clear airplane but torus and future words stay on screen" % cycle)
				if not captured and mode == "Seconds" and "--capture" in OS.get_cmdline_user_args() and \
					DisplayServer.get_name() != "headless":
					await process_frame
					await RenderingServer.frame_post_draw
					var screenshot := root.get_texture().get_image()
					var filename := "user://_qa_human_plane_through_center_prefetch_20261029.png"
					_check(screenshot != null and not screenshot.is_empty() and screenshot.save_png(filename) == OK,
						"real native render screenshot saved at " + ProjectSettings.globalize_path(filename))
					print("NATIVE TORUS CAPTURE: " + ProjectSettings.globalize_path(filename))
					captured = true
				game.call("_resolve_at_answer_line")
				_check(int(game.get("score")) == previous_score + 100 and int(game.get("attempts")) == cycle + 1,
					mode + " wave%d scoring is idempotent on repeat event" % cycle)
				scored = true
			if scored and not passed and progress > answer + (1.0 - answer) * 0.40:
				var selected_ring := pool[active_idx][correct_lane] as Node3D
				_check(selected_ring.visible and selected_ring.global_position.z > plane.global_position.z + 2.0,
					mode + " wave%d ring stays visible past airplane nose toward camera" % cycle)
				_check(absf(selected_ring.global_position.y - plane.global_position.y) < 0.035,
					mode + " wave%d ring stays centered vertically along actual aircraft flight line" % cycle)
				_check(float(game.call("_gate_passage_alpha", progress)) == 1.0,
					mode + " wave%d no premature ring/word fade during physical passage" % cycle)
				passed = true
			# Sample while still several native frames BEFORE the 1.0 handoff.
			# Faster waves can skip the final 1.5% between 60 Hz frames.
			if scored and not behind_view and progress > answer + (1.0 - answer) * 0.94:
				var final_ring := pool[active_idx][correct_lane] as Node3D
				var camera := renderer.get_node("RenderViewport/FlightWorld3D/Camera") as Camera3D
				_check(camera.global_position.z - final_ring.global_position.z < 1.2,
					mode + " wave%d torus nearly reaches camera before reusing pool" % cycle)
				behind_view = true
			if int(game.get("waves_completed")) > cycle:
				break
		_check(queued_visible and scored and passed and behind_view,
			mode + " wave%d next visible, correct score, physical passage, camera exit" % cycle)
		_check(int(game.get("waves_completed")) == cycle + 1 and int(game.get("score")) == previous_score + 100,
			mode + " wave%d exact one scored answer through native handoff" % cycle)
		_check((pool[next_idx][1] as Node3D).position.z > earlier_next_z,
			mode + " wave%d next torus traveled forward while current passed" % cycle)
		_check(int(game.get("lives")) == 3 and not bool(game.get("finished")),
			mode + " wave%d correctly preserves lives and strict round ending" % cycle)
		_check(gates.get_child_count() == 6,
			mode + " wave%d still six bounded native ring instances" % cycle)
		for ring_set in pool:
			for ring in ring_set:
				var mesh := (ring as Node3D).get_node("Ring") as MeshInstance3D
				_check(ring.get_instance_id() == ring_ids[ring.name] and
					mesh.get_instance_id() == mesh_ids[ring.name] and
					mesh.mesh.get_instance_id() == resource_ids[ring.name],
					mode + " wave%d native TorusMesh and node IDs stay stable" % cycle)
	_check(int(game.get("correct_count")) == CYCLES and int(game.get("score")) == CYCLES * 100,
		mode + " all six real hits give exactly 600")
	_check(float(game.get("speed_multiplier")) > 1.0 and int(game.get("speed_boost_count")) == CYCLES,
		mode + " difficulty progression remains intact")
	game.queue_free()
	await process_frame
	await process_frame


func _place_at_lane(game: Control, lane: int) -> void:
	var at_answer := float(game.call("_progress_for_answer_line"))
	var rect: Rect2 = game.call("_gate_visible_rect", lane, at_answer)
	var left := game.get_node("FlightPaths/PlaneLeftLimit") as Control
	var right := game.get_node("FlightPaths/PlaneRightLimit") as Control
	var rig := game.get_node("PlaneRig") as Control
	var hitbox := game.get_node("PlaneRig/Hitbox") as Control
	var offset := hitbox.get_rect().get_center().x - rig.size.x * 0.5
	game.set("plane_x_norm", (rect.get_center().x - offset -
		float(game.get("_plane_authored_offset_x")) - left.get_rect().get_center().x) /
		(right.get_rect().get_center().x - left.get_rect().get_center().x))
	game.call("_sync_visuals")


func _check(ok: bool, title: String) -> void:
	assertions += 1
	if not ok:
		errors.append(title)
		printerr("CENTER/PREFETCH FAIL: " + title)
