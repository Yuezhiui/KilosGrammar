extends SceneTree

# Focused, short Results-transition audio regression; game/UI source READ-ONLY.
# Godot 4.7.2:
# --headless --path . --script res://tools/test_catch_round_end_audio.gd
#
# Catch is freed by the main menu when its requested("results", payload) fires,
# so the user-supplied low-score cue must belong to the *Results* scene.
# Prime confirmed exclusive score <500 cutoff (upper edge of user's 450-500
# preference). Test exact 499 vs 500, and clearly low/high 200 vs 800.

const CATCH_SCENE := "res://ui/minigames/catch_word.tscn"
const RESULTS_SCENE := "res://ui/secondary/results.tscn"
const BAD_END_CLIP := "res://assets/audio/catch_voice/Better Luck.mp3"
const MODES := ["Seconds", "Lives"]
const LOW_SCORE := 200
const HIGH_SCORE := 800
const CONFIRMED_CUTOFF := 500

var checks := 0
var failures: Array[String] = []
var scenarios := 0
var source_clip: AudioStreamMP3
var catch_scene: PackedScene
var results_scene: PackedScene


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_size := root.size
	root.size = Vector2i(1280, 720)
	catch_scene = load(CATCH_SCENE) as PackedScene
	results_scene = load(RESULTS_SCENE) as PackedScene
	_check(catch_scene != null, "Catch the Word scene is loadable")
	_check(results_scene != null, "Results scene is loadable")
	_check(FileAccess.file_exists(BAD_END_CLIP), "actual user-recorded Better Luck.mp3 exists")
	_check(ResourceLoader.exists(BAD_END_CLIP), "user-recorded Better Luck.mp3 is imported")
	source_clip = load(BAD_END_CLIP) as AudioStreamMP3
	_check(source_clip != null and source_clip.get_length() > 0.1,
		"Better Luck.mp3 decodes into a nonempty real MP3 stream")
	var results_script: Script = load("res://ui/secondary/results.gd") as Script
	if results_script != null:
		_check(int(results_script.get("LOW_SCORE_CATCH_THRESHOLD")) == CONFIRMED_CUTOFF,
			"Results uses prime-confirmed exclusive below-500 low-score cutoff")
	if catch_scene != null and results_scene != null and source_clip != null:
		for mode in MODES:
			await _exercise_case(mode, "low_complete", LOW_SCORE)
			await _exercise_case(mode, "high_complete", HIGH_SCORE)
			await _exercise_case(mode, "boundary_below", CONFIRMED_CUTOFF - 1)
			await _exercise_case(mode, "boundary_at", CONFIRMED_CUTOFF)
			await _exercise_case(mode, "manual_exit", LOW_SCORE)
			await _exercise_case(mode, "pause", LOW_SCORE)
		await _assert_other_game_cannot_trigger_catch_voice()
	root.size = original_size
	if failures.is_empty():
		print("PASS Catch round-end Results audio: %d checks, %d short round/route cases" %
			[checks, scenarios])
		quit(0)
	else:
		for i in range(mini(failures.size(), 35)):
			push_error("ROUND END VOICE QA: " + failures[i])
		if failures.size() > 35:
			print("... %d further checks failed" % (failures.size() - 35))
		print("FAIL Catch round-end Results audio: %d failures in %d checks / %d cases" %
			[failures.size(), checks, scenarios])
		quit(1)


func _exercise_case(mode: String, kind: String, starting_score: int) -> void:
	scenarios += 1
	var ctx := "%s %s score=%d" % [mode, kind, starting_score]
	var original_children := root.get_child_count()
	var host := Control.new()
	host.name = "RoundAudioHost"
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var game := catch_scene.instantiate() as Control
	_check(game != null and game.get_script() != null, ctx + ": Catch script loads")
	if game == null:
		host.queue_free()
		await process_frame
		return
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	game.set_context({
		"activity": "Catch the Word",
		"game_mode": mode,
		"topic": "Noun",
		"difficulty": "Normal",
		"catch_character": "Boy",
		"catch_map": "City",
		"score": starting_score,
		"student_id": "AudioTest",
	})
	game.set_process(false)
	var messages: Array[Dictionary] = []
	game.requested.connect(func(target: String, payload: Dictionary) -> void:
		messages.append({"target": target, "payload": payload.duplicate(true)})
	)
	await process_frame
	var catch_player := game.get_node_or_null("CatchVoicePlayer") as AudioStreamPlayer
	_check(catch_player != null and _count_players(game) == 1,
		ctx + ": gameplay has one reusable voice player")

	match kind:
		"low_complete", "high_complete", "boundary_below", "boundary_at":
			game._finish_round()
			game._finish_round()
			_check(messages.size() == 1 and messages[0].get("target", "") == "results",
				ctx + ": duplicate _finish_round calls emit exactly one Results event")
			_check(bool(game.round_completed) and bool(game.round_finished),
				ctx + ": completed round has distinct completed/finished flags")
		"manual_exit":
			game._manual_finish()
			game._manual_finish()
			_check(messages.size() == 1 and messages[0].get("target", "") == "results",
				ctx + ": duplicate manual exits emit Results only once")
			_check(not bool(game.round_completed) and String(game.finish_reason) == "manual_exit",
				ctx + ": manually exited game is NOT a completed round")
		"pause":
			game._speak_catch_feedback(true)
			game._pause()
			_check(messages.size() == 1 and messages[0].get("target", "") == "pause",
				ctx + ": pause emits pause only, never Results")
			_check(not bool(game.round_finished) and not bool(game.round_completed)
				and not bool(game.round_running),
				ctx + ": pause does not finish the round")
			_check(catch_player != null and not catch_player.playing,
				ctx + ": pausing stops Catch spoken feedback")
			game._resume()
			_check(bool(game.round_running) and not bool(game.round_finished),
				ctx + ": resuming does not generate a completed-round result")
		_:
			_fail(ctx + ": unexpected test case kind")

	if messages.is_empty():
		_fail(ctx + ": no Catch request signal was recorded")
		host.queue_free()
		await process_frame
		return
	var payload: Dictionary = messages[0].get("payload", {})
	_check(int(payload.get("score", -1)) == starting_score
		and String(payload.get("game_mode", "")) == mode
		and String(payload.get("activity", "")) == "Catch the Word",
		ctx + ": route payload carries Catch identity, mode and exact score")
	_check(bool(payload.get("round_completed", false)) == (kind in [
			"low_complete", "high_complete", "boundary_below", "boundary_at"]),
		ctx + ": route payload distinguishes completed and exited/paused round")

	# Real main_menu route removes gameplay BEFORE mounting Results. Simulate
	# that lifecycle so the clip must outlive the destroyed Catch voice node.
	game.queue_free()
	await process_frame
	await process_frame
	_check(_count_players(host) == 0, ctx + ": old Catch voice player freed before Results mounts")

	if kind == "pause":
		# There is deliberately no Results screen for a pause signal.
		_check(String(messages[0].get("target")) != "results",
			ctx + ": pause never navigates to game-over Results")
		# If the pause screen offers a View Results action, reusing the pause
		# payload must still NEVER sound like a completed losing round.
		await _assert_results_route(host, payload, ctx + " viewed from pause", false)
	else:
		await _assert_results_route(host, payload, ctx,
			kind in ["low_complete", "boundary_below"])

	if kind == "low_complete" or kind == "boundary_below":
		# New round/retry on the same gameplay instance after a completed
		# event should reset previous score and end flags, with no old audio.
		var retry_game := catch_scene.instantiate() as Control
		host.add_child(retry_game)
		retry_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		retry_game.set_context({
			"activity": "Catch the Word", "topic": "Noun",
			"game_mode": mode, "difficulty": "Normal",
			"catch_character": "Boy", "catch_map": "City",
		})
		retry_game.set_process(false)
		_check(int(retry_game.score) == 0 and not bool(retry_game.round_finished)
			and not bool(retry_game.round_completed),
			ctx + ": retry resets score and end flags for a fresh round")
		var fresh_player := retry_game.get_node_or_null("CatchVoicePlayer") as AudioStreamPlayer
		_check(fresh_player != null and _count_players(retry_game) == 1
			and not fresh_player.playing,
			ctx + ": reset creates one idle Catch voice player, no stale result cue")
		retry_game.queue_free()
		await process_frame
		await process_frame

	host.queue_free()
	await process_frame
	await process_frame
	_check(root.get_child_count() == original_children,
		ctx + ": temporary scene and audio players freed without leaks")


func _assert_other_game_cannot_trigger_catch_voice() -> void:
	var host := Control.new()
	root.add_child(host)
	var ctx := "non-Catch completed low score"
	await _assert_results_route(host, {
		"activity": "Balloon Popping",
		"game_mode": "Lives",
		"score": LOW_SCORE,
		"round_completed": true,
		"completion_reason": "game_over",
	}, ctx, false)
	host.queue_free()
	await process_frame
	await process_frame
	_check(_count_players(root) == 0,
		ctx + ": no leftover audio player after an unrelated game's result")


func _assert_results_route(host: Control, payload: Dictionary,
		ctx: String, expect_low_voice: bool) -> void:
	var results := results_scene.instantiate() as Control
	_check(results != null and results.get_script() != null,
		ctx + ": Results scene script loads after Catch is destroyed")
	if results == null:
		return
	host.add_child(results)
	results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	results.set_context(payload)
	await process_frame
	var visible_score := results.get_node_or_null("%ScoreValue") as Label
	_check(visible_score != null and visible_score.text == str(payload["score"]),
		ctx + ": Results shows final score of completed or manual-exit round")
	var players: Array[AudioStreamPlayer] = []
	_collect_players(results, players)
	_check(players.size() <= 1, ctx + ": Results contains at most ONE audio player")
	var voice := players[0] if not players.is_empty() else null
	if expect_low_voice:
		_check(players.size() == 1,
			ctx + ": completed low-score Results owns one persistent voice player")
		_check(voice != null and voice.name == "LowScoreVoicePlayer",
			ctx + ": voice is the approved Results-owned LowScoreVoicePlayer")
		_check(voice != null and _stream_is_better_luck(voice.stream),
			ctx + ": completed low score selects EXACT Better Luck.mp3")
		_check(voice != null and voice.playing,
			ctx + ": low-score cue is actually playing on Results (not freed Catch)")
	else:
		_check(voice == null or not voice.playing,
			ctx + ": high-score/manual-exit Results must not play low-score cue")
		_check(voice == null or not _stream_is_better_luck(voice.stream),
			ctx + ": high-score/manual-exit Results does not queue Better Luck.mp3")

	# Calling set_context twice with the identical results payload must never
	# trigger a second cue. A deliberately stopped player is a deterministic
	# negative control, avoiding slow, unreliable playback-position timing.
	if expect_low_voice and voice != null:
		voice.stop()
		voice.stream = null
		results.set_context(payload.duplicate(true))
		await process_frame
		_check(not voice.playing and voice.stream == null,
			ctx + ": duplicate identical result payload NEVER restarts spoken cue")
		_check(_count_players(results) == 1,
			ctx + ": duplicate Results refresh reuses one player")

	for target in ["student_setup", "main"]:
		var route_messages: Array[Dictionary] = []
		results.requested.connect(func(next_target: String, next_payload: Dictionary) -> void:
			route_messages.append({"target": next_target, "payload": next_payload})
		, CONNECT_ONE_SHOT)
		# Force a live cue before the navigation call; leaving Results must
		# stop it regardless of how the user got here.
		if voice != null and expect_low_voice:
			voice.stream = source_clip
			voice.play()
		results.call("_request", target)
		_check(route_messages.size() == 1 and route_messages[0].get("target", "") == target,
			"%s: %s button signals correct navigation" % [ctx, target])
		_check(voice == null or not voice.playing,
			"%s: navigating to %s immediately stops old Results audio" % [ctx, target])

	results.queue_free()
	await process_frame
	await process_frame
	_check(_count_players(host) == 0,
		ctx + ": Results transition/exit frees audio player")


func _stream_is_better_luck(stream: AudioStream) -> bool:
	return stream is AudioStreamMP3 and stream.resource_path == BAD_END_CLIP


func _count_players(node: Node) -> int:
	var result := 1 if node is AudioStreamPlayer or node is AudioStreamPlayer2D \
		or node is AudioStreamPlayer3D else 0
	for child in node.get_children():
		result += _count_players(child)
	return result


func _collect_players(node: Node, result: Array[AudioStreamPlayer]) -> void:
	if node is AudioStreamPlayer:
		result.append(node as AudioStreamPlayer)
	for child in node.get_children():
		_collect_players(child, result)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		_fail(description)


func _fail(description: String) -> void:
	failures.append(description)
