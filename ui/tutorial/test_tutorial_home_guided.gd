extends SceneTree

# Focused regression for the editor-authored guided tutorial landing screen.
const TUTORIAL_HOME := preload("res://ui/tutorial/tutorial_home.tscn")
const VIEWPORTS := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const BUTTON_PATHS := ["StartButton", "GrammarButton", "BackButton"]
const CARD_PATHS := ["ChooseGameCard", "CameraCalibrateCard", "LearnPlayingCard"]
const CARD_TITLES := ["CHOOSE GAME", "CAMERA & CALIBRATE", "LEARN WHILE PLAYING"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport_size in VIEWPORTS:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		var home := TUTORIAL_HOME.instantiate() as Control
		root.add_child(home)
		home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame

		var stage := home.get_node_or_null("TutorialStage") as Control
		_check(stage != null, "authored TutorialStage exists")
		if stage == null:
			home.queue_free()
			await process_frame
			continue
		_check(stage.get_global_rect().position.x >= -2.0 and stage.get_global_rect().end.x <= viewport_size.x + 2.0, "stage fits viewport width")
		_check(stage.get_global_rect().position.y >= -2.0 and stage.get_global_rect().end.y <= viewport_size.y + 2.0, "stage fits viewport height")
		_check(stage.get_node_or_null("PracticeButton") == null, "old practice button removed")
		_check(stage.get_node_or_null("ButtonArtwork_MOVEMENT_PRACTICE") == null, "old practice artwork removed")
		_check(stage.get_node_or_null("StepsArtwork") == null, "painted legacy instruction cards removed")
		_check(stage.get_node_or_null("CameraAdvisoryArtwork") == null, "legacy camera-preview notice removed")

		for i in range(CARD_PATHS.size()):
			var card := stage.get_node_or_null(CARD_PATHS[i]) as Panel
			_check(card != null, "%s is an editor-authored card" % CARD_PATHS[i])
			if card != null:
				var title := card.get_node_or_null("Title") as Label
				_check(title != null and title.text == CARD_TITLES[i], "card title: %s" % CARD_TITLES[i])
				_check(card.get_node_or_null("Icon") is TextureRect, "%s icon is independently editable" % CARD_PATHS[i])
				_check(card.get_node_or_null("Description") is Label, "%s description is independently editable" % CARD_PATHS[i])

		var buttons: Array[Button] = []
		for path in BUTTON_PATHS:
			var button := stage.get_node_or_null(path) as Button
			_check(button != null, "%s is an editor-authored button" % path)
			if button == null:
				continue
			buttons.append(button)
			_check(button.focus_mode == Control.FOCUS_ALL, "%s supports keyboard focus" % path)
			var bounds := button.get_global_rect()
			_check(bounds.position.x >= -2.0 and bounds.position.y >= -2.0
				and bounds.end.x <= viewport_size.x + 2.0 and bounds.end.y <= viewport_size.y + 2.0,
				"%s fits %s" % [path, viewport_size])
			var art := button.get_node_or_null("Artwork") as TextureRect
			_check(art != null and art.texture != null, "%s has child PNG artwork" % path)
			if art != null:
				_check(art.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s artwork ignores input" % path)
				_check(art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "%s preserves PNG ratio" % path)
			_check(button.get_theme_stylebox("normal") is StyleBoxEmpty, "%s has an invisible hitbox" % path)
		_check(buttons.size() == 3, "exactly three navigation buttons")
		if buttons.size() == 3:
			for first in range(buttons.size()):
				for second in range(first + 1, buttons.size()):
					_check(not buttons[first].get_global_rect().intersects(buttons[second].get_global_rect()), "navigation button hitboxes do not overlap")

			var requests: Array[Dictionary] = []
			home.requested.connect(func(target: String, payload: Dictionary) -> void:
				requests.append({"target": target, "payload": payload}))
			buttons[0].pressed.emit()
			_check(requests.size() == 1 and requests[0]["target"] == "play_activity", "guided tutorial opens game selection")
			if requests.size() == 1:
				_check(requests[0]["payload"] == {"entry_source": "tutorial", "guided_tutorial": true, "fresh_setup": true}, "guided tutorial carries setup payload")
			buttons[1].pressed.emit()
			_check(requests.size() == 2 and requests[1]["target"] == "grammar_guide", "grammar guide route works")
			buttons[2].pressed.emit()
			_check(requests.size() == 3 and requests[2]["target"] == "main", "main menu route works")

		home.queue_free()
		await process_frame

	root.size = Vector2i(1280, 720)
	if failures.is_empty():
		print("PASS tutorial home guided: %d checks at three viewport sizes" % checks)
		quit(0)
	else:
		for message in failures:
			push_error(message)
		print("FAIL tutorial home guided: %d failures / %d checks" % [failures.size(), checks])
		quit(1)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
