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
var smooth_x := 0.0
var last_pose_valid := false
var arms_were_up := false
var last_fire_ms := -2000


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
	outgoing["camera_live"] = bool(context.get("camera_live", false)) and PoseService.active
	requested.emit(route, outgoing)


func _process(delta: float) -> void:
	# Godot renders/smooths at up to 60 FPS independently of YOLO inference.
	# No stale pose is allowed to keep moving the player.
	if bool(context.get("keyboard_mode", false)) or not bool(context.get("camera_live", false)):
		return
	if not is_instance_valid(active_game):
		return
	if not PoseService.has_valid_pose() or not bool(PoseService.calibration.get("valid", false)):
		if last_pose_valid:
			if active_game.has_method("clear_body_input"):
				active_game.call("clear_body_input")
			else:
				set_body_x(0.0)
		last_pose_valid = false
		arms_were_up = false
		return
	var raw_x := PoseService.normalized_body_x()
	if not last_pose_valid:
		smooth_x = raw_x
	else:
		smooth_x = lerpf(smooth_x, raw_x, 1.0 - exp(-maxf(delta, 0.0) * 14.0))
	set_body_x(smooth_x)
	last_pose_valid = true
	# Avoid repeated shots while arms remain raised; lift both hands again
	# after lowering them to trigger the next shot.
	var both_raised := bool(PoseService.current_status.get("raised", false))
	if String(context.get("activity", "")) == "Balloon Popping" and both_raised and not arms_were_up:
		if Time.get_ticks_msec() - last_fire_ms >= 800 and active_game.has_method("_launch_projectile"):
			active_game.call("_launch_projectile")
			last_fire_ms = Time.get_ticks_msec()
	arms_were_up = both_raised


func _exit_tree() -> void:
	# The router parks this live wrapper on Pause; it is only freed when
	# the player leaves gameplay permanently.
	if PoseService.active:
		PoseService.stop_camera()


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
