extends Control

## EDITOR-DRIVEN LEADERBOARD: all permanent UI controls, backgrounds,
## positions, textures and styles are authored in leaderboard.tscn.
## Drag them in Godot's 2D editor; no script assigns node coordinates.
signal requested(target: String, payload: Dictionary)
## Only the host/backend may execute these operations. Paths are user-selected.
signal database_import_xlsx_requested(path: String)
signal database_export_xlsx_requested(path: String)
signal database_delete_all_requested(confirmation: String)

const FIELD_KEYS := ["student_id", "student_name", "grade", "game_style", "game_mode", "difficulty", "score"]
const ROW_SCENE := preload("res://ui/secondary/leaderboard/leaderboard_row.tscn")
const ROW_LABELS := ["StudentId", "StudentName", "Grade", "GameStyle", "GameMode", "Difficulty", "Score"]
const DELETE_CONFIRMATION := "DELETE ALL DATA"
const MAX_IMPORT_XLSX_BYTES := 8000000
const MINIGAME_FILTER_OPTIONS := ["ALL MINIGAMES", "CATCH THE WORD", "BALLOON POPPING", "HUMAN PLANE"]
const EDITOR_CANVAS_SIZE := Vector2(1280, 720)
const FILTER_INVISIBLE_ARROW := preload("res://Components/Leaderboard/Secondary/transparent_dropdown_arrow.png")
## Inspector-editable selected-state artwork. Index 0 is the original ALL image.
## Every element is an authored StyleBoxTexture from leaderboard.tscn.
@export var style_filter_skins: Array[StyleBoxTexture] = []
@export var mode_filter_skins: Array[StyleBoxTexture] = []
@export var difficulty_filter_skins: Array[StyleBoxTexture] = []
# Each node keeps its independent editor-authored position. Only proportional
# viewport scaling/centering happens at runtime, never per-button hardcoded XY.
const RESPONSIVE_NODE_NAMES := [
	"BoardArtwork", "TitleArt", "BackButton",
	"StyleFilter", "ModeFilter", "DifficultyFilter",
	"GradeLevelFilter", "SectionFilter", "StudentSearch", "ScoreSort",
	"TableHeaderArt", "TableBodyArt",
	"TableContent", "ImportCsvButton", "ExportCsvButton",
		"DeleteAllButton", "NoticeOverlay/NoticeStage"
]

var _context: Dictionary = {}
var _all_rows: Array[Dictionary] = []
var _visible_rows: Array[Dictionary] = []
var _selected_minigame := "ALL MINIGAMES"
var _filter_historical_minigame_only := false
var _grade_regex: RegEx
var _section_regex: RegEx

@onready var back_button: Button = %BackButton
@onready var style_filter: OptionButton = %StyleFilter
@onready var mode_filter: OptionButton = %ModeFilter
@onready var difficulty_filter: OptionButton = %DifficultyFilter
@onready var grade_level_filter: OptionButton = %GradeLevelFilter
@onready var section_filter: OptionButton = %SectionFilter
@onready var student_search: LineEdit = %StudentSearch
@onready var score_sort: OptionButton = %ScoreSort
@onready var empty_message: Label = %EmptyMessage
@onready var scroll: ScrollContainer = %ScoreRowsScroll
@onready var rows_container: VBoxContainer = %ScoreRows
@onready var notice_overlay: Control = %NoticeOverlay
@onready var notice_message: Label = %NoticeMessage
@onready var notice_okay_button: Button = %NoticeOkayButton
@onready var notice_close_button: Button = %NoticeCloseButton
@onready var import_button: Button = %ImportCsvButton
@onready var export_button: Button = %ExportCsvButton
@onready var delete_button: Button = %DeleteAllButton
@onready var import_dialog: FileDialog = %ImportCsvDialog
@onready var import_review_dialog: ConfirmationDialog = %ImportReviewDialog
@onready var database_export_dialog: FileDialog = %ExportDatabaseCsvDialog
@onready var delete_first_overlay: Control = %DeleteFirstOverlay
@onready var first_cancel_button: Button = %FirstCancelButton
@onready var first_continue_button: Button = %FirstContinueButton
@onready var delete_final_overlay: Control = %DeleteFinalOverlay
@onready var typed_confirmation_edit: LineEdit = %TypedConfirmationEdit
@onready var final_cancel_button: Button = %FinalCancelButton
@onready var final_delete_button: Button = %FinalDeleteButton
@onready var delete_success_overlay: Control = %DeleteSuccessOverlay
@onready var success_message: Label = %SuccessMessage
@onready var success_okay_button: Button = %SuccessOkayButton

var _delete_first_confirmed := false
var _transfer_pending := false
var _pending_import_path := ""
var _last_management_action := ""
var _queued_transfer_notice := ""
var _queued_transfer_success := false
var _last_transfer_notice_text := ""
var _notice_success := false
var _authored_ui_transforms: Dictionary = {}


func _ready() -> void:
	_grade_regex = RegEx.create_from_string("(?i)(?:^|[^a-z0-9])(?:grade\\s*|g\\s*)([0-9]{1,2})(?=$|[^0-9])")
	_section_regex = RegEx.create_from_string("(?i)^(?:grade\\s*|g\\s*)?[0-9]{1,2}\\s*[-:,&/| ]*\\s*(?:section\\s*)?")
	_capture_editor_layout()
	# All notice controls are editor-authored; no native AcceptDialog survives.
	notice_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	notice_overlay.hide()
	notice_okay_button.pressed.connect(_dismiss_notice)
	notice_close_button.pressed.connect(_dismiss_notice)
	resized.connect(_apply_viewport_layout)
	call_deferred("_apply_viewport_layout")
	back_button.pressed.connect(_request_main)
	# Minigame filtering remains host-callable without hidden controls.
	# The three visible selection filters remain editor-authored.
	for selector in [style_filter, mode_filter, difficulty_filter]:
		selector.item_selected.connect(_on_filter_changed.unbind(1))
	grade_level_filter.item_selected.connect(_on_grade_changed.unbind(1))
	section_filter.item_selected.connect(_on_filter_changed.unbind(1))
	student_search.text_changed.connect(_on_filter_changed.unbind(1))
	score_sort.item_selected.connect(_on_filter_changed.unbind(1))
	# Native Windows File Explorer dialogs use the actual Downloads folder,
	# instead of Godot's default project directory. Do not change the XLSX
	# security/authorization callbacks or their selected absolute paths.
	for dialog in [import_dialog, database_export_dialog]:
		dialog.use_native_dialog = OS.get_name() == "Windows" and DisplayServer.get_name() != "headless"
		_set_xlsx_start_directory(dialog)
	import_button.pressed.connect(_choose_import_xlsx)
	export_button.pressed.connect(_choose_database_export_xlsx)
	delete_button.pressed.connect(_begin_delete_all)
	import_dialog.file_selected.connect(_on_import_file_selected)
	import_review_dialog.confirmed.connect(_confirm_import_xlsx)
	import_review_dialog.canceled.connect(_cancel_import_xlsx)
	database_export_dialog.file_selected.connect(_on_export_file_selected)
	first_cancel_button.pressed.connect(_cancel_delete_all)
	first_continue_button.pressed.connect(_on_delete_first_confirmed)
	typed_confirmation_edit.text_changed.connect(_on_typed_confirmation_changed)
	typed_confirmation_edit.text_submitted.connect(_on_typed_confirmation_submitted)
	final_cancel_button.pressed.connect(_cancel_delete_all)
	final_delete_button.pressed.connect(_on_final_delete_pressed)
	success_okay_button.pressed.connect(_dismiss_delete_success)
	# These full-screen overlays capture pointer events while a destructive
	# confirmation is open, including clicks outside the artwork.
	delete_first_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	delete_final_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	delete_first_overlay.hide()
	delete_final_overlay.hide()
	delete_success_overlay.hide()
	# Context and transfer progress may be injected before add_child()/ _ready().
	_set_transfer_pending_state(_transfer_pending)
	_on_typed_confirmation_changed("")
	call_deferred("_focus_back")
	_on_filter_changed()
	if not _queued_transfer_notice.is_empty():
		call_deferred("_flush_queued_transfer_notice")


func set_minigame_filter(minigame: String) -> bool:
	## Host/API entry point, retained without a hidden FILTERS popup.
	## Historical rows have no known activity. Accept the old "Legacy" request
	## internally without presenting Legacy as a playable minigame.
	var wanted := minigame.strip_edges().to_upper()
	if wanted == "LEGACY":
		_filter_historical_minigame_only = true
		_selected_minigame = MINIGAME_FILTER_OPTIONS[0]
		_on_filter_changed()
		return true
	for option in MINIGAME_FILTER_OPTIONS:
		if option == wanted:
			_filter_historical_minigame_only = false
			_selected_minigame = option
			_on_filter_changed()
			return true
	return false


func _capture_editor_layout() -> void:
	for node_name in RESPONSIVE_NODE_NAMES:
		var control := get_node_or_null(node_name) as Control
		if control != null:
			_authored_ui_transforms[node_name] = {
				"position": control.position,
				"scale": control.scale
			}


func _apply_viewport_layout() -> void:
	# The root's background is separately full-rect, not moved/scaled here.
	# All UI art and hitboxes scale as a unit, keeping authored .tscn positions
	# accurate in 16:9 1280/1600/1920 windows. No scene element is reparented.
	var actual_size := size
	if actual_size.x < 10.0 or actual_size.y < 10.0:
		return
	var factor := minf(actual_size.x / EDITOR_CANVAS_SIZE.x,
		actual_size.y / EDITOR_CANVAS_SIZE.y)
	var upper_left := (actual_size - EDITOR_CANVAS_SIZE * factor) * 0.5
	for node_name in _authored_ui_transforms:
		var control := get_node_or_null(node_name) as Control
		if control == null:
			continue
		var authored: Dictionary = _authored_ui_transforms[node_name]
		control.scale = Vector2(authored["scale"]) * factor
		control.position = upper_left + Vector2(authored["position"]) * factor


func _focus_back() -> void:
	if is_instance_valid(back_button) and back_button.is_inside_tree():
		back_button.grab_focus()


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)
	# A new database state must revoke a pending destructive confirmation.
	_cancel_delete_all()
	if not _teacher_authorized():
		_cancel_import_xlsx()
	_all_rows.clear()
	# Rows are supplied by the local PostgreSQL client. Never synthesize scores
	# while the service is unavailable, and keep all scene-authored layout.
	var source: Variant = _context.get("leaderboard_rows", [])
	if source is Array:
		for item in source:
			if item is Dictionary:
				_all_rows.append((item as Dictionary).duplicate(true))
	_all_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0)) > float(b.get("score", 0))
	)
	if is_node_ready():
		_rebuild_grade_options()
		_on_filter_changed()


func _request_main() -> void:
	_cancel_delete_all()
	if is_instance_valid(delete_success_overlay):
		delete_success_overlay.hide()
	requested.emit("main", _context.duplicate(true))


func _on_filter_changed() -> void:
	_update_filter_appearance()
	_visible_rows.clear()
	var selected_minigame := _selected_minigame
	var selected_style := style_filter.get_item_text(style_filter.selected).to_upper()
	var selected_mode := mode_filter.get_item_text(mode_filter.selected).to_upper()
	var selected_difficulty := difficulty_filter.get_item_text(difficulty_filter.selected).to_upper()
	var selected_grade := grade_level_filter.get_item_text(grade_level_filter.selected)
	var selected_section := section_filter.get_item_text(section_filter.selected)
	var search_term := student_search.text.strip_edges().to_lower()
	for record in _all_rows:
		var actual_minigame := _minigame_name(record).to_upper()
		if _filter_historical_minigame_only and actual_minigame != "LEGACY":
			continue
		if not _filter_historical_minigame_only and selected_minigame != "ALL MINIGAMES" and actual_minigame != selected_minigame.to_upper():
			continue
		if selected_style != "ALL STYLES" and _record_text(record, 3).to_upper() != selected_style:
			continue
		if selected_mode != "ALL MODES" and _record_text(record, 4).to_upper() != selected_mode:
			continue
		if selected_difficulty != "ALL DIFFICULTIES" and _record_text(record, 5).to_upper() != selected_difficulty:
			continue
		if selected_grade != "All Grades" and _grade_level(record) != selected_grade:
			continue
		if selected_section != "All Sections" and _section_name(record) != selected_section:
			continue
		if not search_term.is_empty() and not _student_id(record).to_lower().contains(search_term) \
				and not _record_text(record, 1).to_lower().contains(search_term):
			continue
		_visible_rows.append(record)
	_sort_visible_rows()
	_redraw_rows()


func _on_grade_changed() -> void:
	_rebuild_section_options()
	# A newly selected grade begins with ALL its sections; keeping an old
	# similarly named section can silently hide other pupils in the new grade.
	section_filter.select(0)
	_on_filter_changed()


func _grade_level(record: Dictionary) -> String:
	var raw := _record_text(record, 2).strip_edges()
	var hit := _grade_regex.search(raw)
	if hit != null:
		return "Grade " + str(int(hit.get_string(1)))
	# Historic rows may contain only "4 - Emerald" or "4".
	var prefix := raw.split(" ", false)[0].trim_suffix("-").trim_suffix(":") if not raw.is_empty() else ""
	if prefix.is_valid_int() and int(prefix) >= 1 and int(prefix) <= 12:
		return "Grade " + str(int(prefix))
	return "Unspecified Grade"


func _section_name(record: Dictionary) -> String:
	var raw := _record_text(record, 2).strip_edges()
	if _grade_level(record) == "Unspecified Grade":
		return raw if not raw.is_empty() else "Unspecified Section"
	var stripped := _section_regex.sub(raw, "", true).strip_edges()
	stripped = stripped.trim_prefix("-").trim_prefix(":").trim_prefix("&").trim_prefix(",").strip_edges()
	if stripped.to_lower().begins_with("section "):
		stripped = stripped.substr(8).strip_edges()
	return stripped if not stripped.is_empty() else "Unspecified Section"


func _student_id(record: Dictionary) -> String:
	return str(record.get("student_id", "")).strip_edges()


func _rebuild_grade_options() -> void:
	var previous := grade_level_filter.get_item_text(grade_level_filter.selected) if grade_level_filter.selected >= 0 else "All Grades"
	var unique: Dictionary = {}
	for record in _all_rows:
		unique[_grade_level(record)] = true
	var keys := unique.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		if str(a) == "Unspecified Grade":
			return false
		if str(b) == "Unspecified Grade":
			return true
		return int(str(a).trim_prefix("Grade ")) < int(str(b).trim_prefix("Grade "))
	)
	grade_level_filter.clear()
	grade_level_filter.add_item("All Grades")
	for value in keys:
		grade_level_filter.add_item(str(value))
	_select_item_by_text(grade_level_filter, previous)
	_rebuild_section_options()


func _rebuild_section_options() -> void:
	var previous := section_filter.get_item_text(section_filter.selected) if section_filter.selected >= 0 else "All Sections"
	var grade := grade_level_filter.get_item_text(grade_level_filter.selected)
	var unique: Dictionary = {}
	for record in _all_rows:
		if grade == "All Grades" or _grade_level(record) == grade:
			unique[_section_name(record)] = true
	var names := unique.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a).naturalnocasecmp_to(str(b)) < 0)
	section_filter.clear()
	section_filter.add_item("All Sections")
	for name in names:
		section_filter.add_item(str(name))
	_select_item_by_text(section_filter, previous)


func _select_item_by_text(selector: OptionButton, title: String) -> void:
	selector.select(0)
	for index in range(1, selector.item_count):
		if selector.get_item_text(index) == title:
			selector.select(index)
			break


func _sort_visible_rows() -> void:
	var kind := score_sort.selected
	_visible_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		match kind:
			1:
				return _record_text(a, 1).naturalnocasecmp_to(_record_text(b, 1)) < 0
			2:
				return _student_id(a).naturalnocasecmp_to(_student_id(b)) < 0
			3:
				var a_grade := _grade_level(a)
				var b_grade := _grade_level(b)
				if a_grade != b_grade:
					return a_grade.naturalnocasecmp_to(b_grade) < 0
				var a_section := _section_name(a)
				var b_section := _section_name(b)
				if a_section != b_section:
					return a_section.naturalnocasecmp_to(b_section) < 0
			4:
				return float(a.get("score", 0)) < float(b.get("score", 0))
		return float(a.get("score", 0)) > float(b.get("score", 0))
	)


func _update_filter_appearance() -> void:
	var controls: Array[OptionButton] = [style_filter, mode_filter, difficulty_filter]
	var skin_sets: Array = [style_filter_skins, mode_filter_skins, difficulty_filter_skins]
	for index in controls.size():
		var selector := controls[index]
		var skins: Array = skin_sets[index]
		if selector.selected < 0 or selector.selected >= skins.size():
			continue
		var style := skins[selector.selected] as StyleBoxTexture
		if style == null:
			continue
		# The native button handles focus/click/dropdown; the image carries
		# the selected caption and its ONE arrow in every selected state.
		selector.add_theme_icon_override("arrow", FILTER_INVISIBLE_ARROW)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			selector.add_theme_stylebox_override(state, style)
		for key in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
			selector.add_theme_color_override(key, Color.TRANSPARENT)


func _redraw_rows() -> void:
	for row in rows_container.get_children():
		rows_container.remove_child(row)
		row.queue_free()
	scroll.visible = not _visible_rows.is_empty()
	empty_message.visible = _visible_rows.is_empty()
	if empty_message.visible:
		if not _all_rows.is_empty():
			empty_message.text = "No scores match these filters"
		elif bool(_context.get("database_loading", false)):
			empty_message.text = "Loading saved student scores..."
		elif not bool(_context.get("database_connected", false)):
			empty_message.text = "Local database unavailable • Ask your teacher for help"
		else:
			empty_message.text = "No completed scores saved yet"
	for record in _visible_rows:
		var row: Control = ROW_SCENE.instantiate()
		rows_container.add_child(row)
		for col in range(FIELD_KEYS.size()):
			var cell := row.get_node_or_null(ROW_LABELS[col]) as Label
			if cell != null:
				if FIELD_KEYS[col] == "game_style":
					var topic := _record_text(record, col)
					var minigame := _minigame_name(record)
					if minigame.to_upper() == "LEGACY":
						# The pre-migration activity is unknown; only its grammar topic
						# was recorded. Never imply that Legacy was a game mode.
						cell.text = _topic_short(topic)
						cell.tooltip_text = "Grammar topic: %s" % topic
					else:
						cell.text = "%s / %s" % [_minigame_short(minigame), _topic_short(topic)]
						cell.tooltip_text = "%s • Grammar topic: %s" % [minigame, topic]
				else:
					cell.text = _record_text(record, col)
					# Long IDs, names, and grade/section values are real school data.
					# Keep the complete source text available when the row must ellipsize.
					cell.tooltip_text = cell.text
					_fit_row_cell_font(cell, col)

func _fit_row_cell_font(cell: Label, column: int) -> void:
	# Columns and their maximum fonts are defined in leaderboard_row.tscn.
	# IDs, names and grade/section can use two lines within the authored row.
	# Shrink overflowing text only after using that vertical space. Exceptionally
	# long values are still available in full through the tooltip.
	var font := cell.get_theme_font("font")
	var font_size := cell.get_theme_font_size("font_size")
	var minimum_size := 10
	if font == null:
		return
	var available_width := cell.size.x - 6.0
	if column <= 2 and _row_text_width(font, cell.text, font_size) > available_width:
		cell.text = _break_row_text(cell.text, font, font_size)
	while font_size > minimum_size and (_row_text_width(font, cell.text, font_size) > available_width
		or cell.text.contains("\n") and font.get_height(font_size) * 2.0 > cell.size.y - 2.0):
		font_size -= 1
	cell.add_theme_font_size_override("font_size", font_size)


func _row_text_width(font: Font, cell_text: String, font_size: int) -> float:
	var result := 0.0
	for line in cell_text.split("\n"):
		result = maxf(result, font.get_string_size(line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	return result


func _break_row_text(value: String, font: Font, font_size: int) -> String:
	# Prefer a meaningful break, e.g. KG-2026 / 001 or Grade 5 / Section A.
	# For an all-digit student ID there may be no separator; use its midpoint.
	var best_split := -1
	var smallest_width := INF
	for index in range(2, value.length() - 1):
		var before := value[index - 1]
		var after := value[index]
		if before != " " and before != "-" and before != "_" and after != " ":
			continue
		var first := value.substr(0, index).strip_edges()
		var second := value.substr(index).strip_edges()
		if first.is_empty() or second.is_empty():
			continue
		var widest := maxf(_row_text_width(font, first, font_size),
			_row_text_width(font, second, font_size))
		if widest < smallest_width:
			smallest_width = widest
			best_split = index
	if best_split < 0:
		best_split = value.length() / 2
	return value.substr(0, best_split).strip_edges() + "\n" + value.substr(best_split).strip_edges()


func _minigame_name(record: Dictionary) -> String:
	# The additive database migration explicitly marks old scores as Legacy.
	var label := str(record.get("minigame", "Legacy")).strip_edges()
	return "Legacy" if label.is_empty() else label


func _minigame_short(minigame: String) -> String:
	match minigame.to_upper():
		"CATCH THE WORD":
			return "CATCH"
		"BALLOON POPPING":
			return "POP"
		"HUMAN PLANE":
			return "PLANE"
		_:
			return minigame.left(8).to_upper()


func _topic_short(topic: String) -> String:
	match topic.to_upper():
		"PRONOUN":
			return "PRON"
		"ADJECTIVE":
			return "ADJ"
		"ADVERB":
			return "ADV"
		"PREPOSITION":
			return "PREP"
		"CONJUNCTION":
			return "CONJ"
		"INTERJECTION":
			return "INTERJ"
		_:
			return topic.left(8).to_upper()


func _record_text(record: Dictionary, column: int) -> String:
	var key: String = FIELD_KEYS[column]
	if key == "score":
		# PostgreSQL/JSON may supply a decimal representation (e.g. 1660.0)
		# of an integer score. Keep the source value intact for sorting/CSV,
		# but show a clean whole-number score in the leaderboard rows.
		return str(roundi(float(record.get("score", 0))))
	if key == "student_name":
		return str(record.get("student_name", record.get("name", "")))
	if key == "grade":
		return str(record.get("grade", record.get("grade_section", "")))
	if key == "game_style":
		return str(record.get("game_style", record.get("topic", "")))
	return str(record.get(key, ""))


func _set_xlsx_start_directory(dialog: FileDialog) -> void:
	# Windows' Known Folder API resolves Downloads even when the user moved it
	# away from C:/Users/<account>/Downloads. FileDialog requires filesystem
	# access for both Windows' native chooser and Godot's non-Windows fallback.
	var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if not downloads.is_empty() and DirAccess.dir_exists_absolute(downloads):
		dialog.current_dir = downloads


func _open_xlsx_dialog(dialog: FileDialog, suggested_filename: String = "") -> void:
	# Reset on EVERY open: the prior user-selected folder must not override the
	# requested Downloads default for the next import or export.
	_set_xlsx_start_directory(dialog)
	dialog.current_file = suggested_filename
	# The previous backend result must not remain an exclusive native window
	# over a new Excel workbook file chooser.
	if notice_overlay.visible:
		_dismiss_notice()
	dialog.popup_centered()


func _choose_import_xlsx() -> void:
	if _transfer_pending:
		_show_status("Finish the pending database transfer before importing another file.")
		return
	_last_management_action = "import"
	if not _teacher_authorized():
		set_transfer_status("Teacher authorization required to import student records.")
		return
	_cancel_import_xlsx()
	_open_xlsx_dialog(import_dialog)


func _choose_database_export_xlsx() -> void:
	if _transfer_pending:
		_show_status("A database transfer is already pending. Please finish it first.")
		return
	_last_management_action = "export"
	if not _teacher_authorized():
		set_transfer_status("Teacher authorization required to export student records.")
		return
	_open_xlsx_dialog(database_export_dialog, "kilosgrammar_student_scores.xlsx")


func _on_import_file_selected(path: String) -> void:
	import_dialog.hide()
	if _transfer_pending:
		_show_status("Another database transfer is still pending.")
		return
	_last_management_action = "import"
	if not _teacher_authorized():
		set_transfer_status("Teacher authorization expired. Import canceled.")
		return
	var validation := _validate_import_xlsx(path)
	if not validation.is_empty():
		set_transfer_status(validation)
		return
	_pending_import_path = path
	import_review_dialog.dialog_text = (
		"Selected Excel workbook: %s\n\nThis may create or update student profiles and completed scores. "
		+ "The local database must validate each row before saving. Confirm only if "
		+ "you recognize this file and intend to import its contents."
	) % path.get_file()
	# File selection signals can arrive directly in tests or from native dialogs.
	# Close a prior backend notice before opening this exclusive review window.
	if notice_overlay.visible:
		_dismiss_notice()
	import_review_dialog.popup_centered()


func _confirm_import_xlsx() -> void:
	import_review_dialog.hide()
	var path := _pending_import_path
	_pending_import_path = ""
	if _transfer_pending:
		_show_status("Excel import canceled because another database operation is pending.")
		return
	_last_management_action = "import"
	if not _teacher_authorized() or path.is_empty():
		set_transfer_status("Excel import canceled: teacher authorization required.")
		return
	# Recheck because the file could be replaced while the review window opens.
	var validation := _validate_import_xlsx(path)
	if not validation.is_empty():
		set_transfer_status(validation)
		return
	set_transfer_pending("Import requested. The database must validate records before saving anything.")
	database_import_xlsx_requested.emit(path)


func _cancel_import_xlsx() -> void:
	_pending_import_path = ""
	if is_instance_valid(import_review_dialog):
		import_review_dialog.hide()


func _on_export_file_selected(path: String) -> void:
	database_export_dialog.hide()
	if _transfer_pending:
		_show_status("Another database transfer is still pending.")
		return
	_last_management_action = "export"
	if not _teacher_authorized():
		set_transfer_status("Teacher authorization expired. Excel export canceled.")
		return
	if not _is_xlsx_path(path):
		set_transfer_status("Choose a .xlsx filename for the full database export.")
		return
	set_transfer_pending("Full Excel workbook export requested for ALL student profiles and completed scores.")
	database_export_xlsx_requested.emit(path)


func _begin_delete_all() -> void:
	if _transfer_pending:
		_show_status("Finish the pending database operation before deleting records.")
		return
	_last_management_action = "delete"
	if not _teacher_authorized():
		set_transfer_status("Teacher authorization required before deleting ALL students and scores.")
		return
	_reset_delete_confirmation()
	if notice_overlay.visible:
		# An earlier notice must not cover the custom delete warning board.
		# Restore its text after the teacher closes the delete challenge.
		_queued_transfer_notice = notice_message.text
		_queued_transfer_success = _notice_success
		_dismiss_notice()
	# The custom board carries the complete warning; no separate status banner.
	delete_first_overlay.show()
	first_continue_button.call_deferred("grab_focus")


func _on_delete_first_confirmed() -> void:
	# A synthetic button signal or stale event cannot skip the visible first
	# stage. Only the Continue button on that stage authorizes advancing.
	if not delete_first_overlay.visible:
		return
	if _transfer_pending:
		_reset_delete_confirmation()
		_show_status("Cannot continue deletion during a pending database operation.")
		return
	if not _teacher_authorized():
		_reset_delete_confirmation()
		set_transfer_status("Teacher authorization is required for deletion.")
		return
	_delete_first_confirmed = true
	typed_confirmation_edit.clear()
	delete_first_overlay.hide()
	delete_final_overlay.show()
	_on_typed_confirmation_changed("")
	typed_confirmation_edit.call_deferred("grab_focus")


func _on_typed_confirmation_changed(value: String) -> void:
	final_delete_button.disabled = value != DELETE_CONFIRMATION or not _delete_first_confirmed or not _teacher_authorized() or _transfer_pending


func _on_typed_confirmation_submitted(value: String) -> void:
	if value == DELETE_CONFIRMATION:
		_on_final_delete_pressed()


func _on_final_delete_pressed() -> void:
	# Check everything again even when called directly or through keyboard
	# activation; a disabled visual button is not an authorization boundary.
	if not delete_final_overlay.visible or not _delete_first_confirmed:
		return
	if not _teacher_authorized() or _transfer_pending or typed_confirmation_edit.text != DELETE_CONFIRMATION:
		_on_typed_confirmation_changed(typed_confirmation_edit.text)
		return
	_cancel_delete_all()
	set_transfer_pending("Permanent deletion requested for ALL student profiles and completed scores.")
	database_delete_all_requested.emit(DELETE_CONFIRMATION)


func _cancel_delete_all() -> void:
	var was_open := (is_instance_valid(delete_first_overlay) and delete_first_overlay.visible) \
		or (is_instance_valid(delete_final_overlay) and delete_final_overlay.visible)
	_reset_delete_confirmation()
	if was_open and not _transfer_pending and is_instance_valid(delete_button) \
			and delete_button.is_visible_in_tree() and not notice_overlay.visible:
		delete_button.grab_focus()


func _reset_delete_confirmation() -> void:
	var was_open := (is_instance_valid(delete_first_overlay) and delete_first_overlay.visible) \
		or (is_instance_valid(delete_final_overlay) and delete_final_overlay.visible)
	_delete_first_confirmed = false
	if is_instance_valid(delete_first_overlay):
		delete_first_overlay.hide()
	if is_instance_valid(delete_final_overlay):
		delete_final_overlay.hide()
	if is_instance_valid(typed_confirmation_edit):
		typed_confirmation_edit.clear()
	if is_instance_valid(final_delete_button):
		final_delete_button.disabled = true
	if was_open:
		_flush_queued_transfer_notice()


func show_delete_success(students_deleted: int, scores_deleted: int) -> void:
	## Called only after the host receives a successful delete_all_data reply.
	## Unlike CSV completion, this shows the supplied wooden success artwork.
	## Counts come from the acknowledged server response, never hardcoded text.
	if not is_node_ready():
		return
	_set_transfer_pending_state(false)
	_reset_delete_confirmation()
	_queued_transfer_notice = ""
	_queued_transfer_success = false
	_last_transfer_notice_text = ""
	notice_overlay.hide()
	success_message.text = "Deleted %d student profiles and %d saved scores." % [
		maxi(0, students_deleted), maxi(0, scores_deleted)]
	delete_success_overlay.show()
	success_okay_button.grab_focus()


func _dismiss_delete_success() -> void:
	delete_success_overlay.hide()
	_flush_queued_transfer_notice()
	if is_instance_valid(back_button) and back_button.is_visible_in_tree():
		back_button.grab_focus()


func _input(event: InputEvent) -> void:
	# Keep keyboard navigation inside the active modal, as well as capturing
	# pointer events. Escape is intentionally inert throughout this app:
	# destructive dialogs may be dismissed only with their authored buttons.
	if not delete_first_overlay.visible and not delete_final_overlay.visible:
		if notice_overlay.visible and event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("ui_focus_prev") or event.is_action_pressed("ui_focus_next"):
				var focus := get_viewport().gui_get_focus_owner()
				var backwards := event.is_action_pressed("ui_focus_prev")
				(notice_close_button if (focus == notice_okay_button and backwards) \
					else notice_okay_button if backwards or focus == notice_close_button \
					else notice_close_button).grab_focus()
				get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("ui_focus_prev"):
		# Physical Shift+Tab can match both ui_focus_prev and ui_focus_next.
		# Handle backwards first so confirmation dialog keyboard focus is safe.
		_cycle_delete_focus(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_focus_next"):
		_cycle_delete_focus(false)
		get_viewport().set_input_as_handled()


func _cycle_delete_focus(backwards: bool) -> void:
	var targets: Array[Control] = []
	if delete_final_overlay.visible:
		targets = [typed_confirmation_edit, final_cancel_button]
		if not final_delete_button.disabled:
			targets.append(final_delete_button)
	elif delete_first_overlay.visible:
		targets = [first_cancel_button, first_continue_button]
	var focus_index := targets.find(get_viewport().gui_get_focus_owner())
	if focus_index < 0:
		focus_index = 0 if backwards else -1
	var direction := -1 if backwards else 1
	targets[posmod(focus_index + direction, targets.size())].grab_focus()


func _teacher_authorized() -> bool:
	# A trusted app host must set this only after teacher authentication.
	# The server must independently enforce teacher privileges for mutations.
	return bool(_context.get("teacher_authorized", false))


func _is_xlsx_path(path: String) -> bool:
	return not path.is_empty() and path.to_lower().ends_with(".xlsx") and not path.contains("\n") and not path.contains("\r")


func _validate_import_xlsx(path: String) -> String:
	if not _is_xlsx_path(path):
		return "Import requires an .xlsx Excel workbook."
	if not FileAccess.file_exists(path):
		return "Selected Excel workbook does not exist or cannot be read."
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Cannot open the selected Excel workbook."
	var length := file.get_length()
	if length < 4 or length > MAX_IMPORT_XLSX_BYTES:
		return "Excel workbook must be non-empty and no larger than 8 MB."
	var signature := file.get_buffer(4)
	file.close()
	if signature != PackedByteArray([80, 75, 3, 4]):
		return "Selected file is not a valid .xlsx workbook (ZIP format required)."
	# XLSX is an Office Open XML archive; check only structure on the client.
	# Schema, row counts, data validity and spreadsheet formulas are rechecked
	# by the authorized backend before any student data is written.
	var workbook := ZIPReader.new()
	if workbook.open(path) != OK:
		return "Selected Excel workbook could not be opened."
	var files := workbook.get_files()
	var has_workbook := files.has("xl/workbook.xml")
	var has_worksheet := false
	for entry in files:
		if entry.begins_with("xl/worksheets/") and entry.ends_with(".xml"):
			has_worksheet = true
			break
	workbook.close()
	if not files.has("[Content_Types].xml") or not has_workbook or not has_worksheet:
		return "Selected Excel file is missing required workbook or worksheet entries."
	return ""


func _show_status(message: String) -> void:
	# Deliberate Excel actions may need validation feedback. The in-table empty
	# state already communicates routine offline health without a banner.
	_queue_or_show_transfer_notice(message, false)


func set_transfer_status(message: String, success: bool = false) -> void:
	## Main menu should call this when the backend acknowledges an operation.
	## A failed call keeps database state unchanged; show the actual server error.
	var was_pending := _transfer_pending
	var action := _last_management_action
	_set_transfer_pending_state(false)
	if message.begins_with("Connection lost. Any pending import/delete outcome is unknown"):
		# The host emits this generic warning whenever its health changes to
		# offline, even at startup with no import or delete in flight. Only a
		# dispatched mutation can have an unknown write outcome.
		if was_pending and action in ["import", "delete"]:
			var operation := "Excel import" if action == "import" else "DELETE ALL DATA"
			_queue_or_show_transfer_notice("Connection lost during %s. Its outcome is unknown. After reconnection, check saved records before attempting it again." % operation, false)
		_last_management_action = ""
		return
	_queue_or_show_transfer_notice(_explain_management_authorization(message), success)
	_last_management_action = ""
	# A successful *unrelated* export must not close a teacher's active delete
	# challenge or make its queued notice cover the custom warning artwork.
	# Any fresh backend context is applied through set_context(), which already
	# revokes a challenge when database/authorization state actually changes.


func _explain_management_authorization(message: String) -> String:
	# The backend enforces administrator authorization for EVERY /data/ route.
	# Preserve that security rule and translate its 403 text into the action the
	# teacher actually attempted. Never imply that a protected operation ran.
	var status := message.strip_edges().to_lower()
	if not status.contains("local administrator authorization required") \
			and not status.contains("admin_authorization_required"):
		return message
	match _last_management_action:
		"delete":
			return "DELETE ALL DATA was blocked. Local administrator authorization is required. No student profiles or scores were deleted. Ask the local administrator to authorize database management."
		"import":
			return "Excel import was blocked. Local administrator authorization is required to import student records. No records were imported. Ask the local administrator to authorize database management."
		"export":
			return "Full database Excel export was blocked. Local administrator authorization is required for database-wide exports. No workbook was created. Ask the local administrator to authorize database management."
		_:
			return "Database administration was blocked. Local administrator authorization is required for import, full export, and permanent deletion. No database change was confirmed."


func _queue_or_show_transfer_notice(message: String, success: bool) -> void:
	if not is_instance_valid(notice_overlay):
		# Hosts can call status methods before the scene enters the tree.
		_queued_transfer_notice = message
		_queued_transfer_success = success
		return
	if (is_instance_valid(delete_first_overlay) and delete_first_overlay.visible) \
			or (is_instance_valid(delete_final_overlay) and delete_final_overlay.visible) \
			or (is_instance_valid(delete_success_overlay) and delete_success_overlay.visible):
		# A generic notice must never obscure any custom delete challenge.
		_queued_transfer_notice = message
		_queued_transfer_success = success
	elif not message.is_empty():
		_show_transfer_notice(message, success)
	else:
		_queued_transfer_notice = ""
		_queued_transfer_success = false
		if notice_overlay.visible and notice_message.text == _last_transfer_notice_text:
			_dismiss_notice()
		_last_transfer_notice_text = ""


func _flush_queued_transfer_notice() -> void:
	if (is_instance_valid(delete_first_overlay) and delete_first_overlay.visible) \
			or (is_instance_valid(delete_final_overlay) and delete_final_overlay.visible) \
			or (is_instance_valid(delete_success_overlay) and delete_success_overlay.visible):
		return
	var message := _queued_transfer_notice
	var success := _queued_transfer_success
	_queued_transfer_notice = ""
	_queued_transfer_success = false
	if not message.is_empty():
		_show_transfer_notice(message, success)


func _show_transfer_notice(message: String, success: bool) -> void:
	if message.is_empty():
		return
	_last_transfer_notice_text = message
	_notice_success = success
	notice_message.text = message
	# Long security explanations must remain readable inside the illustrated
	# wood board; preserve the exact backend text without truncating it.
	notice_message.add_theme_font_size_override("font_size",
		20 if message.length() > 280 else 23 if message.length() > 160 else 27)
	notice_overlay.show()
	notice_okay_button.grab_focus()


func _dismiss_notice() -> void:
	if is_instance_valid(notice_overlay):
		notice_overlay.hide()
	_last_transfer_notice_text = ""
	if is_instance_valid(back_button) and back_button.is_visible_in_tree():
		back_button.grab_focus()


func set_transfer_pending(message: String) -> void:
	## Host calls this for "Preparing..." and other interim database progress.
	## Buttons remain locked until set_transfer_status indicates completion.
	_set_transfer_pending_state(true)
	# Progress text no longer creates a persistent status panel or interrupts
	# a CSV transfer. Backend completion/errors use set_transfer_status().


func set_processing(message: String) -> void:
	# Compatible shorthand for status reporters that already use this name.
	set_transfer_pending(message)


func _set_transfer_pending_state(pending: bool) -> void:
	_transfer_pending = pending
	# A transfer beginning from elsewhere must revoke any unfinished delete
	# challenge instead of leaving an actionable confirmation on screen.
	if pending and ((is_instance_valid(delete_first_overlay) and delete_first_overlay.visible) \
			or (is_instance_valid(delete_final_overlay) and delete_final_overlay.visible)):
		_cancel_delete_all()
	for button in [import_button, export_button, delete_button]:
		if is_instance_valid(button):
			button.disabled = pending
