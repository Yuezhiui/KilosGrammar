extends SceneTree

## Reproduces the student's post 3-2-1 Catch freeze using the production
## Gameplay wrapper, calibrated PoseService contract, and real Catch scene.
## Only localhost mock UDP; no webcam, Python worker, external network or DB.
## Godot --headless --path . --script res://tools/test_play_vs_tutorial_live_countdown_movement.gd

const WRAPPER_PATH := "res://ui/play/gameplay/gameplay.tscn"
const SOURCES := ["play", "tutorial"]
const TRACK_ID := 407

var checks := 0
var failures: Array[String] = []
var pose: Node


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(20.0).timeout
	_check(false, "bounded A/B test did not exit")
	_finish()


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload is available")
	if pose == null:
		_finish()
		return
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(false)
	root.size = Vector2i(1280, 720)
	for source in SOURCES:
		await _exercise_source(source)
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _exercise_source(source: String) -> void:
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(false)
	var udp := PacketPeerUDP.new()
	_check(udp.bind(0, "127.0.0.1") == OK,
		source + " mock localhost UDP camera receiver binds")
	pose.peer = udp
	pose.worker_pid = OS.get_process_id()
	pose.session_token = "countdown-qa-mock-camera"
	_set_pose(0.5)
	_check(bool(pose.call("set_calibration", 0.2, 0.5, 0.8)),
		source + " physical 3-position calibration accepted without tracker identity")
	var authored_scene := (load("res://ui/minigames/catch_the_word/catch_word.tscn") as PackedScene).instantiate() as Control
	var authored_hud := authored_scene.get_node("HUDLayer/HUD") as Control
	var authored_score := authored_hud.get_node_or_null("ScoreNumber") as Label
	var authored_plaque := authored_hud.get_node_or_null("ScorePlaque") as TextureRect
	_check(authored_score != null and not authored_hud.has_node("ScoreBottomContainer"),
		source + " editable Catch scene has one direct HUD/ScoreNumber and no container")
	var authored_position := authored_score.position if authored_score != null else Vector2.ZERO
	var authored_size := authored_score.size if authored_score != null else Vector2.ZERO
	var authored_font_size := authored_score.get_theme_font_size("font_size") if authored_score != null else 0
	var plaque_position := authored_plaque.position if authored_plaque != null else Vector2.ZERO
	var plaque_size := authored_plaque.size if authored_plaque != null else Vector2.ZERO
	authored_scene.free()
	var source_scene := load(WRAPPER_PATH) as PackedScene
	_check(source_scene != null, source + " gameplay wrapper source parses")
	if source_scene == null:
		return
	var wrapper := source_scene.instantiate() as Control
	_check(wrapper != null and wrapper.has_method("set_context"),
		source + " wrapper has real Gameplay implementation, not an inert Control")
	if wrapper == null or not wrapper.has_method("set_context"):
		if wrapper != null:
			wrapper.free()
		return
	root.add_child(wrapper)
	wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wrapper.set_context({"activity": "Catch the Word", "game_mode": "Seconds",
		"difficulty": "Easy", "topic": "Noun", "start_countdown": true,
		"entry_source": source, "guided_tutorial": source == "tutorial",
		"camera_live": true, "camera_requested": true,
		"calibration_live": true, "calibration_measured": true,
		"student_id": "SYNTHETIC-ONLY", "student_lookup_connected": source == "play"})
	await process_frame
	var catch_game := wrapper.get("active_game") as Control
	_check(catch_game != null and catch_game.process_mode == Node.PROCESS_MODE_DISABLED,
		source + " Catch is held during guided/countdown startup")
	if catch_game == null:
		pose.worker_pid = -1
		wrapper.queue_free()
		await process_frame
		return
	# Assert that Catch uses the actual direct-child editor score, preserving its
	# artwork and geometry while reparenting it behind the playable character.
	var score_number := catch_game.get("score_bottom_number") as Label
	var score_plaque := catch_game.get("score_plaque") as TextureRect
	var score_layer := catch_game.get("score_draw_layer") as Control
	_check(is_instance_valid(score_number),
		source + " user-authored ScoreNumber binds without a missing-node error")
	if is_instance_valid(score_number):
		_check(score_number.get_parent() == score_layer and score_number.visible and
			catch_game.get_node_or_null("ScoreDrawLayer/ScoreNumber") == score_number and
			catch_game.get_node_or_null("ScoreDrawLayer/ScoreBottomContainer") == null,
			source + " only authored score is visible in behind-character draw layer")
		_check(score_number.position.distance_to(authored_position) < 1.0 and
			score_number.size.distance_to(authored_size) < 1.0,
			source + " ScoreNumber keeps its authored 1280x720 position")
		_check(score_number.get_theme_font_size("font_size") == authored_font_size,
			source + " ScoreNumber keeps its scene-authored font size")
		_check(score_plaque != null and score_plaque.position.distance_to(plaque_position) < 1.0
			and score_plaque.size.distance_to(plaque_size) < 1.0,
			source + " scoreboard PNG keeps saved editor placement and size")
		var score_center_fraction := (score_number.position.y + score_number.size.y * 0.5 \
			- score_plaque.position.y) / score_plaque.size.y
		_check(absf(score_center_fraction - 0.60) < 0.10,
			source + " numeric score center is inside the artwork's brown inset")
		catch_game.set("score", 125)
		catch_game.call("_refresh_hud")
		_check(score_number.text == "125",
			source + " actual scoreboard updates when Catch score changes")
		catch_game.set("score", 0)
		catch_game.call("_refresh_hud")
	if source == "tutorial":
		wrapper.call("_on_spotlight_finished")
		await process_frame
	_check(String(wrapper.get("guided_stage")) == "countdown",
		source + " enters same shared 3-2-1 countdown")
	for _tick in range(3):
		wrapper.call("_on_countdown_tick")
	_check(String(wrapper.get("guided_stage")) == "", # contract currently clears marker
		source + " releases overlay at GO")
	_check(catch_game.process_mode == Node.PROCESS_MODE_INHERIT,
		source + " Catch processing enabled after three countdown ticks")
	var before_x := float(catch_game.get("basket_x"))
	var before_time := float(catch_game.get("time_remaining"))
	_set_pose(0.8)
	wrapper.call("_process", 0.05)
	catch_game.call("_process", 0.20)
	_check(bool(catch_game.get("body_input_active")),
			source + " receives fresh SOLO body input after GO")
	_check(float(catch_game.get("basket_x")) > before_x + 1.0,
		source + " visible Catch basket actually moves right after GO")
	_check(float(catch_game.get("time_remaining")) < before_time - 0.1,
		source + " countdown-to-live transition advances gameplay clock")
	# A single fresh YOLO human with temporarily invalid pose never toggles
	# PAUSE/PLAY. Movement is neutral until a valid new pose appears.
	pose.last_pose_ms = Time.get_ticks_msec() - 2400
	wrapper.call("_process", 0.70)
	_check(not bool(wrapper.get("tracking_suspended")) and
		catch_game.process_mode != Node.PROCESS_MODE_DISABLED and
		not bool(wrapper.get("last_pose_valid")),
		source + " visible solo with missing pose keeps game going without stale motion")
	_set_pose(0.2)
	wrapper.call("_process", 0.04)
	_check(not bool(wrapper.get("tracking_suspended")) and
		catch_game.process_mode == Node.PROCESS_MODE_INHERIT,
			source + " fresh one-person pose automatically unfreezes game")
	var held_x := float(catch_game.get("basket_x"))
	catch_game.call("_process", 0.25)
	_check(float(catch_game.get("basket_x")) < held_x - 1.0,
			source + " one-person camera input steers left after tracking recovery")
	pose.worker_pid = -1 # Wrapper _exit_tree invokes stop_camera: do not kill Godot PID.
	wrapper.queue_free()
	await process_frame
	await process_frame
	pose.worker_pid = -1
	pose.stop_camera()


func _set_pose(x: float) -> void:
	pose.active = true
	var packet := {"kind": "pose", "token": pose.session_token,
		"camera_phase": "tracking", "state": "tracking", "pose": true,
		"camera": true, "people": 1, "lock_state": "locked",
		"camera_frame_age_ms": 20,
		"locked_id": TRACK_ID, "x": x, "hand_observation_valid": true}
	pose.call("_apply_pose_packet", packet, Time.get_ticks_msec())


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("PLAY/TUTORIAL COUNTDOWN CATCH FAIL: ", label)


func _finish() -> void:
	print("PLAY VS TUTORIAL LIVE COUNTDOWN/CATCH: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
