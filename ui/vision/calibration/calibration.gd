extends Control

signal requested(target: String, payload: Dictionary)

# One shared, full-screen camera calibration for Tutorial and ordinary Play.
# PoseService owns the camera, fresh single-person poses and video.
# The complete visible layout is editable in calibration.tscn.
const ART := preload("res://ui/tutorial/tutorial_theme.gd")
const CalibrationVoice = preload("res://ui/vision/calibration/calibration_voice.gd")
const DESIGN_SIZE := Vector2(1280.0, 720.0)
const CAPTURE_ORDER := ["CENTER", "RIGHT", "LEFT"]
const BALLOON_CAPTURE_ORDER := ["CENTER", "RIGHT", "LEFT"]
const INTRO_SECONDS := 3.0
const SUCCESS_SECONDS := 3.0
const HOLD_SECONDS := 3.0
const PLANE_HOLD_SECONDS := 3.0
const REQUIRED_SAMPLES := 8
const MAX_SAMPLE_SPREAD := 0.095
const MAX_PACKET_GAP_SECONDS := 0.7
# One genuine visible person can have a single low-confidence torso/wrist
# packet. Briefly PAUSE the hold without erasing previously measured fresh
	# samples; never count the invalid time as part of the 3-second hold.
const SOLO_POSE_HOLD_DROPOUT_SECONDS := 0.35
const PLANE_DEMO_SECONDS_PER_SIDE := 2.2
const ZONE_CENTER_RADIUS := 0.18
const ZONE_RIGHT_START := 0.64
const ZONE_LEFT_END := 0.36

const STAGE_TEXT := {
	"CENTER": ["STAY IN THE CENTER", "Stay in the center"],
	"RIGHT": ["MOVE TO THE RIGHT", "Move to the right"],
	"LEFT": ["MOVE TO THE LEFT", "Move to the left"]
}
const PLANE_STAGE_TEXT := {
	"CENTER": ["HOLD A T-POSE IN CENTER", "Stand in the middle with both arms extended"]
}
const BALLOON_DEFAULT_TEXT := ["KEEP BOTH HANDS DOWN", "Keep both hands lowered"]
const BALLOON_RAISE_TEXT := ["RAISE BOTH HANDS TO SHOOT", "Raise both hands to shoot"]
const PLANE_STEERING_STABILITY := 0.16
const PLANE_NEUTRAL_MAX_SPREAD := 0.16

var context: Dictionary = {}
var camera_entry_requested := false
var progress_label: Label
var status_label: Label
var latest_instruction_text := "" # Status for diagnostics; no retired label is recreated.
var intro_overlay: Control
var success_overlay: Control
var success_subtitle: Label
var authored_success_subtitle := ""
var back_main_button: Button
var intro_stage_visibility: Dictionary = {}
var success_stage_visibility: Dictionary = {}
var success_running := false
var success_elapsed := 0.0
var plane_demo_elapsed := 0.0
var plane_demo_running := false
var plane_demo_last_announced_side := ""
var calibration_voice: Node
var camera_unavailable: Label
var camera_inset: TextureRect
var skeleton_placement: ReferenceRect
# Supplied CALIB artwork stays in independently movable .tscn TextureRects.
# These UI nodes never become children of the camera texture or get painted
# into JPEG preview pixels by the Python pose worker.
var art_title_nodes: Dictionary = {}
var art_arrow_nodes: Dictionary = {}
var art_hint_nodes: Dictionary = {}
var art_step_nodes: Array[Control] = []
var art_countdown_nodes: Array[Control] = []
var pose_guide_default: Control
var pose_guide_left: Control
var pose_guide_right: Control
var pose_guide_balloon_raise: Control
var pose_guide_balloon_raise_left: Control
var pose_guide_balloon_raise_right: Control
var pose_guide_plane_center: Control
var pose_guide_plane_left: Control
var pose_guide_plane_right: Control
var neutral_instruction: Label
var pose_default_by_zone: Dictionary = {}
var pose_raise_by_zone: Dictionary = {}

var intro_elapsed := 0.0
var intro_running := true
var live_step := 0
var balloon_pose_phase := 0 # 0 = BOTH hands DOWN, 1 = BOTH hands UP
var live_timer := 0.0
var live_samples: Array[float] = []
var last_fresh_sample_id := 0
var packet_gap_seconds := 0.0
var brief_solo_invalid_seconds := 0.0
var plane_hold_invalid_seconds := 0.0
var anchor_x := -1.0
var anchor_plane_steering := -999.0
var plane_hold_started_when := -1.0
var plane_last_sample_when := -1.0
var plane_camera_samples: Array[float] = []
var measured_points: Dictionary = {}
var passing_to_ready := false # Camera ownership passes to gameplay on success.
var transition_queued := false
var capture_camera_session_token := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var stage := get_node_or_null("TutorialStage") as Control
	if stage == null:
		push_error("Calibration requires an editor-authored TutorialStage.")
		return
	_bind_scene_nodes(stage)
	# A single optional spoken prompt player. Missing user recordings are silent;
	# every visible guide and game flow remains completely editor-authored.
	calibration_voice = CalibrationVoice.new()
	calibration_voice.name = "CalibrationVoice"
	add_child(calibration_voice)
	resized.connect(_fit_stage)
	_fit_stage()
	PoseService.status_updated.connect(_on_pose_status)
	PoseService.preview_updated.connect(_on_live_preview)
	# A previous round may have delivered its latest genuine JPEG before this
	# new Control connected. Rebind only a fresh preview; never replay ghost
	# skeletons from a stale or disconnected camera session.
	if PoseService.has_method("refresh_calibration_preview") and is_instance_valid(camera_inset) \
			and camera_inset.texture == null:
		PoseService.refresh_calibration_preview()
	# A newly entered round must measure its own holds; _ready runs before
	# the router delivers set_context for this selected camera activity.
	_reset_live_samples(false)
	_refresh_camera_status()
	# Only the styled CALIBRATION title may be visible during the first
	# 3 seconds. Store each direct child Control's authored state,
		# including inactive mode-specific artwork, without changing geometry.
	_show_intro_only(stage)
	set_process(true) # Intro and status continue even while the camera is off.


func _bind_scene_nodes(stage: Control) -> void:
	status_label = stage.get_node_or_null("CameraFeedback/CameraStatusLabel") as Label
	progress_label = stage.get_node_or_null("CameraFeedback/ProgressLabel") as Label
	camera_inset = stage.get_node_or_null("CameraArea/LiveCameraInset") as TextureRect
	skeleton_placement = stage.get_node_or_null("CameraArea/SkeletonPlacement") as ReferenceRect
	camera_unavailable = stage.get_node_or_null("CameraFeedback/CameraUnavailableLabel") as Label
	pose_guide_default = stage.get_node_or_null("PoseGuides/PoseGuideDefault") as Control
	pose_guide_left = stage.get_node_or_null("PoseGuides/PoseGuideLeft") as Control
	pose_guide_right = stage.get_node_or_null("PoseGuides/PoseGuideRight") as Control
	pose_guide_balloon_raise = stage.get_node_or_null("PoseGuides/PoseGuideBalloonRaise") as Control
	pose_guide_balloon_raise_left = stage.get_node_or_null("PoseGuides/PoseGuideBalloonRaiseLeft") as Control
	pose_guide_balloon_raise_right = stage.get_node_or_null("PoseGuides/PoseGuideBalloonRaiseRight") as Control
	pose_guide_plane_center = stage.get_node_or_null("PoseGuides/PoseGuidePlaneCenter") as Control
	pose_guide_plane_left = stage.get_node_or_null("PoseGuides/PoseGuidePlaneLeft") as Control
	pose_guide_plane_right = stage.get_node_or_null("PoseGuides/PoseGuidePlaneRight") as Control
	neutral_instruction = stage.get_node_or_null("NeutralInstruction") as Label
	# Explicit editor-authored per-zone guides, never runtime-translated.
	# PoseGuideDefault remains the CENTER pose; Human Plane guides are separate.
	pose_default_by_zone = {
		"CENTER": pose_guide_default,
		"RIGHT": pose_guide_right,
		"LEFT": pose_guide_left,
	}
	pose_raise_by_zone = {
		"CENTER": pose_guide_balloon_raise,
		"RIGHT": pose_guide_balloon_raise_right,
		"LEFT": pose_guide_balloon_raise_left,
	}
	for zone in ["CENTER", "RIGHT", "LEFT"]:
		art_title_nodes[zone] = stage.get_node_or_null("Directions/ArtTitle" + zone.capitalize()) as Control
		art_arrow_nodes[zone] = stage.get_node_or_null("Directions/ArtArrow" + zone.capitalize()) as Control
		art_hint_nodes[zone] = stage.get_node_or_null("Directions/ArtMoveHint" + zone.capitalize()) as Control
	for index in range(1, 4):
		art_step_nodes.append(stage.get_node_or_null("Directions/ArtStep%d" % index) as Control)
		art_countdown_nodes.append(stage.get_node_or_null("CountdownArtwork/ArtCountdown%d" % index) as Control)
	intro_overlay = stage.get_node_or_null("IntroOverlay") as Control
	success_overlay = stage.get_node_or_null("SuccessOverlay") as Control
	success_subtitle = stage.get_node_or_null("SuccessOverlay/SuccessSubtitle") as Label
	if is_instance_valid(success_subtitle):
		authored_success_subtitle = success_subtitle.text
	back_main_button = stage.get_node_or_null("Navigation/BackButton") as Button
	if back_main_button:
		back_main_button.pressed.connect(_go_back)
		back_main_button.disabled = false
		back_main_button.focus_mode = Control.FOCUS_ALL
	else:
		push_error("Calibration requires an editor-authored TutorialStage/Navigation/BackButton.")
	if camera_inset:
		camera_inset.visible = false
	if is_instance_valid(intro_overlay):
		intro_overlay.visible = true
	if is_instance_valid(success_overlay):
		success_overlay.visible = false


func _show_intro_only(stage: Control) -> void:
	intro_stage_visibility.clear()
	for child in stage.get_children():
		if child is Control and child != intro_overlay:
			var visual := child as Control
			intro_stage_visibility[visual] = visual.visible
			visual.visible = false
	if is_instance_valid(intro_overlay):
		# The intro's darkness is editor-authored on IntroOverlay (0.66 black,
		# combined with the existing ClassroomDimmer for about 69% opacity).
		# Never force its alpha to zero: that hid the intended intro treatment.
		intro_overlay.visible = true


func _finish_intro_only() -> void:
	for saved_node in intro_stage_visibility:
		if is_instance_valid(saved_node):
			(saved_node as Control).visible = bool(intro_stage_visibility[saved_node])
	intro_stage_visibility.clear()
	if is_instance_valid(intro_overlay):
		intro_overlay.visible = false
	# A Retry scene can mount AFTER an active camera's latest JPEG was emitted.
	# Refresh it now instead of requiring the student to physically leave and
	# re-enter the YOLO camera before the new screen shows its bones.
	if PoseService.has_method("refresh_calibration_preview") and is_instance_valid(camera_inset) \
			and camera_inset.texture == null:
		PoseService.refresh_calibration_preview()
	# A camera texture may have arrived while the footer and HUD were hidden.
		# Restore the real feed without revealing other mode-specific controls.
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


func _show_success_only() -> void:
	var stage := get_node_or_null("TutorialStage") as Control
	if stage == null or not is_instance_valid(success_overlay):
		push_error("Calibration requires an editor-authored SuccessOverlay.")
		return
	success_stage_visibility.clear()
	for child in stage.get_children():
		if child is Control and child != success_overlay:
			var visual := child as Control
			success_stage_visibility[visual] = visual.visible
			visual.visible = false
	if is_instance_valid(back_main_button):
		back_main_button.release_focus()
	success_overlay.visible = true


func _hide_success_only() -> void:
	if is_instance_valid(success_overlay):
		success_overlay.visible = false
	for saved_node in success_stage_visibility:
		if is_instance_valid(saved_node):
			(saved_node as Control).visible = bool(success_stage_visibility[saved_node])
	success_stage_visibility.clear()
	success_running = false
	success_elapsed = 0.0
	if is_instance_valid(camera_inset):
		camera_inset.visible = not intro_running and PoseService.active and camera_inset.texture != null


func _begin_success() -> void:
	# Only a completed, source-verified SOLO round may show the success title.
	if intro_running or success_running or passing_to_ready or not _has_fresh_solo_pose() \
			or not bool(PoseService.calibration.get("valid", false)) \
			or (_is_human_plane() and not bool(PoseService.plane_calibration.get("valid", false))):
		return
	success_running = true
	success_elapsed = 0.0
	transition_queued = true
	_show_success_only()
	if is_instance_valid(calibration_voice):
		calibration_voice.call("play_stage", "%s:success" % _capture_voice_activity(), "success")


func _fit_stage() -> void:
	var stage := get_node_or_null("TutorialStage") as Control
	if is_instance_valid(stage):
		ART.fit(self, stage, DESIGN_SIZE)


func set_context(value: Dictionary) -> void:
	var previous_activity := String(context.get("activity", ""))
	camera_entry_requested = not value.is_empty()
	context = value.duplicate(true)
	if is_instance_valid(success_subtitle):
		success_subtitle.text = "Ready to play!" if _single_neutral_body_mode() else authored_success_subtitle
	# Stale settings from previous menu routes must not enable keyboard play.
	context["keyboard_mode"] = false
	# set_context normally arrives during the introduction. If an existing
	# screen is repurposed after it, discard its previous activity's holds.
	if not intro_running and previous_activity != String(context.get("activity", "")):
		_reset_live_samples(false)
	# Entering this screen means a NEW ROUND. It is never a way to resume a
	# paused/absent gameplay student. Old measurements must not bypass the new
	# round; preserve an already running camera/model without binding its ID.
	if camera_entry_requested and (previous_activity.is_empty() \
			or previous_activity != String(context.get("activity", "")) \
			or passing_to_ready \
			or bool(value.get("new_round", false)) or bool(value.get("round_restart", false))):
		passing_to_ready = false
		_clear_previous_calibration_for_reentry()
	if not intro_running:
		_update_target_guide()
		_set_stage_instruction()
	_try_start_camera()
	if PoseService.has_method("refresh_calibration_preview"):
		PoseService.refresh_calibration_preview()
	capture_camera_session_token = String(PoseService.session_token)
	_refresh_camera_status()


func _is_human_plane() -> bool:
	return String(context.get("activity", "")).strip_edges() == "Human Plane"


func _is_balloon_popping() -> bool:
	return String(context.get("activity", "")).strip_edges() == "Balloon Popping"


func _single_neutral_body_mode() -> bool:
	# The dedicated multiplayer camera scene and Human Plane retain their own
	# genuine capture protocols; never enter this mode for either.
	return String(context.get("player_mode", "Single Player")).to_lower() != "multiplayer" \
		and String(context.get("activity", "")).strip_edges() in ["Catch the Word", "Balloon Popping"]


func _sample_matches_pose_phase(sample: Dictionary) -> bool:
	# Balloon must prove BOTH wrists on this SAME authenticated YOLO packet.
	# hand_up is only an either-hand shooting gesture; hand_up=false alone
	# cannot establish two lowered hands. Fail closed on partial occlusion.
	# Calibration-only raw measurements bypass the *shooting* release latch:
	# they still require genuinely observed shoulders/wrists in a fresh SOLO
	# packet. The legacy fields remain for older isolated mock-only fixtures.
	if _is_balloon_popping():
		if not bool(sample.get("calibration_hand_observation_valid",
				sample.get("hand_observation_valid", false))):
			return false
		var both_up := bool(sample.get("calibration_both_hands_up",
				sample.get("both_hands_up", false)))
		var both_down := bool(sample.get("calibration_both_hands_down",
				sample.get("both_hands_down", false)))
		if both_up == both_down:
			return false
		return both_up if balloon_pose_phase == 1 else both_down
	# Catch keeps its existing observation contract; Balloon alone requires
	# strict independent raw two-wrist calibration evidence.
	return bool(sample.get("hand_observation_valid", false)) and not bool(sample.get("hand_up", false))


func _capture_order() -> Array:
	if _single_neutral_body_mode():
		return ["NEUTRAL"]
	# Balloon's six hand holds and Catch both visit CENTER→RIGHT→LEFT.
	# Human Plane retains its single physical CENTER T-pose reference.
	if _is_human_plane():
		return ["CENTER"]
	return BALLOON_CAPTURE_ORDER if _is_balloon_popping() else CAPTURE_ORDER


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


func _refresh_camera_status() -> void:
	var state := String(PoseService.current_status.get("state", "off"))
	if is_instance_valid(camera_unavailable):
		var feed_is_visible := PoseService.active and is_instance_valid(camera_inset) and camera_inset.texture != null
		camera_unavailable.visible = not feed_is_visible and not intro_running and not success_running
		if not PoseService.active:
			camera_unavailable.text = ("CAMERA UNAVAILABLE\nAsk your teacher to check the camera."
				if _single_neutral_body_mode() else
				"CAMERA UNAVAILABLE\nAsk your teacher to check the camera.")
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
	camera_inset.visible = texture != null and not intro_running and not success_running
	_refresh_camera_status()


func _on_pose_status(_data: Dictionary) -> void:
	_refresh_camera_status()


func _process(delta: float) -> void:
	var tracking_delta := maxf(delta, 0.0)
	if intro_running:
		intro_elapsed += tracking_delta
		if intro_elapsed < INTRO_SECONDS:
			return
		# Never credit introduction time toward a student's stationary hold.
		tracking_delta = maxf(0.0, intro_elapsed - INTRO_SECONDS)
		intro_running = false
		# The required 8 measurements must belong to the live hold, not to
		# camera packets accumulated behind the introduction screen.
		last_fresh_sample_id = PoseService.latest_pose_sample_id
		_finish_intro_only()
	# A camera transport reset DURING new-round calibration discards partial
	# captures. Gameplay itself resumes after lost-camera without returning to
	# this scene; no enrolled track ID or tracking epoch is needed here.
	var session_now := String(PoseService.session_token)
	if capture_camera_session_token.is_empty():
		capture_camera_session_token = session_now
	elif session_now != capture_camera_session_token:
		capture_camera_session_token = session_now
		if success_running:
			# The student has ALREADY finished their real stationary holds.
			# A reconnect must supply new authenticated SOLO occupancy, but it
			# cannot discard that completed round or send them back to CENTER.
			# _has_fresh_raw_solo_on_camera checks the new packet's session.
			if _single_neutral_body_mode():
				_set_live_instruction("CAMERA RECONNECTING • Waiting for one student.")
			else:
				_set_live_instruction("CAMERA RECONNECTING • Wait for one student.")
			return
		_clear_previous_calibration_for_reentry()
		if _single_neutral_body_mode():
			_set_live_instruction("CAMERA SESSION CHANGED • START A NEW NEUTRAL HOLD.")
		else:
			_set_live_instruction("CAMERA SESSION CHANGED • CALIBRATE AGAIN.")
		return
	if success_running:
		# A finished round is LATCHED. Green skeletons, a wrist or a stable
		# standing position can temporarily disappear as the student MOVES.
		# Those joints are required for the original 3s physical holds, never
		# again for the post-success handoff. Trust ONLY fresh raw YOLO SOLO
		# occupancy with a live worker/transport and current session token.
		# Missing/zero/crowd/stale means FREEZE here, not back to CENTER.
		if not _has_fresh_raw_solo_on_camera() \
				or not bool(PoseService.calibration.get("valid", false)) \
				or (_is_human_plane() and not bool(PoseService.plane_calibration.get("valid", false))):
			_set_live_instruction("WAIT FOR ONE PERSON IN CAMERA • Calibration is saved.")
			return
		success_elapsed += tracking_delta
		if success_elapsed >= SUCCESS_SECONDS:
			_continue_flow()
		return
	if plane_demo_running:
		_process_plane_demonstration(tracking_delta)
		return
	var capture_order := _capture_order()
	if live_step >= capture_order.size():
		# The last stage already finished its authentic capture. A missing
		# pose here is a pending SUCCESS, not grounds to erase CENTER/RIGHT/LEFT.
		if not transition_queued and _has_fresh_solo_pose() \
				and bool(PoseService.calibration.get("valid", false)) \
				and (not _is_human_plane() or bool(PoseService.plane_calibration.get("valid", false))):
			_begin_success()
		return
	if transition_queued:
		return
	if _is_human_plane():
		_process_stationary_plane(tracking_delta)
		return
	if _single_neutral_body_mode():
		_process_single_neutral_body(tracking_delta)
		return
	if not PoseService.active:
		_reset_current_hold()
		_set_live_instruction("CAMERA UNAVAILABLE • Ask your teacher for assistance.")
		if is_instance_valid(progress_label):
			progress_label.text = "Camera unavailable • Ask your teacher."
		return
	if not _has_fresh_solo_pose():
		# Tracking loss interrupts the CURRENT hold, not previously measured
		# CENTER or RIGHT positions. Only a fresh continuous hold may advance.
		if _keep_hold_for_brief_solo_dropout(tracking_delta):
			return
		_reset_current_hold()
		var detail := String(PoseService.current_status.get("detail", "")).strip_edges()
		if detail.is_empty():
			detail = "We lost sight of you. Please step back into the camera view."
		# The live camera service explains the current condition, without
		# directing a child toward removed STOP/RESET/SKIP controls.
		if is_instance_valid(status_label):
			status_label.text = detail.left(78)
		if is_instance_valid(progress_label):
			progress_label.text = "Return to the camera's visible playing area."
		_set_live_instruction("%s\nReturn to the visible playing area." % detail)
		return
	var x := PoseService.player_x
	var target: String = capture_order[live_step]
	if not _inside_zone(target, x):
		_reset_current_hold()
		_set_live_instruction("%s • %s\nStand inside the highlighted area." % STAGE_TEXT[target])
		return
	if anchor_x < 0.0:
		anchor_x = x
		live_samples.clear()
		live_timer = 0.0
		packet_gap_seconds = 0.0
	if absf(x - anchor_x) > MAX_SAMPLE_SPREAD:
		_reset_current_hold()
		_set_live_instruction("MOVEMENT DETECTED • Stop moving, then hold for 3 seconds.")
		return
	var fresh_samples: Array[Dictionary] = PoseService.get_pose_samples_after(last_fresh_sample_id)
	var has_fresh_packet := not fresh_samples.is_empty()
	if has_fresh_packet:
		# Tracking must produce NEW poses to earn hold time. A retained pose
		# can keep rendering the guide, but never advance the countdown.
		if packet_gap_seconds > _allowed_packet_gap_seconds():
			_reset_current_hold()
			_set_live_instruction("POSE FRAMES PAUSED • Hold will restart after tracking resumes.")
			return
		if not fresh_samples.is_empty():
			# Every source packet has its own strictly increasing worker timestamp.
			# The renderer only needs the newest pose, but the three-second hold
			# must not discard seven genuine detections in the same UI frame.
			for sample: Dictionary in fresh_samples:
				var sample_x := float(sample.get("x", -1.0))
				if int(sample.get("people", -1)) != 1 \
						or not _inside_zone(target, sample_x) or absf(sample_x - anchor_x) > MAX_SAMPLE_SPREAD:
					_reset_current_hold()
					_set_live_instruction("ONE PERSON ONLY • Keep your position steady.")
					return
				if not _sample_matches_pose_phase(sample):
					if _keep_hold_for_brief_wrist_dropout(tracking_delta, sample):
						_set_live_instruction("KEEP YOUR POSITION • Hold paused while wrists are briefly hidden.")
						return
					_reset_current_hold()
					var prompt: Array = BALLOON_RAISE_TEXT if balloon_pose_phase == 1 else BALLOON_DEFAULT_TEXT
					_set_live_instruction("%s • Hold for 3 seconds.\n%s." % prompt)
					return
				live_samples.append(sample_x)
				last_fresh_sample_id = int(sample["id"])
		# Count the actual elapsed time between fresh, stable pose packets.
		# Inference is slower than rendering, so adding only this frame's delta
		# would incorrectly turn a 3-second hold into a much longer wait.
		# The camera was genuinely unable to verify the torso during any brief
		# solo-confidence dips. Do not credit that unobserved time as a hold.
		live_timer += tracking_delta + maxf(0.0, packet_gap_seconds - brief_solo_invalid_seconds)
		packet_gap_seconds = 0.0
		brief_solo_invalid_seconds = 0.0
	else:
		packet_gap_seconds += tracking_delta
		if packet_gap_seconds > _allowed_packet_gap_seconds():
			_reset_current_hold()
			_set_live_instruction("POSE FRAMES PAUSED • Hold will restart after tracking resumes.")
			return
	var remaining := maxi(0, ceili(HOLD_SECONDS - live_timer))
	_update_hold_countdown()
	if is_instance_valid(progress_label):
		progress_label.text = "%s • %s • %d MORE SECONDS" % [target,
				"BOTH HANDS UP" if _is_balloon_popping() and balloon_pose_phase == 1 else "BOTH HANDS DOWN",
			remaining]
	if _is_balloon_popping():
		var pose_prompt: Array = BALLOON_RAISE_TEXT if balloon_pose_phase == 1 else BALLOON_DEFAULT_TEXT
		_set_live_instruction("%s • %s: %d seconds\n%s • %s." % [
			STAGE_TEXT[target][0], pose_prompt[0], remaining, STAGE_TEXT[target][1], pose_prompt[1]])
	else:
		_set_live_instruction("%s • HOLD STILL: %d seconds\n%s." % [STAGE_TEXT[target][0], remaining, STAGE_TEXT[target][1]])
	if live_timer < HOLD_SECONDS or live_samples.size() < REQUIRED_SAMPLES:
		return
	var sum := 0.0
	for sample in live_samples:
		sum += sample
	if not _is_balloon_popping() or balloon_pose_phase == 0:
		measured_points[target.to_lower()] = sum / float(live_samples.size())
	# Balloon has TWO genuine holds at EACH real floor position: both
	# hands DOWN for 3s then BOTH hands UP for 3s. The NEXT zone is not
	# entered until both source-verified gestures have succeeded.
	if _is_balloon_popping() and balloon_pose_phase == 0:
		balloon_pose_phase = 1
		_reset_current_hold()
		_update_target_guide()
		_set_stage_instruction()
		return
	balloon_pose_phase = 0
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
		if is_instance_valid(progress_label):
			progress_label.text = "CALIBRATION SUCCESSFUL • 3 REAL POSITIONS MEASURED"
		_set_live_instruction("CALIBRATION COMPLETE! Preparing the game.")
		_begin_success()
	else:
		_reset_live_samples()
		_set_live_instruction("POSITIONS TOO CLOSE • Please repeat with wider LEFT and RIGHT movements.")


func _process_single_neutral_body(delta: float) -> void:
	# Catch and Balloon share ONE fresh 3-second neutral standing observation.
	# The student may stand ANYWHERE visible in camera space; never require
	# CENTER/RIGHT/LEFT zones, raised hands, or made-up side measurements.
	if not _has_fresh_solo_pose():
		if _keep_hold_for_brief_solo_dropout(delta):
			plane_hold_invalid_seconds += maxf(delta, 0.0)
			return
		_reset_current_hold()
		_set_live_instruction("ONE STUDENT IN CAMERA • Stand still for 3 seconds.")
		if is_instance_valid(progress_label):
			progress_label.text = "STAND STILL • WAITING FOR LIVE POSE"
		return
	var samples: Array[Dictionary] = PoseService.get_pose_samples_after(last_fresh_sample_id)
	if samples.is_empty():
		packet_gap_seconds += delta
		if packet_gap_seconds > _allowed_packet_gap_seconds():
			_reset_current_hold()
			_set_live_instruction("POSE FRAMES PAUSED • Hold will restart.")
		return
	for sample: Dictionary in samples:
		var sample_id := int(sample.get("id", -1))
		var source_x := float(sample.get("x", -1.0))
		var packet_when := float(sample.get("when", -1.0))
		if sample_id <= last_fresh_sample_id or int(sample.get("people", -1)) != 1 \
				or not is_finite(source_x) or source_x < 0.0 or source_x > 1.0 \
				or not is_finite(packet_when) or packet_when < 0.0:
			_reset_current_hold()
			_set_live_instruction("ONE VISIBLE STUDENT ONLY • Please stand still.")
			return
		if plane_hold_started_when < 0.0:
			anchor_x = source_x
			plane_hold_started_when = packet_when
			plane_last_sample_when = packet_when
		if absf(source_x - anchor_x) > MAX_SAMPLE_SPREAD \
				or (not live_samples.is_empty() and packet_when <= plane_last_sample_when) \
				or packet_when - plane_last_sample_when > _allowed_packet_gap_seconds():
			_reset_current_hold()
			_set_live_instruction("MOVEMENT DETECTED • Stand still and restart the 3-second hold.")
			return
		plane_last_sample_when = packet_when
		live_samples.append(source_x)
		last_fresh_sample_id = sample_id
	plane_hold_invalid_seconds += brief_solo_invalid_seconds
	brief_solo_invalid_seconds = 0.0
	live_timer = maxf(0.0, plane_last_sample_when - plane_hold_started_when - plane_hold_invalid_seconds)
	packet_gap_seconds = 0.0
	_update_hold_countdown()
	var remaining := maxi(0, ceili(HOLD_SECONDS - live_timer))
	if is_instance_valid(progress_label):
		progress_label.text = "STAND STILL • %d SECONDS • %d / %d LIVE POSES" % [
			remaining, live_samples.size(), REQUIRED_SAMPLES]
	_set_live_instruction("STAND COMFORTABLY WHERE THE CAMERA CAN SEE YOU • %d SECONDS" % remaining)
	if live_timer < HOLD_SECONDS or live_samples.size() < REQUIRED_SAMPLES:
		return
	# Robust median of actual source packet X; median deviation measures
	# natural body jitter without implying physical LEFT or RIGHT movement.
	var ordered := live_samples.duplicate()
	ordered.sort()
	var center := _plane_median(ordered)
	var deviations: Array[float] = []
	for value in ordered:
		deviations.append(absf(value - center))
	deviations.sort()
	var noise := _plane_median(deviations)
	if noise > 0.12 or not PoseService.has_method("set_neutral_body_calibration") \
			or not PoseService.set_neutral_body_calibration(center, noise):
		_reset_live_samples()
		_set_live_instruction("STAND FULLY IN CAMERA VIEW AND KEEP STILL FOR 3 SECONDS.")
		return
	measured_points["center"] = center
	measured_points["neutral_noise"] = noise
	live_step = 1
	_reset_current_hold()
	if is_instance_valid(progress_label):
		progress_label.text = "CALIBRATION SUCCESSFUL • NEUTRAL STANCE MEASURED"
	_set_live_instruction("NEUTRAL CALIBRATION COMPLETE! Preparing the game.")
	_begin_success()


func _process_stationary_plane(delta: float) -> void:
	# One freshly detected, unambiguous person and distinct real source packets
	# are sufficient. No registered tracker ID or matching tracking epoch.
	if not _has_fresh_solo_pose():
		if _keep_hold_for_brief_solo_dropout(delta):
			return
		_reset_current_hold()
		_set_live_instruction("ONE PERSON IN CAMERA • Stand alone in center.")
		return
	var fresh_samples: Array[Dictionary] = PoseService.get_pose_samples_after(last_fresh_sample_id)
	if fresh_samples.is_empty():
		packet_gap_seconds += delta
		if packet_gap_seconds > _allowed_packet_gap_seconds():
			_reset_current_hold()
			_set_live_instruction("TRACKING PAUSED • Hold restarts after new pose frames.")
		return
	for sample: Dictionary in fresh_samples:
		var sample_id := int(sample.get("id", -1))
		# The T-pose detector already verifies both wrists and elbows on this
		# exact source frame and emits the corresponding real arm-bank value.
		# Prefer that neutral reference: an independent smoothed torso tracker
		# can temporarily have no plane_steering despite a perfectly valid T.
		# The legacy source steering fallback supports older saved QA packets.
		var raw: Variant = sample.get("plane_bank", sample.get("plane_steering", null))
		var camera_x := float(sample.get("x", -1.0))
		var packet_when := float(sample.get("when", -1.0))
		if not bool(sample.get("plane_t_pose_valid", false)) \
				and _keep_hold_for_brief_wrist_dropout(delta, sample):
			_set_live_instruction("HOLD YOUR CENTER POSITION • Wrist tracking paused briefly.")
			return
		if int(sample.get("people", -1)) != 1 \
			or not bool(sample.get("plane_t_pose_valid", false)) \
			or not (raw is float or raw is int) \
			or not is_finite(float(raw)) or absf(float(raw)) > 1.0 \
			or not is_finite(packet_when) or camera_x < 0.28 or camera_x > 0.72:
			_reset_current_hold()
			_set_live_instruction("ONE PERSON • HOLD A FULL T-POSE IN CENTER.")
			return
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
			_set_live_instruction("MOVED FROM CENTER • Hold still again.")
			return
		plane_last_sample_when = packet_when
		plane_hold_invalid_seconds += brief_solo_invalid_seconds
		brief_solo_invalid_seconds = 0.0
		live_timer = maxf(0.0, packet_when - plane_hold_started_when - plane_hold_invalid_seconds)
		live_samples.append(steering)
		plane_camera_samples.append(camera_x)
		last_fresh_sample_id = sample_id
	packet_gap_seconds = 0.0
	_update_hold_countdown()
	var remaining := maxi(0, ceili(PLANE_HOLD_SECONDS - live_timer))
	if is_instance_valid(progress_label):
		progress_label.text = "CENTER STEADY • %d SEC • %d / %d LIVE POSES" % [remaining, live_samples.size(), REQUIRED_SAMPLES]
	_set_live_instruction("HOLD YOUR ARMS OUT IN A T-POSE • %d SECONDS" % remaining)
	if live_timer < PLANE_HOLD_SECONDS or live_samples.size() < REQUIRED_SAMPLES:
		return
		# Median and median-absolute-deviation reject incidental arm jitter.
	# Actual LEFT/RIGHT movement is tracked live; no side endpoint is invented.
	var sorted_steering := live_samples.duplicate()
	sorted_steering.sort()
	if sorted_steering.back() - sorted_steering.front() > PLANE_NEUTRAL_MAX_SPREAD:
		_reset_current_hold()
		_set_live_instruction("PLEASE STAND A LITTLE STEADIER IN CENTER.\nPakipirmi sa gitna.")
		return
	var neutral_steering := _plane_median(sorted_steering)
	var deviations: Array[float] = []
	for value in sorted_steering:
		deviations.append(absf(value - neutral_steering))
	deviations.sort()
	var neutral_noise := _plane_median(deviations)
	var total_camera_x := 0.0
	for camera_x in plane_camera_samples:
		total_camera_x += camera_x
		# The service's 'center' is the measured torso X (0..1). T-pose
		# neutral bank is independent (-1..1) and usually equals 0.
	var camera_center_x := total_camera_x / float(plane_camera_samples.size())
	measured_points["center"] = camera_center_x
	measured_points["neutral_steering"] = neutral_steering
	measured_points["neutral_noise"] = neutral_noise
	measured_points["camera_center_x"] = camera_center_x
	var accepted := PoseService.set_stationary_plane_calibration(
		camera_center_x, -1, camera_center_x, neutral_noise
	)
	if not accepted:
		_reset_live_samples()
		_set_live_instruction("STAND COMFORTABLY IN THE CAMERA'S CENTER, THEN HOLD STILL.")
		return
	live_step = 1
	_reset_current_hold()
	plane_demo_running = true
	plane_demo_elapsed = 0.0
	plane_demo_last_announced_side = ""
	_update_target_guide()
	if is_instance_valid(progress_label):
		progress_label.text = "CENTER CALIBRATED • WATCH LEFT AND RIGHT TURN GUIDES"
	_set_live_instruction("CENTER COMPLETE • Watch the LEFT and RIGHT arm movement guides.")
	_announce_plane_demo_side("left")


func _process_plane_demonstration(delta: float) -> void:
	# The neutral CENTER T-pose is already saved. The two side images are a
	# visual lesson only: no new physical zone, hold timer or calibration samples.
	# Continue showing the current image if occupancy is momentarily uncertain.
	if not _has_fresh_raw_solo_on_camera():
		return
	plane_demo_elapsed += maxf(delta, 0.0)
	var side := "left" if plane_demo_elapsed < PLANE_DEMO_SECONDS_PER_SIDE else "right"
	_announce_plane_demo_side(side)
	_sync_reference_art()
	if plane_demo_elapsed >= 2.0 * PLANE_DEMO_SECONDS_PER_SIDE and _has_fresh_solo_pose():
		plane_demo_running = false
		_begin_success()


func _announce_plane_demo_side(side: String) -> void:
	if plane_demo_last_announced_side == side:
		return
	plane_demo_last_announced_side = side
	if is_instance_valid(calibration_voice):
		calibration_voice.call("play_stage", "%s:demo:%s" % [_capture_voice_activity(), side],
			"plane_" + side)


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


func _keep_hold_for_brief_solo_dropout(delta: float) -> bool:
	# This is *not* a synthetic valid pose: calibration never advances on a
	# rejected packet. It only retains the existing real samples for a brief
	# confidence hiccup while a newly received source frame still reports one
	# safe foreground person. Never interpret distant spectators as a crowd.
	var status: Dictionary = PoseService.current_status
	if not PoseService.active or String(status.get("state", "")) != "tracking" \
			or not bool(status.get("camera", false)) \
			or PoseService.fresh_camera_population() != 1 \
			or PoseService.foreground_is_ambiguous() \
			or Time.get_ticks_msec() - int(PoseService.get("_last_packet_ms")) > 250:
		return false
	var unobserved := maxf(delta, 0.0)
	packet_gap_seconds += unobserved
	brief_solo_invalid_seconds += unobserved
	if packet_gap_seconds > minf(SOLO_POSE_HOLD_DROPOUT_SECONDS, _allowed_packet_gap_seconds()):
		return false
	# Pause the on-screen hold number. No pose samples, timer credit or progress.
	return true


func _keep_hold_for_brief_wrist_dropout(delta: float, sample: Dictionary) -> bool:
	# A fresh source frame still sees exactly one stationary child, but cannot
	# classify BOTH wrists. Keep previous genuine samples for <=350ms. The bad
	# frame earns neither a pose sample nor countdown time. A known wrong hand
	# gesture, moved torso, missing person or crowded view always resets.
	if not _has_fresh_solo_pose() or int(sample.get("people", -1)) != 1 \
			or bool(sample.get("calibration_hand_observation_valid",
				sample.get("hand_observation_valid", false))) \
			or bool(sample.get("calibration_both_hands_up",
				sample.get("both_hands_up", false))) \
			or bool(sample.get("calibration_both_hands_down",
				sample.get("both_hands_down", false))) \
			or int(sample.get("id", -1)) <= last_fresh_sample_id:
		return false
	var x := float(sample.get("x", -1.0))
	var target: String = String(_capture_order()[live_step])
	if not _inside_zone(target, x) or anchor_x < 0.0 \
			or absf(x - anchor_x) > MAX_SAMPLE_SPREAD:
		return false
	brief_solo_invalid_seconds += maxf(delta, 0.0)
	if brief_solo_invalid_seconds > SOLO_POSE_HOLD_DROPOUT_SECONDS:
		return false
	last_fresh_sample_id = int(sample["id"])
	packet_gap_seconds = 0.0 # A source packet arrived, with INVALID wrists.
	return true


func _set_stage_instruction() -> void:
	var capture_order := _capture_order()
	if live_step >= capture_order.size():
		return
	if _single_neutral_body_mode():
		if is_instance_valid(progress_label):
			progress_label.text = "STAND STILL • ONE 3-SECOND HOLD"
		_set_live_instruction("STAND WHERE THE CAMERA CAN SEE YOU • HOLD STILL FOR 3 SECONDS")
		_sync_reference_art()
		# Legacy movement/hand-pose audio says CENTER, RIGHT, LEFT or BOTH
		# HANDS UP. It must not instruct children to perform removed stages.
		return
	var target: String = capture_order[live_step]
	var messages: Array = PLANE_STAGE_TEXT[target] if _is_human_plane() else STAGE_TEXT[target]
	if _is_balloon_popping():
		var pose_words: Array = BALLOON_RAISE_TEXT if balloon_pose_phase == 1 else BALLOON_DEFAULT_TEXT
		messages = ["%s • %s" % [messages[0], pose_words[0]],
			"%s • %s" % [messages[1], pose_words[1]]]
	# The independently editable PNG titles and arrows now supply the visual
	# heading/position. The deleted legacy labels are never recreated in code.
	if is_instance_valid(progress_label):
		progress_label.text = ("ONE T-POSE HOLD • ARMS OUT" if _is_human_plane() else
				"%s • %s" % [target, "RAISE BOTH HANDS" if balloon_pose_phase == 1 else "BOTH HANDS DOWN"]
			if _is_balloon_popping() else "%s • STAND IN POSITION" % target)
	_set_live_instruction("%s\n%s" % messages)
	_sync_reference_art()
	# This method may be called to refresh labels after a pose flicker. The
	# helper keys every real stage/phase once and never restarts speech on
	# repeated refreshes. Intro and success are narration-free except SUCCESS.
	if intro_running or success_running or not is_instance_valid(calibration_voice):
		return
	var phase := "raised" if _is_balloon_popping() and balloon_pose_phase == 1 else "default"
	var stage_id := "%s:%s:%s" % [_capture_voice_activity(), target, phase]
	if _is_human_plane():
		calibration_voice.call("play_stage", stage_id, "t_pose")
	elif _is_balloon_popping():
		if balloon_pose_phase == 1:
			# This genuinely bilateral calibration stage has its own recorded
			# VOICE1 clip. Do not substitute the one-hand shooting cue.
			calibration_voice.call("play_stage", stage_id, "raise_both_hands")
		else:
				# Center starts with BOTH DOWN; side transitions announce the new
				# location then the separate 'lower both hands' voice recording.
				if target == "CENTER":
					calibration_voice.call("play_stage", stage_id, "hands_down")
				else:
					calibration_voice.call("play_stage", stage_id, target.to_lower(), "hands_down")
	else:
		# Actual supplied pair: "Move to the [zone]" then "Stay to the [zone]".
		# Follow-up starts only when MOVE finishes and cancels on stage changes.
		calibration_voice.call("play_stage", stage_id, target.to_lower(), "stay_" + target.to_lower())


func _capture_voice_activity() -> String:
	return String(context.get("activity", "Catch the Word")).strip_edges()


func _update_hold_countdown() -> void:
	# Display the large 3/2/1 only during a real stationary, fresh-pose
	# hold. Moving, losing the pose, or stale packets hides and resets it.
	_sync_reference_art()


func _set_live_instruction(message: String) -> void:
	# Retained only for diagnostics and QA. User removed InstructionLabel;
	# mode-specific editor-authored PNG artwork is the on-screen instruction.
	latest_instruction_text = message


func _update_target_guide() -> void:
	# Five authored pose PNGs provide the visual standing/arm guides. Obsolete
	# neon guide textures and duplicate lane panels have been retired.
	_sync_reference_art()


func _sync_reference_art() -> void:
	# Pure visibility switches preserve every asset's Godot Inspector transform
	# (the teacher can drag/resize title, step badge and digits independently).
	# The router calls set_context AFTER _ready hid every TutorialStage sibling
	# for the three-second intro. Its new-round reset reaches this method before
	# the introduction ends, so never re-show the header, pose guide, arrows,
	# countdown art, or hints beneath the translucent CALIBRATION screen.
	# _finish_intro_only restores the authored nodes and synchronizes the active
	# zone once the full three seconds have elapsed.
	if intro_running or success_running:
		return
	var capture_order := _capture_order()
	var active_zone: String = "DONE" if live_step >= capture_order.size() else String(capture_order[live_step])
	var plane_mode := _is_human_plane()
	var neutral_mode := _single_neutral_body_mode()
	var showing_pose := active_zone != "DONE" and not neutral_mode
	if is_instance_valid(neutral_instruction):
		neutral_instruction.visible = neutral_mode and active_zone != "DONE"
		if neutral_instruction.visible:
				neutral_instruction.text = "STAND NATURALLY • HOLD STILL FOR 3 SECONDS"
	# Each zone now owns its OWN PNG TextureRect in calibration.tscn:
	# CENTER=PoseGuideDefault, RIGHT=PoseGuideRight, LEFT=PoseGuideLeft.
	# Teachers can independently drag/resize each guide in Godot. Runtime
	# ONLY toggles visibility; no X/Y/size/scale assignment occurs here.
	for zone in pose_default_by_zone:
		var default_guide := pose_default_by_zone[zone] as Control
		if is_instance_valid(default_guide):
			default_guide.visible = showing_pose and not plane_mode \
				and zone == active_zone and (not _is_balloon_popping() or balloon_pose_phase == 0)
	for zone in pose_raise_by_zone:
		var raised_guide := pose_raise_by_zone[zone] as Control
		if is_instance_valid(raised_guide):
			raised_guide.visible = showing_pose and not plane_mode \
				and _is_balloon_popping() and balloon_pose_phase == 1 and zone == active_zone
	if is_instance_valid(pose_guide_plane_center):
		pose_guide_plane_center.visible = showing_pose and plane_mode and not plane_demo_running
	if is_instance_valid(pose_guide_plane_left):
		pose_guide_plane_left.visible = plane_mode and plane_demo_running \
			and plane_demo_elapsed < PLANE_DEMO_SECONDS_PER_SIDE
	if is_instance_valid(pose_guide_plane_right):
		pose_guide_plane_right.visible = plane_mode and plane_demo_running \
			and plane_demo_elapsed >= PLANE_DEMO_SECONDS_PER_SIDE
	for zone in art_title_nodes:
		var title := art_title_nodes[zone] as Control
		if is_instance_valid(title):
			title.visible = not plane_mode and not neutral_mode and zone == active_zone
	for zone in art_arrow_nodes:
		var arrow := art_arrow_nodes[zone] as Control
		if is_instance_valid(arrow):
			arrow.visible = not plane_mode and not neutral_mode and zone == active_zone
	for zone in art_hint_nodes:
		var hint := art_hint_nodes[zone] as Control
		if is_instance_valid(hint):
			hint.visible = not plane_mode and not neutral_mode and zone == active_zone
	for index in range(art_step_nodes.size()):
		if is_instance_valid(art_step_nodes[index]):
			art_step_nodes[index].visible = not plane_mode and not neutral_mode and live_step == index
	# The illustrated countdown starts at 3 even while we await the student;
	# unlike the decoration, calibration time only advances on NEW valid
	# stationary pose frames, as verified by the underlying hold timer.
	var remaining := clampi(ceili(_hold_seconds() - live_timer), 1, 3)
	for index in range(art_countdown_nodes.size()):
		if is_instance_valid(art_countdown_nodes[index]):
			art_countdown_nodes[index].visible = not plane_demo_running \
				and live_step < capture_order.size() and index == remaining - 1
func _reset_current_hold() -> void:
	live_timer = 0.0
	anchor_x = -1.0
	anchor_plane_steering = -999.0
	plane_hold_started_when = -1.0
	plane_last_sample_when = -1.0
	plane_camera_samples.clear()
	live_samples.clear()
	last_fresh_sample_id = PoseService.latest_pose_sample_id
	packet_gap_seconds = 0.0
	brief_solo_invalid_seconds = 0.0
	plane_hold_invalid_seconds = 0.0
	_update_hold_countdown()


func _reset_live_samples(clear_service_calibration: bool = true) -> void:
	# Only a deliberate NEW measurement attempt clears already announced
	# stages. Tracking/pose flickers call _reset_current_hold, never this.
	if is_instance_valid(calibration_voice):
		calibration_voice.call("reset_for_new_attempt")
	if success_running:
		_hide_success_only()
	transition_queued = false
	plane_demo_running = false
	plane_demo_elapsed = 0.0
	plane_demo_last_announced_side = ""
	live_step = 0
	balloon_pose_phase = 0
	measured_points.clear()
	_reset_current_hold()
	if clear_service_calibration:
		PoseService.calibration.clear()
		PoseService.plane_calibration.clear()
	_update_target_guide()
	_set_stage_instruction()


func _clear_previous_calibration_for_reentry() -> void:
	# Only called when entering a NEW round or when the camera itself changes
	# DURING calibration. Never part of mid-round gameplay tracking recovery.
	_reset_live_samples(false)
	if PoseService.has_method("begin_new_round_tracking"):
		PoseService.begin_new_round_tracking()
	if PoseService.has_method("clear_calibration_for_reentry"):
		PoseService.call("clear_calibration_for_reentry")
	# That compatibility method intentionally preserves a finished LIVE round.
	# But here the router explicitly mounted calibration for a NEW round, so
	# stale completed limits must be invalidated before new measurements begin.
	PoseService.calibration.clear()
	PoseService.plane_calibration.clear()


func _has_fresh_solo_pose() -> bool:
	# Only the authenticated foreground player can earn a physical 3-second,
	# eight-source-frame hold. Raw YOLO people may include distant spectators.
	var status: Dictionary = PoseService.current_status
	return PoseService.active and PoseService.has_valid_pose() \
		and PoseService.has_verified_foreground_player() \
		and String(status.get("state", "")) == "tracking" \
		and bool(status.get("pose", false)) \
		and PoseService.player_x >= 0.0 \
		and Time.get_ticks_msec() - PoseService.last_pose_ms <= PoseService.LOST_AFTER_MS


func _has_fresh_raw_solo_on_camera() -> bool:
	# Completed calibration can only hand off a verified foreground player.
	# Raw count remains diagnostic and includes distant classmates.
	# Its current_status must also belong to the current camera session so
	# packets from before a reconnect cannot release a completed round.
	return PoseService.has_verified_foreground_player() \
		and String(PoseService.current_status.get("token", "")) == String(PoseService.session_token)


func _continue_flow(skipped: bool = false) -> void:
	# No callers (including retired Continue/Skip) bypass the complete three-
	# second success overlay or an authenticated, source-fresh RAW SOLO camera.
	if skipped or passing_to_ready or not success_running or success_elapsed < SUCCESS_SECONDS:
		return
	var live_measured := _has_fresh_raw_solo_on_camera() \
		and bool(PoseService.calibration.get("valid", false))
	if _is_human_plane():
		live_measured = live_measured and live_step >= 1 \
			and measured_points.has("center") \
			and measured_points.has("neutral_noise") \
			and bool(PoseService.plane_calibration.get("valid", false))
	elif _single_neutral_body_mode():
		live_measured = live_measured and live_step >= 1 \
			and measured_points.has("center") and measured_points.has("neutral_noise") \
			and String(PoseService.calibration.get("mode", "")) == "neutral_body" \
			and bool(PoseService.calibration.get("neutral_only", false)) \
			and not measured_points.has("left") and not measured_points.has("right")
	else:
		live_measured = live_measured and live_step >= CAPTURE_ORDER.size() \
			and measured_points.has("center") and measured_points.has("right") \
			and measured_points.has("left")
	live_measured = live_measured and not bool(PoseService.calibration.get("center_only", false))
	if not live_measured:
		if _single_neutral_body_mode():
			_set_live_instruction("COMPLETE ONE LIVE THREE-SECOND NEUTRAL STANDING HOLD FIRST.")
		else:
			_set_live_instruction("COMPLETE THE SINGLE LIVE HAND-POSE HOLD FIRST." if _is_human_plane() else
				"COMPLETE ALL THREE LIVE POSITIONS FIRST.")
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
		payload["plane_steering_mode"] = "continuous_arm_bank"
		payload["calibration_neutral_only"] = true
		payload["calibration_steering_sensitivity"] = PoseService.plane_calibration["sensitivity"]
		payload["calibration_steering_deadzone"] = PoseService.plane_calibration["deadzone"]
		payload["calibration_camera_center_x"] = PoseService.plane_calibration["camera_center_x"]
	elif _single_neutral_body_mode():
		payload.erase("calibration_left")
		payload.erase("calibration_right")
		payload["calibration_neutral_only"] = true
	else:
		payload["calibration_left"] = PoseService.calibration["left"]
		payload["calibration_right"] = PoseService.calibration["right"]
	passing_to_ready = true
	if is_instance_valid(calibration_voice):
		calibration_voice.call("stop")
		# One shared gameplay wrapper handles the calibrated 3-2-1 countdown
		# for both the Guided Tutorial and normal Play entry routes.
	requested.emit("gameplay", payload)


func _go_back() -> void:
	if is_instance_valid(calibration_voice):
		calibration_voice.call("stop")
	if success_running:
		_hide_success_only()
	transition_queued = false
	passing_to_ready = false
	if PoseService.active:
		PoseService.stop_camera()
	requested.emit("play_activity", context.duplicate(true))


func _exit_tree() -> void:
	if is_instance_valid(calibration_voice):
		calibration_voice.call("stop")
	if PoseService.status_updated.is_connected(_on_pose_status):
		PoseService.status_updated.disconnect(_on_pose_status)
	if PoseService.preview_updated.is_connected(_on_live_preview):
		PoseService.preview_updated.disconnect(_on_live_preview)
	if PoseService.active and not passing_to_ready:
		PoseService.stop_camera()
