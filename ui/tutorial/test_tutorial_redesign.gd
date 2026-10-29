extends SceneTree

# Focus, navigation and compact-viewport regression for the current tutorial screens.
const BUTTON_SOUND_WIRING := preload("res://ui/shared/button_sound_wiring.gd")
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const SCENES := {
	"tutorial_home": "res://ui/tutorial/tutorial_home.tscn",
	"grammar_guide": "res://ui/tutorial/grammar_guide/grammar_guide.tscn",
	"calibration": "res://ui/vision/calibration/calibration.tscn"
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
			# Calling Calibration.set_context starts a real webcam/YOLO worker.
			# This QA checks its authored UI without accessing physical hardware.
			if route != "calibration":
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
			_check(clickable.size() >= 1,
				route + ": native navigation remains, including calibration's sole on-screen Back")
			if route in ["tutorial_home", "grammar_guide"]:
				# The main menu owns the only ButtonSounds instance in production.
				# A duplicate watch() must not duplicate any hover/click connections.
				var sounds := BUTTON_SOUND_WIRING.new()
				root.add_child(sounds)
				sounds.call("watch", screen)
				sounds.call("watch", screen)
				for button in clickable:
					for signal_name in ["mouse_entered", "focus_entered", "button_down"]:
						var owned := 0
						for connection: Dictionary in button.get_signal_connection_list(signal_name):
							if (connection["callable"] as Callable).get_object() == sounds:
								owned += 1
						_check(owned == 1,
							"%s/%s %s has one shared SFX listener after rewatch (got %d)" %
								[route, button.name, signal_name, owned])
				sounds.queue_free()
				await process_frame
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
				# Calibration no longer contains the retired neon guides or
				# redundant SKIP/RESET navigation controls.
				_check(not screen.has_method("_run_demo_step"), "calibration never fabricates pose steps")
				_check(stage.get_node_or_null("PoseGuides/PoseGuideDefault") is TextureRect,
					"center guide is editor-authored PoseGuideDefault PNG")
				_check(stage.get_node_or_null("ArtGuideCenter") == null,
					"retired ArtGuideCenter remains absent")
				_check(stage.get_node_or_null("Navigation/BackButton") is Button
					and clickable.size() == 1,
					"calibration retains exactly one native Back button")
			if route == "grammar_guide":
				var scroll := screen.get_node_or_null("TutorialStage/GrammarCardScroll") as ScrollContainer
				_check(scroll != null and scroll.focus_mode == Control.FOCUS_ALL, "grammar cards keyboard-scrollable")
				if scroll != null:
					var grid := scroll.get_node_or_null("GridContainer") as GridContainer
					_check(grid != null and grid.get_child_count() == 5,
						"Explore Grammar preserves exactly five editor-authored topic cards")
					if grid != null:
						var names: Array[String] = []
						for card in grid.get_children():
							var label := card.get_node_or_null("TopicName") as Label
							var badge := card.get_node_or_null("TopicBadge") as TextureRect
							var meaning := card.get_node_or_null("Meaning") as Label
							var examples := card.get_node_or_null("Examples") as Label
							_check(card.get_node_or_null("PanelArtwork") == null,
								"removed redundant panel artwork: " + card.name)
							_check(label != null and badge != null and badge.texture != null
								and meaning != null and examples != null
								and not meaning.text.is_empty() and not examples.text.is_empty(),
								"editable badge, topic and readable examples preserved: " + card.name)
							if label != null:
								names.append(label.text)
							if viewport.x >= 1280:
								_check(scroll.get_global_rect().grow(2).encloses(card.get_global_rect()),
									card.name + " fully visible initially at " + str(viewport))
						_check(names == ["NOUN", "PRONOUN", "VERB", "ADJECTIVE", "ADVERB"],
							"five exact topic names in required order, no retired placeholders")
					scroll.scroll_vertical = 300
					await process_frame
					_check(scroll.scroll_vertical > 0, "grammar guide still scrolls on demand")
					var back := stage.get_node_or_null("BackButton") as Button
					var nav: Array[String] = []
					screen.requested.connect(func(target: String, _payload: Dictionary) -> void: nav.append(target))
					if back != null:
						back.pressed.emit()
					_check(back != null and nav == ["tutorial_home"],
						"grammar guide Back emits exactly one tutorial_home navigation")
					if back != null:
						var art := back.get_node_or_null("Artwork") as TextureRect
						back.grab_focus()
						await process_frame
						_check(art != null and art.modulate.r >= 1.05,
							"grammar guide focus brightens the Back PNG without duplicate styling")
			screen.queue_free()
			await process_frame
	root.size = Vector2i(1280, 720)
	if issues.is_empty():
		print("PASS tutorial redesign: %d checks across four routes and four viewport sizes" % checks)
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
