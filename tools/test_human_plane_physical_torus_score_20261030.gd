extends SceneTree

# Offline scoring regression: the real airplane AND torus have editable 3D
# collision volumes; only a full, unique passage on the answer-line Z plane
# can earn +100. No live camera, student API, or PostgreSQL access.
const GAME := preload("res://ui/minigames/human_plane/human_plane.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var checks := 0
var failures: Array[String] = []
var captures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dims in SIZES:
		for mode in ["Seconds", "Lives"]:
			await _exercise(dims, mode)
	print("PHYSICAL 3D TORUS +100 / +0: %s checks=%d failures=%d gpu_captures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), captures])
	quit(0 if failures.is_empty() else 1)


func _exercise(dims: Vector2i, mode: String) -> void:
	root.size = dims
	root.content_scale_size = dims
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(dims)
	var game := GAME.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity": "Human Plane", "topic": "Noun", "game_mode": mode,
		"difficulty": "Normal"})
	for _frame in range(3):
		await process_frame
	game.set_process(false)
	game.set_airplane_pose_active(true)
	var hybrid := game.get_node("HybridFlight3D") as Node2D
	hybrid.set_process(false)
	var label := "%dx%d/%s" % [dims.x, dims.y, mode]
	var airplane := hybrid.get_node("RenderViewport/FlightWorld3D/PlaneAnchor/PlanePassageHitbox/HitShape") as CollisionShape3D
	_check(airplane.shape is SphereShape3D, label + " authentic plane collision sphere")
	for lane in range(3):
		var ring := hybrid.get_node("RenderViewport/FlightWorld3D/Gates/Gate%s/RingPassageHitbox/HitShape" % ["Left", "Center", "Right"][lane]) as CollisionShape3D
		_check(ring.shape is CylinderShape3D, label + " lane%d real hollow passage collider" % lane)
	var progress := float(game.call("_progress_for_answer_line"))
	var centers: PackedFloat32Array = game.call("_normalized_scoring_lane_centers", progress)
	_check(centers.size() == 3, label + " all three authored rings have reachable centers")
	if centers.size() != 3:
		game.queue_free()
		await process_frame
		return

	for cycle in range(6):
		for lane in range(3):
			game.call("_start_wave")
			var wave: Dictionary = (game.round_data as Dictionary).duplicate(true)
			wave["valid_indices"] = [lane]
			game.round_data = wave
			game.plane_x_norm = centers[lane]
			game.call("_sync_visuals")
			hybrid.call("_process", 0.0)
			_check(int(hybrid.call("physical_lane_at_answer_line")) == lane,
				label + " cycle%d lane%d centered aircraft physically fits torus" % [cycle, lane])
			if cycle == 0:
				game.plane_x_norm = clampf(centers[lane] + 0.007, 0.0, 1.0)
				_check(int(hybrid.call("physical_lane_at_answer_line")) == lane,
					label + " lane%d full wing span clears near-center ring opening" % lane)
				game.plane_x_norm = clampf(centers[lane] + 0.03, 0.0, 1.0)
				_check(int(hybrid.call("physical_lane_at_answer_line")) == -1,
					label + " lane%d wing touching torus tube cannot score" % lane)
				game.plane_x_norm = centers[lane]
			var before := int(game.score)
			var before_attempts := int(game.attempts)
			var before_boosts := int(game.speed_boost_count)
			for _frame in range(250):
				if bool(game.gate_resolved):
					break
				game.call("_update_gate_wave", 1.0 / 60.0)
				game.call("_sync_visuals")
				hybrid.call("_process", 0.0)
			_check(game.gate_resolved and int(game.score) == before + 100 and
				int(game.selected_lane) == lane and int(game.attempts) == before_attempts + 1,
				label + " cycle%d lane%d real Z crossing awards exactly +100" % [cycle, lane])
			_check(int(game.speed_boost_count) == before_boosts + 1 and
				(game.get_node("ScoreFeedbackLayer/FloatingScore") as Label).text == "+100",
				label + " cycle%d lane%d boost and live score pop" % [cycle, lane])
			if cycle == 0 and lane == 1 and mode == "Seconds":
				await _capture(dims, "correct_plus100")
			game.call("_resolve_at_answer_line")
			_check(int(game.score) == before + 100 and int(game.attempts) == before_attempts + 1,
				label + " cycle%d lane%d crossing can never pay twice" % [cycle, lane])

	for lane in range(3):
		game.call("_start_wave")
		if mode == "Lives":
			game.lives = 3
		var wave: Dictionary = (game.round_data as Dictionary).duplicate(true)
		wave["valid_indices"] = [lane]
		game.round_data = wave
		game.plane_x_norm = centers[(lane + 1) % 3]
		var before := int(game.score)
		game.call("_resolve_at_answer_line")
		_check(int(game.selected_lane) == (lane + 1) % 3 and int(game.score) == before and
			(game.get_node("ScoreFeedbackLayer/FloatingScore") as Label).text == "+0",
			label + " lane%d entering incorrect ring scores +0" % lane)
		if lane == 1 and mode == "Seconds":
			await _capture(dims, "wrong_plus0")
		game.call("_start_wave")
		if mode == "Lives":
			game.lives = 3
		wave = (game.round_data as Dictionary).duplicate(true)
		wave["valid_indices"] = [lane]
		game.round_data = wave
		game.plane_x_norm = 0.0
		game.call("_resolve_at_answer_line")
		_check(int(game.selected_lane) == -1 and int(game.score) == before,
			label + " lane%d physical miss cannot grant points" % lane)

	# Adjacent authored rings meet at their edges but a plane touching both
	# torus tubes is never rewarded; use the same world-space geometric test.
	for lane in range(2):
		game.plane_x_norm = (centers[lane] + centers[lane + 1]) * 0.5
		_check(int(hybrid.call("physical_lane_at_answer_line")) == -1,
			label + " lanes%d-%d edge contact has no physically clear passage" % [lane, lane + 1])

	# A lost solo student, lowered arm, or camera occlusion MUST withhold points
	# even if the last rendered airplane remains centered on the correct hole.
	game.call("_start_wave")
	if mode == "Lives":
		game.lives = 3
	var valid: int = int((game.round_data.get("valid_indices", [0]) as Array)[0])
	game.plane_x_norm = centers[valid]
	game.set_airplane_pose_active(false)
	_check(int(hybrid.call("physical_lane_at_answer_line")) == -1,
		label + " lowered/occluded both-arm pose cannot select a correct portal")
	var untracked_before := int(game.score)
	game.call("_resolve_at_answer_line")
	_check(int(game.score) == untracked_before and game.selected_lane == -1,
		label + " lost tracked student grants +0 even when ghost plane is centered")
	game.set_airplane_pose_active(true)

	# Guided tutorial is embedded in the game scene and must freeze a live
	# round, advance six component spotlights and expose no arrow artwork.
	var previous_progress := float(game.gate_progress)
	var previous_score := int(game.score)
	game.call("_sync_visuals")
	hybrid.call("_process", 0.0)
	game.call("begin_guided_tutorial")
	hybrid.call("_process", 0.0)
	game.call("_layout_tutorial_spotlight")
	game.process_mode = Node.PROCESS_MODE_DISABLED
	_check(game.call("is_tutorial_active") and not game.running and
		game.get_node("TutorialSpotlightLayer/TutorialSpotlight").visible,
		label + " embedded guided tutorial freezes gameplay and opens spotlight")
	var skip := game.get_node("TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide/SkipButton") as Button
	var next := game.get_node("TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide/NextButton") as Button
	var back := game.get_node("TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide/BackButton") as Button
	var replay := game.get_node("TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide/ReplayButton") as Button
	var pause_voice := game.get_node("TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide/PauseVoiceButton") as Button
	var voice := game.get_node("TutorialSpotlightLayer/TutorialNarration") as AudioStreamPlayer
	_check(skip.can_process() and next.can_process() and back.can_process() and
		replay.can_process() and pause_voice.can_process() and voice.can_process(),
		label + " Next Skip Back Replay Pause Voice and narration process despite disabled game wrapper")
	_check(back.disabled and voice.stream != null and voice.playing,
		label + " initial movement voice starts and previous-step button is disabled")
	var actual_plane: Rect2 = hybrid.call("get_airplane_highlight_rect")
	var highlighted_plane := game.get_node("TutorialSpotlightLayer/TutorialSpotlight/HighlightOutline") as Control
	_check(highlighted_plane.get_global_rect().intersects(actual_plane),
		label + " movement spotlight tracks actual 3D airplane, never invisible 2D rig")
	if mode == "Seconds":
		await _capture(dims, "tutorial_movement")
	for step in range(6):
		var outline := game.get_node("TutorialSpotlightLayer/TutorialSpotlight/HighlightOutline") as Control
		_check(outline.size.x > 0.0 and outline.size.y > 0.0,
			label + " step%d focused component has a visible cutout" % step)
		_check(not game.get_node("TutorialSpotlightLayer/TutorialSpotlight/TutorialArrow").visible,
			label + " step%d future arrow remains hidden" % step)
		var audio_type := String(["movement", "ring", "prompt", "mode", "score", "pause"][step])
		if audio_type == "mode":
			audio_type = "seconds" if mode == "Seconds" else "lives"
		var audio_path := "res://assets/audio/tutorial_spotlight/human_plane_" + audio_type + ".wav"
		_check(ResourceLoader.exists(audio_path) and voice.stream != null,
			label + " step%d original recorded narration available for %s" % [step, audio_type])
		if step == 1:
			var expected_ring: Rect2 = hybrid.call("get_ring_highlight_rect", 1)
			_check(outline.get_global_rect().intersects(expected_ring),
				label + " ring spotlight tracks actual TorusMesh aperture")
			back.pressed.emit()
			_check(int(game.get("_tutorial_step")) == 0 and back.disabled,
				label + " Back moves to real previous component without unfreezing game")
			next.pressed.emit()
			_check(int(game.get("_tutorial_step")) == 1 and not back.disabled,
				label + " Next returns to ring explanation without skipping countdown")
			if mode == "Seconds":
				await _capture(dims, "tutorial_ring")
		if step == 2:
			pause_voice.pressed.emit()
			_check(voice.stream_paused and pause_voice.text == "RESUME VOICE",
				label + " Pause Voice stops narration audio while leaving panel interactive")
			pause_voice.pressed.emit()
			_check(not voice.stream_paused and pause_voice.text == "PAUSE VOICE",
				label + " Resume Voice continues original narration")
			replay.pressed.emit()
			_check(voice.playing and not voice.stream_paused,
				label + " Replay Voice restarts current recorded clip")
			if mode == "Seconds":
				await _capture(dims, "tutorial_prompt")
		if step < 5:
			game.call("_next_tutorial_step")
			if step == 3 and mode == "Seconds":
				await _capture(dims, "tutorial_score")
	_check(int(game.score) == previous_score and is_equal_approx(float(game.gate_progress), previous_progress),
		label + " tutorial explanations never affect score or wave progression")
	game.call("_next_tutorial_step")
	_check(not game.call("is_tutorial_active") and not game.running and
		not game.get_node("TutorialSpotlightLayer/TutorialSpotlight").visible and
		not voice.playing and not voice.stream_paused,
		label + " step6 completes tutorial and leaves countdown with router")
	game.queue_free()
	await process_frame
	await process_frame


func _capture(dims: Vector2i, stage: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	for _frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://showcase/qa_human_plane_physical_20261030")
	_check(DirAccess.make_dir_recursive_absolute(folder) == OK, "GPU capture output folder available")
	var dest := folder.path_join("%dx%d_%s.png" % [dims.x, dims.y, stage])
	var image := root.get_texture().get_image()
	var okay := image != null and not image.is_empty() and image.save_png(dest) == OK
	_check(okay, "GPU screenshot %dx%d %s saved" % [dims.x, dims.y, stage])
	if okay:
		captures += 1
		print("PHYSICAL TORUS GPU CAPTURE ", dest)


func _check(value: bool, reason: String) -> void:
	checks += 1
	if not value:
		failures.append(reason)
		printerr("PHYSICAL TORUS FAIL: ", reason)
