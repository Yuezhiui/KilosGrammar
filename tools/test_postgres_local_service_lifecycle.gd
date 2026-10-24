extends SceneTree

## Validate Main Menu's real local-service lifecycle reactions without IO.
## Run: Godot --headless --path . --script res://tools/test_postgres_local_service_lifecycle.gd
const TEST_MENU_PATH := "res://tools/test_postgres_lifecycle_menu.gd"
var failures: Array[String] = []
var assertions := 0
var _app: Control
var _client: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://main_menu.tscn") as PackedScene
	_check(packed != null, "Real Main Menu scene loads")
	if packed == null:
		quit(1)
		return
	_app = packed.instantiate() as Control
	var mocked_menu := load(TEST_MENU_PATH) as Script
	_check(mocked_menu != null and mocked_menu.can_instantiate(),
		"Lifecycle subclass can load after PoseService autoload initialization")
	if mocked_menu == null or not mocked_menu.can_instantiate():
		_app.free()
		quit(1)
		return
	_app.set_script(mocked_menu)
	root.add_child(_app)
	await process_frame
	_client = _app.get("database_client") as Node
	_check(is_instance_valid(_client), "Pure in-memory mock replaces actual PostgreSQL client")
	if not is_instance_valid(_client):
		await _finish()
		return
	_check(_client.call("count", "ensure_local_service") == 1,
		"Startup calls ensure_local_service once")
	_check(_client.call("count", "health") == 0,
		"Startup does not bypass lifecycle with standalone health call")
	_check(_client.get_child_count() == 0 and int(_client.get("launch_attempts")) == 0,
		"No HTTPRequest, Timer, or Windows PowerShell subprocess exists in test mock")
	_check(not bool(_app.get("database_online")), "Initial connectivity is unconfirmed")

	await _test_pending_student_lookup()
	await _test_lookup_stale_id_guard()
	await _test_leaderboard_reconnect()
	await _finish()


func _test_pending_student_lookup() -> void:
	var play := _app.get_node("MainLayer/CenterMenu/Play") as Button
	play.pressed.emit()
	await process_frame
	_check(String(_app.get("current_route")) == "student_setup", "Real native Play opens Student Setup")
	var form := _app.get("active_panel") as Control
	if form == null:
		return
	var status := form.get("_database_status") as Label
	var status_position := status.position
	_check(_client.call("count", "ensure_local_service") == 2,
		"Opening Student Setup offline asks launcher to reconnect")
	_client.call("emit_state", "checking")
	_check(not bool(_app.get("database_online")), "Checking does not prematurely declare online")
	_check(status.text.contains("CONNECTING") and not status.text.contains("OFFLINE"),
		"Checking shows CONNECTING, not premature OFFLINE")
	_client.call("emit_probe_result", false)
	_check(not bool(_app.get("database_online")) and status.text.contains("CONNECTING"),
		"Transient health probe error does not trigger offline or overwrite status")
	_client.call("emit_state", "starting")
	_check(status.text.contains("CONNECTING"), "Starting preserves nonterminal connecting message")
	_client.call("emit_state", "retrying", "server_unreachable")
	_check(status.text.contains("CONNECTING") and not status.text.contains("OFFLINE"),
		"Retrying keeps the UI in connecting state until a terminal result")
	var field := form.get("_student_id_edit") as LineEdit
	field.text = "S-RECONNECT"
	form.call("_update_validation")
	(form.get("_lookup_button") as Button).pressed.emit()
	_check(String(_app.get("database_pending_lookup_id")) == "S-RECONNECT",
		"Offline lookup is queued by exact student ID")
	_check(_client.call("count", "find_student") == 0,
		"Offline lookup does not fetch a profile until local service is ready")
	_check(_client.call("count", "ensure_local_service") == 3,
		"Queued lookup triggers idempotent service assurance")
	_client.call("emit_state", "online")
	_check(bool(_app.get("database_online")), "Terminal online status marks database usable")
	_check(String(_app.get("database_pending_lookup_id")).is_empty(),
		"Pending lookup ID is consumed once after online signal")
	_check(_client.call("count", "find_student") == 1,
		"Online signal reloads queued student lookup exactly once")
	var pending: Dictionary = _client.call("find_pending", "find_student", "student_lookup")
	_check(pending.get("args", {}).get("student_id", "") == "S-RECONNECT",
		"Queued profile reload uses exact captured student ID")
	_check(_client.call("reply", "find_student", {"ok": true,
		"status": 200, "data": {"student": {
			"student_id": "S-RECONNECT", "student_name": "A Real Student",
			"grade_section": "5 - Orchid",
		}}}, "student_lookup"), "Matching confirmed profile reload callback is delivered")
	_check((form.get("_name_edit") as LineEdit).text == "A Real Student",
		"Recovered lookup populates teacher's native form")
	_check(status.text.contains("STUDENT FOUND"),
		"Verified profile success is visible")
	_client.call("emit_state", "checking")
	_client.call("emit_probe_result", false)
	_client.call("emit_state", "retrying", "http_health_failed")
	_check(bool(_app.get("database_online")) and status.text.contains("STUDENT FOUND"),
		"Probing while online preserves verified profile status and connectivity")
	_check(status.position == status_position,
		"Lifecycle updates preserve the editor-authored status node placement")


func _test_lookup_stale_id_guard() -> void:
	var form := _app.get("active_panel") as Control
	var field := form.get("_student_id_edit") as LineEdit
	var status := form.get("_database_status") as Label
	_client.call("emit_state", "offline", "setup_required")
	_check(not bool(_app.get("database_online")), "Terminal offline alone marks database unavailable")
	_check(status.text.contains("OFFLINE") and status.text.contains("SET UP LOCAL DATABASE")
		and (form.get("_database_recovery_button") as Button).visible,
		"Missing local configuration offers one-click secure setup on the native form")
	field.text = "S-OLD"
	field.text_changed.emit(field.text)
	form.call("_update_validation")
	(form.get("_lookup_button") as Button).pressed.emit()
	_check(String(_app.get("database_pending_lookup_id")) == "S-OLD",
		"New offline lookup queues original student ID")
	field.text = "S-NEW"
	field.text_changed.emit(field.text)
	_client.call("emit_state", "online")
	_check(_client.call("count", "find_student") == 1,
		"Changing student ID during reconnection suppresses stale profile request")
	_check(String(_app.get("database_pending_lookup_id")).is_empty(),
		"Stale queued lookup is dropped after online signal")
	_check((form.get("_name_edit") as LineEdit).text.is_empty(),
		"Stale lookup does not inject another student's name")
	_check(bool(_app.get("database_online")), "Reconnect still marks database online")
	_client.call("emit_state", "offline", "database_auth_or_schema")
	_check(status.text.contains("SET UP LOCAL DATABASE")
		and (form.get("_database_recovery_button") as Button).visible,
		"Database auth/schema offline reason offers actionable secure setup")


func _test_leaderboard_reconnect() -> void:
	_app.call("_return_to_main")
	await process_frame
	var reconnects_before: int = _client.call("count", "ensure_local_service")
	var fetch_before: int = _client.call("count", "get_leaderboard")
	(_app.get_node("MainLayer/LeftMenu/Leaderboard") as Button).pressed.emit()
	await process_frame
	_check(String(_app.get("current_route")) == "leaderboard", "Native leaderboard button opens its scene")
	var board := _app.get("active_panel") as Control
	var empty := board.get_node("%EmptyMessage") as Label
	var scores := board.get_node("%ScoreRows") as VBoxContainer
	var empty_position := empty.position
	_check(_client.call("count", "get_leaderboard") == fetch_before and scores.get_child_count() == 0,
		"Offline leaderboard does not issue a read or synthesize any ranking")
	_check(_client.call("count", "ensure_local_service") == reconnects_before + 1,
		"Opening offline leaderboard invokes ensure_local_service exactly once")
	_check(empty.text.contains("Loading"), "Leaderboard shows loading during reconnect retries")
	_client.call("emit_state", "checking")
	_client.call("emit_probe_result", false)
	_client.call("emit_state", "retrying")
	_check(empty.text.contains("Loading") and scores.get_child_count() == 0,
		"Nonterminal probes keep leaderboard loading and without fake scores")
	_client.call("emit_state", "online")
	_check(_client.call("count", "get_leaderboard") == fetch_before + 1,
		"Online lifecycle event reloads the leaderboard once")
	_check(_client.call("reply", "get_leaderboard", {
		"ok": true, "status": 200, "data": {"leaderboard": [{
			"student_id": "S-RECONNECT", "student_name": "A Real Student",
			"grade_section": "5 - Orchid", "game_style": "Noun",
			"game_mode": "Seconds", "difficulty": "Easy", "score": 77,
		}]},
	}, "leaderboard"), "Leaderboard receives one real-data response")
	_check(scores.get_child_count() == 1
		and (scores.get_child(0).get_node("Score") as Label).text == "77",
		"Reconnected leaderboard shows only server-provided score")
	_client.call("emit_state", "checking")
	_client.call("emit_probe_result", false)
	_client.call("emit_state", "retrying")
	_check(scores.get_child_count() == 1 and bool(_app.get("database_online")),
		"Transient retries while online preserve existing scores")
	_client.call("emit_state", "offline", "server_unreachable")
	_check(scores.get_child_count() == 0 and empty.text.contains("database unavailable"),
		"Final offline transition removes stale leaderboard rows and displays offline state")
	_check(empty.position == empty_position,
		"Async status preserves authored leaderboard node geometry")
	fetch_before = _client.call("count", "get_leaderboard")
	_client.call("emit_state", "online")
	_check(_client.call("count", "get_leaderboard") == fetch_before + 1,
		"Recovery from offline reloads leaderboard again")
	_check(_client.call("reply", "get_leaderboard", {
		"ok": true, "status": 200, "data": {"leaderboard": []},
	}, "leaderboard"), "Empty database rankings can recover cleanly")
	_check(scores.get_child_count() == 0 and empty.text.contains("No completed scores"),
		"Empty recovered leaderboard reports no saved completed scores")
	_check(int(_client.get("launch_attempts")) == 0 and _client.get_child_count() == 0,
		"Lifecycle regression did not spawn subprocesses or network request objects")


func _check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		printerr("FAIL local service lifecycle: ", label)


func _finish() -> void:
	if is_instance_valid(_app):
		_app.call("_return_to_main")
		_app.queue_free()
		await process_frame
		await process_frame
	print("POSTGRES LOCAL SERVICE LIFECYCLE: ",
		"PASS" if failures.is_empty() else "FAIL",
		" (%d assertions, %d failures)" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)
