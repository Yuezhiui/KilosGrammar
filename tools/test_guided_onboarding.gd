extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_guided_onboarding.gd
# Distinct QA from the viewport matrix: scene-authored countdown, native
# Pause behavior and no-countdown legacy normal Play. No camera/DB/network.
const WRAPPER := "res://ui/play/gameplay/gameplay.tscn"
const COUNTDOWN := "res://ui/play/gameplay/guided_countdown.tscn"
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const MODES := ["Seconds", "Lives"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var pose := root.get_node_or_null("PoseService")
	_expect(pose != null, "real PoseService exists")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	_expect(not FileAccess.file_exists("res://ui/tutorial/spotlight/spotlight_overlay.tscn"),
		"deleted standalone spotlight scene stays absent")
	var authored := load(COUNTDOWN) as PackedScene
	_expect(authored != null, "shared count-in PackedScene survives")
	if authored != null:
		var panel := authored.instantiate() as Control
		_expect(panel != null and panel.get_node_or_null("CountdownNumber") is Label,
			"3-2-1 digits are editor-authored")
		_expect(panel != null and panel.get_node_or_null("CountdownTimer") is Timer,
			"3-2-1 timing is editor-authored")
		panel.free()
	var scene := load(WRAPPER) as PackedScene
	_expect(scene != null, "shared game wrapper survives")
	if scene != null:
		for activity in ACTIVITIES:
			for mode in MODES:
				await _guided_case(scene, activity, mode)
		await _normal_play_native_pause(scene)
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _guided_case(scene: PackedScene, activity: String, mode: String) -> void:
	var label := "%s / %s" % [activity, mode]
	var wrapper := scene.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({
		"activity": activity, "game_mode": mode,
		"guided_tutorial": true, "start_countdown": true,
		"camera_live": false, "keyboard_mode": false,
		"calibration_measured": false, "topic": "Noun",
		"difficulty": "Easy"
	})
	await process_frame
	await process_frame
	var game := wrapper.get_node_or_null("ActiveMiniGame") as Control
	_expect(game != null, label + ": real minigame mounted")
	if game == null:
		wrapper.queue_free()
		await process_frame
		return
	_expect(game.process_mode == Node.PROCESS_MODE_DISABLED,
		label + ": all gameplay input/timers/physics disabled before GO")
	_expect(String(wrapper.get("guided_stage")) == "countdown",
		label + ": Guided routes DIRECTLY to 3-2-1, no tutorial/Spotlight stage")
	_expect(not _has_legacy_spotlight(wrapper)
		and _count_named(wrapper, "GuidedSpotlight") == 0
		and _count_named(wrapper, "SpotlightOverlay") == 0,
		label + ": no phantom overlay node/property")
	var panel := wrapper.get("countdown_panel") as Control
	_expect(panel != null, label + ": direct scene-authored countdown mounted once")
	var digits := panel.get_node_or_null("CountdownNumber") as Label if panel != null else null
	_expect(digits != null and digits.text == "3", label + ": count-in begins at 3")
	_expect(String(game.get("game_mode")) == mode, label + ": selected mode retained")
	var hud_root := "HudLayer" if activity == "Balloon Popping" else "HUDLayer/HUD"
	var hud_path := hud_root + ("/LivesPlaque" if mode == "Lives" else "/TimerPlaque")
	var hud := game.get_node_or_null(hud_path) as CanvasItem
	_expect(hud != null and hud.is_visible_in_tree(),
		label + ": matching Seconds/Lives HUD is visible")
	var baseline := _snapshot(game)
	var original_id := game.get_instance_id()
	wrapper.call("_pause")
	_expect(String(wrapper.get("guided_stage")) == "countdown",
		label + ": Pause cannot skip the frozen countdown")
	await create_timer(0.16).timeout
	_expect(_snapshot(game) == baseline, label + ": no time, score, hearts or lives spent before GO")
	for next_digit in ["2", "1"]:
		wrapper.call("_on_countdown_tick")
		_expect(digits != null and digits.text == next_digit,
			label + ": genuine countdown advances to " + next_digit)
		_expect(game.process_mode == Node.PROCESS_MODE_DISABLED and _snapshot(game) == baseline,
			label + ": game remains frozen at " + next_digit)
	wrapper.call("_on_countdown_tick")
	_expect(game.process_mode == Node.PROCESS_MODE_INHERIT and
		wrapper.get("countdown_panel") == null and
		String(wrapper.get("guided_stage")) == "",
		label + ": GO releases original game and removes countdown")
	for i in range(3):
		wrapper.call("_on_countdown_tick")
		wrapper.call("_complete_countdown_start")
	_expect(game.get_instance_id() == original_id and _count_named(wrapper, "GuidedCountdown") == 0
		and wrapper.get("countdown_panel") == null,
		label + ": no duplicate countdown or new minigame from stale callbacks")
	wrapper.queue_free()
	await process_frame
	await process_frame


func _normal_play_native_pause(scene: PackedScene) -> void:
	# Deliberately no start_countdown: unlike measured camera sessions, a
	# non-guided wrapper is expected to preserve ordinary native pause/resume.
	var wrapper := scene.instantiate() as Control
	root.add_child(wrapper)
	wrapper.set_context({
		"activity": "Catch the Word", "game_mode": "Seconds",
		"guided_tutorial": false, "start_countdown": false,
		"camera_live": false, "topic": "Noun", "difficulty": "Easy"
	})
	await process_frame
	await process_frame
	var game := wrapper.get_node_or_null("ActiveMiniGame") as Control
	_expect(game != null and game.process_mode == Node.PROCESS_MODE_INHERIT,
		"normal Play with no count-in mounts immediately playing minigame")
	_expect(wrapper.get("countdown_panel") == null and not _has_legacy_spotlight(wrapper),
		"normal Play does not invent guided UI")
	var routes: Array[String] = []
	wrapper.requested.connect(func(route: String, _payload: Dictionary) -> void:
		routes.append(route))
	wrapper.call("_pause")
	_expect(routes.has("pause"), "normal Play still routes native Pause")
	wrapper.call("_resume")
	_expect(game != null and bool(game.get("round_running")),
		"normal Play can resume original round")
	wrapper.queue_free()
	await process_frame
	await process_frame


func _snapshot(game: Control) -> Dictionary:
	var saved := {}
	for field in ["score", "time_remaining", "lives", "hearts", "round_running", "round_completed"]:
		for property in game.get_property_list():
			if String(property.get("name", "")) == field:
				saved[field] = game.get(field)
				break
	return saved


func _has_legacy_spotlight(wrapper: Control) -> bool:
	for item in wrapper.get_property_list():
		if String(item.get("name", "")) == "spotlight_overlay":
			return true
	return false


func _count_named(root_node: Node, wanted: String) -> int:
	var total := 1 if root_node.name == wanted else 0
	for child in root_node.get_children():
		total += _count_named(child, wanted)
	return total


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("GUIDED ONBOARDING RED: ", message)


func _finish() -> void:
	print("GUIDED ONBOARDING: %s checks=%d failures=%d (3 games x 2 modes + normal Play)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
