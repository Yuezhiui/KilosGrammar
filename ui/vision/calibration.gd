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
const PLANE_HOLD_SECONDS := 2.5
const REQUIRED_SAMPLES := 8
const MAX_SAMPLE_SPREAD := 0.095
const MAX_PACKET_GAP_SECONDS := 0.7
const ZONE_CENTER_RADIUS := 0.18
const ZONE_RIGHT_START := 0.64
const ZONE_LEFT_END := 0.36

const STAGE_TEXT := {
	"CENTER": ["STAY IN THE CENTER", "MANATILI SA GITNA"],
	"RIGHT": ["MOVE TO THE RIGHT", "GUMALAW SA KANAN"],
	"LEFT": ["MOVE TO THE LEFT", "GUMALAW SA KALIWA"]
}
const PLANE_STAGE_TEXT := {
	"CENTER": ["HOLD CENTER • SHOW BOTH HANDS", "Tumayo sa gitna • Ipakita ang dalawang kamay"]
}
const PLANE_STEERING_STABILITY := 0.16
const PLANE_NEUTRAL_MAX_SPREAD := 0.16

var context: Dictionary = {}
var camera_entry_requested := false
var lane_panels: Array[Control] = []
var lane_labels: Array[Label] = []
var lane_hints: Array[Label] = []
var instruction_label: Label
var instruction_fil: Label
var countdown_label: Label
var progress_label: Label
var player_label: Label
var status_label: Label
var stage_heading: Label
var step_badge: Label
var plane_step_badge: Control
var plane_steering_title: Label
var plane_steering_footnote: Label
var badge_label: Label
var intro_overlay: Control
var intro_countdown: Label
var intro_back_button: Button
var back_main_button: Button
var intro_stage_visibility: Dictionary = {}
var camera_unavailable: Label
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
var last_fresh_sample_id := 0
var packet_gap_seconds := 0.0
var anchor_x := -1.0
var anchor_plane_steering := -999.0
var plane_hold_started_when := -1.0
var plane_last_sample_when := -1.0
var plane_locked_id := -1
var plane_camera_samples: Array[float] = []
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
	plane_steering_title = stage.get_node_or_null("PlaneSteeringTitle") as Label
	plane_steering_footnote = stage.get_node_or_null("PlaneSteeringFootnote") as Label
	badge_label = stage.get_node_or_null("BadgeLabel") as Label
	instruction_label = stage.get_node_or_null("InstructionLabel") as Label
	instruction_fil = stage.get_node_or_null("InstructionFIL") as Label
	countdown_label = stage.get_node_or_null("CountdownLabel") as Label
	progress_label = stage.get_node_or_null("ProgressLabel") as Label
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
	if camera_inset:
		camera_inset.visible = false
	if is_instance_valid(countdown_label):
		countdown_label.visible = false
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
	# an older serialized scene must not strand a student without Back to Choose Activity.
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
	if not intro_running:
		_update_target_guide()
		_set_stage_instruction()
	var intro_description := get_node_or_null("TutorialStage/IntroOverlay/IntroDescription") as Label
	if is_instance_valid(intro_description):
			intro_description.text = ("STAND CENTER • SHOW BOTH HANDS • THEN FLY LEFT AND RIGHT" if _is_human_plane() else
			"CENTER → RIGHT → LEFT • Move to each floor position")
	_refresh_player_label()
	_try_start_camera()
	_refresh_camera_status()


func _is_human_plane() -> bool:
	return String(context.get("activity", "")).strip_edges() == "Human Plane"


func _capture_order() -> Array:
	# Human Plane calibrates one neutral pose. Other games retain all three
	# actual LEFT/CENTER/RIGHT floor positions.
	return ["CENTER"] if _is_human_plane() else CAPTURE_ORDER


func _hold_seconds() -> float:
	return PLANE_HOLD_SECONDS if _is_human_plane() else HOLD_SECONDS


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
		# The required 8 measurements must belong to the live hold, not to
		# camera packets accumulated behind the introduction screen.
		last_fresh_sample_id = PoseService.latest_pose_sample_id
		_finish_intro_only()
	var capture_order := _capture_order()
	if live_step >= capture_order.size():
		# A temporary player loss after calibration must not strand
		# the student at a finished screen with Continue hidden. Automatically
		# retry the handoff when that same locked player is visible again.
		if not transition_queued and PoseService.active and PoseService.has_valid_pose() \
				and bool(PoseService.calibration.get("valid", false)) \
				and (not _is_human_plane() or PoseService.has_stationary_plane_pose()):
			transition_queued = true
			call_deferred("_advance_after_calibration", transition_generation)
		return
	if transition_queued:
		return
	if _is_human_plane():
		_process_stationary_plane(tracking_delta)
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
		live_samples.clear()
		live_timer = 0.0
		packet_gap_seconds = 0.0
	if absf(x - anchor_x) > MAX_SAMPLE_SPREAD:
		_reset_current_hold()
		_set_live_instruction("MOVEMENT DETECTED • Stop moving, then hold for 3 seconds.\nMay galaw • Huminto at manatili nang 3 segundo.")
		return
	var fresh_samples: Array[Dictionary] = PoseService.get_pose_samples_after(last_fresh_sample_id)
	var has_fresh_packet := not fresh_samples.is_empty() or PoseService.packet_sequence != last_packet_sequence
	if has_fresh_packet:
		# Tracking must produce NEW poses to earn hold time. A retained pose
		# can keep rendering the guide, but never advance the countdown.
		if packet_gap_seconds > _allowed_packet_gap_seconds():
			_reset_current_hold()
			_set_live_instruction("POSE FRAMES PAUSED • Hold will restart after tracking resumes.\nNawala ang tracking • Uulit ang bilang.")
			return
		last_packet_sequence = PoseService.packet_sequence
		if not fresh_samples.is_empty():
			# Every source packet has its own strictly increasing worker timestamp.
			# The renderer only needs the newest pose, but the three-second hold
			# must not discard seven genuine detections in the same UI frame.
			for sample: Dictionary in fresh_samples:
				var sample_x := float(sample.get("x", -1.0))
				if not _inside_zone(target, sample_x) or absf(sample_x - anchor_x) > MAX_SAMPLE_SPREAD:
					_reset_current_hold()
					_set_live_instruction("MOVEMENT DETECTED • Hold still in the glowing box.\nMay galaw • Manatili sa kahon.")
					return
				live_samples.append(sample_x)
				last_fresh_sample_id = int(sample["id"])
		else:
			# Backwards-compatible path for synthetic test sources that inject a
			# single valid PoseService body state instead of real UDP packets.
			live_samples.append(x)
		# Count the actual elapsed time between fresh, stable pose packets.
		# Inference is slower than rendering, so adding only this frame's delta
		# would incorrectly turn a 3-second hold into a much longer wait.
		live_timer += tracking_delta + packet_gap_seconds
		packet_gap_seconds = 0.0
	else:
		packet_gap_seconds += tracking_delta
		if packet_gap_seconds > _allowed_packet_gap_seconds():
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
		# The non-plane games still require real measured floor positions.
	var good := PoseService.set_calibration(
		float(measured_points["left"]),
		float(measured_points["center"]),
		float(measured_points["right"])
	)
	if good:
		transition_queued = true
		if is_instance_valid(progress_label):
			progress_label.text = "CALIBRATION SUCCESSFUL • 3 REAL POSITIONS MEASURED"
		_set_live_instruction("CALIBRATION COMPLETE! Preparing the game.\nTapos na ang calibration! Magsisimula na ang laro.")
		call_deferred("_advance_after_calibration", transition_generation)
	else:
		_reset_live_samples()
		_set_live_instruction("POSITIONS TOO CLOSE • Please repeat with wider LEFT and RIGHT movements.\nUlitin gamit ang mas malawak na paggalaw.")


func _process_stationary_plane(delta: float) -> void:
	# Only actual, strictly increasing UDP samples with a worker-verified locked
	# student may satisfy these holds. No legacy packet_sequence fallback.
	if not PoseService.active or not PoseService.has_valid_pose():
		_reset_current_hold()
		_set_live_instruction("STUDENT NOT TRACKED • Stand alone in camera view.\nDapat iisang estudyante ang makita sa kamera.")
		return
	var fresh_samples: Array[Dictionary] = PoseService.get_pose_samples_after(last_fresh_sample_id)
	if fresh_samples.is_empty():
		packet_gap_seconds += delta
		if packet_gap_seconds > _allowed_packet_gap_seconds():
			_reset_current_hold()
			_set_live_instruction("TRACKING PAUSED • Hold restarts after new pose frames.\nNawala ang tracking • Uulit ang bilang.")
		return
	for sample: Dictionary in fresh_samples:
		var sample_id := int(sample.get("id", -1))
		var locked_id := int(sample.get("locked_id", -1))
		var raw: Variant = sample.get("plane_steering", null)
		var camera_x := float(sample.get("x", -1.0))
		var packet_when := float(sample.get("when", -1.0))
		if locked_id < 0 or not (raw is float or raw is int) \
				or not is_finite(float(raw)) or absf(float(raw)) > 1.0 \
				or not is_finite(packet_when) or camera_x < 0.28 or camera_x > 0.72:
			_reset_current_hold()
			_set_live_instruction("SHOW BOTH HANDS AND TORSO • Stand centered for calibration.\nIpakita ang dalawang kamay at katawan • Tumayo sa gitna.")
			return
		if plane_locked_id >= 0 and plane_locked_id != locked_id:
			# A reacquired bystander must never reuse someone else's neutral.
			_reset_live_samples()
			_set_live_instruction("NEW STUDENT DETECTED • Hold your neutral pose again.\nBagong estudyante • Ulitin ang maikling pagkakakalibrate.")
			return
		if plane_locked_id < 0:
			plane_locked_id = locked_id
		var steering := float(raw)
		if plane_hold_started_when < 0.0:
			anchor_x = camera_x
			anchor_plane_steering = steering
			plane_hold_started_when = packet_when
			plane_last_sample_when = packet_when
		if absf(camera_x - anchor_x) > MAX_SAMPLE_SPREAD \
				or absf(steering - anchor_plane_steering) > PLANE_STEERING_STABILITY \
				or packet_when <= plane_last_sample_when and not live_samples.is_empty() \
				or packet_when - plane_last_sample_when > _allowed_packet_gap_seconds():
			_reset_current_hold()
			_set_live_instruction("MOVED FROM CENTER • Hold still again.\nGumalaw mula sa gitna • Manatiling nakapirmi.")
			return
		plane_last_sample_when = packet_when
		live_timer = maxf(0.0, packet_when - plane_hold_started_when)
		live_samples.append(steering)
		plane_camera_samples.append(camera_x)
		last_fresh_sample_id = sample_id
	packet_gap_seconds = 0.0
	_update_hold_countdown()
	var remaining := maxi(0, ceili(PLANE_HOLD_SECONDS - live_timer))
	if is_instance_valid(progress_label):
		progress_label.text = "CENTER STEADY • %d SEC • %d / %d LIVE POSES" % [remaining, live_samples.size(), REQUIRED_SAMPLES]
	_set_live_instruction("KEEP BOTH HANDS VISIBLE • %d SECONDS\nManatili sa gitna • Ipakita ang dalawang kamay." % remaining)
	if live_timer < PLANE_HOLD_SECONDS or live_samples.size() < REQUIRED_SAMPLES:
		return
	# Median and median-absolute-deviation reject incidental torso jitter.
	# Actual LEFT/RIGHT movement is tracked live; no side endpoint is invented.
	var sorted_steering := live_samples.duplicate()
	sorted_steering.sort()
	if sorted_steering.back() - sorted_steering.front() > PLANE_NEUTRAL_MAX_SPREAD:
		_reset_current_hold()
		_set_live_instruction("PLEASE STAND A LITTLE STEADIER IN CENTER.\nPakipirmi sa gitna.")
		return
	var center := _plane_median(sorted_steering)
	var deviations: Array[float] = []
	for value in sorted_steering:
		deviations.append(absf(value - center))
	deviations.sort()
	var neutral_noise := _plane_median(deviations)
	var total_camera_x := 0.0
	for camera_x in plane_camera_samples:
		total_camera_x += camera_x
	measured_points["center"] = center
	measured_points["neutral_noise"] = neutral_noise
	measured_points["camera_center_x"] = total_camera_x / float(plane_camera_samples.size())
	var accepted := PoseService.set_stationary_plane_calibration(
		center, plane_locked_id, float(measured_points["camera_center_x"]), neutral_noise
	)
	if not accepted:
		_reset_live_samples()
		_set_live_instruction("STAND COMFORTABLY IN THE CAMERA'S CENTER, THEN HOLD STILL.\nTumayo sa gitna at panatilihing nakapirmi.")
		return
	live_step = 1
	_reset_current_hold()
	_update_target_guide()
	transition_queued = true
	if is_instance_valid(progress_label):
		progress_label.text = "SUCCESS • CENTER CALIBRATED"
	_set_live_instruction("READY TO FLY • MOVE LEFT OR RIGHT TO STEER!\nHanda nang lumipad • Gumalaw pakaliwa o pakanan!")
	call_deferred("_advance_after_calibration", transition_generation)


func _plane_median(sorted_values: Array[float]) -> float:
	if sorted_values.is_empty():
		return 0.0
	var size := sorted_values.size()
	if size % 2 == 1:
		return sorted_values[size / 2]
	return 0.5 * (sorted_values[size / 2 - 1] + sorted_values[size / 2])


func _inside_zone(target: String, x: float) -> bool:
	match target:
		"CENTER":
			return absf(x - 0.5) <= ZONE_CENTER_RADIUS
		"RIGHT":
			return x >= maxf(ZONE_RIGHT_START, float(measured_points.get("center", 0.5)) + 0.12)
		"LEFT":
			return x <= minf(ZONE_LEFT_END, float(measured_points.get("center", 0.5)) - 0.12)
	return false


func _allowed_packet_gap_seconds() -> float:
	# A genuinely slow pose model may deliver 2-3 fresh frames per second.
	# Requiring <0.7s between every packet makes calibration impossible at
	# 1-2 FPS. This adjustment never counts an old frame twice or relaxes the
	# required hold duration / 8 source measurements per actual stage.
	var pose_fps := float(PoseService.current_status.get("fps", 0.0))
	if pose_fps > 0.0 and pose_fps < 5.0:
		return clampf(1.75 / pose_fps, MAX_PACKET_GAP_SECONDS, 1.45)
	return MAX_PACKET_GAP_SECONDS


func _set_stage_instruction() -> void:
	var capture_order := _capture_order()
	if live_step >= capture_order.size():
		return
	var target: String = capture_order[live_step]
	var messages: Array = PLANE_STAGE_TEXT[target] if _is_human_plane() else STAGE_TEXT[target]
	if is_instance_valid(stage_heading):
		stage_heading.text = String(messages[0])
	if is_instance_valid(step_badge):
		step_badge.text = "STEP %d / %d" % [live_step + 1, capture_order.size()]
	# Keep the designer's separate, visible Filipino label; StageHeading owns English.
	if is_instance_valid(instruction_fil):
		var sentence := String(messages[1]).to_lower()
		instruction_fil.text = sentence.substr(0, 1).to_upper() + sentence.substr(1)
	if is_instance_valid(progress_label):
		progress_label.text = "ONE NEUTRAL HOLD • HANDS VISIBLE" if _is_human_plane() else "%s • STAND IN THE GLOWING BOX" % target
	_set_live_instruction("%s\n%s" % messages)
	_sync_reference_art()


func _update_hold_countdown() -> void:
	# Display the large 3/2/1 only during a real stationary, fresh-pose
	# hold. Moving, losing the pose, or stale packets hides and resets it.
	if is_instance_valid(countdown_label):
		countdown_label.visible = live_timer > 0.0 and live_step < _capture_order().size()
		if countdown_label.visible:
				countdown_label.text = str(clampi(ceili(_hold_seconds() - live_timer), 1, 3))
	_sync_reference_art()


func _set_live_instruction(message: String) -> void:
	if is_instance_valid(instruction_label):
		instruction_label.text = message


func _update_target_guide() -> void:
	# The updated PARAMETERS.png artwork is the ONLY visible standing guide.
	# The older green lane panels and their child captions are retained solely
	# as editor-reference rectangles. Never reveal them during calibration:
	# they duplicate the yellow PNG square and can cover the camera/status.
	var capture_order := _capture_order()
	var active_zone: String = "DONE" if live_step >= capture_order.size() else String(capture_order[live_step])
	# Synthetic QA and reset routes may call this directly without calling
	# _set_stage_instruction(), so the step indicator must never remain stale.
	if is_instance_valid(step_badge):
		step_badge.text = "STEP %d / %d" % [clampi(live_step + 1, 1, capture_order.size()), capture_order.size()]
	for i in range(lane_panels.size()):
		if not is_instance_valid(lane_panels[i]):
			continue
		lane_panels[i].visible = false
		lane_panels[i].modulate = Color(1, 1, 1, 0)
		if i < lane_labels.size() and is_instance_valid(lane_labels[i]):
			lane_labels[i].visible = false
		if i < lane_hints.size() and is_instance_valid(lane_hints[i]):
			lane_hints[i].visible = false
	_sync_reference_art()


func _sync_reference_art() -> void:
	# Pure visibility switches preserve every asset's Godot Inspector transform
	# (the teacher can drag/resize title, step badge and digits independently).
	var capture_order := _capture_order()
	var active_zone: String = "DONE" if live_step >= capture_order.size() else String(capture_order[live_step])
	var plane_mode := _is_human_plane()
	if is_instance_valid(plane_steering_title):
		plane_steering_title.visible = plane_mode and active_zone != "DONE"
		if plane_steering_title.visible:
			plane_steering_title.text = String(PLANE_STAGE_TEXT[active_zone][0])
	if is_instance_valid(plane_steering_footnote):
		plane_steering_footnote.visible = plane_mode
	for zone in art_title_nodes:
		var title := art_title_nodes[zone] as Control
		if is_instance_valid(title):
			title.visible = not plane_mode and zone == active_zone
	for zone in art_guide_nodes:
		var guide := art_guide_nodes[zone] as Control
		if is_instance_valid(guide):
			guide.visible = (zone == "CENTER" and active_zone != "DONE") if plane_mode else zone == active_zone
	for zone in art_arrow_nodes:
		var arrow := art_arrow_nodes[zone] as Control
		if is_instance_valid(arrow):
			arrow.visible = not plane_mode and zone == active_zone
	for zone in art_hint_nodes:
		var hint := art_hint_nodes[zone] as Control
		if is_instance_valid(hint):
			hint.visible = not plane_mode and zone == active_zone
	var fallback_hint := get_node_or_null("TutorialStage/ArtMoveHint") as Control
	if is_instance_valid(fallback_hint):
		fallback_hint.visible = not plane_mode and not art_hint_nodes.values().any(func(node: Variant) -> bool: return is_instance_valid(node))
	var fallback_arrow := get_node_or_null("TutorialStage/ArtArrow") as Control
	if is_instance_valid(fallback_arrow):
		# Hide the generic arrow if independently draggable directional variants
		# exist. Individual arrows are all positioned in the Godot editor.
		fallback_arrow.visible = not plane_mode and not art_arrow_nodes.values().any(func(node: Variant) -> bool: return is_instance_valid(node))
	for index in range(art_step_nodes.size()):
		if is_instance_valid(art_step_nodes[index]):
			art_step_nodes[index].visible = not plane_mode and live_step == index
	# ONE-POSE plaque uses its own editor-authored transforms for Plane only.
	if is_instance_valid(plane_step_badge):
		plane_step_badge.visible = plane_mode and active_zone != "DONE"
	# The illustrated countdown starts at 3 even while we await the student;
	# unlike the decoration, calibration time only advances on NEW valid
	# stationary pose frames, as verified by the underlying hold timer.
	var remaining := clampi(ceili(_hold_seconds() - live_timer), 1, 3)
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
	anchor_plane_steering = -999.0
	plane_hold_started_when = -1.0
	plane_last_sample_when = -1.0
	plane_camera_samples.clear()
	live_samples.clear()
	last_packet_sequence = PoseService.packet_sequence
	last_fresh_sample_id = PoseService.latest_pose_sample_id
	packet_gap_seconds = 0.0
	_update_hold_countdown()


func _reset_live_samples(clear_service_calibration: bool = true) -> void:
	transition_generation += 1
	transition_queued = false
	live_step = 0
	measured_points.clear()
	plane_locked_id = -1
	_reset_current_hold()
	if clear_service_calibration:
		PoseService.calibration.clear()
		PoseService.plane_calibration.clear()
	_update_target_guide()
	_set_stage_instruction()


func _advance_after_calibration(generation: int) -> void:
	await get_tree().create_timer(2.0).timeout
	if not is_inside_tree() or generation != transition_generation:
		return
	if PoseService.active and PoseService.has_valid_pose() and bool(PoseService.calibration.get("valid", false)) \
			and (not _is_human_plane() or PoseService.has_stationary_plane_pose()):
		_continue_flow()
	else:
		transition_queued = false
		_set_live_instruction("PLAYER LOST • Return to the marked zone to continue.\nNawala ang tracking • Bumalik sa kahon.")


func _continue_flow(skipped: bool = false) -> void:
	# Deprecated callers cannot bypass live camera calibration.
	if skipped:
		return
	var live_measured := PoseService.active and PoseService.has_valid_pose() and bool(PoseService.calibration.get("valid", false))
	if _is_human_plane():
		live_measured = live_measured and live_step >= 1 \
			and measured_points.has("center") \
			and measured_points.has("neutral_noise") \
			and PoseService.has_stationary_plane_pose()
	live_measured = live_measured and not bool(PoseService.calibration.get("center_only", false))
	if not live_measured:
		_set_live_instruction("COMPLETE THE SINGLE LIVE HAND-POSE HOLD FIRST.\nKumpletuhin ang isang pagkakakalibrate." if _is_human_plane() else
			"COMPLETE ALL THREE LIVE POSITIONS FIRST.\nKumpletuhin muna ang tatlong posisyon.")
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
	payload["calibration_center"] = PoseService.calibration["center"]
	if _is_human_plane():
		# Explicitly remove any stale physical floor limits from a prior game.
		payload.erase("calibration_left")
		payload.erase("calibration_right")
		payload["calibration_stationary"] = true
		payload["plane_steering_mode"] = "centered_torso_x_one_wrist"
		payload["calibration_neutral_only"] = true
		payload["calibration_steering_sensitivity"] = PoseService.plane_calibration["sensitivity"]
		payload["calibration_steering_deadzone"] = PoseService.plane_calibration["deadzone"]
		payload["calibration_camera_center_x"] = PoseService.plane_calibration["camera_center_x"]
	else:
		payload["calibration_left"] = PoseService.calibration["left"]
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
	requested.emit("play_activity", context.duplicate(true))


func _exit_tree() -> void:
	if PoseService.status_updated.is_connected(_on_pose_status):
		PoseService.status_updated.disconnect(_on_pose_status)
	if PoseService.preview_updated.is_connected(_on_live_preview):
		PoseService.preview_updated.disconnect(_on_live_preview)
	if PoseService.active and not passing_to_ready:
		PoseService.stop_camera()
