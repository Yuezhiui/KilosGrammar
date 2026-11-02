extends Control

signal requested(target: String, payload: Dictionary)
signal tutorial_finished()

const TITLE_FONT: Font = preload("res://assets/fonts/TitanOne-Regular.ttf")
const KidsVoice = preload("res://ui/shared/kids_voice_feedback.gd")
const GRAMMAR_BANK_PATH := "res://ui/minigames/shared/grammar_bank.gd"

const APPLE_TEXTURE: Texture2D = preload("res://Components/Gameplay/Catch the Word/Items/Apple.png")
const HALF_APPLE_TEXTURE: Texture2D = preload("res://Components/Gameplay/Catch the Word/Items/APPLE HALF SEAMLESS.png")
const CAUGHT_APPLE_FRONT_CLIP: Shader = preload("res://ui/minigames/catch_the_word/caught_apple_above_rim.gdshader")
# Only the previously transparent lower 21px of the ORIGINAL half-apple is
# extended in this derived art. The visibly painted bottom now meets the wicker
# while the basket's higher editor-authored z-order conceals the seam. No
# character rig, sprite position, collectible hitbox or apple width is changed.
const HALF_APPLE_PAINTED_HEIGHT_RATIO := 1.0
const HEART_RED: Texture2D = preload("res://Components/Gameplay/Shared/Hearts/HeartRed.png")
const HEART_BLACK: Texture2D = preload("res://Components/Gameplay/Shared/Hearts/HeartBlack.png")
const PAUSE_ICON: Texture2D = preload("res://Components/Gameplay/Controls/pause_white.svg")
const PLAY_ICON: Texture2D = preload("res://Components/Gameplay/Controls/play_white.svg")
const REFERENCE_PNG_DIR := "res://Components/Gameplay/Catch the Word/HUD/generated/"
const GENERATED_ITEM_DIR := "res://Components/Gameplay/Catch the Word/Characters/Generated/"
const LIVES_STATE_DIR := "res://Components/Gameplay/Catch the Word/HUD/generated/replacement/"
const HUD_DESIGN_SIZE := Vector2(1280.0, 720.0)
const HUD_INK := Color("#57321F")
const TUTORIAL_AUDIO_ROOT := "res://assets/audio/tutorial_spotlight/catch_word_"
const CATCH_TUTORIAL_STEPS := [
	{"id": "prompt", "title": "READ THE QUESTION",
		"caption": "Look at the question at the top of the screen. Read it carefully, then find the matching word on a falling apple."},
	{"id": "movement", "title": "MOVE YOUR BASKET",
		"caption": "Move your body left, center, or right to guide your basket. Catch the apple with the correct word. You've got this!"},
	{"id": "seconds", "title": "WATCH YOUR TIMER",
		"caption": "In Seconds mode, you have sixty seconds. Catch as many correct words as you can before the timer reaches zero!"},
	{"id": "lives", "title": "PROTECT YOUR HEARTS",
		"caption": "In Lives mode, you start with three hearts. Catching a wrong apple costs one heart, so look carefully before you move."},
	{"id": "score", "title": "EARN POINTS",
		"caption": "Every correct apple earns one hundred points! A wrong answer never takes away points you have already earned. Keep trying!"},
	{"id": "pause", "title": "TAKE A BREAK",
		"caption": "Need a little break? Press Pause to stop for a moment. Press Resume when you're ready to play again!"}
]

# Inspector controls use coordinates of the authored 1280x720 tutorial.
# Adjust the cutout without changing any character, basket or HUD geometry.
@export_group("Catch Tutorial Spotlight")
@export var tutorial_focus_padding := Vector2(10.0, 10.0)
@export var tutorial_focus_offset := Vector2.ZERO
@export var tutorial_step_focus_offsets: Dictionary = {
	"prompt": Vector2.ZERO,
	"movement": Vector2.ZERO,
	"seconds": Vector2.ZERO,
	"lives": Vector2.ZERO,
	"score": Vector2.ZERO,
	"pause": Vector2.ZERO,
}

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
const APPLE_SPACING_MARGIN := 12.0
const BODY_FOLLOW_SPEED := 10.0
const MULTIPLAYER_RUN_SPEED := 430.0 # pixels/second at 1280x720.
# The three falling apples are generated dynamically, so these Inspector
# controls define their rendered artwork/hitbox instead of moving any locked
# character, basket, collected apple or HUD scene nodes.
@export_group("Falling Apples - Classroom Readability")
@export var APPLE_SIZE := Vector2(160.0, 164.0)
@export_range(16, 34, 1) var falling_word_font_size := 26
@export_range(18, 24, 1) var falling_word_min_font_size := 20
# Each character is its own root-level editable group. Gameplay moves only the
# selected group; the other groups keep their scene-authored transforms.
const CHARACTER_NODES := ["Bear", "Cat", "Dog", "Lion", "Panda"]
const COLLECTED_WORD_LIMIT := 3
const SECONDS_ROUND_DURATION := 60.0
const LIVES_ROUND_HEARTS := 3
const CORRECT_ANSWER_POINTS := 100

const MAP_ASSETS := {
	"City": "res://Components/Gameplay/Catch the Word/Maps/CityMap.png",
	"Forest": "res://Components/Gameplay/Catch the Word/Maps/ForestMap.png",
	"Mountain": "res://Components/Gameplay/Catch the Word/Maps/MountainMap.png"
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
# Each correct answer provides subtle speed progression. Classrooms need time
# to read and move; even at the cap Hard is only modestly quicker than Easy.
const WAVE_SPEED_CAPS := {"Easy": 1.12, "Normal": 1.13, "Hard": 1.14}
const WAVE_SPEED_REMAINING_FACTOR := 0.8
# Difficulty affects how quickly the word apples fall, never how many points
# a correct catch earns. Keep Normal/Hard only slightly above Easy for grades 1-6.
const BASE_EASY_FALL_SPEED := 96.0
const DIFFICULTY_SPEED_MULTIPLIER := {
	"Easy": 1.0,
	"Normal": 102.0 / 96.0,
	"Hard": 109.0 / 96.0
}

var spawn_interval := 0.0 # Waves now start moving immediately from above the screen.
var base_fall_speed := BASE_EASY_FALL_SPEED
@export_range(1, 10) var default_lives: int = 3
@export var default_duration: float = 60.0
# The larger words have wider visible apple bodies. Narrow the catch center
# only (never touch the character/basket artwork) to keep adjacent answers
# mutually exclusive while preserving each basket's editable sprite geometry.
@export_range(0.1, 1.0, 0.01) var basket_hitbox_width_ratio := 0.55
@export_range(0.1, 1.0, 0.01) var basket_hitbox_height_ratio := 0.52
# Small, consistent half apples are composed from the original Basket sprite's
# Inspector-authored width. Teachers can adjust the per-apple width and spacing
# here and drag CollectedApplePlacement in the scene for positional fine-tuning.
@export_range(0.14, 0.28, 0.005) var caught_half_apple_basket_width_ratio := 0.21
@export_range(1.0, 1.3, 0.01) var caught_half_apple_spacing_ratio := 1.07
var spawn_clock := 0.0
var wave_phase := "idle" # idle, reading, falling, clearing
var wave_index := 0
var wave_speed := BASE_EASY_FALL_SPEED
var _kids_voice: RefCounted

var basket_x := 640.0
var basket_velocity := 0.0
var body_input_active := false
var body_target_normalized := 0.0
# Competitive pilot: one shared falling wave, two independent, camera-driven
# basket positions and score/lives. Keep all original solo fields unmodified.
var multiplayer_enabled := false
var player2_character := ""
var player2_group: Node2D
var player2_basket_sprite: Sprite2D
var player2_basket_x := 900.0
var player2_input_active := false
var player2_direction := 0.0
var player2_score := 0
var player2_lives := LIVES_ROUND_HEARTS
var player2_correct := 0
var player2_attempts := 0
var player2_streak := 0
var player2_best_streak := 0

var falling_tiles: Array[Dictionary] = []
var collected_words: Array[String] = []
# Retire all three shown words for the current vocabulary cycle, regardless
# of whether they were caught. Once a complete 1+2 wave is impossible, start
# another cycle rather than ending a timed/lives round early.
var used_session_words: Dictionary = {}
var vocabulary_cycle := 0
var last_wave_words: Array[String] = []
var selected_character := ""
var selected_map := ""
var character_editor_origin := Vector2.ZERO
var character_editor_scale := Vector2.ONE
var character_editor_transforms: Dictionary = {}
var collected_editor_offset := Vector2.ZERO
var collected_editor_scale := Vector2.ONE
var collected_apple_placement_offset := Vector2.ZERO
var basket_painted_rim_offsets: Dictionary = {}

var tile_style_cache: Dictionary = {}

@onready var background: TextureRect = $Background
@onready var falling_word_layer: Node2D = $FallingWordLayer
@onready var character_group: Node2D = $Bear
@onready var body_sprite: Sprite2D = $Bear/Body
@onready var collected_word_layer: Node2D = $CollectedWords
@onready var collected_apple_placement: Marker2D = $CollectedApplePlacement
@onready var basket_sprite: Sprite2D = $Bear/Basket
@onready var hud: Control = $HUDLayer/HUD
@onready var title_plaque: TextureRect = $HUDLayer/HUD/TitlePlaque
@onready var timer_plaque: TextureRect = $HUDLayer/HUD/TimerPlaque
@onready var lives_plaque: TextureRect = $HUDLayer/HUD/LivesPlaque
@onready var pause_plaque: TextureRect = $HUDLayer/HUD/PausePlaque
@onready var score_plaque: TextureRect = $HUDLayer/HUD/ScorePlaque
@onready var prompt_label: Label = $HUDLayer/HUD/PromptLabel
@onready var time_label: Label = $HUDLayer/HUD/TimeLabel
@onready var pause_button: Button = $HUDLayer/HUD/PauseButton
@onready var tutorial_layer: CanvasLayer = $GuidedTutorialLayer
@onready var tutorial_overlay: Control = $GuidedTutorialLayer/GuidedTutorial
@onready var tutorial_dim: ColorRect = $GuidedTutorialLayer/GuidedTutorial/Dim
@onready var tutorial_focus: Panel = $GuidedTutorialLayer/GuidedTutorial/FocusOutline
@onready var tutorial_card: Panel = $GuidedTutorialLayer/GuidedTutorial/TutorialCard
@onready var tutorial_counter: Label = $GuidedTutorialLayer/GuidedTutorial/TutorialCard/StepCounter
@onready var tutorial_title: Label = $GuidedTutorialLayer/GuidedTutorial/TutorialCard/StepTitle
@onready var tutorial_caption: Label = $GuidedTutorialLayer/GuidedTutorial/TutorialCard/StepCaption
@onready var tutorial_back: Button = $GuidedTutorialLayer/GuidedTutorial/TutorialCard/BackButton
@onready var tutorial_next: Button = $GuidedTutorialLayer/GuidedTutorial/TutorialCard/NextButton
@onready var tutorial_skip: Button = $GuidedTutorialLayer/GuidedTutorial/TutorialCard/SkipButton
@onready var tutorial_replay: Button = $GuidedTutorialLayer/GuidedTutorial/TutorialCard/ReplayButton
@onready var tutorial_pause_voice: Button = $GuidedTutorialLayer/GuidedTutorial/TutorialCard/PauseVoiceButton
@onready var tutorial_back_art: TextureRect = $GuidedTutorialLayer/GuidedTutorial/TutorialCard/BackButton/BackArt
@onready var tutorial_next_art: TextureRect = $GuidedTutorialLayer/GuidedTutorial/TutorialCard/NextButton/NextArt
@onready var tutorial_start_label: Label = $GuidedTutorialLayer/GuidedTutorial/TutorialCard/NextButton/StartLabel
@onready var tutorial_narration: AudioStreamPlayer = $GuidedTutorialLayer/GuidedTutorial/TutorialNarration

var hearts_box: HBoxContainer
@onready var score_bottom_number: Label = $HUDLayer/HUD/ScoreNumber
@onready var multiplayer_board: Control = $HUDLayer/HUD/MultiplayerBoard
@onready var player1_score_label: Label = $HUDLayer/HUD/MultiplayerBoard/Player1Score
@onready var player2_score_label: Label = $HUDLayer/HUD/MultiplayerBoard/Player2Score
var score_number_editor_position := Vector2.ZERO
var score_number_editor_font_size := 35
var score_plaque_editor_position := Vector2.ZERO
var score_draw_layer: Control
var using_reference_pngs := false
var gameplay_apple_texture: Texture2D = APPLE_TEXTURE
var lives_texture_cache: Dictionary = {}
var last_score_layout_value := -1
var last_prompt_layout_text := ""
var tutorial_step_index := -1
var tutorial_active := false
var tutorial_voice_paused := false
var tutorial_generation := 0
var tutorial_was_running := true


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Capture all five saved positions/scales before the round moves anything.
	# Inactive characters and the loose CollectedWords layer are editor-owned.
	for name in CHARACTER_NODES:
		var group := get_node(name) as Node2D
		character_editor_transforms[name] = {"position": group.position, "scale": group.scale}
	character_editor_origin = character_group.position
	character_editor_scale = character_group.scale
	collected_editor_offset = collected_word_layer.position - character_group.position
	collected_editor_scale = collected_word_layer.scale
	# Editor-authored adjustment for the collected RED APPLES only. The marker
	# is a sibling, not a child of CollectedWords, so the layer still contains
	# exactly the dynamically spawned word apples expected by gameplay/tests.
	# Read the offset once before runtime camera steering moves the character.
	collected_apple_placement_offset = collected_apple_placement.position - collected_word_layer.position
	rng.randomize()
	_initialize_voice_feedback()
	_load_grammar_bank_if_available()
	_build_controls()
	_wire_integrated_tutorial()
	_apply_generated_reference_assets()
	_place_score_behind_character()
	_select_round_art({})
	_apply_difficulty()
	_reset_round_geometry()
	_refresh_hud()
	_refresh_collected_words()
	set_process(true)
	resized.connect(_on_resized)
	get_viewport().size_changed.connect(_on_tutorial_viewport_resized)
	call_deferred("_deferred_begin")


func set_context(value: Dictionary) -> void:
	_cancel_integrated_tutorial()
	_stop_voice_feedback()
	context = value.duplicate(true)
	context["activity"] = "Catch the Word"
	multiplayer_enabled = bool(context.get("multiplayer", false)) or String(context.get("player_mode", "")).to_lower() in ["multiplayer", "two", "2", "two players"]
	# Multiplayer honors the teacher-selected round type. Seconds shares one
	# 60-second clock; Lives starts both children with three hearts and ends
	# ONLY when both have exhausted all hearts. Never silently replace Lives
	# with Seconds, since results must match main_menu completion proof.
	if multiplayer_enabled:
		context["player_mode"] = "Multiplayer"
	topic = _canonical_topic(String(context.get("topic", context.get("game_style", "Noun"))))
	difficulty = _canonical_difficulty(String(context.get("difficulty", "Easy")))
	_apply_difficulty()
	_select_round_art(value)

	var is_resume := _is_resume_snapshot(value)
	# Incoming score/lives fields from another minigame must never seed a fresh
	# round. Resume alone can restore earned points, lives, and speed progress.
	score = maxi(int(context.get("score", 0)), 0) if is_resume else 0
	streak = maxi(int(context.get("streak", 0)), 0) if is_resume else 0
	best_streak = maxi(int(context.get("best_streak", streak)), streak) if is_resume else 0
	correct_count = maxi(int(context.get("correct", 0)), 0) if is_resume else 0
	attempts = maxi(int(context.get("attempts", 0)), 0) if is_resume else 0
	# Competitive Catch uses independent hearts in BOTH Seconds and Lives
	# modes. Restore P1 hearts on pause/recovery just like P2; resetting only
	# P1 to three would grant extra catches after a pause in timed multiplayer.
	lives = clampi(int(context.get("lives", LIVES_ROUND_HEARTS)), 0, LIVES_ROUND_HEARTS) if is_resume and (is_lives_mode or multiplayer_enabled) else LIVES_ROUND_HEARTS
	player2_score = maxi(int(context.get("player2_score", 0)), 0) if is_resume and multiplayer_enabled else 0
	player2_lives = clampi(int(context.get("player2_lives", LIVES_ROUND_HEARTS)), 0, LIVES_ROUND_HEARTS) if is_resume and multiplayer_enabled else LIVES_ROUND_HEARTS
	player2_correct = maxi(int(context.get("player2_correct", 0)), 0) if is_resume and multiplayer_enabled else 0
	player2_attempts = maxi(int(context.get("player2_attempts", 0)), 0) if is_resume and multiplayer_enabled else 0
	player2_streak = maxi(int(context.get("player2_streak", 0)), 0) if is_resume and multiplayer_enabled else 0
	player2_best_streak = maxi(int(context.get("player2_best_streak", 0)), 0) if is_resume and multiplayer_enabled else 0
	# Lives has no countdown. Only a paused Seconds round restores its clock.
	time_remaining = clampf(float(context.get("time_remaining", SECONDS_ROUND_DURATION)), 0.0, SECONDS_ROUND_DURATION) if is_resume and is_seconds_mode else default_duration
	wave_speed = _correct_answer_wave_speed()
	round_finished = false
	round_completed = false
	round_running = true
	finish_reason = ""
	spawn_clock = 0.0
	wave_phase = "idle"
	wave_index = maxi(int(context.get("catch_wave_index", 0)), 0) if is_resume else 0
	used_session_words.clear()
	vocabulary_cycle = maxi(int(context.get("catch_vocab_cycle", 0)), 0) if is_resume else 0
	last_wave_words.clear()
	if is_resume:
		for entry in context.get("catch_last_wave_words", []):
			var recent := _word_key(String(entry))
			if not recent.is_empty() and not last_wave_words.has(recent):
				last_wave_words.append(recent)
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
	body_input_active = false
	player2_input_active = false
	_refresh_collected_words()
	_refresh_hud()
	_spawn_wave()
	queue_redraw()

	# The gameplay router may have disabled this minigame before the first
	# frame. Its embedded guide is PROCESS_MODE_ALWAYS so the student can still
	# read/hear the explanations and press Next before the 3-2-1 overlay.
	# Ordinary Play, resumed sessions and score/camera logic never enter here.
	if bool(context.get("guided_tutorial", false)) and not is_resume:
		call_deferred("begin_guided_tutorial")


func get_context() -> Dictionary:
	return _result_payload()


func set_body_x(normalized_x: float) -> void:
	if multiplayer_enabled:
		set_multiplayer_body_x(0, normalized_x)
		return
	body_target_normalized = clampf(normalized_x, -1.0, 1.0)
	body_input_active = true


func clear_body_input() -> void:
	body_input_active = false
	if multiplayer_enabled:
		player2_input_active = false


func set_multiplayer_body_x(index: int, value: float) -> void:
	if not multiplayer_enabled or index < 0 or index > 1 or not is_finite(value):
		return
	# PoseService sends signed horizontal VELOCITY, not a screen destination.
	# -999 (tracking lost) must never move/catch for that student.
	if value < -1.0 or value > 1.0:
		clear_multiplayer_body_input(index)
		return
	if index == 0:
		body_target_normalized = clampf(value, -1.0, 1.0)
		body_input_active = true
	else:
		player2_direction = clampf(value, -1.0, 1.0)
		player2_input_active = true


func clear_multiplayer_body_input(index: int) -> void:
	if index == 0:
		body_input_active = false
	elif index == 1:
		player2_input_active = false


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
	if tutorial_active or round_finished or not round_running:
		return

	_update_basket(delta)
	_sync_character_position()
	if multiplayer_enabled:
		_sync_player2_position()
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


func _wire_integrated_tutorial() -> void:
	# Only editor-authored controls are used; no detached tutorial .tscn,
	# runtime-created arrows or dynamic panel/character positions.
	tutorial_layer.visible = false
	tutorial_overlay.visible = false
	# Every scene instance owns its cutout parameter; switching between
	# Tutorial and Play must not inherit another instance's last highlight.
	tutorial_dim.material = tutorial_dim.material.duplicate(true)
	tutorial_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	tutorial_narration.process_mode = Node.PROCESS_MODE_ALWAYS
	tutorial_back.pressed.connect(tutorial_previous_step)
	tutorial_next.pressed.connect(tutorial_next_step)
	tutorial_skip.pressed.connect(skip_guided_tutorial)
	tutorial_replay.pressed.connect(replay_tutorial_voice)
	tutorial_pause_voice.pressed.connect(toggle_tutorial_voice_pause)
	# The cartoon textures own the visual button states. The native Button
	# keeps the hitbox/keyboard activation and a visible yellow focus ring.
	for art_button: Button in [tutorial_back, tutorial_next, tutorial_replay, tutorial_skip]:
		art_button.focus_entered.connect(_set_tutorial_art_focus.bind(art_button, true))
		art_button.focus_exited.connect(_set_tutorial_art_focus.bind(art_button, false))


func _set_tutorial_art_focus(button: Button, focused: bool) -> void:
	if not is_instance_valid(button):
		return
	var focus_ring := button.get_node_or_null("KeyboardFocusRing") as Panel
	if is_instance_valid(focus_ring):
		focus_ring.visible = focused


func _tutorial_steps() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in CATCH_TUTORIAL_STEPS:
		if entry["id"] == "seconds" and not is_seconds_mode:
			continue
		if entry["id"] == "lives" and not is_lives_mode:
			continue
		result.append(entry)
	return result


func is_tutorial_active() -> bool:
	return tutorial_active


func begin_guided_tutorial() -> void:
	if tutorial_active or round_finished or not bool(context.get("guided_tutorial", false)):
		return
	tutorial_generation += 1
	tutorial_active = true
	tutorial_step_index = 0
	tutorial_was_running = round_running
	round_running = false
	_stop_voice_feedback()
	# The guide does not progress waves, answer correctness, hearts or time.
	# The outer wrapper can keep this game disabled until after 3-2-1.
	set_process(false)
	tutorial_overlay.visible = true
	tutorial_layer.visible = true
	tutorial_overlay.move_to_front()
	_show_tutorial_step()


func tutorial_next_step() -> void:
	if not tutorial_active:
		return
	if tutorial_step_index >= _tutorial_steps().size() - 1:
		_finish_integrated_tutorial()
		return
	tutorial_step_index += 1
	_show_tutorial_step()


func tutorial_previous_step() -> void:
	if not tutorial_active or tutorial_step_index <= 0:
		return
	tutorial_step_index -= 1
	_show_tutorial_step()


func skip_guided_tutorial() -> void:
	if tutorial_active:
		_finish_integrated_tutorial()


func replay_tutorial_voice() -> void:
	if not tutorial_active:
		return
	tutorial_voice_paused = false
	tutorial_pause_voice.text = "PAUSE VOICE"
	tutorial_narration.stop()
	var step := _tutorial_steps()[tutorial_step_index]
	var clip_path := TUTORIAL_AUDIO_ROOT + String(step["id"]) + ".wav"
	if ResourceLoader.exists(clip_path):
		tutorial_narration.stream = load(clip_path) as AudioStream
		tutorial_narration.play()
	else:
		# Captions remain legible and navigation works when sound is missing.
		tutorial_narration.stream = null
		tutorial_replay.disabled = true


func toggle_tutorial_voice_pause() -> void:
	if not tutorial_active:
		return
	tutorial_voice_paused = not tutorial_voice_paused
	tutorial_narration.stream_paused = tutorial_voice_paused
	tutorial_pause_voice.text = "RESUME VOICE" if tutorial_voice_paused else "PAUSE VOICE"


func _show_tutorial_step() -> void:
	if not tutorial_active:
		return
	var steps := _tutorial_steps()
	if tutorial_step_index < 0 or tutorial_step_index >= steps.size():
		return
	var entry := steps[tutorial_step_index]
	tutorial_counter.text = "STEP %d OF %d" % [tutorial_step_index + 1, steps.size()]
	tutorial_title.text = entry["title"]
	tutorial_caption.text = entry["caption"]
	tutorial_back.disabled = tutorial_step_index == 0
	tutorial_back_art.texture = preload("res://ui/minigames/catch_the_word/tutorial_art/back_disabled.png") if tutorial_back.disabled else preload("res://ui/minigames/catch_the_word/tutorial_art/back_enabled.png")
	var is_final := tutorial_step_index == steps.size() - 1
	tutorial_next.text = "START COUNTDOWN" if is_final else "NEXT"
	tutorial_next_art.texture = preload("res://ui/minigames/catch_the_word/tutorial_art/header.png") if is_final else preload("res://ui/minigames/catch_the_word/tutorial_art/next.png")
	tutorial_start_label.visible = is_final
	tutorial_replay.disabled = false
	_refresh_tutorial_focus()
	replay_tutorial_voice()


func _on_tutorial_viewport_resized() -> void:
	# HUD and gameplay sizing may run later in the same resize notification.
	call_deferred("_refresh_tutorial_focus")


func _refresh_tutorial_focus() -> void:
	if not tutorial_active or not is_instance_valid(tutorial_dim):
		return
	var step := _tutorial_steps()[tutorial_step_index]
	var target: CanvasItem = prompt_label
	match String(step["id"]):
		"movement":
			target = basket_sprite
		"seconds":
			target = timer_plaque
		"lives":
			target = lives_plaque
		"score":
			target = score_plaque
		"pause":
			target = pause_plaque
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return
	# Keep the draggable guide at the same design scale as the Catch HUD.
	var factor := maxf(minf(viewport_size.x / 1280.0, viewport_size.y / 720.0), 0.01)
	tutorial_overlay.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tutorial_overlay.position = Vector2.ZERO
	tutorial_overlay.size = viewport_size / factor
	tutorial_overlay.scale = Vector2.ONE * factor
	# Both the target and overlay may live in different CanvasLayers.
	# Transform all four local corners into the overlay's coordinate system;
	# the SAME local rectangle drives the yellow outline AND the shader hole.
	var target_rect := Rect2()
	if target is Control:
		target_rect = Rect2(Vector2.ZERO, (target as Control).size)
	elif target is Sprite2D:
		target_rect = (target as Sprite2D).get_rect()
	if not target_rect.has_area():
		return
	var into_overlay := tutorial_overlay.get_global_transform_with_canvas().affine_inverse() * target.get_global_transform_with_canvas()
	var corners := [
		into_overlay * target_rect.position,
		into_overlay * Vector2(target_rect.end.x, target_rect.position.y),
		into_overlay * target_rect.end,
		into_overlay * Vector2(target_rect.position.x, target_rect.end.y),
	]
	var focus := Rect2(corners[0], Vector2.ZERO)
	for corner in corners:
		focus = focus.expand(corner)
	var step_offset: Variant = tutorial_step_focus_offsets.get(String(step["id"]), Vector2.ZERO)
	if step_offset is Vector2:
		focus.position += step_offset
	focus.position += tutorial_focus_offset
	focus = focus.grow_individual(maxf(tutorial_focus_padding.x, 0.0),
		maxf(tutorial_focus_padding.y, 0.0),
		maxf(tutorial_focus_padding.x, 0.0),
		maxf(tutorial_focus_padding.y, 0.0))
	focus = focus.intersection(Rect2(Vector2.ZERO, tutorial_overlay.size))
	if not focus.has_area():
		return
	tutorial_dim.position = Vector2.ZERO
	tutorial_dim.size = tutorial_overlay.size
	tutorial_focus.position = focus.position
	tutorial_focus.size = focus.size
	var uv := Rect2(focus.position / tutorial_dim.size, focus.size / tutorial_dim.size)
	(tutorial_dim.material as ShaderMaterial).set_shader_parameter("focus_rect",
		Vector4(uv.position.x, uv.position.y, uv.size.x, uv.size.y))


func _cancel_integrated_tutorial() -> void:
	tutorial_generation += 1
	tutorial_active = false
	tutorial_step_index = -1
	tutorial_voice_paused = false
	if is_instance_valid(tutorial_narration):
		tutorial_narration.stop()
		tutorial_narration.stream_paused = false
	if is_instance_valid(tutorial_overlay):
		tutorial_overlay.visible = false
	if is_instance_valid(tutorial_layer):
		tutorial_layer.visible = false


func _finish_integrated_tutorial() -> void:
	if not tutorial_active:
		return
	_cancel_integrated_tutorial()
	round_running = tutorial_was_running
	set_process(true)
	# The wrapper receives this exactly once and starts its frozen 3-2-1.
	# A standalone tutorial test can also observe this without a router.
	tutorial_finished.emit()


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

	# ScoreNumber is the designer's direct HUD child in the shared Catch scene.
	# Retain its editor-authored size, coordinates, font and style; never create
	# an obsolete ScoreBottomContainer or another score label at runtime.
	score_number_editor_position = score_bottom_number.position
	score_number_editor_font_size = score_bottom_number.get_theme_font_size("font_size")
	score_plaque_editor_position = score_plaque.position
	score_bottom_number.mouse_filter = Control.MOUSE_FILTER_IGNORE

	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for plaque in [title_plaque, timer_plaque, lives_plaque, pause_plaque, score_plaque]:
		plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Only dynamic text remains: the static title/score are already in the PNG.
	for label in [prompt_label, time_label]:
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
	# PNG headings are the sole visible title; HUD/ScoreNumber draws the value.
	# Pause is an actual PNG button, with a transparent clickable hit target.
	pause_button.icon = null
	var apple_path := GENERATED_ITEM_DIR + "word_apple.png"
	if ResourceLoader.exists(apple_path):
		gameplay_apple_texture = load(apple_path) as Texture2D
	_layout_controls()


func _place_score_behind_character() -> void:
	# The HUD lives in CanvasLayer 20; score nodes inside it always cover the
	# player, regardless of z_index. Keep the rest of the HUD on that layer.
	# Preserve the scene's authored ordering: Body=0, Basket=2,
	# CollectedWords=1. The basket lip renders over the tucked-in fruit.
	# Falling apples retain their original independent FallingWordLayer.
	score_draw_layer = Control.new()
	score_draw_layer.name = "ScoreDrawLayer"
	score_draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(score_draw_layer)
	score_plaque.reparent(score_draw_layer)
	# Both the score board and its original editor-authored number render behind
	# the player, rather than the rest of the CanvasLayer-20 HUD covering them.
	score_bottom_number.reparent(score_draw_layer, true)
	score_draw_layer.z_index = -3
	for name in CHARACTER_NODES:
		(get_node(name) as Node2D).z_index = 0
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
	# ScorePlaque is authored in the editor, just like its ScoreNumber sibling.
	# Do not overwrite the saved position/size with old generated HUD coordinates.

	_set_hud_rect(prompt_label, Vector2(58, 77), Vector2(370, 36))
	_set_hud_rect(time_label, Vector2(1085, 16), Vector2(98, 52))
	_set_hud_rect(pause_button, Vector2(1217, 29), Vector2(36, 36))
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if is_instance_valid(hearts_box):
		_set_hud_rect(hearts_box, Vector2(1024, 21), Vector2(136, 40))
	if using_reference_pngs:
		_set_hud_rect(title_plaque, Vector2(13, 10), Vector2(506, 157))
		_set_hud_rect(timer_plaque, Vector2(990 + extra_x, 8), Vector2(195, 76))
		_set_hud_rect(lives_plaque, Vector2(990 + extra_x, 8), Vector2(195, 76))
		_set_hud_rect(pause_plaque, Vector2(1195 + extra_x, 8), Vector2(81, 81))
		score_plaque.position = score_plaque_editor_position + Vector2(extra_x, extra_y)
		# Title board's cream question strip is y≈93..131, x≈114..419.
		# Center the baseline within the strip, not against its bottom trim.
		_set_hud_rect(prompt_label, Vector2(115, 93), Vector2(306, 33))
		_set_hud_rect(time_label, Vector2(1062 + extra_x, 20), Vector2(110, 50))
		_set_hud_rect(pause_button, Vector2(1212 + extra_x, 25), Vector2(48, 48))
		if is_instance_valid(hearts_box):
			_set_hud_rect(hearts_box, Vector2(1034 + extra_x, 27), Vector2(114, 34))
		# Keep the original editor-authored number aligned with its plaque on
		# wider/taller windows; never change the authored size or offsets.
		score_bottom_number.position = score_number_editor_position + Vector2(extra_x, extra_y)



func _set_hud_rect(control: Control, top_left: Vector2, dimensions: Vector2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = top_left
	control.size = dimensions


func _apply_difficulty() -> void:
	var raw_mode := String(context.get("game_mode", context.get("mode", "Lives"))).to_lower()
	default_lives = LIVES_ROUND_HEARTS
	if raw_mode in ["seconds", "60s", "sec"]:
		game_mode = "Seconds"
		is_seconds_mode = true
		is_lives_mode = false
		default_duration = SECONDS_ROUND_DURATION
	else:
		game_mode = "Lives"
		is_seconds_mode = false
		is_lives_mode = true
		default_duration = 0.0

	spawn_interval = 0.0
	base_fall_speed = BASE_EASY_FALL_SPEED * float(DIFFICULTY_SPEED_MULTIPLIER.get(difficulty, 1.0))
	wave_speed = base_fall_speed

	lives = LIVES_ROUND_HEARTS
	time_remaining = default_duration


func _select_round_art(source: Dictionary) -> void:
	var requested_character := String(source.get("catch_character", ""))
	var requested_map := String(source.get("catch_map", ""))

	if requested_character in CHARACTER_NODES:
		selected_character = requested_character
	else:
		selected_character = CHARACTER_NODES[rng.randi_range(0, CHARACTER_NODES.size() - 1)]

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
	# All five artwork groups are editable independently in catch_word.tscn.
	# Selecting a character only changes visibility, never its sprite transforms
	# or textures. This also preserves artist-adjusted basket/body alignment.
	player2_character = ""
	player2_group = null
	player2_basket_sprite = null
	if multiplayer_enabled:
		var requested_p2 := String(context.get("player2_catch_character", context.get("catch_character_p2", "")))
		if requested_p2 in CHARACTER_NODES and requested_p2 != selected_character:
			player2_character = requested_p2
		else:
			# A second existing editor-authored animal, NEVER a duplicated sprite.
			for candidate in CHARACTER_NODES:
				if candidate != selected_character:
					player2_character = candidate
					break
	for name in CHARACTER_NODES:
		var group := get_node_or_null(name) as Node2D
		if group == null:
			push_error("Missing editor-authored Catch character: " + name)
			continue
		var saved: Dictionary = character_editor_transforms.get(name, {})
		if selected_character != name and saved.has("position"):
			# A previous random/startup selection may have moved this group.
			# Return inactive variants to their exact Inspector positions.
			group.position = saved["position"]
		group.visible = selected_character == name or (multiplayer_enabled and player2_character == name)
		# Keep both parts individually editable in the scene Inspector.
		if selected_character == name:
			character_group = group
			body_sprite = group.get_node("Body") as Sprite2D
			basket_sprite = group.get_node("Basket") as Sprite2D
			character_editor_origin = saved.get("position", group.position)
			character_editor_scale = saved.get("scale", group.scale)
		if multiplayer_enabled and player2_character == name:
			player2_group = group
			player2_basket_sprite = group.get_node("Basket") as Sprite2D
	# The original wooden score plaque remains untouched in the editor. Only
	# multiplayer hides it in favor of two unambiguous player score panels.
	if is_instance_valid(score_draw_layer):
		score_draw_layer.visible = not multiplayer_enabled
	if is_instance_valid(multiplayer_board):
		multiplayer_board.visible = multiplayer_enabled


func _character_baseline_y() -> float:
	return character_editor_origin.y * (_view_size().y / HUD_DESIGN_SIZE.y)


func _basket_local_center() -> Vector2:
	# CollectedWords is a root sibling, so convert the chosen basket to its space.
	return collected_word_layer.to_local(basket_sprite.global_position)


func _basket_visual_size() -> Vector2:
	var artwork_size: Vector2 = basket_sprite.region_rect.size if basket_sprite.region_enabled else basket_sprite.texture.get_size()
	var rig_scale: Vector2 = collected_word_layer.global_scale
	var sprite_scale: Vector2 = basket_sprite.global_scale
	return artwork_size * Vector2(absf(sprite_scale.x / maxf(absf(rig_scale.x), 0.001)), absf(sprite_scale.y / maxf(absf(rig_scale.y), 0.001)))


func _basket_wood_top_in_apple_layer() -> float:
	# Every original basket PNG has a short opaque uniform-colored band above
	# its first actual wooden pixel. Read its edge instead of hardcoding a UI
	# location or changing any artist-authored Basket transform or texture.
	var key := selected_character
	if not basket_painted_rim_offsets.has(key):
		var image := basket_sprite.texture.get_image()
		var region := basket_sprite.region_rect if basket_sprite.region_enabled else Rect2(Vector2.ZERO, basket_sprite.texture.get_size())
		var sample_x := clampi(int(region.position.x + region.size.x * 0.5), 0, image.get_width() - 1)
		var painted_offset := 0.0
		for row in range(mini(int(region.size.y), 96)):
			var pixel := image.get_pixel(sample_x, clampi(int(region.position.y) + row, 0, image.get_height() - 1))
			# Dark brown/gold wicker, not green, blue, red, purple, or white uniform.
			if pixel.r > 0.45 and pixel.g > 0.255 and pixel.g > pixel.b * 1.35 and pixel.r > pixel.g * 1.25:
				painted_offset = float(row)
				break
		basket_painted_rim_offsets[key] = painted_offset
	var wooden_edge_local_y: float = basket_sprite.get_rect().position.y + float(basket_painted_rim_offsets[key])
	return collected_word_layer.to_local(basket_sprite.to_global(Vector2(0.0, wooden_edge_local_y))).y


func _basket_world_size() -> Vector2:
	return _basket_visual_size() * Vector2(absf(collected_word_layer.scale.x), absf(collected_word_layer.scale.y))


func _basket_world_offset() -> Vector2:
	return character_group.to_local(basket_sprite.global_position) * character_group.scale


func _sync_character_scale() -> void:
	# Scale each editor-authored sibling as the viewport changes. Preserve all
	# body/basket sprite transforms and their individual Inspector adjustments.
	var view := _view_size()
	var factor := minf(view.x / HUD_DESIGN_SIZE.x, view.y / HUD_DESIGN_SIZE.y)
	for name in CHARACTER_NODES:
		var group := get_node(name) as Node2D
		var saved: Dictionary = character_editor_transforms[name]
		group.scale = Vector2(saved["scale"]) * factor
	# Match the selected group's scale while keeping the collected layer's
	# original Inspector scale and its tiny offset from the Bear at rest.
	var bear_saved_scale: Vector2 = character_editor_transforms["Bear"]["scale"]
	var ratio := Vector2(
		character_editor_scale.x / maxf(absf(bear_saved_scale.x), 0.001),
		character_editor_scale.y / maxf(absf(bear_saved_scale.y), 0.001)
	)
	collected_word_layer.scale = collected_editor_scale * ratio * factor


func _reset_round_geometry() -> void:
	var field := _game_rect()
	# The selected character's own saved root position is its starting point.
	_sync_character_scale()
	basket_x = character_editor_origin.x * (_view_size().x / HUD_DESIGN_SIZE.x)
	var half_basket_width := _basket_world_size().x * 0.5
	var sprite_center_offset := _basket_world_offset().x
	basket_x = clampf(basket_x, field.position.x + half_basket_width + 8.0 - sprite_center_offset, field.end.x - half_basket_width - 8.0 - sprite_center_offset)
	if multiplayer_enabled:
		basket_x = lerpf(field.position.x + half_basket_width, field.end.x - half_basket_width, 0.28)
	basket_velocity = 0.0
	_sync_character_position()
	if multiplayer_enabled and is_instance_valid(player2_group):
		player2_basket_x = lerpf(field.position.x + half_basket_width, field.end.x - half_basket_width, 0.72)
		_sync_player2_position()


func _sync_character_position() -> void:
	character_group.position = Vector2(basket_x, _character_baseline_y())
	var view := _view_size()
	collected_word_layer.position = character_group.position + collected_editor_offset * Vector2(
		view.x / HUD_DESIGN_SIZE.x, view.y / HUD_DESIGN_SIZE.y
	)


func _sync_player2_position() -> void:
	if is_instance_valid(player2_group):
		# Original animal sprite transforms (including intentional lower cropping)
		# remain exactly those authored in catch_word.tscn.
		player2_group.position = Vector2(player2_basket_x, _character_baseline_y())


func _multiplayer_basket_rect(index: int) -> Rect2:
	if index == 0:
		return _basket_rect()
	if not is_instance_valid(player2_group) or not is_instance_valid(player2_basket_sprite):
		return Rect2()
	var sprite := player2_basket_sprite
	var image_size: Vector2 = sprite.region_rect.size if sprite.region_enabled else sprite.texture.get_size()
	var world_size := image_size * Vector2(absf(sprite.global_scale.x), absf(sprite.global_scale.y))
	var center := Vector2(player2_basket_x, _character_baseline_y()) + sprite.position * player2_group.scale
	center.y -= world_size.y * 0.05
	return Rect2(center - world_size * Vector2(basket_hitbox_width_ratio, basket_hitbox_height_ratio) * 0.5,
		world_size * Vector2(basket_hitbox_width_ratio, basket_hitbox_height_ratio))


func _update_basket(delta: float) -> void:
	# Camera/pose input is the only movement source. Never read A/D or the
	# ui_left/ui_right actions: keyboard avatar movement is deliberately gone.
	var field := _game_rect()
	var visible_half_width := _basket_world_size().x * 0.5
	var center_offset_x := _basket_world_offset().x
	var min_x := field.position.x + visible_half_width + 8.0 - center_offset_x
	var max_x := field.end.x - visible_half_width - 8.0 - center_offset_x
	basket_velocity = 0.0
	if multiplayer_enabled:
		# Both children may travel the SAME field. Absent camera tracking freezes
		# that child only: never move or collect on old/stale pose coordinates.
		var run := MULTIPLAYER_RUN_SPEED * maxf(delta, 0.0) * (_view_size().x / HUD_DESIGN_SIZE.x)
		if body_input_active and lives > 0:
			basket_x += body_target_normalized * run
		basket_x = clampf(basket_x, min_x, max_x)
		if is_instance_valid(player2_group) and is_instance_valid(player2_basket_sprite):
			var second_size := _multiplayer_basket_rect(1).size
			var second_offset := player2_basket_sprite.position.x * player2_group.scale.x
			var second_min := field.position.x + second_size.x * 0.5 + 8.0 - second_offset
			var second_max := field.end.x - second_size.x * 0.5 - 8.0 - second_offset
			if player2_input_active and player2_lives > 0:
				player2_basket_x += player2_direction * run
			player2_basket_x = clampf(player2_basket_x, second_min, second_max)
		return
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
		if wave_phase == "falling":
			if multiplayer_enabled:
				var winning_player := _multiplayer_catch_owner(tile)
				if winning_player >= 0:
					_handle_multiplayer_catch(tile, winning_player)
					_free_tile_node(tile)
					falling_tiles.remove_at(index)
					_resolve_wave(true)
					return
			elif (not bool(context.get("camera_live", false)) or body_input_active) and _tile_rect(tile).intersects(basket_rect):
				# A missing live pose must NEVER score via a stationary ghost
				# basket, while ordinary non-camera QA/demo stays unchanged.
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
	# Use the available width instead of leaving oversize apples crowded in
	# the center. The right lane still clears the editor-authored score board.
	var left := field.position.x + APPLE_SIZE.x * 0.5 + 140.0
	var right := minf(field.end.x - APPLE_SIZE.x * 0.5 - 12.0,
		score_plaque.position.x - APPLE_SIZE.x * 0.5 - APPLE_SPACING_MARGIN)
	# Equal visual spacing and a gap greater than the basket catch width:
	# one movement cannot accidentally collect adjacent options.
	return [left, (left + right) * 0.5, right]


func _correct_answer_wave_speed() -> float:
	var cap: float = WAVE_SPEED_CAPS.get(difficulty, WAVE_SPEED_CAPS["Easy"])
	var total_correct := correct_count + player2_correct if multiplayer_enabled else correct_count
	var multiplier := 1.0 + (cap - 1.0) * (1.0 - pow(WAVE_SPEED_REMAINING_FACTOR, float(total_correct)))
	return base_fall_speed * minf(multiplier, cap)


func _spawn_wave() -> void:
	if round_finished or wave_phase != "idle" or not falling_tiles.is_empty():
		return
	# Reserve a whole valid wave. Never end Seconds before 0 or Lives before
	# 0 hearts just because a finite grade/topic vocabulary has been shown.
	var correct_lane := rng.randi_range(0, APPLES_PER_WAVE - 1)
	var wave_words := _pick_unused_wave_words(correct_lane)
	if wave_words.size() != APPLES_PER_WAVE:
		# Start a new no-repeat cycle only when the remaining pool cannot fill
		# one correct + two distractors. Prefer excluding the previous three
		# words at the boundary, except when a tiny source makes that impossible.
		used_session_words.clear()
		vocabulary_cycle += 1
		var boundary_exclusions: Dictionary = {}
		for word in last_wave_words:
			boundary_exclusions[word] = true
		wave_words = _pick_unused_wave_words(correct_lane, boundary_exclusions)
		if wave_words.size() != APPLES_PER_WAVE:
			wave_words = _pick_unused_wave_words(correct_lane)
		if wave_words.size() != APPLES_PER_WAVE:
			# A malformed/empty external bank cannot supply a fair wave. Do not
			# synthesize grammar examples or route to Results prematurely.
			push_error("Catch the Word: fewer than one correct and two distinct distractors are available for %s/%s." % [topic, difficulty])
			return
	last_wave_words = wave_words.duplicate()
	var field := _game_rect()
	# Begin with the apple entirely above the viewport; let it descend into
	# view naturally rather than materializing mid-screen and hovering.
	var spawn_y := -APPLE_SIZE.y * 0.52
	wave_speed = _correct_answer_wave_speed()
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


func _pick_unused_wave_words(correct_lane: int, additional_exclusions: Dictionary = {}) -> Array[String]:
	var reserved: Dictionary = used_session_words.duplicate()
	for word in additional_exclusions:
		reserved[_word_key(String(word))] = true
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
	if not caught and not multiplayer_enabled:
		for tile in falling_tiles:
			if bool(tile["matching"]):
				_handle_missed_correct(tile)
				break
	if is_lives_mode:
		if (multiplayer_enabled and lives <= 0 and player2_lives <= 0) \
				or (not multiplayer_enabled and lives <= 0):
			# Main menu accepts Lives completion only with outer lives==0.
			# In multi this can happen ONLY after BOTH children are depleted.
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


func _multiplayer_catch_owner(tile: Dictionary) -> int:
	# A single apple belongs to exactly ONE eligible, currently tracked
	# basket. Nearest center wins simultaneous overlap; P1 wins exact ties.
	# No pose means NO catch for that child, not an automatic game pause.
	var apple := _tile_rect(tile)
	var best := -1
	var best_distance := INF
	for index in range(2):
		var active := body_input_active if index == 0 else player2_input_active
		var health := lives if index == 0 else player2_lives
		if not active or health <= 0:
			continue
		var basket := _multiplayer_basket_rect(index)
		if not apple.intersects(basket):
			continue
		var dist := absf(Vector2(tile["pos"]).x - basket.get_center().x)
		if dist < best_distance:
			best = index
			best_distance = dist
	return best


func _handle_multiplayer_catch(tile: Dictionary, index: int) -> void:
	var correct := bool(tile["matching"])
	var basket := _multiplayer_basket_rect(index)
	var catch_pos := basket.get_center() + Vector2(0.0, -40.0)
	if index == 0:
		attempts += 1
		if correct:
			correct_count += 1
			streak += 1
			best_streak = maxi(best_streak, streak)
			score += CORRECT_ANSWER_POINTS
			if collected_words.size() < COLLECTED_WORD_LIMIT:
				collected_words.append(String(tile["word"]))
				_refresh_collected_words()
		else:
			streak = 0
			lives = maxi(lives - 1, 0)
	else:
		player2_attempts += 1
		if correct:
			player2_correct += 1
			player2_streak += 1
			player2_best_streak = maxi(player2_best_streak, player2_streak)
			player2_score += CORRECT_ANSWER_POINTS
		else:
			player2_streak = 0
			player2_lives = maxi(player2_lives - 1, 0)
	# Wave progress is based on both students' correct answers.
	wave_speed = _correct_answer_wave_speed()
	_spawn_confetti(catch_pos.x, catch_pos.y, not correct)
	_show_floating_score(("P%d +100" % [index + 1]) if correct else
		("P%d -1 HEART" % [index + 1]), catch_pos,
		Color("#4EF082") if correct else Color("#FF6C8A"))
	_speak_catch_feedback(correct)


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
	# Larger, outlined word labels remain inside the bigger falling apple.
	# Normal words remain one line; long Grade 1-6 vocabulary wraps across
	# readable lines instead of shrinking into tiny illegible print.
	var word_font_size := falling_word_font_size
	while word_font_size > falling_word_min_font_size and TITLE_FONT.get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, word_font_size).x > APPLE_SIZE.x - 20.0:
		word_font_size -= 1
	if TITLE_FONT.get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, word_font_size).x > APPLE_SIZE.x - 20.0:
		label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.add_theme_font_size_override("font_size", word_font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.18, 0.1, 0.1, 0.95))
	label.add_theme_constant_override("outline_size", 5)
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
		# GrammarBank owns the valid difficulty/topic pools. Exclusions prevent
		# repeats within the cycle without fabricating suffixes or new words.
		return String(grammar_bank.call("pick_word", topic, matching, rng, difficulty, excluded)).strip_edges()
	# Offline fallback for a missing bank, with the same cycle policy.
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
		wave_speed = _correct_answer_wave_speed()
		streak += 1
		best_streak = maxi(best_streak, streak)
		# Every correct apple earns the same amount at every difficulty and
		# streak length. Difficulty changes falling speed, not score value.
		var gain := CORRECT_ANSWER_POINTS
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
	if _kids_voice != null:
		return
	_kids_voice = KidsVoice.new()
	_kids_voice.setup(self)
	var player := _kids_voice.get_voice_player() as AudioStreamPlayer
	if player != null:
		player.name = "CatchVoicePlayer"


func _speak_catch_feedback(correct: bool, missed: bool = false) -> void:
	if _kids_voice == null:
		return
	if missed:
		_kids_voice.play_missed()
	elif correct:
		_kids_voice.play_correct()
	else:
		_kids_voice.play_wrong()


func _stop_voice_feedback() -> void:
	if _kids_voice != null:
		_kids_voice.stop()


func _exit_tree() -> void:
	_cancel_integrated_tutorial()
	_stop_voice_feedback()
	if _kids_voice != null:
		_kids_voice.release()


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
		if tutorial_active:
			match event.keycode:
				KEY_ESCAPE, KEY_P, KEY_SPACE:
					toggle_tutorial_voice_pause()
				KEY_ENTER, KEY_KP_ENTER, KEY_RIGHT:
					tutorial_next_step()
				KEY_LEFT:
					tutorial_previous_step()
				_:
					return
			get_viewport().set_input_as_handled()
			return
		if event.keycode in [KEY_ESCAPE, KEY_P]:
			_pause()
			get_viewport().set_input_as_handled()


func _pause() -> void:
	if round_finished:
		return
	if tutorial_active:
		toggle_tutorial_voice_pause()
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
	if multiplayer_enabled:
		# Explicitly attribute scores to students; never submit a fictitious
		# combined score as if it belonged to either student. The results/backend
		# router can persist P2 separately when its API contract is ready.
		payload["player_mode"] = "Multiplayer"
		payload["multiplayer"] = true
		payload["player1_score"] = score
		payload["player1_lives"] = lives
		payload["player2_score"] = player2_score
		payload["player2_lives"] = player2_lives
		payload["player2_correct"] = player2_correct
		payload["player2_attempts"] = player2_attempts
		payload["player2_streak"] = player2_streak
		payload["player2_best_streak"] = player2_best_streak
		payload["player2_catch_character"] = player2_character
		payload["player2_student_id"] = String(context.get("player2_student_id", ""))
		payload["player2_student_name"] = String(context.get("player2_student_name", ""))
		payload["player2_grade_section"] = String(context.get("player2_grade_section", ""))
		payload["multiplayer_result_provisional"] = true
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
	payload["catch_vocab_cycle"] = vocabulary_cycle
	payload["catch_last_wave_words"] = last_wave_words.duplicate()
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
	var apple_width := basket_size.x * caught_half_apple_basket_width_ratio
	var apple_size := Vector2(apple_width,
		apple_width * float(HALF_APPLE_TEXTURE.get_height()) / float(HALF_APPLE_TEXTURE.get_width()))
	var spacing := apple_size.x * caught_half_apple_spacing_ratio
	var count := mini(collected_words.size(), COLLECTED_WORD_LIMIT)
	var rim_y := center.y - basket_size.y * 0.5
	var painted_wicker_top_y := _basket_wood_top_in_apple_layer()

	for index in range(count):
		var apple := TextureRect.new()
		apple.name = "CaughtApple%d" % (index + 1)
		apple.texture = HALF_APPLE_TEXTURE
		apple.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		apple.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Do NOT add the old UV clipping material: APPLE HALF.png is actual half
		# artwork. All three have the same fixed size and share the same lip line.
		# The filled lower red edge sits behind the front-facing wicker lip,
		# without revealing the character's uniform through a transparent gap.
		# The artist's editable marker still moves the whole cluster as a unit.
		apple.position = Vector2(center.x + (float(index) - (float(count) - 1.0) * 0.5) * spacing - apple_size.x * 0.5,
			rim_y - apple_size.y * HALF_APPLE_PAINTED_HEIGHT_RATIO) + collected_apple_placement_offset
		apple.size = apple_size
		# Keep apple pixels visible across the opaque uniform band baked into
		# the basket PNG. The new clip stops at the REAL wooden rim, so the red
		# fruit stays behind the wicker without moving the Body/Basket/marker.
		apple.z_index = 2 # CollectedWords(1) + local(2) = above Basket(2).
		var front_clip := ShaderMaterial.new()
		front_clip.shader = CAUGHT_APPLE_FRONT_CLIP
		front_clip.set_shader_parameter("wicker_top_uv", clampf((painted_wicker_top_y - apple.position.y) / maxf(apple_size.y, 0.001), 0.0, 1.0))
		apple.material = front_clip
		apple.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	if score_bottom_number and (score != last_score_layout_value or score_bottom_number.text != str(score)):
		last_score_layout_value = score
		score_bottom_number.text = "%d" % score
		var score_font_size := score_number_editor_font_size
		while score_font_size > 16 and TITLE_FONT.get_string_size(score_bottom_number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, score_font_size).x > score_bottom_number.size.x - 18.0:
			score_font_size -= 2
		score_bottom_number.add_theme_font_size_override("font_size", score_font_size)
	if is_instance_valid(multiplayer_board):
		multiplayer_board.visible = multiplayer_enabled
		if multiplayer_enabled:
			player1_score_label.text = "P1  %d  |  %d HEARTS" % [score, lives]
			player2_score_label.text = "P2  %d  |  %d HEARTS" % [player2_score, player2_lives]

	if is_seconds_mode:
		timer_plaque.visible = true
		lives_plaque.visible = false
		time_label.visible = true
		time_label.text = "%ds" % int(ceil(time_remaining))
		if hearts_box:
			hearts_box.visible = false
	else:
		timer_plaque.visible = false
		lives_plaque.visible = true
		time_label.visible = false
		_update_hearts_visual()


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
	if multiplayer_enabled and is_instance_valid(player2_group):
		var second_box := _multiplayer_basket_rect(1)
		player2_basket_x = clampf(player2_basket_x,
			field.position.x + second_box.size.x * 0.5 + 8.0,
			field.end.x - second_box.size.x * 0.5 - 8.0)
		_sync_player2_position()
	_refresh_collected_words()
	_refresh_hud()
	_refresh_tutorial_focus()
	queue_redraw()
