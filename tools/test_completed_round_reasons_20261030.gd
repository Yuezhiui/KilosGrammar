extends SceneTree
## Explicit completion proofs from REAL minigame scenes, not test-only payloads.
## No MainMenu/DB, camera, score queue or student account is ever opened.
## Godot 4.7.2 --headless --path . --script res://tools/test_completed_round_reasons_20261030.gd
const SCENES := {
	"Catch the Word": "res://ui/minigames/catch_the_word/catch_word.tscn",
	"Balloon Popping": "res://ui/minigames/balloon_popping/balloon_popping.tscn",
	"Human Plane": "res://ui/minigames/human_plane/human_plane.tscn",
}
var checks := 0
var issues: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	for activity in SCENES:
		for mode in ["Seconds", "Lives"]:
			await _case(activity, mode, false)
			await _case(activity, mode, true)
	print("COMPLETED ROUND REASONS: %s checks=%d failures=%d / 12 real minigame cases" % [
		"PASS" if issues.is_empty() else "FAIL", checks, issues.size()])
	for issue in issues:
		printerr("COMPLETE-ONLY QA: ", issue)
	quit(0 if issues.is_empty() else 1)

func _case(activity: String, mode: String, finish_normally: bool) -> void:
	var label := "%s / %s / %s" % [activity, mode, "exhausted" if finish_normally else "early"]
	var scene := load(SCENES[activity]) as PackedScene
	_check(scene != null, label + " packed scene available")
	if scene == null:
		return
	var game := scene.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Match the production gameplay wrapper: deliver context immediately after
	# add_child(), BEFORE Human Plane's deferred _ensure_started() executes.
	game.set_context({"activity": activity, "entry_source": "play", "topic": "Noun",
		"game_style": "Noun", "game_mode": mode, "difficulty": "Easy",
		"catch_character": "Bear", "catch_map": "City", "student_id": "QA-ONLY"})
	await process_frame
	game.set_process(false)
	var requested_results: Array[Dictionary] = []
	game.requested.connect(func(target: String, payload: Dictionary) -> void:
		if target == "results":
			requested_results.append(payload.duplicate(true)))
	var before: Dictionary = game.get_context()
	_check(not bool(before.get("round_completed", true)) and String(before.get("completion_reason", "")) == "",
		label + " fresh round has no completion proof")
	if finish_normally:
		if mode == "Seconds":
			game.set("time_remaining", 0.0)
		else:
			game.set("lives" if activity != "Balloon Popping" else "hearts", 0)
		if activity == "Catch the Word":
			game.set("finish_reason", "time_up" if mode == "Seconds" else "lives_empty")
	game.call("_finish_round")
	var after: Dictionary = game.get_context()
	if finish_normally:
		var expected_reason := "time_up" if mode == "Seconds" else "lives_empty"
		_check(bool(after.get("round_completed", false)) and
			String(after.get("completion_reason", "")) == expected_reason,
			label + " actual exhausted round emits exact completion proof: " +
			str([after.get("round_completed"), after.get("completion_reason"), after.get("lives"), after.get("game_mode")]))
		_check(requested_results.size() == 1 and
			String(requested_results[0].get("completion_reason", "")) == expected_reason,
			label + " one genuine Results route contains completion proof")
	else:
		_check(String(after.get("completion_reason", "")) not in ["time_up", "lives_empty"],
			label + " calling finish early does NOT authorize a score save")
		_check(requested_results.is_empty() or
			String(requested_results[0].get("completion_reason", "")) == "manual",
			label + " early results cannot claim a true completion")
	game.queue_free()
	await process_frame
	await process_frame

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		issues.append(what)
