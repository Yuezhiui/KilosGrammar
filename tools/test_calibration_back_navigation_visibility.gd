extends SceneTree

# Focused no-webcam regression for editable Back buttons before and after
# calibration's intro.  Run:
# Godot --headless --path . --script res://tools/test_calibration_back_navigation_visibility.gd
const CALIBRATION_SCENE := "res://ui/vision/calibration.tscn"
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const STAGES := ["CENTER", "RIGHT", "LEFT"]
const STEP_ZONE := ["ArtGuideCenter", "ArtGuideRight", "ArtGuideLeft"]
const INTENDED_RECT := Rect2(Vector2(47, 622), Vector2(255, 85))
const BACK_ART := "res://Components/Gameplay/Calibration/BACK.png"
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pose := root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload available")
	if pose == null:
		_end()
		return
	pose.stop_camera()
	var saved_status: Dictionary = pose.current_status.duplicate(true)
	var original_size := root.size
	var original_content_scale := root.content_scale_size
	var packed := load(CALIBRATION_SCENE) as PackedScene
	_check(packed != null, "calibration scene parses")
	if packed != null:
		for viewport_size in VIEWPORTS:
			root.size = viewport_size
			root.content_scale_size = viewport_size
			await process_frame
			await _check_intro_click(packed, pose, viewport_size)
			await _check_offline_stages_and_keyboard(packed, pose, viewport_size)
			await _check_post_intro_mouse(packed, pose, viewport_size)
	pose.current_status = saved_status
	root.content_scale_size = original_content_scale
	root.size = original_size
	_end()


func _make_screen(packed: PackedScene) -> Control:
	var screen := packed.instantiate() as Control
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	screen.set_process(false)
	return screen


func _check_intro_click(packed: PackedScene, pose: Node, viewport_size: Vector2i) -> void:
	pose.stop_camera()
	var screen := await _make_screen(packed)
	var stage := screen.get_node_or_null("TutorialStage") as Control
	var intro := stage.get_node_or_null("IntroOverlay") as Control
	var intro_back := stage.get_node_or_null("IntroOverlay/IntroBackButton") as Button
	var main_back := stage.get_node_or_null("BackButton") as Button
	var routes: Array[String] = []
	var payloads: Array[Dictionary] = []
	# Assign context directly: this UI-only test must not activate a webcam.
	screen.set("context", {"student_name": "QA STUDENT", "student_id": "QA-001", "activity": "Human Plane"})
	screen.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append(target)
		payloads.append(payload.duplicate(true)))
	_check(intro != null and intro.is_visible_in_tree(),
		"%s intro visible during opening 2.5 seconds" % viewport_size)
	_check(intro_back != null and intro_back.owner == screen and intro_back.is_visible_in_tree()
		and not intro_back.disabled, "%s intro Back enabled and editor-authored" % viewport_size)
	_check(main_back != null and main_back.owner == screen and not main_back.is_visible_in_tree(),
		"%s post-intro Back does not cover intro button" % viewport_size)
	if intro_back != null:
		_check(intro_back.focus_mode == Control.FOCUS_ALL
			and intro_back.get_global_rect().has_point(intro_back.get_global_rect().get_center()),
			"%s intro Back supports native keyboard and mouse" % viewport_size)
		await _click_real_mouse(intro_back)
	_check(routes == ["play_activity"], "%s clicking intro Back navigates to Choose Activity (actual=%s)" %
		[viewport_size, routes])
	_check(payloads.size() == 1 and payloads[0].get("student_id", "") == "QA-001"
		and payloads[0].get("activity", "") == "Human Plane",
		"%s intro Back carries student and chosen game context" % viewport_size)
	_check(not pose.active, "%s intro Back never starts camera" % viewport_size)
	screen.queue_free()
	await process_frame
	await process_frame


func _check_offline_stages_and_keyboard(packed: PackedScene, pose: Node,
		viewport_size: Vector2i) -> void:
	pose.stop_camera()
	# Model failed startup without calling PoseService.start_camera().
	pose.current_status = {"state": "error", "detail": "No camera device detected"}
	var screen := await _make_screen(packed)
	var stage := screen.get_node("TutorialStage") as Control
	var intro := stage.get_node("IntroOverlay") as Control
	var main_back := stage.get_node_or_null("BackButton") as Button
	var intro_back := stage.get_node("IntroOverlay/IntroBackButton") as Button
	var camera := stage.get_node("LiveCameraInset") as TextureRect
	var skeleton := stage.get_node("SkeletonPlacement") as ReferenceRect
	var status := stage.get_node("CameraUnavailableLabel") as Label
	var results: Array[String] = []
	screen.requested.connect(func(target: String, _payload: Dictionary) -> void: results.append(target))
	_check(main_back != null and main_back.owner == screen,
		"%s normal Back is serialized/editable in Calibration scene" % viewport_size)
	if main_back == null:
		screen.queue_free()
		await process_frame
		return
	_check(main_back.position.is_equal_approx(INTENDED_RECT.position)
		and main_back.size.is_equal_approx(INTENDED_RECT.size),
		"%s normal Back position and size stay authored, not calculated at runtime" % viewport_size)
	var intro_art := intro_back.get_node_or_null("Artwork") as TextureRect
	var active_art := main_back.get_node_or_null("Artwork") as TextureRect
	_check(intro_art != null and active_art != null
		and intro_art.owner == screen and active_art.owner == screen
		and intro_art.texture != null and active_art.texture != null
		and intro_art.texture.resource_path == BACK_ART
		and active_art.texture.resource_path == BACK_ART
		and main_back.accessibility_name == "Back to Choose Activity"
		and intro_back.accessibility_name == "Back to Choose Activity",
			"%s both Back buttons use the updated calibration BACK.png with activity destination" % viewport_size)
	_check(main_back.get_theme_stylebox("focus") is StyleBoxEmpty
		and intro_back.get_theme_stylebox("focus") is StyleBoxEmpty,
		"%s neither Back button draws yellow focus corners or another rectangle" % viewport_size)
	_check(main_back.get_theme_stylebox("normal") == intro_back.get_theme_stylebox("normal")
		and main_back.get_theme_font("font") == intro_back.get_theme_font("font"),
		"%s normal Back matches intro artwork-button styling" % viewport_size)
	_check(camera.size.is_equal_approx(Vector2(1007, 446))
		and skeleton.size.is_equal_approx(camera.size),
		"%s camera and independent skeleton geometry match for accurate pose overlay" % viewport_size)
	_check(not main_back.get_global_rect().intersects(camera.get_global_rect()),
		"%s normal Back stays below camera preview, never blocks skeleton/video" % viewport_size)
	_check(_screen_rect(viewport_size).encloses(main_back.get_global_rect()),
		"%s normal Back fully within screen" % viewport_size)
	for art_name in ["ArtStep1", "ArtStep2", "ArtStep3", "ArtTitleCenter",
		"ArtTitleRight", "ArtTitleLeft", "ArtMoveHintCenter", "ArtMoveHintRight",
		"ArtMoveHintLeft", "ArtCat"]:
		var art := stage.get_node_or_null(art_name) as Control
		if art != null:
			_check(not main_back.get_global_rect().intersects(art.get_global_rect()),
					"%s Back avoids interactive foreground artwork %s" % [viewport_size, art_name])
	# No successful pose, so intro time must only switch UI, not game state.
	# Godot can process one or two real frames during mounting. Subtract the
	# already-elapsed introduction time to check its precise 2.5s boundary.
	screen.call("_process", maxf(0.0, 2.48 - float(screen.get("intro_elapsed"))))
	_check(intro.is_visible_in_tree() and not main_back.is_visible_in_tree(),
		"%s normal Back stays hidden just before intro ends" % viewport_size)
	screen.call("_process", 0.02)
	await process_frame
	await process_frame
	_check(not intro.visible and not bool(screen.get("intro_running")),
		"%s intro switches to calibration after 2.5 seconds" % viewport_size)
	_check(main_back.visible and main_back.is_visible_in_tree() and not main_back.disabled
		and main_back.focus_mode == Control.FOCUS_ALL,
		"%s Back enabled and visible after intro when camera offline" % viewport_size)
	_check(root.gui_get_focus_owner() == main_back,
		"%s focus transfers from Intro Back to main Back" % viewport_size)
	_check(status.visible and status.is_visible_in_tree()
		and status.text.to_upper().contains("CAMERA"),
		"%s offline camera warning visible without hiding Back" % viewport_size)
	for index in range(STAGES.size()):
		screen.set("live_step", index)
		screen.call("_update_target_guide")
		screen.call("_set_stage_instruction")
		screen.call("_process", 4.0) # No valid pose: cannot complete a stage.
		_check(int(screen.get("live_step")) == index and not screen.get("passing_to_ready"),
			"%s offline %s never advances into gameplay" % [viewport_size, STAGES[index]])
		_check(main_back.visible and main_back.is_visible_in_tree() and not main_back.disabled,
			"%s Back stays usable for offline %s" % [viewport_size, STAGES[index]])
		_check(stage.get_node(STEP_ZONE[index]).visible,
			"%s %s yellow PNG guide still active with Back visible" % [viewport_size, STAGES[index]])
		_check(not (stage.get_node(["CenterCalibrationLane", "RightCalibrationLane", "LeftCalibrationLane"][index]) as Control).visible,
			"%s %s old green duplicate panel remains hidden" % [viewport_size, STAGES[index]])
		_check(camera.size.is_equal_approx(Vector2(1007, 446))
			and main_back.position.is_equal_approx(INTENDED_RECT.position),
			"%s %s cannot move the camera or Back art layout" % [viewport_size, STAGES[index]])
	_check(results.is_empty(), "%s offline stages emit no gameplay request" % viewport_size)
	await _press_real_keyboard(main_back)
	_check(results == ["play_activity"], "%s Enter on focused Back navigates to Choose Activity only (actual=%s)" %
		[viewport_size, results])
	_check(not pose.active, "%s keyboard Back leaves webcam stopped" % viewport_size)
	screen.queue_free()
	await process_frame
	await process_frame


func _check_post_intro_mouse(packed: PackedScene, pose: Node,
		viewport_size: Vector2i) -> void:
	pose.stop_camera()
	pose.current_status = {"state": "error", "detail": "Camera failed to initialize"}
	var screen := await _make_screen(packed)
	var stage := screen.get_node("TutorialStage") as Control
	var back := stage.get_node("BackButton") as Button
	var routes: Array[String] = []
	screen.requested.connect(func(target: String, _payload: Dictionary) -> void: routes.append(target))
	screen.call("_process", 2.51)
	await process_frame
	_check(back.is_visible_in_tree() and not back.disabled,
		"%s Back visibly survives camera initialization failure" % viewport_size)
	await _click_real_mouse(back)
	_check(routes == ["play_activity"],
		"%s actual mouse click after intro returns only to Choose Activity (%s)" % [viewport_size, routes])
	_check(not pose.active, "%s offline mouse Back does not open a camera" % viewport_size)
	screen.queue_free()
	await process_frame
	await process_frame


func _click_real_mouse(button: Button) -> void:
	# Godot's GUI viewport processes actual native-style mouse events, rather
	# than manually emitting Button.pressed.
	var coordinate := button.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = coordinate
	move.global_position = coordinate
	root.push_input(move, true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = coordinate
	press.global_position = coordinate
	press.pressed = true
	root.push_input(press, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = coordinate
	release.global_position = coordinate
	release.pressed = false
	root.push_input(release, true)
	await process_frame


func _press_real_keyboard(button: Button) -> void:
	button.grab_focus()
	await process_frame
	var keydown := InputEventKey.new()
	keydown.keycode = KEY_ENTER
	keydown.physical_keycode = KEY_ENTER
	keydown.pressed = true
	root.push_input(keydown, true)
	var keyup := InputEventKey.new()
	keyup.keycode = KEY_ENTER
	keyup.physical_keycode = KEY_ENTER
	keyup.pressed = false
	root.push_input(keyup, true)
	await process_frame


func _screen_rect(size: Vector2i) -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(size))


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _end() -> void:
	for problem in failures:
		printerr("CALIBRATION BACK FAIL: ", problem)
	print("CALIBRATION BACK: %s (%d/%d assertions)" %
		["PASS" if failures.is_empty() else "FAIL", checks - failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
