extends SceneTree

# Godot 4.7.2 runtime test for the user-supplied Wii Fit title music and
# original recorded Catch the Word spoken feedback.
# Run with --headless for resource/wiring tests; repeat without --headless
# for Windows GUI/audio-device routing. Neither run can certify audibility.

const MENU_SCENE: PackedScene = preload("res://main_menu.tscn")
const CATCH_SCENE: PackedScene = preload("res://ui/minigames/catch_word.tscn")
const TITLE_MUSIC_PATH := "res://assets/audio/user_provided/wii_fit_user_settings.mp3"
const CLIP_DIR := "res://assets/audio/catch_voice/"
const GOOD_CLIPS := [
    "GoodJob.mp3", "niceee.mp3", "Awesome.mp3",
    "Perfect.mp3", "You Nailed it.mp3"
]
const BAD_CLIPS := [
    "Awww.mp3", "Wrong Answer.mp3", "You Missed.mp3",
    "Better Luck.mp3"
]

var checks := 0
var failures: Array[String] = []
var voice_samples := 0


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var original_size := root.size
    root.size = Vector2i(1280, 720)
    await _test_imported_clips()
    await _test_main_menu_music()
    for mode in ["Seconds", "Lives"]:
        await _test_catch_voice(mode)
    root.size = original_size
    # Drain audio callbacks after all menu/game fixtures have been freed.
    await create_timer(0.5).timeout
    if failures.is_empty():
        print("PASS Catch recorded audio: %d checks, %d voice choices verified; backend=%s" %
            [checks, voice_samples, DisplayServer.get_name()])
        print("NOTE play() and stream state are tested, but audible speaker output requires a listener.")
        quit(0)
    else:
        for failure in failures:
            push_error("CATCH AUDIO QA: " + failure)
        print("FAIL Catch recorded audio: %d failures across %d checks; backend=%s" %
            [failures.size(), checks, DisplayServer.get_name()])
        quit(1)


func _test_imported_clips() -> void:
    _check(ResourceLoader.exists(TITLE_MUSIC_PATH), "User-supplied Wii Fit title MP3 is imported")
    _check(FileAccess.file_exists(TITLE_MUSIC_PATH), "User-supplied title MP3 exists as a file")
    var song := load(TITLE_MUSIC_PATH) as AudioStreamMP3
    _check(song != null, "Title music decodes as a real AudioStreamMP3")
    if song != null:
        _check(song.get_length() > 30.0, "Title music has nonempty musical duration")
        print("MUSIC source=%s duration=%.2fs size=%d bytes" %
            [song.resource_path, song.get_length(), FileAccess.get_file_as_bytes(TITLE_MUSIC_PATH).size()])

    for file_name in GOOD_CLIPS + BAD_CLIPS:
        var path: String = CLIP_DIR + String(file_name)
        _check(FileAccess.file_exists(path), "Recorded voice file present: " + file_name)
        _check(ResourceLoader.exists(path), "Recorded voice MP3 imported: " + file_name)
        var clip := load(path) as AudioStreamMP3
        _check(clip != null, "Voice clip decodes to AudioStreamMP3: " + file_name)
        if clip != null:
            _check(clip.get_length() > 0.1, "Recorded voice has nonzero duration: " + file_name)
            _check(not clip.loop, "Recorded phrase is one-shot, not a loop: " + file_name)
            print("VOICE clip=%s length=%.2fs" % [file_name, clip.get_length()])


func _test_main_menu_music() -> void:
    var app := MENU_SCENE.instantiate() as Control
    _check(app != null and app.get_script() != null, "Main menu instantiates with gameplay script")
    if app == null:
        return
    root.add_child(app)
    await process_frame
    await process_frame
    var player := app.get_node_or_null("TitleMusic") as AudioStreamPlayer
    _check(player != null, "Main menu creates its TitleMusic AudioStreamPlayer")
    if player != null:
        _check(player == app.get("title_music_player"), "Menu stores the same title music player")
        _check(player.stream is AudioStreamMP3, "Menu plays MP3 rather than previous OGG")
        if player.stream is AudioStreamMP3:
            _check(player.stream.resource_path == TITLE_MUSIC_PATH,
                "Menu uses exact user-selected Wii Fit title music file")
            _check((player.stream as AudioStreamMP3).loop, "Wii Fit title music loops indefinitely")
            _check(player.stream.get_length() > 30.0, "Menu playback stream has musical duration")
        _check(player.bus == "KilosMusic", "Title music routes to the independently adjustable Music bus")
        _check(AudioServer.get_bus_index("KilosMusic") >= 0, "Title music's mixer bus exists")
        _check(player.playing, "Main menu issued music playback at startup")
        _check(player.volume_db > -80.0, "Title music volume is not set to silent")
    # The intro coroutine runs for 1.12 seconds after _ready().
    await create_timer(1.3).timeout
    if player != null:
        _check(player.playing, "Title music continues playing after the menu introduction")
        player.stop()
    _stop_audio_tree(app)
    app.queue_free()
    await process_frame
    await process_frame


func _test_catch_voice(mode: String) -> void:
    var host := Control.new()
    host.size = Vector2(1280.0, 720.0)
    root.add_child(host)
    var game := CATCH_SCENE.instantiate() as Control
    _check(game != null and game.get_script() != null, "%s: Catch scene script loads" % mode)
    if game == null:
        host.queue_free()
        return
    host.add_child(game)
    game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    await process_frame
    game.set_process(false)
    game.set_context({
        "topic": "Noun", "difficulty": "Normal",
        "game_mode": mode, "catch_character": "Boy", "catch_map": "City"
    })
    game.set_process(false)
    await process_frame

    var player := game.get_node_or_null("CatchVoicePlayer") as AudioStreamPlayer
    _check(player != null, "%s: the CatchVoicePlayer exists" % mode)
    if player == null:
        host.queue_free()
        await process_frame
        return
    _check(player.bus == "KilosSFX" and AudioServer.get_bus_index("KilosSFX") >= 0,
        "%s: voice uses the effects volume bus" % mode)
    _check(player.volume_db > -65.0, "%s: voice output volume is above mute" % mode)
    _check(not player.stream_paused, "%s: voice playback is not paused" % mode)
    _check(_count_audio_players(game) == 1, "%s: exactly one reusable voice player exists" % mode)

    var initial_score: int = game.score
    var initial_attempts: int = game.attempts
    var initial_lives: int = game.lives
    game._handle_catch({"word": "apple", "matching": true})
    _check(game.attempts == initial_attempts + 1 and game.correct_count == 1,
        "%s: correct catch registers one answer" % mode)
    _check(game.score > initial_score, "%s: correct catch scores points" % mode)
    _check(player.playing, "%s: correct catch triggers recorded speech playback" % mode)
    _check(_stream_in_group(player.stream, GOOD_CLIPS),
        "%s: correct catch chooses only a positive recorded phrase (got %s)" %
            [mode, _stream_path(player.stream)])
    _check(game.lives == initial_lives, "%s: correct catch leaves lives intact" % mode)
    voice_samples += 1

    var score_after_correct: int = game.score
    var attempts_after_correct: int = game.attempts
    game._handle_catch({"word": "quickly", "matching": false})
    _check(game.attempts == attempts_after_correct + 1, "%s: wrong catch registers one answer" % mode)
    _check(game.score == score_after_correct, "%s: wrong catch never awards points" % mode)
    _check(player.playing, "%s: wrong catch triggers recorded speech playback" % mode)
    _check(_stream_in_group(player.stream, BAD_CLIPS),
        "%s: wrong catch chooses only a negative recorded phrase (got %s)" %
            [mode, _stream_path(player.stream)])
    _check(game.lives == (initial_lives - 1 if mode == "Lives" else initial_lives),
        "%s: wrong answer applies the correct life penalty" % mode)
    _check(_count_audio_players(game) == 1,
        "%s: repeated speech reuses the same player without leaking nodes" % mode)
    voice_samples += 1
    print("CATCH mode=%s correct/wrong streams verified; last=%s playing=%s volume=%.1fdB" %
        [mode, _stream_path(player.stream), str(player.playing), player.volume_db])

    # Speech must stop when pausing and when leaving the minigame.
    game._pause()
    _check(not player.playing, "%s: pause immediately stops spoken feedback" % mode)
    _stop_audio_tree(host)
    host.queue_free()
    await process_frame
    await process_frame


func _stop_audio_tree(node: Node) -> void:
    if node is AudioStreamPlayer:
        (node as AudioStreamPlayer).stop()
        (node as AudioStreamPlayer).stream = null
    for child in node.get_children():
        _stop_audio_tree(child)


func _stream_in_group(stream: AudioStream, choices: Array) -> bool:
    if not stream is AudioStreamMP3:
        return false
    for file_name in choices:
        if stream.resource_path == CLIP_DIR + file_name:
            return true
    return false


func _stream_path(stream: AudioStream) -> String:
    return stream.resource_path if stream != null else "<no stream>"


func _count_audio_players(node: Node) -> int:
    var total := 1 if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D else 0
    for child in node.get_children():
        total += _count_audio_players(child)
    return total


func _check(valid: bool, name: String) -> void:
    checks += 1
    if not valid:
        failures.append(name)
