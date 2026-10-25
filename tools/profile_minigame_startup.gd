extends SceneTree

# Read-only Godot 4.7 startup profiler. Never modifies a production scene.
# Run independent cold processes in both orders:
#   godot --headless --path . --script res://tools/profile_minigame_startup.gd -- --order=catch
#   godot --headless --path . --script res://tools/profile_minigame_startup.gd -- --order=balloon
# Metrics are CPU wall-clock; --headless cannot measure GPU upload/render latency.

const GAME_PATHS := {
	"catch": "res://ui/minigames/catch_word.tscn",
	"balloon": "res://ui/minigames/balloon_popping.tscn"
}
const ACTIVITY := {"catch": "Catch the Word", "balloon": "Balloon Popping"}
const WRAPPER_PATH := "res://ui/play/gameplay.tscn"
const MENU_PATH := "res://main_menu.tscn"
const CATCH_PROBE := {
	"hud": [
		"res://Components/Gameplay/Catch the Word/HUD/generated/title_board.png",
		"res://Components/Gameplay/Catch the Word/HUD/generated/lives_badge.png",
		"res://Components/Gameplay/Catch the Word/HUD/generated/timer_badge.png",
		"res://Components/Gameplay/Catch the Word/HUD/generated/pause_badge.png",
		"res://Components/Gameplay/Catch the Word/HUD/generated/score_board.png",
		"res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_1.png",
		"res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_2.png",
		"res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_3.png",
		"res://Components/Gameplay/Catch the Word/Characters/Generated/word_apple.png"
	],
	"character_map": [
		"res://Components/Gameplay/Catch the Word/Maps/CityMap.png",
		"res://Components/Gameplay/Catch the Word/Maps/ForestMap.png",
		"res://Components/Gameplay/Catch the Word/Maps/MountainMap.png",
		"res://Components/Gameplay/Catch the Word/Characters/BOY BODY.png",
		"res://Components/Gameplay/Catch the Word/Characters/BOY BASKET.png",
		"res://Components/Gameplay/Catch the Word/Characters/GIRL BODY.png",
		"res://Components/Gameplay/Catch the Word/Characters/GIRL BASKET.png",
		"res://Components/Gameplay/Catch the Word/Characters/GRANDMA BODY.png",
		"res://Components/Gameplay/Catch the Word/Characters/GRANDMA BASKET.png",
		"res://Components/Gameplay/Catch the Word/Characters/GRANDPA BODY.png",
		"res://Components/Gameplay/Catch the Word/Characters/GRANDPA BASKET.png"
	],
	"voice": [
		"GoodJob.mp3", "niceee.mp3", "Awesome.mp3", "Perfect.mp3",
		"You Nailed it.mp3", "Awww.mp3", "Wrong Answer.mp3",
		"You Missed.mp3", "Better Luck.mp3"
	]
}
const BOOT_CONTEXT := {
	"topic": "Noun", "game_style": "Noun", "difficulty": "Normal",
	"game_mode": "Seconds", "demo_mode": true
}
var held_scenes: Dictionary = {}
var held_assets: Array[Resource] = []
var hold_scene_resources := false


func _initialize() -> void:
	call_deferred("_profile")


func _ms(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0


func _report(name: String, iteration: int, stage: String, value: float) -> void:
	print("STARTUP|%s|%d|%s|%.3f" % [name, iteration, stage, value])


func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count


func _profile() -> void:
	root.size = Vector2i(1280, 720)
	var args := OS.get_cmdline_user_args()
	hold_scene_resources = "--hold-scenes" in args
	var order := ["catch", "balloon"]
	if "--order=balloon" in args:
		order = ["balloon", "catch"]
	print("STARTUP|environment|0|rendering_method|", ProjectSettings.get_setting("rendering/renderer/rendering_method", "default"))
	print("STARTUP|environment|0|driver|", DisplayServer.get_name())
	print("STARTUP|environment|0|hold-scenes|", hold_scene_resources)
	if "--profile-ready" in args:
		await _profile_ready_route()
		print("STARTUP|done|0|status|complete")
		quit(0)
		return
	if "--probe-catch-assets" in args:
		_probe_catch_assets()
	for name in order:
		await _profile_game(name)
	for name in order:
		await _profile_wrapper(name)
	print("STARTUP|done|0|status|complete")
	held_scenes.clear()
	held_assets.clear()
	quit(0)


func _profile_ready_route() -> void:
	var t := Time.get_ticks_usec()
	var menu_scene := load(MENU_PATH) as PackedScene
	_report("ready", 0, "menu_scene_load_ms", _ms(t))
	var menu := menu_scene.instantiate() as Control
	root.add_child(menu)
	var context := BOOT_CONTEXT.duplicate(true)
	context["activity"] = "Catch the Word"
	# Make the test deterministic. Normal Ready flow picks random originals
	# when these values are absent and forwards that choice to gameplay.
	context["catch_character"] = "Grandpa"
	context["catch_map"] = "Forest"
	t = Time.get_ticks_usec()
	menu.call("_on_panel_requested", "ready", context)
	_report("ready", 0, "enter_ready_and_queue_ms", _ms(t))
	var preloader := menu.get("catch_asset_preloader") as Node
	if preloader == null:
		print("READY_CHECK|ERROR|no preloader")
		menu.queue_free()
		return
	print("READY_CHECK|initial|", preloader.call("get_preload_stats"))
	var preload_start := Time.get_ticks_usec()
	var stats: Dictionary = preloader.call("get_preload_stats")
	for frame in range(180):
		if bool(stats.get("complete", false)):
			break
		await process_frame
		stats = preloader.call("get_preload_stats")
	_report("ready", 0, "all_selected_assets_warm_ms", _ms(preload_start))
	print("READY_CHECK|after_warm|", stats)
	var selected_context: Dictionary = (menu.get("session_state") as Dictionary).duplicate(true)
	t = Time.get_ticks_usec()
	menu.call("_on_panel_requested", "gameplay", selected_context)
	_report("ready", 0, "gameplay_mount_after_ready_ms", _ms(t))
	var wrapper := menu.get("active_panel") as Control
	var game := wrapper.get_node_or_null("ActiveMiniGame") as Control if wrapper != null else null
	print("READY_CHECK|game|", {
		"is_active": game != null,
		"selected_character": game.get("selected_character") if game != null else "",
		"selected_map": game.get("selected_map") if game != null else "",
		"round_started": String(game.get("wave_phase")) if game != null else "",
		"preload_complete": (preloader.call("get_preload_stats") as Dictionary).get("complete", false)
	})
	menu.call("_return_to_main")
	await process_frame
	print("READY_CHECK|after_return_main|", preloader.call("get_preload_stats"))
	var music := menu.get("title_music_player") as AudioStreamPlayer
	if music != null:
		music.stop()
		music.stream = null
	menu.queue_free()
	await process_frame


func _probe_catch_assets() -> void:
	for category in CATCH_PROBE:
		var total := 0.0
		for short_path in CATCH_PROBE[category]:
			var path: String = "res://assets/audio/catch_voice/" + short_path if category == "voice" else short_path
			var cached := ResourceLoader.has_cached(path)
			var t := Time.get_ticks_usec()
			var asset := load(path) as Resource
			var elapsed := _ms(t)
			total += elapsed
			print("ASSET|%s|%s|cached=%s|ms=%.3f|ok=%s" % [category, short_path, str(cached), elapsed, str(asset != null)])
			if asset != null:
				held_assets.append(asset)
		print("ASSET_TOTAL|%s|%d|%.3f" % [category, (CATCH_PROBE[category] as Array).size(), total])


func _profile_game(name: String) -> void:
	var path: String = GAME_PATHS[name]
	var cached := ResourceLoader.has_cached(path)
	print("STARTUP|%s|0|cached_before_load|%s" % [name, str(cached)])
	var t := Time.get_ticks_usec()
	var packed := load(path) as PackedScene
	_report(name, 0, "load_ms", _ms(t))
	if packed == null:
		print("STARTUP|%s|0|ERROR|scene load failed" % name)
		return
	if hold_scene_resources:
		held_scenes[name] = packed
	for trial in range(4):
		var ctx := BOOT_CONTEXT.duplicate(true)
		ctx["activity"] = ACTIVITY[name]
		t = Time.get_ticks_usec()
		var game := packed.instantiate() as Control
		_report(name, trial, "instantiate_ms", _ms(t))
		if game == null:
			break
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		t = Time.get_ticks_usec()
		root.add_child(game)
		_report(name, trial, "add_child_ready_ms", _ms(t))
		_report(name, trial, "nodes", float(_count_nodes(game)))
		t = Time.get_ticks_usec()
		if game.has_method("set_context"):
			game.call("set_context", ctx)
		_report(name, trial, "set_context_ms", _ms(t))
		# Pauses processing only after the foreground startup calls have finished.
		game.set_process(false)
		game.set_physics_process(false)
		t = Time.get_ticks_usec()
		await process_frame
		_report(name, trial, "first_frame_ms", _ms(t))
		t = Time.get_ticks_usec()
		await process_frame
		_report(name, trial, "second_frame_ms", _ms(t))
		t = Time.get_ticks_usec()
		root.remove_child(game)
		game.free()
		_report(name, trial, "free_ms", _ms(t))
		await process_frame


func _profile_wrapper(name: String) -> void:
	var t := Time.get_ticks_usec()
	var packed := load(WRAPPER_PATH) as PackedScene
	_report("wrapper", 0, "load_ms", _ms(t))
	if packed == null:
		return
	for trial in range(2):
		print("STARTUP|%s_route|%d|cached_before_mount|%s" % [name, trial, str(ResourceLoader.has_cached(GAME_PATHS[name]))])
		t = Time.get_ticks_usec()
		var wrapper := packed.instantiate() as Control
		_report(name + "_route", trial, "wrapper_instantiate_ms", _ms(t))
		t = Time.get_ticks_usec()
		root.add_child(wrapper)
		_report(name + "_route", trial, "wrapper_add_ready_ms", _ms(t))
		var ctx := BOOT_CONTEXT.duplicate(true)
		ctx["activity"] = ACTIVITY[name]
		t = Time.get_ticks_usec()
		wrapper.call("set_context", ctx)
		_report(name + "_route", trial, "wrapper_set_context_mount_total_ms", _ms(t))
		var game := wrapper.get_node_or_null("ActiveMiniGame") as Control
		_report(name + "_route", trial, "child_nodes", float(_count_nodes(game)) if game != null else 0.0)
		if game != null:
			game.set_process(false)
			game.set_physics_process(false)
		await process_frame
		root.remove_child(wrapper)
		wrapper.free()
		await process_frame
