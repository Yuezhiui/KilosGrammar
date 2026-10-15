extends SceneTree

# Focused headless QA for the three playable KilosGrammar minigames.
# Run after the scenes land:
# Godot --headless --path . --script res://tools/test_minigames.gd

const SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

const GAMES: Array[Dictionary] = [
	{
		"activity": "Catch the Word",
		"path": "res://ui/minigames/catch_word.tscn",
	},
	{
		"activity": "Balloon Popping",
		"path": "res://ui/minigames/balloon_popping.tscn",
	},
	{
		"activity": "Human Plane",
		"path": "res://ui/minigames/human_plane.tscn",
	},
]

const HUD_NAME_HINTS := [
	"score", "time", "timer", "prompt", "pause", "instruction",
	"title", "mode", "difficulty", "status", "streak", "round",
]

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_lane_generation()
	for game_info in GAMES:
		var activity := String(game_info["activity"])
		var path := String(game_info["path"])
		if not ResourceLoader.exists(path):
			_fail("%s scene missing: %s" % [activity, path])
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			_fail("%s could not load as PackedScene" % activity)
			continue
		await _test_pause_contract(packed, activity)
		await _test_completion_contract(packed, activity)
		await _test_collision_idempotence(packed, activity)
		await _test_layout(packed, activity)
	await _test_early_exit_not_completed()
	await _test_balloon_negative_prompts()

	if failures.is_empty():
		print("PASS  minigames: %d checks across 3 playable scenes" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("MINIGAME QA: " + failure)
		quit(1)


func _test_pause_contract(packed: PackedScene, activity: String) -> void:
	root.size = Vector2i(1280, 720)
	var game := _instantiate_game(packed, activity)
	if game == null:
		return
	var events: Array[Dictionary] = []
	var pause_payload: Dictionary = {}
	game.connect("requested", func(target: String, payload: Dictionary) -> void:
		events.append({"target": target, "payload": payload.duplicate(true)})
	)
	game.call("set_context", _context_for(activity))
	await process_frame
	await process_frame
	_assert_base_api(game, activity)
	if game.has_method("set_body_x"):
		game.call("set_body_x", -1.0)
		game.call("set_body_x", 0.0)
		game.call("set_body_x", 1.0)
		_pass("%s accepts normalized body-x bridge values" % activity)

	var pause_method := ""
	if game.has_method("_pause"):
		pause_method = "_pause"
	elif game.has_method("_request_pause"):
		pause_method = "_request_pause"
	if pause_method.is_empty():
		_fail("%s has no runtime pause hook (_pause/_request_pause)" % activity)
		await _dispose(game)
		return

	game.call(pause_method)
	await process_frame
	var pause_event := _find_event(events, "pause")
	var paused_time := -1.0
	if pause_event.is_empty():
		_fail("%s did not emit requested('pause', payload)" % activity)
	else:
		var payload: Dictionary = pause_event["payload"]
		pause_payload = payload.duplicate(true)
		paused_time = float(payload.get("time_remaining", -1.0))
		_assert_context_identity(payload, activity, "pause")
		_assert_score_and_timer(payload, activity, "pause")
		if bool(payload.get("round_completed", false)):
			_fail("%s pause payload incorrectly marks round_completed=true" % activity)
		else:
			_pass("%s pause payload remains incomplete" % activity)

	# A real pause must freeze the round clock while the scene is waiting to be
	# replaced by the pause overlay. This catches timers that keep counting down
	# after a pause request.
	await create_timer(0.16).timeout
	var after := _safe_context(game)
	if paused_time >= 0.0 and after.has("time_remaining"):
		var drift := absf(float(after["time_remaining"]) - paused_time)
		if drift > 0.05:
			_fail("%s timer advanced %.3fs after pause" % [activity, drift])
		else:
			_pass("%s timer freezes on pause" % activity)
	await _dispose(game)

	# Resume is implemented by rebuilding the gameplay scene from the pause
	# payload. Core score/timer state must survive that reconstruction.
	if not pause_payload.is_empty():
		var resumed := _instantiate_game(packed, activity)
		if resumed != null:
			resumed.call("set_context", pause_payload)
			await process_frame
			await process_frame
			var resumed_context := _safe_context(resumed)
			if int(resumed_context.get("score", -1)) != int(pause_payload.get("score", -2)):
				_fail("%s resume changed score" % activity)
			else:
				_pass("%s resume preserves score" % activity)
			var original_time := float(pause_payload.get("time_remaining", -1.0))
			var resumed_time := float(resumed_context.get("time_remaining", -2.0))
			if original_time < 0.0 or resumed_time < original_time - 0.20 or resumed_time > original_time + 0.02:
				_fail("%s resume did not preserve timer (pause %.3f, resume %.3f)" % [activity, original_time, resumed_time])
			else:
				_pass("%s resume preserves timer" % activity)
			if bool(resumed_context.get("round_completed", false)):
				_fail("%s resumed scene incorrectly starts completed" % activity)
			else:
				_pass("%s resume remains an active/incomplete round" % activity)
			await _dispose(resumed)


func _test_completion_contract(packed: PackedScene, activity: String) -> void:
	root.size = Vector2i(1280, 720)
	var game := _instantiate_game(packed, activity)
	if game == null:
		return
	var events: Array[Dictionary] = []
	game.connect("requested", func(target: String, payload: Dictionary) -> void:
		events.append({"target": target, "payload": payload.duplicate(true)})
	)
	game.call("set_context", _context_for(activity))
	await process_frame
	await process_frame
	if not game.has_method("_finish_round"):
		_fail("%s has no _finish_round test/completion hook" % activity)
		await _dispose(game)
		return
	game.call("_finish_round")
	await process_frame
	var result_event := _find_event(events, "results")
	if result_event.is_empty():
		_fail("%s did not emit requested('results', payload)" % activity)
	else:
		var payload: Dictionary = result_event["payload"]
		_assert_context_identity(payload, activity, "results")
		_assert_score_and_timer(payload, activity, "results")
		if not bool(payload.get("round_completed", false)):
			_fail("%s results payload is missing round_completed=true" % activity)
		else:
			_pass("%s results payload marks a completed round" % activity)
		if bool(payload.get("camera_live", false)):
			_fail("%s claims camera_live=true although camera/CV is unimplemented" % activity)
		else:
			_pass("%s completion does not fabricate live-camera status" % activity)
	await _dispose(game)


func _test_collision_idempotence(packed: PackedScene, activity: String) -> void:
	root.size = Vector2i(1280, 720)
	var game := _instantiate_game(packed, activity)
	if game == null:
		return
	game.call("set_context", _context_for(activity))
	if activity == "Catch the Word":
		# Freeze automatic ticks before the assertion: spawned apples must still
		# have their exact initial, off-screen Y, then we manually test movement.
		game.set_process(false)
	await process_frame
	await process_frame
	var before := int(_safe_context(game).get("attempts", 0))
	var exercised := false

	match activity:
		"Catch the Word":
			if game.has_method("_basket_rect") and game.has_method("_update_tiles") and game.has_method("_update_spawning"):
				var tiles: Array = game.get("falling_tiles")
				var matching_index := -1
				var matching_count := 0
				for index in range(tiles.size()):
					if bool(tiles[index].get("matching", false)):
						matching_index = index
						matching_count += 1
				if tiles.size() != 3 or matching_count != 1 or String(game.get("wave_phase")) != "falling":
					_fail("Catch collision fixture needs an immediately falling wave of 3 apples (1 correct)")
				else:
					# New waves enter falling at once, starting fully above the top edge.
					# Check positive descent before moving the correct apple into the basket.
					game.set_process(false)
					var start_y: float = (tiles[0]["pos"] as Vector2).y
					if start_y >= -53.0 or float(game.get("spawn_interval")) > 0.0:
						_fail("Catch wave was not spawned fully above screen without a reading pause")
					game.call("_update_tiles", 0.05)
					if String(game.get("wave_phase")) != "falling" or (tiles[0]["pos"] as Vector2).y <= start_y:
						_fail("Catch did not begin descending immediately after spawn")
					var tile: Dictionary = tiles[matching_index]
					var basket_rect: Rect2 = game.call("_basket_rect")
					tile["pos"] = basket_rect.get_center()
					tiles[matching_index] = tile
					game.set("falling_tiles", tiles)
					game.call("_update_tiles", 0.0)
					var first_phase := String(game.get("wave_phase"))
					var scored_once := int(game.get("score"))
					var correct_once := int(game.get("correct_count"))
					game.call("_update_tiles", 0.0)
					if first_phase != "clearing" or String(game.get("wave_phase")) != "clearing":
						_fail("Catch one selection did not move its entire three-apple wave to clearing")
					if scored_once <= 0 or int(game.get("score")) != scored_once or correct_once != 1 or int(game.get("correct_count")) != 1:
						_fail("Catch counted a correct three-apple selection more than once")
					if (game.get("falling_tiles") as Array).size() != 2:
						_fail("Catch did not leave exactly two unchosen apples to clear")
					exercised = true
		"Balloon Popping":
			if game.has_method("_pop_balloon"):
				var lanes: Array = game.get("valid_lanes")
				if not lanes.is_empty():
					var lane := int(lanes[0])
					game.call("_pop_balloon", lane)
					game.call("_pop_balloon", lane)
					exercised = true
		"Human Plane":
			if game.has_method("_resolve_at_answer_line"):
				game.call("_resolve_at_answer_line")
				game.call("_resolve_at_answer_line")
				exercised = true

	if not exercised:
		_fail("%s collision-resolution path could not be exercised" % activity)
	else:
		var after := int(_safe_context(game).get("attempts", 0))
		if after - before != 1:
			_fail("%s resolved one collision/answer %d times" % [activity, after - before])
		else:
			_pass("%s resolves a collision/answer exactly once" % activity)
	await _dispose(game)


func _test_lane_generation() -> void:
	const BANK_PATH := "res://ui/minigames/grammar_bank.gd"
	if not ResourceLoader.exists(BANK_PATH):
		_fail("grammar_bank.gd missing")
		return
	var bank := load(BANK_PATH) as Script
	if bank == null or not bank.has_method("lane_round"):
		_fail("grammar bank has no lane_round()")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 260926
	var saw_one := false
	var saw_two := false
	for difficulty in ["Normal", "Hard"]:
		for _sample in range(60):
			var round_data: Dictionary = bank.call("lane_round", "Noun", difficulty, rng)
			var options: Array = round_data.get("options", [])
			var valid: Array = round_data.get("valid_indices", [])
			if options.size() != 3:
				_fail("%s lane round did not produce exactly 3 options" % difficulty)
				continue
			if valid.size() < 1 or valid.size() > 2:
				_fail("%s lane round produced %d correct lanes; expected 1 or 2" % [difficulty, valid.size()])
				continue
			var unique := {}
			for value in valid:
				var lane := int(value)
				if lane < 0 or lane >= 3:
					_fail("%s lane round produced out-of-range correct lane %d" % [difficulty, lane])
				unique[lane] = true
			if unique.size() != valid.size():
				_fail("%s lane round duplicated a correct lane" % difficulty)
			saw_one = saw_one or valid.size() == 1
			saw_two = saw_two or valid.size() == 2
	if saw_one and saw_two:
		_pass("grammar bank supports both one- and two-answer lane rounds")
	else:
		_fail("grammar bank sampling did not demonstrate both one- and two-answer rounds")


func _test_early_exit_not_completed() -> void:
	for info in [
		{"path": "res://ui/minigames/catch_word.tscn", "activity": "Catch the Word", "method": "_manual_finish"},
		{"path": "res://ui/minigames/balloon_popping.tscn", "activity": "Balloon Popping", "method": "_exit_to_results"}
	]:
		var packed := load(String(info["path"])) as PackedScene
		var activity := String(info["activity"])
		var game := _instantiate_game(packed, activity)
		game.call("set_context", _context_for(activity))
		await process_frame
		var events: Array[Dictionary] = []
		game.connect("requested", func(route: String, payload: Dictionary) -> void:
			events.append({"route": route, "payload": payload.duplicate(true)})
		)
		game.call(String(info["method"]))
		await process_frame
		if events.is_empty() or String(events[0].get("route", "")) != "results":
			_fail(activity + " manual exit did not navigate to results")
		elif bool((events[0]["payload"] as Dictionary).get("round_completed", true)):
			_fail(activity + " manual exit incorrectly marked a completed round")
		else:
			_pass(activity + " manual exit cannot overwrite completed score")
		await _dispose(game)


func _test_balloon_negative_prompts() -> void:
	var packed := load("res://ui/minigames/balloon_popping.tscn") as PackedScene
	var game := _instantiate_game(packed, "Balloon Popping")
	var state := _context_for("Balloon Popping")
	state["difficulty"] = "Hard"
	game.call("set_context", state)
	await process_frame
	var prompt: Label = game.get("prompt_label") as Label
	var valid: Array = game.get("valid_lanes")
	var balloons: Array = game.get("balloons")
	var bank := load("res://ui/minigames/grammar_bank.gd") as Script
	if prompt == null or not prompt.text.contains("NOT NOUNS"):
		_fail("Hard Balloon Popping did not ask pupils to pop NON-nouns")
	elif balloons.size() != 3 or valid.size() < 1 or valid.size() > 2:
		_fail("Negative Balloon Popping does not have three lanes and 1-2 valid answers")
	else:
		var truthful := true
		for lane in range(3):
			var balloon := balloons[lane] as Area2D
			if balloon == null:
				truthful = false
				continue
			var word := ""
			for child in balloon.get_children():
				if child is Label:
					word = String((child as Label).text)
			if word.is_empty() or (valid.has(lane) == bool(bank.call("is_matching", word, "Noun"))):
				truthful = false
		if truthful:
			_pass("Hard Balloon Popping selects actual NON-nouns, supports multi-target hits")
		else:
			_fail("Balloon negative prompt validity disagrees with word grammar")
	await _dispose(game)


func _test_layout(packed: PackedScene, activity: String) -> void:
	for viewport_size in SIZES:
		root.size = viewport_size
		var game := _instantiate_game(packed, activity)
		if game == null:
			return
		game.call("set_context", _context_for(activity))
		await process_frame
		await process_frame
		var frame := Rect2(Vector2.ZERO, Vector2(viewport_size))
		var controls: Array[Control] = []
		_collect_controls(game, controls)
		var measured := 0
		for control in controls:
			if not control.is_visible_in_tree():
				continue
			if not (control is Button or control is Label):
				continue
			if control.get_global_rect().size.x < 1.0 or control.get_global_rect().size.y < 1.0:
				continue
			if control is Label and not _looks_like_hud(control):
				continue
			var rect := control.get_global_rect()
			measured += 1
			if not frame.encloses(rect.grow(-1.0)):
				_fail("%s %s HUD control %s outside viewport: %s" % [
					activity, str(viewport_size), control.name, str(rect)
				])
		if measured == 0:
			_fail("%s %s exposed no measurable HUD labels/buttons" % [activity, str(viewport_size)])
		else:
			_pass("%s HUD fits %s (%d controls checked)" % [activity, str(viewport_size), measured])
		await _dispose(game)


func _instantiate_game(packed: PackedScene, activity: String) -> Control:
	var game := packed.instantiate() as Control
	if game == null:
		_fail("%s root must inherit Control" % activity)
		return null
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not game.has_signal("requested"):
		_fail("%s has no requested(target, payload) signal" % activity)
	if not game.has_method("set_context"):
		_fail("%s has no set_context(Dictionary)" % activity)
	if not game.has_method("get_context"):
		_fail("%s has no get_context()" % activity)
	return game


func _assert_base_api(game: Control, activity: String) -> void:
	if game.has_signal("requested") and game.has_method("set_context") and game.has_method("get_context"):
		_pass("%s exposes navigation/context API" % activity)
	if not game.has_method("set_body_x"):
		_fail("%s has no set_body_x(normalized_x) camera-bridge hook" % activity)
	var state := _safe_context(game)
	_assert_context_identity(state, activity, "runtime")
	_assert_score_and_timer(state, activity, "runtime")


func _assert_context_identity(payload: Dictionary, activity: String, phase: String) -> void:
	if String(payload.get("activity", "")) != activity:
		_fail("%s %s payload lost activity" % [activity, phase])
	else:
		_pass("%s %s preserves activity" % [activity, phase])
	var style := String(payload.get("game_style", payload.get("topic", "")))
	if style != "Noun":
		_fail("%s %s payload lost Noun game style" % [activity, phase])
	else:
		_pass("%s %s preserves Noun game style" % [activity, phase])
	if String(payload.get("difficulty", "")) != "Normal":
		_fail("%s %s payload lost Normal difficulty" % [activity, phase])
	else:
		_pass("%s %s preserves Normal difficulty" % [activity, phase])


func _assert_score_and_timer(payload: Dictionary, activity: String, phase: String) -> void:
	if not payload.has("score"):
		_fail("%s %s payload has no score" % [activity, phase])
	elif int(payload["score"]) < 0:
		_fail("%s %s score is negative" % [activity, phase])
	else:
		_pass("%s %s exposes nonnegative score" % [activity, phase])
	if not payload.has("time_remaining"):
		_fail("%s %s payload has no time_remaining" % [activity, phase])
	elif float(payload["time_remaining"]) < -0.01:
		_fail("%s %s time_remaining is negative" % [activity, phase])
	else:
		_pass("%s %s exposes nonnegative timer" % [activity, phase])


func _context_for(activity: String) -> Dictionary:
	return {
		"activity": activity,
		"topic": "Noun",
		"game_style": "Noun",
		"game_mode": "Activity",
		"difficulty": "Normal",
		"student_id": "QA-SYNTHETIC",
		"demo_mode": true,
		"preview_mode": true,
		"camera_live": false,
		"database_connected": false,
	}


func _safe_context(game: Control) -> Dictionary:
	if game.has_method("get_context"):
		var value = game.call("get_context")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {}


func _find_event(events: Array[Dictionary], target: String) -> Dictionary:
	for event in events:
		if String(event.get("target", "")) == target:
			return event
	return {}


func _collect_controls(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		if child is Control:
			out.append(child as Control)
		_collect_controls(child, out)


func _looks_like_hud(control: Control) -> bool:
	var cursor: Node = control
	while cursor != null:
		var lowered := String(cursor.name).to_lower()
		for hint in HUD_NAME_HINTS:
			if lowered.contains(hint):
				return true
		cursor = cursor.get_parent()
	return false


func _dispose(game: Control) -> void:
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	await process_frame


func _pass(label: String) -> void:
	checks += 1
	print("PASS  ", label)


func _fail(reason: String) -> void:
	failures.append(reason)
