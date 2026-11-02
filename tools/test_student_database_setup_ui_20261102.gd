extends SceneTree

## No PostgreSQL, HTTP, PowerShell or credentials: test the standalone UI.
## Run with Godot --headless --path . --script res://tools/test_student_database_setup_ui_20261102.gd
const SCENE := preload("res://ui/student/setup/student_setup.tscn")
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const AUTHORED_SETUP_RECT := Rect2(945, 546, 263, 38)
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _run() -> void:
	for viewport in VIEWPORTS:
		await _test_viewport(viewport)
	for failure in failures:
		printerr("STUDENT DATABASE SETUP UI FAIL: ", failure)
	print("STUDENT DATABASE SETUP UI: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _test_viewport(viewport: Vector2i) -> void:
	root.size = viewport
	root.content_scale_size = viewport
	var form := SCENE.instantiate() as Control
	root.add_child(form)
	form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	var key := str(viewport)
	var stage := form.get_node("SetupStage") as Control
	var profile := form.get_node("SetupStage/StudentProfileCard") as Control
	var button := profile.get_node("DatabaseSetupButton") as Button
	var status := profile.get_node("ProfileStatus") as Label
	var back := form.get_node("SetupStage/SetupActions/BackButton") as Button
	var next := form.get_node("SetupStage/SetupActions/ContinueButton") as Button
	var id := profile.get_node("StudentIdGroup/StudentIdEdit") as LineEdit
	var name_edit := profile.get_node("StudentNameGroup/StudentNameEdit") as LineEdit
	var grade := profile.get_node("GradeSectionGroup/GradeSectionEdit") as LineEdit
	var count := [0]
	form.database_setup_requested.connect(func() -> void: count[0] += 1)

	_check(form.has_signal("database_setup_requested"), key + " exposes existing MainMenu setup signal")
	_check(button != null and button.text == "SET UP LOCAL DATABASE", key + " has single authored setup control")
	_check(not button.visible and not button.is_visible_in_tree(), key + " setup hidden by default")
	_check(profile.visible and String(form.get("_setup_phase")) == "profile", key + " opens Student Profile")
	_check(button.position == AUTHORED_SETUP_RECT.position and button.size == AUTHORED_SETUP_RECT.size,
		key + " retains editor-authored setup button rectangle")
	_check(button.position.x >= status.position.x + status.size.x and button.position.y >= grade.position.y,
		key + " setup action does not overlap profile feedback")
	_check(back.position == Vector2.ZERO and back.size == Vector2(278, 85)
		and next.position == Vector2(302, 0)
		and next.size == Vector2(278, 85), key + " original Back/Continue geometry remains")
	_check(next.disabled, key + " Continue remains gray while required fields are blank")
	var factor := minf(float(viewport.x) / 1280.0, float(viewport.y) / 720.0)
	var actual := button.get_global_rect()
	var expected := Rect2(stage.global_position + AUTHORED_SETUP_RECT.position * factor, AUTHORED_SETUP_RECT.size * factor)
	_check(actual.position.distance_to(expected.position) < 1.0 and actual.size.distance_to(expected.size) < 1.0,
		key + " authored setup hitbox scales with stage")

	button.pressed.emit()
	_check(count[0] == 0, key + " hidden button cannot request setup")
	form.show_database_status("LOCAL POSTGRESQL OFFLINE", false, false)
	_check(not button.visible, key + " ordinary offline status does not show teacher setup")
	form.show_database_status("LOCAL POSTGRESQL NEEDS SETUP", false, true)
	_check(button.visible and button.is_visible_in_tree(), key + " setup-required offline shows action")
	_check(count[0] == 0, key + " status alone never launches setup")
	button.pressed.emit()
	_check(count[0] == 1, key + " explicit click emits exactly one setup request")
	form.show_database_status("LOCAL POSTGRESQL CONNECTED", true, true)
	_check(not button.visible, key + " connected state hides setup even with stale setup_required")
	button.pressed.emit()
	_check(count[0] == 1, key + " connected state cannot dispatch setup")
	form.show_database_status("LOCAL POSTGRESQL OFFLINE", false, true)
	_check(button.visible, key + " fresh setup-required status restores setup action")

	id.text = "TEST-STUDENT-01"
	name_edit.text = "QA Test Student"
	grade.text = "Grade 2 - Ruby"
	form.call("_update_validation")
	_check(not next.disabled, key + " valid identity still enables Continue")
	form.call("_continue")
	_check(String(form.get("_setup_phase")) == "game" and not profile.visible,
		key + " valid Continue navigates to unchanged Game Setup")
	_check(not button.visible and not button.is_visible_in_tree(),
		key + " Game Setup phase hides setup button")
	button.pressed.emit()
	_check(count[0] == 1, key + " Game Setup phase cannot dispatch setup")
	form.call("_go_back")
	_check(String(form.get("_setup_phase")) == "profile" and button.visible,
		key + " returning to still-offline profile restores setup action")
	form.set_context({"student_setup_prefill": false, "database_connected": false})
	_check(not button.visible and String(form.get("_setup_phase")) == "profile",
		key + " fresh context cannot inherit stale setup-required action")
	_check(count[0] == 1, key + " all navigation/status changes are non-launching")
	form.queue_free()
	await process_frame
