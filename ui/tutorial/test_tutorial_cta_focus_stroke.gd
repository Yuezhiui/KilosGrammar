extends SceneTree

# Regression: remove ONLY the unwanted yellow focus outline around
# START GUIDED TUTORIAL. Preserve the source PNG, button geometry, keyboard
# accessibility, focus/hover/click feedback and all three navigation routes.
# Godot --headless --path . -s res://ui/tutorial/test_tutorial_cta_focus_stroke.gd
const HOME := preload("res://ui/tutorial/tutorial_home.tscn")
const GUIDED_ART := "res://Components/Tutorial/Redesign/button_guided.png"
const VIEWPORTS := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]

var checks := 0
var issues: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport in VIEWPORTS:
		root.size = viewport
		root.content_scale_size = viewport
		var home := HOME.instantiate() as Control
		root.add_child(home)
		home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		var stage := home.get_node_or_null("TutorialStage") as Control
		_check(stage != null, "Stage exists at %s" % viewport)
		if stage == null:
			home.queue_free()
			await process_frame
			continue

		var start := stage.get_node_or_null("StartButton") as Button
		var grammar := stage.get_node_or_null("GrammarButton") as Button
		var back := stage.get_node_or_null("BackButton") as Button
		_check(start != null and grammar != null and back != null,
			"All three editor-authored CTA buttons remain")
		if start == null or grammar == null or back == null:
			home.queue_free()
			await process_frame
			continue

		_check(start.text == "START GUIDED TUTORIAL", "Start CTA accessible label is preserved")
		_check(start.position.is_equal_approx(Vector2(137, 535)),
			"Start CTA editor-authored position remains unchanged")
		_check(start.size.is_equal_approx(Vector2(345, 70)),
			"Start CTA editor-authored 345x70 hitbox remains unchanged")
		_check(start.focus_mode == Control.FOCUS_ALL,
			"Start CTA remains keyboard-focusable")
		_check(start.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND,
			"Start CTA keeps pointer cursor")
		for theme_state in ["normal", "hover", "pressed", "focus"]:
			_check(start.get_theme_stylebox(theme_state) is StyleBoxEmpty,
				"Start CTA has no native yellow stroke in %s state" % theme_state)
		_check(grammar.get_theme_stylebox("focus") is StyleBoxFlat,
			"Grammar CTA focus treatment is left unchanged")
		_check(back.get_theme_stylebox("focus") is StyleBoxFlat,
			"Back CTA focus treatment is left unchanged")
		var art := start.get_node_or_null("Artwork") as TextureRect
		_check(art != null and art.texture != null,
			"Original guided green PNG remains attached as child artwork")
		if art != null:
			_check(art.texture.resource_path == GUIDED_ART,
				"Exact original guided button PNG resource is preserved")
			_check(art.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"PNG does not block native button input")
			_check(art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
				"Source PNG aspect is preserved")
			_check(art.position.is_equal_approx(Vector2.ZERO)
				and art.size.is_equal_approx(start.size),
				"Green artwork fills the same authored CTA rectangle")

		start.grab_focus()
		await process_frame
		_check(start.has_focus(), "Start CTA keeps automatic focus at %s" % viewport)
		_check(start.get_theme_stylebox("focus") is StyleBoxEmpty,
			"Focused Start CTA does not render yellow outline")
		if art != null:
			_check(art.modulate.is_equal_approx(Color(1.10, 1.10, 1.10)),
				"Focused Start CTA retains existing brightening feedback")
		start.release_focus()
		await process_frame
		if art != null:
			_check(art.modulate.is_equal_approx(Color.WHITE),
				"Leaving keyboard focus restores original PNG colors")
		start.mouse_entered.emit()
		if art != null:
			_check(art.modulate.is_equal_approx(Color(1.10, 1.10, 1.10)),
				"Mouse hover brightens the PNG without a stylebox border")
		start.button_down.emit()
		if art != null:
			_check(art.modulate.is_equal_approx(Color(0.86, 0.86, 0.86)),
				"Pressed state keeps original darkening feedback")
		start.button_up.emit()
		start.mouse_exited.emit()
		if art != null:
			_check(art.modulate.is_equal_approx(Color.WHITE),
				"Mouse exit returns artwork to its normal color")
		_check(start.find_next_valid_focus() == grammar,
			"Tab navigation still moves Start to Grammar")
		_check(grammar.find_next_valid_focus() == back,
			"Tab navigation still moves Grammar to Back")

		var requests: Array[Dictionary] = []
		home.requested.connect(func(target: String, payload: Dictionary) -> void:
			requests.append({"target": target, "payload": payload.duplicate(true)})
		)
		start.pressed.emit()
		_check(requests.size() == 1 and requests[0]["target"] == "play_activity",
			"Start CTA still opens activity selection")
		if requests.size() >= 1:
			_check(requests[0]["payload"] == {
				"entry_source": "tutorial", "guided_tutorial": true, "fresh_setup": true
			}, "Start CTA still forwards guided tutorial context")
		grammar.pressed.emit()
		back.pressed.emit()
		_check(requests.size() == 3 and requests[1]["target"] == "grammar_guide"
			and requests[2]["target"] == "main",
			"Other two CTA routes are unchanged")

		home.queue_free()
		await process_frame

	if issues.is_empty():
		print("PASS Tutorial Start focus stroke: %d assertions across three viewports" % checks)
		quit(0)
	else:
		for problem in issues:
			push_error("TUTORIAL CTA FOCUS QA: " + problem)
		print("FAIL Tutorial Start focus stroke: %d failures / %d assertions" %
			[issues.size(), checks])
		quit(1)


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		issues.append(reason)
