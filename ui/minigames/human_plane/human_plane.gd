extends Control

signal requested(target: String, payload: Dictionary)
signal tutorial_finished

const FONT := preload("res://assets/fonts/TitanOne-Regular.ttf")
const GRAMMAR_BANK_PATH := "res://ui/minigames/shared/grammar_bank.gd"

const SKY_TOP := Color("#80D7F5")
const SKY_BOTTOM := Color("#DFF5E8")
const INK := Color("#474660")
const CREAM := Color("#FDE4B9")
const MINT := Color("#74AB8E")
const GREEN := Color("#00886B")
const RED := Color("#FF4F66")
const YELLOW := Color("#FFC23D")
const BLUE := Color("#62B8E8")
const PURPLE := Color("#B477D2")
const WHITE := Color("#FFFDF5")

const LANE_COLORS := [PURPLE, MINT, BLUE]
const LANE_NAMES := ["LEFT", "CENTER", "RIGHT"]
const SECONDS_ROUND_DURATION := 60.0
const LIVES_ROUND_ALLOWANCE := 3
const POINTS_PER_CORRECT_GATE := 100
# Centered single-ring hits must cover most of the pilot hitbox. When the
# hitbox touches two rings, choose only a clear geometric winner; the answer's
# correctness never influences which lane is selected.
const RING_CENTER_WINDOW_RATIO := 0.30
const MIN_RING_HITBOX_COVERAGE := 0.70
const MIN_DOMINANT_HITBOX_COVERAGE := 0.50
const MIN_OVERLAP_LEAD_FRACTION := 0.20
# Each correct ring permanently speeds up the approaching GATES, not airplane
# steering. Each additional success closes 20% of the remaining gap to the
# difficulty ceiling: first boosts are +5% Easy, +7% Normal, +9% Hard.
const SPEED_REMAINING_FRACTION := 0.80
const KidsVoice = preload("res://ui/shared/kids_voice_feedback.gd")
# Queue a REAL GrammarBank question while the front three TorusMesh gates
# approach. Two fixed authored 2D groups and six pooled 3D rings travel at
# different depths so the pilot always sees the following wave ahead.
const GATE_PREFETCH_AT := 0.55
const GATE_SEPARATION := 0.52
const GATE_PREVIEW_TRAVEL_FACTOR := 0.60
# Rings remain opaque through the airplane and exit through the camera's
# near clipping plane. Fade only the final 2% to avoid a sharp clipped edge.
const GATE_PASSAGE_FADE_START := 0.98
# Perspective is inverse-depth focal projection (2D pseudo-3D). Projected
# apparent size is focal/(focal+depth); normalized far-to-near for authored
# gate guide endpoint consistency with real visible collision arcs.
const PSEUDO_FOCAL_LENGTH := 1.5
const PSEUDO_GATE_FAR_DEPTH := 4.5
const PSEUDO_GATE_NEAR_DEPTH := 0.7
# The wrapper supplies a fresh signed arm bank (-1 LEFT, +1 RIGHT). Banking
# controls continuous LATERAL VELOCITY, never a teleport to an absolute
# camera-torso X. Smooth acceleration follows Catch's sliding feel and is
# independent of 60fps rendering vs 10-20fps YOLO pose inference.
const BODY_FOLLOW_SPEED := 9.0
const BODY_MAX_TRAVEL_PER_SECOND := 0.82
const BODY_MAX_MOTION_STEP := 0.10
const BANK_INPUT_DEADZONE := 0.055
# Optional art is already used as calibration pose guides. Keep original
# authored PLANE.png as the default; switch the SAME scene TextureRect at
# maximum user tilt without moving/resizing the editable PlaneRig/Hitbox.
const LEFT_BANK_TEXTURE_PATH := "res://Components/Gameplay/Calibration/Pose Guides/PLANE GOING TO LEFT.png"
const RIGHT_BANK_TEXTURE_PATH := "res://Components/Gameplay/Calibration/Pose Guides/PLANE GOING TO RIGHT.png"
const BANK_ART_SWITCH_ON := 0.72
const BANK_ART_SWITCH_OFF := 0.48
# Reuse Catch the Word's original LivesPlaque as a mode-specific alternative
# to its TimerPlaque. The scene-authored Catch HUD positions are never moved.
const LIVES_PLAQUE_STATES := {
	0: preload("res://Components/Gameplay/Catch the Word/HUD/generated/lives_badge.png"),
	1: preload("res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_1.png"),
	2: preload("res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_2.png"),
	3: preload("res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_3.png")
}

const DIFFICULTY_CONFIG := {
	# Calm, readable waves with meaningful yet controlled difficulty progression.
	"Easy": {"waves": 12, "gate_speed": 0.20, "inter_wave_delay": 0.62, "speed_ceiling": 1.25},
	"Normal": {"waves": 14, "gate_speed": 0.27, "inter_wave_delay": 0.46, "speed_ceiling": 1.35},
	"Hard": {"waves": 16, "gate_speed": 0.34, "inter_wave_delay": 0.34, "speed_ceiling": 1.45},
}

const FALLBACK_WORDS := {
	"Noun": ["APPLE", "TEACHER", "RIVER", "BOOK", "SCHOOL", "DOG"],
	"Pronoun": ["HE", "SHE", "THEY", "WE", "IT", "YOU"],
	"Verb": ["RUN", "WRITE", "JUMP", "READ", "SING", "CLIMB"],
	"Adjective": ["BRIGHT", "TALL", "HAPPY", "SMALL", "QUIET", "BLUE"],
	"Adverb": ["QUICKLY", "SOFTLY", "ALWAYS", "CAREFULLY", "LOUDLY", "SLOWLY"],
}

# The class camera/pose is the only steering source in the actual game. This
# opt-in switch exists strictly for developers testing with no physical camera.
@export var allow_keyboard_debug := false
# The active flight scene is a genuine Node3D perspective world. Hidden
# editor-authored Control guides PLACE the gates; 3D airplane/torus hitbox
# clearance determines which opening was physically crossed.
@onready var _plane_rig: Control = $PlaneRig
@onready var _plane_artwork: TextureRect = $PlaneRig/PlaneArtwork
@onready var _catch_hud: Control = $HUDLayer/HUD
@onready var _floating_score: Label = $ScoreFeedbackLayer/FloatingScore
# The latest editor-authored Human Plane scene may intentionally omit the
# old visible answer-line UI. Fall back to its existing draggable gate-end
# marker rather than re-adding old artwork or crashing during gameplay.
@onready var _answer_line: Control = get_node_or_null("AnswerLine") as Control
@onready var _plane_left_limit: Control = $FlightPaths/PlaneLeftLimit
@onready var _plane_right_limit: Control = $FlightPaths/PlaneRightLimit
@onready var _gate_starts: Array[Control] = [$FlightPaths/GateStartLeft, $FlightPaths/GateStartCenter, $FlightPaths/GateStartRight]
@onready var _gate_ends: Array[Control] = [$FlightPaths/GateEndLeft, $FlightPaths/GateEndCenter, $FlightPaths/GateEndRight]
@onready var _gate_nodes: Array[Control] = [$MovingGates/GateLeft, $MovingGates/GateCenter, $MovingGates/GateRight]
@onready var _upcoming_gate_nodes: Array[Control] = [$UpcomingGates/GateLeft, $UpcomingGates/GateCenter, $UpcomingGates/GateRight]
var _plane_authored_offset_x := 0.0
var _authored_gate_colors: Array[Dictionary] = []
var _authored_gate_rect_offsets: Array[Rect2] = []
var _upcoming_gate_colors: Array[Dictionary] = []
var _upcoming_rect_offsets: Array[Rect2] = []
var _editor_word_offsets: Dictionary = {}
var next_round_data: Dictionary = {}
var next_gate_progress := 0.0
var _last_prompt_text := ""

var context: Dictionary = {}
var rng := RandomNumberGenerator.new()
var grammar_bank: Script

var topic := "Noun"
var difficulty := "Normal"
var game_mode := "Seconds"
var is_seconds_mode := true
var is_lives_mode := false
var score := 0
var correct_count := 0
var speed_boost_count := 0
var speed_multiplier := 1.0
var attempts := 0
var streak := 0
var lives := LIVES_ROUND_ALLOWANCE
var waves_total := 14
var waves_completed := 0
var time_remaining := 60.0

var started := false
var running := false
var finished := false
var round_completed := false
var paused := false

var round_data: Dictionary = {}
	# No vocabulary repeats within a cycle; once the eligible GrammarBank pool
	# runs low, the cycle starts over using only authentic, tier-matched words.
	# The last ACTUALLY PRESENTED trio stays excluded across the boundary so
	# automatic prefetch never replays that same question back-to-back.
var used_round_words: Dictionary = {}
var _last_presented_words: Dictionary = {}
var _vocabulary_cycle := 0
var _words_exhausted := false
var gate_progress := 0.0
# Exact starting progress of the active prefetched wave. The 3D renderer
# needs this to reconstruct the real forward distance when multiple gameplay
# ticks happen between 3D render frames (e.g. a slow classroom laptop).
var _wave_entry_progress := 0.0
var gate_resolved := false
var selected_lane := -1
var selected_was_correct := false
var inter_wave_delay := 0.0

var target_x_norm := 0.5
var plane_x_norm := 0.5
var _bank_input := 0.0
var _bank_velocity := 0.0
var _bank_art_state := 0
var _plane_default_texture: Texture2D
var _plane_bank_left_texture: Texture2D
var _plane_bank_right_texture: Texture2D
# Set by the camera/pose bridge ONLY while the same enrolled student has
# a fresh, confident calibrated body-position observation. Losing
# a wrist, student lock, or tracking freezes lateral steering immediately.
var airplane_pose_active := false
var _artwork_base_position := Vector2.ZERO
var _artwork_base_rotation := 0.0
var _flight_visual_elapsed := 0.0
var _feedback_voice: AudioStreamPlayer
var _kids_voice

var feedback_text := ""
var feedback_color := CREAM
var feedback_time := 0.0
var _floating_score_tween: Tween
var _tutorial_active := false
var _tutorial_step := 0
var _tutorial_voice_paused := false
const TUTORIAL_AUDIO_ROOT := "res://assets/audio/tutorial_spotlight/human_plane_"
const TUTORIAL_COMPONENTS := [
	{"target": "PlaneRig", "title": "FLY WITH YOUR ARMS", "message": "Stretch both arms out to fly. Lean left or right to steer toward a ring. Lowering an arm holds your position.", "audio": "movement"},
	{"target": "ring", "title": "FLY THROUGH A WORD RING", "message": "Three word rings approach: LEFT, CENTER and RIGHT. Steer the airplane through the opening of the correct ring.", "audio": "ring"},
	{"target": "HUDLayer/HUD/PromptLabel", "title": "READ THE QUESTION", "message": "Look at the grammar question and choose the word that belongs to its requested category.", "audio": "prompt"},
	{"target": "mode", "title": "WATCH YOUR ROUND", "message": "Seconds mode gives you 60 seconds. Lives mode gives you three hearts. Keep playing until the round ends.", "audio": "mode"},
	{"target": "HUDLayer/HUD/ScorePlaque", "title": "EARN POINTS", "message": "A correct ring gives +100 points. A wrong ring or missed opening gives +0. Watch your score here.", "audio": "score"},
	{"target": "HUDLayer/HUD/PausePlaque", "title": "PAUSE ANYTIME", "message": "Use the Pause button to stop the game and resume when you are ready.", "audio": "pause"}
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	set_process_unhandled_key_input(true)
	# Supplied PNG arc sprites and plane are the visible game; the retired
	# rectangle pieces stay hidden, never substituted for the original art.
	$MovingGates.modulate.a = 1.0
	$UpcomingGates.modulate.a = 1.0
	$PlaneRig.modulate.a = 1.0
	# Capture any editor offset from the path midpoint so moving PlaneRig in
	# the editor also moves the actual gameplay hitbox horizontally.
	_plane_authored_offset_x = _plane_rig.get_rect().get_center().x - lerpf(_plane_left_limit.get_rect().get_center().x, _plane_right_limit.get_rect().get_center().x, 0.5)
	_artwork_base_position = _plane_artwork.position
	_artwork_base_rotation = _plane_artwork.rotation
	_plane_default_texture = _plane_artwork.texture
	if ResourceLoader.exists(LEFT_BANK_TEXTURE_PATH):
		_plane_bank_left_texture = load(LEFT_BANK_TEXTURE_PATH) as Texture2D
	if ResourceLoader.exists(RIGHT_BANK_TEXTURE_PATH):
		_plane_bank_right_texture = load(RIGHT_BANK_TEXTURE_PATH) as Texture2D
	if _plane_artwork.pivot_offset.is_zero_approx():
		_plane_artwork.pivot_offset = _plane_artwork.size * 0.5
	# The editable colors in the .tscn are the default gate artwork. Only a
	# resolved hit temporarily overrides them with green/red feedback.
	for gate in _gate_nodes:
		var original_colors := {}
		for part in ["LeftPillar", "RightPillar", "TopBar"]:
			original_colors[part] = (gate.get_node(part) as ColorRect).color
		_authored_gate_colors.append(original_colors)
	# Teachers can drag either the visible gate artwork OR its Start/End
	# guides. Preserve gate artwork edits as an offset applied to the entire
	# authored travel path, so animation and collision never disagree.
	for i in range(3):
		var authored := _gate_nodes[i].get_rect()
		var default_start := _gate_starts[i].get_rect()
		_authored_gate_rect_offsets.append(Rect2(authored.position - default_start.position, authored.size - default_start.size))
		var upcoming_authored := _upcoming_gate_nodes[i].get_rect()
		_upcoming_rect_offsets.append(Rect2(upcoming_authored.position - default_start.position, upcoming_authored.size - default_start.size))
		var colors := {}
		for part in ["LeftPillar", "RightPillar", "TopBar"]:
			colors[part] = (_upcoming_gate_nodes[i].get_node(part) as ColorRect).color
		_upcoming_gate_colors.append(colors)
	# WordPlate/WordLabel anchors and Inspector offsets remain the authored
	# source. A right-lane word that intersects Catch's exact score plaque
	# shifts UP just enough for readability, never changes gate/hitbox position.
	for group in [_gate_nodes, _upcoming_gate_nodes]:
		for gate in group:
			for child_name in ["WordPlate", "WordLabel"]:
				var item := (gate as Control).get_node(child_name) as Control
				_editor_word_offsets[item.get_instance_id()] = Vector4(
					item.offset_left, item.offset_top, item.offset_right, item.offset_bottom)
	resized.connect(_on_scene_resized)
	$HUDLayer/HUD/PauseButton.pressed.connect(_request_pause)
	$TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide/NextButton.pressed.connect(_next_tutorial_step)
	$TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide/SkipButton.pressed.connect(_end_guided_tutorial)
	$TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide/BackButton.pressed.connect(_previous_tutorial_step)
	$TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide/ReplayButton.pressed.connect(replay_tutorial_voice)
	$TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide/PauseVoiceButton.pressed.connect(toggle_tutorial_voice_pause)
	for name in ["BackButton", "NextButton", "ReplayButton", "SkipButton"]:
		var art_button := $TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide.get_node(name) as Button
		art_button.add_theme_color_override("font_hover_pressed_color", Color.TRANSPARENT)
		art_button.add_theme_color_override("font_focus_color", Color.TRANSPARENT)
		art_button.mouse_entered.connect(_set_tutorial_art_hover.bind(art_button, true))
		art_button.mouse_exited.connect(_set_tutorial_art_hover.bind(art_button, false))
		art_button.focus_entered.connect(_set_tutorial_art_hover.bind(art_button, true))
		art_button.focus_exited.connect(_set_tutorial_art_hover.bind(art_button, false))
	rng.randomize()
	_initialize_voice_feedback()
	if ResourceLoader.exists(GRAMMAR_BANK_PATH):
		grammar_bank = load(GRAMMAR_BANK_PATH) as Script
	call_deferred("_ensure_started")
	call_deferred("_on_scene_resized")


func set_context(new_context: Dictionary) -> void:
	context = new_context.duplicate(true)
	if not started:
		_apply_initial_context()
	else:
		# Runtime callers may update presentation context, but active game state wins.
		topic = _canonical_topic(_first_text(context, ["topic", "game_style"], topic))
		difficulty = _canonical_difficulty(_first_text(context, ["difficulty"], difficulty))
		speed_multiplier = _earned_gate_speed_multiplier()
	_sync_visuals()
	if _tutorial_active:
		_show_tutorial_step()


func begin_guided_tutorial() -> void:
	# The router invokes this on the actual minigame scene before countdown.
	# Freeze time, gates, pose steering and all scoring while explaining HUD.
	if finished:
		return
	_ensure_started()
	_tutorial_active = true
	_tutorial_step = 0
	_tutorial_voice_paused = false
	running = false
	set_airplane_pose_active(false)
	$TutorialSpotlightLayer/TutorialSpotlight.visible = true
	_show_tutorial_step()


func is_tutorial_active() -> bool:
	return _tutorial_active


func _next_tutorial_step() -> void:
	if not _tutorial_active:
		return
	_tutorial_step += 1
	if _tutorial_step >= TUTORIAL_COMPONENTS.size():
		_end_guided_tutorial()
	else:
		_show_tutorial_step()


func _previous_tutorial_step() -> void:
	if not _tutorial_active or _tutorial_step <= 0:
		return
	_tutorial_step -= 1
	_show_tutorial_step()


func _end_guided_tutorial() -> void:
	if not _tutorial_active:
		return
	_tutorial_active = false
	$TutorialSpotlightLayer/TutorialSpotlight.visible = false
	var narration := $TutorialSpotlightLayer/TutorialNarration as AudioStreamPlayer
	narration.stop()
	narration.stream_paused = false
	_tutorial_voice_paused = false
	# The router receives tutorial_finished and owns the subsequent countdown.
	# Keep flight frozen until the router explicitly resumes this instance.
	running = false
	tutorial_finished.emit()


func _show_tutorial_step() -> void:
	if not _tutorial_active or not is_node_ready():
		return
	# The Gameplay router intentionally disables the entire minigame before
	# tutorial begins. Place the real native 3D airplane and torus once with a
	# zero-delta render sync, so spotlight geometry matches what is VISIBLE to
	# students even before the first active game frame / countdown.
	($HybridFlight3D as Node2D).call("_process", 0.0)
	var info: Dictionary = TUTORIAL_COMPONENTS[_tutorial_step]
	var guide := $TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide as Control
	(guide.get_node("Title") as Label).text = String(info["title"])
	(guide.get_node("Message") as Label).text = String(info["message"])
	(guide.get_node("StepCounter") as Label).text = "STEP %d OF %d" % [_tutorial_step + 1, TUTORIAL_COMPONENTS.size()]
	var final_step := _tutorial_step == TUTORIAL_COMPONENTS.size() - 1
	var next_button := guide.get_node("NextButton") as Button
	next_button.text = "START" if final_step else "NEXT"
	var next_art := next_button.get_node_or_null("NextArt") as TextureRect
	if next_art != null:
		next_art.visible = not final_step
	var start_plate := next_button.get_node_or_null("StartPlate") as Panel
	if start_plate != null:
		start_plate.visible = final_step
	var back_button := guide.get_node("BackButton") as Button
	back_button.disabled = _tutorial_step == 0
	var back_art := back_button.get_node_or_null("BackArt") as TextureRect
	if back_art != null:
		back_art.texture = preload("res://ui/minigames/catch_the_word/tutorial_art/back_disabled.png") \
			if back_button.disabled else preload("res://ui/minigames/catch_the_word/tutorial_art/back_enabled.png")
	_layout_tutorial_spotlight()
	replay_tutorial_voice()


func _set_tutorial_art_hover(button: Button, highlighted: bool) -> void:
	if not is_instance_valid(button):
		return
	var tint := Color(1.0, 0.96, 0.8, 1.0) if highlighted and not button.disabled else Color.WHITE
	for node_name in ["BackArt", "NextArt", "ReplayArt", "SkipArt", "StartPlate"]:
		var artwork := button.get_node_or_null(node_name) as CanvasItem
		if artwork != null:
			artwork.modulate = tint


func replay_tutorial_voice() -> void:
	if not _tutorial_active:
		return
	var info: Dictionary = TUTORIAL_COMPONENTS[_tutorial_step]
	var narration := $TutorialSpotlightLayer/TutorialNarration as AudioStreamPlayer
	narration.stop()
	narration.stream_paused = false
	_tutorial_voice_paused = false
	var guide := $TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide as Control
	var replay := guide.get_node("ReplayButton") as Button
	var pause_button := guide.get_node("PauseVoiceButton") as Button
	pause_button.text = "PAUSE VOICE"
	var audio_name := String(info["audio"])
	if audio_name == "mode":
		audio_name = "seconds" if is_seconds_mode else "lives"
	if not audio_name.is_empty():
		var audio_path := TUTORIAL_AUDIO_ROOT + audio_name + ".wav"
		if ResourceLoader.exists(audio_path):
			narration.stream = load(audio_path) as AudioStream
			replay.disabled = narration.stream == null
			pause_button.disabled = replay.disabled
			if narration.stream != null:
				narration.play()
			return
	narration.stream = null
	replay.disabled = true
	pause_button.disabled = true


func toggle_tutorial_voice_pause() -> void:
	if not _tutorial_active:
		return
	var narration := $TutorialSpotlightLayer/TutorialNarration as AudioStreamPlayer
	if narration.stream == null:
		return
	_tutorial_voice_paused = not _tutorial_voice_paused
	narration.stream_paused = _tutorial_voice_paused
	($TutorialSpotlightLayer/TutorialSpotlight/TutorialGuide/PauseVoiceButton as Button).text = \
		"RESUME VOICE" if _tutorial_voice_paused else "PAUSE VOICE"


func _layout_tutorial_spotlight() -> void:
	if not _tutorial_active or not is_node_ready():
		return
	var overlay := $TutorialSpotlightLayer/TutorialSpotlight as Control
	var info: Dictionary = TUTORIAL_COMPONENTS[_tutorial_step]
	var target := String(info["target"])
	var visible_rect := Rect2()
	if target == "PlaneRig":
		# This accessor projects the actual 22 3D airplane mesh AABBs. The
		# invisible oversized 2D steering rig must NEVER enlarge the cutout.
		visible_rect = ($HybridFlight3D as Node2D).call("get_airplane_highlight_rect")
	elif target == "ring":
		visible_rect = _tutorial_projected_ring_mesh_rect(1)
	elif target == "mode":
		var mode_path := "HUDLayer/HUD/TimerPlaque" if is_seconds_mode else "HUDLayer/HUD/LivesPlaque"
		visible_rect = _tutorial_control_rect(get_node(mode_path) as Control)
	else:
		visible_rect = _tutorial_control_rect(get_node(target) as Control)
	if target == "PlaneRig" or target == "ring":
		# Hybrid's projected pixels are in the game's local canvas; convert to
		# the independent CanvasLayer coordinates used by the four dim pieces.
		visible_rect = _tutorial_canvas_rect(visible_rect)
	# Four source-authored dimming regions create a REAL transparent cutout.
	# Their bounds follow the currently highlighted editor component and
	# automatically adapt to 1280, 1600 and 1920 classroom viewports.
	var canvas := overlay.size
	var padding := maxf(canvas.y / 720.0 * 9.0, 5.0)
	var focus := visible_rect.grow(padding).intersection(Rect2(Vector2.ZERO, canvas))
	if not focus.has_area():
		return
	var left := overlay.get_node("DimLeft") as ColorRect
	var right := overlay.get_node("DimRight") as ColorRect
	var above := overlay.get_node("DimAbove") as ColorRect
	var below := overlay.get_node("DimBelow") as ColorRect
	left.position = Vector2.ZERO
	left.size = Vector2(maxf(focus.position.x, 0.0), canvas.y)
	right.position = Vector2(focus.end.x, 0.0)
	right.size = Vector2(maxf(canvas.x - focus.end.x, 0.0), canvas.y)
	above.position = Vector2(focus.position.x, 0.0)
	above.size = Vector2(focus.size.x, maxf(focus.position.y, 0.0))
	below.position = Vector2(focus.position.x, focus.end.y)
	below.size = Vector2(focus.size.x, maxf(canvas.y - focus.end.y, 0.0))
	var outline := overlay.get_node("HighlightOutline") as Panel
	outline.position = focus.position
	outline.size = focus.size
	var guide := overlay.get_node("TutorialGuide") as Control
	# Use Inspector-authored guide anchors at the top or bottom depending on
	# where the highlighted control lives, so it does not block the cutout.
	var top_anchor := overlay.get_node("GuideTopAnchor") as Control
	var bottom_anchor := overlay.get_node("GuideBottomAnchor") as Control
	var anchor := top_anchor if focus.get_center().y > canvas.y * 0.53 else bottom_anchor
	guide.position = anchor.position
	guide.size = anchor.size


func _tutorial_control_rect(control: Control) -> Rect2:
	if control == null:
		return Rect2()
	var to_overlay := ($TutorialSpotlightLayer/TutorialSpotlight as Control).get_global_transform_with_canvas().affine_inverse() * control.get_global_transform_with_canvas()
	return _tutorial_transform_rect(to_overlay, Rect2(Vector2.ZERO, control.size))


func _tutorial_canvas_rect(rect: Rect2) -> Rect2:
	var to_overlay := ($TutorialSpotlightLayer/TutorialSpotlight as Control).get_global_transform_with_canvas().affine_inverse() * get_global_transform_with_canvas()
	return _tutorial_transform_rect(to_overlay, rect)


func _tutorial_transform_rect(transform: Transform2D, rect: Rect2) -> Rect2:
	var result := Rect2(transform * rect.position, Vector2.ZERO)
	for corner in [Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)]:
		result = result.expand(transform * corner)
	return result.abs()


func _tutorial_projected_ring_mesh_rect(lane: int) -> Rect2:
	# Actual native TorusMesh geometry and camera projection, including depth.
	# The projected 2D editor gate is deliberately not a focus target.
	var hybrid := $HybridFlight3D as Node2D
	var pools: Array = hybrid.get("_ring_pools")
	var active_parent := _gate_nodes[0].get_parent()
	var front_index := 0 if active_parent == hybrid.get("_first_gate_group") else 1
	if pools.size() <= front_index or (pools[front_index] as Array).size() <= lane:
		return hybrid.call("get_ring_highlight_rect", lane)
	var ring := (pools[front_index] as Array)[lane] as Node3D
	var mesh := ring.get_node_or_null("Ring") as MeshInstance3D
	var camera := hybrid.get("view_camera") as Camera3D
	var viewport := hybrid.get("viewport") as SubViewport
	if mesh == null or not mesh.mesh is TorusMesh or camera == null or viewport == null \
			or viewport.size.x < 1 or viewport.size.y < 1:
		return hybrid.call("get_ring_highlight_rect", lane)
	var tex_scale := size / Vector2(viewport.size)
	var bounds := Rect2()
	var has_corner := false
	var aabb := mesh.get_aabb()
	for corner in range(8):
		var world_corner := mesh.to_global(aabb.get_endpoint(corner))
		if camera.is_position_behind(world_corner):
			continue
		var projected := camera.unproject_position(world_corner) * tex_scale
		if not has_corner:
			bounds = Rect2(projected, Vector2.ZERO)
			has_corner = true
		else:
			bounds = bounds.expand(projected)
	return bounds if has_corner and bounds.has_area() else hybrid.call("get_ring_highlight_rect", lane)


func get_context() -> Dictionary:
	var payload := context.duplicate(true)
	payload["activity"] = "Human Plane"
	payload["topic"] = topic
	payload["game_style"] = topic
	payload["difficulty"] = difficulty
	payload["game_mode"] = game_mode
	payload["score"] = score
	payload["correct"] = correct_count
	payload["plane_speed_boosts"] = speed_boost_count
	payload["plane_speed_multiplier"] = speed_multiplier
	payload["plane_used_words"] = used_round_words.keys()
	payload["plane_previous_wave_words"] = _last_presented_words.keys()
	payload["plane_vocabulary_cycle"] = _vocabulary_cycle
	payload["plane_words_exhausted"] = _words_exhausted
	payload["attempts"] = attempts
	payload["total"] = waves_total
	payload["waves_completed"] = waves_completed
	payload["lives"] = lives
	payload["streak"] = streak
	payload["time_remaining"] = maxf(time_remaining, 0.0)
	payload["body_x"] = plane_x_norm * 2.0 - 1.0
	payload["demo_mode"] = true
	payload["score_saved"] = false
	payload["gameplay_implemented"] = true
	payload["camera_live"] = false
	payload["database_connected"] = false
	payload["round_completed"] = round_completed
	payload["completion_reason"] = ("time_up" if is_seconds_mode else "lives_empty") \
		if round_completed and ((is_seconds_mode and time_remaining <= 0.0) \
		or (is_lives_mode and lives <= 0)) else ""
	return payload


func set_body_x(normalized_x: float) -> void:
	# Signed bank now expresses arm-angle VELOCITY, NOT torso world position.
	# The wrapper/PoseService must validate this frame's actual YOLO SOLO body,
	# visible wrists and physical neutral T-pose calibration BEFORE calling.
	if not airplane_pose_active or paused or finished or not is_finite(normalized_x):
		return
	var requested := clampf(normalized_x, -1.0, 1.0)
	_bank_input = 0.0 if absf(requested) < BANK_INPUT_DEADZONE else requested


func set_wing_steering(roll: float, active: bool) -> void:
	# Equivalent validated signed-bank hook for gameplay wrappers. This does
	# not read any old cached gesture or synthesize a pose on its own.
	set_airplane_pose_active(active and is_finite(roll))
	if airplane_pose_active:
		set_body_x(roll)


func set_airplane_pose_active(active: bool) -> void:
	# Freeze the CURRENT visual/physical X immediately on occlusion, loss of
	# student lock, or unreliable arm steering. Re-arming needs a fresh input;
	# no stale pose is replayed from the last frame or another student.
	if airplane_pose_active == active:
		return
	airplane_pose_active = active
	_bank_input = 0.0
	_bank_velocity = 0.0
	target_x_norm = plane_x_norm
	if not active:
		_set_bank_artwork(0)
		# A lost hand must not leave a tilted wing painted indefinitely while
		# the full 2D scene is paused for person count or missing keypoints.
		if is_instance_valid(_plane_artwork):
			_plane_artwork.rotation = _artwork_base_rotation
			_plane_artwork.position = _artwork_base_position
	_sync_visuals()


func _finish_round(message: String = "ROUND COMPLETE") -> void:
	if finished:
		return
	# Never treat an early Exit/View Results or a direct call as completion.
	# A completed result requires this mode's actual end condition.
	if (is_seconds_mode and time_remaining > 0.0) or (is_lives_mode and lives > 0):
		return
	finished = true
	running = false
	paused = false
	round_completed = true
	feedback_text = message
	feedback_color = GREEN
	feedback_time = 2.0
	_stop_voice_feedback()
	_sync_visuals()
	requested.emit("results", get_context())


func _ensure_started() -> void:
	if started:
		return
	_apply_initial_context()
	started = true
	running = true
	paused = false
	round_completed = false
	_start_wave()
	_sync_visuals()


func _apply_initial_context() -> void:
	if not started:
		used_round_words.clear()
		for word in context.get("plane_used_words", []):
			var key := _word_key(String(word))
			if not key.is_empty():
				used_round_words[key] = true
		_last_presented_words.clear()
		for word in context.get("plane_previous_wave_words", []):
			var key := _word_key(String(word))
			if not key.is_empty():
				_last_presented_words[key] = true
		_vocabulary_cycle = maxi(int(context.get("plane_vocabulary_cycle", 0)), 0)
		_words_exhausted = bool(context.get("plane_words_exhausted", false))
	topic = _canonical_topic(_first_text(context, ["topic", "game_style"], "Noun"))
	difficulty = _canonical_difficulty(_first_text(context, ["difficulty"], "Normal"))
	# Teacher setup uses Seconds/Lives. Older "Quiz" sessions also mean
	# Seconds; never silently inherit a difficulty-dependent timer in either.
	var requested_mode := _first_text(context, ["game_mode", "mode"], "Seconds").to_lower()
	game_mode = "Lives" if requested_mode in ["lives", "life", "hearts"] else "Seconds"
	is_seconds_mode = game_mode == "Seconds"
	is_lives_mode = not is_seconds_mode
	var config: Dictionary = DIFFICULTY_CONFIG[difficulty]
	waves_total = int(context.get("total", config["waves"]))
	waves_total = maxi(waves_total, 10)
	score = maxi(int(context.get("score", 0)), 0)
	correct_count = maxi(int(context.get("correct", 0)), 0)
	# A resumed game may be restored independently of streak (wrong answers
	# reset streak, not the flight speed). Never reduce an earned boost.
	speed_boost_count = maxi(int(context.get("plane_speed_boosts", correct_count)), correct_count)
	speed_multiplier = _earned_gate_speed_multiplier()
	attempts = maxi(int(context.get("attempts", 0)), 0)
	streak = maxi(int(context.get("streak", 0)), 0)
	waves_completed = maxi(int(context.get("waves_completed", attempts)), 0)
	# Seconds has no heart-loss rule; Lives starts with three and can only
	# finish after the last one is lost. Resume accepts 0–3 remaining.
	lives = LIVES_ROUND_ALLOWANCE if is_seconds_mode else clampi(
		int(context.get("lives", LIVES_ROUND_ALLOWANCE)), 0, LIVES_ROUND_ALLOWANCE)
	# A fresh Seconds round begins at 60s. If a paused Human Plane round is
	# reconstructed from get_context(), restore its remaining time rather than
	# resetting it to 60. Lives never acquires a timed-loss condition.
	time_remaining = 0.0 if is_lives_mode else clampf(float(context.get("time_remaining", SECONDS_ROUND_DURATION)), 0.0, SECONDS_ROUND_DURATION)
	var restored_body_x := clampf(float(context.get("body_x", 0.0)), -1.0, 1.0)
	target_x_norm = (restored_body_x + 1.0) * 0.5
	plane_x_norm = target_x_norm
	_bank_input = 0.0
	_bank_velocity = 0.0
	finished = false
	paused = false
	round_completed = false
		# The 3D renderer owns its independently moving clouds; no 2D parallax
		# or camera-tracking data is changed by reinitializing the round.


func _earned_gate_speed_multiplier() -> float:
	var ceiling := float(DIFFICULTY_CONFIG[difficulty]["speed_ceiling"])
	return minf(ceiling, 1.0 + (ceiling - 1.0) * (
		1.0 - pow(SPEED_REMAINING_FRACTION, float(speed_boost_count))))


func _process(delta: float) -> void:
	if not started:
		return
	if _tutorial_active:
		_layout_tutorial_spotlight()
		return
	if paused:
		return
	_update_plane_motion(delta)
	_update_flight_artwork(delta)
		# Real 3D sky/cloud parallax is advanced by the flight renderer only
		# during authenticated, active flight.
	if feedback_time > 0.0:
		feedback_time = maxf(feedback_time - delta, 0.0)
	if running and not finished:
		if is_seconds_mode:
			time_remaining = maxf(time_remaining - delta, 0.0)
			if time_remaining <= 0.0:
					_finish_round("TIME!")
			else:
				_update_gate_wave(delta)
		else:
			_update_gate_wave(delta)
	_sync_visuals()


func _update_plane_motion(delta: float) -> void:
	# Sliding analogue to Catch: integrate proportionally from real arm tilt
	# continuously. Max travel is speed-limited per render step so no pose,
	# retry/recovery, or an arms-crossing glitch can jump between gate lanes.
	if not airplane_pose_active or paused or finished:
		return
	var step := clampf(delta, 0.0, BODY_MAX_MOTION_STEP)
	if step <= 0.0:
		return
	var requested_speed := _bank_input * BODY_MAX_TRAVEL_PER_SECOND
	var follow := 1.0 - exp(-BODY_FOLLOW_SPEED * step)
	_bank_velocity = lerpf(_bank_velocity, requested_speed, follow)
	plane_x_norm = clampf(plane_x_norm + _bank_velocity * step, 0.0, 1.0)
	if (plane_x_norm <= 0.0 and _bank_velocity < 0.0) \
			or (plane_x_norm >= 1.0 and _bank_velocity > 0.0):
		_bank_velocity = 0.0
	# The visible sprite AND the scoring hitbox share plane_x_norm; this
	# moving preview is only a direction indicator, never an instant target.
	target_x_norm = plane_x_norm


func _update_flight_artwork(delta: float) -> void:
	# A hint of forward-flight life without moving the PlaneRig hitbox or
	# editor-authored gate collision guides.
	# Tracking loss/arms lowered or Pause freeze the existing visual pose.
	if not airplane_pose_active or not running or finished:
		return
	_flight_visual_elapsed += maxf(delta, 0.0)
	var bank := deg_to_rad(_bank_input * 3.0)
	_plane_artwork.rotation = lerp_angle(_plane_artwork.rotation, _artwork_base_rotation + bank,
		clampf(delta * 5.0, 0.0, 1.0))
	var bob := sin(_flight_visual_elapsed * 2.4) * 2.0 * clampf(size.y / 720.0, 0.8, 1.5)
	_plane_artwork.position = _artwork_base_position + Vector2(0.0, bob)
	var desired_art := 0
	if _bank_input >= (BANK_ART_SWITCH_OFF if _bank_art_state == 1 else BANK_ART_SWITCH_ON):
		desired_art = 1
	elif _bank_input <= -(BANK_ART_SWITCH_OFF if _bank_art_state == -1 else BANK_ART_SWITCH_ON):
		desired_art = -1
	_set_bank_artwork(desired_art)


func _set_bank_artwork(direction: int) -> void:
	# The teacher's original sprite dimensions, position and Hitbox remain
	# editor-authored. All three art states use this ONE TextureRect.
	_bank_art_state = clampi(direction, -1, 1)
	if not is_instance_valid(_plane_artwork):
		return
	var texture := _plane_default_texture
	if _bank_art_state < 0 and _plane_bank_left_texture != null:
		texture = _plane_bank_left_texture
	elif _bank_art_state > 0 and _plane_bank_right_texture != null:
		texture = _plane_bank_right_texture
	if _plane_artwork.texture != texture:
		_plane_artwork.texture = texture


func _update_gate_wave(delta: float) -> void:
	# Substeps keep a dropped frame from skipping the distant preview or
	# crossing the answer line without resolving a gate.
	var remaining := maxf(delta, 0.0)
	var iterations := 0
	var completed_before := waves_completed
	while remaining > 0.000001 and iterations < 150 and not finished:
		var step := minf(remaining, 1.0 / 30.0)
		remaining -= step
		iterations += 1
		_advance_gate_step(step)
		# A large frame hitch may complete the current wave, but cannot
		# retroactively fail several future questions the player never saw.
		if waves_completed > completed_before:
			break


func _advance_gate_step(delta: float) -> void:
	var progress_per_second := float(DIFFICULTY_CONFIG[difficulty]["gate_speed"]) * speed_multiplier
	if round_data.is_empty():
		return
	var previous_y := _gate_y(gate_progress)
	gate_progress = minf(gate_progress + progress_per_second * delta, 1.0)
	if not next_round_data.is_empty():
		next_gate_progress = minf(next_gate_progress + progress_per_second * GATE_PREVIEW_TRAVEL_FACTOR * delta, 1.0)
	elif gate_progress >= GATE_PREFETCH_AT:
		_prefetch_next_wave()
	var current_y := _gate_y(gate_progress)
	var answer_y := _answer_line_y()
	if not gate_resolved and previous_y < answer_y and current_y >= answer_y:
		# The actual airplane and ring colliders, at this frame's crossing,
		# decide the lane. A projected guide alone must never grant points.
		# Only a genuinely live webcam round can rely on the current physics
		# frame. Offline previews and isolated deterministic tests have no
		# authenticated tracking frame to synchronize with native collision
		# objects; preserve the predictive collider-geometry check for them.
		_resolve_at_answer_line(bool(context.get("camera_live", false)))
	if finished:
		return
	if gate_progress >= 1.0:
		if not gate_resolved:
			_resolve_at_answer_line(bool(context.get("camera_live", false)))
		waves_completed += 1
		if is_lives_mode and lives <= 0:
			_finish_round("OUT OF LIVES")
		elif not next_round_data.is_empty():
			_promote_prefetched_wave()
		else:
			# The safety fallback only applies if an external caller advances
			# past a full wave in one step or vocabulary has been exhausted.
			_start_wave()


func _remember_displayed_words(data: Dictionary) -> void:
	for option in data.get("options", []):
		used_round_words[_word_key(String(option))] = true


func _mark_presented_wave(data: Dictionary) -> void:
	# Do NOT call this during prefetch: its question is not on screen yet.
	_last_presented_words.clear()
	for option in data.get("options", []):
		_last_presented_words[_word_key(String(option))] = true


func _prefetch_next_wave() -> void:
	if finished or _words_exhausted or not next_round_data.is_empty():
		return
	var generated := _make_lane_round()
	if generated.is_empty():
		return
	next_round_data = generated
	_remember_displayed_words(generated)
	next_gate_progress = maxf(0.0, gate_progress - GATE_SEPARATION)
	# Display a second authored vocabulary trio in the distance while the
	# passed trio continues toward/through the airplane. Real scoring is
	# still performed exclusively against _gate_nodes and round_data.
	_upcoming_gate_nodes[0].get_parent().visible = true
	_upcoming_gate_nodes[0].get_parent().z_index = 0
	_sync_visuals()


func _promote_prefetched_wave() -> void:
	# Switch two already visible 2D/3D pooled groups at the exact wave
	# boundary. Outgoing rings have passed behind the camera by this point.
	var previous_gate_nodes := _gate_nodes
	var previous_rect_offsets := _authored_gate_rect_offsets
	var previous_gate_colors := _authored_gate_colors
	var outgoing_group := previous_gate_nodes[0].get_parent() as Control
	var incoming_group := _upcoming_gate_nodes[0].get_parent() as Control
	outgoing_group.visible = false
	_gate_nodes = _upcoming_gate_nodes
	_authored_gate_rect_offsets = _upcoming_rect_offsets
	_authored_gate_colors = _upcoming_gate_colors
	_upcoming_gate_nodes = previous_gate_nodes
	_upcoming_rect_offsets = previous_rect_offsets
	_upcoming_gate_colors = previous_gate_colors
	incoming_group.z_index = 1
	outgoing_group.z_index = 0
	incoming_group.visible = true
	round_data = next_round_data
	_mark_presented_wave(round_data)
	gate_progress = next_gate_progress
	_wave_entry_progress = gate_progress
	next_round_data = {}
	next_gate_progress = 0.0
	gate_resolved = false
	selected_lane = -1
	selected_was_correct = false
	inter_wave_delay = 0.0


func _start_wave() -> void:
	if finished:
		return
	# This public legacy test/gameplay hook explicitly starts a fresh wave.
	# Discard any auto-prefetched set rather than spending its words twice.
	next_round_data.clear()
	next_gate_progress = 0.0
	_upcoming_gate_nodes[0].get_parent().visible = false
	_gate_nodes[0].get_parent().visible = true
	if is_lives_mode and lives <= 0:
		_finish_round("OUT OF LIVES")
		return
	if is_seconds_mode and time_remaining <= 0.0:
		_finish_round("TIME!")
		return
	round_data = _make_lane_round()
	if round_data.is_empty():
		# This is only reachable if even the unfiltered real bank cannot form
		# one correct + two legitimate lane options, not ordinary depletion.
		_words_exhausted = true
		_show_word_exhaustion()
		return
	_words_exhausted = false
	_remember_displayed_words(round_data)
	_mark_presented_wave(round_data)
	gate_progress = 0.0
	_wave_entry_progress = 0.0
	gate_resolved = false
	selected_lane = -1
	selected_was_correct = false
	feedback_text = ""
	feedback_time = 0.0


func _show_word_exhaustion() -> void:
	round_data = {}
	next_round_data = {}
	gate_resolved = true
	_gate_nodes[0].get_parent().visible = false
	_upcoming_gate_nodes[0].get_parent().visible = false
	feedback_text = "NO MORE UNIQUE WORDS"
	feedback_color = YELLOW
	feedback_time = 0.0
	_sync_visuals()


func _make_lane_round() -> Dictionary:
	# First, spend each authentic difficulty-eligible word at most once in
	# this cycle. A zero-round response means that one of the matching or
	# distractor pools has too few eligible unused words for a fair trio.
	if grammar_bank != null:
		var generated: Variant = grammar_bank.call("lane_round", topic, difficulty, rng, used_round_words.duplicate())
		if generated is Dictionary and _round_is_valid(generated):
			return generated
		return _renew_vocab_cycle()
	var fallback := _fallback_lane_round()
	if _round_is_valid(fallback):
		return fallback
	return _renew_vocab_cycle()


func _renew_vocab_cycle() -> Dictionary:
	# Recycling vocabulary is allowed ONLY after the remaining unused pool
	# fails to supply a complete, valid round. First reserve the last *visible*
	# trio, preventing back-to-back reuse across the cycle boundary. A tiny
	# future bank may make that impossible; retry with no exclusions only then.
	# These are real GrammarBank or authored fallback words, never synthesized.
	var previously_used := used_round_words.duplicate()
	for preserve_recent in [true, false]:
		used_round_words = _last_presented_words.duplicate() if preserve_recent else {}
		var generated: Dictionary = {}
		if grammar_bank != null:
			var candidate: Variant = grammar_bank.call("lane_round", topic, difficulty, rng, used_round_words.duplicate())
			if candidate is Dictionary:
				generated = candidate
		else:
			generated = _fallback_lane_round()
		if _round_is_valid(generated):
			_vocabulary_cycle += 1
			return generated
	used_round_words = previously_used
	# The real underlying bank is empty/invalid. Retain state rather than
	# inventing grammar words or emitting fake Results; this is diagnostic.
	push_error("Human Plane cannot build a fair round from GrammarBank topic=%s difficulty=%s." % [topic, difficulty])
	return {}


func _round_is_valid(value: Dictionary) -> bool:
	if not value.has("prompt") or not value.has("options") or not value.has("valid_indices"):
		return false
	var options: Array = value["options"]
	var valid: Array = value["valid_indices"]
	if options.size() != 3 or valid.is_empty() or valid.size() > 2:
		return false
	var local_words := {}
	for word in options:
		var key := _word_key(String(word))
		if key.is_empty() or local_words.has(key) or used_round_words.has(key):
			return false
		local_words[key] = true
	var unique_indices := {}
	for index in valid:
		if int(index) < 0 or int(index) >= 3 or unique_indices.has(int(index)):
			return false
		unique_indices[int(index)] = true
	return true


func _word_key(word: String) -> String:
	return word.strip_edges().to_lower()


func _fallback_lane_round() -> Dictionary:
	var canonical := _canonical_topic(topic)
	var correct_words: Array[String] = []
	var distractor_words: Array[String] = []
	for word in FALLBACK_WORDS[canonical]:
		if not used_round_words.has(_word_key(String(word))):
			correct_words.append(String(word))
	for other_topic in FALLBACK_WORDS:
		if other_topic == canonical:
			continue
		for word in FALLBACK_WORDS[other_topic]:
			if not used_round_words.has(_word_key(String(word))):
				distractor_words.append(String(word))
	if correct_words.is_empty() or distractor_words.size() < 1:
		return {}
	var options: Array[String] = []
	var valid_indices: Array[int] = []
	var correct_slots := 2 if difficulty == "Hard" and correct_words.size() >= 2 and rng.randf() < 0.35 else 1
	if distractor_words.size() < 3 - correct_slots:
		correct_slots = 2 if correct_words.size() >= 2 else 1
	if distractor_words.size() < 3 - correct_slots:
		return {}
	for i in range(3):
		if i < correct_slots:
			options.append(correct_words.pop_at(rng.randi_range(0, correct_words.size() - 1)))
			valid_indices.append(i)
		else:
			options.append(distractor_words.pop_at(rng.randi_range(0, distractor_words.size() - 1)))
	# Shuffle options and rebuild valid indices so fallback also supports 1-2 correct lanes.
	var tagged: Array = []
	for i in range(options.size()):
		tagged.append({"word": options[i], "valid": i in valid_indices})
	# Use this game RNG, not a global RNG, for reproducible seeded QA.
	for index in range(tagged.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var temporary: Dictionary = tagged[index]
		tagged[index] = tagged[other]
		tagged[other] = temporary
	options.clear()
	valid_indices.clear()
	for i in range(tagged.size()):
		options.append(String(tagged[i]["word"]))
		if bool(tagged[i]["valid"]):
			valid_indices.append(i)
	return {
		"prompt": "FIND THE %s" % canonical.to_upper(),
		"options": options,
		"valid_indices": valid_indices,
	}


func _resolve_at_answer_line(require_live_collision: bool = false) -> void:
	if gate_resolved or finished or paused or not running or _tutorial_active:
		return
	gate_resolved = true
	attempts += 1
	var flight := get_node_or_null("HybridFlight3D") as Node2D
	if flight != null and bool(flight.get("hybrid_enabled")) and bool(flight.get("draw_3d_gates")):
		selected_lane = int(flight.call("physical_lane_at_answer_line", require_live_collision))
	else:
		selected_lane = _lane_hit_at_answer_line()
	var valid: Array = round_data.get("valid_indices", [])
	selected_was_correct = selected_lane >= 0 and selected_lane in valid
	if selected_was_correct:
		correct_count += 1
		speed_boost_count += 1
		speed_multiplier = _earned_gate_speed_multiplier()
		streak += 1
		score += POINTS_PER_CORRECT_GATE
		feedback_text = "+%d  CORRECT!" % POINTS_PER_CORRECT_GATE
		feedback_color = GREEN
		_show_floating_score("+%d" % POINTS_PER_CORRECT_GATE, Color("#4EF082"))
		_play_voice_feedback(true)
	elif selected_lane >= 0:
		streak = 0
		if is_lives_mode:
			lives = maxi(lives - 1, 0)
		var options: Array = round_data.get("options", [])
		feedback_text = "TRY AGAIN  •  %s" % String(options[selected_lane])
		feedback_color = RED
		_show_floating_score("+0", Color(0.12, 0.12, 0.12, 1.0))
		_play_voice_feedback(false)
	else:
		streak = 0
		if is_lives_mode:
			lives = maxi(lives - 1, 0)
		feedback_text = "MISSED THE GATES  •  TRY AGAIN"
		feedback_color = YELLOW
		_show_floating_score("+0", Color(0.12, 0.12, 0.12, 1.0))
		_play_voice_feedback(false, true)
	feedback_time = 1.15
	# Update the serialized heart/score sprites immediately when a gate resolves;
	# don't show the old hearts until the next rendering/process tick.
	_sync_visuals()
	if is_lives_mode and lives <= 0:
		_finish_round("OUT OF LIVES")


func _show_floating_score(value: String, color: Color) -> void:
	# Catch's +100 / zero-points 28pt outlined pop-and-rise, using ONE
	# reusable editor-authored Label. Its destination derives from the actual
	# authored PlaneRig position, not hardcoded viewport coordinates.
	if not is_instance_valid(_floating_score):
		return
	if _floating_score_tween != null and _floating_score_tween.is_running():
		_floating_score_tween.kill()
	_floating_score.text = value
	_floating_score.add_theme_color_override("font_color", color)
	var pilot := $PlaneRig as Control
	# The answer may resolve before the next _sync_visuals() updates PlaneRig.
	# Read the SAME current authoritative collision/steering coordinates as
	# scoring, never the previous render frame's visual rig X.
	var label_size := _floating_score.size
	# A missed gate can occur at the edge of the camera frame. Keep the
	# Catch-style +0 readable even when a test/recovery state is out-of-range.
	var pilot_center := Vector2(clampf(_plane_center_x(), label_size.x * 0.5,
		maxf(label_size.x * 0.5, size.x - label_size.x * 0.5)), _plane_y())
	_floating_score.position = pilot_center - Vector2(label_size.x * 0.5, pilot.size.y * 0.70)
	_floating_score.modulate.a = 1.0
	_floating_score.scale = Vector2.ONE
	_floating_score.visible = true
	_floating_score_tween = create_tween().bind_node(_floating_score).set_parallel(true)
	_floating_score_tween.tween_property(_floating_score, "position:y",
		_floating_score.position.y - pilot.size.y * 0.6, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_floating_score_tween.tween_property(_floating_score, "modulate:a", 0.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_floating_score_tween.chain().tween_callback(func() -> void: _floating_score.visible = false)


func _initialize_voice_feedback() -> void:
	if _kids_voice != null:
		return
	_kids_voice = KidsVoice.new()
	_kids_voice.setup(self)
	_feedback_voice = _kids_voice.get_voice_player()
	_feedback_voice.name = "HumanPlaneVoicePlayer"


func _play_voice_feedback(correct: bool, missed: bool = false) -> void:
	if _kids_voice == null or not is_instance_valid(_feedback_voice):
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
	_stop_voice_feedback()
	if _kids_voice != null:
		_kids_voice.release()


func _lane_hit_at_answer_line() -> int:
	# Legacy 2D fallback for the non-hybrid art view. Native 3D gameplay calls
	# physical_lane_at_answer_line() on the 3D flight renderer instead.
	# Lateral movement before the answer line never locks in a selection.
	var plane_x := _plane_center_x()
	var authored_hitbox := $PlaneRig/Hitbox as Control
	var half_hitbox := authored_hitbox.size.x * 0.5
	plane_x += authored_hitbox.get_rect().get_center().x - _plane_rig.size.x * 0.5
	if not is_finite(plane_x) or not is_finite(half_hitbox) or half_hitbox <= 0.0:
		return -1
	var hit_left := plane_x - half_hitbox
	var hit_right := plane_x + half_hitbox
	var answer_progress := _progress_for_answer_line()
	var overlapping_lane := -1
	var overlapping_rect := Rect2()
	var best_overlap := 0.0
	var second_overlap := 0.0
	var total_overlap := 0.0
	var overlap_count := 0
	for lane in range(3):
		# A gate's authored movement rect may be wider/taller than the actual
		# texture shown by STRETCH_KEEP_ASPECT_CENTERED. Only the *rendered*
		# sprite can be hit, never the transparent letterbox beside it.
		var rect := _gate_visible_rect(lane, answer_progress)
		if rect.size.x <= 0.0:
			continue
		var overlap := minf(hit_right, rect.end.x) - maxf(hit_left, rect.position.x)
		if overlap <= 0.0:
			continue
		overlap_count += 1
		total_overlap += overlap
		if overlap > best_overlap:
			second_overlap = best_overlap
			best_overlap = overlap
			overlapping_lane = lane
			overlapping_rect = rect
		else:
			second_overlap = maxf(second_overlap, overlap)
	if overlapping_lane < 0:
		return -1
	var hitbox_width := half_hitbox * 2.0
	if overlap_count > 1:
		# Example: 80/20 touching two rings selects the dominant one; 52/48
		# yields no score. Requiring at least half of the pilot hitbox inside
		# the leading ring prevents a tiny sliver from claiming a hit.
		if best_overlap < hitbox_width * MIN_DOMINANT_HITBOX_COVERAGE \
				or (best_overlap - second_overlap) < total_overlap * MIN_OVERLAP_LEAD_FRACTION:
			return -1
		return overlapping_lane
	if best_overlap < hitbox_width * MIN_RING_HITBOX_COVERAGE:
		return -1
	var center_offset := absf(plane_x - overlapping_rect.get_center().x)
	var safe_half_width := minf(overlapping_rect.size.x * RING_CENTER_WINDOW_RATIO,
		overlapping_rect.size.x * 0.5 - half_hitbox)
	if safe_half_width <= 0.0 or center_offset > safe_half_width:
		return -1
	return overlapping_lane


func _pause() -> void:
	if finished or paused:
		return
	paused = true
	running = false
	_stop_voice_feedback()
	# Pause is a real input boundary. Require a NEW fresh signed bank on
	# resume; otherwise last moment's velocity could move a ghost plane.
	set_airplane_pose_active(false)
	# Resume waits for a fresh body sample instead of replaying a target from
	# before the pause (the camera wrapper may have continued reading poses).
	target_x_norm = plane_x_norm
	round_completed = false
	# All sprites run on this same paused scene; there is no independent 3D
	# renderer that could keep moving after the gameplay has frozen.
	_sync_visuals()
	var payload := get_context()
	payload["round_completed"] = false
	requested.emit("pause", payload)


func _resume() -> void:
	if finished:
		return
	paused = false
	running = true
	_sync_visuals()


func _request_pause() -> void:
	if _tutorial_active:
		return
	_pause()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			_request_pause()
			get_viewport().set_input_as_handled()
		elif allow_keyboard_debug and not paused and not finished:
			# No-camera QA only; production retains pose-locked X exclusively.
			if event.keycode in [KEY_A, KEY_LEFT]:
				airplane_pose_active = true
				target_x_norm = clampf(target_x_norm - 0.28, 0.0, 1.0)
				get_viewport().set_input_as_handled()
			elif event.keycode in [KEY_D, KEY_RIGHT]:
				airplane_pose_active = true
				target_x_norm = clampf(target_x_norm + 0.28, 0.0, 1.0)
				get_viewport().set_input_as_handled()


# All visible artwork is editor-authored PNG arch TextureRects and Labels.
# Hidden legacy ColorRect guides are unchanged; gates remain open for flight.
func _draw() -> void:
	pass


func _draw_hud() -> void:
	# Legacy QA entry point: the actual HUD is editable in the scene.
	_sync_visuals()


func _draw_plane() -> void:
	# Legacy QA entry point: the plane is the authored PlaneRig.
	_sync_visuals()


func _sync_visuals() -> void:
	if not is_node_ready():
		return
	var score_number := $HUDLayer/HUD/ScoreNumber as Label
	score_number.text = str(score)
	# Match the original Catch score plaque while accommodating long scores.
	var score_font_size := 35
	while score_font_size > 16 and FONT.get_string_size(score_number.text, HORIZONTAL_ALIGNMENT_LEFT, -1, score_font_size).x > score_number.size.x - 18.0:
		score_font_size -= 2
	if score_number.get_theme_font_size("font_size") != score_font_size:
		score_number.add_theme_font_size_override("font_size", score_font_size)
	var timer := $HUDLayer/HUD/TimerPlaque as TextureRect
	var time_text := $HUDLayer/HUD/TimeLabel as Label
	var lives_artwork := $HUDLayer/HUD/LivesPlaque as TextureRect
	var next_artwork := LIVES_PLAQUE_STATES[clampi(lives, 0, LIVES_ROUND_ALLOWANCE)] as Texture2D
	if lives_artwork.texture != next_artwork:
		lives_artwork.texture = next_artwork
	timer.visible = is_seconds_mode
	time_text.visible = is_seconds_mode
	lives_artwork.visible = not is_seconds_mode
	if is_seconds_mode:
		time_text.text = "%ds" % int(ceil(time_remaining))
		# No duplicate FeedbackLabel: sound and result flow own feedback now.
	var prompt := $HUDLayer/HUD/PromptLabel as Label
	var article := "AN" if topic in ["Adjective", "Adverb"] else "A"
	var prompt_text := "WHICH WORD IS %s %s?" % [article, topic.to_upper()]
	if prompt_text != _last_prompt_text:
		_last_prompt_text = prompt_text
		prompt.text = prompt_text
		var prompt_font_size := 24
		while prompt_font_size > 17 and FONT.get_string_size(prompt_text, HORIZONTAL_ALIGNMENT_LEFT, -1, prompt_font_size).x > prompt.size.x - 10.0:
			prompt_font_size -= 1
		prompt.add_theme_font_size_override("font_size", prompt_font_size)
	# The scene-authored PlaneRig's Y and dimensions are never overwritten.
	_plane_rig.position.x = _plane_center_x() - _plane_rig.size.x * 0.5
	_render_gate_trio(_gate_nodes, round_data, gate_progress,
		_authored_gate_colors, _authored_gate_rect_offsets, gate_resolved)
	if not next_round_data.is_empty():
		_render_gate_trio(_upcoming_gate_nodes, next_round_data, next_gate_progress,
			_upcoming_gate_colors, _upcoming_rect_offsets, false, true)
	# Native 3D TorusMesh and 2D word plaques use corresponding pooled guides.


func _normalized_scoring_lane_centers(answer_progress: float) -> PackedFloat32Array:
	# Convert artist-authored 2D lane centers to the SAME 0..1 calibrated
	# steering coordinates used by the 3D airplane. Moving a Godot editor
	# guide moves the physical torus target, with the renderer checking its
	# actual ring opening rather than a transparent 2D artwork rectangle.
	var left_x := _plane_left_limit.get_rect().get_center().x
	var right_x := _plane_right_limit.get_rect().get_center().x
	var width := right_x - left_x
	var hitbox := $PlaneRig/Hitbox as Control
	if width <= 0.0 or hitbox == null:
		return PackedFloat32Array()
	var hitbox_offset := hitbox.get_rect().get_center().x - _plane_rig.size.x * 0.5
	var centers := PackedFloat32Array()
	for lane in range(3):
		var visible_rect := _gate_visible_rect(lane, answer_progress)
		if visible_rect.size.x <= 0.0:
			return PackedFloat32Array()
		var norm := (visible_rect.get_center().x - left_x - _plane_authored_offset_x - hitbox_offset) / width
		if not is_finite(norm):
			return PackedFloat32Array()
		centers.append(norm)
	return centers


func _render_gate_trio(gates: Array[Control], data: Dictionary, progress: float,
		colors: Array[Dictionary], offsets: Array[Rect2], resolved: bool,
		upcoming: bool = false) -> void:
	var options: Array = data.get("options", [])
	var passage_alpha := _gate_passage_alpha(progress) if resolved else 1.0
	var renderer := get_node_or_null("HybridFlight3D") as Node2D
	for i in range(3):
		var gate := gates[i] as Control
		gate.visible = i < options.size() and not finished
		if not gate.visible:
			continue
		# Full opacity through the aircraft, with a tiny fade once the ring is
		# already outside the camera. Reuse the same original label and plaque.
		gate.modulate.a = passage_alpha
		var rect := _gate_rect_with_offsets(i, progress, offsets)
		# Authored guides place the physical target rings; the 2D word plaques
		# follow their visual positions and never decide a 3D collision.
		var visual_center := rect.get_center()
		if renderer != null and bool(renderer.get("hybrid_enabled")) and bool(renderer.get("draw_3d_gates")):
			var ring_rect := _gate_visible_rect_with_offsets(i, progress, offsets, gates)
			visual_center = renderer.call("gate_screen_center", i, progress, ring_rect, upcoming,
				offsets, gates)
			var guide_center := ring_rect.get_center()
			rect.position += visual_center - guide_center
		gate.position = rect.position
		gate.size = rect.size
		var word_label := gate.get_node("WordLabel") as Label
		var word_plate := gate.get_node("WordPlate") as CanvasItem
		word_label.text = String(options[i]).to_upper()
		# Words are fully readable BEFORE scoring, including three authentic
		# incoming vocabulary options. Once resolved, the outgoing wooden
		# plaques vanish so they cannot obscure the airplane passing THROUGH
		# the ring; its real 3D TorusMesh remains until past the camera.
		word_label.visible = not resolved
		word_plate.visible = not resolved
		# Original wooden word plaques should be readable before the crossing
		# line, particularly on classroom projectors. Preserve their authoring.
		# The editor-authored cream WordPlate is wider than the torus opening.
		# Fit text to the PLATE, not the former 70%-of-ring safe area: otherwise
		# long real GrammarBank words become 9-13px even on 1080p classroom TVs.
		var fit := _gate_word_fit(word_label.text, rect.size.x * 1.12, int(clampf(rect.size.x * 0.135, 12.0, 31.0)))
		word_label.add_theme_font_size_override("font_size", int(fit["font_size"]))
		word_label.pivot_offset.x = word_label.size.x * 0.5
		word_label.scale.x = float(fit["scale_x"])
		_keep_word_clear_of_catch_score(gate, word_plate as Control, word_label)
		for part in ["LeftPillar", "RightPillar", "TopBar"]:
			var authored_color: Color = colors[i][part]
			if resolved and not upcoming and i == selected_lane:
				authored_color = GREEN if selected_was_correct else RED
			(gate.get_node(part) as ColorRect).color = authored_color


func _keep_word_clear_of_catch_score(gate: Control, word_plate: Control, word_label: Label) -> void:
	# Uses ONLY two editor-authored rectangles and original per-gate anchors.
	# The Catch-identical ScorePlaque position is NEVER adjusted at runtime;
	# gate travel, words, hitboxes, and three-lane scoring remain unchanged.
	for item in [word_plate, word_label]:
		var authored: Vector4 = _editor_word_offsets.get(item.get_instance_id(),
			Vector4(item.offset_left, item.offset_top, item.offset_right, item.offset_bottom))
		item.offset_left = authored.x
		item.offset_top = authored.y
		item.offset_right = authored.z
		item.offset_bottom = authored.w
	var plaque := $HUDLayer/HUD/ScorePlaque as TextureRect
	if not gate.visible or not word_plate.visible or not plaque.is_visible_in_tree():
		return
	var word_box := word_plate.get_global_rect()
	var score_box := plaque.get_global_rect()
	if not score_box.intersects(word_box):
		return
	var padding := maxf(3.0, float(word_label.get_theme_font_size("font_size")) * 0.25)
	var shift := minf(0.0, score_box.position.y - padding - word_box.end.y) / \
		maxf(gate.get_global_transform().get_scale().y, 0.001)
	for item in [word_plate, word_label]:
		item.offset_top += shift
		item.offset_bottom += shift


func _gate_passage_alpha(progress: float) -> float:
	if not gate_resolved:
		return 1.0
	var answer_progress := clampf(_progress_for_answer_line(), 0.0, 0.999)
	var beyond := clampf((progress - answer_progress) / maxf(1.0 - answer_progress, 0.001), 0.0, 1.0)
	if beyond <= GATE_PASSAGE_FADE_START:
		return 1.0
	var remaining := clampf((1.0 - beyond) / (1.0 - GATE_PASSAGE_FADE_START), 0.0, 1.0)
	return remaining * remaining * (3.0 - 2.0 * remaining)


func _on_scene_resized() -> void:
	# Scale only the overall 1280×720 Catch HUD, not its cloned draggable
	# editor-authored children. Their offsets remain byte-for-byte from Catch.
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = size
	var hud_scale := maxf(0.01, minf(viewport_size.x / 1280.0, viewport_size.y / 720.0))
	_catch_hud.scale = Vector2.ONE * hud_scale
		# The 3D layer has its own viewport resize handling and editor-authored
		# cloud hierarchy; only 2D HUD uses this responsive scaling.
	_sync_visuals()
	_layout_tutorial_spotlight()


func _gate_rect(lane: int, progress: float) -> Rect2:
	return _gate_rect_with_offsets(lane, progress, _authored_gate_rect_offsets)


func _gate_rect_with_offsets(lane: int, progress: float, offsets: Array[Rect2]) -> Rect2:
	var index := clampi(lane, 0, 2)
	var start := _gate_starts[index].get_rect()
	var destination := _gate_ends[index].get_rect()
	# Small beyond-end extrapolation lets the passed gate fly offscreen while
	# the subsequent gate is already approaching; never changes guide markers.
	var amount := _gate_eased_progress(progress)
	var authored_offset := offsets[index] if offsets.size() == 3 else Rect2()
	return Rect2(start.position.lerp(destination.position, amount) + authored_offset.position, start.size.lerp(destination.size, amount) + authored_offset.size)


func _gate_eased_progress(progress: float) -> float:
	# Lou-style perspective: distance decreases continuously while apparent
	# projected size grows as focal/(focal+depth). We normalize the projection
	# so original teacher-editable GateStart and GateEnd stay exact endpoints.
	var fraction := clampf(progress, 0.0, 1.0)
	var far_scale := PSEUDO_FOCAL_LENGTH / (PSEUDO_FOCAL_LENGTH + PSEUDO_GATE_FAR_DEPTH)
	var near_scale := PSEUDO_FOCAL_LENGTH / (PSEUDO_FOCAL_LENGTH + PSEUDO_GATE_NEAR_DEPTH)
	var depth := lerpf(PSEUDO_GATE_FAR_DEPTH, PSEUDO_GATE_NEAR_DEPTH, fraction)
	var apparent_scale := PSEUDO_FOCAL_LENGTH / (PSEUDO_FOCAL_LENGTH + depth)
	return clampf((apparent_scale - far_scale) / (near_scale - far_scale), 0.0, 1.0)


func _gate_visible_rect(lane: int, progress: float) -> Rect2:
	return _gate_visible_rect_with_offsets(lane, progress, _authored_gate_rect_offsets, _gate_nodes)


func _gate_visible_rect_with_offsets(lane: int, progress: float,
		offsets: Array[Rect2], gates: Array[Control]) -> Rect2:
	# Project the editor-authored GateArtwork anchors/offsets into the gate's
	# animated scene rectangle. This represents the actual image draw area,
	# including teacher edits to the artwork's placement and to the gate path.
	# KeepAspectCentered is an inscribed rectangle, NOT the whole gate Control.
	var gate_rect := _gate_rect_with_offsets(lane, progress, offsets)
	var artwork := gates[clampi(lane, 0, 2)].get_node("GateArtwork") as TextureRect
	var draw_box := Rect2(
		gate_rect.position + Vector2(gate_rect.size.x * artwork.anchor_left + artwork.offset_left, gate_rect.size.y * artwork.anchor_top + artwork.offset_top),
		Vector2(gate_rect.size.x * (artwork.anchor_right - artwork.anchor_left) + artwork.offset_right - artwork.offset_left,
		gate_rect.size.y * (artwork.anchor_bottom - artwork.anchor_top) + artwork.offset_bottom - artwork.offset_top)
	)
	if artwork.texture == null or draw_box.size.x <= 0.0 or draw_box.size.y <= 0.0:
		return Rect2(draw_box.position, Vector2.ZERO)
	var image_size := artwork.texture.get_size()
	if image_size.x <= 0.0 or image_size.y <= 0.0:
		return Rect2(draw_box.position, Vector2.ZERO)
	match artwork.stretch_mode:
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			var scale_value := minf(draw_box.size.x / image_size.x, draw_box.size.y / image_size.y)
			var rendered_size := image_size * scale_value
			return Rect2(draw_box.position + (draw_box.size - rendered_size) * 0.5, rendered_size)
		TextureRect.STRETCH_KEEP_ASPECT:
			var scale_value := minf(draw_box.size.x / image_size.x, draw_box.size.y / image_size.y)
			return Rect2(draw_box.position, image_size * scale_value)
		_:
			# Covered and scaled modes draw/crop across the authored TextureRect.
			return draw_box


func _gate_y(progress: float) -> float:
	# Follow the visible CENTER gate artwork, including its editor-authored
	# placement, instead of resolving while the sprite is elsewhere vertically.
	return _gate_visible_rect(1, progress).get_center().y


func _progress_for_answer_line() -> float:
	# Binary search the SAME eased visible path used by the actual gate art,
	# so collision timing matches its painted position during every wave.
	var low := 0.0
	var high := 1.0
	var target := _answer_line_y()
	for _i in range(16):
		var middle := (low + high) * 0.5
		if _gate_y(middle) < target:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


func _answer_line_y() -> float:
	if is_instance_valid(_answer_line):
		return _answer_line.get_rect().get_center().y
	return _gate_ends[1].get_rect().get_center().y


func _plane_y() -> float:
	return _plane_rig.get_rect().get_center().y


func _plane_center_x() -> float:
	var left_x := _plane_left_limit.get_rect().get_center().x
	var right_x := _plane_right_limit.get_rect().get_center().x
	return lerpf(left_x, right_x, plane_x_norm) + _plane_authored_offset_x


func _scaled(value: float) -> float:
	return value * clampf(size.y / 720.0, 0.86, 1.50)


func _gate_word_fit(word: String, gate_width: float, preferred_size: int) -> Dictionary:
	var available := maxf(gate_width * 0.88, 1.0)
	# Even the far gate's native 144px-tall lane artwork has room for 20px
	# glyphs in the wider cream plaque. Shrink long words horizontally instead
	# of turning them into tiny 9px text as they approach the player.
	var minimum_readable := 20
	var font_size := maxi(preferred_size, minimum_readable)
	var measured := FONT.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	while measured > available and font_size > minimum_readable:
		font_size -= 1
		measured = FONT.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	return {"font_size": font_size, "scale_x": minf(1.0, available / maxf(measured, 1.0)), "rendered_width": minf(measured, available)}


func _life_text() -> String:
	var hearts := ""
	for _i in range(lives):
		hearts += "\u25CF"
	return hearts if not hearts.is_empty() else "0"


func _first_text(source: Dictionary, keys: Array, fallback: String) -> String:
	for key in keys:
		if source.has(key):
			var value := String(source[key]).strip_edges()
			if not value.is_empty():
				return value
	return fallback


func _canonical_topic(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	for candidate in ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]:
		if candidate.to_lower() == normalized:
			return candidate
	return "Noun"


func _canonical_difficulty(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	if normalized == "medium":
		normalized = "normal"
	for candidate in ["Easy", "Normal", "Hard"]:
		if candidate.to_lower() == normalized:
			return candidate
	return "Normal"
