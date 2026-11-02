extends SceneTree
## Offline no-webcam/no-PostgreSQL route/calibration contract smoke test.
const SERVICE := preload("res://ui/vision/pose_service.gd")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("MULTI CAMERA QA FAILED: ", message)


func _run() -> void:
	# An isolated Godot --script SceneTree does NOT register the application's
	# PoseService singleton, so loading the actual calibration scene would
	# emit a misleading compile error. Verify the editor-authored scene's
	# metadata without instantiating it; the project editor parse tests script.
	var scene_text := FileAccess.get_file_as_string(
		"res://ui/vision/calibration/multiplayer_calibration.tscn")
	_check(scene_text.contains("multiplayer_calibration.gd"),
		"two-player scene uses dedicated calibration controller")
	for name in ["PlayerOne", "PlayerTwo"]:
		_check(scene_text.contains('[node name="%s"' % name),
			name + " camera group authored")
		_check(scene_text.contains('parent="Stage/%s"' % name),
			name + " nested camera and status controls")
	_check(scene_text.contains('[node name="DistanceNote"'),
		"floor reference text authored")
	_check(scene_text.contains('[node name="BackButton"'),
		"Back navigation available")
	_check(scene_text.contains("LiveCamera"),
		"live camera preview nodes present")
	var service := SERVICE.new()
	service.set_multiplayer_mode(true)
	_check(not service.has_multiplayer_calibration(), "new session uncalibrated")
	_check(service.multiplayer_set_center(0, .23, .01), "P1 independent left neutral")
	_check(service.multiplayer_set_center(1, .74, .02), "P2 independent right neutral")
	_check(service.has_multiplayer_calibration(), "both centers needed")
	_check(not service.has_multiplayer_pose(0), "no synthetic body authority")
	_check(service.multiplayer_player_x(0) == -999.0, "no ghost movement before camera")
	_check(not service.multiplayer_set_center(2, .3), "only two controllers")
	_check(not service.multiplayer_set_center(0, -1), "invalid position rejected")
	service.begin_new_multiplayer_calibration()
	_check(not service.has_multiplayer_calibration(), "fresh round requires fresh hold")
	service.free()
	for f in failures.slice(0, 20):
		printerr(f)
	print("MULTIPLAYER CAMERA CALIBRATION QA: %s %d checks, %d failures" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
