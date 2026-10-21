extends Control

signal requested(target: String, payload: Dictionary)

const TITLE_FONT := preload("res://assets/fonts/TitanOne-Regular.ttf")
const CREAM := Color("#F7E6BD")
const INK := Color("#494463")
const MINT := Color("#00886B")
const RED := Color("#FF4F66")
const YELLOW := Color("#FFC23D")
const BLUE := Color("#7BC9EF")
const PURPLE := Color("#C171CF")
const PANEL := Color("#F7E6BDF2")
const LANE_NAMES := ["LEFT", "CENTER", "RIGHT"]
const LANE_COLORS := [PURPLE, MINT, BLUE]
const DEMO_SEQUENCE := [1, 0, 1, 2]
const ART := preload("res://ui/tutorial/tutorial_theme.gd")

var context: Dictionary = {}
var demo_index := -1
var lane_panels: Array[Control] = []
var lane_labels: Array[Label] = []
var lane_hints: Array[Label] = []
var instruction_label: Label
var progress_label: Label
var demo_button: Button
var player_label: Label
var outer_margin: MarginContainer
var live_step := 0
var capturing_live := false
var live_samples: Array[float] = []
var last_packet_sequence := -1
var measured_points: Dictionary = {}
var continue_button: Button
var live_timer := 0.0
var anchor_x := -1.0
var guide_cursor: ColorRect
var camera_inset: TextureRect
var passing_to_ready := false
const CAPTURE_ORDER := ["CENTER", "RIGHT", "LEFT"]
const HOLD_SECONDS := 5.0
const REQUIRED_SAMPLES := 8
const MAX_SAMPLE_SPREAD := 0.095

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var stage := get_node_or_null("TutorialStage") as Control
	if stage != null:
		_bind_scene_nodes(stage)
	else:
		_build_redesign()
	_setup_live_calibration()

func _bind_scene_nodes(stage: Control) -> void:
	player_label = stage.get_node_or_null("PlayerLabel") as Label
	_refresh_player_label()
	lane_panels = [
		stage.get_node_or_null("LeftCalibrationLane") as Control,
		stage.get_node_or_null("CenterCalibrationLane") as Control,
		stage.get_node_or_null("RightCalibrationLane") as Control
	]
	lane_labels = [
		stage.get_node_or_null("LeftCalibrationLane/LeftName") as Label,
		stage.get_node_or_null("CenterCalibrationLane/CenterName") as Label,
		stage.get_node_or_null("RightCalibrationLane/RightName") as Label
	]
	lane_hints = [
		stage.get_node_or_null("LeftCalibrationLane/LeftHint") as Label,
		stage.get_node_or_null("CenterCalibrationLane/CenterHint") as Label,
		stage.get_node_or_null("RightCalibrationLane/RightHint") as Label
	]
	instruction_label = stage.get_node_or_null("InstructionLabel") as Label
	progress_label = stage.get_node_or_null("ProgressLabel") as Label
	var back := stage.get_node_or_null("BackButton") as Button
	if back:
		back.pressed.connect(_request.bind("camera_check", {"preview_mode": true, "camera_live": false}))
	demo_button = stage.get_node_or_null("DemoButton") as Button
	if demo_button:
		demo_button.pressed.connect(_capture_or_demo_step)
		demo_button.call_deferred("grab_focus")
	var retry := stage.get_node_or_null("RetryButton") as Button
	if retry:
		retry.pressed.connect(_retry_calibration)
		retry.text = "RESET PLAYER"
	var skip := stage.get_node_or_null("SkipButton") as Button
	if skip:
		skip.pressed.connect(_continue_flow.bind(true))
	var next := stage.get_node_or_null("ContinueButton") as Button
	if next:
		next.pressed.connect(_continue_flow.bind(false))
		continue_button = next
	resized.connect(func() -> void: ART.fit(self, stage))
	ART.fit(self, stage)

func set_context(value: Dictionary) -> void:
	context = value.duplicate(true)
	_refresh_player_label()
	_try_start_camera()


func _setup_live_calibration() -> void:
	PoseService.status_updated.connect(_on_pose_status)
	# Do not open a device when a scene is inspected by the editor or a
	# screenshot test. The host passes camera_requested through set_context
	# once a student actively enters the camera-play path.
	var stage := get_node_or_null("TutorialStage") as Control
	if stage:
		var title := stage.get_node_or_null("Heading") as Label
		var subtitle := stage.get_node_or_null("Description") as Label
		var badge := stage.get_node_or_null("BadgeLabel") as Label
		if title:
			title.text = "AUTO BODY CALIBRATION"
		if subtitle:
			subtitle.text = "Follow the highlighted stop zones: CENTER, then RIGHT, then LEFT."
		if badge:
			badge.text = "YOLO26 • CAMERA ON" if PoseService.active else "CAMERA UNAVAILABLE"
		_build_simple_live_guide(stage)
	demo_button.visible = true
	demo_button.text = "STOP CAMERA" if PoseService.active else "RETRY CAMERA"
	if is_instance_valid(continue_button):
		continue_button.disabled = true
	_set_live_instruction("Stand in CENTER to lock the active player. Others may remain in the background.")
	PoseService.preview_updated.connect(_on_live_preview)
	set_process(PoseService.active)


func _try_start_camera() -> void:
	if not is_inside_tree() or not bool(context.get("camera_requested", false)):
		return
	if not PoseService.active and not bool(context.get("keyboard_mode", false)):
		PoseService.start_camera()
	if is_instance_valid(demo_button):
		demo_button.text = "STOP CAMERA" if PoseService.active else "RETRY CAMERA"
	set_process(PoseService.active)


func _build_simple_live_guide(stage: Control) -> void:
	# The existing three large panels are the position boxes. The moving bar
	# shows what YOLO sees and makes the intended stop location obvious.
	var bar := ColorRect.new()
	bar.position = Vector2(92, 423)
	bar.size = Vector2(937, 13)
	bar.color = Color("#1B3242")
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(bar)
	guide_cursor = ColorRect.new()
	guide_cursor.color = Color("#FFFFFF")
	guide_cursor.size = Vector2(15, 27)
	guide_cursor.position = Vector2(92, 416)
	guide_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(guide_cursor)
	guide_cursor.visible = false
	# Live video inset gives an immediate visual reference without replacing
	# or damaging the supplied original art and native button hitboxes.
	camera_inset = TextureRect.new()
	camera_inset.position = Vector2(456, 227)
	camera_inset.size = Vector2(208, 118)
	camera_inset.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	camera_inset.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	camera_inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camera_inset.visible = false
	stage.add_child(camera_inset)
	if PoseService.preview_texture != null:
		_on_live_preview(PoseService.preview_texture)
	_update_target_guide()


func _on_live_preview(texture: Texture2D) -> void:
	if is_instance_valid(camera_inset):
		camera_inset.texture = texture
		camera_inset.visible = true


func _update_target_guide() -> void:
	var target_index: int = int([1, 2, 0][mini(live_step, 2)])
	for i in range(lane_panels.size()):
		var target := i == target_index and live_step < CAPTURE_ORDER.size()
		lane_panels[i].add_theme_stylebox_override("panel", _lane_style(LANE_COLORS[i], target))
		lane_labels[i].text = ("STOP HERE • " if target else "") + LANE_NAMES[i]
		if target:
			lane_hints[i].text = "HOLD STILL FOR 5 SECONDS"
		elif measured_points.has(LANE_NAMES[i].to_lower()):
			lane_hints[i].text = "DONE ✓"
		else:
			lane_hints[i].text = "WAIT"


func _capture_or_demo_step() -> void:
	# The old CAPTURE button is now an always-visible emergency camera stop /
	# retry action. Captures themselves occur without any button press.
	if PoseService.active:
		PoseService.stop_camera()
		_reset_live_samples()
		_set_live_instruction("Camera stopped. Choose SKIP for keyboard or RETRY CAMERA.")
		set_process(false)
	else:
		PoseService.start_camera()
		_reset_live_samples()
		demo_button.text = "STOP CAMERA" if PoseService.active else "RETRY CAMERA"
		set_process(PoseService.active)


func _process(delta: float) -> void:
	if not PoseService.active:
		_set_live_instruction("Camera unavailable. Check permissions, or choose SKIP for keyboard gameplay.")
		return
	if is_instance_valid(guide_cursor):
		guide_cursor.visible = PoseService.has_valid_pose()
		if guide_cursor.visible:
			guide_cursor.position.x = 92.0 + clampf(PoseService.player_x, 0.0, 1.0) * 922.0
	if live_step >= CAPTURE_ORDER.size():
		return
	if not PoseService.has_valid_pose():
		_reset_current_hold()
		var lock_state := String(PoseService.current_status.get("lock_state", ""))
		if lock_state == "lost":
			_set_live_instruction("PLAYER LOCK LOST. Press RESET PLAYER; classmates will not take over.")
		else:
			_set_live_instruction(String(PoseService.current_status.get("detail", "Stand in CENTER to select a player.")))
		return
	var x := PoseService.player_x
	var target: String = String(CAPTURE_ORDER[live_step])
	var inside_zone := false
	if target == "CENTER":
		inside_zone = absf(x - 0.5) <= 0.19
	elif target == "RIGHT":
		inside_zone = x >= float(measured_points.get("center", 0.5)) + 0.12
	else:
		inside_zone = x <= float(measured_points.get("center", 0.5)) - 0.12
	if not inside_zone:
		_reset_current_hold()
		_set_live_instruction("MOVE TO %s • Follow the highlighted box; wait until you enter its zone." % target)
		return
	if anchor_x < 0.0:
		anchor_x = x
		live_timer = 0.0
		live_samples.clear()
		last_packet_sequence = -1
	if absf(x - anchor_x) > MAX_SAMPLE_SPREAD:
		_reset_current_hold()
		_set_live_instruction("Too much movement. Stop inside the %s box for 5 seconds." % target)
		return
	if PoseService.packet_sequence != last_packet_sequence:
		last_packet_sequence = PoseService.packet_sequence
		live_samples.append(x)
	live_timer += delta
	var remaining := maxi(0, ceili(HOLD_SECONDS - live_timer))
	progress_label.text = "%s • HOLD: %d seconds • %d fresh pose frames" % [target, remaining, live_samples.size()]
	_set_live_instruction("STAY ON %s FOR %d SECONDS • Hold still until the next zone lights up." % [target, remaining])
	if live_timer < HOLD_SECONDS or live_samples.size() < REQUIRED_SAMPLES:
		return
	var sum := 0.0
	for number in live_samples:
		sum += number
	var average := sum / float(live_samples.size())
	measured_points[target.to_lower()] = average
	live_step += 1
	_reset_current_hold()
	_update_target_guide()
	if live_step < CAPTURE_ORDER.size():
		_set_live_instruction("%s saved (%.3f). MOVE TO %s and stop for 5 seconds." % [
			CAPTURE_ORDER[live_step - 1], average, CAPTURE_ORDER[live_step]
		])
		return
	var good := PoseService.set_calibration(
		float(measured_points["left"]), float(measured_points["center"]), float(measured_points["right"])
	)
	if good:
		if is_instance_valid(continue_button):
			continue_button.disabled = false
		_update_target_guide()
		_set_live_instruction("SUCCESS • Range %.3f–%.3f, center %.3f. Live movement test complete." % [
			float(measured_points["left"]), float(measured_points["right"]), float(measured_points["center"])
		])
		progress_label.text = "CALIBRATED • 3 zones measured using YOLO26; no images stored."
		_set_live_instruction("Calibration complete! Starting the next screen automatically in 2 seconds.")
		call_deferred("_advance_after_calibration")
	else:
		_set_live_instruction("Range invalid or CENTER outside bounds. Retry, using wider LEFT/RIGHT movements.")
		_reset_live_samples()


func _advance_after_calibration() -> void:
	await get_tree().create_timer(2.0).timeout
	if not is_inside_tree():
		return
	if not PoseService.active or not PoseService.has_valid_pose():
		_set_live_instruction("Player lost after calibration. Stand in view, then press CONTINUE.")
		return
	if not bool(PoseService.calibration.get("valid", false)):
		return
	_continue_flow(false)


func _reset_current_hold() -> void:
	live_timer = 0.0
	anchor_x = -1.0
	live_samples.clear()
	last_packet_sequence = -1


func _on_pose_status(data: Dictionary) -> void:
	if is_instance_valid(player_label):
		if PoseService.has_valid_pose():
			player_label.text = "YOLO26 %s • CAM %.1f FPS • POSE %.1f FPS • X %.3f" % [
				String(data.get("device", "")), float(data.get("camera_fps", 0.0)),
				float(data.get("fps", 0.0)), PoseService.player_x
			]
		else:
			player_label.text = "YOLO26 • %s" % String(data.get("detail", "WAITING FOR ONE PLAYER")).to_upper().left(86)


func _set_live_instruction(message: String) -> void:
	if is_instance_valid(instruction_label):
		instruction_label.text = message


func _reset_live_samples() -> void:
	live_step = 0
	measured_points.clear()
	_reset_current_hold()
	PoseService.calibration.clear()
	if is_instance_valid(demo_button):
		demo_button.visible = true
		demo_button.text = "STOP CAMERA" if PoseService.active else "RETRY CAMERA"
	if is_instance_valid(continue_button):
		continue_button.disabled = true
	_update_target_guide()
	progress_label.text = "AUTO • CENTER 5s → RIGHT 5s → LEFT 5s"


func _exit_tree() -> void:
	if PoseService.status_updated.is_connected(_on_pose_status):
		PoseService.status_updated.disconnect(_on_pose_status)
	if PoseService.preview_updated.is_connected(_on_live_preview):
		PoseService.preview_updated.disconnect(_on_live_preview)
	if PoseService.active and not passing_to_ready:
		PoseService.stop_camera()


func _build_redesign() -> void:
	var stage := ART.prepare(self, "CALIBRATION PREVIEW", "Try the suggested LEFT, CENTER and RIGHT zones with simulated movement steps.", "DEMO • NOT MEASURED")
	player_label = ART.label(stage, "PLAYER: DEMO PREVIEW  •  LANES ARE NOT MEASURED", Rect2(80, 145, 944, 28), 15, ART.INK)
	_refresh_player_label()
	for i in range(3):
		var x := 92.0 + i * 331.0
		var lane := PanelContainer.new()
		lane.name = LANE_NAMES[i] + "CalibrationLane"
		lane.position = Vector2(x, 186)
		lane.size = Vector2(275, 245)
		lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lane.add_theme_stylebox_override("panel", _lane_style(LANE_COLORS[i], false))
		stage.add_child(lane)
		lane_panels.append(lane)
		if i == 1:
			ART.icon(stage, ART.TUTORIAL_ART + "icon_calibration.png", Rect2(x + 89, 199, 98, 93))
		else:
			ART.label(stage, ["←", "", "→"][i], Rect2(x + 17, 202, 241, 85), 56, ART.CREAM)
		var name := ART.label(stage, LANE_NAMES[i], Rect2(x + 15, 293, 245, 43), 25, ART.CREAM)
		lane_labels.append(name)
		var hint := ART.label(stage, ["Player moves left", "Player starts here", "Player moves right"][i], Rect2(x + 11, 351, 251, 42), 13, ART.CREAM)
		lane_hints.append(hint)
	instruction_label = ART.label(stage, "Start at CENTER. Select TEST STEP to preview a future calibration sequence.", Rect2(81, 443, 966, 31), 16, ART.INK)
	progress_label = ART.label(stage, "Calibration status: NOT MEASURED  •  Demo step 0 / 4", Rect2(111, 477, 888, 28), 14, ART.INK)
	var back := ART.button(stage, "BACK", Rect2(61, 539, 190, 57), ART.PURPLE, 16)
	back.pressed.connect(_request.bind("camera_check", {"preview_mode": true, "camera_live": false}))
	demo_button = ART.button(stage, "TEST STEP • DEMO", Rect2(272, 539, 210, 57), ART.YELLOW, 15)
	demo_button.pressed.connect(_capture_or_demo_step)
	var retry := ART.button(stage, "RETRY PREVIEW", Rect2(502, 539, 203, 57), ART.BLUE, 15)
	retry.pressed.connect(_retry_calibration)
	var skip := ART.button(stage, "SKIP", Rect2(727, 539, 137, 57), ART.RED, 16)
	skip.pressed.connect(_continue_flow.bind(true))
	var next := ART.button(stage, "CONTINUE", Rect2(884, 539, 172, 57), ART.GREEN, 16)
	next.pressed.connect(_continue_flow.bind(false))
	continue_button = next
	demo_button.call_deferred("grab_focus")

func _build_ui() -> void:
	outer_margin = MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(outer_margin)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_style(PANEL, 28, 8))
	outer_margin.add_child(card)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 40)
	pad.add_theme_constant_override("margin_right", 40)
	pad.add_theme_constant_override("margin_top", 24)
	pad.add_theme_constant_override("margin_bottom", 24)
	card.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 11)
	pad.add_child(column)
	column.add_child(_label("CALIBRATION PREVIEW", 34, INK, HORIZONTAL_ALIGNMENT_CENTER))
	column.add_child(_label("TRACKING NOT CONNECTED  •  DEMO ONLY", 14, RED, HORIZONTAL_ALIGNMENT_CENTER))
	player_label = _label("PLAYER: DEMO PREVIEW", 14, INK, HORIZONTAL_ALIGNMENT_CENTER)
	player_label.modulate.a = 0.78
	column.add_child(player_label)
	column.add_child(_label("Each player will get LEFT, CENTER, and RIGHT movement zones after camera integration. This screen only previews that flow.", 14, INK, HORIZONTAL_ALIGNMENT_CENTER))

	var lane_row := HBoxContainer.new()
	lane_row.add_theme_constant_override("separation", 14)
	lane_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(lane_row)
	for i in range(3):
		var lane := PanelContainer.new()
		lane.custom_minimum_size = Vector2(0, 220)
		lane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lane.add_theme_stylebox_override("panel", _lane_style(LANE_COLORS[i], false))
		lane_row.add_child(lane)
		lane_panels.append(lane)
		var box := VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 8)
		lane.add_child(box)
		var symbol: String = ["←", "●", "→"][i]
		box.add_child(_label(symbol, 52, CREAM, HORIZONTAL_ALIGNMENT_CENTER))
		var lane_label := _label(LANE_NAMES[i], 22, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
		lane_labels.append(lane_label)
		box.add_child(lane_label)
		var lane_hint_text: String = ["Player moves left", "Player starts here", "Player moves right"][i]
		var lane_hint := _label(lane_hint_text, 12, CREAM, HORIZONTAL_ALIGNMENT_CENTER)
		lane_hints.append(lane_hint)
		box.add_child(lane_hint)

	instruction_label = _label("Start in CENTER. Press TEST STEP to preview a per-player calibration sequence.", 15, INK, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(instruction_label)
	progress_label = _label("Calibration status: NOT MEASURED  •  Demo step 0 / 4", 13, INK, HORIZONTAL_ALIGNMENT_CENTER)
	column.add_child(progress_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	var back := _button("BACK", INK, 130)
	back.pressed.connect(_request.bind("camera_check", {"preview_mode": true, "camera_live": false}))
	actions.add_child(back)
	demo_button = _button("TEST STEP • DEMO", YELLOW, 180)
	demo_button.pressed.connect(_capture_or_demo_step)
	actions.add_child(demo_button)
	var retry := _button("RETRY CALIBRATION", BLUE, 190)
	retry.tooltip_text = "Reset the UI-only calibration preview"
	retry.pressed.connect(_retry_calibration)
	actions.add_child(retry)
	var skip := _button("SKIP", RED, 115)
	skip.pressed.connect(_continue_flow.bind(true))
	actions.add_child(skip)
	var next := _button("CONTINUE", MINT, 160)
	next.pressed.connect(_continue_flow.bind(false))
	actions.add_child(next)
	continue_button = next
	demo_button.call_deferred("grab_focus")

func _run_demo_step() -> void:
	demo_index = (demo_index + 1) % DEMO_SEQUENCE.size()
	var active_index: int = DEMO_SEQUENCE[demo_index]
	for i in range(lane_panels.size()):
		lane_panels[i].add_theme_stylebox_override("panel", _lane_style(LANE_COLORS[i], i == active_index))
		lane_labels[i].text = ("★ " if i == active_index else "") + LANE_NAMES[i]
		lane_hints[i].text = "DEMO PLAYER HERE" if i == active_index else ["Player moves left", "Player starts here", "Player moves right"][i]
	instruction_label.text = "DEMO STEP: Move to %s. The highlighted lane is UI animation only." % LANE_NAMES[active_index]
	progress_label.text = "Calibration status: NOT MEASURED  •  Demo step %d / %d" % [demo_index + 1, DEMO_SEQUENCE.size()]
	if demo_index == DEMO_SEQUENCE.size() - 1:
		instruction_label.text = "Preview complete. No camera data, pose, or lane measurements were captured."
		demo_button.text = "REPLAY DEMO"

func _retry_calibration() -> void:
	if bool(context.get("camera_requested", false)) or PoseService.active:
		# A new camera/YOLO worker clears the old temporary track ID.
		# Restart is explicit; never reassign an identity during a round.
		PoseService.stop_camera()
		PoseService.start_camera()
		_reset_live_samples()
		set_process(PoseService.active)
		_set_live_instruction("Player lock reset. Stand near the camera in CENTER for enrollment.")
		return
	demo_index = -1
	for i in range(lane_panels.size()):
		lane_panels[i].add_theme_stylebox_override("panel", _lane_style(LANE_COLORS[i], false))
		lane_labels[i].text = LANE_NAMES[i]
		lane_hints[i].text = ["Player moves left", "Player starts here", "Player moves right"][i]
	instruction_label.text = "Calibration preview reset. Start in CENTER and press TEST STEP when ready."
	progress_label.text = "Calibration status: NOT MEASURED  •  Demo step 0 / 4"
	demo_button.text = "TEST STEP • DEMO"
	demo_button.grab_focus()

func _continue_flow(skipped: bool) -> void:
	var live_measured := PoseService.active and bool(PoseService.calibration.get("valid", false))
	if not skipped and PoseService.active and not live_measured:
		_set_live_instruction("Complete CENTER, LEFT, RIGHT first, or choose SKIP for keyboard play.")
		return
	var entry_source := String(context.get("entry_source", "play"))
	var target := "tutorial_practice" if entry_source == "tutorial" else "ready"
	var payload := {
		"preview_mode": not live_measured,
		"camera_live": false, # Gameplay is still keyboard-only in this milestone.
		"calibration_live": live_measured and not skipped,
		"calibration_measured": live_measured and not skipped,
		"from_calibration": true,
		"calibration_skipped": skipped,
		"calibration_previewed": demo_index >= 0
	}
	if live_measured and not skipped:
		payload["calibration_left"] = PoseService.calibration["left"]
		payload["calibration_center"] = PoseService.calibration["center"]
		payload["calibration_right"] = PoseService.calibration["right"]
	# Preserve the process across Ready -> Gameplay, but never after SKIP.
	passing_to_ready = target == "ready" and live_measured and not skipped
	requested.emit(target, payload)

func _request(target: String, payload: Dictionary) -> void:
	requested.emit(target, payload)

func _refresh_player_label() -> void:
	if not is_instance_valid(player_label):
		return
	var display_name := "DEMO PREVIEW"
	for key in ["name", "student_name", "player_name"]:
		var candidate := String(context.get(key, "")).strip_edges()
		if not candidate.is_empty():
			display_name = candidate.to_upper()
			break
	player_label.text = "PLAYER: " + display_name + "  •  LANES ARE NOT MEASURED"

func _apply_responsive_layout() -> void:
	if not is_instance_valid(outer_margin):
		return
	var horizontal_margin := int(clampf(size.x * 0.055, 52.0, 112.0))
	var vertical_margin := int(clampf(size.y * 0.050, 30.0, 62.0))
	outer_margin.add_theme_constant_override("margin_left", horizontal_margin)
	outer_margin.add_theme_constant_override("margin_right", horizontal_margin)
	outer_margin.add_theme_constant_override("margin_top", vertical_margin)
	outer_margin.add_theme_constant_override("margin_bottom", vertical_margin)
	var lane_height := clampf(size.y * 0.29, 195.0, 305.0)
	for lane in lane_panels:
		lane.custom_minimum_size.y = lane_height

func _label(text_value: String, font_size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font", TITLE_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _button(text_value: String, color: Color, width: float) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(width, 52)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", TITLE_FONT)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_hover_color", CREAM)
	button.add_theme_stylebox_override("normal", _panel_style(color, 13, 4))
	button.add_theme_stylebox_override("hover", _panel_style(color.lightened(0.08), 13, 6))
	button.add_theme_stylebox_override("pressed", _panel_style(color.darkened(0.08), 13, 2))
	button.add_theme_stylebox_override("focus", _focus_style())
	return button

func _lane_style(color: Color, active: bool) -> StyleBoxFlat:
	var style := _panel_style(color if active else color.darkened(0.05), 22, 8 if active else 4)
	style.border_width_left = 5 if active else 2
	style.border_width_top = 5 if active else 2
	style.border_width_right = 5 if active else 2
	style.border_width_bottom = 5 if active else 2
	style.border_color = CREAM if active else Color(CREAM.r, CREAM.g, CREAM.b, 0.5)
	return style

func _panel_style(color: Color, radius: int, shadow: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(INK.r, INK.g, INK.b, 0.34)
	style.shadow_size = shadow
	style.shadow_offset = Vector2(4, 6)
	return style

func _focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = CREAM
	style.corner_radius_top_left = 13
	style.corner_radius_top_right = 13
	style.corner_radius_bottom_left = 13
	style.corner_radius_bottom_right = 13
	return style
