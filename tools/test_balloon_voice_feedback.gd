extends SceneTree

# Voice playback/lifecycle regression for Balloon Popping.
# Godot --headless --path . --script res://tools/test_balloon_voice_feedback.gd

const GAME_SCENE := preload("res://ui/minigames/balloon_popping.tscn")
const VOICE_ROOT := "res://assets/audio/catch_voice/"
const POSITIVE_CUES := ["GoodJob.mp3", "niceee.mp3", "Awesome.mp3", "Perfect.mp3", "You Nailed it.mp3"]
const NEGATIVE_CUES := ["Awww.mp3", "Wrong Answer.mp3", "You Missed.mp3"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game := GAME_SCENE.instantiate() as Control
	_check(game != null, "Balloon Popping scene instantiates")
	if game == null:
		quit(1)
		return
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)

	var voice := game.get_node_or_null("BalloonVoicePlayer") as AudioStreamPlayer
	_check(voice != null, "One persistent voice player is present")
	if voice == null:
		game.queue_free()
		await process_frame
		quit(1)
		return
	_check(game.get_children().filter(func(child): return child is AudioStreamPlayer).size() == 1,
		"Voice uses exactly one audio player")
	_check(voice.bus == ("KilosSFX" if AudioServer.get_bus_index("KilosSFX") >= 0 else "Master"),
		"Voice routes through KilosSFX with Master fallback")
	_check(game.balloon_voice_streams.size() == POSITIVE_CUES.size() + NEGATIVE_CUES.size(),
		"All recorded Catch feedback phrases are cached")

	game._speak_balloon_feedback(true)
	_check(voice.playing and voice.stream != null
		and VOICE_ROOT + voice.stream.resource_path.get_file() == voice.stream.resource_path
		and POSITIVE_CUES.has(voice.stream.resource_path.get_file()), "Correct pop selects a positive Catch voice cue")
	game._speak_balloon_feedback(false)
	_check(voice.playing and voice.stream != null and NEGATIVE_CUES.has(voice.stream.resource_path.get_file()),
		"Wrong pop switches the same player to a negative Catch cue")
	var negative_stream := voice.stream
	game._speak_balloon_feedback(false, true)
	_check(voice.stream == negative_stream, "Immediate missed shot does not cut off ongoing speech")

	game._stop_voice_feedback()
	game._speak_balloon_feedback(false, true)
	_check(voice.playing and voice.stream != null and voice.stream.resource_path.get_file() == "You Missed.mp3",
		"An idle missed shot plays the recorded You Missed phrase")
	game._stop_voice_feedback()
	game._speak_balloon_feedback(false, true)
	_check(voice.stream == null, "Missed shot cooldown prevents immediate repeated announcements")

	game._speak_balloon_feedback(true)
	game._pause()
	_check(voice.stream == null and not voice.playing, "Pausing stops and releases the playing stream")
	game._resume()
	game._speak_balloon_feedback(false)
	game.set_context({"game_mode": "Seconds", "time_remaining": 60.0})
	_check(voice.stream == null and not voice.playing, "Context restart stops previous feedback")
	game._speak_balloon_feedback(true)
	game._finish_round()
	_check(voice.stream == null and not voice.playing, "Round end stops and releases voice")
	game.set_context({"game_mode": "Seconds", "time_remaining": 60.0})
	game._speak_balloon_feedback(true)
	game._exit_to_results()
	_check(voice.stream == null and not voice.playing, "Manual results exit stops and releases voice")
	game.queue_free()
	await process_frame
	_check(not is_instance_valid(voice), "Exiting scene frees persistent audio player")
	# Allow the round's SceneTreeTimers and deferred resource releases to settle.
	await create_timer(1.0).timeout
	await process_frame

	if failures.is_empty():
		print("PASS Balloon voice feedback: %d assertions" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("BALLOON VOICE QA: " + failure)
		print("FAIL Balloon voice feedback: %d errors / %d assertions" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
