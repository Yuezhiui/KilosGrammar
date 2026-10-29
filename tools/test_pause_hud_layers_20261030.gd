extends SceneTree

# Router-level pause visibility regression for all three activities.
# No webcam, PostgreSQL, or live recovery journal is used.
# Headless: Godot --headless --path . --script res://tools/test_pause_hud_layers_20261030.gd
# Native screenshots: Godot --rendering-driver opengl3 --path . --script res://tools/test_pause_hud_layers_20261030.gd
const MENU := "res://ui/main_menu/main_menu.tscn"
const QA_MENU := "res://tools/test_pause_ready_escape_menu_20261029.gd"
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const OUTPUT_DIR := "res://showcase/pause_hud_20261030"

var checks := 0
var failures: Array[String] = []
var captures := 0
var use_graphics := false


func _initialize() -> void:
	ProjectSettings.set_setting("kilos/recovery_test_directory",
		"user://test_pause_hud_layers_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	call_deferred("_run")


func _run() -> void:
	use_graphics = DisplayServer.get_name() != "headless"
	if use_graphics:
		var create_result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
		_check(create_result == OK, "Native screenshot directory is writable")
	root.size = Vector2i(1280, 720)
	var app := (load(MENU) as PackedScene).instantiate() as Control
	var test_script := load(QA_MENU) as Script
	if app == null or test_script == null or not test_script.can_instantiate():
		_check(false, "Test-only Main Menu loads safely")
		_finish()
		return
	app.set_script(test_script)
	root.add_child(app)
	await process_frame
	for viewport_size in SIZES:
		root.size = viewport_size
		if use_graphics:
			DisplayServer.window_set_size(viewport_size)
		await process_frame
		await process_frame
		for activity in ACTIVITIES:
			await _exercise(app, activity, viewport_size)
	await app.call("prepare_for_shutdown")
	app.queue_free()
	await process_frame
	_finish()


func _exercise(app: Control, activity: String, viewport_size: Vector2i) -> void:
	var case_id := "%s_%dx%d" % [
		activity.to_lower().replace(" ", "_"), viewport_size.x, viewport_size.y
	]
	app.call("_return_to_main")
	app.call("_on_panel_requested", "student_setup", {})
	await process_frame
	app.call("_on_panel_requested", "gameplay", {
		"activity": activity, "topic": "Noun", "game_style": "Noun",
		"game_mode": "Seconds", "difficulty": "Easy",
		"student_id": "TEST-ONLY", "camera_live": false,
		"start_countdown": false, "database_connected": false
	})
	await process_frame
	await process_frame
	var wrapper := app.get("active_panel") as Control
	var game := wrapper.get_node_or_null("ActiveMiniGame") as Control if wrapper != null else null
	if wrapper == null or game == null:
		_check(false, "%s: live wrapper and game mounted" % activity)
		return
	var layers := wrapper.find_children("*", "CanvasLayer", true, false)
	_check(not layers.is_empty(), "%s: wrapper owns CanvasLayers" % activity)
	var visibility := {}
	for node in layers:
		var layer := node as CanvasLayer
		visibility[layer] = layer.visible
	# An already-concealed layer must stay concealed when the game resumes.
	var tracking := wrapper.get_node("TrackingNoticeLayer") as CanvasLayer
	tracking.visible = false
	visibility[tracking] = false
	var hud_path := "HudLayer/PauseButton" if activity == "Balloon Popping" else "HUDLayer/HUD/PauseButton"
	var button := game.get_node_or_null(hud_path) as Button
	_check(button != null, "%s: teacher Pause button exists" % activity)
	if button == null:
		return
	var catch_hud: Array[CanvasItem] = []
	if activity == "Catch the Word":
		for path in [
			"HUDLayer/HUD/TitlePlaque", "HUDLayer/HUD/PromptLabel",
			"HUDLayer/HUD/TimeLabel"
		]:
			var hud_item := game.get_node_or_null(path) as CanvasItem
			_check(hud_item != null and hud_item.is_visible_in_tree(),
				"%s: active game displays %s before Pause" % [case_id, path])
			if hud_item != null:
				catch_hud.append(hud_item)
	var before := wrapper.get_context() as Dictionary
	button.pressed.emit()
	await process_frame
	_check(String(app.get("current_route")) == "pause", "%s: Pause route opens" % activity)
	_check(app.get("paused_game_panel") == wrapper and not wrapper.visible
		and wrapper.process_mode == Node.PROCESS_MODE_DISABLED,
		"%s: original round parked and disabled" % activity)
	var hidden := true
	for layer in layers:
		hidden = hidden and not (layer as CanvasLayer).visible
	_check(hidden, "%s: every gameplay CanvasLayer hidden during Pause" % activity)
	for hud_item in catch_hud:
		_check(not hud_item.is_visible_in_tree(),
			"%s: Catch %s does not paint through Pause" % [case_id, hud_item.name])
	var pause_panel := app.get("active_panel") as Control
	var pause_card := pause_panel.get_node_or_null("PauseStage/PauseCard") as Control if pause_panel != null else null
	_check(pause_card != null and pause_card.is_visible_in_tree(),
		"%s: Pause screen remains visible" % activity)
	await _capture(case_id + "_paused.png", viewport_size)
	await create_timer(0.12).timeout
	var frozen := wrapper.get_context() as Dictionary
	_check(int(before.get("score", 0)) == int(frozen.get("score", 0))
		and absf(float(before.get("time_remaining", 0.0)) - float(frozen.get("time_remaining", 0.0))) < 0.20,
		"%s: timer and score frozen on Pause" % activity)
	var resume := pause_panel.get_node("PauseStage/PauseCard/ResumeButton") as Button
	resume.pressed.emit()
	await process_frame
	_check(String(app.get("current_route")) == "gameplay"
		and app.get("active_panel") == wrapper and game == wrapper.get_node_or_null("ActiveMiniGame"),
		"%s: Resume restores same round" % activity)
	var restored := true
	for layer in layers:
		restored = restored and (layer as CanvasLayer).visible == bool(visibility[layer])
	_check(restored, "%s: Resume restores every layer's previous visibility" % activity)
	for hud_item in catch_hud:
		_check(hud_item.is_visible_in_tree(),
			"%s: Catch %s returns on Resume" % [case_id, hud_item.name])
	await _capture(case_id + "_resumed.png", viewport_size)
	app.call("_return_to_main")
	await process_frame
	await process_frame


func _capture(filename: String, viewport_size: Vector2i) -> void:
	if not use_graphics:
		return
	# Read the actual OpenGL-rendered viewport after the route and all canvas
	# layers have completed a draw. No screenshot is synthesized or composited.
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_check(picture != null and picture.get_size() == viewport_size,
		"%s: native GPU screenshot matches %s" % [filename, viewport_size])
	if picture == null or picture.get_size() != viewport_size:
		return
	var output := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(filename))
	var result := picture.save_png(output)
	_check(result == OK, "%s: GPU screenshot saved" % filename)
	if result == OK:
		captures += 1
		print("CAPTURED ", output)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("PAUSE HUD: " + description)


func _finish() -> void:
	if use_graphics:
		_check(captures == SIZES.size() * ACTIVITIES.size() * 2,
			"All 18 routed Pause/Resume GPU screenshots saved")
	print("PAUSE HUD QA: %s (%d checks, %d failures, %d native GPU captures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size(), captures])
	quit(0 if failures.is_empty() else 1)
