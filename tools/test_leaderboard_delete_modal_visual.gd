extends SceneTree

## Pure UI and signal regression for the two editor-authored delete notices.
## No transport, PostgreSQL client, destructive method or real student data.
## godot --headless --path . --script res://tools/test_leaderboard_delete_modal_visual.gd
## Optional graphical screenshots: CAPTURE_LEADERBOARD_DELETE_VISUAL=1
const SCENE := preload("res://ui/secondary/leaderboard.tscn")
const PHRASE := "DELETE ALL DATA"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
# These are the teacher-adjusted offsets/sizing in leaderboard.tscn. Checking
# both states against one authored rect catches accidental runtime resizing.
const EDITOR_FINAL_DELETE_POSITION := Vector2(490, 430)
const EDITOR_FINAL_DELETE_SIZE := Vector2(288, 71)
const FRAME_TOLERANCE := 4.0

var checks := 0
var failures: Array[String] = []
var emitted: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = SIZES[0]
	var panel := SCENE.instantiate() as Control
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var first := panel.get_node_or_null("%DeleteFirstOverlay") as Control
	var final := panel.get_node_or_null("%DeleteFinalOverlay") as Control
	var delete := panel.get_node_or_null("%DeleteAllButton") as Button
	var input := panel.get_node_or_null("%TypedConfirmationEdit") as LineEdit
	var permanent := panel.get_node_or_null("%FinalDeleteButton") as Button
	var final_cancel := panel.get_node_or_null("%FinalCancelButton") as Button
	var first_cancel := panel.get_node_or_null("%FirstCancelButton") as Button
	var first_continue := panel.get_node_or_null("%FirstContinueButton") as Button
	var first_art := panel.get_node_or_null("%DeleteFirstOverlay/BoardArtwork") as TextureRect
	var final_art := panel.get_node_or_null("%DeleteFinalOverlay/ConfirmPanel") as TextureRect
	var status_panel := panel.get_node_or_null("TransferStatusPanel") as Panel
	var status_label := panel.get_node_or_null("%TransferStatus") as Label
	var notice := panel.get_node_or_null("%EmptyNotice") as AcceptDialog
	_check(first != null and final != null and delete != null and input != null
		and permanent != null and final_cancel != null
		and first_cancel != null and first_continue != null
			and status_panel == null and status_label == null and notice != null,
			"Both modals and native notice retained; obsolete beige status panel/label removed")
	if (first == null or final == null or delete == null or input == null or permanent == null
		or final_cancel == null or first_cancel == null or first_continue == null
			or notice == null):
		panel.free()
		quit(1)
		return
	_check(panel.find_child("DeleteFirstWarning", true, false) == null,
		"Stock Godot DeleteFirstWarning ConfirmationDialog is removed from the scene")
	_check(not first.visible and not final.visible and permanent.disabled,
		"Both modal surfaces initialize hidden with destructive action disabled")
	_check(first.mouse_filter == Control.MOUSE_FILTER_STOP
		and final.mouse_filter == Control.MOUSE_FILTER_STOP,
		"Custom overlays capture pointer clicks outside modal artwork")
	_check(_button_art_path(first_continue).ends_with("show final conf.png")
		and _button_art_path(first_cancel).ends_with("cancel.png"),
		"Stage-one native buttons display the exact supplied Continue and Cancel PNGs")
	_check(_button_art_path(permanent).ends_with("permanent delete if add_.png")
		and _button_art_path(final_cancel).ends_with("cancel.png")
		and _button_art_path(permanent, "disabled").ends_with("permanent delete default.png"),
		"Final-stage native buttons use supplied enabled/disabled Permanent Delete and Cancel PNGs")
	_check(permanent.position.is_equal_approx(EDITOR_FINAL_DELETE_POSITION)
		and permanent.size.is_equal_approx(EDITOR_FINAL_DELETE_SIZE),
			"Teacher-edited native FinalDeleteButton keeps its scene-authored 490,430 / 288x71 layout")
	var enabled_frame := _visible_frame_in_button(permanent, "normal")
	var disabled_frame := _visible_frame_in_button(permanent, "disabled")
	_check(enabled_frame.has_area() and disabled_frame.has_area(),
		"Both original red and gray PNG crops contain decodable visible artwork")
	print("FINAL DELETE PNG BOUNDS: red=", enabled_frame, " gray=", disabled_frame)
	_check(_frames_equivalent(enabled_frame, disabled_frame),
		"Enabled-red and disabled-gray PNG visual alpha bounds match within %.1f logical pixels" % FRAME_TOLERANCE)
	_check(_has_board_png(first) and _has_board_png(final),
		"Both overlays use separately rendered original PNG board art as movable controls")
	panel.set_transfer_status("")
	_check(status_panel == null and status_label == null and not notice.visible,
		"An empty status does not create a beige panel or a generic popup")
	panel.database_delete_all_requested.connect(func(value: String) -> void: emitted.append(value))
	first_continue.pressed.emit()
	_check(not final.visible, "Forged Continue before opening a warning cannot advance")
	delete.pressed.emit()
	_check(not first.visible and not final.visible and emitted.is_empty(),
		"Teacher permission is required before either custom modal can open")
	panel.set_context({"teacher_authorized": true, "database_connected": true})
	# The deliberate unauthorized press above legitimately reports its own
	# teacher-auth failure. Clear it before exercising the empty-status path.
	panel.set_transfer_status("")
	notice.hide()
	_check(not notice.visible and status_panel == null,
		"Dismissed earlier authorization error leaves no obstructing native notice")

	for resolution in SIZES:
		root.size = resolution
		await process_frame
		# canvas_items stretching maps the game's logical 1280x720 canvas
		# into the physical Window.size. Assigning panel.size to Window.size
		# applies the size multiplier twice and produces a clipped capture.
		var logical_size := Vector2i(panel.size)
		print("DELETE MODAL SIZE: physical=", root.size,
			" logical=", root.get_visible_rect().size,
			" panel=", panel.size, " content_scale=", root.content_scale_size)
		delete.pressed.emit()
		_check(first.visible and not final.visible and emitted.is_empty(),
			"First warning opens alone at %s without dispatch" % resolution)
		_check(not notice.visible and status_panel == null,
			"Delete CSV shows only custom first-stage artwork, not beige or generic notice at %s" % resolution)
		_check(_overlay_covers_screen(first, logical_size),
			"First warning dim/click-catching surface fills %s" % resolution)
		_check(_button_geometry_valid(first, logical_size),
			"Stage-one native button hitboxes fit and do not intersect at %s" % resolution)
		_check(first_art != null and first_art.get_global_rect().get_center().distance_to(
			Vector2(logical_size) * 0.5) <= 30.0,
			"First modal artwork stays centered on the logical 16:9 viewport at %s" % resolution)
		_check(_no_stock_dialog_visible(panel),
			"No stock Godot alert/dialog is visible behind first warning at %s" % resolution)
		await _capture("warning", resolution)
		first_cancel.pressed.emit()
		_check(not first.visible and not final.visible and emitted.is_empty(),
			"First-stage Cancel closes both overlays without emitting at %s" % resolution)
		_check(not notice.visible, "First cancel leaves no redundant status popup at %s" % resolution)
		delete.pressed.emit()
		var first_escape := InputEventKey.new()
		first_escape.keycode = KEY_ESCAPE
		first_escape.pressed = true
		root.push_input(first_escape)
		await process_frame
		_check(not first.visible and not final.visible and emitted.is_empty(),
			"Escape cancels initial warning before final confirmation at %s" % resolution)
		delete.pressed.emit()
		first_continue.pressed.emit()
		await process_frame
		_check(not first.visible and final.visible and permanent.disabled,
			"Native Continue button moves to locked second stage at %s" % resolution)
		_check(not notice.visible and status_panel == null,
			"Final modal has no beige status panel or generic dialog obstructing it at %s" % resolution)
		_check(_overlay_covers_screen(final, logical_size)
			and _button_geometry_valid(final, logical_size),
			"Final warning fills viewport with separate accessible native buttons at %s" % resolution)
		_check(final_art != null and final_art.get_global_rect().get_center().distance_to(
			Vector2(logical_size) * 0.5) <= 30.0,
			"Final modal artwork stays centered on the logical 16:9 viewport at %s" % resolution)
		_check(_within_screen(input.get_global_rect(), logical_size),
			"Typed confirmation field stays on-screen at %s" % resolution)
		var before_state := permanent.get_global_rect()
		_check(permanent.position.is_equal_approx(EDITOR_FINAL_DELETE_POSITION)
			and permanent.size.is_equal_approx(EDITOR_FINAL_DELETE_SIZE),
			"Authored FinalDeleteButton layout is unchanged at physical %s" % resolution)
		_check(_within_screen(before_state, logical_size)
			and _frames_equivalent(_visible_frame_in_button(permanent, "normal"),
				_visible_frame_in_button(permanent, "disabled")),
			"Red/gray artwork occupies matching visible button frames at %s" % resolution)
		_check(_no_stock_dialog_visible(panel),
			"No native ConfirmationDialog replaces the requested final artwork at %s" % resolution)
		await _capture("final", resolution)
		input.text = "DELETE ALL DAT"
		input.text_changed.emit(input.text)
		permanent.pressed.emit()
		_check(permanent.disabled and emitted.is_empty(),
			"Wrong phrase cannot trigger sensitive signal at %s" % resolution)
		input.text = PHRASE
		input.text_changed.emit(input.text)
		_check(not permanent.disabled,
			"Exact phrase enables native destructive button at %s" % resolution)
		_check(emitted.is_empty() and not bool(panel.get("_transfer_pending")),
			"Typing exact phrase and switching gray to red never sends a delete request at %s" % resolution)
		_check(permanent.get_global_rect().is_equal_approx(before_state),
			"Typing exact phrase changes gray to red without changing native hitbox at %s" % resolution)
		_check(_frames_equivalent(_visible_frame_in_button(permanent, "normal"),
				_visible_frame_in_button(permanent, "disabled")),
			"Enabled and disabled artwork remain equally sized after switch at %s" % resolution)
		await _capture("final_enabled", resolution)
		# An actual Escape key event must cancel the second stage and clear the text.
		var esc := InputEventKey.new()
		esc.keycode = KEY_ESCAPE
		esc.pressed = true
		root.push_input(esc)
		await process_frame
		_check(not first.visible and not final.visible and input.text.is_empty()
			and permanent.disabled and emitted.is_empty(),
			"Escape cancels final stage, clears confirmation and preserves data at %s" % resolution)
		_check(not notice.visible,
			"Escape from final stage does not resurrect an empty status popup at %s" % resolution)
		delete.pressed.emit()
		_check(first.visible and not final.visible, "Canceled stage can reopen at %s" % resolution)
		first_continue.pressed.emit()
		_check(input.text.is_empty() and permanent.disabled,
			"Reopening from Escape resets typed state at %s" % resolution)
		final_cancel.pressed.emit()
		_check(not first.visible and not final.visible and input.text.is_empty(),
			"Second-stage Cancel closes and resets both modal stages at %s" % resolution)
		_check(not notice.visible and status_panel == null,
			"Final-stage Cancel preserves removed beige panel and no empty popup at %s" % resolution)

		# Native import/export feedback waits while custom delete art is active.
		# After either Cancel, only genuine queued backend result may appear.
		for status_case in [
			{"name": "import", "message": "CSV import failed: invalid columns.", "ok": false},
			{"name": "export", "message": "Full CSV export saved: 12 students, 48 scores.", "ok": true},
		]:
			var genuine_message := String(status_case["message"])
			panel.set_transfer_status(genuine_message, bool(status_case["ok"]))
			_check(notice.visible and notice.dialog_text == genuine_message,
				"Backend %s result appears in native notice at %s" % [status_case["name"], resolution])
			notice.hide() # Teacher dismisses notice before opening delete.
			delete.pressed.emit()
			_check(first.visible and not final.visible and not notice.visible,
				"First warning is not obstructed by native notice at %s" % resolution)
			panel.set_transfer_status(genuine_message, bool(status_case["ok"]))
			_check(not notice.visible and first.visible,
				"During first warning, backend %s result queues without generic popup at %s" % [status_case["name"], resolution])
			first_cancel.pressed.emit()
			_check(not first.visible and not final.visible and notice.visible
				and notice.dialog_text == genuine_message,
				"First-stage Cancel restores genuine %s notice at %s" % [status_case["name"], resolution])
			notice.hide()
			delete.pressed.emit()
			first_continue.pressed.emit()
			_check(not first.visible and final.visible and not notice.visible,
				"Final artwork unobstructed by generic notice at %s" % resolution)
			panel.set_transfer_status(genuine_message, bool(status_case["ok"]))
			_check(not notice.visible and final.visible,
				"Backend %s notice queues until final modal is closed at %s" % [status_case["name"], resolution])
			final_cancel.pressed.emit()
			_check(not first.visible and not final.visible and notice.visible
				and notice.dialog_text == genuine_message,
				"Final-stage Cancel restores genuine %s notice at %s" % [status_case["name"], resolution])
			notice.hide()
			panel.set_transfer_status("")
			_check(not notice.visible and status_panel == null,
				"Cleared notice leaves no permanent beige UI at %s" % resolution)

	# Teacher context changes must revoke an already-open stage, even when an
	# old synthetic Button.pressed signal is delivered after authorization loss.
	delete.pressed.emit()
	first_continue.pressed.emit()
	input.text = PHRASE
	input.text_changed.emit(input.text)
	panel.set_context({"teacher_authorized": false, "database_connected": true})
	permanent.pressed.emit()
	_check(not first.visible and not final.visible and permanent.disabled and emitted.is_empty(),
		"Teacher authorization loss cancels typed deletion and forged click is ignored")
	panel.set_context({"teacher_authorized": true, "database_connected": true})
	panel.set_transfer_pending("Test-only pending CSV transfer")
	delete.pressed.emit()
	first_continue.pressed.emit()
	_check(not first.visible and not final.visible and emitted.is_empty(),
		"Pending transfer blocks both warning stages")
	panel.set_transfer_status("Test-only transfer finished")
	delete.pressed.emit()
	first_continue.pressed.emit()
	input.text = PHRASE
	input.text_changed.emit(input.text)
	permanent.pressed.emit()
	_check(emitted == [PHRASE] and not first.visible and not final.visible,
		"Only both explicit confirmations emit exactly one sensitive signal")
	permanent.pressed.emit()
	_check(emitted.size() == 1 and panel.get("_transfer_pending"),
		"Double-click cannot dispatch another signal during pending backend reply")
	panel.free()
	await process_frame
	print("DELETE MODAL VISUAL QA: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _no_stock_dialog_visible(panel: Node) -> bool:
	for item in panel.find_children("*", "ConfirmationDialog", true, false):
		if (item as ConfirmationDialog).visible:
			return false
	return true


func _has_board_png(overlay: Control) -> bool:
	for item in overlay.find_children("*", "TextureRect", true, false):
		var texture := (item as TextureRect).texture
		if _texture_path(texture).ends_with(".png"):
			return true
	for item in overlay.find_children("*", "NinePatchRect", true, false):
		var texture := (item as NinePatchRect).texture
		if _texture_path(texture).ends_with(".png"):
			return true
	for item in overlay.find_children("*", "Panel", true, false):
		var style := (item as Panel).get_theme_stylebox("panel")
		if style is StyleBoxTexture and _texture_path((style as StyleBoxTexture).texture).ends_with(".png"):
			return true
	return false


func _button_art_path(button: Button, state: String = "normal") -> String:
	return _texture_path(_button_art_texture(button, state))


func _button_art_texture(button: Button, state: String) -> Texture2D:
	var box := button.get_theme_stylebox(state)
	if box is StyleBoxTexture:
		return (box as StyleBoxTexture).texture
	return null


func _visible_frame_in_button(button: Button, state: String) -> Rect2:
	var texture := _button_art_texture(button, state)
	if texture == null:
		return Rect2()
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Rect2()
	# PNGs have transparent padding; comparing raw source dimensions or only
	# Button.get_rect() would miss visibly undersized gray/red artwork.
	var alpha := image.get_used_rect()
	var source_size := Vector2(image.get_size())
	if source_size.x <= 0 or source_size.y <= 0:
		return Rect2()
	return Rect2(Vector2(alpha.position) * button.size / source_size,
		Vector2(alpha.size) * button.size / source_size)


func _frames_equivalent(red: Rect2, gray: Rect2) -> bool:
	if not red.has_area() or not gray.has_area():
		return false
	return red.position.distance_to(gray.position) <= FRAME_TOLERANCE \
		and absf(red.size.x - gray.size.x) <= FRAME_TOLERANCE \
		and absf(red.size.y - gray.size.y) <= FRAME_TOLERANCE


func _texture_path(texture: Texture2D) -> String:
	if texture == null:
		return ""
	if texture is AtlasTexture:
		return _texture_path((texture as AtlasTexture).atlas)
	return texture.resource_path.to_lower()


func _overlay_covers_screen(overlay: Control, resolution: Vector2i) -> bool:
	var rect := overlay.get_global_rect()
	return (absf(rect.position.x) < 3.0 and absf(rect.position.y) < 3.0
		and absf(rect.size.x - resolution.x) < 3.0
		and absf(rect.size.y - resolution.y) < 3.0)


func _button_geometry_valid(overlay: Control, resolution: Vector2i) -> bool:
	var buttons := overlay.find_children("*", "Button", true, false)
	if buttons.size() != 2:
		return false
	var first_rect := (buttons[0] as Button).get_global_rect()
	var second_rect := (buttons[1] as Button).get_global_rect()
	return (_within_screen(first_rect, resolution) and _within_screen(second_rect, resolution)
		and first_rect.size.x >= 60.0 and second_rect.size.x >= 60.0
		and first_rect.size.y >= 32.0 and second_rect.size.y >= 32.0
		and not first_rect.intersects(second_rect))


func _within_screen(rect: Rect2, resolution: Vector2i) -> bool:
	return (rect.size.x > 0.0 and rect.size.y > 0.0
		and rect.position.x >= -2.0 and rect.position.y >= -2.0
		and rect.end.x <= resolution.x + 2.0 and rect.end.y <= resolution.y + 2.0)


func _capture(stage: String, resolution: Vector2i) -> void:
	if (OS.get_environment("CAPTURE_LEADERBOARD_DELETE_VISUAL") != "1"
		or DisplayServer.get_name() == "headless"):
		return
	await RenderingServer.frame_post_draw
	var path := "user://qa_leaderboard_delete_%s_%dx%d.png" % [stage, resolution.x, resolution.y]
	var result := root.get_texture().get_image().save_png(path)
	_check(result == OK, "Graphical screenshot saved for %s at %s" % [stage, resolution])
	if result == OK:
		print("DELETE MODAL SCREENSHOT: ", ProjectSettings.globalize_path(path))


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("DELETE MODAL QA FAIL: ", description)
