extends Control

signal requested(target: String, payload: Dictionary)

# One shared, full-screen camera calibration for Tutorial and ordinary Play.
# PoseService owns the actual camera, player lock, measurements and video.
# The complete visible layout is editable in calibration.tscn.
const ART := preload("res://ui/tutorial/tutorial_theme.gd")
const DESIGN_SIZE := Vector2(1280.0, 720.0)
const CAPTURE_ORDER := ["CENTER", "RIGHT", "LEFT"]
const INTRO_SECONDS := 2.5
const HOLD_SECONDS := 3.0
const REQUIRED_SAMPLES := 8
const MAX_SAMPLE_SPREAD := 0.095
const MAX_PACKET_GAP_SECONDS := 0.7
const ZONE_CENTER_RADIUS := 0.16
const ZONE_RIGHT_START := 0.68
const ZONE_LEFT_END := 0.32

const STAGE_TEXT := {
	"CENTER": ["STAY IN THE CENTER", "MANATILI SA GITNA"],
	"RIGHT": ["MOVE TO THE RIGHT", "GUMALAW SA KANAN"],
	"LEFT": ["MOVE TO THE LEFT", "GUMALAW SA KALIWA"]
}

var context: Dictionary = {}
var camera_entry_requested := false
var lane_panels: Array[Control] = []
var lane_labels: Array[Label] = []
var lane_hints: Array[Label] = []
var instruction_label: Label
var instruction_en: Label
var instruction_fil: Label
var countdown_label: Label
var progress_label: Label
var player_label: Label
var status_label: Label
var stage_heading: Label
var step_badge: Label
var plane_step_badge: Control
var badge_label: Label
var continue_button: Button
var intro_overlay: Control
var intro_countdown: Label
var intro_back_button: Button
var back_main_button: Button
var intro_stage_visibility: Dictionary = {}
var camera_unavailable: Label
var guide_bar: Control
var guide_cursor: Control
var camera_inset: TextureRect
var skeleton_placement: ReferenceRect
# Supplied CALIB artwork stays in independently movable .tscn TextureRects.
# These UI nodes never become children of the camera texture or get painted
# into JPEG preview pixels by the Python pose worker.
var art_title_nodes: Dictionary = {}
var art_guide_nodes: Dictionary = {}
var art_arrow_nodes: Dictionary = {}
var art_hint_nodes: Dictionary = {}
var art_step_nodes: Array[Control] = []
var art_countdown_nodes: Array[Control] = []

var intro_elapsed := 0.0
var intro_running := true
var live_step := 0
var live_timer := 0.0
var live_samples: Array[float] = []
var last_packet_sequence := -1
var packet_gap_seconds := 0.0
var anchor_x := -1.0
var measured_points: Dictionary = {}
var passing_to_ready := false # Camera ownership passes to gameplay on success.
var transition_queued := false
var transition_generation := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var stage := get_node_or_null("TutorialStage") as Control
	if stage == null:
		push_error("Calibration requires an editor-authored TutorialStage.")
		return
	_bind_scene_nodes(stage)
	resized.connect(_fit_stage)
	_fit_stage()
	PoseService.status_updated.connect(_on_pose_status)
	PoseService.preview_updated.connect(_on_live_preview)
	# If a camera session arrives with an already-valid measurement (e.g. a
	# navigation return), preserve the device calibration until the user
	# explicitly resets, stops or re-measures it.
	_reset_live_samples(false)
	_refresh_player_label()
	_refresh_camera_status()
	# Only the intro's title, countdown and Back button may be visible during
	# the first 2.5 seconds. Store each direct child Control's authored state,
	# including editor-hidden legacy nodes, to restore it without geometry edits.
	_show_intro_only(stage)
	set_process(true) # Intro and status continue even while the camera is off.
	if is_instance_valid(intro_back_button):
		intro_back_button.call_deferred("grab_focus")


func _bind_scene_nodes(stage: Control) -> void:
	player_label = stage.get_node_or_null("PlayerLabel") as Label
	status_label = stage.get_node_or_null("CameraStatusLabel") as Label
	stage_heading = stage.get_node_or_null("StageHeading") as Label
	step_badge = stage.get_node_or_null("StepBadge") as Label
	plane_step_badge = stage.get_node_or_null("PlaneStepBadge") as Control
	badge_label = stage.get_node_or_null("BadgeLabel") as Label
	instruction_label = stage.get_node_or_null("InstructionLabel") as Label
	instruction_en = stage.get_node_or_null("InstructionEN") as Label
	instruction_fil = stage.get_node_or_null("InstructionFIL") as Label
	countdown_label = stage.get_node_or_null("CountdownLabel") as Label
	progress_label = stage.get_node_or_null("ProgressLabel") as Label
	guide_bar = stage.get_node_or_null("CalibrationGuideBar") as Control
	guide_cursor = stage.get_node_or_null("CalibrationGuideCursor") as Control
	camera_inset = stage.get_node_or_null("LiveCameraInset") as TextureRect
	skeleton_placement = stage.get_node_or_null("SkeletonPlacement") as ReferenceRect
	camera_unavailable = stage.get_node_or_null("CameraUnavailableLabel") as Label
	for zone in ["CENTER", "RIGHT", "LEFT"]:
		art_title_nodes[zone] = stage.get_node_or_null("ArtTitle" + zone.capitalize()) as Control
		art_guide_nodes[zone] = stage.get_node_or_null("ArtGuide" + zone.capitalize()) as Control
		art_arrow_nodes[zone] = stage.get_node_or_null("ArtArrow" + zone.capitalize()) as Control
		art_hint_nodes[zone] = stage.get_node_or_null("ArtMoveHint" + zone.capitalize()) as Control
	for index in range(1, 4):
		art_step_nodes.append(stage.get_node_or_null("ArtStep%d" % index) as Control)
		art_countdown_nodes.append(stage.get_node_or_null("ArtCountdown%d" % index) as Control)
	intro_overlay = stage.get_node_or_null("IntroOverlay") as Control
	intro_countdown = stage.get_node_or_null("IntroOverlay/IntroCountdown") as Label
	intro_back_button = stage.get_node_or_null("IntroOverlay/IntroBackButton") as Button
	back_main_button = stage.get_node_or_null("BackButton") as Button
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
	if back_main_button:
		back_main_button.pressed.connect(_go_back)
		back_main_button.disabled = false
		back_main_button.focus_mode = Control.FOCUS_ALL
	else:
		push_error("Calibration requires an editor-authored TutorialStage/BackButton.")
	if intro_back_button:
		intro_back_button.pressed.connect(_go_back)
		intro_back_button.disabled = false
		intro_back_button.focus_mode = Control.FOCUS_ALL
	continue_button = stage.get_node_or_null("ContinueButton") as Button
	if continue_button:
		continue_button.disabled = true
		# Progression happens only after three verified live holds.
		continue_button.visible = false
	if camera_inset:
		camera_inset.visible = false
	# The standing silhouettes in the camera are the sole position guides.
	# Keep the old marker nodes for scene compatibility, but don't draw them.
	if is_instance_valid(guide_bar):
		guide_bar.visible = false
	if is_instance_valid(guide_cursor):
		guide_cursor.visible = false
	if is_instance_valid(countdown_label):
		countdown_label.visible = false
	if is_instance_valid(instruction_en):
		# The main, large StageHeading owns the English command. Its smaller
		# authored English label is intentionally hidden to prevent duplicate
		# directions; Filipino remains visible immediately below the heading.
		instruction_en.visible = false
	for panel in lane_panels:
		if panel == null:
			push_error("Calibration zone missing from authored .tscn.")
	if is_instance_valid(intro_overlay):
		intro_overlay.visible = true


func _show_intro_only(stage: Control) -> void:
	intro_stage_visibility.clear()
	for child in stage.get_children():
		if child is Control and child != intro_overlay:
			var visual := child as Control
			intro_stage_visibility[visual] = visual.visible
			visual.visible = false
	if is_instance_valid(intro_overlay):
		# ClassroomDimmer is the sole designer-authored background tint. A
		# second dark intro fill would dim the new bright CALIB scene twice.
		if intro_overlay is ColorRect:
			var intro_color := (intro_overlay as ColorRect).color
			intro_color.a = 0.0
			(intro_overlay as ColorRect).color = intro_color
		var old_footer_mask := intro_overlay.get_node_or_null("IntroFooterMask") as Control
		if is_instance_valid(old_footer_mask):
			old_footer_mask.visible = false
		intro_overlay.visible = true


func _finish_intro_only() -> void:
	for saved_node in intro_stage_visibility:
		if is_instance_valid(saved_node):
			(saved_node as Control).visible = bool(intro_stage_visibility[saved_node])
	intro_stage_visibility.clear()
	if is_instance_valid(intro_overlay):
		intro_overlay.visible = false
	# A camera texture may have arrived while the footer and HUD were hidden.
	# Restore the real feed without restoring legacy/unused preview controls.
	if is_instance_valid(camera_inset):
		camera_inset.visible = PoseService.active and camera_inset.texture != null
	_refresh_camera_status()
	_update_target_guide()
	_set_stage_instruction()
	_sync_reference_art()
	# The intro deliberately hides *all* stage siblings. Never rely on
	# restoring a saved visible flag for navigation: a camera startup error or
	# an older serialized scene must not strand a student without Back to Main.
	# Its rectangle and art style are serialized in calibration.tscn, not set
	# or rebuilt at runtime.
	if is_instance_valid(back_main_button):
		back_main_button.visible = true
		back_main_button.disabled = false
		back_main_button.focus_mode = Control.FOCUS_ALL
		back_main_button.call_deferred("grab_focus")


func _fit_stage() -> void:
	var stage := get_node_or_null("TutorialStage") as Control
	if is_instance_valid(stage):
		ART.fit(self, stage, DESIGN_SIZE)


func set_context(value: Dictionary) -> void:
	var previous_activity := String(context.get("activity", ""))
	camera_entry_requested = not value.is_empty()
	context = value.duplicate(true)
	# Stale settings from previous menu routes must not enable keyboard play.
	context["keyboard_mode"] = false
	# set_context normally arrives during the introduction. If an existing
	# screen is repurposed after it, discard its previous activity's holds.
	if not intro_running and previous_activity != String(context.get("activity", "")):
		_reset_live_samples(false)
	_refresh_player_label()
	_try_start_camera()
	_refresh_camera_status()


func _is_human_plane() -> bool:
	return String(context.get("activity", "")).strip_edges() == "Human Plane"


func _capture_order() -> Array:
	# Every camera-driven game measures the student's actual travel limits.
	# Human Plane uses these same bounds to steer by body position.
	return CAPTURE_ORDER


func _try_start_camera() -> void:
	if not is_inside_tree() or not camera_entry_requested:
		return
	_apply_skeleton_placement()
	if not PoseService.active:
		PoseService.start_camera()
	_refresh_camera_status()


func _apply_skeleton_placement() -> void:
	# The teacher's native scene rectangle owns the green skeleton's visual
	# offset and size. These are normalized against LiveCameraInset; no stage
	# pixel values or coordinates are hardcoded in either runtime script.
	if is_instance_valid(camera_inset) and is_instance_valid(skeleton_placement) \
			and camera_inset.size.x > 0 and camera_inset.size.y > 0:
		var normalized_offset := (skeleton_placement.position - camera_inset.position) / camera_inset.size
		var normalized_scale := skeleton_placement.size / camera_inset.size
		PoseService.set_skeleton_visual_transform(normalized_offset, normalized_scale)


func _refresh_player_label() -> void:
	if not is_instance_valid(player_label):
		return
	var name := "STUDENT"
	for key in ["student_name", "name", "player_name"]:
		var candidate := String(context.get(key, "")).strip_edges()
		if not candidate.is_empty():
			name = candidate.to_upper()
			break
	player_label.text = "PLAYER: " + name


func _refresh_camera_status() -> void:
	var state := String(PoseService.current_status.get("state", "off"))
	if is_instance_valid(badge_label):
		badge_label.text = ("PLAYER TRACKING • YOLO26" if PoseService.has_valid_pose() else "CAMERA STARTING / SEARCHING") if PoseService.active else ("CAMERA ERROR" if state == "error" else "CAMERA OFF")
	if is_instance_valid(camera_unavailable):
		var feed_is_visible := PoseService.active and is_instance_valid(camera_inset) and camera_inset.texture != null
		camera_unavailable.visible = not feed_is_visible and not intro_running
		if not PoseService.active:
			camera_unavailable.text = "CAMERA UNAVAILABLE\nAsk your teacher to check the camera.\nWalang camera • Tawagin ang guro."
		else:
			camera_unavailable.text = "CONNECTING TO LIVE CAMERA\nPlease stand where the camera can see you."
	if is_instance_valid(status_label):
		if PoseService.has_valid_pose():
			status_label.text = "PLAYER FOUND • HOLD STILL"
		elif not PoseService.active:
			status_label.text = "CAMERA OFFLINE • TEACHER ASSISTANCE NEEDED"
		else:
			status_label.text = String(PoseService.current_status.get("detail", "Waiting for one student.")).left(78)


func _on_live_preview(texture: Texture2D) -> void:
	if not is_instance_valid(camera_inset):
		return
	camera_inset.texture = texture
	camera_inset.visible = not intro_running
	_refresh_camera_status()


func _on_pose_status(_data: Dictionary) -> void:
	_refresh_camera_status()


func _process(delta: float) -> void:
	var tracking_delta := maxf(delta, 0.0)
	if intro_running:
		intro_elapsed += tracking_delta
		if is_instance_valid(intro_countdown):
			intro_countdown.text = str(maxi(1, ceili(INTRO_SECONDS - intro_elapsed)))
		if intro_elapsed < INTRO_SECONDS:
			return
		# Never credit introduction time toward a student's stationary hold.
		tracking_delta = maxf(0.0, intro_elapsed - INTRO_SECONDS)
		intro_running = false
		_finish_intro_only()
	var capture_order := _capture_order()
	if live_step >= capture_order.size():
		# A temporary player loss after calibration must not strand
		# the student at a finished screen with Continue hidden. Automatically
		# retry the handoff when that same locked player is visible again.
		if not transition_queued and PoseService.active and PoseService.has_valid_pose() and bool(PoseService.calibration.get("valid", false)):
			transition_queued = true
			call_deferred("_advance_after_calibration", transition_generation)
		return
	if transition_queued:
		return
	if not PoseService.active:
		_reset_current_hold()
		_set_live_instruction("CAMERA UNAVAILABLE • Ask your teacher for assistance.\nWalang camera • Tawagin ang guro.")
		if is_instance_valid(progress_label):
			progress_label.text = "Walang camera • Tawagin ang guro."
		return
	if not PoseService.has_valid_pose():
		# Tracking loss interrupts the CURRENT hold, not previously measured
		# CENTER or RIGHT positions. Only a fresh continuous hold may advance.
		_reset_current_hold()
		var detail := String(PoseService.current_status.get("detail", "")).strip_edges()
		if detail.is_empty():
			detail = "We lost sight of you. Please step back into the camera view."
		# The live camera service explains the current condition, without
		# directing a child toward removed STOP/RESET/SKIP controls.
		if is_instance_valid(status_label):
			status_label.text = detail.left(78)
		if is_instance_valid(progress_label):
			progress_label.text = "Bumalik sa kamera at sa maliwanag na kahon."
		_set_live_instruction("%s\nBumalik sa kamera at sa maliwanag na kahon." % detail)
		return
	var x := PoseService.player_x
	var target: String = capture_order[live_step]
	if not _inside_zone(target, x):
		_reset_current_hold()
		_set_live_instruction("%s • %s\nPumuwesto sa maliwanag na kahon." % STAGE_TEXT[target])
		return
	if anchor_x < 0.0:
		anchor_x = x
		last_packet_sequence = -1
		live_samples.clear()
		live_timer = 0.0
		packet_gap_seconds = 0.0
	if absf(x - anchor_x) > MAX_SAMPLE_SPREAD:
		_reset_current_hold()
		_set_live_instruction("MOVEMENT DETECTED • Stop moving, then hold for 3 seconds.\nMay galaw • Huminto at manatili nang 3 segundo.")
		return
	if PoseService.packet_sequence != last_packet_sequence:
		# Tracking must produce NEW poses to earn hold time. A retained pose
		# can keep rendering the guide, but never advance the countdown.
		if packet_gap_seconds > MAX_PACKET_GAP_SECONDS:
			_reset_current_hold()
			_set_live_instruction("POSE FRAMES PAUSED • Hold will restart after tracking resumes.\nNawala ang tracking • Uulit ang bilang.")
			return
		last_packet_sequence = PoseService.packet_sequence
		live_samples.append(x)
		# Count the actual elapsed time between fresh, stable pose packets.
		# Inference is slower than rendering, so adding only this frame's delta
		# would incorrectly turn a 3-second hold into a much longer wait.
		live_timer += tracking_delta + packet_gap_seconds
		packet_gap_seconds = 0.0
	else:
		packet_gap_seconds += tracking_delta
		if packet_gap_seconds > MAX_PACKET_GAP_SECONDS:
			_reset_current_hold()
			_set_live_instruction("POSE FRAMES PAUSED • Hold will restart after tracking resumes.\nNawala ang tracking • Uulit ang bilang.")
			return
	var remaining := maxi(0, ceili(HOLD_SECONDS - live_timer))
	_update_hold_countdown()
	if is_instance_valid(progress_label):
		progress_label.text = "%s • HOLD STILL FOR %d MORE SECONDS" % [target, remaining]
	_set_live_instruction("%s • HOLD STILL: %d seconds\n%s • Huwag gumalaw." % [STAGE_TEXT[target][0], remaining, STAGE_TEXT[target][1]])
	if live_timer < HOLD_SECONDS or live_samples.size() < REQUIRED_SAMPLES:
		return
	var sum := 0.0
	for sample in live_samples:
		sum += sample
	measured_points[target.to_lower()] = sum / float(live_samples.size())
	live_step += 1
	_reset_current_hold()
	_update_target_guide()
	if live_step < capture_order.size():
		_set_stage_instruction()
		return
	# Human Plane, Catch the Word and Balloon Popping all require real
	# measured CENTER, RIGHT and LEFT bounds. No synthetic side positions.
	var good := PoseService.set_calibration(
		float(measured_points["left"]),
		float(measured_points["center"]),
		float(measured_points["right"])
	)
	if good:
		transition_queued = true
		if is_instance_valid(continue_button):
			# Legacy completion status only; remains hidden and non-interactive.
			continue_button.disabled = false
		if is_instance_valid(progress_label):
			progress_label.text = "CALIBRATION SUCCESSFUL • 3 REAL POSITIONS MEASURED"
		_set_live_instruction("CALIBRATION COMPLETE! Preparing the game.\nTapos na ang calibration! Magsisimula na ang laro.")
		call_deferred("_advance_after_calibration", transition_generation)
	else:
		_reset_live_samples()
		_set_live_instruction("POSITIONS TOO CLOSE • Please repeat with wider LEFT and RIGHT movements.\nUlitin gamit ang mas malawak na paggalaw.")


func _inside_zone(target: String, x: float) -> bool:
	match target:
		"CENTER":
			return absf(x - 0.5) <= ZONE_CENTER_RADIUS
		"RIGHT":
			return x >= maxf(ZONE_RIGHT_START, float(measured_points.get("center", 0.5)) + 0.12)
		"LEFT":
			return x <= minf(ZONE_LEFT_END, float(measured_points.get("center", 0.5)) - 0.12)
	return false


func _set_stage_instruction() -> void:
	var capture_order := _capture_order()
	if live_step >= capture_order.size():
		return
	var target: String = capture_order[live_step]
	if is_instance_valid(stage_heading):
		stage_heading.text = String(STAGE_TEXT[target][0])
	if is_instance_valid(step_badge):
		step_badge.text = "STEP %d / %d" % [live_step + 1, capture_order.size()]
	# Separate editor-authored labels retain the designer's Gochi Hand font.
	if is_instance_valid(instruction_en):
		instruction_en.text = String(STAGE_TEXT[target][0])
	if is_instance_valid(instruction_fil):
		var sentence := String(STAGE_TEXT[target][1]).to_lower()
		instruction_fil.text = sentence.substr(0, 1).to_upper() + sentence.substr(1)
	if is_instance_valid(progress_label):
		progress_label.text = "%s • STAND IN THE GLOWING BOX" % target
	_set_live_instruction("%s\n%s" % STAGE_TEXT[target])
	_sync_reference_art()


func _update_hold_countdown() -> void:
	# Display the large 3/2/1 only during a real stationary, fresh-pose
	# hold. Moving, losing the pose, or stale packets hides and resets it.
	if is_instance_valid(countdown_label):
		countdown_label.visible = live_timer > 0.0 and live_step < _capture_order().size()
		if countdown_label.visible:
			countdown_label.text = str(clampi(ceili(HOLD_SECONDS - live_timer), 1, 3))
	_sync_reference_art()


func _set_live_instruction(message: String) -> void:
	if is_instance_valid(instruction_label):
		instruction_label.text = message


func _update_target_guide() -> void:
	# The standing guide is independent editor-authored UI artwork, not
	# rectangles overlaid on the pixel data from the camera. Only one guide
	# is visible per position; the pose preview retains bones/keypoints only.
	var capture_order := _capture_order()
	var active_zone: String = "DONE" if live_step >= capture_order.size() else String(capture_order[live_step])
	# Synthetic QA and reset routes may call this directly without calling
	# _set_stage_instruction(), so the step indicator must never remain stale.
	if is_instance_valid(step_badge):
		step_badge.text = "STEP %d / %d" % [clampi(live_step + 1, 1, capture_order.size()), capture_order.size()]
	for i in range(lane_panels.size()):
		if not is_instance_valid(lane_panels[i]):
			continue
		var zone: String = ["LEFT", "CENTER", "RIGHT"][i]
		var current: bool = zone == active_zone
		lane_panels[i].visible = current
		lane_panels[i].modulate = Color.WHITE
		if i < lane_labels.size() and is_instance_valid(lane_labels[i]):
			# Standing guide stays a glowing outline; bilingual directions are
			# shown in the independent scene-authored headings above the camera.
			lane_labels[i].visible = false
		if i < lane_hints.size() and is_instance_valid(lane_hints[i]):
			lane_hints[i].visible = false
	_sync_reference_art()


func _sync_reference_art() -> void:
	# Pure visibility switches preserve every asset's Godot Inspector transform
	# (the teacher can drag/resize title, step badge and digits independently).
	var capture_order := _capture_order()
	var active_zone: String = "DONE" if live_step >= capture_order.size() else String(capture_order[live_step])
	for zone in art_title_nodes:
		var title := art_title_nodes[zone] as Control
		if is_instance_valid(title):
			title.visible = zone == active_zone
	for zone in art_guide_nodes:
		var guide := art_guide_nodes[zone] as Control
		if is_instance_valid(guide):
			guide.visible = zone == active_zone
	for zone in art_arrow_nodes:
		var arrow := art_arrow_nodes[zone] as Control
		if is_instance_valid(arrow):
			arrow.visible = zone == active_zone
	for zone in art_hint_nodes:
		var hint := art_hint_nodes[zone] as Control
		if is_instance_valid(hint):
			hint.visible = zone == active_zone
	var fallback_hint := get_node_or_null("TutorialStage/ArtMoveHint") as Control
	if is_instance_valid(fallback_hint):
		fallback_hint.visible = not art_hint_nodes.values().any(func(node: Variant) -> bool: return is_instance_valid(node))
	var fallback_arrow := get_node_or_null("TutorialStage/ArtArrow") as Control
	if is_instance_valid(fallback_arrow):
		# Hide the generic arrow if independently draggable directional variants
		# exist. Individual arrows are all positioned in the Godot editor.
		fallback_arrow.visible = not art_arrow_nodes.values().any(func(node: Variant) -> bool: return is_instance_valid(node))
	for index in range(art_step_nodes.size()):
		if is_instance_valid(art_step_nodes[index]):
			art_step_nodes[index].visible = live_step == index
	# The previous one-position Plane plaque remains editor-authored in the
	# scene for compatibility, but no longer applies to any active game.
	if is_instance_valid(plane_step_badge):
		plane_step_badge.visible = false
	# The illustrated countdown starts at 3 even while we await the student;
	# unlike the decoration, calibration time only advances on NEW valid
	# stationary pose frames, as verified by the underlying hold timer.
	var remaining := clampi(ceili(HOLD_SECONDS - live_timer), 1, 3)
	var static_badge := get_node_or_null("TutorialStage/ArtCountdownBadge") as Control
	if is_instance_valid(static_badge):
		# This is the fixed old 3 illustration. The dynamic 1/2/3 assets now
		# own the countdown, so never layer a permanent 3 beneath a 2 or 1.
		static_badge.visible = art_countdown_nodes.is_empty()
	for index in range(art_countdown_nodes.size()):
		if is_instance_valid(art_countdown_nodes[index]):
			art_countdown_nodes[index].visible = live_step < capture_order.size() and index == remaining - 1


func _reset_current_hold() -> void:
	live_timer = 0.0
	anchor_x = -1.0
	live_samples.clear()
	last_packet_sequence = -1
	packet_gap_seconds = 0.0
	_update_hold_countdown()


func _reset_live_samples(clear_service_calibration: bool = true) -> void:
	transition_generation += 1
	transition_queued = false
	live_step = 0
	measured_points.clear()
	_reset_current_hold()
	if clear_service_calibration:
		PoseService.calibration.clear()
	if is_instance_valid(continue_button):
		continue_button.disabled = true
		continue_button.visible = false
	_update_target_guide()
	_set_stage_instruction()


func _advance_after_calibration(generation: int) -> void:
	await get_tree().create_timer(2.0).timeout
	if not is_inside_tree() or generation != transition_generation:
		return
	if PoseService.active and PoseService.has_valid_pose() and bool(PoseService.calibration.get("valid", false)):
		_continue_flow()
	else:
		transition_queued = false
		_set_live_instruction("PLAYER LOST • Return to the marked zone to continue.\nNawala ang tracking • Bumalik sa kahon.")


func _continue_flow(skipped: bool = false) -> void:
	# Deprecated callers cannot bypass live camera calibration.
	if skipped:
		return
	var live_measured := PoseService.active and PoseService.has_valid_pose() and bool(PoseService.calibration.get("valid", false))
	# Reusing an earlier center-only calibration would supply fabricated travel
	# limits. Plane must finish its three actual positions on this screen.
	if _is_human_plane():
		live_measured = live_measured and live_step >= CAPTURE_ORDER.size() \
			and measured_points.has("center") and measured_points.has("left") \
			and measured_points.has("right")
	live_measured = live_measured and not bool(PoseService.calibration.get("center_only", false))
	if not live_measured:
		_set_live_instruction("COMPLETE ALL THREE LIVE POSITIONS FIRST.\nKumpletuhin muna ang tatlong posisyon.")
		return
	var payload := context.duplicate(true)
	payload.merge({
		"start_countdown": true,
		"preview_mode": false,
		"camera_live": true,
		"keyboard_mode": false,
		"calibration_live": true,
		"calibration_measured": true,
		"calibration_center_only": false,
		"from_calibration": true,
		"calibration_skipped": false,
		"calibration_previewed": false
	}, true)
	payload["calibration_left"] = PoseService.calibration["left"]
	payload["calibration_center"] = PoseService.calibration["center"]
	payload["calibration_right"] = PoseService.calibration["right"]
	passing_to_ready = true
	# One shared gameplay wrapper handles guided spotlight and 3-2-1 countdown.
	requested.emit("gameplay", payload)


func _go_back() -> void:
	transition_generation += 1
	transition_queued = false
	passing_to_ready = false
	if PoseService.active:
		PoseService.stop_camera()
	requested.emit("main", context.duplicate(true))


func _exit_tree() -> void:
	if PoseService.status_updated.is_connected(_on_pose_status):
		PoseService.status_updated.disconnect(_on_pose_status)
	if PoseService.preview_updated.is_connected(_on_live_preview):
		PoseService.preview_updated.disconnect(_on_live_preview)
	if PoseService.active and not passing_to_ready:
		PoseService.stop_camera()
