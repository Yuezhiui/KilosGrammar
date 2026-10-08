extends Control

signal requested(target: String, payload: Dictionary)

@onready var empty_title: Label = %EmptyTitle
@onready var empty_copy: Label = %EmptyCopy
@onready var category_buttons: Array[Button] = [
	%OverallButton,
	%CatchButton,
	%PlaneButton,
	%BalloonButton,
]

var _context: Dictionary = {}
var _category := "Overall"


func _ready() -> void:
	%BackButton.pressed.connect(_request_main)
	%OverallButton.pressed.connect(_select_category.bind("Overall", 0))
	%CatchButton.pressed.connect(_select_category.bind("Catch the Word", 1))
	%PlaneButton.pressed.connect(_select_category.bind("Human Plane", 2))
	%BalloonButton.pressed.connect(_select_category.bind("Balloon Popping", 3))
	_select_category(_category, 0)
	%BackButton.grab_focus()


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)


func _request_main() -> void:
	requested.emit("main", _context.duplicate(true))


func _select_category(category: String, active_index: int) -> void:
	_category = category
	for index in range(category_buttons.size()):
		var button: Button = category_buttons[index]
		button.disabled = index == active_index
	empty_title.text = "EMPTY LOCAL • %s" % category.to_upper()
	empty_copy.text = "No local scores yet for %s.\nComplete a round and this area can show results once local score storage is connected." % category
