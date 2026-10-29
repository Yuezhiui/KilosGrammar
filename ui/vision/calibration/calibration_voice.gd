extends Node

## Optional recorded instructions for Play and Tutorial calibration.
## The WAV files are supplied by the user, not generated at runtime. A missing
## file is intentionally silent; visual pose instructions still work normally.
const VOICE_DIR := "res://assets/audio/calibration_voice/"
const CUE_FILES := {
	"center": "center.wav",
	"right": "right.wav",
	"left": "left.wav",
	"hands_down": "hands_down.wav",
	"raise_hand": "raise_hand.wav",
	"t_pose": "t_pose.wav",
	"success": "success.wav"
}
# Additional exact recordings supplied in Downloads/VOICE1 on 2026-10-29.
# These are separate meanings: a STAY instruction must never be substituted
# for MOVE, and "raise both hands" is not the Balloon one-hand gesture.
const SUPPLIED_CUE_FILES := {
	"stay_center": "stay_center.wav",
	"stay_right": "stay_right.wav",
	"stay_left": "stay_left.wav",
	"raise_left_hand": "raise_left_hand.wav",
	"raise_right_hand": "raise_right_hand.wav",
	"raise_both_hands": "raise_both_hands.wav"
}
const EFFECTS_BUS := "KilosSFX"
const GameAudio = preload("res://ui/shared/game_audio.gd")

var _player: AudioStreamPlayer
var _played_stages: Dictionary = {}
var _streams: Dictionary = {}
var _pending_followup_cue := ""
var _finished_callback: Callable
var _stage_generation := 0
var _music: Node


func _ready() -> void:
	_music = GameAudio.ensure(get_tree())
	# Calibration can be entered directly in tests without visiting Main Menu.
	# Keep Settings' existing bus gain and mute state unchanged.
	if AudioServer.get_bus_index(EFFECTS_BUS) < 0:
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, EFFECTS_BUS)
		AudioServer.set_bus_send(index, "Master")
	_player = AudioStreamPlayer.new()
	_player.name = "PromptPlayer"
	_player.bus = EFFECTS_BUS
	_player.volume_db = 0.0
	add_child(_player)


## Announce one cue on a unique verified calibration stage/phase boundary.
## stage_id must identify a genuine step, such as "RIGHT:DOWN". Repeating an
## ID after a pose flicker, brief camera loss or instruction refresh stays
## silent. Explicit reset_for_new_attempt() enables a fresh attempt.
## An optional followup_cue plays AFTER the first recording finishes naturally
## (for example, "right" then "hands_down" on Balloon's RIGHT:DOWN phase).
## No clip, no synthetic speech; if the first clip is absent, no second clip
## is scheduled. True means the first recording was assigned; false means
## silent/duplicate. A new stage cancels any pending followup immediately.
func play_stage(stage_id: String, cue: String, followup_cue: String = "") -> bool:
	if not is_instance_valid(_player) or stage_id.is_empty() or not _has_cue(cue):
		return false
	if _played_stages.has(stage_id):
		return false
	_played_stages[stage_id] = true
	# One voice player: switching stages stops the previous instruction before
	# starting the next, and a missing recording never leaves stale speech.
	stop()
	var stream := _load_cue(cue)
	if stream == null:
		return false
	_player.stream = stream
	if not followup_cue.is_empty() and _has_cue(followup_cue):
		_pending_followup_cue = followup_cue
		# Only the natural end of THIS primary clip may start its followup.
		# A token and disconnected listener protect against stale queued signals
		# after a stage change, skipped instruction or scene transition.
		_finished_callback = Callable(self, "_on_primary_finished").bind(_stage_generation)
		_player.finished.connect(_finished_callback, CONNECT_ONE_SHOT)
	if DisplayServer.get_name() != "headless":
		if is_instance_valid(_music):
			_music.call("duck_for_voice", stream.get_length() + 0.15)
		_player.play()
	return true


## Stops an in-progress phrase but preserves stage de-duplication. Call when
## leaving calibration, pausing its flow or before transferring to gameplay.
func stop() -> void:
	_stage_generation += 1
	_pending_followup_cue = ""
	if is_instance_valid(_player) and _finished_callback.is_valid() \
			and _player.finished.is_connected(_finished_callback):
		_player.finished.disconnect(_finished_callback)
	_finished_callback = Callable()
	if is_instance_valid(_player):
		_player.stop()
		_player.stream = null


func _on_primary_finished(generation: int) -> void:
	if generation != _stage_generation or not is_instance_valid(_player):
		return
	var cue := _pending_followup_cue
	_pending_followup_cue = ""
	_finished_callback = Callable()
	if cue.is_empty():
		return
	var next_stream := _load_cue(cue)
	# The previous instruction is finished. Never leave it queued or replay
	# stale audio when an optional followup file has not been supplied.
	_player.stop()
	_player.stream = next_stream
	if next_stream != null and DisplayServer.get_name() != "headless":
		if is_instance_valid(_music):
			_music.call("duck_for_voice", next_stream.get_length() + 0.15)
		_player.play()


## Call only when intentionally starting a NEW calibration attempt. Do not
## reset on pose flicker or brief camera dropout, which would repeat narration.
func reset_for_new_attempt() -> void:
	stop()
	_played_stages.clear()


func _has_cue(cue: String) -> bool:
	return CUE_FILES.has(cue) or SUPPLIED_CUE_FILES.has(cue)


func _load_cue(cue: String) -> AudioStream:
	if _streams.has(cue):
		return _streams[cue] as AudioStream
	var filename := String(CUE_FILES.get(cue, SUPPLIED_CUE_FILES.get(cue, "")))
	if filename.is_empty():
		return null
	var file_path: String = VOICE_DIR + filename
	if not ResourceLoader.exists(file_path):
		return null
	var stream := load(file_path) as AudioStreamWAV
	if stream == null:
		push_warning("Calibration narration must be a WAV: " + file_path)
		return null
	# Narration is always one-shot, including after Godot imports external WAVs.
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_streams[cue] = stream
	return stream


func _exit_tree() -> void:
	stop()
	_music = null
	_played_stages.clear()
	_streams.clear()
