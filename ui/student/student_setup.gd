extends Control

signal requested(target: String, payload: Dictionary)
signal student_lookup_requested(student_id: String)
signal student_id_edited(student_id: String)

const UI = preload("res://ui/play/play_ui.gd")
const EXISTING_SCORE_DIALOG = preload("res://ui/student/existing_score_dialog.tscn")

const GAME_STYLES := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const FUTURE_STYLES := ["Preposition", "Conjunction", "Interjection"]
const GAME_MODES := ["Seconds", "Lives"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const STYLE_COLORS := [UI.GREEN, UI.PURPLE, UI.RED, Color("#E29A36"), UI.BLUE]
const MODE_COLORS := [UI.DEEP_BLUE, UI.GREEN]
const DIFFICULTY_COLORS := [UI.GREEN, Color("#E29A36"), UI.RED]

var context: Dictionary = {}
var _identity_student_id := ""
var _applying_context := false

var _student_id_edit: LineEdit
var _name_edit: LineEdit
var _grade_edit: LineEdit
var _lookup_button: Button
var _database_status: Label
var _validation_label: Label
var _continue_button: Button
var _score_dialog: Control

var _style_buttons: Dictionary = {}
var _mode_buttons: Dictionary = {}
var _difficulty_buttons: Dictionary = {}
var _selected_style := ""
var _selected_mode := ""
var _selected_difficulty := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_score_dialog = EXISTING_SCORE_DIALOG.instantiate()
	add_child(_score_dialog)
	_apply_context_to_ui()
	_update_validation()
	call_deferred("_focus_first")


func set_context(new_context: Dictionary) -> void:
	context = new_context.duplicate(true)
	if not _should_prefill(new_context):
		_clear_setup_context()
	if is_node_ready():
		_apply_context_to_ui()
		_update_validation()


func apply_lookup_result(profile: Dictionary) -> void:
	if not bool(profile.get("lookup_confirmed", false)):
		_set_database_status("DATABASE LOOKUP: NOT CONNECTED • No student profile was applied.", UI.RED)
		return

	var result_id := _first_text(profile, ["student_id", "studentId", "id"])
	if result_id.is_empty() or result_id != _student_id_edit.text.strip_edges():
		_set_database_status("LOOKUP RESULT REJECTED • Student ID does not match the current field.", UI.RED)
		return

	_applying_context = true
	_name_edit.text = _first_text(profile, ["student_name", "name"])
	_grade_edit.text = _first_text(profile, ["grade_section", "grade", "section"])
	_applying_context = false
	_identity_student_id = result_id
	_set_database_status("PROFILE APPLIED FROM CONFIRMED LOOKUP • Saving remains NOT CONNECTED.", UI.YELLOW)
	_update_validation()


func show_existing_score_confirmation(confirmed_record: Dictionary) -> void:
	_score_dialog.call("present_confirmed", confirmed_record)


func show_score_check_unavailable() -> void:
	_score_dialog.call("present_unavailable")


func _should_prefill(source: Dictionary) -> bool:
	if bool(source.get("student_setup_prefill", false)):
		return true
	var entry_source := String(source.get("entry_source", "")).strip_edges().to_lower()
	return entry_source in ["retry", "results", "game_over"]


func _clear_setup_context() -> void:
	for key in [
		"student_id", "studentId", "id", "student_name", "name",
		"grade_section", "grade", "section", "game_style", "style",
		"game_mode", "mode", "difficulty", "topic"
	]:
		context.erase(key)
	context.erase("student_setup_prefill")


func _build_ui() -> void:
	var column := UI.make_compact_screen_column(self, 34)
	UI.add_compact_title(
		column,
		"Teacher Setup",
		"Student & Game Setup",
		"Enter the student details and choose the lesson setup. All fields start blank for a new Play session."
	)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)

	_build_student_card(body)
	_build_game_card(body)

	var footer: Array[Button] = UI.add_compact_footer(column, "BACK", "CONTINUE")
	footer[0].pressed.connect(_go_back)
	_continue_button = footer[1]
	_continue_button.pressed.connect(_continue)


func _build_student_card(parent: HBoxContainer) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 410
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UI.make_panel(Color(UI.CREAM, 0.97), 24))
	parent.add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 9)
	card.add_child(content)

	var title := UI.make_label("STUDENT PROFILE", 24, UI.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.custom_minimum_size.y = 34
	content.add_child(title)

	var helper := UI.make_body_label("Required fields • teacher-entered for this UI preview", 13, Color(UI.INK, 0.72))
	helper.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	helper.custom_minimum_size.y = 24
	content.add_child(helper)

	_student_id_edit = _add_field(content, "STUDENT ID", "Enter student ID", 32)
	_name_edit = _add_field(content, "NAME", "Enter student name", 64)
	_grade_edit = _add_field(content, "GRADE & SECTION", "Example: Grade 2 Apple", 64)

	_student_id_edit.text_changed.connect(_on_student_id_changed)
	_student_id_edit.focus_exited.connect(_associate_identity_with_current_id)
	_name_edit.text_changed.connect(_on_field_changed)
	_grade_edit.text_changed.connect(_on_field_changed)
	_student_id_edit.text_submitted.connect(func(_value: String) -> void: _name_edit.grab_focus())
	_name_edit.text_submitted.connect(func(_value: String) -> void: _grade_edit.grab_focus())
	_grade_edit.text_submitted.connect(func(_value: String) -> void: _focus_first_style())

	var database_panel := PanelContainer.new()
	database_panel.add_theme_stylebox_override("panel", _soft_panel(Color(UI.RED, 0.10), Color(UI.RED, 0.48), 14))
	content.add_child(database_panel)
	var database_box := VBoxContainer.new()
	database_box.add_theme_constant_override("separation", 7)
	database_panel.add_child(database_box)

	_database_status = UI.make_body_label(
		"LOCAL POSTGRESQL • SEARCH / SAVE: NOT CONNECTED\nNo student record has been searched, loaded, or registered.",
		12,
		UI.RED
	)
	_database_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_database_status.custom_minimum_size.y = 46
	database_box.add_child(_database_status)

	_lookup_button = Button.new()
	_lookup_button.text = "LOOK UP ID • NOT CONNECTED"
	_lookup_button.custom_minimum_size.y = 42
	UI.style_button(_lookup_button, UI.INK, 14)
	_lookup_button.pressed.connect(_request_lookup)
	database_box.add_child(_lookup_button)


func _build_game_card(parent: HBoxContainer) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UI.make_panel(Color(UI.INK, 0.93), 24))
	parent.add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	card.add_child(content)

	var title := UI.make_label("GAME SETUP", 24, UI.CREAM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.custom_minimum_size.y = 34
	content.add_child(title)

	content.add_child(_section_label("GAME STYLE • GRAMMAR TOPIC"))
	var style_grid := GridContainer.new()
	style_grid.columns = 4
	style_grid.add_theme_constant_override("h_separation", 8)
	style_grid.add_theme_constant_override("v_separation", 8)
	content.add_child(style_grid)

	var style_group := ButtonGroup.new()
	for index in range(GAME_STYLES.size()):
		var game_style: String = GAME_STYLES[index]
		var button := _selection_button(game_style.to_upper(), STYLE_COLORS[index], 44, 14)
		button.button_group = style_group
		button.pressed.connect(_select_style.bind(game_style))
		style_grid.add_child(button)
		_style_buttons[game_style] = button

	for future_style in FUTURE_STYLES:
		var future := _selection_button("%s • SOON" % future_style.to_upper(), UI.INK, 44, 11)
		future.disabled = true
		style_grid.add_child(future)

	var lower := HBoxContainer.new()
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lower.add_theme_constant_override("separation", 12)
	content.add_child(lower)

	var mode_column := VBoxContainer.new()
	mode_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_column.add_theme_constant_override("separation", 8)
	lower.add_child(mode_column)
	mode_column.add_child(_section_label("GAME MODE • UI PREVIEW"))
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	mode_column.add_child(mode_row)
	var mode_group := ButtonGroup.new()
	for index in range(GAME_MODES.size()):
		var game_mode: String = GAME_MODES[index]
		var label_text: String = "60s" if game_mode == "Seconds" else "3 LIVES"
		var button := _selection_button(label_text, MODE_COLORS[index], 58, 15)
		button.button_group = mode_group
		button.pressed.connect(_select_mode.bind(game_mode))
		mode_row.add_child(button)
		_mode_buttons[game_mode] = button

	var difficulty_column := VBoxContainer.new()
	difficulty_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty_column.add_theme_constant_override("separation", 8)
	lower.add_child(difficulty_column)
	difficulty_column.add_child(_section_label("DIFFICULTY"))
	var difficulty_row := HBoxContainer.new()
	difficulty_row.add_theme_constant_override("separation", 8)
	difficulty_column.add_child(difficulty_row)
	var difficulty_group := ButtonGroup.new()
	for index in range(DIFFICULTIES.size()):
		var difficulty: String = DIFFICULTIES[index]
		var button := _selection_button(difficulty.to_upper(), DIFFICULTY_COLORS[index], 58, 13)
		button.button_group = difficulty_group
		button.pressed.connect(_select_difficulty.bind(difficulty))
		difficulty_row.add_child(button)
		_difficulty_buttons[difficulty] = button

	var validation_panel := PanelContainer.new()
	validation_panel.add_theme_stylebox_override("panel", _soft_panel(Color(UI.CREAM, 0.12), Color(UI.CREAM, 0.45), 14))
	content.add_child(validation_panel)
	_validation_label = UI.make_body_label("", 13, UI.CREAM)
	_validation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_validation_label.custom_minimum_size.y = 46
	validation_panel.add_child(_validation_label)


func _add_field(parent: VBoxContainer, label_text: String, placeholder: String, max_length: int) -> LineEdit:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	parent.add_child(stack)

	var label := UI.make_label(label_text, 13, UI.INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.custom_minimum_size.y = 20
	stack.add_child(label)

	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = max_length
	field.custom_minimum_size.y = 44
	field.focus_mode = Control.FOCUS_ALL
	field.add_theme_font_size_override("font_size", 16)
	field.add_theme_color_override("font_color", UI.INK)
	field.add_theme_color_override("font_placeholder_color", Color(UI.INK, 0.45))
	field.add_theme_color_override("caret_color", UI.MINT)
	field.add_theme_stylebox_override("normal", _field_style(false))
	field.add_theme_stylebox_override("focus", _field_style(true))
	stack.add_child(field)
	return field


func _field_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UI.WHITE
	style.border_width_left = 3 if focused else 2
	style.border_width_top = 3 if focused else 2
	style.border_width_right = 3 if focused else 2
	style.border_width_bottom = 3 if focused else 2
	style.border_color = UI.MINT if focused else Color(UI.INK, 0.28)
	style.corner_radius_top_left = 11
	style.corner_radius_top_right = 11
	style.corner_radius_bottom_left = 11
	style.corner_radius_bottom_right = 11
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _soft_panel(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = border
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style


func _section_label(text_value: String) -> Label:
	var label := UI.make_label(text_value, 13, Color(UI.CREAM, 0.78))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.custom_minimum_size.y = 20
	return label


func _selection_button(text_value: String, color: Color, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.text = text_value
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0, height)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UI.style_button(button, color, font_size)
	button.add_theme_stylebox_override("pressed", UI.make_button_style(color.darkened(0.12), false, true))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button


func _apply_context_to_ui() -> void:
	if _student_id_edit == null:
		return

	_applying_context = true
	var prefill := _should_prefill(context)
	_student_id_edit.text = _first_text(context, ["student_id", "studentId", "id"]) if prefill else ""
	_name_edit.text = _first_text(context, ["student_name", "name"]) if prefill else ""
	_grade_edit.text = _first_text(context, ["grade_section", "grade", "section"]) if prefill else ""
	_selected_style = _canonical_value(_first_text(context, ["game_style", "topic", "style"]), GAME_STYLES) if prefill else ""
	_selected_mode = _canonical_value(_first_text(context, ["game_mode", "mode"]), GAME_MODES) if prefill else ""
	_selected_difficulty = _canonical_value(_first_text(context, ["difficulty"]), DIFFICULTIES) if prefill else ""
	_identity_student_id = _student_id_edit.text.strip_edges() if prefill and (not _name_edit.text.strip_edges().is_empty() or not _grade_edit.text.strip_edges().is_empty()) else ""
	_sync_selection_buttons()
	_applying_context = false
	_set_database_status(
		"LOCAL POSTGRESQL • SEARCH / SAVE: NOT CONNECTED\nNo student record has been searched, loaded, or registered.",
		UI.RED
	)


func _sync_selection_buttons() -> void:
	for game_style in _style_buttons:
		(_style_buttons[game_style] as Button).set_pressed_no_signal(game_style == _selected_style)
	for game_mode in _mode_buttons:
		(_mode_buttons[game_mode] as Button).set_pressed_no_signal(game_mode == _selected_mode)
	for difficulty in _difficulty_buttons:
		(_difficulty_buttons[difficulty] as Button).set_pressed_no_signal(difficulty == _selected_difficulty)


func _on_student_id_changed(value: String) -> void:
	if _applying_context:
		return
	var clean_id := value.strip_edges()
	student_id_edited.emit(clean_id)
	if not _identity_student_id.is_empty() and clean_id != _identity_student_id:
		_applying_context = true
		_name_edit.clear()
		_grade_edit.clear()
		_applying_context = false
		_identity_student_id = ""
		_set_database_status(
			"STUDENT ID CHANGED • Name and Grade & Section were cleared to prevent stale identity data. DATABASE LOOKUP: NOT CONNECTED.",
			UI.RED
		)
	_update_validation()


func _on_field_changed(_value: String) -> void:
	if _applying_context:
		return
	var student_id := _student_id_edit.text.strip_edges()
	var has_identity_fields := not _name_edit.text.strip_edges().is_empty() or not _grade_edit.text.strip_edges().is_empty()
	if not student_id.is_empty() and has_identity_fields:
		_identity_student_id = student_id
	elif not has_identity_fields:
		_identity_student_id = ""
	_update_validation()


func _associate_identity_with_current_id() -> void:
	if _applying_context:
		return
	var student_id := _student_id_edit.text.strip_edges()
	var has_identity_fields := not _name_edit.text.strip_edges().is_empty() or not _grade_edit.text.strip_edges().is_empty()
	if not student_id.is_empty() and has_identity_fields:
		_identity_student_id = student_id


func _select_style(game_style: String) -> void:
	var canonical := _canonical_value(game_style, GAME_STYLES)
	_selected_style = canonical if not canonical.is_empty() else game_style
	_sync_selection_buttons()
	_update_validation()


func _select_mode(game_mode: String) -> void:
	var canonical := _canonical_value(game_mode, GAME_MODES)
	_selected_mode = canonical if not canonical.is_empty() else game_mode
	_sync_selection_buttons()
	_update_validation()


func _select_difficulty(difficulty: String) -> void:
	var canonical := _canonical_value(difficulty, DIFFICULTIES)
	_selected_difficulty = canonical if not canonical.is_empty() else difficulty
	_sync_selection_buttons()
	_update_validation()


func _request_lookup() -> void:
	var student_id := _student_id_edit.text.strip_edges()
	if student_id.is_empty():
		_set_database_status("ENTER A STUDENT ID FIRST • DATABASE LOOKUP: NOT CONNECTED.", UI.RED)
		_student_id_edit.grab_focus()
		return
	_set_database_status(
		"DATABASE LOOKUP: NOT CONNECTED • No profile was searched or loaded. Backend hook emitted only.",
		UI.RED
	)
	student_lookup_requested.emit(student_id)


func _set_database_status(message: String, color: Color) -> void:
	if _database_status == null:
		return
	_database_status.text = message
	_database_status.add_theme_color_override("font_color", color)


func _update_validation() -> void:
	if _continue_button == null or _validation_label == null:
		return

	var missing: Array[String] = []
	if _student_id_edit.text.strip_edges().is_empty():
		missing.append("Student ID")
	if _name_edit.text.strip_edges().is_empty():
		missing.append("Name")
	if _grade_edit.text.strip_edges().is_empty():
		missing.append("Grade & Section")
	if not GAME_STYLES.has(_selected_style):
		missing.append("Game Style")
	if not GAME_MODES.has(_selected_mode):
		missing.append("Game Mode")
	if not DIFFICULTIES.has(_selected_difficulty):
		missing.append("Difficulty")

	_continue_button.disabled = not missing.is_empty()
	_lookup_button.disabled = _student_id_edit.text.strip_edges().is_empty()
	if missing.is_empty():
		_validation_label.text = "READY • All required setup fields are complete. Database lookup and save remain NOT CONNECTED."
		_validation_label.add_theme_color_override("font_color", UI.GREEN)
	else:
		_validation_label.text = "REQUIRED • %s" % ", ".join(missing)
		_validation_label.add_theme_color_override("font_color", UI.CREAM)


func _continue() -> void:
	_update_validation()
	if _continue_button.disabled:
		return

	var payload := context.duplicate(true)
	payload["student_id"] = _student_id_edit.text.strip_edges()
	payload["student_name"] = _name_edit.text.strip_edges()
	payload["grade_section"] = _grade_edit.text.strip_edges()
	payload["game_style"] = _selected_style
	payload["topic"] = _selected_style
	payload["game_mode"] = _selected_mode
	payload["difficulty"] = _selected_difficulty
	payload["entry_source"] = "play"
	payload["preview_mode"] = true
	payload["setup_preview"] = true
	payload["database_connected"] = false
	payload["student_lookup_connected"] = false
	payload.erase("student_setup_prefill")
	requested.emit("play_activity", payload)


func _go_back() -> void:
	requested.emit("main", context.duplicate(true))


func _focus_first() -> void:
	if is_instance_valid(_student_id_edit):
		_student_id_edit.grab_focus()


func _focus_first_style() -> void:
	var button: Button = _style_buttons.get(GAME_STYLES[0])
	if button:
		button.grab_focus()


func _first_text(source: Dictionary, keys: Array) -> String:
	for key in keys:
		if source.has(key):
			var value := str(source[key]).strip_edges()
			if not value.is_empty():
				return value
	return ""


func _canonical_value(value: String, allowed: Array) -> String:
	var clean := value.strip_edges()
	for option in allowed:
		if option.to_lower() == clean.to_lower():
			return option
	if allowed == GAME_MODES:
		match clean.to_lower():
			"quiz", "sec", "60s", "seconds":
				return "Seconds"
			"activity", "life", "3 lives", "lives":
				return "Lives"
	return ""
