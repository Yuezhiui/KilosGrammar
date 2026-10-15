extends SceneTree

# Run: godot --headless --path . --script res://tools/test_catch_spawn_hud_safety.gd
const SCENE := preload("res://ui/minigames/catch_word.tscn")
const MODES := ["Seconds", "Lives"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const CHARACTERS := ["Boy", "Girl", "Grandma", "Grandpa"]
const HUD_NAMES := ["TitlePlaque", "TimerPlaque", "LivesPlaque", "PausePlaque"]
const MARGIN := 12.0
const WAVE_SIZE := 3
var failures: Array[String] = []
var checked := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for mode in MODES:
		for difficulty in DIFFICULTIES:
			for character in CHARACTERS:
				await _case(mode, difficulty, character)
	if checked != 24:
		failures.append("Only %d of 24 gameplay configurations executed" % checked)
	if failures.is_empty():
		print("PASS: top-edge immediate-fall three-apple waves, HUD/score safety, collisions, pause, and restart in all 24 mode/difficulty/character configurations")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _case(mode: String, difficulty: String, character: String) -> void:
	var host := Control.new()
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var game := SCENE.instantiate() as Control
	if game == null or game.get_script() == null:
		failures.append("%s/%s/%s: Catch Word scene or gameplay script cannot load" % [mode, difficulty, character])
		host.queue_free()
		await process_frame
		return
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	game.set_process(false)
	var context := {"topic": "Noun", "difficulty": difficulty, "game_mode": mode, "catch_character": character}
	game.set_context(context)
	await process_frame
	var case_name := "%s/%s/%s" % [mode, difficulty, character]
	checked += 1
	for deleted_hud in ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]:
		if game.get_node_or_null("HUDLayer/HUD/" + deleted_hud) != null:
			failures.append("%s: deleted HUD node still exists: %s" % [case_name, deleted_hud])
	if game.selected_character != character or game.game_mode != mode:
		failures.append("%s: requested character/mode was not selected" % case_name)
	if game.body_sprite.texture == null or game.basket_sprite.texture == null:
		failures.append("%s: character texture missing" % case_name)
	_check_wave(game, case_name + " initial")
	game._pause()
	var paused_tiles: Array = game.falling_tiles.duplicate(true)
	game._process(0.2)
	if game.falling_tiles != paused_tiles:
		failures.append("%s: tiles moved while paused" % case_name)
	game._resume()
	for iteration in range(12):
		# Restart begins a fresh complete wave; the earlier test spawned a
		# single apple repeatedly, which no longer represents live gameplay.
		game.set_context(context)
		game.set_process(false)
		await process_frame
		_check_wave(game, "%s reset %d" % [case_name, iteration])
		if game.falling_tiles.size() > WAVE_SIZE:
			failures.append("%s: wave exceeded three simultaneous apples" % case_name)
		var tiles_layer := game.get_node_or_null("FallingWordLayer")
		if tiles_layer != null and tiles_layer.get_child_count() != game.falling_tiles.size():
			failures.append("%s: orphan or missing word sprites after reset %d" % [case_name, iteration])
	# Opposite-correctness apples must never intersect in the active playfield.
	for i in range(game.falling_tiles.size()):
		for j in range(i):
			var a: Dictionary = game.falling_tiles[i]
			var b: Dictionary = game.falling_tiles[j]
			if bool(a["matching"]) != bool(b["matching"]):
				var ar := Rect2(Vector2(a["pos"]) - game.APPLE_SIZE * 0.5, game.APPLE_SIZE)
				var br := Rect2(Vector2(b["pos"]) - game.APPLE_SIZE * 0.5, game.APPLE_SIZE)
				if ar.intersects(br):
					failures.append("%s: opposite correctness apples overlap" % case_name)
	game.collected_words.append("apple")
	game._refresh_collected_words()
	game.set_context(context)
	await process_frame
	if not game.collected_words.is_empty() or game.collected_word_layer.get_child_count() != 0:
		failures.append("%s: restart retained collected words or basket labels" % case_name)
	_check_tiles(game, "%s restart" % case_name)
	_check_wave(game, "%s restart" % case_name)
	var tiles_layer := game.get_node_or_null("FallingWordLayer")
	if tiles_layer != null and tiles_layer.get_child_count() != game.falling_tiles.size():
		failures.append("%s: orphan tile nodes after restart" % case_name)
	await _check_wave_resolution(game, case_name)
	host.queue_free()
	await process_frame

func _check_wave_resolution(game: Control, case_name: String) -> void:
	# All three answers now begin fully above the viewport and fall
	# immediately. Their initial offscreen state must not overlap the HUD.
	var initial_y := Vector2(game.falling_tiles[0]["pos"]).y
	var initial_xs: Array[float] = []
	for tile in game.falling_tiles:
		initial_xs.append(Vector2(tile["pos"]).x)
	if game.wave_phase != "falling":
		failures.append(case_name + ": fresh wave did not start falling immediately")
		return
	var first_delta := 0.12
	game._update_tiles(first_delta)
	if game.falling_tiles.size() != WAVE_SIZE or game.wave_phase != "falling":
		failures.append(case_name + ": immediate descent unexpectedly removed a wave apple")
		return
	var expected_y: float = initial_y + float(game.falling_tiles[0]["speed"]) * first_delta
	for index in range(WAVE_SIZE):
		var tile: Dictionary = game.falling_tiles[index]
		var position: Vector2 = tile["pos"]
		if absf(position.y - expected_y) > 0.05 or position.y <= initial_y:
			failures.append("%s: apple %d did not immediately descend in sync (got %.2f expected %.2f)" %
				[case_name, index, position.y, expected_y])
		if absf(position.x - initial_xs[index]) > 0.01:
			failures.append("%s: apple %d changed lanes while falling" % [case_name, index])
	# Advance beyond the intentionally overlaid top banner before checking
	# whether the exposed gameplay area is clear of HUD blockers.
	game._update_tiles(2.8)
	if game.falling_tiles.size() != WAVE_SIZE or game.wave_phase != "falling":
		failures.append(case_name + ": all three apples must remain in flight across the upper playfield")
		return
	_check_tiles(game, case_name + " active playfield")
	# Place the correct apple just above the real basket collision region,
	# then advance physics enough for exactly one apple to be selected.
	_catch_chosen_lane(game, true, case_name + " correct")
	if game.wave_phase != "clearing" or game.attempts != 1 or game.correct_count != 1 or game.score <= 0:
		failures.append(case_name + ": correct choice was not resolved exactly once")
	if game.falling_tiles.size() != WAVE_SIZE - 1:
		failures.append(case_name + ": choosing an apple did not leave exactly two clearing apples")
	for tile in game.falling_tiles:
		if not bool(tile.get("passed_line", false)):
			failures.append(case_name + ": unchosen apple stayed collectible after wave resolved")
	var attempts_after_correct: int = game.attempts
	game._update_tiles(0.05)
	if game.attempts != attempts_after_correct:
		failures.append(case_name + ": clearing apples caused another catch")
	var previous_wave_index: int = game.wave_index
	game._update_spawning(game.WAVE_CLEAR_SECONDS + 0.05)
	await process_frame
	_check_wave(game, case_name + " after clearing")
	if game.wave_phase != "falling" or game.wave_index != previous_wave_index + 1:
		failures.append(case_name + ": no fresh complete wave appeared after clearing")
	if game.falling_word_layer.get_child_count() != WAVE_SIZE:
		failures.append(case_name + ": clearing leaked sprites into the next wave")
	# A wrong choice costs one life only in Lives mode; no double collision.
	var score_before: int = game.score
	var lives_before: int = game.lives
	var attempts_before: int = game.attempts
	_catch_chosen_lane(game, false, case_name + " wrong")
	if game.wave_phase != "clearing" or game.attempts != attempts_before + 1 or game.score != score_before:
		failures.append(case_name + ": wrong choice did not resolve precisely once without score gain")
	var expected_lives := lives_before - 1 if game.is_lives_mode else lives_before
	if game.lives != expected_lives:
		failures.append(case_name + ": wrong choice changed lives incorrectly")

func _catch_chosen_lane(game: Control, matching: bool, case_name: String) -> void:
	if game.wave_phase != "falling":
		failures.append(case_name + ": wave is not falling before selection")
		return
	var target_index := -1
	for index in range(game.falling_tiles.size()):
		if bool(game.falling_tiles[index]["matching"]) == matching:
			target_index = index
			break
	if target_index < 0:
		failures.append(case_name + ": requested correct/wrong lane does not exist")
		return
	game.basket_x = Vector2(game.falling_tiles[target_index]["pos"]).x
	var center_y: float = game._basket_rect().get_center().y
	for index in range(game.falling_tiles.size()):
		var tile: Dictionary = game.falling_tiles[index]
		var position: Vector2 = tile["pos"]
		position.y = center_y - game.APPLE_SIZE.y * 0.5 - 10.0
		tile["pos"] = position
		game.falling_tiles[index] = tile
		game._sync_tile_node(tile)
	game._update_tiles(0.15)

func _check_wave(game: Control, case_name: String) -> void:
	var tiles: Array = game.falling_tiles
	if tiles.size() != WAVE_SIZE:
		failures.append("%s: expected exactly three apple choices, got %d" % [case_name, tiles.size()])
		return
	var matches := 0
	var lanes: Dictionary = {}
	var words: Dictionary = {}
	var start_y := Vector2((tiles[0] as Dictionary)["pos"]).y
	var common_speed := float((tiles[0] as Dictionary)["speed"])
	var centers: Array[float] = []
	if game.wave_phase != "falling":
		failures.append("%s: freshly spawned wave must fall immediately (phase %s)" %
			[case_name, String(game.wave_phase)])
	for index in range(WAVE_SIZE):
		var tile := tiles[index] as Dictionary
		var position: Vector2 = tile["pos"]
		centers.append(position.x)
		if bool(tile.get("matching", false)):
			matches += 1
		var lane := int(tile.get("lane", -1))
		if lane < 0 or lane > 2 or lanes.has(lane):
			failures.append("%s: apple %d has duplicate/invalid lane %d" % [case_name, index, lane])
		lanes[lane] = true
		var word := String(tile.get("word", ""))
		if word.is_empty() or words.has(word):
			failures.append("%s: apple %d has duplicate/empty word %s" % [case_name, index, word])
		words[word] = true
		if absf(Vector2(tile["pos"]).y - start_y) > 1.0 or absf(float(tile["speed"]) - common_speed) > 0.01:
			failures.append("%s: wave apples lack synchronized height/fall speed" % case_name)
		var sprite_rect := Rect2(position - game.APPLE_SIZE * 0.5, game.APPLE_SIZE)
		if sprite_rect.end.y > 0.0:
			failures.append("%s: apple %d must begin completely above the viewport (top/bottom %.2f/%.2f)" %
				[case_name, index, sprite_rect.position.y, sprite_rect.end.y])
		if bool(tile.get("passed_line", false)):
			failures.append("%s: newly spawned apple already passed catch line" % case_name)
		var node := tile.get("node") as Control
		if node == null or not is_instance_valid(node) or node.get_parent() != game.get_node("FallingWordLayer"):
			failures.append("%s: apple %d lacks live sprite node" % [case_name, index])
	if matches != 1:
		failures.append("%s: expected one correct plus two incorrect apples, got %d correct" % [case_name, matches])
	# Three apples are ordered left-to-right and shifted into the playfield;
	# gaps are equal and wide enough that the basket cannot catch two at once.
	var gap_a := centers[1] - centers[0]
	var gap_b := centers[2] - centers[1]
	if gap_a <= 0.0 or gap_b <= 0.0 or absf(gap_a - gap_b) > 2.0:
		failures.append("%s: three lanes are not horizontally aligned/equally spaced" % case_name)
	if gap_a < game.APPLE_SIZE.x + game._basket_rect().size.x + game.APPLE_SPACING_MARGIN:
		failures.append("%s: adjacent apples can both intersect the basket" % case_name)
	if centers[0] < game._game_rect().position.x + game.APPLE_SIZE.x * 0.5 + 90.0:
		failures.append("%s: apple formation reverted to leftmost edge" % case_name)
	_check_tiles(game, case_name)

func _check_tiles(game: Control, case_name: String) -> void:
	var hud := game.get_node("HUDLayer/HUD") as Control
	var blockers: Array[Rect2] = []
	for name in HUD_NAMES:
		var control := hud.get_node_or_null(name) as Control
		if control != null and control.visible:
			blockers.append(Rect2(control.global_position - Vector2.ONE * MARGIN, control.size + Vector2.ONE * MARGIN * 2.0))
	for i in range(game.falling_tiles.size()):
		var tile: Dictionary = game.falling_tiles[i]
		var position: Vector2 = tile["pos"]
		var sprite_rect := Rect2(position - game.APPLE_SIZE * 0.5, game.APPLE_SIZE)
		# The wooden score plaque overlays the bottom-right catch zone.
		# Falling apples must not be placed in a lane that enters behind it.
		var score := hud.get_node("ScorePlaque") as TextureRect
		var rightmost_safe_x: float = score.position.x - game.APPLE_SIZE.x * 0.5 - game.APPLE_SPACING_MARGIN
		if position.x > rightmost_safe_x + 0.5:
			failures.append("%s: apple %d will pass behind scoreboard at %s" % [case_name, i, position])
		# The top badges' safety margins can protrude above y=0. Apples
		# completely above the viewport cannot cover visible HUD artwork.
		if sprite_rect.end.y > 0.0:
			for blocker in blockers:
				if sprite_rect.intersects(blocker):
					failures.append("%s: visible apple %d overlaps HUD at %s" % [case_name, i, position])
		for j in range(i):
			var other: Dictionary = game.falling_tiles[j]
			var other_rect := Rect2(Vector2(other["pos"]) - game.APPLE_SIZE * 0.5, game.APPLE_SIZE)
			if sprite_rect.intersects(other_rect):
				failures.append("%s: apples %d and %d overlap" % [case_name, i, j])
