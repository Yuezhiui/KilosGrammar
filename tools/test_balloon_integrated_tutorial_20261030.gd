extends SceneTree

# Isolated component tutorial regression for Balloon Popping. No camera, API,
# student identity, or live database; optional real OpenGL screenshots.
const SCENE := preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const AUDIO_ROOT := "res://assets/audio/tutorial_spotlight/balloon_popping_"
const OUTPUT := "user://worker2_balloon_cartoon_tutorial_20261030"

var checks := 0
var failures: Array[String] = []
var screenshots := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var native := DisplayServer.get_name() != "headless"
	if native:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for resolution in RESOLUTIONS:
		root.content_scale_size = resolution
		root.size = resolution
		if native:
			DisplayServer.window_set_size(resolution)
		await process_frame
		for mode in ["Seconds", "Lives"]:
			await _case(resolution, mode, true, native)
			await _case(resolution, mode, false, false)
	await _material_isolation_case()
	for reason in failures:
		printerr("BALLOON GUIDED QA FAIL: ", reason)
	print("BALLOON INTEGRATED TUTORIAL QA: %s checks=%d failures=%d screenshots=%d backend=%s" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(),
		screenshots, DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)


func _case(resolution: Vector2i, mode: String, guided: bool, native: bool) -> void:
	var tag := "%dx%d %s %s" % [resolution.x, resolution.y, mode,
		"tutorial" if guided else "normal Play"]
	var game := SCENE.instantiate() as Control
	# Match router ordering: the wrapper freezes the game before first frame.
	if guided:
		game.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var counts := {"finished": 0, "routes": 0}
	game.tutorial_finished.connect(func() -> void: counts["finished"] += 1)
	game.requested.connect(func(_route: String, _payload: Dictionary) -> void:
		counts["routes"] += 1)
	game.set_context({
		"activity": "Balloon Popping", "topic": "Noun", "difficulty": "Normal",
		"game_mode": mode, "guided_tutorial": guided, "camera_live": false,
		"keyboard_mode": true, "score": 0, "attempts": 0
	})
	await process_frame
	await process_frame
	var overlay := game.get_node("GuidedTutorialLayer/GuidedTutorial") as Control
	_check(game.is_tutorial_active() == guided and overlay.visible == guided,
		tag + ": guide activates only when explicitly requested")
	if not guided:
		_check(counts["finished"] == 0 and game.timer_running and game.round_active,
			tag + ": normal Play runs without tutorial or completion signal")
		game.queue_free()
		await process_frame
		return
	_check(overlay.can_process() and game.tutorial_next.can_process()
		and game.tutorial_skip.can_process() and game.tutorial_narration.can_process(),
		tag + ": editor-authored guide works while wrapper freezes game")
	var initial_score: int = game.score
	var initial_hearts: int = game.hearts
	var initial_seconds: float = game.time_remaining
	var initial_round: int = game.round_index
	var before_locations: Array[Vector2] = []
	for target in game.balloons:
		if is_instance_valid(target):
			before_locations.append(target.position)
	var expected := ["prompt", "movement", "seconds" if mode == "Seconds" else "lives",
		"score", "pause"]
	for i in range(expected.size()):
		var entry: Dictionary = game._tutorial_steps()[game.tutorial_step_index]
		_check(String(entry["id"]) == expected[i] and game.tutorial_step_index == i,
			tag + ": step %d explains %s" % [i + 1, expected[i]])
		_check(not game.tutorial_caption.text.is_empty()
			and game.tutorial_caption.text == String(entry["caption"]),
			tag + ": narration text is readable on the card")
		_check(game.tutorial_counter.text == "STEP %d OF 5" % [i + 1]
			and (game.tutorial_overlay.get_node("TutorialCard/PanelArt") as TextureRect).texture != null,
			tag + ": numbered cartoon art is loaded for " + expected[i])
		_check_cartoon_controls(game, tag + " " + expected[i], i == expected.size() - 1)
		_check(overlay.visible and game.tutorial_focus.size.x > 30.0
			and game.tutorial_focus.size.y > 20.0,
			tag + ": real art spotlight is bounded and overlay visible at %s" % expected[i])
		var bounds := Rect2(game.tutorial_focus.global_position,
			game.tutorial_focus.size * overlay.scale)
		_check(Rect2(Vector2.ZERO, Vector2(resolution)).grow(1.0).encloses(bounds),
			tag + ": spotlight stays inside physical viewport at %s: %s" % [expected[i], bounds])
		_check(ResourceLoader.exists(AUDIO_ROOT + expected[i] + ".wav")
			and game.tutorial_narration.stream != null,
			tag + ": authentic narration WAV loads for " + expected[i])
		_check(not game.has_node("GuidedTutorialLayer/GuidedTutorial/Arrow")
			and not game.has_node("GuidedTutorialLayer/GuidedTutorial/Arrows"),
			tag + ": directional arrows remain absent")
		game._process(0.95)
		game._physics_process(0.95)
		_check(initial_score == game.score and initial_hearts == game.hearts
			and is_equal_approx(initial_seconds, game.time_remaining)
			and initial_round == game.round_index and game.attempts == 0,
			tag + ": score, hearts, timer, shots and rounds remain frozen at " + expected[i])
		var after_locations: Array[Vector2] = []
		for target in game.balloons:
			if is_instance_valid(target):
				after_locations.append(target.position)
		_check(before_locations == after_locations,
			tag + ": balloons do not advance during " + expected[i])
		_check(not game.set_hand_raise_state(true, true, 3000 + i * 1000),
			tag + ": camera gesture cannot shoot during narration")
		if native and i in [0, 1, 2, 4]:
			await _capture(resolution, mode, expected[i])
		if i == 1:
			game.toggle_tutorial_voice_pause()
			_check(game.tutorial_voice_paused and game.tutorial_narration.stream_paused,
				tag + ": Pause Voice freezes current narration")
			game.toggle_tutorial_voice_pause()
			_check(not game.tutorial_voice_paused and not game.tutorial_narration.stream_paused,
				tag + ": Resume Voice continues clip")
			game.replay_tutorial_voice()
			_check(not game.tutorial_voice_paused and game.tutorial_narration.stream != null,
				tag + ": Replay Voice restarts available clip")
		if i == 2:
			game.tutorial_previous_step()
			_check(game.tutorial_step_index == 1, tag + ": Back returns to movement")
			game.tutorial_next_step()
			_check(game.tutorial_step_index == 2, tag + ": Next re-enters mode step")
		if i < expected.size() - 1:
			game.tutorial_next_step()
	_check(counts["finished"] == 0 and game.is_tutorial_active(),
		tag + ": countdown cannot start during narration")
	game.tutorial_next_step()
	_check(counts["finished"] == 1 and not game.is_tutorial_active() and not overlay.visible,
		tag + ": last explanation sends exactly one countdown-ready signal")
	game.skip_guided_tutorial()
	game.tutorial_next_step()
	_check(counts["finished"] == 1 and counts["routes"] == 0,
		tag + ": duplicate controls never route or repeat countdown")
	_check(game.score == initial_score and game.hearts == initial_hearts
		and is_equal_approx(game.time_remaining, initial_seconds),
		tag + ": exiting tutorial does not fabricate a score or lost heart")
	game.queue_free()
	await process_frame

	var skipped := SCENE.instantiate() as Control
	root.add_child(skipped)
	skipped.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skipped.set_context({"guided_tutorial": true, "game_mode": mode,
		"topic": "Noun", "difficulty": "Normal"})
	await process_frame
	var skips := {"count": 0}
	skipped.tutorial_finished.connect(func() -> void: skips["count"] += 1)
	skipped.skip_guided_tutorial()
	_check(skips["count"] == 1 and not skipped.is_tutorial_active()
		and not skipped.tutorial_overlay.visible,
		tag + ": Skip closes the guide immediately and requests countdown once")
	skipped.queue_free()
	await process_frame


func _material_isolation_case() -> void:
	# Two games may briefly coexist during Play/Tutorial transitions. Their
	# spotlight rectangles must never share a mutable material uniform.
	var games: Array[Control] = []
	for mode in ["Seconds", "Lives"]:
		var game := SCENE.instantiate() as Control
		game.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(game)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game.set_context({"guided_tutorial": true, "game_mode": mode,
			"topic": "Noun", "difficulty": "Normal"})
		games.append(game)
	await process_frame
	await process_frame
	var first_material := games[0].tutorial_dim.material as ShaderMaterial
	var second_material := games[1].tutorial_dim.material as ShaderMaterial
	_check(first_material != second_material,
		"simultaneous guide scenes have independent shader materials")
	var second_focus: Vector4 = second_material.get_shader_parameter("focus_rect")
	games[0].tutorial_next_step()
	_check(second_material.get_shader_parameter("focus_rect") == second_focus,
		"advancing first guide never moves second guide's focus")
	for game in games:
		game.queue_free()
	await process_frame


func _check_cartoon_controls(game: Control, tag: String, final_step: bool) -> void:
	var card := game.tutorial_overlay.get_node("TutorialCard") as Control
	for name in ["BackButton", "NextButton", "ReplayButton", "SkipButton"]:
		var button := card.get_node(name) as Button
		var image_name: String = String(name).trim_suffix("Button") + "Art"
		var art := button.get_node(image_name) as TextureRect
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			_check(button.get_theme_stylebox(state) is StyleBoxEmpty,
				tag + ": " + name + " has no old Godot " + state + " background")
		_check(art.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and button.mouse_filter == Control.MOUSE_FILTER_STOP
			and art.size.distance_to(button.size) < 1.0,
			tag + ": " + name + " image ignores mouse and hitbox matches artwork")
		_check(Rect2(Vector2.ZERO, card.size).grow(1.0).encloses(button.get_rect()),
			tag + ": " + name + " keeps its entire active rectangle inside card")
		game.call("_set_tutorial_art_hover", button, true)
		_check((art.modulate != Color.WHITE) == (not button.disabled),
			tag + ": " + name + " hover respects active/disabled state")
		game.call("_set_tutorial_art_hover", button, false)
		_check(art.modulate == Color.WHITE,
			tag + ": " + name + " hover restores original cartoon colors")
	var next := game.tutorial_next as Button
	var plate := next.get_node("StartPlate") as Panel
	var next_art := next.get_node("NextArt") as TextureRect
	_check(plate.visible == final_step and next_art.visible != final_step,
		tag + ": illustrated NEXT swaps to readable green START plate only on final step")
	_check((plate.get_node("StartLabel") as Label).text == "START" and
		plate.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		tag + ": START plate text and non-blocking mouse input")
	var pause_voice := game.tutorial_pause_voice as Button
	_check(pause_voice.get_theme_stylebox("normal") is StyleBoxFlat and
		pause_voice.get_theme_stylebox("pressed") is StyleBoxFlat and
		pause_voice.text in ["PAUSE VOICE", "RESUME VOICE"],
		tag + ": native PAUSE/RESUME VOICE remains readable and clickable")


func _capture(resolution: Vector2i, mode: String, stage: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	var filename := "%s_%s_%dx%d.png" % [mode.to_lower(), stage, resolution.x, resolution.y]
	var saved := shot.save_png(ProjectSettings.globalize_path(OUTPUT.path_join(filename)))
	_check(saved == OK and shot.get_size() == resolution, "native PNG " + filename)
	if saved == OK:
		screenshots += 1
		print("BALLOON_GUIDE_CAPTURE ", ProjectSettings.globalize_path(OUTPUT.path_join(filename)))


func _check(success: bool, description: String) -> void:
	checks += 1
	if not success:
		failures.append(description)
