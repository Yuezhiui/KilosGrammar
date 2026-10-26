extends SceneTree

# Run: Godot --headless --path . --script res://tools/test_guided_onboarding.gd
# Integration coverage for the real game wrapper, without webcam access.
const WRAPPER := "res://ui/play/gameplay.tscn"
const SPOTLIGHT := "res://ui/tutorial/spotlight_overlay.tscn"
const COUNTDOWN := preload("res://ui/play/guided_countdown.tscn")
const SCENARIOS := [
	{"activity": "Catch the Word", "mode": "Seconds"},
	{"activity": "Catch the Word", "mode": "Lives"},
	{"activity": "Balloon Popping", "mode": "Seconds"},
	{"activity": "Balloon Popping", "mode": "Lives"},
	{"activity": "Human Plane", "mode": "Seconds"},
	{"activity": "Human Plane", "mode": "Lives"}
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_expect(ResourceLoader.exists(SPOTLIGHT), "Scene-authored spotlight is installed")
	var countdown := COUNTDOWN.instantiate() as Control
	_expect(countdown != null, "Countdown is an editable Control scene")
	if countdown != null:
		_expect(countdown.get_node_or_null("CountdownNumber") is Label, "Countdown label is editor-authored")
		_expect(countdown.get_node_or_null("GetReadyTitle") is Label, "Countdown headline is editor-authored")
		_expect(countdown.get_node_or_null("CountdownTimer") is Timer, "Countdown timer is part of the .tscn")
		countdown.free()
	for scenario in SCENARIOS:
		await _check_guided(String(scenario["activity"]), String(scenario["mode"]))
	await _check_regular_play()
	print("GUIDED ONBOARDING: ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	for failure in failures:
		printerr("FAIL guided-onboarding: ", failure)
	quit(0 if failures.is_empty() else 1)


func _check_guided(activity: String, mode: String) -> void:
	var label := "%s / %s" % [activity, mode]
	var wrapper := (load(WRAPPER) as PackedScene).instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({
		"activity": activity, "game_mode": mode,
		"guided_tutorial": true, "keyboard_mode": true,
		"camera_live": false, "topic": "Noun", "game_style": "Noun",
		"difficulty": "Easy"
	})
	await process_frame
	await process_frame
	await process_frame
	var game := wrapper.get_node_or_null("ActiveMiniGame") as Control
	_expect(game != null, label + ": real minigame mounted")
	if game == null:
		wrapper.queue_free()
		await process_frame
		return
	_expect(game.process_mode == Node.PROCESS_MODE_DISABLED, label + ": gameplay/input frozen during tutorial")
	_expect(String(wrapper.get("guided_stage")) == "tutorial", label + ": spotlight comes before gameplay")
	var overlay := wrapper.get("spotlight_overlay") as CanvasLayer
	_expect(overlay != null, label + ": spotlight is visible")
	var focus := wrapper.call("_spotlight_targets") as Dictionary
	_expect(focus.has("pause") and focus.has("play_area"), label + ": targets live game controls")
	_expect(focus.has("prompt") and focus.has("score") and focus.has("mode"), label + ": prompt, score and mode HUD targets exist")
	if focus.has("mode"):
		var expected_mode := "LivesPlaque" if mode == "Lives" else "TimerPlaque"
		_expect(String((focus["mode"] as Node).name) == expected_mode, label + ": spotlight selects proper time/life counter")
	if activity == "Human Plane":
		# Human Plane now uses the same scene-authored CanvasLayer/HUD nodes as
		# Catch the Word. Obsolete HUD/* artwork paths silently fall back to
		# generic spotlight rectangles and fail to highlight the live controls.
		var hud_targets := {
			"prompt": "HUDLayer/HUD/PromptLabel",
			"mode": "HUDLayer/HUD/LivesPlaque" if mode == "Lives" else "HUDLayer/HUD/TimerPlaque",
			"score": "HUDLayer/HUD/ScorePlaque",
			"pause": "HUDLayer/HUD/PauseButton",
			"play_area": "PlaneRig",
		}
		for key in hud_targets:
			var expected := game.get_node_or_null(String(hud_targets[key])) as CanvasItem
			_expect(expected != null, label + ": authored %s target exists (%s)" % [key, hud_targets[key]])
			_expect(expected != null and focus.get(key) == expected,
				label + ": %s resolves to live %s (not obsolete HUD/* or fallback)" % [key, hud_targets[key]])
			if key in ["prompt", "mode", "score", "pause"] and expected != null:
				_expect(expected.is_visible_in_tree(), label + ": %s target is actually visible" % key)
		var inactive_mode_path := (
			"HUDLayer/HUD/TimerPlaque" if mode == "Lives" else "HUDLayer/HUD/LivesPlaque"
		)
		var inactive_mode := game.get_node_or_null(inactive_mode_path) as CanvasItem
		_expect(inactive_mode != null and not inactive_mode.is_visible_in_tree(),
			label + ": inactive Seconds/Lives plaque stays hidden")
		if overlay != null:
			_check_human_plane_spotlight(overlay, focus, label)
	var initial_time := float(game.get("time_remaining"))
	var initial_score := int(game.get("score"))
	var initial_lives := _remaining_lives(game, activity)
	# Movement-only preview remains enabled during spotlight without running
	# scoring/timers; Human Plane is now explicitly gated by BOTH arms outward.
	var initial_x := _visual_player_x(game, activity)
	game.call("set_body_x", 0.85)
	wrapper.call("_preview_guided_movement", 0.2)
	if activity == "Human Plane":
		_expect(is_equal_approx(_visual_player_x(game, activity), initial_x), label + ": arms lowered prevent airplane movement even during tutorial")
		# After three-position calibration, WIDE arms enable the same
		# physical left/right stepping preview used by Catch the Word.
		# Tilt/gyro angle no longer controls Human Plane.
		game.call("set_airplane_pose_active", true)
		game.call("set_body_x", 0.85)
		wrapper.call("_preview_guided_movement", 0.2)
		_expect(not is_equal_approx(_visual_player_x(game, activity), initial_x), label + ": wide arms and calibrated body X enable guided movement without starting round")
		game.call("set_airplane_pose_active", false)
	else:
		_expect(not is_equal_approx(_visual_player_x(game, activity), initial_x), label + ": body movement previews without starting the round")
	await create_timer(0.16).timeout
	_expect(is_equal_approx(float(game.get("time_remaining")), initial_time), label + ": clock holds through spotlight")
	_expect(int(game.get("score")) == initial_score, label + ": scoring holds through spotlight")
	_expect(_remaining_lives(game, activity) == initial_lives, label + ": lives hold through spotlight")
	# Calling ESC through the wrapper must not trigger ordinary Pause underneath.
	wrapper.call("_pause")
	_expect(String(wrapper.get("guided_stage")) == "tutorial", label + ": native Pause cannot bypass spotlight")
	if overlay != null:
		_expect(overlay.has_signal("skipped") and overlay.has_signal("finished"), label + ": overlay exposes close signals")
		if mode == "Lives":
			# Exercise the actual Next/Start controls through all five Spotlight
			# steps, including the active lives rule and finished signal.
			var steps := overlay.call("get_step_ids") as PackedStringArray
			_expect(steps.size() == 5, label + ": five interactive spotlight steps")
			_expect(steps.has(activity.to_lower().replace(" ", "_").replace("the_", "") + "_lives"), label + ": lives rule appears in the walkthrough")
			for step in range(steps.size()):
				overlay.call("go_next")
		else:
			overlay.call("skip")
	await process_frame
	_expect(String(wrapper.get("guided_stage")) == "countdown", label + ": skip starts 3-2-1")
	_expect(game.process_mode == Node.PROCESS_MODE_DISABLED, label + ": minigame remains frozen for countdown")
	var countdown_panel := wrapper.get("countdown_panel") as Control
	_expect(countdown_panel != null, label + ": countdown scene mounted")
	if countdown_panel != null:
		var number := countdown_panel.get_node_or_null("CountdownNumber") as Label
		_expect(number != null and number.text == "3", label + ": countdown begins at 3")
		wrapper.call("_on_countdown_tick")
		_expect(number.text == "2", label + ": countdown reaches 2")
		wrapper.call("_on_countdown_tick")
		_expect(number.text == "1", label + ": countdown reaches 1")
		_expect(game.process_mode == Node.PROCESS_MODE_DISABLED, label + ": remains frozen through last number")
		wrapper.call("_on_countdown_tick")
		_expect(game.process_mode == Node.PROCESS_MODE_INHERIT, label + ": child released after final countdown tick")
		_expect(wrapper.get_node_or_null("ActiveMiniGame") == game, label + ": countdown resumes original minigame instance")
		_expect(wrapper.get("countdown_panel") == null, label + ": countdown overlay removed")
	wrapper.queue_free()
	await process_frame
	await process_frame
	print("Checked guided flow: ", label)


func _check_regular_play() -> void:
	var wrapper := (load(WRAPPER) as PackedScene).instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({
		"activity": "Catch the Word", "game_mode": "Seconds",
		"guided_tutorial": false, "keyboard_mode": true,
		"camera_live": false, "topic": "Noun", "difficulty": "Easy"
	})
	await process_frame
	await process_frame
	var game := wrapper.get_node_or_null("ActiveMiniGame") as Control
	_expect(game != null and game.process_mode == Node.PROCESS_MODE_INHERIT, "Ordinary Play mounts running minigame immediately")
	_expect(wrapper.get("spotlight_overlay") == null and wrapper.get("countdown_panel") == null, "Ordinary Play bypasses guided UI")
	var requested_routes: Array[String] = []
	wrapper.requested.connect(func(route: String, _payload: Dictionary) -> void: requested_routes.append(route))
	wrapper.call("_pause")
	_expect(requested_routes.has("pause"), "Ordinary Play retains native Pause navigation")
	wrapper.call("_resume")
	_expect(bool(game.get("round_running")), "Ordinary Play resumes native round state")
	wrapper.queue_free()
	await process_frame
	await process_frame


func _remaining_lives(game: Control, activity: String) -> int:
	if activity == "Balloon Popping":
		return int(game.get("hearts"))
	return int(game.get("lives"))


func _check_human_plane_spotlight(overlay: CanvasLayer, focus: Dictionary, label: String) -> void:
	# The shader hole must follow each actual live target, including the
	# CanvasLayer HUD, while NEXT/BACK continue to work. Restore step 1 before
	# the existing onboarding assertions exercise Skip or Start Game.
	var sequence: Array[String] = ["prompt", "play_area", "mode", "score", "pause"]
	for index in range(sequence.size()):
		if index > 0:
			overlay.call("go_next")
		var key: String = sequence[index]
		var target := focus.get(key) as Control
		if target == null:
			continue
		var hole := overlay.call("get_spotlight_rect") as Rect2
		var center := target.get_global_rect().get_center()
		if bool(overlay.get("use_editor_highlights")):
			var slot_name: String = String({
				"prompt": "Prompt", "play_area": "PlayArea", "mode": "Seconds" if label.contains("Seconds") else "Lives",
				"score": "Score", "pause": "Pause"
			}.get(key, "Prompt"))
			var guide := overlay.get_node_or_null("Overlay/FocusRegions/HumanPlane/" + String(slot_name)) as Control
			if guide != null:
				center = guide.get_global_rect().get_center()
		_expect(hole.get_area() > 0.0 and hole.has_point(center),
			label + ": step %d spotlight hole covers the editor-authored %s guide" % [index + 1, key])
	for _index in range(sequence.size() - 1):
		overlay.call("go_back")
	_expect(String(overlay.call("get_current_step_id")) == "human_plane_prompt",
		label + ": spotlight navigation returns to the original prompt step")


func _visual_player_x(game: Control, activity: String) -> float:
	match activity:
		"Catch the Word":
			return float(game.get("basket_x"))
		"Balloon Popping":
			return float(game.get("launcher_x"))
		_:
			return float(game.get("plane_x_norm"))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
