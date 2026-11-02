extends Control

signal requested(target: String, payload: Dictionary)
signal student_autofill_requested(field: String, exact_value: String, edit_epoch: int)
signal student_id_edited(student_id: String)

const GAME_STYLES := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const GAME_MODES := ["Seconds", "Lives"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const PLAYER_MODES := ["Single Player", "Multiplayer"]
const AUTOFILL_IDLE_SECONDS := 2.5
const CONFLICT_ID_TEXT_COLOR := Color(0.65, 0.26, 0.16, 1.0)
const STATUS_TEXT_COLOR := Color(0.32, 0.29, 0.22, 1.0)
const MAX_STUDENT_ID_LENGTH := 64
const INVALID_STUDENT_ID_MESSAGE := "STUDENT ID: USE LETTERS, NUMBERS, . _ - (MAX 64)"

const DESIGN_SIZE := Vector2(1280.0, 720.0)
var _setup_stage: Control
var _root_margin: MarginContainer
var _content_scroll: ScrollContainer
var _setup_grid: Control
var _student_card: Control
var _game_card: Control
var _style_grid: Control
var _footer: Control
var _back_button: Button
var _header_title: Label
var _scroll_hint_button: Button

var context: Dictionary = {}
var _identity_student_id := ""
var _verified_lookup_identity: Dictionary = {}
var _applying_context := false
var _registration_error := ""
var _lookup_pending := false
var _default_id_text_color := Color.WHITE

var _student_id_edit: LineEdit
var _name_edit: LineEdit
var _grade_edit: LineEdit
var _autofill_timer: Timer
var _autofill_epoch := 0
var _autofill_field := ""
var _autofill_value := ""
var _validation_label: Label
var _continue_button: Button
var _profile_status: Label
var _player_one_summary: Label
var _player_two_panel: Panel
var _player_two_status: Label
var _player_two_id_edit: LineEdit
var _player_two_name_edit: LineEdit
var _player_two_grade_edit: LineEdit
var _player_mode_buttons: Dictionary = {}
var _selected_player_mode := ""
var _setup_phase := "profile"

var _style_buttons: Dictionary = {}
var _mode_buttons: Dictionary = {}
var _difficulty_buttons: Dictionary = {}
var _selected_style := ""
var _selected_mode := ""
var _selected_difficulty := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_autofill_timer = Timer.new()
	_autofill_timer.one_shot = true
	_autofill_timer.wait_time = AUTOFILL_IDLE_SECONDS
	_autofill_timer.timeout.connect(_autofill_if_unchanged)
	add_child(_autofill_timer)
	resized.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")
	_apply_context_to_ui()
	_update_validation()
	call_deferred("_focus_first")


func set_context(new_context: Dictionary) -> void:
	_invalidate_autofill()
	_registration_error = ""
	_lookup_pending = false
	context = new_context.duplicate(true)
	if not _should_prefill(new_context):
		_clear_setup_context()
	if is_node_ready():
		_apply_context_to_ui()
		_update_validation()


func apply_lookup_result(profile: Dictionary) -> void:
	# Legacy router compatibility: a late response still needs an exact match.
	apply_autofill_result(profile, "id", _student_id_edit.text.strip_edges(), _autofill_epoch)


func apply_autofill_result(profile: Dictionary, field: String, query: String, edit_epoch: int) -> bool:
	if not bool(profile.get("lookup_confirmed", false)) or edit_epoch != _autofill_epoch \
			or _autofill_field != field or _autofill_value != query:
		return false
	var student_id := _first_text(profile, ["student_id", "studentId", "id"])
	var student_name := _first_text(profile, ["student_name", "name"])
	var grade := _first_text(profile, ["grade_section", "grade", "section"])
	if student_id.is_empty() or student_name.is_empty() or grade.is_empty():
		return false
	if field == "id":
		if _student_id_edit.text.strip_edges() != query or student_id != query:
			return false
		# Never replace a teacher's manually entered conflicting identity.
		if not _name_edit.text.strip_edges().is_empty() and \
				_name_edit.text.strip_edges().to_lower() != student_name.to_lower():
			return false
		if not _grade_edit.text.strip_edges().is_empty() and \
				_grade_edit.text.strip_edges().to_lower() != grade.to_lower():
			return false
	elif field == "name":
		if _name_edit.text.strip_edges().to_lower() != query.to_lower() \
				or student_name.to_lower() != query.to_lower():
			return false
		if not _student_id_edit.text.strip_edges().is_empty() and _student_id_edit.text.strip_edges() != student_id:
			return false
		if not _grade_edit.text.strip_edges().is_empty() and \
				_grade_edit.text.strip_edges().to_lower() != grade.to_lower():
			return false
	else:
		return false
	_applying_context = true
	_student_id_edit.text = student_id
	_name_edit.text = student_name
	_grade_edit.text = grade
	_applying_context = false
	_identity_student_id = student_id
	_verified_lookup_identity = {
		"student_id": student_id,
		"student_name": student_name,
		"grade_section": grade,
	}
	context["student_lookup_connected"] = true
	# A confirmed, exact lookup is authoritative enough to clear an old
	# registration hold. Unconfirmed or mismatched replies return above.
	_registration_error = ""
	_update_validation()
	return true


func show_database_status(message: String, connected: bool = false, setup_required: bool = false) -> void:
	# The form intentionally contains no connection/lookup UI. Keep state for
	# score persistence, but don't disclose internal database errors to pupils.
	# The router sends a read-only ID check before Play can open Game Selection.
	# Give a small, neutral status in the existing editor-authored label; an
	# asynchronous check must not look like a dead green Continue button.
	var upper := message.strip_edges().to_upper()
	_lookup_pending = upper.begins_with("CHECKING STUDENT ID") or upper.begins_with("STILL CHECKING STUDENT ID")
	# An absent ID is an ordinary first-time Play registration. A fresh
	# confirmed not-found result may clear a previous transient lookup error,
	# but it must never lift a hold on a genuinely conflicting existing ID.
	if _is_missing_student_status(upper) and not _is_existing_identity_conflict(_registration_error):
		_registration_error = ""
	if not _lookup_pending:
		context["database_connected"] = connected
	_update_validation()


func show_registration_error(message: String) -> void:
	# A mismatched student ID remains a real safety hold. Explain what to
	# correct in a short neutral message; don't reproduce the long red banner.
	_lookup_pending = false
	# The router may report a confirmed missing ID through either status
	# entry point. It means "new student", not a failed/invalid registration.
	var clean_message := message.strip_edges()
	if _is_missing_student_status(clean_message):
		if not _is_existing_identity_conflict(_registration_error):
			_registration_error = ""
	else:
		_registration_error = clean_message
	_update_validation()


func _is_missing_student_status(message: String) -> bool:
	var upper := message.strip_edges().to_upper()
	return (
		upper.begins_with("STUDENT ID NOT FOUND")
		or upper.begins_with("STUDENT NOT FOUND")
		or upper.begins_with("NEW STUDENT")
		or upper == "STUDENT_NOT_FOUND"
	)


func _is_existing_identity_conflict(message: String) -> bool:
	var upper := message.strip_edges().to_upper()
	return (
		upper.contains("ALREADY REGISTERED")
		or upper.contains("CHECK STUDENT ID AND NAME")
		or upper.contains("STUDENT_CONFLICT")
		or upper.contains("IDENTITY CONFLICT")
	)


func _valid_student_id(value: String) -> bool:
	# Match the offline Python API's student_id_field exactly: the first
	# character must be an ASCII letter or digit; subsequent characters may
	# additionally be dot, underscore or hyphen. No spaces or Unicode IDs.
	var student_id := value.strip_edges()
	if student_id.is_empty() or student_id.length() > MAX_STUDENT_ID_LENGTH:
		return false
	for index in student_id.length():
		var char_code := student_id.unicode_at(index)
		var ascii_letter := (char_code >= 65 and char_code <= 90) or (char_code >= 97 and char_code <= 122)
		var digit := char_code >= 48 and char_code <= 57
		if ascii_letter or digit:
			continue
		if index > 0 and char_code in [46, 95, 45]:
			continue
		return false
	return true


func _should_prefill(source: Dictionary) -> bool:
	# An explicit fresh-setup request must override any legacy Retry/Results
	# entry_source carried by the router; never show green from stale fields.
	if source.has("student_setup_prefill"):
		return bool(source["student_setup_prefill"])
	var entry_source := String(source.get("entry_source", "")).strip_edges().to_lower()
	return entry_source in ["retry", "results", "game_over"]


func _clear_setup_context() -> void:
	for key in [
		"student_id", "studentId", "id", "student_name", "name",
		"grade_section", "grade", "section", "game_style", "style",
		"game_mode", "mode", "difficulty", "topic", "student_lookup_connected",
		"player_mode", "player_count", "players", "player_1", "player_2",
		"player2_student_id", "player2_student_name", "player2_grade_section",
		"player_2_student_id", "player_2_student_name", "player_2_grade_section"
	]:
		context.erase(key)
	context.erase("student_setup_prefill")
	_verified_lookup_identity.clear()


func _build_ui() -> void:
	# All permanent layout, PNGs, buttons and fields are authored in the .tscn.
	_setup_stage = get_node("SetupStage") as Control
	_student_card = _setup_stage.get_node("StudentProfileCard") as Control
	_game_card = _setup_stage.get_node("GameSetupCard") as Control
	_student_id_edit = _student_card.get_node("StudentIdGroup/StudentIdEdit") as LineEdit
	_profile_status = _student_card.get_node("ProfileStatus") as Label
	_default_id_text_color = _student_id_edit.get_theme_color("font_color")
	_name_edit = _student_card.get_node("StudentNameGroup/StudentNameEdit") as LineEdit
	_grade_edit = _student_card.get_node("GradeSectionGroup/GradeSectionEdit") as LineEdit
	var game := _game_card.get_node("GameContent") as Control
	_style_grid = game.get_node("GameStyleGrid") as Control
	_validation_label = game.get_node("ValidationPanel/ValidationLabel") as Label
	_player_one_summary = _game_card.get_node("PlayerOneSummary") as Label
	_player_two_panel = _game_card.get_node("PlayerTwoPanel") as Panel
	_player_two_status = _player_two_panel.get_node("Player2Status") as Label
	_player_two_id_edit = _player_two_panel.get_node("Player2IdEdit") as LineEdit
	_player_two_name_edit = _player_two_panel.get_node("Player2NameEdit") as LineEdit
	_player_two_grade_edit = _player_two_panel.get_node("Player2GradeEdit") as LineEdit
	var player_mode_row := _game_card.get_node("PlayerModeRow") as Control
	var player_mode_group := ButtonGroup.new()
	for item in PLAYER_MODES:
		var name := "SinglePlayerButton" if item == "Single Player" else "MultiplayerButton"
		var player_button := player_mode_row.get_node(name) as Button
		player_button.button_group = player_mode_group
		player_button.pressed.connect(_select_player_mode.bind(item))
		_player_mode_buttons[item] = player_button
	for edit in [_player_two_id_edit, _player_two_name_edit, _player_two_grade_edit]:
		edit.text_changed.connect(_on_player_two_changed)
	_player_two_id_edit.text_submitted.connect(func(_value: String) -> void: _player_two_name_edit.grab_focus())
	_player_two_name_edit.text_submitted.connect(func(_value: String) -> void: _player_two_grade_edit.grab_focus())
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
	var mode_row := game.get_node("LowerSelections/ModeColumn/ModeRow") as Control
	for item in GAME_MODES:
		var mode_button := mode_row.get_node(item + "Button") as Button
		mode_button.button_group = mode_group
		mode_button.pressed.connect(_select_mode.bind(item))
		mode_button.focus_entered.connect(_ensure_selection_visible.bind(mode_button))
		_mode_buttons[item] = mode_button
	var difficulty_group := ButtonGroup.new()
	var difficulty_row := game.get_node("LowerSelections/DifficultyColumn/DifficultyRow") as Control
	for item in DIFFICULTIES:
		var difficulty_button := difficulty_row.get_node(item + "Button") as Button
		difficulty_button.button_group = difficulty_group
		difficulty_button.pressed.connect(_select_difficulty.bind(item))
		difficulty_button.focus_entered.connect(_ensure_selection_visible.bind(difficulty_button))
		_difficulty_buttons[item] = difficulty_button

	_student_id_edit.text_changed.connect(_on_student_id_changed)
	_student_id_edit.focus_exited.connect(_associate_identity_with_current_id)
	_name_edit.text_changed.connect(_on_student_name_changed)
	_grade_edit.text_changed.connect(_on_grade_changed)
	_student_id_edit.text_submitted.connect(func(_value: String) -> void: _name_edit.grab_focus())
	_name_edit.text_submitted.connect(func(_value: String) -> void: _grade_edit.grab_focus())
	_grade_edit.text_submitted.connect(func(_value: String) -> void:
		if _profile_complete():
			_continue_button.grab_focus())
	_footer = _setup_stage.get_node("SetupActions") as Control
	_back_button = _footer.get_node("BackButton") as Button
	_continue_button = _footer.get_node("ContinueButton") as Button
	_back_button.pressed.connect(_go_back)
	_continue_button.pressed.connect(_continue)


func _apply_responsive_layout() -> void:
	if not is_instance_valid(_setup_stage):
		return
	# One editor-authored 1280x720 stage is uniformly fitted to the viewport.
	# No runtime positions of the independently draggable assets are changed.
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	_setup_stage.scale = Vector2.ONE * factor
	_setup_stage.position = (size - DESIGN_SIZE * factor) * 0.5


func _on_setup_scrolled(_value: float) -> void:
	call_deferred("_refresh_scroll_hint")


func _refresh_scroll_hint() -> void:
	pass # Fixed 1280x720 art requires no redundant scroll hint.


func _activate_scroll_hint() -> void:
	_focus_first_style()


func _ensure_selection_visible(control: Control) -> void:
	pass # The entire setup is already visible and scales with SetupStage.


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
	_selected_player_mode = _canonical_value(_first_text(context, ["player_mode"]), PLAYER_MODES) if prefill else ""
	var second: Dictionary = context.get("player_2", {}) if context.get("player_2", {}) is Dictionary else {}
	_player_two_id_edit.text = String(second.get("student_id", context.get("player2_student_id", ""))) if prefill else ""
	_player_two_name_edit.text = String(second.get("student_name", context.get("player2_student_name", ""))) if prefill else ""
	_player_two_grade_edit.text = String(second.get("grade_section", context.get("player2_grade_section", ""))) if prefill else ""
	_identity_student_id = _student_id_edit.text.strip_edges() if prefill and (not _name_edit.text.strip_edges().is_empty() or not _grade_edit.text.strip_edges().is_empty()) else ""
	_verified_lookup_identity.clear()
	if prefill and bool(context.get("student_lookup_connected", false)) and not _identity_student_id.is_empty():
		_verified_lookup_identity = {
			"student_id": _identity_student_id,
			"student_name": _name_edit.text.strip_edges(),
			"grade_section": _grade_edit.text.strip_edges(),
		}
	_sync_selection_buttons()
	_setup_phase = "profile"
	_show_setup_phase()
	_applying_context = false
	_invalidate_autofill()


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
	for player_mode in _player_mode_buttons:
		var button := _player_mode_buttons[player_mode] as Button
		button.set_pressed_no_signal(player_mode == _selected_player_mode)
	_player_two_panel.visible = _selected_player_mode == "Multiplayer" and _setup_phase == "game"


func _show_setup_phase() -> void:
	var profile_active := _setup_phase == "profile"
	_student_card.visible = profile_active
	_game_card.visible = not profile_active
	if is_instance_valid(_player_one_summary):
		_player_one_summary.text = "PLAYER ONE: " + _name_edit.text.strip_edges()
	if is_instance_valid(_player_two_panel):
		_player_two_panel.visible = not profile_active and _selected_player_mode == "Multiplayer"
	_update_validation()


func _select_player_mode(mode: String) -> void:
	if mode not in PLAYER_MODES:
		return
	_selected_player_mode = mode
	_sync_selection_buttons()
	_update_validation()


func _on_player_two_changed(_value: String) -> void:
	if _applying_context:
		return
	_update_validation()


func _profile_complete() -> bool:
	return _valid_student_id(_student_id_edit.text) \
		and not _name_edit.text.strip_edges().is_empty() \
		and not _grade_edit.text.strip_edges().is_empty() \
		and _registration_error.is_empty() and not _lookup_pending


func _player_two_complete() -> bool:
	if _selected_player_mode != "Multiplayer":
		return true
	return _valid_student_id(_player_two_id_edit.text) \
		and not _player_two_name_edit.text.strip_edges().is_empty() \
		and not _player_two_grade_edit.text.strip_edges().is_empty() \
		and _player_two_id_edit.text.strip_edges().to_lower() != _student_id_edit.text.strip_edges().to_lower()


func _multiplayer_activity_supported() -> bool:
	if _selected_player_mode != "Multiplayer":
		return true
	var chosen_activity := String(context.get("activity", "")).strip_edges()
	return chosen_activity.is_empty() or chosen_activity == "Catch the Word"


func _game_complete() -> bool:
	return _profile_complete() and GAME_STYLES.has(_selected_style) \
		and GAME_MODES.has(_selected_mode) and DIFFICULTIES.has(_selected_difficulty) \
		and PLAYER_MODES.has(_selected_player_mode) and _player_two_complete() \
		and _multiplayer_activity_supported()


func _on_student_id_changed(value: String) -> void:
	if _applying_context:
		return
	_registration_error = ""
	_lookup_pending = false
	_schedule_autofill("id", value)
	var clean_id := value.strip_edges()
	student_id_edited.emit(clean_id)
	if not _identity_student_id.is_empty() and clean_id != _identity_student_id:
		_applying_context = true
		_name_edit.clear()
		_grade_edit.clear()
		_applying_context = false
		_identity_student_id = ""
		_verified_lookup_identity.clear()
		context["student_lookup_connected"] = false
	_update_validation()


func _on_student_name_changed(value: String) -> void:
	if _applying_context:
		return
	_registration_error = ""
	_lookup_pending = false
	# A verified prior student's ID and grade must never be left on a newly
	# entered full name. Manually typed unverified IDs are not overwritten.
	if not _verified_lookup_identity.is_empty() \
			and value.strip_edges().to_lower() != String(_verified_lookup_identity.get("student_name", "")).to_lower():
		_applying_context = true
		_student_id_edit.clear()
		_grade_edit.clear()
		_applying_context = false
		_identity_student_id = ""
		_verified_lookup_identity.clear()
		context["student_lookup_connected"] = false
	_schedule_autofill("name", value)
	_on_field_changed(value)


func _on_grade_changed(value: String) -> void:
	if _applying_context:
		return
	_lookup_pending = false
	# Teacher edits to Grade & Section invalidate any in-flight ID/name
	# autofill. A late old response must not repopulate a deliberately cleared
	# grade and incorrectly unlock the green Continue button.
	_invalidate_autofill()
	_on_field_changed(value)


func _invalidate_autofill() -> void:
	_autofill_epoch += 1
	_autofill_field = ""
	_autofill_value = ""
	if is_instance_valid(_autofill_timer):
		_autofill_timer.stop()


func _schedule_autofill(field: String, text: String) -> void:
	_invalidate_autofill()
	var clean := text.strip_edges()
	if clean.length() < 2:
		return
	# A full name is required. A partially entered first name must never be
	# treated as a unique student profile even if its short prefix matches.
	if field == "name" and clean.split(" ", false).size() < 2:
		return
	_autofill_field = field
	_autofill_value = clean
	if is_instance_valid(_autofill_timer):
		_autofill_timer.start(AUTOFILL_IDLE_SECONDS)


func _autofill_if_unchanged() -> void:
	var actual := _student_id_edit.text.strip_edges() if _autofill_field == "id" \
		else _name_edit.text.strip_edges()
	if _autofill_field in ["id", "name"] and not _autofill_value.is_empty() \
			and actual == _autofill_value and is_inside_tree():
		student_autofill_requested.emit(_autofill_field, _autofill_value, _autofill_epoch)


func _on_field_changed(_value: String) -> void:
	if _applying_context:
		return
	_registration_error = ""
	_lookup_pending = false
	if not _verified_lookup_identity.is_empty() and not _lookup_matches_current_fields():
		_verified_lookup_identity.clear()
		context["student_lookup_connected"] = false
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
	_lookup_pending = false
	_sync_selection_buttons()
	_update_validation()


func _select_mode(game_mode: String) -> void:
	var canonical := _canonical_value(game_mode, GAME_MODES)
	_selected_mode = canonical if not canonical.is_empty() else game_mode
	_lookup_pending = false
	_sync_selection_buttons()
	_update_validation()


func _select_difficulty(difficulty: String) -> void:
	var canonical := _canonical_value(difficulty, DIFFICULTIES)
	_selected_difficulty = canonical if not canonical.is_empty() else difficulty
	_lookup_pending = false
	_sync_selection_buttons()
	_update_validation()


func _update_validation() -> void:
	if _continue_button == null or _validation_label == null:
		return

	var invalid_student_id := not _student_id_edit.text.strip_edges().is_empty() and not _valid_student_id(_student_id_edit.text)
	_continue_button.disabled = not (_profile_complete() if _setup_phase == "profile" else _game_complete())
	_continue_button.modulate = Color.WHITE
	var profile_message := ""
	if invalid_student_id:
		profile_message = INVALID_STUDENT_ID_MESSAGE
	elif _lookup_pending:
		profile_message = "CHECKING STUDENT ID..."
	elif not _registration_error.is_empty():
		if _is_existing_identity_conflict(_registration_error):
			profile_message = "CHECK STUDENT ID AND NAME"
		else:
			profile_message = "STUDENT ID CHECK FAILED • TRY AGAIN"
	_profile_status.text = profile_message
	_profile_status.visible = _setup_phase == "profile" and not profile_message.is_empty()
	_validation_label.text = profile_message
	_validation_label.visible = _setup_phase == "game" and not profile_message.is_empty()
	var second_message := ""
	if _selected_player_mode == "Multiplayer":
		if not _multiplayer_activity_supported():
			second_message = "MULTIPLAYER IS AVAILABLE ONLY IN CATCH THE WORD"
		elif not _player_two_id_edit.text.strip_edges().is_empty() and not _valid_student_id(_player_two_id_edit.text):
			second_message = INVALID_STUDENT_ID_MESSAGE
		elif not _player_two_id_edit.text.strip_edges().is_empty() \
				and _player_two_id_edit.text.strip_edges().to_lower() == _student_id_edit.text.strip_edges().to_lower():
			second_message = "PLAYER TWO MUST HAVE A DIFFERENT STUDENT ID"
	_player_two_status.text = second_message
	_player_two_status.visible = not second_message.is_empty() and _player_two_panel.visible
	_validation_label.add_theme_color_override("font_color", STATUS_TEXT_COLOR)
	_student_id_edit.add_theme_color_override("font_color",
		CONFLICT_ID_TEXT_COLOR if invalid_student_id or not _registration_error.is_empty() else _default_id_text_color)
	var active_art := _continue_button.get_node_or_null("ButtonArtwork") as CanvasItem
	var disabled_art := _continue_button.get_node_or_null("ContinueDisabledArtwork") as CanvasItem
	if is_instance_valid(active_art):
		active_art.visible = not _continue_button.disabled
	if is_instance_valid(disabled_art):
		disabled_art.visible = _continue_button.disabled


func _continue() -> void:
	_update_validation()
	if _continue_button.disabled:
		return
	if _setup_phase == "profile":
		_setup_phase = "game"
		_show_setup_phase()
		call_deferred("_focus_first_style")
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
	payload["student_lookup_connected"] = _lookup_matches_current_fields()
	payload["player_mode"] = _selected_player_mode
	payload["player_count"] = 2 if _selected_player_mode == "Multiplayer" else 1
	if _selected_player_mode == "Multiplayer":
		payload["player2_student_id"] = _player_two_id_edit.text.strip_edges()
		payload["player2_student_name"] = _player_two_name_edit.text.strip_edges()
		payload["player2_grade_section"] = _player_two_grade_edit.text.strip_edges()
		payload["activity"] = "Catch the Word"
	else:
		for key in ["player2_student_id", "player2_student_name", "player2_grade_section"]:
			payload.erase(key)
	payload.erase("student_setup_prefill")
	if bool(context.get("guided_tutorial", false)):
		# The selected activity was carried from Guided Tutorial's first
		# Game Selection panel. The teacher's choices now complete setup.
		payload["keyboard_mode"] = false
		payload["camera_requested"] = true
		requested.emit("calibration", payload)
	elif _selected_player_mode == "Multiplayer":
		payload.erase("guided_tutorial")
		payload["entry_source"] = "play"
		payload["camera_requested"] = true
		payload["keyboard_mode"] = false
		requested.emit("calibration", payload)
	else:
		payload.erase("guided_tutorial")
		payload["entry_source"] = "play"
		requested.emit("play_activity", payload)


func _go_back() -> void:
	if _setup_phase == "game":
		_setup_phase = "profile"
		_show_setup_phase()
		call_deferred("_focus_first")
		return
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


func _lookup_matches_current_fields() -> bool:
	return not _verified_lookup_identity.is_empty() \
		and String(_verified_lookup_identity.get("student_id", "")) == _student_id_edit.text.strip_edges() \
		and String(_verified_lookup_identity.get("student_name", "")) == _name_edit.text.strip_edges() \
		and String(_verified_lookup_identity.get("grade_section", "")) == _grade_edit.text.strip_edges()


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
