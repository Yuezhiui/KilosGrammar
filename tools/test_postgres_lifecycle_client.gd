extends "res://tools/test_postgres_mock_client.gd"

## In-memory lifecycle mock. No real local service, socket, or child process.
signal local_service_status_changed(state: String, details: Dictionary)

var launch_attempts := 0


func ensure_local_service(context: Dictionary = {}) -> int:
	return _record("ensure_local_service", {}, context)


func emit_state(state: String, reason: String = "") -> void:
	local_service_status_changed.emit(state, {"reason": reason})


func emit_probe_result(healthy: bool) -> void:
	## Probe results should never be interpreted as terminal states by Main.
	request_finished.emit(
		{"operation": "health", "purpose": "startup", "local_service_probe": true},
		{"ok": healthy, "data": {"database": "connected"} if healthy else null,
			"status": 200 if healthy else 503, "error": "" if healthy else "database_unavailable"}
	)
