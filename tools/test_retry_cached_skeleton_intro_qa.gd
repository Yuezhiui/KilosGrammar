extends SceneTree

# Regression for Main Menu -> results Retry -> NEW Play/Tutorial calibration.
# Uses real menu, Results, Student Setup, Activity and Calibration Controls,
# but strictly synthetic fresh SOLO pose packets and a green-bones preview
# image. Never opens a webcam, YOLO helper, real PostgreSQL, or an Internet URL.
# Godot --headless --path . --script res://tools/test_retry_cached_skeleton_intro_qa.gd

const MOCK_DATABASE := preload("res://tools/play_route_mock_database.gd")
const POSITIONS := [0.50, 0.80, 0.20]
const INTRO_SECONDS_REQUESTED := 3.0
const SUCCESS_SECONDS_REQUESTED := 3.0
var checks := 0
var failures: Array[String] = []
var pose: Node
var app: Control
var sample_time := 1000.0
var green_bones: ImageTexture


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(28.0).timeout
	_assert(false, "QA watchdog: test did not finish before 28 seconds")
	_disarm_fake_worker()
	_finish()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	pose = root.get_node_or_null("PoseService")
	_assert(pose != null, "Real PoseService autoload exists")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	green_bones = _green_skeleton_preview()
	app = (load("res://ui/main_menu/main_menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(app)
	await process_frame
	await _install_fake_database()
	for tutorial in [false, true]:
		await _run_retry(tutorial)
	_disarm_fake_worker()
	if is_instance_valid(app):
		app.call("_return_to_main")
		await process_frame
		await app.call("prepare_for_shutdown")
		app.queue_free()
		await process_frame
		await process_frame
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _install_fake_database() -> void:
	var client := app.get("database_client") as Node
	if is_instance_valid(client):
		var finished := Callable(app, "_on_database_request_finished")
		if client.has_signal("request_finished") and client.is_connected("request_finished", finished):
			client.disconnect("request_finished", finished)
		var lifecycle := Callable(app, "_on_database_local_service_status_changed")
		if client.has_signal("local_service_status_changed") and client.is_connected("local_service_status_changed", lifecycle):
			client.disconnect("local_service_status_changed", lifecycle)
		client.queue_free()
		await process_frame
	var fake := MOCK_DATABASE.new() as Node
	app.add_child(fake)
	app.set("database_client", fake)
	fake.request_finished.connect(Callable(app, "_on_database_request_finished"))
	fake.local_service_status_changed.connect(Callable(app, "_on_database_local_service_status_changed"))
	app.set("database_online", false) # NO student registration or DB requests.
	_assert(fake.get("register_calls").is_empty(), "No real DB registration during QA setup")


func _run_retry(tutorial: bool) -> void:
	var prefix := "Tutorial Retry" if tutorial else "Play Retry"
	app.call("_return_to_main")
	await process_frame
	pose.set_process(false)
	# Exercise the actual Tutorial Home and activity selector before the
	# previous completed synthetic round, so its Retry must remain practice.
	if tutorial:
		app.call("_on_panel_requested", "tutorial_home", {})
		await process_frame
		var home := app.get("active_panel") as Control
		(home.get_node("TutorialStage/StartButton") as Button).pressed.emit()
		await process_frame
		var selection := app.get("active_panel") as Control
		_assert(String(app.get("current_route")) == "play_activity",
			prefix + ": Tutorial Home enters genuine activity chooser")
		selection.call("_select_activity", "Catch the Word")
		selection.call("_go_next")
		await process_frame
		_assert(String(app.get("current_route")) == "student_setup",
			prefix + ": Tutorial chooses Catch before entering student setup")
	else:
		app.call("_on_panel_requested", "student_setup", {})
		await process_frame
		_assert(String(app.get("current_route")) == "student_setup",
			prefix + ": main Play opens real student setup")
	# Synthesize completion and show the REAL Results scene; its Retry button
	# must route through main_menu.gd, not a manually created calibration.
	var previous := {
		"student_id": "RETRY-STUDENT", "student_name": "Student Before",
		"grade_section": "Grade 4 - OLD", "game_style": "Noun",
		"topic": "Noun", "game_mode": "Seconds", "difficulty": "Easy",
		"activity": "Catch the Word", "entry_source": "tutorial" if tutorial else "play",
		"guided_tutorial": tutorial, "round_completed": true, "score": 250,
	}
	app.set("session_state", previous)
	app.call("_show_panel", "results")
	await process_frame
	var results := app.get("active_panel") as Control
	_assert(String(app.get("current_route")) == "results",
		prefix + ": real Results screen shown after completed Catch round")
	var retry := results.get_node_or_null("%RetryButton") as Button
	_assert(retry != null, prefix + ": Results Retry button exists")
	if retry == null:
		return
	retry.pressed.emit()
	await process_frame
	_assert(String(app.get("current_route")) == "student_setup",
		prefix + ": Results Retry routes to real editable Student Setup")
	var form := app.get("active_panel") as Control
	var new_name := "Student Changed " + ("T" if tutorial else "P")
	(form.get("_student_id_edit") as LineEdit).text = "RETRY-STUDENT"
	(form.get("_name_edit") as LineEdit).text = new_name
	(form.get("_grade_edit") as LineEdit).text = "Grade 6 - NEW"
	form.call("_select_style", "Verb")
	form.call("_select_mode", "Seconds")
	form.call("_select_difficulty", "Normal")
	# The Tutorial form emits 'calibration' synchronously; cache the SOLO
	# camera BEFORE _continue so no webcam worker may launch in its _ready.
	if tutorial:
		_seed_continuous_preview(0.50)
	# The form is real and we do not connect to any database.
	form.call("_continue")
	if not tutorial:
		await process_frame
		_assert(String(app.get("current_route")) == "play_activity",
			prefix + ": changed Play student info continues to real activity picker")
		var choose := app.get("active_panel") as Control
		choose.call("_select_activity", "Catch the Word")
		# Ensure the user does not have to leave/reenter to see a skeleton.
		# Seed the service while a live solo student remains continuously in view.
		_seed_continuous_preview(0.50)
		choose.call("_go_next")
	# Tutorial -> Setup keeps the already selected activity and routes
	# directly to calibration. Play -> Setup selects that same activity again.
	_assert(String(app.get("current_route")) == "calibration",
		prefix + ": Retry reaches genuine calibration without keyboard fallback")
	var screen := app.get("active_panel") as Control
	if screen == null or String(app.get("current_route")) != "calibration":
		_disarm_fake_worker()
		return
	# Disable actual frame-driven screen processing before yielding; the
	# synthetic packet stream below owns the exact calibration test timings.
	screen.set_process(false)
	_pose_packet(0.50)
	_assert(String((app.get("session_state") as Dictionary).get("student_name", "")) == new_name
		and String((app.get("session_state") as Dictionary).get("activity", "")) == "Catch the Word",
		prefix + ": new student details and SAME activity survive retry")
	_assert(not bool(pose.calibration.get("valid", false)),
		prefix + ": Retry starts a NEW physical calibration")
	# Do not let actual scene _process run: all time and pose packets below
	# are deterministic and use the original scene's real methods.
	await _check_intro_and_cached_bones(screen, prefix)
	# Let the editor-authored Back focus request resolve while calibration is
	# still mounted, before the success route queues that screen for removal.
	await process_frame
	await _check_three_positions(screen, prefix)
	_assert(pose.active and pose.worker_pid == OS.get_process_id() and pose.peer != null,
		prefix + ": preview uses safe in-process liveness, no YOLO/webcam worker spawned")
	_disarm_fake_worker()


func _seed_continuous_preview(x: float) -> void:
	pose.active = true
	pose.set_process(false)
	pose.session_token = "qa-retry-same-camera"
	# The production cache correctly demands a live worker + socket; model
	# ONLY that check using our already running Godot PID and an unbound UDP
	# object. Restore both before ANY stop_camera call or route that stops it.
	pose.worker_pid = OS.get_process_id()
	pose.peer = PacketPeerUDP.new()
	pose.set("_restart_pending", false)
	pose.preview_texture = green_bones
	pose.set("_last_preview_ms", Time.get_ticks_msec())
	_pose_packet(x)


func _disarm_fake_worker() -> void:
	if pose != null and pose.worker_pid == OS.get_process_id():
		pose.worker_pid = -1
		pose.peer = null


func _check_intro_and_cached_bones(screen: Control, prefix: String) -> void:
	var stage := screen.get_node("TutorialStage") as Control
	var intro := stage.get_node("IntroOverlay") as ColorRect
	var success := stage.get_node("SuccessOverlay") as ColorRect
	var dimmer := screen.get_node("ClassroomDimmer") as ColorRect
	var camera := stage.get_node("CameraArea/LiveCameraInset") as TextureRect
	_assert(bool(screen.get("intro_running")) and intro.visible,
		prefix + ": CALIBRATION intro begins immediately on Retry")
	var composite_darkness := 1.0 - (1.0 - dimmer.color.a) * (1.0 - intro.color.a)
	_assert(composite_darkness >= 0.60 and composite_darkness <= 0.70,
		prefix + ": intro darkness %.2f must be 60-70%%" % composite_darkness)
	var visible_labels: Array[String] = []
	for node in intro.get_children():
		if node is Label and (node as Label).is_visible_in_tree():
			visible_labels.append((node as Label).text.strip_edges())
	_assert(visible_labels == ["CALIBRATION"]
		and intro.get_node_or_null("ArtIntroTitle") is Label,
		prefix + ": only CALIBRATION text appears in intro (visible=%s)" % str(visible_labels))
	for retired in ["IntroDescription", "IntroCountdown", "IntroBackButton", "IntroHeading"]:
		_assert(intro.get_node_or_null(retired) == null,
			prefix + ": unused intro control removed: " + retired)
	_assert(not success.visible
		and success.get_node_or_null("SuccessTitle") is Label
		and success.get_node_or_null("SuccessSubtitle") is Label,
		prefix + ": authored success screen remains hidden during CALIBRATION introduction")
	# Regression for real Results -> Retry: a fresh set_context must not
	# resurrect stage siblings underneath the 66% transparent intro overlay.
	for asset in ["PoseGuides/PoseGuideDefault",
			"Directions/ArtArrowCenter", "Directions/ArtTitleCenter", "Directions/ArtStep1", "CountdownArtwork/ArtCountdown3",
			"Directions/ArtMoveHintCenter"]:
		var node := stage.get_node_or_null(asset) as Control
		_assert(node != null and not node.is_visible_in_tree(),
			prefix + ": %s stays hidden until CALIBRATION intro ends" % asset)
	_assert(not camera.is_visible_in_tree() and int(screen.get("live_step")) == 0,
		prefix + ": camera/stage remain hidden during intro")
	var constants := screen.get_script().get_script_constant_map() as Dictionary
	_assert(is_equal_approx(float(constants.get("INTRO_SECONDS", -1.0)), INTRO_SECONDS_REQUESTED),
		prefix + ": intro duration is exactly 3.0 seconds")
	_assert(is_equal_approx(float(constants.get("SUCCESS_SECONDS", -1.0)), SUCCESS_SECONDS_REQUESTED),
		prefix + ": success screen requires exactly 3.0 seconds after real holds")
	# Model a continuous stationary SOLO child throughout the full 3 seconds:
	# source packets are fresh, but there is no new *preview_updated* event.
	var entry_elapsed := float(screen.get("intro_elapsed"))
	_assert(entry_elapsed < 0.10,
		prefix + ": NEW calibration intro does not inherit old UI elapsed time")
	_pose_packet(0.50)
	screen.call("_process", 1.50)
	_pose_packet(0.50)
	screen.call("_process", maxf(0.0, 2.98 - float(screen.get("intro_elapsed"))))
	_assert(bool(screen.get("intro_running")) and int(screen.get("live_step")) == 0,
		prefix + ": intro still visible at 2.99 seconds; no hold credited")
	_pose_packet(0.50)
	screen.call("_process", 0.04)
	_assert(not bool(screen.get("intro_running")) and not intro.visible,
		prefix + ": intro completes after full 3 seconds")
	_assert((stage.get_node("PoseGuides/PoseGuideDefault") as Control).visible
		and not (stage.get_node("PoseGuides/PoseGuideBalloonRaise") as Control).visible
		and not (stage.get_node("PoseGuides/PoseGuidePlaneCenter") as Control).visible
		and stage.get_node_or_null("ArtGuideCenter") == null,
		prefix + ": new DEFAULT PNG appears after intro without retired neon art")
	# A live solo person has NEVER left the camera. The bones are the green
	# polyline pixels baked into the synthetic pose-preview JPEG texture.
	# New calibration must attach the current cached frame upon mounting,
	# rather than requiring a NEW preview_updated signal from worker/YOLO.
	_assert(pose.preview_texture == green_bones and pose.has_valid_pose(),
		prefix + ": PoseService still has fresh SOLO pose and green bones preview; state=%s x=%.2f active=%s" % [
			str(pose.current_status), float(pose.player_x), str(pose.active)])
	_assert(camera.texture == green_bones and camera.is_visible_in_tree(),
		prefix + ": cached green skeleton is visible IMMEDIATELY without leave/reenter")
	# Diagnostic control: next *unchanged* live preview event should restore
	# bones if the only problem was missing replay on scene attach.
	pose.preview_updated.emit(green_bones)
	_assert(camera.texture == green_bones and camera.is_visible_in_tree(),
		prefix + ": same-person next preview refresh renders the very same bones")
	_assert((green_bones.get_image() as Image).get_pixel(30, 20).g > 0.75,
		prefix + ": synthetic frame contains recognizable bright green bones")


func _check_three_positions(screen: Control, prefix: String) -> void:
	var routed: Array[String] = []
	screen.requested.connect(func(route: String, _payload: Dictionary) -> void: routed.append(route))
	for index in range(POSITIONS.size()):
		for _i in range(58):
			_pose_packet(POSITIONS[index])
			sample_time += 0.12
			pose.call("_record_fresh_calibration_pose", pose.current_status, sample_time)
			screen.call("_process", 0.12)
			# Stop on the FIRST genuine completed hold. Continuing for the
			# original 58 packets can consume the new success screen while still
			# trying to use a Calibration node already replaced by gameplay.
			if int(screen.get("live_step")) > index:
				break
		_assert(int(screen.get("live_step")) == index + 1,
			prefix + ": stage %d of CENTER RIGHT LEFT passes with continuous SOLO pose" % (index + 1))
	var measured := screen.get("measured_points") as Dictionary
	_assert(measured.has("center") and measured.has("right") and measured.has("left")
		and absf(float(measured.get("center", -1)) - 0.50) < 0.03
		and absf(float(measured.get("right", -1)) - 0.80) < 0.03
		and absf(float(measured.get("left", -1)) - 0.20) < 0.03,
		prefix + ": fresh CENTER/RIGHT/LEFT coordinates captured with NO leave/reenter")
	_assert(bool(pose.calibration.get("valid", false)) and bool(screen.get("transition_queued")),
		prefix + ": real calibrated results are ready without another camera enrollment")
	var stage := screen.get_node("TutorialStage") as Control
	var success := stage.get_node("SuccessOverlay") as ColorRect
	var dimmer := screen.get_node("ClassroomDimmer") as ColorRect
	var darkness := 1.0 - (1.0 - dimmer.color.a) * (1.0 - success.color.a)
	_assert(success.visible and bool(screen.get("success_running"))
		and darkness >= 0.60 and darkness <= 0.70,
		prefix + ": fresh complete holds display 60-70% dark success screen")
	_assert((success.get_node("SuccessTitle") as Label).text.contains("CALIBRATION SUCCESS")
		and (success.get_node("SuccessSubtitle") as Label).text.contains("Handa"),
		prefix + ": editor-authored success title/subtitle appear on Retry")
	for child in stage.get_children():
		if child is Control and child != success:
			_assert(not (child as Control).visible,
				prefix + ": success hides all directions, pose, timer and Back art: " + child.name)
	_assert(routed.is_empty(), prefix + ": no gameplay transition on the last physical hold")
	screen.call("_continue_flow", false)
	_assert(routed.is_empty(), prefix + ": legacy direct Continue never skips success")
	# Stay in the exact same camera frame and repeat fresh SOLO packets for
	# the next three seconds. No leave/reenter, stale sample, or shortcut.
	var before_ticks := maxi(0, floori((SUCCESS_SECONDS_REQUESTED -
		float(screen.get("success_elapsed")) - 0.15) / 0.12))
	for tick in range(before_ticks):
		_pose_packet(0.50)
		sample_time += 0.12
		pose.call("_record_fresh_calibration_pose", pose.current_status, sample_time)
		screen.call("_process", 0.12)
	_assert(routed.is_empty() and success.visible
		and float(screen.get("success_elapsed")) < SUCCESS_SECONDS_REQUESTED,
		prefix + ": same student remains on success until 3 real seconds")
	for tick in range(3):
		_pose_packet(0.50)
		sample_time += 0.12
		pose.call("_record_fresh_calibration_pose", pose.current_status, sample_time)
		screen.call("_process", 0.12)
		if not routed.is_empty():
			break
	_assert(routed == ["gameplay"] and String(app.get("current_route")) == "gameplay",
		prefix + ": post-success handoff enters real gameplay exactly once")
	await process_frame
	var wrapper := app.get("active_panel") as Control
	_assert(wrapper != null and wrapper.has_method("_on_countdown_tick"),
		prefix + ": real gameplay wrapper created by MainMenu")
	if wrapper == null or not wrapper.has_method("_on_countdown_tick"):
		return
	var game_context := wrapper.get("context") as Dictionary
	_assert(bool(game_context.get("calibration_measured", false))
		and bool(game_context.get("camera_live", false))
		and bool(game_context.get("start_countdown", false))
		and not bool(game_context.get("keyboard_mode", true)),
		prefix + ": verified camera score run inherits fresh calibration and countdown flags")
	var tutorial := prefix.begins_with("Tutorial")
	_assert(bool(game_context.get("guided_tutorial", false)) == tutorial,
		prefix + ": Retry carries the original Play or Tutorial flow into gameplay")
	var active := wrapper.get("active_game") as Control
	_assert(active != null and active.process_mode == Node.PROCESS_MODE_DISABLED,
		prefix + ": gameplay is frozen before GO")
	if active == null:
		return
	_assert(String(wrapper.get("guided_stage")) == "countdown",
		prefix + ": verified calibration enters direct 3-2-1 in Tutorial and Play")
	var countdown := wrapper.get("countdown_panel") as Control
	_assert(countdown != null and countdown.get_node_or_null("CountdownNumber") is Label
		and (countdown.get_node("CountdownNumber") as Label).text == "3",
		prefix + ": editor-authored countdown begins at 3 immediately after calibration")
	var frozen_score := int(active.get("score"))
	var frozen_lives := int(active.get("lives"))
	var frozen_time := float(active.get("time_remaining"))
	for tick in range(3):
		_pose_packet(0.50)
		wrapper.call("_on_countdown_tick")
	_assert(String(wrapper.get("guided_stage")) == ""
		and wrapper.get("countdown_panel") == null
		and active.process_mode == Node.PROCESS_MODE_INHERIT,
		prefix + ": 3-2-1 reaches GO and releases gameplay only with fresh SOLO pose " +
		"(stage=%s mode=%s pose=%s population=%s countdown=%s)" % [
			str(wrapper.get("guided_stage")), str(active.process_mode),
			str(pose.has_valid_pose()), str(pose.fresh_camera_population()),
			str(wrapper.get("countdown_value"))])
	_assert(int(active.get("score")) == frozen_score and int(active.get("lives")) == frozen_lives
		and is_equal_approx(float(active.get("time_remaining")), frozen_time),
		prefix + ": score, lives and 60-second timer do not advance before GO")


func _pose_packet(x: float) -> void:
	pose.call("_apply_pose_packet", {
		"token": pose.session_token, "kind": "pose", "state": "tracking",
		"camera": true, "camera_phase": "tracking", "pose": true,
		"people": 1, "lock_state": "locked", "locked_id": 31,
			"camera_frame_age_ms": 20, "x": x, "fps": 10.0,
			"hand_observation_valid": true, "hand_up": false,
	}, Time.get_ticks_msec())


func _green_skeleton_preview() -> ImageTexture:
	var image := Image.create(64, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.13, 0.18, 0.26, 1.0))
	for y in range(8, 39):
		image.set_pixel(30, y, Color(0.12, 1.0, 0.15, 1.0))
	for x in range(18, 44):
		image.set_pixel(x, 20, Color(0.12, 1.0, 0.15, 1.0))
	return ImageTexture.create_from_image(image)


func _assert(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
		printerr("RETRY INTRO/SKELETON QA FAIL: ", detail)


func _finish() -> void:
	print("RETRY INTRO & CACHED SKELETON QA: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
