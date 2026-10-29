extends SceneTree

# Render and check three-apple waves using the actual Catch scene and gameplay.
# Graphical Godot 4.7.2 (do not run with --headless):
# Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility --script res://tools/capture_catch_waves.gd
#
# Capture entry (apples partly beyond top edge) and descent (clear of top
# HUD) across three display sizes. No manual apple creation/repositioning.
# The helper steps the actual game process and saves its real rendered output.

const SCENE := "res://ui/minigames/catch_the_word/catch_word.tscn"
const OUTPUT_DIR := "res://showcase/catch_word_hud/waves"
const SIZES := [Vector2i(1280, 720), Vector2i(875, 500), Vector2i(1920, 1080)]
const CASES := [
	{"map": "City", "mode": "Seconds", "topic": "Noun", "character": "Bear"},
	{"map": "City", "mode": "Lives", "topic": "Pronoun", "character": "Cat"},
	{"map": "Forest", "mode": "Seconds", "topic": "Verb", "character": "Dog"},
	{"map": "Forest", "mode": "Lives", "topic": "Adjective", "character": "Lion"},
	{"map": "Mountain", "mode": "Seconds", "topic": "Adverb", "character": "Cat"},
	{"map": "Mountain", "mode": "Lives", "topic": "Noun", "character": "Bear"}
]
const REMOVED_OVERLAYS := ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]
const VISIBLE_PLATES := ["TitlePlaque", "PausePlaque", "ScorePlaque"]
const APPLE_PADDING := 5.0
const HUD_OVERLAP_MARGIN := 1.0
const SIM_DT := 1.0 / 60.0
const MAX_SIM_STEPS := 600
const Y_ALIGNMENT_TOLERANCE := 2.0
const GAP_ALIGNMENT_RATIO := 0.025
const RIGHT_SHIFT_MIN_FRACTION := 0.14
const ENTRY_EXPOSED_FRACTION := 0.20
const DESCENT_CLEARANCE := 18.0

var failures: Array[String] = []
var captures := 0
var cases_passed := 0
var expected_captures := SIZES.size() * CASES.size() * 2


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		push_error("WAVE QA: cannot load Catch scene")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for requested_size in SIZES:
		root.size = requested_size
		DisplayServer.window_set_size(requested_size)
		await process_frame
		await process_frame
		for entry in CASES:
			await _capture(packed, requested_size, entry)
	print("WAVE QA: %d/%d screenshots; %d scenarios without failures; %d failures" %
		[captures, expected_captures, cases_passed, failures.size()])
	if failures.is_empty() and captures == expected_captures:
		print("PASS Catch waves: offscreen start, entering and descending three aligned apples, no HUD obstruction")
		quit(0)
	else:
		for reason in failures:
			push_error("WAVE QA FAIL: " + reason)
		quit(1)


func _capture(packed: PackedScene, requested_size: Vector2i, entry: Dictionary) -> void:
	var label := "%s/%s/%s %dx%d" % [entry["map"], entry["mode"], entry["character"], requested_size.x, requested_size.y]
	var start_failures := failures.size()
	var game := packed.instantiate() as Control
	if game == null:
		_fail(label + ": failed to instantiate game")
		return
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {
		"activity": "Catch the Word", "topic": entry["topic"],
		"game_style": entry["topic"], "game_mode": entry["mode"],
		"difficulty": "Normal", "catch_character": entry["character"],
		"catch_map": entry["map"]
	})
	game.set_process(false)
	# Production builds their waves in set_context/_deferred_begin. Disable
	# automatic _process after deferred setup for deterministic stepping.
	await process_frame
	await process_frame
	await process_frame
	var tiles: Array = game.get("falling_tiles")
	var hud := game.get_node_or_null("HUDLayer/HUD") as Control
	if hud == null:
		_fail(label + ": HUD node missing")
	else:
		_check_hud(game, hud, entry, label)
		_check_art(game, entry, label)
		_check_wave(game, tiles, hud, label, "spawn")
		_check_reading_starts_offscreen(game, tiles, label)
		if _step_until_entry(game, hud, label):
			_check_wave(game, game.get("falling_tiles"), hud, label, "entering")
			await _save_capture(requested_size, entry, "entering", label)
		if _step_until_descent(game, hud, label):
			_check_wave(game, game.get("falling_tiles"), hud, label, "descent")
			await _save_capture(requested_size, entry, "descent", label)
	if failures.size() == start_failures:
		cases_passed += 1
	game.queue_free()
	await process_frame


func _save_capture(requested_size: Vector2i, entry: Dictionary, stage: String, label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	if screenshot.get_size() != requested_size:
		_fail(label + ": screenshot size %s != %s" % [screenshot.get_size(), requested_size])
	var filename := "%s_%s_%s_%s_%dx%d.png" % [
		String(entry["character"]).to_lower(), String(entry["map"]).to_lower(),
		String(entry["topic"]).to_lower(), String(entry["mode"]).to_lower(),
		requested_size.x, requested_size.y
	]
	filename = filename.trim_suffix(".png") + "_" + stage + ".png"
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(filename))
	var write_error := screenshot.save_png(output_path)
	if write_error == OK:
		captures += 1
		print("CAPTURED ", output_path)
	else:
		_fail(label + ": screenshot save failed error=" + str(write_error))


func _check_hud(game: Control, hud: Control, entry: Dictionary, label: String) -> void:
	var view_size := game.get_viewport_rect().size
	for name in REMOVED_OVERLAYS:
		var item := hud.get_node_or_null(name) as CanvasItem
		if item != null and item.is_visible_in_tree():
			_fail(label + ": removed objective/feedback component visible: " + name)
	for name in VISIBLE_PLATES:
		var control := hud.get_node_or_null(name) as Control
		if control == null or not control.is_visible_in_tree():
			_fail(label + ": missing visible HUD component: " + name)
			continue
		var rect := _on_canvas_rect(control)
		if rect.position.x < -8.0 or rect.position.y < -8.0 or rect.end.x > view_size.x + 8.0 or rect.end.y > view_size.y + 8.0:
			_fail(label + ": HUD element outside logical view: " + name + " " + str(rect))
	var expected_badge := "TimerPlaque" if entry["mode"] == "Seconds" else "LivesPlaque"
	var badge := hud.get_node_or_null(expected_badge) as CanvasItem
	if badge == null or not badge.is_visible_in_tree():
		_fail(label + ": mode indicator missing: " + expected_badge)


func _check_wave(game: Control, tiles: Array, hud: Control, label: String, stage: String) -> void:
	if tiles.size() != 3:
		_fail(label + " " + stage + ": expected exactly three simultaneous apples, got " + str(tiles.size()))
		return
	var view_size := game.get_viewport_rect().size
	var correct := 0
	var wrong := 0
	var rectangles: Array[Rect2] = []
	var xs: Array[float] = []
	var ys: Array[float] = []
	for index in range(tiles.size()):
		var tile: Dictionary = tiles[index]
		if bool(tile.get("matching", false)):
			correct += 1
		else:
			wrong += 1
		var apple := tile.get("node") as Control
		if apple == null or not apple.is_visible_in_tree():
			_fail(label + ": apple %d missing or invisible" % index)
			continue
		var rect := _on_canvas_rect(apple)
		rectangles.append(rect)
		xs.append(rect.get_center().x)
		ys.append(rect.get_center().y)
		if rect.size.x < 20.0 or rect.size.y < 20.0:
			_fail(label + ": apple %d rendered too small: %s" % [index, rect])
		if rect.position.x < 0 or rect.end.x > view_size.x:
			_fail(label + ": apple %d outside horizontal playfield: %s" % [index, rect])
		if stage == "entering" and (rect.position.y >= -0.5 or rect.end.y <= rect.size.y * ENTRY_EXPOSED_FRACTION or rect.end.y >= rect.size.y):
			_fail(label + ": apple %d should be partially above the top with visible lower tip: %s" % [index, rect])
		if stage == "descent" and (rect.position.y < -0.1 or rect.end.y > view_size.y):
			_fail(label + ": apple %d should be fully visible in the descent capture: %s" % [index, rect])
		for name in ["TitlePlaque", "PausePlaque", "ScorePlaque", "TimerPlaque", "LivesPlaque"]:
			var panel := hud.get_node_or_null(name) as Control
			if panel == null or not panel.is_visible_in_tree():
				continue
			var inset_apple := rect.grow(-HUD_OVERLAP_MARGIN)
			var panel_rect := _on_canvas_rect(panel).grow(-HUD_OVERLAP_MARGIN)
			# The top HUD CanvasLayer covers apples while they pass behind it.
			# Once the apple clears the top HUD, visible painted regions must
			# not intersect. At the initial entry overlap is intentional layering.
			if stage == "descent" and inset_apple.intersects(panel_rect):
				_fail(label + ": apple %d overlaps %s during visible descent: %s" % [index, name, rect])
			# Falling apples keep their X lane; if one reaches the scoreboard's X
			# span, it could hide behind the score later even if the spawn is clear.
			if name == "ScorePlaque" and inset_apple.position.x < panel_rect.end.x and inset_apple.end.x > panel_rect.position.x:
				_fail(label + ": apple %d lane will intersect scoreboard while falling" % index)
	for i in range(rectangles.size()):
		for j in range(i + 1, rectangles.size()):
			if rectangles[i].grow(APPLE_PADDING).intersects(rectangles[j].grow(APPLE_PADDING)):
				_fail(label + ": apples %d and %d touch or overlap" % [i, j])
	if correct != 1 or wrong != 2:
		_fail(label + ": expected one correct and two wrong, got correct=%d wrong=%d" % [correct, wrong])
	if ys.size() == 3 and (ys.max() - ys.min()) > Y_ALIGNMENT_TOLERANCE:
		_fail(label + " " + stage + ": apple Y values not aligned: " + str(ys))
	if xs.size() == 3:
		xs.sort()
		var first_gap := xs[1] - xs[0]
		var second_gap := xs[2] - xs[1]
		if first_gap < 180.0 or second_gap < 180.0:
			_fail(label + " " + stage + ": lanes not sufficiently separated: " + str(xs))
		if absf(first_gap - second_gap) > maxf(6.0, (first_gap + second_gap) * 0.5 * GAP_ALIGNMENT_RATIO):
			_fail(label + " " + stage + ": unequal horizontal spacing: " + str(xs))
		if xs[0] < minf(view_size.x, 1280.0) * RIGHT_SHIFT_MIN_FRACTION:
			_fail(label + " " + stage + ": left lane not shifted right enough: " + str(xs))
		print("LAYOUT ", label, " ", stage, " x=", xs, " y=", ys, " spacing=", snappedf(first_gap, 0.1), "/", snappedf(second_gap, 0.1))


func _check_reading_starts_offscreen(game: Control, tiles: Array, label: String) -> void:
	# The updated gameplay should never stop three visible apples in midair.
	if String(game.get("wave_phase")) != "falling":
		_fail(label + ": initial phase should be falling immediately, got " + str(game.get("wave_phase")))
	if tiles.size() != 3:
		return
	for index in range(3):
		var rect := _on_canvas_rect(tiles[index]["node"] as Control)
		if rect.end.y > 1.0:
			_fail(label + ": apple %d began visibly mid-screen instead of above top edge: %s" % [index, rect])
	print("SPAWN ", label, " y=", Vector2(tiles[0]["pos"]).y, " phase=", game.get("wave_phase"))


func _advance_checked(game: Control, label: String) -> bool:
	var before: Array = game.get("falling_tiles")
	if before.size() != 3 or String(game.get("wave_phase")) != "falling":
		_fail(label + ": incomplete or paused wave during falling motion")
		return false
	var previous: Array[Vector2] = []
	for tile in before:
		previous.append(Vector2(tile["pos"]))
	game.call("_process", SIM_DT)
	var after: Array = game.get("falling_tiles")
	if after.size() != 3:
		_fail(label + ": lost wave apples during free fall")
		return false
	var first_delta := Vector2(after[0]["pos"]).y - previous[0].y
	if first_delta < 0.5:
		_fail(label + ": midair pause detected; Y changed only %s in a 1/60s frame" % first_delta)
		return false
	for i in range(3):
		var position := Vector2(after[i]["pos"])
		if absf(position.y - previous[i].y - first_delta) > 0.1:
			_fail(label + ": apples are descending at unequal speeds")
			return false
		if absf(position.x - previous[i].x) > 0.1:
			_fail(label + ": apple lane moved horizontally during falling")
			return false
	return true


func _step_until_entry(game: Control, hud: Control, label: String) -> bool:
	for step in range(MAX_SIM_STEPS):
		var tiles: Array = game.get("falling_tiles")
		if tiles.size() != 3:
			_fail(label + ": wave incomplete before top entry")
			return false
		var apple := tiles[0]["node"] as Control
		var rect := _on_canvas_rect(apple)
		if rect.end.y >= rect.size.y * (ENTRY_EXPOSED_FRACTION + 0.04):
			if rect.position.y >= 0.0:
				_fail(label + ": first visible checkpoint missed partially above frame")
				return false
			return true
		if not _advance_checked(game, label):
			return false
	_fail(label + ": apples did not reach top entry within simulation limit")
	return false


func _step_until_descent(game: Control, hud: Control, label: String) -> bool:
	var top_hud_bottom := 0.0
	for name in ["TitlePlaque", "TimerPlaque", "LivesPlaque", "PausePlaque"]:
		var panel := hud.get_node_or_null(name) as Control
		if panel != null and panel.is_visible_in_tree():
			top_hud_bottom = maxf(top_hud_bottom, _on_canvas_rect(panel).end.y)
	var target_top := top_hud_bottom + DESCENT_CLEARANCE
	for step in range(MAX_SIM_STEPS):
		var tiles: Array = game.get("falling_tiles")
		if tiles.size() != 3:
			_fail(label + ": wave incomplete before descent checkpoint")
			return false
		var rect := _on_canvas_rect(tiles[0]["node"] as Control)
		if rect.position.y >= target_top:
			return true
		if not _advance_checked(game, label):
			return false
	_fail(label + ": apples did not clear top HUD within simulation limit")
	return false


func _check_art(game: Control, entry: Dictionary, label: String) -> void:
	var background := game.get_node_or_null("Background") as TextureRect
	var body := game.get_node_or_null("CharacterRig/Body") as Sprite2D
	var basket := game.get_node_or_null("CharacterRig/Basket") as Sprite2D
	var map_path := "res://Components/Gameplay/Catch the Word/Maps/%sMap.png" % entry["map"]
	var body_path := "res://Components/Gameplay/Catch the Word/Characters/%s BODY.png" % String(entry["character"]).to_upper()
	var basket_path := "res://Components/Gameplay/Catch the Word/Characters/%s BASKET.png" % String(entry["character"]).to_upper()
	if background == null or background.texture == null or background.texture.resource_path != map_path:
		_fail(label + ": original map not in use: " + map_path)
	if body == null or body.texture == null or body.texture.resource_path != body_path:
		_fail(label + ": original character not in use: " + body_path)
	if basket == null or basket.texture == null or basket.texture.resource_path != basket_path:
		_fail(label + ": original basket not in use: " + basket_path)


func _on_canvas_rect(control: Control) -> Rect2:
	var transform := control.get_global_transform_with_canvas()
	var origin := transform * Vector2.ZERO
	return Rect2(origin, transform * control.size - origin)


func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL ", message)
