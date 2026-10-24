extends SceneTree

## In-process localhost HTTP mock and fake launcher. No PostgreSQL connection,
## DPAPI secrets or external Windows process is ever used.

const FAKE_CLIENT := preload("res://ui/database/test_postgres_client_fake.gd")

var failures := 0
var _server := TCPServer.new()
var _connections: Array[Dictionary] = []
var _old_port := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_old_port = OS.get_environment("KILOSGRAMMAR_DB_PORT")
	var port := 45710
	while port < 45730 and _server.listen(port, "127.0.0.1") != OK:
		port += 1
	if not _server.is_listening():
		printerr("Cannot start localhost test HTTP server")
		quit(1)
		return
	OS.set_environment("KILOSGRAMMAR_DB_PORT", str(port))
	process_frame.connect(_serve)

	var client := FAKE_CLIENT.new()
	client.allow_fake_launch = true
	client.enable_local_service_launcher = false
	client.enable_local_service_watchdog = true
	client.watchdog_online_interval_seconds = 1.0
	client.watchdog_offline_min_seconds = 1.0
	client.watchdog_offline_max_seconds = 3.0
	client.startup_timeout_seconds = 2.8
	root.add_child(client)
	var events: Array[Dictionary] = []
	var heartbeats := [0]
	client.local_service_status_changed.connect(func(state: String, details: Dictionary) -> void:
		events.append({"state": state, "details": details})
	)
	client.request_finished.connect(func(context: Dictionary, _result: Dictionary) -> void:
		if bool(context.get("local_service_watchdog", false)):
			heartbeats[0] += 1
			_check(context.get("operation", "") == "health" and bool(context.get("local_service_probe", false)),
				"Watchdog retains health request_finished context contract")
	)
	client.ensure_local_service({"purpose": "startup"})
	_check(await _wait_for_state_count(events, "online", 1, 2.0), "Initial local service health is online")
	_check(client.launch_calls == 0, "Watchdog never starts a second listener while healthy")

	# The service disappears after already becoming online. A single heartbeat
	# detects loss and initiates recovery; fake launcher records only the request.
	_server.stop()
	_check(await _wait_for_launch_count(client, 1, 5.0), "Runtime outage invokes automatic recovery")
	_check(_count_state(events, "offline") >= 1, "Runtime failure emits an offline status")
	_check(heartbeats[0] >= 1, "Watchdog sent an asynchronous health probe")
	_check(_server.listen(port, "127.0.0.1") == OK, "Mock API can return after outage")
	_check(await _wait_for_state_count(events, "online", 2, 4.0), "Client detects API recovery without user action")
	_check(client.launch_calls == 1, "One outage starts at most one process")

	# Immediate second outage must respect cross-cycle launch cooldown, even
	# though the first cycle succeeded and the watchdog has re-armed.
	_server.stop()
	_check(await _wait_for_state_count(events, "offline", 2, 4.0), "Second API loss detected")
	await create_timer(1.1).timeout
	_check(client.launch_calls == 1, "Repeated outages cannot trigger rapid process storms")
	client.queue_free()
	await process_frame

	# The game starts without credentials. Its watchdog should check for new
	# configuration while idle and restart automatically once config appears.
	var setup_client := FAKE_CLIENT.new()
	setup_client.allow_fake_launch = true
	setup_client.enable_local_service_launcher = false
	setup_client.enable_local_service_watchdog = true
	setup_client.have_fake_credentials = false
	setup_client.watchdog_offline_min_seconds = 1.0
	setup_client.watchdog_offline_max_seconds = 3.0
	setup_client.startup_timeout_seconds = 3.0
	root.add_child(setup_client)
	var setup_events: Array[Dictionary] = []
	setup_client.local_service_status_changed.connect(func(state: String, details: Dictionary) -> void:
		setup_events.append({"state": state, "details": details})
	)
	setup_client.ensure_local_service()
	_check(await _wait_for_state_count(setup_events, "offline", 1, 2.5), "Missing credentials reported offline")
	_check(String(setup_events.back()["details"].get("reason", "")) == "setup_required",
		"No credential status specifically reports setup_required")
	await create_timer(2.1).timeout
	_check(setup_client.launch_calls == 0, "Watchdog never invokes launcher without credentials")
	setup_client.have_fake_credentials = true
	_check(await _wait_for_launch_count(setup_client, 1, 4.0), "New credentials detected without restarting game")
	_check(_server.listen(port, "127.0.0.1") == OK, "API can come online after local setup")
	_check(await _wait_for_state_count(setup_events, "online", 1, 4.0), "New credentials allow automatic recovery")
	setup_client.queue_free()
	await process_frame

	process_frame.disconnect(_serve)
	_server.stop()
	OS.set_environment("KILOSGRAMMAR_DB_PORT", _old_port)
	print("POSTGRES WATCHDOG: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)


func _serve() -> void:
	while _server.is_connection_available():
		_connections.append({"peer": _server.take_connection(), "buffer": "", "responded": false})
	for connection in _connections:
		if bool(connection["responded"]):
			continue
		var peer := connection["peer"] as StreamPeerTCP
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var amount := peer.get_available_bytes()
		if amount > 0:
			var chunk := peer.get_data(amount)
			if int(chunk[0]) == OK:
				connection["buffer"] += (chunk[1] as PackedByteArray).get_string_from_utf8()
		if String(connection["buffer"]).find("\r\n\r\n") < 0:
			continue
		var body := JSON.stringify({"ok": true, "data": {"status": "ok", "database": "connected"}, "error": null})
		var response := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [body.to_utf8_buffer().size(), body]
		peer.put_data(response.to_utf8_buffer())
		connection["responded"] = true
	for idx in range(_connections.size() - 1, -1, -1):
		if bool(_connections[idx]["responded"]):
			var peer := _connections[idx]["peer"] as StreamPeerTCP
			peer.disconnect_from_host()
			_connections.remove_at(idx)


func _count_state(events: Array[Dictionary], expected: String) -> int:
	var count := 0
	for item in events:
		if String(item.get("state", "")) == expected:
			count += 1
	return count


func _wait_for_state_count(events: Array[Dictionary], expected: String, count: int, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while _count_state(events, expected) < count and Time.get_ticks_msec() < deadline:
		await process_frame
	return _count_state(events, expected) >= count


func _wait_for_launch_count(client: Node, count: int, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while int(client.get("launch_calls")) < count and Time.get_ticks_msec() < deadline:
		await process_frame
	return int(client.get("launch_calls")) >= count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL postgres watchdog: ", message)
