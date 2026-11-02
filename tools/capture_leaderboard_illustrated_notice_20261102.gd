extends SceneTree

## Visual review of the REAL Leaderboard scene after its illustrated notice is
## installed. Standalone preview: no MainMenu, API, database, or account writes.
## Run with graphical Godot:
##   godot --path . --script res://tools/capture_leaderboard_illustrated_notice_20261102.gd

const SCENE := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const OUTPUT := "res://showcase/leaderboard_notice_20261102"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const IMPORT_TEXT := "Teacher authorization required to import student records."
const DELETE_TEXT := (
	"DELETE ALL DATA was blocked. Local administrator authorization is required. "
	+ "No student profiles or scores were deleted. "
	+ "Ask the local administrator to authorize database management."
)

var checks := 0
var errors: Array[String] = []
var captured: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _verify(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		errors.append(description)
		printerr("ILLUSTRATED NOTICE CAPTURE FAIL: ", description)


func _changed_pixels(before: Image, after: Image) -> int:
	if before.is_empty() or after.is_empty() or before.get_size() != after.get_size():
		return 0
	var changed := 0
	var step_x := maxi(12, before.get_width() / 40)
	var step_y := maxi(12, before.get_height() / 26)
	for y in range(int(step_y / 2), before.get_height(), step_y):
		for x in range(int(step_x / 2), before.get_width(), step_x):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.22:
				changed += 1
	return changed


func _capture(filename: String, expected: Vector2i, previous: Image) -> void:
	for _frame in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	_verify(not picture.is_empty() and picture.get_size() == expected,
		"%s screenshot native resolution is %s" % [filename, expected])
	var pixels := _changed_pixels(previous, picture)
	_verify(pixels >= 100,
		"%s contains an illustrated/dimmed in-scene notice, not just the native OS popup (changed pixels=%d)" % [
			filename, pixels
		])
	var path := ProjectSettings.globalize_path(OUTPUT.path_join(filename))
	var result := picture.save_png(path) if not picture.is_empty() else ERR_CANT_CREATE
	_verify(result == OK, "Screenshot saved: " + path)
	if result == OK:
		captured.append(path)
		print("NOTICE SCREENSHOT: ", path)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("Graphical display required for native screenshot capture")
		quit(1)
		return
	var dir_result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	_verify(dir_result == OK, "Output screenshot folder exists")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	for resolution in SIZES:
		DisplayServer.window_set_size(resolution)
		root.size = resolution
		root.content_scale_size = resolution
		await process_frame
		var panel := SCENE.instantiate() as Control
		root.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		panel.set_context({
			"teacher_authorized": true,
			"database_connected": true,
			"database_loading": false,
			"leaderboard_rows": [],
		})
		for _frame in range(4):
			await process_frame
		await RenderingServer.frame_post_draw
		var baseline := root.get_texture().get_image()
		panel.set_transfer_status(IMPORT_TEXT, false)
		await _capture("NOTICE_Import_%dx%d.png" % [resolution.x, resolution.y], resolution, baseline)
		# Replace the notice message using the same public status entry point.
		# The long message verifies multiline formatting and button clearance.
		panel.set_transfer_status(DELETE_TEXT, false)
		await _capture("NOTICE_DeleteWarning_%dx%d.png" % [resolution.x, resolution.y], resolution, baseline)
		panel.queue_free()
		await process_frame
		await process_frame
	print("ILLUSTRATED LEADERBOARD NOTICE: %s checks=%d failures=%d screenshots=%d database_writes=0" % [
		"PASS" if errors.is_empty() else "FAIL", checks, errors.size(), captured.size()
	])
	quit(0 if errors.is_empty() else 1)
