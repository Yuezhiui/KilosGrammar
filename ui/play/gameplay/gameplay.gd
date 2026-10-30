extends Control

# Entry point used by main_menu.gd. The three playable 2D activities own
# their own collisions and round logic; this wrapper preserves the existing
# Student Setup -> Activity -> Calibration -> Countdown -> Gameplay routes.
signal requested(target: String, payload: Dictionary)

const GAME_SCENES := {
	"Catch the Word": "res://ui/minigames/catch_the_word/catch_word.tscn",
	"Balloon Popping": "res://ui/minigames/balloon_popping/balloon_popping.tscn",
	"Human Plane": "res://ui/minigames/human_plane/human_plane.tscn"
}
const COUNTDOWN_SCENE := preload("res://ui/play/gameplay/guided_countdown.tscn")
const GameAudio = preload("res://ui/shared/game_audio.gd")

var context: Dictionary = {}
var active_game: Control
var smooth_x := 0.0
var last_pose_valid := false
var missing_pose_seconds := 0.0
var confirmed_missing_student_seconds := 0.0
var saw_student_in_live_round := false
var tracking_suspended := false
@onready var tracking_notice: Control = $TrackingNoticeLayer/TrackingNotice
var countdown_layer: CanvasLayer
var countdown_panel: Control
var countdown_timer: Timer
var countdown_value := 0
var guided_stage := "" # "tutorial" -> "countdown" -> live gameplay.
var _mount_generation := 0
var _retain_camera_for_restart := false
var _game_music: Node
var _countdown_requires_locked_pose := false
var _countdown_waiting_for_pose := false
var _paused_canvas_layer_visibility: Dictionary = {}
const TRACKING_NOTICE_MISSING := "COME BACK INTO THE CAMERA!"
const TRACKING_NOTICE_MISSING_DETAIL := "Step into view • Bumalik sa harap ng camera"
const TRACKING_NOTICE_MULTIPLE := "ONLY ONE PLAYER!"
const TRACKING_NOTICE_MULTIPLE_DETAIL := "Classmates, please step aside • Isang manlalaro lang"
const COUNTDOWN_STANDING_HINT := "Stand in the center and watch for the first word!"


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
	# Deferred guide/countdown calls from the previous scene must never start
	# a newly selected activity or revive one that is being removed.
	_mount_generation += 1
	_clear_countdown_ui()
	# Reuse the SceneTree-level player across Calibration, the 3-2-1 and all
	# three minigames. Never reset the track just because a scene was mounted.
	# Direct standalone gameplay (without calibration) still starts it at GO.
	_game_music = GameAudio.ensure(get_tree())
	# A fresh minigame has no prior camera steering history. Do not reuse the
	# previous activity's last smoothing target during countdown/recalibration.
	smooth_x = 0.0
	missing_pose_seconds = 0.0
	confirmed_missing_student_seconds = 0.0
	saw_student_in_live_round = false
	tracking_suspended = false
	last_pose_valid = false
	_countdown_requires_locked_pose = false
	_countdown_waiting_for_pose = false
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
	var camera_live := bool(context.get("camera_live", false))
	var count_in := guided or bool(context.get("start_countdown", false)) or camera_live
	# Calibrate ONCE at the beginning of this Play/Tutorial round. Neither
	# flow can start at GO without a fresh, verified single person. Changes
	# to temporary ByteTrack IDs/worker sessions must NOT restart calibration.
	# Any live-camera round MUST prove measured calibration and a fresh solo
	# player before GO; missing calibration must not disable the safety gate.
	_countdown_requires_locked_pose = camera_live
	if count_in:
		# Freeze the whole minigame, including input, physics, animations and
		# scoring, before its first frame. The camera service is a separate
		# autoload and remains live for a verified single student.
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
		# Integrated component narration belongs to this actual minigame. Its
		# CanvasLayer controls run in PROCESS_MODE_ALWAYS while gameplay stays
		# completely disabled. The one-shot signal is the ONLY countdown gate.
		if not active_game.has_signal("tutorial_finished") or not active_game.has_method("begin_guided_tutorial") \
				or not active_game.has_method("is_tutorial_active"):
			push_error("Integrated tutorial contract missing: " + game_path)
			return
		active_game.connect("tutorial_finished", Callable(self, "_on_guided_tutorial_finished").bind(active_game, _mount_generation))
		call_deferred("_begin_integrated_tutorial", active_game, _mount_generation)
	elif count_in:
		# Normal Play still enters its 3-2-1 as soon as the game is mounted.
		call_deferred("_begin_countdown")
	else:
		_start_gameplay_music()


func _begin_integrated_tutorial(game: Control, generation: int) -> void:
	if guided_stage != "tutorial" or generation != _mount_generation \
			or not is_instance_valid(game) or game != active_game:
		return
	# Each editor-authored spotlight is in its own named CanvasLayer. Allow
	# ONLY those tutorial layers to process while their gameplay parent stays
	# disabled: narration, Next, Back and Skip must remain interactive even if
	# the camera currently has no trustworthy pose or student in view.
	for node in game.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		var layer_name := layer.name.to_lower()
		if layer_name.contains("tutorial") or layer_name.contains("guide"):
			layer.process_mode = Node.PROCESS_MODE_ALWAYS
	game.call("begin_guided_tutorial")
	if guided_stage == "tutorial" and not bool(game.call("is_tutorial_active")):
		# Fail safely if a minigame has not displayed its integrated controls.
		# Never advance a tutorial straight to 3-2-1 on missing/broken guides.
		push_error("Integrated tutorial did not activate: " + String(context.get("activity", "")))


func _on_guided_tutorial_finished(game: Control, generation: int) -> void:
	# Duplicate Skip/Next events and signals emitted by a removed old game
	# cannot consume more countdowns or activate a replacement scene.
	if guided_stage != "tutorial" or generation != _mount_generation \
			or not is_instance_valid(game) or game != active_game:
		return
	guided_stage = "countdown"
	_clear_gesture_input()
	call_deferred("_begin_countdown")


func _start_gameplay_music() -> void:
	if is_instance_valid(_game_music):
		_game_music.call("start_gameplay")


func _ensure_countdown_layer() -> void:
	if is_instance_valid(countdown_layer):
		return
	# Draw the countdown above gameplay HUD layers without changing game art.
	countdown_layer = CanvasLayer.new()
	countdown_layer.name = "CountdownLayer"
	countdown_layer.layer = 100
	add_child(countdown_layer)


func _begin_countdown() -> void:
	if guided_stage != "countdown" or not is_instance_valid(active_game):
		return
	if is_instance_valid(countdown_panel):
		return
	_ensure_countdown_layer()
	countdown_panel = COUNTDOWN_SCENE.instantiate() as Control
	if countdown_panel == null:
		push_error("Could not instantiate guided countdown scene")
		return
	countdown_panel.name = "GuidedCountdown"
	countdown_layer.add_child(countdown_panel)
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
	if _countdown_requires_locked_pose and not _has_live_calibrated_player():
		# A missing/occluded pose at GO previously started a Play round which
		# _process() immediately disabled after 0.65 s. Keep the minigame's
		# timers safely frozen while stating what the student must do. The
		# a fresh stable SOLO observation can resume automatically from _process().
		_countdown_waiting_for_pose = true
		countdown_value = 1
		_update_countdown_text()
		var hint := countdown_panel.get_node_or_null("MovementHint") as Label
		if hint != null:
			hint.text = "TRACKING PAUSED • Wait for one player in view."
		if is_instance_valid(countdown_timer):
			countdown_timer.stop()
		return
	guided_stage = "completed"
	_clear_countdown_ui()
	# The round must not inherit a stale "missing" timer from calibration or
	# the countdown when a fresh camera inference frame is still pending.
	missing_pose_seconds = 0.0
	confirmed_missing_student_seconds = 0.0
	tracking_notice.visible = false
	if is_instance_valid(active_game):
		if bool(context.get("guided_tutorial", false)) and active_game.has_method("_resume"):
			# Human Plane deliberately keeps running=false after its explanations;
			# other games may similarly hold their timers until the real GO.
			active_game.call("_resume")
		active_game.process_mode = Node.PROCESS_MODE_INHERIT
	_start_gameplay_music()


func _clear_countdown_ui() -> void:
	if is_instance_valid(countdown_timer):
		countdown_timer.stop()
	if is_instance_valid(countdown_layer):
		remove_child(countdown_layer)
		countdown_layer.queue_free()
	countdown_layer = null
	countdown_panel = null
	countdown_timer = null
	countdown_value = 0
	guided_stage = ""
	_countdown_waiting_for_pose = false


func _has_live_calibrated_player() -> bool:
	# PoseService validates a fresh, trusted YOLO observation of exactly one
	# stable, enrolled student (not an ID or epoch recycled from a prior frame).
	# The initial physical positions remain in calibration for the whole round.
	return bool(context.get("calibration_measured", false)) \
		and PoseService.has_valid_pose() \
		and bool(PoseService.calibration.get("valid", false)) \
		and (String(context.get("activity", "")) != "Human Plane" \
			or PoseService.has_stationary_plane_pose())


func _fresh_camera_population() -> int:
	# Authenticated live YOLO person-box count, not pose/StudentLock success.
	# PoseService rejects stale source captures, warmup/recovering snapshots,
	# missing UDP transport, invalid counts and offline workers. Only a truly
	# fresh one-person box permits the calibrated round to keep PLAYING.
	return PoseService.fresh_camera_population()


func _show_tracking_problem(kind: String) -> void:
	var title := tracking_notice.get_node_or_null("Title") as Label
	var description := tracking_notice.get_node_or_null("Description") as Label
	if title != null:
		title.text = TRACKING_NOTICE_MULTIPLE if kind == "multiple" else TRACKING_NOTICE_MISSING
	if description != null:
		description.text = TRACKING_NOTICE_MULTIPLE_DETAIL if kind == "multiple" \
			else TRACKING_NOTICE_MISSING_DETAIL
	tracking_notice.visible = true


func _relay_navigation(route: String, payload: Dictionary) -> void:
	if guided_stage in ["tutorial", "countdown"] and route in ["pause", "results"]:
		return # A frozen explanation/countdown cannot end or pause a round.
	if guided_stage in ["tutorial", "countdown"]:
		# Leaving an unstarted round (including change activity and restart)
		# cancels its pending callback/timer before another scene takes over.
		_mount_generation += 1
		_clear_countdown_ui()
	if route == "pause":
		_conceal_gameplay_layers()
	if is_instance_valid(_game_music):
		if route == "pause":
			_game_music.call("pause_music")
		elif route in ["results", "main", "tutorial_home", "play_activity", "student_setup"]:
			_game_music.call("stop_gameplay")
		# The results are real in-game scores, but are still UNSAVED until
	# local PostgreSQL persistence is implemented in a later milestone.
	var outgoing := get_context()
	outgoing.merge(payload, true)
	outgoing["activity"] = String(context.get("activity", "Catch the Word"))
	outgoing["gameplay_implemented"] = true
	outgoing["demo_mode"] = true
	outgoing["camera_live"] = bool(context.get("camera_live", false)) and PoseService.active
	requested.emit(route, outgoing)


func _conceal_gameplay_layers() -> void:
	# CanvasLayer renders on its own canvas, independently of the wrapper's
	# Control.visible state. The router parks this wrapper behind the Pause
	# panel, so also conceal every HUD/score/tracking layer before navigation.
	# Keep each layer's original visibility (including layers already hidden)
	# so Resume restores exactly the prior gameplay presentation.
	for node in find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if not _paused_canvas_layer_visibility.has(layer):
			_paused_canvas_layer_visibility[layer] = layer.visible
		layer.visible = false


func _restore_gameplay_layers() -> void:
	for node in _paused_canvas_layer_visibility:
		if is_instance_valid(node) and node is CanvasLayer:
			(node as CanvasLayer).visible = bool(_paused_canvas_layer_visibility[node])
	_paused_canvas_layer_visibility.clear()


func _process(delta: float) -> void:
	# Camera-only gameplay: no keyboard steering or demo movement fallback.
	# Godot animates up to 60 FPS independently from YOLO inference.
	if guided_stage == "tutorial":
		# The independent pose service stays live for calibration continuity.
		# Gameplay must remain disabled even if camera presence disappears or
		# reappears; the guide's ALWAYS-process controls can still be used.
		return
	if not bool(context.get("camera_live", false)):
		return
	if not is_instance_valid(active_game):
		return
	# Temporary YOLO tracker IDs/epochs may churn, including after the worker
	# restarts. There is NO automatic calibration route during a round.
	# Camera PRESENCE (one real YOLO detection) controls the round's pause;
	# independently, a fresh enrolled pose controls movement and gestures.
	# This deliberate ID-free policy permits a different sole person to take
	# over the unfinished round when the previous child leaves the camera.
	var population := _fresh_camera_population()
	var has_solo_pose := population == 1 and _has_live_calibrated_player()
	if guided_stage == "countdown" and is_instance_valid(countdown_timer):
		if not has_solo_pose:
			countdown_timer.stop()
		elif not _countdown_waiting_for_pose and countdown_timer.is_stopped():
			countdown_timer.start()
		var countdown_hint := countdown_panel.get_node_or_null("MovementHint") as Label
		if countdown_hint != null and not _countdown_waiting_for_pose:
			if population == 0:
				countdown_hint.text = TRACKING_NOTICE_MISSING
			elif population >= 2:
				countdown_hint.text = TRACKING_NOTICE_MULTIPLE
			elif not has_solo_pose:
				countdown_hint.text = "WAIT FOR ONE STEADY PLAYER IN THE CAMERA!"
			else:
				countdown_hint.text = COUNTDOWN_STANDING_HINT
	if _countdown_waiting_for_pose and has_solo_pose:
		_complete_countdown_start()
	# Human Plane's arms and wrists still require real fresh landmarks before
	# steering, but not to keep the round's timer running when ONE box is seen.
	var human_plane := String(context.get("activity", "")) == "Human Plane"
	var verified_plane_pose := not human_plane or PoseService.has_stationary_plane_pose()
	var countdown_active := guided_stage == "countdown"
	# Physical calibration remains a hard prerequisite. After the game has
	# actually started, exactly ONE freshly detected person (even an untracked
	# passerby or a person with momentarily missing joints) keeps it running.
	var measured_round := bool(PoseService.calibration.get("valid", false)) \
		and (not human_plane or bool(PoseService.plane_calibration.get("valid", false)))
	var solo_present := population == 1 and measured_round
	var usable_pose := has_solo_pose and verified_plane_pose
	# The previous completed camera calibration is also proof that this
	# session had a real locked player, even if the first gameplay frame after
	# GO is empty. Never arm on fake/demo pose data.
	var previously_seen := saw_student_in_live_round or (bool(PoseService.calibration.get("valid", false)) \
		and bool(PoseService.get("_ever_tracked")))
	var confirmed_missing := previously_seen and not countdown_active and population == 0
	# During 3-2-1 the scene must still wait for ACTUAL usable pose.
	# Only an already-started activity uses presence-only pause policy.
	if not solo_present or (countdown_active and not usable_pose):
		_clear_gesture_input()
		missing_pose_seconds += maxf(delta, 0.0)
		confirmed_missing_student_seconds = confirmed_missing_student_seconds + maxf(delta, 0.0) if confirmed_missing else 0.0
		if last_pose_valid:
			if active_game.has_method("clear_body_input"):
				active_game.call("clear_body_input")
		last_pose_valid = false
		# Zero/multiple/unknown/stale camera data freeze the whole activity
		# immediately. No fabricated person, inferred ID or stale bones can play.
		if not countdown_active:
			active_game.process_mode = Node.PROCESS_MODE_DISABLED
			tracking_suspended = true
			if is_instance_valid(_game_music):
				_game_music.call("pause_music")
		if not countdown_active and population == 0:
			_show_tracking_problem("missing")
		elif not countdown_active and population >= 2:
			_show_tracking_problem("multiple")
		else:
			tracking_notice.visible = false
		return
	missing_pose_seconds = 0.0
	confirmed_missing_student_seconds = 0.0
	tracking_notice.visible = false
	if not countdown_active:
		saw_student_in_live_round = true
	if tracking_suspended:
		tracking_suspended = false
		if not countdown_active:
			active_game.process_mode = Node.PROCESS_MODE_INHERIT
			if is_instance_valid(_game_music):
				_game_music.call("resume_music")
	elif not countdown_active and active_game.process_mode == Node.PROCESS_MODE_DISABLED:
		# A transient, single-frame SOLO dropout froze gameplay without
		# changing the visible pause state. Resume on the next VERIFIED pose.
		active_game.process_mode = Node.PROCESS_MODE_INHERIT
	# With ONE real person present, the game itself keeps playing even when
	# YOLO cannot measure a trustworthy body pose. No stale body movement,
	# shooting, or airplane input is allowed until genuinely fresh landmarks
	# come back. The timer/score/other gameplay continue normally.
	if not usable_pose:
		_clear_gesture_input()
		if last_pose_valid and active_game.has_method("clear_body_input"):
			active_game.call("clear_body_input")
		last_pose_valid = false
		return
	# During 3-2-1, never mutate frozen gameplay or latch steering/gesture
	# history. A verified fresh pose will be read after GO.
	if countdown_active:
		_clear_gesture_input()
		last_pose_valid = false
		return
	# Gestures continue to require their OWN short source-freshness budget.
	_update_gesture_input()
	if human_plane:
		# A single neutral hold establishes camera-space body/torso steering.
		# The pose service validates student lock and requires at least one
		# confidently visible wrist; only HumanPlane applies the smooth glide.
		if PoseService.has_stationary_plane_pose():
			set_body_x(PoseService.normalized_plane_steering())
			last_pose_valid = true
		else:
			if active_game.has_method("set_airplane_pose_active"):
				active_game.call("set_airplane_pose_active", false)
			last_pose_valid = false
		return
	var raw_x: float = PoseService.normalized_body_x()
	if not last_pose_valid:
		smooth_x = raw_x
	else:
		smooth_x = lerpf(smooth_x, raw_x, 1.0 - exp(-maxf(delta, 0.0) * 14.0))
	set_body_x(smooth_x)
	last_pose_valid = true


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
			var eligible: bool = fresh and PoseService.has_stationary_plane_pose() \
				and guided_stage != "countdown"
			if active_game.has_method("set_airplane_pose_active"):
				active_game.call("set_airplane_pose_active", eligible)
		"Balloon Popping":
			if active_game.has_method("set_hand_raise_state"):
				# Paused/countdown sessions do not launch projectiles; only
				# the live minigame owns its one-shot edge and 1.5-second cooldown.
				# A lost wrist is UNKNOWN, not a deliberate hand-down event.
				var allowed: bool = fresh and PoseService.has_valid_hand_observation() \
					and guided_stage != "countdown"
				active_game.call("set_hand_raise_state", allowed and PoseService.has_hand_raised(), allowed)


func _exit_tree() -> void:
	# The main route controller owns track STOP on menu/results/quit transitions.
	# Stopping here races a queued-free paused game during Restart -> Calibration
	# and cuts off the new calibration music after it already started.
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
	_conceal_gameplay_layers()
	if is_instance_valid(_game_music):
		_game_music.call("pause_music")
	if is_instance_valid(active_game) and active_game.has_method("_pause"):
		active_game.call("_pause")
	else:
		requested.emit("pause", get_context())


func _resume() -> void:
	_restore_gameplay_layers()
	if is_instance_valid(_game_music) and not tracking_suspended:
		_game_music.call("resume_music")
	# main_menu reuses this same wrapper and live minigame after Pause.
	if is_instance_valid(active_game) and active_game.has_method("_resume"):
		active_game.call("_resume")


func set_body_x(normalized_x: float) -> void:
	# Future camera bridge: forward body horizontal position without assuming
	# a camera is connected or calibrated today.
	if is_instance_valid(active_game) and active_game.has_method("set_body_x"):
		active_game.call("set_body_x", normalized_x)
