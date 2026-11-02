extends Control

signal requested(target: String, payload: Dictionary)

const LOW_SCORE_CATCH_VOICE_PATH := "res://assets/audio/catch_voice/Better Luck.mp3"
# The requested low-score band was approximately 450-500; use its upper edge.
const LOW_SCORE_CATCH_THRESHOLD := 500
const DESIGN_SIZE := Vector2(1280.0, 720.0)

var _context: Dictionary = {}
var _low_score_voice: AudioStreamPlayer
var _encouragement_started := false


func _ready() -> void:
	%RetryButton.pressed.connect(_request.bind("student_setup"))
	%MainButton.pressed.connect(_request.bind("main"))
	resized.connect(_adapt_layout)
	call_deferred("_adapt_layout")
	_refresh()
	_play_low_score_encouragement()
	%RetryButton.grab_focus()


func _adapt_layout() -> void:
	# Child positions/sizes belong to the 2D editor. Only scale the authored
	# 1280x720 stage to accommodate 16:9 windows and wider aspect ratios.
	var stage := $ResultsStage as Control
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	stage.scale = Vector2.ONE * factor
	stage.position = (size - DESIGN_SIZE * factor) * 0.5


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)
	if is_node_ready():
		_refresh()
		_play_low_score_encouragement()


func _play_low_score_encouragement() -> void:
	# Pause -> View Results is not a completed round, and other games must not
	# inherit Catch's spoken message.
	if not should_play_catch_low_score(_context):
		# The same Results instance can receive another game's context while
		# the Catch encouragement is still playing.
		if _encouragement_started:
			_stop_low_score_encouragement()
		return
	if _encouragement_started:
		return
	if not ResourceLoader.exists(LOW_SCORE_CATCH_VOICE_PATH):
		return
	if not is_instance_valid(_low_score_voice):
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
		and not _is_two_player_catch(context) \
		and bool(context.get("round_completed", false)) \
		and context.has("score") and int(context["score"]) < LOW_SCORE_CATCH_THRESHOLD


static func _is_two_player_catch(context: Dictionary) -> bool:
	# The competitive board belongs only to Catch's shared-arena mode. A
	# stale multiplayer flag from a previous activity must not change other
	# games' original, single-player results artwork.
	return String(context.get("activity", "")) == "Catch the Word" \
		and (String(context.get("player_mode", "")).strip_edges().to_lower() == "multiplayer" \
		or bool(context.get("multiplayer", false)))


static func _competitive_score(value: Variant) -> int:
	# Incomplete/stale/invalid results must never invent a winner. Legitimate
	# Catch emits non-negative integer scores, not arbitrary formatted text.
	if not (value is int or value is float):
		return -1
	var measured := float(value)
	if not is_finite(measured) or measured < 0.0 or measured > 2147483647.0:
		return -1
	return int(measured)


static func competitive_winner(context: Dictionary) -> String:
	## Returns Player 1, Player 2, Tie, or Unavailable; never infers saving.
	if not _is_two_player_catch(context) or not bool(context.get("round_completed", false)):
		return "Unavailable"
	var p1 := _competitive_score(context.get("player1_score", context.get("score")))
	var p2 := _competitive_score(context.get("player2_score"))
	if p1 < 0 or p2 < 0:
		return "Unavailable"
	if p1 == p2:
		return "Tie"
	return "Player 1" if p1 > p2 else "Player 2"


func _exit_tree() -> void:
	_stop_low_score_encouragement()


func _stop_low_score_encouragement() -> void:
	if is_instance_valid(_low_score_voice):
		_low_score_voice.stop()
	_encouragement_started = false


func _refresh() -> void:
	var competitive := _is_two_player_catch(_context)
	_set_optional_row(%StudentIdRow, %StudentIdValue, ["student_id", "studentId", "id"])
	_set_optional_row(%StudentNameRow, %StudentNameValue, ["student_name", "name"])
	_set_optional_row(%GradeRow, %GradeValue, ["grade", "grade_section", "section"])
	%StudentCard.visible = not competitive and (%StudentIdRow.visible or %StudentNameRow.visible or %GradeRow.visible)
	_set_optional_row(%GameStyleRow, %GameStyleValue, ["game_style", "topic", "style"])
	_set_optional_row(%GameModeRow, %GameModeValue, ["game_mode", "mode"])
	_set_optional_row(%DifficultyRow, %DifficultyValue, ["difficulty"])
	%GameCard.visible = not competitive and (%GameStyleRow.visible or %GameModeRow.visible or %DifficultyRow.visible)
	var score := _context_text(["score", "points"], "")
	%ScoreCard.visible = not competitive and not score.is_empty()
	%ScoreValue.text = score
	var activity := _context_text(["activity"], "")
	# The selected minigame owns its illustrated game-over title. Unknown
	# activity values deliberately show no mislabeled banner.
	var catch_banner := activity == "Catch the Word"
	var balloon_banner := activity == "Balloon Popping"
	var plane_banner := activity == "Human Plane"
	%GameOverBannerCatch.visible = catch_banner
	%GameOverBannerBalloon.visible = balloon_banner
	%GameOverBannerPlane.visible = plane_banner
	%MultiplayerResults.visible = competitive
	if competitive:
		_refresh_competitive_results()


func _refresh_competitive_results() -> void:
	# Original ScoreCard represents only P1; never label that number as the
	# whole team's score. Both players receive independent score plaques.
	var p1_name := _context_text(["student_name", "name"], "Player 1")
	var p2_name := _context_text(["player2_student_name"], "Player 2")
	_set_competitive_text(%PlayerOneName, p1_name)
	_set_competitive_text(%PlayerTwoName, p2_name)
	_set_competitive_text(%PlayerOneId, _context_text(["student_id", "studentId", "id"], "Not provided"))
	_set_competitive_text(%PlayerTwoId, _context_text(["player2_student_id"], "Not provided"))
	_set_competitive_text(%PlayerOneGrade, _context_text(["grade_section", "grade", "section"], "Not provided"))
	_set_competitive_text(%PlayerTwoGrade, _context_text(["player2_grade_section"], "Not provided"))
	var p1_score := _competitive_score(_context.get("player1_score", _context.get("score")))
	var p2_score := _competitive_score(_context.get("player2_score"))
	%PlayerOneScore.text = str(p1_score) if p1_score >= 0 else "—"
	%PlayerTwoScore.text = str(p2_score) if p2_score >= 0 else "—"
	_set_competitive_text(%PlayerOneLives, _lives_label(_context.get("player1_lives", _context.get("lives"))))
	_set_competitive_text(%PlayerTwoLives, _lives_label(_context.get("player2_lives")))
	match competitive_winner(_context):
		"Player 1":
			%CompetitiveOutcome.text = "PLAYER 1 WINS!"
			%PlayerOneCard.modulate = Color(0.87, 1.0, 0.86)
			%PlayerTwoCard.modulate = Color.WHITE
		"Player 2":
			%CompetitiveOutcome.text = "PLAYER 2 WINS!"
			%PlayerOneCard.modulate = Color.WHITE
			%PlayerTwoCard.modulate = Color(0.87, 1.0, 0.86)
		"Tie":
			%CompetitiveOutcome.text = "IT'S A TIE!"
			%PlayerOneCard.modulate = Color.WHITE
			%PlayerTwoCard.modulate = Color.WHITE
		_:
			%CompetitiveOutcome.text = "ROUND NOT COMPLETED" if not bool(_context.get("round_completed", false)) else "RESULT NOT AVAILABLE"
			%PlayerOneCard.modulate = Color.WHITE
			%PlayerTwoCard.modulate = Color.WHITE
	# This field cannot report an unconditional DB success. In particular,
	# `score_saved` is P1's receipt, not proof that P2's independent score
	# made it to PostgreSQL. Only two explicit receipts permit that wording.
	if not bool(_context.get("round_completed", false)):
		%CompetitiveSaveNotice.text = "No completed round to save"
	elif bool(_context.get("player1_score_saved", false)) and bool(_context.get("player2_score_saved", false)):
		%CompetitiveSaveNotice.text = "Both scores confirmed saved"
	else:
		%CompetitiveSaveNotice.text = "Database saves not yet confirmed for both players"


func _lives_label(value: Variant) -> String:
	if value is int or value is float:
		var lives := float(value)
		if is_finite(lives) and lives >= 0.0 and lives <= 999.0:
			return "HEARTS: %d" % int(lives)
	return "HEARTS: —"


func _set_competitive_text(label: Label, value: String) -> void:
	label.text = value
	label.tooltip_text = value


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
