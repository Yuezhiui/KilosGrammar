extends SceneTree

# Synthetic scoring tests: no webcam, PostgreSQL writes or real round replay.
const GAME := preload("res://ui/minigames/catch_word.tscn")
const DIFFICULTY_SPEEDS := {"Easy": 105.0, "Normal": 185.0, "Hard": 245.0}
const MODES := ["Seconds", "Lives"]

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var tier_speeds: Array[float] = []
	for difficulty in ["Easy", "Normal", "Hard"]:
		for mode in MODES:
			var game := GAME.instantiate() as Control
			root.add_child(game)
			game.set_process(false)
			game.call("set_context", {
				"topic": "Noun", "difficulty": difficulty, "game_mode": mode,
				"catch_character": "Boy", "catch_map": "City"
			})
			game.set_process(false)
			var case := "%s %s" % [difficulty, mode]
			_check(is_equal_approx(float(game.get("base_fall_speed")), float(DIFFICULTY_SPEEDS[difficulty])),
				case + " uses original tiered falling speed")
			if mode == "Seconds":
				tier_speeds.append(float(game.get("base_fall_speed")))
			_check(int(game.get("score")) == 0, case + " starts with 0 score")
			for index in 3:
				game.call("_handle_catch", {"matching": true, "word": ["apple", "teacher", "river"][index]})
				_check(int(game.get("score")) == (index + 1) * 100,
					case + " correct answer %d gives exactly +100, no streak/difficulty multiplier" % (index + 1))
				_check(int(game.get("streak")) == index + 1,
					case + " streak still tracked separately from points")
			game.call("_handle_catch", {"matching": false, "word": "wrong"})
			_check(int(game.get("score")) == 300, case + " incorrect catch adds no points")
			_check(int(game.get("streak")) == 0, case + " incorrect catch resets streak")
			game.call("_handle_catch", {"matching": true, "word": "school"})
			_check(int(game.get("score")) == 400, case + " next correct catch remains +100")
			game.call("_stop_voice_feedback")
			game.call("_clear_falling_tiles")
			game.queue_free()
			await process_frame
	_check(tier_speeds.size() == 3 and tier_speeds[0] < tier_speeds[1] and tier_speeds[1] < tier_speeds[2],
		"fall speed strictly rises Easy -> Normal -> Hard")
	for cleanup_frame in range(4):
		await process_frame
	await create_timer(0.2).timeout
	print("CATCH FIXED SCORE + SPEED: %s (%d checks, %d failures)" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", description)
