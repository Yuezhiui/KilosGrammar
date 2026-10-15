extends Control

signal requested(target: String, payload: Dictionary)

const FONT := preload("res://assets/fonts/TitanOne-Regular.ttf")
const GRAMMAR_BANK_PATH := "res://ui/minigames/grammar_bank.gd"

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

const DIFFICULTY_CONFIG := {
	"Easy": {"waves": 12, "time": 80.0, "lives": 5, "gate_speed": 0.34, "bonus": 0},
	"Normal": {"waves": 14, "time": 70.0, "lives": 4, "gate_speed": 0.40, "bonus": 20},
	"Hard": {"waves": 16, "time": 60.0, "lives": 3, "gate_speed": 0.47, "bonus": 40},
}

const FALLBACK_WORDS := {
	"Noun": ["APPLE", "TEACHER", "RIVER", "BOOK", "SCHOOL", "DOG"],
	"Pronoun": ["HE", "SHE", "THEY", "WE", "IT", "YOU"],
	"Verb": ["RUN", "WRITE", "JUMP", "READ", "SING", "CLIMB"],
	"Adjective": ["BRIGHT", "TALL", "HAPPY", "SMALL", "QUIET", "BLUE"],
	"Adverb": ["QUICKLY", "SOFTLY", "ALWAYS", "CAREFULLY", "LOUDLY", "SLOWLY"],
}

var context: Dictionary = {}
var rng := RandomNumberGenerator.new()
var grammar_bank: Script

var topic := "Noun"
var difficulty := "Normal"
var score := 0
var correct_count := 0
var attempts := 0
var streak := 0
var lives := 4
var waves_total := 14
var waves_completed := 0
var time_remaining := 70.0

var started := false
var running := false
var finished := false
var round_completed := false
var paused := false

var round_data: Dictionary = {}
var gate_progress := 0.0
var gate_resolved := false
var selected_lane := -1
var selected_was_correct := false
var inter_wave_delay := 0.0

var target_x_norm := 0.5
var plane_x_norm := 0.5
var keyboard_velocity := 0.0

var feedback_text := ""
var feedback_color := CREAM
var feedback_time := 0.0
var cloud_scroll := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	set_process_unhandled_key_input(true)
	resized.connect(queue_redraw)
	_style_pause_button()
	%PauseButton.pressed.connect(_request_pause)
	rng.randomize()
	if ResourceLoader.exists(GRAMMAR_BANK_PATH):
		grammar_bank = load(GRAMMAR_BANK_PATH) as Script
	call_deferred("_ensure_started")


func set_context(new_context: Dictionary) -> void:
	context = new_context.duplicate(true)
	if not started:
		_apply_initial_context()
	else:
		# Runtime callers may update presentation context, but active game state wins.
		topic = _canonical_topic(_first_text(context, ["topic", "game_style"], topic))
		difficulty = _canonical_difficulty(_first_text(context, ["difficulty"], difficulty))
	queue_redraw()


func get_context() -> Dictionary:
	var payload := context.duplicate(true)
	payload["activity"] = "Human Plane"
	payload["topic"] = topic
	payload["game_style"] = topic
	payload["difficulty"] = difficulty
	payload["score"] = score
	payload["correct"] = correct_count
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
	return payload


func set_body_x(normalized_x: float) -> void:
	# Future camera bridge: -1.0 = left edge, 0.0 = center, +1.0 = right edge.
	var camera_value := clampf(normalized_x, -1.0, 1.0)
	target_x_norm = clampf((camera_value + 1.0) * 0.5, 0.055, 0.945)


func _finish_round() -> void:
	if finished:
		return
	finished = true
	running = false
	paused = false
	round_completed = true
	feedback_text = "ROUND COMPLETE"
	feedback_color = GREEN
	queue_redraw()
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
	queue_redraw()


func _apply_initial_context() -> void:
	topic = _canonical_topic(_first_text(context, ["topic", "game_style"], "Noun"))
	difficulty = _canonical_difficulty(_first_text(context, ["difficulty"], "Normal"))
	var config: Dictionary = DIFFICULTY_CONFIG[difficulty]
	waves_total = int(context.get("total", config["waves"]))
	waves_total = maxi(waves_total, 10)
	score = maxi(int(context.get("score", 0)), 0)
	correct_count = maxi(int(context.get("correct", 0)), 0)
	attempts = maxi(int(context.get("attempts", 0)), 0)
	streak = maxi(int(context.get("streak", 0)), 0)
	waves_completed = clampi(int(context.get("waves_completed", attempts)), 0, waves_total)
	lives = maxi(int(context.get("lives", config["lives"])), 0)
	time_remaining = maxf(float(context.get("time_remaining", config["time"])), 0.0)
	var restored_body_x := clampf(float(context.get("body_x", 0.0)), -1.0, 1.0)
	target_x_norm = clampf((restored_body_x + 1.0) * 0.5, 0.055, 0.945)
	plane_x_norm = target_x_norm
	finished = false
	paused = false
	round_completed = false


func _process(delta: float) -> void:
	if not started:
		return
	if paused:
		return
	cloud_scroll = fposmod(cloud_scroll + delta * 10.0, maxf(size.x, 1.0))
	_update_plane_motion(delta)
	if feedback_time > 0.0:
		feedback_time = maxf(feedback_time - delta, 0.0)
	if running and not finished:
		time_remaining = maxf(time_remaining - delta, 0.0)
		if time_remaining <= 0.0:
			feedback_text = "TIME!"
			feedback_color = YELLOW
			_finish_round()
		else:
			_update_gate_wave(delta)
	queue_redraw()


func _update_plane_motion(delta: float) -> void:
	var axis := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A):
		axis -= 1.0
	if Input.is_key_pressed(KEY_D):
		axis += 1.0
	axis = clampf(axis, -1.0, 1.0)
	var desired_velocity := axis * 0.72
	keyboard_velocity = move_toward(keyboard_velocity, desired_velocity, 2.9 * delta)
	if absf(axis) < 0.01:
		keyboard_velocity = move_toward(keyboard_velocity, 0.0, 2.2 * delta)
	target_x_norm = clampf(target_x_norm + keyboard_velocity * delta, 0.055, 0.945)
	# Exponential ease means even a large camera target change glides rather than teleports.
	var follow := 1.0 - exp(-7.5 * delta)
	plane_x_norm = lerpf(plane_x_norm, target_x_norm, follow)


func _update_gate_wave(delta: float) -> void:
	if inter_wave_delay > 0.0:
		inter_wave_delay = maxf(inter_wave_delay - delta, 0.0)
		if inter_wave_delay <= 0.0:
			if lives <= 0 or waves_completed >= waves_total:
				_finish_round()
			else:
				_start_wave()
		return
	if round_data.is_empty():
		return
	var previous_y := _gate_y(gate_progress)
	var config: Dictionary = DIFFICULTY_CONFIG[difficulty]
	gate_progress = minf(gate_progress + float(config["gate_speed"]) * delta, 1.0)
	var current_y := _gate_y(gate_progress)
	var answer_y := _answer_line_y()
	if not gate_resolved and previous_y < answer_y and current_y >= answer_y:
		_resolve_at_answer_line()
	if gate_progress >= 1.0:
		if not gate_resolved:
			_resolve_at_answer_line()
		waves_completed += 1
		inter_wave_delay = 0.62


func _start_wave() -> void:
	if waves_completed >= waves_total or lives <= 0 or time_remaining <= 0.0:
		_finish_round()
		return
	round_data = _make_lane_round()
	gate_progress = 0.0
	gate_resolved = false
	selected_lane = -1
	selected_was_correct = false
	feedback_text = ""
	feedback_time = 0.0


func _make_lane_round() -> Dictionary:
	if grammar_bank != null:
		var generated: Variant = grammar_bank.call("lane_round", topic, difficulty, rng)
		if generated is Dictionary and _round_is_valid(generated):
			return generated
	return _fallback_lane_round()


func _round_is_valid(value: Dictionary) -> bool:
	if not value.has("prompt") or not value.has("options") or not value.has("valid_indices"):
		return false
	var options: Array = value["options"]
	var valid: Array = value["valid_indices"]
	if options.size() != 3 or valid.is_empty() or valid.size() > 2:
		return false
	for index in valid:
		if int(index) < 0 or int(index) >= 3:
			return false
	return true


func _fallback_lane_round() -> Dictionary:
	var canonical := _canonical_topic(topic)
	var correct_words: Array = FALLBACK_WORDS[canonical]
	var distractor_topics := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
	distractor_topics.erase(canonical)
	var options: Array[String] = []
	var valid_indices: Array[int] = []
	var correct_slots := 2 if difficulty == "Hard" and rng.randf() < 0.35 else 1
	var slot_order := [0, 1, 2]
	slot_order.shuffle()
	for i in range(3):
		if i < correct_slots:
			options.append(String(correct_words[rng.randi_range(0, correct_words.size() - 1)]))
			valid_indices.append(i)
		else:
			var other_topic: String = distractor_topics[rng.randi_range(0, distractor_topics.size() - 1)]
			var bank: Array = FALLBACK_WORDS[other_topic]
			options.append(String(bank[rng.randi_range(0, bank.size() - 1)]))
	# Shuffle options and rebuild valid indices so fallback also supports 1-2 correct lanes.
	var tagged: Array = []
	for i in range(options.size()):
		tagged.append({"word": options[i], "valid": i in valid_indices})
	tagged.shuffle()
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


func _resolve_at_answer_line() -> void:
	if gate_resolved:
		return
	gate_resolved = true
	attempts += 1
	selected_lane = _lane_hit_at_answer_line()
	var valid: Array = round_data.get("valid_indices", [])
	selected_was_correct = selected_lane >= 0 and selected_lane in valid
	if selected_was_correct:
		correct_count += 1
		streak += 1
		var config: Dictionary = DIFFICULTY_CONFIG[difficulty]
		var gained := 100 + int(config["bonus"]) + maxi(streak - 1, 0) * 10
		score += gained
		feedback_text = "+%d  CORRECT!" % gained
		feedback_color = GREEN
	elif selected_lane >= 0:
		streak = 0
		lives = maxi(lives - 1, 0)
		score = maxi(score - 40, 0)
		var options: Array = round_data.get("options", [])
		feedback_text = "WRONG GATE  •  %s" % String(options[selected_lane])
		feedback_color = RED
	else:
		streak = 0
		lives = maxi(lives - 1, 0)
		score = maxi(score - 20, 0)
		feedback_text = "MISSED THE GATES  •  -1 LIFE"
		feedback_color = YELLOW
	feedback_time = 1.15


func _lane_hit_at_answer_line() -> int:
	# Deliberately sampled only when the approaching gates cross the answer line.
	# Lateral movement before this moment never selects the center (or any other) lane.
	var plane_x := _plane_center_x()
	var half_hitbox := _scaled(22.0)
	var hit_left := plane_x - half_hitbox
	var hit_right := plane_x + half_hitbox
	var answer_progress := _progress_for_answer_line()
	for lane in range(3):
		var rect := _gate_rect(lane, answer_progress)
		if hit_right >= rect.position.x and hit_left <= rect.end.x:
			return lane
	return -1


func _pause() -> void:
	if finished or paused:
		return
	paused = true
	running = false
	keyboard_velocity = 0.0
	round_completed = false
	var payload := get_context()
	payload["round_completed"] = false
	requested.emit("pause", payload)


func _resume() -> void:
	if finished:
		return
	paused = false
	running = true
	queue_redraw()


func _request_pause() -> void:
	_pause()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			_request_pause()
			get_viewport().set_input_as_handled()


func _draw() -> void:
	_draw_sky()
	_draw_landscape()
	_draw_lane_guides()
	_draw_answer_line()
	_draw_gates()
	_draw_plane()
	_draw_hud()
	_draw_feedback()


func _draw_sky() -> void:
	var bands := 8
	for i in range(bands):
		var t := float(i) / float(bands - 1)
		var color := SKY_TOP.lerp(SKY_BOTTOM, t)
		var y := size.y * 0.0 + size.y * 0.62 * float(i) / bands
		draw_rect(Rect2(0.0, y, size.x, size.y * 0.62 / bands + 2.0), color)
	draw_circle(Vector2(size.x * 0.84, size.y * 0.16), _scaled(42.0), Color(YELLOW, 0.88))
	_draw_cloud(size.x * 0.15 - cloud_scroll * 0.28, size.y * 0.18, 0.9)
	_draw_cloud(size.x * 0.48 - cloud_scroll * 0.18, size.y * 0.11, 0.72)
	_draw_cloud(size.x * 0.79 - cloud_scroll * 0.24, size.y * 0.29, 1.0)
	_draw_cloud(fposmod(size.x * 1.15 - cloud_scroll * 0.28, size.x * 1.25) - size.x * 0.12, size.y * 0.21, 0.82)


func _draw_cloud(x: float, y: float, scale_value: float) -> void:
	var r := _scaled(22.0) * scale_value
	var c := Color(WHITE, 0.84)
	draw_circle(Vector2(x, y), r, c)
	draw_circle(Vector2(x + r * 0.9, y - r * 0.28), r * 1.15, c)
	draw_circle(Vector2(x + r * 1.9, y), r * 0.9, c)
	draw_rect(Rect2(x, y, r * 2.0, r * 0.7), c)


func _draw_landscape() -> void:
	var horizon := size.y * 0.42
	var far := PackedVector2Array([
		Vector2(0, horizon + _scaled(42)), Vector2(size.x * 0.12, horizon - _scaled(25)),
		Vector2(size.x * 0.25, horizon + _scaled(22)), Vector2(size.x * 0.39, horizon - _scaled(52)),
		Vector2(size.x * 0.54, horizon + _scaled(12)), Vector2(size.x * 0.68, horizon - _scaled(32)),
		Vector2(size.x * 0.84, horizon + _scaled(18)), Vector2(size.x, horizon - _scaled(20)),
		Vector2(size.x, size.y), Vector2(0, size.y)
	])
	draw_colored_polygon(far, Color("#7BAF7B"))
	draw_rect(Rect2(0, size.y * 0.55, size.x, size.y * 0.45), Color("#8FCC75"))
	# Perspective runway/flight corridor.
	var vanishing := Vector2(size.x * 0.5, size.y * 0.34)
	var runway := PackedVector2Array([
		Vector2(size.x * 0.42, size.y), vanishing, Vector2(size.x * 0.58, size.y)
	])
	draw_colored_polygon(runway, Color("#6FAF8F"))


func _draw_lane_guides() -> void:
	var vanish := Vector2(size.x * 0.5, size.y * 0.34)
	for i in range(4):
		var bottom_x := size.x * (0.08 + 0.28 * i)
		draw_line(vanish, Vector2(bottom_x, size.y), Color(WHITE, 0.22), _scaled(2.0))


func _draw_answer_line() -> void:
	var y := _answer_line_y()
	var dash := _scaled(18.0)
	var gap := _scaled(10.0)
	var x := size.x * 0.07
	while x < size.x * 0.93:
		draw_line(Vector2(x, y), Vector2(minf(x + dash, size.x * 0.93), y), Color(YELLOW, 0.92), _scaled(4.0))
		x += dash + gap
	_draw_text("ANSWER LINE", Vector2(size.x * 0.07, y - _scaled(10.0)), 12, INK, HORIZONTAL_ALIGNMENT_LEFT, _scaled(180.0))


func _draw_gates() -> void:
	if round_data.is_empty():
		return
	var options: Array = round_data.get("options", [])
	for lane in range(mini(options.size(), 3)):
		var rect := _gate_rect(lane, gate_progress)
		var color: Color = LANE_COLORS[lane]
		if gate_resolved and lane == selected_lane:
			color = GREEN if selected_was_correct else RED
		_draw_gate(rect, String(options[lane]), color, lane)


func _draw_gate(rect: Rect2, option: String, color: Color, lane: int) -> void:
	var pillar := maxf(rect.size.x * 0.105, _scaled(7.0))
	var top_h := maxf(rect.size.y * 0.23, _scaled(24.0))
	draw_rect(Rect2(rect.position + Vector2(_scaled(5), _scaled(7)), rect.size), Color(INK, 0.20))
	draw_rect(Rect2(rect.position, Vector2(pillar, rect.size.y)), color)
	draw_rect(Rect2(Vector2(rect.end.x - pillar, rect.position.y), Vector2(pillar, rect.size.y)), color)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x, top_h)), color)
	draw_rect(Rect2(rect.position + Vector2(pillar, top_h), Vector2(rect.size.x - pillar * 2.0, rect.size.y - top_h)), Color(WHITE, 0.10))
	var font_size := int(clampf(rect.size.x * 0.105, _scaled(11.0), _scaled(22.0)))
	_draw_text(option.to_upper(), Vector2(rect.position.x, rect.position.y + top_h * 0.73), font_size, CREAM, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
	var lane_size := int(clampf(rect.size.x * 0.065, _scaled(8.0), _scaled(13.0)))
	_draw_text(LANE_NAMES[lane], Vector2(rect.position.x, rect.end.y - _scaled(8.0)), lane_size, Color(CREAM, 0.78), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


func _draw_plane() -> void:
	var c := Vector2(_plane_center_x(), _plane_y())
	var s := _scaled(1.0)
	# Small explicit hitbox cue beneath the aircraft.
	var hitbox := Rect2(c.x - _scaled(22), c.y - _scaled(10), _scaled(44), _scaled(20))
	draw_rect(hitbox, Color(YELLOW, 0.13), false, _scaled(1.5))
	# Original procedural airplane silhouette.
	var body := PackedVector2Array([
		c + Vector2(0, -34) * s, c + Vector2(13, -12) * s,
		c + Vector2(12, 31) * s, c + Vector2(0, 43) * s,
		c + Vector2(-12, 31) * s, c + Vector2(-13, -12) * s
	])
	draw_colored_polygon(body, Color("#F05A63"))
	var wings := PackedVector2Array([
		c + Vector2(-13, -5) * s, c + Vector2(-62, 18) * s,
		c + Vector2(-48, 29) * s, c + Vector2(0, 13) * s,
		c + Vector2(48, 29) * s, c + Vector2(62, 18) * s,
		c + Vector2(13, -5) * s
	])
	draw_colored_polygon(wings, Color("#F7C648"))
	var tail := PackedVector2Array([
		c + Vector2(-9, 25) * s, c + Vector2(-30, 39) * s,
		c + Vector2(0, 35) * s, c + Vector2(30, 39) * s,
		c + Vector2(9, 25) * s
	])
	draw_colored_polygon(tail, Color("#62B8E8"))
	draw_circle(c + Vector2(0, -13) * s, _scaled(8.0), Color("#BFEAFF"))
	draw_circle(c + Vector2(0, -13) * s, _scaled(8.0), INK, false, _scaled(2.0))


func _draw_hud() -> void:
	var top_rect := Rect2(size.x * 0.17, _scaled(16), size.x * 0.66, _scaled(64))
	draw_rect(Rect2(top_rect.position + Vector2(_scaled(4), _scaled(5)), top_rect.size), Color(INK, 0.20))
	draw_rect(top_rect, Color(INK, 0.90))
	_draw_text("SCORE %04d" % score, Vector2(top_rect.position.x + _scaled(18), top_rect.position.y + _scaled(40)), 18, CREAM, HORIZONTAL_ALIGNMENT_LEFT, top_rect.size.x * 0.24)
	_draw_text("LIVES %s" % _life_text(), Vector2(top_rect.position.x + top_rect.size.x * 0.25, top_rect.position.y + _scaled(40)), 18, RED, HORIZONTAL_ALIGNMENT_CENTER, top_rect.size.x * 0.24)
	_draw_text("WAVE %02d/%02d" % [mini(waves_completed + 1, waves_total), waves_total], Vector2(top_rect.position.x + top_rect.size.x * 0.50, top_rect.position.y + _scaled(40)), 17, MINT, HORIZONTAL_ALIGNMENT_CENTER, top_rect.size.x * 0.24)
	_draw_text("TIME %02d" % int(ceil(time_remaining)), Vector2(top_rect.position.x + top_rect.size.x * 0.76, top_rect.position.y + _scaled(40)), 18, YELLOW, HORIZONTAL_ALIGNMENT_RIGHT, top_rect.size.x * 0.21)
	var prompt_rect := Rect2(size.x * 0.27, _scaled(92), size.x * 0.46, _scaled(58))
	draw_rect(Rect2(prompt_rect.position + Vector2(_scaled(4), _scaled(5)), prompt_rect.size), Color(INK, 0.17))
	draw_rect(prompt_rect, Color(CREAM, 0.96))
	var prompt := "FIND THE %s" % topic.to_upper()
	_draw_text(prompt, Vector2(prompt_rect.position.x, prompt_rect.position.y + _scaled(37)), 22, INK, HORIZONTAL_ALIGNMENT_CENTER, prompt_rect.size.x)
	_draw_text("A / D  or  ← / →  •  STEER BEFORE THE GOLD LINE", Vector2(size.x * 0.26, size.y - _scaled(24)), 12, Color(INK, 0.80), HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.48)
	_draw_text(difficulty.to_upper(), Vector2(size.x * 0.76, size.y - _scaled(24)), 12, Color(INK, 0.75), HORIZONTAL_ALIGNMENT_CENTER, size.x * 0.13)


func _draw_feedback() -> void:
	if feedback_text.is_empty() or feedback_time <= 0.0:
		return
	var rect := Rect2(size.x * 0.32, size.y * 0.54, size.x * 0.36, _scaled(54))
	draw_rect(Rect2(rect.position + Vector2(_scaled(4), _scaled(5)), rect.size), Color(INK, 0.18))
	draw_rect(rect, Color(CREAM, 0.95))
	_draw_text(feedback_text, Vector2(rect.position.x, rect.position.y + _scaled(35)), 18, feedback_color, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)


func _gate_rect(lane: int, progress: float) -> Rect2:
	var p := clampf(progress, 0.0, 1.0)
	var horizon_center := size.x * 0.5
	var bottom_centers := [size.x * 0.22, size.x * 0.50, size.x * 0.78]
	var lane_center := lerpf(horizon_center + (lane - 1) * size.x * 0.055, float(bottom_centers[lane]), p)
	var width := lerpf(size.x * 0.09, size.x * 0.22, p)
	var height := lerpf(_scaled(58.0), _scaled(182.0), p)
	var y := _gate_y(p)
	return Rect2(lane_center - width * 0.5, y - height * 0.5, width, height)


func _gate_y(progress: float) -> float:
	return lerpf(size.y * 0.30, size.y * 0.88, clampf(progress, 0.0, 1.0))


func _progress_for_answer_line() -> float:
	var start_y := size.y * 0.30
	var end_y := size.y * 0.88
	return clampf((_answer_line_y() - start_y) / maxf(end_y - start_y, 1.0), 0.0, 1.0)


func _answer_line_y() -> float:
	# The collision check is performed when gate centers reach the airplane,
	# not ~100 pixels above it. This makes the drawn yellow line, small plane
	# hitbox and score selection all refer to the same physical crossing.
	return _plane_y()


func _plane_y() -> float:
	return size.y * 0.835


func _plane_center_x() -> float:
	return size.x * plane_x_norm


func _scaled(value: float) -> float:
	return value * clampf(size.y / 720.0, 0.86, 1.50)


func _draw_text(text_value: String, baseline: Vector2, font_size: int, color: Color, alignment: HorizontalAlignment, width: float) -> void:
	draw_string(FONT, baseline, text_value, alignment, width, int(round(_scaled(float(font_size)))), color)


func _life_text() -> String:
	var text := ""
	for i in range(lives):
		text += "●"
	return text if not text.is_empty() else "0"


func _style_pause_button() -> void:
	var button := %PauseButton
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", CREAM)
	button.add_theme_stylebox_override("normal", _button_style(INK, 14, 4))
	button.add_theme_stylebox_override("hover", _button_style(INK.lightened(0.08), 14, 6))
	button.add_theme_stylebox_override("pressed", _button_style(INK.darkened(0.08), 14, 2))
	button.add_theme_stylebox_override("focus", _focus_style())


func _button_style(color: Color, radius: int, shadow: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(INK, 0.24)
	style.shadow_size = shadow
	style.shadow_offset = Vector2(3, 5)
	return style


func _focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = YELLOW
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	return style


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
