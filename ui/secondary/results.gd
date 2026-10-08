extends Control

signal requested(target: String, payload: Dictionary)

@onready var mode_badge: Label = %ModeBadge
@onready var activity_label: Label = %ActivityLabel
@onready var score_value: Label = %ScoreValue
@onready var accuracy_value: Label = %AccuracyValue
@onready var correct_value: Label = %CorrectValue
@onready var streak_value: Label = %StreakValue
@onready var status_label: Label = %StatusLabel

var _context: Dictionary = {}


func _ready() -> void:
	%RetryButton.pressed.connect(_request.bind("retry"))
	%TopicButton.pressed.connect(_request.bind("play_topic"))
	%ActivityButton.pressed.connect(_request.bind("play_activity"))
	%MainButton.pressed.connect(_request.bind("main"))
	_refresh()
	%RetryButton.grab_focus()


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)
	if is_node_ready():
		_refresh()


func _refresh() -> void:
	var is_demo := bool(_context.get("demo_mode", false))
	mode_badge.text = "DEMO ROUND" if is_demo else "ROUND RESULTS"

	var activity := str(_context.get("activity", ""))
	var topic := str(_context.get("topic", ""))
	var difficulty := str(_context.get("difficulty", ""))
	var detail_parts := PackedStringArray()
	for part in [activity, topic, difficulty]:
		if not part.is_empty():
			detail_parts.append(part)
	activity_label.text = " • ".join(detail_parts) if not detail_parts.is_empty() else "No round details received"

	score_value.text = _format_value(["score", "points"])
	accuracy_value.text = _format_accuracy()
	correct_value.text = _format_correct()
	streak_value.text = _format_value(["best_streak", "streak"])

	var has_result_data := _has_any_result_data()
	if has_result_data and is_demo:
		status_label.text = "Demo result values were provided by the gameplay preview."
	elif has_result_data:
		status_label.text = "Round values received from gameplay."
	else:
		status_label.text = "No result data received yet. Values stay blank until gameplay sends them."


func _format_value(keys: Array) -> String:
	for key in keys:
		if _context.has(key):
			return str(_context[key])
	return "—"


func _format_accuracy() -> String:
	if _context.has("accuracy"):
		var raw = _context["accuracy"]
		if typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT:
			var value := float(raw)
			if value <= 1.0:
				value *= 100.0
			return "%d%%" % int(round(value))
		return str(raw)
	if _context.has("correct") and (_context.has("total") or _context.has("attempts")):
		var total := maxi(int(_context.get("total", _context.get("attempts", 0))), 0)
		if total > 0:
			return "%d%%" % int(round(float(_context["correct"]) / float(total) * 100.0))
	return "—"


func _format_correct() -> String:
	if _context.has("correct") and (_context.has("total") or _context.has("attempts")):
		var total = _context.get("total", _context.get("attempts"))
		return "%s / %s" % [str(_context["correct"]), str(total)]
	return _format_value(["correct"])


func _has_any_result_data() -> bool:
	for key in ["score", "points", "accuracy", "correct", "total", "attempts", "best_streak", "streak"]:
		if _context.has(key):
			return true
	return false


func _request(target: String) -> void:
	requested.emit(target, _context.duplicate(true))
