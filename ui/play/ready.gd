extends Control

signal requested(target: String, payload: Dictionary)

const UI = preload("res://ui/play/play_ui.gd")

var context: Dictionary = {}
var summary_label: Label
var countdown_label: Label
var start_button: Button
var back_button: Button
var countdown_running := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var clean_backdrop := ColorRect.new()
	clean_backdrop.color = Color("087e75")
	clean_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clean_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clean_backdrop)
	var background := TextureRect.new()
	background.name = "SetupArtworkBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = load("res://ui/redesign/assets/student/setup_main_panel.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var compact := get_viewport_rect().size.y <= 550.0
	var column := UI.make_screen_column(self, 26 if compact else 86)
	UI.add_title(column, "Ready Check", "Get in Position", "Stand comfortably inside the play area before starting.")

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(720, 220 if compact else 330)
	card.add_theme_stylebox_override("panel", UI.make_panel(Color(UI.INK, 0.88), 30))
	center.add_child(card)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 5 if compact else 16)
	card.add_child(content)

	countdown_label = UI.make_label("READY?", 72, UI.YELLOW)
	countdown_label.custom_minimum_size.y = 58 if compact else 100
	content.add_child(countdown_label)

	summary_label = UI.make_body_label("", 20)
	summary_label.custom_minimum_size.y = 46 if compact else 76
	content.add_child(summary_label)

	var hint := UI.make_body_label("Camera mode moves with your body (or use A/D). Raise BOTH hands to fire balloons. Keyboard: SPACE to shoot.", 16, Color(UI.CREAM, 0.78))
	hint.custom_minimum_size.y = 32 if compact else 50
	content.add_child(hint)

	var footer: Array[Button] = UI.add_footer(column, "BACK", "START COUNTDOWN")
	back_button = footer[0]
	back_button.text = "BACK: GAME SELECT" if bool(context.get("keyboard_mode", false)) else "BACK: CAMERA CHECK"
	start_button = footer[1]
	back_button.pressed.connect(_go_back)
	start_button.pressed.connect(_start_countdown)
	_refresh_summary()
	call_deferred("_focus_start")


func set_context(new_context: Dictionary) -> void:
	for key in new_context:
		context[key] = new_context[key]
	if back_button:
		back_button.text = "BACK: GAME SELECT" if bool(context.get("keyboard_mode", false)) else "BACK: CAMERA CHECK"
	if PoseService.active and bool(PoseService.calibration.get("valid", false)):
		countdown_label.text = "YOLO READY"
	_refresh_summary()


func _refresh_summary() -> void:
	if summary_label == null:
		return
	summary_label.text = "%s\n%s • %s" % [
		String(context.get("activity", "Activity")),
		String(context.get("topic", "Topic")),
		String(context.get("difficulty", "Difficulty"))
	]


func _focus_start() -> void:
	if start_button:
		start_button.grab_focus()


func _go_back() -> void:
	if countdown_running:
		return
	requested.emit("play_activity" if bool(context.get("keyboard_mode", false)) else "camera_check", context.duplicate(true))


func _start_countdown() -> void:
	if countdown_running:
		return
	countdown_running = true
	start_button.disabled = true
	back_button.disabled = true
	for value in [3, 2, 1]:
		countdown_label.text = str(value)
		countdown_label.scale = Vector2(1.15, 1.15)
		countdown_label.pivot_offset = countdown_label.size * 0.5
		var tween := create_tween()
		tween.tween_property(countdown_label, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(0.65).timeout
	countdown_label.text = "GO!"
	await get_tree().create_timer(0.35).timeout
	var payload := context.duplicate(true)
	payload["demo_mode"] = true
	payload["camera_live"] = PoseService.active and bool(PoseService.calibration.get("valid", false)) and not bool(context.get("keyboard_mode", false))
	requested.emit("gameplay", payload)
