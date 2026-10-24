extends Control

signal requested(target: String, payload: Dictionary)
signal student_lookup_requested(student_id: String)
signal student_id_edited(student_id: String)
signal database_setup_requested
signal database_retry_requested

const UI = preload("res://ui/play/play_ui.gd")

const GAME_STYLES := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const GAME_MODES := ["Seconds", "Lives"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]

var _root_margin: MarginContainer
var _content_scroll: ScrollContainer
var _setup_grid: GridContainer
var _student_card: PanelContainer
var _game_card: PanelContainer
var _style_grid: GridContainer
var _footer: HBoxContainer
var _back_button: Button
var _header_title: Label
var _scroll_hint_button: Button

var context: Dictionary = {}
var _identity_student_id := ""
var _applying_context := false

var _student_id_edit: LineEdit
var _name_edit: LineEdit
var _grade_edit: LineEdit
var _lookup_button: Button
var _database_status: Label
var _database_recovery_button: Button
var _database_needs_setup := false
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
	resized.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")
	_score_dialog = get_node("ExistingScoreDialog") as Control
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
		_set_database_status("DATABASE LOOKUP UNAVAILABLE • No student profile was applied.", UI.RED)
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
	context["database_connected"] = true
	_set_database_status("STUDENT FOUND IN LOCAL POSTGRESQL • Profile loaded from the verified student ID.", UI.GREEN)
	_update_validation()


func show_database_status(message: String, connected: bool = false, setup_required: bool = false) -> void:
	context["database_connected"] = connected
	_set_database_status(message, UI.GREEN if connected else UI.RED)
	_database_needs_setup = setup_required
	if is_instance_valid(_lookup_button):
		_lookup_button.text = "LOOK UP ID" if connected else "LOOK UP ID • NOT CONNECTED"
	if is_instance_valid(_database_recovery_button):
		_database_recovery_button.visible = not connected
		_database_recovery_button.text = "SET UP LOCAL DATABASE" if setup_required else "RETRY LOCAL CONNECTION"
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
	# All permanent layout, PNGs, buttons and fields are authored in the .tscn.
	_root_margin = get_node("LayoutMargins") as MarginContainer
	var column := get_node("LayoutMargins/StudentSetupColumn") as VBoxContainer
	_header_title = column.get_node("SetupHeader/SetupTitle") as Label
	_content_scroll = column.get_node("StudentSetupScroll") as ScrollContainer
	_setup_grid = _content_scroll.get_node("SetupCardGrid") as GridContainer
	_student_card = _setup_grid.get_node("StudentProfileCard") as PanelContainer
	_game_card = _setup_grid.get_node("GameSetupCard") as PanelContainer
	var profile := _student_card.get_node("ProfileContent") as VBoxContainer
	_student_id_edit = profile.get_node("StudentIdGroup/StudentIdEdit") as LineEdit
	_name_edit = profile.get_node("StudentNameGroup/StudentNameEdit") as LineEdit
	_grade_edit = profile.get_node("GradeSectionGroup/GradeSectionEdit") as LineEdit
	_database_status = profile.get_node("DatabasePanel/DatabaseContent/DatabaseStatus") as Label
	_lookup_button = profile.get_node("DatabasePanel/DatabaseContent/LookupButton") as Button
	_database_recovery_button = profile.get_node("DatabasePanel/DatabaseContent/DatabaseRecoveryButton") as Button
	var game := _game_card.get_node("GameContent") as VBoxContainer
	_style_grid = game.get_node("GameStyleGrid") as GridContainer
	_validation_label = game.get_node("ValidationPanel/ValidationLabel") as Label
	_style_buttons.clear()
	_mode_buttons.clear()
	_difficulty_buttons.clear()

	var styles_group := ButtonGroup.new()
	for item in GAME_STYLES:
		var style_button := _style_grid.get_node(item + "Button") as Button
		style_button.button_group = styles_group
		style_button.pressed.connect(_select_style.bind(item))
		style_button.focus_entered.connect(_ensure_selection_visible.bind(style_button))
		_style_buttons[item] = style_button
	var mode_group := ButtonGroup.new()
	var mode_row := game.get_node("LowerSelections/ModeColumn/ModeRow") as HBoxContainer
	for item in GAME_MODES:
		var mode_button := mode_row.get_node(item + "Button") as Button
		mode_button.button_group = mode_group
		mode_button.pressed.connect(_select_mode.bind(item))
		mode_button.focus_entered.connect(_ensure_selection_visible.bind(mode_button))
		_mode_buttons[item] = mode_button
	var difficulty_group := ButtonGroup.new()
	var difficulty_row := game.get_node("LowerSelections/DifficultyColumn/DifficultyRow") as HBoxContainer
	for item in DIFFICULTIES:
		var difficulty_button := difficulty_row.get_node(item + "Button") as Button
		difficulty_button.button_group = difficulty_group
		difficulty_button.pressed.connect(_select_difficulty.bind(item))
		difficulty_button.focus_entered.connect(_ensure_selection_visible.bind(difficulty_button))
		_difficulty_buttons[item] = difficulty_button

	_student_id_edit.text_changed.connect(_on_student_id_changed)
	_student_id_edit.focus_exited.connect(_associate_identity_with_current_id)
	_name_edit.text_changed.connect(_on_field_changed)
	_grade_edit.text_changed.connect(_on_field_changed)
	_student_id_edit.text_submitted.connect(func(_value: String) -> void: _name_edit.grab_focus())
	_name_edit.text_submitted.connect(func(_value: String) -> void: _grade_edit.grab_focus())
	_grade_edit.text_submitted.connect(func(_value: String) -> void: _focus_first_style())
	_lookup_button.pressed.connect(_request_lookup)
	_database_recovery_button.pressed.connect(_request_database_recovery)
	_content_scroll.get_v_scroll_bar().value_changed.connect(_on_setup_scrolled)
	_scroll_hint_button = column.get_node("GameSetupScrollHint") as Button
	_scroll_hint_button.pressed.connect(_activate_scroll_hint)
	_footer = column.get_node("SetupActions") as HBoxContainer
	_back_button = _footer.get_node("BackButton") as Button
	_continue_button = _footer.get_node("ContinueButton") as Button
	_back_button.pressed.connect(_go_back)
	_continue_button.pressed.connect(_continue)


func _apply_responsive_layout() -> void:
	if not is_instance_valid(_setup_grid):
		return
	# Only adaptive container columns change at runtime. Card geometry, art,
	# font sizes, margins and button dimensions remain editable in the scene.
	var physical_width := size.x
	if DisplayServer.get_name() != "headless":
		physical_width = float(DisplayServer.window_get_size().x)
	var narrow := size.x < 1040.0 or physical_width < 1000.0
	_setup_grid.columns = 1 if narrow else 2
	_style_grid.columns = 2 if narrow else 4
	call_deferred("_refresh_scroll_hint")


func _on_setup_scrolled(_value: float) -> void:
	call_deferred("_refresh_scroll_hint")


func _refresh_scroll_hint() -> void:
	if not is_instance_valid(_scroll_hint_button) or not is_instance_valid(_content_scroll):
		return
	var bar := _content_scroll.get_v_scroll_bar()
	var has_overflow := bar.max_value > bar.page + 3.0
	_scroll_hint_button.visible = _setup_grid.columns == 1 and has_overflow
	if not _scroll_hint_button.visible:
		return
	var game_top := _game_card.get_global_rect().position.y
	var visible_top := _content_scroll.get_global_rect().position.y
	# Seeing just the heading of the second card is not enough: its topic
	# controls must be reachable in the current scroll region before the cue
	# changes to "Back to Student Profile".
	var at_game_setup := game_top < visible_top + 160.0
	_scroll_hint_button.text = "↑ BACK TO STUDENT PROFILE" if at_game_setup else "SCROLL DOWN FOR GAME SETUP ↓"


func _activate_scroll_hint() -> void:
	if _scroll_hint_button.text.begins_with("↑"):
		_content_scroll.scroll_vertical = 0
		_student_id_edit.grab_focus()
	else:
		_focus_first_style()


func _ensure_selection_visible(control: Control) -> void:
	if is_instance_valid(control) and is_instance_valid(_content_scroll) and _content_scroll.is_ancestor_of(control):
		_content_scroll.ensure_control_visible(control)
		call_deferred("_refresh_scroll_hint")


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
		"LOCAL POSTGRESQL • Look up a student by ID or register when you continue.",
		UI.YELLOW
	)


func _sync_selection_buttons() -> void:
	for game_style in _style_buttons:
		var button := _style_buttons[game_style] as Button
		button.set_pressed_no_signal(game_style == _selected_style)
		button.modulate.a = 1.0 if _selected_style.is_empty() or game_style == _selected_style else 0.78
	for game_mode in _mode_buttons:
		var button := _mode_buttons[game_mode] as Button
		button.set_pressed_no_signal(game_mode == _selected_mode)
		button.modulate.a = 1.0 if _selected_mode.is_empty() or game_mode == _selected_mode else 0.78
	for difficulty in _difficulty_buttons:
		var button := _difficulty_buttons[difficulty] as Button
		button.set_pressed_no_signal(difficulty == _selected_difficulty)
		button.modulate.a = 1.0 if _selected_difficulty.is_empty() or difficulty == _selected_difficulty else 0.78


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
				"STUDENT ID CHANGED • Name and Grade & Section cleared to protect the student's identity. Look up the new ID.",
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
		_set_database_status("ENTER A STUDENT ID FIRST • Then search the local database.", UI.RED)
		_student_id_edit.grab_focus()
		return
	_set_database_status(
		"SEARCHING LOCAL POSTGRESQL • Checking the student ID...",
		UI.YELLOW
	)
	student_lookup_requested.emit(student_id)


func _request_database_recovery() -> void:
	if _database_needs_setup:
		_set_database_status("OPENING SECURE LOCAL SETUP • Follow the teacher prompts to configure PostgreSQL.", UI.YELLOW)
		database_setup_requested.emit()
	else:
		_set_database_status("RECONNECTING TO LOCAL POSTGRESQL • Checking the service...", UI.YELLOW)
		database_retry_requested.emit()


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
	_continue_button.modulate = Color("#9EB1C3") if _continue_button.disabled else Color.WHITE
	_lookup_button.disabled = _student_id_edit.text.strip_edges().is_empty()
	if missing.is_empty():
		_validation_label.text = "READY • All required fields are complete. Student registration is checked when you continue."
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
	payload["entry_source"] = "tutorial" if bool(context.get("guided_tutorial", false)) else "play"
	payload["preview_mode"] = true
	payload["setup_preview"] = true
	payload["database_connected"] = bool(context.get("database_connected", false))
	payload["student_lookup_connected"] = false
	payload.erase("student_setup_prefill")
	if bool(context.get("guided_tutorial", false)):
		# The selected activity was carried from Guided Tutorial's first
		# Game Selection panel. The teacher's choices now complete setup.
		payload["keyboard_mode"] = false
		payload["camera_requested"] = true
		requested.emit("calibration", payload)
	else:
		requested.emit("play_activity", payload)


func _go_back() -> void:
	requested.emit("play_activity" if bool(context.get("guided_tutorial", false)) else "main", context.duplicate(true))


func _focus_first() -> void:
	if is_instance_valid(_student_id_edit):
		_student_id_edit.grab_focus()


func _focus_first_style() -> void:
	var button: Button = _style_buttons.get(GAME_STYLES[0])
	if button:
		button.grab_focus()
		call_deferred("_ensure_selection_visible", button)


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
