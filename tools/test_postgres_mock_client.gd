extends Node

## Deterministic transport for routed UI tests. This never opens a socket.
signal request_finished(context: Dictionary, result: Dictionary)

var requests: Array[Dictionary] = []
var _next_id := 0


func check_health(context: Dictionary = {}) -> int:
	return _record("health", {}, context)


func health(context: Dictionary = {}) -> int:
	return check_health(context)


func find_student(student_id: String, context: Dictionary = {}) -> int:
	return _record("find_student", {"student_id": student_id}, context)


func register_student(student_id: String, student_name: String, grade_section: String, context: Dictionary = {}) -> int:
	return _record("register_student", {
		"student_id": student_id, "student_name": student_name,
		"grade_section": grade_section,
	}, context)


func complete_round(student_id: String, game_style: String, game_mode: String, difficulty: String, score: int, context: Dictionary = {}) -> int:
	return _record("complete_round", {
		"student_id": student_id, "game_style": game_style, "game_mode": game_mode,
		"difficulty": difficulty, "score": score,
	}, context)


func get_leaderboard(game_style: String = "", game_mode: String = "", difficulty: String = "", grade_section: String = "", context: Dictionary = {}) -> int:
	return _record("get_leaderboard", {
		"game_style": game_style, "game_mode": game_mode,
		"difficulty": difficulty, "grade_section": grade_section,
	}, context)


func count(operation: String) -> int:
	var total := 0
	for request in requests:
		if request["context"]["operation"] == operation:
			total += 1
	return total


func find_pending(operation: String, purpose: String = "") -> Dictionary:
	for index in range(requests.size() - 1, -1, -1):
		var request: Dictionary = requests[index]
		var info: Dictionary = request["context"]
		if not request["responded"] and info["operation"] == operation \
				and (purpose.is_empty() or String(info.get("purpose", "")) == purpose):
			return request
	return {}


func reply(operation: String, response: Dictionary, purpose: String = "") -> bool:
	var pending := find_pending(operation, purpose)
	if pending.is_empty():
		return false
	pending["responded"] = true
	var context: Dictionary = pending["context"]
	var result: Dictionary = {
		"request_id": context["request_id"], "ok": false, "data": null,
		"status": 0, "error": "", "message": "",
	}
	for key in response:
		result[key] = response[key]
	request_finished.emit(context.duplicate(true), result)
	return true


func _record(operation: String, args: Dictionary, context: Dictionary) -> int:
	_next_id += 1
	var info := context.duplicate(true)
	info["operation"] = operation
	info["request_id"] = _next_id
	requests.append({"context": info, "args": args.duplicate(true), "responded": false})
	return _next_id
