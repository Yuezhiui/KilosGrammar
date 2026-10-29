extends SceneTree

## Full real gameplay flight passage through two fixed TorusMesh pools.
## Each of four waves in both modes uses source GrammarBank options and
## authoritative PlaneRig/Hitbox scoring; no fabricated success or manual score.
## --headless supported; native OpenGL -- --capture saves GPU images to user://.
const SCENE := preload("res://ui/minigames/human_plane/human_plane.tscn")
const STEP := 1.0 / 60.0
const LANES := ["Left", "Center", "Right"]
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const CYCLES := 4

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dims in SIZES:
		root.size = dims
		root.content_scale_size = dims
		for mode in ["Seconds", "Lives"]:
			await _exercise(dims, mode)
	print("HUMAN PLANE TORUS PASSAGE: %s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _exercise(dims: Vector2i, mode: String) -> void:
	var tag := "%dx%d/%s" % [dims.x, dims.y, mode]
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(dims)
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity":"Human Plane", "topic":"Noun", "difficulty":"Normal", "game_mode":mode})
	for frame in range(3):
		await process_frame
	game.set_process(false)
	var renderer := game.get_node("HybridFlight3D") as Node2D
	renderer.set_process(false)
	var world := renderer.get_node("RenderViewport/FlightWorld3D") as Node3D
	var camera := world.get_node("Camera") as Camera3D
	var plane := world.get_node("PlaneAnchor") as Node3D
	var gates := world.get_node("Gates") as Node3D
	var imported := world.get_node("PlaneAnchor/PlaneModelPlacement/DownloadedCartoonPlane") as Node3D
	var pools: Array = renderer.get("_ring_pools")
	_check(pools.size() == 2 and gates.get_child_count() == 6,
		tag + " exactly six fixed ring nodes in two physical trios")
	var ids := {}
	var mesh_ids := {}
	var resource_ids := {}
	for pool in pools:
		for lane_i in range(3):
			var ring := pool[lane_i] as Node3D
			var mesh := ring.get_node("Ring") as MeshInstance3D
			_check(mesh.mesh is TorusMesh and mesh.material_override is StandardMaterial3D,
				tag + " real TorusMesh/material " + ring.name)
			ids[ring.name] = ring.get_instance_id()
			mesh_ids[ring.name] = mesh.get_instance_id()
			resource_ids[ring.name] = mesh.mesh.get_instance_id()
	_check(ids.size() == 6 and mesh_ids.size() == 6,
		tag + " unique one-time native ring and mesh instances for both trios")
	_check(bool(game.get("started")) and not bool(game.get("finished")) and
		String(game.get("topic")) == "Noun" and String(game.get("difficulty")) == "Normal",
		tag + " real Noun/Normal gameplay starts with correct source context")
	_check(int(game.get("score")) == 0 and int(game.get("lives")) == 3 and
		int(game.get("attempts")) == 0,
		tag + " strict game counters start at score zero, lives three")
	var captures := 0
	for cycle in range(CYCLES):
		var options: Dictionary = (game.get("round_data") as Dictionary).duplicate(true)
		var valid: Array = options.get("valid_indices", [])
		var words: Array = options.get("options", [])
		_check(valid.size() >= 1 and words.size() == 3 and
			words[0] != words[1] and words[0] != words[2] and words[1] != words[2],
			tag + " wave %d has three distinct real GrammarBank options" % cycle)
		if valid.is_empty() or words.size() != 3:
			break
		var correct_lane := int(valid[0])
		_place_at_lane(game, correct_lane)
		_check(int(game.call("_lane_hit_at_answer_line")) == correct_lane,
			tag + " wave %d real hitbox aligned with correct scoring lane" % cycle)
		var answer_progress := float(game.call("_progress_for_answer_line"))
		_check(answer_progress > 0.0 and answer_progress < 0.98,
			tag + " wave %d valid scoring before camera exit" % cycle)
		var active_controls: Array = game.get("_gate_nodes")
		var active_idx := 0 if (active_controls[0] as Control).get_parent() == game.get_node("MovingGates") else 1
		var next_idx := 1 - active_idx
		var queued_visible := false
		var scored := false
		var passed := false
		var near_clip := false
		var late_alpha_checked := false
		var current_words_hidden := false
		var first_next_depth := -INF
		var queued_options: Array = []
		var score_before := int(game.get("score"))
		var attempt_before := int(game.get("attempts"))
		# Sample actual engine advancement more finely in the last 7% of
		# camera-depth travel: a full 60 FPS step can legitimately jump past
		# a 1.5%-wide near-clip window at the earned higher gate speeds.
		for tick in range(1400):
			var near_end_fraction := clampf((float(game.get("gate_progress")) - answer_progress) /
				maxf(1.0 - answer_progress, 0.001), 0.0, 1.0)
			var advance_step := STEP * 0.25 if near_end_fraction > 0.93 else STEP
			game.call("_update_gate_wave", advance_step)
			game.call("_sync_visuals")
			renderer.call("_process", 0.0)
			var progress := float(game.get("gate_progress"))
			var beyond := clampf((progress - answer_progress) /
				maxf(1.0 - answer_progress, 0.001), 0.0, 1.0)
			if not queued_visible and not (game.get("next_round_data") as Dictionary).is_empty():
				queued_options = (game.get("next_round_data") as Dictionary).get("options", []).duplicate()
				var incoming_controls: Array = game.get("_upcoming_gate_nodes")
				var trio_is_real: bool = queued_options.size() == 3 and \
					(incoming_controls[0] as Control).get_parent().visible
				for i in range(3):
					var upcoming := pools[next_idx][i] as Node3D
					var incoming_word := (incoming_controls[i] as Control).get_node("WordLabel") as Label
					var incoming_plate := (incoming_controls[i] as Control).get_node("WordPlate") as CanvasItem
					trio_is_real = trio_is_real and upcoming.visible and \
						incoming_word.visible and incoming_plate.visible
					trio_is_real = trio_is_real and incoming_word.text == String(queued_options[i]).to_upper()
					_check((pools[active_idx][i] as Node3D).visible and upcoming.visible,
						tag + " wave %d %s both physical trios on screen together" % [cycle, LANES[i]])
				_check(trio_is_real, tag + " wave %d authentic approaching next labels visible" % cycle)
				first_next_depth = (pools[next_idx][1] as Node3D).position.z
				_check(first_next_depth < (pools[active_idx][1] as Node3D).position.z - 2.0,
					tag + " wave %d prefetched torus starts farther from camera" % cycle)
				queued_visible = true
			if bool(game.get("gate_resolved")) and not scored:
				_check(int(game.get("selected_lane")) == correct_lane and
					bool(game.get("selected_was_correct")),
					tag + " wave %d original collision selects correct GrammarBank answer" % cycle)
				_check(int(game.get("score")) == score_before + 100 and
					int(game.get("attempts")) == attempt_before + 1,
					tag + " wave %d scoring +100 exactly once at actual answer line" % cycle)
				var selected_ring := pools[active_idx][correct_lane] as Node3D
				var hole := ((selected_ring.get_node("Ring") as MeshInstance3D).mesh as TorusMesh).inner_radius
				var relative := selected_ring.global_position - plane.global_position
				_check(selected_ring.visible and absf(relative.y) < 0.035 and
					absf(relative.x) < selected_ring.scale.x * hole * 0.30 and
					absf(relative.z) < 0.30,
					tag + " wave %d aircraft 3D center crosses selected real ring hole at scoring" % cycle)
				_check(_outer_mesh_fraction(imported, selected_ring.global_position,
					selected_ring.scale.x * hole, selected_ring.scale.y * hole) < 0.96,
					tag + " wave %d actual 22-mesh airplane body and wings physically fit hollow ring" % cycle)
				var incoming_controls: Array = game.get("_upcoming_gate_nodes")
				var outgoing_controls: Array = game.get("_gate_nodes")
				var outgoing_hidden := true
				var incoming_visible := true
				for i in range(3):
					outgoing_hidden = outgoing_hidden and \
						not (outgoing_controls[i] as Control).get_node("WordLabel").visible and \
						not (outgoing_controls[i] as Control).get_node("WordPlate").visible
					incoming_visible = incoming_visible and \
						(incoming_controls[i] as Control).get_node("WordLabel").visible and \
						(incoming_controls[i] as Control).get_node("WordPlate").visible and \
						(pools[active_idx][i] as Node3D).visible and \
						(pools[next_idx][i] as Node3D).visible
				_check(outgoing_hidden and incoming_visible,
					tag + " wave %d outgoing plaques HIDE immediately, SIX rings and next words persist" % cycle)
				current_words_hidden = outgoing_hidden
				game.call("_resolve_at_answer_line")
				_check(int(game.get("score")) == score_before + 100 and
					int(game.get("attempts")) == attempt_before + 1,
					tag + " wave %d second collision callback cannot double score" % cycle)
				if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless" and \
					mode == "Seconds" and cycle == 0 and captures == 0:
					for frame in range(3):
						await process_frame
					await RenderingServer.frame_post_draw
					var screenshot := root.get_texture().get_image()
					var filename := "user://_qa_torus_passage_%dx%d_%s.png" % [dims.x, dims.y, mode.to_lower()]
					_check(screenshot != null and not screenshot.is_empty() and
						screenshot.save_png(filename) == OK,
						tag + " real native six-ring scoring screenshot captured")
					print("TORUS_PASSAGE_CAPTURE: " + ProjectSettings.globalize_path(filename))
					captures += 1
				scored = true
			if scored and not passed and beyond >= 0.40:
				var through := true
				for i in range(3):
					var ring := pools[active_idx][i] as Node3D
					through = through and ring.visible and \
						ring.global_position.z > plane.global_position.z + 2.0 and \
						absf(ring.global_position.y - plane.global_position.y) < 0.035
					through = through and not ((game.get("_gate_nodes") as Array)[i] as Control).get_node("WordLabel").visible
				_check(through, tag + " wave %d outgoing torus passes airplane in fixed XY while labels stay hidden" % cycle)
				_check(is_equal_approx(float(game.call("_gate_passage_alpha", progress)), 1.0),
					tag + " wave %d no fade while real torus passes aircraft" % cycle)
				passed = true
			if scored and not near_clip and beyond >= 0.985:
				var all_near := true
				var all_opaque_or_fading := true
				var alpha := float(game.call("_gate_passage_alpha", progress))
				for i in range(3):
					var ring := pools[active_idx][i] as Node3D
					var physical_distance := camera.global_position.z - ring.global_position.z
					var material := (ring.get_node("Ring") as MeshInstance3D).material_override as StandardMaterial3D
					all_near = all_near and ring.visible and \
						physical_distance < 1.2 and physical_distance > camera.near
					all_opaque_or_fading = all_opaque_or_fading and \
						absf(material.albedo_color.a - alpha) < 0.001
				_check(all_near, tag + " wave %d ALL scored torus nodes reach CAMERA near clip before reuse" % cycle)
				_check(alpha > 0.0 and alpha < 1.0 and all_opaque_or_fading,
					tag + " wave %d last-2-percent fade matches physical 3D ring alpha" % cycle)
				_check(float(renderer.call("_gate_distance", 1.0, answer_progress)) <= camera.near * 1.1,
					tag + " wave %d ring trajectory ends at actual camera clipping plane" % cycle)
				late_alpha_checked = true
				near_clip = true
			if int(game.get("waves_completed")) > cycle:
				break
		_check(queued_visible and scored and passed and near_clip and late_alpha_checked and current_words_hidden,
			tag + " wave %d complete real scoring, opaque passage, near-clip exit and live next vocabulary" % cycle)
		_check(int(game.get("waves_completed")) == cycle + 1 and
			int(game.get("score")) == score_before + 100 and
			int(game.get("attempts")) == attempt_before + 1,
			tag + " wave %d natural handoff exactly one +100 award" % cycle)
		_check((game.get("round_data") as Dictionary).get("options", []) == queued_options and
			(game.get("_gate_nodes") as Array)[0].get_parent() ==
				(game.get_node("MovingGates") if next_idx == 0 else game.get_node("UpcomingGates")),
			tag + " wave %d prefetched real GrammarBank question promoted in source guide pool" % cycle)
		_check((pools[next_idx][1] as Node3D).position.z > first_next_depth,
			tag + " wave %d next trio actually approached continuously during outgoing passage" % cycle)
		_check(int(game.get("lives")) == 3 and not bool(game.get("finished")) and
			(mode == "Lives" or float(game.get("time_remaining")) > 0.0),
			tag + " wave %d preserves hearts and strict Seconds/Lives ending" % cycle)
		_check(gates.get_child_count() == 6 and (renderer.get("_ring_pools") as Array).size() == 2,
			tag + " wave %d exactly six bounded native ring instances, no allocation growth" % cycle)
		for ring_set in pools:
			for node in ring_set:
				var ring := node as Node3D
				var mesh := ring.get_node("Ring") as MeshInstance3D
				_check(ring.get_instance_id() == ids[ring.name] and
					mesh.get_instance_id() == mesh_ids[ring.name] and
					mesh.mesh.get_instance_id() == resource_ids[ring.name],
					tag + " wave %d stable ring/mesh/resource ID for %s" % [cycle, ring.name])
	_check(int(game.get("score")) == CYCLES * 100 and
		int(game.get("correct_count")) == CYCLES and
		int(game.get("attempts")) == CYCLES,
		tag + " four real consecutive correct cycles give precisely 400 and four scored attempts")
	_check(int(game.get("speed_boost_count")) == CYCLES and
		float(game.get("speed_multiplier")) > 1.0,
		tag + " genuine score-earned flight acceleration stays active")
	game.queue_free()
	await process_frame
	await process_frame


func _place_at_lane(game: Control, lane: int) -> void:
	var at_line := float(game.call("_progress_for_answer_line"))
	var rect: Rect2 = game.call("_gate_visible_rect", lane, at_line)
	var left := game.get_node("FlightPaths/PlaneLeftLimit") as Control
	var right := game.get_node("FlightPaths/PlaneRightLimit") as Control
	var rig := game.get_node("PlaneRig") as Control
	var hitbox := game.get_node("PlaneRig/Hitbox") as Control
	var offset := hitbox.get_rect().get_center().x - rig.size.x * 0.5
	game.set("plane_x_norm", (rect.get_center().x - offset -
		float(game.get("_plane_authored_offset_x")) - left.get_rect().get_center().x) /
		(right.get_rect().get_center().x - left.get_rect().get_center().x))
	game.call("_sync_visuals")


func _outer_mesh_fraction(node: Node, hole_center: Vector3, radius_x: float, radius_y: float) -> float:
	var farthest := 0.0
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_node := node as MeshInstance3D
		var bounds := mesh_node.mesh.get_aabb()
		for corner in range(8):
			var point := mesh_node.global_transform * bounds.get_endpoint(corner)
			var nx := (point.x - hole_center.x) / radius_x
			var ny := (point.y - hole_center.y) / radius_y
			farthest = maxf(farthest, sqrt(nx * nx + ny * ny))
	for child in node.get_children():
		farthest = maxf(farthest, _outer_mesh_fraction(child, hole_center, radius_x, radius_y))
	return farthest


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		printerr("TORUS PASSAGE FAIL: " + detail)
