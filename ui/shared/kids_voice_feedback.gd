extends RefCounted

## Recorded student encouragement; one voice per live minigame. A missed
## interaction uses coaching phrases, while a correct answer uses praise.
const GameAudio = preload("res://ui/shared/game_audio.gd")
const VOICE_DIR := "res://assets/audio/kids_voice/"
const CORRECT := [
	"01_Great_job.wav", "02_Awesome_work.wav", "03_You_got_it.wav",
	"04_Well_done.wav", "05_Amazing.wav", "06_Thats_correct.wav",
	"07_Fantastic.wav", "08_Excellent_work.wav", "09_Youre_a_star.wav",
	"10_Super_job.wav", "11_You_nailed_it.wav", "12_Brilliant.wav",
	"13_Nice_thinking.wav", "14_Wonderful.wav", "15_Keep_it_up.wav"
]
const ENCOURAGEMENT := [
	"01_Good_try.wav", "02_Almost_there.wav", "03_Keep_trying.wav",
	"04_Not_quite.wav", "05_Nice_effort.wav", "06_You_can_do_it.wav",
	"07_Dont_give_up.wav", "08_Keep_learning.wav", "09_Thats_okay.wav",
	"10_Try_the_next_one.wav", "11_Keep_going.wav", "12_Youre_getting_better.wav",
	"13_Every_try_counts.wav", "14_Lets_keep_practicing.wav",
	"15_Give_it_another_go.wav", "16_Nice_try_superstar.wav",
	"17_Oops_Keep_going.wav", "18_Youll_get_the_next_one.wav",
	"19_So_close.wav", "20_Watch_for_the_next_one.wav",
	"21_Stay_focused.wav", "22_You_can_catch_the_next_one.wav",
	"23_Keep_your_eyes_open.wav", "24_Lets_try_the_next_one.wav"
]
const MISSED := [
	"01_Good_try.wav", "03_Keep_trying.wav", "06_You_can_do_it.wav",
	"07_Dont_give_up.wav", "09_Thats_okay.wav", "10_Try_the_next_one.wav",
	"11_Keep_going.wav", "17_Oops_Keep_going.wav", "19_So_close.wav",
	"20_Watch_for_the_next_one.wav", "21_Stay_focused.wav",
	"23_Keep_your_eyes_open.wav", "24_Lets_try_the_next_one.wav"
]

var _player: AudioStreamPlayer
var _music
var _clips: Dictionary = {}
var _last_file := ""
var _random := RandomNumberGenerator.new()


func setup(host: Node) -> void:
	if is_instance_valid(_player) or not is_instance_valid(host):
		return
	_random.randomize()
	_music = GameAudio.ensure(host.get_tree())
	_player = AudioStreamPlayer.new()
	_player.name = "KidsVoicePlayer"
	_player.bus = "KilosSFX" if AudioServer.get_bus_index("KilosSFX") >= 0 else "Master"
	_player.volume_db = 0.0
	host.add_child(_player)


func play_correct() -> bool:
	return _play(CORRECT)


func play_wrong() -> bool:
	return _play(ENCOURAGEMENT)


func play_missed() -> bool:
	return _play(MISSED)


func stop() -> void:
	if is_instance_valid(_player):
		_player.stop()
		_player.stream = null


func release() -> void:
	stop()
	_clips.clear()
	_music = null


func get_voice_player() -> AudioStreamPlayer:
	return _player if is_instance_valid(_player) else null


func _play(options: Array) -> bool:
	if not is_instance_valid(_player) or options.is_empty():
		return false
	# A new answer immediately updates the feedback. The same bounded player
	# replaces any earlier phrase rather than playing overlapping voices.
	var index := _random.randi_range(0, options.size() - 1)
	if options.size() > 1 and options[index] == _last_file:
		index = (index + 1) % options.size()
	var filename: String = options[index]
	var path := VOICE_DIR + filename
	if not _clips.has(filename):
		if not ResourceLoader.exists(path):
			push_warning("Kids voice recording missing: " + path)
			return false
		_clips[filename] = load(path) as AudioStream
	var clip := _clips[filename] as AudioStream
	if clip == null:
		return false
	_last_file = filename
	_player.stop()
	_player.stream = clip
	if DisplayServer.get_name() != "headless":
		if is_instance_valid(_music):
			_music.duck_for_voice(clip.get_length() + 0.15)
		_player.play()
	return true
