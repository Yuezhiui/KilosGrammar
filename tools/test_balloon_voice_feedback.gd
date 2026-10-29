extends SceneTree

# Balloon Popping's current child-friendly WAV feedback, pause, restart and
# exit contracts. No camera, database, or physical microphone is required.
# Run: Godot --headless --path . -s res://tools/test_balloon_voice_feedback.gd
# A display-backed run additionally checks active playback/missed overlap.
const GAME_SCENE := preload("res://ui/minigames/balloon_popping/balloon_popping.tscn")
const KidsVoice := preload("res://ui/shared/kids_voice_feedback.gd")
const VOICE_ROOT := "res://assets/audio/kids_voice/"

var checks := 0
var failures: Array[String] = []
var playback_guard_checked := false


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
	_check(voice != null, "One reusable voice player is present")
	if voice == null:
		game.queue_free()
		await process_frame
		quit(1)
		return
	_check(_voice_player_count(game) == 1, "Balloon owns exactly one voice player")
	_check(voice.bus == "KilosSFX", "Voice uses independent Settings effects bus")
	_check(not voice.playing and voice.stream == null, "Initial voice is idle")

	# All recordings are WAVs, positive and supportive categories are distinct,
	# and missed cues are a subset of age-appropriate coaching.
	var seen := {}
	for filename in KidsVoice.CORRECT + KidsVoice.ENCOURAGEMENT:
		var name := String(filename)
		var path := VOICE_ROOT + name
		_check(not seen.has(name), "Recording appears in only one category: " + name)
		seen[name] = true
		_check(ResourceLoader.exists(path), "Recording imported: " + name)
		var wav := load(path) as AudioStreamWAV
		_check(wav != null and wav.get_length() > 0.2, "Voice WAV decodes: " + name)
	for filename in KidsVoice.MISSED:
		_check(KidsVoice.ENCOURAGEMENT.has(filename), "Missed phrase uses supportive vocabulary")
	_check(seen.size() == 39, "Current source contains exactly 39 voice WAVs")

	# Correct and wrong outcomes replace the selected stream on the SAME player.
	# This bounds voice output even when the next answer arrives immediately.
	game._speak_balloon_feedback(true)
	_check(_stream_in_bank(voice, KidsVoice.CORRECT), "Correct pop chooses a praise WAV")
	var first_positive: AudioStream = voice.stream
	game._speak_balloon_feedback(false)
	_check(_stream_in_bank(voice, KidsVoice.ENCOURAGEMENT), "Wrong pop chooses a coaching WAV")
	_check(voice.stream != first_positive, "Immediate wrong answer replaces previous praise")
	_check(_voice_player_count(game) == 1, "Rapid feedback never creates simultaneous players")
	var first_wrong: AudioStream = voice.stream
	game._speak_balloon_feedback(true)
	_check(_stream_in_bank(voice, KidsVoice.CORRECT), "Immediate correct answer replaces wrong feedback")
	_check(voice.stream != first_wrong, "Rapid positive feedback uses new stream")
	_check(_voice_player_count(game) == 1, "Rapid response still uses exactly one player")

	# In headless mode the implementation deliberately binds WAVs without
	# starting the audio driver. Test missed cooldown independently there;
	# exercise the playing guard only if an actual player reports playing.
	game._stop_voice_feedback()
	_check(voice.stream == null and not voice.playing, "Stop releases the old phrase")
	game._speak_balloon_feedback(false, true)
	_check(_stream_in_bank(voice, KidsVoice.MISSED), "Idle missed shot selects supportive missed WAV")
	var first_missed: AudioStream = voice.stream
	game._stop_voice_feedback()
	game._speak_balloon_feedback(false, true)
	_check(voice.stream == null, "Missed-shot cooldown blocks immediate repetition")
	game._speak_balloon_feedback(true)
	_check(_stream_in_bank(voice, KidsVoice.CORRECT), "Missed cooldown does not block correct answers")
	_check(voice.stream != first_missed, "Correct answers do not replay stale missed voice")

	# Manually start the bound WAV to trigger the actual 'voice.playing' guard.
	# This is the only synthetic playback in headless mode; stop it at once.
	voice.play()
	if voice.playing:
		playback_guard_checked = true
		var during_voice: AudioStream = voice.stream
		game.last_missed_shot_voice_msec = -100000
		game._speak_balloon_feedback(false, true)
		_check(voice.stream == during_voice, "Missed shot never interrupts a currently playing phrase")
		_check(_voice_player_count(game) == 1, "Playing and missed events do not layer voice players")
	else:
		print("NOTE active playback overlap check unavailable on this audio backend")
	voice.stop()
	game._stop_voice_feedback()

	game._speak_balloon_feedback(true)
	_check(_stream_in_bank(voice, KidsVoice.CORRECT), "Pre-pause phrase is present")
	game._pause()
	_check(not game.timer_running, "Pause freezes round timer")
	_check(voice.stream == null and not voice.playing, "Pause stops and releases voice")
	game._speak_balloon_feedback(false)
	_check(voice.stream == null, "Pause rejects new voice feedback")
	game._resume()
	_check(game.timer_running, "Resume restores timer")
	game._speak_balloon_feedback(false)
	_check(_stream_in_bank(voice, KidsVoice.ENCOURAGEMENT), "Voice feedback resumes after pause")

	game.set_context({"game_mode": "Seconds", "time_remaining": 60.0})
	_check(voice.stream == null and not voice.playing, "Context restart clears old phrase")
	_check(game.last_missed_shot_voice_msec < 0, "Context restart clears missed-shot cooldown")
	game._speak_balloon_feedback(false, true)
	_check(_stream_in_bank(voice, KidsVoice.MISSED), "Fresh round can speak missed feedback immediately")
	game._speak_balloon_feedback(true)
	_check(_stream_in_bank(voice, KidsVoice.CORRECT), "Fresh round correct feedback plays")
	# Manual calls and vocabulary exhaustion must not end a 60-second run.
	game._finish_round()
	_check(not game.finishing and game.timer_running and game.time_remaining == 60.0,
		"Premature Results request cannot finish Seconds while global time remains")
	game._process(60.0)
	game.set_process(false)
	_check(game.finishing and game.round_completed and game.time_remaining == 0.0,
		"Actual Seconds timer reaching zero finishes gameplay")
	_check(voice.stream == null and not voice.playing, "Completed round stops and releases voice")
	game._speak_balloon_feedback(false)
	_check(voice.stream == null, "Completed round refuses late feedback")

	game.set_context({"game_mode": "Seconds", "time_remaining": 60.0})
	_check(not game.finishing and game.timer_running, "Context restart enables a new live round")
	game._speak_balloon_feedback(true)
	_check(_stream_in_bank(voice, KidsVoice.CORRECT), "Restarted round voice works with original player")
	_check(_voice_player_count(game) == 1, "Restart never creates another voice player")
	game._exit_to_results()
	_check(game.finishing and not game.round_completed, "Manual results exit is incomplete")
	_check(voice.stream == null and not voice.playing, "Manual results exit releases voice")
	game._speak_balloon_feedback(true)
	_check(voice.stream == null, "Manual results exit rejects late voice")

	game.queue_free()
	await process_frame
	_check(not is_instance_valid(voice), "Leaving game scene frees its voice player")
	await create_timer(0.15).timeout
	if failures.is_empty():
		print("PASS Balloon kids WAV feedback: %d assertions; playback-overlap=%s; backend=%s" %
			[checks, "checked" if playback_guard_checked else "unavailable", DisplayServer.get_name()])
		quit(0)
	else:
		for failure in failures:
			push_error("BALLOON VOICE QA: " + failure)
		print("FAIL Balloon kids WAV feedback: %d errors / %d assertions" % [failures.size(), checks])
		quit(1)


func _voice_player_count(host: Node) -> int:
	var count := 0
	for child in host.get_children():
		if child is AudioStreamPlayer:
			count += 1
	return count


func _stream_in_bank(player: AudioStreamPlayer, bank: Array) -> bool:
	if not is_instance_valid(player) or not (player.stream is AudioStreamWAV):
		return false
	var filename := player.stream.resource_path.get_file()
	return bank.has(filename) and player.stream.resource_path == VOICE_ROOT + filename


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
