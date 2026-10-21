extends SceneTree

# Focus, navigation and compact-viewport regression for the six authentic-art screens.
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const SCENES := {
	"tutorial_home": "res://ui/tutorial/tutorial_home.tscn",
	"tutorial_practice": "res://ui/tutorial/tutorial_practice.tscn",
	"grammar_guide": "res://ui/tutorial/grammar_guide.tscn",
	"tutorial_complete": "res://ui/tutorial/tutorial_complete.tscn",
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
			_check(clickable.size() >= (5 if route == "calibration" else 1), route + ": interactive native buttons")
			for button in clickable:
				var bounds := button.get_global_rect()
				_check(button.focus_mode == Control.FOCUS_ALL, route + ": " + button.text + " keyboard focus")
				_check(bounds.position.x >= -2.0 and bounds.position.y >= -2.0
					and bounds.end.x <= viewport.x + 2.0 and bounds.end.y <= viewport.y + 2.0,
					route + ": " + button.text + " fully onscreen at " + str(viewport))
			if route == "tutorial_home" and stage != null:
				# Painted buttons must be independent aspect-preserving images with
				# accessible native hitboxes, never stretched StyleBoxTextures.
				var expected := {
					"START GUIDED TUTORIAL": "camera_check",
					"MOVEMENT PRACTICE": "tutorial_practice",
					"GRAMMAR GUIDE": "grammar_guide",
					"BACK TO MAIN": "main"
				}
				var requests: Array[String] = []
				screen.requested.connect(func(target: String, _payload: Dictionary) -> void: requests.append(target))
				for button in clickable:
					var image_name := "ButtonArtwork_" + button.text.replace(" ", "_")
					var art := stage.get_node_or_null(image_name) as TextureRect
					_check(art != null, button.text + " uses separate PNG artwork")
					if art != null:
						_check(art.texture != null and art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
							button.text + " preserves source image ratio")
						_check(art.mouse_filter == Control.MOUSE_FILTER_IGNORE, button.text + " image cannot block clicks")
					_check(button.get_theme_stylebox("normal") is StyleBoxEmpty,
						button.text + " no longer stretches image through a stylebox")
					button.pressed.emit()
					_check(requests.size() > 0 and requests.back() == expected.get(button.text, ""),
						button.text + " still requests correct navigation target")
			if route == "tutorial_practice":
				screen.call("_run_demo_step")
				_check(int(screen.get("demo_step")) == 0, "practice advances first demo step")
				_check(str(screen.get("status_label").text).contains("not being read"), "practice discloses no body tracking")
			if route == "calibration":
				screen.call("_run_demo_step")
				_check(int(screen.get("demo_index")) == 0, "calibration advances first preview step")
				screen.call("_retry_calibration")
				_check(int(screen.get("demo_index")) == -1, "calibration retry resets preview")
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
		print("PASS tutorial redesign: %d checks across six routes and three viewport sizes" % checks)
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
