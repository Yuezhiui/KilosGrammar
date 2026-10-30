extends SceneTree

# No API, PostgreSQL, recovery queue, CSV or camera. This exercises real
# Student Setup fields, not a mock UI, in both modes and native screen sizes.
const SCENE := preload("res://ui/student/setup/student_setup.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const MODES := ["Seconds", "Lives"]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, details: String) -> void:
	checks += 1
	if not ok:
		failures.append(details)
		printerr("STUDENT MANUAL QA FAILED: ", details)


func _edit(field: LineEdit, value: String) -> void:
	field.text = value
	field.text_changed.emit(value)


func _select(form: Control, group: String, value: String) -> void:
	((form.get(group) as Dictionary)[value] as Button).pressed.emit()


func _is_green(form: Control) -> bool:
	var button := form.get("_continue_button") as Button
	var green := button.get_node("ButtonArtwork") as CanvasItem
	var grey := button.get_node("ContinueDisabledArtwork") as CanvasItem
	return not button.disabled and green.visible and not grey.visible


func _is_grey(form: Control) -> bool:
	var button := form.get("_continue_button") as Button
	var green := button.get_node("ButtonArtwork") as CanvasItem
	var grey := button.get_node("ContinueDisabledArtwork") as CanvasItem
	return button.disabled and not green.visible and grey.visible


func _run_case(dims: Vector2i, mode: String) -> void:
	root.size = dims
	root.content_scale_size = dims
	await process_frame
	var form := SCENE.instantiate() as Control
	var authored := form.get_node("SetupStage/StudentProfileCard/StudentIdGroup/StudentIdEdit") as LineEdit
	var original_position := authored.position
	var original_size := authored.size
	root.add_child(form)
	form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	form.set_context({"entry_source": "play", "database_connected": true})
	for frame in range(3):
		await process_frame
	var tag := "%s %s" % [dims, mode]
	var factor := minf(float(dims.x) / 1280.0, float(dims.y) / 720.0)
	var stage := form.get_node("SetupStage") as Control
	_check(stage.scale.is_equal_approx(Vector2.ONE * factor)
		and authored.position == original_position and authored.size == original_size,
		tag + " original editor-authored geometry untouched")
	var student_id := form.get("_student_id_edit") as LineEdit
	var student_name := form.get("_name_edit") as LineEdit
	var grade := form.get("_grade_edit") as LineEdit
	var validation := form.get("_validation_label") as Label
	var routes: Array[Dictionary] = []
	form.requested.connect(func(route: String, payload: Dictionary) -> void:
		routes.append({"route":route, "data":payload.duplicate(true)}))
	_edit(student_id, "UNSEEN-" + str(dims.x) + "-" + mode)
	_edit(student_name, "Avery")
	_edit(grade, "Grade 4 - Jade")
	_select(form, "_style_buttons", "Noun")
	_select(form, "_mode_buttons", mode)
	_select(form, "_difficulty_buttons", "Easy")
	_check(_is_green(form), tag + " unseen manual student enables Continue without CSV")
	for valid_id in ["123", "AbC001", "S-5._2", "a" + "B".repeat(63)]:
		_edit(student_id, valid_id)
		_edit(student_name, "Avery")
		_edit(grade, "Grade 4 - Jade")
		_check(_is_green(form), tag + " backend-compatible ID accepted: " + valid_id.left(12))
	for invalid_id in [".123", "_123", "-123", "has spaces", "a/b", "ñ123", "A".repeat(65), "A\tB"]:
		_edit(student_id, invalid_id)
		_edit(student_name, "Avery")
		_edit(grade, "Grade 4 - Jade")
		_check(_is_grey(form) and validation.visible
			and validation.text == "STUDENT ID: USE LETTERS, NUMBERS, . _ - (MAX 64)",
			tag + " invalid ID gives actionable validation: " + invalid_id.left(12))
	_edit(student_id, "UNSEEN-" + str(dims.x) + "-" + mode)
	_edit(student_name, "Avery")
	_edit(grade, "Grade 4 - Jade")
	_check(_is_green(form), tag + " restoring valid ID returns enabled Continue")
	form.show_database_status("CHECKING STUDENT ID • Please keep this screen open.", true)
	_check(_is_grey(form) and validation.visible and validation.text == "CHECKING STUDENT ID...",
		tag + " during read-only identity check Continue pauses visibly")
	form.show_database_status("STUDENT ID NOT FOUND • Enter name and grade, then Continue to register.", true)
	_check(_is_green(form) and not validation.visible and String(form.get("_registration_error")).is_empty(),
		tag + " missing ID is new candidate, not a failed check")
	# An explicit NOT_FOUND supplied via the registration-status entry point
	# must also release a prior transient error, never a genuine ID conflict.
	form.show_registration_error("STUDENT ID CHECK FAILED • CHECK STUDENT DETAILS")
	_check(_is_grey(form), tag + " transient error is shown without guessing identity")
	form.show_registration_error("STUDENT ID NOT FOUND")
	_check(_is_green(form), tag + " later confirmed missing ID clears transient error")
	form.call("_continue")
	_check(routes.size() == 1 and String(routes[0]["route"]) == "play_activity",
		tag + " new student proceeds to activity selection exactly once")
	if not routes.is_empty():
		var data: Dictionary = routes[0]["data"]
		_check(String(data.get("student_id", "")) == student_id.text
			and String(data.get("student_name", "")) == "Avery"
			and String(data.get("grade_section", "")) == "Grade 4 - Jade"
			and String(data.get("game_mode", "")) == mode
			and not bool(data.get("student_lookup_connected", true)),
			tag + " new ID carries manual fields as unverified, ready for read-only router check")
	routes.clear()
	form.show_registration_error("PLEASE CHECK STUDENT ID AND NAME")
	_check(_is_grey(form) and validation.text == "CHECK STUDENT ID AND NAME",
		tag + " existing record conflict remains held")
	form.show_database_status("STUDENT ID NOT FOUND • New learner", true)
	_check(_is_grey(form), tag + " unrelated not-found status cannot bypass known identity conflict")
	form.show_registration_error("STUDENT ID NOT FOUND")
	_check(_is_grey(form), tag + " new-ID status cannot erase confirmed conflict")
	form.call("_continue")
	_check(routes.is_empty(), tag + " conflict never navigates")
	_edit(student_id, "RETURN-" + str(dims.x) + "-" + mode)
	_edit(student_name, "Maria Santos")
	_edit(grade, "Grade 5 - Rose")
	_check(_is_green(form), tag + " correcting conflicted ID restores green Continue")
	form.call("_schedule_autofill", "id", student_id.text)
	var epoch := int(form.get("_autofill_epoch"))
	var server_profile := {"student_id":student_id.text, "student_name":"Maria Santos",
		"grade_section":"Grade 5 - Rose", "lookup_confirmed":true}
	_check(bool(form.apply_autofill_result(server_profile, "id", student_id.text, epoch)),
		tag + " returning profile is accepted only after exact confirmed lookup")
	form.call("_continue")
	_check(routes.size() == 1 and bool((routes[0]["data"] as Dictionary).get("student_lookup_connected", false)),
		tag + " returning profile is marked verified, unlike fresh manual ID")
	_edit(student_name, "Different Child")
	_check(student_id.text.is_empty() and grade.text.is_empty() and _is_grey(form),
		tag + " verified ID/grade erased if teacher changes registered full name")
	form.queue_free()
	await process_frame


func _run() -> void:
	for dims in SIZES:
		for mode in MODES:
			await _run_case(dims, mode)
	print("STUDENT NEW MANUAL + RETURNING REGISTRATION: %s checks=%d failures=%d renderer=%s" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(), DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)
