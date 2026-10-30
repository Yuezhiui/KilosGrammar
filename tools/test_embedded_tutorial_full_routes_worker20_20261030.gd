extends SceneTree

# QA-only regression. Exercise real MainMenu buttons, activity chooser, Student
# Setup, intercepted physical calibration and the actual gameplay wrapper.
# No webcam, PostgreSQL, HTTP API, persistent scores or teacher profile writes.
# Run with isolated APPDATA/LOCALAPPDATA containing 'kg_worker20_isolated'.
# Optional -- --cycles=120 --native-capture when running with OpenGL3.
const MENU_SCENE := "res://ui/main_menu/main_menu.tscn"
const MENU_HARNESS := "res://tools/test_play_router_harness_20261030.gd"
const GAMEPLAY := "res://ui/play/gameplay/gameplay.tscn"
const GAMES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const OUTPUT := "res://showcase/qa_embedded_tutorial_routes_worker20"

class FakeDatabase:
	extends Node
	var network_calls := 0
	func check_health(_extra: Dictionary = {}) -> int:
		network_calls += 1
		return -1
	func ensure_local_service(_extra: Dictionary = {}) -> void:
		network_calls += 1
	func find_student(_student_id: String, _extra: Dictionary = {}) -> int:
		network_calls += 1
		return -1
	func find_student_by_name(_name: String, _extra: Dictionary = {}) -> int:
		network_calls += 1
		return -1
	func cancel_request(_id: int) -> void:
		pass

var failures: Array[String] = []
var checks := 0
var tutorial_launches := 0
var play_launches := 0
var screenshots := 0
var app: Control
var db: FakeDatabase
var native_capture := false
var cycles := 120


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var qa_dir := OS.get_user_data_dir().replace("\\", "/").to_lower()
	check(qa_dir.contains("kg_worker20_isolated"), "test uses isolated user:// directory, got " + qa_dir)
	if not failures.is_empty():
		_finish()
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cycles="):
			cycles = maxi(1, arg.trim_prefix("--cycles=").to_int())
	native_capture = DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().has("--native-capture")
	if native_capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var pose := root.get_node_or_null("PoseService")
	check(pose != null and not pose.active, "camera service initially inactive")
	if pose == null or pose.active:
		_finish()
		return
	pose.set_process(false)
	for size_index in range(RESOLUTIONS.size()):
		var size: Vector2i = RESOLUTIONS[size_index]
		root.size = size
		root.content_scale_size = size
		if native_capture:
			DisplayServer.window_set_size(size)
		await process_frame
		await _start_app()
		for cycle in range(cycles):
			if (int(cycle / GAMES.size()) % RESOLUTIONS.size()) != size_index:
				continue
			var activity: String = GAMES[cycle % GAMES.size()]
			var mode := "Lives" if cycle % 2 else "Seconds"
			await _route_case(cycle, size, activity, mode, true)
			await _route_case(cycle, size, activity, mode, false)
		check(not pose.active, "no webcam started at " + str(size))
		await _stop_app()
	check(db == null or db.network_calls == 0, "mock has no network calls")
	pose.set_process(true)
	_finish()


func _start_app() -> void:
	var scene := load(MENU_SCENE) as PackedScene
	var harness := load(MENU_HARNESS) as Script
	check(scene != null and harness != null and harness.can_instantiate(), "menu and isolated router compiled")
	if scene == null or harness == null or not harness.can_instantiate():
		return
	app = scene.instantiate() as Control
	app.set_script(harness)
	root.add_child(app)
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	db = FakeDatabase.new()
	db.name = "Worker20InMemoryDatabase"
	app.add_child(db)
	app.set("database_client", db)
	app.set("database_online", false)
	await process_frame
	check(String(app.get("current_route")) == "main", "Main Menu test harness ready")


func _stop_app() -> void:
	if is_instance_valid(app):
		app.call("_return_to_main")
		await process_frame
		app.queue_free()
		await process_frame
		await process_frame
	app = null
	db = null


func _route_case(cycle: int, resolution: Vector2i, activity: String, mode: String, tutorial: bool) -> void:
	var tag := "%d %s %s %s %s" % [cycle, str(resolution), activity, mode, "Tutorial" if tutorial else "Play"]
	if not is_instance_valid(app):
		check(false, tag + ": application router unavailable")
		return
	app.call("_return_to_main")
	await process_frame
	app.set("database_online", false)
	if tutorial:
		(app.get_node("MainLayer/CenterMenu/Tutorial") as Button).pressed.emit()
		await process_frame
		check(_route() == "tutorial_home", tag + ": Main Menu Tutorial opens tutorial home")
		if _route() != "tutorial_home":
			return
		var tutorial_home := app.get("active_panel") as Control
		(tutorial_home.get_node("TutorialStage/StartButton") as Button).pressed.emit()
		await process_frame
		check(_route() == "play_activity", tag + ": Tutorial Start opens activity selection")
	else:
		(app.get_node("MainLayer/CenterMenu/Play") as Button).pressed.emit()
		await process_frame
		check(_route() == "student_setup", tag + ": Play opens Student Setup")
	if tutorial:
		if _route() != "play_activity":
			return
		await _select_activity(activity)
		check(_route() == "student_setup", tag + ": Tutorial activity selection opens setup")
	if _route() != "student_setup":
		return
	var setup := app.get("active_panel") as Control
	_edit(setup.get("_student_id_edit") as LineEdit, "KG-W20-%04d" % cycle)
	_edit(setup.get("_name_edit") as LineEdit, "QA Test Student")
	_edit(setup.get("_grade_edit") as LineEdit, "Grade 4 Jade")
	(setup.get("_style_buttons")["Noun"] as Button).pressed.emit()
	(setup.get("_mode_buttons")[mode] as Button).pressed.emit()
	(setup.get("_difficulty_buttons")["Easy"] as Button).pressed.emit()
	var continue_button := setup.get("_continue_button") as Button
	check(not continue_button.disabled, tag + ": completed fields enable Continue")
	continue_button.pressed.emit()
	await process_frame
	if not tutorial:
		check(_route() == "play_activity", tag + ": Play Continue opens activity selection")
		if _route() == "play_activity":
			await _select_activity(activity)
	check(_route() == "calibration", tag + ": selection reaches physical calibration route")
	if _route() != "calibration":
		return
	var payload: Dictionary = app.get("intercepted_calibration_payload")
	check(String(payload.get("activity", "")) == activity
		and String(payload.get("game_mode", "")) == mode
		and String(payload.get("student_id", "")) == "KG-W20-%04d" % cycle,
		tag + ": session activity/mode/student retained through calibration")
	check(bool(payload.get("guided_tutorial", false)) == tutorial
		and String(payload.get("entry_source", "")) == ("tutorial" if tutorial else "play"),
		tag + ": tutorial practice flag and entry source retained")
	check(bool(payload.get("camera_requested", false)) and not bool(payload.get("keyboard_mode", true)),
		tag + ": physical calibration requested for both routes")
	# The test harness only intercepts calibration. Hand this real route payload
	# to the same real Gameplay wrapper, with physical camera deliberately off.
	var context := payload.duplicate(true)
	context["camera_live"] = false
	context["start_countdown"] = true
	context["calibration_measured"] = false
	var wrapper_scene := load(GAMEPLAY) as PackedScene
	check(wrapper_scene != null, tag + ": gameplay wrapper loads")
	if wrapper_scene == null:
		return
	var wrapper := wrapper_scene.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context(context)
	await process_frame
	await process_frame
	var game := wrapper.get("active_game") as Control
	check(game != null, tag + ": actual integrated minigame mounted")
	if game == null:
		wrapper.queue_free()
		await process_frame
		return
	check(game.process_mode == Node.PROCESS_MODE_DISABLED, tag + ": game frozen on entry")
	if tutorial:
		tutorial_launches += 1
		await _tutorial_case(wrapper, game, tag, resolution, activity, mode, cycle)
	else:
		play_launches += 1
		await _play_case(wrapper, game, tag)
	wrapper.queue_free()
	await process_frame
	await process_frame
	app.call("_return_to_main")
	await process_frame


func _select_activity(activity: String) -> void:
	var chooser := app.get("active_panel") as Control
	(chooser.get("activity_buttons")[activity] as Button).pressed.emit()
	(chooser.get("next_button") as Button).pressed.emit()
	await process_frame


func _tutorial_case(wrapper: Control, game: Control, tag: String, size: Vector2i, activity: String, mode: String, cycle: int) -> void:
	check(String(wrapper.get("guided_stage")) == "tutorial", tag + ": tutorial stage before countdown")
	check(game.has_method("is_tutorial_active") and bool(game.call("is_tutorial_active")), tag + ": actual guide active")
	check(wrapper.get("countdown_panel") == null, tag + ": 3-2-1 absent until explanations end")
	var initial := _snapshot(game)
	var names := ["prompt", "movement", "seconds" if mode == "Seconds" else "lives", "score", "pause"]
	if activity == "Human Plane":
		names = ["movement", "ring", "prompt", "mode", "score", "pause"]
	var next := _button(game, "NextButton")
	var skip := _button(game, "SkipButton")
	var back := _button(game, "BackButton")
	var replay := _button(game, "ReplayButton")
	var pause := _button(game, "PauseVoiceButton")
	var narration := _audio(game)
	check(next != null and next.can_process() and skip != null and skip.can_process(), tag + ": Next/Skip controls accept input when game is frozen")
	check(back != null and back.can_process(), tag + ": Back exists and accepts input")
	check(replay != null and replay.can_process(), tag + ": Replay Voice exists and accepts input")
	check(pause != null and pause.can_process(), tag + ": Pause Voice exists and accepts input")
	check(narration != null and narration.can_process(), tag + ": independent narration stream can process")
	for index in range(names.size()):
		check(bool(game.call("is_tutorial_active")), tag + ": explanation remains open at step %d" % index)
		check(wrapper.get("countdown_panel") == null, tag + ": no early countdown at step %d" % index)
		var expected_title := _step_title(game, activity)
		check(not expected_title.is_empty(), tag + ": step %d has explanatory title" % index)
		check(_step_index(game, activity) == index, tag + ": ordered step index %d" % index)
		check(_guide_visible(game, activity), tag + ": embedded dim overlay visible at step %d" % index)
		check(_focus_correct(game, activity, names[index], size), tag + ": cutout focuses actual %s component" % names[index])
		check(not _visible_arrow(game), tag + ": directional arrows hidden at step %d" % index)
		var audio_id: String = "seconds" if names[index] == "mode" and mode == "Seconds" else "lives" if names[index] == "mode" else names[index]
		var audio_file := "res://assets/audio/tutorial_spotlight/%s_%s.wav" % [_audio_prefix(activity), audio_id]
		check(ResourceLoader.exists(audio_file), tag + ": pre-recorded voice exists for " + audio_id)
		check(narration != null and narration.stream != null and narration.playing,
			tag + ": matching step narration actually started for " + audio_id)
		if index == 1 and back != null and next != null:
			back.pressed.emit()
			check(_step_index(game, activity) == 0, tag + ": Back revisits previous component")
			next.pressed.emit()
			check(_step_index(game, activity) == 1, tag + ": Next reenters current component")
		if index == 2 and replay != null and pause != null and narration != null:
			pause.pressed.emit()
			check(narration.stream_paused, tag + ": Pause Voice pauses stream")
			pause.pressed.emit()
			check(not narration.stream_paused, tag + ": Resume Voice resumes stream")
			replay.pressed.emit()
			check(narration.playing, tag + ": Replay Voice replays current clip")
		if native_capture and cycle < 9 and index in [0, names.size() - 1]:
			await _capture(size, activity, mode, names[index])
		game.call("_process", 0.75)
		check(_snapshot(game) == initial, tag + ": no time/score/lives advancement during guide step %d" % index)
		if next != null:
			next.pressed.emit()
	check(not bool(game.call("is_tutorial_active")), tag + ": Next completed embedded guide")
	await process_frame
	check(String(wrapper.get("guided_stage")) == "countdown", tag + ": exactly one countdown after final step")
	var panel := wrapper.get("countdown_panel") as Control
	check(panel != null and (panel.get_node("CountdownNumber") as Label).text == "3", tag + ": 3-2-1 starts at 3")
	if next != null:
		next.pressed.emit()
	if skip != null:
		skip.pressed.emit()
	check(wrapper.get("countdown_panel") == panel, tag + ": duplicate Next/Skip cannot restart countdown")
	check(_snapshot(game) == initial, tag + ": countdown begins with unchanged score/time/lives")
	for tick in range(3):
		wrapper.call("_on_countdown_tick")
	check(wrapper.get("countdown_panel") == null and game.process_mode == Node.PROCESS_MODE_INHERIT,
		tag + ": GO releases same game once")
	check(_snapshot(game) == initial, tag + ": 3-2-1 does not consume score/time/lives")


func _play_case(wrapper: Control, game: Control, tag: String) -> void:
	check(String(wrapper.get("guided_stage")) == "countdown", tag + ": Play starts countdown directly")
	check(not bool(game.call("is_tutorial_active")), tag + ": Play never starts embedded explanations")
	check(not _guide_visible(game, String(wrapper.context.get("activity", ""))), tag + ": Play guide remains hidden")
	var before := _snapshot(game)
	var panel := wrapper.get("countdown_panel") as Control
	check(panel != null and (panel.get_node("CountdownNumber") as Label).text == "3", tag + ": Play countdown starts at 3")
	check(_snapshot(game) == before, tag + ": Play remains frozen during countdown")
	for tick in range(3):
		wrapper.call("_on_countdown_tick")
	check(game.process_mode == Node.PROCESS_MODE_INHERIT and wrapper.get("countdown_panel") == null,
		tag + ": Play GO releases game")
	check(_snapshot(game) == before, tag + ": Play countdown did not consume game resources")


func _focus_correct(game: Control, activity: String, step: String, resolution: Vector2i) -> bool:
	var outline: Control
	var target: CanvasItem
	if activity == "Human Plane":
		outline = game.get_node_or_null("TutorialSpotlightLayer/TutorialSpotlight/HighlightOutline") as Control
		match step:
			"movement":
				var hybrid := game.get_node_or_null("HybridFlight3D") as Node2D
				if hybrid != null and hybrid.has_method("get_airplane_highlight_rect") and outline != null:
					var expected := hybrid.call("get_airplane_highlight_rect") as Rect2
					return _bounds_enclose(Rect2(outline.global_position, outline.size), expected, resolution) \
						and _dim_hole_correct(game, activity, resolution) and _rendered_aircraft_focused(game, resolution)
			"prompt": target = game.get_node_or_null("HUDLayer/HUD/PromptLabel") as CanvasItem
			"mode": target = game.get_node_or_null("HUDLayer/HUD/TimerPlaque" if bool(game.get("is_seconds_mode")) else "HUDLayer/HUD/LivesPlaque") as CanvasItem
			"score": target = game.get_node_or_null("HUDLayer/HUD/ScorePlaque") as CanvasItem
			"pause": target = game.get_node_or_null("HUDLayer/HUD/PausePlaque") as CanvasItem
			"ring":
				var hybrid := game.get_node_or_null("HybridFlight3D")
				if hybrid != null and hybrid.has_method("get_ring_highlight_rect") and outline != null:
					var expected := hybrid.call("get_ring_highlight_rect", 1) as Rect2
					return _bounds_enclose(Rect2(outline.global_position, outline.size), expected, resolution) and _dim_hole_correct(game, activity, resolution)
	else:
		outline = game.get_node_or_null("GuidedTutorialLayer/GuidedTutorial/FocusOutline") as Control
		var property_name := ""
		match step:
			"prompt": property_name = "prompt_label" if activity == "Catch the Word" else "carnival_objective_plaque"
			"movement": property_name = "basket_sprite" if activity == "Catch the Word" else "launcher"
			"seconds": property_name = "timer_plaque" if activity == "Catch the Word" else "shared_timer_plaque"
			"lives": property_name = "lives_plaque" if activity == "Catch the Word" else "shared_lives_plaque"
			"score": property_name = "score_plaque" if activity == "Catch the Word" else "carnival_score_plaque"
			"pause": property_name = "pause_plaque"
		target = game.get(property_name) as CanvasItem if not property_name.is_empty() else null
		if step == "movement" and activity == "Balloon Popping" and target != null:
			target = target.get_node_or_null("TutorialFocusArea") as CanvasItem
	if outline == null or target == null:
		return false
	var actual := Rect2(outline.get_global_transform_with_canvas() * Vector2.ZERO,
		outline.get_global_transform_with_canvas() * outline.size - outline.get_global_transform_with_canvas() * Vector2.ZERO).abs()
	var expected := Rect2()
	if target is Control:
		var control := target as Control
		var transform := control.get_global_transform_with_canvas()
		expected = Rect2(transform * Vector2.ZERO, transform * control.size - transform * Vector2.ZERO).abs()
	elif target is Sprite2D:
		var sprite := target as Sprite2D
		var transform := sprite.get_global_transform_with_canvas()
		expected = Rect2(transform * sprite.get_rect().position, transform * sprite.get_rect().end - transform * sprite.get_rect().position).abs()
	return _bounds_enclose(actual, expected, resolution) and _dim_hole_correct(game, activity, resolution)


func _rendered_aircraft_focused(game: Control, resolution: Vector2i) -> bool:
	# The 3D aircraft's mesh bounds are the user's visible aircraft. PlaneRig
	# and PlanePassageHitbox can be offset or differently sized in the editor.
	# Highlighting either guide while dimming a visible wing is a regression.
	var hybrid := game.get_node_or_null("HybridFlight3D") as Node2D
	var camera := hybrid.get_node_or_null("RenderViewport/FlightWorld3D/Camera") as Camera3D if hybrid != null else null
	var anchor := hybrid.get_node_or_null("RenderViewport/FlightWorld3D/PlaneAnchor") as Node3D if hybrid != null else null
	var viewport := hybrid.get_node_or_null("RenderViewport") as SubViewport if hybrid != null else null
	var focus := game.get_node_or_null("TutorialSpotlightLayer/TutorialSpotlight/HighlightOutline") as Panel
	if camera == null or anchor == null or viewport == null or focus == null or viewport.size.x <= 0 or viewport.size.y <= 0:
		return false
	var projected := Rect2()
	var mesh_count := 0
	var have_point := false
	var multiplier := Vector2(game.size.x / viewport.size.x, game.size.y / viewport.size.y)
	for node in anchor.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		var shape := mesh.get_aabb()
		for xi in [0.0, 1.0]:
			for yi in [0.0, 1.0]:
				for zi in [0.0, 1.0]:
					var point := shape.position + Vector3(shape.size.x * xi, shape.size.y * yi, shape.size.z * zi)
					var world_point := mesh.to_global(point)
					if camera.is_position_behind(world_point):
						continue
					var screen_point := camera.unproject_position(world_point) * multiplier
					if not have_point:
						projected = Rect2(screen_point, Vector2.ZERO)
						have_point = true
					projected = projected.expand(screen_point)
		mesh_count += 1
	if mesh_count == 0:
		return false
	var actual_focus := Rect2(focus.global_position, focus.size)
	var enclosed := _bounds_enclose(actual_focus, projected, resolution)
	if not enclosed:
		printerr("WORKER20 3D AIRCRAFT BOUNDS: focus=", actual_focus, " rendered_mesh=", projected, " resolution=", resolution)
	return enclosed


func _dim_hole_correct(game: Control, activity: String, resolution: Vector2i) -> bool:
	var overlay_path := "TutorialSpotlightLayer/TutorialSpotlight" if activity == "Human Plane" else "GuidedTutorialLayer/GuidedTutorial"
	var overlay := game.get_node_or_null(overlay_path) as Control
	if overlay == null:
		return false
	if activity == "Human Plane":
		var outline := overlay.get_node_or_null("HighlightOutline") as Control
		var left := overlay.get_node_or_null("DimLeft") as ColorRect
		var right := overlay.get_node_or_null("DimRight") as ColorRect
		var above := overlay.get_node_or_null("DimAbove") as ColorRect
		var below := overlay.get_node_or_null("DimBelow") as ColorRect
		if outline == null or left == null or right == null or above == null or below == null:
			return false
		return left.visible and right.visible and above.visible and below.visible \
			and left.color.a >= 0.60 and right.color.a >= 0.60 \
			and absf(left.size.x - outline.position.x) < 3.0 \
			and absf(right.position.x - (outline.position.x + outline.size.x)) < 3.0 \
			and absf(above.size.y - outline.position.y) < 3.0 \
			and absf(below.position.y - (outline.position.y + outline.size.y)) < 3.0
	var dim := overlay.get_node_or_null("Dim") as ColorRect
	var outline := overlay.get_node_or_null("FocusOutline") as Control
	if dim == null or outline == null or not (dim.material is ShaderMaterial):
		return false
	var uv: Vector4 = (dim.material as ShaderMaterial).get_shader_parameter("focus_rect")
	var xf := outline.get_global_transform_with_canvas()
	var bounds := Rect2(xf * Vector2.ZERO, xf * outline.size - xf * Vector2.ZERO).abs()
	var expected_uv := Rect2(bounds.position / Vector2(resolution), bounds.size / Vector2(resolution))
	return dim.visible and dim.color.a >= 0.60 \
		and absf(uv.x - expected_uv.position.x) < 0.007 \
		and absf(uv.y - expected_uv.position.y) < 0.007 \
		and absf(uv.z - expected_uv.size.x) < 0.007 \
		and absf(uv.w - expected_uv.size.y) < 0.007


func _bounds_enclose(actual: Rect2, expected: Rect2, resolution: Vector2i) -> bool:
	var screen := Rect2(Vector2.ZERO, Vector2(resolution))
	var clipped := expected.intersection(screen)
	return actual.has_area() and screen.grow(3).encloses(actual) and clipped.has_area() \
		and actual.grow(3).encloses(clipped)


func _snapshot(game: Control) -> Dictionary:
	var values := {}
	for key in ["score", "time_remaining", "lives", "hearts", "wave_index", "round_index", "attempts", "correct_count", "gate_progress"]:
		for prop in game.get_property_list():
			if String(prop.get("name", "")) == key:
				values[key] = game.get(key)
				break
	return values


func _step_index(game: Control, activity: String) -> int:
	return int(game.get("_tutorial_step")) if activity == "Human Plane" else int(game.get("tutorial_step_index"))


func _step_title(game: Control, activity: String) -> String:
	var path := "TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide/Title" if activity == "Human Plane" else "GuidedTutorialLayer/GuidedTutorial/TutorialCard/StepTitle"
	var control := game.get_node_or_null(path) as Label
	return control.text if control != null else ""


func _guide_visible(game: Control, activity: String) -> bool:
	var path := "TutorialSpotlightLayer/TutorialSpotlight" if activity == "Human Plane" else "GuidedTutorialLayer/GuidedTutorial"
	var control := game.get_node_or_null(path) as Control
	return control != null and control.visible


func _visible_arrow(game: Control) -> bool:
	for control in game.find_children("*", "CanvasItem", true, false):
		if String(control.name).to_lower().contains("arrow") and (control as CanvasItem).visible:
			return true
	return false


func _audio_prefix(activity: String) -> String:
	match activity:
		"Catch the Word": return "catch_word"
		"Balloon Popping": return "balloon_popping"
		_: return "human_plane"


func _audio(game: Control) -> AudioStreamPlayer:
	var path := "TutorialSpotlightLayer/TutorialNarration" if game.name == "ActiveMiniGame" and game.has_node("TutorialSpotlightLayer/TutorialNarration") else "GuidedTutorialLayer/GuidedTutorial/TutorialNarration"
	return game.get_node_or_null(path) as AudioStreamPlayer


func _button(game: Control, node_name: String) -> Button:
	for found in game.find_children(node_name, "Button", true, false):
		return found as Button
	return null


func _edit(field: LineEdit, value: String) -> void:
	field.text = value
	field.text_changed.emit(value)


func _route() -> String:
	return String(app.get("current_route"))


func _capture(size: Vector2i, activity: String, mode: String, step: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	var filename := "%s_%s_%s_%dx%d.png" % [activity.to_snake_case(), mode.to_lower(), step, size.x, size.y]
	var code := frame.save_png(ProjectSettings.globalize_path(OUTPUT.path_join(filename)))
	check(code == OK and frame.get_size() == size, "native GPU screenshot correct dimensions: " + filename)
	if code == OK:
		screenshots += 1
		print("WORKER20_SCREENSHOT ", ProjectSettings.globalize_path(OUTPUT.path_join(filename)))


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		if failures.size() <= 60:
			printerr("WORKER20 QA FAIL: ", message)


func _finish() -> void:
	print("WORKER20 EMBEDDED ROUTE QA: %s checks=%d failures=%d tutorial_launches=%d/%d play_launches=%d/%d screenshots=%d backend=%s" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), tutorial_launches, cycles, play_launches, cycles,
		screenshots, DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)
