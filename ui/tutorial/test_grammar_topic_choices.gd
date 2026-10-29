extends SceneTree

# Five grammar topics are playable in Guide/teacher choice/Student Setup.
# Student Setup now has ONLY five playable topics; the three retired SOON
# placeholders were explicitly deleted without touching the five survivors.
const GUIDE := preload("res://ui/tutorial/grammar_guide/grammar_guide.tscn")
const TOPIC := preload("res://ui/play/topic/play_topic.tscn")
const STUDENT := preload("res://ui/student/setup/student_setup.tscn")
const EXPECTED := ["NOUN", "PRONOUN", "VERB", "ADJECTIVE", "ADVERB"]
const RETIRED := ["PREPOSITION", "CONJUNCTION", "INTERJECTION"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport in [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport
		root.content_scale_size = viewport
		var guide := GUIDE.instantiate() as Control
		root.add_child(guide)
		guide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		var cards := guide.get_node_or_null("TutorialStage/GrammarCardScroll/GridContainer") as GridContainer
		if cards == null:
			_check(false, "grammar guide authored scroll/grid retained at %s" % viewport)
			guide.queue_free()
			await process_frame
			continue
		_check(cards.get_child_count() == 5, "grammar guide has five cards at %s" % viewport)
		var guide_labels: Array[String] = []
		_collect_labels(cards, guide_labels)
		for topic in EXPECTED:
			_check(topic in guide_labels, "grammar guide shows %s at %s" % [topic, viewport])
			var topic_card := cards.get_node_or_null(topic.capitalize() + "Card") as Control
			# The simplified five-topic guide intentionally removed the
			# redundant large colored backing panels. Its original individual
			# topic badges, heading and learning text remain editor-authored.
			_check(topic_card != null
				and topic_card.get_node_or_null("TopicName") is Label
				and topic_card.get_node_or_null("TopicBadge") is TextureRect
				and topic_card.get_node_or_null("Meaning") is Label
				and topic_card.get_node_or_null("Examples") is Label,
				"grammar guide has editable %s badge and teaching copy" % topic)
		for retired in RETIRED:
			_check(retired not in guide_labels, "grammar guide hides %s at %s" % [retired, viewport])
			_check(guide.get_node_or_null("TutorialStage/Description") == null,
				"redundant Explore Grammar subtitle has been physically removed")
		guide.queue_free()
		await process_frame

		var student := STUDENT.instantiate() as Control
		root.add_child(student)
		student.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		var styles := student.get_node_or_null("SetupStage/GameSetupCard/GameContent/GameStyleGrid") as Control
		if styles == null:
			_check(false, "student setup contains authored SetupStage/GameStyleGrid")
			student.queue_free()
			await process_frame
			continue
		_check(styles.get_child_count() == 5,
			"student setup keeps only the five selectable, editor-authored choices at %s" % viewport)
		for topic in EXPECTED:
			var active := styles.get_node_or_null(topic.capitalize() + "Button") as Button
			_check(active != null and not active.disabled,
				"student setup has enabled %s button" % topic)
			_check(active != null and active.get_node_or_null("ButtonArtwork") is TextureRect,
				"student setup exposes editable PNG on enabled %s button" % topic)
		for retired in RETIRED:
			_check(styles.get_node_or_null(retired.capitalize() + "Button") == null,
				"student setup no longer contains retired %s button" % retired)
		_check(student.find_child("ExistingScoreDialog", true, false) == null,
			"student setup's retired ExistingScoreDialog is absent")
		student.queue_free()
		await process_frame

		var topic_screen := TOPIC.instantiate() as Control
		root.add_child(topic_screen)
		topic_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		var topic_buttons: Dictionary = topic_screen.get("topic_buttons")
		_check(topic_buttons.size() == 5, "teacher topic step has five choices at %s" % viewport)
		for topic in EXPECTED:
			_check(topic.capitalize() in topic_buttons, "teacher topic step shows %s" % topic)
		for retired in RETIRED:
			_check(retired.capitalize() not in topic_buttons, "teacher topic step hides %s" % retired)
		var all_buttons: Array[Button] = []
		_collect_buttons(topic_screen, all_buttons)
		for button in all_buttons:
			_check(not button.text.contains("SOON"), "topic step has no disabled placeholder")
		topic_screen.queue_free()
		await process_frame

	if failures.is_empty():
		print("PASS grammar topic choices: %d checks across three screens and three viewport sizes" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL grammar topic choices: %d failures / %d checks" % [failures.size(), checks])
		quit(1)


func _collect_labels(node: Node, texts: Array[String]) -> void:
	if node is Label:
		texts.append((node as Label).text)
	for child in node.get_children():
		_collect_labels(child, texts)


func _collect_buttons(node: Node, buttons: Array[Button]) -> void:
	if node is Button:
		buttons.append(node)
	for child in node.get_children():
		_collect_buttons(child, buttons)


func _check(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures.append(detail)
