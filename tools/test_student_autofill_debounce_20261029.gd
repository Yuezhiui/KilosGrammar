extends SceneTree

const SCENE := "res://ui/student/setup/student_setup.tscn"
var checks := 0
var failures: Array[String] = []
var scene: Control
var signals: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	_check(packed != null, "new Student Setup scene parses")
	if packed == null:
		_finish()
		return
	scene = packed.instantiate() as Control
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	scene.student_autofill_requested.connect(func(field: String, value: String, token: int) -> void:
		signals.append({"field": field, "value": value, "token": token}))
	var sid := scene.get("_student_id_edit") as LineEdit
	var name_field := scene.get("_name_edit") as LineEdit
	var grade := scene.get("_grade_edit") as LineEdit
	var idle := scene.get("_autofill_timer") as Timer
	_check(sid != null and name_field != null and grade != null and idle != null,
		"all three real editor-authored LineEdits and timer bound")
	if sid == null or name_field == null or grade == null or idle == null:
		_finish()
		return
	_check(is_equal_approx(idle.wait_time, 2.5), "exact 2.5-second inactivity debounce")
	sid.text = "A"
	sid.text_changed.emit(sid.text)
	_check(idle.is_stopped(), "incomplete one-character input never searches")
	sid.text = "STU-OLD"
	sid.text_changed.emit(sid.text)
	_check(not idle.is_stopped(), "timer begins only after completed editing event")
	var stale_token: int = scene.get("_autofill_epoch")
	await create_timer(0.45).timeout
	_check(signals.is_empty(), "still typing/no idle timeout triggers no request")
	sid.text = "STU-42"
	sid.text_changed.emit(sid.text)
	_check(int(scene.get("_autofill_epoch")) > stale_token, "typing invalidates old epoch")
	await create_timer(2.1).timeout
	_check(signals.is_empty(), "old timer did not fire after latest keystroke")
	await create_timer(0.6).timeout
	_check(signals.size() == 1 and signals[0]["field"] == "id"
		and signals[0]["value"] == "STU-42", "one exact search occurs after 2.5-second idle")
	var new_token := int(signals[0]["token"])
	var old_profile := {"lookup_confirmed": true, "student_id": "STU-OLD",
		"student_name": "Old Student", "grade_section": "Grade 3"}
	_check(not bool(scene.call("apply_autofill_result", old_profile, "id", "STU-OLD", stale_token)),
		"out-of-order previous query is rejected")
	_check(name_field.text.is_empty() and grade.text.is_empty(), "rejected stale response leaves fields untouched")
	var exact := {"lookup_confirmed": true, "student_id": "STU-42",
		"student_name": "Luna Santos", "grade_section": "Grade 4 - Rose"}
	_check(bool(scene.call("apply_autofill_result", exact, "id", "STU-42", new_token)),
		"matching existing ID fills student data")
	_check(name_field.text == "Luna Santos" and grade.text == "Grade 4 - Rose",
		"existing student name and grade filled exactly")
	# Switch the verified name: the old student's ID and grade must be erased.
	name_field.text = "Marco Reyes"
	name_field.text_changed.emit(name_field.text)
	_check(sid.text.is_empty() and grade.text.is_empty(),
		"new full name clears old verified student identity safely")
	_check(not idle.is_stopped(), "complete full name schedules delayed lookup")
	scene.call("_autofill_if_unchanged")
	var name_request: Dictionary = signals.back()
	_check(name_request["field"] == "name" and name_request["value"] == "Marco Reyes",
		"full-name search uses exact normalized name, not prefix")
	var by_name := {"lookup_confirmed": true, "student_id": "STU-54",
		"student_name": "Marco Reyes", "grade_section": "Grade 5 - Ivy"}
	_check(bool(scene.call("apply_autofill_result", by_name, "name", "Marco Reyes", int(name_request["token"]))),
		"matching full name fills student ID and grade")
	_check(sid.text == "STU-54" and grade.text == "Grade 5 - Ivy",
		"reverse autofill fills both fields correctly")
	# Typing a different name must not let a delayed previously confirmed
	# response silently write the prior student's ID over the teacher's entry.
	name_field.text = "Unknown Student"
	name_field.text_changed.emit(name_field.text)
	_check(sid.text.is_empty() and grade.text.is_empty(),
		"unknown full name clears old verified ID and grade")
	_check(not bool(scene.call("apply_autofill_result", by_name, "name",
		"Marco Reyes", int(name_request["token"]))),
		"old verified callback rejected after teacher edits")
	_check(sid.text.is_empty() and grade.text.is_empty() \
		and name_field.text == "Unknown Student", "missing record never fills any profile")
	for locked in ["PrepositionButton", "ConjunctionButton", "InterjectionButton"]:
		var button := scene.find_child(locked, true, false) as Button
		_check(button == null, locked + " is intentionally removed, not focusable")
	var grid := scene.get_node_or_null("SetupStage/GameSetupCard/GameContent/GameStyleGrid") as Control
	_check(grid != null and grid.get_child_count() == 5,
		"exactly five surviving playable grammar topic controls")
	_check(scene.find_child("ExistingScoreDialog", true, false) == null,
		"retired ExistingScoreDialog no longer intercepts form input")
	_check(scene.get_node_or_null("SetupStage/StudentProfileCard/DatabasePanel") == null,
		"redundant lookup/status UI absent from new scene")
	scene.queue_free()
	await process_frame
	_finish()


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)


func _finish() -> void:
	print("STUDENT AUTOFILL DEBOUNCE: %s | checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for failure in failures:
		printerr("AUTOFILL FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)
