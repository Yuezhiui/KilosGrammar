@tool
extends Control

signal requested(target: String, payload: Dictionary)

const UI = preload("res://ui/play/shared/play_ui.gd")
const FONT: Font = preload("res://assets/fonts/TitanOne-Regular.ttf")
const GRAMMAR_BANK = preload("res://ui/minigames/shared/grammar_bank.gd")
const STONE_SCENE: PackedScene = preload("res://ui/minigames/balloon_popping/balloon_art/stone.tscn")

const BOOTH_PNG := "res://Components/Gameplay/Balloon Popping/Background/0826b13c-250f-42e1-9398-a83d2922a1d8.png"
const COUNTER_PNG := "res://Components/Gameplay/Balloon Popping/Background/95ae2a22-302d-48f7-9b5f-e12b0104c822.png"
const BALLOON_PNGS := [
	"res://Components/Gameplay/Balloon Popping/Balloons/purple.png",
	"res://Components/Gameplay/Balloon Popping/Balloons/green.png",
	"res://Components/Gameplay/Balloon Popping/Balloons/blue.png"
]
const POP_TEXTURE: Texture2D = preload("res://Components/Gameplay/Balloon Popping/Effects/Pop.png")
const HEART_RED: Texture2D = preload("res://Components/Gameplay/Shared/Hearts/HeartRed.png")
const HEART_BLACK: Texture2D = preload("res://Components/Gameplay/Shared/Hearts/HeartBlack.png")
const SHARED_TIMER_BADGE: Texture2D = preload("res://Components/Gameplay/Catch the Word/HUD/generated/timer_badge.png")
const SHARED_LIVES_STATE_1: Texture2D = preload("res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_1.png")
const SHARED_LIVES_STATE_2: Texture2D = preload("res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_2.png")
const SHARED_LIVES_STATE_3: Texture2D = preload("res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_3.png")
const CARNIVAL_ART := "res://Components/Gameplay/Balloon Popping/Art/reference/"
const PAUSE_ICON: Texture2D = preload("res://Components/Gameplay/Controls/pause_white.svg")
const PLAY_ICON: Texture2D = preload("res://Components/Gameplay/Controls/play_white.svg")
const KidsVoice = preload("res://ui/shared/kids_voice_feedback.gd")
const MISSED_SHOT_VOICE_COOLDOWN_MS := 1400

const ACTIVITY := "Balloon Popping"
const CORRECT_POP_SCORE := 100
const SECONDS_MODE_DURATION := 60.0
const LIVES_MODE_HEARTS := 3
# Each correct pop closes 20% of the remaining gap to the difficulty cap.
# This starts at +5%/+7%/+9% and diminishes naturally without reaching an
# excessive speed after long streaks.
const BALLOON_SPEED_BOOST_BLEND := 0.20
const BALLOON_SPEED_CAPS := {"Easy": 1.25, "Normal": 1.35, "Hard": 1.45}
const LANE_COUNT := 3
const BALLOON_COLLISION_RADIUS := 58.0
const PROJECTILE_COLLISION_RADIUS := 9.0
const SWEPT_COLLISION_MIN_TRAVEL := (BALLOON_COLLISION_RADIUS + PROJECTILE_COLLISION_RADIUS) * 2.0
const UPPER_LINE_Y := 125.0
const BALLOON_FLOAT_SPEED := 52.0
const BALLOON_REVEAL_SECONDS := 1.15
const HAND_RAISE_RELOAD_MS := 1500
const HAND_RAISE_LOWER_CONFIRM_MS := 180
const HAND_RAISE_UP_CONFIRM_MS := 80

const TOPIC_PLURALS := {
	"Noun": "NOUNS",
	"Verb": "VERBS",
	"Adjective": "ADJECTIVES",
	"Adverb": "ADVERBS",
	"Pronoun": "PRONOUNS"
}
const BALLOON_COLORS := [Color("#C171CF"), Color("#69BE9A"), Color("#7BC9EF")]

var context: Dictionary = {}
var rng := RandomNumberGenerator.new()

var score := 0
var correct_count := 0
var attempts := 0
@export_range(1, 10) var default_lives: int = 3
@export var default_duration: float = 60.0
var hearts := 3
var time_remaining := 60.0
var round_time_remaining := 7.0
var round_index := 0
var timer_running := true
var round_active := false
var round_active_before_pause := false
var next_round_pending := false
var finishing := false
var round_completed := false
var used_words: Dictionary = {}
var last_round_words: Dictionary = {}

var game_mode := "Seconds"
var is_seconds_mode := true
var is_lives_mode := false

var projectile_speed := 1000.0
var launcher_max_speed := 650.0
var launcher_acceleration := 2300.0
var round_time_limit := 7.0
var balloon_float_speed := BALLOON_FLOAT_SPEED
var balloon_base_float_speed := BALLOON_FLOAT_SPEED
var balloon_speed_multiplier := 1.0
var balloon_reveal_seconds := BALLOON_REVEAL_SECONDS
var wrong_penalty := 0
var miss_costs_heart := false

var launcher_x := 640.0
var launcher_velocity := 0.0
var body_target_x := 640.0
var body_target_timer := 0.0
var launcher: Node2D
var projectile_layer: Node2D
var booth_backdrop: TextureRect
var foreground_counter: TextureRect
var balloon_slots: Array[Area2D] = []
var balloons: Array[Area2D] = []
var projectiles: Array[Area2D] = []
var projectile_velocities: Dictionary = {}
var hand_raise_tracking_valid := false
var hand_raise_raw_raised := false
var hand_raise_sample_since_ms := 0
var hand_raise_confirmed_raised := false
var hand_raise_armed := false
var hand_raise_last_shot_ms := -1
var _hand_raise_firing_authorized := false
var valid_lanes: Array[int] = []
var pending_valid_lanes: Array[int] = []

var balloon_floating := false
var float_start_delay := 0.55
var float_timer := 0.0

var score_label: Label
var score_bottom_container: VBoxContainer
var score_bottom_number: Label
var hearts_label: Label
var hearts_box: HBoxContainer
var shared_timer_plaque: TextureRect
var shared_lives_plaque: TextureRect
var carnival_objective_plaque: TextureRect
var carnival_title_plaque: TextureRect
var carnival_score_plaque: TextureRect
var time_label: Label
var banner_tagline: Label
var feedback_label: Label
var round_label: Label
var camera_label: Label
var title_label: Label
var _authored_banner_rects: Dictionary = {}
var pause_button: Button
var finish_button: Button
var balloon_motion_tween: Tween
var balloon_tween_paused := false
var balloon_voice_player: AudioStreamPlayer
var _kids_voice
var last_missed_shot_voice_msec := -100000


func _ready() -> void:
	if Engine.is_editor_hint():
		_setup_editor_preview()
		resized.connect(_layout_editor_preview)
		call_deferred("_layout_editor_preview")
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	rng.randomize()
	_initialize_voice_feedback()
	_build_scene()
	_apply_context()
	resized.connect(_layout_scene)
	call_deferred("_layout_scene")
	set_process(true)
	set_physics_process(true)


func _setup_editor_preview() -> void:
	booth_backdrop = get_node_or_null("BoothBackdrop") as TextureRect
	foreground_counter = get_node_or_null("ForegroundCounter") as TextureRect
	launcher = get_node_or_null("LauncherLayer/Launcher") as Node2D
	balloon_slots = [
		get_node_or_null("BalloonLayer/LeftTarget") as Area2D,
		get_node_or_null("BalloonLayer/CenterTarget") as Area2D,
		get_node_or_null("BalloonLayer/RightTarget") as Area2D
	]
	_bind_raw_art_textures()
	for lane in range(balloon_slots.size()):
		var balloon := balloon_slots[lane]
		if not is_instance_valid(balloon):
			continue
		balloon.visible = true
		balloon.monitoring = false
		balloon.monitorable = false
		var preview_label := balloon.get_node_or_null("WordLabel") as Label
		if preview_label != null:
			preview_label.text = ["NOUN", "VERB", "ADJECTIVE"][lane]
	_layout_editor_preview()


func _layout_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	var preview_size := size
	if preview_size.x < 100.0 or preview_size.y < 100.0:
		preview_size = Vector2(1280.0, 720.0)
	if is_instance_valid(foreground_counter):
		foreground_counter.position = Vector2(0.0, preview_size.y * 0.445)
		foreground_counter.size = preview_size
	if is_instance_valid(launcher):
		launcher.position = Vector2(preview_size.x * 0.5, preview_size.y - clampf(preview_size.y * 0.10, 68.0, 105.0))
	for lane in range(mini(balloon_slots.size(), LANE_COUNT)):
		var balloon := balloon_slots[lane]
		if is_instance_valid(balloon):
			balloon.position = Vector2(
				lerpf(preview_size.x * 0.24, preview_size.x * 0.76, float(lane) / 2.0),
				clampf(preview_size.y * 0.43, 245.0, 440.0)
			)


func set_context(new_context: Dictionary) -> void:
	# A new setup clears words; a saved game snapshot may restore them.
	if not new_context.has("balloon_used_words"):
		context.erase("balloon_used_words")
	for key in new_context:
		context[key] = new_context[key]
	if is_node_ready():
		_apply_context()


func get_context() -> Dictionary:
	var payload := context.duplicate(true)
	payload["activity"] = ACTIVITY
	payload["topic"] = _topic()
	payload["game_style"] = _topic()
	payload["game_mode"] = game_mode
	payload["difficulty"] = _difficulty()
	payload["score"] = score
	payload["correct"] = correct_count
	payload["attempts"] = attempts
	payload["total"] = attempts
	payload["time_remaining"] = maxf(time_remaining, 0.0)
	payload["hearts"] = hearts
	payload["lives"] = hearts
	payload["balloon_round"] = round_index
	payload["demo_mode"] = true
	payload["database_connected"] = false
	payload["gameplay_implemented"] = true
	payload["camera_live"] = false
	payload["minigame_route"] = "balloon_popping"
	payload["round_completed"] = round_completed
	# Only the real game-ending timer or final lost heart can authorize a
	# durable Play result. Pause/View Results/shutdown must not masquerade as
	# completion, even if a caller carries stale context from another round.
	payload["completion_reason"] = ("time_up" if is_seconds_mode else "lives_empty") \
		if round_completed and ((is_seconds_mode and time_remaining <= 0.0) \
		or (is_lives_mode and hearts <= 0)) else ""
	return payload


func set_body_x(normalized_x: float) -> void:
	var safe_x := clampf(normalized_x, -1.0, 1.0)
	var unit_x := (safe_x + 1.0) * 0.5
	# Aim at the three ACTUAL balloon lanes, not the wider launcher travel
	# bounds. At calibrated LEFT/RIGHT, the old 16%-84% travel endpoints
	# missed the balloons centered at roughly 24%/76% by 100+ px at 1280.
	# Read the scene's target positions so authored balloon locations remain
	# the source of truth if their spacing changes.
	var left_target_x := _lane_x(0)
	var right_target_x := _lane_x(LANE_COUNT - 1)
	if balloon_slots.size() == LANE_COUNT and is_instance_valid(balloon_slots[0]) \
			and is_instance_valid(balloon_slots[LANE_COUNT - 1]):
		left_target_x = balloon_slots[0].position.x
		right_target_x = balloon_slots[LANE_COUNT - 1].position.x
	body_target_x = lerpf(left_target_x, right_target_x, unit_x)
	body_target_timer = 0.30


func clear_body_input() -> void:
	# The game may keep running with one fresh YOLO person box even when that
	# person's wrist/torso pose briefly disappears. Stop the last commanded
	# launcher motion immediately; never drive from a stale camera target.
	body_target_timer = 0.0
	body_target_x = launcher_x
	launcher_velocity = 0.0


# Caller supplies the combined (left OR right) hand-up state for each valid
# camera frame, including repeated unchanged frames. Untracked frames must use
# tracking_valid=false: missing pose data is never interpreted as lowering.
# The optional clock lets headless tests verify the 1.5-second reload exactly.
# Returns true only if this sample actually fired one projectile.
func set_hand_raise_state(raised: bool, tracking_valid: bool = true, now_ms: int = -1) -> bool:
	if not tracking_valid:
		clear_hand_raise_tracking()
		return false
	# During physical calibration the game is not mounted; the tutorial and
	# 3-2-1 countdown mount it DISABLED. Ignore even direct gesture calls there.
	if process_mode == Node.PROCESS_MODE_DISABLED:
		clear_hand_raise_tracking()
		return false
	if Engine.is_editor_hint() or finishing or not timer_running or not is_inside_tree():
		return false
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	if not hand_raise_tracking_valid or raised != hand_raise_raw_raised:
		hand_raise_tracking_valid = true
		hand_raise_raw_raised = raised
		hand_raise_sample_since_ms = now
	if not raised:
		# Ignore brief pose-estimation flicker: lowering must be sustained before
		# a fresh raise can create another shot.
		if now - hand_raise_sample_since_ms >= HAND_RAISE_LOWER_CONFIRM_MS:
			hand_raise_confirmed_raised = false
			hand_raise_armed = true
		return false
	if hand_raise_confirmed_raised or now - hand_raise_sample_since_ms < HAND_RAISE_UP_CONFIRM_MS:
		return false
	hand_raise_confirmed_raised = true
	var can_fire := hand_raise_armed
	# Every confirmed rise consumes its edge, even during reload or while a
	# question is unavailable. Holding a hand high cannot queue a later shot.
	hand_raise_armed = false
	if not can_fire or (hand_raise_last_shot_ms >= 0 and now - hand_raise_last_shot_ms < HAND_RAISE_RELOAD_MS):
		return false
	_hand_raise_firing_authorized = true
	var fired := _launch_projectile(now)
	_hand_raise_firing_authorized = false
	return fired


func clear_hand_raise_tracking() -> void:
	# Require a real, stable lowered pose before arming after a tracking dropout
	# or a paused/tutorial screen. Preserve the latest shot's reload deadline.
	hand_raise_tracking_valid = false
	hand_raise_raw_raised = false
	hand_raise_sample_since_ms = 0
	hand_raise_confirmed_raised = false
	hand_raise_armed = false
	_hand_raise_firing_authorized = false


func _finish_round() -> void:
	if finishing:
		return
	# Vocabulary availability is never a game-over condition. Only the selected
	# mode's actual losing condition may open Results.
	if (is_seconds_mode and time_remaining > 0.0) or (is_lives_mode and hearts > 0):
		return
	clear_hand_raise_tracking()
	_stop_voice_feedback()
	finishing = true
	round_completed = true
	timer_running = false
	round_active = false
	round_active_before_pause = false
	next_round_pending = false
	_clear_projectiles()
	requested.emit("results", get_context())


func _build_scene() -> void:
	booth_backdrop = $BoothBackdrop as TextureRect
	foreground_counter = $ForegroundCounter as TextureRect
	launcher = $LauncherLayer/Launcher as Node2D
	projectile_layer = $ProjectileLayer as Node2D
	balloon_slots = [
		$BalloonLayer/LeftTarget as Area2D,
		$BalloonLayer/CenterTarget as Area2D,
		$BalloonLayer/RightTarget as Area2D
	]
	_bind_raw_art_textures()
	for lane in range(balloon_slots.size()):
		balloon_slots[lane].set_meta("balloon_lane", lane)
		balloon_slots[lane].visible = false
		balloon_slots[lane].monitoring = false
		balloon_slots[lane].monitorable = false

	var hud_layer := $HudLayer as Control
	hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	carnival_objective_plaque = hud_layer.get_node_or_null("ObjectivePanel") as TextureRect
	if carnival_objective_plaque == null:
		carnival_objective_plaque = _create_carnival_hud_plaque(hud_layer, "objective_panel.png", "ObjectivePanel")
	if carnival_objective_plaque == null:
		carnival_title_plaque = hud_layer.get_node_or_null("CarnivalTitle") as TextureRect
		if carnival_title_plaque == null:
			carnival_title_plaque = _create_carnival_hud_plaque(hud_layer, "title_marquee.png", "CarnivalTitle")
	carnival_score_plaque = hud_layer.get_node_or_null("CarnivalScore") as TextureRect
	if carnival_score_plaque == null:
		carnival_score_plaque = _create_carnival_hud_plaque(hud_layer, "score_plaque_blank.png", "CarnivalScore")

	shared_timer_plaque = hud_layer.get_node_or_null("TimerPlaque") as TextureRect
	if shared_timer_plaque == null:
		shared_timer_plaque = TextureRect.new()
		shared_timer_plaque.name = "TimerPlaque"
		shared_timer_plaque.texture = SHARED_TIMER_BADGE
		shared_timer_plaque.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shared_timer_plaque.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shared_timer_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(shared_timer_plaque)

	shared_lives_plaque = hud_layer.get_node_or_null("LivesPlaque") as TextureRect
	if shared_lives_plaque == null:
		shared_lives_plaque = TextureRect.new()
		shared_lives_plaque.name = "LivesPlaque"
		shared_lives_plaque.texture = SHARED_LIVES_STATE_3
		shared_lives_plaque.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shared_lives_plaque.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shared_lives_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(shared_lives_plaque)

	title_label = hud_layer.get_node_or_null("TitleLabel") as Label
	if title_label == null:
		title_label = Label.new()
		title_label.name = "TitleLabel"
		title_label.text = "BALLOON POPPING"
		title_label.add_theme_font_override("font", FONT)
		title_label.add_theme_font_size_override("font_size", 24)
		title_label.add_theme_color_override("font_color", Color.WHITE)
		title_label.add_theme_color_override("font_outline_color", Color.BLACK)
		title_label.add_theme_constant_override("outline_size", 6)
		title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(title_label)
	if carnival_objective_plaque != null or carnival_title_plaque != null:
		title_label.visible = false
	banner_tagline = hud_layer.get_node_or_null("BannerTagline") as Label

	score_bottom_container = hud_layer.get_node_or_null("ScoreBottomContainer") as VBoxContainer
	if score_bottom_container == null:
		score_bottom_container = VBoxContainer.new()
		score_bottom_container.name = "ScoreBottomContainer"
		score_bottom_container.add_theme_constant_override("separation", -4)
		score_bottom_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(score_bottom_container)

	var score_title := score_bottom_container.get_node_or_null("ScoreTitle") as Label
	if score_title == null:
		score_title = Label.new()
		score_title.name = "ScoreTitle"
		score_title.text = "SCORE"
		score_title.add_theme_font_override("font", FONT)
		score_title.add_theme_font_size_override("font_size", 30)
		score_title.add_theme_color_override("font_color", Color.WHITE)
		score_title.add_theme_color_override("font_outline_color", Color.BLACK)
		score_title.add_theme_constant_override("outline_size", 6)
		score_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		score_bottom_container.add_child(score_title)
	if carnival_score_plaque != null:
		score_title.visible = false

	score_bottom_number = score_bottom_container.get_node_or_null("ScoreNumber") as Label
	if score_bottom_number == null:
		score_bottom_number = Label.new()
		score_bottom_number.name = "ScoreNumber"
		score_bottom_number.text = "0"
		score_bottom_number.add_theme_font_override("font", FONT)
		score_bottom_number.add_theme_font_size_override("font_size", 38)
		score_bottom_number.add_theme_color_override("font_color", Color.WHITE)
		score_bottom_number.add_theme_color_override("font_outline_color", Color.BLACK)
		score_bottom_number.add_theme_constant_override("outline_size", 6)
		score_bottom_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_bottom_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		score_bottom_container.add_child(score_bottom_number)
	if carnival_score_plaque != null:
		score_bottom_number.add_theme_color_override("font_color", Color("#102962"))
		score_bottom_number.add_theme_constant_override("outline_size", 0)
	score_label = score_bottom_number

	hearts_box = hud_layer.get_node_or_null("HeartsBox") as HBoxContainer
	if hearts_box == null:
		hearts_box = HBoxContainer.new()
		hearts_box.name = "HeartsBox"
		hearts_box.add_theme_constant_override("separation", 10)
		hearts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(hearts_box)
		for i in range(3):
			var heart_rect := TextureRect.new()
			heart_rect.name = "Heart%d" % (i + 1)
			heart_rect.texture = HEART_RED
			heart_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			heart_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			heart_rect.custom_minimum_size = Vector2(44, 40)
			heart_rect.size = Vector2(44, 40)
			heart_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hearts_box.add_child(heart_rect)

	time_label = hud_layer.get_node_or_null("TimeLabel") as Label
	if time_label == null:
		time_label = Label.new()
		time_label.name = "TimeLabel"
		time_label.text = "60s"
		time_label.add_theme_font_override("font", FONT)
		time_label.add_theme_font_size_override("font_size", 29)
		time_label.add_theme_color_override("font_color", Color.WHITE)
		time_label.add_theme_color_override("font_outline_color", Color.BLACK)
		time_label.add_theme_constant_override("outline_size", 6)
		time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_layer.add_child(time_label)

	pause_button = hud_layer.get_node_or_null("PauseButton") as Button
	if pause_button == null:
		var empty_style := StyleBoxEmpty.new()
		pause_button = Button.new()
		pause_button.name = "PauseButton"
		pause_button.icon = PAUSE_ICON
		pause_button.expand_icon = true
		pause_button.custom_minimum_size = Vector2(44, 44)
		pause_button.focus_mode = Control.FOCUS_NONE
		pause_button.mouse_filter = Control.MOUSE_FILTER_STOP
		pause_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		pause_button.add_theme_stylebox_override("normal", empty_style)
		pause_button.add_theme_stylebox_override("hover", empty_style)
		pause_button.add_theme_stylebox_override("pressed", empty_style)
		pause_button.add_theme_stylebox_override("focus", empty_style)
		hud_layer.add_child(pause_button)
	if not pause_button.pressed.is_connected(_toggle_pause):
		pause_button.pressed.connect(_toggle_pause)

	# Compatibility labels for QA testing
	hearts_label = Label.new()
	hearts_label.name = "HeartsLabel"
	hearts_label.visible = false
	hud_layer.add_child(hearts_label)

	round_label = Label.new()
	round_label.name = "RoundLabel"
	round_label.visible = false
	hud_layer.add_child(round_label)

	feedback_label = Label.new()
	feedback_label.name = "FeedbackLabel"
	feedback_label.visible = false
	hud_layer.add_child(feedback_label)

	camera_label = Label.new()
	camera_label.name = "CameraLabel"
	camera_label.visible = false
	hud_layer.add_child(camera_label)

	finish_button = Button.new()
	finish_button.name = "FinishButton"
	finish_button.visible = false
	finish_button.pressed.connect(_exit_to_results)
	hud_layer.add_child(finish_button)


func _create_carnival_hud_plaque(hud_layer: Control, filename: String, node_name: String) -> TextureRect:
	var path := CARNIVAL_ART + filename
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var plaque := TextureRect.new()
	plaque.name = node_name
	plaque.texture = tex
	plaque.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plaque.stretch_mode = TextureRect.STRETCH_SCALE
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(plaque)
	return plaque


func _bind_raw_art_textures() -> void:
	booth_backdrop.texture = _load_raw_png(BOOTH_PNG)
	foreground_counter.texture = _load_raw_png(COUNTER_PNG)
	for lane in range(mini(balloon_slots.size(), BALLOON_PNGS.size())):
		var slot := balloon_slots[lane]
		var sprite := slot.get_node_or_null("Sprite") as Sprite2D
		if sprite != null:
			var new_path: String = CARNIVAL_ART + String(["balloon_purple.png", "balloon_green.png", "balloon_blue.png"][lane])
			var has_new_art := ResourceLoader.exists(new_path)
			sprite.texture = _load_raw_png(new_path if has_new_art else String(BALLOON_PNGS[lane]))
			if has_new_art and sprite.texture != null:
				var source_size := sprite.texture.get_size()
				sprite.scale = Vector2(128.0 / source_size.x, 183.0 / source_size.y)
			else:
				sprite.scale = Vector2(0.50, 0.50)
			sprite.position = Vector2(0.0, 38.0)
		var label := slot.get_node_or_null("WordLabel") as Label
		if label != null:
			label.add_theme_font_override("font", FONT)
			label.add_theme_font_size_override("font_size", 22)
			label.add_theme_color_override("font_color", Color.WHITE)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 6)


func _load_raw_png(path: String) -> Texture2D:
	# Reuse Godot's imported and cached textures across retries/scene switches.
	# Decoding raw PNGs and creating new GPU textures on every _ready() caused
	# a noticeable startup hitch and unnecessary duplicate allocations.
	if not ResourceLoader.exists(path):
		push_error("Balloon Popping art texture missing: %s" % path)
		return null
	return load(path) as Texture2D


func _apply_context() -> void:
	clear_hand_raise_tracking()
	hand_raise_last_shot_ms = -1
	_stop_voice_feedback()
	last_missed_shot_voice_msec = -100000
	used_words.clear()
	last_round_words.clear()
	var previous_words: Variant = context.get("balloon_used_words", [])
	if previous_words is Array:
		for value in previous_words:
			var key := String(value).strip_edges().to_lower()
			if not key.is_empty():
				used_words[key] = true
	elif previous_words is Dictionary:
		for value in previous_words.keys():
			var key := String(value).strip_edges().to_lower()
			if not key.is_empty() and bool(previous_words[value]):
				used_words[key] = true
	var raw_mode := String(context.get("game_mode", context.get("mode", "Seconds"))).to_lower()
	if raw_mode in ["seconds", "60s", "sec", "quiz"]:
		game_mode = "Seconds"
		is_seconds_mode = true
		is_lives_mode = false
		# Seconds mode is strictly one 60-second attempt; hearts do not exist.
		time_remaining = SECONDS_MODE_DURATION
		hearts = 0
	else:
		game_mode = "Lives"
		is_seconds_mode = false
		is_lives_mode = true
		# Lives ends on zero hearts, without a global countdown.
		time_remaining = 0.0
		hearts = LIVES_MODE_HEARTS

	var difficulty := _difficulty()
	match difficulty:
		"Easy":
			projectile_speed = 950.0
			launcher_max_speed = 540.0
			launcher_acceleration = 1900.0
			round_time_limit = 9.0
			balloon_float_speed = BALLOON_FLOAT_SPEED
			balloon_reveal_seconds = BALLOON_REVEAL_SECONDS
			float_start_delay = 0.55
		"Hard":
			projectile_speed = 1490.0
			launcher_max_speed = 920.0
			launcher_acceleration = 3700.0
			round_time_limit = 5.0
			balloon_float_speed = 154.0
			balloon_reveal_seconds = 0.72
			float_start_delay = 0.20
		_:
			projectile_speed = 1250.0
			launcher_max_speed = 750.0
			launcher_acceleration = 2900.0
			round_time_limit = 7.0
			balloon_float_speed = 98.0
			balloon_reveal_seconds = 0.92
			float_start_delay = 0.37
	# Every fresh gameplay session resets its boost; subsequent question rounds
	# and ordinary pause/resume never replace this current cumulative speed.
	balloon_base_float_speed = balloon_float_speed
	balloon_speed_multiplier = 1.0

	miss_costs_heart = is_lives_mode
	wrong_penalty = 0

	score = int(context.get("score", 0))
	correct_count = int(context.get("correct", 0))
	attempts = int(context.get("attempts", 0))
	finishing = false
	round_completed = false
	timer_running = true
	round_active_before_pause = false
	next_round_pending = false
	# Start the launcher centered in the current gameplay viewport, including
	# Godot's smaller editor preview; never assume the width is always 1280.
	launcher_x = size.x * 0.5
	body_target_x = launcher_x
	launcher_velocity = 0.0
	round_index = maxi(int(context.get("balloon_round", 0)), 0)
	_refresh_hud()
	_start_new_round()


func _process(delta: float) -> void:
	if not timer_running or finishing:
		return
	if is_seconds_mode:
		time_remaining = maxf(time_remaining - delta, 0.0)
		if time_remaining <= 0.0:
			_finish_round()
			return
	if is_lives_mode and hearts <= 0:
		_finish_round()
		return

	if round_active:
		# Wait until all three balloons have actually risen into view before
		# counting down the question or applying their gentle floating motion.
		# Otherwise the tween and manual movement fight over position:y, making
		# balloons appear to jump into the middle of the booth.
		var revealing := is_instance_valid(balloon_motion_tween) and balloon_motion_tween.is_running()
		if not revealing:
			round_time_remaining = maxf(round_time_remaining - delta, 0.0)
			if round_time_remaining <= 0.0:
				_on_question_timeout()
				_refresh_hud()
				return
		if revealing:
			pass
		elif not balloon_floating:
			float_timer -= delta
			if float_timer <= 0.0:
				balloon_floating = true
		else:
			for lane in range(balloons.size()):
				var balloon := balloons[lane]
				if balloon != null and is_instance_valid(balloon) and balloon.visible:
					balloon.position.y -= balloon_float_speed * delta
					if balloon.position.y < -120.0:
						balloon.visible = false
						balloon.monitoring = false
						balloon.monitorable = false
						balloons[lane] = null

			var has_active := false
			for b in balloons:
				if b != null and is_instance_valid(b) and b.visible:
					has_active = true
					break
			if not has_active:
				round_active = false
				balloon_floating = false
				_schedule_next_round(0.55)

	_refresh_hud()


func _input(event: InputEvent) -> void:
	if finishing:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if key_event.keycode in [KEY_P, KEY_ESCAPE]:
			if timer_running:
				_pause()
			else:
				_resume()
			get_viewport().set_input_as_handled()
			return
		if not timer_running:
			return


func _physics_process(delta: float) -> void:
	if finishing or not timer_running:
		return
	_update_launcher(delta)
	_update_projectiles(delta)


func _update_launcher(delta: float) -> void:
	# Steering is camera-only. The last pose target is held while tracking
	# briefly recovers instead of falling back to unrelated keyboard input.
	if body_target_timer > 0.0:
		body_target_timer = maxf(body_target_timer - delta, 0.0)
		var desired_velocity := clampf((body_target_x - launcher_x) * 7.0, -launcher_max_speed, launcher_max_speed)
		launcher_velocity = move_toward(launcher_velocity, desired_velocity, launcher_acceleration * delta)
		launcher_x += launcher_velocity * delta
	else:
		launcher_velocity = move_toward(launcher_velocity, 0.0, launcher_acceleration * delta)
		launcher_x += launcher_velocity * delta

	launcher_x = clampf(launcher_x, _play_left(), _play_right())
	launcher.position = Vector2(launcher_x, _launcher_y())


func _launch_projectile(now_ms: int = -1) -> bool:
	# Only the gesture edge above may authorize a launch. This also blocks old
	# or duplicate callers of _launch_projectile from bypassing the reload.
	if not _hand_raise_firing_authorized or finishing or not timer_running or not round_active \
			or projectiles.size() >= 2 or not is_instance_valid(projectile_layer) \
			or not is_instance_valid(launcher):
		return false
	var now := Time.get_ticks_msec() if now_ms < 0 else now_ms
	if hand_raise_last_shot_ms >= 0 and now - hand_raise_last_shot_ms < HAND_RAISE_RELOAD_MS:
		return false
	var projectile := STONE_SCENE.instantiate() as Area2D
	if projectile == null:
		return false
	projectile.name = "StoneProjectile"
	projectile.position = Vector2(launcher_x, launcher.position.y - 145.0)
	projectile.z_index = 10
	projectile_layer.add_child(projectile)
	projectile.area_entered.connect(_on_projectile_area_entered.bind(projectile))
	projectiles.append(projectile)
	projectile_velocities[projectile] = Vector2(0.0, -projectile_speed)
	hand_raise_last_shot_ms = now
	return true


func _update_projectiles(delta: float) -> void:
	# A question that has already timed out or transitioned away cannot accept
	# any more shots. Retire its in-flight stones without recording an attempt.
	if not round_active:
		_clear_projectiles()
		return
	for projectile in projectiles.duplicate():
		if not is_instance_valid(projectile):
			_forget_projectile(projectile)
			continue
		var velocity: Vector2 = projectile_velocities.get(projectile, Vector2(0.0, -projectile_speed))
		var previous_position: Vector2 = projectile.position
		var next_position: Vector2 = previous_position + velocity * delta
		projectile.position = next_position

		if previous_position.distance_to(next_position) > SWEPT_COLLISION_MIN_TRAVEL:
			var swept_lane := _find_swept_balloon_lane(previous_position, next_position)
			if swept_lane >= 0:
				_resolve_projectile_balloon_hit(projectile, swept_lane)
				continue
		if projectile.position.y < 90.0:
			_on_projectile_missed(projectile)


func _find_swept_balloon_lane(from_position: Vector2, to_position: Vector2) -> int:
	if finishing or not timer_running or not round_active:
		return -1
	var travel := to_position - from_position
	var travel_length_sq := travel.length_squared()
	if travel_length_sq <= 0.0001:
		return -1
	var combined_radius := BALLOON_COLLISION_RADIUS + PROJECTILE_COLLISION_RADIUS
	var combined_radius_sq := combined_radius * combined_radius
	var earliest_t := INF
	var earliest_lane := -1
	for lane in range(mini(balloons.size(), LANE_COUNT)):
		var balloon := balloons[lane]
		# Swept/low-FPS collision must respect the same hit window as the
		# physics Area2D. A balloon rising behind the counter is not hittable.
		if not is_instance_valid(balloon) or not balloon.visible or not balloon.monitorable or not balloon.monitoring:
			continue
		var center := balloon.position
		var t := clampf((center - from_position).dot(travel) / travel_length_sq, 0.0, 1.0)
		var closest := from_position + travel * t
		if closest.distance_squared_to(center) <= combined_radius_sq and t < earliest_t:
			earliest_t = t
			earliest_lane = lane
	return earliest_lane


func _on_projectile_area_entered(area: Area2D, projectile: Area2D) -> void:
	if finishing or not timer_running or not round_active:
		return
	if not is_instance_valid(projectile) or not projectile_velocities.has(projectile):
		return
	if not area.has_meta("balloon_lane"):
		return
	if not area.visible or not area.monitorable or not area.monitoring:
		return
	var lane := int(area.get_meta("balloon_lane"))
	if lane < 0 or lane >= balloons.size() or balloons[lane] != area:
		return
	_resolve_projectile_balloon_hit(projectile, lane)


func _resolve_projectile_balloon_hit(projectile: Area2D, lane: int) -> void:
	if finishing or not timer_running or not round_active:
		return
	if not is_instance_valid(projectile) or not projectile_velocities.has(projectile):
		return
	var hit_pos := projectile.position
	_forget_projectile(projectile)
	projectile.queue_free()
	_handle_balloon_hit(lane, hit_pos)


func _handle_balloon_hit(lane: int, hit_pos: Vector2) -> void:
	if finishing or not timer_running or not round_active:
		return
	if lane < 0 or lane >= balloons.size():
		return
	var balloon := balloons[lane]
	if not is_instance_valid(balloon) or not balloon.visible:
		return
	# Half-balloon upper threshold line check:
	# If half of the balloon touches the line (balloon center is at or above UPPER_LINE_Y),
	# the balloon cannot pop. Show the pop burst starburst, but balloon keeps floating!
	if balloon.position.y <= UPPER_LINE_Y:
		_spawn_pop_burst(hit_pos)
		return
	_pop_balloon(lane)


func _pop_balloon(lane: int) -> void:
	if finishing or not timer_running or not round_active:
		return
	if lane < 0 or lane >= balloons.size():
		return
	var balloon := balloons[lane]
	if not is_instance_valid(balloon):
		return
	var was_valid := pending_valid_lanes.has(lane)
	var pop_position := balloon.position
	balloon.set_deferred("monitoring", false)
	balloon.set_deferred("monitorable", false)
	balloon.visible = false
	balloons[lane] = null
	_spawn_pop_burst(pop_position)

	attempts += 1
	if was_valid:
		pending_valid_lanes.erase(lane)
		correct_count += 1
		_boost_balloon_ascent()
		_speak_balloon_feedback(true)
		var award := _correct_award()
		score += award
		_show_floating_score("+%d" % award, pop_position, Color("#FFEB3B"))
		_spawn_confetti(pop_position, true)
		if pending_valid_lanes.is_empty():
			feedback_label.text = "+%d • GREAT POP!" % award
			round_active = false
			balloon_floating = false
			_schedule_next_round(0.62)
		else:
			feedback_label.text = "+%d • ONE CORRECT BALLOON LEFT" % award
	else:
		_speak_balloon_feedback(false)
		_show_floating_score("-0", pop_position, Color("#E53935"))
		_spawn_confetti(pop_position, false)
		if is_lives_mode:
			hearts = maxi(hearts - 1, 0)
			feedback_label.text = "WRONG BALLOON • -0 POINTS • -1 HEART"
			if hearts <= 0:
				_finish_round()
		else:
			feedback_label.text = "WRONG BALLOON • -0 POINTS"
	_refresh_hud()


func _on_projectile_missed(projectile: Area2D) -> void:
	if not projectile_velocities.has(projectile):
		return
	_forget_projectile(projectile)
	projectile.queue_free()
	# A late physics/miss notification after a round ends is cleanup only; it
	# must never consume a Lives heart or change the attempt denominator.
	if finishing or not timer_running or not round_active:
		return
	attempts += 1
	_speak_balloon_feedback(false, true)
	if miss_costs_heart:
		hearts = maxi(hearts - 1, 0)
		feedback_label.text = "MISSED SHOT • -1 HEART"
		if hearts <= 0:
			_finish_round()
	else:
		feedback_label.text = "MISSED SHOT"
	_refresh_hud()


func _on_question_timeout() -> void:
	if not round_active:
		return
	round_active = false
	balloon_floating = false
	_speak_balloon_feedback(false, true)
	if is_lives_mode:
		hearts = maxi(hearts - 1, 0)
		if hearts <= 0:
			_finish_round()
			return
	_schedule_next_round(0.55)


func _schedule_next_round(delay: float) -> void:
	next_round_pending = true
	_hide_balloons_behind_counter()
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(_on_next_round_delay_elapsed)


func _on_next_round_delay_elapsed() -> void:
	if not next_round_pending:
		return
	if finishing:
		next_round_pending = false
		return
	if not timer_running:
		return
	next_round_pending = false
	_start_new_round()


func _start_new_round() -> void:
	if finishing or not timer_running or not is_inside_tree():
		return
	next_round_pending = false
	_clear_balloons()
	_clear_projectiles()
	var data := _request_round_data()
	var normalized := _normalize_round(data)
	if normalized.is_empty() and (data.get("options", []) as Array).is_empty():
		# No three-word round can be built from the remaining eligible pools.
		# Recycle only the exhausted matching/distractor pool, not the entire
		# shared history: an exhausted Pronoun pool must not prematurely reuse
		# still-fresh words from its larger distractor pool.
		if _recycle_exhausted_vocabulary():
			var exclusions := used_words.duplicate()
			for word in last_round_words:
				exclusions[word] = true
			data = GRAMMAR_BANK.lane_round(_topic(), _difficulty(), rng, exclusions)
			normalized = _normalize_round(data)
			if normalized.is_empty():
				# Extremely small custom banks might require the previous round's
				# words, but only relax the immediate-repeat safeguard if necessary.
				data = _request_round_data()
				normalized = _normalize_round(data)
	if normalized.is_empty():
		# Invalid/unavailable vocabulary must never be interpreted as losing a
		# timed game or its remaining lives; retry without opening Results.
		push_warning("Balloon Popping: no valid %s/%s question; retrying." % [_topic(), _difficulty()])
		round_active = false
		_schedule_next_round(0.55)
		return
	var options: Array[String] = normalized["options"]
	last_round_words.clear()
	for word in options:
		var key := word.strip_edges().to_lower()
		used_words[key] = true
		last_round_words[key] = true
	round_index += 1
	valid_lanes = normalized["valid_indices"]
	var negative_prompt := _difficulty() == "Hard" or (_difficulty() == "Normal" and round_index % 3 == 0)
	if negative_prompt:
		var excludes: Array[int] = []
		for lane in range(LANE_COUNT):
			if not valid_lanes.has(lane):
				excludes.append(lane)
		valid_lanes = excludes
	pending_valid_lanes = valid_lanes.duplicate()
	# A negative grammar round changes which balloons score. Keep that rule
	# visible in the existing wooden banner after removing the duplicate card.
	if is_instance_valid(banner_tagline):
		var category := String(TOPIC_PLURALS.get(_topic(), "NOUNS"))
		banner_tagline.text = ("POP NOT %s!" if negative_prompt else "POP %s!") % category
		_layout_hud()
	round_time_remaining = round_time_limit
	round_active = true
	_spawn_balloons(options)
	_refresh_hud()


func _request_round_data() -> Dictionary:
	return GRAMMAR_BANK.lane_round(_topic(), _difficulty(), rng, used_words)


func _recycle_exhausted_vocabulary() -> bool:
	var matching: Array[String] = GRAMMAR_BANK._available_words(_topic(), true, _difficulty(), used_words)
	var distractors: Array[String] = GRAMMAR_BANK._available_words(_topic(), false, _difficulty(), used_words)
	var recycle_matching := matching.is_empty()
	# A three-lane question needs at least one matching and one distractor;
	# a single remaining word in each pool cannot form three distinct lanes.
	# Prefer recycling distractors in that case so the final new matching word
	# remains available instead of being discarded.
	var recycle_distractors := distractors.is_empty() or (matching.size() == 1 and distractors.size() == 1)
	if not recycle_matching and not recycle_distractors:
		return false
	if recycle_matching:
		for word in GRAMMAR_BANK._available_words(_topic(), true, _difficulty(), {}):
			used_words.erase(word.strip_edges().to_lower())
	if recycle_distractors:
		for word in GRAMMAR_BANK._available_words(_topic(), false, _difficulty(), {}):
			used_words.erase(word.strip_edges().to_lower())
	return true


func _normalize_round(data: Dictionary) -> Dictionary:
	var raw_options: Array = data.get("options", [])
	var raw_valid: Array = data.get("valid_indices", [])
	if raw_options.size() != LANE_COUNT:
		return {}
	var options: Array[String] = []
	var round_words: Dictionary = {}
	for value in raw_options:
		var word := String(value).strip_edges()
		var key := word.to_lower()
		if key.is_empty() or used_words.has(key) or round_words.has(key):
			return {}
		round_words[key] = true
		options.append(word)
	var valid: Array[int] = []
	for value in raw_valid:
		var index := int(value)
		if index < 0 or index >= LANE_COUNT or valid.has(index):
			return {}
		valid.append(index)
	if valid.is_empty() or valid.size() == LANE_COUNT:
		return {}
	return {"options": options, "valid_indices": valid}


func _spawn_balloons(options: Array[String]) -> void:
	balloons = balloon_slots.duplicate()
	if is_instance_valid(balloon_motion_tween):
		balloon_motion_tween.kill()
	balloon_tween_paused = false
	balloon_floating = false
	float_timer = float_start_delay
	balloon_motion_tween = create_tween()
	balloon_motion_tween.set_parallel(true)
	for lane in range(LANE_COUNT):
		var balloon := balloon_slots[lane]
		balloon.set_meta("balloon_lane", lane)
		balloon.collision_layer = 2
		balloon.collision_mask = 4
		# Move while still hidden, then reveal behind the foreground counter.
		# The rising balloon gradually enters the opening instead of flashing
		# at its old location for one frame.
		balloon.monitoring = false
		balloon.monitorable = false
		var label := balloon.get_node("WordLabel") as Label
		label.text = options[lane]
		_fit_balloon_word_label(label)
		balloon.position = Vector2(_lane_x(lane), _balloon_hidden_y())
		balloon.visible = true
		balloon_motion_tween.tween_property(balloon, "position:y", _balloon_y(), balloon_reveal_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	balloon_motion_tween.finished.connect(_on_balloon_reveal_finished)
	_layout_scene()


func _fit_balloon_word_label(label: Label) -> void:
	# Keep longer Normal/Hard vocabulary centered inside the authored balloons.
	# Scale just the text; the artist-provided label geometry stays editable.
	var max_width := minf(label.size.x - 12.0, 145.0)
	var font_size := 18
	while font_size > 8 and FONT.get_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x > max_width:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)


func _on_balloon_reveal_finished() -> void:
	if not round_active or not timer_running or finishing:
		return
	for balloon in balloons:
		if is_instance_valid(balloon) and balloon.visible:
			balloon.monitoring = true
			balloon.monitorable = true
	float_timer = float_start_delay


func _spawn_pop_burst(position_value: Vector2, _color: Color = Color.WHITE) -> void:
	var burst := Sprite2D.new()
	burst.texture = POP_TEXTURE
	burst.position = position_value
	burst.z_index = 12
	burst.scale = Vector2(0.40, 0.40)
	add_child(burst)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(burst, "scale", Vector2(0.80, 0.80), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(burst, "modulate:a", 0.0, 0.30).set_delay(0.04)
	tween.chain().tween_callback(burst.queue_free)


func _spawn_confetti(pos: Vector2, is_correct: bool) -> void:
	var confetti_root := Node2D.new()
	confetti_root.position = pos
	confetti_root.z_index = 30
	add_child(confetti_root)

	var piece_count := 26 if is_correct else 20
	var rainbow_colors: Array[Color] = [
		Color("#FF4D4D"), Color("#FF9E42"), Color("#FFD54F"),
		Color("#66BB6A"), Color("#42A5F5"), Color("#AB47BC"),
		Color("#EC407A"), Color("#26C6DA")
	]

	for i in range(piece_count):
		var piece := Polygon2D.new()
		var hw := rng.randf_range(3.0, 7.0)
		var hh := rng.randf_range(3.0, 6.0)
		piece.polygon = PackedVector2Array([
			Vector2(-hw, -hh), Vector2(hw, -hh),
			Vector2(hw, hh), Vector2(-hw, hh)
		])
		if is_correct:
			piece.color = rainbow_colors[rng.randi_range(0, rainbow_colors.size() - 1)]
		else:
			piece.color = Color("#111111") if rng.randf() < 0.85 else Color("#2A2A2A")

		confetti_root.add_child(piece)

		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(35.0, 110.0)
		var target_pos := Vector2(cos(angle), sin(angle)) * dist
		var end_rot := rng.randf_range(-PI * 3.0, PI * 3.0)

		var tween := create_tween().set_parallel(true)
		tween.tween_property(piece, "position", target_pos, rng.randf_range(0.55, 0.85)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(piece, "rotation", end_rot, rng.randf_range(0.55, 0.85))
		tween.tween_property(piece, "modulate:a", 0.0, 0.8).set_delay(rng.randf_range(0.3, 0.5))

	var cleanup_tween := create_tween()
	cleanup_tween.tween_interval(0.9)
	cleanup_tween.tween_callback(confetti_root.queue_free)


func _show_floating_score(score_text: String, pos: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = score_text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.position = pos - Vector2(30.0, 40.0)
	label.z_index = 25
	add_child(label)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", pos.y - 80.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


func _clear_balloons() -> void:
	if is_instance_valid(balloon_motion_tween):
		balloon_motion_tween.kill()
	balloon_tween_paused = false
	balloon_floating = false
	for balloon in balloon_slots:
		if is_instance_valid(balloon):
			balloon.monitoring = false
			balloon.monitorable = false
			balloon.visible = false
	balloons.clear()


func _clear_projectiles() -> void:
	for projectile in projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	projectiles.clear()
	projectile_velocities.clear()


func _forget_projectile(projectile: Area2D) -> void:
	projectile_velocities.erase(projectile)
	projectiles.erase(projectile)


func _layout_scene() -> void:
	if not is_instance_valid(launcher):
		return
	if is_instance_valid(foreground_counter):
		foreground_counter.position = Vector2(0.0, size.y * 0.445)
		foreground_counter.size = size
	launcher_x = clampf(launcher_x, _play_left(), _play_right())
	launcher.position = Vector2(launcher_x, _launcher_y())
	for lane in range(mini(balloons.size(), LANE_COUNT)):
		var balloon := balloons[lane]
		if is_instance_valid(balloon):
			balloon.position.x = _lane_x(lane)

	_layout_hud()


func _layout_hud() -> void:
	if not is_instance_valid(title_label):
		return
	if carnival_objective_plaque != null or carnival_title_plaque != null:
		# The carnival stage uses a 1280x720 design canvas. Scale the whole HUD
		# coherently for the smaller embedded editor preview and fullscreen.
		var ui_scale := clampf(minf(size.x / 1280.0, size.y / 720.0), 0.66, 1.50)
		if carnival_objective_plaque != null:
			# Preserve the editable banner/tagline rectangles authored in the scene.
			for item: Control in [carnival_objective_plaque, banner_tagline]:
				if not is_instance_valid(item):
					continue
				if not _authored_banner_rects.has(item.name):
					_authored_banner_rects[item.name] = item.get_rect()
				var authored: Rect2 = _authored_banner_rects[item.name]
				item.position = authored.position * ui_scale
				item.size = authored.size * ui_scale
		else:
			carnival_title_plaque.position = Vector2(22.0, 10.0) * ui_scale
			carnival_title_plaque.size = Vector2(310.0, 70.0) * ui_scale
		if is_instance_valid(banner_tagline):
			var tagline_font_size := maxi(13, int(round(20.0 * ui_scale)))
			while tagline_font_size > 13 and FONT.get_string_size(
				banner_tagline.text, HORIZONTAL_ALIGNMENT_CENTER, -1, tagline_font_size
			).x > banner_tagline.size.x - 8.0:
				tagline_font_size -= 1
			banner_tagline.add_theme_font_size_override("font_size", tagline_font_size)
		if carnival_score_plaque != null:
			carnival_score_plaque.position = Vector2(size.x - 470.0 * ui_scale, 14.0 * ui_scale)
			carnival_score_plaque.size = Vector2(204.0, 128.0) * ui_scale
			if is_instance_valid(score_bottom_container):
				score_bottom_container.position = carnival_score_plaque.position + Vector2(47.0, 50.0) * ui_scale
				score_bottom_container.size = Vector2(110.0, 46.0) * ui_scale
			var score_font_size := maxi(17, int(round(39.0 * ui_scale)))
			while score_font_size > 17 and FONT.get_string_size(score_bottom_number.text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, score_font_size).x > score_bottom_container.size.x - 6.0:
				score_font_size -= 2
			score_bottom_number.add_theme_font_size_override("font_size", score_font_size)
		# The original Catch textures are approximately 3:1, not 177:78.
		# Give each badge one uniform width scale; derive its height from the
		# ACTUAL active texture ratio so neither the stopwatch nor hearts squash.
		var badge_width := 171.0 * ui_scale
		var badge_x := size.x - 248.0 * ui_scale
		var badge_y := 16.0 * ui_scale
		var timer_height := badge_width * SHARED_TIMER_BADGE.get_height() / SHARED_TIMER_BADGE.get_width()
		var lives_height := badge_width * SHARED_LIVES_STATE_3.get_height() / SHARED_LIVES_STATE_3.get_width()
		if is_instance_valid(shared_timer_plaque):
			shared_timer_plaque.position = Vector2(badge_x, badge_y)
			shared_timer_plaque.size = Vector2(badge_width, timer_height)
		if is_instance_valid(shared_lives_plaque):
			shared_lives_plaque.position = Vector2(badge_x, badge_y)
			shared_lives_plaque.size = Vector2(badge_width, lives_height)
		if is_instance_valid(time_label):
			time_label.position = Vector2(badge_x + 63.0 * ui_scale, badge_y + 9.0 * ui_scale)
			time_label.size = Vector2(101.0, 39.0) * ui_scale
			time_label.add_theme_font_size_override("font_size", maxi(15, int(round(26.0 * ui_scale))))
		if is_instance_valid(pause_button):
			pause_button.position = Vector2(size.x - 65.0 * ui_scale, 16.0 * ui_scale)
			pause_button.size = Vector2(45.0, 45.0) * ui_scale
		return
	title_label.position = Vector2(36.0, 16.0)
	title_label.size = Vector2(340.0, 36.0)

	if is_instance_valid(banner_tagline):
		banner_tagline.position = Vector2(36.0, 52.0)
		banner_tagline.size = Vector2(minf(size.x * 0.35, 500.0), 78.0)

	if is_instance_valid(score_bottom_container):
		# Keep the number away from the shooting cannon.
		score_bottom_container.position = Vector2(size.x - 450.0, 16.0)
		score_bottom_container.size = Vector2(220.0, 95.0)

	if is_instance_valid(time_label):
		# Numeric time belongs in the inset of the blue stopwatch graphic.
		time_label.position = Vector2(size.x - 218.0, 21.0)
		time_label.size = Vector2(110.0, 50.0)
	if is_instance_valid(shared_timer_plaque):
		shared_timer_plaque.position = Vector2(size.x - 290.0, 8.0)
		shared_timer_plaque.size = Vector2(195.0, 76.0)
	if is_instance_valid(shared_lives_plaque):
		shared_lives_plaque.position = Vector2(size.x - 290.0, 8.0)
		shared_lives_plaque.size = Vector2(195.0, 76.0)

	if is_instance_valid(hearts_box):
		hearts_box.position = Vector2(size.x - 240.0, 25.0)
		hearts_box.size = Vector2(160.0, 44.0)

	if is_instance_valid(pause_button):
		pause_button.position = Vector2(size.x - 72.0, 22.0)
		pause_button.size = Vector2(44.0, 44.0)


func _hide_balloons_behind_counter() -> void:
	if is_instance_valid(balloon_motion_tween):
		balloon_motion_tween.kill()
	balloon_tween_paused = false
	balloon_floating = false
	balloon_motion_tween = create_tween()
	balloon_motion_tween.set_parallel(true)
	for balloon in balloon_slots:
		if is_instance_valid(balloon) and balloon.visible:
			balloon.set_deferred("monitoring", false)
			balloon.set_deferred("monitorable", false)
			balloon_motion_tween.tween_property(balloon, "position:y", _balloon_hidden_y(), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _refresh_hud() -> void:
	if score_bottom_number != null:
		score_bottom_number.text = str(score)
	if is_lives_mode:
		if is_instance_valid(shared_timer_plaque):
			shared_timer_plaque.visible = false
		if is_instance_valid(shared_lives_plaque):
			shared_lives_plaque.visible = hearts > 0
			match clampi(hearts, 1, 3):
				1:
					shared_lives_plaque.texture = SHARED_LIVES_STATE_1
				2:
					shared_lives_plaque.texture = SHARED_LIVES_STATE_2
				_:
					shared_lives_plaque.texture = SHARED_LIVES_STATE_3
		if time_label != null:
			time_label.visible = false
		if hearts_box != null:
			hearts_box.visible = false
		if hearts_label != null:
			hearts_label.text = "HEARTS %d" % hearts
	else:
		if is_instance_valid(shared_timer_plaque):
			shared_timer_plaque.visible = true
		if is_instance_valid(shared_lives_plaque):
			shared_lives_plaque.visible = false
		if time_label != null:
			time_label.visible = true
			time_label.text = "%ds" % int(ceil(maxf(time_remaining, 0.0)))
		if hearts_box != null:
			hearts_box.visible = false
		if hearts_label != null:
			hearts_label.text = "TIME %02d" % int(ceil(maxf(time_remaining, 0.0)))

	if round_label != null:
		round_label.text = "ROUND %d" % maxi(round_index, 1)


func _toggle_pause() -> void:
	if finishing:
		return
	if timer_running:
		_pause()
	else:
		_resume()


func _pause() -> void:
	if finishing or not timer_running:
		return
	clear_hand_raise_tracking()
	_stop_voice_feedback()
	round_active_before_pause = round_active
	timer_running = false
	round_active = false
	balloon_tween_paused = false
	if is_instance_valid(balloon_motion_tween) and balloon_motion_tween.is_running():
		balloon_motion_tween.pause()
		balloon_tween_paused = true
	round_completed = false
	if pause_button != null:
		pause_button.icon = PLAY_ICON
	requested.emit("pause", get_context())


func _resume() -> void:
	if finishing:
		return
	timer_running = true
	if balloon_tween_paused and is_instance_valid(balloon_motion_tween):
		balloon_motion_tween.play()
	balloon_tween_paused = false
	if pause_button != null:
		pause_button.icon = PAUSE_ICON
	if next_round_pending:
		next_round_pending = false
		_start_new_round()
	else:
		round_active = round_active_before_pause
	round_active_before_pause = false


func _exit_to_results() -> void:
	if finishing:
		return
	clear_hand_raise_tracking()
	_stop_voice_feedback()
	finishing = true
	timer_running = false
	round_active = false
	next_round_pending = false
	round_completed = false
	_clear_projectiles()
	requested.emit("results", get_context())


func _initialize_voice_feedback() -> void:
	_kids_voice = KidsVoice.new()
	_kids_voice.setup(self)
	balloon_voice_player = _kids_voice.get_voice_player()
	balloon_voice_player.name = "BalloonVoicePlayer"


func _speak_balloon_feedback(correct: bool, missed: bool = false) -> void:
	if _kids_voice == null or not is_instance_valid(balloon_voice_player) or finishing or not timer_running:
		return
	if missed:
		# A run of missed projectiles should not repeatedly cut off speech.
		var now_msec := Time.get_ticks_msec()
		if balloon_voice_player.playing or now_msec - last_missed_shot_voice_msec < MISSED_SHOT_VOICE_COOLDOWN_MS:
			return
		if _kids_voice.play_missed():
			last_missed_shot_voice_msec = now_msec
	elif correct:
		_kids_voice.play_correct()
	else:
		_kids_voice.play_wrong()


func _stop_voice_feedback() -> void:
	if _kids_voice != null:
		_kids_voice.stop()


func _exit_tree() -> void:
	clear_hand_raise_tracking()
	_stop_voice_feedback()
	if _kids_voice != null:
		_kids_voice.release()


func _topic() -> String:
	var value := String(context.get("topic", context.get("game_style", "Noun"))).strip_edges()
	return value if not value.is_empty() else "Noun"


func _difficulty() -> String:
	var value := String(context.get("difficulty", "Normal")).strip_edges().capitalize()
	return value if value in ["Easy", "Normal", "Hard"] else "Normal"


func _correct_award() -> int:
	return CORRECT_POP_SCORE


func _boost_balloon_ascent() -> void:
	var ceiling: float = BALLOON_SPEED_CAPS[_difficulty()]
	balloon_speed_multiplier = minf(ceiling, lerpf(
		balloon_speed_multiplier, ceiling, BALLOON_SPEED_BOOST_BLEND))
	balloon_float_speed = balloon_base_float_speed * balloon_speed_multiplier


func _lane_x(lane: int) -> float:
	return lerpf(size.x * 0.24, size.x * 0.76, float(lane) / 2.0)


func _play_left() -> float:
	return size.x * 0.16


func _play_right() -> float:
	return size.x * 0.84


func _balloon_y() -> float:
	return clampf(size.y * 0.43, 245.0, 440.0)


func _balloon_hidden_y() -> float:
	# Entire painted balloon + string begins behind the wooden foreground.
	# On 875x500 the larger of these bounds is also below the screen edge.
	return maxf(size.y * 0.88, _balloon_y() + 265.0)


func _launcher_y() -> float:
	return size.y - clampf(size.y * 0.10, 68.0, 105.0)
