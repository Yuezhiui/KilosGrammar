extends SceneTree

# Inspect six real, editor-authored word labels at 720p and 1080p.
# Native GPU captures: Godot --path . --rendering-driver opengl3
#   --script res://tools/test_human_plane_word_plaques_readability_20261029.gd
# Geometry/contrast checks also run with --headless, without claiming screenshots.
const FLIGHT := preload("res://ui/minigames/human_plane/human_plane.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const LANES := ["GateLeft", "GateCenter", "GateRight"]
const GROUPS := ["MovingGates", "UpcomingGates"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for dimensions in SIZES:
		await _check_resolution(dimensions)
	print("HUMAN PLANE WORD PLAQUES: %s (%d assertions, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check_resolution(dimensions: Vector2i) -> void:
	var graphic := DisplayServer.get_name() != "headless"
	if graphic:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(dimensions)
		root.content_scale_size = dimensions
	root.size = dimensions
	var game := FLIGHT.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity": "Human Plane", "topic": "Noun",
		"difficulty": "Hard", "game_mode": "Seconds"})
	for _i in range(4):
		await process_frame
	game.set_process(false)
	print("HUMAN PLANE WORD SIZE: target=", dimensions,
		" window=", DisplayServer.window_get_size() if graphic else "headless",
		" root=", root.size, " texture=", root.get_texture().get_size())

	var title := game.get_node("HUDLayer/HUD/TitlePlaque") as Control
	var score := game.get_node("HUDLayer/HUD/ScorePlaque") as Control
	var timer := game.get_node("HUDLayer/HUD/TimerPlaque") as Control
	var pause := game.get_node("HUDLayer/HUD/PausePlaque") as Control

	for group_name in GROUPS:
		for lane_name in LANES:
			var gate := game.get_node(group_name + "/" + lane_name) as Control
			var plate := gate.get_node_or_null("WordPlate") as Panel
			var label := gate.get_node_or_null("WordLabel") as Label
			var id := "%s %s %s" % [dimensions, group_name, lane_name]
			_check(plate != null and label != null, id + " retains editable plate and word")
			if plate == null or label == null:
				continue
			var style := plate.get_theme_stylebox("panel") as StyleBoxFlat
			_check(style != null and style.bg_color.a >= 0.95, id + " opaque cream plate")
			var contrast := _contrast_ratio(style.bg_color, label.get_theme_color("font_color")) if style != null else 0.0
			_check(contrast >= 7.0, id + " dark word has >=7:1 contrast, actual %.2f" % contrast)
			# Godot clips in unscaled Label-local coordinates. Very long words are
			# scaled by gameplay, so local clipping would cut off final glyphs even
			# though their *rendered* width safely fits on the cream plaque.
			_check(label.get_theme_font("font") != null and not label.clip_text,
				id + " authored typeface and uncut horizontally scaled glyphs")
			_check(plate.mouse_filter == Control.MOUSE_FILTER_IGNORE
				and label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				id + " plaques do not intercept camera/game input")

	var answer_progress := float(game.call("_progress_for_answer_line"))
	var phases := {
		"far": 0.0,
		"mid": minf(answer_progress * 0.55, 0.4),
		"near": answer_progress * 0.94
	}
	for phase in phases:
		game.set("gate_progress", phases[phase])
		game.call("_sync_visuals")
		var hybrid := game.get_node_or_null("HybridFlight3D") as Node2D
		if hybrid != null:
			hybrid.call("_process", 0.0)
		var plates: Array[Rect2] = []
		var words: Array = (game.get("round_data") as Dictionary).get("options", [])
		for lane_index in range(3):
			var gate := game.get_node("MovingGates/" + LANES[lane_index]) as Control
			var plate := gate.get_node("WordPlate") as Panel
			var label := gate.get_node("WordLabel") as Label
			var id := "%s %s %s" % [dimensions, phase, LANES[lane_index]]
			var plaque_rect := plate.get_global_rect()
			var label_rect := label.get_global_rect()
			plates.append(plaque_rect)
			_check(not label.text.is_empty() and label.text == String(words[lane_index]).to_upper(),
				id + " genuine GrammarBank word appears")
			_check(plaque_rect.has_area() and label_rect.has_area()
				and plaque_rect.encloses(label_rect), id + " word stays within the plate")
			_check(plaque_rect.position.y <= gate.get_global_rect().position.y + 1.0
				and plaque_rect.end.y <= gate.get_global_rect().get_center().y,
				id + " label floats at ring top")
			_check(not plaque_rect.intersects(title.get_global_rect())
				and not plaque_rect.intersects(score.get_global_rect())
				and not plaque_rect.intersects(timer.get_global_rect())
				and not plaque_rect.intersects(pause.get_global_rect()),
				id + " word clears title, score, timer, pause HUD")
			var point_size := label.get_theme_font_size("font_size")
			var minimum := 12 if phase == "far" else (16 if phase == "mid" else 20)
			_check(point_size >= minimum, id + " readable actual font size %d >= %d" %
				[point_size, minimum])
			var rendered_text_width := label.get_theme_font("font").get_string_size(
				label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x * absf(label.scale.x)
			var glyph_left := label_rect.get_center().x - rendered_text_width * 0.5
			var glyph_right := glyph_left + rendered_text_width
			_check(glyph_left >= plaque_rect.position.x + 4.0
				and glyph_right <= plaque_rect.end.x - 4.0,
				id + " measured glyph fits plaque: glyph=%.1f text_x=[%.1f,%.1f] plate_x=[%.1f,%.1f] centers=[%.1f,%.1f] scale=%.2f word=%s" %
				[rendered_text_width, glyph_left, glyph_right, plaque_rect.position.x, plaque_rect.end.x,
				 label_rect.get_center().x, plaque_rect.get_center().x, label.scale.x, label.text])
		_check(plates[0].end.x + 4.0 < plates[1].position.x
			and plates[1].end.x + 4.0 < plates[2].position.x,
			"%s %s three ring plaques never collide" % [dimensions, phase])
		if graphic:
			for _i in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			var png := "user://_qa_human_word_plaques_%dx%d_%s.png" % [
				dimensions.x, dimensions.y, phase]
			var frame := root.get_texture().get_image()
			var saved := frame != null and frame.get_width() == dimensions.x \
				and frame.get_height() == dimensions.y
			if saved:
				saved = frame.save_png(ProjectSettings.globalize_path(png)) == OK
			_check(saved, "%s %s real 3D flight screenshot saved" % [dimensions, phase])
			if saved:
				print("HUMAN PLANE WORD IMAGE: ", ProjectSettings.globalize_path(png))
	if not graphic:
		print("HUMAN PLANE WORD IMAGE: SKIP native GPU screenshots (headless renderer)")
	game.queue_free()
	await process_frame
	await process_frame


func _contrast_ratio(background: Color, foreground: Color) -> float:
	var light := maxf(background.get_luminance(), foreground.get_luminance())
	var dark := minf(background.get_luminance(), foreground.get_luminance())
	return (light + 0.05) / (dark + 0.05)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("HUMAN PLANE WORD FAIL: " + description)
