extends SceneTree

# Isolated QA for optional calibration WAVs. Does not create audio assets,
# synthesize speech, use a camera or touch the database.
# Godot --headless --path . -s res://tools/test_calibration_voice_optional.gd
const CalibrationVoice = preload("res://ui/vision/calibration/calibration_voice.gd")

class TestVoice extends "res://ui/vision/calibration/calibration_voice.gd":
	var cue_requests: Array[String] = []

	# An empty in-memory stream tests stage wiring without a supplied recording.
	# Actual gameplay uses the unmodified file-based _load_cue() implementation.
	func _load_cue(cue: String) -> AudioStream:
		cue_requests.append(cue)
		return AudioStreamWAV.new()


var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var expected := {
		"center": "center.wav", "right": "right.wav", "left": "left.wav",
		"hands_down": "hands_down.wav", "raise_hand": "raise_hand.wav",
		"t_pose": "t_pose.wav", "success": "success.wav"
	}
	_check(CalibrationVoice.CUE_FILES == expected, "All seven optional filenames use the exact public API")
	var available_count := 0
	for cue in expected:
		var audio_path: String = "res://assets/audio/calibration_voice/" + expected[cue]
		if ResourceLoader.exists(audio_path):
			available_count += 1
			_check(load(audio_path) is AudioStreamWAV, "Supplied narration has WAV format: " + audio_path)
		else:
			_check(not FileAccess.file_exists(audio_path), "Missing narration is left absent: " + audio_path)

	var host := Node.new()
	root.add_child(host)
	var effects_bus := AudioServer.get_bus_index("KilosSFX")
	if effects_bus < 0:
		AudioServer.add_bus()
		effects_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(effects_bus, "KilosSFX")
	var initial_bus_db := AudioServer.get_bus_volume_db(effects_bus)
	AudioServer.set_bus_volume_db(effects_bus, -14.0)
	var voice := CalibrationVoice.new() as Node
	host.add_child(voice)
	var player := voice.get_node_or_null("PromptPlayer") as AudioStreamPlayer
	_check(player != null, "Exactly one voice player is allocated when the scene mounts")
	_check(voice.get_children().size() == 1, "Voice helper owns only one player")
	_check(player != null and player.bus == "KilosSFX", "Voice player routes through KilosSFX")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(effects_bus), -14.0), "Audio helper preserves Settings bus gain")
	_check(player != null and player.stream == null and not player.playing, "No narration starts during intro")
	_check(not voice.play_stage("UNKNOWN", "bogus"), "Unknown phrase is gracefully rejected")
	_check(voice._played_stages.is_empty(), "Unknown phrase does not consume stage")

	for cue in expected:
		var event: String = "STAGE:" + cue
		var available: bool = ResourceLoader.exists(CalibrationVoice.VOICE_DIR + expected[cue])
		_check(voice.play_stage(event, cue) == available, "Cue is silent unless supplied: " + cue)
		_check(not voice.play_stage(event, cue), "Cue is not retried on pose flicker: " + cue)
		_check((player.stream is AudioStreamWAV) == available, "Only available WAVs are selected: " + cue)
	_check(voice._played_stages.size() == 7, "All seven missing events are remembered once")
	_check(not voice.play_stage("", "center"), "Empty stage ID is rejected")
	_check(not voice.play_stage("STAGE:center", "right"), "Same event ID cannot play a different voice")
	voice.stop()
	_check(voice._played_stages.size() == 7, "Stop preserves de-duplication state")
	voice.reset_for_new_attempt()
	_check(voice._played_stages.is_empty(), "Explicit new attempt permits narration again")
	_check(voice.play_stage("STAGE:center", "center") == ResourceLoader.exists(CalibrationVoice.VOICE_DIR + "center.wav"), "New attempt retries optional recording once")
	voice.queue_free()
	await process_frame
	_check(not is_instance_valid(player), "Leaving calibration frees the voice player")
	AudioServer.set_bus_volume_db(effects_bus, initial_bus_db)

	# Exercise the SAME public stage API with an inert test stream returned by a
	# subclass. This proves one-shot routing if the seven WAVs arrive later.
	var simulated := TestVoice.new()
	host.add_child(simulated)
	var simulated_player := simulated.get_node("PromptPlayer") as AudioStreamPlayer
	_check(simulated.play_stage("CENTER:DOWN", "center"), "First physical stage can bind a WAV stream")
	_check(simulated_player.stream is AudioStreamWAV, "Optional stage selects WAV resource")
	_check(simulated.cue_requests.size() == 1, "Physical stage starts one cue")
	for i in range(25):
		_check(not simulated.play_stage("CENTER:DOWN", "center"), "Pose flicker #%d does not replay" % i)
	_check(simulated.cue_requests.size() == 1, "Repeated frames never request additional narration")
	_check(simulated.play_stage("CENTER:UP", "raise_hand"), "New pose phase can play its own cue")
	_check(simulated_player.stream is AudioStreamWAV, "Second pose phase replaces previous stream")
	_check(simulated.cue_requests.size() == 2, "Two different pose phases request exactly two cues")
	_check(not simulated.play_stage("CENTER:DOWN", "center"), "Returning to earlier stage does not replay after flicker")
	_check(simulated.play_stage("RIGHT:DOWN", "right"), "New floor position can announce direction")
	_check(simulated.play_stage("RIGHT:UP", "raise_hand"), "Hand-raising phase can announce separately")
	_check(simulated.play_stage("LEFT:DOWN", "left"), "Left direction can announce separately")
	_check(simulated.play_stage("PLANE:T", "t_pose"), "Human Plane can announce T-pose")
	_check(simulated.play_stage("SUCCESS", "success"), "Calibration success can announce once")
	_check(not simulated.play_stage("SUCCESS", "success"), "Success does not repeat")
	_check(simulated.cue_requests.size() == 7, "Exactly seven unique events requested narration")
	_check(simulated.get_children().size() == 1, "Stage changes never create another player")
	simulated.stop()
	_check(simulated_player.stream == null, "Route exit immediately clears pending voice")
	_check(not simulated.play_stage("SUCCESS", "success"), "Stop does not permit a duplicate success")
	simulated.reset_for_new_attempt()
	_check(simulated.play_stage("CENTER:DOWN", "center"), "Explicit fresh calibration permits new first cue")
	simulated.queue_free()
	await process_frame
	_check(not is_instance_valid(simulated_player), "Scene exit frees the single audio player")
	host.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS optional calibration voice: %d assertions, %d/7 supplied WAVs, no generated narration" % [checks, available_count])
		quit(0)
	else:
		for failure in failures:
			push_error("CALIBRATION VOICE QA: " + failure)
		print("FAIL optional calibration voice: %d errors / %d assertions" % [failures.size(), checks])
		quit(1)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
