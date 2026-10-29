extends SceneTree

# Godot 4.7.2 --path . --rendering-method gl_compatibility --script res://tools/test_game_chooser_redesign_visual.gd
# Captures 16:9 states without invoking any camera or database code.
const SCENE := preload("res://ui/play/activity/play_activity.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const SELECTED_NAME := ["Catch the Word", "Human Plane", "Balloon Popping"]
const OUTPUT_PREFIX := "user://_qa_chooser_"

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for i in range(SIZES.size()):
		var dimensions: Vector2i = SIZES[i]
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(dimensions)
		root.content_scale_size = dimensions
		root.size = dimensions
		var panel := SCENE.instantiate() as Control
		root.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		_check_reference_layout(panel, dimensions)
		await _capture(panel, dimensions, "default")
		_assert((panel.get_node("LayoutMargins/Content/Footer/NextButton") as Button).disabled,
			"%s default Next disabled" % dimensions)
		var activity: String = SELECTED_NAME[i]
		(panel.get("activity_buttons")[activity] as Button).pressed.emit()
		await _capture(panel, dimensions, activity.to_lower().replace(" ", "_"))
		_assert(not (panel.get_node("LayoutMargins/Content/Footer/NextButton") as Button).disabled,
			"%s selected Next enabled" % dimensions)
		panel.queue_free()
		await process_frame
		await process_frame
	print("GAME CHOOSER GUI: %s (%d checks, %d failures)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_reference_layout(panel: Control, dimensions: Vector2i) -> void:
	var width := float(dimensions.x)
	var height := float(dimensions.y)
	var root_path := "LayoutMargins/Content/"
	var heading := panel.get_node(root_path + "Header/ChooseActivityArtwork") as Control
	var instruction := panel.get_node(root_path + "Header/InstructionArtwork") as Control
	var options := panel.get_node(root_path + "GameRow/GameOptions") as Control
	var preview := panel.get_node(root_path + "GameRow/GameDetail") as Control
	var back := panel.get_node(root_path + "Footer/BackButton") as Button
	var next := panel.get_node(root_path + "Footer/NextButton") as Button
	var heading_box := heading.get_global_rect()
	var instruction_box := instruction.get_global_rect()
	var options_box := options.get_global_rect()
	var preview_box := preview.get_global_rect()
	var back_box := back.get_global_rect()
	var next_box := next.get_global_rect()

	_assert(heading_box.position.x < width * 0.045
		and heading_box.end.x < width * 0.55
		and heading_box.end.y < height * 0.29,
		"%s title occupies top-left reference area" % dimensions)
	_assert(instruction_box.position.x > width * 0.65
		and instruction_box.position.y >= 0
		and instruction_box.end.y < height * 0.20
		and heading_box.end.x < instruction_box.position.x,
		"%s instruction occupies separate top-right reference area" % dimensions)
	_assert(options_box.position.x < width * 0.05
		and options_box.position.y > height * 0.16
		and options_box.position.y < height * 0.22
		and options_box.end.x < width * 0.43
		and options_box.end.y < height * 0.94,
		"%s options board fills left middle area" % dimensions)
	_assert(preview_box.position.x > width * 0.32
		and preview_box.position.x < width * 0.41
		and preview_box.position.y < height * 0.20
		and preview_box.size.y > height * 0.70,
		"%s preview fills middle-right with no empty upper-right" % dimensions)
	_assert(back_box.position.y > height * 0.85
		and next_box.position.y > height * 0.85
		and back_box.end.x < options_box.end.x
		and next_box.position.x > preview_box.position.x
		and back_box.end.x < next_box.position.x,
		"%s Back and Next remain separate bottom corner controls" % dimensions)
	var buttons: Dictionary = panel.get("activity_buttons")
	for activity in buttons:
		var button: Button = buttons[activity]
		_assert(button.get_global_rect().end.x < preview_box.position.x
			and button.get_global_rect().end.y < back_box.position.y,
			"%s %s never overlaps preview or bottom navigation" % [dimensions, activity])

func _capture(panel: Control, dimensions: Vector2i, state: String) -> void:
	for _i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var filename := "%s%dx%d_%s.png" % [OUTPUT_PREFIX, dimensions.x, dimensions.y, state]
	var snapshot := root.get_texture().get_image()
	_assert(snapshot.get_width() >= dimensions.x and snapshot.get_height() >= dimensions.y,
		"%s framebuffer matches window dimensions" % filename)
	_assert(snapshot.save_png(filename) == OK, "GPU screenshot saved: " + filename)
	print("GUI ", filename)

func _assert(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("FAIL chooser GUI: " + description)
