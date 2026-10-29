extends SceneTree

# Independent final QA. No production changes, no real DB or webcam required.
# Headless functional:
#   Godot --headless --path . --script res://tools/test_student_setup_final_20261029.gd
# Native render captures:
#   Godot --path . --rendering-method gl_compatibility \
#      --script res://tools/test_student_setup_final_20261029.gd -- --capture
const SETUP := "res://ui/student/setup/student_setup.tscn"
const IMAGE_DIR := "res://showcase/student_setup_final_20261029"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const REAL_WAIT := 2.75
var checks := 0
var failures: Array[String] = []


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
		printerr("QA FAIL: ", reason)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SETUP) as PackedScene
	_check(packed != null, "student setup scene loads")
	if packed == null:
		_finish()
		return
	await _test_live_id_and_name_autofill(packed)
	await _test_navigation_and_controls(packed, false)
	await _test_navigation_and_controls(packed, true)
	if OS.get_cmdline_user_args().has("--capture"):
		if DisplayServer.get_name() == "headless":
			_check(false, "native capture requires graphical rendering")
		else:
			await _capture_three_viewports(packed)
	_finish()


func _make_form(packed: PackedScene, guided: bool = false) -> Control:
	var form := packed.instantiate() as Control
	root.add_child(form)
	form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	form.set_context({"guided_tutorial": true, "activity": "Catch the Word"} if guided else {"entry_source": "play"})
	return form


func _edit(field: LineEdit, value: String) -> void:
	# Simulate actual text_changed emitted by the native LineEdit when typing.
	field.text = value
	field.text_changed.emit(value)


func _test_live_id_and_name_autofill(packed: PackedScene) -> void:
	var form := _make_form(packed)
	await process_frame
	var student_id := form.get("_student_id_edit") as LineEdit
	var student_name := form.get("_name_edit") as LineEdit
	var grade := form.get("_grade_edit") as LineEdit
	var next := form.get("_continue_button") as Button
	_check(student_id != null and student_name != null and grade != null and next != null,
		"all named form controls are bound")
	if student_id == null or student_name == null or grade == null or next == null:
		form.queue_free()
		await process_frame
		return
	var emitted: Array[Dictionary] = []
	form.student_autofill_requested.connect(func(field: String, value: String, epoch: int) -> void:
		emitted.append({"field": field, "value": value, "epoch": epoch}))
	_check(is_equal_approx(float(form.get_script().get_script_constant_map().get("AUTOFILL_IDLE_SECONDS", 0)), 2.5),
		"actual idle debounce constant is 2.5 seconds")
	_check(next.disabled, "initially disabled Continue")

	# ID starts a real 2.5-second one-shot timer; typing again restarts it.
	_edit(student_id, "KG-00")
	await create_timer(1.10).timeout
	_check(emitted.is_empty(), "ID does not fire while typing (1.10 s)")
	_edit(student_id, "KG-001")
	await create_timer(1.55).timeout
	_check(emitted.is_empty(), "old ID timeout did not fire at 2.65 s from first key")
	await create_timer(1.22).timeout
	_check(emitted.size() == 1, "one ID lookup after 2.5 s of silence")
	var id_event: Dictionary = emitted[0] if not emitted.is_empty() else {}
	_check(id_event.get("field", "") == "id" and id_event.get("value", "") == "KG-001",
		"ID event sends exact edited ID")
	var id_epoch := int(id_event.get("epoch", -1))
	var valid_id := {"lookup_confirmed": true, "student_id": "KG-001",
		"student_name": "Maria Santos", "grade_section": "Grade 3 Jade"}
	_check(not bool(form.apply_autofill_result({}, "id", "KG-001", id_epoch)),
		"None/empty lookup response never fills student")
	_check(not bool(form.apply_autofill_result(
		{"student_id": "KG-001", "student_name": "Maria Santos", "grade_section": "Grade 3 Jade"},
		"id", "KG-001", id_epoch)), "unconfirmed response rejected")
	_check(not bool(form.apply_autofill_result(
		{"lookup_confirmed": true, "student_id": "KG-999",
		"student_name": "Maria Santos", "grade_section": "Grade 3 Jade"},
		"id", "KG-001", id_epoch)), "mismatched returned student ID rejected")
	_check(student_name.text.is_empty() and grade.text.is_empty(),
		"rejected ID results leave teacher's other fields blank")

	_edit(student_name, "Another Student")
	_check(not bool(form.apply_autofill_result(valid_id, "id", "KG-001", id_epoch)),
		"ID match cannot overwrite a manually conflicting full name")
	_edit(student_name, "")
	# Name edit invalidates prior ID query, so the old packet is now stale.
	_check(not bool(form.apply_autofill_result(valid_id, "id", "KG-001", id_epoch)),
		"late ID response rejected after teacher edits another field")
	_edit(student_id, "KG-001")
	await create_timer(REAL_WAIT).timeout
	var latest_id_epoch := int(form.get("_autofill_epoch"))
	_check(bool(form.apply_autofill_result(valid_id, "id", "KG-001", latest_id_epoch)),
		"fresh confirmed exact ID fills all student fields")
	_check(student_name.text == "Maria Santos" and grade.text == "Grade 3 Jade",
		"exact ID fills name and grade without manual lookup button")
	_check(bool(form.get("context").get("student_lookup_connected", false)),
		"confirmed ID sets linked identity state")
	_edit(student_id, "KG-002")
	_check(student_name.text.is_empty() and grade.text.is_empty(),
		"editing a verified student ID clears old name/grade")
	_check(not bool(form.apply_autofill_result(valid_id, "id", "KG-001", latest_id_epoch)),
		"changed ID rejects old identity response")
	_check(next.disabled, "Continue re-disabled after identity edit")

	# Full name uses the same real idle timer. A first name alone never starts it.
	form.set_context({"entry_source": "play"})
	await process_frame
	emitted.clear()
	_edit(student_name, "Maria")
	_check((form.get("_autofill_timer") as Timer).is_stopped(),
		"one-word name is not queried")
	_edit(student_name, "Maria Santos")
	await create_timer(1.15).timeout
	_check(emitted.is_empty(), "full-name lookup does not fire before silence")
	_edit(student_name, "Maria Santos Garcia")
	await create_timer(1.50).timeout
	_check(emitted.is_empty(), "full-name typing restarts 2.5 s timer")
	await create_timer(1.22).timeout
	_check(emitted.size() == 1 and emitted[0].get("field", "") == "name"
		and emitted[0].get("value", "") == "Maria Santos Garcia",
		"full name fires once with exact final query after silence")
	var name_epoch := int((emitted[0] if not emitted.is_empty() else {}).get("epoch", -1))
	var valid_name := {"lookup_confirmed": true, "student_id": "KG-101",
		"student_name": "Maria Santos Garcia", "grade_section": "Grade 4 Rose"}
	_check(not bool(form.apply_autofill_result(valid_name, "name", "Wrong Name", name_epoch)),
		"mismatched requested full name is rejected")
	_check(not bool(form.apply_autofill_result(
		{"lookup_confirmed": true, "student_id": "KG-101",
		"student_name": "Maria Another Garcia", "grade_section": "Grade 4 Rose"},
		"name", "Maria Santos Garcia", name_epoch)),
		"mismatched returned full name is rejected")
	student_id.text = "KG-CONFLICT"
	_check(not bool(form.apply_autofill_result(valid_name, "name", "Maria Santos Garcia", name_epoch)),
		"full name cannot replace a conflicting manually entered ID")
	student_id.clear()
	# Clearing a conflicting field cancels the previous response epoch. Re-enter
	# the full name exactly as the teacher would, to authorize a fresh lookup.
	_edit(student_name, "Maria Santos Garcia")
	await create_timer(REAL_WAIT).timeout
	var fresh_name_epoch := int(form.get("_autofill_epoch"))
	_check(bool(form.apply_autofill_result(valid_name, "name", "Maria Santos Garcia", fresh_name_epoch)),
		"confirmed full name populates ID and grade")
	_check(student_id.text == "KG-101" and grade.text == "Grade 4 Rose",
		"full-name match fills the exact record")
	_edit(student_name, "Different Child")
	_check(student_id.text.is_empty() and grade.text.is_empty(),
		"editing verified full name removes previous student's ID/grade")
	_check(not bool(form.apply_autofill_result(valid_name, "name", "Maria Santos Garcia", name_epoch)),
		"late name lookup cannot restore previous child's identity")
	form.queue_free()
	await process_frame


func _test_navigation_and_controls(packed: PackedScene, guided: bool) -> void:
	var form := _make_form(packed, guided)
	await process_frame
	var where := "guided" if guided else "ordinary"
	var stage := form.get_node_or_null("SetupStage") as Control
	_check(stage != null and stage.size.is_equal_approx(Vector2(1280, 720)),
		where + ": independent editable 1280x720 stage exists")
	_check(not form.has_node("SetupStage/StudentProfileCard/DatabasePanel")
		and form.find_child("LookupButton", true, false) == null,
		where + ": deleted lookup/database panel did not return")
	var style_grid := form.get_node("SetupStage/GameSetupCard/GameContent/GameStyleGrid")
	var styles: Dictionary = form.get("_style_buttons")
	var modes: Dictionary = form.get("_mode_buttons")
	var difficulties: Dictionary = form.get("_difficulty_buttons")
	_check(styles.size() == 5 and modes.size() == 2 and difficulties.size() == 3,
		where + ": exactly 5 / 2 / 3 active button bindings")
	for style in ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]:
		var b := style_grid.get_node_or_null(String(style) + "Button") as Button
		_check(b != null and not b.disabled and b.toggle_mode and styles.get(style) == b,
			where + ": active topic " + String(style))
	for style in ["Preposition", "Conjunction", "Interjection"]:
		var b := style_grid.get_node_or_null(String(style) + "Button") as Button
		_check(b == null,
			where + ": retired " + String(style) + " is completely removed")
	_check(style_grid.get_child_count() == 5,
		where + ": five active topics only, no leftover SOON placeholders")
	var audio_players := form.find_children("*", "AudioStreamPlayer", true, false)
	_check(audio_players.is_empty(), where + ": no duplicate scene-owned hover/click audio")
	var next := form.get("_continue_button") as Button
	var active_art := next.get_node("ButtonArtwork") as CanvasItem
	var inactive_art := next.get_node("ContinueDisabledArtwork") as CanvasItem
	_check(next.disabled and inactive_art.visible and not active_art.visible,
		where + ": correct disabled Continue illustration")
	var name_field := form.get("_name_edit") as LineEdit
	var id_field := form.get("_student_id_edit") as LineEdit
	var grade_field := form.get("_grade_edit") as LineEdit
	var routes: Array[Dictionary] = []
	form.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target": target, "payload": payload.duplicate(true)}))
	(form.get("_back_button") as Button).pressed.emit()
	_check(routes.size() == 1 and String(routes[0].get("target", "")) ==
		("play_activity" if guided else "main"), where + ": real Back signal routes correctly")
	routes.clear()
	_edit(id_field, "KG-777")
	_edit(name_field, "Liza Cruz")
	_edit(grade_field, "Grade 5 Luna")
	(style_grid.get_node("AdverbButton") as Button).pressed.emit()
	((modes["Lives"]) as Button).pressed.emit()
	((difficulties["Hard"]) as Button).pressed.emit()
	_check(not next.disabled and active_art.visible and not inactive_art.visible,
		where + ": Continue enables and swaps to green art after choices")
	next.pressed.emit()
	_check(routes.size() == 1 and String(routes[0].get("target", "")) ==
		("calibration" if guided else "play_activity"), where + ": Continue routes correctly")
	if routes.size() == 1:
		var payload: Dictionary = routes[0]["payload"]
		_check(payload.get("student_id", "") == "KG-777"
			and payload.get("student_name", "") == "Liza Cruz"
			and payload.get("grade_section", "") == "Grade 5 Luna",
			where + ": Continue preserves entered identity")
		_check(payload.get("game_style", "") == "Adverb"
			and payload.get("game_mode", "") == "Lives"
			and payload.get("difficulty", "") == "Hard",
			where + ": Continue preserves chosen topic/mode/difficulty")
		_check(bool(payload.get("guided_tutorial", false)) == guided
			and bool(payload.get("camera_requested", false)) == guided,
			where + ": camera flag and tutorial context correct")
	_check(form.get_node_or_null("ExistingScoreDialog") == null,
		where + ": ExistingScoreDialog removed without disturbing identity or registration")
	# Scene must not play duplicate SFX: router owns the sound-wiring observer.
	var wiring := load("res://ui/shared/button_sound_wiring.gd").new() as Node
	root.add_child(wiring)
	wiring.call("watch", form)
	var one_button := style_grid.get_node("NounButton") as Button
	# GlobalButtonHover autoload binds animation callbacks, while MainMenu's
	# ButtonSoundWiring binds audio callbacks. Two per signal is intentional:
	# verify ONE audio down callback and ONE visual press callback.
	var down_links := one_button.button_down.get_connections()
	var hover_links := one_button.mouse_entered.get_connections()
	var sound_down := 0
	var animation_press := 0
	var global_hover := 0
	for link in down_links:
		var cb: Callable = link.get("callable", Callable())
		if cb.get_method() == "_on_down":
			sound_down += 1
		elif cb.get_method() == "_on_press":
			animation_press += 1
	for link in hover_links:
		var cb: Callable = link.get("callable", Callable())
		if is_instance_valid(cb.get_object()) and (cb.get_object() as Node).name == "GlobalButtonHover":
			global_hover += 1
	_check(down_links.size() == 2 and sound_down == 1 and animation_press == 1
		and hover_links.size() == 2 and global_hover == 1,
		where + ": exactly one router audio and one global animation hookup")
	wiring.queue_free()
	form.queue_free()
	await process_frame


func _capture_three_viewports(packed: PackedScene) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(IMAGE_DIR))
	for resolution in SIZES:
		# Offscreen native Godot render surface guarantees REAL target resolution
		# even when Windows DPI/fullscreen policy overrides the outer app window.
		var viewport := SubViewport.new()
		viewport.name = "StudentSetupFinalCapture"
		viewport.size = resolution
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.disable_3d = true
		root.add_child(viewport)
		var form := packed.instantiate() as Control
		viewport.add_child(form)
		form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		form.set_context({"entry_source": "play"})
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var im := viewport.get_texture().get_image()
		_check(im != null and Vector2i(im.get_size()) == resolution,
			"native capture exact pixels " + str(resolution))
		if im != null:
			var path := ProjectSettings.globalize_path(
				IMAGE_DIR.path_join("student_setup_%dx%d.png" % [resolution.x, resolution.y]))
			var err := im.save_png(path)
			_check(err == OK, "saved native capture " + path)
			if err == OK:
				print("NATIVE CAPTURE ", path)
		viewport.queue_free()
		await process_frame


func _finish() -> void:
	print("STUDENT SETUP FINAL: ", "PASS" if failures.is_empty() else "FAIL",
		" checks=", checks, " failures=", failures.size())
	for reason in failures:
		printerr("QA FAILURE ", reason)
	quit(0 if failures.is_empty() else 1)
