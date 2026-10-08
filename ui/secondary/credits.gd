extends Control

signal requested(target: String, payload: Dictionary)

var _context: Dictionary = {}


func _ready() -> void:
	%BackButton.pressed.connect(_request_main)
	%BackButton.grab_focus()


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)


func _request_main() -> void:
	requested.emit("main", _context.duplicate(true))
