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
const SETTINGS_PREFS: Script = preload("res://ui/secondary/settings.gd")
const POSTGRES_CLIENT_PATH := "res://ui/database/postgres_client.gd"
const LOCAL_DATABASE_SETUP_PATH := "res://database/setup_from_game.ps1"
const BUTTON_SOUND_WIRING: Script = preload("res://ui/shared/button_sound_wiring.gd")
const BUTTON_HOVER: AudioStream = preload("res://assets/audio/lexispell_intro/button_hover.wav")
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
# falling word cards and title music continue to be reused. The normal
# system mouse cursor remains visible across the main menu and UI panels.
const PANEL_SCENES := {
	"tutorial_home": "res://ui/tutorial/tutorial_home.tscn",
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
# Database requests are asynchronous. No SQL or credentials live in Godot,
# and the classroom can still play when the local service is offline.
var database_client: Node
var database_online := false
var database_registration_pending := false
var database_registration_confirmed := false
var database_pending_route: Dictionary = {}
var database_save_ticket := 0
var database_pending_lookup_id := ""
var database_setup_required := false
var database_connection_epoch := 0
var database_latest_leaderboard_request_id := -1
var database_transfer_ticket := 0

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
var button_sounds: Node
var logo_bump_active := false
var tooltip_tween: Tween
const TOOLTIP_GAP := 24.0
var _shutting_down := false
var _shutdown_audio_prepared := false
var _shutdown_audio_drain_complete := false


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
	# Keep the default operating-system pointer; do not replace or hide it.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# A window close needs the same mixer drain as the Quit button. Otherwise
	# cached MP3/WAV playback may still own ObjectDB/RID resources at exit.
	get_tree().auto_accept_quit = false
	rng.seed = 260926
	_setup_panel_host()
	# Use the original layered main panel, not the flattened logo artwork.
	# Individual GRAMMAR tiles must remain visible for their pop animations and
	# falling grammar cards must remain fully opaque behind the buttons.
	# The Kilos TextureRect dimensions come from the editor scene.
	logo_home = logo_group.position
	left_home = left_menu.position
	center_home = center_menu.position
	_ensure_audio_buses()
	button_sounds = BUTTON_SOUND_WIRING.new()
	button_sounds.name = "ButtonSounds"
	add_child(button_sounds)
	button_sounds.call("watch", $MainLayer)
	button_sounds.call("watch", panel_host)
	# Every fresh launch starts fullscreen. Restore only mixer and mute settings:
	# an old saved "windowed" preference must not undo the launch mode.
	SETTINGS_PREFS.apply_display_mode(true)
	SETTINGS_PREFS.restore_saved_preferences(false)
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
	_start_database_client()
	_register_logo_interactions()

	fall_timer.timeout.connect(_spawn_falling_grammar_card)
	tooltip.z_index = 40
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.visible = false
	call_deferred("_play_intro")


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
	if _shutting_down or not is_inside_tree():
		return
	_play_one_shot(stream, pitch, volume_db)


func _play_one_shot(stream: AudioStream, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if _shutting_down:
		return
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


func _hover_button(button: Button) -> void:
	button.z_index = 20
	_kill_button_tween(button)
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
	var tween: Tween = create_tween()
	button_tweens[button] = tween
	tween.tween_property(button, "scale", Vector2(0.94, 0.90), 0.055).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _release_button(button: Button) -> void:
	var hovered: bool = button.get_global_rect().has_point(get_viewport().get_mouse_position())
	if hovered:
		_hover_button(button)
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
	var restarting_round := current_route == "pause" and route in ["restart", "ready"]
	var fresh_round := route in ["retry", "play_again", "restart", "change_activity", "last_play"]
	var ordinary_reentry := route in ["retry", "play_again", "last_play", "change_activity"] or (current_route in ["results", "pause"] and route in ["student_setup", "play_activity", "play_topic", "play_difficulty"])
	if current_route == "results" and route == "student_setup":
		# Game Over Retry retains the student/setup, never the finished score.
		fresh_round = true
	if route == "ready" and current_route == "pause":
		fresh_round = true
	if current_route in ["results", "pause"] and route in ["play_activity", "play_topic", "play_difficulty"]:
		fresh_round = true
	if restarting_round:
		# The previous Pause -> Ready path normalized to Gameplay but
		# accidentally triggered _show_panel's Resume branch. Throw away its
		# saved stats, question history and instance before routing to NEW play.
		payload = _restart_setup_context(payload)
		payload["start_countdown"] = true
		payload["guided_tutorial"] = false
		payload["round_completed"] = false
		database_save_ticket += 1
		if is_instance_valid(paused_game_panel):
			if paused_game_panel.has_method("preserve_camera_for_restart"):
				paused_game_panel.call("preserve_camera_for_restart")
			_discard_paused_game()
		session_state = payload.duplicate(true)
		route = "gameplay"
		fresh_round = true
	if route == "pause" and current_route == "gameplay" and payload.is_empty() and is_instance_valid(active_panel):
		if active_panel.has_method("get_context"):
			payload = active_panel.call("get_context")
	if route == "quit":
		_request_clean_quit()
		return
	if route == "main":
		_return_to_main()
		return
	# A teacher's Continue action registers a new student ID only if the
	# local service is available. An existing ID cannot silently overwrite a
	# registered student's name or grade/section. Offline play stays possible.
	if current_route == "student_setup" and route in ["play_activity", "calibration"] and payload.has("student_id"):
		if database_registration_pending:
			return
		if not database_registration_confirmed and database_online and is_instance_valid(database_client):
			database_registration_pending = true
			database_pending_route = {"route": route, "payload": payload.duplicate(true)}
			_database_student_status("CHECKING STUDENT REGISTRATION • Please keep this screen open.")
			database_client.call("register_student", String(payload.get("student_id", "")),
				String(payload.get("student_name", "")), String(payload.get("grade_section", "")),
				{"purpose": "registration"})
			return
		payload = payload.duplicate(true)
		payload["database_connected"] = database_online and database_registration_confirmed
	# Calibration owns the camera preview for both entry flows. The old
	# camera-check Back action should reopen game selection, where teachers
	# can change activities without discarding their completed setup.
	if route == "camera_check" and current_route == "calibration":
		route = "student_setup" if bool(session_state.get("guided_tutorial", false)) else "play_activity"
	# Normalize all pre-game starts through a single game-owned countdown.
	# Students must calibrate with a real camera; never bypass into a
	# keyboard/demo session through legacy setup routes.
	if route == "ready" and current_route == "play_activity":
		route = "calibration"
		payload = payload.duplicate(true)
		payload["keyboard_mode"] = false
		payload["camera_requested"] = true
	elif route == "ready":
		route = "gameplay"
		payload = payload.duplicate(true)
		payload["start_countdown"] = true
	elif route == "gameplay" and current_route == "calibration":
		# Calibration may emit gameplay directly after a successful live
		# capture; keep the countdown contract independent of that signal name.
		payload = payload.duplicate(true)
		payload["start_countdown"] = true
	if PoseService.active and route in ["student_setup", "play_activity", "play_topic", "play_difficulty", "results", "tutorial_home", "quit"]:
		PoseService.stop_camera()
	if route == "last_play":
		route = "student_setup"
	if route == "retry" or route == "play_again":
		route = "student_setup"
	if route == "change_topic":
		route = "play_topic"
	if route == "change_activity":
		route = "play_activity"

	# Guided Tutorial enters the game selection before student/teacher setup.
	# Clear old round/student values when launching a new guided session, then
	# carry its flag and selected activity across every subsequent panel.
	if route == "play_activity" and current_route == "tutorial_home" and bool(payload.get("guided_tutorial", false)):
		session_state = {"entry_source": "tutorial", "guided_tutorial": true, "demo_mode": true}
	for key in payload:
		session_state[key] = payload[key]
	if ordinary_reentry and not bool(payload.get("guided_retry", false)):
		# Results and pause actions start ordinary Play sessions even when their
		# previous game context contained a guided_tutorial flag.
		session_state.erase("guided_tutorial")
		session_state["entry_source"] = "play"
	if route == "student_setup":
		if current_route == "main" or (bool(payload.get("fresh_setup", false)) and not bool(session_state.get("guided_tutorial", false))):
			# Opening Play from the menu always starts with EMPTY fields.
			session_state = {"entry_source": "play", "demo_mode": true, "student_setup_prefill": false}
		elif bool(session_state.get("guided_tutorial", false)) and current_route == "play_activity":
			# Keep the chosen game while the learner/teacher fields start empty.
			session_state["student_setup_prefill"] = false
		else:
			# Retry or Back from activity must preserve the editable student form.
			session_state["student_setup_prefill"] = true
	if fresh_round:
		for stat_key in ["score", "streak", "best_streak", "correct", "attempts", "total", "accuracy", "time_remaining", "lives", "misses", "round_completed", "completion_reason", "round_reason", "gameplay_implemented", "body_x", "catch_collected_words", "round_running"]:
			session_state.erase(stat_key)
	if route == "tutorial_home":
		session_state["entry_source"] = "tutorial"
	elif route == "play_activity":
		session_state["entry_source"] = "tutorial" if bool(session_state.get("guided_tutorial", false)) else "play"
	# Preload the selected Catch artwork before the shared pre-game countdown.
	if route == "gameplay" and current_route != "pause":
		_prepare_catch_assets_for_ready()
	# Saving is attempted only when a live minigame reports a *completed*
	# round, never when a teacher opens Results from a paused/aborted round.
	var completed_round := route == "results" and current_route == "gameplay" \
		and bool(payload.get("round_completed", false)) and payload.has("score")
	if completed_round:
		session_state["score_saved"] = false
		session_state["database_connected"] = database_online
		session_state["database_saving"] = database_online
	elif route == "results":
		# Viewing an aborted/paused round's Results invalidates any older
		# asynchronous score-save callback. It must never mark these results
		# as a successful completed-round save from a previous game.
		database_save_ticket += 1
		session_state["score_saved"] = false
		session_state["database_saving"] = false
		session_state["database_connected"] = database_online
	_show_panel(route)
	if route == "leaderboard":
		_load_database_leaderboard()
	elif completed_round:
		_save_completed_round()


func _restart_setup_context(snapshot: Dictionary) -> Dictionary:
	# Allowlist only teacher/student configuration and measured camera setup.
	# Never replay gameplay-specific saved apples, words, waves, elapsed time,
	# scores, shots, or completion fields from the just-discarded round.
	var source := session_state.duplicate(true)
	source.merge(snapshot, true)
	var fresh: Dictionary = {}
	for key in [
		"student_id", "student_name", "grade_section", "activity", "topic",
		"game_style", "game_mode", "difficulty", "catch_character", "catch_map",
		"entry_source", "demo_mode", "database_connected", "camera_live",
		"camera_requested", "keyboard_mode", "calibration_valid",
		"calibration_live", "calibration_measured", "calibration_left",
		"calibration_center", "calibration_right", "from_calibration",
		"teacher_authorized", "student_setup_prefill"
	]:
		if source.has(key):
			fresh[key] = source[key]
	return fresh


func _start_database_client() -> void:
	if not ResourceLoader.exists(POSTGRES_CLIENT_PATH):
		return
	var script := load(POSTGRES_CLIENT_PATH) as Script
	if script == null:
		return
	database_client = script.new() as Node
	if database_client == null:
		return
	database_client.name = "LocalPostgreSQLClient"
	add_child(database_client)
	database_client.connect("request_finished", Callable(self, "_on_database_request_finished"))
	if database_client.has_signal("local_service_status_changed"):
		database_client.connect("local_service_status_changed", Callable(self, "_on_database_local_service_status_changed"))
	if database_client.has_method("ensure_local_service"):
		database_client.call("ensure_local_service", {"purpose": "startup"})
	else:
		database_client.call("check_health", {"purpose": "startup"})


func _ensure_database_service() -> void:
	if not is_instance_valid(database_client):
		return
	if database_client.has_method("ensure_local_service"):
		database_client.call("ensure_local_service", {"purpose": "reconnect"})
	else:
		database_client.call("check_health", {"purpose": "startup"})


func _on_database_local_service_status_changed(state: String, details: Dictionary) -> void:
	# Health probes are internal to the nonblocking launcher. Update the UI
	# only on lifecycle signals so it does not flash OFFLINE between retries.
	if state in ["checking", "starting", "retrying"]:
		if not database_online:
			_database_student_status("CONNECTING TO LOCAL POSTGRESQL • Checking the local database...")
		return
	if state == "online":
		if not database_online:
			database_connection_epoch += 1
		database_online = true
		database_setup_required = false
		_database_student_status("LOCAL POSTGRESQL CONNECTED • Student profiles and completed scores can be saved.", true)
		if current_route == "leaderboard":
			_request_database_leaderboard()
		elif current_route == "student_setup" and not database_pending_lookup_id.is_empty() \
			and is_instance_valid(active_panel):
			var id_field := active_panel.get("_student_id_edit") as LineEdit
			var requested_id := database_pending_lookup_id
			database_pending_lookup_id = ""
			if id_field != null and id_field.text.strip_edges() == requested_id:
				_lookup_student_in_database(requested_id)
		return
	if state == "offline":
		database_transfer_ticket += 1 # Ignore any now-ambiguous CSV/delete callbacks.
		if current_route == "leaderboard" and is_instance_valid(active_panel) \
				and active_panel.has_method("set_transfer_status"):
			active_panel.call("set_transfer_status",
				"Connection lost. Any pending import/delete outcome is unknown; check saved records after reconnection.")
		if database_online:
			database_connection_epoch += 1
		database_online = false
		database_pending_lookup_id = ""
		var reason := String(details.get("reason", ""))
		database_setup_required = reason in ["setup_required", "database_auth_or_schema"]
		var hint := "Press SET UP LOCAL DATABASE to finish secure configuration." if database_setup_required \
			else "Connection lost. The local service will retry automatically."
		_database_student_status("LOCAL POSTGRESQL OFFLINE • %s Completed scores will not save." % hint, false, database_setup_required)
		if current_route == "leaderboard":
			_set_leaderboard_database_rows([], false)


func _database_student_status(message: String, connected: bool = false, setup_required: bool = false) -> void:
	if current_route == "student_setup" and is_instance_valid(active_panel) \
		and active_panel.has_method("show_database_status"):
		active_panel.call("show_database_status", message, connected, setup_required)


func _on_database_setup_requested() -> void:
	# Setup must be an explicit teacher action: never open an interactive
	# PowerShell window without a user pressing the authored Setup button.
	if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless":
		_database_student_status("LOCAL DATABASE SETUP • Available on the Windows computer running Godot.", false, true)
		return
	# Exported builds must invoke the physical file next to the EXE, not
	# a virtual `res://` path into Godot's packed resource archive.
	var path := OS.get_executable_path().get_base_dir().path_join("database/setup_from_game.ps1")
	if not FileAccess.file_exists(path):
		path = ProjectSettings.globalize_path(LOCAL_DATABASE_SETUP_PATH)
	if not FileAccess.file_exists(path):
		_database_student_status("LOCAL DATABASE SETUP UNAVAILABLE • Check database/setup_from_game.ps1.", false, true)
		return
	var args := PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
		"-ExecutionPolicy", "Bypass", "-File", path,
	])
	var pid := OS.create_process("powershell.exe", args, false)
	if pid <= 0:
		_database_student_status("CANNOT OPEN LOCAL SETUP • Windows PowerShell is unavailable.", false, true)
		return
	_database_student_status("SECURE SETUP WINDOW OPENED • Follow the teacher prompts. The game will reconnect automatically.", false, true)


func _on_database_retry_requested() -> void:
	_database_student_status("RECONNECTING • Checking the local PostgreSQL service...")
	_ensure_database_service()


func _lookup_student_in_database(student_id: String) -> void:
	if not is_instance_valid(database_client):
		_database_student_status("LOCAL DATABASE UNAVAILABLE • Ask your teacher to start PostgreSQL.")
		return
	if database_online:
		database_client.call("find_student", student_id, {"purpose": "student_lookup"})
	else:
		if database_client.has_method("ensure_local_service"):
			database_pending_lookup_id = student_id.strip_edges()
			_ensure_database_service()
		else:
			database_client.call("check_health", {"purpose": "lookup_health", "student_id": student_id})


func _load_database_leaderboard() -> void:
	if current_route != "leaderboard" or not is_instance_valid(active_panel):
		return
	var state := session_state.duplicate(true)
	state["database_connected"] = database_online
	state["database_loading"] = is_instance_valid(database_client)
	state["leaderboard_rows"] = []
	state["teacher_authorized"] = _has_local_database_admin_access()
	active_panel.call("set_context", state)
	if not is_instance_valid(database_client):
		return
	if database_online:
		_request_database_leaderboard()
	else:
		if database_client.has_method("ensure_local_service"):
			_ensure_database_service()
		else:
			database_client.call("check_health", {"purpose": "leaderboard_health"})


func _request_database_leaderboard() -> void:
	if is_instance_valid(database_client):
		# No filters: the existing editor-authored controls filter actual data
		# locally without issuing dozens of separate requests each time.
		database_latest_leaderboard_request_id = int(database_client.call(
			"get_leaderboard", "", "", "", "",
			{"purpose": "leaderboard", "epoch": database_connection_epoch}))


func _has_local_database_admin_access() -> bool:
	# A configured local Windows user owns the private service token; there is
	# no hardcoded teacher PIN or unconditional admin bypass in the student UI.
	# The server separately verifies the token for each CSV/destructive request.
	return database_online and is_instance_valid(database_client) \
		and database_client.has_method("has_local_admin_token") \
		and bool(database_client.call("has_local_admin_token"))


func _leaderboard_management_context() -> Dictionary:
	return {"purpose": "leaderboard_management", "epoch": database_connection_epoch,
		"panel_id": active_panel.get_instance_id() if is_instance_valid(active_panel) else -1,
		"ticket": database_transfer_ticket}


func _is_current_leaderboard_management(info: Dictionary) -> bool:
	return database_online and current_route == "leaderboard" and is_instance_valid(active_panel) \
		and int(info.get("epoch", -1)) == database_connection_epoch \
		and int(info.get("ticket", -1)) == database_transfer_ticket \
		and int(info.get("panel_id", -1)) == active_panel.get_instance_id()


func _leaderboard_management_status(message: String, success: bool = false) -> void:
	if current_route == "leaderboard" and is_instance_valid(active_panel) \
			and active_panel.has_method("set_transfer_status"):
		active_panel.call("set_transfer_status", message, success)


func _leaderboard_management_pending(message: String) -> void:
	if current_route == "leaderboard" and is_instance_valid(active_panel):
		if active_panel.has_method("set_processing"):
			active_panel.call("set_processing", message)
		elif active_panel.has_method("set_transfer_status"):
			active_panel.call("set_transfer_status", message)


func _on_database_export_csv_requested(path: String) -> void:
	if not database_online or not is_instance_valid(database_client):
		_leaderboard_management_status("Local database is offline. Nothing was exported.")
		return
	if path.get_extension().to_lower() != "csv" or path.is_empty():
		_leaderboard_management_status("Choose a .csv file to export the complete database.")
		return
	database_transfer_ticket += 1
	_leaderboard_management_pending("Preparing full database CSV export...")
	var context := _leaderboard_management_context()
	context["path"] = path
	database_client.call("export_data_csv", context)


func _on_database_import_csv_requested(path: String) -> void:
	if not database_online or not is_instance_valid(database_client):
		_leaderboard_management_status("Local database is offline. Nothing was imported.")
		return
	if path.get_extension().to_lower() != "csv" or path.is_empty():
		_leaderboard_management_status("Choose a valid .csv file. Nothing was changed.")
		return
	var csv_file := FileAccess.open(path, FileAccess.READ)
	if csv_file == null:
		_leaderboard_management_status("Could not read the selected CSV file. Nothing was changed.")
		return
	if csv_file.get_length() < 1 or csv_file.get_length() > 1_000_000:
		csv_file.close()
		_leaderboard_management_status("CSV must contain data and be 1 MB or smaller. Nothing was changed.")
		return
	var csv_text := csv_file.get_as_text()
	csv_file.close()
	database_transfer_ticket += 1
	_leaderboard_management_pending("Validating and importing CSV. This may take a moment...")
	database_client.call("import_data_csv", csv_text, _leaderboard_management_context())


func _on_database_delete_all_requested(confirmation: String) -> void:
	if not database_online or not is_instance_valid(database_client):
		_leaderboard_management_status("Local database is offline. Nothing was deleted.")
		return
	if confirmation != "DELETE ALL DATA":
		_leaderboard_management_status("Delete cancelled. Type DELETE ALL DATA exactly to continue.")
		return
	database_transfer_ticket += 1
	_leaderboard_management_pending("Requesting secure, one-time deletion confirmation...")
	database_client.call("request_delete_all_challenge", _leaderboard_management_context())


func _handle_database_management_result(info: Dictionary, result: Dictionary) -> void:
	if not _is_current_leaderboard_management(info):
		return # Never write an export or delete based on an old screen/connection.
	var operation := String(info.get("operation", ""))
	var successful := bool(result.get("ok", false))
	var data: Dictionary = result.get("data", {}) if result.get("data", {}) is Dictionary else {}
	if not successful:
		var message := String(result.get("message", "")).strip_edges()
		if message.is_empty():
			message = "Local database rejected the request. No success was recorded."
		_leaderboard_management_status("Database operation failed: " + message.left(160))
		return
	if operation == "export_data_csv":
		var csv_data := String(data.get("csv", ""))
		var filename := String(info.get("path", ""))
		if csv_data.is_empty() or csv_data.to_utf8_buffer().size() > 1_500_000 \
				or filename.get_extension().to_lower() != "csv":
			_leaderboard_management_status("Export data was invalid. No file was written.")
			return
		var target := FileAccess.open(filename, FileAccess.WRITE)
		if target == null:
			_leaderboard_management_status("Could not write to the selected file. Try another location.")
			return
		target.store_string(csv_data)
		target.flush()
		var write_error := target.get_error()
		target.close()
		if write_error != OK:
			_leaderboard_management_status("Could not finish writing the CSV. Please try again.")
		else:
			_leaderboard_management_status("Full CSV export saved: %d students, %d scores." % [
				int(data.get("students", 0)), int(data.get("scores", 0))], true)
		return
	if operation == "import_data_csv":
		_leaderboard_management_status("CSV imported: %d new students, %d score records." % [
			int(data.get("students_created", 0)), int(data.get("scores_imported", 0))], true)
		_request_database_leaderboard()
		return
	if operation == "request_delete_all_challenge":
		var challenge := String(data.get("challenge", ""))
		if challenge.is_empty() or String(data.get("confirmation_phrase", "")) != "DELETE ALL DATA":
			_leaderboard_management_status("Secure deletion challenge failed. Nothing was deleted.")
			return
		database_client.call("delete_all_data", challenge, "DELETE ALL DATA",
			_leaderboard_management_context())
		return
	if operation == "delete_all_data":
		_leaderboard_management_status("Deleted %d student profiles and %d saved scores." % [
			int(data.get("students_deleted", 0)), int(data.get("scores_deleted", 0))], true)
		# Never keep a now-deleted student's identity in the next game session.
		for key in ["student_id", "student_name", "grade_section", "student_lookup_connected"]:
			session_state.erase(key)
		_request_database_leaderboard()



func _save_completed_round() -> void:
	if current_route != "results" or not is_instance_valid(active_panel):
		return
	database_save_ticket += 1
	var state := session_state.duplicate(true)
	state["score_saved"] = false
	state["database_saving"] = false
	if database_online and is_instance_valid(database_client) \
		and not String(state.get("student_id", "")).strip_edges().is_empty():
		state["database_saving"] = true
		session_state["database_saving"] = true
		database_client.call("complete_round",
			String(state.get("student_id", "")),
			String(state.get("game_style", state.get("topic", ""))),
			String(state.get("game_mode", "")),
			String(state.get("difficulty", "")),
			maxi(int(state.get("score", 0)), 0),
				{"purpose": "completed_round", "ticket": database_save_ticket,
					"minigame": String(state.get("activity", ""))})
	active_panel.call("set_context", state)


func _on_database_request_finished(info: Dictionary, result: Dictionary) -> void:
	var operation := String(info.get("operation", ""))
	var purpose := String(info.get("purpose", ""))
	var successful := bool(result.get("ok", false))
	var data: Dictionary = result.get("data", {}) if result.get("data", {}) is Dictionary else {}
	if operation in ["export_data_csv", "import_data_csv", "request_delete_all_challenge", "delete_all_data"]:
		_handle_database_management_result(info, result)
		return
	if operation == "health":
		if bool(info.get("local_service_probe", false)):
			return # Lifecycle signal handles automatic health retries.
		var was_online := database_online
		database_online = successful and String(data.get("database", "")) == "connected"
		if was_online != database_online:
			database_connection_epoch += 1
		if purpose == "leaderboard_health":
			if database_online:
				_request_database_leaderboard()
			else:
				_set_leaderboard_database_rows([], false)
		elif purpose == "lookup_health":
			if database_online:
				_lookup_student_in_database(String(info.get("student_id", "")))
			else:
				_database_student_status("LOCAL POSTGRESQL UNAVAILABLE • No profile was searched.")
		elif current_route == "student_setup":
			_database_student_status(
				"LOCAL POSTGRESQL CONNECTED • Enter an ID to search, or continue to register."
				if database_online else "LOCAL POSTGRESQL OFFLINE • You may play, but scores cannot be saved.",
				database_online)
		return
	if operation == "find_student":
		if current_route != "student_setup" or not is_instance_valid(active_panel):
			return
		if successful and data.get("student", null) is Dictionary:
			var student: Dictionary = (data["student"] as Dictionary).duplicate(true)
			student["lookup_confirmed"] = true
			active_panel.call("apply_lookup_result", student)
		elif String(result.get("error", "")) == "student_not_found":
			_database_student_status("STUDENT ID NOT FOUND • Enter name and grade, then Continue to register.", true)
		else:
			_database_student_status("STUDENT LOOKUP FAILED • Please check the local database.")
		return
	if operation == "register_student":
		if not database_registration_pending or database_pending_route.is_empty():
			return
		var pending := database_pending_route.duplicate(true)
		database_registration_pending = false
		database_pending_route.clear()
		# A delayed request must never move the teacher to another screen or
		# register a different ID after they edited/backed out of this form.
		if current_route != "student_setup" or not is_instance_valid(active_panel):
			return
		var id_field := active_panel.get("_student_id_edit") as LineEdit
		var name_field := active_panel.get("_name_edit") as LineEdit
		var grade_field := active_panel.get("_grade_edit") as LineEdit
		var expected: Dictionary = pending["payload"]
		if id_field == null or name_field == null or grade_field == null \
			or id_field.text.strip_edges() != String(expected.get("student_id", "")) \
			or name_field.text.strip_edges() != String(expected.get("student_name", "")) \
			or grade_field.text.strip_edges() != String(expected.get("grade_section", "")):
			_database_student_status("STUDENT DETAILS CHANGED • Please press CONTINUE again to verify the current student.")
			return
		if successful and data.get("student", null) is Dictionary:
			var payload: Dictionary = pending["payload"]
			payload["database_connected"] = true
			payload["student_lookup_connected"] = true
			database_registration_confirmed = true
			_on_panel_requested(String(pending["route"]), payload)
			database_registration_confirmed = false
		elif String(result.get("error", "")) in ["student_exists", "student_conflict"]:
			_database_student_status("STUDENT ID ALREADY REGISTERED • Use LOOK UP first; existing identity was NOT overwritten.")
		elif String(result.get("error", "")) in ["connection_error", "database_unavailable", "schema_not_ready"]:
			# Losing the local DB must never trap a classroom in student setup.
			# The round may continue, but its result will be explicitly unsaved.
			database_online = false
			var offline: Dictionary = pending["payload"]
			offline["database_connected"] = false
			_on_panel_requested(String(pending["route"]), offline)
		else:
			_database_student_status("REGISTRATION FAILED • Please review the student ID, name, and grade.")
		return
	if operation == "get_leaderboard":
		# A delayed successful HTTP response cannot resurrect offline/stale
		# rankings after the connection dropped and a new epoch began.
		if int(info.get("epoch", -1)) != database_connection_epoch:
			return # Never erase a newer, valid result after reconnection.
		if info.has("request_id") and database_latest_leaderboard_request_id >= 0 \
			and int(info["request_id"]) != database_latest_leaderboard_request_id:
			return # Another leaderboard query superseded this response.
		if not database_online:
			_set_leaderboard_database_rows([], false)
			return
		var list: Array = data.get("leaderboard", []) if successful and data.get("leaderboard", []) is Array else []
		_set_leaderboard_database_rows(list, successful)
		return
	if operation == "complete_round":
		if int(info.get("ticket", -1)) != database_save_ticket or current_route != "results":
			return
		session_state["database_saving"] = false
		session_state["score_saved"] = successful and data.get("score", null) is Dictionary
		if not successful:
			session_state["database_connected"] = false
		if is_instance_valid(active_panel):
			active_panel.call("set_context", session_state.duplicate(true))


func _set_leaderboard_database_rows(rows: Array, connected: bool) -> void:
	if current_route != "leaderboard" or not is_instance_valid(active_panel):
		return
	var state := session_state.duplicate(true)
	state["database_connected"] = connected
	state["database_loading"] = false
	state["leaderboard_rows"] = rows
	state["teacher_authorized"] = _has_local_database_admin_access() if connected else false
	active_panel.call("set_context", state)


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
		button_sounds.call("reset_hover_origin", active_panel)
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
	if route == "student_setup":
		if active_panel.has_signal("student_lookup_requested"):
			active_panel.connect("student_lookup_requested", Callable(self, "_lookup_student_in_database"))
		if active_panel.has_signal("database_setup_requested"):
			active_panel.connect("database_setup_requested", Callable(self, "_on_database_setup_requested"))
		if active_panel.has_signal("database_retry_requested"):
			active_panel.connect("database_retry_requested", Callable(self, "_on_database_retry_requested"))
		if is_instance_valid(database_client):
			if database_online:
				database_client.call("check_health", {"purpose": "student_setup_health"})
			else:
				_ensure_database_service()
	if route == "leaderboard":
		if active_panel.has_signal("database_export_csv_requested"):
			active_panel.connect("database_export_csv_requested", Callable(self, "_on_database_export_csv_requested"))
		if active_panel.has_signal("database_import_csv_requested"):
			active_panel.connect("database_import_csv_requested", Callable(self, "_on_database_import_csv_requested"))
		if active_panel.has_signal("database_delete_all_requested"):
			active_panel.connect("database_delete_all_requested", Callable(self, "_on_database_delete_all_requested"))
	button_sounds.call("watch", active_panel)
	button_sounds.call("reset_hover_origin", active_panel)
	current_route = route
	if route == "student_setup" and database_setup_required and not database_online:
		_database_student_status("LOCAL POSTGRESQL NEEDS SETUP • Press SET UP LOCAL DATABASE below.", false, true)


func _return_to_main() -> void:
	database_registration_pending = false
	database_pending_route.clear()
	if PoseService.active:
		PoseService.stop_camera()
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
	button_sounds.call("reset_hover_origin", $MainLayer)
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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			SETTINGS_PREFS.toggle_fullscreen()
			if current_route == "settings" and is_instance_valid(active_panel) and active_panel.has_method("sync_fullscreen_state"):
				active_panel.call("sync_fullscreen_state")
			get_viewport().set_input_as_handled()
			return
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
					"play_activity": "tutorial_home" if bool(session_state.get("guided_tutorial", false)) else "student_setup",
					"student_setup": "play_activity" if bool(session_state.get("guided_tutorial", false)) else "main",
				"play_topic": "play_activity",
				"play_difficulty": "play_topic",
				"camera_check": "play_activity" if bool(session_state.get("guided_tutorial", false)) else ("play_activity" if bool(session_state.get("setup_preview", false)) else "play_difficulty"),
					"calibration": "student_setup" if bool(session_state.get("guided_tutorial", false)) else "play_activity",
				"grammar_guide": "tutorial_home",
				"ready": "calibration"
				}
			_on_panel_requested(String(previous_routes.get(current_route, "main")), {})
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_inside_tree():
		_request_clean_quit()


func _request_clean_quit() -> void:
	if _shutting_down:
		return
	# Suppress duplicate close events before the deferred mixer drain starts.
	_shutting_down = true
	call_deferred("_quit_after_audio_drain")


func _quit_after_audio_drain() -> void:
	await prepare_for_shutdown()
	if is_inside_tree():
		get_tree().quit()


func prepare_for_shutdown() -> void:
	# Also callable by isolated Godot regression tests before they queue_free()
	# a menu. Stopping after its scene is already freed is too late: Godot 4.7
	# may report lingering AudioStreamMP3/WAV playback instances at exit.
	if _shutdown_audio_prepared:
		return
	_shutdown_audio_prepared = true
	_shutting_down = true
	if is_instance_valid(fall_timer):
		fall_timer.stop()
	if is_instance_valid(logo_sequence_tween) and logo_sequence_tween.is_valid():
		logo_sequence_tween.kill()
	if is_instance_valid(tooltip_tween) and tooltip_tween.is_valid():
		tooltip_tween.kill()
	if is_instance_valid(panel_host):
		panel_host.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(button_sounds):
		# Focus/hover events must not schedule another SFX during mixer drain.
		button_sounds.set_process_input(false)
	if PoseService.active:
		PoseService.stop_camera()
	if is_instance_valid(catch_asset_preloader) and catch_asset_preloader.has_method("finish_pending_for_shutdown"):
		# A Catch round can be exited before its threaded Ready preloads finish.
		# Let ResourceLoader hand back its pending refs while its owner is alive.
		catch_asset_preloader.call("finish_pending_for_shutdown")
	# Gather BOTH the persistent title music and every temporary button/intro
	# one-shot, including nested players. Do not change bus preferences.
	var audio_players := find_children("*", "AudioStreamPlayer", true, false)
	for node in audio_players:
		var player := node as AudioStreamPlayer
		if not is_instance_valid(player):
			continue
		player.stop()
		player.stream = null
		player.queue_free()
	title_music_player = null
	audio_players.clear()
	if is_instance_valid(button_sounds):
		button_sounds.queue_free()
		button_sounds = null
	# Let the audio mixer's queued work retire WHILE Godot still processes
	# frames. Immediate stop/free followed by quit still leaks playback RIDs.
	await get_tree().create_timer(0.65).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	_shutdown_audio_drain_complete = true
