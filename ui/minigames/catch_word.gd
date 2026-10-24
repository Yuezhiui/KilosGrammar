extends Control

signal requested(target: String, payload: Dictionary)

const UI = preload("res://ui/play/play_ui.gd")
const TITLE_FONT: Font = preload("res://assets/fonts/TitanOne-Regular.ttf")
const GRAMMAR_BANK_PATH := "res://ui/minigames/grammar_bank.gd"

const APPLE_TEXTURE: Texture2D = preload("res://Components/Apple.png")
const HEART_RED: Texture2D = preload("res://Components/HeartRed.png")
const HEART_BLACK: Texture2D = preload("res://Components/HeartBlack.png")
const PAUSE_ICON: Texture2D = preload("res://assets/icons/pause_white.svg")
const PLAY_ICON: Texture2D = preload("res://assets/icons/play_white.svg")
const REFERENCE_PNG_DIR := "res://ui/minigames/catch_hud/generated/"
const REFERENCE_BOY_DIR := "res://ui/minigames/catch_hud/generated/character/"
const LIVES_STATE_DIR := "res://ui/minigames/catch_hud/generated/replacement/"
const HUD_DESIGN_SIZE := Vector2(1280.0, 720.0)
const HUD_INK := Color("#57321F")

const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const FALLBACK_WORDS := {
	"Noun": ["apple", "teacher", "river", "school", "pencil", "garden", "friend", "planet", "basket", "window"],
	"Pronoun": ["he", "she", "they", "we", "it", "you", "him", "her", "them", "ours"],
	"Verb": ["learn", "write", "sing", "carry", "listen", "climb", "whisper", "study", "paint", "read"],
	"Adjective": ["kind", "small", "happy", "gentle", "tiny", "brave", "quiet", "tall", "sleepy", "noisy"],
	"Adverb": ["quickly", "softly", "often", "carefully", "always", "quietly", "slowly", "silently", "kindly", "bravely"]
}
const TILE_COLORS := [
	Color("#69BE9A"),
	Color("#7BC9EF"),
	Color("#C171CF"),
	Color("#FFC23D"),
	Color("#F4985F")
]

const TILE_SIZE := Vector2(106.0, 109.0)
const APPLE_SIZE := Vector2(106.0, 109.0)
const APPLE_SPACING_MARGIN := 12.0
const BODY_FOLLOW_SPEED := 10.0
# The CharacterRig and each character's Body/Basket offsets, crops and scales
# are authored in catch_word.tscn. Gameplay only moves the shared rig on X.
const CHARACTER_NODES := {
	"Boy": ".",
	"Girl": "Girl",
	"Grandma": "Grandma",
	"Grandpa": "Grandpa"
}
const COLLECTED_WORD_LIMIT := 3
const SECONDS_ROUND_DURATION := 60.0

const MAP_ASSETS := {
	"City": "res://WordCatcherMaps/CityMap.png",
	"Forest": "res://WordCatcherMaps/ForestMap.png",
	"Mountain": "res://WordCatcherMaps/MountainMap.png"
}

const CHARACTER_ASSETS := {
	"Boy": {
		"body": "res://WordCatcherCharacters/BOY BODY.png",
		"basket": "res://WordCatcherCharacters/BOY BASKET.png",
		"body_bbox": Rect2(97, 125, 748, 1547),
		"basket_bbox": Rect2(11, 890, 920, 459)
	},
	"Girl": {
		"body": "res://WordCatcherCharacters/GIRL BODY.png",
		"basket": "res://WordCatcherCharacters/GIRL BASKET.png",
		"body_bbox": Rect2(106, 130, 722, 1542),
		"basket_bbox": Rect2(8, 878, 920, 459)
	},
	"Grandma": {
		"body": "res://WordCatcherCharacters/GRANDMA BODY.png",
		"basket": "res://WordCatcherCharacters/GRANDMA BASKET.png",
		"body_bbox": Rect2(94, 125, 750, 1547),
		"basket_bbox": Rect2(8, 870, 923, 448)
	},
	"Grandpa": {
		"body": "res://WordCatcherCharacters/GRANDPA BODY.png",
		"basket": "res://WordCatcherCharacters/GRANDPA BASKET.png",
		"body_bbox": Rect2(97, 130, 743, 1542),
		"basket_bbox": Rect2(10, 873, 918, 456)
	}
}

var context: Dictionary = {}
var rng := RandomNumberGenerator.new()
var grammar_bank = null

var topic := "Noun"
var difficulty := "Easy"
var game_mode := "Seconds"
var is_seconds_mode := true
var is_lives_mode := false

var score := 0
var lives := 3
var streak := 0
var best_streak := 0
var correct_count := 0
var attempts := 0
var time_remaining := 60.0
var round_finished := false
var round_completed := false
var round_running := true
var finish_reason := ""

# Wave mode: exactly one correct answer and two distractors, on three lanes.
const APPLES_PER_WAVE := 3
const WAVE_CLEAR_SECONDS := 0.75
const WAVE_SPEED_GAIN := 0.045
const WAVE_MAX_SPEED_MULTIPLIER := 1.55
const CATCH_VOICE_DIR := "res://assets/audio/catch_voice/"
const POSITIVE_VOICE_CUES := ["GoodJob.mp3", "niceee.mp3", "Awesome.mp3", "Perfect.mp3", "You Nailed it.mp3"]
const NEGATIVE_VOICE_CUES := ["Awww.mp3", "Wrong Answer.mp3", "You Missed.mp3"]

var spawn_interval := 0.0 # Waves now start moving immediately from above the screen.
var base_fall_speed := 105.0
@export_range(1, 10) var default_lives: int = 3
@export var default_duration: float = 60.0
# The collision follows the selected Basket sprite's edited size and offset.
@export_range(0.1, 1.0, 0.01) var basket_hitbox_width_ratio := 0.82
@export_range(0.1, 1.0, 0.01) var basket_hitbox_height_ratio := 0.52
var spawn_clock := 0.0
var wave_phase := "idle" # idle, reading, falling, clearing
var wave_index := 0
var wave_speed := 105.0
var catch_voice_player: AudioStreamPlayer
var catch_voice_streams: Dictionary = {}

var basket_x := 640.0
var basket_velocity := 0.0
var body_input_active := false
var body_target_normalized := 0.0

var falling_tiles: Array[Dictionary] = []
var collected_words: Array[String] = []
# Every word displayed on an apple is retired for the entire round, whether
# it was correct, wrong, caught, or missed. Keys are case-insensitive.
var used_session_words: Dictionary = {}
var selected_character := ""
var selected_map := ""
var character_editor_origin := Vector2.ZERO
var character_editor_scale := Vector2.ONE

var tile_style_cache: Dictionary = {}

@onready var background: TextureRect = $Background
@onready var falling_word_layer: Node2D = $FallingWordLayer
@onready var character_rig: Node2D = $CharacterRig
@onready var body_sprite: Sprite2D = $CharacterRig/Body
@onready var collected_word_layer: Node2D = $CharacterRig/CollectedWords
@onready var basket_sprite: Sprite2D = $CharacterRig/Basket
@onready var hud: Control = $HUDLayer/HUD
@onready var title_plaque: TextureRect = $HUDLayer/HUD/TitlePlaque
@onready var timer_plaque: TextureRect = $HUDLayer/HUD/TimerPlaque
@onready var lives_plaque: TextureRect = $HUDLayer/HUD/LivesPlaque
@onready var pause_plaque: TextureRect = $HUDLayer/HUD/PausePlaque
@onready var score_plaque: TextureRect = $HUDLayer/HUD/ScorePlaque
@onready var title_label: Label = $HUDLayer/HUD/TitleLabel
@onready var title_the_label: Label = $HUDLayer/HUD/TitleTheLabel
@onready var title_word_label: Label = $HUDLayer/HUD/TitleWordLabel
@onready var prompt_label: Label = $HUDLayer/HUD/PromptLabel
@onready var score_label: Label = $HUDLayer/HUD/ScoreLabel
@onready var lives_label: Label = $HUDLayer/HUD/LivesLabel
@onready var time_label: Label = $HUDLayer/HUD/TimeLabel
@onready var streak_label: Label = $HUDLayer/HUD/StreakLabel
@onready var footer_label: Label = $HUDLayer/HUD/FooterLabel
@onready var finish_button: Button = $HUDLayer/HUD/FinishButton
@onready var pause_button: Button = $HUDLayer/HUD/PauseButton

var hearts_box: HBoxContainer
var score_bottom_container: VBoxContainer
var score_bottom_number: Label
var score_draw_layer: Control
var using_reference_pngs := false
var gameplay_apple_texture: Texture2D = APPLE_TEXTURE
var lives_texture_cache: Dictionary = {}
var last_score_layout_value := -1
var last_prompt_layout_text := ""


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The scene editor owns the resting X/Y; do not recompute the rig's baseline
	# from screen height and hide its lower body below the viewport.
	character_editor_origin = character_rig.position
	character_editor_scale = character_rig.scale
	rng.randomize()
	_initialize_voice_feedback()
	_load_grammar_bank_if_available()
	_build_controls()
	_apply_generated_reference_assets()
	_place_score_behind_character()
	_select_round_art({})
	_apply_difficulty()
	_reset_round_geometry()
	_refresh_hud()
	_refresh_collected_words()
	set_process(true)
	resized.connect(_on_resized)
	call_deferred("_deferred_begin")


func set_context(value: Dictionary) -> void:
	_stop_voice_feedback()
	context = value.duplicate(true)
	context["activity"] = "Catch the Word"
	topic = _canonical_topic(String(context.get("topic", context.get("game_style", "Noun"))))
	difficulty = _canonical_difficulty(String(context.get("difficulty", "Easy")))
	_apply_difficulty()
	_select_round_art(value)

	score = maxi(int(context.get("score", 0)), 0)
	streak = maxi(int(context.get("streak", 0)), 0)
	best_streak = maxi(int(context.get("best_streak", streak)), streak)
	correct_count = maxi(int(context.get("correct", 0)), 0)
	attempts = maxi(int(context.get("attempts", 0)), 0)
	lives = clampi(int(context.get("lives", default_lives)), 0, default_lives)
	# A new Seconds round always starts at 60. Only an actual paused round
	# can restore elapsed time; an inherited Lives placeholder may be 999.
	var is_resume := _is_resume_snapshot(value)
	time_remaining = clampf(float(context.get("time_remaining", default_duration)), 0.0, default_duration) if is_resume else default_duration
	round_finished = false
	round_completed = false
	round_running = true
	finish_reason = ""
	spawn_clock = 0.0
	wave_phase = "idle"
	wave_index = maxi(int(context.get("catch_wave_index", 0)), 0) if is_resume else 0
	used_session_words.clear()
	if is_resume:
		var saved_words = context.get("catch_used_words", [])
		if saved_words is Array:
			for entry in saved_words:
				var key := _word_key(String(entry))
				if not key.is_empty():
					used_session_words[key] = true
		elif saved_words is Dictionary:
			for entry in saved_words.keys():
				var key := _word_key(String(entry))
				if not key.is_empty():
					used_session_words[key] = true
		# Older pause snapshots did not record all displayed apples. At least
		# exclude their collected words when restoring an older save.
		for entry in context.get("catch_collected_words", []):
			var key := _word_key(String(entry))
			if not key.is_empty():
				used_session_words[key] = true
	_clear_falling_tiles()
	_clear_transient_effects()
	collected_words.clear()
	if is_resume:
		for word in context.get("catch_collected_words", []):
			if collected_words.size() >= COLLECTED_WORD_LIMIT:
				break
			collected_words.append(String(word))
	_reset_round_geometry()
	_refresh_collected_words()
	_refresh_hud()
	_spawn_wave()
	queue_redraw()


func get_context() -> Dictionary:
	return _result_payload()


func set_body_x(normalized_x: float) -> void:
	body_target_normalized = clampf(normalized_x, -1.0, 1.0)
	body_input_active = true


func clear_body_input() -> void:
	body_input_active = false


func _finish_round() -> void:
	if round_finished:
		return
	if finish_reason.is_empty():
		finish_reason = "manual"
	round_finished = true
	round_completed = true
	round_running = false
	# Results owns the end-of-round cue. Stop any catch phrase before routing.
	_stop_voice_feedback()
	_clear_falling_tiles()
	_clear_transient_effects()
	set_process(false)
	requested.emit("results", _result_payload())


func _process(delta: float) -> void:
	if round_finished or not round_running:
		return

	_update_basket(delta)
	_sync_character_position()
	_update_timer(delta)
	if round_finished:
		return
	_update_tiles(delta)
	if round_finished:
		return
	_update_spawning(delta)
	_refresh_hud()


func _deferred_begin() -> void:
	_reset_round_geometry()
	_refresh_collected_words()
	_refresh_hud()
	_ensure_matching_tile()
	queue_redraw()


func _load_grammar_bank_if_available() -> void:
	if ResourceLoader.exists(GRAMMAR_BANK_PATH):
		grammar_bank = load(GRAMMAR_BANK_PATH)


func _build_controls() -> void:
	var empty_style := StyleBoxEmpty.new()
	pause_button.text = ""
	pause_button.icon = PAUSE_ICON
	pause_button.expand_icon = true
	pause_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_button.custom_minimum_size = Vector2.ZERO
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pause_button.add_theme_constant_override("icon_max_width", 35)
	pause_button.add_theme_stylebox_override("normal", empty_style)
	pause_button.add_theme_stylebox_override("hover", empty_style)
	pause_button.add_theme_stylebox_override("pressed", empty_style)
	pause_button.add_theme_stylebox_override("focus", empty_style)
	if not pause_button.pressed.is_connected(_pause):
		pause_button.pressed.connect(_pause)

	UI.style_button(finish_button, UI.RED, 14)
	if not finish_button.pressed.is_connected(_manual_finish):
		finish_button.pressed.connect(_manual_finish)
	finish_button.visible = false

	if not hud.has_node("HeartsBox"):
		hearts_box = HBoxContainer.new()
		hearts_box.name = "HeartsBox"
		hearts_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Three generated heart recesses are 39px apart on the PNG badge.
		# Leave real space between heart silhouettes and their outlines.
		hearts_box.add_theme_constant_override("separation", 6)
		hud.add_child(hearts_box)
		for i in range(3):
			var heart_rect := TextureRect.new()
			heart_rect.name = "Heart%d" % (i + 1)
			heart_rect.texture = HEART_RED
			heart_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			heart_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			heart_rect.custom_minimum_size = Vector2(34, 33)
			heart_rect.size = Vector2(34, 33)
			heart_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hearts_box.add_child(heart_rect)
	else:
		hearts_box = hud.get_node("HeartsBox") as HBoxContainer

	if not hud.has_node("ScoreBottomContainer"):
		score_bottom_container = VBoxContainer.new()
		score_bottom_container.name = "ScoreBottomContainer"
		score_bottom_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		score_bottom_container.add_theme_constant_override("separation", -4)
		hud.add_child(score_bottom_container)

		var score_title := Label.new()
		score_title.text = "SCORE"
		# The generated score board paints the heading itself. Keep this
		# legacy label disabled even before the asset initialization runs.
		score_title.visible = false
		score_title.add_theme_font_override("font", TITLE_FONT)
		score_title.add_theme_font_size_override("font_size", 25)
		score_title.add_theme_color_override("font_color", Color("#FFEB9D"))
		score_title.add_theme_color_override("font_outline_color", Color("#5C2A12"))
		score_title.add_theme_constant_override("outline_size", 4)
		score_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		score_title.custom_minimum_size = Vector2(146, 34)
		score_bottom_container.add_child(score_title)

		score_bottom_number = Label.new()
		score_bottom_number.name = "ScoreNumber"
		score_bottom_number.text = "0"
		score_bottom_number.add_theme_font_override("font", TITLE_FONT)
		score_bottom_number.add_theme_font_size_override("font_size", 36)
		score_bottom_number.add_theme_color_override("font_color", Color.WHITE)
		score_bottom_number.add_theme_color_override("font_outline_color", Color("#351C11"))
		score_bottom_number.add_theme_constant_override("outline_size", 4)
		score_bottom_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score_bottom_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		score_bottom_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		score_bottom_number.custom_minimum_size = Vector2(146, 48)
		score_bottom_container.add_child(score_bottom_number)
	else:
		score_bottom_container = hud.get_node("ScoreBottomContainer") as VBoxContainer
		score_bottom_number = score_bottom_container.get_node("ScoreNumber") as Label

	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for plaque in [title_plaque, timer_plaque, lives_plaque, pause_plaque, score_plaque]:
		plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The PNG title owns all three words. The live labels are kept only so
	# old scene references remain valid; never paint a second title.
	for baked_title in [title_label, title_the_label, title_word_label]:
		baked_title.visible = false
	for label in [title_label, title_the_label, title_word_label, prompt_label, score_label, lives_label, time_label, streak_label, footer_label]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.clip_text = true
	prompt_label.add_theme_color_override("font_color", HUD_INK)
	time_label.add_theme_color_override("font_color", Color.WHITE)
	time_label.add_theme_color_override("font_outline_color", Color("#073A6B"))
	time_label.add_theme_constant_override("outline_size", 3)
	_layout_controls()


func _apply_generated_reference_assets() -> void:
	# The scene serializes the complete generated PNG pack. Use its baked
	# text as the sole source of headings in both editor and runtime.
	var artwork := {
		"title_board.png": title_plaque,
		"lives_badge.png": lives_plaque,
		"timer_badge.png": timer_plaque,
		"pause_badge.png": pause_plaque,
		"score_board.png": score_plaque,
	}
	for filename in artwork:
		var plaque := artwork[filename] as TextureRect
		var asset_path: String = REFERENCE_PNG_DIR + filename
		if ResourceLoader.exists(asset_path):
			plaque.texture = load(asset_path) as Texture2D
		# The generated image has its own intended proportions and transparent
		# margins. Make the object fill its actual reference HUD slot.
		plaque.stretch_mode = TextureRect.STRETCH_SCALE
	# The supplied life meter images already paint the hearts for every state.
	# Cache the three separate textures once, rather than allocating new heart
	# controls or loading images every frame.
	lives_texture_cache.clear()
	for life_count in range(1, 4):
		var life_path := LIVES_STATE_DIR + "lives_state_%d.png" % life_count
		if ResourceLoader.exists(life_path):
			lives_texture_cache[life_count] = load(life_path) as Texture2D
	using_reference_pngs = true
	# Both PNG headings are already painted on the generated art.
	for label in [title_label, title_the_label, title_word_label]:
		label.visible = false
	if is_instance_valid(score_bottom_container):
		for label in score_bottom_container.get_children():
			if label is Label and label != score_bottom_number:
				label.visible = false
	# Pause is an actual PNG button, with a transparent clickable hit target.
	pause_button.icon = null
	var apple_path := REFERENCE_BOY_DIR + "word_apple.png"
	if ResourceLoader.exists(apple_path):
		gameplay_apple_texture = load(apple_path) as Texture2D
	_layout_controls()


func _place_score_behind_character() -> void:
	# The HUD lives in CanvasLayer 20; score nodes inside it always cover the
	# player, regardless of z_index. Keep the rest of the HUD on that layer.
	# Same-canvas absolute draw order (all author-owned Sprite2D z values are
	# relative to CharacterRig): score -3 < body -2 < collected -1 < basket 0
	# < falling apples 1. Thus falling apples stay ABOVE even the front basket.
	score_draw_layer = Control.new()
	score_draw_layer.name = "ScoreDrawLayer"
	score_draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(score_draw_layer)
	score_plaque.reparent(score_draw_layer)
	score_bottom_container.reparent(score_draw_layer)
	score_draw_layer.z_index = -3
	character_rig.z_index = 0
	_layout_controls()


func _layout_controls() -> void:
	if not is_instance_valid(hud):
		return
	# CanvasLayer uses viewport coordinates, even when the game is embedded in
	# a smaller Control. Scale the 1280x720 HUD to the actual drawing area.
	var viewport_size := get_viewport_rect().size
	if viewport_size.x < 1.0 or viewport_size.y < 1.0:
		viewport_size = size
	var hud_scale := minf(viewport_size.x / HUD_DESIGN_SIZE.x, viewport_size.y / HUD_DESIGN_SIZE.y)
	hud_scale = maxf(hud_scale, 0.01)
	# Aspect-expand windows can be taller or wider than 16:9. Keep headings
	# against the top, mode/pause against the right and score at the bottom.
	var hud_canvas_size := viewport_size / hud_scale
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = hud_canvas_size
	hud.scale = Vector2.ONE * hud_scale
	hud.position = Vector2.ZERO
	if is_instance_valid(score_draw_layer):
		# Match the HUD's viewport scaling after moving only its score art.
		score_draw_layer.size = hud_canvas_size
		score_draw_layer.scale = hud.scale
		score_draw_layer.position = hud.position
	var extra_x := maxf(0.0, hud_canvas_size.x - HUD_DESIGN_SIZE.x)
	var extra_y := maxf(0.0, hud_canvas_size.y - HUD_DESIGN_SIZE.y)

	_set_hud_rect(title_plaque, Vector2(15, 12), Vector2(450, 133))
	_set_hud_rect(timer_plaque, Vector2(1032, 10), Vector2(162, 65))
	_set_hud_rect(lives_plaque, Vector2(990, 10), Vector2(204, 65))
	_set_hud_rect(pause_plaque, Vector2(1199, 12), Vector2(71, 71))
	_set_hud_rect(score_plaque, Vector2(1036, 554), Vector2(236, 150))

	_set_hud_rect(title_label, Vector2(59, 27), Vector2(165, 49))
	_set_hud_rect(title_the_label, Vector2(214, 27), Vector2(88, 49))
	_set_hud_rect(title_word_label, Vector2(290, 27), Vector2(164, 49))
	_set_hud_rect(prompt_label, Vector2(58, 77), Vector2(370, 36))
	_set_hud_rect(time_label, Vector2(1085, 16), Vector2(98, 52))
	_set_hud_rect(pause_button, Vector2(1217, 29), Vector2(36, 36))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if is_instance_valid(hearts_box):
		_set_hud_rect(hearts_box, Vector2(1024, 21), Vector2(136, 40))
	if is_instance_valid(score_bottom_container):
		_set_hud_rect(score_bottom_container, Vector2(1093, 587), Vector2(156, 82))
	if using_reference_pngs:
		_set_hud_rect(title_plaque, Vector2(13, 10), Vector2(506, 157))
		_set_hud_rect(timer_plaque, Vector2(990 + extra_x, 8), Vector2(195, 76))
		_set_hud_rect(lives_plaque, Vector2(990 + extra_x, 8), Vector2(195, 76))
		_set_hud_rect(pause_plaque, Vector2(1195 + extra_x, 8), Vector2(81, 81))
		_set_hud_rect(score_plaque, Vector2(1002 + extra_x, 537 + extra_y), Vector2(274, 176))
		# Title board's cream question strip is y≈93..131, x≈114..419.
		# Center the baseline within the strip, not against its bottom trim.
		_set_hud_rect(prompt_label, Vector2(115, 93), Vector2(306, 33))
		_set_hud_rect(time_label, Vector2(1062 + extra_x, 20), Vector2(110, 50))
		_set_hud_rect(pause_button, Vector2(1212 + extra_x, 25), Vector2(48, 48))
		if is_instance_valid(hearts_box):
			_set_hud_rect(hearts_box, Vector2(1034 + extra_x, 27), Vector2(114, 34))
		if is_instance_valid(score_bottom_container):
			# The dynamic number sits slightly left and above its previous baseline,
			# safely within the dark carved inset of the supplied score board.
			_set_hud_rect(score_bottom_container, Vector2(1053 + extra_x, 613 + extra_y), Vector2(174, 60))

	score_label.visible = false
	lives_label.visible = false
	streak_label.visible = false
	footer_label.visible = false


func _set_hud_rect(control: Control, top_left: Vector2, dimensions: Vector2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = top_left
	control.size = dimensions


func _apply_difficulty() -> void:
	var raw_mode := String(context.get("game_mode", context.get("mode", "Lives"))).to_lower()
	if raw_mode in ["seconds", "60s", "sec"]:
		game_mode = "Seconds"
		is_seconds_mode = true
		is_lives_mode = false
		default_duration = SECONDS_ROUND_DURATION
		default_lives = int(context.get("lives", default_lives))
	else:
		game_mode = "Lives"
		is_seconds_mode = false
		is_lives_mode = true
		default_duration = float(context.get("time_remaining", 999.0))
		default_lives = int(context.get("lives", default_lives))

	match difficulty:
		"Hard":
			spawn_interval = 0.0
			base_fall_speed = 245.0
		"Normal":
			spawn_interval = 0.0
			base_fall_speed = 185.0
		_:
			spawn_interval = 0.0
			base_fall_speed = 105.0
	wave_speed = base_fall_speed

	lives = default_lives
	time_remaining = default_duration


func _select_round_art(source: Dictionary) -> void:
	var requested_character := String(source.get("catch_character", ""))
	var requested_map := String(source.get("catch_map", ""))

	var character_keys := CHARACTER_ASSETS.keys()
	if CHARACTER_ASSETS.has(requested_character):
		selected_character = requested_character
	else:
		selected_character = String(character_keys[rng.randi_range(0, character_keys.size() - 1)])

	var map_keys := MAP_ASSETS.keys()
	if MAP_ASSETS.has(requested_map):
		selected_map = requested_map
	else:
		selected_map = String(map_keys[rng.randi_range(0, map_keys.size() - 1)])

	_apply_art_selection()


func _apply_art_selection() -> void:
	var map_path: String = MAP_ASSETS[selected_map]

	if ResourceLoader.exists(map_path):
		background.texture = load(map_path) as Texture2D
	# All four artwork groups are editable independently in catch_word.tscn.
	# Selecting a character only changes visibility, never its sprite transforms
	# or textures. This also preserves artist-adjusted basket/body alignment.
	for name in CHARACTER_NODES:
		var rig_path: String = String(CHARACTER_NODES[name])
		var group: Node2D = character_rig if rig_path == "." else character_rig.get_node_or_null(rig_path) as Node2D
		if group == null:
			push_error("Missing editor-authored Catch character: " + name)
			continue
		if name == "Boy":
			(character_rig.get_node("Body") as Sprite2D).visible = selected_character == name
			(character_rig.get_node("Basket") as Sprite2D).visible = selected_character == name
		else:
			group.visible = selected_character == name
		if selected_character == name:
			body_sprite = group.get_node("Body") as Sprite2D
			basket_sprite = group.get_node("Basket") as Sprite2D


func _character_baseline_y() -> float:
	return character_editor_origin.y * (_view_size().y / HUD_DESIGN_SIZE.y)


func _basket_local_center() -> Vector2:
	# Support dragging either the basket itself OR its character variant group.
	return character_rig.to_local(basket_sprite.global_position)


func _basket_visual_size() -> Vector2:
	var artwork_size: Vector2 = basket_sprite.region_rect.size if basket_sprite.region_enabled else basket_sprite.texture.get_size()
	var rig_scale: Vector2 = character_rig.global_scale
	var sprite_scale: Vector2 = basket_sprite.global_scale
	return artwork_size * Vector2(absf(sprite_scale.x / maxf(absf(rig_scale.x), 0.001)), absf(sprite_scale.y / maxf(absf(rig_scale.y), 0.001)))


func _basket_world_size() -> Vector2:
	return _basket_visual_size() * Vector2(absf(character_rig.scale.x), absf(character_rig.scale.y))


func _basket_world_offset() -> Vector2:
	return _basket_local_center() * character_rig.scale


func _sync_character_scale() -> void:
	# Scale the entire *editor-authored* rig with the design canvas, just like
	# the other game HUD graphics. Child Sprite2Ds remain freely editable and
	# are never resized/repositioned from code.
	var view := _view_size()
	var factor := minf(view.x / HUD_DESIGN_SIZE.x, view.y / HUD_DESIGN_SIZE.y)
	character_rig.scale = character_editor_scale * factor


func _selected_character_data() -> Dictionary:
	# All four rigs use their original WordCatcherCharacters texture pair
	# and original cropped regions. Never select generated character assets.
	return CHARACTER_ASSETS.get(selected_character, CHARACTER_ASSETS["Boy"])


func _reset_round_geometry() -> void:
	var field := _game_rect()
	# Drag CharacterRig in the .tscn to choose the starting position. Gameplay
	# moves that rig horizontally while leaving all sprite offsets alone.
	_sync_character_scale()
	basket_x = character_editor_origin.x * (_view_size().x / HUD_DESIGN_SIZE.x)
	var half_basket_width := _basket_world_size().x * 0.5
	var sprite_center_offset := _basket_world_offset().x
	basket_x = clampf(basket_x, field.position.x + half_basket_width + 8.0 - sprite_center_offset, field.end.x - half_basket_width - 8.0 - sprite_center_offset)
	basket_velocity = 0.0
	_sync_character_position()


func _sync_character_position() -> void:
	character_rig.position = Vector2(basket_x, _character_baseline_y())


func _update_basket(delta: float) -> void:
	# Camera/pose input is the only movement source. Never read A/D or the
	# ui_left/ui_right actions: keyboard avatar movement is deliberately gone.
	var field := _game_rect()
	var visible_half_width := _basket_world_size().x * 0.5
	var center_offset_x := _basket_world_offset().x
	var min_x := field.position.x + visible_half_width + 8.0 - center_offset_x
	var max_x := field.end.x - visible_half_width - 8.0 - center_offset_x
	basket_velocity = 0.0
	if body_input_active:
		var body_target_x := lerpf(min_x, max_x, (body_target_normalized + 1.0) * 0.5)
		basket_x = lerpf(basket_x, body_target_x, 1.0 - exp(-BODY_FOLLOW_SPEED * delta))
	basket_x = clampf(basket_x, min_x, max_x)


func _update_timer(delta: float) -> void:
	if not is_seconds_mode:
		return
	time_remaining = maxf(time_remaining - delta, 0.0)
	if time_remaining <= 0.0:
		finish_reason = "time_up"
		_finish_round()


func _update_tiles(delta: float) -> void:
	if wave_phase != "falling" and wave_phase != "clearing":
		return
	var basket_rect := _basket_rect()
	var bottom := _game_rect().end.y + APPLE_SIZE.y
	# All three apples have identical fall speed and start Y; no pair can
	# converge. On a collision, resolve ONE answer, then disable the other two.
	for index in range(falling_tiles.size() - 1, -1, -1):
		var tile: Dictionary = falling_tiles[index]
		var pos: Vector2 = tile["pos"]
		pos.y += float(tile["speed"]) * delta
		tile["pos"] = pos
		falling_tiles[index] = tile
		_sync_tile_node(tile)
		if wave_phase == "falling" and _tile_rect(tile).intersects(basket_rect):
			_handle_catch(tile)
			_free_tile_node(tile)
			falling_tiles.remove_at(index)
			_resolve_wave(true)
			return
		if wave_phase == "clearing" and pos.y > bottom:
			_free_tile_node(tile)
			falling_tiles.remove_at(index)
	if wave_phase == "falling" and not falling_tiles.is_empty():
		# No selection: the correct answer has fallen out of reach.
		if Vector2(falling_tiles[0]["pos"]).y > bottom:
			_resolve_wave(false)


func _update_spawning(delta: float) -> void:
	match wave_phase:
		"reading":
			spawn_clock -= delta
			if spawn_clock <= 0.0:
				wave_phase = "falling"
				if not falling_tiles.is_empty():
					spawn_clock = (_game_rect().end.y + APPLE_SIZE.y - Vector2(falling_tiles[0]["pos"]).y) / maxf(wave_speed, 1.0)
		"falling":
			# Also acts as an observable gameplay clock for pause/resume.
			spawn_clock = maxf(spawn_clock - delta, 0.0)
		"clearing":
			spawn_clock -= delta
			if spawn_clock <= 0.0:
				_clear_falling_tiles()
				wave_phase = "idle"
				_spawn_wave()
		_:
			_spawn_wave()


func _wave_lane_positions() -> Array[float]:
	var field := _game_rect()
	# Shift the formation right from its old left-heavy position, while
	# retaining enough room before the bottom-right SCORE plaque.
	var left := field.position.x + APPLE_SIZE.x * 0.5 + 150.0
	var right := minf(field.end.x - APPLE_SIZE.x * 0.5 - 12.0,
		score_plaque.position.x - APPLE_SIZE.x * 0.5 - APPLE_SPACING_MARGIN)
	# Equal visual spacing and a gap greater than the basket catch width:
	# one movement cannot accidentally collect adjacent options.
	return [left, (left + right) * 0.5, right]


func _spawn_wave() -> void:
	if round_finished or wave_phase != "idle" or not falling_tiles.is_empty():
		return
	# Reserve the complete three-word set before creating any apples. If one
	# category runs dry, complete the round with its score intact rather than
	# showing a repeat, a fake suffixed word, or an incomplete question.
	var correct_lane := rng.randi_range(0, APPLES_PER_WAVE - 1)
	var wave_words := _pick_unused_wave_words(correct_lane)
	if wave_words.size() != APPLES_PER_WAVE:
		finish_reason = "word_pool_exhausted"
		_finish_round()
		return
	var field := _game_rect()
	# Begin with the apple entirely above the viewport; let it descend into
	# view naturally rather than materializing mid-screen and hovering.
	var spawn_y := -APPLE_SIZE.y * 0.52
	wave_speed = base_fall_speed * minf(WAVE_MAX_SPEED_MULTIPLIER,
		1.0 + float(wave_index) * WAVE_SPEED_GAIN)
	var lanes := _wave_lane_positions()
	for lane in range(APPLES_PER_WAVE):
		var matching := lane == correct_lane
		var word: String = wave_words[lane]
		used_session_words[_word_key(word)] = true
		var color: Color = TILE_COLORS[rng.randi_range(0, TILE_COLORS.size() - 1)]
		var tile := {
			"word": word,
			"matching": matching,
			"lane": lane,
			"pos": Vector2(lanes[lane], spawn_y),
			"speed": wave_speed,
			"color": color,
			"passed_line": false,
			"node": _create_tile_node(word, color)
		}
		falling_tiles.append(tile)
		_sync_tile_node(tile)
	wave_index += 1
	wave_phase = "falling"
	spawn_clock = (field.end.y + APPLE_SIZE.y - spawn_y) / maxf(wave_speed, 1.0)


func _pick_unused_wave_words(correct_lane: int) -> Array[String]:
	var reserved: Dictionary = used_session_words.duplicate()
	var options: Array[String] = []
	for lane in range(APPLES_PER_WAVE):
		var candidate := _pick_word(lane == correct_lane, reserved)
		var key := _word_key(candidate)
		if key.is_empty() or reserved.has(key):
			return []
		reserved[key] = true
		options.append(candidate)
	return options


func _word_key(word: String) -> String:
	return word.strip_edges().to_lower()


func _resolve_wave(caught: bool) -> void:
	if wave_phase != "falling":
		return
	if not caught:
		for tile in falling_tiles:
			if bool(tile["matching"]):
				_handle_missed_correct(tile)
				break
	if is_lives_mode and lives <= 0:
		finish_reason = "lives_empty"
		_finish_round()
		return
	wave_phase = "clearing"
	spawn_clock = WAVE_CLEAR_SECONDS
	# The two unchosen apples visibly fall away, without being collectible.
	var out_y := _game_rect().end.y + APPLE_SIZE.y + 12.0
	for index in range(falling_tiles.size()):
		var tile: Dictionary = falling_tiles[index]
		tile["speed"] = maxf(500.0, (out_y - Vector2(tile["pos"]).y) / WAVE_CLEAR_SECONDS)
		tile["passed_line"] = true
		falling_tiles[index] = tile


func _spawn_position_is_clear(candidate: Vector2, speed: float) -> bool:
	var exit_y := _game_rect().end.y + 70.0
	# Keep enough space for the *basket* between two apples as well as for the
	# apple sprites themselves; otherwise two adjacent targets can score together.
	var horizontal_gap := APPLE_SIZE.x + _basket_rect().size.x + APPLE_SPACING_MARGIN
	var vertical_gap := APPLE_SIZE.y + _basket_rect().size.y + APPLE_SPACING_MARGIN
	for other in falling_tiles:
		var other_pos: Vector2 = other["pos"]
		if absf(candidate.x - other_pos.x) >= horizontal_gap:
			continue
		var other_speed := maxf(float(other["speed"]), 0.001)
		var remaining := minf(
			(exit_y - candidate.y) / maxf(speed, 0.001),
			(exit_y - other_pos.y) / other_speed
		)
		if remaining <= 0.0:
			continue
		var gap_now := candidate.y - other_pos.y
		var gap_at_exit := gap_now + (speed - other_speed) * remaining
		if gap_now >= vertical_gap and gap_at_exit >= vertical_gap:
			continue
		if gap_now <= -vertical_gap and gap_at_exit <= -vertical_gap:
			continue
		return false
	return true


func _ensure_matching_tile() -> void:
	# Compatibility entry point for the existing deferred scene initialization.
	if wave_phase == "idle" and falling_tiles.is_empty():
		_spawn_wave()


func _create_tile_node(word: String, _color: Color) -> Control:
	var container := Control.new()
	container.name = "FallingWord"
	container.custom_minimum_size = APPLE_SIZE
	container.size = APPLE_SIZE
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sprite := TextureRect.new()
	sprite.name = "AppleSprite"
	sprite.texture = gameplay_apple_texture
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.custom_minimum_size = APPLE_SIZE
	sprite.size = APPLE_SIZE
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(sprite)

	var label := Label.new()
	label.name = "WordLabel"
	label.text = word.to_upper()
	label.add_theme_font_override("font", TITLE_FONT)
	# Hard vocabulary includes longer words. Fit the actual glyph width inside
	# the original apple without resizing artwork or overlapping another lane.
	var word_font_size := 16
	while word_font_size > 7 and TITLE_FONT.get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, word_font_size).x > APPLE_SIZE.x - 14.0:
		word_font_size -= 1
	label.add_theme_font_size_override("font_size", word_font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.1, 0.95))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_top = 10.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(label)

	falling_word_layer.add_child(container)
	return container


func _sync_tile_node(tile: Dictionary) -> void:
	var node = tile.get("node")
	if node is Control and is_instance_valid(node):
		(node as Control).position = Vector2(tile["pos"]) - APPLE_SIZE * 0.5
		(node as Control).size = APPLE_SIZE


func _free_tile_node(tile: Dictionary) -> void:
	var node = tile.get("node")
	if node is Node and is_instance_valid(node):
		(node as Node).queue_free()


func _clear_falling_tiles() -> void:
	for tile in falling_tiles:
		_free_tile_node(tile)
	falling_tiles.clear()
	wave_phase = "idle"


func _clear_transient_effects() -> void:
	# Restart must not leave confetti or floating scores from the previous round.
	# Their tweens are bound to their owning nodes and stop when freed.
	for child in get_children():
		if child.is_in_group("catch_transient_effect") and not child.is_queued_for_deletion():
			child.queue_free()


func _pick_word(matching: bool, excluded: Dictionary) -> String:
	if grammar_bank != null and grammar_bank.has_method("pick_word"):
		# GrammarBank owns difficulty pools and excludes every earlier apple.
		# Empty means the appropriate pool is exhausted; never recycle it.
		return String(grammar_bank.call("pick_word", topic, matching, rng, difficulty, excluded)).strip_edges()
	# Offline fallback for a missing bank, with the same no-repeat guarantee.
	var candidates: Array[String] = []
	for source_topic in TOPICS:
		if (source_topic == topic) != matching:
			continue
		for candidate in FALLBACK_WORDS[source_topic]:
			var word := String(candidate)
			if not excluded.has(_word_key(word)):
				candidates.append(word)
	if candidates.is_empty():
		return ""
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _handle_catch(tile: Dictionary) -> void:
	attempts += 1
	var catch_pos := Vector2(basket_x, _character_baseline_y()) + _basket_world_offset() + Vector2(0.0, -40.0)
	if bool(tile["matching"]):
		correct_count += 1
		streak += 1
		best_streak = maxi(best_streak, streak)
		var gain := 100 + mini(streak - 1, 8) * 15
		score += gain
		if collected_words.size() < COLLECTED_WORD_LIMIT:
			collected_words.append(String(tile["word"]))
			_refresh_collected_words()
		_spawn_confetti(catch_pos.x, catch_pos.y, false)
		_show_floating_score("+%d" % gain, catch_pos, Color("#4EF082"))
		_speak_catch_feedback(true)
	else:
		streak = 0
		_spawn_confetti(catch_pos.x, catch_pos.y, true)
		_show_floating_score("-0", catch_pos, Color(0.12, 0.12, 0.12, 1.0))
		if is_lives_mode:
			lives = maxi(lives - 1, 0)
			_update_hearts_visual()
		_speak_catch_feedback(false)


func _initialize_voice_feedback() -> void:
	# Use the user's recorded feedback clips rather than artificial TTS.
	# One persistent player per live game keeps catch feedback bounded.
	catch_voice_player = AudioStreamPlayer.new()
	catch_voice_player.name = "CatchVoicePlayer"
	catch_voice_player.bus = "KilosSFX" if AudioServer.get_bus_index("KilosSFX") >= 0 else "Master"
	catch_voice_player.volume_db = 2.0
	add_child(catch_voice_player)
	for filename in POSITIVE_VOICE_CUES + NEGATIVE_VOICE_CUES + ["Better Luck.mp3"]:
		var path: String = CATCH_VOICE_DIR + filename
		if ResourceLoader.exists(path):
			catch_voice_streams[filename] = load(path) as AudioStream


func _speak_catch_feedback(correct: bool, missed: bool = false) -> void:
	if not is_instance_valid(catch_voice_player):
		return
	var cues := POSITIVE_VOICE_CUES if correct else NEGATIVE_VOICE_CUES
	var filename: String = "You Missed.mp3" if missed else cues[rng.randi_range(0, cues.size() - 1)]
	if not catch_voice_streams.has(filename):
		return
	catch_voice_player.stop()
	catch_voice_player.stream = null
	catch_voice_player.stream = catch_voice_streams[filename] as AudioStream
	catch_voice_player.play()


func _stop_voice_feedback() -> void:
	if is_instance_valid(catch_voice_player):
		catch_voice_player.stop()
		catch_voice_player.stream = null


func _exit_tree() -> void:
	_stop_voice_feedback()
	catch_voice_streams.clear()


func _spawn_confetti(pos_x: float, pos_y: float, is_black: bool) -> void:
	var confetti_root := Node2D.new()
	confetti_root.position = Vector2(pos_x, pos_y)
	confetti_root.z_index = 12
	confetti_root.add_to_group("catch_transient_effect")
	add_child(confetti_root)

	var rainbow_colors := [
		Color("#FF4F66"), Color("#FF884D"), Color("#FFC23D"),
		Color("#52C873"), Color("#47B5FF"), Color("#AF6BFF"), Color("#FF63B8")
	]
	var black_colors := [
		Color("#0A0A0A"), Color("#1C1C1C"), Color("#2B2B2B"), Color("#3A3A3A")
	]
	var palette := black_colors if is_black else rainbow_colors
	# One tween controls every piece, instead of dozens of independent tweens.
	var tween := create_tween().bind_node(confetti_root).set_parallel(true)

	for i in range(24):
		var piece := ColorRect.new()
		var p_width := rng.randf_range(6.0, 12.0)
		var p_height := rng.randf_range(6.0, 14.0)
		piece.size = Vector2(p_width, p_height)
		piece.color = palette[rng.randi_range(0, palette.size() - 1)]
		piece.pivot_offset = piece.size * 0.5
		confetti_root.add_child(piece)

		var angle := rng.randf_range(-PI * 0.9, -PI * 0.1)
		var speed := rng.randf_range(160.0, 460.0)
		var velocity := Vector2(cos(angle), sin(angle)) * speed
		var end_offset := velocity * rng.randf_range(0.35, 0.65) + Vector2(0.0, rng.randf_range(100.0, 220.0))
		var end_rot := rng.randf_range(-TAU * 2.0, TAU * 2.0)

		tween.tween_property(piece, "position", end_offset, rng.randf_range(0.55, 0.85)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(piece, "rotation", end_rot, rng.randf_range(0.55, 0.85))
		tween.tween_property(piece, "modulate:a", 0.0, 0.8).set_delay(rng.randf_range(0.3, 0.5))

	var cleanup_tween := create_tween().bind_node(confetti_root)
	cleanup_tween.tween_interval(0.9)
	cleanup_tween.tween_callback(confetti_root.queue_free)


func _show_floating_score(score_text: String, pos: Vector2, color: Color) -> void:
	var label := Label.new()
	label.text = score_text
	label.add_theme_font_override("font", TITLE_FONT)
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.position = pos - Vector2(30.0, 40.0)
	label.z_index = 25
	label.add_to_group("catch_transient_effect")
	add_child(label)

	var tween := create_tween().bind_node(label).set_parallel(true)
	tween.tween_property(label, "position:y", pos.y - 80.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


func _handle_missed_correct(tile: Dictionary) -> void:
	attempts += 1
	streak = 0
	_speak_catch_feedback(false, true)
	# One unanswered wave counts as a miss, never three separate penalties.
	if is_lives_mode:
		lives = maxi(lives - 1, 0)
		_update_hearts_visual()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode in [KEY_ESCAPE, KEY_P]:
			_pause()
			get_viewport().set_input_as_handled()


func _pause() -> void:
	if round_finished:
		return
	_stop_voice_feedback()
	round_running = false
	if pause_button and not using_reference_pngs:
		pause_button.icon = PLAY_ICON
	requested.emit("pause", _result_payload())


func _resume() -> void:
	if round_finished:
		return
	round_running = true
	if pause_button and not using_reference_pngs:
		pause_button.icon = PAUSE_ICON
	set_process(true)


func _manual_finish() -> void:
	if round_finished:
		return
	finish_reason = "manual_exit"
	round_finished = true
	round_completed = false
	round_running = false
	_stop_voice_feedback()
	_clear_falling_tiles()
	_clear_transient_effects()
	set_process(false)
	requested.emit("results", _result_payload())


func _result_payload() -> Dictionary:
	var payload := context.duplicate(true)
	payload["activity"] = "Catch the Word"
	payload["topic"] = topic
	payload["game_style"] = String(payload.get("game_style", topic))
	payload["game_mode"] = game_mode
	payload["difficulty"] = difficulty
	payload["score"] = score
	payload["lives"] = lives
	payload["streak"] = streak
	payload["best_streak"] = best_streak
	payload["correct"] = correct_count
	payload["attempts"] = attempts
	payload["total"] = attempts
	payload["accuracy"] = (float(correct_count) / float(attempts) * 100.0) if attempts > 0 else 0.0
	payload["time_remaining"] = time_remaining
	payload["demo_mode"] = true
	payload["gameplay_implemented"] = true
	payload["unsaved"] = true
	payload["camera_live"] = false
	payload["database_connected"] = false
	payload["round_completed"] = round_completed
	payload["completion_reason"] = finish_reason if round_finished else ""
	payload["round_reason"] = payload["completion_reason"]
	payload["catch_character"] = selected_character
	payload["catch_map"] = selected_map
	payload["catch_collected_words"] = collected_words.duplicate()
	payload["catch_wave_index"] = wave_index
	payload["catch_used_words"] = used_session_words.keys()
	return payload


func _refresh_collected_words() -> void:
	if collected_word_layer == null:
		return
	for child in collected_word_layer.get_children():
		# Refreshing more than once in the same frame must release the old
		# apple names immediately; deferred deletion creates duplicate fruit.
		child.free()
	if collected_words.is_empty():
		return

	var basket_size := _basket_visual_size()
	var center := _basket_local_center()
	var apple_size := Vector2(basket_size.x * 0.34, basket_size.y * 0.76)
	var spacing := apple_size.x * 0.84
	var count := mini(collected_words.size(), COLLECTED_WORD_LIMIT)
	var rim_y := center.y - basket_size.y * 0.5

	for index in range(count):
		var apple := TextureRect.new()
		apple.name = "CaughtApple%d" % (index + 1)
		apple.texture = APPLE_TEXTURE
		apple.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		apple.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Original WordCatcher basket composition: collected fruit rises just
		# above the front rim and the independent basket sprite masks its base.
		apple.position = Vector2(center.x + (float(index) - (float(count) - 1.0) * 0.5) * spacing - apple_size.x * 0.5, rim_y - apple_size.y * 0.82)
		apple.size = apple_size
		apple.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var word := collected_words[index].to_upper()
		var font_size := 13 if word.length() <= 5 else (11 if word.length() <= 8 else 9)
		var label := Label.new()
		label.name = "CollectedWord%d" % (index + 1)
		label.text = word
		label.add_theme_font_override("font", TITLE_FONT)
		label.add_theme_font_size_override("font_size", font_size)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.1, 0.95))
		label.add_theme_constant_override("outline_size", 3)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = true
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		apple.add_child(label)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_top = 6.0
		collected_word_layer.add_child(apple)


func _refresh_hud() -> void:
	if prompt_label == null:
		return
	var article := "AN" if topic in ["Adjective", "Adverb"] else "A"
	var prompt_text := "WHICH WORD IS %s %s?" % [article, topic.to_upper()]
	if prompt_text != last_prompt_layout_text:
		last_prompt_layout_text = prompt_text
		prompt_label.text = prompt_text
		var prompt_size := 19 if using_reference_pngs else 17
		while prompt_size > 13 and TITLE_FONT.get_string_size(prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, prompt_size).x > prompt_label.size.x - 10.0:
			prompt_size -= 1
		prompt_label.add_theme_font_size_override("font_size", prompt_size)
	if score_label:
		score_label.text = "SCORE %04d" % score
	if score_bottom_number and (score != last_score_layout_value or score_bottom_number.text != str(score)):
		last_score_layout_value = score
		score_bottom_number.text = "%d" % score
		var score_font_size := 40 if using_reference_pngs else 36
		while score_font_size > 16 and TITLE_FONT.get_string_size(score_bottom_number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, score_font_size).x > score_bottom_container.size.x - 18.0:
			score_font_size -= 2
		score_bottom_number.add_theme_font_size_override("font_size", score_font_size)

	if is_seconds_mode:
		timer_plaque.visible = true
		lives_plaque.visible = false
		time_label.visible = true
		time_label.text = "%ds" % int(ceil(time_remaining))
		lives_label.visible = false
		if hearts_box:
			hearts_box.visible = false
	else:
		timer_plaque.visible = false
		lives_plaque.visible = true
		time_label.visible = false
		lives_label.visible = false
		_update_hearts_visual()

	streak_label.text = "STREAK %d" % streak


func _update_hearts_visual() -> void:
	var state := clampi(lives, 1, 3)
	if lives_texture_cache.has(state):
		var state_texture := lives_texture_cache[state] as Texture2D
		if lives_plaque.texture != state_texture:
			lives_plaque.texture = state_texture
		if hearts_box:
			hearts_box.visible = false
		return
	# Compatibility if the user's individual heart-state artwork has not
	# been installed. Static state images completely replace this fallback.
	if hearts_box == null:
		return
	hearts_box.visible = true
	var heart_nodes := hearts_box.get_children()
	for i in range(heart_nodes.size()):
		var heart_rect := heart_nodes[i] as TextureRect
		if heart_rect != null:
			heart_rect.texture = HEART_RED if i < lives else HEART_BLACK


func _view_size() -> Vector2:
	return Vector2(maxf(size.x, 1280.0), maxf(size.y, 720.0))


func _game_rect() -> Rect2:
	var view := _view_size()
	return Rect2(28.0, 112.0, view.x - 56.0, view.y - 154.0)


func _basket_rect() -> Rect2:
	var visual_size := _basket_world_size()
	var hitbox_size := visual_size * Vector2(basket_hitbox_width_ratio, basket_hitbox_height_ratio)
	# basket_x is the authoritative movement position (including when camera
	# or a gameplay test sets it before the next visual frame is synced).
	var center := Vector2(basket_x, _character_baseline_y()) + _basket_world_offset()
	center.y -= visual_size.y * 0.05
	return Rect2(center - hitbox_size * 0.5, hitbox_size)


func _tile_rect(tile: Dictionary) -> Rect2:
	var pos: Vector2 = tile["pos"]
	return Rect2(pos - APPLE_SIZE * 0.5, APPLE_SIZE)


func _canonical_topic(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	for candidate in TOPICS:
		if candidate.to_lower() == normalized:
			return candidate
	return "Noun"


func _canonical_difficulty(value: String) -> String:
	match value.strip_edges().to_lower():
		"hard":
			return "Hard"
		"normal", "medium":
			return "Normal"
		_:
			return "Easy"


func _is_resume_snapshot(dict: Dictionary) -> bool:
	return bool(dict.get("round_running", false)) or dict.has("catch_collected_words")


func _on_resized() -> void:
	_layout_controls()
	_sync_character_scale()
	var field := _game_rect()
	var visible_half_width := _basket_world_size().x * 0.5
	var center_offset_x := _basket_world_offset().x
	basket_x = clampf(basket_x, field.position.x + visible_half_width + 8.0 - center_offset_x, field.end.x - visible_half_width - 8.0 - center_offset_x)
	_sync_character_position()
	_refresh_collected_words()
	_refresh_hud()
	queue_redraw()
