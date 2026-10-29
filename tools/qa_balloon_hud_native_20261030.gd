extends SceneTree

# Isolated native-OpenGL image QA. Loads the two minigames directly without
# the router, camera, database, recovery journal or any gameplay-scene edits.
# Run with Godot 4.7.2 --rendering-driver opengl3 --path . --script res://tools/qa_balloon_hud_native_20261030.gd

const BALLOON := preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const CATCH := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const OUTPUT := "res://showcase/qa_balloon_hud_20261030_worker12"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const BADGE_TIMER := "res://Components/Gameplay/Catch the Word/HUD/generated/timer_badge.png"
const BADGE_LIVES_2 := "res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_2.png"
const PAUSE_ART := "res://Components/Gameplay/Catch the Word/HUD/generated/pause_badge.png"
const PAUSE_ICON := "res://Components/Gameplay/Controls/pause_white.svg"

var checks := 0
var failures: Array[String] = []
var captures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_fail("Requires a native graphical renderer")
		_finish()
		return
	var result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if result != OK:
		_fail("Could not create isolated screenshot directory, code %d" % result)
		_finish()
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for dimensions in SIZES:
		# Override the project's default 1280x720 stretch viewport so the
		# screenshot itself, game geometry and HUD are all true physical pixels.
		root.content_scale_size = dimensions
		root.size = dimensions
		DisplayServer.window_set_size(dimensions)
		await process_frame
		await process_frame
		await _capture_case(dimensions, "balloon_seconds", BALLOON, "Balloon Popping", "Seconds")
		await _capture_case(dimensions, "balloon_lives_2", BALLOON, "Balloon Popping", "Lives")
		await _capture_case(dimensions, "catch_seconds", CATCH, "Catch the Word", "Seconds")
	await create_timer(0.1).timeout
	_finish()


func _capture_case(dimensions: Vector2i, label: String, packed: PackedScene, activity: String, mode: String) -> void:
	var instance := packed.instantiate() as Control
	if instance == null or instance.get_script() == null:
		_fail("%s %s: could not instantiate scripted minigame" % [dimensions, label])
		return
	root.add_child(instance)
	instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	instance.call("set_context", {
		"activity": activity, "topic": "Noun", "game_style": "Noun",
		"difficulty": "Normal", "game_mode": mode,
		"camera_live": false, "database_connected": false,
		"student_name": "VISUAL QA", "student_id": "QA-ISOLATED"
	})
	await process_frame
	await process_frame
	instance.set_process(false)
	instance.set_physics_process(false)
	if instance.has_method("_stop_voice_feedback"):
		instance.call("_stop_voice_feedback")
	# Stage the existing 3 real game balloons in the visible playfield for
	# artwork review; their live continuous ascent is a separate gameplay
	# behavior. This only moves this isolated QA instance, never a scene file.
	if activity == "Balloon Popping":
		var targets := instance.get("balloons") as Array
		_check(targets.size() == 3, "%s: actual three word balloons spawned" % label)
		var before_heights: Array[float] = []
		for target in targets:
			if target is Node2D and is_instance_valid(target):
				(target as Node2D).position.y = clampf(instance.size.y * 0.43, 245.0, 440.0)
				before_heights.append((target as Node2D).position.y)
		# One real gameplay _process step verifies the newly approved continuous
		# rising movement while preventing passage into a second grammar round.
		instance.call("_process", 0.10)
		var rising := targets.size() == 3 and before_heights.size() == 3
		for i in range(mini(before_heights.size(), targets.size())):
			var item := targets[i] as Node2D
			rising = rising and item != null and item.position.y < before_heights[i] - 1.0
		_check(rising, "%s: all three balloons rise during real _process delta" % label)
	await create_timer(0.10).timeout
	if activity == "Balloon Popping":
		instance.set("score", 250)
		if mode == "Lives":
			instance.set("hearts", 2)
	else:
		instance.set("score", 250)
	instance.call("_refresh_hud")
	instance.set_process(false)
	instance.set_physics_process(false)
	await process_frame
	await process_frame
	if activity == "Balloon Popping":
		_check_balloon(instance, dimensions, label, mode)
	else:
		_check_catch(instance, dimensions, label)
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	_check(shot != null and shot.get_size() == dimensions,
		"%s %s: actual GPU frame is requested resolution" % [dimensions, label])
	if shot != null and shot.get_size() == dimensions:
		var output := ProjectSettings.globalize_path(
			OUTPUT.path_join("%s_%dx%d.png" % [label, dimensions.x, dimensions.y]))
		var save_result := shot.save_png(output)
		_check(save_result == OK, "%s %s: saved native PNG" % [dimensions, label])
		if save_result == OK:
			captures += 1
			print("QA_CAPTURE ", output)
	instance.queue_free()
	await process_frame
	await process_frame


func _check_balloon(game: Control, dimensions: Vector2i, label: String, mode: String) -> void:
	var hud := game.get_node_or_null("HudLayer") as Control
	var title := game.get_node_or_null("HudLayer/ObjectivePanel") as TextureRect
	var tagline := game.get_node_or_null("HudLayer/BannerTagline") as Label
	var score := game.get_node_or_null("HudLayer/CarnivalScore") as TextureRect
	var number := game.get_node_or_null("HudLayer/ScoreBottomContainer/ScoreNumber") as Label
	var timer := game.get_node_or_null("HudLayer/TimerPlaque") as TextureRect
	var lives := game.get_node_or_null("HudLayer/LivesPlaque") as TextureRect
	var time_text := game.get_node_or_null("HudLayer/TimeLabel") as Label
	var pause_art := game.get_node_or_null("HudLayer/PausePlaque") as TextureRect
	var pause_button := game.get_node_or_null("HudLayer/PauseButton") as Button
	_check(hud != null and title != null and tagline != null and score != null
		and number != null and timer != null and lives != null
		and time_text != null and pause_art != null and pause_button != null,
		label + ": all current Balloon HUD components exist")
	if title == null or score == null or timer == null or lives == null or pause_art == null or pause_button == null or number == null:
		return
	var frame := Rect2(Vector2.ZERO, Vector2(dimensions))
	var active: TextureRect = timer if mode == "Seconds" else lives
	_check(title.texture != null and title.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
		label + ": title PNG keeps its native aspect ratio")
	# Catch's reference prompt rect is (115,93)-(421,126) in design space.
	# Balloon's cream strip has slightly different painted padding, so a
	# 3-pixel vertical center adjustment is legitimate. Guard against the
	# previous production defect (y74, text over BALLOON POPPING headline).
	if tagline != null:
		var compare_scale := minf(float(dimensions.x) / 1280.0, float(dimensions.y) / 720.0)
		var reference_prompt := Rect2(Vector2(115.0, 93.0) * compare_scale,
			Vector2(306.0, 33.0) * compare_scale)
		_check(absf(_rect(tagline).get_center().y - reference_prompt.get_center().y) <= 4.0 * compare_scale
			and absf(_rect(tagline).position.x - reference_prompt.position.x) < 2.0
			and _rect(tagline).size.distance_to(reference_prompt.size) <= 2.0 * compare_scale,
			label + ": Balloon objective text centered inside cream strip (reference %s, got %s)" %
			[reference_prompt, _rect(tagline)])
	if title.texture != null:
		var title_size := title.texture.get_size()
		var title_texture_ratio := title_size.x / title_size.y
		var title_slot_ratio := title.size.x / title.size.y
		print("QA_TITLE %s native=%s ratio=%.4f slot=%s ratio=%.4f keep_aspect=%s" %
			[label, title_size, title_texture_ratio, title.size, title_slot_ratio,
			str(title.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED)])
		_check(absf(title_texture_ratio - 1959.0 / 477.0) < 0.005,
			label + ": Balloon's original title art is loaded")
	_check(number.text == "250", label + ": score digits rendered after isolated QA score injection")
	_check(score.is_visible_in_tree() and frame.encloses(_rect(score)),
		label + ": score art fully visible within viewport")
	_check(not _rect(score).intersects(_rect(active)),
		label + ": score and active timer/lives badge do not overlap")
	_check(not _rect(score).intersects(_rect(pause_art)),
		label + ": score and pause plaque do not overlap")
	_check(not _rect(title).intersects(_rect(score)),
		label + ": title and score plaque do not overlap")
	_check(not _rect(title).intersects(_rect(active)),
		label + ": title and active timer/lives badge do not overlap")
	_check(_rect(score).encloses(_rect(number)),
		label + ": numeric score inside score plaque")
	_check(_rect(pause_art).encloses(_rect(pause_button)),
		label + ": Pause click hitbox remains inside pause artwork")
	_check(pause_art.texture != null and pause_art.texture.resource_path == PAUSE_ART,
		label + ": correct Catch pause plaque texture")
	_check(pause_button.icon != null and pause_button.icon.resource_path == PAUSE_ICON,
		label + ": active white Pause glyph visible on button")
	_check(pause_art.is_visible_in_tree() and pause_button.is_visible_in_tree(),
		label + ": pause plaque and input region visible")
	_check(active.texture != null and active.texture.resource_path ==
		(BADGE_TIMER if mode == "Seconds" else BADGE_LIVES_2),
		label + ": correct Seconds/Lives texture")
	_check(active.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
		label + ": timer/lives source art preserves natural ratio")
	_check(timer.visible == (mode == "Seconds") and lives.visible == (mode == "Lives"),
		label + ": one active mode badge")
	_check(time_text.visible == (mode == "Seconds"),
		label + ": seconds label visible only for Seconds")
	var scale := minf(float(dimensions.x) / 1280.0, float(dimensions.y) / 720.0)
	var expected_pause := Vector2(dimensions.x - 85.0 * scale, 8.0 * scale)
	_check(_rect(pause_art).position.distance_to(expected_pause) < 2.0,
		label + ": pause art aligned to Catch reference position")
	_check(frame.encloses(_rect(pause_art)) and frame.encloses(_rect(title)) and frame.encloses(_rect(active)),
		label + ": title, pause and timer/lives are not clipped")
	print("QA_GEOMETRY %s title=%s score=%s badge=%s pause_art=%s pause_button=%s" %
		[label, _rect(title), _rect(score), _rect(active), _rect(pause_art), _rect(pause_button)])


func _check_catch(game: Control, dimensions: Vector2i, label: String) -> void:
	var title := game.get_node_or_null("HUDLayer/HUD/TitlePlaque") as TextureRect
	var score := game.get_node_or_null("ScoreDrawLayer/ScorePlaque") as TextureRect
	var timer := game.get_node_or_null("HUDLayer/HUD/TimerPlaque") as TextureRect
	var pause_art := game.get_node_or_null("HUDLayer/HUD/PausePlaque") as TextureRect
	var pause_button := game.get_node_or_null("HUDLayer/HUD/PauseButton") as Button
	_check(title != null and timer != null and pause_art != null and pause_button != null,
		label + ": Catch comparison HUD loaded")
	if title == null or timer == null or pause_art == null or pause_button == null:
		return
	var frame := Rect2(Vector2.ZERO, Vector2(dimensions))
	_check(frame.encloses(_rect(pause_art)) and frame.encloses(_rect(timer)),
		label + ": Catch timer and pause artwork fit viewport")
	_check(_rect(pause_art).encloses(_rect(pause_button)),
		label + ": Catch clickable Pause region inside plaque")
	_check(timer.is_visible_in_tree() and pause_art.is_visible_in_tree(),
		label + ": Catch comparison HUD is visible")
	print("QA_CATCH_GEOMETRY %s title=%s timer=%s pause_art=%s score=%s" %
		[label, _rect(title), _rect(timer), _rect(pause_art), _rect(score) if score != null else Rect2()])


func _rect(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	var origin := transform * Vector2.ZERO
	return Rect2(origin, transform * control.size - origin)


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		_fail(reason)


func _fail(reason: String) -> void:
	failures.append(reason)
	print("QA_FAIL ", reason)


func _finish() -> void:
	_check(captures == SIZES.size() * 3, "All 9 Balloon/Catch native PNG captures saved")
	print("QA_BALLOON_HUD_NATIVE %s captures=%d checks=%d failures=%d backend=%s" %
		["PASS" if failures.is_empty() else "FAIL", captures, checks, failures.size(), DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)
