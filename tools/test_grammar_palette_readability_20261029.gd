extends SceneTree
## Panel-free grammar cards and readable body typography. Native GL screenshot validation,
## no main menu, database or camera involved.
const SCENE := preload("res://ui/tutorial/grammar_guide/grammar_guide.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := ProjectSettings.globalize_path("res://showcase/grammar_palette_update_20261029")
	_check(DirAccess.make_dir_recursive_absolute(output) == OK, "preview directory available")
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	for viewport in SIZES:
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_size(viewport)
		root.size = viewport
		root.content_scale_size = viewport
		await process_frame
		var guide := SCENE.instantiate() as Control
		root.add_child(guide)
		guide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		var scroll := guide.get_node("TutorialStage/GrammarCardScroll") as ScrollContainer
		var grid := scroll.get_node("GridContainer") as GridContainer
		_check(grid.get_child_count() == 5, "all five topic cards still present at %s" % viewport)
		for topic in TOPICS:
			var card := grid.get_node(topic + "Card") as Control
			var badge := card.get_node("TopicBadge") as TextureRect
			var title := card.get_node("TopicName") as Label
			var meaning := card.get_node("Meaning") as Label
			var examples := card.get_node("Examples") as Label
			_check(card.get_node_or_null("PanelArtwork") == null,
				"removed redundant background frame for %s" % topic)
			_check(badge.texture != null and title.text == topic.to_upper(),
				"original art and title preserved for %s" % topic)
			_check(not meaning.has_theme_font_override("font") and not examples.has_theme_font_override("font"),
				"clearer built-in sans-serif replaces scratchy GochiHand for %s" % topic)
			_check(int(meaning.get_theme_font_size("font_size")) == 18
				and int(examples.get_theme_font_size("font_size")) == 16,
				"readable two-level typographic hierarchy for %s" % topic)
			# Godot enlarges Label layout rectangles to the active font metrics.
			# Check actual line center separation and the interior-safe baseline,
			# rather than rejecting overlapping invisible layout padding.
			var meaning_center := meaning.position.y + meaning.size.y * 0.5
			var example_center := examples.position.y + examples.size.y * 0.5
			_check(example_center - meaning_center >= 17.0 and example_center < card.size.y - 19.0,
				"definition and example baselines stay inside card bounds for %s" % topic)
			_check(card.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1.0,
				"topic %s visible without initial scroll at %s" % [topic, viewport])
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var filename := output.path_join("grammar_%dx%d.png" % [viewport.x, viewport.y])
			_check(image.get_size() == viewport and image.save_png(filename) == OK,
				"native preview captured at %s" % viewport)
			print("GRAMMAR PALETTE IMAGE: ", filename)
		guide.queue_free()
		await process_frame
	print("GRAMMAR PALETTE QA: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for problem in failures:
		printerr("GRAMMAR PALETTE QA FAIL: " + problem)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
