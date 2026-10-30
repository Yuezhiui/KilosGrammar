extends SceneTree

const WRAPPER_PATH := "res://ui/play/gameplay/gameplay.tscn"
const DIMENSIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const QA_OUTPUT := "user://worker2_human_cartoon_tutorial_20261030"
var failures: Array[String] = []
var checks := 0
var screenshots := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var wrapper_scene := load(WRAPPER_PATH) as PackedScene
	var native := DisplayServer.get_name() != "headless"
	if native:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(QA_OUTPUT))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for dims in DIMENSIONS:
		for mode in ["Seconds", "Lives"]:
			root.size = dims
			root.content_scale_size = dims
			if native:
				DisplayServer.window_set_size(dims)
			var wrapper := wrapper_scene.instantiate() as Control
			root.add_child(wrapper)
			wrapper.set_context({"activity": "Human Plane", "game_mode": mode,
				"topic": "Noun", "difficulty": "Easy", "guided_tutorial": true,
				"camera_live": false, "start_countdown": true})
			for i in range(4):
				await process_frame
			var game := wrapper.get("active_game") as Control
			if game == null:
				_check(false, "%s/%s wrapper failed to mount game" % [dims, mode])
				wrapper.queue_free()
				await process_frame
				continue
			var hybrid := game.get_node("HybridFlight3D") as Node2D
			var plane := game.get_node("PlaneRig") as Control
			var overlay := game.get_node("TutorialSpotlightLayer/TutorialSpotlight") as Control
			var outline := overlay.get_node("HighlightOutline") as Control
			var guide := overlay.get_node("TutorialGuide") as Control
			_check((guide.get_node("PanelArt") as TextureRect).texture != null
				and (guide.get_node("TutorialStar") as TextureRect).texture != null,
				"%s/%s shared cartoon panel artwork loaded" % [dims, mode])
			var score_before: int = int(game.get("score"))
			var time_before: float = float(game.get("time_remaining"))
			_check(bool(game.call("is_tutorial_active")) and not bool(game.get("running")),
				"%s/%s freezes game before countdown" % [dims, mode])
			for index in range(6):
				var target_name: String = String(game.TUTORIAL_COMPONENTS[index]["target"])
				var target_rect := Rect2()
				if target_name == "PlaneRig":
					target_rect = game.call("_tutorial_canvas_rect", hybrid.call("get_airplane_highlight_rect"))
					_check(outline.size.x < plane.get_global_rect().size.x,
						"%s/%s plane spotlight excludes oversized 2D PlaneRig" % [dims, mode])
				elif target_name == "ring":
					target_rect = game.call("_tutorial_canvas_rect", game.call("_tutorial_projected_ring_mesh_rect", 1))
					_check(target_rect.size.x > 20.0 and target_rect.size.y > 20.0,
						"%s/%s actual projected 3D TorusMesh is measurable" % [dims, mode])
				elif target_name == "mode":
					var path := "HUDLayer/HUD/TimerPlaque" if mode == "Seconds" else "HUDLayer/HUD/LivesPlaque"
					target_rect = game.call("_tutorial_control_rect", game.get_node(path))
				else:
					target_rect = game.call("_tutorial_control_rect", game.get_node(target_name))
				var rect := outline.get_rect()
				var padding := maxf(overlay.size.y / 720.0 * 9.0, 5.0)
				var expected := target_rect.grow(padding).intersection(Rect2(Vector2.ZERO, overlay.size))
				_check(expected.position.distance_to(rect.position) < 2.0 and
					expected.size.distance_to(rect.size) < 2.0,
					"%s/%s step %d matches native component geometry" % [dims, mode, index + 1])
				_check((guide.get_node("StepCounter") as Label).text == "STEP %d OF 6" % [index + 1],
					"%s/%s step %d text counter" % [dims, mode, index + 1])
				_check_cartoon_controls(game, guide, "%s/%s step %d" % [dims, mode, index + 1],
					index == 5)
				_check(not (overlay.get_node("TutorialArrow") as Control).visible,
					"%s/%s step %d arrows invisible" % [dims, mode, index + 1])
				_check(guide.get_rect().intersection(rect).get_area() < rect.get_area() * 0.30,
					"%s/%s step %d cartoon guide leaves focus clear" % [dims, mode, index + 1])
				_check(wrapper.get("countdown_panel") == null and int(game.get("score")) == score_before
					and is_equal_approx(float(game.get("time_remaining")), time_before),
					"%s/%s step %d stays before countdown and preserves score" % [dims, mode, index + 1])
				if native and index in [0, 1, 3, 5]:
					await RenderingServer.frame_post_draw
					var shot := root.get_texture().get_image()
					var filename := "%s_%dx%d_step%d.png" % [mode.to_lower(), dims.x, dims.y, index + 1]
					var filepath := ProjectSettings.globalize_path(QA_OUTPUT.path_join(filename))
					var saved := shot.save_png(filepath)
					_check(saved == OK and shot.get_size() == dims, "native screenshot " + filename)
					if saved == OK:
						screenshots += 1
						print("HUMAN_CARTOON_CAPTURE ", filepath)
				if index < 5:
					game.call("_next_tutorial_step")
			_check(bool(game.call("is_tutorial_active")),
				"%s/%s countdown cannot precede final next" % [dims, mode])
			game.call("_next_tutorial_step")
			_check(not bool(game.call("is_tutorial_active")) and not overlay.visible,
				"%s/%s final next closes guide" % [dims, mode])
			wrapper.queue_free()
			await process_frame
			await process_frame
	print("HUMAN PLANE WRAPPER SPOTLIGHT: %s checks=%d failures=%d screenshots=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), screenshots])
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("HUMAN PLANE SPOTLIGHT FAIL: ", message)


func _check_cartoon_controls(game: Control, guide: Control, tag: String, final_step: bool) -> void:
	for name in ["BackButton", "NextButton", "ReplayButton", "SkipButton"]:
		var button := guide.get_node(name) as Button
		var image_name: String = String(name).trim_suffix("Button") + "Art"
		var art := button.get_node(image_name) as TextureRect
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			_check(button.get_theme_stylebox(state) is StyleBoxEmpty,
				tag + ": " + name + " no redundant " + state + " background")
		_check(art.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and button.mouse_filter == Control.MOUSE_FILTER_STOP
			and art.size.distance_to(button.size) < 1.0,
			tag + ": " + name + " art doesn't obstruct full active hitbox")
		_check(Rect2(Vector2.ZERO, guide.size).grow(2.0).encloses(button.get_rect()),
			tag + ": " + name + " stays inside cartoon guide margins")
		game.call("_set_tutorial_art_hover", button, true)
		_check((art.modulate != Color.WHITE) == (not button.disabled),
			tag + ": " + name + " shows hover only while enabled")
		game.call("_set_tutorial_art_hover", button, false)
		_check(art.modulate == Color.WHITE,
			tag + ": " + name + " restores original artwork on exit")
	var next := guide.get_node("NextButton") as Button
	var plate := next.get_node("StartPlate") as Panel
	var next_art := next.get_node("NextArt") as TextureRect
	_check(plate.visible == final_step and next_art.visible != final_step,
		tag + ": LAST step shows only art-backed START, earlier steps show cartoon NEXT")
	_check((plate.get_node("StartLabel") as Label).text == "START" and
		plate.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		tag + ": START label is readable and accepts parent button click")
	var pause_voice := guide.get_node("PauseVoiceButton") as Button
	_check(pause_voice.get_theme_stylebox("normal") is StyleBoxFlat and
		pause_voice.get_theme_stylebox("pressed") is StyleBoxFlat and
		pause_voice.text in ["PAUSE VOICE", "RESUME VOICE"],
		tag + ": PAUSE VOICE stays styled as a functional native text control")
