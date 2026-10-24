extends Control

# Entry point used by main_menu.gd. The three playable 2D activities own
# their own collisions and round logic; this wrapper preserves the existing
# Student Setup -> Activity -> Calibration -> Countdown -> Gameplay routes.
signal requested(target: String, payload: Dictionary)

const GAME_SCENES := {
	"Catch the Word": "res://ui/minigames/catch_word.tscn",
	"Balloon Popping": "res://ui/minigames/balloon_popping.tscn",
	"Human Plane": "res://ui/minigames/human_plane.tscn"
}
const SPOTLIGHT_SCENE := "res://ui/tutorial/spotlight_overlay.tscn"
const COUNTDOWN_SCENE := preload("res://ui/play/guided_countdown.tscn")

var context: Dictionary = {}
var active_game: Control
var smooth_x := 0.0
var last_pose_valid := false
var missing_pose_seconds := 0.0
var tracking_suspended := false
@onready var tracking_notice: Control = $TrackingNoticeLayer/TrackingNotice
var tutorial_layer: CanvasLayer
var spotlight_overlay: CanvasLayer
var countdown_panel: Control
var countdown_timer: Timer
var countdown_value := 0
var guided_stage := "" # "tutorial" or "countdown" until the round becomes live.
var _retain_camera_for_restart := false


func preserve_camera_for_restart() -> void:
	# A paused round is being replaced while retaining the same calibrated
	# camera. All other exits continue to shut tracking down normally.
	_retain_camera_for_restart = true


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
	_clear_guided_ui()
	# A fresh minigame has no prior camera steering history. Do not reuse the
	# previous activity's last smoothing target during countdown/recalibration.
	smooth_x = 0.0
	missing_pose_seconds = 0.0
	tracking_suspended = false
	last_pose_valid = false
	tracking_notice.visible = false
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
	var guided := bool(context.get("guided_tutorial", false))
	var count_in := guided or bool(context.get("start_countdown", false))
	if count_in:
		# Freeze the whole minigame, including input, physics, animations and
		# scoring, before its first frame. The camera service is a separate
		# autoload and remains live for the on-screen movement instructions.
		active_game.process_mode = Node.PROCESS_MODE_DISABLED
		guided_stage = "tutorial" if guided else "countdown"
	add_child(active_game)
	active_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if active_game.has_signal("requested"):
		active_game.connect("requested", Callable(self, "_relay_navigation"))
	if active_game.has_method("set_context"):
		active_game.call("set_context", context.duplicate(true))
	# Never carry over a previous activity's live gesture eligibility. A new
	# game must observe a fresh, verified pose and (for shooting) a new rise.
	_clear_gesture_input()
	if guided:
		call_deferred("_begin_guided_tutorial")
	elif count_in:
		call_deferred("_begin_countdown")


func _begin_guided_tutorial() -> void:
	if guided_stage != "tutorial" or not is_instance_valid(active_game):
		return
	if not ResourceLoader.exists(SPOTLIGHT_SCENE):
		push_error("Guided spotlight scene is missing: " + SPOTLIGHT_SCENE)
		return
	var scene := load(SPOTLIGHT_SCENE) as PackedScene
	if scene == null:
		push_error("Cannot load guided spotlight scene: " + SPOTLIGHT_SCENE)
		return
	spotlight_overlay = scene.instantiate() as CanvasLayer
	if spotlight_overlay == null:
		push_error("Guided spotlight scene must have a CanvasLayer root")
		return
	spotlight_overlay.name = "GuidedSpotlight"
	add_child(spotlight_overlay)
	spotlight_overlay.connect("finished", Callable(self, "_on_spotlight_finished"))
	spotlight_overlay.connect("skipped", Callable(self, "_on_spotlight_finished"))
	spotlight_overlay.call("start_tutorial", _spotlight_activity(), _current_game_mode(), _spotlight_targets())


func _spotlight_activity() -> String:
	match String(context.get("activity", "Catch the Word")):
		"Balloon Popping":
			return "balloon_popping"
		"Human Plane":
			return "human_plane"
		_:
			return "catch_word"


func _current_game_mode() -> String:
	var raw := String(context.get("game_mode", context.get("mode", "Seconds"))).strip_edges().to_lower()
	return "lives" if raw in ["lives", "life", "hearts"] else "seconds"


func _spotlight_targets() -> Dictionary:
	var activity := String(context.get("activity", "Catch the Word"))
	var mode_path := "LivesPlaque" if _current_game_mode() == "lives" else "TimerPlaque"
	var paths: Dictionary
	match activity:
		"Catch the Word":
			paths = {
				"prompt": "HUDLayer/HUD/PromptLabel", "play_area": "CharacterRig/Basket",
				"mode": "HUDLayer/HUD/" + mode_path,
				"score": "ScoreDrawLayer/ScorePlaque", "pause": "HUDLayer/HUD/PausePlaque"
			}
		"Balloon Popping":
			paths = {
				"prompt": "HudLayer/PromptLabel", "play_area": "LauncherLayer/Launcher",
				"mode": "HudLayer/" + mode_path,
				"score": "HudLayer/CarnivalScore", "pause": "HudLayer/PauseButton"
			}
		"Human Plane":
			# Human Plane uses the exact Catch the Word HUD clone. Spotlight
			# must target the current scene-authored plaques, not removed HUD art.
				paths = {
				"prompt": "HUDLayer/HUD/PromptLabel", "play_area": "PlaneRig",
				"mode": "HUDLayer/HUD/" + mode_path,
				"score": "HUDLayer/HUD/ScorePlaque",
				"pause": "HUDLayer/HUD/PauseButton"
				}
		_:
			paths = {"play_area": "."}
	var targets := {}
	for key in paths:
		var target := active_game.get_node_or_null(String(paths[key])) as CanvasItem
		if target != null:
			targets[key] = target
	return targets


func _ensure_tutorial_layer() -> void:
	if is_instance_valid(tutorial_layer):
		return
	# Render over HUD CanvasLayers (Catch HUD is layer 20) without moving
	# or resizing the designer's individual spotlight/countdown UI elements.
	tutorial_layer = CanvasLayer.new()
	tutorial_layer.name = "GuidedTutorialLayer"
	tutorial_layer.layer = 100
	add_child(tutorial_layer)


func _on_spotlight_finished() -> void:
	if guided_stage != "tutorial":
		return
	guided_stage = "countdown"
	if is_instance_valid(spotlight_overlay):
		spotlight_overlay.queue_free()
		spotlight_overlay = null
	_begin_countdown()


func _begin_countdown() -> void:
	if guided_stage != "countdown" or not is_instance_valid(active_game):
		return
	if is_instance_valid(countdown_panel):
		return
	_ensure_tutorial_layer()
	countdown_panel = COUNTDOWN_SCENE.instantiate() as Control
	if countdown_panel == null:
		push_error("Could not instantiate guided countdown scene")
		return
	countdown_panel.name = "GuidedCountdown"
	tutorial_layer.add_child(countdown_panel)
	countdown_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	countdown_timer = countdown_panel.get_node("CountdownTimer") as Timer
	countdown_timer.timeout.connect(_on_countdown_tick)
	countdown_value = 3
	_update_countdown_text()
	countdown_timer.start()


func _on_countdown_tick() -> void:
	if guided_stage != "countdown":
		return
	countdown_value -= 1
	if countdown_value <= 0:
		_complete_countdown_start()
	else:
		_update_countdown_text()


func _update_countdown_text() -> void:
	if is_instance_valid(countdown_panel):
		var label := countdown_panel.get_node_or_null("CountdownNumber") as Label
		if label != null:
			label.text = str(countdown_value)


func _complete_countdown_start() -> void:
	if guided_stage != "countdown":
		return
	guided_stage = "completed"
	_clear_guided_ui()
	if is_instance_valid(active_game):
		active_game.process_mode = Node.PROCESS_MODE_INHERIT


func _clear_guided_ui() -> void:
	if is_instance_valid(spotlight_overlay):
		remove_child(spotlight_overlay)
		spotlight_overlay.queue_free()
	if is_instance_valid(countdown_timer):
		countdown_timer.stop()
	if is_instance_valid(tutorial_layer):
		remove_child(tutorial_layer)
		tutorial_layer.queue_free()
	tutorial_layer = null
	spotlight_overlay = null
	countdown_panel = null
	countdown_timer = null
	countdown_value = 0
	guided_stage = ""


func _relay_navigation(route: String, payload: Dictionary) -> void:
		# The results are real in-game scores, but are still UNSAVED until
	# local PostgreSQL persistence is implemented in a later milestone.
	var outgoing := get_context()
	outgoing.merge(payload, true)
	outgoing["activity"] = String(context.get("activity", "Catch the Word"))
	outgoing["gameplay_implemented"] = true
	outgoing["demo_mode"] = true
	outgoing["camera_live"] = bool(context.get("camera_live", false)) and PoseService.active
	requested.emit(route, outgoing)


func _process(delta: float) -> void:
	# Camera-only gameplay: no keyboard steering or demo movement fallback.
	# Godot animates up to 60 FPS independently from YOLO inference.
	if not bool(context.get("camera_live", false)):
		return
	if not is_instance_valid(active_game):
		return
	if not PoseService.has_valid_pose() or not bool(PoseService.calibration.get("valid", false)):
		_clear_gesture_input()
		missing_pose_seconds += maxf(delta, 0.0)
		if last_pose_valid:
			if active_game.has_method("clear_body_input"):
				active_game.call("clear_body_input")
			else:
				set_body_x(0.0)
		last_pose_valid = false
		# A short grace period prevents flicker between YOLO inference frames.
		# While the student steps back into view, the entire minigame (including
		# its countdown/lives) freezes without affecting the global PoseService.
		if missing_pose_seconds >= 0.65:
			tracking_notice.visible = guided_stage not in ["tutorial", "countdown"]
			if not tracking_suspended and guided_stage not in ["tutorial", "countdown"]:
				active_game.process_mode = Node.PROCESS_MODE_DISABLED
				tracking_suspended = true
		return
	missing_pose_seconds = 0.0
	tracking_notice.visible = false
	if tracking_suspended:
		tracking_suspended = false
		if guided_stage not in ["tutorial", "countdown"]:
			active_game.process_mode = Node.PROCESS_MODE_INHERIT
	# Gestures require their OWN short freshness window even when the regular
	# calibrated position still has a temporary tracking grace period.
	_update_gesture_input()
	if String(context.get("activity", "")) == "Human Plane":
		# Three measured CENTER / RIGHT / LEFT positions now steer the plane,
		# matching Catch the Word. BOTH arms extended are a safety-enable gate,
		# not a gyroscope: lowered arms freeze the current aircraft position.
		# Never let a stale or uncertain arm frame update the target.
		var wide_arms: bool = PoseService.has_airplane_pose()
		if wide_arms and guided_stage != "countdown":
			var raw_plane_x: float = PoseService.normalized_body_x()
			# Smooth noisy YOLO measurements each rendered frame, while the game
			# separately glides its aircraft toward the calibrated target.
			# Keep the previous filter state across arm-lowering for a soft
			# reacquisition rather than a one-frame lateral jump.
			smooth_x = lerpf(smooth_x, raw_plane_x,
				1.0 - exp(-maxf(delta, 0.0) * 12.0))
			set_body_x(smooth_x)
		last_pose_valid = true
		_preview_guided_movement(delta)
		return
	var raw_x: float = PoseService.normalized_body_x()
	if not last_pose_valid:
		smooth_x = raw_x
	else:
		smooth_x = lerpf(smooth_x, raw_x, 1.0 - exp(-maxf(delta, 0.0) * 14.0))
	set_body_x(smooth_x)
	last_pose_valid = true
	_preview_guided_movement(delta)


func _clear_gesture_input() -> void:
	if not is_instance_valid(active_game):
		return
	if active_game.has_method("set_airplane_pose_active"):
		active_game.call("set_airplane_pose_active", false)
	if active_game.has_method("set_hand_raise_state"):
		# The second argument indicates no valid SHOOTING observation. It must
		# never count an occlusion as the student's deliberate hand-lowering.
		active_game.call("set_hand_raise_state", false, false)


func _update_gesture_input() -> void:
	if not is_instance_valid(active_game):
		return
	var fresh: bool = PoseService.has_fresh_gesture_pose()
	match String(context.get("activity", "")):
		"Human Plane":
			var eligible: bool = fresh and PoseService.has_airplane_pose() \
				and guided_stage != "countdown"
			if active_game.has_method("set_airplane_pose_active"):
				active_game.call("set_airplane_pose_active", eligible)
		"Balloon Popping":
			if active_game.has_method("set_hand_raise_state"):
				# Paused/tutorial/countdown sessions do not launch projectiles; only
				# the live minigame owns its one-shot edge and 1.5-second cooldown.
				# A lost wrist is UNKNOWN, not a deliberate hand-down event.
				var allowed: bool = fresh and PoseService.has_valid_hand_observation() \
					and guided_stage not in ["tutorial", "countdown"]
				active_game.call("set_hand_raise_state", allowed and PoseService.has_hand_raised(), allowed)


func _preview_guided_movement(delta: float) -> void:
	if guided_stage != "tutorial" or not is_instance_valid(active_game):
		return
	# Reuse each minigame's movement-only helpers while its process tree is
	# disabled. This animates calibrated body steering during the spotlight
	# without running timers, projectiles, collisions, scores, or lives.
	match String(context.get("activity", "Catch the Word")):
		"Catch the Word":
			active_game.call("_update_basket", delta)
			active_game.call("_sync_character_position")
		"Balloon Popping":
			active_game.call("_update_launcher", delta)
		"Human Plane":
			active_game.call("_update_plane_motion", delta)
			active_game.queue_redraw()


func _exit_tree() -> void:
	# The router parks this live wrapper on Pause; it is only freed when
	# the player leaves gameplay permanently.
	if PoseService.active and not _retain_camera_for_restart:
		PoseService.stop_camera()


func _finish_round() -> void:
	if is_instance_valid(active_game) and active_game.has_method("_finish_round"):
		active_game.call("_finish_round")


func _pause() -> void:
	if guided_stage in ["tutorial", "countdown"]:
		return
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
