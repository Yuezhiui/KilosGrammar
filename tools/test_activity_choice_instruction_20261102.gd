extends SceneTree

## Focused, non-destructive Activity Chooser instruction QA.
## Godot 4.7.2 --headless --path . --script res://tools/test_activity_choice_instruction_20261102.gd
## No live YOLO worker, webcam, database, HTTP, or filesystem writes.
const SCENE := preload("res://ui/play/activity/play_activity.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const ACTIVITIES := ["Catch the Word", "Human Plane", "Balloon Popping"]
const HEADING := "SELECT AN ACTIVITY TO PLAY"
const PREFIX := "LayoutMargins/Content/"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("ACTIVITY INSTRUCTION QA FAIL: ", description)


func _descendant_dialogs(node: Node) -> int:
	var count := 1 if node is Window or node is PopupPanel else 0
	for child in node.get_children():
		count += _descendant_dialogs(child)
	return count


func _assert_heading(scene: Control, resolution: Vector2i, state: String) -> void:
	var heading := scene.get_node_or_null("%ActivityInstructionHeading") as Label
	var panel := scene.get_node_or_null(PREFIX + "Header/ActivityInstructionPanel") as Panel
	var instructions := scene.get_node(PREFIX + "Header/InstructionArtwork") as Control
	var artwork := scene.get_node(PREFIX + "Header/ChooseActivityArtwork") as Control
	var buttons: Dictionary = scene.get("activity_buttons")
	var frame := "%s %s" % [resolution, state]
	_assert(heading != null and panel != null, frame + " editor-authored heading and small panel exist")
	if heading == null or panel == null:
		return
	_assert(heading.text == HEADING, frame + " exact required English heading")
	_assert(heading.is_visible_in_tree() and panel.is_visible_in_tree(), frame + " status is visible without popup")
	_assert(heading.mouse_filter == Control.MOUSE_FILTER_IGNORE and panel.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		frame + " instruction never consumes game-selection clicks")
	_assert(heading.get_theme_font_size("font_size") >= 16,
		frame + " text is legible in the editor-authored overlay")
	var panel_bounds := panel.get_global_rect()
	var heading_bounds := heading.get_global_rect()
	var native_banner_bounds := instructions.get_global_rect()
	var original_title_bounds := artwork.get_global_rect()
	_assert(panel_bounds.size.x <= resolution.x * 0.37 and panel_bounds.size.y <= resolution.y * 0.08,
		frame + " overlay stays compact, never fullscreen")
	_assert(panel_bounds.position.x >= -0.5 and panel_bounds.position.y >= -0.5
		and panel_bounds.end.x <= float(resolution.x) + 0.5
		and panel_bounds.end.y <= float(resolution.y) + 0.5,
		frame + " heading stays within the actual viewport")
	_assert(panel_bounds.encloses(heading_bounds), frame + " heading is inside its panel")
	_assert(not panel_bounds.intersects(native_banner_bounds), frame + " existing illustrated instruction unobstructed")
	_assert(not panel_bounds.intersects(original_title_bounds), frame + " original choose-activity title unobstructed")
	for activity in buttons:
		_assert(not panel_bounds.intersects((buttons[activity] as Button).get_global_rect()),
			frame + " game-choice hitbox unobstructed: " + activity)
	_assert(not panel_bounds.intersects((scene.get_node(PREFIX + "Footer/NextButton") as Button).get_global_rect())
		and not panel_bounds.intersects((scene.get_node(PREFIX + "Footer/BackButton") as Button).get_global_rect()),
		frame + " original Back and Next unobstructed")
	_assert(_descendant_dialogs(scene) == 0, frame + " zero redundant fullscreen/native popups")


func _exercise(resolution: Vector2i) -> void:
	root.size = resolution
	root.content_scale_size = resolution
	var scene := SCENE.instantiate() as Control
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	var buttons: Dictionary = scene.get("activity_buttons")
	var routes: Array[Dictionary] = []
	var camera_prewarm_requests := [0]
	scene.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"route": target, "payload": payload.duplicate(true)}))
	scene.camera_model_prewarm_requested.connect(func() -> void: camera_prewarm_requests[0] += 1)
	var next := scene.get_node(PREFIX + "Footer/NextButton") as Button
	var back := scene.get_node(PREFIX + "Footer/BackButton") as Button
	var preview := scene.get_node(PREFIX + "GameRow/GameDetail/DetailContent/SelectedPreview") as TextureRect
	_assert(buttons.size() == 3, str(resolution) + " original three game-selection buttons remain")
	_assert(next.disabled, str(resolution) + " Next remains disabled before activity selected")
	_assert(preview.texture.resource_path.ends_with("select game default.png"),
		str(resolution) + " default preview asset unchanged")
	_assert_heading(scene, resolution, "default")
	scene.call("_go_next")
	_assert(routes.is_empty(), str(resolution) + " no Next routing without selected activity")
	for activity in ACTIVITIES:
		var button := buttons[activity] as Button
		var before := int(camera_prewarm_requests[0])
		button.pressed.emit()
		_assert(String((scene.get("context") as Dictionary).get("activity", "")) == activity,
			str(resolution) + " exact chosen activity " + activity)
		_assert(not next.disabled and camera_prewarm_requests[0] == before + 1,
			str(resolution) + " selected Next and model prewarm signal intact " + activity)
		_assert(preview.texture != null and not preview.texture.resource_path.ends_with("select game default.png"),
			str(resolution) + " preview changes for " + activity)
		_assert_heading(scene, resolution, activity)
	# Game Setup still owns the grammar topic/mode/difficulty choices. We don't
	# add a fullscreen instruction or a second selector on this scene.
	scene.call("_go_next")
	_assert(routes.size() == 1 and str(routes[0]["route"]) == "play_topic",
		str(resolution) + " missing grammar choices preserves topic flow")
	scene.set_context({"game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy"})
	scene.call("_go_next")
	_assert(routes.size() == 2 and str(routes[1]["route"]) == "calibration"
		and str((routes[1]["payload"] as Dictionary).get("activity", "")) == "Balloon Popping",
		str(resolution) + " complete Game Setup choices still proceed to calibration")
	scene.set_context({"guided_tutorial": true})
	scene.call("_go_next")
	_assert(routes.size() == 3 and str(routes[2]["route"]) == "student_setup"
		and str((routes[2]["payload"] as Dictionary).get("entry_source", "")) == "tutorial",
		str(resolution) + " tutorial setup flow unchanged")
	back.pressed.emit()
	_assert(routes.size() == 4 and str(routes[3]["route"]) == "tutorial_home",
		str(resolution) + " guided Back returns to tutorial home")
	scene.set_context({"guided_tutorial": false})
	back.pressed.emit()
	_assert(routes.size() == 5 and str(routes[4]["route"]) == "student_setup",
		str(resolution) + " ordinary Back returns to student setup")
	for cycle in range(30):
		var selected: String = ACTIVITIES[cycle % ACTIVITIES.size()]
		(buttons[selected] as Button).pressed.emit()
		_assert((scene.get_node("%ActivityInstructionHeading") as Label).text == HEADING,
			str(resolution) + " repeated selections preserve instruction #%d" % cycle)
	scene.queue_free()
	await process_frame
	await process_frame


func _run() -> void:
	for resolution in SIZES:
		await _exercise(resolution)
	print("ACTIVITY CHOICE INSTRUCTION QA: %s checks=%d failures=%d live_services=none" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
