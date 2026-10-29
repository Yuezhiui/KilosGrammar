extends SceneTree

# Independent Godot 4.7.2 soundtrack/lifecycle contract. No camera, SQL,
# physical audio output or whole-menu startup. Full scenes are checked by
# test_all_scenes_bruteforce.gd and test_calibration_voice1_recordings_20261029.gd.
const GameAudio = preload("res://ui/shared/game_audio.gd")
const MUSIC_PATH := "res://assets/audio/gameplay_music/children_soundtrack_4.wav"
const EXPECTED_SHA256 := "69A54333464E60D82B56E5954DCA6111F4AB751A60DDC22D887F3920D895DBFE"
const ROUTER_PATH := "res://ui/main_menu/main_menu.gd"
const WRAPPER_PATH := "res://ui/play/gameplay/gameplay.gd"
const VOICE_PATH := "res://ui/vision/calibration/calibration_voice.gd"
const SCENES := [
	"res://ui/minigames/catch_the_word/catch_word.tscn",
	"res://ui/minigames/balloon_popping/balloon_popping.tscn",
	"res://ui/minigames/human_plane/human_plane.tscn",
	"res://ui/vision/calibration/calibration.tscn"
]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(FileAccess.file_exists(MUSIC_PATH), "Original children soundtrack WAV exists offline")
	_check(FileAccess.get_sha256(MUSIC_PATH).to_upper() == EXPECTED_SHA256,
		"Actual sound is byte-identical to user's Downloads WAV")
	_check(ResourceLoader.exists(MUSIC_PATH), "WAV imported into Godot")
	_check(FileAccess.get_file_as_string(MUSIC_PATH + ".import").contains("edit/loop_mode=1"),
		"WAV import recipe requests a full-track loop (runtime also forces loop)")
	var routing := FileAccess.get_file_as_string(ROUTER_PATH)
	var wrapper := FileAccess.get_file_as_string(WRAPPER_PATH)
	var voice := FileAccess.get_file_as_string(VOICE_PATH)
	_check(routing.contains('if route == "calibration":')
		and routing.contains('music.call("start_gameplay")'),
		"MainMenu actually starts soundtrack when entering Calibration")
	_check(routing.contains('elif route == "pause":') and routing.contains('music.call("pause_music")'),
		"MainMenu pauses soundtrack on paused route")
	_check(routing.contains('music.call("stop_gameplay")'),
		"MainMenu stops the track when returning to menus and Results")
	_check(routing.contains('var soundtrack := get_tree().root.get_node_or_null("KilosGameAudio")')
		and routing.contains('soundtrack_player.stream = null'),
		"Quit drains and releases root-owned WAV, not just menu-local audio players")
	var mount_begin := wrapper.find("func _mount_game()")
	var mount_end := wrapper.find("func _start_gameplay_music()", mount_begin)
	var mount_body := wrapper.substr(mount_begin, mount_end - mount_begin) if mount_begin >= 0 and mount_end > mount_begin else ""
	_check(not mount_body.is_empty() and not mount_body.contains('call("stop_gameplay")'),
		"Gameplay wrapper does not kill calibration music when mounting a minigame")
	_check(wrapper.contains('_game_music.call("start_gameplay")'),
		"Standalone gameplay still starts its music at GO")
	_check(voice.contains('_music.call("duck_for_voice"'),
		"Calibration recording ducks the children's soundtrack")

	for path in SCENES:
		_check(ResourceLoader.exists(path), "Real scene resource remains importable: " + path)

	var music := GameAudio.ensure(self) as Node
	_check(is_instance_valid(music) and music.get_parent() == root,
		"Exactly one SceneTree-root music manager")
	var other := GameAudio.ensure(self) as Node
	_check(other == music, "Repeated games reuse the same manager, no duplicates")
	var player := music.get_node_or_null("GameplayTrack") as AudioStreamPlayer
	_check(player != null and player.bus == "KilosMusic" and music.get_child_count() == 1,
		"Exactly one Settings-controlled music player")
	var music_bus_index := AudioServer.get_bus_index("KilosMusic")
	_check(music_bus_index >= 0, "Existing KilosMusic mixer bus is available")
	var original_bus_gain := AudioServer.get_bus_volume_db(music_bus_index) if music_bus_index >= 0 else 0.0
	var original_bus_mute := AudioServer.is_bus_mute(music_bus_index) if music_bus_index >= 0 else false
	_check(not music.is_gameplay_active(), "Not playing in Main Menu before starting")

	# These are the REAL methods MainMenu invokes on each route, not audio mocks.
	music.start_gameplay() # Calibration entry
	_check(music.is_gameplay_active() and not music.is_music_paused(),
		"Calibration starts soundtrack")
	if DisplayServer.get_name() != "headless":
		_check(player.playing and player.get_playback_position() >= 0.0,
			"Native audio output has a live playing soundtrack from Calibration")
	_check(player.stream is AudioStreamWAV, "Imported WAV attached as actual player stream")
	if player.stream is AudioStreamWAV:
		_check((player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"Loop mode is forward, with no silent gap at end")
		_check(player.stream.get_length() >= 30.0, "Full soundtrack preserved")
	var same_stream := player.stream
	var same_id := player.get_instance_id()
	music.start_gameplay() # GO into Catch/Balloon/Human Plane
	_check(music.is_gameplay_active() and player.stream == same_stream
		and player.get_instance_id() == same_id,
		"Entering gameplay cannot restart calibration's soundtrack/player")

	music.duck_for_voice(2.0)
	_check(is_equal_approx(player.volume_db, GameAudio.DUCK_DB),
		"Voice temporarily ducks the soundtrack")
	music._process(3.0)
	_check(is_zero_approx(player.volume_db), "After voice, full music volume returns")
	music.pause_music()
	_check(music.is_music_paused() and (player.stream_paused or DisplayServer.get_name() == "headless"),
		"Pause freezes music (headless has no real playback stream to suspend)")
	music.start_gameplay() # Restart -> Calibration
	_check(music.is_gameplay_active() and not music.is_music_paused()
		and not player.stream_paused and player.get_instance_id() == same_id,
		"Restart into calibration unpauses without duplicating the WAV player")
	music.pause_music()
	music.resume_music()
	_check(music.is_gameplay_active() and not music.is_music_paused(),
		"Resume picks up the existing music")
	music.stop_gameplay()
	_check(not music.is_gameplay_active() and not music.is_music_paused(),
		"Returning to Results, setup or Main Menu stops children's music")
	_check(music_bus_index >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(music_bus_index), original_bus_gain)
		and AudioServer.is_bus_mute(music_bus_index) == original_bus_mute,
		"Music startup, voice duck, pause and stop never override teacher's mixer volume/mute")

	for failure in failures:
		printerr("CHILDREN SOUNDTRACK QA FAIL: ", failure)
	print("CHILDREN SOUNDTRACK CALIBRATION LOOP: %s checks=%d failures=%d scenes=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), SCENES.size()])
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
