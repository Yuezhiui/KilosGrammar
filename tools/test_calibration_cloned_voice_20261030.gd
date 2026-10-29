extends SceneTree

# Isolated test for three offline cloned narration cues. No live camera,
# database connection, audio device playback, or TTS calls.
# Godot 4.7.2 --headless --path . --script res://tools/test_calibration_cloned_voice_20261030.gd
const Voice = preload("res://ui/vision/calibration/calibration_voice.gd")
const EXPECTED := {
	"hands_down": "hands_down.wav",
	"plane_left": "plane_left.wav",
	"plane_right": "plane_right.wav",
}
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(Voice.CLONED_CUE_FILES == EXPECTED, "Offline cue names use exact calibration API")
	var helper := Voice.new()
	root.add_child(helper)
	var speaker := helper.get_node_or_null("PromptPlayer") as AudioStreamPlayer
	_check(speaker != null and speaker.bus == "KilosSFX", "One player uses Settings effects bus")
	for cue in EXPECTED:
		var path: String = Voice.VOICE_DIR + String(EXPECTED[cue])
		_check(FileAccess.file_exists(path) and ResourceLoader.exists(path), "Cloned recording exists: " + path)
		var bytes := FileAccess.get_file_as_bytes(path)
		var valid_header := bytes.size() > 100 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" \
			and bytes.slice(8, 12).get_string_from_ascii() == "WAVE"
		_check(valid_header, "Valid RIFF/WAVE file: " + path)
		if bytes.size() >= 36:
			_check(bytes.decode_u16(20) == 1 and bytes.decode_u16(22) == 1
				and bytes.decode_u32(24) == 24000 and bytes.decode_u16(34) == 16,
				"Cloned WAV is 24kHz mono PCM16: " + path)
		var clip := load(path) as AudioStreamWAV
		_check(clip != null, "Godot imports real cloned WAV: " + path)
		if clip != null:
			_check(clip.get_length() > 0.5 and clip.get_length() < 12.0,
				"Short usable cue duration: " + path)
			_check(clip.loop_mode == AudioStreamWAV.LOOP_DISABLED,
				"Cloned cue is not looped: " + path)
			var pcm := clip.get_data()
			var peak := 0
			for offset in range(0, pcm.size() - 1, 2):
				peak = maxi(peak, absi(pcm.decode_s16(offset)))
			_check(peak > 500, "Cloned narration contains real non-silent samples: " + path)
		_check(helper.play_stage("CLONED:" + String(cue), String(cue)), "New cue selects recording: " + String(cue))
		_check(speaker.stream == clip or speaker.stream is AudioStreamWAV,
			"Single player holds cloned audio: " + String(cue))
		_check(not helper.play_stage("CLONED:" + String(cue), String(cue)),
			"Pose flicker cannot replay cloned cue: " + String(cue))
	_check(not helper.play_stage("INVALID", "missing_cue"), "Unknown cue remains silent")
	_check(helper._played_stages.size() == 3, "Exactly three distinct narration stages were stored")
	_check(helper.get_children().size() == 1, "Stage changes never create extra players")

	# A new stage must cancel any unfinished earlier instruction and followup.
	helper.reset_for_new_attempt()
	_check(helper.play_stage("BALLOON:DOWN", "right", "hands_down"), "Directional cue can chain hands-down")
	_check(helper._pending_followup_cue == "hands_down", "Hands-down is queued until MOVE ends")
	var old_callback: Callable = helper._finished_callback
	_check(helper.play_stage("PLANE:LEFT", "plane_left"), "Plane left interrupts prior cue")
	old_callback.call()
	_check(speaker.stream == helper._load_cue("plane_left") and helper._pending_followup_cue.is_empty(),
		"Previous finished callback cannot play obsolete hands-down cue")
	_check(not helper.play_stage("PLANE:LEFT", "plane_left"), "Repeated plane-left stage remains silent")
	_check(helper.play_stage("PLANE:RIGHT", "plane_right"), "Plane right gets its own stage")
	helper.stop()
	_check(speaker.stream == null and helper._played_stages.size() == 3,
		"Stop releases stream while preserving stage deduplication")
	helper.reset_for_new_attempt()
	_check(helper.play_stage("PLANE:LEFT", "plane_left"), "Fresh attempt may reannounce left")
	helper.queue_free()
	await process_frame
	_check(not is_instance_valid(speaker), "Scene exit releases cloned narration player")
	if failures.is_empty():
		print("PASS calibration cloned voice: %d assertions, 3 offline WAVs" % checks)
		quit(0)
	else:
		for issue in failures:
			printerr("CALIBRATION CLONED VOICE: ", issue)
		print("FAIL calibration cloned voice: %d failures / %d assertions" % [failures.size(), checks])
		quit(1)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
