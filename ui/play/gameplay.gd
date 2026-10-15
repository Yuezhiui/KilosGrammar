extends Control

# Entry point used by main_menu.gd. The three playable 2D activities own
# their own collisions and round logic; this wrapper preserves the existing
# Student Setup -> Activity -> Camera Preview -> Ready -> Gameplay routes.
signal requested(target: String, payload: Dictionary)

const GAME_SCENES := {
	"Catch the Word": "res://ui/minigames/catch_word.tscn",
	"Balloon Popping": "res://ui/minigames/balloon_popping.tscn",
	"Human Plane": "res://ui/minigames/human_plane.tscn"
}

var context: Dictionary = {}
var active_game: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not context.is_empty():
		_mount_game()


func set_context(new_context: Dictionary) -> void:
	context.merge(new_context, true)
	if is_node_ready():
		_mount_game()


func get_context() -> Dictionary:
	if is_instance_valid(active_game) and active_game.has_method("get_context"):
		return active_game.call("get_context") as Dictionary
	return context.duplicate(true)


func _mount_game() -> void:
	if is_instance_valid(active_game):
		remove_child(active_game)
		active_game.queue_free()
		active_game = null
	var activity := String(context.get("activity", "Catch the Word"))
	if not GAME_SCENES.has(activity):
		activity = "Catch the Word"
	var game_path: String = GAME_SCENES[activity]
	if not ResourceLoader.exists(game_path):
		push_error("Playable KilosGrammar scene missing: " + game_path)
		return
	var scene := load(game_path) as PackedScene
	if scene == null:
		push_error("Could not load KilosGrammar game: " + game_path)
		return
	active_game = scene.instantiate() as Control
	if active_game == null:
		push_error("Game scene must inherit Control: " + game_path)
		return
	active_game.name = "ActiveMiniGame"
	add_child(active_game)
	active_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if active_game.has_signal("requested"):
		active_game.connect("requested", Callable(self, "_relay_navigation"))
	if active_game.has_method("set_context"):
		active_game.call("set_context", context.duplicate(true))


func _relay_navigation(route: String, payload: Dictionary) -> void:
	# The results are real keyboard-play scores, but are still UNSAVED until
	# local PostgreSQL persistence is implemented in a later milestone.
	var outgoing := get_context()
	outgoing.merge(payload, true)
	outgoing["activity"] = String(context.get("activity", "Catch the Word"))
	outgoing["gameplay_implemented"] = true
	outgoing["demo_mode"] = true
	requested.emit(route, outgoing)


func _finish_round() -> void:
	if is_instance_valid(active_game) and active_game.has_method("_finish_round"):
		active_game.call("_finish_round")


func _pause() -> void:
	if is_instance_valid(active_game) and active_game.has_method("_pause"):
		active_game.call("_pause")
	else:
		requested.emit("pause", get_context())


func _resume() -> void:
	# main_menu reuses this same wrapper and live minigame after Pause.
	if is_instance_valid(active_game) and active_game.has_method("_resume"):
		active_game.call("_resume")


func set_body_x(normalized_x: float) -> void:
	# Future camera bridge: forward body horizontal position without assuming
	# a camera is connected or calibrated today.
	if is_instance_valid(active_game) and active_game.has_method("set_body_x"):
		active_game.call("set_body_x", normalized_x)
