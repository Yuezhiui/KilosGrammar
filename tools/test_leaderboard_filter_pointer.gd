extends SceneTree

# Direct viewport pointer dispatch, not calling handlers or emitting pressed.
# FILTERS is now deleted entirely; exercise the three remaining native controls.
const SCENE := preload("res://ui/secondary/leaderboard.tscn")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for viewport in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = viewport
		root.content_scale_size = viewport
		var board := SCENE.instantiate() as Control
		root.add_child(board)
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		for missing in ["FiltersToggle", "FiltersArt", "MoreFiltersPanel", "CloseMoreFilters"]:
			if board.find_child(missing, true, false) != null:
				_failed("Obsolete FILTERS UI still exists: " + missing, viewport)
		for name in ["StyleFilter", "ModeFilter", "DifficultyFilter"]:
			var dropdown := board.get_node("%" + name) as OptionButton
			if not dropdown.is_visible_in_tree() or dropdown.focus_mode != Control.FOCUS_ALL:
				_failed("Visible native dropdown lost: " + name, viewport)
				continue
			var popup := dropdown.get_popup()
			_click(dropdown.get_global_rect().get_center())
			await process_frame
			if not popup.visible:
				_failed("Real mouse click did not open " + name + " popup", viewport)
			popup.hide()
			await process_frame
		if board.get_node("%MinigameFilter").is_visible_in_tree() or board.get_node("%DownloadButton").is_visible_in_tree():
			_failed("Hidden advanced controls leaked into pointer layout", viewport)
		board.queue_free()
		await process_frame
	print("LEADERBOARD POINTER QA: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	quit(0 if failures == 0 else 1)

func _click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	press.global_position = at
	root.push_input(press, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = at
	release.global_position = at
	root.push_input(release, true)

func _failed(reason: String, viewport: Vector2i) -> void:
	failures += 1
	printerr("FAIL ", viewport, ": ", reason)
