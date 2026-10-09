extends Control

signal requested(target: String, payload: Dictionary)

var _context: Dictionary = {}


func _ready() -> void:
	%BackButton.pressed.connect(_request_main)
	_setup_filter(%StyleFilter, ["ALL STYLES", "NOUN", "PRONOUN", "VERB", "ADJECTIVE", "ADVERB", "INTERJECTION • SOON"])
	_setup_filter(%ModeFilter, ["ALL MODES", "QUIZ", "ACTIVITY"])
	_setup_filter(%DifficultyFilter, ["ALL DIFFICULTIES", "EASY", "NORMAL", "HARD"])
	%BackButton.grab_focus()


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)


func _request_main() -> void:
	requested.emit("main", _context.duplicate(true))


func _setup_filter(filter: OptionButton, items: Array[String]) -> void:
	filter.clear()
	for item in items:
		filter.add_item(item)
	filter.select(0)
