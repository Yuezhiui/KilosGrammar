extends Control

## EDITOR-DRIVEN LEADERBOARD: all permanent UI controls, backgrounds,
## positions, textures and styles are authored in leaderboard.tscn.
## Drag them in Godot's 2D editor; no script assigns node coordinates.
signal requested(target: String, payload: Dictionary)

const CSV_FIELDS := ["STUDENT ID", "NAME", "GRADE", "GAME STYLE", "GAME MODE", "DIFFICULTY", "SCORE"]
const FIELD_KEYS := ["student_id", "student_name", "grade", "game_style", "game_mode", "difficulty", "score"]
const ROW_SCENE := preload("res://ui/secondary/leaderboard_row.tscn")
const ROW_LABELS := ["StudentId", "StudentName", "Grade", "GameStyle", "GameMode", "Difficulty", "Score"]

var _context: Dictionary = {}
var _all_rows: Array[Dictionary] = []
var _visible_rows: Array[Dictionary] = []

@onready var back_button: Button = %BackButton
@onready var download_button: Button = %DownloadButton
@onready var style_filter: OptionButton = %StyleFilter
@onready var mode_filter: OptionButton = %ModeFilter
@onready var difficulty_filter: OptionButton = %DifficultyFilter
@onready var empty_message: Label = %EmptyMessage
@onready var scroll: ScrollContainer = %ScoreRowsScroll
@onready var rows_container: VBoxContainer = %ScoreRows
@onready var empty_dialog: AcceptDialog = %EmptyNotice
@onready var csv_dialog: FileDialog = %SaveCsvDialog


func _ready() -> void:
	back_button.pressed.connect(_request_main)
	download_button.pressed.connect(_download_csv)
	for selector in [style_filter, mode_filter, difficulty_filter]:
		selector.item_selected.connect(_on_filter_changed.unbind(1))
	csv_dialog.file_selected.connect(_write_csv)
	call_deferred("_focus_back")
	_on_filter_changed()


func _focus_back() -> void:
	if is_instance_valid(back_button) and back_button.is_inside_tree():
		back_button.grab_focus()


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)
	_all_rows.clear()
	# Only an actual provided data source is shown. Local database storage
	# is not installed yet; an empty Leaderboard is the truthful default.
	var source: Variant = _context.get("leaderboard_rows", [])
	if source is Array:
		for item in source:
			if item is Dictionary:
				_all_rows.append((item as Dictionary).duplicate(true))
	_all_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0)) > float(b.get("score", 0))
	)
	if is_node_ready():
		_on_filter_changed()


func _request_main() -> void:
	requested.emit("main", _context.duplicate(true))


func _on_filter_changed() -> void:
	_visible_rows.clear()
	var selected_style := style_filter.get_item_text(style_filter.selected).to_upper()
	var selected_mode := mode_filter.get_item_text(mode_filter.selected).to_upper()
	var selected_difficulty := difficulty_filter.get_item_text(difficulty_filter.selected).to_upper()
	for record in _all_rows:
		if selected_style != "ALL STYLES" and _record_text(record, 3).to_upper() != selected_style:
			continue
		if selected_mode != "ALL MODES" and _record_text(record, 4).to_upper() != selected_mode:
			continue
		if selected_difficulty != "ALL DIFFICULTIES" and _record_text(record, 5).to_upper() != selected_difficulty:
			continue
		_visible_rows.append(record)
	_redraw_rows()


func _redraw_rows() -> void:
	for row in rows_container.get_children():
		rows_container.remove_child(row)
		row.queue_free()
	scroll.visible = not _visible_rows.is_empty()
	empty_message.visible = _visible_rows.is_empty()
	if empty_message.visible:
		empty_message.text = "No saved scores yet • database pending" if _all_rows.is_empty() else "No scores match these filters"
	for record in _visible_rows:
		var row: Control = ROW_SCENE.instantiate()
		rows_container.add_child(row)
		for col in range(FIELD_KEYS.size()):
			var cell := row.get_node_or_null(ROW_LABELS[col]) as Label
			if cell != null:
				cell.text = _record_text(record, col)


func _record_text(record: Dictionary, column: int) -> String:
	var key: String = FIELD_KEYS[column]
	if key == "student_name":
		return str(record.get("student_name", record.get("name", "")))
	if key == "grade":
		return str(record.get("grade", record.get("grade_section", "")))
	if key == "game_style":
		return str(record.get("game_style", record.get("topic", "")))
	return str(record.get(key, ""))


func _download_csv() -> void:
	if _visible_rows.is_empty():
		empty_dialog.popup_centered()
	else:
		csv_dialog.popup_centered()


func _write_csv(filepath: String) -> void:
	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		empty_dialog.dialog_text = "Could not write CSV to the selected location."
		empty_dialog.popup_centered()
		return
	file.store_string(",".join(CSV_FIELDS) + "\r\n")
	for record in _visible_rows:
		var cells: PackedStringArray = []
		for col in range(FIELD_KEYS.size()):
			var raw := _record_text(record, col).replace("\r", " ").replace("\n", " ")
			cells.append('"' + raw.replace('"', '""') + '"')
		file.store_string(",".join(cells) + "\r\n")
	file.close()
