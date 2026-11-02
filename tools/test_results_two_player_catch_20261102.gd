extends SceneTree

## Actual editor-authored results scene only; no database or camera.
## Godot --headless --path . --script res://tools/test_results_two_player_catch_20261102.gd
const RESULTS := preload("res://ui/secondary/results/results.tscn")
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var assertions := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)


func _text(panel: Control, name: String) -> String:
	return (panel.get_node("%" + name) as Label).text


func _visible(panel: Control, name: String) -> bool:
	return (panel.get_node("%" + name) as Control).visible


func _payload(first: int, second: int) -> Dictionary:
	return {
		"activity": "Catch the Word", "player_mode": "Multiplayer", "multiplayer": true,
		"student_id": "P1-123", "student_name": "Maria Dela Cruz", "grade_section": "Grade 4 Ruby",
		"player2_student_id": "P2-456", "player2_student_name": "Juan Pedro Santos",
		"player2_grade_section": "Grade 5 Sapphire", "game_style": "Noun",
		"game_mode": "Seconds", "difficulty": "Easy", "round_completed": true,
		"completion_reason": "time_up", "player1_score": first, "score": first,
		"player2_score": second, "player1_lives": 2, "lives": 2, "player2_lives": 1,
		"database_connected": true, "score_saved": true, # P1-only receipt must not assert P2 saved
		"player2_recovery_pending": true, "multiplayer_result_provisional": true
	}


func _case(panel: Control, data: Dictionary, result: String, resolution: Vector2i) -> void:
	panel.set_context(data)
	_check(_visible(panel, "MultiplayerResults"), "%s: multiplayer results board visible" % resolution)
	_check(not _visible(panel, "ScoreCard") and not _visible(panel, "StudentCard") and not _visible(panel, "GameCard"),
		"%s: misleading single-player P1-only cards hidden" % resolution)
	_check(_text(panel, "PlayerOneName") == "Maria Dela Cruz" and _text(panel, "PlayerTwoName") == "Juan Pedro Santos",
		"%s: both player names correctly attributed" % resolution)
	_check(_text(panel, "PlayerOneId") == "P1-123" and _text(panel, "PlayerTwoId") == "P2-456",
		"%s: student identifiers remain independent" % resolution)
	_check(_text(panel, "PlayerOneGrade") == "Grade 4 Ruby" and _text(panel, "PlayerTwoGrade") == "Grade 5 Sapphire",
		"%s: grade and section remain independent" % resolution)
	_check(_text(panel, "PlayerOneScore") == str(data["player1_score"]) and
		_text(panel, "PlayerTwoScore") == str(data["player2_score"]),
		"%s: score boxes use P1 and P2 values, never a total" % resolution)
	_check(_text(panel, "PlayerOneLives") == "HEARTS: 2" and _text(panel, "PlayerTwoLives") == "HEARTS: 1",
		"%s: remaining lives labeled per player" % resolution)
	_check(_text(panel, "CompetitiveOutcome") == result,
		"%s: winner/tie shown from own score" % resolution)
	_check(_text(panel, "CompetitiveSaveNotice").contains("not yet confirmed"),
		"%s: P1-only score_saved + P2 journal pending is NOT database success" % resolution)
	_check(_visible(panel, "GameOverBannerCatch") and not _visible(panel, "GameOverBannerPlane")
		and not _visible(panel, "GameOverBannerBalloon"),
		"%s: original Catch game-over art retained" % resolution)
	_check(not bool(panel.call("should_play_catch_low_score", data)),
		"%s: avoid single-player consolation voice in a competitive game" % resolution)


func _test_viewport(resolution: Vector2i) -> void:
	root.size = resolution
	root.content_scale_size = resolution
	var panel := RESULTS.instantiate() as Control
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	var p1 := _payload(30, 10)
	_case(panel, p1, "PLAYER 1 WINS!", resolution)
	_check((panel.get_node("%PlayerOneCard") as Control).modulate.g > (panel.get_node("%PlayerTwoCard") as Control).modulate.g - 0.0001,
		"%s: winner highlight is applied to Player One" % resolution)
	var p2 := _payload(10, 47)
	_case(panel, p2, "PLAYER 2 WINS!", resolution)
	var tie := _payload(12, 12)
	_case(panel, tie, "IT'S A TIE!", resolution)
	var partial := _payload(24, 31)
	partial["round_completed"] = false
	panel.set_context(partial)
	_check(_text(panel, "CompetitiveOutcome") == "ROUND NOT COMPLETED" and
		_text(panel, "CompetitiveSaveNotice") == "No completed round to save",
		"%s: paused/aborted game must not declare a winner or saved score" % resolution)
	var corrupt := _payload(77, 10)
	corrupt["player2_score"] = "not-a-score"
	panel.set_context(corrupt)
	_check(_text(panel, "PlayerTwoScore") == "—" and
		_text(panel, "CompetitiveOutcome") == "RESULT NOT AVAILABLE",
		"%s: missing/untrusted score does not invent a winner" % resolution)
	var without_identity := _payload(1, 1)
	without_identity.erase("player2_student_name")
	without_identity.erase("player2_lives")
	panel.set_context(without_identity)
	_check(_text(panel, "PlayerTwoName") == "Player 2" and _text(panel, "PlayerTwoLives") == "HEARTS: —",
		"%s: missing identity/lives receive readable neutral fallbacks" % resolution)
	var approved := _payload(31, 34)
	approved["player1_score_saved"] = true
	approved["player2_score_saved"] = true
	panel.set_context(approved)
	_check(_text(panel, "CompetitiveSaveNotice") == "Both scores confirmed saved",
		"%s: two explicit score receipts are required for saved wording" % resolution)
	# Mode switch happens through set_context() without reinstantiating Results.
	var single := {"student_id": "SOLO", "student_name": "Only Player",
		"grade_section": "Grade 6 - Jade", "score": 280, "activity": "Balloon Popping",
		"game_style": "Adjective", "game_mode": "Lives", "difficulty": "Hard",
		"round_completed": true}
	panel.set_context(single)
	_check(not _visible(panel, "MultiplayerResults") and _visible(panel, "ScoreCard") and
		_visible(panel, "StudentCard") and _visible(panel, "GameCard"),
		"%s: original single-player cards return after multiplayer" % resolution)
	_check(_text(panel, "ScoreValue") == "280" and _text(panel, "StudentNameValue") == "Only Player" and
		_visible(panel, "GameOverBannerBalloon"),
		"%s: single-player original fields and banner unchanged" % resolution)
	var actions: Array[String] = []
	var payloads: Array[Dictionary] = []
	panel.requested.connect(func(destination: String, args: Dictionary) -> void:
		actions.append(destination)
		payloads.append(args))
	(panel.get_node("%RetryButton") as Button).pressed.emit()
	(panel.get_node("%MainButton") as Button).pressed.emit()
	_check(actions == ["student_setup", "main"] and payloads.size() == 2 and
		String(payloads[0].get("student_id", "")) == "SOLO",
		"%s: Retry and Main Menu keep original routes/payloads" % resolution)
	var stage := panel.get_node("ResultsStage") as Control
	var comp := panel.get_node("%MultiplayerResults") as Control
	for item in [stage, comp, panel.get_node("%RetryButton") as Control, panel.get_node("%MainButton") as Control]:
		var bounds: Rect2 = (item as Control).get_global_rect()
		_check(bounds.position.x >= -0.1 and bounds.position.y >= -0.1 and
			bounds.end.x <= resolution.x + 0.1 and bounds.end.y <= resolution.y + 0.1,
			"%s: authored panel and Retry/Main stay inside viewport" % resolution)
	panel.queue_free()
	await process_frame
	await process_frame


func _run() -> void:
	for resolution in RESOLUTIONS:
		await _test_viewport(resolution)
	for failure in failures:
		printerr("TWO PLAYER RESULTS QA FAIL: ", failure)
	print("TWO PLAYER RESULTS QA: %s checks=%d failures=%d backend_io=none" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
