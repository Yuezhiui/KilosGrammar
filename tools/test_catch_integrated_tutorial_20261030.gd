extends SceneTree

# Isolated guided Catch walkthrough: Godot 4.7.2 on temp user://, NO camera,
# student API or database. Native opengl3 adds PNGs without touching scene art.
const SCENE := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const OUTPUT := "res://showcase/catch_integrated_tutorial_20261030_worker12"
const AUDIO := "res://assets/audio/tutorial_spotlight/catch_word_"

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
		root.size = resolution
		root.content_scale_size = resolution
		if native:
			DisplayServer.window_set_size(resolution)
		await process_frame
		for mode in ["Seconds", "Lives"]:
			await _case(resolution, mode, true, native)
			await _case(resolution, mode, false, false)
	if not native:
		await _stress_reentry()
	for message in failures:
		printerr("CATCH GUIDED QA FAIL: ", message)
	print("CATCH INTEGRATED TUTORIAL QA: %s checks=%d failures=%d screenshots=%d backend=%s" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), screenshots,
		DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)


func _stress_reentry() -> void:
	# 120 independent sessions exercise repeated Tutorial/Play/Skip/Back
	# without a persistent student profile or camera service.
	for cycle in range(120):
		var guided := cycle % 3 != 0
		var game := SCENE.instantiate() as Control
		if guided:
			game.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(game)
		var count := {"done": 0}
		game.tutorial_finished.connect(func() -> void: count["done"] += 1)
		game.set_context({"activity":"Catch the Word", "topic":"Noun",
			"guided_tutorial":guided, "game_mode":"Lives" if cycle % 2 else "Seconds",
			"keyboard_mode":true, "camera_live":false})
		await process_frame
		_check(game.is_tutorial_active() == guided,
			"reentry cycle %d: guide begins only for Tutorial" % cycle)
		if guided:
			for step in range(cycle % 5):
				game.tutorial_next_step()
			if cycle % 4 == 0:
				game.toggle_tutorial_voice_pause()
				game.toggle_tutorial_voice_pause()
			if cycle % 2 == 0:
				game.skip_guided_tutorial()
			else:
				while game.is_tutorial_active():
					game.tutorial_next_step()
			_check(count["done"] == 1 and not game.is_tutorial_active(),
				"reentry cycle %d: guided Next/Skip finishes once" % cycle)
			game.skip_guided_tutorial()
			_check(count["done"] == 1, "reentry cycle %d: late duplicate is inert" % cycle)
		else:
			_check(count["done"] == 0 and not game.tutorial_overlay.visible,
				"reentry cycle %d: Play has no tutorial and no finished signal" % cycle)
		game.queue_free()
		await process_frame


func _case(resolution: Vector2i, mode: String, guided: bool, native: bool) -> void:
	var tag := "%dx%d %s %s" % [resolution.x, resolution.y, mode, "tutorial" if guided else "play"]
	var game := SCENE.instantiate() as Control
	# Mirror the real gameplay wrapper: it disables the entire minigame
	# before installing a guided context and only releases it after 3-2-1.
	if guided:
		game.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var completed := {"count": 0}
	game.tutorial_finished.connect(func() -> void: completed["count"] += 1)
	game.set_context({
		"activity": "Catch the Word", "topic": "Noun", "difficulty": "Easy",
		"game_mode": mode, "guided_tutorial": guided,
		"camera_live": false, "keyboard_mode": true, "demo_mode": guided,
		"catch_character": "Bear", "catch_map": "City"
	})
	await process_frame
	await process_frame
	var overlay := game.get_node("GuidedTutorialLayer/GuidedTutorial") as Control
	var visible_layer := game.get_node("GuidedTutorialLayer") as CanvasLayer
	_check(game.is_tutorial_active() == guided and overlay.visible == guided,
		tag + ": only guided Tutorial starts component explanations")
	_check(visible_layer.visible == guided,
		tag + ": parent CanvasLayer actually shows explanations in Tutorial only")
	if not guided:
		_check(completed["count"] == 0, tag + ": regular Play never emits guide completion")
		game.queue_free()
		await process_frame
		return
	var expected: Array[String] = ["prompt", "movement", "seconds" if mode == "Seconds" else "lives", "score", "pause"]
	_check(overlay.can_process() and game.tutorial_next.can_process()
		and game.tutorial_skip.can_process() and game.tutorial_narration.can_process(),
		tag + ": embedded guide buttons and narration work while parent game is frozen")
	var initial_score: int = game.score
	var initial_lives: int = game.lives
	var initial_seconds: float = game.time_remaining
	var initial_waves: int = game.wave_index
	var before_positions: Array[Vector2] = []
	for tile in game.falling_tiles:
		before_positions.append(tile["pos"])
	for index in range(expected.size()):
		var stage: Dictionary = game._tutorial_steps()[game.tutorial_step_index]
		_check(stage["id"] == expected[index] and game.tutorial_step_index == index,
			tag + ": five ordered explanation steps, one active game-mode step at %d" % index)
		_check(String(game.tutorial_caption.text) == String(stage["caption"])
			and not game.tutorial_caption.text.is_empty(),
			tag + ": original narration script also visible as explanatory caption")
		_check(game.tutorial_overlay.visible
			and game.tutorial_focus.size.x > 20.0 and game.tutorial_focus.size.y > 20.0,
			tag + ": dark overlay and bounded highlighted HUD/character component")
		var focus_rect := Rect2(game.tutorial_focus.global_position, game.tutorial_focus.size * game.tutorial_overlay.scale)
		_check(Rect2(Vector2.ZERO, Vector2(resolution)).grow(1.0).encloses(focus_rect),
			tag + ": highlighted area fully contained in native viewport at step %d: %s" % [index, focus_rect])
		if expected[index] == "movement":
			_check(focus_rect.size.x < resolution.x * 0.34
				and focus_rect.size.y < resolution.y * 0.34
				and focus_rect.get_center().x < resolution.x * 0.70,
				tag + ": basket spotlight does not accidentally include SCORE plaque")
		_check(ResourceLoader.exists(AUDIO + expected[index] + ".wav")
			and game.tutorial_narration.stream != null,
			tag + ": authentic step-specific prerecorded narration loaded")
		_check(not game.has_node("GuidedTutorialLayer/GuidedTutorial/Arrow")
			and not game.has_node("GuidedTutorialLayer/GuidedTutorial/Arrows"),
			tag + ": directional arrows withheld for next update")
		game._process(0.9)
		_check(game.score == initial_score and game.lives == initial_lives
			and is_equal_approx(game.time_remaining, initial_seconds)
			and game.wave_index == initial_waves and game.falling_tiles.size() == before_positions.size(),
			tag + ": guidance freezes timer, wave progression, score, hearts")
		for i in range(before_positions.size()):
			_check(Vector2(game.falling_tiles[i]["pos"]) == before_positions[i],
				tag + ": word apples do not fall during explanation")
		if native and index in [0, 1, 2, 4]:
			await _capture(game, resolution, mode, expected[index])
		if index == 1:
			game.toggle_tutorial_voice_pause()
			_check(game.tutorial_voice_paused and game.tutorial_narration.stream_paused,
				tag + ": Pause Voice stops narration without routing/game movement")
			game.toggle_tutorial_voice_pause()
			_check(not game.tutorial_voice_paused and not game.tutorial_narration.stream_paused,
				tag + ": Resume Voice continues current narration")
		if index == 2:
			game.tutorial_previous_step()
			_check(game.tutorial_step_index == 1, tag + ": Back returns to movement and replays voice")
			game.tutorial_next_step()
			_check(game.tutorial_step_index == 2, tag + ": Next restores mode step")
		if index != expected.size() - 1:
			game.tutorial_next_step()
	_check(completed["count"] == 0 and game.is_tutorial_active(),
		tag + ": countdown cannot begin before all five explanations")
	game.tutorial_next_step()
	_check(completed["count"] == 1 and not game.is_tutorial_active()
		and not overlay.visible and not visible_layer.visible,
		tag + ": finishing last explanation emits one countdown request")
	game.tutorial_next_step()
	game.skip_guided_tutorial()
	_check(completed["count"] == 1, tag + ": duplicate Next/Skip cannot re-trigger countdown")
	_check(game.score == initial_score and game.lives == initial_lives
		and is_equal_approx(game.time_remaining, initial_seconds),
		tag + ": leaving guide preserves original untouched game state")
	game.queue_free()
	await process_frame
	# Independent fresh scene tests skip flow.
	var skipped := SCENE.instantiate() as Control
	root.add_child(skipped)
	skipped.set_context({"activity":"Catch the Word", "guided_tutorial":true,
		"game_mode":mode, "camera_live":false, "keyboard_mode":true})
	await process_frame
	var skip_count := {"count": 0}
	skipped.tutorial_finished.connect(func() -> void: skip_count["count"] += 1)
	skipped.skip_guided_tutorial()
	_check(skip_count["count"] == 1 and not skipped.tutorial_overlay.visible,
		tag + ": Skip immediately exits explanations with exactly one countdown request")
	skipped.queue_free()
	await process_frame


func _capture(_game: Control, resolution: Vector2i, mode: String, step: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var filename := "%s_%s_%dx%d.png" % [mode.to_lower(), step, resolution.x, resolution.y]
	var path := ProjectSettings.globalize_path(OUTPUT.path_join(filename))
	var saved := frame.save_png(path)
	_check(saved == OK and frame.get_size() == resolution,
		"native screenshot " + filename + " saved with correct frame size")
	if saved == OK:
		screenshots += 1
		print("CATCH_GUIDE_CAPTURE ", path)


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
