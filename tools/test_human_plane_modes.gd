extends SceneTree

# Run with Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_modes.gd
const GAME_SCENE := preload("res://ui/minigames/human_plane.tscn")
const DIFFICULTIES := [
	{"name": "Easy", "waves": 12, "seconds_lives": 3, "gate_speed": 0.20, "bonus": 0},
	{"name": "Normal", "waves": 14, "seconds_lives": 3, "gate_speed": 0.27, "bonus": 20},
	{"name": "Hard", "waves": 16, "seconds_lives": 3, "gate_speed": 0.34, "bonus": 40}
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for mode in ["Seconds", "Lives"]:
		for diff in DIFFICULTIES:
			await _check_mode(mode, diff)
	await _check_legacy_quiz_mode()
	if failures.is_empty():
		print("PASS human plane: Seconds 60s and Lives 3 chances across all difficulties; pause, scoring and gate behavior")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL human-plane-modes: ", failure)
		quit(1)


func _check_mode(mode: String, diff: Dictionary) -> void:
	var difficulty := String(diff["name"])
	var label := "%s/%s" % [mode, difficulty]
	var game := GAME_SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var events: Array[String] = []
	game.requested.connect(func(target: String, _payload: Dictionary) -> void: events.append(target))
	game.call("set_context", {"activity": "Human Plane", "game_mode": mode, "topic": "Noun", "difficulty": difficulty})
	await process_frame
	await process_frame
	game.set_process(false)
	var seconds := mode == "Seconds"
	var initial_lives := int(diff["seconds_lives"]) if seconds else 3
	_expect(String(game.get("game_mode")) == mode, label + " canonical mode")
	_expect(bool(game.get("is_seconds_mode")) == seconds, label + " seconds flag")
	_expect(bool(game.get("is_lives_mode")) == not seconds, label + " lives flag")
	_expect(int(game.get("lives")) == initial_lives, label + " initial lives")
	_expect(int(game.get("waves_total")) == int(diff["waves"]), label + " difficulty wave count")
	var start_time := float(game.get("time_remaining"))
	_expect(start_time <= 60.0 and start_time >= 59.75 if seconds else is_zero_approx(start_time), label + " mode timer")
	var payload := game.call("get_context") as Dictionary
	_expect(String(payload.get("game_mode")) == mode and int(payload.get("lives")) == initial_lives, label + " result payload mode and lives")

	# A correct gate keeps the original difficulty scoring formula.
	var lane_data: Dictionary = game.get("round_data")
	var correct_lane := int((lane_data["valid_indices"] as Array)[0])
	var gate_progress: float = game.call("_progress_for_answer_line")
	var chosen_rect: Rect2 = game.call("_gate_rect", correct_lane, gate_progress)
	game.set("plane_x_norm", chosen_rect.get_center().x / game.size.x)
	game.call("_resolve_at_answer_line")
	_expect(int(game.get("correct_count")) == 1, label + " correct hit")
	_expect(int(game.get("score")) == 100 + int(diff["bonus"]), label + " difficulty scoring")
	game.call("_resolve_at_answer_line")
	_expect(int(game.get("attempts")) == 1, label + " idempotent gate resolution")
	game.call("_start_wave")
	game.call("_update_gate_wave", 1.0)
	_expect(is_equal_approx(float(game.get("gate_progress")), float(diff["gate_speed"])), label + " retains difficulty gate speed")

	# In both modes Pause freezes all progress; resume continues the same round.
	var before_pause := float(game.get("time_remaining"))
	game.call("_pause")
	_expect(events.has("pause"), label + " emits native pause")
	game.call("_process", 9.0)
	_expect(is_equal_approx(float(game.get("time_remaining")), before_pause), label + " paused timer does not tick")
	game.call("_resume")
	game.call("_process", 8.0)
	_expect(is_equal_approx(float(game.get("time_remaining")), before_pause - 8.0 if seconds else 0.0), label + " resume respects mode timing")
	_expect(not events.has("results"), label + " no premature results")

	if seconds:
		game.call("_process", 52.0)
		_expect(events.has("results"), label + " finishes at 60 seconds")
		_expect(is_zero_approx(float(game.get("time_remaining"))), label + " timer expires at zero")
	else:
		game.call("_process", 180.0)
		_expect(not events.has("results"), label + " has no 60-second or 180-second timeout")
		# The preceding large delta may itself cross a gate and deduct a life.
		# Reset to the three-life start state for a controlled loss sequence.
		game.set("lives", 3)
		game.call("_start_wave")
		_expect(not events.has("results"), label + " zero time sentinel does not block another wave")
		# Missed gates deduct one life, ending the round at exactly zero lives.
		for remaining in range(2, -1, -1):
			game.set("plane_x_norm", -1.0)
			game.call("_resolve_at_answer_line")
			_expect(int(game.get("lives")) == remaining, label + " life decremented to %d" % remaining)
			if remaining > 0:
				game.call("_start_wave")
		game.call("_start_wave")
		_expect(events.has("results"), label + " last life ends round")
		_expect(int(game.get("score")) >= 0, label + " score remains nonnegative")
	game.queue_free()
	await process_frame
	await process_frame
	print("Verified human-plane ", label)


func _check_legacy_quiz_mode() -> void:
	var game := GAME_SCENE.instantiate() as Control
	root.add_child(game)
	game.call("set_context", {"activity": "Human Plane", "game_mode": "Quiz", "difficulty": "Easy"})
	await process_frame
	await process_frame
	game.set_process(false)
	_expect(String(game.get("game_mode")) == "Seconds", "Legacy Quiz still uses Seconds rules")
	_expect(float(game.get("time_remaining")) <= 60.0 and float(game.get("time_remaining")) >= 59.75, "Legacy Quiz duration is 60 seconds")
	game.queue_free()
	await process_frame
	await process_frame


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
