extends SceneTree

## Safe post-Ready removal regression: both entries use Gameplay's own 3-2-1.
## ESC/P stay inert, top-right Pause and its actions route correctly at
## 1280x720 / 1600x900 / 1920x1080. No real camera, DB or worker.
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


func _initialize() -> void:
	# Defensive QA-only redirect; no runtime recovery event belongs to a pupil.
	ProjectSettings.set_setting("kilos/recovery_test_directory",
		"user://test_recovery_ready_removal_%d_%d" % [
			OS.get_process_id(), Time.get_ticks_usec()])
	call_deferred("_run")


func _run() -> void:
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
		await process_frame
		await _check_pause_subviewport_layout(size)
		await _exercise_idle_esc(app, size)
		for source in SOURCES:
			for activity in ACTIVITIES:
				await _exercise(app, source, activity, size)
		await _exercise_results_does_not_save(app, size)
		await _exercise_restart_recalibrates(app, size)
	await app.call("prepare_for_shutdown")
	app.queue_free()
	await process_frame
	print("PAUSE READY ESCAPE QA: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
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
		"guided_tutorial": source == "tutorial",
		"entry_source": source,
		"student_id": "TEST-ONLY"
	}
	app.call("_return_to_main")
	app.call("_on_panel_requested", "gameplay", payload)
	await process_frame
	await process_frame
	_check(String(app.get("current_route")) == "gameplay",
		label + ": Gameplay mounts without intermediate Ready panel")
	var wrapper := app.get("active_panel") as Control
	if wrapper == null:
		_check(false, label + ": gameplay wrapper missing")
		return
	var game := wrapper.get_node_or_null("ActiveMiniGame") as Control
	var overlay := wrapper.get("countdown_panel") as Control
	_check(game != null and overlay != null
		and String(wrapper.get("guided_stage")) == "countdown",
		label + ": minigame freezes behind in-game 3-2-1")
	if game == null or overlay == null:
		return
	_check(game.process_mode == Node.PROCESS_MODE_DISABLED
		and String((overlay.get_node("CountdownNumber") as Label).text) == "3",
		label + ": counting starts at 3 before scoring begins")
	var escape := _key(KEY_ESCAPE)
	app.call("_input", escape)
	app.call("_unhandled_input", escape)
	_check(String(app.get("current_route")) == "gameplay"
		and String(wrapper.get("guided_stage")) == "countdown",
		label + ": Escape cannot skip the countdown or open Pause")
	for _tick in 3:
		wrapper.call("_on_countdown_tick")
	_check(String(wrapper.get("guided_stage")) != "countdown"
		and game.process_mode == Node.PROCESS_MODE_INHERIT
		and wrapper.get("countdown_panel") == null,
		label + ": after 3-2-1 only the original round becomes live")

	# The routed UI deliberately switches off old minigame keyboard handlers,
	# which would otherwise turn Escape or P into a second pause action.
	_check(not game.is_processing_input()
		and not game.is_processing_unhandled_input()
		and not game.is_processing_unhandled_key_input(),
		label + ": legacy minigame Esc/P shortcuts are disabled by router")
	var pause_path := "HudLayer/PauseButton" if activity == "Balloon Popping" else "HUDLayer/HUD/PauseButton"
	var pause_button := game.get_node_or_null(pause_path) as Button
	_check(pause_button != null, label + ": original authored HUD Pause button exists")
	if pause_button == null:
		return
	var wrapper_id := wrapper.get_instance_id()
	var game_id := game.get_instance_id()
	app.call("_input", escape)
	app.call("_unhandled_input", escape)
	_check(String(app.get("current_route")) == "gameplay",
		label + ": Escape is inert during actual gameplay")
	var p_key := _key(KEY_P)
	app.call("_input", p_key)
	app.call("_unhandled_input", p_key)
	_check(String(app.get("current_route")) == "gameplay",
		label + ": legacy P shortcut cannot open Pause")
	pause_button.pressed.emit()
	await process_frame
	_check(String(app.get("current_route")) == "pause",
		label + ": ONLY the HUD Pause button opens Pause")
	_check(app.get("paused_game_panel") == wrapper
		and wrapper.process_mode == Node.PROCESS_MODE_DISABLED
		and not wrapper.visible,
		label + ": routed Pause freezes and parks unchanged gameplay")
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
	app.call("_return_to_main")
	app.call("_on_panel_requested", "gameplay", {
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
