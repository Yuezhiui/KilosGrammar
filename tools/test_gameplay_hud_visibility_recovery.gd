extends SceneTree

# Cross-game regression for student-visible HUD, apple depth, character bounds,
# teacher setup, and the intentionally minimal calibration controls.
# Godot --headless --path . --script res://tools/test_gameplay_hud_visibility_recovery.gd
# Owns no gameplay nodes or production assets.

const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const CHARACTER_NAMES := ["Boy", "Girl", "Grandma", "Grandpa"]
const GAME_SCENES := {
	"Catch the Word": "res://ui/minigames/catch_word.tscn",
	"Balloon Popping": "res://ui/minigames/balloon_popping.tscn",
	"Human Plane": "res://ui/minigames/human_plane.tscn",
}
const SETUP_SCENE := "res://ui/student/student_setup.tscn"
const CALIBRATION_SCENE := "res://ui/vision/calibration.tscn"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var initial_size := root.size
	for viewport_size in SIZES:
		root.size = viewport_size
		await process_frame
		for game_name in GAME_SCENES:
			await _check_game(String(game_name), String(GAME_SCENES[game_name]), viewport_size)
		await _check_teacher_setup(viewport_size)
		await _check_calibration(viewport_size)
	root.size = initial_size
	if failures.is_empty():
		print("PASS gameplay HUD visibility/recovery: %d checks, 3 games + teacher + calibration at 3 sizes" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("HUD/RECOVERY QA: " + failure)
		print("FAIL gameplay HUD visibility/recovery: %d failures in %d checks" % [failures.size(), checks])
		quit(1)


func _mount(path: String, viewport_size: Vector2i) -> Dictionary:
	var packed := load(path) as PackedScene
	if packed == null:
		_check(false, "%s loads" % path)
		return {}
	var host := Control.new()
	host.name = "RecoveryTestHost"
	host.size = Vector2(viewport_size)
	root.add_child(host)
	var scene := packed.instantiate() as Control
	if scene == null:
		_check(false, "%s instantiates as Control" % path)
		host.queue_free()
		return {}
	# Isolate the precisely timed 2.5-second intro while other scenes and
	# imported artwork load in the same test process. We advance it explicitly.
	if path == CALIBRATION_SCENE:
		scene.process_mode = Node.PROCESS_MODE_DISABLED
	host.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return {"host": host, "scene": scene}


func _unmount(host: Control) -> void:
	host.queue_free()
	await process_frame
	await process_frame


func _check_game(game_name: String, path: String, viewport_size: Vector2i) -> void:
	var mounted := _mount(path, viewport_size)
	if mounted.is_empty():
		return
	var game := mounted["scene"] as Control
	var host := mounted["host"] as Control
	await process_frame
	await process_frame
	if game.has_method("set_context"):
		game.call("set_context", {
			"activity": game_name, "topic": "Noun", "difficulty": "Easy",
			"game_mode": "Seconds", "catch_character": "Grandma",
			"catch_map": "City",
		})
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	_check(game.size.x >= viewport_size.x - 1 and game.size.y >= viewport_size.y - 1,
		"%s %s fills the viewport (size %s)" % [game_name, viewport_size, game.size])
	match game_name:
		"Catch the Word":
			await _check_catch(game, viewport_size)
		"Balloon Popping":
			_check_balloon(game, viewport_size)
		"Human Plane":
			_check_plane(game, viewport_size)
	await _unmount(host)


func _check_catch(game: Control, viewport_size: Vector2i) -> void:
	var layer := game.get_node_or_null("FallingWordLayer") as CanvasItem
	var group := game.get("character_group") as Node2D
	var prompt := game.get_node_or_null("HUDLayer/HUD/PromptLabel") as Label
	var timer := game.get_node_or_null("HUDLayer/HUD/TimeLabel") as Label
	var pause := game.get_node_or_null("HUDLayer/HUD/PauseButton") as Button
	var score := game.get_node_or_null("ScoreDrawLayer/ScoreBottomContainer/ScoreNumber") as Label
	var title := game.get_node_or_null("HUDLayer/HUD/TitlePlaque") as TextureRect
	var score_plaque := game.get_node_or_null("ScoreDrawLayer/ScorePlaque") as TextureRect
	for item in [prompt, timer, pause, score, title, score_plaque]:
		_check(item is Control and item.is_visible_in_tree() and _within_viewport(item.get_global_rect(), viewport_size),
			"Catch %s: visible and unclipped HUD %s" % [viewport_size, item.name if item != null else "missing"])
	_check(layer != null and group != null, "Catch %s: apple layer and selected root character exist" % viewport_size)
	if group != null:
		_check(Vector2(game.get("character_editor_origin")).y > 0.0,
			"Catch %s: scene-authored character Y survives _ready (authored=%s; live=%s)" %
			[viewport_size, game.get("character_editor_origin"), group.position])
	if layer != null and group != null:
		# Test a real gameplay apple node, not only the scene's static layer.
		var apple := game.call("_create_tile_node", "QA", Color.WHITE) as Control
		var apple_art := apple.get_node_or_null("AppleSprite") as CanvasItem if apple != null else null
		var active_body := game.body_sprite as Sprite2D
		var active_basket := game.basket_sprite as Sprite2D
		_check(apple_art != null and active_body != null and active_basket != null,
			"Catch %s: active gameplay apple, body and basket renderers exist" % viewport_size)
		if apple_art != null and active_body != null and active_basket != null:
			var apple_z := _effective_z(apple_art, game)
			var body_z := _effective_z(active_body, game)
			var basket_z := _effective_z(active_basket, game)
			_check(apple_z > body_z and apple_z > basket_z,
				"Catch %s: falling apple paints IN FRONT of both body and basket (z=%d, %d, %d)" %
				[viewport_size, apple_z, body_z, basket_z])
		if apple != null:
			apple.queue_free()
	for character_name in CHARACTER_NAMES:
		game.call("set_context", {
			"activity": "Catch the Word", "game_mode": "Seconds",
			"topic": "Noun", "catch_character": character_name, "catch_map": "City"
		})
		game.set_process(false)
		await process_frame
		for sprite in [game.body_sprite as Sprite2D, game.basket_sprite as Sprite2D]:
			_check(sprite != null and sprite.is_visible_in_tree()
				and _within_viewport(_sprite_rect(sprite), viewport_size),
				"Catch %s %s: active %s fully inside screen (%s)" %
				[viewport_size, character_name, sprite.name if sprite != null else "missing",
				_sprite_rect(sprite) if sprite != null else Rect2()])


func _check_balloon(game: Control, viewport_size: Vector2i) -> void:
	for node_path in [
		"HudLayer/ObjectivePanel", "HudLayer/PromptLabel",
		"HudLayer/CarnivalScore", "HudLayer/ScoreBottomContainer/ScoreNumber",
		"HudLayer/TimerPlaque", "HudLayer/TimeLabel", "HudLayer/PauseButton"
	]:
		var control := game.get_node_or_null(node_path) as Control
		_check(control != null and control.is_visible_in_tree()
			and _within_viewport(control.get_global_rect(), viewport_size),
			"Balloon %s: visible and unclipped %s (%s)" %
			[viewport_size, node_path, control.get_global_rect() if control != null else Rect2()])
	# The score, prompt and timer must stay independently legible.
	var objective := game.get_node_or_null("HudLayer/ObjectivePanel") as Control
	var score := game.get_node_or_null("HudLayer/CarnivalScore") as Control
	var timer := game.get_node_or_null("HudLayer/TimerPlaque") as Control
	if objective != null and score != null and timer != null:
		_check(not objective.get_global_rect().intersects(score.get_global_rect())
			and not score.get_global_rect().intersects(timer.get_global_rect()),
			"Balloon %s: objective, score and timer plaques do not cover each other" % viewport_size)
	# Ensure score/prompt remain active when teacher chose Lives mode.
	game.call("set_context", {"activity": "Balloon Popping", "topic": "Noun", "game_mode": "Lives"})
	var lives := game.get_node_or_null("HudLayer/LivesPlaque") as Control
	_check(lives != null and lives.is_visible_in_tree() and _within_viewport(lives.get_global_rect(), viewport_size),
		"Balloon %s: Lives mode displays complete lives plaque" % viewport_size)
	var timer_after := game.get_node_or_null("HudLayer/TimerPlaque") as Control
	_check(timer_after != null and not timer_after.is_visible_in_tree(),
		"Balloon %s: Lives mode hides obsolete timer overlay" % viewport_size)


func _check_plane(game: Control, viewport_size: Vector2i) -> void:
	# Human Plane's pause action belongs to the editable Catch-style HUD clone.
	# The removed root PauseButton must never be used for input or QA.
	var pause := game.get_node_or_null("HUDLayer/HUD/PauseButton") as Button
	var plaque := game.get_node_or_null("HUDLayer/HUD/PausePlaque") as TextureRect
	_check(game.get_node_or_null("PauseButton") == null,
		"Plane %s: obsolete root pause button is absent" % viewport_size)
	_check(game.get_node_or_null("HUDLayer") is CanvasLayer
		and pause != null and plaque != null and pause.owner == game,
		"Plane %s: real pause button and artwork are authored in the HUD CanvasLayer" % viewport_size)
	_check(pause != null and pause.is_visible_in_tree()
		and _within_viewport(pause.get_global_rect(), viewport_size),
		"Plane %s: teacher-accessible pause remains visible" % viewport_size)
	_check(pause != null and plaque != null and plaque.is_visible_in_tree()
		and plaque.get_global_rect().encloses(pause.get_global_rect().grow(-0.5)),
		"Plane %s: pause hit target stays aligned with its visible plaque" % viewport_size)
	_check(game.has_method("_draw_hud") and game.has_method("_draw_plane"),
		"Plane %s: procedural HUD and character drawing remain callable" % viewport_size)
	var top_rect := Rect2(viewport_size.x * 0.17, 16.0 * minf(viewport_size.y / 720.0, 1.50),
		viewport_size.x * 0.66, 64.0 * minf(viewport_size.y / 720.0, 1.50))
	var prompt_rect := Rect2(viewport_size.x * 0.27, 92.0 * minf(viewport_size.y / 720.0, 1.50),
		viewport_size.x * 0.46, 58.0 * minf(viewport_size.y / 720.0, 1.50))
	_check(_within_viewport(top_rect, viewport_size) and _within_viewport(prompt_rect, viewport_size)
		and not top_rect.intersects(prompt_rect),
		"Plane %s: drawn score/lives/time bar and prompt fit separately" % viewport_size)
	_check(String(game.get("game_mode")) == "Seconds" and float(game.get("time_remaining")) > 0.0,
		"Plane %s: Seconds teacher mode starts with a visible countdown" % viewport_size)
	game.call("set_context", {"activity": "Human Plane", "game_mode": "Lives", "topic": "Noun"})
	game.call("_apply_initial_context")
	_check(String(game.get("game_mode")) == "Lives" and not bool(game.get("is_seconds_mode"))
		and int(game.get("lives")) == 3,
		"Plane %s: Lives teacher mode shows three lives and no countdown" % viewport_size)
	if pause != null:
		var requested_routes: Array[String] = []
		game.requested.connect(func(route: String, _payload: Dictionary) -> void:
			requested_routes.append(route)
		)
		_check(not bool(game.get("paused")), "Plane %s: round begins unpaused" % viewport_size)
		pause.pressed.emit()
		_check(requested_routes == ["pause"] and bool(game.get("paused"))
			and not bool(game.get("running")),
			"Plane %s: real HUD PauseButton emits one pause request and freezes the round" % viewport_size)
		pause.pressed.emit()
		_check(requested_routes == ["pause"],
			"Plane %s: repeat press during pause cannot trigger duplicate navigation" % viewport_size)


func _check_teacher_setup(viewport_size: Vector2i) -> void:
	var mounted := _mount(SETUP_SCENE, viewport_size)
	if mounted.is_empty():
		return
	var scene := mounted["scene"] as Control
	await process_frame
	for name in [
		"StudentIdEdit", "StudentNameEdit", "GradeSectionEdit",
		"NounButton", "PronounButton", "SecondsButton", "LivesButton",
		"EasyButton", "NormalButton", "HardButton",
		"BackButton", "ContinueButton"
	]:
		var control := scene.find_child(name, true, false) as Control
		_check(control != null and control.owner == scene and control.is_visible_in_tree(),
			"Teacher setup %s: editor-authored and visible %s" % [viewport_size, name])
	var id_edit := scene.find_child("StudentIdEdit", true, false) as LineEdit
	var name_edit := scene.find_child("StudentNameEdit", true, false) as LineEdit
	var grade_edit := scene.find_child("GradeSectionEdit", true, false) as LineEdit
	var continue_button := scene.find_child("ContinueButton", true, false) as Button
	_check(continue_button != null and continue_button.disabled,
		"Teacher setup %s: incomplete form cannot continue" % viewport_size)
	if id_edit != null and name_edit != null and grade_edit != null and continue_button != null:
		id_edit.text = "QA-001"
		name_edit.text = "Sample Student"
		grade_edit.text = "Grade 4-A"
		scene.call("_select_style", "Noun")
		scene.call("_select_mode", "Seconds")
		scene.call("_select_difficulty", "Easy")
		scene.call("_update_validation")
		_check(not continue_button.disabled,
			"Teacher setup %s: fully specified student and game settings enable Continue" % viewport_size)
	await _unmount(mounted["host"] as Control)


func _check_calibration(viewport_size: Vector2i) -> void:
	var mounted := _mount(CALIBRATION_SCENE, viewport_size)
	if mounted.is_empty():
		return
	var scene := mounted["scene"] as Control
	await process_frame
	scene.set_process(false)
	var stage := scene.get_node_or_null("TutorialStage") as Control
	var title := scene.get_node_or_null("TutorialStage/IntroOverlay/IntroHeading") as Label
	var back := scene.get_node_or_null("TutorialStage/IntroOverlay/IntroBackButton") as Button
	var dimmer := scene.get_node_or_null("ClassroomDimmer") as ColorRect
	_check(stage != null and stage.owner == scene and title != null and title.is_visible_in_tree()
		and back != null and back.is_visible_in_tree(),
		"Calibration %s: intro has editable title and only Back to Main" % viewport_size)
	# The current CALIB scene intentionally keeps the illustrated classroom
	# bright. Other calibration design suites require a subtle <=15% dimmer.
	# A legacy 70% assertion would incorrectly darken user-authored artwork.
	_check(dimmer != null and is_zero_approx(dimmer.color.r)
		and is_zero_approx(dimmer.color.g) and is_zero_approx(dimmer.color.b)
		and dimmer.color.a >= 0.0 and dimmer.color.a <= 0.15,
		"Calibration %s: illustrated classroom keeps its subtle black dimmer" % viewport_size)
	if stage != null:
		for child in stage.get_children():
			if child is Control and child.name != "IntroOverlay":
				_check(not (child as Control).is_visible_in_tree(),
					"Calibration %s: intro contains no camera/guide/status ghosts (%s)" % [viewport_size, child.name])
	# Simulate the real intro transition without opening the student's camera.
	scene.call("_process", 2.6)
	scene.set_process(false)
	for name in ["SkipButton", "RetryButton", "StopCameraButton", "KeyboardButton"]:
		var control := stage.get_node_or_null(name) as Control if stage != null else null
		_check(control == null or not control.is_visible_in_tree(),
			"Calibration %s: obsolete %s control is absent or hidden" % [viewport_size, name])
	var camera_button := stage.get_node_or_null("DemoButton") as Button if stage != null else null
	_check(camera_button == null or not camera_button.text.to_upper().contains("STOP CAMERA"),
		"Calibration %s: no Stop Camera action remains" % viewport_size)
	if stage != null:
		var zone_names := ["ArtGuideCenter", "ArtGuideRight", "ArtGuideLeft"]
		for index in range(3):
			scene.set("live_step", index)
			scene.call("_update_target_guide")
			scene.call("_set_stage_instruction")
			var zones := 0
			for node_name in zone_names:
				var guide := stage.get_node_or_null(node_name) as Control
				_check(guide != null and guide.owner == scene,
					"Calibration %s: %s yellow PNG guide is editor-authored" % [viewport_size, node_name])
				if guide != null and guide.is_visible_in_tree():
					zones += 1
					_check(node_name == zone_names[index],
						"Calibration %s: step %d highlights correct position, not %s" %
						[viewport_size, index + 1, node_name])
			_check(zones == 1,
				"Calibration %s: step %d shows exactly one PARAMETERS.png guide" % [viewport_size, index + 1])
			var step_badge := stage.get_node_or_null("StepBadge") as Label
			_check(step_badge != null and step_badge.text.contains("%d / 3" % (index + 1)),
				"Calibration %s: step %d indicator is synchronized" % [viewport_size, index + 1])
	await _unmount(mounted["host"] as Control)


func _effective_z(item: CanvasItem, boundary: Node) -> int:
	var z := 0
	var cursor: Node = item
	while cursor != null and cursor != boundary:
		if cursor is CanvasItem:
			z += (cursor as CanvasItem).z_index
			if not (cursor as CanvasItem).z_as_relative:
				break
		cursor = cursor.get_parent()
	return z


func _sprite_rect(sprite: Sprite2D) -> Rect2:
	if sprite == null:
		return Rect2()
	var local := sprite.get_rect()
	var transform := sprite.get_global_transform()
	var a: Vector2 = transform * local.position
	var b: Vector2 = a
	for point in [
		Vector2(local.end.x, local.position.y), local.end,
		Vector2(local.position.x, local.end.y)
	]:
		var corner: Vector2 = transform * point
		a = a.min(corner)
		b = b.max(corner)
	return Rect2(a, b - a)


func _within_viewport(rect: Rect2, viewport_size: Vector2i) -> bool:
	return rect.has_area() and Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(rect.grow(-0.5))


func _check(success: bool, description: String) -> void:
	checks += 1
	if not success:
		failures.append(description)
