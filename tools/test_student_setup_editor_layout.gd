extends SceneTree

# Run: Godot --headless --path . --script res://tools/test_student_setup_editor_layout.gd
# The authoring check happens BEFORE _ready(): nodes added from GDScript are
# never mistaken for editable nodes saved in student_setup.tscn.
const SCENE_PATH := "res://ui/student/setup/student_setup.tscn"
const REQUIRED_FIELDS := {
	"_student_id_edit": "Student ID",
	"_name_edit": "Student Name",
	"_grade_edit": "Grade & Section",
}
const REQUIRED_ACTIONS := {
	"_back_button": "Back",
	"_continue_button": "Continue",
}
const REQUIRED_CHOICES := {
	"_style_buttons": ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"],
	"_mode_buttons": ["Seconds", "Lives"],
	"_difficulty_buttons": ["Easy", "Normal", "Hard"],
}

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load(SCENE_PATH) as PackedScene
	_check(packed != null, "Student Setup scene is loadable")
	if packed == null:
		_done()
		return
	await _check_flow(packed, false)
	await _check_flow(packed, true)
	_done()


func _check_flow(packed: PackedScene, guided: bool) -> void:
	var label := "Guided" if guided else "Ordinary"
	var panel := packed.instantiate() as Control
	_check(panel != null, label + " scene instantiates a Control root")
	if panel == null:
		return

	# Capture exactly the nodes serialized into the PackedScene, before _ready().
	# Also require owner == panel so each required widget is editable in the
	# Student Setup scene itself, even if it is nested inside containers.
	var authored_ids := {}
	var authored_controls: Array[Control] = []
	_collect_authored(panel, panel, authored_ids, authored_controls)
	var authored_inputs := 0
	var authored_buttons := 0
	var textured_art: Array[TextureRect] = []
	for control in authored_controls:
		if control is LineEdit:
			authored_inputs += 1
		if control is Button:
			authored_buttons += 1
		if control is TextureRect and (control as TextureRect).texture != null:
			textured_art.append(control as TextureRect)
	_check(authored_inputs >= 3, label + " ID/name/grade fields must exist in .tscn before _ready")
	_check(authored_buttons >= 12, label + " five topics, two modes, three difficulties and two navigation buttons are editor-authored")
	_check(textured_art.size() >= 3, label + " decorative PNGs must be inspectable TextureRects in .tscn")
	for art in textured_art:
		var inspectable_width := art.size.x > 0.0 or art.custom_minimum_size.x > 0.0 or art.anchor_right > art.anchor_left
		var inspectable_height := art.size.y > 0.0 or art.custom_minimum_size.y > 0.0 or art.anchor_bottom > art.anchor_top
		_check(inspectable_width and inspectable_height, label + " artwork '" + art.name + "' has editable placement/size")

	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.set_context({"guided_tutorial": guided, "activity": "Catch the Word"} if guided else {})
	await process_frame
	await process_frame
	var runtime_controls: Array[Control] = []
	_collect_runtime_ui(panel, runtime_controls)
	var ghost_count := 0
	for control in runtime_controls:
		if control is LineEdit or control is Button or control is TextureRect:
			if not authored_ids.has(control.get_instance_id()):
				ghost_count += 1
				_fail(label + " runtime-created ghost " + control.get_class() + ": " + str(panel.get_path_to(control)))
	_check(ghost_count == 0, label + " form/button/artwork controls are all scene-authored")

	for property in REQUIRED_FIELDS:
		var field := panel.get(property) as LineEdit
		_check(field != null, label + " " + String(REQUIRED_FIELDS[property]) + " field is bound")
		if field == null:
			continue
		_check(authored_ids.has(field.get_instance_id()), label + " " + String(REQUIRED_FIELDS[property]) + " uses saved .tscn node")
		_check(field.owner == panel, label + " " + String(REQUIRED_FIELDS[property]) + " is directly editable in Student Setup")
		_check(field.max_length > 0, label + " " + String(REQUIRED_FIELDS[property]) + " has inspector-editable input limit")
		_check(not field.placeholder_text.is_empty(), label + " " + String(REQUIRED_FIELDS[property]) + " has a placeholder")

	for property in REQUIRED_ACTIONS:
		var button := panel.get(property) as Button
		_check(button != null, label + " " + String(REQUIRED_ACTIONS[property]) + " action exists")
		if button != null:
			_check(authored_ids.has(button.get_instance_id()) and button.owner == panel, label + " " + String(REQUIRED_ACTIONS[property]) + " action is drag-editable")

	for dictionary_property in REQUIRED_CHOICES:
		var choices := panel.get(dictionary_property) as Dictionary
		for option in REQUIRED_CHOICES[dictionary_property]:
			var button := choices.get(option) as Button
			_check(button != null, label + " teacher choice " + String(option) + " exists")
			if button != null:
				_check(authored_ids.has(button.get_instance_id()) and button.owner == panel, label + " teacher choice " + String(option) + " is drag-editable")
				_check(button.toggle_mode, label + " teacher choice " + String(option) + " is a native toggle")

	var student_card := panel.get("_student_card") as Control
	var game_card := panel.get("_game_card") as Control
	_check(student_card != null and authored_ids.has(student_card.get_instance_id()), label + " Student Profile panel is scene-authored")
	_check(game_card != null and authored_ids.has(game_card.get_instance_id()), label + " Game Setup panel is scene-authored")
	var stage := panel.get_node_or_null("SetupStage") as Control
	_check(stage != null and authored_ids.has(stage.get_instance_id())
		and stage.size.is_equal_approx(Vector2(1280, 720)),
		label + " teacher-edited SetupStage remains an authored 1280x720 stage")
	var style_grid := panel.get_node_or_null("SetupStage/GameSetupCard/GameContent/GameStyleGrid") as Control
	_check(style_grid != null and style_grid.get_child_count() == 5,
		label + " only five authored grammar topic buttons survive")
	for removed in ["PrepositionButton", "ConjunctionButton", "InterjectionButton"]:
		_check(panel.find_child(removed, true, false) == null,
			label + " no retired " + removed)
	_check(panel.find_child("ExistingScoreDialog", true, false) == null,
		label + " no removed ExistingScoreDialog modal")

	var requested: Array[Dictionary] = []
	panel.requested.connect(func(route: String, payload: Dictionary) -> void:
		requested.append({"route": route, "payload": payload.duplicate(true)})
	)
	var continue_button := panel.get("_continue_button") as Button
	if continue_button != null:
		_check(continue_button.disabled, label + " Continue initially requires completed form")
	panel.call("_go_back")
	_check(requested.size() == 1 and String(requested[0]["route"]) == ("play_activity" if guided else "main"), label + " Back preserves original route")
	requested.clear()

	var id_edit := panel.get("_student_id_edit") as LineEdit
	var name_edit := panel.get("_name_edit") as LineEdit
	var grade_edit := panel.get("_grade_edit") as LineEdit
	if id_edit != null and name_edit != null and grade_edit != null:
		id_edit.text = "QA-GUIDED" if guided else "QA-PLAY"
		name_edit.text = "Editor QA Student"
		grade_edit.text = "Grade 2 Apple"
		panel.call("_select_style", "Noun")
		panel.call("_select_mode", "Lives" if guided else "Seconds")
		panel.call("_select_difficulty", "Hard" if guided else "Easy")
		panel.call("_continue")
		var expected_route := "calibration" if guided else "play_activity"
		_check(requested.size() == 1 and String(requested[0]["route"]) == expected_route, label + " Continue routes to " + expected_route)
		if requested.size() == 1:
			var payload: Dictionary = requested[0]["payload"]
			_check(String(payload.get("student_id", "")) == id_edit.text, label + " student ID survives Continue")
			_check(String(payload.get("student_name", "")) == name_edit.text, label + " student name survives Continue")
			_check(String(payload.get("grade_section", "")) == grade_edit.text, label + " grade survives Continue")
			_check(String(payload.get("game_style", "")) == "Noun", label + " style survives Continue")
			_check(String(payload.get("game_mode", "")) == ("Lives" if guided else "Seconds"), label + " mode survives Continue")
			_check(String(payload.get("difficulty", "")) == ("Hard" if guided else "Easy"), label + " difficulty survives Continue")
			_check(bool(payload.get("guided_tutorial", false)) == guided, label + " guided flag is preserved")
			if guided:
				_check(bool(payload.get("camera_requested", false)), label + " guided route requests camera preparation")
				_check(String(payload.get("activity", "")) == "Catch the Word", label + " selected game survives teacher setup")
			else:
				_check(String(payload.get("entry_source", "")) == "play", label + " ordinary route remains Play")
	panel.queue_free()
	await process_frame
	await process_frame
	print("Student Setup ", label, " authored: ", authored_inputs, " inputs, ", authored_buttons, " buttons, ", textured_art.size(), " textured assets")


func _collect_authored(node: Node, scene_root: Control, ids: Dictionary, controls: Array[Control]) -> void:
	for child in node.get_children():
		if child.owner == scene_root:
			ids[child.get_instance_id()] = true
			if child is Control:
				controls.append(child as Control)
		_collect_authored(child, scene_root, ids, controls)


func _collect_runtime_ui(node: Node, controls: Array[Control]) -> void:
	for child in node.get_children():
		if child is Control:
			controls.append(child as Control)
		_collect_runtime_ui(child, controls)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		_fail(message)


func _fail(message: String) -> void:
	failures.append(message)
	printerr("FAIL student setup editor: ", message)


func _done() -> void:
	print("STUDENT SETUP EDITOR QA: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks, ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
