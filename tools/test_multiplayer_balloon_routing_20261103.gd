extends SceneTree
## No-camera, no-database smoke test for the existing Multiplayer activity chooser.
const ACTIVITY := preload("res://ui/play/activity/play_activity.tscn")
const RESULTS := preload("res://ui/secondary/results/results.tscn")
const STUDENT_SETUP := preload("res://ui/student/setup/student_setup.tscn")


class FakeResults:
	extends Control
	var last_context: Dictionary = {}
	func set_context(value: Dictionary) -> void:
		last_context = value.duplicate(true)

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("MULTIPLAYER BALLOON ROUTE FAILED: ", description)


func _run() -> void:
	var setup := STUDENT_SETUP.instantiate() as Control
	root.add_child(setup)
	setup.set_context({"entry_source":"play"})
	await process_frame
	var setup_routes: Array[Dictionary] = []
	setup.connect("requested", func(route: String, payload: Dictionary) -> void:
		setup_routes.append({"route": route, "payload": payload.duplicate(true)}))
	for entry in [
		["_student_id_edit", "TEST-P1"], ["_name_edit", "Demo Player One"],
		["_grade_edit", "Grade 4-A"]]:
		var field: LineEdit = setup.get(String(entry[0])) as LineEdit
		field.text = String(entry[1])
		field.text_changed.emit(field.text)
	setup.call("_continue")
	setup.call("_select_style", "Noun")
	setup.call("_select_mode", "Seconds")
	setup.call("_select_difficulty", "Normal")
	setup.call("_select_player_mode", "Multiplayer")
	for entry in [
		["_player_two_id_edit", "TEST-P2"],
		["_player_two_name_edit", "Demo Player Two"],
		["_player_two_grade_edit", "Grade 4-B"]]:
		var field: LineEdit = setup.get(String(entry[0])) as LineEdit
		field.text = String(entry[1])
		field.text_changed.emit(field.text)
	setup.call("_close_player_two_form")
	setup.call("_continue")
	_check(setup_routes.size() == 1 and String(setup_routes[0].get("route", "")) == "play_activity",
		"fresh Multiplayer setup without a selected game opens activity chooser")
	if setup_routes.size() == 1:
		_check(String((setup_routes[0]["payload"] as Dictionary).get("activity", "")) == "",
			"setup never silently defaults Multiplayer to Catch")
	setup.queue_free()
	await process_frame

	var chooser := ACTIVITY.instantiate() as Control
	root.add_child(chooser)
	await process_frame
	chooser.call("set_context", {
		"player_mode": "Multiplayer", "student_id": "TEST-P1",
		"player2_student_id": "TEST-P2", "game_style": "Noun",
		"game_mode": "Seconds", "difficulty": "Normal"})
	var chosen: Array[Dictionary] = []
	chooser.connect("requested", func(route: String, payload: Dictionary) -> void:
		chosen.append({"route": route, "payload": payload.duplicate(true)}))
	var blocked_button := chooser.get_node("LayoutMargins/Content/GameRow/GameOptions/GameOptionsContent/HumanPlaneButton") as Button
	_check(blocked_button.disabled, "Human Plane not offered as multiplayer")
	chooser.call("_select_activity", "Human Plane")
	_check(String(chooser.get("context").get("activity", "")) != "Human Plane",
		"programmatic Human Plane selection also rejected")
	chooser.call("_select_activity", "Balloon Popping")
	_check(String(chooser.get("context").get("activity", "")) == "Balloon Popping",
		"existing chooser selects Balloon Popping")
	chooser.call("_go_next")
	_check(chosen.size() == 1, "one request from Next")
	if chosen.size() == 1:
		_check(String(chosen[0]["route"]) == "calibration", "uses existing calibration route")
		var payload: Dictionary = chosen[0]["payload"]
		_check(String(payload.get("player_mode", "")) == "Multiplayer",
			"multiplayer selection retained")
		_check(String(payload.get("activity", "")) == "Balloon Popping",
			"Balloon selection retained, not overwritten with Catch")
		_check(String(payload.get("player2_student_id", "")) == "TEST-P2",
			"second student's entered identity retained")
	chooser.queue_free()
	await process_frame

	var results := RESULTS.instantiate() as Control
	root.add_child(results)
	await process_frame
	results.call("set_context", {
		"activity": "Balloon Popping", "player_mode": "Multiplayer",
		"student_name": "P1", "player2_student_name": "P2",
		"score": 200, "player1_score": 200, "player2_score": 300,
		"lives": 3, "player2_lives": 2,
		"round_completed": true, "game_mode": "Seconds",
		"multiplayer_solo_test": true, "test_only": true})
	_check((results.get_node("%MultiplayerResults") as Control).visible,
		"Balloon multiplayer has same independent two-score Results board")
	_check((results.get_node("%PlayerOneScore") as Label).text == "200"
			and (results.get_node("%PlayerTwoScore") as Label).text == "300",
		"Balloon results show independent scores instead of only P1")
	var notice := results.get_node_or_null("%CompetitiveSaveNotice") as Label
	if notice != null:
		_check(notice.text.contains("NOT SAVED"), "one-person rehearsal clearly not saved")
	else:
		_check(false, "test-only Results notice exists")
	results.queue_free()
	await process_frame
	# The sole tester is not Player Two's registered human. Verify the
	# production MainMenu save path returns BEFORE any durable recovery/API
	# writes. Check source ordering first, so a future regression cannot make
	# this no-DB test accidentally exercise a real user recovery journal.
	var router_source := FileAccess.get_file_as_string("res://ui/main_menu/main_menu.gd")
	var early_test_guard := router_source.find('if bool(state.get("multiplayer_solo_test", false)):')
	var first_recovery_write := router_source.find('RECOVERY_JOURNAL.find_pending_profile',
		router_source.find("func _save_completed_round"))
	var safe_guard := early_test_guard >= 0 and first_recovery_write > early_test_guard
	_check(safe_guard, "test-only save guard precedes real recovery journal access")
	if safe_guard:
		var menu_script := load("res://ui/main_menu/main_menu.gd") as Script
		var menu := menu_script.new() as Control
		var fake := FakeResults.new()
		menu.current_route = "results"
		menu.active_panel = fake
		menu.session_state = {"activity":"Balloon Popping", "player_mode":"Multiplayer",
			"multiplayer_solo_test":true, "round_completed":true,
			"game_mode":"Seconds", "time_remaining":0.0,
			"completion_reason":"time_up", "score":100, "player2_score":200,
			"student_id":"TEST-P1", "player2_student_id":"TEST-P2"}
		menu.call("_save_completed_round")
		_check(bool(fake.last_context.get("test_only", false))
			and not bool(fake.last_context.get("score_saved", false)),
			"completed one-person multiplayer rehearsal never writes student scores")
		_check(not menu.session_state.has("recovery_event_id"),
			"rehearsal returns without generating durable recovery event")
		menu.free()
		fake.free()
	print("MULTIPLAYER BALLOON ROUTE: %s checks=%d failures=%d backend_io=none" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
