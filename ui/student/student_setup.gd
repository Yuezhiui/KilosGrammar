extends Control

signal requested(target: String, payload: Dictionary)
signal student_lookup_requested(student_id: String)
signal student_id_edited(student_id: String)

const UI = preload("res://ui/play/play_ui.gd")
const EXISTING_SCORE_DIALOG = preload("res://ui/student/existing_score_dialog.tscn")
const CARTOON = preload("res://ui/redesign/cartoon_ui.gd")
const STUDENT_ART := "res://ui/redesign/assets/student/"
const CLASSROOM_ART := "res://ui/redesign/assets/shared/classroom_bg.png"

const GAME_STYLES := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const FUTURE_STYLES := ["Preposition", "Conjunction", "Interjection"]
const GAME_MODES := ["Seconds", "Lives"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const STYLE_COLORS := [UI.GREEN, UI.PURPLE, UI.RED, Color("#E29A36"), UI.BLUE]
const MODE_COLORS := [UI.DEEP_BLUE, UI.GREEN]
const DIFFICULTY_COLORS := [UI.GREEN, Color("#E29A36"), UI.RED]
const PROFILE_CREAM := Color("#FFF2CE")
const CARD_BLUE := Color("#5D9DDF")
const CARD_BLUE_DARK := Color("#285D9B")
const CARD_BLUE_LIGHT := Color("#93CAFC")
const FRAME_INK := Color("#284A73")

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
var _art_nodes: Array[TextureRect] = []

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
	resized.connect(_apply_responsive_layout)
	call_deferred("_apply_responsive_layout")
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
	# A real standalone background fills the view, behind all native input
	# controls. The pale wash keeps the title and card edges readable without
	# obscuring the classroom details around the panels.
	var classroom := CARTOON.background(self, CLASSROOM_ART, "StudentClassroomBackdrop")
	if classroom == null:
		var fallback := ColorRect.new()
		fallback.name = "StudentBackdrop"
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback.color = Color("#D9EFFB")
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fallback)
	var wash := ColorRect.new()
	wash.name = "StudentReadabilityOverlay"
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.color = Color("#E8F4FF", 0.26)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

	_root_margin = MarginContainer.new()
	_root_margin.name = "LayoutMargins"
	_root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root_margin)
	var column := VBoxContainer.new()
	column.name = "StudentSetupColumn"
	column.add_theme_constant_override("separation", 9)
	_root_margin.add_child(column)

	var header := HBoxContainer.new()
	header.name = "SetupHeader"
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	_header_title = UI.make_label("STUDENT & GAME SETUP", 34, FRAME_INK)
	_header_title.name = "SetupTitle"
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_header_title)
	var accent := HSeparator.new()
	accent.add_theme_stylebox_override("separator", _soft_panel(CARD_BLUE_DARK, CARD_BLUE_DARK, 4))
	column.add_child(accent)

	_content_scroll = ScrollContainer.new()
	_content_scroll.name = "StudentSetupScroll"
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_content_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	column.add_child(_content_scroll)

	_setup_grid = GridContainer.new()
	_setup_grid.name = "SetupCardGrid"
	_setup_grid.columns = 2
	_setup_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_setup_grid.add_theme_constant_override("h_separation", 18)
	_setup_grid.add_theme_constant_override("v_separation", 16)
	_content_scroll.add_child(_setup_grid)
	_build_student_card(_setup_grid)
	_build_game_card(_setup_grid)
	_content_scroll.get_v_scroll_bar().value_changed.connect(_on_setup_scrolled)

	# A stacked compact layout puts the second card below the fold. Keep this
	# cue visible outside the scroll area so no student misses the game choices.
	_scroll_hint_button = Button.new()
	_scroll_hint_button.name = "GameSetupScrollHint"
	_scroll_hint_button.text = "SCROLL DOWN FOR GAME SETUP ↓"
	_scroll_hint_button.custom_minimum_size = Vector2(0, 34)
	_scroll_hint_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_scroll_hint_button.focus_mode = Control.FOCUS_ALL
	_scroll_hint_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_scroll_hint_button.add_theme_font_override("font", UI.TITLE_FONT)
	_scroll_hint_button.add_theme_font_size_override("font_size", 15)
	_scroll_hint_button.add_theme_color_override("font_color", Color("#FFF8DE"))
	_scroll_hint_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_scroll_hint_button.add_theme_color_override("font_focus_color", Color("#FFF8DE"))
	_scroll_hint_button.add_theme_stylebox_override("normal", _button_surface(Color("#285D9B", 0.94), Color("#FFF4C8"), 2))
	_scroll_hint_button.add_theme_stylebox_override("hover", _button_surface(Color("#3976B6"), Color.WHITE, 2))
	_scroll_hint_button.add_theme_stylebox_override("pressed", _button_surface(Color("#204B7B"), Color.WHITE, 2))
	_scroll_hint_button.add_theme_stylebox_override("focus", _button_focus())
	_scroll_hint_button.visible = false
	_scroll_hint_button.pressed.connect(_activate_scroll_hint)
	column.add_child(_scroll_hint_button)

	_footer = HBoxContainer.new()
	_footer.name = "SetupActions"
	_footer.add_theme_constant_override("separation", 20)
	_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	_footer.custom_minimum_size.y = 58
	column.add_child(_footer)
	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "← BACK"
	_back_button.custom_minimum_size = Vector2(194, 50)
	_style_action_button(_back_button, Color("#F7D480"))
	_apply_button_art(_back_button, "btn_back.png")
	_back_button.pressed.connect(_go_back)
	_footer.add_child(_back_button)
	_continue_button = Button.new()
	_continue_button.name = "ContinueButton"
	_continue_button.text = "CONTINUE →"
	_continue_button.custom_minimum_size = Vector2(240, 50)
	_style_action_button(_continue_button, Color("#7FC58E"))
	_apply_button_art(_continue_button, "btn_continue.png")
	_continue_button.pressed.connect(_continue)
	_footer.add_child(_continue_button)


func _apply_responsive_layout() -> void:
	if not is_instance_valid(_root_margin) or not is_instance_valid(_setup_grid):
		return
	# With canvas_items stretching, an 875px physical window still exposes the
	# 1280px logical layout. Check the actual window width as well so the
	# already-supported single-column/scrolling layout is used on small screens.
	var physical_width := size.x
	if DisplayServer.get_name() != "headless":
		physical_width = float(DisplayServer.window_get_size().x)
	var narrow := size.x < 1040.0 or physical_width < 1000.0
	var hmargin := int(clampf(size.x * 0.041, 12.0, 124.0))
	var vmargin := int(clampf(size.y * 0.023, 6.0, 26.0))
	_root_margin.add_theme_constant_override("margin_left", hmargin)
	_root_margin.add_theme_constant_override("margin_right", hmargin)
	_root_margin.add_theme_constant_override("margin_top", vmargin)
	_root_margin.add_theme_constant_override("margin_bottom", vmargin)
	_setup_grid.columns = 1 if narrow else 2
	_header_title.add_theme_font_size_override("font_size", 25 if narrow else 34)
	_header_title.custom_minimum_size.y = 36 if narrow else 49
	var compact := size.y <= 580.0
	_footer.custom_minimum_size.y = 44 if compact else 58
	_back_button.custom_minimum_size.y = 40 if compact else 50
	_continue_button.custom_minimum_size.y = 40 if compact else 50
	_back_button.custom_minimum_size.x = 160 if narrow else 194
	_continue_button.custom_minimum_size.x = 178 if narrow else 240
	if is_instance_valid(_style_grid):
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


func _build_student_card(parent: Container) -> void:
	var card := PanelContainer.new()
	card.name = "StudentProfileCard"
	_student_card = card
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _framed_card(PROFILE_CREAM, Color("#F5C77A"), 22))
	parent.add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	card.add_child(content)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 9)
	content.add_child(title_row)
	var student_icon := _small_art_icon("icon_player.png", Vector2(39, 38))
	if student_icon != null:
		title_row.add_child(student_icon)
	var title := UI.make_label("STUDENT PROFILE", 26, FRAME_INK)
	title.name = "StudentCardTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.custom_minimum_size.y = 34
	title_row.add_child(title)

	var helper := UI.make_body_label("Enter your student information", 13, Color(FRAME_INK, 0.84))
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
	database_panel.add_theme_stylebox_override("panel", _soft_panel(Color("#FFF7DF"), Color("#EAB682"), 13))
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
	_style_action_button(_lookup_button, Color("#E6C18A"))
	_lookup_button.pressed.connect(_request_lookup)
	database_box.add_child(_lookup_button)


func _build_game_card(parent: Container) -> void:
	var card := PanelContainer.new()
	card.name = "GameSetupCard"
	_game_card = card
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _framed_card(CARD_BLUE, CARD_BLUE_DARK, 22))
	parent.add_child(card)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	card.add_child(content)

	var heading := _decorative_label_art("setup_heading.png", Vector2(330, 55), "GameCardTitle")
	if heading != null:
		content.add_child(heading)
	else:
		var title := UI.make_label("GAME SETUP", 26, Color("#FFF4CB"))
		title.name = "GameCardTitle"
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.custom_minimum_size.y = 34
		content.add_child(title)

	content.add_child(_art_caption_or_label("setup_topic_caption.png", "GAME STYLE • GRAMMAR TOPIC"))
	_style_grid = GridContainer.new()
	_style_grid.name = "GameStyleGrid"
	_style_grid.columns = 4
	_style_grid.add_theme_constant_override("h_separation", 8)
	_style_grid.add_theme_constant_override("v_separation", 8)
	content.add_child(_style_grid)

	var style_group := ButtonGroup.new()
	for index in range(GAME_STYLES.size()):
		var game_style: String = GAME_STYLES[index]
		var button := _selection_button(game_style.to_upper(), STYLE_COLORS[index], 44, 14)
		_apply_button_art(button, "topic_" + game_style.to_lower() + ".png")
		button.button_group = style_group
		button.focus_entered.connect(_ensure_selection_visible.bind(button))
		button.pressed.connect(_select_style.bind(game_style))
		_style_grid.add_child(button)
		_style_buttons[game_style] = button

	for future_style in FUTURE_STYLES:
		var future := _selection_button("%s • SOON" % future_style.to_upper(), UI.INK, 44, 11)
		_apply_button_art(future, "topic_" + future_style.to_lower() + "_locked.png")
		future.disabled = true
		_style_grid.add_child(future)

	var lower := HBoxContainer.new()
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lower.add_theme_constant_override("separation", 12)
	content.add_child(lower)

	var mode_column := VBoxContainer.new()
	mode_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_column.add_theme_constant_override("separation", 8)
	lower.add_child(mode_column)
	mode_column.add_child(_art_caption_or_label("setup_mode_caption.png", "GAME MODE"))
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 8)
	mode_column.add_child(mode_row)
	var mode_group := ButtonGroup.new()
	for index in range(GAME_MODES.size()):
		var game_mode: String = GAME_MODES[index]
		var label_text: String = "60s" if game_mode == "Seconds" else "3 LIVES"
		var button := _selection_button(label_text, MODE_COLORS[index], 58, 15)
		_apply_button_art(button, "mode_" + game_mode.to_lower() + ".png")
		button.button_group = mode_group
		button.focus_entered.connect(_ensure_selection_visible.bind(button))
		button.pressed.connect(_select_mode.bind(game_mode))
		mode_row.add_child(button)
		_mode_buttons[game_mode] = button

	var difficulty_column := VBoxContainer.new()
	difficulty_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	difficulty_column.add_theme_constant_override("separation", 8)
	lower.add_child(difficulty_column)
	difficulty_column.add_child(_art_caption_or_label("setup_difficulty_caption.png", "DIFFICULTY"))
	var difficulty_row := HBoxContainer.new()
	difficulty_row.add_theme_constant_override("separation", 8)
	difficulty_column.add_child(difficulty_row)
	var difficulty_group := ButtonGroup.new()
	for index in range(DIFFICULTIES.size()):
		var difficulty: String = DIFFICULTIES[index]
		var button := _selection_button(difficulty.to_upper(), DIFFICULTY_COLORS[index], 58, 13)
		_apply_button_art(button, "difficulty_" + difficulty.to_lower() + ".png")
		button.button_group = difficulty_group
		button.focus_entered.connect(_ensure_selection_visible.bind(button))
		button.pressed.connect(_select_difficulty.bind(difficulty))
		difficulty_row.add_child(button)
		_difficulty_buttons[difficulty] = button

	var validation_panel := PanelContainer.new()
	validation_panel.add_theme_stylebox_override("panel", _soft_panel(Color("#4079B8"), Color("#B4DDFF"), 14))
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
	field.custom_minimum_size.y = 43
	field.focus_mode = Control.FOCUS_ALL
	field.add_theme_font_size_override("font_size", 16)
	field.add_theme_color_override("font_color", FRAME_INK)
	field.add_theme_color_override("font_placeholder_color", Color(FRAME_INK, 0.55))
	field.add_theme_color_override("caret_color", CARD_BLUE_DARK)
	field.add_theme_stylebox_override("normal", _field_style(false))
	field.add_theme_stylebox_override("focus", _field_style(true))
	stack.add_child(field)
	return field


func _field_style(focused: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#FFFDF4")
	style.border_width_left = 3 if focused else 2
	style.border_width_top = 3 if focused else 2
	style.border_width_right = 3 if focused else 2
	style.border_width_bottom = 3 if focused else 2
	style.border_color = Color("#E4A83F") if focused else Color("#C2A77B")
	style.corner_radius_top_left = 13
	style.corner_radius_top_right = 13
	style.corner_radius_bottom_left = 13
	style.corner_radius_bottom_right = 13
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
	var label := UI.make_label(text_value, 13, Color("#FCF6DE"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.custom_minimum_size.y = 20
	return label


func _selection_button(text_value: String, color: Color, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.text = text_value
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(0, height)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", UI.TITLE_FONT)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", FRAME_INK)
	button.add_theme_color_override("font_hover_color", FRAME_INK)
	button.add_theme_color_override("font_pressed_color", Color("#FFF9E6"))
	button.add_theme_color_override("font_focus_color", FRAME_INK)
	button.add_theme_color_override("font_disabled_color", Color("#7896B0"))
	button.add_theme_stylebox_override("normal", _button_surface(color, Color("#E8F3FF"), 1))
	button.add_theme_stylebox_override("hover", _button_surface(color.lightened(0.13), Color("#FFF7E8"), 2))
	button.add_theme_stylebox_override("pressed", _button_surface(color.darkened(0.12), CARD_BLUE_DARK, 2))
	button.add_theme_stylebox_override("disabled", _button_surface(Color("#A8BCD0"), Color("#809BB9"), 1))
	button.add_theme_stylebox_override("focus", _button_focus())
	return button


func _button_surface(fill: Color, border: Color, thickness: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_width_left = thickness
	style.border_width_top = thickness
	style.border_width_right = thickness
	style.border_width_bottom = thickness
	style.border_color = border
	style.set_corner_radius_all(11)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.shadow_color = Color("#23457447")
	style.shadow_size = 2
	style.shadow_offset = Vector2(0, 2)
	return style


func _button_focus() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color("#FFFDF4")
	style.set_border_width_all(3)
	style.set_corner_radius_all(13)
	return style


func _style_action_button(button: Button, fill: Color) -> void:
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", UI.TITLE_FONT)
	button.add_theme_font_size_override("font_size", 17)
	button.add_theme_color_override("font_color", FRAME_INK)
	button.add_theme_color_override("font_hover_color", FRAME_INK)
	button.add_theme_color_override("font_pressed_color", FRAME_INK)
	button.add_theme_color_override("font_disabled_color", Color("#64809D"))
	button.add_theme_stylebox_override("normal", _button_surface(fill, FRAME_INK, 3))
	button.add_theme_stylebox_override("hover", _button_surface(fill.lightened(0.14), FRAME_INK, 3))
	button.add_theme_stylebox_override("pressed", _button_surface(fill.darkened(0.14), FRAME_INK, 3))
	button.add_theme_stylebox_override("disabled", _button_surface(Color("#B8CAD7"), Color("#839FB7"), 2))
	button.add_theme_stylebox_override("focus", _button_focus())


func _apply_button_art(button: Button, filename: String) -> void:
	# Preserve the native Button for focus, ButtonGroup selection and signals.
	# The decorative PNG is a mouse-ignoring child, so it never intercepts input.
	var texture := CARTOON.load_art(STUDENT_ART + filename)
	if texture == null:
		return
	var face := TextureRect.new()
	face.name = "ButtonArtwork"
	face.texture = texture
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(face)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(state, Color.TRANSPARENT)


func _decorative_label_art(filename: String, dimensions: Vector2, node_name: String) -> TextureRect:
	var texture := CARTOON.load_art(STUDENT_ART + filename)
	if texture == null:
		return null
	var image := TextureRect.new()
	image.name = node_name
	image.texture = texture
	image.custom_minimum_size = dimensions
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return image


func _small_art_icon(filename: String, dimensions: Vector2) -> TextureRect:
	return _decorative_label_art(filename, dimensions, "StudentIcon")


func _art_caption_or_label(filename: String, fallback: String) -> Control:
	var label_art := _decorative_label_art(filename, Vector2(220, 27), fallback.replace(" ", "") + "Art")
	return label_art if label_art != null else _section_label(fallback)


func _framed_card(fill: Color, outline: Color, radius: int) -> StyleBoxFlat:
	var style := _soft_panel(fill, outline, radius)
	style.set_border_width_all(5)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	style.shadow_color = Color("#2845674D")
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 4)
	return style


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
	_continue_button.modulate = Color("#9EB1C3") if _continue_button.disabled else Color.WHITE
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
