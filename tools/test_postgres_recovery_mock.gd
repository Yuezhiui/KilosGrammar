extends "res://tools/test_postgres_mock_client.gd"

## A deterministic *logical* watcher. There is no server, socket, PowerShell
## invocation, timer, or real Postgres connection. Tests trigger each heartbeat.
signal local_service_status_changed(state: String, details: Dictionary)

var service_available := false
var watch_active := false
var ensure_calls := 0
var heartbeat_count := 0
var launch_attempts := 0
var _active_request_id := -1


func ensure_local_service(context: Dictionary = {}) -> int:
	ensure_calls += 1
	if watch_active:
		return _active_request_id
	watch_active = true
	_active_request_id = _record("ensure_local_service", {}, context)
	local_service_status_changed.emit("checking", {"reason": "", "attempt": 1})
	return _active_request_id


func heartbeat() -> void:
	## Simulate the watcher's repeated /health check. True means a fake server
	## has returned with a database-connected health response.
	heartbeat_count += 1
	if not watch_active:
		return
	if service_available:
		watch_active = false
		local_service_status_changed.emit("online", {"reason": "", "attempt": heartbeat_count})
	else:
		local_service_status_changed.emit("retrying", {"reason": "server_unreachable", "attempt": heartbeat_count})


func finish_offline(reason: String, additional_details: Dictionary = {}) -> void:
	watch_active = false
	var details := {"reason": reason, "attempt": heartbeat_count}
	for key in additional_details:
		details[key] = additional_details[key]
	local_service_status_changed.emit("offline", details)


func lose_service() -> void:
	service_available = false
	finish_offline("server_unreachable")


func restore_service() -> void:
	service_available = true


func probe(healthy: bool) -> void:
	## Internal health results must not flip UI before the watcher settles.
	request_finished.emit(
		{"operation": "health", "purpose": "reconnect",
			"local_service_probe": true, "request_id": -2},
		{"ok": healthy, "status": 200 if healthy else 503,
			"data": {"database": "connected"} if healthy else null,
			"request_id": -2, "error": "" if healthy else "database_unavailable"}
	)


func reply_oldest(operation: String, response: Dictionary, purpose: String = "") -> bool:
	## Force out-of-order completion: choose the earliest unanswered request.
	for request in requests:
		var info: Dictionary = request["context"]
		if request["responded"] or String(info.get("operation", "")) != operation:
			continue
		if not purpose.is_empty() and String(info.get("purpose", "")) != purpose:
			continue
		request["responded"] = true
		var result := {
			"request_id": info["request_id"], "ok": false,
			"data": null, "error": "", "status": 0, "message": "",
		}
		for key in response:
			result[key] = response[key]
		request_finished.emit(info.duplicate(true), result)
		return true
	return false
