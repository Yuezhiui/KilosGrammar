extends Control

signal requested(target: String, payload: Dictionary)

var context: Dictionary = {}
var summary_label: Label
var controls_hint: Label
var countdown_label: Label
var start_button: Button
var back_button: Button
var countdown_running := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Ready UI nodes are authored in ready.tscn and can be repositioned,
	# resized or reskinned in the Godot editor without touching this script.
	countdown_label = get_node_or_null("LayoutMargins/Content/Center/ReadyCard/ReadyCardContent/CountdownLabel") as Label
	summary_label = get_node_or_null("LayoutMargins/Content/Center/ReadyCard/ReadyCardContent/SummaryLabel") as Label
	controls_hint = get_node_or_null("LayoutMargins/Content/Center/ReadyCard/ReadyCardContent/ControlsHint") as Label
	back_button = get_node_or_null("LayoutMargins/Content/Footer/BackButton") as Button
	start_button = get_node_or_null("LayoutMargins/Content/Footer/StartButton") as Button
	if countdown_label == null or summary_label == null or back_button == null or start_button == null:
		push_error("Ready screen is missing required editor-authored controls.")
		return
	back_button.text = _back_button_title()
	back_button.pressed.connect(_go_back)
	start_button.pressed.connect(_start_countdown)
	_refresh_summary()
	call_deferred("_focus_start")


func set_context(new_context: Dictionary) -> void:
	for key in new_context:
		context[key] = new_context[key]
	if back_button:
		back_button.text = _back_button_title()
	if start_button:
		start_button.text = "START GUIDED TUTORIAL" if bool(context.get("guided_tutorial", false)) else "START COUNTDOWN"
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
	# This label stays fully editor-authored: update its content, not its rect.
	if controls_hint != null:
		match String(context.get("activity", "")):
			"Balloon Popping":
				controls_hint.text = "Move to aim. Raise EITHER hand once to shoot; lower it and raise again after 1.5 seconds."
			"Human Plane":
				controls_hint.text = "Extend BOTH arms sideways like airplane wings to steer with your body. Lower them to stop."
			_:
				controls_hint.text = "Move your body left or right to catch the correct grammar word."


func _focus_start() -> void:
	if start_button:
		start_button.grab_focus()


func _go_back() -> void:
	if countdown_running:
		return
	requested.emit("calibration", context.duplicate(true))


func _back_button_title() -> String:
	return "BACK: CALIBRATION"


func _start_countdown() -> void:
	if countdown_running:
		return
	countdown_running = true
	start_button.disabled = true
	back_button.disabled = true
	# The gameplay wrapper controls the only 3-2-1, including a spotlight
	# first when this is a guided session. Never count down on Ready as well.
	_launch_gameplay()


func _launch_gameplay() -> void:
	var payload := context.duplicate(true)
	payload["demo_mode"] = true
	payload["start_countdown"] = true
	payload["camera_live"] = PoseService.active and bool(PoseService.calibration.get("valid", false)) and not bool(context.get("keyboard_mode", false))
	requested.emit("gameplay", payload)
