extends SceneTree

## NEW USER CONTRACT, independent of earlier 2.5s neutral/three-stage Balloon.
## This is QA only: synthetic authenticated YOLO observations, no real camera,
## worker, DB, source image edits, or runtime geometry edits.
## Godot --headless --path . --script res://tools/test_calibration_five_pose_png_sequences.gd
const SCENE_PATH := "res://ui/vision/calibration/calibration.tscn"
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const HOLD := 3.0
const INTRO := 3.0
const DT := 0.15
const ART_NAMES := ["PoseGuideDefault", "PoseGuideLeft", "PoseGuideRight",
	"PoseGuideBalloonRaise", "PoseGuideBalloonRaiseLeft", "PoseGuideBalloonRaiseRight",
	"PoseGuidePlaneCenter"]

var pose: Node
var packed: PackedScene
var screen: Control
var stage: Control
var when := 1000.0
var assertions := 0
var failures: Array[String] = []
var finished := false


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(30.0).timeout
	if not finished:
		_check(false, "30s fixture watchdog")
		_finish()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	if pose == null:
		_check(false, "real PoseService autoload exists")
		_finish()
		return
	# Do NOT preload a script-backed .tscn at GDScript parse time; the PoseService
	# autoload must be initialized before compiling calibration.gd references.
	packed = load(SCENE_PATH) as PackedScene
	if packed == null:
		_check(false, "calibration PackedScene loads with PoseService initialized")
		_finish()
		return
	for activity in ACTIVITIES:
		await _activity(activity)
	_finish()


func _start_screen(activity: String) -> void:
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(false)
	var local_udp := PacketPeerUDP.new()
	_check(local_udp.bind(0, "127.0.0.1") == OK,
		activity + " mocked current-process worker receives localhost UDP")
	pose.peer = local_udp
	pose.worker_pid = OS.get_process_id()
	pose.session_token = "five-pose-qa-only-" + activity
	pose.active = true
	screen = packed.instantiate() as Control
	root.add_child(screen)
	screen.set_process(false)
	stage = screen.get_node("TutorialStage") as Control
	if not screen.has_method("set_context"):
		_check(false, activity + " production calibration.gd parses and set_context is attached")
		return
	screen.set_context({"activity": activity, "entry_source": "tutorial",
		"guided_tutorial": true, "camera_requested": false, "keyboard_mode": false})


func _activity(activity: String) -> void:
	_start_screen(activity)
	_verify_five_authored_pngs(activity)
	if not screen.has_method("set_context"):
		pose.worker_pid = -1
		screen.queue_free()
		await process_frame
		pose.stop_camera()
		return
	_check(screen.get("intro_running") == true, activity + " intro starts active")
	_check(is_equal_approx(float(screen.get_script().get_script_constant_map().get("INTRO_SECONDS", 0.0)), INTRO),
		activity + " intro authored for exactly 3 seconds")
	_check(_hidden_pose_guides(), activity + " all pose art hidden during intro")
	screen.call("_process", 2.99)
	_check(screen.get("intro_running") == true and int(screen.get("live_step")) == 0,
		activity + " 2.99s still intro, never credits hold")
	screen.call("_process", 0.01)
	_check(screen.get("intro_running") != true and int(screen.get("live_step")) == 0,
		activity + " intro ends at exactly 3.00s before all hold stages")
	_check(is_equal_approx(float(screen.call("_hold_seconds")), HOLD),
		activity + " physical stage duration is exactly 3 seconds")
	var holds: Array[Dictionary] = _expected_holds(activity)
	_check(holds.size() == (1 if activity == "Human Plane" else 6 if activity == "Balloon Popping" else 3),
		activity + " expected stage total is correct")
	_check(_stage_progress(activity) == 0, activity + " has no completed physical holds after intro")
	# Calibration is real, not merely a countdown: crowd and absence cannot
	# earn ONE stage even if the packet for a crowd falsely claims pose=true.
	for crowd in [0, 2, 3]:
		for _i in range(8):
			_sample(screen, 0.5, true, true, true, crowd)
		_check(_stage_progress(activity) == 0 and pose.calibration.get("valid", false) != true,
			activity + " 0/2/3 people never complete hold (people=%d)" % crowd)
	# A stale UDP observation / cached image cannot advance a physical stage.
	_sample(screen, 0.5, true, false, true)
	var samples_before := (screen.get("live_samples") as Array).size()
	var hold_before := float(screen.get("live_timer"))
	for _frame in range(3):
		screen.call("_process", 0.10)
	_check(_stage_progress(activity) == 0 and
		(screen.get("live_samples") as Array).size() == samples_before and
		float(screen.get("live_timer")) <= hold_before + 0.001,
		activity + " 300ms replay of last camera frame earns no time/pose samples")
	for i in range(holds.size()):
		var expect: Dictionary = holds[i]
		var name := "%s %s" % [activity, String(expect["name"])]
		var current := _stage_progress(activity)
		_check(current == i, name + " begins after preceding stage, index=%d" % current)
		_check(_active_art_matches(String(expect["art"])),
			name + " uses its distinct editor-authored pose PNG, no neon square")
		var x := float(expect["x"])
		var raised: bool = expect["raised"] == true
		var tpose: bool = expect["tpose"] == true
		for crowd in [0, 2]:
			for _k in range(4):
				_sample(screen, x, true, raised, tpose, crowd)
			_check(_stage_progress(activity) == i and
				is_zero_approx(float(screen.get("live_timer"))),
				name + " rejects people=%d before each required physical phase" % crowd)
		for _k in range(12):
			_sample(screen, x, true, raised, tpose, 1, false)
		_check(_stage_progress(activity) == i,
			name + " invalid source pose cannot advance despite exactly one person")
		# Full-length WRONG gesture never earns a hold: Catch requires hands
		# lowered; Balloon requires BOTH down or BOTH up on the SAME fresh
		# frame; Human Plane requires its source-verified full-arm T-pose.
		for _i in range(26):
			_sample(screen, x, true, not raised, not tpose)
		_check(_stage_progress(activity) == i,
			name + " 3.9s wrong pose cannot skip this stage")
		_rearm_failed_stage(activity, holds, i)
		if activity == "Balloon Popping":
			# Aggregated hand_up means EITHER hand and is never proof of
			# bilateral raise or release. Even 3.9s cannot fake either phase.
			for _j in range(26):
				_sample(screen, x, true, true, false, 1, true, true)
			_check(_stage_progress(activity) == i,
				name + " either-hand gameplay flag cannot satisfy two-wrist calibration")
		for _i in range(24):
			_sample(screen, x, false, raised, tpose)
		_check(_stage_progress(activity) == i,
			name + " wrists unobserved 3.6s cannot finish hand pose")
		_rearm_failed_stage(activity, holds, i)
		# Replaying the SAME worker timestamp may never mint a new physical
		# sample, even if a render tick redraws the retained camera texture.
		_sample(screen, x, true, raised, tpose)
		var prior_sample_id := int(pose.latest_pose_sample_id)
		pose.call("_record_fresh_calibration_pose", pose.current_status, when)
		_check(int(pose.latest_pose_sample_id) == prior_sample_id,
			name + " duplicate worker timestamp cannot mint another pose sample")
		for _k in range(4):
			screen.call("_process", DT)
		_check(_stage_progress(activity) == i,
			name + " retained pose image without packets never completes hold")
		_rearm_failed_stage(activity, holds, i)
		_sample(screen, x, true, raised, tpose, 2) # reset timer before exact 2.7s proof
		# Physical holds may not complete early, even with 8+ real source
		# packets and perfectly visible stable student landmarks.
		for _i in range(18):
			_sample(screen, x, true, raised, tpose)
		_check(_stage_progress(activity) == i, name + " 2.7s of correct pose is insufficient")
		_rearm_failed_stage(activity, holds, i)
		for _i in range(11):
			_sample(screen, x, true, raised, tpose)
		_check(_stage_progress(activity) == i + 1,
			name + " after >=3s / >=8 fresh frames moves exactly one phase")
		if i + 1 < holds.size():
			_check(pose.calibration.get("valid", false) != true,
				name + " cannot mark calibration complete before all holds")
	_check(pose.calibration.get("valid", false) == true,
		activity + " only complete after %d physical 3s holds" % holds.size())
	if activity == "Human Plane":
		_check(pose.plane_calibration.get("valid", false) == true and
			not pose.calibration.has("right") and not pose.calibration.has("left"),
			"Human Plane uses T-pose neutral only; banks after GO without fake side measurements")
		# The student stays at exactly the same torso X after T-pose but changes
		# arm BANK. Steering must come from the arms, not a left/right body slide.
		var bank_left := _plane_bank_steering(-0.8)
		var bank_right := _plane_bank_steering(0.8)
		_check(is_finite(bank_left) and is_finite(bank_right) and
			absf(bank_right - bank_left) > 0.25,
			"Human Plane after T-pose arm BANK drives left/right at fixed torso X " +
			"(left=%f, right=%f)" % [bank_left, bank_right])
	else:
		_check(pose.calibration.has("left") and pose.calibration.has("center")
			and pose.calibration.has("right"),
			activity + " retains all three distinct physical floor locations")
	pose.worker_pid = -1 # _exit_tree may call stop_camera; never OS.kill Godot.
	screen.queue_free()
	await process_frame
	await process_frame
	pose.worker_pid = -1
	pose.stop_camera()


func _expected_holds(activity: String) -> Array[Dictionary]:
	if activity == "Human Plane":
		return [{"name":"CENTER T-POSE", "x":0.5, "raised":false,
			"tpose":true, "art":"PoseGuidePlaneCenter"}]
	var stages: Array[Dictionary] = []
	for zone in (["LEFT", "CENTER", "RIGHT"] if activity == "Balloon Popping"
			else ["CENTER", "RIGHT", "LEFT"]):
		var x: float = 0.5 if zone == "CENTER" else 0.8 if zone == "RIGHT" else 0.2
		stages.append({"name":zone+" DEFAULT", "x":x,
			"raised":false, "tpose":false,
			"art":"PoseGuideDefault" if zone == "CENTER" else "PoseGuideRight" if zone == "RIGHT" else "PoseGuideLeft"})
		if activity == "Balloon Popping":
			stages.append({"name":zone+" BALLOON POP", "x":x,
				"raised":true, "tpose":false,
				"art":"PoseGuideBalloonRaise" if zone == "CENTER" else "PoseGuideBalloonRaiseRight" if zone == "RIGHT" else "PoseGuideBalloonRaiseLeft"})
	return stages


func _stage_progress(activity: String) -> int:
	var zone_index := int(screen.get("live_step"))
	return 2 * zone_index + int(screen.get("balloon_pose_phase")) \
		if activity == "Balloon Popping" else zone_index


func _rearm_failed_stage(activity: String, holds: Array[Dictionary], i: int) -> void:
	# A RED wrong-posture assertion may have *already advanced* production to
	# a later stage. Do not let that first defect cascade into misleading
	# timing/wrist failures: restore real prior holds with fresh packets, never
	# fabricate measured_points or write production/state files.
	if _stage_progress(activity) == i:
		return
	screen.call("_reset_live_samples")
	for earlier in range(i):
		var prior: Dictionary = holds[earlier]
		for _j in range(29):
			_sample(screen, float(prior["x"]), true, prior["raised"] == true,
				prior["tpose"] == true)
	_check(_stage_progress(activity) == i,
		activity + " after failing posture gate restores stage %d via real fresh prior holds" % i)


func _sample(target: Control, x: float, wrists: bool,
		raised: bool, tpose: bool, people: int = 1, pose_ok: bool = true,
		single_hand_only: bool = false) -> void:
	when += DT
	var packet: Dictionary = {"token": pose.session_token, "kind":"pose",
		"camera":true, "camera_phase":"tracking", "state":"tracking",
		"people":people, "pose":pose_ok, "lock_state":"locked",
		"camera_frame_age_ms":20, "fps":8.0,
		"x":x, "hand_observation_valid":wrists,
		"hand_up":raised, "plane_t_pose_valid":tpose and wrists,
		"both_hands_up": wrists and pose_ok and raised and not single_hand_only,
		"both_hands_down": wrists and pose_ok and not raised and not tpose and not single_hand_only,
		"plane_steering":0.5, "plane_steering_valid":true,
		"plane_neutral_valid":true}
	pose.call("_apply_pose_packet", packet, Time.get_ticks_msec())
	pose.call("_record_fresh_calibration_pose", packet, when)
	target.call("_process", DT)


func _plane_bank_steering(bank: float) -> float:
	# This produces genuinely NEW source status after calibrated T-pose, not
	# an old drawing. Either arm bank changes while shoulder center stays 0.5.
	when += DT
	var sample := {"token":pose.session_token, "kind":"pose",
		"state":"tracking", "camera":true, "camera_phase":"tracking",
		"camera_frame_age_ms":20, "people":1, "pose":true,
		"lock_state":"locked", "x":0.5, "fps":8.0,
		"hand_observation_valid":true, "plane_steering":0.5,
		"plane_steering_valid":true, "plane_neutral_valid":true,
		"plane_bank":bank, "plane_bank_valid":true,
		"plane_t_pose_valid":false}
	pose.call("_apply_pose_packet", sample, Time.get_ticks_msec())
	return float(pose.normalized_plane_steering())


func _hidden_pose_guides() -> bool:
	for n in ART_NAMES:
		var guide := stage.get_node_or_null("PoseGuides/" + n) as CanvasItem
		if guide != null and guide.is_visible_in_tree():
			return false
	return true


func _verify_five_authored_pngs(activity: String) -> void:
	var png_paths: Dictionary = {}
	for name in ART_NAMES:
		var node := stage.get_node_or_null("PoseGuides/" + name) as TextureRect
		var source := ""
		if node != null and node.texture != null:
			source = String(node.texture.resource_path)
		_check(node != null and not source.is_empty() and source.to_lower().ends_with(".png")
			and not source.to_lower().contains("parameters.png") and ResourceLoader.exists(source),
			activity + " " + name + " is a real editor-authored independently editable PNG TextureRect")
		if not source.is_empty():
			png_paths[source] = true
	_check(png_paths.size() == 3,
		activity + " seven editable guides reuse exactly three original PNG sources (%d/3)" % png_paths.size())


func _active_art_matches(active: String) -> bool:
	var correct := true
	for name in ART_NAMES:
		var node := stage.get_node_or_null("PoseGuides/" + name) as TextureRect
		if node == null or node.visible != (name == active):
			correct = false
	for old in ["ArtGuideCenter", "ArtGuideLeft", "ArtGuideRight"]:
		var obsolete := stage.get_node_or_null(old) as CanvasItem
		if obsolete != null and obsolete.visible:
			correct = false
	return correct


func _check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok:
		failures.append(detail)
		printerr("FIVE PNG PHYSICAL CALIBRATION QA FAIL: ", detail)


func _finish() -> void:
	if finished:
		return
	finished = true
	if pose != null:
		pose.worker_pid = -1
		pose.stop_camera()
	print("FIVE PNG CALIBRATION STAGES: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
