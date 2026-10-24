extends Control

signal requested(target: String, payload: Dictionary)

const LOW_SCORE_CATCH_VOICE_PATH := "res://assets/audio/catch_voice/Better Luck.mp3"
# The requested low-score band was approximately 450-500; use its upper edge.
const LOW_SCORE_CATCH_THRESHOLD := 500

var _context: Dictionary = {}
var _low_score_voice: AudioStreamPlayer
var _encouragement_started := false


func _ready() -> void:
	%RetryButton.pressed.connect(_request.bind("student_setup"))
	%MainButton.pressed.connect(_request.bind("main"))
	_refresh()
	_play_low_score_encouragement()
	%RetryButton.grab_focus()


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)
	if is_node_ready():
		_refresh()
		_play_low_score_encouragement()


func _play_low_score_encouragement() -> void:
	# Pause -> View Results is not a completed round, and other games must not
	# inherit Catch's spoken message.
	if _encouragement_started or not should_play_catch_low_score(_context):
		return
	if not ResourceLoader.exists(LOW_SCORE_CATCH_VOICE_PATH):
		return
	var clip := load(LOW_SCORE_CATCH_VOICE_PATH) as AudioStream
	if clip == null:
		return
	_low_score_voice = AudioStreamPlayer.new()
	_low_score_voice.name = "LowScoreVoicePlayer"
	_low_score_voice.bus = "KilosSFX" if AudioServer.get_bus_index("KilosSFX") >= 0 else "Master"
	_low_score_voice.stream = clip
	add_child(_low_score_voice)
	_encouragement_started = true
	_low_score_voice.play()


static func should_play_catch_low_score(context: Dictionary) -> bool:
	return String(context.get("activity", "")) == "Catch the Word" \
		and bool(context.get("round_completed", false)) \
		and context.has("score") and int(context["score"]) < LOW_SCORE_CATCH_THRESHOLD


func _exit_tree() -> void:
	_stop_low_score_encouragement()


func _stop_low_score_encouragement() -> void:
	if is_instance_valid(_low_score_voice):
		_low_score_voice.stop()


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
	if bool(_context.get("score_saved", false)):
		%SaveStatus.text = "SCORE SAVED TO LOCAL POSTGRESQL"
	elif bool(_context.get("database_saving", false)):
		%SaveStatus.text = "SAVING COMPLETED SCORE TO LOCAL POSTGRESQL..."
	elif bool(_context.get("round_completed", false)):
		%SaveStatus.text = "SCORE NOT SAVED • LOCAL DATABASE UNAVAILABLE" if not bool(_context.get("database_connected", false)) else "SCORE NOT SAVED • ASK YOUR TEACHER FOR HELP"
	else:
		%SaveStatus.text = "ROUND NOT COMPLETED • NO SCORE WAS SAVED"
	%SaveStatus.visible = true


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
	_stop_low_score_encouragement()
	requested.emit(target, _context.duplicate(true))
