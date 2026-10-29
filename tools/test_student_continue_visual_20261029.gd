extends SceneTree

## Native, isolated visual regression for Student Setup's Continue gate.
## Godot --path . --rendering-method gl_compatibility \
##   --script res://tools/test_student_continue_visual_20261029.gd
## Creates three 16:9 native screenshots at each resolution: default gray,
## complete green, missing one difficulty gray, and missing profile gray.
## All identities are local mock values; no real DB/camera is queried.

const SCENE := "res://ui/student/setup/student_setup.tscn"
const OUTPUT := "res://showcase/student_continue_gate_20261029"
const ACTIVE_TEXTURE := "res://Components/Student Setup/Redesign/btn_continue.png"
const DISABLED_TEXTURE := "res://Components/Student Setup/Redesign/btn_uncontinue.png"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]

var assertions := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "Native screenshots require graphical Godot, no --headless")
		_finish()
		return
	var packed := load(SCENE) as PackedScene
	_check(packed != null, "Student Setup loads")
	if packed == null:
		_finish()
		return
	_check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT)) == OK,
		"Screenshot output directory exists")
	for resolution in SIZES:
		await _check_resolution(packed, resolution)
	_finish()


func _check_resolution(packed: PackedScene, resolution: Vector2i) -> void:
	# SubViewport renders exact native target pixels, independent of Windows DPI.
	var viewport := SubViewport.new()
	viewport.name = "ContinueGateVisual_%dx%d" % [resolution.x, resolution.y]
	viewport.size = resolution
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var form := packed.instantiate() as Control
	viewport.add_child(form)
	form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	form.set_context({"entry_source": "play"})
	await process_frame
	await process_frame
	var next := form.get_node_or_null("SetupStage/SetupActions/ContinueButton") as Button
	if next == null:
		_check(false, "%s: ContinueButton node present" % resolution)
		viewport.queue_free()
		await process_frame
		return
	var green := next.get_node_or_null("ButtonArtwork") as TextureRect
	var gray := next.get_node_or_null("ContinueDisabledArtwork") as TextureRect
	_check(green != null and gray != null, "%s: both artwork nodes exist" % resolution)
	if green == null or gray == null:
		viewport.queue_free()
		await process_frame
		return
	_check(green.texture != null and green.texture.resource_path == ACTIVE_TEXTURE,
		"%s: green artwork is the original active Continue PNG" % resolution)
	_check(gray.texture != null and gray.texture.resource_path == DISABLED_TEXTURE,
		"%s: gray artwork uses the supplied btn_uncontinue.png" % resolution)
	_check(green.position == gray.position and green.size == gray.size,
		"%s: green/gray textures use exactly the same editor-authored rect" % resolution)
	var base_geometry := _snapshot_geometry(form)
	var stage := form.get_node("SetupStage") as Control
	var expected_scale := minf(float(resolution.x) / 1280.0, float(resolution.y) / 720.0)
	_check(stage.scale.is_equal_approx(Vector2.ONE * expected_scale),
		"%s: proportional 16:9 stage scale" % resolution)
	_check(next.disabled and gray.visible and not green.visible,
		"%s: blank entry uses disabled gray artwork" % resolution)
	var gray_score := await _save_capture(viewport, next, resolution, "01_default_gray")

	var id_edit := form.get("_student_id_edit") as LineEdit
	var name_edit := form.get("_name_edit") as LineEdit
	var grade_edit := form.get("_grade_edit") as LineEdit
	_edit(id_edit, "KG-VISUAL-001")
	_edit(name_edit, "Visual Sample")
	_edit(grade_edit, "Grade 4 Jade")
	var styles: Dictionary = form.get("_style_buttons")
	var modes: Dictionary = form.get("_mode_buttons")
	var difficulties: Dictionary = form.get("_difficulty_buttons")
	(styles["Noun"] as Button).pressed.emit()
	(modes["Seconds"] as Button).pressed.emit()
	(difficulties["Easy"] as Button).pressed.emit()
	_check(not next.disabled and green.visible and not gray.visible,
		"%s: all six required fields selected gives green Continue" % resolution)
	_check(_same_geometry(base_geometry, _snapshot_geometry(form), str(resolution) + " complete"),
		"%s: completing form preserves every original UI rect and transform" % resolution)
	var selected_before := _snapshot_selection(form)
	var green_score := await _save_capture(viewport, next, resolution, "02_complete_green")
	_check(green_score > gray_score + 0.09,
		"%s: native Continue button pixels visibly change from gray to green (%.3f to %.3f)" %
		[resolution, gray_score, green_score])

	# Clearing one game selection must gate Continue without altering unrelated
	# profile fields or the selected style/mode highlighting.
	form.call("_select_difficulty", "")
	_check(next.disabled and gray.visible and not green.visible,
		"%s: missing only difficulty returns to gray" % resolution)
	_check(id_edit.text == "KG-VISUAL-001" and name_edit.text == "Visual Sample"
		and grade_edit.text == "Grade 4 Jade",
		"%s: missing difficulty does not clear the entered profile" % resolution)
	_check((styles["Noun"] as Button).button_pressed and (modes["Seconds"] as Button).button_pressed,
		"%s: missing difficulty retains chosen topic and mode highlights" % resolution)
	_check(_same_geometry(base_geometry, _snapshot_geometry(form), str(resolution) + " no difficulty"),
		"%s: removing one game choice preserves authored geometry" % resolution)
	await _save_capture(viewport, next, resolution, "03_missing_difficulty_gray")

	# Once difficulty is restored, removing one profile field also disables
	# Continue, while all three game-choice highlights stay untouched.
	(difficulties["Easy"] as Button).pressed.emit()
	_check(_snapshot_selection(form) == selected_before,
		"%s: restoring difficulty restores selection highlighting exactly" % resolution)
	_edit(grade_edit, "")
	_check(next.disabled and gray.visible and not green.visible,
		"%s: missing only Grade & Section returns to gray" % resolution)
	_check(_snapshot_selection(form) == selected_before,
		"%s: incomplete profile retains all selection highlights" % resolution)
	_check(_same_geometry(base_geometry, _snapshot_geometry(form), str(resolution) + " no grade"),
		"%s: clearing one profile field preserves authored geometry" % resolution)
	await _save_capture(viewport, next, resolution, "04_missing_grade_gray")
	viewport.queue_free()
	await process_frame


func _edit(field: LineEdit, value: String) -> void:
	field.text = value
	field.text_changed.emit(value)


func _snapshot_geometry(form: Control) -> Dictionary:
	var snapshot := {}
	var nodes: Array[Node] = [form]
	nodes.append_array(form.find_children("*", "Control", true, false))
	for node in nodes:
		var control := node as Control
		# Runtime-only children of native widgets may move as text/focus changes.
		# Only nodes owned by the original editor-authored PackedScene count.
		# The hidden ValidationLabel auto-fits its changing status text, but is
		# deliberately invisible on normal incomplete/complete form states.
		if control == null or (control != form and control.owner == null) \
				or control.name == "ValidationLabel":
			continue
		snapshot[str(form.get_path_to(control))] = [
			control.position, control.size,
			Vector4(control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom),
			control.pivot_offset, control.scale, control.rotation,
		]
	return snapshot


func _same_geometry(expected: Dictionary, actual: Dictionary, label: String) -> bool:
	if expected == actual:
		return true
	for key in expected:
		if not actual.has(key):
			printerr("GEOMETRY DETAIL ", label, " missing ", key)
			return false
		if expected[key] != actual[key]:
			printerr("GEOMETRY DETAIL ", label, " ", key,
				" expected=", expected[key], " actual=", actual[key])
			return false
	for key in actual:
		if not expected.has(key):
			printerr("GEOMETRY DETAIL ", label, " unexpected ", key)
			return false
	return true


func _snapshot_selection(form: Control) -> Dictionary:
	var snapshot := {}
	for group_name in ["_style_buttons", "_mode_buttons", "_difficulty_buttons"]:
		var buttons: Dictionary = form.get(group_name)
		for key in buttons:
			var button := buttons[key] as Button
			snapshot[group_name + "/" + str(key)] = [button.button_pressed, button.modulate]
	return snapshot


func _save_capture(viewport: SubViewport, next: Button, resolution: Vector2i, state: String) -> float:
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	var expected := Vector2i(pixels.get_size()) == resolution
	_check(expected, "%s %s: native screenshot pixels match resolution" % [resolution, state])
	var filename := "%s_%dx%d.png" % [state, resolution.x, resolution.y]
	var path := ProjectSettings.globalize_path(OUTPUT.path_join(filename))
	var saved := pixels.save_png(path)
	_check(saved == OK, "%s %s: PNG screenshot saved" % [resolution, state])
	if saved == OK:
		print("CONTINUE VISUAL CAPTURE ", path)
	# Compare visible in-scene pixel color. Both artworks use the same position,
	# so green minus red is strong in the active PNG and small in gray artwork.
	var rect := next.get_global_rect()
	var chroma := 0.0
	var samples := 0
	for yi in range(2, 15):
		for xi in range(2, 25):
			var x := clampi(int(rect.position.x + rect.size.x * (float(xi) / 26.0)), 0, pixels.get_width() - 1)
			var y := clampi(int(rect.position.y + rect.size.y * (float(yi) / 17.0)), 0, pixels.get_height() - 1)
			var sample := pixels.get_pixel(x, y)
			chroma += sample.g - sample.r
			samples += 1
	return chroma / float(maxi(samples, 1))


func _check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures.append(message)
		printerr("CONTINUE VISUAL FAIL: ", message)


func _finish() -> void:
	print("STUDENT CONTINUE VISUAL: %s assertions=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	for error in failures:
		printerr("CONTINUE VISUAL FAILURE ", error)
	quit(0 if failures.is_empty() else 1)
