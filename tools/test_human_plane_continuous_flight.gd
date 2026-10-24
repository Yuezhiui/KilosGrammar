extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_continuous_flight.gd
# No fake gate nodes: tests the two serialized gate sets through real scenes.
const SCENE := preload("res://ui/minigames/human_plane.tscn")
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
	var initial_options: Array = (game.get("round_data") as Dictionary).get("options", [])
	_check(initial_options.size() == 3, title + " first word set contains 3 choices")
	_check(int(game.get("lives")) == 3, title + " exactly three available hearts")
	_check((game.get_node("HUDLayer/HUD/TimeLabel") as Label).visible == (mode == "Seconds"),
		title + " timer visibility respects Seconds/Lives")
	_check((game.get_node("HUDLayer/HUD/LivesPlaque") as TextureRect).visible == (mode == "Lives"),
		title + " native Lives plaque visibility respects mode")
	_check(float(game.get("time_remaining")) > 59.0 if mode == "Seconds"
		else is_zero_approx(float(game.get("time_remaining"))), title + " native mode time unchanged")
	_check(not upcoming.visible, title + " upcoming trio correctly hidden until first prefetch")
	var speed := float(game.DIFFICULTY_CONFIG[difficulty]["gate_speed"])
	var to_preview := (float(game.GATE_PREFETCH_AT) + 0.02) / speed
	game.call("_update_gate_wave", to_preview)
	game.call("_sync_visuals")
	var next_words: Dictionary = game.get("next_round_data")
	_check(not next_words.is_empty() and (next_words.get("options", []) as Array).size() == 3,
		title + " prefetch draws all three next answers BEFORE current gate completes")
	_check(upcoming.visible and upcoming.get_node("GateCenter").is_visible_in_tree(),
		title + " upcoming set visibly exists behind active set BEFORE handoff")
	var current_y: float = ((game.get("_gate_nodes") as Array)[1] as Control).get_rect().get_center().y
	var next_y: float = ((game.get("_upcoming_gate_nodes") as Array)[1] as Control).get_rect().get_center().y
	_check(next_y < current_y - 10.0, title + " upcoming gates are visibly farther away")
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
	var before_rect: Rect2 = (upcoming.get_node("GateCenter") as Control).get_rect()
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
	_check(float(game.get("next_gate_progress")) > before_progress and
		upcoming.get_node("GateCenter").get_rect().get_center().y > before_rect.get_center().y,
		title + " already visible next set continues gliding (not static)")
	# Turn progress to the boundary, exercising one scoring event and the
	# already-visible gate trio handoff. Artificially keep lives sufficient so
	# every difficulty can demonstrate transition.
	game.set("plane_x_norm", 0.5)
	var active_before := float(game.get("gate_progress"))
	var until_exit := (1.0 - active_before + 0.02) / speed
	game.call("_update_gate_wave", until_exit)
	game.call("_sync_visuals")
	_check(int(game.get("waves_completed")) == 1, title + " one completed wave, no double increment")
	_check(int(game.get("attempts")) == 1, title + " exactly one score/resolution for passed gate")
	_check(not bool(game.get("gate_resolved")), title + " promoted next gate starts unresolved")
	_check((game.get("_gate_nodes") as Array)[1].get_instance_id() == stage_id,
		title + " NEXT editor-authored visible gate becomes active, NOT respawned")
	_check((game.get("round_data") as Dictionary).get("options", []) == next_options,
		title + " pre-seen gate words become actual scoring round")
	_check(float(game.get("gate_progress")) > 0.08,
		title + " no reset to zero / visual pop during handoff")
	_check(is_zero_approx(float(game.get("inter_wave_delay"))),
		title + " no empty delay after current gate passes")
	_check((game.get("_retiring_gate_nodes") as Array).size() == 3 and
		float(game.get("_retiring_gate_fade")) > 0.0,
		title + " passing gates fade/exit while next is already visible")
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
		previous_set = active_id
		_check(float(game.get("gate_progress")) > 0.08,
			title + " every subsequent gate handoff keeps pre-existing forward progress")
		_check(is_zero_approx(float(game.get("inter_wave_delay"))),
			title + " no blank gap while recycling scene-authored gate artwork")
	_check((game.get("used_round_words") as Dictionary).size() >= 18,
		title + " at least 18 different choices reserved across 6 consecutive waves")
	# One-off test/editor call remains compatible: explicitly starting a wave
	# resets visible progress and never leaves prefetched phantom words.
	game.call("_start_wave")
	_check(is_zero_approx(float(game.get("gate_progress"))) and
		(game.get("next_round_data") as Dictionary).is_empty(),
		title + " manual _start_wave remains a fresh reset for legacy callers")
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
