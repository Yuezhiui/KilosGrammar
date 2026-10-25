extends SceneTree

# Regression for the editor-authored Catch the Word and Balloon Popping art
# scenes. This deliberately tests the serialized TSCN structure in addition to
# runtime behavior so future refactors do not silently return to script-only art.

const CATCH_SCENE := "res://ui/minigames/catch_word.tscn"
const BALLOON_SCENE := "res://ui/minigames/balloon_popping.tscn"

const CATCH_ASSETS: Array[String] = [
	"res://WordCatcherMaps/CityMap.png",
	"res://WordCatcherMaps/ForestMap.png",
	"res://WordCatcherMaps/MountainMap.png",
	"res://WordCatcherCharacters/BOY BODY.png",
	"res://WordCatcherCharacters/BOY BASKET.png",
	"res://WordCatcherCharacters/GIRL BODY.png",
	"res://WordCatcherCharacters/GIRL BASKET.png",
	"res://WordCatcherCharacters/GRANDMA BODY.png",
	"res://WordCatcherCharacters/GRANDMA BASKET.png",
	"res://WordCatcherCharacters/GRANDPA BODY.png",
	"res://WordCatcherCharacters/GRANDPA BASKET.png",
]

const BALLOON_ASSETS: Array[String] = [
	"res://BalloonPoppingBackground/0826b13c-250f-42e1-9398-a83d2922a1d8.png",
	"res://BalloonPoppingBackground/95ae2a22-302d-48f7-9b5f-e12b0104c822.png",
	"res://BalloonPoppingBalloons/purple.png",
	"res://BalloonPoppingBalloons/green.png",
	"res://BalloonPoppingBalloons/blue.png",
	"res://ui/minigames/balloon_art/balloon_purple.tscn",
	"res://ui/minigames/balloon_art/balloon_green.tscn",
	"res://ui/minigames/balloon_art/balloon_blue.tscn",
	"res://ui/minigames/balloon_art/launcher.tscn",
	"res://ui/minigames/balloon_art/stone.tscn",
]

var failures: Array[String] = []
var checks := 0
var screenshot_paths: Array[String] = []


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	call_deferred("_run")


func _run() -> void:
	await _test_serialized_scene_resources()
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
		"[node name=\"Boy\" type=\"Node2D\"",
		"[node name=\"HUDLayer\" type=\"CanvasLayer\"",
	]:
		_assert(catch_text.contains(expected), "Catch TSCN serializes " + expected)
	# Godot 4.7.2 can insert unique_id= before the closing bracket. Check
	# the actual node name, type and parent instead of a brittle full header.
	_assert(not catch_text.contains("[node name=\"CharacterRig\""), "Catch no obsolete parent node")
	_assert(_has_serialized_node(catch_text, "CollectedWords", "Node2D", "."),
		"Catch CollectedWords is editor-authored root sibling")
	for character_name in ["Boy", "Girl", "Grandma", "Grandpa"]:
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
		["LeftTarget", "BalloonLayer", "res://ui/minigames/balloon_art/balloon_purple.tscn"],
		["CenterTarget", "BalloonLayer", "res://ui/minigames/balloon_art/balloon_green.tscn"],
		["RightTarget", "BalloonLayer", "res://ui/minigames/balloon_art/balloon_blue.tscn"],
		["Launcher", "LauncherLayer", "res://ui/minigames/balloon_art/launcher.tscn"],
	]:
		_assert(_has_serialized_node(balloon_text, node_info[0], "", node_info[1], node_info[2]),
			"Balloon TSCN serializes %s as instance of %s under %s" %
			[node_info[0], node_info[2], node_info[1]])

	var catch := await _instantiate(CATCH_SCENE)
	if catch != null:
		_assert(catch.get_node_or_null("Background") is TextureRect, "Catch Background is editor TextureRect")
		_assert(catch.get_node_or_null("Boy/Body") is Sprite2D, "Catch Body is editor Sprite2D")
		_assert(catch.get_node_or_null("Boy/Basket") is Sprite2D, "Catch Basket is editor Sprite2D")
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
	for character_name in ["Boy", "Girl", "Grandma", "Grandpa"]:
		catch.call("set_context", _catch_context({
			"catch_character": character_name,
			"catch_map": "City",
		}))
		await process_frame
		body = catch.get("body_sprite") as Sprite2D
		basket = catch.get("basket_sprite") as Sprite2D
		var body_rect := Rect2(body.global_position + body.get_rect().position * body.global_scale,
			body.get_rect().size * body.global_scale)
		var basket_rect := Rect2(basket.global_position + basket.get_rect().position * basket.global_scale,
			basket.get_rect().size * basket.global_scale)
		var character_bottom := body_rect.end.y
		var basket_top := basket_rect.position.y
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
	_assert(not _file_text("res://ui/minigames/catch_word.gd").contains("_draw_lane_guides"), "Catch renders no lane guides")
	await _dispose(catch)


func _test_catch_inventory_and_pause() -> void:
	var catch := await _instantiate(CATCH_SCENE)
	if catch == null:
		return
	catch.call("set_context", _catch_context({
		"catch_character": "Boy",
		"catch_map": "City",
	}))
	await process_frame

	for index in range(3):
		catch.call("_handle_catch", {"matching": true, "word": "noun%d" % (index + 1)})
	await process_frame
	var score_at_three := int(catch.get("score"))
	var correct_at_three := int(catch.get("correct_count"))
	catch.call("_handle_catch", {"matching": true, "word": "noun4"})
	catch.call("_handle_catch", {"matching": true, "word": "noun5"})
	await process_frame

	var collected: Array = catch.get("collected_words")
	var collected_layer := catch.get_node("CollectedWords") as Node2D
	_assert(collected.size() == 3, "Catch visual inventory data caps at three words")
	_assert(collected_layer.get_child_count() == 3, "Catch renders at most three collected apples")
	for child in collected_layer.get_children():
		_assert(child is TextureRect and (child as TextureRect).texture != null, "Caught item renders an apple texture")
		_assert(child.get_child_count() == 1 and child.get_child(0) is Label, "Caught apple has its word label")
	_assert(int(catch.get("correct_count")) == correct_at_three + 2, "Catch correct count continues after visual inventory is full")
	_assert(int(catch.get("score")) > score_at_three, "Catch score continues after visual inventory is full")
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
		"activity": "Balloon Popping",
		"topic": "Noun",
		"game_style": "Noun",
		"game_mode": "Activity",
		"difficulty": "Normal",
		"camera_live": false,
	})
	await process_frame

	var layer := balloon.get_node("BalloonLayer") as Node2D
	var counter := balloon.get_node("ForegroundCounter") as TextureRect
	_assert(counter.z_index > layer.z_index, "Balloon foreground counter renders above rising targets")

	# Force a deterministic target set without changing gameplay implementation.
	balloon.call("_clear_balloons")
	balloon.set("timer_running", true)
	balloon.set("round_active", true)
	var one_lane: Array[int] = [0]
	balloon.set("valid_lanes", one_lane.duplicate())
	balloon.set("pending_valid_lanes", one_lane.duplicate())
	var balloon_options: Array[String] = ["APPLE", "SHE", "SOFTLY"]
	balloon.call("_spawn_balloons", balloon_options)
	var slots: Array = balloon.get("balloon_slots")
	var hidden_y := float(balloon.call("_balloon_hidden_y"))
	var exposed_y := float(balloon.call("_balloon_y"))
	_assert(hidden_y > exposed_y + 100.0, "Balloon hidden position is well below exposed target position")
	for lane in range(3):
		var target := slots[lane] as Area2D
		_assert(target.visible, "Balloon lane %d becomes visible for rise animation" % lane)
		_assert(absf(target.position.y - hidden_y) < 3.0, "Balloon lane %d starts behind counter" % lane)
		_assert(not target.monitoring and not target.monitorable,
			"Balloon lane %d has no collision during concealed entrance" % lane)
	# The source's contract is the user's 1.15s ease-in-out tween. Capture all
	# three lanes in one transition rather than checking only the final frame.
	var question_before_reveal := float(balloon.get("round_time_remaining"))
	var float_before_reveal := float(balloon.get("float_timer"))

	# Pause partway through the rise: tween and both timers must remain frozen.
	await create_timer(0.08).timeout
	var rising_y := (slots[0] as Area2D).position.y
	var global_time := float(balloon.get("time_remaining"))
	var question_time := float(balloon.get("round_time_remaining"))
	balloon.call("_pause")
	var paused_y := (slots[0] as Area2D).position.y
	await create_timer(0.18).timeout
	_assert(absf((slots[0] as Area2D).position.y - paused_y) < 0.5, "Balloon rise tween freezes on pause")
	_assert(absf(float(balloon.get("time_remaining")) - global_time) < 0.01, "Balloon global timer freezes on pause")
	_assert(absf(float(balloon.get("round_time_remaining")) - question_time) < 0.01, "Balloon question timer freezes on pause")
	_assert(paused_y < hidden_y and paused_y > exposed_y, "Balloon was genuinely mid-rise when paused")
	_assert(absf(question_time - question_before_reveal) < 0.01,
		"Balloon question countdown does not start before reveal finishes")
	_assert(absf(float_before_reveal - float(balloon.get("float_timer"))) < 0.01,
		"Balloon manual float does not start before reveal finishes")
	balloon.call("_resume")
	var rise_resume_started := Time.get_ticks_msec()
	var last_y: Array[float] = []
	var lane_zero_steps: Array[float] = []
	for lane in range(3):
		last_y.append((slots[lane] as Area2D).position.y)
	var checked_midpoints := 0
	var reveal_deadline := Time.get_ticks_msec() + 2400
	var tween := balloon.get("balloon_motion_tween") as Tween
	while is_instance_valid(tween) and tween.is_running() and Time.get_ticks_msec() < reveal_deadline:
		await create_timer(0.11).timeout
		checked_midpoints += 1
		for lane in range(3):
			var target := slots[lane] as Area2D
			var current_y := target.position.y
			_assert(current_y >= exposed_y - 4.0 and current_y <= hidden_y + 3.0,
				"Balloon lane %d remains within hidden-to-exposed path (no overshoot)" % lane)
			_assert(current_y <= last_y[lane] + 1.0,
				"Balloon lane %d continues rising, never teleports backward" % lane)
			_assert(last_y[lane] - current_y <= (hidden_y - exposed_y) * 0.35,
				"Balloon lane %d advances smoothly without a mid-screen teleport" % lane)
			if lane == 0:
				lane_zero_steps.append(maxf(last_y[lane] - current_y, 0.0))
			last_y[lane] = current_y
			if is_instance_valid(tween) and tween.is_running():
				_assert(not target.monitoring and not target.monitorable,
					"Balloon lane %d stays non-collidable until reveal completes" % lane)
		if is_instance_valid(tween) and tween.is_running():
			_assert(absf(float(balloon.get("round_time_remaining")) - question_before_reveal) < 0.01,
				"Balloon question timer does not tick during 1.15s reveal")
			_assert(absf(float(balloon.get("float_timer")) - float_before_reveal) < 0.01,
				"Balloon manual float stays stopped during reveal")
	_assert(checked_midpoints >= 6, "Balloon 1.15s reveal has several observable gradual animation frames")
	var resumed_rise_elapsed := float(Time.get_ticks_msec() - rise_resume_started) / 1000.0
	_assert(resumed_rise_elapsed >= 0.85 and resumed_rise_elapsed <= 1.35,
		"Balloon new 1.15s entrance does not finish early or stall after resume")
	if lane_zero_steps.size() >= 7:
		var peak_step: float = 0.0
		for step_size in lane_zero_steps:
			peak_step = maxf(peak_step, step_size)
		_assert(peak_step > lane_zero_steps[0] * 1.15 and peak_step > lane_zero_steps[-1] * 1.15,
			"Balloon SINE EASE_IN_OUT rise is slower near its start and end than the middle")
	_assert(is_instance_valid(tween) and not tween.is_running(), "Balloon complete 1.15s tween ends before exposure")
	await process_frame
	for lane in range(3):
		var target := slots[lane] as Area2D
		_assert(absf(target.position.y - exposed_y) < 4.0, "Balloon lane %d completes rise to exposed position" % lane)
		_assert(target.monitoring and target.monitorable, "Exposed balloon lane %d has active collision" % lane)

	await _capture("user://qa_balloon_exposed_1280x720.png")

	# A real question transition marks the round inactive before hiding. Verify
	# that an already-fired stone cannot score after that transition begins.
	balloon.call("_launch_projectile")
	var late_projectiles: Array = balloon.get("projectiles")
	_assert(late_projectiles.size() == 1, "Balloon can have an in-flight stone before hide transition")
	var late_attempts := int(balloon.get("attempts"))
	var late_correct := int(balloon.get("correct_count"))
	var late_score := int(balloon.get("score"))
	balloon.set("round_active", false)
	_assert(not bool(balloon.get("round_active")), "Balloon hide transition is no longer answer-active")

	# Hiding moves the art behind the foreground counter and defers Area2D
	# monitoring changes until the next safe frame.
	balloon.call("_hide_balloons_behind_counter")
	# Monitoring is changed with set_deferred() because Area2D state must not be
	# mutated while physics is flushing overlap notifications.
	await process_frame
	for lane in range(3):
		var target := slots[lane] as Area2D
		_assert(not target.monitoring and not target.monitorable, "Hiding balloon lane %d disables collision" % lane)
	if not late_projectiles.is_empty():
		var late_projectile := late_projectiles[0] as Area2D
		if is_instance_valid(late_projectile):
			# Force its path across the former target band and also exercise the
			# Area2D callback. Both code paths must respect round_active=false.
			balloon.call("_update_projectiles", 0.35)
			if is_instance_valid(late_projectile):
				balloon.call("_on_projectile_area_entered", slots[0], late_projectile)
	_assert(int(balloon.get("attempts")) == late_attempts, "Late stone during hide does not register an attempt")
	_assert(int(balloon.get("correct_count")) == late_correct, "Late stone during hide does not register a correct answer")
	_assert(int(balloon.get("score")) == late_score, "Late stone during hide cannot score")
	balloon.call("_clear_projectiles")
	await create_timer(0.07).timeout
	balloon.call("_pause")
	var hide_pause_y := (slots[1] as Area2D).position.y
	await create_timer(0.16).timeout
	_assert(absf((slots[1] as Area2D).position.y - hide_pause_y) < 0.5, "Balloon hide tween freezes on pause")
	balloon.call("_resume")
	await create_timer(0.31).timeout
	for lane in range(3):
		var target := slots[lane] as Area2D
		_assert(absf(target.position.y - hidden_y) < 4.0, "Balloon lane %d finishes hiding behind counter" % lane)
	await _capture("user://qa_balloon_hidden_1280x720.png")

	# Re-expose the same editor target nodes and verify a real stone physically
	# collides with the exposed valid balloon.
	balloon.set("timer_running", true)
	balloon.set("round_active", true)
	balloon.set("valid_lanes", one_lane.duplicate())
	balloon.set("pending_valid_lanes", one_lane.duplicate())
	balloon.call("_spawn_balloons", balloon_options)
	var replay_tween := balloon.get("balloon_motion_tween") as Tween
	_assert(not (slots[0] as Area2D).monitorable,
		"Balloon second entrance remains non-collidable immediately after respawn")
	# In particular do not fire an exposed-target hit test halfway through the
	# new non-overshooting 1.15s reveal as the old 0.38s fixture did.
	var replay_deadline := Time.get_ticks_msec() + 2400
	while is_instance_valid(replay_tween) and replay_tween.is_running() and Time.get_ticks_msec() < replay_deadline:
		await process_frame
	_assert(is_instance_valid(replay_tween) and not replay_tween.is_running(),
		"Balloon second 1.15s entrance completes before real projectile collision test")
	await process_frame
	var target_zero := slots[0] as Area2D
	_assert(target_zero.monitoring and target_zero.monitorable,
		"Balloon second entrance enables physical hit collision after tween")
	var target_zero_id := target_zero.get_instance_id()
	balloon.set("launcher_x", float(balloon.call("_lane_x", 0)))
	balloon.call("_layout_scene")
	var attempts_before := int(balloon.get("attempts"))
	var correct_before := int(balloon.get("correct_count"))
	var score_before := int(balloon.get("score"))
	balloon.call("_launch_projectile")
	var projectiles: Array = balloon.get("projectiles")
	_assert(projectiles.size() == 1, "Balloon launches one editor-scene stone projectile")
	if not projectiles.is_empty():
		var projectile := projectiles[0] as Area2D
		_assert(projectile.get_node_or_null("CollisionShape2D") is CollisionShape2D, "Stone projectile carries collision shape")

	for _frame in range(55):
		if int(balloon.get("attempts")) > attempts_before:
			break
		await physics_frame
		await process_frame
	_assert(int(balloon.get("attempts")) == attempts_before + 1, "Exposed balloon registers one physical projectile collision")
	_assert(int(balloon.get("correct_count")) == correct_before + 1, "Valid exposed balloon collision increments correct count")
	_assert(int(balloon.get("score")) > score_before, "Valid exposed balloon collision increases score")
	_assert(target_zero.get_instance_id() == target_zero_id, "Balloon collision reuses editor target node rather than replacing it")
	_assert(not target_zero.visible and not target_zero.monitoring, "Popped editor target is hidden and non-collidable")

	await _dispose(balloon)


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
	instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	if condition:
		checks += 1
		print("PASS  ", label)
	else:
		_fail(label)


func _fail(reason: String) -> void:
	failures.append(reason)
