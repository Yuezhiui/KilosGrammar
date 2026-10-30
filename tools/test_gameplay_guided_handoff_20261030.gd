extends SceneTree

# Godot --headless --path . --script res://tools/test_gameplay_guided_handoff_20261030.gd
# Add -- --native-capture to save viewport evidence using the real window.
# Exercises REAL embedded minigame Next/Skip buttons, never synthetic tutorial_finished.
# No main-menu database client, physical webcam or saved score is created.
const WRAPPER_PATH := "res://ui/play/gameplay/gameplay.tscn"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const GAMES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const MODES := ["Seconds", "Lives"]
const REPEATS := 7 # 3 sizes x 3 games x 2 modes x 7 = 126 full pairs.

var checks := 0
var failures: Array[String] = []
var guided_cycles := 0
var play_cycles := 0
var screenshots := 0
var _capture_enabled := false
var _wrapper_scene: PackedScene


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_capture_enabled = DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("--native-capture")
	# SceneTree scripts are compiled before project autoload names are registered.
	# Loading gameplay.gd from a top-level preload can therefore fail to resolve
	# PoseService even though runtime gameplay loads correctly from MainMenu.
	_wrapper_scene = load(WRAPPER_PATH) as PackedScene
	# The Godot executable may report a failed resource script compile while
	# still exiting 0. Verify the actual wrapper is loaded before any cycle;
	# an absent script is a FAILURE, never a zero-check PASS.
	var probe := _wrapper_scene.instantiate() as Control if _wrapper_scene != null else null
	if probe == null or not probe.has_method("set_context") or not probe.has_method("_begin_integrated_tutorial"):
		_check(false, "Gameplay wrapper failed to compile or expose integrated tutorial routing")
		print("GUIDED GAMEPLAY ROUTE: FAIL checks=%d failures=%d" % [checks, failures.size()])
		quit(1)
		return
	probe.free()
	var pose := root.get_node_or_null("PoseService")
	if is_instance_valid(pose):
		pose.call("stop_camera")
		pose.set_process(false)
	if _capture_enabled:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://guided_route_qa"))
	for resolution in SIZES:
		root.size = resolution
		root.content_scale_size = resolution
		if _capture_enabled:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
		await process_frame
		for activity in GAMES:
			for mode in MODES:
				for iteration in (1 if _capture_enabled else REPEATS):
					await _case(resolution, activity, mode, iteration, true)
					await _case(resolution, activity, mode, iteration, false)
		await _cancellation_case(resolution)
	if is_instance_valid(pose):
		pose.set_process(true)
	print("GUIDED GAMEPLAY ROUTE: %s checks=%d failures=%d guided_cycles=%d play_cycles=%d screenshots=%d backend=%s" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), guided_cycles, play_cycles,
		screenshots, DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)


func _case(resolution: Vector2i, activity: String, mode: String, iteration: int, guided: bool) -> void:
	var tag := "%s/%s/%s/%d/%s" % [str(resolution), activity, mode, iteration, "guide" if guided else "play"]
	var wrapper := _wrapper_scene.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({
		"activity": activity, "game_mode": mode, "topic": "Noun", "game_style": "Noun",
		"difficulty": "Easy", "guided_tutorial": guided,
		"entry_source": "tutorial" if guided else "play",
		"camera_live": false, "start_countdown": true, "keyboard_mode": false,
		"demo_mode": guided, "student_id": "ROUTE-QA-ONLY"
	})
	await process_frame
	await process_frame
	var game := wrapper.get("active_game") as Control
	_check(game != null, tag + ": mounted actual minigame scene")
	if game == null:
		wrapper.queue_free()
		await process_frame
		return
	var stage := String(wrapper.get("guided_stage"))
	_check(stage == ("tutorial" if guided else "countdown"), tag + ": expected first phase, found " + stage)
	_check(game.process_mode == Node.PROCESS_MODE_DISABLED, tag + ": gameplay parent frozen before GO")
	var before_score := int(game.get("score"))
	var before_time := float(game.get("time_remaining"))
	var before_lives := int(game.get("hearts")) if activity == "Balloon Popping" else int(game.get("lives"))
	if guided:
		guided_cycles += 1
		_check(game.has_signal("tutorial_finished") and game.has_method("begin_guided_tutorial")
			and game.has_method("is_tutorial_active"), tag + ": integrated tutorial contract")
		if not game.has_method("is_tutorial_active"):
			wrapper.queue_free()
			await process_frame
			return
		_check(bool(game.call("is_tutorial_active")), tag + ": guide visible and active before countdown")
		_check(wrapper.get("countdown_panel") == null, tag + ": countdown has not been constructed early")
		# Camera-only branch must never unlock gameplay or mask a guided overlay,
		# including loss/recovery of tracking while explanation is open.
		(wrapper.context as Dictionary)["camera_live"] = true
		wrapper._process(0.6)
		(wrapper.context as Dictionary)["camera_live"] = false
		_check(game.process_mode == Node.PROCESS_MODE_DISABLED and not bool(wrapper.get("tracking_suspended"))
			and not wrapper.get_node("TrackingNoticeLayer/TrackingNotice").visible,
			tag + ": camera callbacks cannot unfreeze/cover guide")
		_check(int(game.get("score")) == before_score and is_equal_approx(float(game.get("time_remaining")), before_time)
			and (int(game.get("hearts")) if activity == "Balloon Popping" else int(game.get("lives"))) == before_lives,
			tag + ": score, timer and hearts untouched throughout guide")
		var skip := _tutorial_button(game, "SkipButton")
		var next := _tutorial_button(game, "NextButton")
		_check(skip != null and next != null, tag + ": real Next and Skip controls exist")
		if skip != null:
			_check(skip.can_process(), tag + ": Skip input processes while minigame disabled")
		if next != null:
			_check(next.can_process(), tag + ": Next input processes while minigame disabled")
		if _capture_enabled and iteration == 0:
			await _capture(resolution, activity, mode, "guide")
		if next != null and iteration % 2 == 0:
			# Press actual scene-authored Next buttons to finish narration steps.
			for step in 12:
				if not bool(game.call("is_tutorial_active")):
					break
				next.pressed.emit()
		else:
			if skip != null:
				skip.pressed.emit()
		await process_frame
		_check(not bool(game.call("is_tutorial_active")), tag + ": guided controls finish/skip successfully")
		_check(String(wrapper.get("guided_stage")) == "countdown", tag + ": one guide completion starts countdown")
		_check(game.process_mode == Node.PROCESS_MODE_DISABLED, tag + ": finishing guide still leaves gameplay frozen")
		if next != null:
			next.pressed.emit()
		if skip != null:
			skip.pressed.emit()
		_check(String(wrapper.get("guided_stage")) == "countdown", tag + ": duplicate Next/Skip do not restart guide")
	else:
		play_cycles += 1
		_check(wrapper.get("countdown_panel") != null, tag + ": Play begins 3-2-1 without explanation")
		if game.has_method("is_tutorial_active"):
			_check(not bool(game.call("is_tutorial_active")), tag + ": normal Play never displays guide")
	var panel := wrapper.get("countdown_panel") as Control
	_check(panel != null and panel.get_node_or_null("CountdownNumber") is Label,
		tag + ": shared scene-authored countdown present")
	if panel != null:
		_check((panel.get_node("CountdownNumber") as Label).text == "3", tag + ": countdown starts at 3")
	if _capture_enabled and iteration == 0 and guided:
		await _capture(resolution, activity, mode, "countdown")
	for count in 3:
		wrapper._on_countdown_tick()
	_check(game.process_mode == Node.PROCESS_MODE_INHERIT and wrapper.get("countdown_panel") == null,
		tag + ": game becomes live only at GO")
	_check(int(game.get("score")) == before_score and is_equal_approx(float(game.get("time_remaining")), before_time)
		and (int(game.get("hearts")) if activity == "Balloon Popping" else int(game.get("lives"))) == before_lives,
		tag + ": countdown never changed saved scores/time/hearts")
	if guided:
		var payload: Dictionary = wrapper.get_context()
		_check(bool(payload.get("guided_tutorial", false)) and String(payload.get("entry_source", "")) == "tutorial",
			tag + ": tutorial practice cannot be saved as a Play student score")
	if activity == "Human Plane":
		_check(bool(game.get("running")), tag + ": plane running flag restored at GO")
	if activity == "Catch the Word":
		_check(bool(game.get("round_running")), tag + ": Catch game loop restored at GO")
	if activity == "Balloon Popping":
		_check(bool(game.get("timer_running")), tag + ": Balloon game loop restored at GO")
	wrapper.queue_free()
	await process_frame


func _cancellation_case(resolution: Vector2i) -> void:
	for departure in ["tutorial_home", "change_activity", "restart", "main"]:
		# An old minigame's queued signal cannot end the new scene's guide.
		var wrapper := _wrapper_scene.instantiate() as Control
		root.add_child(wrapper)
		wrapper.set_context({"activity": "Catch the Word", "guided_tutorial": true, "game_mode": "Seconds"})
		await process_frame
		var old_game := wrapper.get("active_game") as Control
		wrapper.set_context({"activity": "Human Plane", "guided_tutorial": true})
		# Signal BEFORE the queued free is flushed: this is the actual stale
		# callback race that the generation gate has to protect against.
		old_game.emit_signal("tutorial_finished")
		_check(String(wrapper.get("guided_stage")) == "tutorial" and wrapper.get("countdown_panel") == null,
			str(resolution) + "/" + departure + ": previous game's completion discarded")
		await process_frame
		_check(String(wrapper.get("guided_stage")) == "tutorial", str(resolution) + ": replacement guide still active")
		wrapper._relay_navigation(departure, {})
		var new_game := wrapper.get("active_game") as Control
		if is_instance_valid(new_game):
			new_game.emit_signal("tutorial_finished")
		await process_frame
		_check(String(wrapper.get("guided_stage")) != "countdown" and wrapper.get("countdown_panel") == null,
			str(resolution) + "/" + departure + ": abandoning guide cancels pending countdown")
		wrapper.queue_free()
		await process_frame


func _tutorial_button(game: Control, button_name: String) -> Button:
	for node in game.find_children(button_name, "Button", true, false):
		var button := node as Button
		if button != null:
			return button
	return null


func _capture(resolution: Vector2i, activity: String, mode: String, stage: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	var filename := "%s_%s_%s_%dx%d.png" % [activity.to_snake_case(), mode.to_lower(), stage, resolution.x, resolution.y]
	var target := ProjectSettings.globalize_path("user://guided_route_qa/" + filename)
	var result := screenshot.save_png(target)
	_check(result == OK and screenshot.get_size() == resolution, "native screenshot: " + filename)
	if result == OK:
		screenshots += 1
		print("ROUTE_SCREENSHOT ", target)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("GUIDED ROUTE FAIL: ", message)
