extends SceneTree

# Isolated BUG-006 lifecycle QA. The scene script bypasses main_menu.tscn
# (and its PostgreSQL startup) and NEVER opens a real camera.
#
# Godot 4.7 --headless --path . --script res://tools/test_shutdown_resources.gd -- bare
# Replace bare with: countdown, wrapper, guided, cycle,
# audio_unstopped (negative control), audio_clean (cache, stop + mixer grace),
# audio_cached_nowait, audio_nocache_unstopped, audio_nocache_nowait, audio_nocache_wait,
# audio_direct_nowait, audio_direct_wait, audio_muted_nowait, audio_muted_wait.
# Compare with project main-scene exit: godot --headless --path . --quit --verbose
const COUNTDOWN := "res://ui/play/gameplay/guided_countdown.tscn"
const GAMEPLAY := "res://ui/play/gameplay/gameplay.tscn"
const TITLE_MP3 := "res://assets/audio/user_provided/wii_fit_user_settings.mp3"
const LOGO_WAV := "res://assets/audio/lexispell_intro/logo_bloop.wav"

var errors: Array[String] = []
var _initial_resource_count := 0.0
var _initial_node_count := 0.0
var _initial_orphan_count := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var arguments := OS.get_cmdline_user_args()
	var mode := String(arguments[0]) if not arguments.is_empty() else "bare"
	var pose := root.get_node_or_null("PoseService")
	if pose != null:
		pose.call("stop_camera")
		pose.set_process(false)
	_initial_resource_count = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	_initial_node_count = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	_initial_orphan_count = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	print("SHUTDOWN QA MODE=", mode, " CAMERA=OFF DB=NOT USED")
	_log_counts("begin")
	match mode:
		"bare":
			await _idle_frames()
		"countdown":
			await _plain_countdown()
		"wrapper":
			await _wrapper(false)
		"guided":
			await _wrapper(true)
		"cycle":
			for i in 5:
				await _wrapper(i % 2 == 0)
		"audio_unstopped":
			await _audio_fixture(false)
		"audio_clean":
			await _audio_fixture(true)
		"audio_cached_nowait":
			await _audio_fixture(true, "cache", 0.0)
		"audio_nocache_unstopped":
			await _audio_fixture(false, "nocache", 0.0)
		"audio_nocache_nowait":
			await _audio_fixture(true, "nocache", 0.0)
		"audio_nocache_wait":
			await _audio_fixture(true, "nocache", 0.55)
		"audio_direct_nowait":
			await _audio_fixture(true, "direct", 0.0)
		"audio_direct_wait":
			await _audio_fixture(true, "direct", 0.55)
		"audio_muted_nowait":
			await _audio_fixture(true, "cache", 0.0, true)
		"audio_muted_wait":
			await _audio_fixture(true, "cache", 0.55, true)
		_:
			errors.append("Unknown QA mode: " + mode)
	# The wrapper now creates one SceneTree-root soundtrack manager shared
	# across calibration/countdown/gameplay. Explicit application shutdown
	# must stop and dispose it; otherwise the fixture, not gameplay, leaks.
	var game_audio := root.get_node_or_null("KilosGameAudio") as Node
	if is_instance_valid(game_audio):
		game_audio.call("stop_gameplay")
		var stream_player := game_audio.get_node_or_null("GameplayTrack") as AudioStreamPlayer
		if is_instance_valid(stream_player):
			stream_player.stream = null
		game_audio.queue_free()
		await _idle_frames()
	_log_counts("before-final-drain")
	await _idle_frames()
	_log_counts("after-final-drain")
	if not mode.begins_with("audio_") or mode in ["audio_clean", "audio_nocache_wait", "audio_direct_wait", "audio_muted_wait"]:
		_check(is_equal_approx(Performance.get_monitor(Performance.OBJECT_NODE_COUNT), _initial_node_count), "Scene nodes return to startup baseline")
		_check(is_equal_approx(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), _initial_orphan_count), "No orphan nodes introduced")
	if pose != null:
		pose.call("stop_camera")
		pose.set_process(true)
	var result_label := "PASS" if errors.is_empty() else "FAIL"
	if errors.is_empty() and mode in ["audio_unstopped", "audio_nocache_unstopped", "audio_cached_nowait", "audio_nocache_nowait", "audio_direct_nowait", "audio_muted_nowait"]:
		# Godot prints ObjectDB/resource exit warnings AFTER this script stops.
		# Do not mislabel negative/unstable diagnostic cases as leak-free PASS.
		result_label = "DIAGNOSTIC (CHECK ENGINE EXIT WARNINGS)"
	print("SHUTDOWN RESOURCE QA: ", result_label, " mode=", mode, " failures=", errors.size())
	for error in errors:
		printerr("SHUTDOWN QA FAILED: ", error)
	quit(0 if errors.is_empty() else 1)


func _plain_countdown() -> void:
	var packed := load(COUNTDOWN) as PackedScene
	_check(packed != null, "Countdown PackedScene loads")
	if packed == null:
		return
	var layer := CanvasLayer.new()
	layer.name = "ShutdownTestCanvasLayer"
	root.add_child(layer)
	var panel := packed.instantiate() as Control
	layer.add_child(panel)
	_check(panel.get_node_or_null("CountdownTimer") is Timer, "Countdown Timer is scene-owned")
	_check(panel.get_node_or_null("CountdownNumber") is Label, "Countdown label is scene-owned")
	var timer := panel.get_node("CountdownTimer") as Timer
	timer.start()
	await _idle_frames()
	_log_counts("countdown-mounted")
	timer.stop()
	layer.queue_free()
	await _idle_frames()
	_check(not is_instance_valid(panel) and not is_instance_valid(layer), "Countdown panel and CanvasLayer are destroyed")
	_log_counts("countdown-released")


func _audio_fixture(cleanup: bool, source: String = "cache", grace_seconds: float = 0.55, mute: bool = false) -> void:
	var players: Array[AudioStreamPlayer] = []
	var master_index := AudioServer.get_bus_index("Master")
	var former_mute := AudioServer.is_bus_mute(master_index) if master_index >= 0 else false
	if mute and master_index >= 0:
		AudioServer.set_bus_mute(master_index, true)
	print("SHUTDOWN QA AUDIO SETTINGS source=", source, " grace=", grace_seconds, " mute=", mute)
	for path in [TITLE_MP3, LOGO_WAV]:
		if not ResourceLoader.exists(path):
			print("SHUTDOWN QA AUDIO OPTIONAL ABSENT ", path)
			continue
		var stream: AudioStream
		match source:
			"nocache":
				stream = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
			"direct":
				var native_path := ProjectSettings.globalize_path(path)
				if path.ends_with(".mp3"):
					stream = AudioStreamMP3.load_from_file(native_path)
				else:
					stream = AudioStreamWAV.load_from_file(native_path)
			_:
				stream = load(path) as AudioStream
		_check(stream != null, "Audio stream loads: " + path)
		if stream == null:
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		root.add_child(player)
		player.play()
		players.append(player)
	await _idle_frames()
	_log_counts("audio-players-active")
	if cleanup:
		for player in players:
			player.stop()
			player.stream = null
			player.queue_free()
		await _idle_frames()
		for player in players:
			_check(not is_instance_valid(player), "Audio player freed after stop")
		# Also drop this test function's Array references to freed instances,
		# and let the audio mixer process an explicit grace interval.
		players.clear()
		if grace_seconds > 0.0:
			await create_timer(grace_seconds).timeout
		await _idle_frames()
		_log_counts("audio-explicitly-stopped")
		if grace_seconds > 0.0:
			_check(is_equal_approx(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), _initial_resource_count), "Released audio resources return to startup baseline after mixer grace")
	else:
		# Negative control reproduces an abrupt application exit with active
		# audio. The comparison is diagnostic; this mode may warn at shutdown.
		print("SHUTDOWN QA INTENTIONAL ACTIVE AUDIO ON EXIT")
	if mute and master_index >= 0:
		AudioServer.set_bus_mute(master_index, former_mute)


func _wrapper(guided: bool) -> void:
	var packed := load(GAMEPLAY) as PackedScene
	_check(packed != null, "Gameplay wrapper scene loads")
	if packed == null:
		return
	var wrapper := packed.instantiate() as Control
	root.add_child(wrapper)
	wrapper.call("set_context", {
		"activity": "Catch the Word", "topic": "Noun",
		"game_mode": "Seconds", "difficulty": "Easy",
		"catch_character": "Bear", "catch_map": "City",
		"keyboard_mode": true, "camera_live": false,
		"guided_tutorial": guided, "start_countdown": true
	})
	await _idle_frames()
	var game := wrapper.get("active_game") as Control
	_check(game != null, "Gameplay minigame is mounted")
	_check(String(wrapper.get("guided_stage")) == "countdown",
		"Guided and Play mount the same direct 3-2-1 countdown")
	_check(game != null and game.process_mode == Node.PROCESS_MODE_DISABLED,
		"Countdown freezes the mounted game's resources until GO")
	await _idle_frames()
	var panel := wrapper.get("countdown_panel") as Control
	_check(panel != null, "Countdown panel created in gameplay wrapper")
	if panel != null:
		_check((panel.get_node_or_null("CountdownTimer") as Timer) != null, "Countdown owns timer")
	_log_counts("wrapper-countdown-mounted-" + str(guided))
	# Tear down once DURING an active countdown; other times after completion.
	if guided:
		for i in 3:
			wrapper.call("_on_countdown_tick")
		await _idle_frames()
		_check(wrapper.get("countdown_panel") == null, "Finished countdown resets references")
	wrapper.queue_free()
	await _idle_frames()
	_check(not is_instance_valid(wrapper), "Gameplay wrapper and owned UI are destroyed")
	_log_counts("wrapper-released-" + str(guided))


func _idle_frames() -> void:
	await process_frame
	await process_frame
	await process_frame


func _log_counts(label: String) -> void:
	print("SHUTDOWN QA MONITORS ", label,
		" nodes=", Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		" orphans=", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		" resources=", Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		" objects=", Performance.get_monitor(Performance.OBJECT_COUNT))


func _check(ok: bool, description: String) -> void:
	if not ok:
		errors.append(description)
