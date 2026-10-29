extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_game_chooser_redesign.gd
# Synthetic-only UI regression: no live camera, database or score mutation.
const SCENE := preload("res://ui/play/activity/play_activity.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const PREFIX := "LayoutMargins/Content/"
const BUTTON_PREFIX := PREFIX + "GameRow/GameOptions/GameOptionsContent/"
const PREVIEW_PATH := PREFIX + "GameRow/GameDetail/DetailContent/SelectedPreview"
const NEXT_PATH := PREFIX + "Footer/NextButton"
const CASES := {
	"Catch the Word": ["CatchWordButton", "catch the word.png", "catch the word button.png"],
	"Human Plane": ["HumanPlaneButton", "human plane.png", "human plane button.png"],
	"Balloon Popping": ["BalloonPoppingButton", "balloon popping.png", "ballooon popping button.png"]
}
const SOURCE_SHA256 := {
	"back button.png": "6ed54ddb00978d55b649cf2859269cad5d7a12faa5b879e0a21d3fea3538f1dd",
	"balloon popping.png": "c51f5b8ec575887adcbd1cad714be91943e814eb483fa0c654bcb954df3f6ad3",
	"ballooon popping button.png": "65e491066d3348a94827caa448140bf865acaed6175cea71856ab88e5764ac47",
	"bg1.png": "732c72f144f6c87f2c852467e28cc7e592030b307c0c6ed731871c51c8178cdb",
	"catch the word button.png": "c885fdc182a0a20dbb540aee21b0035d679a9341fffda708f4b120a768bc5d26",
	"catch the word.png": "e6e192eee7a03602633158753e0661e7f35906c0fa029bee009915b309deb097",
	"choose an activity.png": "5efce5bc36b0e2b9e10c5bdff2004ee49f4e4f0d7617de1a07b5620c3bef76c8",
	"header1.png": "140b0cfa8696b9656441c1ce51b5989074161f9d3eb8f7f288c38bb3972d9d6a",
	"human plane button.png": "331f8fe496683211c8e944b4046e8498188d4e6acc842a7bd66ddaafdfbadbd3",
	"human plane.png": "4cc53711768ac3fcda1577d7cb03eefc01349ab7e2c441dbbcb5169628feb0f0",
	"next student setup if already choose.png": "fe13dc0d6b1fafd6c5683c8e84446c24b17da6540edc75b64a2975bafcea80c7",
	"next student setup.png": "82e528378c9c3f07c38a5bcb118a1abbeb021e1e5f620d316493cda639b9b6e4",
	"select game default.png": "c259e8059c305d898eb302e57c95f5c1679f041b77c1af97d9c77e5e4452f0fb"
}

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ResourceLoader.exists("res://ui/play/activity/play_activity.tscn"), "production scene retained at original route")
	_check(ResourceLoader.exists("res://Components/Shared/Redesign/classroom_bg.png"),
		"shared classroom background available")
	var scene_source := FileAccess.get_file_as_string("res://ui/play/activity/play_activity.tscn")
	var script_source := FileAccess.get_file_as_string("res://ui/play/activity/play_activity.gd")
	var host_source := FileAccess.get_file_as_string("res://ui/main_menu/main_menu.gd")
	_check(script_source.contains("camera_model_prewarm_requested")
		and host_source.contains("active_panel.connect(\"camera_model_prewarm_requested\"")
		and host_source.contains("prewarm_camera_model"),
		"explicit activity selection requests early camera-OFF YOLO prewarm through the main menu")
	_check(not scene_source.contains("SelectedOutline") and not scene_source.contains("SelectedFrame"),
		"removed all old bright yellow selected-border scene nodes and style")
	_check(not scene_source.contains("SelectedBadge") and not scene_source.contains("SelectedDescription")
		and not scene_source.contains("SelectedTitle"),
		"removed old hidden compatibility labels")
	var present_pngs := 0
	var present_imports := 0
	var unexpected_files: Array[String] = []
	var directory := DirAccess.open("res://Components/Game Chooser")
	if directory != null:
		for filename in directory.get_files():
			if filename.ends_with(".png"):
				present_pngs += 1
			elif filename.ends_with(".png.import"):
				present_imports += 1
				var original := filename.trim_suffix(".import")
				_check(FileAccess.file_exists("res://Components/Game Chooser/" + original),
					"import sidecar belongs to existing image: " + filename)
			elif filename != "README.md":
				unexpected_files.append(filename)
	_check(present_pngs == SOURCE_SHA256.size(),
		"chooser contains only 13 proved-live original PNGs; no orphan old buttons")
	_check(present_imports == present_pngs and unexpected_files.is_empty(),
		"no orphan import metadata, old button manifests, or stale source files: " + str(unexpected_files))
	for filename in SOURCE_SHA256:
		var path: String = "res://Components/Game Chooser/" + String(filename)
		_check(FileAccess.file_exists(path), "byte-exact original exists: " + filename)
		_check(FileAccess.get_sha256(path) == String(SOURCE_SHA256[filename]), "original SHA-256 unchanged: " + filename)
		_check(FileAccess.file_exists(path + ".import"), "Godot .import generated for: " + filename)
		_check(scene_source.contains(path) or script_source.contains(path),
			"retained PNG is actually loaded by scene or dynamic preview/Next: " + filename)
	for resolution in SIZES:
		await _exercise(resolution)
	print("GAME CHOOSER REDESIGN: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _exercise(resolution: Vector2i) -> void:
	root.size = resolution
	var game := SCENE.instantiate() as Control
	_check(game != null, "Scene instantiates at %s" % resolution)
	if game == null:
		return
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	var label := "%dx%d" % [resolution.x, resolution.y]
	var layout := game.get_node("LayoutMargins") as Control
	# The project uses Godot's 1280x720 logical viewport at larger host sizes.
	# The artboard must fill the actual Control size; the engine handles the
	# remaining physical resolution scaling.
	var expected_scale := game.size.x / 1280.0
	_check(absf(layout.scale.x - expected_scale) < 0.01 and
		absf(layout.scale.y - expected_scale) < 0.01,
		label + " full scene artboard uniformly responsive")
	_check(layout.position.distance_to(Vector2.ZERO) < 0.2,
		label + " centered artboard without viewport clipping")
	var preview := game.get_node(PREVIEW_PATH) as TextureRect
	var next := game.get_node(NEXT_PATH) as Button
	var next_art := next.get_node("Artwork") as TextureRect
	var back := game.get_node(PREFIX + "Footer/BackButton") as Button
	var routes: Array[Dictionary] = []
	game.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target": target, "payload": payload.duplicate(true)}))
	var warmup_signals := [0]
	game.camera_model_prewarm_requested.connect(func() -> void: warmup_signals[0] += 1)
	_check(game.get_node(PREFIX + "Header/ChooseActivityArtwork") is TextureRect
		and game.get_node(PREFIX + "Header/InstructionArtwork") is TextureRect
		and game.get_node(PREFIX + "GameRow/GameOptions/BoardArtwork") is TextureRect,
		label + " header and Game Options board scene-authored")
	_check(game.get_node("CleanBackdrop") is TextureRect and
		(game.get_node("CleanBackdrop") as TextureRect).texture.resource_path.ends_with("classroom_bg.png"),
		label + " classroom backdrop matches supplied screenshot")
	_check(not next.has_focus() and next.disabled, label + " Next disabled before selection")
	_check(preview.texture.resource_path.ends_with("select game default.png"),
		label + " right board shows exactly default artwork")
	var inactive_crop := next_art.texture as AtlasTexture
	_check(inactive_crop != null and inactive_crop.atlas != null and
			inactive_crop.atlas.resource_path.ends_with("next student setup.png") and
			inactive_crop.region.size.x > inactive_crop.region.size.y * 4.0,
			label + " gray default artwork uses visible-ink crop without stretching lettering")
	var buttons: Dictionary = game.get("activity_buttons")
	_check(buttons.size() == 3, label + " exactly three game buttons registered")
	for name in CASES:
		var btn := buttons.get(name) as Button
		_check(btn != null and not btn.button_pressed, label + " " + name + " initially unselected")
		_check(btn.get_node("Artwork") is TextureRect and
			(btn.get_node("Artwork") as TextureRect).texture.resource_path.ends_with(
				String(CASES[name][2])),
			label + " " + name + " uses native Button with scene-authored art")
		_check(btn.get_node_or_null("SelectedFrame") == null and
			(btn.get_node("Artwork") as TextureRect).modulate == Color.WHITE,
			label + " " + name + " has no yellow border and neutral default art tint")
		var focus_style := btn.get_theme_stylebox("focus")
		_check(focus_style is StyleBoxEmpty,
				label + " " + name + " has no blue/purple/yellow UI corner or focus border")
		_check(btn.get_global_rect().has_point(btn.get_global_rect().get_center()) and
			btn.get_global_rect().position.x >= 0.0 and
			btn.get_global_rect().end.x <= game.size.x + 0.2 and
			btn.get_global_rect().end.y <= game.size.y + 0.2,
			label + " " + name + " hit surface within screen")
	game.call("_go_next")
	next.pressed.emit()  # Even a synthetic disabled-button signal cannot navigate.
	_check(routes.is_empty(), label + " both API and disabled native Next block route")
	for name in CASES:
		var btn: Button = buttons[name]
		var warmup_before: int = int(warmup_signals[0])
		btn.pressed.emit()
		_check(warmup_signals[0] == warmup_before + 1,
			label + " each explicit camera-game choice requests exactly one safe model prewarm")
		_check(bool(btn.button_pressed), label + " " + name + " stays selected")
		_check((game.get("context") as Dictionary).get("activity", "") == name,
			label + " " + name + " stored in navigation context")
		_check(btn.has_focus(), label + " " + name + " keyboard focus follows chosen game")
		_check(btn.get_node_or_null("SelectedFrame") == null and
			(btn.get_node("Artwork") as TextureRect).modulate.r > 1.0,
			label + " " + name + " selected via art tint without any rounded border")
		_check(not next.disabled and next_art.texture.resource_path.ends_with(
			"next student setup if already choose.png"),
			label + " " + name + " enables green Next art")
		_check(preview.texture.resource_path.ends_with(String(CASES[name][1])),
			label + " " + name + " updates exact preview")
		for other_name in CASES:
			if other_name == name:
				continue
			_check(not (buttons[other_name] as Button).button_pressed and
				((buttons[other_name] as Button).get_node("Artwork") as TextureRect).modulate == Color.WHITE,
				label + " one selected game at a time")
		btn.pressed.emit()
		_check(btn.button_pressed and not next.disabled,
			label + " clicking already selected game does not clear selection")
		routes.clear()
		next.pressed.emit()
		_check(routes.size() == 1 and routes[0]["target"] == "play_topic"
			and String((routes[0]["payload"] as Dictionary).get("activity", "")) == name,
			label + " " + name + " routes to topic when teacher choices are absent")
	# Full teacher setup continues directly to calibration with the same payload.
	game.set_context({"game_style": "Verb", "game_mode": "Seconds", "difficulty": "Normal"})
	routes.clear()
	next.pressed.emit()
	_check(routes.size() == 1 and routes[0]["target"] == "calibration" and
		String((routes[0]["payload"] as Dictionary).get("activity", "")) == "Balloon Popping" and
		(routes[0]["payload"] as Dictionary).get("camera_requested") == true and
		(routes[0]["payload"] as Dictionary).get("keyboard_mode") == false,
		label + " complete teacher selection keeps camera calibration route")
	routes.clear()
	back.pressed.emit()
	_check(routes.size() == 1 and routes[0]["target"] == "student_setup",
		label + " Back retains ordinary Student Setup route")
	game.set_context({"guided_tutorial": true})
	routes.clear()
	next.pressed.emit()
	_check(routes.size() == 1 and routes[0]["target"] == "student_setup" and
		(routes[0]["payload"] as Dictionary).get("student_setup_prefill") == false,
		label + " guided Next retains Student Setup route")
	routes.clear()
	back.pressed.emit()
	_check(routes.size() == 1 and routes[0]["target"] == "tutorial_home",
		label + " guided Back retains Tutorial Home route")
	game.queue_free()
	await process_frame
	await process_frame


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("FAIL GameChooser: " + description)
