extends SceneTree

# No network, PostgreSQL, CSV, Windows service launch, or user-file writes.
# Observe how the real Godot client validates and decodes manual student calls.
const CLIENT := preload("res://ui/database/postgres_client.gd")


class CaptureClient:
	extends "res://ui/database/postgres_client.gd"
	var sent: Array[Dictionary] = []

	func _send(operation: String, method: int, route: String, payload: Dictionary,
			context: Dictionary) -> int:
		sent.append({"operation": operation, "method": method, "route": route,
			"payload": payload.duplicate(true), "context": context.duplicate(true)})
		return _take_id()


var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var client := CaptureClient.new()
	client.enable_local_service_launcher = false
	client.enable_local_service_watchdog = false
	root.add_child(client)
	var results: Array[Dictionary] = []
	client.request_finished.connect(func(info: Dictionary, result: Dictionary) -> void:
		results.append({"context": info, "result": result}))

	var id := "MANUAL-001"
	client.find_student(id)
	client.register_student(id, "Ada Rivera", "Grade 4")
	client.update_student(id, "Ada Rivera", "Grade 5")
	_check(client.sent.size() == 3, "manual GET, POST and PATCH are distinct client requests")
	_check(client.sent[0]["route"] == "/students/MANUAL-001"
		and client.sent[0]["method"] == HTTPClient.METHOD_GET,
		"GET /students/{id} is a read-only lookup")
	_check(client.sent[1]["route"] == "/students"
		and client.sent[1]["method"] == HTTPClient.METHOD_POST
		and client.sent[1]["payload"] == {"student_id": id,
			"student_name": "Ada Rivera", "grade_section": "Grade 4"},
		"POST /students carries all manual identity fields without CSV")
	_check(client.sent[2]["method"] == HTTPClient.METHOD_PATCH
		and client.sent[2]["payload"].get("grade_section", "") == "Grade 5",
		"PATCH changes profile explicitly, not during registration")

	# Known mismatch: _valid_text admits punctuation and length 65-128, while
	# server.student_id_field permits only 1-64 [A-Za-z0-9._-].
	for bad_id in ["A&B/2", "manual id", "Student@Home", "X".repeat(65)]:
		var before := client.sent.size()
		client.find_student(bad_id)
		client.register_student(bad_id, "Ada Rivera", "Grade 4")
		_check(client.sent.size() == before + 2,
			"CURRENT MISMATCH: client sends server-invalid ID " + bad_id.left(16))
	_check(client.sent[3]["route"] == "/students/A%26B%2F2",
		"Godot URI-encodes an invalid server ID rather than validating its alphabet")

	var before_long_name := client.sent.size()
	client.register_student("MANUAL-002", "N".repeat(175), "Grade 4")
	_check(client.sent.size() == before_long_name + 1,
		"CURRENT MISMATCH: client sends name length 175; server maximum is 150")

	var before_name := client.sent.size()
	var rejected_id := client.find_student_by_name("Ada")
	await process_frame
	_check(client.sent.size() == before_name,
		"CURRENT MISMATCH: client refuses one-word name although backend accepts it")
	_check(results.size() == 1 and results[0]["result"]["error"] == "invalid_full_name"
		and int(results[0]["result"]["request_id"]) == rejected_id,
		"one-word by-name lookup is an asynchronous invalid_full_name, not a 404")

	client.find_student_by_name("Ada Rivera")
	_check(client.sent.back()["operation"] == "find_student_by_name"
		and client.sent.back()["route"] == "/students/by-name?name=Ada%20Rivera",
		"valid full-name lookup uses encoded query")

	# Deterministic HTTP decoding: inject completed mock responses into a
	# throwaway client, never bind to 18765 or any TCP port.
	var decoder := CLIENT.new()
	decoder.enable_local_service_launcher = false
	decoder.enable_local_service_watchdog = false
	root.add_child(decoder)
	var decoded: Array[Dictionary] = []
	decoder.request_finished.connect(func(info: Dictionary, result: Dictionary) -> void:
		decoded.append({"context": info, "result": result}))
	_simulate(decoder, 100, 404, {"ok": false, "data": null,
		"error": {"code": "student_not_found", "message": "No student registered with this ID"}})
	_simulate(decoder, 101, 400, {"ok": false, "data": null,
		"error": {"code": "invalid_input", "message": "Invalid student ID"}})
	_simulate(decoder, 102, 409, {"ok": false, "data": null,
		"error": {"code": "student_exists", "message": "Details differ"}})
	_simulate(decoder, 103, 201, {"ok": true,
		"data": {"student": {"student_id": id}, "recovery_pending": false}, "error": null})
	_simulate(decoder, 104, 200, {"ok": true,
		"data": {"student": {"student_id": id}, "recovery_pending": true}, "error": null})
	_simulate(decoder, 105, 503, {"ok": false, "data": null,
		"error": {"code": "database_unavailable", "message": "Local service unavailable"}})
	_simulate(decoder, 106, 0, {}, HTTPRequest.RESULT_CANT_CONNECT)
	_check(decoded.size() == 7, "every mocked API/transport outcome emits exactly one result")
	for i in range(mini(7, decoded.size())):
		_check(int(decoded[i]["result"]["request_id"]) == 100 + i,
			"response request IDs correlate through callback at index " + str(i))
	_check(decoded[0]["result"]["error"] == "student_not_found"
		and int(decoded[0]["result"]["status"]) == 404,
		"missing student stays distinct from transport errors")
	_check(decoded[1]["result"]["error"] == "invalid_input"
		and int(decoded[1]["result"]["status"]) == 400,
		"invalid ID is not misrepresented as a genuinely missing student")
	_check(decoded[2]["result"]["error"] == "student_exists"
		and int(decoded[2]["result"]["status"]) == 409,
		"identity conflict survives decoded HTTP contract")
	_check(bool(decoded[3]["result"]["ok"]) and int(decoded[3]["result"]["status"]) == 201,
		"new profile registration is a successful 201")
	_check(bool(decoded[4]["result"]["ok"]) and int(decoded[4]["result"]["status"]) == 200
		and bool(decoded[4]["result"]["data"]["recovery_pending"]),
		"offline durable recovery acceptance retains recovery_pending=true")
	_check(decoded[5]["result"]["error"] == "database_unavailable"
		and int(decoded[5]["result"]["status"]) == 503,
		"reachable API with unavailable PostgreSQL reports 503")
	_check(decoded[6]["result"]["error"] == "connection_error"
		and int(decoded[6]["result"]["status"]) == 0,
		"unreachable HTTP service reports connection_error and no fake success")

	client.queue_free()
	decoder.queue_free()
	await process_frame
	for issue in failures:
		printerr("MANUAL STUDENT CLIENT CONTRACT FAIL: ", issue)
	print("MANUAL STUDENT CLIENT NO-CSV CONTRACT: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _simulate(client: Node, request_id: int, status: int, response: Dictionary,
		transport: int = HTTPRequest.RESULT_SUCCESS) -> void:
	var request := HTTPRequest.new()
	client.add_child(request)
	client._inflight[request_id] = {"http": request,
		"context": {"operation": "find_student", "request_id": request_id}}
	client.call("_on_request_completed", transport, status, PackedStringArray(),
		JSON.stringify(response).to_utf8_buffer(), request_id)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
