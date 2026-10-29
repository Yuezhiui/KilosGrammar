extends SceneTree

# Godot --headless --path . --script res://tools/test_calibration_independent_pose_guides.gd
# Verifies manual, editor-authored Left/Center/Right TextureRects replace all
# PosePlacement marker logic, AND that genuine per-source packet-shaped SOLO
# BOTH-DOWN/BOTH-UP holds advance the correct illustrated Balloon zone.
# No real camera, YOLO worker or database is used.
const SCENE := "res://ui/vision/calibration/calibration.tscn"
const DEFAULT := ["PoseGuideDefault", "PoseGuideRight", "PoseGuideLeft"]
const RAISE := ["PoseGuideBalloonRaise", "PoseGuideBalloonRaiseRight", "PoseGuideBalloonRaiseLeft"]
# Human Plane measures only CENTER, then visually demonstrates side turns.
const PLANE := ["PoseGuidePlaneCenter", "PoseGuidePlaneLeft", "PoseGuidePlaneRight"]
const BALLOON_ZONES := ["CENTER", "RIGHT", "LEFT"]
const PHASE_SECONDS := 3.0
const SOURCE_DT := 0.15

var checks := 0
var failures: Array[String] = []
var pose: Node
var source_when := 1000.0
var finished := false


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(18.0).timeout
	if not finished:
		_check(false, "headless independently authored guides fixture timed out")
		_finish()


func _run() -> void:
	var old_size := root.size
	var packed := load(SCENE) as PackedScene
	_check(packed != null, "Scene loads")
	if packed == null:
		_finish()
		return
	for screen_size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = screen_size
		var scene := packed.instantiate() as Control
		root.add_child(scene)
		scene.set_process(false)
		var stage := scene.get_node("TutorialStage") as Control
		var guides := stage.get_node("PoseGuides") as Control
		for zone in ["Left", "Center", "Right"]:
			_check(stage.get_node_or_null("PosePlacement" + zone) == null,
				"Removed PosePlacement" + zone + " no longer exists")
		var center := guides.get_node("PoseGuideDefault") as TextureRect
		var left := guides.get_node("PoseGuideLeft") as TextureRect
		var right := guides.get_node("PoseGuideRight") as TextureRect
		var raised := guides.get_node("PoseGuideBalloonRaise") as TextureRect
		for guide in [left, right]:
			_check(guide.texture == center.texture and guide.texture.resource_path.ends_with("DEFAULT.png"),
				"Left/Right duplicate original DEFAULT.png texture")
			_check(is_equal_approx(guide.position.y, center.position.y)
				and guide.size.is_equal_approx(center.size)
				and guide.scale.is_equal_approx(center.scale),
				"Left/Right preserve original CENTER guide Y, size and scale")
		_check(left.position.x < center.position.x and center.position.x < right.position.x,
			"Three independent DEFAULT positions start LEFT < CENTER < RIGHT")
		for name in ["PoseGuideBalloonRaiseLeft", "PoseGuideBalloonRaiseRight"]:
			var guide := guides.get_node(name) as TextureRect
			_check(guide.texture == raised.texture and guide.texture.resource_path.ends_with("BALOON POP.png"),
				"Balloon raised-hand variant keeps the supplied PNG: " + name)
			_check(is_equal_approx(guide.position.y, raised.position.y)
				and guide.size.is_equal_approx(raised.size)
				and guide.scale.is_equal_approx(raised.scale),
				"Balloon raised variant preserves authored Y/size/scale: " + name)
		var authored: Dictionary = {}
		for name in DEFAULT + RAISE + PLANE:
			var node := guides.get_node(name) as TextureRect
			authored[name] = [node.position, node.size, node.scale, node.texture]
		# Simulate a teacher dragging just RIGHT in Godot. Scene switching must
		# NEVER overwrite that manual position or either guide's size/Y.
		right.position.x += 17.0
		authored["PoseGuideRight"] = [right.position, right.size, right.scale, right.texture]
		scene.intro_running = false
		for activity in ["Catch the Word", "Balloon Popping", "Human Plane"]:
			scene.context = {"activity": activity}
			var expected_order: Array = (["CENTER"] if activity == "Human Plane" else
				BALLOON_ZONES if activity == "Balloon Popping" else ["CENTER", "RIGHT", "LEFT"])
			_check(scene._capture_order() == expected_order,
				activity + " preserves its production-authoritative zone order")
			for index in range(3):
				for phase in range(2):
					scene.live_step = 0 if activity == "Human Plane" else index
					scene.balloon_pose_phase = phase if activity == "Balloon Popping" else 0
					scene._sync_reference_art()
					var active := "PoseGuidePlaneCenter"
					if activity != "Human Plane":
						var raised_phase: bool = activity == "Balloon Popping" and phase == 1
						if activity == "Balloon Popping":
							active = _balloon_guide(BALLOON_ZONES[index], raised_phase)
						else:
							active = DEFAULT[index]
					for name in DEFAULT + RAISE + PLANE:
						var item := guides.get_node(name) as TextureRect
						_check(item.visible == (name == active),
							"%s stage %d phase %d selects only %s" % [activity, index, phase, active])
						var original: Array = authored[name]
						_check(item.position == original[0] and item.size == original[1]
							and item.scale == original[2] and item.texture == original[3],
							"%s keeps manual editor transform and texture during stage changes" % name)
		# Completion clears all pose guides while preserving editable transforms.
		scene.context = {"activity": "Catch the Word"}
		scene.live_step = 3
		scene._sync_reference_art()
		for name in DEFAULT + RAISE + PLANE:
			_check(not (guides.get_node(name) as TextureRect).visible,
				"Completed calibration hides " + name)
		_check(stage.get_node_or_null("CameraArea/SkeletonPlacement") != null,
			"Independent YOLO skeleton placement stays untouched")
		scene.queue_free()
		await process_frame
	# Separately test actual state-machine stage transitions from authenticated
	# fresh mock source observations, not only manually set live_step and phase.
	await _verify_source_authenticated_balloon(packed)
	root.size = old_size
	_finish()


func _balloon_guide(zone: String, raised: bool) -> String:
	if raised:
		return "PoseGuideBalloonRaiseLeft" if zone == "LEFT" else (
			"PoseGuideBalloonRaiseRight" if zone == "RIGHT" else "PoseGuideBalloonRaise")
	return "PoseGuideLeft" if zone == "LEFT" else (
		"PoseGuideRight" if zone == "RIGHT" else "PoseGuideDefault")


func _check_sole_png(guides: Control, expected_name: String, description: String) -> void:
	var visible_count := 0
	for name in DEFAULT + RAISE + PLANE:
		var guide := guides.get_node_or_null(name) as TextureRect
		_check(guide != null, description + " authored node " + name)
		if guide == null:
			continue
		if guide.visible:
			visible_count += 1
		_check(guide.visible == (name == expected_name),
			description + " correct visibility for " + name)
		_check(guide.texture != null and not guide.texture.resource_path.is_empty(),
			description + " uses a real scene PNG: " + name)
	_check(visible_count == (1 if not expected_name.is_empty() else 0),
		description + " has exactly the expected number of visible PNG guides")


func _verify_source_authenticated_balloon(packed: PackedScene) -> void:
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "real PoseService singleton is available")
	if pose == null:
		return
	_safe_stop_pose()
	pose.set_process(false)
	pose.peer = PacketPeerUDP.new()
	_check(pose.peer.bind(0, "127.0.0.1") == OK,
		"loopback-only fake source transport is bound for authenticated frame checks")
	pose.worker_pid = OS.get_process_id() # Stand-in only; disarm before stop_camera.
	pose.session_token = "independent-guide-bilateral-fixture"
	pose.active = true
	var scene := packed.instantiate() as Control
	root.add_child(scene)
	scene.set_process(false)
	scene.set_context({"activity": "Balloon Popping", "camera_requested": false,
		"student_name": "QA STUDENT", "game_mode": "Seconds", "topic": "Noun"})
	var stage := scene.get_node_or_null("TutorialStage") as Control
	if stage == null:
		_check(false, "actual TutorialStage available for source phase tests")
		_safe_stop_pose()
		scene.queue_free()
		await process_frame
		return
	var guides := stage.get_node_or_null("PoseGuides") as Control
	_check(guides != null and guides.owner == scene,
		"source phase tests use the same authored PoseGuides grouping")
	if guides == null:
		_safe_stop_pose()
		scene.queue_free()
		await process_frame
		return
	_check(guides.get_node_or_null("BalloonHandsInstruction") == null,
		"obsolete Balloon bilateral overlay label has been removed")
	var original_rects: Dictionary = {}
	for name in DEFAULT + RAISE + PLANE:
		original_rects[name] = (guides.get_node(name) as TextureRect).get_rect()
	scene._process(3.01) # The three-second INTRO does not count as hand holds.
	_check(scene._capture_order() == BALLOON_ZONES,
		"real Balloon state machine performs CENTER -> RIGHT -> LEFT")
	_check(scene._hold_seconds() == PHASE_SECONDS and not scene.intro_running,
		"intro ended and six physical phases require three seconds EACH")
	var completed := 0
	for zone in BALLOON_ZONES:
		var x := 0.2 if zone == "LEFT" else (0.8 if zone == "RIGHT" else 0.5)
		for phase in [0, 1]:
			var tag := "%s %s" % [zone, "BOTH DOWN" if phase == 0 else "BOTH UP"]
			_check(int(scene.live_step) == completed / 2
				and int(scene.balloon_pose_phase) == phase,
				tag + " starts at the right sequential stage")
			_check_sole_png(guides, _balloon_guide(zone, phase == 1), tag)
			scene._set_stage_instruction()
			_check(String(scene.latest_instruction_text).contains(
					"KEEP BOTH HANDS DOWN" if phase == 0 else "RAISE BOTH HANDS"),
				tag + " describes the bilateral physical posture in mode instructions")
			# Neither either-hand shooting signal nor missing wrist observations
			# certify BOTH wrists on the SAME source packet.
			for i in range(23):
				_send_frame(scene, x, 1, true, false, false, true)
			_check(int(scene.live_step) * 2 + int(scene.balloon_pose_phase) == completed,
				tag + " rejects 3.45s of one-hand-only raised signals")
			for i in range(23):
				_send_frame(scene, x, 1, false, phase == 1, phase == 0, false)
			_check(int(scene.live_step) * 2 + int(scene.balloon_pose_phase) == completed,
				tag + " denies cached bilateral flags without two observed wrists")
			for population in [0, 2]:
				for i in range(9):
					_send_frame(scene, x, population, true, phase == 1, phase == 0, true)
				_check(int(scene.live_step) * 2 + int(scene.balloon_pose_phase) == completed,
					tag + " refuses raw YOLO people=" + str(population))
			for i in range(8):
				scene._process(SOURCE_DT) # No new source packet: zero pose credit.
			_check(int(scene.live_step) * 2 + int(scene.balloon_pose_phase) == completed,
				tag + " cannot advance by replaying last displayed camera frame")
			# Real, strictly increasing source timestamps and true bilateral
			# postures: 2.85s is insufficient; 3.0s+ completes just one phase.
			for i in range(19):
				_send_frame(scene, x, 1, true, phase == 1, phase == 0, true)
			_check(int(scene.live_step) * 2 + int(scene.balloon_pose_phase) == completed,
				tag + " cannot finish 3-second hold at 2.85 seconds")
			for i in range(4):
				_send_frame(scene, x, 1, true, phase == 1, phase == 0, true)
			completed += 1
			_check(int(scene.live_step) * 2 + int(scene.balloon_pose_phase) == completed,
				tag + " advances precisely one phase after fresh 3-second hold")
			if completed < 6:
				_check_sole_png(guides, _balloon_guide(BALLOON_ZONES[completed / 2], completed % 2 == 1),
					tag + " next active guide")
	_check(completed == 6 and scene.live_step == 3 and scene.balloon_pose_phase == 0
		and bool(pose.calibration.get("valid", false)) and pose.plane_calibration.is_empty(),
			"six real CENTER/RIGHT/LEFT bilateral DOWN->UP holds complete calibrated bounds")
	_check(bool(scene.success_running),
		"finishing six verified holds starts success overlay rather than replaying a stage")
	_check_sole_png(guides, "", "completed Balloon calibration")
	for name in original_rects:
		_check((guides.get_node(name) as TextureRect).get_rect() == original_rects[name],
			"authored PNG transform is never touched by real six-phase calibration: " + name)
	_safe_stop_pose()
	scene.queue_free()
	await process_frame
	await process_frame
	pose.set_process(true)


func _send_frame(scene: Control, x: float, population: int, observed: bool,
		both_up: bool, both_down: bool, reliable_pose: bool) -> void:
	source_when += SOURCE_DT
	var frame := {"token": pose.session_token, "kind": "pose", "camera": true,
		"camera_phase": "tracking", "state": "tracking", "people": population,
		"camera_frame_age_ms": 20, "fps": 8.0,
		"pose": reliable_pose and population == 1,
		"lock_state": "locked" if population == 1 and reliable_pose else "lost",
		"x": x if population == 1 and reliable_pose else -1.0,
		"hand_observation_valid": observed,
		"hand_up": not both_down,
		"both_hands_up": both_up, "both_hands_down": both_down}
	pose._apply_pose_packet(frame, Time.get_ticks_msec())
	pose._record_fresh_calibration_pose(frame, source_when)
	if population == 1 and reliable_pose:
		pose.player_x = x # Check actual source target, not renderer smoothing.
	scene._process(SOURCE_DT)


func _safe_stop_pose() -> void:
	if is_instance_valid(pose):
		pose.worker_pid = -1 # Never kill this headless Godot fake-PID process.
		pose.stop_camera()


func _check(ok: bool, explanation: String) -> void:
	checks += 1
	if not ok:
		failures.append(explanation)
		printerr("INDEPENDENT GUIDE FAIL: ", explanation)


func _finish() -> void:
	if finished:
		return
	finished = true
	_safe_stop_pose()
	print("INDEPENDENT POSE GUIDES: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
