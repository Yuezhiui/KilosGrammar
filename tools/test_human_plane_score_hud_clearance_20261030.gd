extends SceneTree

# Native GPU regression: Catch-identical score editor rect and DIRECT
# ScoreNumber must never obscure authored word plates through three-lane flight.
# Godot --rendering-driver opengl3 --path . --script res://tools/test_human_plane_score_hud_clearance_20261030.gd
# No real student, webcam, Postgres, audio mutation or production dynamic layout.
const SCENE := preload("res://ui/minigames/human_plane/human_plane.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const MODES := ["Seconds", "Lives"]
const CAPTURE_POINTS := [0.4, 0.55, 0.75, 0.95]
const EXPECTED_PLAQUE := Rect2(981.0, 519.0, 280.0, 200.0)
const EXPECTED_SCORE := Rect2(1036.0, 607.0, 188.0, 60.0)

var failures: Array[String] = []
var checks := 0
var captures := 0
var overlaps := 0
var phase := "after"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	phase = OS.get_environment("KG_SCORE_LAYOUT_QA").strip_edges().to_lower()
	if phase.is_empty():
		phase = "after"
	_check(phase == "after", "Catch-exact serialized score HUD is authoritative")
	if DisplayServer.get_name() == "headless":
		printerr("GRAPHICS REQUIRED: native screenshots/word occlusion proof")
		quit(2)
		return
	for size in SIZES:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(size)
		root.content_scale_size = size
		root.size = size
		for mode in MODES:
			await _exercise(size, mode)
	_check(overlaps == 0, "Catch-exact plaque and authentic gate words remain separately readable")
	print("SCORE CLEARANCE %s: %s checks=%d failures=%d overlaps=%d captures=%d" % [
		phase, "PASS" if failures.is_empty() else "FAIL", checks, failures.size(),
		overlaps, captures])
	quit(0 if failures.is_empty() else 1)


func _exercise(size: Vector2i, mode: String) -> void:
	var game := SCENE.instantiate() as Control
	var plaque := game.get_node("HUDLayer/HUD/ScorePlaque") as TextureRect
	var label := game.get_node("HUDLayer/HUD/ScoreNumber") as Label
	_check(plaque.get_rect().is_equal_approx(EXPECTED_PLAQUE)
		and label.get_rect().is_equal_approx(EXPECTED_SCORE)
		and game.get_node_or_null("HUDLayer/HUD/ScoreBottomContainer") == null
		and label.get_theme_font_size("font_size") == 35,
		"%s %s exact current Catch editor geometry and direct score font" % [size, mode])
	_check((label.position - plaque.position).is_equal_approx(Vector2(55, 88)),
		"Catch original score number centered inside genuine ScorePlaque")
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity":"Human Plane", "topic":"Noun",
		"difficulty":"Normal", "game_mode":mode})
	for _i in range(5):
		await process_frame
	game.set_process(false)
	game.set("score", 321)
	var title := game.get_node("HUDLayer/HUD/TitlePlaque") as TextureRect
	var timer := game.get_node("HUDLayer/HUD/TimerPlaque") as TextureRect
	var hearts := game.get_node("HUDLayer/HUD/LivesPlaque") as TextureRect
	var pause := game.get_node("HUDLayer/HUD/PauseButton") as Button
	var assert_hud := func() -> void:
		_check(label.text == "321" and label.is_visible_in_tree(),
			"%s %s direct Catch score 321 remains actually readable" % [size, mode])
		_check(not plaque.get_global_rect().intersects(title.get_global_rect().grow(16.0)),
			"%s %s score never obstructs the title and question" % [size, mode])
		_check(not plaque.get_global_rect().intersects(timer.get_global_rect())
			and not plaque.get_global_rect().intersects(hearts.get_global_rect())
			and not plaque.get_global_rect().intersects(pause.get_global_rect()),
			"%s %s score stays clear of timer/lives and Pause" % [size, mode])
		_check(int(game.get("lives")) == 3
			and (float(game.get("time_remaining")) >= 59.0 if mode == "Seconds"
			else is_zero_approx(float(game.get("time_remaining"))))
			and timer.visible == (mode == "Seconds")
			and hearts.visible == (mode == "Lives"), "%s %s timer/hearts unaffected" % [size, mode])
	game.call("_prefetch_next_wave")
	for i in range(41):
		var progress := float(i) / 40.0
		game.set("gate_progress", progress)
		game.set("gate_resolved", false) # Stress readable plaques at full authored depth.
		game.set("next_gate_progress", maxf(0.0, progress - float(game.GATE_SEPARATION)))
		game.call("_sync_visuals")
		for group in [game.get("_gate_nodes"), game.get("_upcoming_gate_nodes")]:
			for lane in range(3):
				var gate: Control = group[lane]
				var word := gate.get_node("WordPlate") as Control
				if not word.is_visible_in_tree():
					continue
				var intersection := plaque.get_global_rect().intersection(word.get_global_rect())
				if intersection.size.x > 1.0 and intersection.size.y > 1.0:
					overlaps += 1
					_check(false, "%s %s p=%.3f score covers %s lane%d by %s" % [
							size, mode, progress, gate.get_parent().name, lane,
							intersection])
		if i in [16, 22, 30, 38]:
			await _screenshot(size, mode, progress)
		assert_hud.call()
	# The new score location is presentation only. Pausing/resuming must
	# preserve the authored score rect and freeze the mode's time value.
	var score_rect_before := plaque.get_rect()
	var numeric_rect_before := label.get_rect()
	var clock_before: float = float(game.get("time_remaining"))
	game.call("_pause")
	game.call("_process", 0.5)
	_check(bool(game.get("paused")) and not bool(game.get("running"))
		and is_equal_approx(float(game.get("time_remaining")), clock_before)
		and plaque.get_rect().is_equal_approx(score_rect_before)
		and label.get_rect().is_equal_approx(numeric_rect_before)
		and label.text == "321" and pause.visible,
		"%s %s Pause freezes clock and preserves editor-authored HUD geometry" % [size, mode])
	game.call("_resume")
	_check(not bool(game.get("paused")) and bool(game.get("running"))
		and plaque.get_rect().is_equal_approx(score_rect_before)
		and label.get_rect().is_equal_approx(numeric_rect_before)
		and label.text == "321",
		"%s %s Resume restores same exact score artwork and number" % [size, mode])
	game.queue_free()
	await process_frame
	await process_frame


func _screenshot(size: Vector2i, mode: String, progress: float) -> void:
	for _i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://showcase/qa_human_plane_oct30/score_%s_%dx%d_%s_p%03d.png" % [
		phase, size.x, size.y, mode.to_lower(), roundi(progress * 100.0)]
	var saved := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	_check(saved == OK, "GPU screenshot saved: " + path)
	if saved == OK:
		captures += 1
		print("SCORE-HUD-CAPTURE ", path)


func _check(value: bool, reason: String) -> void:
	checks += 1
	if not value:
		failures.append(reason)
		printerr("SCORE HUD FAILURE: ", reason)
