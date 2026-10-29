extends SceneTree

## Synthetic lifecycle and recording coverage; no webcam, DB or speaker used.
## Run: Godot --headless --path . -s res://tools/test_kids_gameplay_audio.gd
const GameAudio = preload("res://ui/shared/game_audio.gd")
const KidsVoice = preload("res://ui/shared/kids_voice_feedback.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var music = GameAudio.ensure(self)
	_check(music != null, "GameAudio manager created without a registered global class")
	if music == null:
		quit(1)
		return
	var stream_player := music.get_node_or_null("GameplayTrack") as AudioStreamPlayer
	_check(stream_player != null, "Exactly one soundtrack player was created")
	_check(GameAudio.ensure(self) == music, "ensure is idempotent")
	_check(AudioServer.get_bus_index("KilosMusic") >= 0, "Music bus exists")
	_check(AudioServer.get_bus_index("KilosSFX") >= 0, "Voice bus exists")
	_check(not music.is_gameplay_active(), "Soundtrack is prepared without starting gameplay")
	if stream_player != null:
		_check(stream_player.stream is AudioStreamWAV, "Gameplay music decodes as WAV")
		_check(stream_player.stream.get_length() > 30.0, "Soundtrack length is meaningful")
		_check((stream_player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "Music loops continuously")
		_check(stream_player.bus == "KilosMusic", "Music routed to Settings music bus")
	var music_bus := AudioServer.get_bus_index("KilosMusic")
	var original_music_db := AudioServer.get_bus_volume_db(music_bus)
	AudioServer.set_bus_volume_db(music_bus, -18.0)
	music.start_gameplay()
	music.start_gameplay()
	_check(music.is_gameplay_active(), "Repeated start remains active")
	_check(stream_player != null and stream_player.get_parent() == music, "Repeated start reuses one player")
	music.duck_for_voice(1.0)
	_check(stream_player != null and stream_player.volume_db < -8.0, "Voice temporarily ducks music player")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), -18.0), "Ducking preserves Settings music volume")
	music._process(1.1)
	_check(is_equal_approx(stream_player.volume_db, 0.0), "Duck automatically restores original player gain")
	music.pause_music()
	music.pause_music()
	_check(music.is_music_paused(), "Repeated pause is idempotent")
	if DisplayServer.get_name() != "headless":
		_check(stream_player.stream_paused, "Pause retains soundtrack position")
	music.resume_music()
	music.resume_music()
	_check(not music.is_music_paused(), "Repeated resume is idempotent")
	_check(not stream_player.stream_paused, "Resume clears paused stream state")
	music.duck_for_voice(7.0)
	music.stop_gameplay()
	music.stop_gameplay()
	_check(not music.is_gameplay_active(), "Repeated stop becomes inactive")
	_check(is_equal_approx(stream_player.volume_db, 0.0), "Stop resets voice duck")
	_check(not stream_player.stream_paused, "Stop removes stale pause")
	AudioServer.set_bus_volume_db(music_bus, original_music_db)

	var recorded_files: Dictionary = {}
	for name in KidsVoice.CORRECT + KidsVoice.ENCOURAGEMENT:
		_check(not recorded_files.has(name), "Correct/coaching banks contain no duplicate: " + name)
		recorded_files[name] = true
		var path: String = "res://assets/audio/kids_voice/" + String(name)
		_check(ResourceLoader.exists(path), "Recorded voice exists: " + name)
		var stream := load(path) as AudioStream
		_check(stream is AudioStreamWAV and stream.get_length() >= 0.4, "Recorded voice decodes: " + name)
	_check(recorded_files.size() == 39, "All 39 supplied recordings are represented")
	for name in KidsVoice.MISSED:
		_check(recorded_files.has(name), "Missed bank uses existing coaching phrase: " + name)

	var host := Node.new()
	root.add_child(host)
	var voice = KidsVoice.new()
	voice.setup(host)
	voice.setup(host)
	var player := voice.get_voice_player()
	_check(player != null, "Voice helper created reusable player")
	_check(player != null and player.get_parent() == host, "Voice player is owned by game node")
	_check(player != null and player.bus == "KilosSFX", "Voice uses Effects slider bus")
	_check(host.get_child_count() == 1, "Repeated voice setup never duplicates player")
	for i in range(80):
		_check(voice.play_correct(), "Correct response can be selected #%d" % i)
		_check(KidsVoice.CORRECT.has(player.stream.resource_path.get_file()), "Correct uses praise WAV #%d" % i)
		_check(voice.play_wrong(), "Wrong response can be selected #%d" % i)
		_check(KidsVoice.ENCOURAGEMENT.has(player.stream.resource_path.get_file()), "Wrong uses encouraging WAV #%d" % i)
		_check(voice.play_missed(), "Missed response can be selected #%d" % i)
		_check(KidsVoice.MISSED.has(player.stream.resource_path.get_file()), "Missed uses coaching WAV #%d" % i)
	voice.stop()
	_check(player.stream == null, "Pause/completion clears voice stream")
	voice.release()
	host.queue_free()
	await process_frame
	for round_index in range(20):
		var round_host := Node.new()
		root.add_child(round_host)
		var round_voice = KidsVoice.new()
		round_voice.setup(round_host)
		_check(round_voice.play_correct(), "Round %d can speak after previous scene exits" % round_index)
		round_voice.release()
		round_host.queue_free()
		await process_frame
		music.start_gameplay()
		music.stop_gameplay()
		_check(GameAudio.ensure(self) == music, "Round %d preserves one manager" % round_index)
	await _test_scene_voice_bridges()
	_check(root.get_node_or_null("KilosGameAudio") == music, "Root owns only shared gameplay music")
	music.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS kids gameplay audio: %d assertions, 39 voice WAVs, 20 round transitions" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("KIDS AUDIO: " + failure)
		print("FAIL kids gameplay audio: %d of %d assertions" % [failures.size(), checks])
		quit(1)


func _test_scene_voice_bridges() -> void:
	var balloon_scene := load("res://ui/minigames/balloon_popping/balloon_popping.tscn") as PackedScene
	_check(balloon_scene != null, "Balloon scene loads")
	if balloon_scene != null:
		var balloon := balloon_scene.instantiate() as Control
		root.add_child(balloon)
		await process_frame
		balloon.set_process(false)
		balloon.set_physics_process(false)
		var balloon_voice := balloon.get_node_or_null("BalloonVoicePlayer") as AudioStreamPlayer
		_check(balloon_voice != null, "Balloon uses one reusable kids voice player")
		balloon._speak_balloon_feedback(true)
		_check(balloon_voice != null and balloon_voice.stream != null and KidsVoice.CORRECT.has(balloon_voice.stream.resource_path.get_file()), "Balloon correct answer uses praise")
		balloon._speak_balloon_feedback(false)
		_check(balloon_voice != null and balloon_voice.stream != null and KidsVoice.ENCOURAGEMENT.has(balloon_voice.stream.resource_path.get_file()), "Balloon wrong answer uses coaching")
		balloon._stop_voice_feedback()
		balloon._speak_balloon_feedback(false, true)
		_check(balloon_voice != null and balloon_voice.stream != null and KidsVoice.MISSED.has(balloon_voice.stream.resource_path.get_file()), "Balloon missed shot uses coaching")
		balloon._stop_voice_feedback()
		balloon.queue_free()
		await process_frame
		_check(not is_instance_valid(balloon_voice), "Balloon exit frees its voice")

	var plane_scene := load("res://ui/minigames/human_plane/human_plane.tscn") as PackedScene
	_check(plane_scene != null, "Human Plane scene loads")
	if plane_scene != null:
		var plane := plane_scene.instantiate() as Control
		root.add_child(plane)
		await process_frame
		plane.set_process(false)
		var plane_voice := plane.get_node_or_null("HumanPlaneVoicePlayer") as AudioStreamPlayer
		_check(plane_voice != null, "Plane uses one reusable kids voice player")
		plane._play_voice_feedback(true)
		_check(plane_voice != null and plane_voice.stream != null and KidsVoice.CORRECT.has(plane_voice.stream.resource_path.get_file()), "Plane correct gate uses praise")
		plane._play_voice_feedback(false)
		_check(plane_voice != null and plane_voice.stream != null and KidsVoice.ENCOURAGEMENT.has(plane_voice.stream.resource_path.get_file()), "Plane wrong gate uses coaching")
		plane._play_voice_feedback(false, true)
		_check(plane_voice != null and plane_voice.stream != null and KidsVoice.MISSED.has(plane_voice.stream.resource_path.get_file()), "Plane missed gate uses coaching")
		plane._stop_voice_feedback()
		plane.queue_free()
		await process_frame
		_check(not is_instance_valid(plane_voice), "Plane exit frees its voice")


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
