extends Control

signal requested(target: String, payload: Dictionary)

var _context: Dictionary = {}


func _ready() -> void:
	%RetryButton.pressed.connect(_request.bind("student_setup"))
	%MainButton.pressed.connect(_request.bind("main"))
	_refresh()
	%RetryButton.grab_focus()


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)
	if is_node_ready():
		_refresh()


func _refresh() -> void:
	_set_optional_row(%StudentIdRow, %StudentIdValue, ["student_id", "studentId", "id"])
	_set_optional_row(%StudentNameRow, %StudentNameValue, ["student_name", "name"])
	_set_optional_row(%GradeRow, %GradeValue, ["grade", "grade_section", "section"])
	%StudentCard.visible = %StudentIdRow.visible or %StudentNameRow.visible or %GradeRow.visible
	_set_optional_row(%GameStyleRow, %GameStyleValue, ["game_style", "topic", "style"])
	_set_optional_row(%GameModeRow, %GameModeValue, ["game_mode", "mode"])
	_set_optional_row(%DifficultyRow, %DifficultyValue, ["difficulty"])
	%GameCard.visible = %GameStyleRow.visible or %GameModeRow.visible or %DifficultyRow.visible
	var score := _context_text(["score", "points"], "")
	%ScoreCard.visible = not score.is_empty()
	%ScoreValue.text = score
	var activity := _context_text(["activity"], "")
	%ActivityValue.text = activity
	%ActivityValue.visible = not activity.is_empty()
	var show_unsaved := bool(_context.get("demo_mode", false))
	if _context.has("database_connected"):
		show_unsaved = show_unsaved or not bool(_context["database_connected"])
	%SaveStatus.text = "PLAYABLE KEYBOARD ROUND  -  SCORE NOT SAVED" if bool(_context.get("gameplay_implemented", false)) else "DEMO ROUND  -  SCORE NOT SAVED"
	%SaveStatus.visible = show_unsaved


func _set_optional_row(row: Control, value_label: Label, keys: Array[String]) -> void:
	var value := _context_text(keys, "")
	row.visible = not value.is_empty()
	value_label.text = value


func _context_text(keys: Array[String], fallback: String = "—") -> String:
	for key in keys:
		if _context.has(key):
			var value := str(_context[key]).strip_edges()
			if not value.is_empty():
				return value
	return fallback


func _request(target: String) -> void:
	requested.emit(target, _context.duplicate(true))
