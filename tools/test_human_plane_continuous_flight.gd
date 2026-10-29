extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_continuous_flight.gd
# No fake gate nodes: tests the two serialized gate sets through real scenes.
const SCENE := preload("res://ui/minigames/human_plane/human_plane.tscn")
const SCREEN_SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const MODES := ["Seconds", "Lives"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for size in SCREEN_SIZES:
		for mode in MODES:
			for difficulty in DIFFICULTIES:
				await _exercise(size, mode, difficulty)
	if DisplayServer.get_name() != "headless":
		await _capture_two_wave_handoff()
	print("HUMAN PLANE CONTINUOUS FLIGHT: ", "PASS" if failures.is_empty() else "FAIL",
		" (%d checks, %d failures)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _exercise(size: Vector2i, mode: String, difficulty: String) -> void:
	root.size = size
	var title := "%dx%d %s %s" % [size.x, size.y, mode, difficulty]
	var game := SCENE.instantiate() as Control
	var current := game.get_node_or_null("MovingGates") as Control
	var upcoming := game.get_node_or_null("UpcomingGates") as Control
	_check(current != null and current.owner == game, title + " first trio authored in .tscn")
	_check(upcoming != null and upcoming.owner == game, title + " second trio authored in .tscn")
	if current == null or upcoming == null:
		game.free()
		return
	var authored_ids := {}
	for group in [current, upcoming]:
		for lane in ["Left", "Center", "Right"]:
			var control := group.get_node_or_null("Gate" + lane) as Control
			_check(control != null and control.owner == game, title + " actual editor-authored " + group.name + "/" + lane)
			if control == null:
				continue
			authored_ids[control.get_instance_id()] = true
			for piece in ["GateArtwork", "WordLabel", "LeftPillar", "RightPillar", "TopBar"]:
				var child := control.get_node_or_null(piece)
				_check(child != null and child.owner == game, title + " editor-artifact " + group.name + "/" + lane + "/" + piece)
			_check((control.get_node("GateArtwork") as TextureRect).texture != null,
				title + " original immutable gate PNG referenced")
	_check(authored_ids.size() == 6, title + " exactly 6 authored gates, not runtime-created substitutes")
	var first_layout: Rect2 = (current.get_node("GateCenter") as Control).get_rect()
	var second_layout: Rect2 = (upcoming.get_node("GateCenter") as Control).get_rect()
	_check(first_layout.is_equal_approx(second_layout), title + " standby guide inherits user-authored initial dimensions")
	_check(game.get_node_or_null("HUDLayer/HUD/ScoreBottomContainer/ScoreNumber") != null, title + " Catch HUD score preserved")
	_check(game.get_node_or_null("HUDLayer/HUD/TimeLabel") != null, title + " Catch HUD timer preserved")
	_check(game.get_node_or_null("HUDLayer/HUD/WaveLabel") == null, title + " no WAVE counter resurrected")
	var events: Array[String] = []
	game.requested.connect(func(destination: String, _payload: Dictionary) -> void: events.append(destination))
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity":"Human Plane", "topic":"Noun", "difficulty":difficulty, "game_mode":mode})
	await process_frame
	await process_frame
	game.set_process(false)
	var hybrid := game.get_node_or_null("HybridFlight3D") as Node2D
	_check(hybrid != null and bool(hybrid.get("hybrid_enabled"))
		and bool(hybrid.get("draw_3d_gates"))
		and not (game.get_node("PlaneRig/PlaneArtwork") as TextureRect).visible,
		title + " native low-poly 3D airplane and torus gates are the default")
	if hybrid != null:
		hybrid.set("hybrid_enabled", true)
		hybrid.set("draw_3d_gates", true)
		hybrid.call("_process", 0.0)
	_check(hybrid != null and bool(hybrid.get("hybrid_enabled"))
		and bool(hybrid.get("draw_3d_gates")),
		title + " active genuine 3D aircraft and torus gates remain enabled")
	if hybrid != null:
		var overlay := hybrid.get_node_or_null("OverlayTexture") as TextureRect
		var camera := hybrid.get_node_or_null("RenderViewport/FlightWorld3D/Camera") as Camera3D
		var viewport := hybrid.get_node_or_null("RenderViewport") as SubViewport
		_check(overlay != null and overlay.visible and viewport != null
			and overlay.texture == viewport.get_texture() and camera != null
			and camera.projection == Camera3D.PROJECTION_PERSPECTIVE,
			title + " real 3D sky renderer is composited under the 2D HUD")
		_check((game.get_node("PlaneRig/PlaneArtwork") as TextureRect).texture != null
			and not (game.get_node("PlaneRig/PlaneArtwork") as TextureRect).visible,
			title + " retained original 2D plane PNG is suppressed only during hybrid mode")
		# Actual manual fallbacks on the SAME gameplay scene. Toggling visual
		# mode cannot change words, scoring, lives or gate collision progress.
		var baseline_words := (game.get("round_data") as Dictionary).duplicate(true)
		var baseline_progress := float(game.get("gate_progress"))
		hybrid.set("hybrid_enabled", false)
		hybrid.call("_process", 0.0)
		_check(_is_opaque_trio(game.get("_gate_nodes") as Array[Control])
			and not (hybrid.get_node("OverlayTexture") as TextureRect).visible
			and (game.get_node("PlaneRig/PlaneArtwork") as TextureRect).visible,
			title + " original fully opaque 2D gate/plane PNG fallback is genuinely restored")
		hybrid.set("hybrid_enabled", true)
		hybrid.set("draw_3d_gates", false)
		hybrid.call("_process", 0.0)
		_check(_is_opaque_trio(game.get("_gate_nodes") as Array[Control])
			and (hybrid.get_node("OverlayTexture") as TextureRect).visible
			and not (game.get_node("PlaneRig/PlaneArtwork") as TextureRect).visible,
			title + " 3D plane with authentic 2D gate PNG fallback also renders")
		hybrid.set("draw_3d_gates", true)
		hybrid.call("_process", 0.0)
		_check(_is_opaque_trio(game.get("_gate_nodes") as Array[Control])
			and (game.get("round_data") as Dictionary) == baseline_words
			and is_equal_approx(float(game.get("gate_progress")), baseline_progress)
			and int(game.get("attempts")) == 0 and int(game.get("lives")) == 3,
			title + " true TorusMesh gates return without changing any physics or words")
	var initial_options: Array = (game.get("round_data") as Dictionary).get("options", [])
	_check(initial_options.size() == 3, title + " first word set contains 3 choices")
	_check(int(game.get("lives")) == 3, title + " exactly three available hearts")
	_check((game.get_node("HUDLayer/HUD/TimeLabel") as Label).visible == (mode == "Seconds"),
		title + " timer visibility respects Seconds/Lives")
	_check((game.get_node("HUDLayer/HUD/LivesPlaque") as TextureRect).visible == (mode == "Lives"),
		title + " native Lives plaque visibility respects mode")
	_check(float(game.get("time_remaining")) > 59.0 if mode == "Seconds"
		else is_zero_approx(float(game.get("time_remaining"))), title + " native mode time unchanged")
	_check(current.visible and not upcoming.visible and _ring_pool_count(hybrid) == 6,
		title + " one initial trio, with exactly six preallocated TorusMesh rings")
	var speed := float(game.DIFFICULTY_CONFIG[difficulty]["gate_speed"])
	var to_preview := (float(game.GATE_PREFETCH_AT) + 0.02) / speed
	game.call("_update_gate_wave", to_preview)
	game.call("_sync_visuals")
	var next_words: Dictionary = game.get("next_round_data")
	_check(not next_words.is_empty() and (next_words.get("options", []) as Array).size() == 3,
		title + " prefetch reserves all three next answers BEFORE current gate completes")
	_check(current.visible and upcoming.visible and
		upcoming.get_node("GateCenter").is_visible_in_tree() and
		_is_opaque_trio(game.get("_upcoming_gate_nodes") as Array[Control], true) and
		_ring_pool_count(hybrid) == 6,
		title + " both real vocabulary trios and exactly six pooled torus rings visible during prefetch")
	_check(_is_opaque_trio(game.get("_gate_nodes") as Array[Control]),
		title + " approaching gates and word labels remain fully opaque")
	var current_y: float = ((game.get("_gate_nodes") as Array)[1] as Control).get_rect().get_center().y
	var next_rect: Rect2 = game.call("_gate_rect_with_offsets", 1,
		float(game.get("next_gate_progress")), game.get("_upcoming_rect_offsets"))
	_check(next_rect.get_center().y < current_y - 10.0,
		title + " incoming REAL wave's authored travel position remains farther away")
	var next_options: Array = next_words.get("options", [])
	var word_seen := {}
	for option in initial_options:
		word_seen[String(option).to_lower()] = true
	for option in next_options:
		_check(not word_seen.has(String(option).to_lower()), title + " prefetch excludes earlier words: " + String(option))
		word_seen[String(option).to_lower()] = true
	_check((game.get("used_round_words") as Dictionary).size() == 6,
		title + " current and upcoming three options reserved exactly once")
	var stage_id: int = ((game.get("_upcoming_gate_nodes") as Array)[1] as Control).get_instance_id()
	var before_progress := float(game.get("next_gate_progress"))
	var before_rect: Rect2 = game.call("_gate_rect_with_offsets", 1,
		before_progress, game.get("_upcoming_rect_offsets"))
	# Tracking loss freezes horizontal pose but does not freeze approaching gates.
	game.call("set_airplane_pose_active", false)
	var previous_aircraft_x := float(game.get("plane_x_norm"))
	game.call("set_body_x", 1.0)
	game.call("_update_plane_motion", 0.2)
	_check(is_equal_approx(float(game.get("plane_x_norm")), previous_aircraft_x),
		title + " lost tracking safely holds plane X")
	# Pause freezes score, timer, active and upcoming gate progress.
	game.call("_pause")
	var stopped_current := float(game.get("gate_progress"))
	var stopped_next := float(game.get("next_gate_progress"))
	var stopped_time := float(game.get("time_remaining"))
	game.call("_process", 2.0)
	_check(is_equal_approx(float(game.get("gate_progress")), stopped_current) and
		is_equal_approx(float(game.get("next_gate_progress")), stopped_next) and
		is_equal_approx(float(game.get("time_remaining")), stopped_time),
		title + " pause freezes BOTH flights and game timer")
	game.call("_resume")
	game.call("_update_gate_wave", 0.04)
	game.call("_sync_visuals")
	var after_rect: Rect2 = game.call("_gate_rect_with_offsets", 1,
		float(game.get("next_gate_progress")), game.get("_upcoming_rect_offsets"))
	_check(float(game.get("next_gate_progress")) > before_progress and
		after_rect.get_center().y > before_rect.get_center().y and
		upcoming.visible and _is_opaque_trio(game.get("_gate_nodes") as Array[Control]) and
		_is_opaque_trio(game.get("_upcoming_gate_nodes") as Array[Control], true),
		title + " incoming real six-ring prefetch travels continuously without a ghost or faded gate")
	# Turn progress to the boundary, exercising one scoring event and the
		# next buffered trio's atomic handoff. Keep the original scoring and
		# collision event rather than forcing a fabricated result.
	game.set("plane_x_norm", 0.5)
	var outgoing_group := ((game.get("_gate_nodes") as Array)[0] as Control).get_parent() as Control
	var incoming_group := ((game.get("_upcoming_gate_nodes") as Array)[0] as Control).get_parent() as Control
	var active_before := float(game.get("gate_progress"))
	var until_exit := (1.0 - active_before + 0.02) / speed
	game.call("_update_gate_wave", until_exit)
	game.call("_sync_visuals")
	_check(int(game.get("waves_completed")) == 1, title + " one completed wave, no double increment")
	_check(int(game.get("attempts")) == 1, title + " exactly one score/resolution for passed gate")
	_check(not bool(game.get("gate_resolved")), title + " promoted next gate starts unresolved")
	_check((game.get("_gate_nodes") as Array)[1].get_instance_id() == stage_id,
		title + " NEXT editor-authored gate becomes active, NOT respawned")
	_check((game.get("round_data") as Dictionary).get("options", []) == next_options,
		title + " pre-seen gate words become actual scoring round")
	_check(float(game.get("gate_progress")) > 0.08,
		title + " no reset to zero / visual pop during handoff")
	_check(is_zero_approx(float(game.get("inter_wave_delay"))),
		title + " no empty delay after current gate passes")
	_check(not outgoing_group.visible and incoming_group.visible and
		((game.get("_gate_nodes") as Array)[0] as Control).get_parent() == incoming_group and
		((game.get("_upcoming_gate_nodes") as Array)[0] as Control).get_parent() == outgoing_group,
		title + " old trio hidden atomically; new trio visible with no retired ghost")
	_check(_is_opaque_trio(game.get("_gate_nodes") as Array[Control]) and
		_ring_pool_count(hybrid) == 6,
		title + " promoted answer trio and genuine six-ring pool stay fully opaque and bounded")
	_check(not events.has("results"), title + " transition does not incorrectly finish session")
	_check((game.get("used_round_words") as Dictionary).size() == 6,
		title + " handoff does not pick duplicate word set")
	# Tiny artwork-only bank/bob, never move the real hitbox or alter the PNG.
	var rig := game.get_node("PlaneRig") as Control
	var picture := game.get_node("PlaneRig/PlaneArtwork") as TextureRect
	var rig_y := rig.position.y
	var base_picture_y := picture.position.y
	game.call("set_airplane_pose_active", true)
	game.call("set_body_x", 1.0)
	game.call("_process", 0.04)
	_check(is_equal_approx(rig.position.y, rig_y), title + " artwork flight bob NEVER moves hitbox/PlaneRig Y")
	_check(absf(picture.position.y - base_picture_y) < 3.5 * size.y / 720.0,
		title + " natural airplane-only vertical bob stays within 2px design-size radius")
	_check(absf(picture.rotation) < deg_to_rad(3.2),
		title + " soft airplane bank stays within 3 degrees")
	game.call("_pause")
	var paused_art_position := picture.position
	var paused_art_rotation := picture.rotation
	game.call("_process", 3.0)
	_check(picture.position.is_equal_approx(paused_art_position) and
		is_equal_approx(picture.rotation, paused_art_rotation),
		title + " Pause also freezes subtle airplane artwork animation")
	game.call("_resume")
	# Recycle the two EXISTING trios through several more waves. A newly
	# instantiated third set, disappearing gap or duplicate word would fail.
	var previous_set := ((game.get("_gate_nodes") as Array)[1] as Control).get_instance_id()
	for target_wave in range(2, 6):
		game.set("lives", 3) # QA-only: grant life to observe repeated transitions.
		var attempts_before := int(game.get("attempts"))
		var guard := 0
		while int(game.get("waves_completed")) < target_wave and guard < 120:
			game.call("_update_gate_wave", 0.045)
			game.call("_sync_visuals")
			guard += 1
		_check(guard < 120 and int(game.get("waves_completed")) == target_wave,
			title + " uninterrupted authored transition through wave " + str(target_wave))
		_check(int(game.get("attempts")) == attempts_before + 1,
			title + " each later wave scores exactly once " + str(target_wave))
		var active_id := ((game.get("_gate_nodes") as Array)[1] as Control).get_instance_id()
		_check(active_id != previous_set and authored_ids.has(active_id),
			title + " all continuing waves alternate the original two authored gate sets")
		var active_group := ((game.get("_gate_nodes") as Array)[0] as Control).get_parent() as Control
		var standby_group := ((game.get("_upcoming_gate_nodes") as Array)[0] as Control).get_parent() as Control
		var has_next: bool = not (game.get("next_round_data") as Dictionary).is_empty()
		_check(active_group.visible and standby_group.visible == has_next and
			_is_opaque_trio(game.get("_gate_nodes") as Array[Control]) and
			(not has_next or _is_opaque_trio(game.get("_upcoming_gate_nodes") as Array[Control], true)) and
			_ring_pool_count(hybrid) == 6,
			title + " wave %d has one or two REAL fully opaque trios, never an extra ring" % target_wave)
		previous_set = active_id
		_check(float(game.get("gate_progress")) > 0.08,
			title + " every subsequent gate handoff keeps pre-existing forward progress")
		_check(is_zero_approx(float(game.get("inter_wave_delay"))),
			title + " no blank gap while recycling scene-authored gate artwork")
	_check((game.get("used_round_words") as Dictionary).size() >= 3 and
		int(game.get("_vocabulary_cycle")) >= 0,
		title + " consecutive real waves reserve genuine words; bank may legally cycle on depletion")
	# One-off test/editor call remains compatible: explicitly starting a wave
	# resets visible progress and never leaves prefetched phantom words.
	game.call("_start_wave")
	_check(is_zero_approx(float(game.get("gate_progress"))) and
		(game.get("next_round_data") as Dictionary).is_empty(),
		title + " manual _start_wave remains a fresh reset for legacy callers")
	var manual_active := ((game.get("_gate_nodes") as Array)[0] as Control).get_parent() as Control
	var manual_standby := ((game.get("_upcoming_gate_nodes") as Array)[0] as Control).get_parent() as Control
	game.call("_sync_visuals")
	_check(manual_active.visible and not manual_standby.visible and
		_is_opaque_trio(game.get("_gate_nodes") as Array[Control]),
		title + " manual reset never revives an old ghost trio")
	# Exercise authentic answer-line hit testing, not a fabricated score.
	# Select a real GrammarBank correct lane and ensure duplicate callbacks
	# cannot award the same 100 points twice.
	var scoring_round: Dictionary = game.get("round_data")
	var valid_lanes: Array = scoring_round.get("valid_indices", [])
	_check(not valid_lanes.is_empty(), title + " fresh wave offers a genuine correct grammar lane")
	if not valid_lanes.is_empty():
		var correct_lane := int(valid_lanes[0])
		var centers: PackedFloat32Array = game.call("_normalized_scoring_lane_centers",
			float(game.call("_progress_for_answer_line")))
		game.set("plane_x_norm", float(centers[correct_lane]))
		_check(int(game.call("_lane_hit_at_answer_line")) == correct_lane,
			title + " authentic plane hitbox overlaps the correct visible gate")
		var previous_score := int(game.get("score"))
		var previous_attempts := int(game.get("attempts"))
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == previous_score + 100 and
			int(game.get("attempts")) == previous_attempts + 1 and
			bool(game.get("selected_was_correct")),
			title + " genuine answer-line correct gate awards exactly +100 once")
		game.call("_sync_visuals")
		_check(_is_opaque_trio(game.get("_gate_nodes") as Array[Control]),
			title + " scored outgoing 2D plaques vanish while authentic 3D rings persist")
		game.call("_resolve_at_answer_line")
		_check(int(game.get("score")) == previous_score + 100 and
			int(game.get("attempts")) == previous_attempts + 1,
			title + " repeated collision callback cannot double-score")
	# A 3D presentation may not change the original game's STRICT completion
	# conditions. The continuous handoff tests above exercised actual collisions;
	# this ending check uses the SAME scene after its last authored wave.
	if mode == "Seconds":
		game.set("lives", 3)
		game.set("time_remaining", 0.06)
		game.call("_process", 0.03)
		_check(not bool(game.get("finished")) and not events.has("results")
			and float(game.get("time_remaining")) > 0.0,
			title + " Seconds keeps running until the full clock reaches zero")
		game.call("_process", 0.04)
		_check(bool(game.get("finished")) and events.count("results") == 1
			and is_zero_approx(float(game.get("time_remaining")))
			and int(game.get("lives")) == 3,
			title + " Seconds ends once at timer zero, with no heart deduction")
	else:
		game.set("lives", 3)
		game.set("plane_x_norm", -10.0)
		for miss in range(1, 4):
			game.call("_start_wave")
			game.call("_resolve_at_answer_line")
			_check(int(game.get("lives")) == 3 - miss
				and bool(game.get("finished")) == (miss == 3)
				and events.count("results") == (1 if miss == 3 else 0),
				title + " Lives wrong/missed gate #%d removes one heart, only zero hearts ends" % miss)
		_check(is_zero_approx(float(game.get("time_remaining"))),
			title + " Lives never acquires a hidden countdown")
	game.call("_process", 1.0)
	_check(events.count("results") == 1,
		title + " finished game never emits duplicate Results after another frame")
	game.queue_free()
	await process_frame
	await process_frame
	print("Continuous test verified ", title)


func _capture_two_wave_handoff() -> void:
	for size in SCREEN_SIZES:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(size)
		root.content_scale_size = size
		root.size = size
		var game := SCENE.instantiate() as Control
		root.add_child(game)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game.set_context({"activity": "Human Plane", "topic": "Noun",
			"difficulty": "Normal", "game_mode": "Seconds"})
		for _i in range(5):
			await process_frame
		game.set_process(false)
		for phase in ["prefetched", "handoff"]:
			if phase == "prefetched":
					game.call("_update_gate_wave", 0.83 / float(game.DIFFICULTY_CONFIG["Normal"]["gate_speed"]))
			else:
					game.call("_update_gate_wave", (1.0 - float(game.get("gate_progress")) + 0.01) / float(game.DIFFICULTY_CONFIG["Normal"]["gate_speed"]))
			game.call("_sync_visuals")
			for _i in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			var path := "user://_qa_human_continuous_%dx%d_%s.png" % [size.x, size.y, phase]
			var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
			_check(result == OK, "actual GPU screenshot generated: " + path)
			print("CONTINUOUS VISUAL ", phase, " ", size, " ", ProjectSettings.globalize_path(path))
		game.queue_free()
		await process_frame
		await process_frame


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("HUMAN-PLANE CONTINUOUS FAIL: ", description)


func _ring_pool_count(hybrid: Node2D) -> int:
	if hybrid == null:
		return 0
	var pools: Array = hybrid.get("_ring_pools")
	if pools.size() != 2:
		return 0
	var ids := {}
	for pool in pools:
		if not pool is Array or (pool as Array).size() != 3:
			return 0
		for instance in pool:
			var gate := instance as Node3D
			if gate == null or ids.has(gate.get_instance_id()):
				return 0
			var ring := gate.get_node_or_null("Ring") as MeshInstance3D
			if ring == null or not (ring.mesh is TorusMesh):
				return 0
			ids[gate.get_instance_id()] = true
	return ids.size()


func _is_opaque_trio(gates: Array[Control], upcoming: bool = false) -> bool:
	if gates.size() != 3:
		return false
	var group := gates[0].get_parent() as Control
	var game := group.get_parent() as Control if group != null else null
	if game == null or not group.visible:
		return false
	var hybrid := game.get_node_or_null("HybridFlight3D") as Node2D
	var using_3d: bool = hybrid != null and bool(hybrid.get("hybrid_enabled")) and bool(hybrid.get("draw_3d_gates"))
	var data: Dictionary = game.get("next_round_data") if upcoming else game.get("round_data")
	var options: Array = data.get("options", [])
	var valid: Array = data.get("valid_indices", [])
	if options.size() != 3 or valid.is_empty():
		return false
	var seen := {}
	var bank: Script = game.get("grammar_bank") as Script
	for i in range(3):
		var word := String(options[i]).strip_edges().to_lower()
		if (word.is_empty() or seen.has(word) or bank == null or
				bool(bank.call("is_matching", word, String(game.get("topic")))) != (i in valid)):
			return false
		seen[word] = true
	var progress := float(game.get("next_gate_progress")) if upcoming else float(game.get("gate_progress"))
	var resolved: bool = not upcoming and bool(game.get("gate_resolved"))
	var passage_alpha := float(game.call("_gate_passage_alpha", progress)) if resolved else 1.0
	if hybrid != null:
		hybrid.call("_process", 0.0)
	if using_3d:
		var overlay := hybrid.get_node_or_null("OverlayTexture") as TextureRect
		if overlay == null or not overlay.visible or overlay.texture == null or _ring_pool_count(hybrid) != 6:
			return false
	var pools: Array = hybrid.get("_ring_pools") if hybrid != null else []
	var group_index := 0 if group == game.get_node("MovingGates") else 1
	for i in range(3):
		var gate := gates[i]
		if not gate.visible or absf(gate.modulate.a - passage_alpha) > 0.002:
			return false
		var artwork := gate.get_node_or_null("GateArtwork") as TextureRect
		var word := gate.get_node_or_null("WordLabel") as Label
		var plate := gate.get_node_or_null("WordPlate") as CanvasItem
		if (artwork == null or artwork.texture == null or artwork.visible == using_3d or word == null or plate == null or
				word.visible == resolved or plate.visible == resolved or word.modulate.a < 0.999 or
				word.text != String(options[i]).to_upper()):
			return false
		if using_3d:
			var ring3d := (pools[group_index] as Array)[i] as Node3D
			if ring3d == null or ring3d.visible != (passage_alpha > 0.001):
				return false
			if not ring3d.visible:
				continue
			var mesh := ring3d.get_node_or_null("Ring") as MeshInstance3D
			if (mesh == null or not mesh.visible or not (mesh.mesh is TorusMesh) or
					not (mesh.material_override is StandardMaterial3D) or
					absf((mesh.material_override as StandardMaterial3D).albedo_color.a - passage_alpha) > 0.002 or
					ring3d.scale.x <= 0.0 or ring3d.scale.y <= 0.0):
				return false
	return true
