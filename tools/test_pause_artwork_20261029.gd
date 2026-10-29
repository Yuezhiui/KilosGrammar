extends SceneTree

## Isolated Pause UI QA: no main-menu/router, webcam/YOLO, Postgres or scores.
## Godot 4.7.2 --headless --path . --script res://tools/test_pause_artwork_20261029.gd
## For real screenshots use graphical OpenGL and PAUSE_QA_CAPTURE=1.
const SCENE := preload("res://ui/play/pause/pause.tscn")
const SOUND := preload("res://ui/shared/button_sound_wiring.gd")
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const ACTIONS := [
	["ResumeButton", "RESUME", "gameplay", "button_resume.png"],
	["RestartButton", "RESTART ROUND", "restart", "button_restart_round.png"],
	["ChangeSetupButton", "CHANGE SETUP", "last_play", "button_change_setup.png"],
	["ResultsButton", "VIEW RESULTS", "results", "button_view_results.png"],
	["MainMenuButton", "MAIN MENU", "main", "button_main_menu.png"],
]

var checks := 0
var failures: Array[String] = []
var captures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport in VIEWPORTS:
		root.size = viewport
		root.content_scale_size = viewport
		var screen := SCENE.instantiate() as Control
		_check(screen != null, "Pause scene instantiates at " + str(viewport))
		if screen == null:
			continue
		root.add_child(screen)
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		var stage := screen.get_node_or_null("PauseStage") as Control
		var card := screen.get_node_or_null("PauseStage/PauseCard") as Control
		var background := screen.get_node_or_null("ClassroomBackground") as TextureRect
		var dim := screen.get_node_or_null("BlackDim") as ColorRect
		_check(stage != null and card != null, "Editor-authored stage and purple card at " + str(viewport))
		_check(background != null and background.texture != null
			and background.texture.resource_path == "res://Components/Credits/Redesign/background1.png",
			"Exact Credits background at " + str(viewport))
		_check(dim != null and is_equal_approx(dim.color.a, 0.10),
			"Exactly 10% black dim opacity editable in Inspector at " + str(viewport))
		if stage == null or card == null:
			screen.queue_free()
			await process_frame
			continue
		var stage_rect := stage.get_global_rect()
		_check(stage_rect.position.x >= -1.0 and stage_rect.position.y >= -1.0
			and stage_rect.end.x <= viewport.x + 1.0 and stage_rect.end.y <= viewport.y + 1.0,
			"Pause stage fits target resolution " + str(viewport))
		_check(absf(stage.scale.x - stage.scale.y) < 0.0001,
			"Pause artwork scales uniformly at " + str(viewport))
		for pair in [
			["PanelArtwork", "pause_panel.png"],
			["HeadingArtwork", "pause_heading.png"]
		]:
			var node := card.get_node_or_null(pair[0]) as TextureRect
			_check(node != null and node.texture != null
				and node.texture.resource_path == "res://Components/Pause/Redesign/" + pair[1],
				"Original separate " + pair[0] + " PNG at " + str(viewport))
		_check(card.get_child_count() == 7,
			"Exactly panel, heading and five authored Buttons, no extra actions")
		var input := {"activity": "Catch the Word", "score": 123, "topic": "Noun",
			"identity": {"student_id": "QA-ISOLATED", "list": [1, 2]}}
		screen.set_context(input)
		input["identity"]["list"].append(99)
		_check(screen.context["identity"]["list"] == [1, 2],
			"Pause owns deep-copied payload independent of external mutations")
		var recorded: Array[Dictionary] = []
		screen.requested.connect(func(route: String, payload: Dictionary) -> void:
			recorded.append({"route": route, "payload": payload.duplicate(true)})
		)
		var sound := SOUND.new()
		root.add_child(sound)
		sound.call("watch", screen)
		sound.call("watch", screen) # Intentional: listener counts MUST stay one.
		var global_hover: Node = null
		for singleton in root.get_children():
			var singleton_script := singleton.get_script() as Script
			if singleton_script != null and singleton_script.resource_path == "res://ui/shared/global_button_hover.gd":
				global_hover = singleton
		_check(global_hover != null, "Existing GlobalButtonHover autoload owns animation")
		for item in ACTIONS:
			var button := card.get_node_or_null(item[0]) as Button
			_check(button != null, item[0] + ": editor-authored native Button")
			if button == null:
				continue
			_check(button.text == item[1] and button.focus_mode == Control.FOCUS_ALL
				and not button.disabled and button.is_visible_in_tree(),
				item[0] + ": accessible, enabled, focusable and visible")
			_check(stage_rect.encloses(button.get_global_rect()) and
				card.get_global_rect().encloses(button.get_global_rect()),
				item[0] + ": hitbox entirely inside board and viewport")
			var art := button.get_node_or_null("Artwork") as TextureRect
			_check(art != null and art.texture != null
				and art.texture.resource_path == "res://Components/Pause/Redesign/" + item[3]
				and art.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				item[0] + ": original PNG never intercepts touch or mouse")
			for signal_name in ["mouse_entered", "focus_entered", "button_down"]:
				var listeners := 0
				for connection: Dictionary in button.get_signal_connection_list(signal_name):
					if (connection["callable"] as Callable).get_object() == sound:
						listeners += 1
				_check(listeners == 1,
					item[0] + ": one main-menu shared SFX owner on " + signal_name)
			_check(button.has_meta("kg_global_hover_bound"),
				item[0] + ": one GlobalButtonHover handler bound")
			if global_hover != null:
				var animation_listeners := 0
				for connection: Dictionary in button.get_signal_connection_list("mouse_entered"):
					if (connection["callable"] as Callable).get_object() == global_hover:
						animation_listeners += 1
				_check(animation_listeners == 1,
					item[0] + ": exactly one native global hover animation listener")
			button.pressed.emit()
			_check(recorded.size() > 0 and recorded.back()["route"] == item[2],
				item[0] + ": correct existing router target " + item[2])
			_check(recorded.back()["payload"]["identity"]["list"] == [1, 2],
				item[0] + ": original context remains intact in emitted payload")
			# Caller mutating one result must not poison later navigation.
			recorded.back()["payload"]["identity"]["list"].append(9)
		_check(recorded.size() == ACTIONS.size(), "Exactly five signals for five actions")
		# Stop fixture audio hooks before graphical capture. Shared sound/audio
		# plumbing is *inspected*, not actually played, so exit stays leak-free.
		sound.queue_free()
		await process_frame
		if OS.get_environment("PAUSE_QA_CAPTURE") == "1":
			if DisplayServer.get_name() == "headless":
				_check(false, "Screenshots require a graphical renderer")
			else:
				await RenderingServer.frame_post_draw
				var output_dir := ProjectSettings.globalize_path("res://Components/Pause/Redesign/QA")
				DirAccess.make_dir_recursive_absolute(output_dir)
				var screenshot := output_dir.path_join("pause_%dx%d.png" % [viewport.x, viewport.y])
				var image := root.get_texture().get_image()
				var err := image.save_png(screenshot)
				_check(err == OK and image.get_size() == viewport,
					"Pause graphics saved at exact " + str(viewport))
				if err == OK:
					print("PAUSE_SCREENSHOT " + screenshot)
					captures += 1
		screen.queue_free()
		await process_frame
		await process_frame
		_check(not is_instance_valid(screen), "Pause editor instance freed after " + str(viewport))
	if failures.is_empty():
		print("PAUSE ARTWORK QA: PASS checks=%d viewports=%d screenshots=%d failures=0" %
			[checks, VIEWPORTS.size(), captures])
		quit(0)
	else:
		for problem in failures:
			printerr("PAUSE ARTWORK QA FAIL: " + problem)
		print("PAUSE ARTWORK QA: FAIL checks=%d viewports=%d failures=%d" %
			[checks, VIEWPORTS.size(), failures.size()])
		quit(1)


func _check(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures.append(detail)
