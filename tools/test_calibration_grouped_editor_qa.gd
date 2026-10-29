extends SceneTree

# Godot 4.7.2:
#   --headless --path . --script res://tools/test_calibration_grouped_editor_qa.gd
# Grouped editor nodes + strict camera-protocol integration (NO real webcam,
# Python helper, YOLO detector, database, git mutation, or production edits).
# Synthetic input is sent through PoseService's real token-validated UDP
# receiver. Merely setting player_x/current_status cannot pass this test.

const CALIBRATION := "res://ui/vision/calibration/calibration.tscn"
const DELETED := [
	"PlaneSteeringFootnote", "PlaneSteeringTitle", "InstructionLabel",
	"BadgeLabel", "PlayerLabel", "StatusCapsule", "PlaneStepBadge",
	"CenterOnlyLabel", "ArtStars", "Heading", "StageHeading",
	"InstructionFIL", "Description", "StepBadgeBackground", "StepBadge",
	"CountdownLabel"
]
const GROUP_CONTENTS := {
	"CameraArea": ["CameraFrame", "CameraBlackBacking", "LiveCameraInset",
		"SkeletonPlacement", "ArtCameraFrame"],
	"PoseGuides": ["PoseGuideDefault", "PoseGuideRight", "PoseGuideLeft",
		"PoseGuideBalloonRaise", "PoseGuideBalloonRaiseRight",
		"PoseGuideBalloonRaiseLeft", "PoseGuidePlaneCenter",
		"PoseGuidePlaneLeft", "PoseGuidePlaneRight"],
	"Directions": ["ArtTitleCenter", "ArtTitleRight", "ArtTitleLeft",
		"ArtArrowCenter", "ArtArrowRight", "ArtArrowLeft", "ArtStep1",
		"ArtStep2", "ArtStep3", "ArtMoveHintCenter", "ArtMoveHintRight",
		"ArtMoveHintLeft"],
	"CountdownArtwork": ["ArtCountdown1", "ArtCountdown2", "ArtCountdown3"],
	"CameraFeedback": ["CameraUnavailableLabel", "CameraStatusLabel", "ProgressLabel"],
	"Navigation": ["BackButton"]
}
# These are the ORIGINAL pre-regroup Godot-editor positions (1280x720 scene
# coordinates), not recalculated bounds. A zero-offset Control grouping must
# preserve them even when the node's immediate parent changes.
const AUTHORED_RECT := {
	"LiveCameraInset": [141.0, 147.0, 1007.0, 446.0],
	"SkeletonPlacement": [141.0, 147.0, 1047.0, 446.0],
	"PoseGuideDefault": [262.0, 66.0, 767.0, 484.0],
	"PoseGuideRight": [575.0, 66.0, 767.0, 484.0],
	"PoseGuideLeft": [-50.0, 66.0, 767.0, 484.0],
	"PoseGuideBalloonRaise": [262.0, 66.0, 767.0, 484.0],
	"PoseGuideBalloonRaiseRight": [570.0, 66.0, 767.0, 484.0],
	"PoseGuideBalloonRaiseLeft": [-50.0, 66.0, 767.0, 484.0],
	"PoseGuidePlaneCenter": [262.0, 66.0, 767.0, 484.0],
	"PoseGuidePlaneLeft": [262.0, 66.0, 767.0, 484.0],
	"PoseGuidePlaneRight": [262.0, 66.0, 767.0, 484.0],
	"ArtTitleCenter": [320.0, 28.0, 640.0, 148.0],
	"ArtTitleRight": [320.0, 28.0, 640.0, 148.0],
	"ArtTitleLeft": [320.0, 28.0, 640.0, 148.0],
	"ArtArrowCenter": [384.0, 310.0, 136.0, 136.0],
	"ArtArrowRight": [663.0, 315.0, 136.0, 136.0],
	"ArtArrowLeft": [498.0, 311.0, 136.0, 136.0],
	"ArtCountdown1": [1075.0, -19.0, 228.0, 172.0],
	"ArtCountdown2": [1075.0, -19.0, 228.0, 172.0],
	"ArtCountdown3": [1075.0, -19.0, 228.0, 172.0],
	"BackButton": [497.0, 640.0, 293.0, 80.0]
}
const NINE_TEXTURES := {
	"PoseGuideDefault": "DEFAULT.png",
	"PoseGuideRight": "DEFAULT.png",
	"PoseGuideLeft": "DEFAULT.png",
	"PoseGuideBalloonRaise": "BALOON POP.png",
	"PoseGuideBalloonRaiseRight": "BALOON POP.png",
	"PoseGuideBalloonRaiseLeft": "BALOON POP.png",
	"PoseGuidePlaneCenter": "PLANE T POSE.png",
	"PoseGuidePlaneLeft": "PLANE GOING TO LEFT.png",
	"PoseGuidePlaneRight": "PLANE GOING TO RIGHT.png"
}
const DT := 0.15
var count := 0
var errors: Array[String] = []
var pose: Node
var sender: PacketPeerUDP
var tick := 1000.0
var done := false


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(45.0).timeout
	if not done:
		_check(false, "45s watchdog expired; synthetic scene fixture failed to terminate")
		_finish()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload exists")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	var scene := load(CALIBRATION) as PackedScene
	_check(scene != null, "Production calibration PackedScene still parses")
	if scene == null:
		_finish()
		return
	for activity in ["Catch the Word", "Balloon Popping", "Human Plane"]:
		for entry in ["play", "tutorial"]:
			await _check_round(scene, String(activity), String(entry))
	pose.worker_pid = -1
	pose.stop_camera()
	_check(not pose.active, "No physical webcam was opened")
	_finish()


func _check_round(packed: PackedScene, activity: String, entry: String) -> void:
	var label := activity + " / " + entry
	_setup_local_receiver(label)
	var screen := packed.instantiate() as Control
	_check(screen != null, label + ": can instantiate scene")
	if screen == null:
		_teardown_receiver()
		return
	root.add_child(screen)
	screen.set_process(false)
	var stage := screen.get_node_or_null("TutorialStage") as Control
	_check(stage != null, label + ": design stage preserved")
	if stage == null:
		pose.worker_pid = -1
		screen.queue_free()
		await process_frame
		_teardown_receiver()
		return
	_check(screen.has_method("set_context"), label + ": real calibration script attached")
	_check(stage.get_node_or_null("IntroOverlay") is ColorRect,
		label + ": editor-authored 3s intro remains direct stage child")
	_check(stage.get_node_or_null("SuccessOverlay") is ColorRect
		and stage.get_node_or_null("SuccessOverlay/SuccessTitle") is Label
		and stage.get_node_or_null("SuccessOverlay/SuccessSubtitle") is Label,
		label + ": editor-authored separate 3s success overlay and labels")
	_check(stage.get_node_or_null("IntroOverlay/IntroBackButton") == null,
		label + ": duplicate intro navigation is correctly retired")
	for obsolete in DELETED:
		_check(stage.find_child(obsolete, true, false) == null,
			label + ": deleted legacy name is completely absent: " + obsolete)
	_check(DELETED.size() == 16, label + ": deletion audit covers exactly 16 names")
	var retained: Dictionary = {}
	for group_name in GROUP_CONTENTS:
		var group := stage.get_node_or_null(group_name) as Control
		_check(group != null and group.owner == screen,
			label + ": editable scene-authored Control group " + group_name)
		if group == null:
			continue
		_check(group.position.distance_to(Vector2.ZERO) < 0.1
			and group.scale.distance_to(Vector2.ONE) < 0.01,
			label + ": group " + group_name + " has identity editor transform")
		for name in GROUP_CONTENTS[group_name]:
			var item := group.get_node_or_null(name) as Control
			_check(item != null and item.owner == screen and item.get_parent() == group,
				label + ": draggable authored child in " + group_name + "/" + name)
			if item != null:
				retained[name] = item
				_check_stage_rect(stage, item, label + " " + name)
	var intro := stage.get_node_or_null("IntroOverlay") as Control
	var back := retained.get("BackButton") as Button
	_check(back != null and back.get_node_or_null("Artwork") is TextureRect,
		label + ": Back button and editable decoration survived regrouping")
	_check(back != null and back.position.is_equal_approx(Vector2(497, 640))
		and back.size.is_equal_approx(Vector2(293, 80)),
		label + ": centered Back preserves exact editor-authored 497,640/293x80")
	_check(retained.size() >= 24, label + ": live artwork/control nodes were not flattened")
	var unique_images: Dictionary = {}
	var texture_before: Dictionary = {}
	for name in NINE_TEXTURES:
		var guide := retained.get(name) as TextureRect
		_check(guide != null and guide.texture != null, label + ": nine draggable PNG: " + name)
		if guide == null or guide.texture == null:
			continue
		var path := String(guide.texture.resource_path)
		_check(path.get_file() == NINE_TEXTURES[name] and ResourceLoader.exists(path)
			and not (guide.texture is AtlasTexture),
			label + ": original PNG texture retained unchanged for " + name)
		unique_images[path] = true
		texture_before[name] = [guide.texture, path, FileAccess.get_sha256(path),
			guide.position, guide.size, guide.scale, guide.rotation]
	_check(unique_images.size() == 5, label + ": nine editable guides reuse exact five originals")
	var responses: Array[Dictionary] = []
	screen.requested.connect(func(route: String, payload: Dictionary) -> void:
		responses.append({"route": route, "payload": payload.duplicate(true)}))
	screen.set_context({"activity": activity, "entry_source": entry,
		"guided_tutorial": entry == "tutorial", "game_mode": "Seconds",
		"topic": "Noun", "difficulty": "Easy", "camera_requested": false,
		"keyboard_mode": true, "student_name": "SYNTHETIC QA - NO DATABASE"})
	_check(screen.intro_running and intro != null and intro.visible,
		label + ": intro covers regrouped artwork")
	for name in NINE_TEXTURES:
		var guide := retained.get(name) as Control
		if guide != null:
			_check(not guide.is_visible_in_tree(), label + ": intro does not leak " + name)
	_check(not pose.has_valid_pose() and not bool(pose.calibration.get("valid", false)),
		label + ": no fake pose/calibration before authenticated packet stream")
	if screen.has_method("_continue_flow"):
		screen._continue_flow(false)
		_check(responses.is_empty(), label + ": no calibration bypass from empty pose source")
	screen._process(2.99)
	_check(screen.intro_running and int(screen.live_step) == 0,
		label + ": 2.99-second intro cannot count a hold")
	screen._process(0.01)
	_check(not screen.intro_running and intro != null and not intro.visible,
		label + ": 3.00-second intro completes normally")
	_check(back != null and back.visible and not back.disabled,
		label + ": Back button becomes usable when intro ends")
	_check(is_equal_approx(float(screen.INTRO_SECONDS), 3.0) and
		is_equal_approx(float(screen.SUCCESS_SECONDS), 3.0),
		label + ": intro and success both require three real seconds")
	var phases := _expected_phases(activity)
	for index in range(phases.size()):
		var phase: Dictionary = phases[index]
		var guide_name := String(phase["guide"])
		var zone := String(phase["zone"])
		var phase_label := label + " " + zone + (" raised" if bool(phase["up"]) else " down")
		_check(_one_guide_visible(retained, guide_name), phase_label + ": only the correct authored PNG is visible")
		_check(_directional_art_visible(retained, zone, activity),
			phase_label + ": directional title/arrow and visible 3-step art are correct")
		_check(_countdown_visible(retained, 3), phase_label + ": stage initially displays authored 3 PNG")
		if activity == "Balloon Popping":
			# Either-hand aggregate 'hand_up' is NOT physical evidence of two
			# raised wrists. This must fail even from an authentic SOLO packet.
			await _push_packet(screen, float(phase["x"]), bool(phase["up"]),
				false, 1, false)
			_check(_stage_progress(screen, activity) == index and
				is_zero_approx(float(screen.live_timer)),
				phase_label + ": ambiguous one-hand/partial-wrist SOLO sample cannot earn hold time")
		for bad_people in [0, 2]:
			for _bad in range(3):
				await _push_packet(screen, float(phase["x"]), bool(phase["up"]),
					bool(phase["plane"]), bad_people)
			_check(_stage_progress(screen, activity) == index,
				phase_label + ": raw YOLO people=%d cannot advance hold" % bad_people)
		# Nineteen physically fresh 150 ms frames are less than the required
		# three seconds. One student, even with valid wrists/plane arms, must
		# remain in THIS phase until the full source-timed interval expires.
		for _sample in range(19):
			await _push_packet(screen, float(phase["x"]), bool(phase["up"]),
				bool(phase["plane"]), 1)
		_check(_stage_progress(screen, activity) == index and
			float(screen.live_timer) < 3.0,
			phase_label + ": 19 source-fresh 150 ms observations cannot finish a 3s hold")
		for _sample in range(24):
			await _push_packet(screen, float(phase["x"]), bool(phase["up"]),
				bool(phase["plane"]), 1)
			# Stop at the first genuinely completed phase. Extra camera packets
			# after the FINAL hold would advance the independent 3s SUCCESS
			# countdown before this test can inspect its start boundary.
			if _stage_progress(screen, activity) == index + 1:
				break
		_check(_stage_progress(screen, activity) == index + 1,
			phase_label + ": 3s and 8+ authenticated fresh SOLO UDP frames advance only one stage (got %d)" %
			int(_stage_progress(screen, activity)))
	_check(bool(pose.calibration.get("valid", false)) and bool(screen.transition_queued),
		label + ": only completed source-gated holds yield calibrated result")
	if activity == "Human Plane":
		_check(bool(pose.plane_calibration.get("valid", false)) and not pose.calibration.has("left")
			and not pose.calibration.has("right"),
			label + ": Human Plane uses CENTER T-pose, no invented side positions")
	else:
		_check(pose.calibration.has("left") and pose.calibration.has("right"),
			label + ": Catch/Balloon record genuine left/center/right source measurements")
	var success := stage.get_node_or_null("SuccessOverlay") as Control
	_check(bool(screen.success_running) and success != null and success.is_visible_in_tree(),
		label + ": completed real holds show only editor-authored SUCCESS overlay")
	_check(not stage.get_node("Navigation/BackButton").is_visible_in_tree(),
		label + ": success overlay hides interactive navigation while counting down")
	for bad_people in [0, 2]:
		await _push_packet(screen, 0.5, false, activity == "Human Plane", bad_people)
		screen._process(0.9)
		_check(bool(screen.success_running) and is_zero_approx(float(screen.success_elapsed))
			and responses.is_empty(),
			label + ": post-success raw YOLO people=%d freezes success, without restarting CENTER or routing" % bad_people)
	# A fresh unambiguous SOLO source packet can resume the three-second
	# success timer; previous invalid/crowded time is never credited.
	await _push_packet(screen, 0.5, false, activity == "Human Plane", 1)
	screen._continue_flow(false)
	_check(responses.is_empty(), label + ": cannot force gameplay before 3s success hold")
	screen._process(maxf(0.0, 2.99 - float(screen.success_elapsed)))
	_check(responses.is_empty() and bool(screen.success_running) and
		float(screen.success_elapsed) < 3.0,
		label + ": 2.99s success remains visible and cannot route early")
	screen._process(0.02)
	_check(responses.size() == 1 and String(responses[0]["route"]) == "gameplay",
		label + ": authenticated SOLO population after 3s success automatically routes into gameplay once")
	screen._continue_flow(false)
	_check(responses.size() == 1 and bool(screen.passing_to_ready),
		label + ": success latch prevents duplicate gameplay routing")
	if responses.size() == 1:
		var payload: Dictionary = responses[0]["payload"]
		_check(String(payload.get("entry_source", "")) == entry
			and bool(payload.get("guided_tutorial", false)) == (entry == "tutorial")
			and bool(payload.get("camera_live", false))
			and bool(payload.get("calibration_measured", false))
			and bool(payload.get("start_countdown", false))
			and not bool(payload.get("keyboard_mode", true)),
			label + ": Play/Tutorial route keeps mode, authenticated camera and count-in")
	for name in texture_before:
		var guide := retained.get(name) as TextureRect
		var before: Array = texture_before[name]
		_check(guide.texture == before[0] and String(guide.texture.resource_path) == before[1]
			and FileAccess.get_sha256(String(before[1])) == before[2]
			and guide.position == before[3] and guide.size == before[4]
			and guide.scale == before[5] and is_equal_approx(guide.rotation, float(before[6])),
			label + ": authored texture bytes, x/y, size, scale, rotation unchanged: " + name)
	pose.worker_pid = -1 # The scene calls stop_camera on exit; never kill Godot.
	screen.queue_free()
	await process_frame
	await process_frame
	_teardown_receiver()
	# Fresh separate editor navigation scene to test Back without polluting
	# the successful gameplay handoff or entering real camera setup.
	var back_screen := packed.instantiate() as Control
	root.add_child(back_screen)
	back_screen.set_process(false)
	back_screen.context = {"entry_source": entry, "activity": activity,
		"guided_tutorial": entry == "tutorial"}
	var back_routes: Array[Dictionary] = []
	back_screen.requested.connect(func(route: String, payload: Dictionary) -> void:
		back_routes.append({"route": route, "payload": payload}))
	back_screen._process(3.01)
	var other_back := back_screen.get_node_or_null("TutorialStage/Navigation/BackButton") as Button
	if other_back != null:
		other_back.pressed.emit()
	_check(back_routes.size() == 1 and String(back_routes[0].get("route", "")) == "play_activity",
		label + ": regrouped Back button routes to Choose Activity")
	back_screen.queue_free()
	await process_frame
	await process_frame


func _setup_local_receiver(label: String) -> void:
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(false)
	pose.peer = PacketPeerUDP.new()
	_check(pose.peer.bind(0, "127.0.0.1") == OK,
		label + ": token-validated UDP receiver bound on localhost")
	sender = PacketPeerUDP.new()
	_check(sender.set_dest_address("127.0.0.1", pose.peer.get_local_port()) == OK,
		label + ": isolated sender delivers only to local test receiver")
	pose.worker_pid = OS.get_process_id() # Fake liveness only, disarmed before exit.
	pose.session_token = "grouped-qa-" + label.replace(" ", "_")
	pose._launch_ms = Time.get_ticks_msec()
	pose.active = true


func _teardown_receiver() -> void:
	pose.worker_pid = -1
	if sender != null:
		sender.close()
	pose.stop_camera()
	pose.set_process(false)


func _push_packet(screen: Control, x: float, raised: bool,
		plane: bool, people: int, bilateral_valid: bool = true) -> void:
	tick += DT
	var packet := {"token":pose.session_token, "kind":"pose", "when":tick,
		"camera":true, "camera_phase":"tracking", "state":"tracking",
		"people":people, "pose":true, "lock_state":"locked",
		"camera_frame_age_ms":20, "fps":8.0, "x":x,
		"hand_observation_valid":true, "hand_up":raised,
		"both_hands_up":raised and bilateral_valid,
		"both_hands_down":not raised and bilateral_valid,
		"plane_t_pose_valid":plane, "plane_steering":0.5,
		"plane_steering_valid":true, "plane_neutral_valid":true}
	_check(sender.put_packet(JSON.stringify(packet).to_utf8_buffer()) == OK,
		"authenticated local UDP packet delivered")
	await process_frame
	pose._process(0.016)
	screen._process(DT)


func _expected_phases(activity: String) -> Array[Dictionary]:
	if activity == "Human Plane":
		return [{"zone":"CENTER", "x":0.5, "up":false,
			"plane":true, "guide":"PoseGuidePlaneCenter"}]
	var phases: Array[Dictionary] = []
	var order := ["LEFT", "CENTER", "RIGHT"] if activity == "Balloon Popping" else ["CENTER", "RIGHT", "LEFT"]
	for zone in order:
		var x := 0.5 if zone == "CENTER" else 0.8 if zone == "RIGHT" else 0.2
		var suffix: String = "" if zone == "CENTER" else String(zone).capitalize()
		phases.append({"zone":zone, "x":x, "up":false, "plane":false,
			"guide":"PoseGuideDefault" if zone == "CENTER" else "PoseGuide" + suffix})
		if activity == "Balloon Popping":
			phases.append({"zone":zone, "x":x, "up":true, "plane":false,
				"guide":"PoseGuideBalloonRaise" + suffix})
	return phases


func _stage_progress(screen: Control, activity: String) -> int:
	return int(screen.live_step) * 2 + int(screen.balloon_pose_phase) \
		if activity == "Balloon Popping" else int(screen.live_step)


func _one_guide_visible(retained: Dictionary, active_name: String) -> bool:
	for name in NINE_TEXTURES:
		var guide := retained.get(name) as TextureRect
		if guide == null or guide.visible != (name == active_name):
			return false
	return true


func _directional_art_visible(retained: Dictionary, zone: String, activity: String) -> bool:
	for pos in ["CENTER", "RIGHT", "LEFT"]:
		var suffix: String = String(pos).capitalize()
		for prefix in ["ArtTitle", "ArtArrow", "ArtMoveHint"]:
			var item := retained.get(prefix + suffix) as CanvasItem
			if item == null or item.visible != (pos == zone and activity != "Human Plane"):
				return false
	return true


func _countdown_visible(retained: Dictionary, number: int) -> bool:
	for i in range(1, 4):
		var item := retained.get("ArtCountdown%d" % i) as TextureRect
		if item == null or item.visible != (i == number):
			return false
	return true


func _check_stage_rect(stage: Control, node: Control, label: String) -> void:
	if not AUTHORED_RECT.has(String(node.name)):
		return
	var expected: Array = AUTHORED_RECT[String(node.name)]
	# Read authored offsets in the parent Control's coordinate system. Using
	# node.global_position would falsely shift the LEFT arrow by its width:
	# that artwork is intentionally mirrored with scale.x = -1 and a pivot.
	var authored_point := Vector2(node.offset_left, node.offset_top)
	var stage_point := stage.get_global_transform().affine_inverse() * \
		(node.get_parent() as Control).get_global_transform() * authored_point
	_check(stage_point.distance_to(Vector2(float(expected[0]), float(expected[1]))) < 1.0,
		label + ": editor regroup preserves original stage-relative X/Y, actual=" + str(stage_point))
	_check(node.size.distance_to(Vector2(float(expected[2]), float(expected[3]))) < 1.0,
		label + ": editor regroup preserves original authored width/height")


func _check(result: bool, message: String) -> void:
	count += 1
	if not result:
		errors.append(message)
		printerr("GROUPED_CALIBRATION_QA FAIL: ", message)


func _finish() -> void:
	if done:
		return
	done = true
	for err in errors:
		push_error(err)
	print("GROUPED_CALIBRATION_EDITOR_QA %s checks=%d failures=%d" %
		["PASS" if errors.is_empty() else "FAIL", count, errors.size()])
	quit(0 if errors.is_empty() else 1)
