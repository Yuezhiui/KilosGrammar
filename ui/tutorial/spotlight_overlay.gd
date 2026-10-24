extends CanvasLayer
## Reusable, scene-authored spotlight tutorial placed above an already mounted game.
##
## Host usage:
##   var tutorial = preload("res://ui/tutorial/spotlight_overlay.tscn").instantiate()
##   add_child(tutorial)
##   tutorial.finished.connect(_resume_round)
##   tutorial.skipped.connect(_resume_round)
##   tutorial.start_tutorial("catch_word", "seconds", {
##       "prompt": game.get_node("HUDLayer/HUD/PromptLabel"),
##       "mode": game.get_node("HUDLayer/HUD/TimerPlaque")
##   })
##
## The host holds countdowns, spawns and life deductions until finished/skipped.
## Keep pose tracking/camera processing active during the tutorial. Do not pause
## the SceneTree, because camera and pose processing may need it.

signal tutorial_started(game_type: String, active_mode: String)
signal step_changed(index: int, step_id: String)
signal finished
signal skipped

@export_group("Spotlight Appearance")
@export_range(0.0, 80.0, 1.0) var spotlight_padding_px: float = 12.0
@export_range(0.0, 100.0, 1.0) var spotlight_corner_radius_px: float = 18.0
@export_range(0.0, 30.0, 1.0) var spotlight_feather_px: float = 4.0
@export_group("Captions and Controls")
@export var next_button_text: String = "NEXT  →"
@export var last_button_text: String = "START GAME  ✓"
@export_group("Optional Body Movement Practice")
@export_range(0.1, 0.9, 0.01) var lane_threshold: float = 0.40
@export_range(0.1, 2.0, 0.05) var pose_hold_seconds: float = 0.40
@export_group("ElevenLabs Voice Clips (optional)")
## Dictionary keys are step IDs returned by get_step_ids(); assign AudioStream
## resources here in the Inspector. Missing clips remain silent with captions.
@export var voice_clips: Dictionary[String, AudioStream] = {}
## Alternatively enter imported res://path/to/clip.ogg/mp3/wav filenames here.
## Paths can also be passed in audio_clips to start_tutorial().
@export var voice_clip_paths: Dictionary[String, String] = {}

const FOCUS_NODE_NAMES := {
	"prompt": "Prompt",
	"play_area": "PlayArea",
	"mode_seconds": "Seconds",
	"mode_lives": "Lives",
	"score": "Score",
	"pause": "Pause",
}
const FOCUS_GAME_NODES := {
	"catch_word": "CatchWord",
	"balloon_popping": "BalloonPopping",
	"human_plane": "HumanPlane",
}

@onready var _screen: Control = $Overlay
@onready var _dim: ColorRect = $Overlay/DimMask
@onready var _arrows: Control = $Overlay/GuideArrows
@onready var _focus_regions: Control = $Overlay/FocusRegions
@onready var _header: Label = $Overlay/CaptionCard/Header
@onready var _caption: Label = $Overlay/CaptionCard/Caption
@onready var _step_counter: Label = $Overlay/CaptionCard/StepCounter
@onready var _next_button: Button = $Overlay/CaptionCard/NextButton
@onready var _back_button: Button = $Overlay/CaptionCard/BackButton
@onready var _replay_button: Button = $Overlay/CaptionCard/ReplayButton
@onready var _skip_button: Button = $Overlay/CaptionCard/SkipButton
@onready var _voice_player: AudioStreamPlayer = $Overlay/VoicePlayer
@onready var _movement_feedback: Panel = $Overlay/MovementFeedbackPanel
@onready var _movement_status: Label = $Overlay/MovementFeedbackPanel/MovementStatus

var _active: bool = false
var _game: String = "catch_word"
var _mode: String = "seconds"
var _step_index: int = 0
var _steps: Array[Dictionary] = []
var _target_nodes: Dictionary = {}
var _session_audio_clips: Dictionary = {}
var _last_focus_rect: Rect2 = Rect2()
var _last_mask_size: Vector2 = Vector2.ZERO
var _visited_lanes: Dictionary = {}
var _pose_candidate: String = ""
var _pose_candidate_duration: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_next_button.pressed.connect(go_next)
	_back_button.pressed.connect(go_back)
	_replay_button.pressed.connect(replay)
	_skip_button.pressed.connect(skip)
	_screen.resized.connect(_refresh_spotlight)
	_dim.resized.connect(_refresh_spotlight)
	visible = false
	set_process(false)


## game_type: catch_word, balloon_popping or human_plane (display names accepted).
## active_mode: seconds OR lives. Only the active rule appears in the steps.
## focus_targets: optional CanvasItem/Rect2 values with keys prompt, play_area,
## mode, mode_seconds, mode_lives, score, pause. An absent/unusable target
## uses the individually draggable FocusRegions/<Game>/<Spotlight> scene nodes.
## audio_clips: optional {step_id: AudioStream OR "res://.../clip.ogg"}.
func start_tutorial(game_type: String, active_mode: String,
		focus_targets: Dictionary = {}, audio_clips: Dictionary = {}) -> void:
	_game = _normalize_game(game_type)
	_mode = "lives" if active_mode.to_lower().contains("liv") else "seconds"
	_target_nodes = focus_targets.duplicate()
	_session_audio_clips = audio_clips.duplicate()
	_steps = _build_steps(_game, _mode)
	_step_index = 0
	_last_focus_rect = Rect2()
	_last_mask_size = Vector2.ZERO
	_visited_lanes.clear()
	_pose_candidate = ""
	_pose_candidate_duration = 0.0
	_active = true
	visible = true
	set_process(true)
	tutorial_started.emit(_game, _mode)
	_render_step()
	_next_button.grab_focus.call_deferred()


func go_next() -> void:
	if not _active:
		return
	if _step_index + 1 >= _steps.size():
		_end_tutorial(false)
		return
	_step_index += 1
	_render_step()


func go_back() -> void:
	if not _active or _step_index == 0:
		return
	_step_index -= 1
	_render_step()


func replay() -> void:
	if not _active:
		return
	# Narration replay never changes the student's current step or spotlight.
	_play_optional_voice(get_current_step_id())


func skip() -> void:
	if _active:
		_end_tutorial(true)


func is_tutorial_active() -> bool:
	return _active


func get_current_step_id() -> String:
	if not _active or _step_index >= _steps.size():
		return ""
	return String(_steps[_step_index]["id"])


func get_step_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for step in _steps:
		result.append(String(step["id"]))
	return result


## Returns the actual hole bounds in overlay-local scene pixels; useful for QA.
func get_spotlight_rect() -> Rect2:
	return _last_focus_rect


func _process(delta: float) -> void:
	if _active:
		_refresh_spotlight()
		_update_live_movement(delta)


func _unhandled_key_input(event: InputEvent) -> void:
	if not _active or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		skip()
	elif _game != "human_plane" and String(_steps[_step_index]["focus"]) == "play_area" and event.keycode in [KEY_A, KEY_S, KEY_D]:
		match event.keycode:
			KEY_A:
				_mark_lane("LEFT")
			KEY_S:
				_mark_lane("CENTER")
			KEY_D:
				_mark_lane("RIGHT")
	elif event.keycode == KEY_LEFT:
		go_back()
	elif event.keycode == KEY_RIGHT:
		go_next()
	elif event.keycode == KEY_HOME:
		replay()
	else:
		return
	get_viewport().set_input_as_handled()


func _normalize_game(raw: String) -> String:
	var normalized := raw.strip_edges().to_lower().replace(" ", "_").replace("-", "_")
	match normalized:
		"catch_the_word", "catch_word", "word_catcher":
			return "catch_word"
		"balloon_catcher", "balloon_popping", "balloon_pop", "balloon_catch":
			return "balloon_popping"
		"human_plane", "human_airplane":
			return "human_plane"
		_:
			push_warning("Unknown spotlight game '%s'; using catch_word layout." % raw)
			return "catch_word"


func _build_steps(game_type: String, active_mode: String) -> Array[Dictionary]:
	var game_copy := {
		"catch_word": {
			"prompt_title": "READ THE QUESTION",
			"prompt": "Look at the question on the board. Find the word that matches the grammar topic.",
			"movement_title": "MOVE TO CATCH THE WORD",
			"movement": "Move left, center, or right to catch the correct falling word in your basket.",
			"score": "Each correct word adds to your score. Keep your eyes on the question!",
			"pause": "Use Pause whenever you need a break from Catch the Word.",
		},
		"balloon_popping": {
			"prompt_title": "FIND THE MATCHING WORD",
			"prompt": "Check the question on the board. Look for the balloon with the matching word.",
				"movement_title": "RAISE ONE HAND TO SHOOT",
				"movement": "Move your body to aim. Raise either hand for ONE shot, then lower it and wait 1.5 seconds before raising it again.",
			"score": "Watch your points here as you pop balloons with correct answers.",
			"pause": "Use Pause if you want to stop the balloon activity for a moment.",
		},
		"human_plane": {
			"prompt_title": "FOLLOW THE FLIGHT MISSION",
			"prompt": "Get ready for your flight challenge. Read the activity instructions first.",
			"movement_title": "SPREAD YOUR ARMS AND STEP SIDEWAYS",
			"movement": "Spread BOTH arms wide like airplane wings, then STEP LEFT or RIGHT to fly smoothly. Stand at your measured CENTER to return to the middle. Lower your arms to stop the plane; raise them wide again to resume at your current position.",
			"score": "Watch this part of the screen for your progress during the flight.",
			"pause": "Use Pause if you need to stop flying for a moment.",
		},
	}
	var copy: Dictionary = game_copy[game_type]
	var rule_title := "60 SECONDS TO PLAY" if active_mode == "seconds" else "THREE LIVES TO PLAY"
	var rule_caption := (
		"The round lasts 60 seconds. Answer as many questions as you can before time runs out."
		if active_mode == "seconds"
		else "You have three lives. Incorrect attempts can cost a life, so choose carefully."
	)
	return [
		{"id": game_type + "_prompt", "title": copy["prompt_title"], "caption": copy["prompt"],
			"focus": "prompt", "arrow": "PromptArrow"},
		{"id": game_type + "_movement", "title": copy["movement_title"], "caption": copy["movement"],
			"focus": "play_area", "arrow": "PlayArrow"},
		{"id": game_type + "_" + active_mode, "title": rule_title, "caption": rule_caption,
			"focus": "mode_" + active_mode, "arrow": "ModeArrow"},
		{"id": game_type + "_score", "title": "CHECK YOUR SCORE",
			"caption": copy["score"], "focus": "score", "arrow": "ScoreArrow"},
		{"id": game_type + "_pause", "title": "TAKE A BREAK",
			"caption": copy["pause"], "focus": "pause",
			"arrow": "PlanePauseArrow" if game_type == "human_plane" else "PauseArrow"},
	]


func _render_step() -> void:
	if not _active:
		return
	var step: Dictionary = _steps[_step_index]
	_header.text = String(step["title"])
	_caption.text = String(step["caption"])
	_step_counter.text = "STEP %d OF %d" % [_step_index + 1, _steps.size()]
	_back_button.disabled = _step_index == 0
	_next_button.text = last_button_text if _step_index == _steps.size() - 1 else next_button_text
	_movement_feedback.visible = String(step["focus"]) == "play_area"
	if _movement_feedback.visible:
		_refresh_movement_caption()
	for node in _arrows.get_children():
		if node is CanvasItem:
			var arrow_name: String = String(step["arrow"])
			if _game == "catch_word" and arrow_name in ["PromptArrow", "PlayArrow"]:
				arrow_name = "CatchWord" + arrow_name
			(node as CanvasItem).visible = node.name == arrow_name
	_refresh_spotlight()
	_play_optional_voice(String(step["id"]))
	step_changed.emit(_step_index, String(step["id"]))


func _update_live_movement(delta: float) -> void:
	if String(_steps[_step_index]["focus"]) != "play_area":
		return
	var pose := get_node_or_null("/root/PoseService")
	if pose == null or not pose.has_method("has_valid_pose") or not pose.has_method("normalized_body_x"):
		return
	if not bool(pose.call("has_valid_pose")) or not bool(pose.get("calibration").get("valid", false)):
		_pose_candidate = ""
		_pose_candidate_duration = 0.0
		return
	# All three games share measured CENTER/RIGHT/LEFT camera positions. Human
	# Plane additionally requires BOTH arms spread wide for lane practice;
	# lowered/occluded arms cannot advance the spotlight's movement lesson.
	var x: float = float(pose.call("normalized_body_x"))
	if _game == "human_plane" and not bool(pose.call("has_airplane_pose")):
		_pose_candidate = ""
		_pose_candidate_duration = 0.0
		return
	var lane := "LEFT" if x <= -lane_threshold else ("RIGHT" if x >= lane_threshold else "CENTER")
	if lane != _pose_candidate:
		_pose_candidate = lane
		_pose_candidate_duration = 0.0
	else:
		_pose_candidate_duration += delta
	if _pose_candidate_duration >= pose_hold_seconds:
		_mark_lane(lane)


func _mark_lane(lane: String) -> void:
	if _visited_lanes.has(lane):
		return
	_visited_lanes[lane] = true
	_refresh_movement_caption()


func _refresh_movement_caption() -> void:
	var all_lanes: Array[String] = ["LEFT", "CENTER", "RIGHT"]
	var indicators := PackedStringArray()
	for lane in all_lanes:
		indicators.append(("✓ " if _visited_lanes.has(lane) else "○ ") + lane)
	if _visited_lanes.size() == 3:
		_movement_status.text = "GREAT! ALL THREE LANES!\n" + "   ".join(indicators)
	else:
		var pose := get_node_or_null("/root/PoseService")
		var camera_ready := pose != null and pose.has_method("has_valid_pose") and bool(pose.call("has_valid_pose"))
		var hint := ("Spread BOTH arms and STEP to LEFT / CENTER / RIGHT." if camera_ready else "Stand in CENTER and spread both arms when the camera is ready.") if _game == "human_plane" else ("Move and hold each pose." if camera_ready else "Ask your teacher to check the camera.")
		_movement_status.text = hint + "\n" + "   ".join(indicators)


func _refresh_spotlight() -> void:
	if not _active:
		return
	var focus_key := String(_steps[_step_index]["focus"])
	var target: Variant = _target_nodes.get(focus_key)
	if target == null and focus_key.begins_with("mode_"):
		target = _target_nodes.get("mode")
	var rect := _rect_for_target(target)
	# Human Plane currently supplies its full-screen game root for play_area.
	# That is a valid Control, but spotlighting the whole viewport would erase
	# the dim and stop emphasizing the player's movement area. Use the editor-
	# authored, individually draggable activity focus region in that case.
	if focus_key == "play_area" and rect.size.x >= _dim.size.x * 0.9 and rect.size.y >= _dim.size.y * 0.9:
		rect = Rect2()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		rect = _rect_for_target(_fallback_region(focus_key))
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	if rect.is_equal_approx(_last_focus_rect) and _dim.size.is_equal_approx(_last_mask_size):
		return
	_last_focus_rect = rect
	_last_mask_size = _dim.size
	var scene_size := Vector2(maxf(1.0, _dim.size.x), maxf(1.0, _dim.size.y))
	var material := _dim.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("hole_center", rect.get_center() / scene_size)
	material.set_shader_parameter("hole_half_size", rect.size * 0.5 / scene_size)
	material.set_shader_parameter("hole_roundness", spotlight_corner_radius_px / minf(scene_size.x, scene_size.y))
	material.set_shader_parameter("hole_feather", spotlight_feather_px / minf(scene_size.x, scene_size.y))


func _fallback_region(focus_key: String) -> Control:
	var group_name := String(FOCUS_GAME_NODES.get(_game, "CatchWord"))
	var region_name := String(FOCUS_NODE_NAMES.get(focus_key, "Prompt"))
	return _focus_regions.get_node_or_null(NodePath(group_name + "/" + region_name)) as Control


func _rect_for_target(source: Variant) -> Rect2:
	if source is Rect2:
		return (source as Rect2).grow(spotlight_padding_px)
	if not source is CanvasItem or not is_instance_valid(source):
		return Rect2()
	var item := source as CanvasItem
	if not item.is_inside_tree():
		return Rect2()
	var local := Rect2()
	if item is Control:
		var control := item as Control
		local = Rect2(Vector2.ZERO, control.size)
	elif item is Sprite2D:
		local = (item as Sprite2D).get_rect()
	else:
		return Rect2()
	if local.size.x <= 0.0 or local.size.y <= 0.0:
		return Rect2()
	var into_overlay: Transform2D = _dim.get_global_transform_with_canvas().affine_inverse() * item.get_global_transform_with_canvas()
	var a: Vector2 = into_overlay * local.position
	var b: Vector2 = into_overlay * Vector2(local.end.x, local.position.y)
	var c: Vector2 = into_overlay * Vector2(local.position.x, local.end.y)
	var d: Vector2 = into_overlay * local.end
	var min_corner := Vector2(minf(minf(a.x, b.x), minf(c.x, d.x)), minf(minf(a.y, b.y), minf(c.y, d.y)))
	var max_corner := Vector2(maxf(maxf(a.x, b.x), maxf(c.x, d.x)), maxf(maxf(a.y, b.y), maxf(c.y, d.y)))
	return Rect2(min_corner, max_corner - min_corner).grow(spotlight_padding_px)


func _play_optional_voice(step_id: String) -> void:
	_voice_player.stop()
	_voice_player.stream = null
	var source: Variant = _session_audio_clips.get(step_id)
	if source == null:
		source = voice_clips.get(step_id)
	if source == null:
		source = voice_clip_paths.get(step_id)
	if source is AudioStream:
		_voice_player.stream = source as AudioStream
	elif source is String and not String(source).is_empty():
		if ResourceLoader.exists(source):
			_voice_player.stream = load(source) as AudioStream
	if _voice_player.stream != null:
		_voice_player.play()


func _end_tutorial(was_skipped: bool) -> void:
	_active = false
	set_process(false)
	_voice_player.stop()
	visible = false
	if was_skipped:
		skipped.emit()
	else:
		finished.emit()
