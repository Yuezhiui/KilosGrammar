extends Control

signal overwrite_confirmed(record: Dictionary)
signal keep_existing_requested(record: Dictionary)
signal cancelled

const UI = preload("res://ui/play/play_ui.gd")

var _record: Dictionary = {}
var _title_label: Label
var _body_label: Label
var _keep_button: Button
var _replace_button: Button
var _close_button: Button


func _ready() -> void:
	var card := get_node_or_null("DialogCard") as Control
	if card != null:
		_bind_scene_nodes(card)
	else:
		_build_ui()
	hide()

func _bind_scene_nodes(card: Control) -> void:
	_title_label = card.get_node_or_null("TitleLabel") as Label
	_body_label = card.get_node_or_null("BodyLabel") as Label
	_keep_button = card.get_node_or_null("Actions/KeepButton") as Button
	if _keep_button:
		_keep_button.pressed.connect(_keep_existing)
	_replace_button = card.get_node_or_null("Actions/ReplaceButton") as Button
	if _replace_button:
		_replace_button.pressed.connect(_replace_existing)
	_close_button = card.get_node_or_null("Actions/CloseButton") as Button
	if _close_button:
		_close_button.pressed.connect(_cancel)


func present_confirmed(record: Dictionary) -> void:
	_record = record.duplicate(true)
	if not bool(_record.get("record_confirmed", false)):
		present_unavailable()
		return

	var student_id := _first_text(_record, ["student_id", "studentId", "id"], "Unknown ID")
	var game_style := _first_text(_record, ["game_style", "topic", "style"], "Unspecified style")
	var game_mode := _first_text(_record, ["game_mode", "mode"], "Unspecified mode")
	var difficulty := _first_text(_record, ["difficulty"], "Unspecified difficulty")
	var score := _first_text(_record, ["score", "points"], "—")
	_title_label.text = "EXISTING SCORE CONFIRMED"
	_body_label.text = (
		"A connected data source confirmed a saved score for this exact setup.\n"
		+ "%s  •  %s  •  %s  •  %s\n"
		+ "Saved score: %s\n\n"
		+ "Choose the action for the future save handler."
	) % [student_id, game_style, game_mode, difficulty, score]
	_keep_button.visible = true
	_replace_button.visible = true
	_close_button.text = "CANCEL"
	_show_modal(_keep_button)


func present_unavailable() -> void:
	_record.clear()
	_title_label.text = "SCORE CHECK UNAVAILABLE"
	_body_label.text = (
		"LOCAL POSTGRESQL: NOT CONNECTED\n\n"
		+ "Existing scores were not searched. No saved record has been assumed, "
		+ "and no overwrite decision can be made yet."
	)
	_keep_button.visible = false
	_replace_button.visible = false
	_close_button.text = "CLOSE"
	_show_modal(_close_button)


func _show_modal(focus_target: Button) -> void:
	show()
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_target.call_deferred("grab_focus")


func _hide_modal() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _keep_existing() -> void:
	var payload := _record.duplicate(true)
	_hide_modal()
	keep_existing_requested.emit(payload)


func _replace_existing() -> void:
	var payload := _record.duplicate(true)
	_hide_modal()
	overwrite_confirmed.emit(payload)


func _cancel() -> void:
	_hide_modal()
	cancelled.emit()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.08, 0.07, 0.11, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(650, 330)
	card.add_theme_stylebox_override("panel", UI.make_panel(Color(UI.CREAM, 0.99), 28))
	center.add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	card.add_child(content)

	_title_label = UI.make_label("SCORE CHECK", 30, UI.INK)
	_title_label.custom_minimum_size.y = 48
	content.add_child(_title_label)

	_body_label = UI.make_body_label("", 17, UI.INK)
	_body_label.custom_minimum_size = Vector2(0, 150)
	content.add_child(_body_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)

	_keep_button = Button.new()
	_keep_button.text = "KEEP SAVED SCORE"
	_keep_button.custom_minimum_size = Vector2(190, 48)
	UI.style_button(_keep_button, UI.INK, 15)
	_keep_button.pressed.connect(_keep_existing)
	actions.add_child(_keep_button)

	_replace_button = Button.new()
	_replace_button.text = "REPLACE ON SAVE"
	_replace_button.custom_minimum_size = Vector2(190, 48)
	UI.style_button(_replace_button, UI.RED, 15)
	_replace_button.pressed.connect(_replace_existing)
	actions.add_child(_replace_button)

	_close_button = Button.new()
	_close_button.text = "CANCEL"
	_close_button.custom_minimum_size = Vector2(140, 48)
	UI.style_button(_close_button, UI.GREEN, 15)
	_close_button.pressed.connect(_cancel)
	actions.add_child(_close_button)


func _first_text(source: Dictionary, keys: Array, fallback: String) -> String:
	for key in keys:
		if source.has(key):
			var value := str(source[key]).strip_edges()
			if not value.is_empty():
				return value
	return fallback
