extends SceneTree

## Headless, credential-free HTTP transport integration test. Runs an isolated
## loopback mock; never opens or modifies the real PostgreSQL database.

const CLIENT := preload("res://ui/database/postgres_client.gd")
const STARTUP_FAKE_CLIENT := preload("res://ui/database/test_postgres_client_fake.gd")

var failures := 0
var _server := TCPServer.new()
var _peers: Array[Dictionary] = []
var _captured: Array[Dictionary] = []
var _replies: Dictionary = {}
var _old_port := ""
var _health_unavailable := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_old_port = OS.get_environment("KILOSGRAMMAR_DB_PORT")
	OS.set_environment("KILOSGRAMMAR_DB_PORT", "")
	var client := CLIENT.new()
	_check(client._origin() == "http://127.0.0.1:18765",
		"Default service origin is localhost:18765 when no port override is set")
	var port := 45670
	while port < 45690 and _server.listen(port, "127.0.0.1") != OK:
		port += 1
	_check(_server.is_listening(), "Loopback-only mock HTTP server starts")
	if not _server.is_listening():
		quit(1)
		return
	OS.set_environment("KILOSGRAMMAR_DB_PORT", str(port))
	_check(client._origin() == "http://127.0.0.1:%d" % port,
		"KILOSGRAMMAR_DB_PORT overrides the default service port")
	process_frame.connect(_serve)
	root.add_child(client)
	client.request_finished.connect(func(context: Dictionary, result: Dictionary) -> void:
		_replies[context["request_id"]] = {"context": context, "result": result}
	)

	var ids := {
		"health": client.health({"tag": "ping"}),
		"student": client.find_student("A&B/2", {"tag": "lookup"}),
		"register": client.register_student("A&B/2", "Jane Doe", "4-Orchid"),
		"update": client.update_student("A&B/2", "Jane Doe", "5-Orchid"),
		"score": client.find_score("A&B/2", "Noun", "Seconds", "Easy"),
		"complete": client.complete_round("A&B/2", "Noun", "Seconds", "Easy", 10),
			"complete_plane": client.complete_round("A&B/2", "Noun", "Seconds", "Easy", 123, {"minigame": "Human Plane"}),
			"complete_catch": client.complete_round("A&B/2", "Noun", "Seconds", "Easy", 97, {"minigame": "Catch the Word"}),
		"leaderboard": client.get_leaderboard(),
		"filtered": client.get_leaderboard("Noun", "Seconds", "Easy", "4-Orchid"),
			"filtered_game": client.get_leaderboard("Noun", "Seconds", "Easy", "", {"minigame": "Human Plane"}),
		"missing": client.find_student("missing"),
		"invalid": client.register_student("", "Jane", "4-Orchid"),
	}
	var cancelled_id: int = client.health({"tag": "cancel-test"})
	client.cancel_request(cancelled_id)

	var deadline := Time.get_ticks_msec() + 5000
	while _replies.size() < ids.size() + 1 and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(_replies.size() == ids.size() + 1, "All parallel responses and cancellation finish without ERR_BUSY")
	for key in ids:
		var request_id: int = ids[key]
		_check(_replies.has(request_id), "Response delivered for " + key)
		if not _replies.has(request_id):
			continue
		var item: Dictionary = _replies[request_id]
		var context: Dictionary = item["context"]
		var result: Dictionary = item["result"]
		_check(int(context["request_id"]) == request_id and int(result["request_id"]) == request_id,
			"Request id correlates result for " + key)
		_check(context.has("operation"), "Operation context delivered for " + key)
		if key in ["invalid", "missing"]:
			_check(not bool(result["ok"]), "Expected failure is explicit for " + key)
		else:
			_check(bool(result["ok"]), "Server success is decoded for " + key)
	_check(_replies.has(cancelled_id) and _replies[cancelled_id]["result"]["error"] == "cancelled",
		"Cancel reports cancellation without late success")
	_check(_replies[ids["health"]]["context"].get("tag", "") == "ping", "Caller context is returned unchanged")
	_check(_replies[ids["missing"]]["result"].get("error", "") == "not_found",
		"Structured HTTP error code and message are decoded")
	_check(_replies[ids["score"]]["result"].get("data", {}).has("score"), "Nullable score payload stays nested")
	_check(_replies[ids["leaderboard"]]["result"].get("data", {}).has("leaderboard"),
		"Leaderboard list payload is parsed")

	var capture_by_operation := {}
	var all_completed: Array[Dictionary] = []
	var game_leaderboard_found := false
	for capture in _captured:
		var method: String = capture["method"]
		var route: String = capture["route"]
		if method == "PATCH":
			capture_by_operation["update"] = capture
		if method == "POST" and route == "/rounds/complete":
			capture_by_operation["complete"] = capture
			all_completed.append(capture)
		if route.begins_with("/leaderboard?") and route.contains("minigame=Human%20Plane"):
			game_leaderboard_found = true
		if route == "/leaderboard":
			capture_by_operation["leaderboard"] = capture
		if route.begins_with("/students/A%26B%2F2"):
			capture_by_operation["student"] = capture
	_check(capture_by_operation.has("update"), "Student update uses PATCH")
	_check(capture_by_operation.has("student"), "Student ID path segments are URL encoded")
	_check(capture_by_operation.has("leaderboard"), "All-styles leaderboard calls /leaderboard without query")
	var actual_game_scores: Dictionary = {}
	for request in all_completed:
		actual_game_scores[String(request["json"].get("minigame", ""))] = int(request["json"].get("score", -1))
	_check(actual_game_scores.get("Legacy", -1) == 10, "Old score client calls keep explicit Legacy score identity")
	_check(actual_game_scores.get("Human Plane", -1) == 123 and actual_game_scores.get("Catch the Word", -1) == 97,
		"Completed scores carry distinct Human Plane and Catch the Word minigame identities")
	_check(game_leaderboard_found, "Leaderboard minigame filter is correctly encoded into local API URL")
	_check(_captured.size() >= ids.size() - 1 and _captured.size() <= ids.size(),
		"Validation sends no HTTP request; cancellation may race with wire send")

	# Healthy API: no startup process must ever be launched.
	var ready_client := STARTUP_FAKE_CLIENT.new()
	ready_client.enable_local_service_launcher = false
	ready_client.allow_fake_launch = true
	root.add_child(ready_client)
	var ready_events: Array[Dictionary] = []
	ready_client.local_service_status_changed.connect(func(state: String, details: Dictionary) -> void:
		ready_events.append({"state": state, "details": details})
	)
	var first_id: int = ready_client.ensure_local_service({"purpose": "startup"})
	_check(ready_client.ensure_local_service({"purpose": "duplicate"}) == first_id,
		"Repeated startup request returns same in-progress request ID")
	_check(await _wait_for_state(ready_events, "online", 2.0),
		"Connected health check reaches online state without spawning process")
	_check(ready_client.launch_calls == 0, "Working service must never launch another backend")
	ready_client.queue_free()
	await process_frame

	# Simulate no listener, then the server appearing during nonblocking retries.
	# Fake process counts launch attempts and never starts a real PowerShell.
	_server.stop()
	var unconfigured := STARTUP_FAKE_CLIENT.new()
	unconfigured.enable_local_service_launcher = false
	unconfigured.allow_fake_launch = true
	unconfigured.have_fake_credentials = false
	root.add_child(unconfigured)
	var setup_events: Array[Dictionary] = []
	unconfigured.local_service_status_changed.connect(func(state: String, details: Dictionary) -> void:
		setup_events.append({"state": state, "details": details})
	)
	unconfigured.ensure_local_service()
	_check(await _wait_for_state(setup_events, "offline", 2.0), "Missing credentials conclude startup")
	_check(String(setup_events.back()["details"].get("reason", "")) == "setup_required",
		"Missing DPAPI credentials report setup_required")
	_check(unconfigured.launch_calls == 0, "Missing credentials never run hidden startup script")
	unconfigured.queue_free()
	await process_frame

	# Repeated launch requests within one attempt reuse the first probe, and
	# recovery after service startup needs only one fake process invocation.
	var recovering := STARTUP_FAKE_CLIENT.new()
	recovering.enable_local_service_launcher = false
	recovering.allow_fake_launch = true
	recovering.startup_timeout_seconds = 4.0
	root.add_child(recovering)
	var recovering_events: Array[Dictionary] = []
	recovering.local_service_status_changed.connect(func(state: String, details: Dictionary) -> void:
		recovering_events.append({"state": state, "details": details})
	)
	recovering.ensure_local_service({"purpose": "startup"})
	var online_deadline := Time.get_ticks_msec() + 5500
	var reopen_at := -1
	while not _has_state(recovering_events, "online") and Time.get_ticks_msec() < online_deadline:
		if recovering.launch_calls > 0 and reopen_at == -1:
			reopen_at = Time.get_ticks_msec() + 350
		if reopen_at > 0 and Time.get_ticks_msec() >= reopen_at and not _server.is_listening():
			_check(_server.listen(port, "127.0.0.1") == OK, "Mock service can return after launch")
		await process_frame
	if recovering.launch_calls != 1 or not _has_state(recovering_events, "online"):
		print("DEBUG startup phases: ", recovering_events, " launches=", recovering.launch_calls)
	_check(_has_state(recovering_events, "online"), "Health retries detect service after delayed startup")
	_check(recovering.launch_calls == 1, "Disconnected startup calls launcher exactly once")
	_check(_has_state(recovering_events, "starting") and _has_state(recovering_events, "retrying"),
		"Startup states expose launch and retry progression")
	recovering.queue_free()
	await process_frame

	# Reachable HTTP 503 means PostgreSQL cannot authenticate or schema is
	# missing; launching another web server would create a port collision.
	_health_unavailable = true
	var unavailable := STARTUP_FAKE_CLIENT.new()
	unavailable.enable_local_service_launcher = false
	unavailable.allow_fake_launch = true
	unavailable.startup_timeout_seconds = 0.75
	root.add_child(unavailable)
	var offline_events: Array[Dictionary] = []
	unavailable.local_service_status_changed.connect(func(state: String, details: Dictionary) -> void:
		offline_events.append({"state": state, "details": details})
	)
	unavailable.ensure_local_service()
	_check(await _wait_for_state(offline_events, "offline", 2.0), "503 health probe reports offline")
	_check(unavailable.launch_calls == 0, "HTTP listener reporting PostgreSQL 503 never launches another listener")
	_check(String(offline_events.back()["details"].get("reason", "")) == "database_auth_or_schema",
		"Offline state explains local PostgreSQL credentials/schema issue")
	unavailable.queue_free()
	_health_unavailable = false
	await process_frame
	var headless_client := CLIENT.new()
	headless_client.enable_local_service_launcher = true
	_check(not headless_client._can_launch_local_service(), "Real launcher is suppressed under Godot headless")
	headless_client.free()

	client.queue_free()
	await process_frame
	process_frame.disconnect(_serve)
	_server.stop()
	OS.set_environment("KILOSGRAMMAR_DB_PORT", _old_port)
	print("POSTGRES CLIENT: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)


func _serve() -> void:
	while _server.is_connection_available():
		_peers.append({"connection": _server.take_connection(), "buffer": "", "done": false, "ticks": 0})
	for connection in _peers:
		var peer: StreamPeerTCP = connection["connection"]
		if connection["done"]:
			connection["ticks"] += 1
			if connection["ticks"] > 3:
				peer.disconnect_from_host()
			continue
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var available := peer.get_available_bytes()
		if available > 0:
			var read_result := peer.get_data(available)
			if read_result[0] != OK:
				continue
			connection["buffer"] += (read_result[1] as PackedByteArray).get_string_from_utf8()
		var contents: String = connection["buffer"]
		var header_end := contents.find("\r\n\r\n")
		if header_end < 0:
			continue
		var header := contents.substr(0, header_end)
		var content_length := 0
		for entry in header.split("\r\n"):
			if entry.to_lower().begins_with("content-length:"):
				content_length = entry.get_slice(":", 1).strip_edges().to_int()
		if contents.length() < header_end + 4 + content_length:
			continue
		var first_line := header.get_slice("\r\n", 0)
		var method := first_line.get_slice(" ", 0)
		var route := first_line.get_slice(" ", 1)
		var body := contents.substr(header_end + 4, content_length)
		var json_body: Variant = JSON.parse_string(body) if not body.is_empty() else {}
		if not json_body is Dictionary:
			json_body = {}
		_captured.append({"method": method, "route": route, "json": json_body})
		var status := 200
		var reply := {"ok": true, "data": {"score": null}, "error": null}
		if route == "/health":
			if _health_unavailable:
				status = 503
				reply = {"ok": false, "data": null, "error": {"code": "database_unavailable", "message": "Local PostgreSQL unavailable"}}
			else:
				reply["data"] = {"status": "ok", "database": "connected"}
		elif route == "/students/missing":
			status = 404
			reply = {"ok": false, "data": null, "error": {"code": "not_found", "message": "Student not found"}}
		elif route.begins_with("/students/") or route == "/students":
			reply["data"] = {"student": {"student_id": "A&B/2"}}
			if method == "POST":
				status = 201
		elif route.begins_with("/leaderboard"):
			reply["data"] = {"leaderboard": [], "count": 0}
		elif route == "/rounds/complete":
			reply["data"] = {"score": json_body}
		var reply_body := JSON.stringify(reply)
		var response := "HTTP/1.1 %d Test\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [status, reply_body.to_utf8_buffer().size(), reply_body]
		peer.put_data(response.to_utf8_buffer())
		connection["done"] = true
	for index in range(_peers.size() - 1, -1, -1):
		if _peers[index]["done"] and _peers[index]["ticks"] > 3:
			_peers.remove_at(index)


func _check(condition: bool, explanation: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL postgres client: ", explanation)


func _has_state(events: Array[Dictionary], wanted: String) -> bool:
	for event in events:
		if String(event.get("state", "")) == wanted:
			return true
	return false


func _wait_for_state(events: Array[Dictionary], wanted: String, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not _has_state(events, wanted) and Time.get_ticks_msec() < deadline:
		await process_frame
	return _has_state(events, wanted)
