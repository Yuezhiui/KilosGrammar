extends SceneTree

# Regression for the editor-authored Catch the Word and Balloon Popping art
# scenes. This deliberately tests the serialized TSCN structure in addition to
# runtime behavior so future refactors do not silently return to script-only art.

const CATCH_SCENE := "res://ui/minigames/catch_the_word/catch_word.tscn"
const BALLOON_SCENE := "res://ui/minigames/balloon_popping/balloon_popping.tscn"
const CAUGHT_HALF_APPLE := "res://Components/Gameplay/Catch the Word/Items/APPLE HALF.png"

const CATCH_ASSETS: Array[String] = [
	"res://Components/Gameplay/Catch the Word/Maps/CityMap.png",
	"res://Components/Gameplay/Catch the Word/Maps/ForestMap.png",
	"res://Components/Gameplay/Catch the Word/Maps/MountainMap.png",
	"res://Components/Gameplay/Catch the Word/Characters/BEAR BODY.png",
	"res://Components/Gameplay/Catch the Word/Characters/BEAR BASKET.png",
	"res://Components/Gameplay/Catch the Word/Characters/CAT BODY.png",
	"res://Components/Gameplay/Catch the Word/Characters/CAT BASKET.png",
	"res://Components/Gameplay/Catch the Word/Characters/DOG BODY.png",
	"res://Components/Gameplay/Catch the Word/Characters/DOG BASKET.png",
	"res://Components/Gameplay/Catch the Word/Characters/LION BODY.png",
	"res://Components/Gameplay/Catch the Word/Characters/LION BASKET.png",
	"res://Components/Gameplay/Catch the Word/Characters/PANDA BODY.png",
	"res://Components/Gameplay/Catch the Word/Characters/PANDA BASKET.png",
]

const BALLOON_ASSETS: Array[String] = [
	"res://Components/Gameplay/Balloon Popping/Background/0826b13c-250f-42e1-9398-a83d2922a1d8.png",
	"res://Components/Gameplay/Balloon Popping/Background/95ae2a22-302d-48f7-9b5f-e12b0104c822.png",
	"res://Components/Gameplay/Balloon Popping/Balloons/purple.png",
	"res://Components/Gameplay/Balloon Popping/Balloons/green.png",
	"res://Components/Gameplay/Balloon Popping/Balloons/blue.png",
	"res://ui/minigames/balloon_popping/balloon_art/balloon_purple.tscn",
	"res://ui/minigames/balloon_popping/balloon_art/balloon_green.tscn",
	"res://ui/minigames/balloon_popping/balloon_art/balloon_blue.tscn",
	"res://ui/minigames/balloon_popping/balloon_art/launcher.tscn",
	"res://ui/minigames/balloon_popping/balloon_art/stone.tscn",
]

var failures: Array[String] = []
var checks := 0
var screenshot_paths: Array[String] = []


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	await _test_serialized_scene_resources()
	# Isolate Balloon integration regressions with the command-line argument
	# -- --balloon-only. The default mixed art audit continues checking Catch.
	if not OS.get_cmdline_user_args().has("--balloon-only"):
		await _test_catch_random_art()
		await _test_catch_inventory_and_pause()
	await _test_balloon_reveal_hide_pause_and_collision()

	if failures.is_empty():
		print("PASS  art scenes: %d checks" % checks)
		for path in screenshot_paths:
			print("ART_QA_SCREENSHOT  ", path)
		quit(0)
	else:
		for failure in failures:
			push_error("ART SCENE QA: " + failure)
		print("FAIL  art scenes: %d checks / %d failures (exit 1)" % [checks, failures.size()])
		for path in screenshot_paths:
			print("ART_QA_SCREENSHOT  ", path)
		quit(1)


func _test_serialized_scene_resources() -> void:
	for path in CATCH_ASSETS + BALLOON_ASSETS:
		if path.ends_with(".png"):
			# Balloon intentionally raw-loads source PNGs so the art remains robust
			# even when Godot .png.import sidecars do not exist yet.
			_assert(FileAccess.file_exists(path), "raw art file exists: " + path)
		else:
			_assert(ResourceLoader.exists(path), "resource exists: " + path)

	var catch_text := _file_text(CATCH_SCENE)
	for expected in [
		"[node name=\"Background\" type=\"TextureRect\"",
		"[node name=\"FallingWordLayer\" type=\"Node2D\"",
		"[node name=\"Bear\" type=\"Node2D\"",
		"[node name=\"HUDLayer\" type=\"CanvasLayer\"",
	]:
		_assert(catch_text.contains(expected), "Catch TSCN serializes " + expected)
	# Godot 4.7.2 can insert unique_id= before the closing bracket. Check
	# the actual node name, type and parent instead of a brittle full header.
	_assert(not catch_text.contains("[node name=\"CharacterRig\""), "Catch no obsolete parent node")
	_assert(_has_serialized_node(catch_text, "CollectedWords", "Node2D", "."),
		"Catch CollectedWords is editor-authored root sibling")
	for character_name in ["Bear", "Cat", "Dog", "Lion", "Panda"]:
		_assert(_has_serialized_node(catch_text, character_name, "Node2D", "."),
			"Catch %s scene-authored root group" % character_name)
		for part in ["Body", "Basket"]:
			_assert(_has_serialized_node(catch_text, part, "Sprite2D", character_name),
				"Catch %s/%s is scene-authored sprite" % [character_name, part])

	var balloon_text := _file_text(BALLOON_SCENE)
	for expected in [
		"[node name=\"BoothBackdrop\" type=\"TextureRect\"",
		"[node name=\"BalloonLayer\" type=\"Node2D\"",
		"[node name=\"ForegroundCounter\" type=\"TextureRect\"",
		"[node name=\"ProjectileLayer\" type=\"Node2D\"",
	]:
		_assert(balloon_text.contains(expected), "Balloon TSCN serializes " + expected)
	# PackedScene instance headers may include optional unique_id=. Verify
	# each child is the expected instance *from the expected art file*,
	# rather than accepting any scene or simply checking for "instance=".
	for node_info in [
		["LeftTarget", "BalloonLayer", "res://ui/minigames/balloon_popping/balloon_art/balloon_purple.tscn"],
		["CenterTarget", "BalloonLayer", "res://ui/minigames/balloon_popping/balloon_art/balloon_green.tscn"],
		["RightTarget", "BalloonLayer", "res://ui/minigames/balloon_popping/balloon_art/balloon_blue.tscn"],
		["Launcher", "LauncherLayer", "res://ui/minigames/balloon_popping/balloon_art/launcher.tscn"],
	]:
		_assert(_has_serialized_node(balloon_text, node_info[0], "", node_info[1], node_info[2]),
			"Balloon TSCN serializes %s as instance of %s under %s" %
			[node_info[0], node_info[2], node_info[1]])

	var catch := await _instantiate(CATCH_SCENE)
	if catch != null:
		_assert(catch.get_node_or_null("Background") is TextureRect, "Catch Background is editor TextureRect")
		_assert(catch.get_node_or_null("Bear/Body") is Sprite2D, "Catch Body is editor Sprite2D")
		_assert(catch.get_node_or_null("Bear/Basket") is Sprite2D, "Catch Basket is editor Sprite2D")
		_assert(catch.get_node_or_null("CollectedWords") is Node2D, "Catch CollectedWords is editor Node2D")
		var bg := catch.get_node("Background") as TextureRect
		var body := catch.get("body_sprite") as Sprite2D
		var basket := catch.get("basket_sprite") as Sprite2D
		_assert(bg.texture != null, "Catch Background has an editable texture resource")
		_assert(body.texture != null and basket.texture != null, "Catch body/basket have editable texture resources")
		await _dispose(catch)

	var balloon := await _instantiate(BALLOON_SCENE)
	if balloon != null:
		var backdrop := balloon.get_node_or_null("BoothBackdrop") as TextureRect
		var counter := balloon.get_node_or_null("ForegroundCounter") as TextureRect
		var layer := balloon.get_node_or_null("BalloonLayer") as Node2D
		_assert(backdrop != null and backdrop.texture != null, "Balloon booth backdrop is an editor texture")
		_assert(counter != null and counter.texture != null, "Balloon foreground counter is an editor texture")
		_assert(layer != null and counter.z_index > layer.z_index, "Balloon counter masks in front of target layer")
		for target_name in ["LeftTarget", "CenterTarget", "RightTarget"]:
			var target := balloon.get_node_or_null("BalloonLayer/" + target_name) as Area2D
			_assert(target != null, "Balloon " + target_name + " is editor Area2D")
			if target != null:
				var sprite := target.get_node_or_null("Sprite") as Sprite2D
				var shape := target.get_node_or_null("CollisionShape2D") as CollisionShape2D
				var word := target.get_node_or_null("WordLabel") as Label
				_assert(sprite != null and sprite.texture != null, target_name + " has editable sprite asset")
				_assert(shape != null and shape.shape != null, target_name + " has editable collision shape")
				_assert(word != null, target_name + " has editable word label")
		await _dispose(balloon)


func _test_catch_random_art() -> void:
	var pair_a := await _catch_pair_for_seed(20260919)
	var pair_b := await _catch_pair_for_seed(20260919)
	_assert(pair_a == pair_b and pair_a.size() == 2, "Catch seeded art selection is deterministic")

	var unique_pairs := {}
	var unique_characters := {}
	var unique_maps := {}
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var pair := await _catch_pair_for_seed(seed_value)
		if pair.size() == 2:
			unique_pairs["%s|%s" % [pair[0], pair[1]]] = true
			unique_characters[pair[0]] = true
			unique_maps[pair[1]] = true
	_assert(unique_pairs.size() >= 2, "Catch varies art across fresh seeded scene instances")
	_assert(unique_characters.size() >= 2, "Catch randomization reaches multiple characters")
	_assert(unique_maps.size() >= 2, "Catch randomization reaches multiple maps")

	var catch := await _instantiate(CATCH_SCENE)
	if catch == null:
		return
	var restored_character := String(pair_a[0])
	var restored_map := String(pair_a[1])
	catch.call("set_context", _catch_context({
		"catch_character": restored_character,
		"catch_map": restored_map,
		"round_completed": false,
		"score": 125,
		"time_remaining": 42.0,
	}))
	await process_frame
	_assert(String(catch.get("selected_character")) == restored_character, "Catch pause snapshot restores exact character")
	_assert(String(catch.get("selected_map")) == restored_map, "Catch pause snapshot restores exact map")
	var background := catch.get_node("Background") as TextureRect
	var body := catch.get("body_sprite") as Sprite2D
	var basket := catch.get("basket_sprite") as Sprite2D
	_assert(background.texture != null, "Catch restored map texture is applied")
	_assert(body.texture != null, "Catch restored body texture is applied")
	_assert(basket.texture != null, "Catch restored basket texture is applied")
	# Generated characters have separately rendered body and wicker-basket
	# canvases with different pixel resolutions. Their *visible centers* must
	# align; their raw sprite scale factors do not need to be equal.
	_assert(absf(body.position.x - basket.position.x) < 8.0, "Catch body and basket share horizontal alignment")
	var collision_center: Vector2 = (catch.call("_basket_rect") as Rect2).get_center()
	var visual_center := basket.global_position
	_assert(absf(visual_center.x - collision_center.x) < 8.0, "Catch visual basket stays horizontally aligned to gameplay basket")
	for character_name in ["Bear", "Cat", "Dog", "Lion", "Panda"]:
		catch.call("set_context", _catch_context({
			"catch_character": character_name,
			"catch_map": "City",
		}))
		await process_frame
		body = catch.get("body_sprite") as Sprite2D
		basket = catch.get("basket_sprite") as Sprite2D
		if character_name == "Bear":
			print("ART_QA_GEOMETRY root=", root.size, " viewport=", catch.get_viewport_rect().size,
				" scene=", catch.size, " character=", catch.get("character_group").position)
		var body_rect := Rect2(body.global_position + body.get_rect().position * body.global_scale,
			body.get_rect().size * body.global_scale)
		var basket_rect := Rect2(basket.global_position + basket.get_rect().position * basket.global_scale,
			basket.get_rect().size * basket.global_scale)
		var character_bottom := body_rect.end.y
		var basket_top := basket_rect.position.y
		print("ART_QA_CHARACTER_BOUNDS ", character_name, " body=", body_rect,
			" basket=", basket_rect, " scene=", catch.size)
		_assert(body_rect.position.y >= 0.0 and character_bottom <= catch.size.y + 1.0
			and character_bottom >= catch.size.y * 0.75,
			"Catch %s entire original body and feet are in the screen" % character_name)
		_assert(basket_rect.position.x >= 0.0 and basket_rect.end.x <= catch.size.x
			and basket_rect.position.y >= 0.0 and basket_rect.end.y <= catch.size.y,
			"Catch %s entire original basket is in the screen" % character_name)
		# All four restored WordCatcherCharacters use the original framing.
		# The removed using_reference_character flag must not be queried.
		print("Catch original ", character_name, " basket_top=", basket_top, " viewport_height=", catch.size.y)
		var lower_basket_limit: float = 0.48
		_assert(basket_top > catch.size.y * lower_basket_limit and basket_top < catch.size.y * 0.70, "Catch %s basket sits near bottom rim" % character_name)
	_assert(not _file_text("res://ui/minigames/catch_the_word/catch_word.gd").contains("_draw_lane_guides"), "Catch renders no lane guides")
	await _dispose(catch)


func _test_catch_inventory_and_pause() -> void:
	var catch := await _instantiate(CATCH_SCENE)
	if catch == null:
		return
	catch.call("set_context", _catch_context({
			"catch_character": "Bear",
		"catch_map": "City",
	}))
	await process_frame

	# Use five ACTUAL grade-matched vocabulary words from the same live bank,
	# not manufactured "noun1" strings that grammar gameplay never displays.
	var actual_words: Array[String] = []
	var bank = catch.get("grammar_bank")
	var seen_words: Dictionary = {}
	_assert(bank != null and bank.has_method("pick_word"),
		"Catch real grammar bank is present for collected-word art/scoring fixture")
	if bank == null or not bank.has_method("pick_word"):
		await _dispose(catch)
		return
	for index in range(5):
		var word := String(bank.call("pick_word", "Noun", true, catch.get("rng"), "Normal", seen_words))
		_assert(not word.is_empty() and not seen_words.has(word.to_lower()),
			"Collected apple test uses distinct real Noun/Normal vocabulary")
		seen_words[word.to_lower()] = true
		actual_words.append(word)
	for index in range(3):
		catch.call("_handle_catch", {"matching": true, "word": actual_words[index]})
	await process_frame
	var score_at_three := int(catch.get("score"))
	var correct_at_three := int(catch.get("correct_count"))
	catch.call("_handle_catch", {"matching": true, "word": actual_words[3]})
	catch.call("_handle_catch", {"matching": true, "word": actual_words[4]})
	await process_frame

	var collected: Array = catch.get("collected_words")
	var collected_layer := catch.get_node("CollectedWords") as Node2D
	_assert(collected.size() == 3, "Catch visual inventory data caps at three words")
	_assert(collected_layer.get_child_count() == 3, "Catch renders at most three collected apples")
	var basket_width: float = float((catch.call("_basket_visual_size") as Vector2).x)
	var collected_width := -1.0
	for child in collected_layer.get_children():
		_assert(child is TextureRect and (child as TextureRect).texture != null, "Caught item renders an apple texture")
		if child is TextureRect:
			var collected_apple := child as TextureRect
			_assert(collected_apple.texture.resource_path == CAUGHT_HALF_APPLE,
				"Caught apple uses original APPLE HALF artwork, not falling apple artwork")
			_assert(collected_apple.size.x > 0.0 and collected_apple.size.x <= basket_width * 0.29,
				"Caught apple is small relative to authored basket, not oversized")
			_assert(collected_width < 0.0 or is_equal_approx(collected_width, collected_apple.size.x),
				"All three collected halves remain uniformly sized")
			collected_width = collected_apple.size.x
			_assert(collected_apple.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"Small caught half apples do not intercept gameplay input")
		_assert(child.get_child_count() == 0,
			"Caught APPLE HALF has no word label or other unwanted child overlay")
	# Falling grammar apples are different: their real gameplay tile instances
	# must still carry their word labels and their original, full apple artwork.
	var falling: Array = catch.get("falling_tiles")
	_assert(falling.size() == 3, "Active Catch wave contains three actual falling word apples")
	for tile in falling:
		var tile_node: Control = tile.get("node") as Control
		var word := String(tile.get("word", ""))
		var word_label := tile_node.get_node_or_null("WordLabel") as Label if tile_node != null else null
		var full_apple := tile_node.get_node_or_null("AppleSprite") as TextureRect if tile_node != null else null
		_assert(word_label != null and word_label.text == word.to_upper() and not word.is_empty(),
			"Falling grammar apple retains its actual uppercase word label")
		_assert(full_apple != null and full_apple.texture != null
			and full_apple.texture == catch.get("gameplay_apple_texture"),
			"Falling grammar apple retains its original full-size labeled artwork")
	_assert(int(catch.get("correct_count")) == correct_at_three + 2, "Catch correct count continues after visual inventory is full")
	_assert(int(catch.get("score")) == score_at_three + 2 * int(catch.get("CORRECT_ANSWER_POINTS")),
		"Catch continues awarding exactly +100 per real correct grammar word after inventory fills")
	var context: Dictionary = catch.call("get_context")
	_assert((context.get("catch_collected_words", []) as Array).size() == 3, "Catch payload preserves three-word visual inventory")

	var before_cards := _card_snapshot(collected_layer)
	var before_time := float(catch.get("time_remaining"))
	catch.call("_pause")
	await create_timer(0.18).timeout
	var after_cards := _card_snapshot(collected_layer)
	_assert(before_cards == after_cards, "Catch pause preserves exact visual inventory nodes/text")
	_assert(absf(float(catch.get("time_remaining")) - before_time) < 0.01, "Catch pause freezes timer with visual inventory intact")
	await _capture("user://qa_catch_art_1280x720.png")
	catch.call("_resume")
	await _dispose(catch)


func _test_balloon_reveal_hide_pause_and_collision() -> void:
	var balloon := await _instantiate(BALLOON_SCENE)
	if balloon == null:
		return
	balloon.call("set_context", {
		"activity": "Balloon Popping", "topic": "Noun", "game_style": "Noun",
		"game_mode": "Activity", "difficulty": "Normal", "camera_live": false
	})
	balloon.set_process(false)
	balloon.set_physics_process(false)
	var layer := balloon.get_node("BalloonLayer") as Node2D
	var counter := balloon.get_node("ForegroundCounter") as TextureRect
	_assert(counter.z_index > layer.z_index, "Balloon wooden foreground occludes target sprites")

	# The title matches Catch's 506x157 rectangle, with the changing grammar
	# prompt inside the cream band rather than across the title lettering.
	var title := balloon.get_node("HudLayer/ObjectivePanel") as TextureRect
	var prompt := balloon.get_node("HudLayer/BannerTagline") as Label
	_assert(title.position.distance_to(Vector2(13.0, 10.0)) < 0.5
		and title.size.distance_to(Vector2(506.0, 157.0)) < 0.5,
		"Balloon title matches Catch's exact authored objective position and size")
	_assert(prompt.position.distance_to(Vector2(115.0, 96.0)) < 0.5
		and prompt.size.distance_to(Vector2(306.0, 34.0)) < 0.5,
		"Balloon grammar text uses the cream strip, clear of title lettering")

	# Set real editor-owned Area2D lanes and remember their identity.
	balloon.call("_clear_balloons")
	balloon.set("timer_running", true)
	balloon.set("round_active", true)
	var one_lane: Array[int] = [0]
	var options: Array[String] = ["APPLE", "SHE", "SOFTLY"]
	balloon.set("valid_lanes", one_lane.duplicate())
	balloon.set("pending_valid_lanes", one_lane.duplicate())
	balloon.call("_spawn_balloons", options)
	balloon.set_process(false)
	var slots: Array = balloon.get("balloon_slots")
	var hidden_y: float = float(balloon.call("_balloon_hidden_y"))
	var exposed_y: float = float(balloon.call("_balloon_y"))
	var speed: float = float(balloon.get("balloon_float_speed"))
	var exit_y: float = float(balloon.get("BALLOON_EXIT_Y"))
	var baseline_ids: Array[int] = []
	_assert((hidden_y - exit_y) / speed < float(balloon.get("round_time_limit")),
		"Balloon continuous flight reaches the top before its path-aware question cutoff")
	for lane in range(3):
		var target := slots[lane] as Area2D
		baseline_ids.append(target.get_instance_id())
		_assert(target.visible and absf(target.position.y - hidden_y) < 1.0,
			"Balloon lane %d starts fully behind wooden counter" % lane)
		_assert(not target.monitoring and not target.monitorable,
			"Concealed balloon lane %d has no collision" % lane)
	var initial_question: float = balloon.get("round_time_remaining")
	balloon._process(0.30)
	balloon.set_process(false)
	_assert(absf((slots[0] as Area2D).position.y - (hidden_y - speed * 0.30)) < 0.5,
		"Balloon first 300ms follows constant speed without an easing tween")
	_assert(absf(float(balloon.get("round_time_remaining")) - (initial_question - 0.30)) < 0.01,
		"Balloon seven-second question clock starts during concealed ascent")
	for lane in range(3):
		var target := slots[lane] as Area2D
		_assert(not target.monitoring, "Balloon lane %d is noncolliding below exposed area" % lane)
	await _capture("user://qa_balloon_hidden_1280x720.png")

	# Pause freezes actual positions, question clock and global clock.
	var rising_y: float = (slots[0] as Area2D).position.y
	var question_before_pause: float = balloon.get("round_time_remaining")
	var timer_before_pause: float = balloon.get("time_remaining")
	balloon._pause()
	balloon._process(0.5)
	balloon._physics_process(0.5)
	_assert(absf((slots[0] as Area2D).position.y - rising_y) < 0.5,
		"Balloon continuous ascent freezes on pause")
	_assert(absf(float(balloon.get("round_time_remaining")) - question_before_pause) < 0.01
		and absf(float(balloon.get("time_remaining")) - timer_before_pause) < 0.01,
		"Balloon pause freezes question and total mode clock")
	balloon._resume()
	balloon.set_process(false)
	var destination_y := float(balloon.get("UPPER_LINE_Y")) + 135.0
	balloon._process((rising_y - destination_y) / speed)
	balloon.set_process(false)
	for lane in range(3):
		var target := slots[lane] as Area2D
		_assert(absf(target.position.y - destination_y) < 1.0 and
			target.position.y < exposed_y,
			"Balloon lane %d continues same ascent into visible playfield" % lane)
		_assert(target.monitoring and target.monitorable,
			"Exposed balloon lane %d permits a valid hit" % lane)
	await _capture("user://qa_balloon_exposed_1280x720.png")

	# A stone already launched when the question closes cannot score, damage
	# health or alter attempts, even if it crosses the old target position.
	_assert(not bool(balloon.call("_launch_projectile")),
		"Direct projectile spawn cannot bypass verified hand gesture")
	_assert(_fire_with_observed_raise(balloon),
		"Fresh physical low/high gesture launches a real stone")
	var late_stones: Array = balloon.get("projectiles")
	_assert(late_stones.size() == 1, "One editor-authored stone flies before a transition")
	var before_attempts: int = balloon.get("attempts")
	var before_correct: int = balloon.get("correct_count")
	var before_score: int = balloon.get("score")
	var before_hearts: int = balloon.get("hearts")
	balloon.set("round_active", false)
	balloon.call("_hide_balloons_behind_counter")
	await process_frame
	for lane in range(3):
		var target := slots[lane] as Area2D
		_assert(not target.visible and not target.monitoring and not target.monitorable,
			"Retired balloon lane %d remains fully hidden and noncolliding" % lane)
	if not late_stones.is_empty():
		var late := late_stones[0] as Area2D
		if is_instance_valid(late):
			balloon.call("_update_projectiles", 0.35)
			if is_instance_valid(late):
				balloon.call("_on_projectile_area_entered", slots[0], late)
	_assert(int(balloon.get("attempts")) == before_attempts
		and int(balloon.get("correct_count")) == before_correct
		and int(balloon.get("score")) == before_score
		and int(balloon.get("hearts")) == before_hearts,
		"Late projectile after wave retirement cannot score, cost hearts or count attempts")
	balloon.call("_clear_projectiles")

	# Reuse the authored targets on the following wave and test actual physics
	# collision against the left correct balloon (not just direct hit handler).
	balloon.set("timer_running", true)
	balloon.set("round_active", true)
	balloon.set("valid_lanes", one_lane.duplicate())
	balloon.set("pending_valid_lanes", one_lane.duplicate())
	balloon.call("_spawn_balloons", options)
	balloon.set_process(false)
	_assert(not (slots[0] as Area2D).monitorable,
		"Respawned balloon does not collide until it rises past counter")
	balloon._process((hidden_y - destination_y) / float(balloon.get("balloon_float_speed")))
	balloon.set_process(false)
	var left_target := slots[0] as Area2D
	_assert(left_target.visible and left_target.monitoring and left_target.monitorable,
		"Second ascent enables real collision at the exposed balloon")
	_assert(left_target.get_instance_id() == baseline_ids[0],
		"New wave reuses the original editable left target Area2D")
	balloon.set("launcher_x", float(balloon.call("_lane_x", 0)))
	balloon.call("_layout_scene")
	var shots_before: int = balloon.get("attempts")
	var correct_before: int = balloon.get("correct_count")
	var score_before: int = balloon.get("score")
	var previous_shot: int = int(balloon.get("hand_raise_last_shot_ms"))
	_assert(previous_shot >= 0 and balloon.HAND_RAISE_RELOAD_MS == 1000,
		"Balloon uses the approved 1000ms repeat interval for genuine hands")
	_assert(_fire_with_observed_raise(balloon),
		"Fresh re-raise after previous stone sends another physical projectile")
	_assert(int(balloon.get("hand_raise_last_shot_ms")) >= previous_shot + 1000,
		"Real launched stone is spaced by at least 1000ms")
	_assert((balloon.get("projectiles") as Array).size() == 1,
		"Live scene contains one moving projectile")
	balloon.set_physics_process(true)
	for frame in range(90):
		if int(balloon.get("attempts")) > shots_before:
			break
		await physics_frame
		await process_frame
	balloon.set_physics_process(false)
	_assert(int(balloon.get("attempts")) == shots_before + 1,
		"Real Area2D projectile collision registers exactly one attempt")
	_assert(int(balloon.get("correct_count")) == correct_before + 1,
		"Physical collision registers correct grammar answer")
	_assert(int(balloon.get("score")) == score_before + int(balloon.get("CORRECT_POP_SCORE")),
		"Physical collision awards exactly +100")
	_assert(not left_target.visible and not left_target.monitoring,
		"Successful physical pop hides target and retires its collision")
	_assert(left_target.get_instance_id() == baseline_ids[0],
		"Balloon never replaces the authored target instance")
	await _dispose(balloon)
func _fire_with_observed_raise(game: Control) -> bool:
	# Launch permission is deliberately private to a fresh camera gesture. A
	# direct _launch_projectile() call must never bypass the new safety gate.
	# Advance source times monotonically and honor the actual 180ms lowered,
	# 80ms raised and 1000ms post-shot reload requirements.
	var last_shot := int(game.get("hand_raise_last_shot_ms"))
	var start := maxi(Time.get_ticks_msec(), last_shot + int(game.get("HAND_RAISE_RELOAD_MS")) + 100)
	game.call("set_hand_raise_state", false, true, start)
	game.call("set_hand_raise_state", false, true, start + 200)
	game.call("set_hand_raise_state", true, true, start + 201)
	return bool(game.call("set_hand_raise_state", true, true, start + 300))


func _catch_pair_for_seed(seed_value: int) -> Array[String]:
	var catch := await _instantiate(CATCH_SCENE)
	if catch == null:
		return []
	var rng: RandomNumberGenerator = catch.get("rng")
	rng.seed = seed_value
	catch.call("set_context", _catch_context({}))
	await process_frame
	var pair: Array[String] = [
		String(catch.get("selected_character")),
		String(catch.get("selected_map")),
	]
	await _dispose(catch)
	return pair


func _catch_context(extra: Dictionary) -> Dictionary:
	var result := {
		"activity": "Catch the Word",
		"topic": "Noun",
		"game_style": "Noun",
		"game_mode": "Activity",
		"difficulty": "Normal",
		"camera_live": false,
	}
	result.merge(extra, true)
	return result


func _instantiate(path: String) -> Control:
	if not ResourceLoader.exists(path):
		_fail("Missing scene: " + path)
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		_fail("Could not load PackedScene: " + path)
		return null
	var instance := packed.instantiate() as Control
	if instance == null:
		_fail("Scene root is not Control: " + path)
		return null
	root.add_child(instance)
	# Headless Windows may expose a 64x64 root and a *square* logical
	# get_viewport_rect() despite the project's 1280x720 game design. Mount
	# the editor-authored scene in an exact 1280x720 logical test canvas rather
	# than testing its geometry inside the headless fallback's 1280x1280 area.
	instance.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	instance.size = Vector2(1280.0, 720.0)
	await process_frame
	await process_frame
	return instance


func _dispose(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
	await process_frame
	await process_frame


func _card_snapshot(layer: Node2D) -> Array:
	var result: Array = []
	for child in layer.get_children():
		if child is TextureRect and not child.is_queued_for_deletion():
			var label_text := ""
			if child.get_child_count() > 0 and child.get_child(0) is Label:
				label_text = String((child.get_child(0) as Label).text)
			result.append({
				"id": child.get_instance_id(),
				"text": label_text,
				"position": child.position,
			})
	return result


func _capture(relative_path: String) -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		print("ART_QA_SCREENSHOT_SKIP  headless renderer: ", relative_path)
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_warning("ART QA screenshot unavailable with current renderer: " + relative_path)
		return
	_assert(image.get_width() >= 1280 and image.get_height() >= 720, "Captured 1280x720 art frame: " + relative_path)
	var err := image.save_png(relative_path)
	if err != OK:
		push_warning("ART QA could not save screenshot: " + relative_path)
		return
	screenshot_paths.append(ProjectSettings.globalize_path(relative_path))


func _file_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Could not read serialized scene: " + path)
		return ""
	return file.get_as_text()


func _has_serialized_node(scene_text: String, node_name: String, node_type: String,
		parent_path: String, packed_scene_path: String = "") -> bool:
	# Match real node declaration lines, allowing optional Godot attributes
	# such as unique_id in any position; never infer a node from mere text.
	for line in scene_text.split("\n"):
		if not line.begins_with('[node name="%s"' % node_name) or not line.ends_with("]"):
			continue
		if not line.contains(' parent="%s"' % parent_path):
			continue
		if not node_type.is_empty() and not line.contains(' type="%s"' % node_type):
			continue
		if packed_scene_path.is_empty():
			return true
		var instance_prefix := ' instance=ExtResource("'
		var prefix_index := line.find(instance_prefix)
		if prefix_index < 0:
			continue
		var resource_start := prefix_index + instance_prefix.length()
		var resource_end := line.find('")', resource_start)
		if resource_end < 0:
			continue
		var resource_id := line.substr(resource_start, resource_end - resource_start)
		# Resolve the ID to its declared PackedScene resource so even an
		# accidentally swapped instance is caught by this structural check.
		for resource_line in scene_text.split("\n"):
			if resource_line.begins_with("[ext_resource ") \
					and resource_line.contains(' type="PackedScene"') \
					and resource_line.contains(' path="%s"' % packed_scene_path) \
					and resource_line.contains(' id="%s"' % resource_id):
				return true
	return false


func _assert(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS  ", label)
	else:
		_fail(label)


func _fail(reason: String) -> void:
	failures.append(reason)
