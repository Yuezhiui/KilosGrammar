extends SceneTree

## Read-only visual/behavior QA: no real database, no real destructive requests.
## CAPTURE_DELETE_SUCCESS_VISUAL=1 enables full-window PNG screenshots in user://.
const BOARD_SCENE := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const NOTIFICATION_ART := [
	"res://Components/Leaderboard/Success/bg.png",
	"res://Components/Leaderboard/Success/OkayButton.png",
	"res://Components/Leaderboard/Success/00669de2-99cd-46c6-bef9-f3a0f69c72e1.png",
	"res://Components/Leaderboard/NotifLeader/notif background.png",
	"res://Components/Leaderboard/NotifLeader/cancel.png",
	"res://Components/Leaderboard/NotifLeader/show final conf.png",
	"res://Components/Leaderboard/NotifLeader/permanent delete default.png",
	"res://Components/Leaderboard/NotifLeader/permanent delete if add_.png",
	"res://Components/Leaderboard/NotifLeader/header end.png",
	"res://Components/Leaderboard/NotifLeader/hgeader before end.png",
	"res://Components/Leaderboard/NotifLeader/type delete all data.png",
]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Original Downloads folders are source-only, never runtime dependencies.
	for path in NOTIFICATION_ART:
		_check(ResourceLoader.exists(path) and FileAccess.file_exists(path + ".import"),
			"Notification PNG and .import are installed locally: " + path.get_file())
	var serialized := FileAccess.get_file_as_string("res://ui/secondary/leaderboard/leaderboard.tscn").to_lower()
	_check(not serialized.contains("downloads") and not serialized.contains("notifleaderboard success")
		and not serialized.contains("notif leader"),
		"Production Leaderboard scene never references either external Downloads source folder")
	root.size = VIEWPORTS[0]
	var panel := BOARD_SCENE.instantiate() as Control
	var overlay := panel.get_node("DeleteSuccessOverlay") as Control
	_check(not overlay.visible, "Success overlay starts hidden in serialized Godot scene")
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	var bg := panel.get_node("DeleteSuccessOverlay/SuccessBoard") as TextureRect
	var header := panel.get_node("DeleteSuccessOverlay/SuccessHeader") as TextureRect
	var message := panel.get_node("%SuccessMessage") as Label
	var okay := panel.get_node("%SuccessOkayButton") as Button
	var notice := panel.get_node("%EmptyNotice") as AcceptDialog
	var first := panel.get_node("%DeleteFirstOverlay") as Control
	var final := panel.get_node("%DeleteFinalOverlay") as Control
	_check(bg.texture is AtlasTexture and (bg.texture as AtlasTexture).atlas.resource_path.ends_with("/Success/bg.png"),
		"Real user-supplied wooden success background is loaded with transparent padding cropped")
	_check(okay.get_theme_stylebox("normal") is StyleBoxTexture
		and ((okay.get_theme_stylebox("normal") as StyleBoxTexture).texture as AtlasTexture).atlas.resource_path.ends_with("/Success/OkayButton.png"),
		"Real user-supplied green OK art powers native editable Button")
	_check(header.texture != null and header.texture.resource_path.ends_with("/Success/00669de2-99cd-46c6-bef9-f3a0f69c72e1.png")
		and panel.get_node_or_null("DeleteSuccessOverlay/SuccessBoard/SuccessTitle") == null,
		"Supplied decorated Leaderboard — Completed header replaces duplicate plain text title")
	_check(header.get_parent() == overlay and header.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"Decorative header is a separate editor-editable overlay and never steals OK clicks")
	_check(not overlay.visible and not first.visible and not final.visible,
		"Success artwork never obstructs Leaderboard before backend acknowledgement")
	panel.set_context({"teacher_authorized": true, "database_connected": true})
	panel.set_transfer_status("Database deletion failed: nothing was deleted.")
	_check(not overlay.visible and notice.visible and notice.dialog_text.contains("failed"),
		"Failed deletion stays on ordinary notice and cannot trigger false success")
	notice.hide()
	panel.set_transfer_status("Full CSV export saved.", true)
	_check(not overlay.visible and notice.visible and notice.dialog_text.contains("CSV export"),
		"Unrelated successful CSV export still uses its ordinary notice")
	notice.hide()

	for resolution in VIEWPORTS:
		root.size = resolution
		await process_frame
		panel.set_transfer_pending("Mock test-only pending delete")
		panel.show_delete_success(0, 0)
		await process_frame
		_check(overlay.visible and not first.visible and not final.visible and not notice.visible,
			"Only custom success overlay is visible at %s" % resolution)
		_check(message.text == "Deleted 0 student profiles and 0 saved scores.",
			"Zero counts come from response rather than fabricated deletion at %s" % resolution)
		_check(not bool(panel.get("_transfer_pending")),
			"Confirmed delete success unlocks transfer UI at %s" % resolution)
		_check(_inside(bg.get_global_rect(), panel.size) and _inside(okay.get_global_rect(), panel.size)
			and _inside(header.get_global_rect(), panel.size),
			"Board, decorated header and green OK hitbox remain on logical 16:9 canvas at %s" % resolution)
		_check(absf(header.get_global_rect().get_center().x - bg.get_global_rect().get_center().x) <= 8.0
			and header.get_global_rect().intersects(bg.get_global_rect()),
			"Supplied wooden header stays visually centered over edited board at %s" % resolution)
		_check(message.get_global_rect().intersects(bg.get_global_rect()) and okay.size.x >= 120,
			"Readable message and editor-sized native OK button remain on the board at %s" % resolution)
		await _capture(resolution)
		panel.set_transfer_status("CSV import done later.", true)
		_check(overlay.visible and not notice.visible,
			"Unrelated notice queues behind success board at %s" % resolution)
		okay.pressed.emit()
		_check(not overlay.visible and notice.visible and notice.dialog_text == "CSV import done later.",
			"Native green OK closes board and restores queued CSV notice at %s" % resolution)
		notice.hide()
	panel.show_delete_success(12, 34)
	_check(message.text == "Deleted 12 student profiles and 34 saved scores.",
		"Nonzero deleted counts are rendered from supplied backend figures")
	okay.pressed.emit()
	_check(not overlay.visible, "Green OK clears success board for later operations")
	panel.queue_free()
	await process_frame
	print("LEADERBOARD DELETE SUCCESS VISUAL: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _inside(rect: Rect2, canvas: Vector2) -> bool:
	return rect.position.x >= -1.0 and rect.position.y >= -1.0 and rect.end.x <= canvas.x + 1.0 \
		and rect.end.y <= canvas.y + 1.0 and rect.has_area()


func _capture(resolution: Vector2i) -> void:
	if OS.get_environment("CAPTURE_DELETE_SUCCESS_VISUAL") != "1" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := "user://qa_delete_success_%dx%d.png" % [resolution.x, resolution.y]
	var error := root.get_texture().get_image().save_png(path)
	_check(error == OK, "Graphical screenshot saved at %s" % resolution)
	if error == OK:
		print("DELETE SUCCESS SCREENSHOT: ", ProjectSettings.globalize_path(path))


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("DELETE SUCCESS QA FAIL: ", description)
