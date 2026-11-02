extends SceneTree

# Student-only QA. No database, camera, CSV writes or route side effects.
# Godot 4.7.2 --headless --path . --script res://tools/test_student_two_stage_multiplayer_20261102.gd
const SCENE := preload("res://ui/student/setup/student_setup.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("TWO-STAGE STUDENT QA FAILED: ", description)


func _edit(field: LineEdit, value: String) -> void:
	field.text = value
	field.text_changed.emit(value)


func _button(form: Control) -> Button:
	return form.get("_continue_button") as Button


func _art_matches(form: Control, green: bool) -> bool:
	var button := _button(form)
	return button.disabled != green \
		and (button.get_node("ButtonArtwork") as CanvasItem).visible == green \
		and (button.get_node("ContinueDisabledArtwork") as CanvasItem).visible != green


func _select(form: Control, group: String, value: String) -> void:
	var button := ((form.get(group) as Dictionary).get(value)) as Button
	_check(button != null, "selection exists " + group + "/" + value)
	if button != null:
		button.pressed.emit()


func _enter_profile(form: Control, sid: String, name: String, grade: String) -> void:
	_edit(form.get("_student_id_edit") as LineEdit, sid)
	_edit(form.get("_name_edit") as LineEdit, name)
	_edit(form.get("_grade_edit") as LineEdit, grade)


func _enter_p2(form: Control, sid: String, name: String, grade: String) -> void:
	_edit(form.get("_player_two_id_edit") as LineEdit, sid)
	_edit(form.get("_player_two_name_edit") as LineEdit, name)
	_edit(form.get("_player_two_grade_edit") as LineEdit, grade)


func _step(form: Control) -> void:
	_button(form).pressed.emit()


func _visible(form: Control, phase: String) -> bool:
	return String(form.get("_setup_phase")) == phase \
		and (form.get("_student_card") as Control).visible == (phase == "profile") \
		and (form.get("_game_card") as Control).visible == (phase == "game")


func _run_case(dims: Vector2i, player_mode: String, game_mode: String) -> void:
	root.size = dims
	root.content_scale_size = dims
	var form := SCENE.instantiate() as Control
	root.add_child(form)
	form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	form.set_context({"entry_source": "play", "database_connected": true})
	await process_frame
	var tag := "%s / %s / %s" % [dims, player_mode, game_mode]
	var expected_scale := minf(dims.x / 1280.0, dims.y / 720.0)
	var stage := form.get_node("SetupStage") as Control
	_check(stage.scale.is_equal_approx(Vector2.ONE * expected_scale), tag + " stage scales uniformly")
	_check(_visible(form, "profile"), tag + " profile alone is visible on opening")
	_check(_art_matches(form, false), tag + " gray Continue on empty profile")
	var selected: Array[Dictionary] = []
	form.requested.connect(func(target: String, payload: Dictionary) -> void:
		selected.append({"target": target, "payload": payload.duplicate(true)}))
	_enter_profile(form, "P1-%s-%s" % [dims.x, game_mode], "Maria Santos", "")
	_check(_art_matches(form, false), tag + " missing grade keeps Continue gray")
	_edit(form.get("_grade_edit") as LineEdit, "Grade 4 - Jade")
	_check(_art_matches(form, true), tag + " profile-only completion unlocks green Continue")
	_step(form)
	_check(_visible(form, "game"), tag + " profile Continue opens Game Setup, no route emitted")
	_check(selected.is_empty(), tag + " stage transition performs no registration or game dispatch")
	_check(_art_matches(form, false), tag + " selection stage begins with gray Continue")
	var p2_panel := form.get("_player_two_panel") as Panel
	_check(not p2_panel.visible, tag + " Player 2 fields initially hidden")
	form.call("_go_back")
	_check(_visible(form, "profile") and _art_matches(form, true),
		tag + " Back from Game Setup retains entered profile")
	_step(form)
	_check(_visible(form, "game"), tag + " repeat Continue reopens Game Setup")
	_select(form, "_style_buttons", "Noun")
	_select(form, "_mode_buttons", game_mode)
	_select(form, "_difficulty_buttons", "Easy")
	_check(_art_matches(form, false), tag + " player mode is a required explicit selection")
	_select(form, "_player_mode_buttons", player_mode)
	_check(p2_panel.visible == (player_mode == "Multiplayer"), tag + " Player 2 form matches selected mode")
	if player_mode == "Multiplayer":
		_check(_art_matches(form, false), tag + " multiplayer requires Player 2 profile")
		_enter_p2(form, "p1-%s-%s" % [dims.x, game_mode], "Someone Else", "Grade 5")
		_check(_art_matches(form, false) and String((form.get("_player_two_status") as Label).text).contains("DIFFERENT STUDENT ID"),
			tag + " duplicate case-insensitive Student ID blocked")
		_enter_p2(form, ".bad", "John Reyes", "Grade 5")
		_check(_art_matches(form, false) and String((form.get("_player_two_status") as Label).text).contains("MAX 64"),
			tag + " invalid Player 2 ID blocked with actionable guidance")
		_enter_p2(form, "P2-%s-%s" % [dims.x, game_mode], "John Reyes", "")
		_check(_art_matches(form, false), tag + " missing Player 2 grade stays blocked")
		_edit(form.get("_player_two_grade_edit") as LineEdit, "Grade 5 - Rose")
		_check(_art_matches(form, true), tag + " valid unique Player 2 unlocks Continue")
	else:
		_check(_art_matches(form, true), tag + " Single Player ready without Player 2")
	_step(form)
	_check(selected.size() == 1, tag + " final Continue dispatches exactly once")
	if selected.size() == 1:
		var payload: Dictionary = selected[0]["payload"]
		var route: String = selected[0]["target"]
		_check(payload.get("student_name") == "Maria Santos" and payload.get("game_style") == "Noun"
			and payload.get("difficulty") == "Easy" and payload.get("game_mode") == game_mode,
			tag + " Player 1 and game settings preserved")
		_check(payload.get("player_mode") == player_mode
			and int(payload.get("player_count", 0)) == (2 if player_mode == "Multiplayer" else 1),
			tag + " canonical multiplayer mode + player count")
		if player_mode == "Multiplayer":
			_check(route == "calibration" and payload.get("activity") == "Catch the Word"
				and bool(payload.get("camera_requested", false)),
				tag + " Multiplayer emits Catch calibration with camera request")
			_check(payload.get("player2_student_id") == "P2-%s-%s" % [dims.x, game_mode]
				and payload.get("player2_student_name") == "John Reyes"
				and payload.get("player2_grade_section") == "Grade 5 - Rose",
				tag + " explicit second student payload contract")
		else:
			_check(route == "play_activity" and not payload.has("player2_student_id")
				and not payload.has("player2_student_name") and not payload.has("player2_grade_section"),
				tag + " Single Player retains original chooser route and no second identity")
	form.queue_free()
	await process_frame


func _test_returning_student() -> void:
	root.size = SIZES[0]
	root.content_scale_size = SIZES[0]
	var form := SCENE.instantiate() as Control
	root.add_child(form)
	form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	form.set_context({"entry_source": "retry", "student_setup_prefill": true,
		"student_id": "OLD-203", "student_name": "Returning Learner",
		"grade_section": "Grade 6 - Pine", "student_lookup_connected": true,
		"game_style": "Verb", "game_mode": "Lives", "difficulty": "Hard",
		"player_mode": "Single Player"})
	await process_frame
	_check(_visible(form, "profile"), "retry opens Profile page before Game Setup")
	_check((form.get("_student_id_edit") as LineEdit).text == "OLD-203"
		and (form.get("_name_edit") as LineEdit).text == "Returning Learner"
		and _art_matches(form, true), "returning student's server-confirmed profile prefilled correctly")
	_step(form)
	_check(_visible(form, "game") and _art_matches(form, true),
		"retry preserves previously selected game options and Player Mode")
	var outputs: Array[Dictionary] = []
	form.requested.connect(func(target: String, data: Dictionary) -> void:
		outputs.append({"route": target, "payload": data.duplicate(true)}))
	_step(form)
	_check(outputs.size() == 1 and outputs[0]["route"] == "play_activity"
		and bool((outputs[0]["payload"] as Dictionary).get("student_lookup_connected", false)),
		"returning confirmed learner uses verified single-player route")
	form.set_context({"entry_source": "play", "student_setup_prefill": false,
		"student_id": "LEAK", "student_name": "Old", "grade_section": "Grade 2",
		"player_mode": "Multiplayer", "player2_student_id": "LEAK-2"})
	_check(_visible(form, "profile") and _art_matches(form, false)
		and (form.get("_student_id_edit") as LineEdit).text.is_empty()
		and (form.get("_player_two_id_edit") as LineEdit).text.is_empty()
		and String(form.get("_selected_player_mode")).is_empty(),
		"fresh Play clears previous P1/P2 identity, mode, and options")
	form.queue_free()
	await process_frame


func _test_guided_activity_limits() -> void:
	root.size = SIZES[0]
	root.content_scale_size = SIZES[0]
	var form := SCENE.instantiate() as Control
	root.add_child(form)
	form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	form.set_context({"guided_tutorial": true, "activity": "Human Plane"})
	await process_frame
	_enter_profile(form, "GUIDED-01", "Guided Student", "Grade 4")
	_step(form)
	_select(form, "_style_buttons", "Adjective")
	_select(form, "_mode_buttons", "Seconds")
	_select(form, "_difficulty_buttons", "Easy")
	_select(form, "_player_mode_buttons", "Multiplayer")
	_enter_p2(form, "GUIDED-02", "Second Guided", "Grade 5")
	_check(_art_matches(form, false)
		and (form.get("_player_two_status") as Label).text == "MULTIPLAYER IS AVAILABLE ONLY IN CATCH THE WORD",
		"non-Catch guided tutorial clearly blocks Multiplayer before calibration")
	var routed: Array[String] = []
	form.requested.connect(func(target: String, _payload: Dictionary) -> void: routed.append(target))
	_step(form)
	_check(routed.is_empty(), "unsupported multiplayer activity never emits calibration")
	_select(form, "_player_mode_buttons", "Single Player")
	_check(_art_matches(form, true), "Single Player remains available for other guided activities")
	_step(form)
	_check(routed == ["calibration"], "single-player guided tutorial preserves original calibration route")
	form.queue_free()
	await process_frame


func _run() -> void:
	for dims in SIZES:
		for player_mode in ["Single Player", "Multiplayer"]:
			for game_mode in ["Seconds", "Lives"]:
				await _run_case(dims, player_mode, game_mode)
	await _test_returning_student()
	await _test_guided_activity_limits()
	print("STUDENT TWO-STAGE MULTIPLAYER: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
