extends Node

	## One calibration-and-gameplay music player owned by SceneTree root. Title
	## music remains controlled by MainMenu; it never shares this player.
const MUSIC_PATH := "res://assets/audio/gameplay_music/children_soundtrack_4.wav"
const MUSIC_BUS := "KilosMusic"
const VOICE_BUS := "KilosSFX"
const DUCK_DB := -11.0

var _music_player: AudioStreamPlayer
var _active := false
var _paused := false
var _duck_seconds := 0.0


static func ensure(tree: SceneTree):
	if tree == null or tree.root == null:
		return null
	var existing := tree.root.get_node_or_null("KilosGameAudio")
	var music_script := load("res://ui/shared/game_audio.gd") as Script
	if existing != null and existing.get_script() == music_script:
		return existing
	if existing != null:
		push_error("The SceneTree root already has a non-audio node named KilosGameAudio")
		return null
	var manager := music_script.new() as Node
	manager.name = "KilosGameAudio"
	tree.root.add_child(manager)
	return manager


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(VOICE_BUS)
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "GameplayTrack"
	_music_player.bus = MUSIC_BUS
	_music_player.volume_db = 0.0
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)
	# Decode/import the soundtrack during scene preparation. start_gameplay()
	# is called only at GO, so the large file cannot block the countdown exit.
	_load_music()
	set_process(false)


func start_gameplay() -> void:
	if _active:
		# A paused previous round can enter a fresh Calibration on Restart.
		# Retain playback time, but never leave that new calibration silent.
		if _paused:
			resume_music()
		return
	if not _load_music():
		return
	_active = true
	_paused = false
	_reset_duck()
	_music_player.stream_paused = false
	if DisplayServer.get_name() != "headless":
		_music_player.play()


func pause_music() -> void:
	if not _active or _paused:
		return
	_paused = true
	_music_player.stream_paused = true
	_reset_duck()


func resume_music() -> void:
	if not _active or not _paused:
		return
	_paused = false
	_music_player.stream_paused = false
	if not _music_player.playing and DisplayServer.get_name() != "headless":
		_music_player.play()


func stop_gameplay() -> void:
	_active = false
	_paused = false
	_reset_duck()
	if is_instance_valid(_music_player):
		_music_player.stream_paused = false
		_music_player.stop()


func duck_for_voice(seconds: float = 1.5) -> void:
	if not _active or _paused or not is_instance_valid(_music_player):
		return
	_duck_seconds = maxf(_duck_seconds, clampf(seconds, 0.0, 20.0))
	if _duck_seconds > 0.0:
		_music_player.volume_db = DUCK_DB
		set_process(true)


func is_gameplay_active() -> bool:
	return _active


func is_music_paused() -> bool:
	return _paused


func _process(delta: float) -> void:
	_duck_seconds -= maxf(delta, 0.0)
	if _duck_seconds <= 0.0:
		_reset_duck()


func _load_music() -> bool:
	if _music_player.stream != null:
		return true
	if not ResourceLoader.exists(MUSIC_PATH):
		push_warning("Gameplay soundtrack is missing: " + MUSIC_PATH)
		return false
	var stream := load(MUSIC_PATH) as AudioStream
	if stream == null:
		return false
	# Godot's WAV import defaults to no looping. Loop at the stream level;
	# the finished signal also restarts it for other import representations.
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_player.stream = stream
	return true


func _reset_duck() -> void:
	_duck_seconds = 0.0
	set_process(false)
	if is_instance_valid(_music_player):
		_music_player.volume_db = 0.0


func _on_music_finished() -> void:
	if _active and not _paused and DisplayServer.get_name() != "headless":
		_music_player.play()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var new_index := AudioServer.bus_count
	AudioServer.add_bus(new_index)
	AudioServer.set_bus_name(new_index, bus_name)
	AudioServer.set_bus_send(new_index, "Master")
