@tool
extends Control

signal requested(target: String, payload: Dictionary)

const UI = preload("res://ui/play/play_ui.gd")
const FONT: Font = preload("res://assets/fonts/TitanOne-Regular.ttf")
const GRAMMAR_BANK = preload("res://ui/minigames/grammar_bank.gd")
const STONE_SCENE: PackedScene = preload("res://ui/minigames/balloon_art/stone.tscn")

const BOOTH_PNG := "res://BalloonPoppingBackground/0826b13c-250f-42e1-9398-a83d2922a1d8.png"
const COUNTER_PNG := "res://BalloonPoppingBackground/95ae2a22-302d-48f7-9b5f-e12b0104c822.png"
const BALLOON_PNGS := [
	"res://BalloonPoppingBalloons/purple.png",
	"res://BalloonPoppingBalloons/green.png",
	"res://BalloonPoppingBalloons/blue.png"
]
const POP_TEXTURE: Texture2D = preload("res://Components/Pop.png")
const HEART_RED: Texture2D = preload("res://Components/HeartRed.png")
const HEART_BLACK: Texture2D = preload("res://Components/HeartBlack.png")
const SHARED_TIMER_BADGE: Texture2D = preload("res://ui/minigames/catch_hud/generated/timer_badge.png")
const SHARED_LIVES_STATE_1: Texture2D = preload("res://ui/minigames/catch_hud/generated/replacement/lives_state_1.png")
const SHARED_LIVES_STATE_2: Texture2D = preload("res://ui/minigames/catch_hud/generated/replacement/lives_state_2.png")
const SHARED_LIVES_STATE_3: Texture2D = preload("res://ui/minigames/catch_hud/generated/replacement/lives_state_3.png")
const CARNIVAL_ART := "res://ui/minigames/balloon_art/reference/"
const PAUSE_ICON: Texture2D = preload("res://assets/icons/pause_white.svg")
const PLAY_ICON: Texture2D = preload("res://assets/icons/play_white.svg")

const ACTIVITY := "Balloon Popping"
const LANE_COUNT := 3
const BALLOON_COLLISION_RADIUS := 58.0
const PROJECTILE_COLLISION_RADIUS := 9.0
const SWEPT_COLLISION_MIN_TRAVEL := (BALLOON_COLLISION_RADIUS + PROJECTILE_COLLISION_RADIUS) * 2.0
const UPPER_LINE_Y := 125.0
const BALLOON_FLOAT_SPEED := 52.0
const BALLOON_REVEAL_SECONDS := 1.15

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

var game_mode := "Seconds"
var is_seconds_mode := true
var is_lives_mode := false

var projectile_speed := 1000.0
var launcher_max_speed := 650.0
var launcher_acceleration := 2300.0
var round_time_limit := 7.0
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
var carnival_prompt_plaque: TextureRect
var carnival_score_plaque: TextureRect
var time_label: Label
var prompt_label: Label
var feedback_label: Label
var round_label: Label
var camera_label: Label
var title_label: Label
var pause_button: Button
var finish_button: Button
var balloon_motion_tween: Tween
var balloon_tween_paused := false


func _ready() -> void:
	if Engine.is_editor_hint():
		_setup_editor_preview()
		resized.connect(_layout_editor_preview)
		call_deferred("_layout_editor_preview")
		return
	mouse_filter = Control.MOUSE_FILTER_STOP
	rng.randomize()
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
	return payload


func set_body_x(normalized_x: float) -> void:
	var safe_x := clampf(normalized_x, -1.0, 1.0)
	var unit_x := (safe_x + 1.0) * 0.5
	body_target_x = lerpf(_play_left(), _play_right(), unit_x)
	body_target_timer = 0.30


func _finish_round() -> void:
	if finishing:
		return
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

	# Painted carnival HUD graphics are separate transparent sprites. The
	# prompt and score remain live text; never bake example words or numbers.
	carnival_objective_plaque = _create_carnival_hud_plaque(hud_layer, "objective_panel.png", "ObjectivePanel")
	if carnival_objective_plaque == null:
		carnival_title_plaque = _create_carnival_hud_plaque(hud_layer, "title_marquee.png", "CarnivalTitle")
		carnival_prompt_plaque = _create_carnival_hud_plaque(hud_layer, "prompt_blank.png", "CarnivalPrompt")
	carnival_score_plaque = _create_carnival_hud_plaque(hud_layer, "score_plaque_blank.png", "CarnivalScore")

	# Share Catch the Word's exact timer and complete 3/2/1-heart PNGs.
	# Keep the old heart nodes only as hidden compatibility nodes; do not
	# overlay them on these complete heart-state images.
	shared_timer_plaque = TextureRect.new()
	shared_timer_plaque.name = "TimerPlaque"
	shared_timer_plaque.texture = SHARED_TIMER_BADGE
	shared_timer_plaque.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shared_timer_plaque.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shared_timer_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(shared_timer_plaque)
	shared_lives_plaque = TextureRect.new()
	shared_lives_plaque.name = "LivesPlaque"
	shared_lives_plaque.texture = SHARED_LIVES_STATE_3
	shared_lives_plaque.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shared_lives_plaque.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shared_lives_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(shared_lives_plaque)

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

	prompt_label = Label.new()
	prompt_label.name = "PromptLabel"
	prompt_label.text = "POP THE MATCHING WORD"
	prompt_label.add_theme_font_override("font", FONT)
	prompt_label.add_theme_font_size_override("font_size", 16)
	prompt_label.add_theme_color_override("font_color", Color.WHITE)
	prompt_label.add_theme_color_override("font_outline_color", Color.BLACK)
	prompt_label.add_theme_constant_override("outline_size", 4)
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if carnival_objective_plaque != null or carnival_prompt_plaque != null:
		prompt_label.add_theme_color_override("font_color", Color("#122650"))
		prompt_label.add_theme_constant_override("outline_size", 0)
		prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(prompt_label)

	score_bottom_container = VBoxContainer.new()
	score_bottom_container.name = "ScoreBottomContainer"
	score_bottom_container.add_theme_constant_override("separation", -4)
	score_bottom_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(score_bottom_container)

	var score_title := Label.new()
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

	time_label = Label.new()
	time_label.name = "TimeLabel"
	time_label.text = "60s"
	time_label.add_theme_font_override("font", FONT)
	time_label.add_theme_font_size_override("font_size", 36)
	time_label.add_theme_color_override("font_color", Color.WHITE)
	time_label.add_theme_color_override("font_outline_color", Color.BLACK)
	time_label.add_theme_constant_override("outline_size", 6)
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.add_theme_font_size_override("font_size", 29)
	time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(time_label)

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
	pause_button.pressed.connect(_toggle_pause)
	hud_layer.add_child(pause_button)

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
	if is_instance_valid(launcher):
		var cannon := launcher.get_node_or_null("GunSprite") as Sprite2D
		if cannon != null and ResourceLoader.exists(CARNIVAL_ART + "cannon_front.png"):
			cannon.texture = _load_raw_png(CARNIVAL_ART + "cannon_front.png")
			cannon.scale = Vector2(0.34, 0.34)
			# Place the painted star/front face above the lower screen edge.
			# The launcher/projectile origin itself remains unchanged.
			cannon.position = Vector2(0.0, -28.0)


func _load_raw_png(path: String) -> Texture2D:
	# Reuse Godot's imported and cached textures across retries/scene switches.
	# Decoding raw PNGs and creating new GPU textures on every _ready() caused
	# a noticeable startup hitch and unnecessary duplicate allocations.
	if not ResourceLoader.exists(path):
		push_error("Balloon Popping art texture missing: %s" % path)
		return null
	return load(path) as Texture2D


func _apply_context() -> void:
	var raw_mode := String(context.get("game_mode", context.get("mode", "Seconds"))).to_lower()
	if raw_mode in ["seconds", "60s", "sec", "quiz"]:
		game_mode = "Seconds"
		is_seconds_mode = true
		is_lives_mode = false
		time_remaining = float(context.get("time_remaining", 60.0))
		hearts = int(context.get("lives", context.get("hearts", 3)))
	else:
		game_mode = "Lives"
		is_seconds_mode = false
		is_lives_mode = true
		time_remaining = float(context.get("time_remaining", 999.0))
		hearts = int(context.get("lives", context.get("hearts", 3)))

	var difficulty := _difficulty()
	match difficulty:
		"Easy":
			projectile_speed = 950.0
			launcher_max_speed = 540.0
			launcher_acceleration = 1900.0
			round_time_limit = 9.0
		"Hard":
			projectile_speed = 1160.0
			launcher_max_speed = 780.0
			launcher_acceleration = 3000.0
			round_time_limit = 5.0
		_:
			projectile_speed = 1020.0
			launcher_max_speed = 650.0
			launcher_acceleration = 2350.0
			round_time_limit = 7.0

	miss_costs_heart = false
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
					balloon.position.y -= BALLOON_FLOAT_SPEED * delta
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
		if key_event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			_launch_projectile()
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if finishing or not timer_running:
		return
	_update_launcher(delta)
	_update_projectiles(delta)


func _update_launcher(delta: float) -> void:
	var axis := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A):
		axis -= 1.0
	if Input.is_key_pressed(KEY_D):
		axis += 1.0
	axis = clampf(axis, -1.0, 1.0)

	if absf(axis) > 0.01:
		body_target_timer = 0.0
		launcher_velocity = move_toward(launcher_velocity, axis * launcher_max_speed, launcher_acceleration * delta)
		launcher_x += launcher_velocity * delta
	elif body_target_timer > 0.0:
		body_target_timer = maxf(body_target_timer - delta, 0.0)
		var desired_velocity := clampf((body_target_x - launcher_x) * 7.0, -launcher_max_speed, launcher_max_speed)
		launcher_velocity = move_toward(launcher_velocity, desired_velocity, launcher_acceleration * delta)
		launcher_x += launcher_velocity * delta
	else:
		launcher_velocity = move_toward(launcher_velocity, 0.0, launcher_acceleration * delta)
		launcher_x += launcher_velocity * delta

	launcher_x = clampf(launcher_x, _play_left(), _play_right())
	launcher.position = Vector2(launcher_x, _launcher_y())


func _launch_projectile() -> void:
	if not timer_running or not round_active or projectiles.size() >= 2:
		return
	var projectile := STONE_SCENE.instantiate() as Area2D
	projectile.name = "StoneProjectile"
	projectile.position = Vector2(launcher_x, launcher.position.y - 145.0)
	projectile.z_index = 10
	projectile_layer.add_child(projectile)
	projectile.area_entered.connect(_on_projectile_area_entered.bind(projectile))
	projectiles.append(projectile)
	projectile_velocities[projectile] = Vector2(0.0, -projectile_speed)


func _update_projectiles(delta: float) -> void:
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
	attempts += 1
	feedback_label.text = "MISSED SHOT"
	_refresh_hud()


func _on_question_timeout() -> void:
	if not round_active:
		return
	round_active = false
	balloon_floating = false
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
	round_index += 1
	var data := _request_round_data()
	var prompt := String(data.get("prompt", "WHICH WORD IS A %s?" % _topic().to_upper()))
	var normalized := _normalize_round(data)
	var options: Array[String] = normalized["options"]
	valid_lanes = normalized["valid_indices"]
	var negative_prompt := _difficulty() == "Hard" or (_difficulty() == "Normal" and round_index % 3 == 0)
	if negative_prompt:
		var excludes: Array[int] = []
		for lane in range(LANE_COUNT):
			if not valid_lanes.has(lane):
				excludes.append(lane)
		valid_lanes = excludes
		prompt = "POP WORDS THAT ARE NOT %s" % String(TOPIC_PLURALS.get(_topic(), "NOUNS"))
	pending_valid_lanes = valid_lanes.duplicate()
	prompt_label.text = prompt.to_upper()
	round_time_remaining = round_time_limit
	round_active = true
	_spawn_balloons(options)
	_refresh_hud()


func _request_round_data() -> Dictionary:
	var result: Dictionary = GRAMMAR_BANK.lane_round(_topic(), _difficulty(), rng)
	if not result.is_empty():
		return result
	return _fallback_round()


func _normalize_round(data: Dictionary) -> Dictionary:
	var raw_options: Array = data.get("options", [])
	var raw_valid: Array = data.get("valid_indices", [])
	var selected_source_indices: Array[int] = []
	var source_valid: Array[int] = []
	for value in raw_valid:
		var index := int(value)
		if index >= 0 and index < raw_options.size() and not source_valid.has(index):
			source_valid.append(index)
	for index in source_valid:
		if selected_source_indices.size() >= 2:
			break
		selected_source_indices.append(index)
	for index in range(raw_options.size()):
		if selected_source_indices.size() >= LANE_COUNT:
			break
		if not selected_source_indices.has(index):
			selected_source_indices.append(index)

	var options: Array[String] = []
	var valid: Array[int] = []
	for source_index in selected_source_indices:
		if options.size() >= LANE_COUNT:
			break
		var lane := options.size()
		options.append(String(raw_options[source_index]))
		if source_valid.has(source_index):
			valid.append(lane)

	while options.size() < LANE_COUNT:
		var make_matching := valid.is_empty()
		var word := _request_word(make_matching)
		var lane := options.size()
		options.append(word)
		if make_matching:
			valid.append(lane)

	var pair_data: Array[Dictionary] = []
	for lane in range(options.size()):
		pair_data.append({"word": options[lane], "valid": valid.has(lane)})
	pair_data.shuffle()
	options.clear()
	valid.clear()
	for lane in range(pair_data.size()):
		options.append(String(pair_data[lane]["word"]))
		if bool(pair_data[lane]["valid"]):
			valid.append(lane)
	return {"options": options, "valid_indices": valid}


func _request_word(matching: bool) -> String:
	var word := String(GRAMMAR_BANK.pick_word(_topic(), matching, rng)).strip_edges()
	if not word.is_empty():
		return word
	var pools := _fallback_pools()
	var match_pool: Array = pools["match"] if matching else pools["other"]
	return String(match_pool[rng.randi_range(0, match_pool.size() - 1)])


func _fallback_round() -> Dictionary:
	var pools := _fallback_pools()
	var match_pool: Array = pools["match"]
	var other_pool: Array = pools["other"]
	var target_count := 2 if rng.randf() < 0.34 else 1
	var options: Array[String] = []
	var valid: Array[int] = []
	for i in range(target_count):
		valid.append(options.size())
		options.append(String(match_pool[rng.randi_range(0, match_pool.size() - 1)]))
	while options.size() < LANE_COUNT:
		options.append(String(other_pool[rng.randi_range(0, other_pool.size() - 1)]))
	return {
		"prompt": "POP THE %s WORD%s" % [_topic().to_upper(), "S" if target_count > 1 else ""],
		"options": options,
		"valid_indices": valid
	}


func _fallback_pools() -> Dictionary:
	match _topic():
		"Verb":
			return {"match": ["RUN", "JUMP", "WRITE", "SING"], "other": ["APPLE", "KIND", "QUICKLY", "SHE"]}
		"Adjective":
			return {"match": ["BRIGHT", "HAPPY", "SMALL", "KIND"], "other": ["RUN", "PENCIL", "SHE", "QUICKLY"]}
		"Adverb":
			return {"match": ["QUICKLY", "QUIETLY", "TODAY", "HERE"], "other": ["DOG", "BLUE", "THEY", "DANCE"]}
		"Pronoun":
			return {"match": ["SHE", "THEY", "WE", "IT"], "other": ["TEACHER", "HAPPY", "RUN", "SOFTLY"]}
		_:
			return {"match": ["APPLE", "TEACHER", "PARK", "PENCIL"], "other": ["RUN", "BRIGHT", "QUICKLY", "THEY"]}


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
		balloon.position = Vector2(_lane_x(lane), _balloon_hidden_y())
		balloon.visible = true
		balloon_motion_tween.tween_property(balloon, "position:y", _balloon_y(), BALLOON_REVEAL_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	balloon_motion_tween.finished.connect(_on_balloon_reveal_finished)
	_layout_scene()


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
		var left := 22.0 * ui_scale
		if carnival_objective_plaque != null:
			var panel_pos := Vector2(left, size.y - 169.0 * ui_scale)
			var panel_size := Vector2(455.0, 164.0) * ui_scale
			carnival_objective_plaque.position = panel_pos
			carnival_objective_plaque.size = panel_size
			prompt_label.position = panel_pos + Vector2(24.0, 86.0) * ui_scale
			prompt_label.size = Vector2(406.0, 66.0) * ui_scale
		else:
			carnival_title_plaque.position = Vector2(left, size.y - 210.0 * ui_scale)
			carnival_title_plaque.size = Vector2(310.0, 140.0) * ui_scale
			carnival_prompt_plaque.position = Vector2(left, size.y - 96.0 * ui_scale)
			carnival_prompt_plaque.size = Vector2(460.0, 87.0) * ui_scale
			prompt_label.position = carnival_prompt_plaque.position + Vector2(26.0, 12.0) * ui_scale
			prompt_label.size = Vector2(408.0, 65.0) * ui_scale
		# Keep long grammar descriptions centered inside the actual cream inset.
		var prompt_font_size := maxi(12, int(round(17.0 * ui_scale)))
		while prompt_font_size > 12 and FONT.get_multiline_string_size(prompt_label.text,
			HORIZONTAL_ALIGNMENT_CENTER, prompt_label.size.x - 10.0, prompt_font_size).y > prompt_label.size.y - 4.0:
			prompt_font_size -= 1
		prompt_label.add_theme_font_size_override("font_size", prompt_font_size)
		if carnival_score_plaque != null:
			carnival_score_plaque.position = Vector2(size.x - 400.0 * ui_scale, size.y - 165.0 * ui_scale)
			carnival_score_plaque.size = Vector2(216.0, 136.0) * ui_scale
			if is_instance_valid(score_bottom_container):
				score_bottom_container.position = carnival_score_plaque.position + Vector2(53.0, 58.0) * ui_scale
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
		var badge_x := size.x - 177.0 * ui_scale
		var badge_y := size.y - 137.0 * ui_scale
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
			pause_button.position = Vector2(size.x - 69.0 * ui_scale, 22.0 * ui_scale)
			pause_button.size = Vector2(45.0, 45.0) * ui_scale
		return
	title_label.position = Vector2(36.0, size.y - 126.0)
	title_label.size = Vector2(340.0, 36.0)

	prompt_label.position = Vector2(36.0, size.y - 93.0)
	# Reserve the center for the cannon. On compact windows a narrower prompt
	# wraps into three readable lines instead of painting across its barrel.
	prompt_label.size = Vector2(minf(size.x * 0.35, 500.0), 78.0)

	if is_instance_valid(score_bottom_container):
		# Keep the number away from both the shooting cannon and the prompt.
		score_bottom_container.position = Vector2(size.x - 250.0, size.y - 110.0)
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
	finishing = true
	timer_running = false
	round_active = false
	next_round_pending = false
	round_completed = false
	_clear_projectiles()
	requested.emit("results", get_context())


func _topic() -> String:
	var value := String(context.get("topic", context.get("game_style", "Noun"))).strip_edges()
	return value if not value.is_empty() else "Noun"


func _difficulty() -> String:
	var value := String(context.get("difficulty", "Normal")).strip_edges().capitalize()
	return value if value in ["Easy", "Normal", "Hard"] else "Normal"


func _correct_award() -> int:
	match _difficulty():
		"Easy": return 100
		"Hard": return 175
		_: return 125


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
