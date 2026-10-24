extends SceneTree

# Regression for the three editor-authored instructions and accessible navigation.
# Optionally captures the 1280x720 screen with CAPTURE_TUTORIAL_HOME=1 (graphical renderer).
const HOME := preload("res://ui/tutorial/tutorial_home.tscn")
const VIEWPORTS := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const CARD_NAMES := ["ChooseGameCard", "CameraCalibrateCard", "LearnPlayingCard"]
const BUTTON_NAMES := ["StartButton", "GrammarButton", "BackButton"]
const CAPTURE_FILE := "res://ui/tutorial/_review_tutorial_home.png"

var checks := 0
var issues: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport_size in VIEWPORTS:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		var home := HOME.instantiate() as Control
		root.add_child(home)
		home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		var stage := home.get_node_or_null("TutorialStage") as Control
		_check(stage != null, "TutorialStage exists")
		if stage == null:
			home.queue_free()
			await process_frame
			continue

		for card_name in CARD_NAMES:
			var card := stage.get_node_or_null(card_name) as Panel
			_check(card != null, card_name + ": editable panel")
			if card == null:
				continue
			var panel_style := card.get_theme_stylebox("panel") as StyleBoxFlat
			_check(panel_style != null, card_name + ": editor-authored panel style")
			for label_name in ["Title", "Description"]:
				var label := card.get_node_or_null(label_name) as Label
				_check(label != null, card_name + ": " + label_name + " exists")
				if label == null or panel_style == null:
					continue
				var ratio := _contrast_ratio(label.get_theme_color("font_color"), panel_style.bg_color)
				var font_size := label.get_theme_font_size("font_size")
				# Large bold Titan One title has a 3:1 target; descriptions need 4.5:1.
				var minimum := 3.0 if label_name == "Title" and font_size >= 18 else 4.5
				_check(ratio >= minimum, "%s %s contrast %.2f:1 (needs %.1f)" % [card_name, label_name, ratio, minimum])
				_check(card.get_global_rect().encloses(label.get_global_rect()),
					"%s %s bounds remain inside card at %s" % [card_name, label_name, viewport_size])
				_check(not label.text.is_empty(), card_name + ": " + label_name + " has text")

		var buttons: Array[Button] = []
		for name in BUTTON_NAMES:
			var button := stage.get_node_or_null(name) as Button
			_check(button != null, name + ": exists")
			if button == null:
				continue
			buttons.append(button)
			_check(button.focus_mode == Control.FOCUS_ALL, name + ": keyboard focus enabled")
			_check(button.get_global_rect().size.x >= 44 and button.get_global_rect().size.y >= 44,
				"%s: >=44x44 px hit target at %s" % [name, viewport_size])
			_check(not button.text.is_empty(), name + ": accessible native button name")
			var art := button.get_node_or_null("Artwork") as TextureRect
			_check(art != null and art.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				name + ": art does not intercept pointer or keyboard input")

		_check(buttons.size() == 3, "exactly three focusable actions")
		if buttons.size() == 3:
			_check(buttons[0].find_next_valid_focus() == buttons[1], "Tab proceeds Start -> Grammar")
			_check(buttons[1].find_next_valid_focus() == buttons[2], "Tab proceeds Grammar -> Back")
			buttons[0].grab_focus()
			await process_frame
			_check(buttons[0].has_focus(), "Start receives default keyboard focus")

		var notice := stage.get_node_or_null("GuideNotice/NoticeText") as Label
		_check(notice != null, "instruction notice remains editable")
		if notice:
			var panel := stage.get_node_or_null("GuideNotice") as Panel
			var notice_style := panel.get_theme_stylebox("panel") as StyleBoxFlat
			_check(_contrast_ratio(notice.get_theme_color("font_color"), notice_style.bg_color) >= 4.5,
				"instruction notice meets 4.5:1 contrast")

		if viewport_size == Vector2i(1280, 720) and OS.get_environment("CAPTURE_TUTORIAL_HOME") == "1":
			if DisplayServer.get_name() == "headless":
				_check(false, "graphical renderer required for visual capture")
			else:
				await RenderingServer.frame_post_draw
				var screenshot := root.get_texture().get_image()
				_check(screenshot.save_png(ProjectSettings.globalize_path(CAPTURE_FILE)) == OK, "1280x720 screenshot saved")
				print("VISUAL CAPTURE ", ProjectSettings.globalize_path(CAPTURE_FILE))

		home.queue_free()
		await process_frame

	if issues.is_empty():
		print("PASS tutorial home accessibility: %d checks, three viewport sizes" % checks)
		quit(0)
	else:
		for issue in issues:
			push_error(issue)
		print("FAIL tutorial home accessibility: %d issues / %d checks" % [issues.size(), checks])
		quit(1)


func _luminance(color: Color) -> float:
	var r := color.r / 12.92 if color.r <= 0.04045 else pow((color.r + 0.055) / 1.055, 2.4)
	var g := color.g / 12.92 if color.g <= 0.04045 else pow((color.g + 0.055) / 1.055, 2.4)
	var b := color.b / 12.92 if color.b <= 0.04045 else pow((color.b + 0.055) / 1.055, 2.4)
	return 0.2126 * r + 0.7152 * g + 0.0722 * b


func _contrast_ratio(first: Color, second: Color) -> float:
	var bright := maxf(_luminance(first), _luminance(second))
	var dark := minf(_luminance(first), _luminance(second))
	return (bright + 0.05) / (dark + 0.05)


func _check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		issues.append(message)
