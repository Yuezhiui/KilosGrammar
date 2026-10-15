extends Control

const FALLING_GRAMMAR_CATEGORIES := [
	"noun", "verb", "pronoun", "adverb", "adjective", "preposition", "conjunction"
]
const FALLING_GRAMMAR_SAMPLES := {
	"noun": [
		"APPLE", "BOOK", "CAT", "DOG", "HOUSE",
		"SCHOOL", "TEACHER", "RIVER", "FRIEND", "MUSIC",
		"CITY", "TABLE", "FLOWER", "CLOUD", "PENCIL"
	],
	"verb": [
		"RUN", "READ", "WRITE", "JUMP", "SING",
		"DANCE", "PLAY", "SWIM", "THINK", "LEARN",
		"BUILD", "SMILE", "TALK", "WALK", "CREATE"
	],
	"pronoun": [
		"I", "YOU", "HE", "SHE", "IT",
		"WE", "THEY", "ME", "HIM", "HER",
		"US", "THEM", "THIS", "THAT", "WHO"
	],
	"adverb": [
		"QUICKLY", "SLOWLY", "SOFTLY", "LOUDLY", "HAPPILY",
		"BRAVELY", "QUIETLY", "GENTLY", "ALWAYS", "NEVER",
		"OFTEN", "HERE", "THERE", "TODAY", "SOON"
	],
	"adjective": [
		"HAPPY", "BRAVE", "BRIGHT", "SMALL", "LARGE",
		"QUICK", "QUIET", "COLORFUL", "KIND", "SOFT",
		"TALL", "WARM", "FUNNY", "SMART", "FRESH"
	],
	"preposition": [
		"IN", "ON", "AT", "UNDER", "OVER",
		"BESIDE", "BETWEEN", "THROUGH", "AROUND", "BEFORE",
		"AFTER", "WITH", "WITHOUT", "NEAR", "INTO"
	],
	"conjunction": [
		"AND", "BUT", "OR", "SO", "YET",
		"FOR", "NOR", "BECAUSE", "WHILE", "ALTHOUGH",
		"IF", "WHEN", "SINCE", "UNLESS", "AS"
	]
}
const FALLING_GRAMMAR_COLORS := [
	Color("#69BE9A"), # noun
	Color("#FF4F66"), # verb
	Color("#C171CF"), # pronoun
	Color("#7BC9EF"), # adverb
	Color("#FFC23D"), # adjective
	Color("#F4985F"), # preposition
	Color("#5AA0D7")  # conjunction
]
const LOGO_BLOOP: AudioStream = preload("res://assets/audio/lexispell_intro/logo_bloop.wav")
const LETTER_POP: AudioStream = preload("res://assets/audio/lexispell_intro/letter_pop.wav")
# Optional user-provided local soundtrack. Never require third-party music
# for a fresh checkout of the public source repository.
const TITLE_MUSIC_PATH := "res://assets/audio/user_provided/wii_fit_user_settings.mp3"
const CATCH_PRELOADER_SCRIPT: Script = preload("res://ui/play/catch_asset_preloader.gd")
const BUTTON_HOVER: AudioStream = preload("res://assets/audio/lexispell_intro/button_hover.wav")
const BUTTON_CLICK: AudioStream = preload("res://assets/audio/lexispell_intro/button_click.wav")
const MUSIC_BUS := "KilosMusic"
const EFFECTS_BUS := "KilosSFX"

@onready var logo_group: Control = $MainLayer/LogoGroup
@onready var kilos_label: TextureRect = $MainLayer/LogoGroup/Kilos
@onready var grammar_tiles: Array[Control] = [
	$MainLayer/LogoGroup/GrammarG,
	$MainLayer/LogoGroup/GrammarR1,
	$MainLayer/LogoGroup/GrammarA1,
	$MainLayer/LogoGroup/GrammarM1,
	$MainLayer/LogoGroup/GrammarM2,
	$MainLayer/LogoGroup/GrammarA2,
	$MainLayer/LogoGroup/GrammarR2
]
@onready var left_menu: Control = $MainLayer/LeftMenu
@onready var center_menu: Control = $MainLayer/CenterMenu
@onready var version: Label = get_node_or_null("MainLayer/Version") as Label
@onready var tooltip: PanelContainer = $MainLayer/Tooltip
@onready var tooltip_label: Label = $MainLayer/Tooltip/Text
@onready var falling_layer: Control = $FallingLayer
@onready var falling_template: PanelContainer = $FallingLayer/FallingTemplate
@onready var fall_timer: Timer = $FallTimer

# New screens are hosted above the original menu so the animated background,
# falling word cards, title music and custom cursor continue to be reused.
const PANEL_SCENES := {
	"tutorial_home": "res://ui/tutorial/tutorial_home.tscn",
	"tutorial_practice": "res://ui/tutorial/tutorial_practice.tscn",
	"tutorial_complete": "res://ui/tutorial/tutorial_complete.tscn",
	"grammar_guide": "res://ui/tutorial/grammar_guide.tscn",
	"student_setup": "res://ui/student/student_setup.tscn",
	"play_activity": "res://ui/play/play_activity.tscn",
	"play_topic": "res://ui/play/play_topic.tscn",
	"play_difficulty": "res://ui/play/play_difficulty.tscn",
	"camera_check": "res://ui/vision/camera_check.tscn",
	"calibration": "res://ui/vision/calibration.tscn",
	"ready": "res://ui/play/ready.tscn",
	"gameplay": "res://ui/play/gameplay.tscn",
	"pause": "res://ui/play/pause.tscn",
	"results": "res://ui/secondary/results.tscn",
	"leaderboard": "res://ui/secondary/leaderboard.tscn",
	"settings": "res://ui/secondary/settings.tscn",
	"credits": "res://ui/secondary/credits.tscn"
}
var panel_host: Control
var active_panel: Control
# Keep the active minigame alive behind the pause screen. Rebuilding a fresh
# gameplay scene on Resume discarded falling tiles, answer gates and shots.
var paused_game_panel: Control
var current_route := "main"
var session_state: Dictionary = {"entry_source": "play", "demo_mode": true}
var catch_asset_preloader: Node

var rng := RandomNumberGenerator.new()
var button_tweens: Dictionary = {}
var logo_tweens: Dictionary = {}
var logo_sequence_tween: Tween
var grammar_home_positions: Dictionary = {}
var grammar_home_rotations: Dictionary = {}
var logo_home := Vector2.ZERO
var left_home := Vector2.ZERO
var center_home := Vector2.ZERO
var intro_done := false
var idle_time := 0.0
var title_music_player: AudioStreamPlayer
var logo_bump_active := false
var tooltip_tween: Tween
const TOOLTIP_GAP := 24.0


func _process(delta: float) -> void:
	if not intro_done or current_route != "main":
		return

	idle_time += delta
	logo_group.position = logo_home + Vector2(0.0, sin(idle_time * 1.18) * 1.3)
	for index in range(grammar_tiles.size()):
		var tile: Control = grammar_tiles[index]
		var phase: float = float(index) * 1.12
		var tile_home: Vector2 = grammar_home_positions[tile]
		var rotation_home: float = grammar_home_rotations[tile]
		tile.position = tile_home + Vector2(0.0, sin(idle_time * 1.65 + phase) * 1.7)
		tile.rotation = rotation_home + sin(idle_time * 1.22 + phase) * 0.010


func _ready() -> void:
	rng.seed = 260926
	_setup_panel_host()
	_sync_kilos_texture_rect()
	logo_home = logo_group.position
	left_home = left_menu.position
	center_home = center_menu.position
	_ensure_audio_buses()
	_setup_title_music()

	for tile in grammar_tiles:
		grammar_home_positions[tile] = tile.position
		grammar_home_rotations[tile] = tile.rotation

	_register_left_button($MainLayer/LeftMenu/Leaderboard, "View student scores and rankings.", 0.015)
	_register_left_button($MainLayer/LeftMenu/Settings, "Adjust audio, display, and gameplay preferences.", 0.013)
	_register_left_button($MainLayer/LeftMenu/Credits, "View the KilosGrammar team and acknowledgments.", -0.012)

	_register_button($MainLayer/CenterMenu/Tutorial, -0.026)
	_register_button($MainLayer/CenterMenu/Play, 0.018)
	_register_button($MainLayer/CenterMenu/Quit, -0.016)
	$MainLayer/CenterMenu/Tutorial.pressed.connect(_on_main_navigation.bind("tutorial_home"))
	$MainLayer/CenterMenu/Play.pressed.connect(_on_main_navigation.bind("student_setup"))
	$MainLayer/CenterMenu/Quit.pressed.connect(_on_main_navigation.bind("quit"))
	$MainLayer/LeftMenu/Leaderboard.pressed.connect(_on_main_navigation.bind("leaderboard"))
	$MainLayer/LeftMenu/Settings.pressed.connect(_on_main_navigation.bind("settings"))
	$MainLayer/LeftMenu/Credits.pressed.connect(_on_main_navigation.bind("credits"))
	_register_logo_interactions()

	fall_timer.timeout.connect(_spawn_falling_grammar_card)
	tooltip.z_index = 40
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.visible = false
	call_deferred("_play_intro")


func _sync_kilos_texture_rect() -> void:
	if kilos_label.texture == null:
		return

	var texture_size: Vector2 = kilos_label.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return

	# Keep the designed width/center, but derive height from the real texture
	# aspect ratio. This prevents fresh imports/runs from squeezing KILOS.
	var center: Vector2 = kilos_label.position + kilos_label.size * 0.5
	var display_width: float = kilos_label.size.x
	var display_height: float = display_width * texture_size.y / texture_size.x

	kilos_label.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	kilos_label.size = Vector2(display_width, display_height)
	kilos_label.position = center - kilos_label.size * 0.5


func _play_intro() -> void:
	if version:
		version.modulate.a = 0.0
	left_menu.position = left_home + Vector2(-250, 0)
	center_menu.position = center_home + Vector2(0, 300)

	# Lexispell's logo intro starts with a compressed word mark, overshoots,
	# then settles while the remaining letters pop in one after another.
	for part: Control in [kilos_label]:
		part.pivot_offset = part.size * 0.5
		part.scale = Vector2(0.00001, 0.00001)
		part.rotation = -0.20944

	for index in range(grammar_tiles.size()):
		var tile: Control = grammar_tiles[index]
		tile.position = grammar_home_positions[tile]
		tile.pivot_offset = tile.size * 0.5
		tile.rotation = grammar_home_rotations[tile]
		tile.scale = Vector2(0.00001, 0.00001)
		tile.modulate.a = 0.0

	var menu_buttons: Array[Button] = [
		$MainLayer/LeftMenu/Leaderboard,
		$MainLayer/LeftMenu/Settings,
		$MainLayer/LeftMenu/Credits,
		$MainLayer/CenterMenu/Tutorial,
		$MainLayer/CenterMenu/Play,
		$MainLayer/CenterMenu/Quit
	]
	for button: Button in menu_buttons:
		button.scale = Vector2(0.86, 0.86)
		button.modulate.a = 0.0

	_schedule_sfx(LOGO_BLOOP, 1.0, 0.067, -4.0)

	# Keep each squash stage sequential. The previous set_parallel()+chain()
	# setup made multiple scale tweens fight over the same property, leaving
	# KILOS stuck at the first overshoot until it was clicked.
	var word_tween: Tween = create_tween()
	word_tween.tween_property(kilos_label, "rotation", 0.07854, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	word_tween.parallel().tween_property(kilos_label, "scale", Vector2(1.23, 0.865), 0.267).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	word_tween.tween_property(kilos_label, "rotation", 0.0, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	word_tween.parallel().tween_property(kilos_label, "scale", Vector2(0.9, 1.1), 0.067).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	word_tween.tween_property(kilos_label, "scale", Vector2.ONE, 0.133).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var menu_tween: Tween = create_tween()
	menu_tween.set_parallel(true)
	menu_tween.tween_property(left_menu, "position", left_home, 0.34).set_delay(0.52).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	menu_tween.tween_property(center_menu, "position", center_home, 0.36).set_delay(0.56).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if version:
		menu_tween.tween_property(version, "modulate:a", 1.0, 0.16).set_delay(0.72)

	for index in range(grammar_tiles.size()):
		var tile: Control = grammar_tiles[index]
		var delay: float = 0.283 + float(index) * 0.055
		var pop_pitch: float = 1.0 + float(index) * 0.05
		var tile_tween: Tween = create_tween()
		tile_tween.tween_interval(delay)
		tile_tween.tween_callback(_reveal_intro_tile.bind(tile, pop_pitch))
		tile_tween.tween_property(tile, "scale", Vector2(1.2, 1.2), 0.115).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tile_tween.parallel().tween_property(tile, "rotation", grammar_home_rotations[tile] - 0.16, 0.115).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tile_tween.tween_property(tile, "scale", Vector2.ONE, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tile_tween.parallel().tween_property(tile, "rotation", grammar_home_rotations[tile], 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	for index in range(menu_buttons.size()):
		var button: Button = menu_buttons[index]
		var button_delay: float = 0.58 + float(index) * 0.035
		menu_tween.tween_property(button, "scale", Vector2.ONE, 0.20).set_delay(button_delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		menu_tween.tween_property(button, "modulate:a", 1.0, 0.10).set_delay(button_delay)

	await get_tree().create_timer(1.12).timeout
	intro_done = true
	$MainLayer/CenterMenu/Play.grab_focus()
	fall_timer.start()
	for i in range(3):
		_spawn_falling_grammar_card()


func _reveal_intro_tile(tile: Control, pitch: float) -> void:
	tile.modulate.a = 1.0
	_play_one_shot(LETTER_POP, pitch, -5.0)


func _setup_title_music() -> void:
	# The user's optional local soundtrack remains available in their editor,
	# but the public repository is playable without distributing that MP3.
	if not ResourceLoader.exists(TITLE_MUSIC_PATH):
		return
	var selected_music := load(TITLE_MUSIC_PATH) as AudioStream
	if selected_music == null:
		return
	title_music_player = AudioStreamPlayer.new()
	title_music_player.name = "TitleMusic"
	title_music_player.bus = MUSIC_BUS
	title_music_player.stream = selected_music
	title_music_player.volume_db = -32.0
	add_child(title_music_player)
	if title_music_player.stream is AudioStreamOggVorbis:
		(title_music_player.stream as AudioStreamOggVorbis).loop = true
	elif title_music_player.stream is AudioStreamMP3:
		(title_music_player.stream as AudioStreamMP3).loop = true
	title_music_player.play()
	var fade: Tween = create_tween()
	fade.tween_property(title_music_player, "volume_db", -8.0, 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _schedule_sfx(stream: AudioStream, pitch: float, delay: float, volume_db: float = 0.0) -> void:
	await get_tree().create_timer(delay).timeout
	_play_one_shot(stream, pitch, volume_db)


func _play_one_shot(stream: AudioStream, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = EFFECTS_BUS
	player.pitch_scale = pitch
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


func _ensure_audio_buses() -> void:
	# UI volume controls need real mixer destinations. These buses are local to
	# the current Godot session and are never treated as persisted preferences.
	for bus_name in [MUSIC_BUS, EFFECTS_BUS]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var new_index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(new_index, bus_name)
		AudioServer.set_bus_send(new_index, "Master")


func _register_left_button(button: Button, copy: String, hover_rotation: float) -> void:
	_register_button(button, hover_rotation)
	button.mouse_entered.connect(_show_tooltip.bind(button, copy))
	button.mouse_exited.connect(_hide_tooltip)


func _register_button(button: Button, _hover_rotation: float) -> void:
	button.set_meta("home_rotation", button.rotation)
	button.mouse_entered.connect(_hover_button.bind(button))
	button.mouse_exited.connect(_unhover_button.bind(button))
	button.button_down.connect(_press_button.bind(button))
	button.button_up.connect(_release_button.bind(button))
	button.resized.connect(_refresh_pivot.bind(button))
	call_deferred("_refresh_pivot", button)


func _register_logo_interactions() -> void:
	kilos_label.mouse_filter = Control.MOUSE_FILTER_STOP
	kilos_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	kilos_label.mouse_entered.connect(_hover_kilos)
	kilos_label.mouse_exited.connect(_unhover_kilos)
	kilos_label.gui_input.connect(_on_kilos_gui_input)

	for index in range(grammar_tiles.size()):
		var tile: Control = grammar_tiles[index]
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
		tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tile.gui_input.connect(_on_grammar_tile_gui_input.bind(tile, index))


func _refresh_pivot(button: Button) -> void:
	if is_instance_valid(button):
		button.pivot_offset = button.size * 0.5


func _hover_button(button: Button, play_sound: bool = true) -> void:
	button.z_index = 20
	_kill_button_tween(button)
	if play_sound:
		_play_one_shot(BUTTON_HOVER, 1.0, -4.0)
	var scale_ratio: float = clampf(128.0 / maxf(button.size.x, 1.0), 0.5, 1.0)
	var scale_target: float = 1.0 + 0.2 * scale_ratio
	var rotation_target: float = float([-1.0, 1.0].pick_random()) * deg_to_rad(5.0 * scale_ratio)
	var tween: Tween = create_tween()
	button_tweens[button] = tween
	tween.set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(button, "scale:x", scale_target, 0.20)
	tween.tween_property(button, "scale:y", scale_target, 0.35)
	tween.tween_property(button, "rotation", float(button.get_meta("home_rotation", 0.0)) + rotation_target, 0.10)
	tween.tween_property(button, "rotation", float(button.get_meta("home_rotation", 0.0)), 0.10).set_delay(0.10)


func _unhover_button(button: Button) -> void:
	_kill_button_tween(button)
	var tween: Tween = create_tween()
	button_tweens[button] = tween
	tween.set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(button, "scale:x", 1.0, 0.25)
	tween.tween_property(button, "scale:y", 1.0, 0.35)
	tween.tween_property(button, "rotation", float(button.get_meta("home_rotation", 0.0)), 0.10)
	await tween.finished
	if is_instance_valid(button):
		button.z_index = 0


func _press_button(button: Button) -> void:
	_kill_button_tween(button)
	_play_one_shot(BUTTON_CLICK, 1.0, -1.0)
	var tween: Tween = create_tween()
	button_tweens[button] = tween
	tween.tween_property(button, "scale", Vector2(0.94, 0.90), 0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _release_button(button: Button) -> void:
	var hovered: bool = button.get_global_rect().has_point(get_viewport().get_mouse_position())
	if hovered:
		_hover_button(button, false)
	else:
		_unhover_button(button)


func _kill_button_tween(button: Button) -> void:
	var old: Tween = button_tweens.get(button)
	if old and old.is_valid():
		old.kill()


func _hover_kilos() -> void:
	if not intro_done or logo_bump_active:
		return
	_play_one_shot(BUTTON_HOVER, 0.92, -6.0)
	_bump_kilos(Vector2(1.035, 1.035), 0.10, false)


func _unhover_kilos() -> void:
	if not intro_done or logo_bump_active:
		return
	_bump_kilos(Vector2.ONE, 0.12, false)


func _on_kilos_gui_input(event: InputEvent) -> void:
	if not intro_done:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_play_logo_bump_sequence()


func _on_grammar_tile_gui_input(event: InputEvent, tile: Control, index: int) -> void:
	if not intro_done:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_play_one_shot(LETTER_POP, 1.0 + float(index) * 0.05, -5.0)
		_bump_grammar_tile(tile)


func _play_logo_bump_sequence() -> void:
	logo_bump_active = true
	_play_one_shot(LOGO_BLOOP, 1.0, -5.0)
	_bump_kilos(Vector2.ONE, 0.0, true)

	if logo_sequence_tween and logo_sequence_tween.is_valid():
		logo_sequence_tween.kill()
	logo_sequence_tween = create_tween()
	logo_sequence_tween.tween_interval(0.22)
	for index in range(grammar_tiles.size()):
		var tile: Control = grammar_tiles[index]
		var pitch: float = 1.0 + float(index) * 0.05
		logo_sequence_tween.tween_callback(_logo_tile_pop.bind(tile, pitch))
		logo_sequence_tween.tween_interval(0.055)
	logo_sequence_tween.tween_callback(_finish_logo_bump)


func _logo_tile_pop(tile: Control, pitch: float) -> void:
	_play_one_shot(LETTER_POP, pitch, -5.0)
	_bump_grammar_tile(tile)


func _finish_logo_bump() -> void:
	logo_bump_active = false


func _bump_kilos(target_scale: Vector2, duration: float, full_bump: bool) -> void:
	var key := "kilos"
	var old: Tween = logo_tweens.get(key)
	if old and old.is_valid():
		old.kill()

	var tween: Tween = create_tween()
	logo_tweens[key] = tween
	if full_bump:
		var angle: float = deg_to_rad(rng.randf_range(4.0, 7.0) * float([-1.0, 1.0].pick_random()))
		var squash := Vector2(rng.randf_range(1.15, 1.25), rng.randf_range(0.80, 0.90))
		tween.tween_property(kilos_label, "scale", squash, 0.10).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.parallel().tween_property(kilos_label, "rotation", angle, 0.10).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_property(kilos_label, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.parallel().tween_property(kilos_label, "rotation", 0.0, 0.15).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	else:
		tween.tween_property(kilos_label, "scale", target_scale, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _bump_grammar_tile(tile: Control) -> void:
	var old: Tween = logo_tweens.get(tile)
	if old and old.is_valid():
		old.kill()
	var tween: Tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	logo_tweens[tile] = tween
	tween.tween_property(tile, "scale", Vector2(rng.randf_range(1.15, 1.25), rng.randf_range(0.80, 0.90)), 0.10)
	tween.tween_property(tile, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)


func _show_tooltip(button: Button, copy: String) -> void:
	if current_route != "main":
		return
	if tooltip_tween and tooltip_tween.is_valid():
		tooltip_tween.kill()
	tooltip_label.text = copy
	tooltip.custom_minimum_size = Vector2(260.0, 72.0)
	tooltip.size = Vector2(260.0, 72.0)
	var rect: Rect2 = button.get_global_rect()
	var viewport_rect: Rect2 = get_viewport_rect()
	var tooltip_width: float = tooltip.size.x
	var tooltip_height: float = tooltip.size.y
	var target_x: float = rect.end.x + TOOLTIP_GAP
	if target_x + tooltip_width > viewport_rect.end.x - 12.0:
		target_x = rect.position.x - TOOLTIP_GAP - tooltip_width
	var target_y: float = rect.position.y + (rect.size.y - tooltip_height) * 0.5
	target_y = clampf(target_y, 12.0, maxf(12.0, viewport_rect.size.y - tooltip_height - 12.0))
	tooltip.global_position = Vector2(target_x, target_y)
	tooltip.pivot_offset = Vector2(0.0, tooltip_height * 0.5)
	tooltip.visible = true
	tooltip.scale = Vector2(0.94, 0.94)
	tooltip.modulate.a = 0.0
	tooltip_tween = create_tween()
	tooltip_tween.set_parallel(true)
	tooltip_tween.tween_property(tooltip, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tooltip_tween.tween_property(tooltip, "modulate:a", 1.0, 0.08)


func _hide_tooltip() -> void:
	if not tooltip.visible:
		return
	if tooltip_tween and tooltip_tween.is_valid():
		tooltip_tween.kill()
	tooltip_tween = create_tween()
	tooltip_tween.set_parallel(true)
	tooltip_tween.tween_property(tooltip, "scale", Vector2(0.94, 0.94), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tooltip_tween.tween_property(tooltip, "modulate:a", 0.0, 0.08)
	tooltip_tween.chain().tween_callback(func() -> void: tooltip.visible = false)


func _spawn_falling_grammar_card() -> void:
	if falling_layer.get_child_count() > 10:
		return
	fall_timer.wait_time = rng.randf_range(0.48, 0.95)

	var card: PanelContainer = falling_template.duplicate() as PanelContainer
	card.name = "FallingGrammarCard"
	card.visible = true
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	falling_layer.add_child(card)

	var category_index := rng.randi_range(0, FALLING_GRAMMAR_CATEGORIES.size() - 1)
	var category: String = FALLING_GRAMMAR_CATEGORIES[category_index]
	var sample_words: Array = FALLING_GRAMMAR_SAMPLES[category]
	var grammar_word: String = sample_words[rng.randi_range(0, sample_words.size() - 1)]
	var card_height: float = rng.randf_range(50.0, 60.0)
	var card_width: float = clampf(42.0 + float(grammar_word.length()) * 15.0, 74.0, 180.0)
	card.size = Vector2(card_width, card_height)
	card.pivot_offset = card.size * 0.5
	var viewport_width: float = maxf(falling_layer.size.x, 1280.0)
	card.position = Vector2(rng.randf_range(20.0, maxf(21.0, viewport_width - card_width - 20.0)), -card_height - 22.0)
	card.rotation = rng.randf_range(-0.20, 0.20)

	var letter: Label = card.get_node("Letter") as Label
	letter.text = grammar_word
	var word_font_size := int(card_height * 0.43)
	if grammar_word.length() >= 8:
		word_font_size = int(card_height * 0.36)
	elif grammar_word.length() >= 6:
		word_font_size = int(card_height * 0.40)
	letter.add_theme_font_size_override("font_size", word_font_size)

	# Each part of speech keeps one color, while the visible text is an
	# actual example of that category instead of the category name itself.
	var style: StyleBoxFlat = card.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var falling_style: StyleBoxFlat = style.duplicate() as StyleBoxFlat
		falling_style.bg_color = FALLING_GRAMMAR_COLORS[category_index]
		var corner := maxi(10, int(card_height * 0.22))
		falling_style.corner_radius_top_left = corner
		falling_style.corner_radius_top_right = corner
		falling_style.corner_radius_bottom_right = corner
		falling_style.corner_radius_bottom_left = corner
		card.add_theme_stylebox_override("panel", falling_style)

	var fall_duration: float = rng.randf_range(5.0, 7.2)
	var target_x: float = clampf(card.position.x + rng.randf_range(-150.0, 150.0), 18.0, viewport_width - card_width - 18.0)
	var target_rotation: float = card.rotation + rng.randf_range(-1.65, 1.65)
	var target_y: float = maxf(get_viewport_rect().size.y + 80.0, 800.0)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "position", Vector2(target_x, target_y), fall_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(card, "rotation", target_rotation, fall_duration).set_trans(Tween.TRANS_LINEAR)
	tween.chain().tween_callback(card.queue_free)


func _setup_panel_host() -> void:
	panel_host = Control.new()
	panel_host.name = "PanelHost"
	panel_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_host.z_index = 50
	panel_host.visible = false
	add_child(panel_host)
	# Adding a child to a container-less Control before layout has settled can
	# leave the overlay at zero size; resize it after the parent is in the tree.
	panel_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_main_navigation(route: String) -> void:
	if not intro_done:
		return
	_on_panel_requested(route, {})


func _on_panel_requested(route: String, payload: Dictionary = {}) -> void:
	# A fresh round must not inherit fake prototype points from an older demo.
	var fresh_round := route in ["retry", "play_again", "restart", "change_activity", "last_play"]
	if current_route == "results" and route == "student_setup":
		# Game Over Retry retains the student/setup, never the finished score.
		fresh_round = true
	if route == "ready" and current_route == "pause":
		fresh_round = true
	if current_route in ["results", "pause"] and route in ["play_activity", "play_topic", "play_difficulty"]:
		fresh_round = true
	if route == "pause" and current_route == "gameplay" and payload.is_empty() and is_instance_valid(active_panel):
		if active_panel.has_method("get_context"):
			payload = active_panel.call("get_context")
	if route == "quit":
		get_tree().quit()
		return
	if route == "main":
		_return_to_main()
		return
	if route == "last_play":
		route = "student_setup"
	if route == "retry" or route == "play_again":
		route = "student_setup"
	if route == "change_topic":
		route = "play_topic"
	if route == "change_activity":
		route = "play_activity"

	for key in payload:
		session_state[key] = payload[key]
	if route == "student_setup":
		if current_route == "main" or bool(payload.get("fresh_setup", false)):
			# Opening Play from the menu always starts with EMPTY fields.
			session_state = {"entry_source": "play", "demo_mode": true, "student_setup_prefill": false}
		else:
			# Retry or Back from activity must preserve the editable student form.
			session_state["student_setup_prefill"] = true
	if fresh_round:
		for stat_key in ["score", "streak", "best_streak", "correct", "attempts", "total", "accuracy", "time_remaining", "lives", "misses", "round_completed", "completion_reason", "round_reason", "gameplay_implemented", "body_x", "catch_collected_words", "round_running"]:
			session_state.erase(stat_key)
	if route == "tutorial_home":
		session_state["entry_source"] = "tutorial"
	elif route == "play_activity":
		session_state["entry_source"] = "play"
	# Ready is already a pre-game screen. Warm ONLY the upcoming Catch round's
	# imported assets in the background while the user checks position/counts
	# down; keep the references alive when the Ready panel is freed on START.
	if route == "ready":
		_prepare_catch_assets_for_ready()
	_show_panel(route)


func _prepare_catch_assets_for_ready() -> void:
	if String(session_state.get("activity", "")) != "Catch the Word":
		if is_instance_valid(catch_asset_preloader):
			catch_asset_preloader.call("clear_selection")
		return
	# Catch chooses these at random only when none were explicitly supplied.
	# Resolve the same random choice just before Ready to preload ONLY one
	# character pair and one map, then pass it unchanged to live gameplay.
	var characters := ["Boy", "Girl", "Grandma", "Grandpa"]
	var maps := ["City", "Forest", "Mountain"]
	var character := String(session_state.get("catch_character", ""))
	var map_name := String(session_state.get("catch_map", ""))
	if not characters.has(character):
		character = String(characters.pick_random())
		session_state["catch_character"] = character
	if not maps.has(map_name):
		map_name = String(maps.pick_random())
		session_state["catch_map"] = map_name
	if not is_instance_valid(catch_asset_preloader):
		catch_asset_preloader = CATCH_PRELOADER_SCRIPT.new() as Node
		catch_asset_preloader.name = "CatchAssetPreloader"
		add_child(catch_asset_preloader)
	catch_asset_preloader.call("prepare", character, map_name)


func _show_panel(route: String) -> void:
	if route == "gameplay" and current_route == "pause" and is_instance_valid(paused_game_panel):
		# Resume the exact game instance, including its live physics/question state.
		if is_instance_valid(active_panel):
			panel_host.remove_child(active_panel)
			active_panel.queue_free()
		active_panel = paused_game_panel
		paused_game_panel = null
		active_panel.visible = true
		active_panel.process_mode = Node.PROCESS_MODE_INHERIT
		if active_panel.has_method("_resume"):
			active_panel.call("_resume")
		current_route = "gameplay"
		return
	if not PANEL_SCENES.has(route):
		push_warning("Unknown KilosGrammar panel route: " + route)
		return
	var path: String = PANEL_SCENES[route]
	if not ResourceLoader.exists(path):
		push_warning("Panel is not available yet: " + path)
		return
	var panel_scene: PackedScene = load(path) as PackedScene
	if panel_scene == null:
		push_warning("Cannot load KilosGrammar panel: " + path)
		return

	if route == "pause" and current_route == "gameplay" and is_instance_valid(active_panel):
		# The game already emitted its pause event and froze its own timers.
		# Disable its entire scene to suspend even queued node/physics updates.
		paused_game_panel = active_panel
		paused_game_panel.process_mode = Node.PROCESS_MODE_DISABLED
		paused_game_panel.visible = false
	else:
		# Any other navigation from Pause (Results, Restart, Setup) ends the
		# suspended game rather than leaving it active in the background.
		_discard_paused_game()
		if is_instance_valid(active_panel):
			panel_host.remove_child(active_panel)
			active_panel.queue_free()
	active_panel = panel_scene.instantiate() as Control
	if active_panel == null:
		push_error("Expected a Control scene: " + path)
		return
	panel_host.visible = true
	logo_group.visible = false
	left_menu.visible = false
	center_menu.visible = false
	tooltip.visible = false
	if version:
		version.visible = false
	panel_host.add_child(active_panel)
	active_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if active_panel.has_signal("requested"):
		active_panel.connect("requested", Callable(self, "_on_panel_requested"))
	if active_panel.has_method("set_context"):
		active_panel.call("set_context", session_state.duplicate(true))
	current_route = route


func _return_to_main() -> void:
	if is_instance_valid(catch_asset_preloader):
		catch_asset_preloader.call("clear_selection")
	_discard_paused_game()
	if is_instance_valid(active_panel):
		panel_host.remove_child(active_panel)
		active_panel.queue_free()
	active_panel = null
	panel_host.visible = false
	logo_group.visible = true
	left_menu.visible = true
	center_menu.visible = true
	tooltip.visible = false
	if version:
		version.visible = true
	current_route = "main"
	$MainLayer/CenterMenu/Play.call_deferred("grab_focus")


func _discard_paused_game() -> void:
	if is_instance_valid(paused_game_panel):
		panel_host.remove_child(paused_game_panel)
		paused_game_panel.queue_free()
	paused_game_panel = null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if current_route == "main":
			return
		if current_route == "gameplay":
			# ESC must call the same game pause hook as its on-screen button;
			# switching panels directly used to bypass the physics freeze.
			if is_instance_valid(active_panel) and active_panel.has_method("_pause"):
				active_panel.call("_pause")
			else:
				_on_panel_requested("pause", {})
		elif current_route == "pause":
			_on_panel_requested("gameplay", {})
		else:
			var previous_routes := {
				"play_activity": "student_setup",
				"student_setup": "main",
				"play_topic": "play_activity",
				"play_difficulty": "play_topic",
				"camera_check": "tutorial_home" if session_state.get("entry_source", "play") == "tutorial" else ("play_activity" if bool(session_state.get("setup_preview", false)) else "play_difficulty"),
				"calibration": "camera_check",
				"tutorial_practice": "calibration" if bool(session_state.get("from_calibration", false)) else "tutorial_home",
				"grammar_guide": "tutorial_home",
				"ready": "play_activity" if bool(session_state.get("keyboard_mode", false)) else "camera_check"
			}
			_on_panel_requested(String(previous_routes.get(current_route, "main")), {})
		get_viewport().set_input_as_handled()
