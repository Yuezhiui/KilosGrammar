extends SceneTree

# Regression for two-part optional calibration narration:
# Balloon LEFT -> CENTER -> RIGHT; each 3-second BOTH-DOWN stage speaks
# its actual MOVE cue followed by STAY (if supplied), then its separate
# 3-second BOTH-UP stage says raise_both_hands. Never overlap players.
# Run: Godot --headless --path . -s res://tools/test_calibration_voice_followup.gd
# No camera, database, recording creation, TTS, or production changes.
const CalibrationVoice = preload("res://ui/vision/calibration/calibration_voice.gd")

class StubVoice extends "res://ui/vision/calibration/calibration_voice.gd":
	var requested_cues: Array[String] = []
	var missing_cues: Array[String] = []

	# Inert WAV objects verify routing without imitating any human speech.
	# The real helper must still load user-provided files by their exact paths.
	func _load_cue(cue: String) -> AudioStream:
		requested_cues.append(cue)
		if missing_cues.has(cue):
			return null
		return AudioStreamWAV.new()


var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var legacy_clips := {
		"center": "center.wav", "right": "right.wav", "left": "left.wav",
		"hands_down": "hands_down.wav", "raise_hand": "raise_hand.wav",
		"t_pose": "t_pose.wav", "success": "success.wav"
	}
	var supplied_clips := {
		"stay_center": "stay_center.wav", "stay_right": "stay_right.wav",
		"stay_left": "stay_left.wav", "raise_left_hand": "raise_left_hand.wav",
		"raise_right_hand": "raise_right_hand.wav",
		"raise_both_hands": "raise_both_hands.wav"
	}
	_check(CalibrationVoice.CUE_FILES == legacy_clips, "Legacy voice aliases remain backward-compatible")
	_check(CalibrationVoice.SUPPLIED_CUE_FILES == supplied_clips, "All six extra VOICE1 aliases map to exact user recordings")
	_check(not ResourceLoader.exists(CalibrationVoice.VOICE_DIR + "raise_hand.wav"),
		"No generic single-hand WAV has been fabricated")
	var clip_count := 0
	var available := legacy_clips.duplicate()
	available.merge(supplied_clips)
	for cue in available:
		if cue == "hands_down":
			continue # generated offline later; not one of eleven original VOICE1 recordings
		var path: String = CalibrationVoice.VOICE_DIR + String(available[cue])
		if ResourceLoader.exists(path):
			clip_count += 1
			_check(load(path) is AudioStreamWAV, "A supplied file must decode as WAV: " + path)
		else:
			_check(not FileAccess.file_exists(path), "No synthetic fallback file is written: " + path)

	var bus := AudioServer.get_bus_index("KilosSFX")
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, "KilosSFX")
	var original_gain := AudioServer.get_bus_volume_db(bus)
	AudioServer.set_bus_volume_db(bus, -13.0)
	var parent := Node.new()
	root.add_child(parent)
	var absent := StubVoice.new()
	absent.missing_cues.append("hands_down")
	parent.add_child(absent)
	var empty_player := absent.get_node("PromptPlayer") as AudioStreamPlayer
	_check(clip_count == 11, "All 11 original VOICE1 WAVs are present without synthesized stand-ins")
	# An unknown stage must stay silent and cannot conjure missing assets.
	_check(not absent.play_stage("BALLOON:INVALID", "hands_down", "raise_both_hands"),
		"An absent primary hands-down recording cannot conjure bilateral narration")
	_check(empty_player.stream == null and absent._pending_followup_cue.is_empty(),
		"Absent primary never starts a ghost followup")
	empty_player.finished.emit()
	_check(empty_player.stream == null, "Idle finished event does not invent speech")
	absent.queue_free()
	await process_frame
	_check(not is_instance_valid(empty_player), "Scene exit frees optional player")

	var helper := StubVoice.new()
	parent.add_child(helper)
	var player := helper.get_node("PromptPlayer") as AudioStreamPlayer
	_check(player != null and player.bus == "KilosSFX", "Only one player uses KilosSFX")
	_check(helper.get_children().size() == 1, "Exactly one playback node is allocated")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(bus), -13.0), "Settings effects gain is preserved")
	_check(helper.play_stage("BALLOON:LEFT:DOWN", "left", "stay_left"),
		"Balloon starts LEFT with the supplied MOVE LEFT recording")
	_check(helper.requested_cues == ["left"], "STAY LEFT is NOT played before MOVE LEFT finishes")
	_check(helper._pending_followup_cue == "stay_left", "STAY LEFT waits for MOVE LEFT to finish")
	for i in range(30):
		_check(not helper.play_stage("BALLOON:LEFT:DOWN", "left", "stay_left"),
			"Pose flicker #%d cannot restart a spoken stage" % i)
	_check(helper.requested_cues == ["left"], "Pose flicker cannot queue extra clips")
	player.finished.emit()
	_check(helper.requested_cues == ["left", "stay_left"], "Finish chains exactly one STAY LEFT recording")
	_check(player.stream is AudioStreamWAV, "Secondary narration reuses the same WAV player")
	_check(helper._pending_followup_cue.is_empty(), "Pending followup is consumed once")
	player.finished.emit()
	_check(helper.requested_cues.size() == 2, "Second finished event cannot replay STAY LEFT")
	_check(helper.get_children().size() == 1, "No overlapping second audio player is created")

	_check(helper.play_stage("BALLOON:LEFT:UP", "raise_both_hands"),
		"LEFT BOTH-UP phase uses the one exact bilateral VOICE1 clip")
	_check(helper.requested_cues.back() == "raise_both_hands"
		and helper._pending_followup_cue.is_empty(),
		"LEFT UP never uses raise_left_hand or a queued STAY recording")
	_check(not helper.play_stage("BALLOON:LEFT:UP", "raise_both_hands"),
		"Repeated BOTH-UP packets never replay the raised-hands cue")

	_check(helper.play_stage("BALLOON:CENTER:DOWN", "center", "stay_center"),
		"Second floor position is CENTER DOWN after LEFT DOWN and UP")
	var canceled_center_callback: Callable = helper._finished_callback
	_check(helper.requested_cues.back() == "center", "CENTER MOVE is spoken first")
	_check(helper.play_stage("BALLOON:CENTER:UP", "raise_both_hands"),
		"Next CENTER BOTH-UP phase interrupts any pending STAY CENTER")
	var requests_before_stale := helper.requested_cues.size()
	canceled_center_callback.call()
	_check(helper.requested_cues.size() == requests_before_stale,
		"Late CENTER DOWN finished callback cannot play stale STAY CENTER")
	_check(helper._pending_followup_cue.is_empty(), "CENTER BOTH-UP does not queue a STAY prompt")
	player.finished.emit()
	_check(helper.requested_cues.size() == requests_before_stale,
		"BOTH-UP finished signal cannot invoke stale CENTER DOWN followup")
	_check(helper.get_children().size() == 1, "Changing stages never duplicates the player")
	_check(not helper.play_stage("BALLOON:LEFT:DOWN", "left", "stay_left"),
		"Returning to LEFT after CENTER cannot reannounce earlier physical stage")

	_check(helper.play_stage("BALLOON:RIGHT:DOWN", "right", "stay_right"),
		"Third zone is RIGHT DOWN after LEFT and CENTER")
	_check(helper.requested_cues.back() == "right" and helper._pending_followup_cue == "stay_right",
		"RIGHT MOVE queues the supplied STAY RIGHT recording")
	player.finished.emit()
	_check(helper.requested_cues.back() == "stay_right",
		"RIGHT stage plays STAY RIGHT only after MOVE RIGHT finishes")
	_check(helper.play_stage("BALLOON:RIGHT:UP", "raise_both_hands"),
		"Last of six phases requests BOTH HANDS UP, not raise_right_hand")
	_check(helper.requested_cues.back() == "raise_both_hands"
		and helper._pending_followup_cue.is_empty(),
		"RIGHT BOTH-UP narration cannot replay previous STAY cue")
	_check(not helper.play_stage("BALLOON:RIGHT:UP", "raise_both_hands"),
		"Last BOTH-UP stage is deduped even during pose flicker")

	# An unavailable optional STAY WAV must not replay MOVE or leave a ghost.
	helper.missing_cues.append("stay_right")
	_check(helper.play_stage("BALLOON:RIGHT:DOWN:TEST_MISSING_FOLLOWUP", "right", "stay_right"),
		"Primary recorded direction still plays when followup is absent")
	var before_missing := helper.requested_cues.size()
	player.finished.emit()
	_check(helper.requested_cues.size() == before_missing + 1,
		"Missing secondary is attempted only at natural finish")
	_check(helper.requested_cues.back() == "stay_right", "Missing secondary lookup uses exact STAY name")
	_check(player.stream == null, "Missing second clip leaves no stale stream playing")
	player.finished.emit()
	_check(helper.requested_cues.size() == before_missing + 1,
		"Missing secondary does not loop, retry, or invent narration")
	helper.missing_cues.clear()

	# Missing primary MOVE WAV must never skip directly to STAY.
	helper.missing_cues.append("left")
	var requests_before_missing_first := helper.requested_cues.size()
	_check(not helper.play_stage("BALLOON:LEFT:DOWN:TEST_MISSING_PRIMARY", "left", "stay_left"),
		"Missing primary is silent even when followup exists")
	player.finished.emit()
	_check(helper.requested_cues.size() == requests_before_missing_first + 1,
		"Missing primary never schedules followup")
	_check(player.stream == null and helper._pending_followup_cue.is_empty(),
		"Missing primary leaves no active playback")
	helper.missing_cues.clear()

	# Stopping during a speaking DOWN stage (scene leave or transition)
	# cancels STAY, without erasing the stage history or changing effects gain.
	_check(helper.play_stage("BALLOON:RIGHT:DOWN:TEST_EXIT", "right", "stay_right"),
		"New RIGHT DOWN narration begins before scene exit")
	var canceled_exit_callback: Callable = helper._finished_callback
	var before_stop := helper.requested_cues.size()
	helper.stop()
	_check(player.stream == null and helper._pending_followup_cue.is_empty(), "Stop cancels queued phrase")
	canceled_exit_callback.call()
	player.finished.emit()
	_check(helper.requested_cues.size() == before_stop, "Late finished callbacks after exit are ignored")
	_check(not helper.play_stage("BALLOON:RIGHT:DOWN:TEST_EXIT", "right", "stay_right"),
		"Stop does not undo stage dedupe")
	_check(helper.get_children().size() == 1, "Stop retains a single reusable player")

	helper.reset_for_new_attempt()
	_check(helper._played_stages.is_empty(), "Only intentional new attempt resets dedupe")
	_check(helper.play_stage("BALLOON:LEFT:DOWN", "left", "stay_left"),
		"Fresh actual attempt starts again at LEFT DOWN")
	player.finished.emit()
	_check(helper.requested_cues.back() == "stay_left", "Fresh attempt can chain supplied STAY LEFT")
	_check(helper.play_stage("CALIBRATION:SUCCESS", "success"),
		"Success uses optional one-shot cue without secondary")
	var before_success_end := helper.requested_cues.size()
	player.finished.emit()
	_check(helper.requested_cues.size() == before_success_end, "Success never replays or chains a cue")
	_check(not helper.play_stage("CALIBRATION:SUCCESS", "success"),
		"Success cannot be repeated after a single authentic completion")
	_check(helper.play_stage("PLANE:CENTER:T", "t_pose"),
		"Existing two-argument Human Plane narration remains supported")
	helper.queue_free()
	await process_frame
	_check(not is_instance_valid(player), "Exit frees player and cancels any pending callback")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(bus), -13.0), "No helper operation alters Settings bus")
	AudioServer.set_bus_volume_db(bus, original_gain)
	parent.queue_free()
	await process_frame

	if failures.is_empty():
		print("PASS calibration voice followup: %d assertions; genuine VOICE1 clips=%d/11" % [checks, clip_count])
		quit(0)
	else:
		for failure in failures:
			push_error("CALIBRATION VOICE FOLLOWUP: " + failure)
		print("FAIL calibration voice followup: %d/%d assertions failed" % [failures.size(), checks])
		quit(1)


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
