extends Control

signal requested(target: String, payload: Dictionary)

const UI = preload("res://ui/play/play_ui.gd")
const ROUND_TOTAL := 10

var context: Dictionary = {}
var score := 0
var streak := 0
var best_streak := 0
var correct_count := 0
var attempts := 0
var time_remaining := 60.0
var timer_running := true

var score_label: Label
var time_label: Label
var streak_label: Label
var context_label: Label
var prompt_label: Label
var feedback_label: Label
var progress_label: Label
var correct_button: Button
var wrong_button: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	var column := UI.make_screen_column(self, 34)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	column.add_child(top)

	var pause_button := Button.new()
	pause_button.text = "PAUSE"
	pause_button.custom_minimum_size = Vector2(150, 52)
	UI.style_button(pause_button, UI.INK, 20)
	pause_button.pressed.connect(_pause)
	top.add_child(pause_button)

	var title := UI.make_label("GAMEPLAY HUD", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)

	var demo_badge := UI.make_body_label("PROTOTYPE / DEMO • NO LIVE CAMERA OR YOLO INFERENCE", 14, UI.YELLOW)
	demo_badge.custom_minimum_size = Vector2(390, 48)
	top.add_child(demo_badge)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 12)
	column.add_child(stats)
	score_label = _add_stat(stats, "SCORE  0", UI.GREEN)
	time_label = _add_stat(stats, "TIME  60", UI.BLUE)
	streak_label = _add_stat(stats, "STREAK  0", UI.PURPLE)

	var stage := PanelContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.add_theme_stylebox_override("panel", UI.make_panel(Color(UI.INK, 0.86), 30))
	column.add_child(stage)

	var stage_content := VBoxContainer.new()
	stage_content.alignment = BoxContainer.ALIGNMENT_CENTER
	stage_content.add_theme_constant_override("separation", 18)
	stage.add_child(stage_content)

	context_label = UI.make_body_label("", 18, Color(UI.CREAM, 0.76))
	stage_content.add_child(context_label)

	prompt_label = UI.make_label("", 40)
	prompt_label.custom_minimum_size.y = 100
	stage_content.add_child(prompt_label)

	progress_label = UI.make_body_label("ROUND 1 / %d" % ROUND_TOTAL, 18, Color(UI.CREAM, 0.80))
	stage_content.add_child(progress_label)

	feedback_label = UI.make_label("DEMO CONTROLS READY", 24, UI.YELLOW)
	feedback_label.custom_minimum_size.y = 48
	stage_content.add_child(feedback_label)

	var demo_controls := HBoxContainer.new()
	demo_controls.alignment = BoxContainer.ALIGNMENT_CENTER
	demo_controls.add_theme_constant_override("separation", 18)
	stage_content.add_child(demo_controls)

	correct_button = Button.new()
	correct_button.text = "SIMULATE CORRECT"
	correct_button.custom_minimum_size = Vector2(270, 58)
	UI.style_button(correct_button, UI.GREEN, 20)
	correct_button.pressed.connect(_simulate_correct)
	demo_controls.add_child(correct_button)

	wrong_button = Button.new()
	wrong_button.text = "SIMULATE WRONG"
	wrong_button.custom_minimum_size = Vector2(270, 58)
	UI.style_button(wrong_button, UI.RED, 20)
	wrong_button.pressed.connect(_simulate_wrong)
	demo_controls.add_child(wrong_button)

	var finish_button := Button.new()
	finish_button.text = "FINISH DEMO"
	finish_button.custom_minimum_size = Vector2(220, 58)
	UI.style_button(finish_button, UI.INK, 20)
	finish_button.pressed.connect(_finish_demo)
	demo_controls.add_child(finish_button)

	_refresh_all()
	call_deferred("_focus_demo")


func set_context(new_context: Dictionary) -> void:
	for key in new_context:
		context[key] = new_context[key]
	if new_context.has("score"):
		score = int(new_context["score"])
	if new_context.has("streak"):
		streak = int(new_context["streak"])
	if new_context.has("best_streak"):
		best_streak = int(new_context["best_streak"])
	if new_context.has("correct"):
		correct_count = int(new_context["correct"])
	if new_context.has("attempts"):
		attempts = int(new_context["attempts"])
	if new_context.has("time_remaining"):
		time_remaining = float(new_context["time_remaining"])
	_refresh_all()


func set_score(value: int) -> void:
	score = maxi(value, 0)
	_refresh_stats()


func set_time_remaining(seconds: float) -> void:
	time_remaining = maxf(seconds, 0.0)
	_refresh_stats()


func set_prompt_text(text_value: String) -> void:
	if prompt_label:
		prompt_label.text = text_value


func set_round_progress(current: int, total: int = ROUND_TOTAL) -> void:
	if progress_label:
		progress_label.text = "ROUND %d / %d" % [maxi(current, 1), maxi(total, 1)]


func show_feedback(message: String, is_correct: bool) -> void:
	if feedback_label:
		feedback_label.text = message.to_upper()
		feedback_label.add_theme_color_override("font_color", UI.GREEN if is_correct else UI.RED)


func get_context() -> Dictionary:
	return _payload_with_demo_state()


func _process(delta: float) -> void:
	if not timer_running:
		return
	time_remaining = maxf(time_remaining - delta, 0.0)
	if time_label:
		time_label.text = "TIME  %02d" % int(ceil(time_remaining))
	if time_remaining <= 0.0:
		timer_running = false
		show_feedback("Demo time complete", true)


func _add_stat(parent: HBoxContainer, text_value: String, color: Color) -> Label:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UI.make_panel(Color(color, 0.90), 14, false))
	var label := UI.make_label(text_value, 20)
	label.custom_minimum_size.y = 44
	panel.add_child(label)
	parent.add_child(panel)
	return label


func _focus_demo() -> void:
	if correct_button:
		correct_button.grab_focus()


func _refresh_all() -> void:
	_refresh_stats()
	if context_label:
		context_label.text = "%s  •  %s  •  %s" % [
			String(context.get("activity", "Activity")),
			String(context.get("topic", "Topic")),
			String(context.get("difficulty", "Difficulty"))
		]
	if prompt_label:
		prompt_label.text = _default_prompt()
	set_round_progress(mini(attempts + 1, ROUND_TOTAL), ROUND_TOTAL)


func _refresh_stats() -> void:
	if score_label:
		score_label.text = "SCORE  %d" % score
	if time_label:
		time_label.text = "TIME  %02d" % int(ceil(time_remaining))
	if streak_label:
		streak_label.text = "STREAK  %d" % streak


func _default_prompt() -> String:
	match String(context.get("activity", "Catch the Word")):
		"Human Plane":
			return "DEMO: MOVE TO THE CENTER LANE"
		"Balloon Popping":
			return "DEMO: POP THE %s BALLOON" % String(context.get("topic", "Noun")).to_upper()
		_:
			return "DEMO: CHOOSE THE %s WORD" % String(context.get("topic", "Noun")).to_upper()


func _simulate_correct() -> void:
	attempts += 1
	correct_count += 1
	streak += 1
	best_streak = maxi(best_streak, streak)
	score += 100 + (streak - 1) * 10
	show_feedback("+%d • Correct!" % (100 + (streak - 1) * 10), true)
	_after_demo_attempt()


func _simulate_wrong() -> void:
	attempts += 1
	streak = 0
	show_feedback("Try the next one", false)
	_after_demo_attempt()


func _after_demo_attempt() -> void:
	_refresh_stats()
	set_round_progress(mini(attempts + 1, ROUND_TOTAL), ROUND_TOTAL)
	if attempts >= ROUND_TOTAL:
		correct_button.disabled = true
		wrong_button.disabled = true
		timer_running = false
		show_feedback("Demo round complete", true)


func _payload_with_demo_state() -> Dictionary:
	var payload := context.duplicate(true)
	payload["demo_mode"] = true
	payload["score"] = score
	payload["streak"] = streak
	payload["best_streak"] = best_streak
	payload["correct"] = correct_count
	payload["attempts"] = attempts
	payload["total"] = attempts
	payload["time_remaining"] = time_remaining
	return payload


func _pause() -> void:
	timer_running = false
	requested.emit("pause", _payload_with_demo_state())


func _finish_demo() -> void:
	timer_running = false
	requested.emit("results", _payload_with_demo_state())
