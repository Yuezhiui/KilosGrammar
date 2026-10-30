extends SceneTree

## Beta3 regression: Play starts 3-2-1 directly, while Tutorial explains the
## real minigame's components BEFORE 3-2-1. ESC/P stay inert, and only the
## original HUD Pause button parks/resumes the same round. No camera/DB/worker.
## Run with isolated APPDATA/LOCALAPPDATA containing kg_pause_worker21.
## Godot 4.7.2 --headless --path . \
##   --script res://tools/test_pause_ready_escape_20261029.gd

const OFFLINE_MENU := "res://tools/test_pause_ready_escape_menu_20261029.gd"
const MENU_SCENE := "res://ui/main_menu/main_menu.tscn"
const COUNTDOWN_SCENE := preload("res://ui/play/gameplay/guided_countdown.tscn")
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const SOURCES := ["play", "tutorial"]
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

var checks := 0
var failures: Array[String] = []
var guide_cycles := 0
var play_cycles := 0
var screenshots := 0
var native_capture := false


func _initialize() -> void:
	# Defensive QA-only redirect; no runtime recovery event belongs to a pupil.
	ProjectSettings.set_setting("kilos/recovery_test_directory",
		"user://test_recovery_ready_removal_%d_%d" % [
			OS.get_process_id(), Time.get_ticks_usec()])
	call_deferred("_run")


func _run() -> void:
	_check(OS.get_user_data_dir().replace("\\", "/").to_lower().contains("kg_pause_worker21"),
		"QA user:// must use isolated kg_pause_worker21 APPDATA")
	if not failures.is_empty():
		_finish()
		return
	native_capture = DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("--native-capture")
	var pose := root.get_node_or_null("PoseService")
	_check(pose != null and not bool(pose.get("active")), "Camera service inactive before QA")
	if pose == null or bool(pose.get("active")):
		_finish()
		return
	pose.set_process(false)
	root.size = Vector2i(1280, 720)
	var production := load("res://ui/main_menu/main_menu.gd") as GDScript
	var screens: Dictionary = production.get_script_constant_map().get("PANEL_SCENES", {})
	_check(not screens.has("ready"), "Router no longer registers the retired Ready panel")
	_check(screens.get("calibration", "") == "res://ui/vision/calibration/calibration.tscn"
		and screens.get("gameplay", "") == "res://ui/play/gameplay/gameplay.tscn"
		and screens.get("pause", "") == "res://ui/play/pause/pause.tscn",
		"Calibration, Gameplay and Pause still route to their own scenes")
	var countdown := COUNTDOWN_SCENE.instantiate() as Control
	_check(countdown.get_node_or_null("CountdownTimer") is Timer
		and countdown.get_node_or_null("CountdownNumber") is Label,
		"Shared gameplay countdown retains authored Timer and number")
	countdown.free()
	_check(not ResourceLoader.exists("res://ui/play/ready/ready.tscn")
		and not FileAccess.file_exists("res://ui/play/ready/ready.gd"),
		"Removed Ready scene and GDScript cannot be loaded accidentally")

	# Delay all MainMenu script loading until Godot autoloads exist. A top-level
	# preload would compile it before PoseService is available.
	var app := (load(MENU_SCENE) as PackedScene).instantiate() as Control
	var offline_script := load(OFFLINE_MENU) as Script
	_check(offline_script != null and offline_script.can_instantiate(),
		"Mock-only MainMenu subclass resolves after autoload initialization")
	if offline_script == null or not offline_script.can_instantiate():
		app.free()
		quit(1)
		return
	app.set_script(offline_script)
	root.add_child(app)
	await process_frame
	for size in SIZES:
		root.size = size
		if native_capture:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(size)
		await process_frame
		await _check_pause_subviewport_layout(size)
		await _exercise_idle_esc(app, size)
		for source in SOURCES:
			for activity in ACTIVITIES:
				await _exercise(app, source, activity, size)
		await _exercise_results_does_not_save(app, size)
		await _exercise_restart_recalibrates(app, size)
		_check(not bool(pose.get("active")), str(size) + ": test never opened a webcam")
	await app.call("prepare_for_shutdown")
	app.queue_free()
	await process_frame
	pose.set_process(true)
	_finish()


func _finish() -> void:
	print("PAUSE READY ESCAPE QA: %s checks=%d failures=%d guides=%d plays=%d screenshots=%d backend=%s" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(),
		guide_cycles, play_cycles, screenshots, DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)


func _exercise_idle_esc(app: Control, size: Vector2i) -> void:
	app.call("_return_to_main")
	var before := String(app.get("current_route"))
	var escape := _key(KEY_ESCAPE)
	app.call("_input", escape)
	app.call("_unhandled_input", escape)
	_check(String(app.get("current_route")) == before,
		str(size) + ": Escape is inert on the Main Menu")
	app.call("_on_panel_requested", "pause", {})
	_check(String(app.get("current_route")) == "main",
		str(size) + ": cannot create Pause without active gameplay")


func _exercise(app: Control, source: String, activity: String, size: Vector2i) -> void:
	var label := str(size) + " / " + source + " / " + activity
	var guided := source == "tutorial"
	var payload := {
		"activity": activity,
		"game_style": "Noun",
		"topic": "Noun",
		"difficulty": "Easy",
		"game_mode": "Seconds",
		"start_countdown": true,
		"camera_live": false,
		"camera_requested": false,
		"calibration_measured": false,
		"guided_tutorial": guided,
		"entry_source": source,
		"student_id": "TEST-ONLY"
	}
	_begin_synthetic_session(app, payload)
	await process_frame
	await process_frame
	_check(String(app.get("current_route")) == "gameplay",
		label + ": Gameplay mounts without intermediate Ready panel")
	var wrapper := app.get("active_panel") as Control
	if wrapper == null:
		_check(false, label + ": gameplay wrapper missing")
		return
	var game := wrapper.get_node_or_null("ActiveMiniGame") as Control
	_check(game != null and game.process_mode == Node.PROCESS_MODE_DISABLED,
		label + ": real minigame is frozen before explanation or countdown")
	if game == null:
		return
	var initial := _snapshot(game)
	var escape := _key(KEY_ESCAPE)
	app.call("_input", escape)
	app.call("_unhandled_input", escape)
	_check(String(app.get("current_route")) == "gameplay"
		and String(wrapper.get("guided_stage")) == ("tutorial" if guided else "countdown"),
		label + ": Escape cannot skip current pregame stage")
	var pause_path := "HudLayer/PauseButton" if activity == "Balloon Popping" else "HUDLayer/HUD/PauseButton"
	var pause_button := game.get_node_or_null(pause_path) as Button
	_check(pause_button != null, label + ": original editor-authored HUD Pause button exists")
	if pause_button == null:
		return
	if guided:
		guide_cycles += 1
		await _exercise_embedded_guide(app, wrapper, game, label, size)
	else:
		play_cycles += 1
		_check(String(wrapper.get("guided_stage")) == "countdown"
			and not bool(game.call("is_tutorial_active")), label + ": Play bypasses component guide")
		_check(not _guide_visible(game, activity),
			label + ": normal Play never shows tutorial overlay")
	if String(wrapper.get("guided_stage")) != "countdown":
		_check(false, label + ": cannot start countdown before guide completes")
		return
	var overlay := wrapper.get("countdown_panel") as Control
	_check(overlay != null, label + ": countdown appears only after any integrated guide")
	if overlay == null:
		return
	_check(game.process_mode == Node.PROCESS_MODE_DISABLED
		and String((overlay.get_node("CountdownNumber") as Label).text) == "3"
		and _snapshot(game) == initial,
		label + ": 3 is frozen, without any points or time/heart loss")
	# The wrapper has the only valid Pause entry; early requests from a game
	# cannot end a tutorial or its countdown, even with a spoofed HUD signal.
	wrapper.call("_relay_navigation", "pause", {})
	wrapper.call("_relay_navigation", "results", {})
	_check(String(app.get("current_route")) == "gameplay"
		and app.get("active_panel") == wrapper, label + ": pregame rejects game Pause/Results requests")
	app.call("_input", escape)
	app.call("_unhandled_input", escape)
	_check(String(wrapper.get("guided_stage")) == "countdown",
		label + ": Escape is inert during 3-2-1")
	var p_key := _key(KEY_P)
	app.call("_input", p_key)
	app.call("_unhandled_input", p_key)
	_check(String(app.get("current_route")) == "gameplay",
		label + ": P cannot navigate during countdown")
	for expected in [2, 1]:
		wrapper.call("_on_countdown_tick")
		_check(String((overlay.get_node("CountdownNumber") as Label).text) == str(expected)
			and game.process_mode == Node.PROCESS_MODE_DISABLED
			and _snapshot(game) == initial,
			label + ": %s remains frozen without scoring" % expected)
	# Challenge the actual GO gate with an uncalibrated camera. This synthetic
	# safety probe never injects fake PoseService landmarks or unlocks a camera.
	wrapper.set("_countdown_requires_locked_pose", true)
	wrapper.call("_on_countdown_tick")
	_check(String(wrapper.get("guided_stage")) == "countdown"
		and bool(wrapper.get("_countdown_waiting_for_pose"))
		and String((overlay.get_node("CountdownNumber") as Label).text) == "1"
		and game.process_mode == Node.PROCESS_MODE_DISABLED
		and _snapshot(game) == initial,
		label + ": missing actual solo calibration blocks GO and score")
	wrapper.set("_countdown_requires_locked_pose", false)
	wrapper.call("_on_countdown_tick")
	_check(String(wrapper.get("guided_stage")) == ""
		and game.process_mode == Node.PROCESS_MODE_INHERIT
		and wrapper.get("countdown_panel") == null,
		label + ": after 3-2-1 only the original round becomes live")
	_check(_snapshot(game) == initial, label + ": countdown caused no early scoring")

	# The routed UI deliberately switches off old minigame keyboard handlers,
	# which would otherwise turn Escape or P into a second pause action.
	_check(not game.is_processing_input()
		and not game.is_processing_unhandled_input()
		and not game.is_processing_unhandled_key_input(),
		label + ": legacy minigame Esc/P shortcuts are disabled by router")
	var wrapper_id := wrapper.get_instance_id()
	var game_id := game.get_instance_id()
	app.call("_input", escape)
	app.call("_unhandled_input", escape)
	_check(String(app.get("current_route")) == "gameplay",
		label + ": Escape is inert during actual gameplay")
	app.call("_input", p_key)
	app.call("_unhandled_input", p_key)
	_check(String(app.get("current_route")) == "gameplay",
		label + ": legacy P shortcut cannot open Pause")
	var visible_layers_before := _count_visible_canvas_layers(wrapper)
	pause_button.pressed.emit()
	await process_frame
	_check(String(app.get("current_route")) == "pause",
		label + ": ONLY the HUD Pause button opens Pause")
	_check(app.get("paused_game_panel") == wrapper
		and wrapper.process_mode == Node.PROCESS_MODE_DISABLED
		and not wrapper.visible and _count_visible_canvas_layers(wrapper) == 0,
		label + ": routed Pause parks gameplay with NO lingering visible HUD layers")
	var pause := app.get("active_panel") as Control
	if pause == null:
		_check(false, label + ": pause panel missing")
		return
	app.call("_input", escape)
	app.call("_unhandled_input", escape)
	_check(String(app.get("current_route")) == "pause",
		label + ": Escape cannot close Pause or resume a game")
	var resume := pause.get_node_or_null("PauseStage/PauseCard/ResumeButton") as Button
	_check(resume != null, label + ": teacher Resume button remains interactive")
	if resume == null:
		return
	var pause_stage := pause.get_node_or_null("PauseStage") as Control
	_check(pause_stage != null
		and is_equal_approx(pause_stage.scale.x,
			minf(pause.size.x / 1280.0, pause.size.y / 720.0)),
		label + ": routed Pause stage fits its actual logical canvas")
	resume.pressed.emit()
	await process_frame
	_check(String(app.get("current_route")) == "gameplay"
		and app.get("paused_game_panel") == null
		and app.get("active_panel") == wrapper
		and wrapper.get_instance_id() == wrapper_id
		and is_instance_valid(game) and game.get_instance_id() == game_id,
		label + ": Resume reuses exactly the paused wrapper and game")
	_check(_count_visible_canvas_layers(wrapper) == visible_layers_before
		and wrapper.visible and wrapper.process_mode == Node.PROCESS_MODE_INHERIT,
		label + ": Resume restores exactly the original visible HUD layers")
	if native_capture and source == "tutorial":
		await _capture(label, size)


func _exercise_embedded_guide(app: Control, wrapper: Control, game: Control, label: String, size: Vector2i) -> void:
	var context := wrapper.get("context") as Dictionary
	var activity := String(context.get("activity", ""))
	_check(String(wrapper.get("guided_stage")) == "tutorial"
		and bool(game.call("is_tutorial_active"))
		and wrapper.get("countdown_panel") == null,
		label + ": Tutorial opens real component explanations BEFORE 3-2-1")
	_check(_guide_visible(game, activity), label + ": in-game dim spotlight is visible")
	var next := _button(game, "NextButton")
	var back := _button(game, "BackButton")
	var skip := _button(game, "SkipButton")
	_check(next != null and back != null and skip != null
		and next.can_process() and back.can_process() and skip.can_process(),
		label + ": Next/Back/Skip controls process despite frozen gameplay")
	var initial := _snapshot(game)
	var desc := _find_guide_description(game, activity)
	_check(desc != null and not desc.text.is_empty(), label + ": component explained with descriptive text")
	_check(not pause_gameplay_possible(wrapper, game, app), label + ": spotlight blocks game HUD Pause requests")
	if next == null or skip == null:
		return
	var first_index := _guide_index(game, activity)
	next.pressed.emit()
	_check(_guide_index(game, activity) == first_index + 1
		and bool(game.call("is_tutorial_active"))
		and wrapper.get("countdown_panel") == null
		and _snapshot(game) == initial,
		label + ": Next advances explanation without starting gameplay")
	if back != null:
		back.pressed.emit()
		_check(_guide_index(game, activity) == first_index
			and bool(game.call("is_tutorial_active"))
			and _snapshot(game) == initial,
			label + ": Back revisits first explanation without scoring")
	if native_capture:
		await _capture(label + " guide", size)
	if size.x == 1600:
		# Exercise each actual Next action to the end in the middle resolution.
		for _step in 12:
			if not bool(game.call("is_tutorial_active")):
				break
			_check(wrapper.get("countdown_panel") == null
				and game.process_mode == Node.PROCESS_MODE_DISABLED
				and _snapshot(game) == initial,
				label + ": every guide step keeps round frozen")
			next.pressed.emit()
	else:
		skip.pressed.emit()
	await process_frame
	_check(not bool(game.call("is_tutorial_active"))
		and not _guide_visible(game, activity),
		label + ": finishing guide hides dim/spotlight and narration controls")
	_check(String(wrapper.get("guided_stage")) == "countdown"
		and game.process_mode == Node.PROCESS_MODE_DISABLED
		and _snapshot(game) == initial,
		label + ": guide completion schedules exactly one frozen 3-2-1")
	var original_countdown := wrapper.get("countdown_panel") as Control
	next.pressed.emit()
	skip.pressed.emit()
	_check(wrapper.get("countdown_panel") == original_countdown,
		label + ": stale Next/Skip events cannot restart countdown")


func _begin_synthetic_session(app: Control, payload: Dictionary) -> void:
	app.call("_return_to_main")
	# This fixture directly enters Gameplay to test the wrapper. In the real
	# MainMenu, selecting Play from the Home screen clears any old Tutorial
	# context at Student Setup. Reproduce that boundary for each mock case:
	# otherwise MainMenu forcibly retains guided_tutorial from the last case.
	app.set("session_state", {})
	app.call("_on_panel_requested", "gameplay", payload)


func _guide_visible(game: Control, activity: String) -> bool:
	var path := "TutorialSpotlightLayer/TutorialSpotlight" if activity == "Human Plane" else "GuidedTutorialLayer/GuidedTutorial"
	var overlay := game.get_node_or_null(path) as Control
	return overlay != null and overlay.visible


func _guide_index(game: Control, activity: String) -> int:
	return int(game.get("_tutorial_step")) if activity == "Human Plane" else int(game.get("tutorial_step_index"))


func _find_guide_description(game: Control, activity: String) -> Label:
	var path := "TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide/Message" if activity == "Human Plane" else "GuidedTutorialLayer/GuidedTutorial/TutorialCard/StepCaption"
	return game.get_node_or_null(path) as Label


func _button(game: Control, button_name: String) -> Button:
	for found in game.find_children(button_name, "Button", true, false):
		return found as Button
	return null


func _snapshot(game: Control) -> Dictionary:
	var stats := {}
	for key in ["score", "time_remaining", "lives", "hearts", "wave_index", "round_index", "attempts", "correct_count", "gate_progress"]:
		for prop in game.get_property_list():
			if String(prop.get("name", "")) == key:
				stats[key] = game.get(key)
				break
	return stats


func pause_gameplay_possible(wrapper: Control, game: Control, app: Control) -> bool:
	wrapper.call("_relay_navigation", "pause", {})
	wrapper.call("_relay_navigation", "results", {})
	return String(app.get("current_route")) != "gameplay" or app.get("active_panel") != wrapper


func _count_visible_canvas_layers(wrapper: Control) -> int:
	var count := 0
	for found in wrapper.find_children("*", "CanvasLayer", true, false):
		if (found as CanvasLayer).visible:
			count += 1
	return count


func _capture(label: String, size: Vector2i) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := "user://pause_ready_escape_worker21"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	var filename := "%s_%dx%d.png" % [label.replace(" / ", "_").replace(" ", "_").to_lower(), size.x, size.y]
	var photo := root.get_texture().get_image()
	var result := photo.save_png(ProjectSettings.globalize_path(path.path_join(filename)))
	_check(result == OK and photo.get_size() == size, "native viewport capture: " + filename)
	if result == OK:
		screenshots += 1
		print("PAUSE_QA_SCREENSHOT ", ProjectSettings.globalize_path(path.path_join(filename)))


func _exercise_results_does_not_save(app: Control, size: Vector2i) -> void:
	var label := str(size) + " / paused Results"
	await _mount_live_round_for_teacher_action(app)
	var wrapper := app.get("active_panel") as Control
	var game := wrapper.get("active_game") as Control
	var pause_button := game.get_node("HUDLayer/HUD/PauseButton") as Button
	pause_button.pressed.emit()
	await process_frame
	var pause := app.get("active_panel") as Control
	_check(String(app.get("current_route")) == "pause", label + ": paused round present")
	if pause == null:
		return
	var results := pause.get_node_or_null("PauseStage/PauseCard/ResultsButton") as Button
	_check(results != null, label + ": teacher can choose View Results")
	if results == null:
		return
	results.pressed.emit()
	await process_frame
	_check(String(app.get("current_route")) == "results"
		and not bool((app.get("session_state") as Dictionary).get("score_saved", false))
		and not bool((app.get("session_state") as Dictionary).get("round_completed", false)),
		label + ": paused/aborted round opens Results but is NEVER falsely saved")
	_check(app.get("paused_game_panel") == null,
		label + ": viewing aborted Results disposes parked round")
	app.call("_input", _key(KEY_ESCAPE))
	app.call("_unhandled_input", _key(KEY_ESCAPE))
	_check(String(app.get("current_route")) == "results",
		label + ": Escape cannot back out of Results")


func _exercise_restart_recalibrates(app: Control, size: Vector2i) -> void:
	var label := str(size) + " / teacher Restart"
	await _mount_live_round_for_teacher_action(app)
	var wrapper := app.get("active_panel") as Control
	var game := wrapper.get("active_game") as Control
	(game.get_node("HUDLayer/HUD/PauseButton") as Button).pressed.emit()
	await process_frame
	var pause := app.get("active_panel") as Control
	if pause == null:
		_check(false, label + ": pause panel exists before Restart")
		return
	var restart := pause.get_node_or_null("PauseStage/PauseCard/RestartButton") as Button
	_check(restart != null, label + ": new Pause artwork includes native Restart button")
	if restart == null:
		return
	var before := int(app.get("intercepted_calibration_routes"))
	restart.pressed.emit()
	await process_frame
	_check(String(app.get("current_route")) == "calibration"
		and int(app.get("intercepted_calibration_routes")) == before + 1,
		label + ": Restart routes to NEW physical calibration (webcam mount safely intercepted)")
	app.call("_input", _key(KEY_ESCAPE))
	app.call("_unhandled_input", _key(KEY_ESCAPE))
	_check(String(app.get("current_route")) == "calibration",
		label + ": Escape is inert even in restarted Calibration")
	_check(app.get("paused_game_panel") == null,
		label + ": Restart discarded old parked game and its score state")
	var context := app.get("session_state") as Dictionary
	_check(not bool(context.get("calibration_measured", true))
		and not bool(context.get("round_completed", false))
		and bool(context.get("start_countdown", false)),
		label + ": restart resets calibration/round completion and queues one in-game 3-2-1 [measured=%s completed=%s countdown=%s]" %
			[str(context.get("calibration_measured", "absent")), str(context.get("round_completed", "absent")), str(context.get("start_countdown", "absent"))])
	# The stubbed calibration avoids any physical webcam in this QA only.
	app.call("_return_to_main")
	app.call("_input", _key(KEY_ESCAPE))
	app.call("_unhandled_input", _key(KEY_ESCAPE))
	_check(String(app.get("current_route")) == "main",
		label + ": Escape cannot navigate after returning to Main")


func _check_pause_subviewport_layout(size: Vector2i) -> void:
	# project.godot's stretch canvas_items keeps MainMenu's *logical* canvas
	# at 1280x720 even when Window pixels are 1600x900/1920x1080.
	# An independent editor-authored Pause scene in an exact-size SubViewport
	# exercises real width/height responsiveness without any hardware.
	var viewport := SubViewport.new()
	viewport.name = "PauseLayoutAuditViewport"
	viewport.size = size
	viewport.disable_3d = true
	root.add_child(viewport)
	var scene := load("res://ui/play/pause/pause.tscn") as PackedScene
	var pause := scene.instantiate() as Control
	viewport.add_child(pause)
	pause.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	var stage := pause.get_node_or_null("PauseStage") as Control
	var card := pause.get_node_or_null("PauseStage/PauseCard") as Control
	var target_scale := minf(float(size.x) / 1280.0, float(size.y) / 720.0)
	_check(Vector2i(pause.size) == size and stage != null and card != null,
		str(size) + ": independent Pause scene fills exact-size SubViewport")
	if stage != null and card != null:
		_check(is_equal_approx(stage.scale.x, target_scale)
			and is_equal_approx(stage.scale.y, target_scale),
			str(size) + ": stage scales uniformly within actual viewport")
		var card_rect := card.get_global_rect()
		_check(card_rect.position.x >= -1.0 and card_rect.position.y >= -1.0
			and card_rect.end.x <= size.x + 1 and card_rect.end.y <= size.y + 1,
			str(size) + ": authored Pause panel remains fully on-screen")
	viewport.queue_free()
	await process_frame


func _mount_live_round_for_teacher_action(app: Control) -> void:
	_begin_synthetic_session(app, {
		"activity": "Catch the Word", "topic": "Noun", "game_style": "Noun",
		"game_mode": "Seconds", "difficulty": "Easy", "start_countdown": true,
		"camera_live": false, "camera_requested": false,
		"entry_source": "play", "guided_tutorial": false,
		"student_id": "QA-ONLY", "score": 0})
	await process_frame
	await process_frame
	var wrapper := app.get("active_panel") as Control
	if wrapper != null:
		for _tick in 3:
			wrapper.call("_on_countdown_tick")


func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
		printerr("READY REMOVAL FAIL: ", reason)
