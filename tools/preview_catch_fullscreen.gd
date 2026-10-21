extends SceneTree

# Dedicated standalone entry point for Catch the Word. It deliberately does not
# replace the application's main scene or modify the project's window settings.
# Run through tools/run_catch_fullscreen.ps1 (or Godot --script with user args).

const CATCH_SCENE := "res://ui/minigames/catch_word.tscn"
const RESULTS_SCRIPT := preload("res://ui/secondary/results.gd")
const DEFAULTS := {
	"character": "Boy",
	"topic": "Noun",
	"map": "City",
	"mode": "Seconds",
	"difficulty": "Easy",
}
const ALLOWED := {
	"character": ["Boy", "Girl", "Grandma", "Grandpa"],
	"topic": ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"],
	"map": ["City", "Forest", "Mountain"],
	"mode": ["Seconds", "Lives"],
	"difficulty": ["Easy", "Normal", "Hard"],
}

var options: Dictionary = DEFAULTS.duplicate()
var smoke_test := false
var host: Control
var game: Control
var pause_dialog: ConfirmationDialog
var result_dialog: ConfirmationDialog
var low_score_voice_player: AudioStreamPlayer
var low_score_voice_started := false


func _initialize() -> void:
	call_deferred("_launch")


func _launch() -> void:
	if not _read_options():
		quit(2)
		return
	var scene := load(CATCH_SCENE) as PackedScene
	if scene == null:
		push_error("Catch fullscreen: missing %s" % CATCH_SCENE)
		quit(1)
		return

	# Godot's --fullscreen flag applies before the first frame. This ensures a
	# direct script invocation also becomes an independent fullscreen window.
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		# Headless runs otherwise start at 64x64, unrelated to gameplay sizing.
		root.size = Vector2i(1280, 720)
	await process_frame

	host = Control.new()
	host.name = "StandaloneCatchHost"
	host.size = Vector2(root.size)
	root.add_child(host)
	root.size_changed.connect(_resize_host)

	game = scene.instantiate() as Control
	if game == null:
		push_error("Catch fullscreen: instantiated scene is not a Control")
		quit(1)
		return
	host.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", _game_context())
	game.connect("requested", Callable(self, "_game_requested"))
	_resize_host()
	_build_dialogs()

	if smoke_test:
		await process_frame
		var actual_window_mode := DisplayServer.window_get_mode()
		if DisplayServer.get_name() != "headless" and actual_window_mode not in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]:
			push_error("Catch fullscreen smoke test: graphical window did not enter fullscreen mode")
			quit(1)
			return
		if String(game.get("topic")) != String(options["topic"]) \
			or String(game.get("selected_character")) != String(options["character"]) \
			or String(game.get("selected_map")) != String(options["map"]) \
			or String(game.get("game_mode")) != String(options["mode"]) \
			or String(game.get("difficulty")) != String(options["difficulty"]) \
			or game.size.x < 1280.0 or game.size.y < 720.0:
			push_error("Catch fullscreen smoke test: requested settings were not applied")
			quit(1)
			return
		print("PASS Catch standalone preview: ", _game_context(), ", viewport=", root.size, ", display=", DisplayServer.get_name(), ", window_mode=", actual_window_mode)
		quit(0)
		return

	print("Catch standalone fullscreen: ", _game_context(), ". Close the window to quit.")


func _read_options() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument == "--smoke-test":
			smoke_test = true
			continue
		var pair := String(argument).split("=", false, 1)
		if pair.size() != 2 or not pair[0].begins_with("--"):
			push_error("Catch fullscreen: unrecognized argument '%s'" % argument)
			return false
		var key := String(pair[0]).trim_prefix("--")
		if not ALLOWED.has(key):
			push_error("Catch fullscreen: unknown option '%s'" % key)
			return false
		var chosen := ""
		for allowed_value in ALLOWED[key]:
			if String(allowed_value).nocasecmp_to(String(pair[1])) == 0:
				chosen = String(allowed_value)
				break
		if chosen.is_empty():
			push_error("Catch fullscreen: invalid %s '%s' (choose from %s)" % [key, pair[1], ALLOWED[key]])
			return false
		options[key] = chosen
	return true


func _game_context() -> Dictionary:
	return {
		"activity": "Catch the Word",
		"topic": options["topic"],
		"game_style": options["topic"],
		"game_mode": options["mode"],
		"difficulty": options["difficulty"],
		"catch_character": options["character"],
		"catch_map": options["map"],
	}


func _resize_host() -> void:
	if is_instance_valid(host):
		host.size = Vector2(root.size)
	if is_instance_valid(game):
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_dialogs() -> void:
	pause_dialog = ConfirmationDialog.new()
	pause_dialog.title = "Catch the Word - Paused"
	pause_dialog.dialog_text = "The game is paused. Resume playing?"
	pause_dialog.ok_button_text = "Resume"
	pause_dialog.cancel_button_text = "Exit game"
	pause_dialog.confirmed.connect(_resume)
	pause_dialog.canceled.connect(_exit_game)
	host.add_child(pause_dialog)

	result_dialog = ConfirmationDialog.new()
	result_dialog.title = "Catch the Word - Round Complete"
	result_dialog.ok_button_text = "Play again"
	result_dialog.cancel_button_text = "Exit game"
	result_dialog.confirmed.connect(_restart)
	result_dialog.canceled.connect(_exit_game)
	host.add_child(result_dialog)


func _game_requested(target: String, result: Dictionary) -> void:
	if target == "pause" and is_instance_valid(pause_dialog):
		pause_dialog.popup_centered()
	elif target == "results" and is_instance_valid(result_dialog):
		_play_result_encouragement(result)
		result_dialog.dialog_text = "Score: %s    Correct: %s    Attempts: %s\n\nPlay another round?" % [
			result.get("score", 0), result.get("correct", 0), result.get("attempts", 0)
		]
		result_dialog.popup_centered()


func _play_result_encouragement(result: Dictionary) -> void:
	if low_score_voice_started or not RESULTS_SCRIPT.should_play_catch_low_score(result):
		return
	if not ResourceLoader.exists(RESULTS_SCRIPT.LOW_SCORE_CATCH_VOICE_PATH):
		return
	var clip := load(RESULTS_SCRIPT.LOW_SCORE_CATCH_VOICE_PATH) as AudioStream
	if clip == null:
		return
	if not is_instance_valid(low_score_voice_player):
		low_score_voice_player = AudioStreamPlayer.new()
		low_score_voice_player.name = "PreviewLowScoreVoicePlayer"
		low_score_voice_player.bus = "KilosSFX" if AudioServer.get_bus_index("KilosSFX") >= 0 else "Master"
		host.add_child(low_score_voice_player)
	low_score_voice_player.stream = clip
	low_score_voice_started = true
	low_score_voice_player.play()


func _stop_result_encouragement() -> void:
	if is_instance_valid(low_score_voice_player):
		low_score_voice_player.stop()
		low_score_voice_player.stream = null


func _resume() -> void:
	if is_instance_valid(game):
		game.call("_resume")


func _restart() -> void:
	_stop_result_encouragement()
	low_score_voice_started = false
	if is_instance_valid(game):
		game.call("set_context", _game_context())
		game.set_process(true)


func _exit_game() -> void:
	_stop_result_encouragement()
	quit(0)
