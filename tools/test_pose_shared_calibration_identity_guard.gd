extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_pose_shared_calibration_identity_guard.gd
# Real authored calibration scene, synthetic statuses only; no webcam/model/DB.
const SCENE := "res://ui/vision/calibration/calibration.tscn"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pose := root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload available")
	if pose == null:
		_finish()
		return
	var scene := load(SCENE) as PackedScene
	_check(scene != null, "native shared calibration loads without a webcam")
	if scene == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	_set_student(pose, 6)
	_check(bool(pose.set_calibration(0.18, 0.50, 0.82, 6)),
			"physical calibration measures actual classroom positions")
	_check(not pose.calibration.has("locked_id") \
		and pose.has_valid_pose(), "completed physical calibration is NOT bound to YOLO track ID")
	var original: float = float(pose.normalized_body_x())
	_set_student(pose, 7)
	_check(pose.has_valid_pose() and is_equal_approx(pose.normalized_body_x(), original),
		"fresh stable SOLO person with changed ID inherits the round's measured positions")
	_check(bool(pose.calibration.get("valid", false)),
		"measured values survive any tracker ID change")
	_set_student(pose, 6)
	_check(pose.has_valid_pose() and is_equal_approx(pose.normalized_body_x(), original),
		"original same ID may also resume without recalibrating")

	for activity in ["Catch the Word", "Balloon Popping", "Human Plane"]:
		pose.stop_camera()
		_set_student(pose, 6)
		var screen := scene.instantiate() as Control
		_check(screen != null and screen.has_method("set_context"),
			activity + ": shared scene works")
		if screen == null:
			continue
		root.add_child(screen)
		screen.set_context({"activity": activity, "student_name": "QA"})
		screen.set_process(false)
		screen.set("intro_running", false)
		screen.call("_finish_intro_only")
		if activity == "Human Plane":
			_check(bool(pose.set_stationary_plane_calibration(0.50, 6, 0.50, 0.0)),
				"Human Plane stays neutral-only")
			screen.set("live_step", 1)
			screen.set("plane_locked_id", 6)
		else:
			_check(bool(pose.set_calibration(0.18, 0.50, 0.82, 6)),
				activity + ": three physically measured positions retained")
			screen.set("live_step", 3)
			screen.set("physical_locked_id", 6)
		_set_student(pose, 7)
		screen.call("_process", 0.016)
		_check(int(screen.get("live_step")) == (1 if activity == "Human Plane" else 3),
			activity + ": changing track ID must NOT restart finished calibration")
		_check(bool(pose.calibration.get("valid", false)),
			activity + ": finished neutral/3-position calibration is retained")
		screen.queue_free()
		await process_frame
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _set_student(pose: Node, track_id: int) -> void:
	pose.active = true
	pose.player_x = 0.52
	pose.last_pose_ms = Time.get_ticks_msec()
	pose.current_status = {"state": "tracking", "pose": true, "camera": true,
		"lock_state": "locked", "locked_id": track_id, "people": 1,
		"camera_frame_age_ms": 40,
		"plane_steering": 0.52, "plane_steering_valid": true,
		"plane_neutral_valid": true}


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)


func _finish() -> void:
	for reason in failures:
		printerr("FAIL shared calibration identity: ", reason)
	print("%s shared calibration identity: %d checks, %d failures" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
