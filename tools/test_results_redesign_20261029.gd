extends SceneTree

# QA ONLY: zero-camera, zero-database regression for the Results redesign.
# Godot 4.7.2:
# Godot_v4.7.2-stable_win64_console.exe --headless --path . \
#   --script res://tools/test_results_redesign_20261029.gd
# Intentionally exercises the real Results scene, its UI script and buttons.
# No screenshots or new assets are written into the project.

const RESULTS := "res://ui/secondary/results/results.tscn"
const MAIN_SCRIPT := "res://ui/main_menu/main_menu.gd"
const LOW_SCORE_CLIP := "res://assets/audio/catch_voice/Better Luck.mp3"
const GAMES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const MODES := ["Seconds", "Lives"]
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const BANNER_NODES := {
	"Catch the Word": "GameOverBannerCatch",
	"Balloon Popping": "GameOverBannerBalloon",
	"Human Plane": "GameOverBannerPlane",
}
const BANNER_TEXTURES := {
	"Catch the Word": "game_over_catch_the_word.png",
	"Balloon Popping": "game_over_balloon_popping.png",
	"Human Plane": "game_over_human_plane.png",
}
const FIELD_EXPECTATIONS := {
	"%StudentIdValue": "QA-RSLT-42",
	"%StudentNameValue": "QA Student",
	"%GradeValue": "Grade 4 - Orion",
	"%GameStyleValue": "Adjective",
	"%DifficultyValue": "Normal",
}
const DISPLAY_NODES := [
	"%StudentCard", "%StudentIdRow", "%StudentNameRow", "%GradeRow",
	"%GameCard", "%GameStyleRow", "%GameModeRow", "%DifficultyRow",
	"%ScoreCard", "%ScoreValue",
]

var checks := 0
var failures: Array[String] = []
var cases := 0
var scene_resource: PackedScene


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	scene_resource = load(RESULTS) as PackedScene
	_check(scene_resource != null, "Results scene parses as PackedScene")
	_check(ResourceLoader.exists(LOW_SCORE_CLIP), "approved Catch low-score voice asset is imported")
	_check(FileAccess.file_exists(MAIN_SCRIPT), "main route script exists")
	_check_main_contract()
	if scene_resource != null:
		for size in SIZES:
			for game in GAMES:
				for mode in MODES:
					await _exercise(size, game, mode)
		await _exercise_aliases()
		await _exercise_missing_context()
	await process_frame
	print("RESULTS REDESIGN QA: %s | cases=%d checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", cases, checks, failures.size()])
	for failure in failures:
		printerr("RESULTS REDESIGN FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _exercise(size: Vector2i, game: String, mode: String) -> void:
	cases += 1
	var tag := "%s / %s / %s" % [game, mode, size]
	var scene := scene_resource.instantiate() as Control
	_check(scene != null, tag + ": Results instantiates as Control")
	if scene == null:
		return
	var viewport := SubViewport.new()
	viewport.name = "ResultsQAVP"
	viewport.size = size
	viewport.disable_3d = true
	root.add_child(viewport)
	var payload := _base_context(game, mode)
	# MainMenu calls set_context after add_child. Also cover pre-ready data.
	scene.call("set_context", payload)
	viewport.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	_check(scene.size.distance_to(Vector2(size)) < 2.0,
		tag + ": root scene fills viewport")
	for path in FIELD_EXPECTATIONS:
		_check_label(scene, path, FIELD_EXPECTATIONS[path], tag)
	_check_label(scene, "%GameModeValue", mode, tag)
	_check_label(scene, "%ScoreValue", "780", tag)
	_check(scene.get_node_or_null("%GameOverFallback") == null
		and scene.get_node_or_null("%ActivityValue") == null,
		tag + ": no redundant game-over heading labels")
	_check(scene.get_node_or_null("ResultsStage/SaveStatusBoard") == null
		and scene.get_node_or_null("%SaveStatus") == null,
		tag + ": no redundant save-status UI")
	for path in DISPLAY_NODES:
		var control := scene.get_node_or_null(path) as Control
		_check(control != null, tag + ": UI field exists " + path)
		if control != null:
			_check(control.is_visible_in_tree(), tag + ": populated field shown " + path)
			_check(_inside_viewport(control, size), tag + ": field within viewport " + path)
	for button_path in ["%RetryButton", "%MainButton"]:
		var button := scene.get_node_or_null(button_path) as BaseButton
		_check(button != null, tag + ": " + button_path + " exists")
		if button != null:
			_check(button.visible and not button.disabled, tag + ": " + button_path + " enabled")
			_check(_inside_viewport(button, size), tag + ": " + button_path + " on screen")
	_check_layout(scene, size, tag)
	_check_art(scene, size, tag)
	_check_game_banner(scene, game, tag)
	await _check_navigation(scene, payload, tag)
	scene.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(scene), tag + ": Results instance freed")
	viewport.queue_free()
	await process_frame


func _base_context(game: String, mode: String) -> Dictionary:
	return {
		"student_id": "QA-RSLT-42", "student_name": "QA Student",
		"grade_section": "Grade 4 - Orion",
		"topic": "Adjective", "game_style": "Adjective",
		"game_mode": mode, "difficulty": "Normal", "activity": game,
		"score": 780, "round_completed": true, "completion_reason": "game_over",
		"score_saved": true, "database_connected": true,
		"database_saving": false, "entry_source": "play",
		"guided_tutorial": false, "qa_nested": {"source": "results_qa"},
	}


func _check_navigation(scene: Control, payload: Dictionary, tag: String) -> void:
	var events: Array[Dictionary] = []
	scene.connect("requested", func(target: String, context: Dictionary) -> void:
		events.append({"target": target, "context": context})
	)
	var retry := scene.get_node_or_null("%RetryButton") as BaseButton
	var main := scene.get_node_or_null("%MainButton") as BaseButton
	if retry != null:
		retry.pressed.emit()
		_check(events.size() == 1, tag + ": Retry emits exactly one navigation")
		if events.size() >= 1:
			_check(String(events[0]["target"]) == "student_setup",
				tag + ": Retry routes to student setup")
			_check(events[0]["context"] == payload, tag + ": Retry preserves context")
	if main != null:
		main.pressed.emit()
		_check(events.size() == 2, tag + ": Main emits exactly one navigation")
		if events.size() >= 2:
			_check(String(events[1]["target"]) == "main", tag + ": Main routes home")
			_check(events[1]["context"] == payload, tag + ": Main preserves context")
	# The outgoing payload must be detached from mutable caller-owned data.
	if events.size() >= 1:
		var emitted: Dictionary = events[0]["context"]
		var nested: Dictionary = emitted.get("qa_nested", {})
		nested["source"] = "mutated"
		_check(payload["qa_nested"]["source"] == "results_qa",
			tag + ": emitted payload is deeply copied")


func _check_layout(scene: Control, size: Vector2i, tag: String) -> void:
	var score := scene.get_node_or_null("%ScoreValue") as Control
	var retry := scene.get_node_or_null("%RetryButton") as Control
	var main := scene.get_node_or_null("%MainButton") as Control
	if score != null:
		var center_x := score.get_global_rect().get_center().x
		_check(absf(center_x - float(size.x) * 0.5) < float(size.x) * 0.13,
			tag + ": score is centered on responsive canvas")
	if retry != null and main != null:
		_check(retry.get_global_rect().end.x < main.get_global_rect().position.x,
			tag + ": Retry/Main controls remain horizontally distinct")
		_check(absf(retry.get_global_rect().get_center().y -
			main.get_global_rect().get_center().y) < 40.0,
			tag + ": navigation buttons stay aligned")


func _check_art(scene: Control, size: Vector2i, tag: String) -> void:
	var pieces: Array[Control] = []
	_collect_sprite_controls(scene, pieces)
	var themed_textures := {}
	var roles := {"background": false, "title": false, "score": false,
		"retry": false, "main": false}
	for control in pieces:
		var texture: Texture2D = null
		if control is TextureRect:
			texture = (control as TextureRect).texture
		elif control is TextureButton:
			texture = (control as TextureButton).texture_normal
		elif control is Button:
			texture = (control as Button).icon
		if texture == null:
			continue
		var path := String(texture.resource_path).to_lower()
		if path.contains("results/redesign") or path.contains("credits/redesign"):
			themed_textures[path] = true
		var name := String(control.name).to_lower().replace("_", "")
		if name.contains("background") or name.contains("backdrop"):
			roles["background"] = true
		if name.contains("gameover") or name.contains("title") or name.contains("header"):
			roles["title"] = true
		if name.contains("score") or name.contains("board"):
			roles["score"] = true
		if name.contains("retry"):
			roles["retry"] = true
		if name.contains("main") or name.contains("home"):
			roles["main"] = true
		var is_fullscreen := control.anchor_left == 0.0 and control.anchor_top == 0.0 \
			and control.anchor_right == 1.0 and control.anchor_bottom == 1.0 \
			and control.offset_left == 0.0 and control.offset_top == 0.0 \
			and control.offset_right == 0.0 and control.offset_bottom == 0.0
		if control.is_visible_in_tree() and not is_fullscreen:
			_check(_inside_viewport(control, size),
				tag + ": sprite stays in viewport " + String(control.get_path()))
	_check(themed_textures.size() >= 4,
		tag + ": four or more distinct Results/selected classroom sprite textures loaded")
	for role in roles:
		_check(roles[role], tag + ": semantic " + role + " sprite is independently named")


func _collect_sprite_controls(node: Node, pieces: Array[Control]) -> void:
	if node is TextureRect or node is TextureButton or node is Button:
		pieces.append(node as Control)
	for child in node.get_children():
		_collect_sprite_controls(child, pieces)


func _check_game_banner(scene: Control, game: String, tag: String) -> void:
	for activity in GAMES:
		var banner := scene.find_child(BANNER_NODES[activity], true, false) as TextureRect
		_check(banner != null, tag + ": named " + activity + " banner exists")
		if banner != null:
			_check(banner.is_visible_in_tree() == (activity == game),
				tag + ": only selected game banner is visible: " + activity)
			_check(banner.texture != null and
				String(banner.texture.resource_path).ends_with(BANNER_TEXTURES[activity]),
				tag + ": " + activity + " uses supplied source banner")
	_check(scene.get_node_or_null("%GameOverFallback") == null,
		tag + ": generic Game Over fallback was removed")
	_check_art_path(scene, "%ScoreCard", "panel_final_score.png", tag)
	_check_art_path(scene, "%StudentCard", "panel_student_tall.png", tag)
	_check_art_path(scene, "%GameCard", "panel_round.png", tag)
	var round_card := scene.get_node_or_null("%GameCard") as TextureRect
	_check(round_card != null and round_card.get_node_or_null("RoundHeader") == null,
		tag + ": exact ROUND art replaces obsolete custom green header")
	if round_card != null:
		for row_name in ["GameStyleRow", "GameModeRow", "DifficultyRow"]:
			var row := round_card.get_node_or_null(row_name) as Control
			_check(row != null and not (row is Panel),
				tag + ": " + row_name + " overlays supplied printed row without duplicate panel")
	var background := scene.find_child("ClassroomBackground", true, false) as TextureRect
	_check(background != null and background.texture != null and
		String(background.texture.resource_path).ends_with("Credits/Redesign/background1.png"),
		tag + ": Results reuses requested Credits classroom background")
	var retry_art := scene.find_child("RetryArtwork", true, false) as TextureRect
	_check(retry_art != null and retry_art.texture != null and
		String(retry_art.texture.resource_path).ends_with("button_retry.png"),
		tag + ": Retry button uses independently editable supplied art")
	var main_art := scene.find_child("MainArtwork", true, false) as TextureRect
	_check(main_art != null and main_art.texture != null and
		String(main_art.texture.resource_path).ends_with("button_main_menu.png"),
		tag + ": Main Menu button uses independently editable supplied art")


func _check_art_path(scene: Control, node_path: String, filename: String, tag: String) -> void:
	var sprite := scene.get_node_or_null(node_path) as TextureRect
	_check(sprite != null and sprite.texture != null and
		String(sprite.texture.resource_path).ends_with(filename),
		tag + ": " + node_path + " uses supplied " + filename)


func _inside_viewport(control: Control, size: Vector2i) -> bool:
	var rect := control.get_global_rect()
	return rect.size.x > 0.0 and rect.size.y > 0.0 \
		and rect.position.x >= -2.0 and rect.position.y >= -2.0 \
		and rect.end.x <= float(size.x) + 2.0 \
		and rect.end.y <= float(size.y) + 2.0


func _exercise_aliases() -> void:
	var scene := scene_resource.instantiate() as Control
	root.add_child(scene)
	var aliases := {"id": "ALT-ID", "name": "Alias Student", "section": "Grade 2",
		"style": "Verb", "mode": "Lives", "points": 44}
	scene.call("set_context", aliases)
	for path in {"%StudentIdValue": "ALT-ID", "%StudentNameValue": "Alias Student",
			"%GradeValue": "Grade 2", "%GameStyleValue": "Verb",
			"%GameModeValue": "Lives", "%ScoreValue": "44"}:
		_check_label(scene, path, {
			"%StudentIdValue": "ALT-ID", "%StudentNameValue": "Alias Student",
			"%GradeValue": "Grade 2", "%GameStyleValue": "Verb",
			"%GameModeValue": "Lives", "%ScoreValue": "44"}[path], "alias context")
	scene.queue_free()
	await process_frame


func _exercise_missing_context() -> void:
	var scene := scene_resource.instantiate() as Control
	root.add_child(scene)
	scene.call("set_context", {})
	await process_frame
	for path in ["%ScoreCard", "%StudentCard", "%GameCard"]:
		var control := scene.get_node_or_null(path) as Control
		_check(control != null and not control.visible,
			"empty context hides unpopulated " + path)
	_check(scene.get_node_or_null("%SaveStatus") == null, "empty context has no redundant save-status text")
	scene.queue_free()
	await process_frame
	# Isolated real playback cases. No audio/persistence services are started.
	for game in GAMES:
		for mode in MODES:
			await _exercise_low_score_voice(game, mode)


func _exercise_low_score_voice(game: String, mode: String) -> void:
	for score in [200, 499, 500, 800]:
		var tag := "voice %s/%s score=%d" % [game, mode, score]
		var payload := _base_context(game, mode)
		payload["score"] = score
		payload["score_saved"] = false
		var expected: bool = game == "Catch the Word" and int(score) < 500
		var scene := scene_resource.instantiate() as Control
		root.add_child(scene)
		scene.call("set_context", payload)
		await process_frame
		var player := scene.get_node_or_null("LowScoreVoicePlayer") as AudioStreamPlayer
		_check((player != null) == expected, tag + ": voice gated by completed Catch < 500")
		if player != null:
			_check(player.stream != null and String(player.stream.resource_path) == LOW_SCORE_CLIP,
				tag + ": approved Better Luck MP3 played")
			_check(player.playing, tag + ": voice started on Results")
			scene.call("set_context", payload.duplicate(true))
			_check(_count_named_voice(scene) == 1, tag + ": duplicate refresh does not replay")
			var retry := scene.get_node_or_null("%RetryButton") as BaseButton
			if retry != null:
				retry.pressed.emit()
				_check(not player.playing, tag + ": Retry stops cue")
		if game == "Catch the Word" and score == 200:
			payload["round_completed"] = false
			_check(not bool(scene.call("should_play_catch_low_score", payload)),
				tag + ": abandoned Catch round never qualifies for encouragement")
			payload["round_completed"] = true
		scene.queue_free()
		await process_frame


func _count_named_voice(node: Node) -> int:
	var total := 1 if node is AudioStreamPlayer and node.name == "LowScoreVoicePlayer" else 0
	for child in node.get_children():
		total += _count_named_voice(child)
	return total


func _check_main_contract() -> void:
	var source := FileAccess.get_file_as_string(MAIN_SCRIPT)
	_check(source.contains('"results": "res://ui/secondary/results/results.tscn"'),
		"MainMenu keeps actual Results scene route")
	_check(source.contains('current_route == "results" and route == "student_setup"'),
		"MainMenu Retry treats Results to student setup as fresh round")
	_check(source.contains('route == "results" and current_route == "gameplay"'),
		"MainMenu only persists completed gameplay, not pause Results")
	_check(source.contains('not bool(session_state.get("guided_tutorial", false))'),
		"MainMenu excludes guided tutorial from completed-round save")
	_check(source.contains('database_save_ticket += 1'),
		"MainMenu invalidates late save tickets")


func _check_label(scene: Control, path: String, expected: String, tag: String) -> void:
	var label := scene.get_node_or_null(path) as Label
	_check(label != null, tag + ": missing " + path)
	if label != null:
		_check(label.text == expected, "%s: %s expected '%s', got '%s'" %
			[tag, path, expected, label.text])


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)
