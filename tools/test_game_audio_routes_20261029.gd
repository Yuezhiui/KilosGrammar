extends SceneTree

# Exact route-based audio lifecycle test: no main-menu _ready(), webcam or DB.
# Godot 4.7.2 --headless --path . --script res://tools/test_game_audio_routes_20261029.gd
# Optional audio-device run (not silent):
# Godot --rendering-method gl_compatibility --path . --script res://tools/test_game_audio_routes_20261029.gd
const GameAudio = preload("res://ui/shared/game_audio.gd")
const GAMEPLAY_PATH := "res://ui/play/gameplay/gameplay.tscn"
const MENU_SCRIPT_PATH := "res://ui/main_menu/main_menu.gd"
const MENU_SCENE_PATH := "res://ui/main_menu/main_menu.tscn"
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var pose := root.get_node_or_null("PoseService")
	if pose != null:
		pose.call("stop_camera")
		pose.set_process(false)
	var manager: Node = GameAudio.ensure(self) as Node
	_check(manager != null, "Single root-owned gameplay soundtrack manager is created")
	if manager == null:
		quit(1)
		return
	var track := manager.get_node("GameplayTrack") as AudioStreamPlayer
	_check(track != null and track.bus == "KilosMusic", "Gameplay audio uses Settings KilosMusic bus")
	_check(track != null and track.stream is AudioStreamWAV, "Gameplay track is original WAV")
	if track != null and track.stream is AudioStreamWAV:
		_check((track.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "WAV loops at source stream level")
		_check(track.stream.resource_path == GameAudio.MUSIC_PATH, "Correct children soundtrack is loaded")
	_check(manager == GameAudio.ensure(self), "No duplicate root music manager")
	await _test_title_routes()
	var original_music_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("KilosMusic"))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("KilosMusic"), -21.0)
	for guided in [false, true]:
		for activity in ACTIVITIES:
			await _test_round(manager, track, activity, guided)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("KilosMusic"), original_music_db)
	manager.call("stop_gameplay")
	# SceneTree-level manager must release cached audio streams before shutdown.
	if is_instance_valid(track):
		track.stream = null
	manager.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.55).timeout
	await process_frame
	_check(root.get_node_or_null("KilosGameAudio") == null, "Manager fully released after all rounds")
	if pose != null:
		pose.set_process(true)
	for failure in failures:
		push_error("GAME MUSIC ROUTES: " + failure)
	print("GAME MUSIC ROUTES: ", "PASS" if failures.is_empty() else "FAIL",
		" checks=", checks, " rounds=6 modes=Play+Guided games=Catch+Balloon+Plane failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _test_title_routes() -> void:
	# The real route handler now uses get_tree(), so exercise it on a properly
	# mounted scene while overriding only the expensive MainMenu _ready().
	var menu_script := load(MENU_SCRIPT_PATH) as GDScript
	_check(menu_script != null and menu_script.can_instantiate(), "Menu script loads after PoseService registration")
	if menu_script == null or not menu_script.can_instantiate():
		return
	var packed := load(MENU_SCENE_PATH) as PackedScene
	var menu := packed.instantiate() as Control if packed != null else null
	if menu != null:
		# Compile only AFTER SceneTree/autoload registration. A top-level
		# subclass compiles before PoseService becomes an available global.
		var route_only_script := GDScript.new()
		route_only_script.source_code = "extends \"res://ui/main_menu/main_menu.gd\"\nfunc _ready() -> void:\n\tpass\n"
		_check(route_only_script.reload() == OK and route_only_script.can_instantiate(),
			"Audio-only MainMenu subclass compiles after PoseService registration")
		menu.set_script(route_only_script)
		root.add_child(menu)
	_check(menu != null and menu.is_inside_tree(), "Real menu scene mounts with no-DB audio-only _ready()")
	if menu == null:
		return
	var title := AudioStreamPlayer.new()
	# stream_paused is meaningful only for a *playing* stream. Using an
	# unattached, unplayed AudioStreamPlayer would falsely report all routes
	# unpaused even when the production setter is correct.
	root.add_child(title)
	var title_fixture := AudioStreamGenerator.new()
	title_fixture.mix_rate = 22050
	title.stream = title_fixture
	title.play()
	_check(title.playing, "Title route fixture is playing before pause assertions")
	menu.set("title_music_player", title)
	for route in ["main", "tutorial_home", "student_setup", "play_activity", "calibration", "gameplay", "pause", "results"]:
		menu.call("_sync_title_music_for_route", route)
		var must_pause: bool = route in ["calibration", "gameplay", "pause"]
		_check(title.stream_paused == must_pause, "Title soundtrack conflicts with " + route)
		var track := (root.get_node("KilosGameAudio") as Node).get_node("GameplayTrack") as AudioStreamPlayer
		var music := root.get_node("KilosGameAudio") as Node
		var must_play_gameplay: bool = route in ["calibration", "gameplay", "pause"]
		_check(bool(music.call("is_gameplay_active")) == must_play_gameplay,
			"Gameplay soundtrack starts once on Calibration, persists through Gameplay/Pause and stops on " + route)
		_check(bool(music.call("is_music_paused")) == (route == "pause") if must_play_gameplay else true,
			"Pause route suspends game soundtrack without stopping the calibration track on " + route)
		_check(track.bus == "KilosMusic", "Music controls persist while switching " + route)
	menu.queue_free()
	title.stop()
	title.stream = null
	title.queue_free()
	await process_frame
	_check(not is_instance_valid(menu), "Audio-only title menu fixture releases without database startup")


func _test_round(manager: Node, track: AudioStreamPlayer, activity: String, guided: bool) -> void:
	var tag := activity + ("/Guided" if guided else "/Play")
	# Load after autoload globals are registered, as GDScript dependency
	# parse order differs for direct --script headless invocations.
	var packed := load(GAMEPLAY_PATH) as PackedScene
	_check(packed != null, tag + " PackedScene loads")
	if packed == null:
		return
	var wrapper := packed.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrapper.call("set_context", {
		"activity": activity, "game_mode": "Seconds", "topic": "Noun",
		"difficulty": "Easy", "keyboard_mode": true, "camera_live": false,
		"guided_tutorial": guided, "start_countdown": true,
		"catch_character": "Bear", "catch_map": "Forest"
	})
	await process_frame
	await process_frame
	_check(wrapper.get("active_game") is Control, tag + " actual game instance mounted")
	_check(not manager.call("is_gameplay_active"), tag + " no children music before GO")
	_check(String(wrapper.get("guided_stage")) == "countdown",
		tag + " starts direct 3-2-1 after calibration/Play (no Spotlight)")
	_check((wrapper.get("countdown_panel") as Control) != null,
		tag + " direct countdown panel exists before GO")
	_check((wrapper.get("active_game") as Control).process_mode == Node.PROCESS_MODE_DISABLED,
		tag + " active game and score/timers stay frozen before GO")
	await process_frame
	_check(String(wrapper.get("guided_stage")) == "countdown", tag + " 3-2-1 before activity")
	_check(not manager.call("is_gameplay_active"), tag + " 3-2-1 silent")
	for tick in 2:
		wrapper.call("_on_countdown_tick")
		_check(not manager.call("is_gameplay_active"), tag + " no early music on tick " + str(tick))
	wrapper.call("_on_countdown_tick")
	_check(manager.call("is_gameplay_active"), tag + " music activates exactly at GO")
	_check(String(wrapper.get("guided_stage")) == "", tag + " countdown UI cleared at GO")
	_check((wrapper.get("active_game") as Control).process_mode == Node.PROCESS_MODE_INHERIT, tag + " game actually starts at GO")
	_check(manager == GameAudio.ensure(self), tag + " GO does not create duplicate soundtrack player")
	_check(track.stream != null and track.bus == "KilosMusic", tag + " live track routed through Music bus")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("KilosMusic")), -21.0), tag + " Settings music slider preserved")
	if DisplayServer.get_name() != "headless":
		_check(track.playing, tag + " physical audio playback starts")
	manager.call("duck_for_voice", 1.0)
	_check(track.volume_db <= GameAudio.DUCK_DB + 0.05, tag + " voice ducks music")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("KilosMusic")), -21.0), tag + " voice duck keeps Settings music volume")
	manager.call("_process", 1.2)
	_check(is_zero_approx(track.volume_db), tag + " voice duck restores gain")
	wrapper.call("_pause")
	_check(manager.call("is_music_paused"), tag + " Pause pauses soundtrack")
	wrapper.call("_resume")
	_check(not manager.call("is_music_paused"), tag + " Resume resumes soundtrack")
	# A completed round routes to results even before its wrapper is destroyed.
	wrapper.call("_relay_navigation", "results", {"round_completed": true})
	_check(not manager.call("is_gameplay_active"), tag + " Results stop soundtrack")
	wrapper.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(wrapper), tag + " gameplay wrapper destroyed")
	_check(not manager.call("is_gameplay_active"), tag + " music stays off after scene exit")
	print("GAME MUSIC ROUND ", tag, " PASS")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
