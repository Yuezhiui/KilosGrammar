extends SceneTree

# Focus, navigation and compact-viewport regression for the current tutorial screens.
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const SCENES := {
	"tutorial_home": "res://ui/tutorial/tutorial_home.tscn",
	"grammar_guide": "res://ui/tutorial/grammar_guide.tscn",
	"camera_check": "res://ui/vision/camera_check.tscn",
	"calibration": "res://ui/vision/calibration.tscn"
}
var checks := 0
var issues: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for viewport in SIZES:
		root.size = viewport
		root.content_scale_size = viewport
		for route in SCENES:
			var resource := load(SCENES[route]) as PackedScene
			_check(resource != null, route + ": resource imported")
			if resource == null:
				continue
			var screen := resource.instantiate() as Control
			root.add_child(screen)
			screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			screen.call("set_context", {"entry_source": "tutorial", "preview_mode": true, "camera_live": false, "name": "STUDENT"})
			await process_frame
			await process_frame
			var stage := screen.get_node_or_null("TutorialStage") as Control
			_check(stage != null, route + ": native responsive design stage exists")
			if stage != null:
				var box := stage.get_global_rect()
				_check(box.position.x >= -2.0 and box.position.y >= -2.0
					and box.end.x <= viewport.x + 2.0 and box.end.y <= viewport.y + 2.0,
					route + ": stage visible at " + str(viewport))
			var clickable: Array[Button] = []
			_collect_buttons(screen, clickable)
			_check(clickable.size() >= (2 if route == "calibration" else 1),
				route + ": interactive native buttons; calibration's deleted legacy controls stay absent")
			for button in clickable:
				var bounds := button.get_global_rect()
				_check(button.focus_mode == Control.FOCUS_ALL, route + ": " + button.text + " keyboard focus")
				_check(bounds.position.x >= -2.0 and bounds.position.y >= -2.0
					and bounds.end.x <= viewport.x + 2.0 and bounds.end.y <= viewport.y + 2.0,
					route + ": " + button.text + " fully onscreen at " + str(viewport))
			if route == "tutorial_home" and stage != null:
				# Guided flow is authored in the editor as three independent
				# native buttons with aspect-preserving PNG children.
				var expected := {
					"START GUIDED TUTORIAL": "play_activity",
					"GRAMMAR GUIDE": "grammar_guide",
					"BACK TO MAIN": "main"
				}
				_check(clickable.size() == expected.size(), "tutorial home: exactly three navigation buttons")
				_check(stage.get_node_or_null("PracticeButton") == null, "tutorial home: no legacy movement practice button")
				_check(stage.get_node_or_null("StepsArtwork") == null, "tutorial home: no baked legacy instructions")
				var titles := {
					"ChooseGameCard": "CHOOSE GAME",
					"CameraCalibrateCard": "CAMERA & CALIBRATE",
					"LearnPlayingCard": "LEARN WHILE PLAYING"
				}
				for card_name in titles:
					var card := stage.get_node_or_null(card_name) as Panel
					_check(card != null, card_name + " editable stage card")
					if card != null:
						var title := card.get_node_or_null("Title") as Label
						_check(title != null and title.text == titles[card_name], card_name + " title")
						_check(card.get_node_or_null("Icon") is TextureRect, card_name + " editable icon")
				var requests: Array[Dictionary] = []
				screen.requested.connect(func(target: String, payload: Dictionary) -> void:
					requests.append({"target": target, "payload": payload})
				)
				for button in clickable:
					var art := button.get_node_or_null("Artwork") as TextureRect
					_check(art != null, button.text + " uses editor-authored PNG child artwork")
					if art != null:
						_check(art.texture != null and art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
							button.text + " preserves source image ratio")
						_check(art.mouse_filter == Control.MOUSE_FILTER_IGNORE, button.text + " image cannot block clicks")
					_check(button.get_theme_stylebox("normal") is StyleBoxEmpty,
						button.text + " no longer stretches image through a stylebox")
					button.pressed.emit()
					_check(requests.size() > 0 and requests.back()["target"] == expected.get(button.text, ""),
						button.text + " still requests correct navigation target")
				_check(requests.size() == 3, "all three navigation buttons emit requests")
				if requests.size() > 0:
					var guided: Dictionary = requests[0]["payload"]
					_check(bool(guided.get("guided_tutorial", false)), "guided tutorial flag reaches game selection")
					_check(guided.get("entry_source") == "tutorial", "guided tutorial entry source is preserved")
					_check(bool(guided.get("fresh_setup", false)), "guided tutorial starts with fresh student setup")
			if route == "calibration":
				# Calibration requires real tracked camera packets, not the old
				# synthetic demo-step API. Validate only scene-authored visuals here.
				_check(not screen.has_method("_run_demo_step"), "calibration never fabricates pose steps")
				_check(stage.get_node_or_null("ArtGuideCenter") is TextureRect,
					"center guide is editor-authored PNG, not an autogenerated overlay")
			if route == "camera_check":
				screen.call("_refresh_preview_status")
				_check(str(screen.get("info_label").text).contains("NOT CONNECTED"), "camera status remains disconnected")
			if route == "grammar_guide":
				var scroll := screen.get_node_or_null("TutorialStage/GrammarCardScroll") as ScrollContainer
				_check(scroll != null and scroll.focus_mode == Control.FOCUS_ALL, "grammar cards keyboard-scrollable")
				if scroll != null:
					scroll.scroll_vertical = 300
					await process_frame
					_check(scroll.scroll_vertical > 0, "grammar guide exposes lower cards")
			screen.queue_free()
			await process_frame
	root.size = Vector2i(1280, 720)
	if issues.is_empty():
		print("PASS tutorial redesign: %d checks across four routes and three viewport sizes" % checks)
		quit(0)
	else:
		for issue in issues:
			push_error(issue)
		print("FAIL tutorial redesign: %d failures / %d checks" % [issues.size(), checks])
		quit(1)

func _collect_buttons(node: Node, result: Array[Button]) -> void:
	if node is Button:
		result.append(node)
	for child in node.get_children():
		_collect_buttons(child, result)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		issues.append(message)
