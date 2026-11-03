extends SceneTree

# No webcam, camera start, Python process, DB, or MainMenu. The scene is
# instantiated without entering the tree, so _ready() does not start a camera.
const SOURCE_PATH := "res://ui/vision/calibration/multiplayer_calibration.gd"
const SERVICE := preload("res://ui/vision/pose_service.gd")
var _service: Node
var _runtime_script: GDScript
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("SEQUENTIAL MULTIPLAYER FAIL: ", label)

func _packet(scene: Control, timestamp: float, left: float, right: float,
		left_live: bool, right_live: bool) -> void:
	scene.call("_on_pose", {"mode": "multiplayer", "state": "tracking", "camera": true,
		"camera_source_timestamp": timestamp,
		"players": [{"active": left_live, "x": left}, {"active": right_live, "x": right}]})

func _feed(scene: Control, start_time: float, left: float, right: float,
		left_live: bool, right_live: bool, packets: int = 17) -> float:
	var time := start_time
	for i in packets:
		time += 0.25
		_packet(scene, time, left, right, left_live, right_live)
	return time

func _new_calibration() -> Control:
	_service.set_multiplayer_mode(true)
	_service.begin_new_multiplayer_calibration()
	var scene := _runtime_script.new() as Control
	if scene == null:
		return null
	scene.set("_isolated_pose_service", _service)
	var states: Array[Dictionary] = [
		{"ready":false,"timer":0.0,"count":0,"samples":[],"last_source":-1.0},
		{"ready":false,"timer":0.0,"count":0,"samples":[],"last_source":-1.0},
	]
	scene.set("player_state", states)
	scene.source_time = -1.0
	scene.sequential_solo = false
	return scene

func _run() -> void:
	# `godot --script` deliberately omits project autoloads. Compile the
	# UNCHANGED production controller in memory with its PoseService reference
	# bound to a separate no-camera service. No source-file rewriting and no
	# scene tree insertion, so _ready() never starts an actual camera.
	_service = SERVICE.new()
	var text_source := FileAccess.get_file_as_string(SOURCE_PATH)
	_check(text_source.contains("_single_live_player") and text_source.contains("_ready_to_go"),
		"production controller contains live sequential enrollment functions")
	_runtime_script = GDScript.new()
	_runtime_script.source_code = text_source.replace("extends Control", "extends Control\nvar _isolated_pose_service") \
		.replace("PoseService", "_isolated_pose_service")
	var parsed := _runtime_script.reload() == OK
	_check(parsed, "real production controller compiles with isolated pose stub")
	if not parsed:
		quit(1)
		return
	var solo := _new_calibration()
	solo.set_context({"activity":"Balloon Popping","player_mode":"Multiplayer"})
	_check(solo.context.get("activity") == "Balloon Popping", "existing Balloon Popping route preserved")
	var t := _feed(solo, 0.0, .24, -.1, true, false)
	_check(bool(solo.player_state[0]["ready"]) and not bool(solo.player_state[1]["ready"]),
		"one real body on left completes P1 after 3 seconds")
	_check(solo.sequential_solo, "P1 sole-body calibration enables sequential enrollment")
	_check(is_equal_approx(float(_service.multiplayer_calibration[0].get("center", -1)), .24),
		"left neutral fixed in PoseService")
	_check(not solo.call("_ready_to_go"), "P1 alone never starts game")
	t = _feed(solo, t, .43, -.1, true, false)
	_check(not bool(solo.player_state[1]["ready"]), "same left body cannot impersonate right P2")
	# Same person crosses frame but worker may still label the single person P1.
	t = _feed(solo, t, .78, -.1, true, false)
	_check(bool(solo.player_state[1]["ready"]), "single body right accepted as P2 even in P1 slot")
	_check(is_equal_approx(float(_service.multiplayer_calibration[1].get("center", -1)), .78),
		"right neutral stored independently")
	_check(is_equal_approx(float(_service.multiplayer_calibration[0].get("center", -1)), .24),
		"walking right never recenters P1")
	_check(bool(solo.call("_ready_to_go")), "both spatial centers authorize GO with one live pose")
	_check(_service.has_multiplayer_calibration(), "PoseService recognizes both neutrals")
	solo.free()

	var swapped := _new_calibration()
	t = _feed(swapped, 0.0, -.1, .22, false, true)
	_check(bool(swapped.player_state[0]["ready"]), "lone left body in Python slot1 still enrolls P1")
	_check(not bool(swapped.player_state[1]["ready"]),
		"one left body cannot also finish P2 while P1 calibrates")
	t = _feed(swapped, t, -.1, .79, false, true)
	_check(bool(swapped.player_state[1]["ready"]) and bool(swapped.call("_ready_to_go")),
		"same lone body can enroll right P2 while remaining in slot1")
	swapped.free()

	var dual := _new_calibration()
	t = _feed(dual, 0.0, .23, .75, true, true)
	_check(bool(dual.player_state[0]["ready"]) and bool(dual.player_state[1]["ready"]),
		"original simultaneous two-person path independently calibrates both")
	_check(not dual.sequential_solo, "two real bodies do not enter sequential fallback")
	_check(bool(dual.call("_ready_to_go")),
		"two-person GO does not wait for live poses after both neutral holds")
	dual.free()

	var invalid := _new_calibration()
	t = _feed(invalid, 0.0, .73, -.1, true, false)
	_check(not bool(invalid.player_state[0]["ready"]), "P1 lone person must begin on left")
	_check(not _service.has_multiplayer_calibration(), "invalid spatial setup cannot start game")
	invalid.free()
	_service.set_multiplayer_mode(false)
	_service.free()
	_runtime_script = null
	print("SEQUENTIAL MULTIPLAYER CALIBRATION: %s checks=%d failures=%d camera_io=none" % [
		"PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
