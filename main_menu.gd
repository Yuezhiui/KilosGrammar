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
const TITLE_MUSIC: AudioStream = preload("res://assets/audio/lexispell_intro/title_music.ogg")
const BUTTON_HOVER: AudioStream = preload("res://assets/audio/lexispell_intro/button_hover.wav")
const BUTTON_CLICK: AudioStream = preload("res://assets/audio/lexispell_intro/button_click.wav")

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


func _process(delta: float) -> void:
	if not intro_done:
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
	_sync_kilos_texture_rect()
	logo_home = logo_group.position
	left_home = left_menu.position
	center_home = center_menu.position
	_setup_title_music()

	for tile in grammar_tiles:
		grammar_home_positions[tile] = tile.position
		grammar_home_rotations[tile] = tile.rotation

	_register_left_button($MainLayer/LeftMenu/Leaderboard, "Global spelling scores and player rankings.", 0.015)
	_register_left_button($MainLayer/LeftMenu/Librarium, "Browse your collected words and discoveries.", -0.012)
	_register_left_button($MainLayer/LeftMenu/Settings, "Settings, controls and dictionaries.", 0.013)
	_register_left_button($MainLayer/LeftMenu/Credits, "Meet the people behind the game.", -0.012)

	_register_button($MainLayer/CenterMenu/Resume, -0.026)
	_register_button($MainLayer/CenterMenu/Play, 0.018)
	_register_button($MainLayer/CenterMenu/Quit, -0.016)
	_register_logo_interactions()

	fall_timer.timeout.connect(_spawn_falling_grammar_card)
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
		$MainLayer/LeftMenu/Librarium,
		$MainLayer/LeftMenu/Settings,
		$MainLayer/LeftMenu/Credits,
		$MainLayer/CenterMenu/Resume,
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
	fall_timer.start()
	for i in range(3):
		_spawn_falling_grammar_card()


func _reveal_intro_tile(tile: Control, pitch: float) -> void:
	tile.modulate.a = 1.0
	_play_one_shot(LETTER_POP, pitch, -5.0)


func _setup_title_music() -> void:
	title_music_player = AudioStreamPlayer.new()
	title_music_player.name = "TitleMusic"
	title_music_player.stream = TITLE_MUSIC
	title_music_player.volume_db = -32.0
	add_child(title_music_player)
	if title_music_player.stream is AudioStreamOggVorbis:
		(title_music_player.stream as AudioStreamOggVorbis).loop = true
	title_music_player.play()
	var fade: Tween = create_tween()
	fade.tween_property(title_music_player, "volume_db", -8.0, 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _schedule_sfx(stream: AudioStream, pitch: float, delay: float, volume_db: float = 0.0) -> void:
	await get_tree().create_timer(delay).timeout
	_play_one_shot(stream, pitch, volume_db)


func _play_one_shot(stream: AudioStream, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


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
	tooltip_label.text = copy
	var rect: Rect2 = button.get_global_rect()
	tooltip.global_position = Vector2(rect.end.x + 9.0, rect.position.y - 4.0)
	tooltip.pivot_offset = Vector2(0, tooltip.size.y * 0.5)
	tooltip.visible = true
	tooltip.scale = Vector2(0.82, 0.82)
	tooltip.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(tooltip, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(tooltip, "modulate:a", 1.0, 0.08)


func _hide_tooltip() -> void:
	if not tooltip.visible:
		return
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(tooltip, "scale", Vector2(0.88, 0.88), 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(tooltip, "modulate:a", 0.0, 0.08)
	await tween.finished
	tooltip.visible = false


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
