extends SceneTree

# Catch the Word integration regression at the 1280x720 design viewport.
# Run: Godot --headless --path . --script res://tools/test_catch_visual_layout.gd
# Exercises 5 grammar topics x 2 modes x 3 map selections, then mutates
# score, timer and lives to prove the visible HUD is refreshed dynamically.

const SCENE_PATH := "res://ui/minigames/catch_word.tscn"
const VIEWPORT := Vector2i(1280, 720)
const TOPICS: Array[String] = ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const MODES: Array[String] = ["Seconds", "Lives"]
const MAPS: Array[String] = ["City", "Forest", "Mountain"]
const HUD_PLAQUES: Array[String] = [
	"TitlePlaque", "TimerPlaque",
	"LivesPlaque", "PausePlaque", "ScorePlaque",
]
const STATIC_LIVES_PNGS := {
	1: "res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_1.png",
	2: "res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_2.png",
	3: "res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_3.png",
}

var failures: Array[String] = []
var checks := 0
var scenarios := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var previous_size := root.size
	root.size = VIEWPORT
	if not ResourceLoader.exists(SCENE_PATH):
		_fail("Catch the Word scene is missing: %s" % SCENE_PATH)
		_finish(previous_size)
		return
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_fail("Catch the Word does not load as a PackedScene")
		_finish(previous_size)
		return

	# Match the game's real parent hierarchy: a full-window gameplay Control.
	var existing_children := root.get_child_count()
	var host := Control.new()
	host.name = "CatchLayoutTestHost"
	host.size = Vector2(VIEWPORT)
	root.add_child(host)
	var game := packed.instantiate() as Control
	if game == null:
		_fail("Catch the Word did not instantiate as Control")
		host.queue_free()
		await process_frame
		_finish(previous_size)
		return
	if game.get_script() == null:
		_fail("Catch the Word gameplay script did not load; check upstream GDScript parse errors")
		host.queue_free()
		await process_frame
		_finish(previous_size)
		return
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	game.set_process(false)

	var hud := game.get_node_or_null("HUDLayer/HUD") as Control
	var background := game.get_node_or_null("Background") as TextureRect
	var prompt := game.get_node_or_null("HUDLayer/HUD/PromptLabel") as Label
	var score := game.get_node_or_null("ScoreDrawLayer/ScoreBottomContainer/ScoreNumber") as Label
	var old_score := game.get_node_or_null("HUDLayer/HUD/ScoreLabel") as Label
	var timer := game.get_node_or_null("HUDLayer/HUD/TimeLabel") as Label
	var hearts := game.get_node_or_null("HUDLayer/HUD/HeartsBox") as HBoxContainer
	var pause := game.get_node_or_null("HUDLayer/HUD/PauseButton") as Button

	_check(hud != null and game.get_node_or_null("HUDLayer") is CanvasLayer,
		"HUD remains separately editable inside a CanvasLayer")
	_check(background != null, "Background remains a TextureRect separate from HUD")
	_check(prompt != null and score != null,
		"Wooden-title grammar question and numeric score labels exist")
	for removed_name in ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]:
		_check(game.get_node_or_null("HUDLayer/HUD/" + removed_name) == null,
			"Removed %s is absent from the HUD" % removed_name)
	_check(timer != null and hearts != null and pause != null,
		"Clock, hidden legacy hearts container and pause button remain independent controls")

	if hud != null and background != null and prompt != null \
			and score != null and timer != null and hearts != null and pause != null:
		var previous_map_path := ""
		var selected_map_paths: Dictionary = {}
		for map_name in MAPS:
			for mode in MODES:
				for topic in TOPICS:
					var label := "%s / %s / %s" % [map_name, mode, topic]
					game.call("set_context", {
						"activity": "Catch the Word",
						"topic": topic,
						"game_style": topic,
						"game_mode": mode,
						"difficulty": "Normal",
						"catch_map": map_name,
						"catch_character": "Girl",
						"score": 37,
						"lives": 2,
						"time_remaining": 42.0,
							"round_running": true, # Preserve the elapsed timer in this resume fixture.
					})
					game.set_process(false)
					await process_frame
					scenarios += 1

					# Each context reset must produce the full, synchronized answer
					# wave before we inspect its HUD and selected map.
					_assert_initial_wave(game, label)
					_check(String(game.get("topic")) == topic, label + ": chosen grammar topic")
					_check(String(game.get("game_mode")) == mode, label + ": chosen mode")
					_check(String(game.get("selected_map")) == map_name,
						label + ": requested map was selected")
					var expected_map := "res://Components/Gameplay/Catch the Word/Maps/%sMap.png" % map_name
					var actual_map := background.texture.resource_path if background.texture != null else ""
					_check(actual_map == expected_map, label + ": correct map PNG texture (got " + actual_map + ")")
					selected_map_paths[actual_map] = true
					if not previous_map_path.is_empty() and previous_map_path != actual_map:
						_check(background.texture != null, label + ": switched map without losing texture")
					previous_map_path = actual_map
					_check(background.is_visible_in_tree() and background.texture != null,
						label + ": background is rendered")
					_assert_control_in_view(background, label + " background", true)

					var article := "AN" if topic in ["Adjective", "Adverb"] else "A"
					_check(prompt.text == "WHICH WORD IS %s %s?" % [article, topic.to_upper()],
						label + ": dynamic prompt and correct article")
					_check(prompt.is_visible_in_tree(), label + ": dynamic title question is visible")
					for removed_name in ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]:
						_check(game.get_node_or_null("HUDLayer/HUD/" + removed_name) == null,
							"%s: %s remains absent after context update" % [label, removed_name])
					_check(pause.is_visible_in_tree() and not pause.disabled,
						label + ": pause control is usable")
					_check(old_score == null or not old_score.is_visible_in_tree(),
						label + ": old score label is not duplicated")

					_assert_mode(game, mode, timer, hearts, label)
					_assert_score_changes(game, score, label)
					_assert_all_visible_hud_controls(hud, label)
					_assert_plaque_alignment(game, hud, score, prompt, timer, hearts, pause, mode, label)

		_check(selected_map_paths.size() == MAPS.size(),
			"City, Forest and Mountain load three distinct background images")

	host.queue_free()
	await process_frame
	await process_frame
	_check(root.get_child_count() == existing_children, "Test scene and HUD release all attached controls")
	_finish(previous_size)


func _assert_initial_wave(game: Control, label: String) -> void:
	var tiles: Array = game.get("falling_tiles")
	_check(tiles.size() == 3, "%s: reset starts exactly three answer apples (got %d)" % [label, tiles.size()])
	if tiles.size() != 3:
		return
	var matching := 0
	var used_words: Dictionary = {}
	var first_y := Vector2((tiles[0] as Dictionary)["pos"]).y
	var first_speed := float((tiles[0] as Dictionary)["speed"])
	var layer := game.get_node_or_null("FallingWordLayer")
	for index in range(tiles.size()):
		var tile := tiles[index] as Dictionary
		if bool(tile.get("matching", false)):
			matching += 1
		var word := String(tile.get("word", ""))
		_check(not word.is_empty() and not used_words.has(word), "%s: wave apple %d has unique word %s" % [label, index, word])
		used_words[word] = true
		_check(absf(Vector2(tile["pos"]).y - first_y) < 1.0, "%s: three apples enter at same height" % label)
		_check(absf(float(tile["speed"]) - first_speed) < 0.01, "%s: three apples fall at same speed" % label)
		_check(not bool(tile.get("passed_line", false)), "%s: fresh apple is catchable" % label)
		var node := tile.get("node") as Control
		_check(node != null and is_instance_valid(node) and node.get_parent() == layer,
			"%s: wave apple %d has an attached visible sprite" % [label, index])
		for other_index in range(index):
			var other := tiles[other_index] as Dictionary
			var rect := Rect2(Vector2(tile["pos"]) - game.APPLE_SIZE * 0.5, game.APPLE_SIZE)
			var other_rect := Rect2(Vector2(other["pos"]) - game.APPLE_SIZE * 0.5, game.APPLE_SIZE)
			_check(not rect.intersects(other_rect), "%s: wave apples %d and %d never overlap" % [label, index, other_index])
	_check(matching == 1, "%s: wave offers exactly one correct choice (got %d)" % [label, matching])


func _assert_mode(game: Control, mode: String, timer: Label,
		hearts: HBoxContainer, label: String) -> void:
	var hud := game.get_node("HUDLayer/HUD")
	var seconds_plaque := hud.get_node_or_null("TimerPlaque") as TextureRect
	var lives_plaque := hud.get_node_or_null("LivesPlaque") as TextureRect
	_check(seconds_plaque != null and lives_plaque != null, label + ": separate mode plaques exist")
	if seconds_plaque == null or lives_plaque == null:
		return
	if mode == "Seconds":
		_check(seconds_plaque.is_visible_in_tree() and not lives_plaque.is_visible_in_tree(),
			label + ": seconds plaque only")
		_check(timer.is_visible_in_tree() and not hearts.is_visible_in_tree(),
			label + ": visible timer replaces hidden static lives panel and legacy heart overlays")
		_check(timer.text == "42s", label + ": countdown starts at 42s")
		game.set("time_remaining", 7.0)
		game.call("_refresh_hud")
		_check(timer.text == "7s", label + ": countdown changes visibly to 7s")
		_check(seconds_plaque.is_visible_in_tree(), label + ": timer plaque survives countdown update")
		_check(not lives_plaque.is_visible_in_tree() and not hearts.is_visible_in_tree(),
			label + ": static lives panel and dynamic heart overlays stay hidden after countdown update")
	else:
		_check(lives_plaque.is_visible_in_tree() and not seconds_plaque.is_visible_in_tree(),
			label + ": lives plaque only")
		_check(not timer.is_visible_in_tree() and not hearts.is_visible_in_tree(),
			label + ": static lives PNG replaces hidden timer and legacy heart overlays")
		_assert_static_lives_panel(lives_plaque, hearts, 2, label + " initial lives")
		game.set("lives", 1)
		game.call("_refresh_hud")
		_assert_static_lives_panel(lives_plaque, hearts, 1, label + " depleted lives")
		_check(not timer.is_visible_in_tree() and not seconds_plaque.is_visible_in_tree(),
			label + ": timer remains completely hidden when lives decrease from 2 to 1")


func _assert_static_lives_panel(plaque: TextureRect,
		legacy_hearts: HBoxContainer, remaining: int, label: String) -> void:
	var expected: String = STATIC_LIVES_PNGS[remaining]
	var actual := plaque.texture.resource_path if plaque.texture != null else ""
	_check(plaque.is_visible_in_tree() and actual == expected,
		"%s: exact %d-lives static PNG is displayed (got %s)" % [label, remaining, actual])
	_check(ResourceLoader.exists(expected),
		"%s: static %d-lives texture has been imported" % [label, remaining])
	_check(not legacy_hearts.is_visible_in_tree(),
		label + ": old HeartRed/HeartBlack overlay container is hidden")
	for icon in legacy_hearts.get_children():
		if icon is TextureRect:
			_check(not (icon as TextureRect).is_visible_in_tree(),
				"%s: legacy heart icon %s is not painted over static PNG" % [label, icon.name])
	_assert_control_in_view(plaque, label + " static lives plaque", false)


func _assert_score_changes(game: Control, score: Label, label: String) -> void:
	_check(score.is_visible_in_tree() and score.text == "37",
		label + ": starting score is visible and exactly 37")
	for value in [0, 128, 10000]:
		game.set("score", value)
		game.call("_refresh_hud")
		_check(score.is_visible_in_tree() and score.text == str(value),
			"%s: live score changes to %d (actual %s)" % [label, value, score.text])


func _assert_all_visible_hud_controls(node: Node, label: String) -> void:
	if node is Control:
		var control := node as Control
		if control.is_visible_in_tree() and control.size.x > 0.0 and control.size.y > 0.0:
			_assert_control_in_view(control, label + " " + str(control.get_path()), false)
	for child in node.get_children():
		_assert_all_visible_hud_controls(child, label)


func _assert_control_in_view(control: Control, label: String, require_cover: bool) -> void:
	var rect := control.get_global_rect()
	var screen := Rect2(Vector2.ZERO, Vector2(VIEWPORT))
	var within := rect.size.x >= 1.0 and rect.size.y >= 1.0 \
		and screen.encloses(rect.grow(-0.5))
	if require_cover:
		within = within and rect.get_area() >= screen.get_area() * 0.95
	_check(within, "%s fits 1280x720: %s" % [label, rect])


func _assert_plaque_alignment(game: Control, hud: Control, score: Label, prompt: Label,
		timer: Label, hearts: HBoxContainer, pause: Button,
		mode: String, label: String) -> void:
	var title_plaque := hud.get_node_or_null("TitlePlaque") as TextureRect
	var score_plaque := game.get_node_or_null("ScoreDrawLayer/ScorePlaque") as TextureRect
	var pause_plaque := hud.get_node_or_null("PausePlaque") as TextureRect
	var timer_plaque := hud.get_node_or_null("TimerPlaque") as TextureRect
	var lives_plaque := hud.get_node_or_null("LivesPlaque") as TextureRect
	for plaque_name in HUD_PLAQUES:
		var plaque := game.get_node_or_null("ScoreDrawLayer/ScorePlaque") as TextureRect if plaque_name == "ScorePlaque" else hud.get_node_or_null(plaque_name) as TextureRect
		_check(plaque != null and plaque.texture != null,
			label + ": " + plaque_name + " has bitmap/vector background")
	if title_plaque != null:
		_check(title_plaque.is_visible_in_tree(), label + ": title plaque is visible")
		_assert_overlap(prompt, title_plaque, label + ": grammar question on wooden title")
	if score_plaque != null:
		_check(score_plaque.is_visible_in_tree(), label + ": score plaque is visible")
		_assert_overlap(score, score_plaque, label + ": numeric score on scoreboard")
	if pause_plaque != null:
		_check(pause_plaque.is_visible_in_tree(), label + ": pause plaque is visible")
		_assert_overlap(pause, pause_plaque, label + ": pause hit target over badge")
	if timer_plaque != null and lives_plaque != null:
		if mode == "Seconds":
			_assert_overlap(timer, timer_plaque, label + ": countdown over blue badge")
		else:
			_check(lives_plaque.is_visible_in_tree() and not hearts.is_visible_in_tree(),
				label + ": static heart panel renders alone without overlaid dynamic hearts")
			_assert_control_in_view(lives_plaque, label + " static heart panel", false)
	if title_plaque != null:
		_check(title_plaque.get_global_rect().encloses(prompt.get_global_rect().grow(-1.0)),
			label + ": entire grammar question fits the wooden title")


func _assert_overlap(foreground: Control, backdrop: Control, label: String) -> void:
	if not foreground.is_visible_in_tree() or not backdrop.is_visible_in_tree():
		_fail(label + " is not visible")
		return
	var area := foreground.get_global_rect().get_area()
	var intersect := foreground.get_global_rect().intersection(backdrop.get_global_rect()).get_area()
	_check(area > 0.0 and intersect >= area * 0.35, label + ": overlay properly aligned")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)


func _fail(description: String) -> void:
	failures.append(description)


func _finish(previous_size: Vector2i) -> void:
	root.size = previous_size
	if failures.is_empty():
		print("PASS  Catch visual layout: %d checks across %d topic/mode/map scenarios at 1280x720" % [checks, scenarios])
		quit(0)
	else:
		for failure in failures:
			push_error("CATCH VISUAL QA: " + failure)
		print("FAIL  Catch visual layout: %d failures across %d checks, %d scenarios" % [failures.size(), checks, scenarios])
		quit(1)
