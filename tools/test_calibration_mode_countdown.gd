extends SceneTree

# Godot --headless --path . --script res://tools/test_calibration_mode_countdown.gd
# End-to-end controller contract from VALID live camera calibration to gameplay.
# Synthetic fresh pose status is test-only; production never fakes a camera.

const CALIBRATION_PATH := "res://ui/vision/calibration.tscn"
const GAMEPLAY_PATH := "res://ui/play/gameplay.tscn"
const CASES := [
	{"mode": "Seconds", "guided": false},
	{"mode": "Lives", "guided": false},
	{"mode": "Seconds", "guided": true},
	{"mode": "Lives", "guided": true}
]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var service := root.get_node_or_null("PoseService")
	_expect(service != null, "PoseService autoload exists")
	if service == null:
		_finish()
		return
	service.stop_camera()
	service.set_process(false) # Do not launch or poll the real webcam in QA.
	# Runtime loading is intentional: calibration references the PoseService
	# autoload, which cannot be resolved by a preload at script parse time.
	var calibration_scene := load(CALIBRATION_PATH) as PackedScene
	var game_scene := load(GAMEPLAY_PATH) as PackedScene
	_expect(calibration_scene != null and game_scene != null, "actual scenes load")
	if calibration_scene == null or game_scene == null:
		_finish()
		return
	for test_case in CASES:
		await _check_case(calibration_scene, game_scene, test_case)
	service.stop_camera()
	service.set_process(true)
	_finish()


func _check_case(calibration_scene: PackedScene, game_scene: PackedScene, test_case: Dictionary) -> void:
	var guided := bool(test_case["guided"])
	var mode := String(test_case["mode"])
	var label := "%s / %s" % ["Guided" if guided else "Normal Play", mode]
	var service := root.get_node("PoseService")
	service.stop_camera()
	var calibration := calibration_scene.instantiate() as Control
	root.add_child(calibration)
	calibration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	calibration.set_process(false)
	calibration.call("_process", 2.51) # Finish the authored 2.5-second intro.
	var routes: Array[Dictionary] = []
	calibration.requested.connect(func(target: String, payload: Dictionary) -> void:
		routes.append({"target": target, "payload": payload}))
	for removed in ["SkipButton", "RetryButton", "DemoButton", "KeyboardButton"]:
		_expect(calibration.get_node_or_null("TutorialStage/" + removed) == null,
			label + ": removed action is not in scene: " + removed)
	calibration.call("_continue_flow", true)
	calibration.call("_continue_flow", false)
	_expect(routes.is_empty(), label + ": without a live pose neither skip nor continue can start gameplay")
	# Simulate only the measurements that have already passed PoseService's
	# validation API: no fake game, preview, or camera packet in production.
	service.active = true
	service.player_x = 0.50
	service.current_status = {"state": "tracking", "pose": true, "lock_state": "locked"}
	service.last_pose_ms = Time.get_ticks_msec()
	_expect(service.set_calibration(0.20, 0.50, 0.80), label + ": PoseService accepts 3 real-valued position bounds")
	calibration.set_context({
		"activity": "Catch the Word", "game_mode": mode,
		"topic": "Noun", "difficulty": "Easy",
		"guided_tutorial": guided, "camera_requested": true, "keyboard_mode": true
	})
	calibration.call("_continue_flow", false)
	_expect(routes.size() == 1 and String(routes[0].get("target", "")) == "gameplay",
		label + ": validated live calibration requests shared game wrapper")
	if routes.is_empty():
		calibration.queue_free()
		await process_frame
		return
	var payload := routes[0]["payload"] as Dictionary
	_expect(bool(payload.get("start_countdown", false)), label + ": countdown explicitly requested")
	_expect(bool(payload.get("guided_tutorial", false)) == guided, label + ": guided flag round-trips")
	_expect(String(payload.get("game_mode", "")) == mode, label + ": selected game mode round-trips")
	_expect(bool(payload.get("camera_live", false)) and not bool(payload.get("keyboard_mode", true))
		and bool(payload.get("calibration_measured", false)) and not bool(payload.get("calibration_skipped", true)),
		label + ": live camera is preserved and stale keyboard/skip context rejected")
	calibration.queue_free()
	await process_frame

	var wrapper := game_scene.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context(payload)
	await process_frame
	await process_frame
	await process_frame
	var minigame := wrapper.get_node_or_null("ActiveMiniGame") as Control
	_expect(minigame != null, label + ": selected activity's real game is mounted")
	if minigame == null:
		wrapper.queue_free()
		await process_frame
		return
	_expect(minigame.process_mode == Node.PROCESS_MODE_DISABLED,
		label + ": gameplay score, timer and physics are frozen until 3-2-1 finishes")
	var mode_target := wrapper.call("_spotlight_targets") as Dictionary
	var expected_mode_node := "TimerPlaque" if mode == "Seconds" else "LivesPlaque"
	_expect(mode_target.has("mode") and String((mode_target.get("mode") as Node).name) == expected_mode_node,
		label + ": HUD targets the selected Seconds/Lives indicator")
	var spotlight := wrapper.get("spotlight_overlay") as CanvasLayer
	if guided:
		_expect(String(wrapper.get("guided_stage")) == "tutorial" and spotlight != null,
			label + ": guided spotlight comes before countdown")
		_expect(wrapper.get("countdown_panel") == null,
			label + ": countdown cannot overlap active spotlight")
		if spotlight != null:
			spotlight.call("skip")
			await process_frame
	else:
		_expect(spotlight == null and String(wrapper.get("guided_stage")) == "countdown",
			label + ": normal Play skips spotlight and starts 3-2-1 directly")
	_expect(String(wrapper.get("guided_stage")) == "countdown",
		label + ": countdown is active after calibration")
	var countdown := wrapper.get("countdown_panel") as Control
	_expect(countdown != null, label + ": actual scene-authored countdown overlay is mounted")
	if countdown != null:
		var number := countdown.get_node_or_null("CountdownNumber") as Label
		_expect(number != null and number.text == "3", label + ": countdown begins at 3")
		var score := int(minigame.get("score"))
		var seconds := float(minigame.get("time_remaining"))
		var lives := int(minigame.get("lives"))
		for expected_digit in ["2", "1"]:
			wrapper.call("_on_countdown_tick")
			_expect(number != null and number.text == expected_digit,
				label + ": countdown updates to " + expected_digit)
			_expect(minigame.process_mode == Node.PROCESS_MODE_DISABLED,
				label + ": gameplay remains frozen through " + expected_digit)
		_expect(int(minigame.get("score")) == score and is_equal_approx(float(minigame.get("time_remaining")), seconds)
			and int(minigame.get("lives")) == lives,
			label + ": count-in never spends time, lives or score")
		wrapper.call("_on_countdown_tick")
		_expect(minigame.process_mode == Node.PROCESS_MODE_INHERIT,
			label + ": gameplay unfreezes after the final countdown tick")
		_expect(wrapper.get("countdown_panel") == null,
			label + ": 3-2-1 scene is removed without recreating the minigame")
	wrapper.queue_free()
	await process_frame
	await process_frame
	print("CALIBRATION COUNTDOWN CASE: ", label)


func _expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)


func _finish() -> void:
	for failure in failures:
		printerr("FAIL calibration countdown: ", failure)
	print("%s calibration mode countdown: %d checks, %d failures" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
