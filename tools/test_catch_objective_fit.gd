extends SceneTree

# Acceptance regression for removing the objective/feedback UI while retaining
# exactly one explicitly authorized recorded voice player for apple feedback.
# Godot 4.7.2 --headless --path . --script res://tools/test_catch_objective_fit.gd
# Keep this legacy filename so existing test runners still exercise the removal.
const SCENE := "res://ui/minigames/catch_word.tscn"
const GAME_SCRIPT := "res://ui/minigames/catch_word.gd"
const REMOVED := ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const MODES := ["Seconds", "Lives"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(875, 500)]

var checks := 0
var scenarios := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var previous_size := root.size
	var packed := load(SCENE) as PackedScene
	_check(packed != null, "Catch scene loads without removed objective nodes")
	_check(FileAccess.file_exists(GAME_SCRIPT), "gameplay source exists for authorized-audio check")
	if packed != null:
		var authored := packed.instantiate() as Control
		_check(authored != null, "serialized editor scene can instantiate")
		if authored != null:
			_assert_removed_nodes_absent(authored, "authored .tscn")
			_assert_no_audio_nodes(authored, "authored .tscn")
			var hud := authored.get_node_or_null("HUDLayer/HUD") as Control
			_check(hud != null and hud.has_node("TitlePlaque")
				and hud.has_node("PromptLabel") and hud.has_node("ScorePlaque"),
				"authored HUD retains title, grammar prompt, and score artwork")
			authored.free()
		for size in VIEWPORTS:
			await _run_viewport(packed, size)
	_assert_authorized_audio_source()
	root.size = previous_size
	if failures.is_empty():
		print("PASS Catch objective removal: %d checks across %d topic/mode/difficulty/screen scenarios" % [checks, scenarios])
		quit(0)
	else:
		for failure in failures.slice(0, mini(failures.size(), 35)):
			push_error("CATCH OBJECTIVE REMOVAL: " + failure)
		if failures.size() > 35:
			print("... %d additional failures suppressed" % (failures.size() - 35))
		print("FAIL Catch objective removal: %d failures in %d checks, %d scenarios" % [failures.size(), checks, scenarios])
		quit(1)


func _run_viewport(packed: PackedScene, physical: Vector2i) -> void:
	root.size = physical
	await process_frame
	await process_frame
	var old_children := root.get_child_count()
	var host := Control.new()
	host.name = "NoObjectiveQAHost"
	host.size = Vector2(physical)
	root.add_child(host)
	var game := packed.instantiate() as Control
	if game == null or game.get_script() == null:
		_fail("%s: game script failed to instantiate" % physical)
		host.queue_free()
		await process_frame
		return
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	game.set_process(false)
	_assert_one_voice_player(game, "%s initial runtime" % physical)
	_assert_removed_nodes_absent(game, "%s initial runtime" % physical)
	_check(not game.has_method("_set_feedback"),
		"%s: removed feedback handler cannot display or play a response" % physical)

	var hud := game.get_node_or_null("HUDLayer/HUD") as Control
	var prompt := game.get_node_or_null("HUDLayer/HUD/PromptLabel") as Label
	var title := game.get_node_or_null("HUDLayer/HUD/TitlePlaque") as TextureRect
	var score := game.get_node_or_null("ScoreDrawLayer/ScoreBottomContainer/ScoreNumber") as Label
	var timer := game.get_node_or_null("HUDLayer/HUD/TimerPlaque") as TextureRect
	var clock := game.get_node_or_null("HUDLayer/HUD/TimeLabel") as Label
	var lives := game.get_node_or_null("HUDLayer/HUD/LivesPlaque") as TextureRect
	if hud == null or prompt == null or title == null or score == null \
			or timer == null or clock == null or lives == null:
		_fail("%s: essential title/prompt/score/mode controls missing" % physical)
		host.queue_free()
		await process_frame
		return

	for difficulty in DIFFICULTIES:
		for mode in MODES:
			for topic in TOPICS:
				game.call("set_context", {
					"activity": "Catch the Word",
					"topic": topic,
					"game_mode": mode,
					"difficulty": difficulty,
					"catch_character": "Boy",
					"catch_map": "Forest",
					"score": 94,
					"lives": 3,
					"time_remaining": 42.0,
				})
				game.set_process(false)
				await process_frame
				scenarios += 1
				var ctx := "%s %s %s %s" % [physical, difficulty, mode, topic]
				_assert_removed_nodes_absent(game, ctx)
				_assert_one_voice_player(game, ctx)
				_check(not game.has_method("_set_feedback"),
					ctx + ": transient feedback handler remains absent")
				var article := "AN" if topic in ["Adjective", "Adverb"] else "A"
				var expected := "WHICH WORD IS %s %s?" % [article, topic.to_upper()]
				_check(prompt.is_visible_in_tree() and prompt.text == expected,
					ctx + ": original dynamic grammar question remains visible")
				_check(title.is_visible_in_tree() and title.texture != null
					and title.texture.resource_path.ends_with("/title_board.png"),
					ctx + ": title PNG remains visible")
				_check(title.get_global_rect().encloses(prompt.get_global_rect().grow(-0.5)),
					ctx + ": question stays inside wooden title")
				_check(score.is_visible_in_tree() and score.text == "94",
					ctx + ": dynamic numeric score remains correct")
				_check(timer.is_visible_in_tree() == (mode == "Seconds")
					and clock.is_visible_in_tree() == (mode == "Seconds"),
					ctx + ": seconds timer appears only in timed mode")
				_check(lives.is_visible_in_tree() == (mode == "Lives"),
					ctx + ": lives PNG appears only in lives mode")
				if mode == "Lives":
					for amount in [3, 2, 1]:
						game.set("lives", amount)
						game.call("_refresh_hud")
						_check(lives.texture != null and lives.texture.resource_path.ends_with(
							"/replacement/lives_state_%d.png" % amount),
							"%s: lives=%d static heart panel preserved" % [ctx, amount])
						_assert_removed_nodes_absent(game, "%s lives=%d" % [ctx, amount])

	host.queue_free()
	await process_frame
	await process_frame
	_check(root.get_child_count() == old_children,
		"%s: removed objective test leaves no scene leaks" % physical)


func _assert_removed_nodes_absent(parent: Node, ctx: String) -> void:
	for removed_name in REMOVED:
		_check(not _contains_node_named(parent, removed_name),
			"%s: no %s node anywhere in the scene" % [ctx, removed_name])


func _contains_node_named(node: Node, target: String) -> bool:
	if node.name == target:
		return true
	for child in node.get_children():
		if _contains_node_named(child, target):
			return true
	return false


func _assert_no_audio_nodes(node: Node, ctx: String) -> void:
	_check(not (node is AudioStreamPlayer or node is AudioStreamPlayer2D
		or node is AudioStreamPlayer3D),
		"%s: no audible AudioStreamPlayer in the game scene (%s)" % [ctx, node.name])
	for child in node.get_children():
		_assert_no_audio_nodes(child, ctx)


func _count_audio_players(node: Node) -> int:
	var count := 1 if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D else 0
	for child in node.get_children():
		count += _count_audio_players(child)
	return count


func _assert_one_voice_player(game: Node, ctx: String) -> void:
	var player := game.get_node_or_null("CatchVoicePlayer") as AudioStreamPlayer
	_check(_count_audio_players(game) == 1 and player != null,
		"%s: one reusable CatchVoicePlayer and no extra audio players" % ctx)
	if player == null:
		return
	_check(player.bus in ["KilosSFX", "Master"],
		"%s: feedback player uses the audio mixer (KilosSFX, Master fallback)" % ctx)
	var streams: Dictionary = game.get("catch_voice_streams")
	_check(streams.size() == 9,
		"%s: nine user-recorded feedback files are available" % ctx)
	for filename in ["GoodJob.mp3", "niceee.mp3", "Awesome.mp3", "Perfect.mp3",
			"You Nailed it.mp3", "Awww.mp3", "Wrong Answer.mp3", "You Missed.mp3",
			"Better Luck.mp3"]:
		_check(streams.get(filename) is AudioStreamMP3,
			"%s: authentic recorded %s MP3 loaded" % [ctx, filename])


func _assert_authorized_audio_source() -> void:
	var script_text := FileAccess.get_file_as_string(GAME_SCRIPT)
	var scene_text := FileAccess.get_file_as_string(SCENE)
	_check(not script_text.is_empty() and not scene_text.is_empty(),
		"scene and script source readable for authorized audio verification")
	_check(not scene_text.contains("AudioStream") and not scene_text.contains("AudioStreamPlayer"),
		"authored Catch scene has no audio resource or playback node")
	_check(script_text.contains('name = "CatchVoicePlayer"')
		and script_text.contains("AudioStreamPlayer.new()")
		and script_text.contains("CATCH_VOICE_DIR")
		and script_text.contains("catch_voice_player.play()"),
		"Catch source explicitly owns one reusable recorded MP3 feedback player")
	_check(not script_text.contains("DisplayServer.tts_speak")
		and not script_text.contains("tts_get_voices_for_language"),
		"Catch source does not use device-dependent synthetic TTS")
	for removed_name in REMOVED:
		_check(not scene_text.contains('name="' + removed_name + '"'),
			"serialized .tscn does not define removed " + removed_name)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)
