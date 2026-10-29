extends Node

signal request_finished(context: Dictionary, result: Dictionary)
signal local_service_status_changed(state: String, details: Dictionary)

var registration_mode := "success"
var completion_mode := "success"
var register_calls: Array[Dictionary] = []
var complete_calls: Array[Dictionary] = []
var leaderboard_calls: Array[Dictionary] = []
var delete_calls: Array[Dictionary] = []
var cancelled_requests: Array[int] = []
var persisted_scores: Dictionary = {}

var _next_request_id := 1
var _held_requests: Dictionary = {}
var _held_completion_requests: Dictionary = {}


func reset_calls() -> void:
	register_calls.clear()
	complete_calls.clear()
	leaderboard_calls.clear()
	delete_calls.clear()
	cancelled_requests.clear()
	_held_requests.clear()
	_held_completion_requests.clear()
	persisted_scores.clear()
	completion_mode = "success"


func register_student(student_id: String, student_name: String, grade_section: String,
		context: Dictionary = {}) -> int:
	var request_id := _take_request_id()
	var info := _request_info("register_student", request_id, context)
	register_calls.append({
		"student_id": student_id,
		"student_name": student_name,
		"grade_section": grade_section,
		"info": info.duplicate(true),
	})
	match registration_mode:
		"success":
			call_deferred("_emit_result", info, {
				"ok": true,
				"data": {"student": {"student_id": student_id}},
				"error": "",
			})
		"conflict":
			call_deferred("_emit_result", info, {
				"ok": false,
				"data": {},
				"error": "student_exists",
			})
		"offline":
			call_deferred("_emit_result", info, {
				"ok": false,
				"data": {},
				"error": "database_unavailable",
			})
		"hold":
			_held_requests[request_id] = info.duplicate(true)
		_:
			call_deferred("_emit_result", info, {
				"ok": false,
				"data": {},
				"error": "invalid_test_mode",
			})
	return request_id


func complete_round(student_id: String, game_style: String, game_mode: String,
		difficulty: String, score: int, context: Dictionary = {}) -> int:
	var request_id := _take_request_id()
	var info := _request_info("complete_round", request_id, context)
	var minigame := String(context.get("minigame", "Legacy"))
	complete_calls.append({
		"student_id": student_id,
		"game_style": game_style,
		"game_mode": game_mode,
		"difficulty": difficulty,
		"score": score,
		"info": info.duplicate(true),
	})
	var row := {
		"student_id": student_id,
		"student_name": "Mock Student",
		"grade_section": "Mock Grade",
		"minigame": minigame,
		"game_style": game_style,
		"game_mode": game_mode,
		"difficulty": difficulty,
		"score": score,
	}
	var score_key := "%s|%s|%s|%s|%s" % [student_id, minigame, game_style, game_mode, difficulty]
	persisted_scores[score_key] = row.duplicate(true)
	var result := {
		"ok": true,
		"data": {"score": row.duplicate(true)},
		"error": "",
	}
	if completion_mode == "hold":
		_held_completion_requests[request_id] = {
			"info": info.duplicate(true),
			"result": result.duplicate(true),
		}
	else:
		call_deferred("_emit_result", info, result)
	return request_id


func release_held_completions() -> void:
	var held := _held_completion_requests.values()
	_held_completion_requests.clear()
	for entry: Dictionary in held:
		call_deferred("_emit_result", entry["info"], entry["result"])


func get_leaderboard(_game_style: String = "", _game_mode: String = "",
			_difficulty: String = "", _grade_section: String = "",
			context: Dictionary = {}) -> int:
	var request_id := _take_request_id()
	var info := _request_info("get_leaderboard", request_id, context)
	leaderboard_calls.append(info.duplicate(true))
	var rows: Array = []
	for row: Dictionary in persisted_scores.values():
		rows.append(row.duplicate(true))
	call_deferred("_emit_result", info, {
		"ok": true,
		"data": {"leaderboard": rows, "count": rows.size()},
		"error": "",
	})
	return request_id


func has_local_admin_token() -> bool:
	return true


func request_delete_all_challenge(context: Dictionary = {}) -> int:
	var request_id := _take_request_id()
	var info := _request_info("request_delete_all_challenge", request_id, context)
	call_deferred("_emit_result", info, {
		"ok": true,
		"data": {"challenge": "mock-delete-challenge", "confirmation_phrase": "DELETE ALL DATA"},
		"error": "",
	})
	return request_id


func delete_all_data(challenge: String, confirmation: String, context: Dictionary = {}) -> int:
	var request_id := _take_request_id()
	var info := _request_info("delete_all_data", request_id, context)
	delete_calls.append({
		"challenge": challenge,
		"confirmation": confirmation,
		"info": info.duplicate(true),
	})
	var score_count := persisted_scores.size()
	if challenge == "mock-delete-challenge" and confirmation == "DELETE ALL DATA":
		persisted_scores.clear()
	call_deferred("_emit_result", info, {
		"ok": true,
		"data": {"students_deleted": 1, "scores_deleted": score_count},
		"error": "",
	})
	return request_id


func check_health(context: Dictionary = {}) -> int:
	var request_id := _take_request_id()
	var info := _request_info("health", request_id, context)
	call_deferred("_emit_result", info, {
		"ok": true,
		"data": {"database": "connected"},
		"error": "",
	})
	return request_id


func ensure_local_service(context: Dictionary = {}) -> int:
	call_deferred("_emit_online")
	return check_health(context)


func cancel_request(request_id: int) -> void:
	cancelled_requests.append(request_id)
	_held_requests.erase(request_id)


func _take_request_id() -> int:
	var request_id := _next_request_id
	_next_request_id += 1
	return request_id


func _request_info(operation: String, request_id: int, context: Dictionary) -> Dictionary:
	var info := context.duplicate(true)
	info["operation"] = operation
	info["request_id"] = request_id
	return info


func _emit_result(info: Dictionary, result: Dictionary) -> void:
	request_finished.emit(info.duplicate(true), result.duplicate(true))


func _emit_online() -> void:
	local_service_status_changed.emit("online", {"reason": "", "origin": "mock"})
