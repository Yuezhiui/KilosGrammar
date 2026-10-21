extends SceneTree

# Headless verification of the actual generated title/score art, dynamic
# overlay visibility, and compact/editor-sized HUD geometry.
# Godot --headless --path . --script res://tools/test_catch_duplicate_labels.gd
#
# The PNGs visibly contain "CATCH THE WORD" and "SCORE": these words must
# not be painted again by runtime Label nodes. Keep only the question,
# game-mode value, and live numeric score labels visible.

const GAME_SCENE := "res://ui/minigames/catch_word.tscn"
const PNG_DIR := "res://ui/minigames/catch_hud/generated/"
const FONT_PATH := "res://assets/fonts/TitanOne-Regular.ttf"
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const MODES := ["Seconds", "Lives"]
const SIZES := [Vector2i(1280, 720), Vector2i(875, 500)]
const HIDDEN_HEADING_NODES := ["TitleLabel", "TitleTheLabel", "TitleWordLabel", "ScoreLabel"]
const STATIC_LIVES_PNGS := {
	1: PNG_DIR + "replacement/lives_state_1.png",
	2: PNG_DIR + "replacement/lives_state_2.png",
	3: PNG_DIR + "replacement/lives_state_3.png",
}

var checks := 0
var failures: Array[String] = []
var scenarios := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_size := root.size
	_check(_png_is_valid(PNG_DIR + "title_board.png"),
		"Generated title PNG exists, decodes, and has a substantial raster image")
	_check(_png_is_valid(PNG_DIR + "score_board.png"),
		"Generated score PNG exists, decodes, and has a substantial raster image")
	for amount in [3, 2, 1]:
		_check(_png_is_valid(String(STATIC_LIVES_PNGS[amount])),
			"Supplied static %d-lives PNG exists, imports and decodes" % amount)
	_check(ResourceLoader.exists(FONT_PATH), "Titan One question font exists")
	var packed := load(GAME_SCENE) as PackedScene
	_check(packed != null, "Catch Word scene loads")
	if packed != null:
		for screen_size in SIZES:
			await _run_size(packed, screen_size)
	root.size = original_size
	if failures.is_empty():
		print("PASS  Catch duplicate labels & compact HUD: %d checks across %d topic/mode/screen scenarios" % [checks, scenarios])
		quit(0)
	else:
		for failure in failures:
			push_error("CATCH DUPLICATE HUD QA: " + failure)
		print("FAIL  Catch duplicate labels & compact HUD: %d failures in %d checks, %d scenarios" % [failures.size(), checks, scenarios])
		quit(1)


func _png_is_valid(path: String) -> bool:
	if not FileAccess.file_exists(path) or not ResourceLoader.exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var png := Image.new()
	if png.load_png_from_buffer(bytes) != OK:
		return false
	return png.get_width() >= 300 and png.get_height() >= 100


func _run_size(packed: PackedScene, screen_size: Vector2i) -> void:
	root.size = screen_size
	await process_frame
	await process_frame
	var existing := root.get_child_count()
	var host := Control.new()
	host.name = "CatchEditorRectTestHost"
	host.size = Vector2(screen_size)
	root.add_child(host)
	var game := packed.instantiate() as Control
	if game == null or game.get_script() == null:
		_fail("%s: game scene/gameplay script failed to instantiate" % screen_size)
		host.queue_free()
		await process_frame
		return
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	game.set_process(false)

	var hud := game.get_node_or_null("HUDLayer/HUD") as Control
	if hud == null:
		_fail("%s: HUD control is missing" % screen_size)
		host.queue_free()
		await process_frame
		return
	var title := hud.get_node_or_null("TitlePlaque") as TextureRect
	var scoreboard := game.get_node_or_null("ScoreDrawLayer/ScorePlaque") as TextureRect
	var numeric := game.get_node_or_null("ScoreDrawLayer/ScoreBottomContainer/ScoreNumber") as Label
	var prompt := hud.get_node_or_null("PromptLabel") as Label
	var title_panel := title as Control
	var time_label := hud.get_node_or_null("TimeLabel") as Label
	var hearts := hud.get_node_or_null("HeartsBox") as HBoxContainer
	var timer_plaque := hud.get_node_or_null("TimerPlaque") as TextureRect
	var lives_plaque := hud.get_node_or_null("LivesPlaque") as TextureRect

	_check(bool(game.get("using_reference_pngs")),
		"%s: scene is actually using generated PNG plaques" % screen_size)
	_check(title != null and title.texture != null
		and title.texture.resource_path == PNG_DIR + "title_board.png",
		"%s: title drawn from the bitmap with baked CATCH THE WORD heading" % screen_size)
	_check(scoreboard != null and scoreboard.texture != null
		and scoreboard.texture.resource_path == PNG_DIR + "score_board.png",
		"%s: score board uses bitmap with baked SCORE heading" % screen_size)
	for absent_name in ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]:
		_check(not hud.has_node(absent_name),
			"%s: removed %s node is absent" % [screen_size, absent_name])
	if prompt != null and numeric != null and title_panel != null \
			and time_label != null and hearts != null \
			and timer_plaque != null and lives_plaque != null:
		for mode in MODES:
			for topic in TOPICS:
				game.call("set_context", {
					"activity": "Catch the Word",
					"topic": topic,
					"game_mode": mode,
					"difficulty": "Normal",
					"catch_character": "Boy",
					"catch_map": "Forest",
					"score": 108,
					"lives": 2,
					"time_remaining": 42.0,
					"round_running": true, # Simulate a saved 42s clock.
				})
				game.set_process(false)
				await process_frame
				scenarios += 1
				var context := "%s %s %s" % [screen_size, mode, topic]
				_assert_headings(hud, numeric, context)
				_assert_question(prompt, title_panel, topic, context)
				for absent_name in ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]:
					_check(not hud.has_node(absent_name),
						context + ": removed " + absent_name + " not recreated by set_context")
				_assert_mode(game, hearts, lives_plaque, time_label, timer_plaque, mode, context)
				_assert_offscreen(hud, screen_size, context)

	host.queue_free()
	await process_frame
	await process_frame
	_check(root.get_child_count() == existing, "%s: scene teardown has no remaining root children" % screen_size)


func _assert_headings(hud: Control, numeric: Label, context: String) -> void:
	var all_labels: Array[Label] = []
	_collect_labels(hud, all_labels)
	# Include the numeric score that now sits below the character canvas.
	if numeric != null:
		all_labels.append(numeric)
	var visible_headings := 0
	var visible_scores := 0
	var visible_live_numbers := 0
	var visible_texts: Array[String] = []
	for node in all_labels:
		if not node.is_visible_in_tree():
			continue
		var text_value := node.text.strip_edges()
		if text_value.is_empty():
			continue
		visible_texts.append(text_value)
		var normalized := text_value.to_upper().replace(" ", "")
		if normalized in ["CATCH", "THE", "WORD", "CATCHTHEWORD"]:
			visible_headings += 1
		if normalized.begins_with("SCORE"):
			visible_scores += 1
		if normalized.is_valid_int():
			visible_live_numbers += 1
	_check(visible_headings == 0 and visible_scores == 0,
		"%s: no duplicated CATCH/THE/WORD/SCORE text nodes (visible %s)" %
		[context, visible_texts])
	for node_name in HIDDEN_HEADING_NODES:
		var node := hud.get_node_or_null(node_name) as Label
		_check(node != null and not node.is_visible_in_tree(),
			"%s: %s label exists but stays hidden over baked text" % [context, node_name])
	var extra_score_titles := 0
	var visible_score_titles := 0
	var score_container := numeric.get_parent() if numeric != null else null
	if score_container != null:
		var container := score_container
		for child in container.get_children():
			if child is Label and (child as Label).text.strip_edges().to_upper() == "SCORE":
				extra_score_titles += 1
				if (child as Label).is_visible_in_tree():
					visible_score_titles += 1
	_check(visible_score_titles == 0,
		"%s: %d legacy SCORE title nodes, none visible on the baked PNG" %
		[context, extra_score_titles])
	_check(numeric.is_visible_in_tree() and numeric.text == "108"
		and visible_live_numbers == 1,
		"%s: exactly one editable 108 score value is visible (actual %s)" % [context, visible_texts])
	_check(visible_texts.size() == (3 if context.contains("Seconds") else 2),
		"%s: expected only question+score%s labels; actual %s" %
		[context, "+timer" if context.contains("Seconds") else "", visible_texts])


func _collect_labels(node: Node, result: Array[Label]) -> void:
	if node is Label:
		result.append(node as Label)
	for child in node.get_children():
		_collect_labels(child, result)


func _assert_question(label: Label, panel: Control, topic: String, context: String) -> void:
	var article := "AN" if topic in ["Adjective", "Adverb"] else "A"
	var expected := "WHICH WORD IS %s %s?" % [article, topic.to_upper()]
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var size_text := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	_check(label.text == expected and label.is_visible_in_tree(),
		context + ": exact visible grammar question")
	_check(label.clip_text and label.autowrap_mode == TextServer.AUTOWRAP_OFF,
		context + ": one-line question with overflow clipping enabled")
	_check(size_text.x <= label.size.x - 2.0 and font.get_height(font_size) <= label.size.y,
		"%s: question text is not actually clipped (text %s, container %s, font %d)" %
		[context, size_text, label.size, font_size])
	_check(label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER
		and label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER,
		context + ": question center aligned")
	var rect := label.get_global_rect()
	var board := panel.get_global_rect()
	_check(board.encloses(rect.grow(-0.5)), context + ": question rectangle stays inside title image")
	_check(absf(rect.get_center().x - board.get_center().x) <= board.size.x * 0.08,
		context + ": question centered within title image cream strip")


func _assert_mode(game: Control, hearts: HBoxContainer, lives: TextureRect, time: Label,
		timer: TextureRect, mode: String, context: String) -> void:
	if mode == "Seconds":
		_check(timer.is_visible_in_tree() and time.is_visible_in_tree()
			and time.text == "42s", context + ": timer text and PNG visible")
		_check(not lives.is_visible_in_tree() and not hearts.is_visible_in_tree(),
			context + ": static lives panel and legacy heart strip hidden while timer visible")
		_assert_no_dynamic_heart_overlays(hearts, context)
		return
	_check(lives.is_visible_in_tree() and not hearts.is_visible_in_tree(),
		context + ": static lives PNG visible without legacy heart strip")
	_check(not timer.is_visible_in_tree() and not time.is_visible_in_tree(),
		context + ": timer text and PNG fully hidden in Lives mode")
	# The user's new artwork paints all hearts directly into ONE state bitmap.
	# Verify 2 -> 1 and 3 -> 2 texture swaps instead of obsolete per-heart
	# visibility, color, spacing or independent position assertions.
	for amount in [2, 1, 3]:
		game.set("lives", amount)
		game.call("_refresh_hud")
		var expected: String = STATIC_LIVES_PNGS[amount]
		var actual := lives.texture.resource_path if lives.texture != null else ""
		_check(lives.is_visible_in_tree() and actual == expected,
			"%s: lives=%d displays exact static PNG (got %s)" % [context, amount, actual])
		_check(lives.texture != null and lives.texture.get_width() >= 300,
			"%s: lives=%d displays a decoded static heart image" % [context, amount])
		_check(not timer.is_visible_in_tree() and not time.is_visible_in_tree(),
			"%s: lives=%d keeps timer completely hidden" % [context, amount])
		_check(not hearts.is_visible_in_tree(),
			"%s: lives=%d has no legacy dynamic heart strip" % [context, amount])
		_assert_no_dynamic_heart_overlays(hearts, "%s lives=%d" % [context, amount])
		var panel := lives.get_global_rect()
		_check(panel.has_area() and lives.get_viewport_rect().encloses(panel.grow(-0.5)),
			"%s: lives=%d static panel stays inside viewport" % [context, amount])
	game.set("lives", 2)
	game.call("_refresh_hud")


func _assert_no_dynamic_heart_overlays(hearts: HBoxContainer, context: String) -> void:
	_check(not hearts.is_visible_in_tree(),
		context + ": legacy dynamic hearts container is not drawn")
	for icon in hearts.get_children():
		if icon is TextureRect:
			_check(not (icon as TextureRect).is_visible_in_tree(),
				"%s: legacy heart %s never paints over static art" % [context, icon.name])


func _assert_offscreen(hud: Control, screen_size: Vector2i, context: String) -> void:
	# Godot's project stretch setting keeps Controls in a 1280-wide logical
	# canvas, even when the *physical editor preview* is 875x500. A raw
	# get_global_rect() comparison to 875x500 falsely reports offscreen HUD.
	# Check both the logical viewport and the projected physical rectangle.
	var logical_size := hud.get_viewport_rect().size
	_check(logical_size.x > 0.0 and logical_size.y > 0.0,
		context + ": editor viewport has nonzero dimensions")
	if logical_size.x <= 0.0 or logical_size.y <= 0.0:
		return
	var logical_screen := Rect2(Vector2.ZERO, logical_size)
	var physical_screen := Rect2(Vector2.ZERO, Vector2(screen_size))
	var projection := Vector2(float(screen_size.x) / logical_size.x,
		float(screen_size.y) / logical_size.y)
	# Negative control: ensure the bounds test would catch a genuinely
	# offscreen element, rather than unconditionally passing the 875x500 case.
	var out_of_bounds := Rect2(Vector2(logical_size.x + 4.0, 12.0), Vector2(24.0, 24.0))
	_check(not _physical_bounds_ok(out_of_bounds, projection, physical_screen),
		context + ": bounds self-test rejects a deliberately offscreen control")
	_check(logical_screen.encloses(hud.get_global_rect().grow(-1.0)),
		"%s: HUD fits logical %s viewport (actual %s)" %
		[context, logical_size, hud.get_global_rect()])
	_check(_physical_bounds_ok(hud.get_global_rect(), projection, physical_screen),
		"%s: scaled HUD not offscreen in physical %s" % [context, screen_size])
	for name in ["TitlePlaque", "ScorePlaque", "PausePlaque",
			"PauseButton", "PromptLabel", "ScoreBottomContainer",
			"TimerPlaque", "LivesPlaque", "TimeLabel", "HeartsBox"]:
		var control := hud.get_parent().get_parent().get_node_or_null("ScoreDrawLayer/" + name) as Control if name in ["ScorePlaque", "ScoreBottomContainer"] else hud.get_node_or_null(name) as Control
		if control == null:
			_fail(context + ": missing HUD control " + name)
			continue
		if not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		_check(rect.has_area() and logical_screen.encloses(rect.grow(-0.5)),
			"%s: %s stays within logical screen %s (actual %s)" %
			[context, name, logical_size, rect])
		_check(_physical_bounds_ok(rect, projection, physical_screen),
			"%s: %s not offscreen in physical %s (projected %s)" %
			[context, name, screen_size,
				Rect2(rect.position * projection, rect.size * projection)])
	for child in hud.get_children():
		if child is Label and (child as Label).is_visible_in_tree():
			var label := child as Label
			_check(logical_screen.encloses(label.get_global_rect().grow(-0.5)),
				"%s: visible %s Label within logical viewport" % [context, label.name])
			_check(_physical_bounds_ok(label.get_global_rect(), projection, physical_screen),
				"%s: visible %s Label within physical viewport" % [context, label.name])


func _physical_bounds_ok(logical_rect: Rect2, scale: Vector2, physical_screen: Rect2) -> bool:
	var projected := Rect2(logical_rect.position * scale, logical_rect.size * scale)
	return projected.has_area() and physical_screen.encloses(projected.grow(-0.35))


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		_fail(description)


func _fail(description: String) -> void:
	failures.append(description)
