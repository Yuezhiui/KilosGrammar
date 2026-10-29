extends Node

## Nonblocking local PostgreSQL service transport. The HTTP server owns SQL,
## transactions and credential storage; scenes only use this asynchronous API.
##
## request_finished(context, result):
##   context = caller-supplied fields + operation + request_id (+ lookup keys)
##   result = {ok: bool, data: Variant, error: String, message: String,
##             status: int, request_id: int}
## Every public call returns a request_id immediately. Even validation failures
## are delivered on a later idle frame so callers can record the returned id.

signal request_finished(context: Dictionary, result: Dictionary)
## Emitted as (state, details); states: checking, starting, retrying,
## online, offline. Failed startup includes a non-secret details.reason.
signal local_service_status_changed(state: String, details: Dictionary)

const DEFAULT_PORT := 18765
const REQUEST_TIMEOUT_SECONDS := 8.0
const STARTUP_PROBE_TIMEOUT_SECONDS := 1.5
const AUTO_START_SCRIPT := "res://database/start_auto.ps1"
const MIN_LAUNCH_GAP_MSEC := 60000
const MAX_IDENTIFIER_LENGTH := 128
const MAX_NAME_LENGTH := 200
const MAX_GRADE_LENGTH := 100
const MAX_IMPORT_CSV_BYTES := 1_000_000
const ADMIN_OPERATIONS := ["export_data_csv", "import_data_csv", "request_delete_all_challenge", "delete_all_data"]

var _next_request_id := 0
var _inflight: Dictionary = {}

## Explicit opt-out for scenes/tests. Native Windows GUI startup additionally
## requires the local, user-configured startup script to exist on disk.
@export var enable_local_service_launcher := true
@export_range(0.5, 30.0, 0.5) var startup_timeout_seconds := 10.0
## Enabled after the first ensure_local_service() call, so opening a client
## for a one-off lookup doesn't silently start background activity.
@export var enable_local_service_watchdog := true
@export_range(1.0, 120.0, 1.0) var watchdog_online_interval_seconds := 15.0
@export_range(1.0, 120.0, 1.0) var watchdog_offline_min_seconds := 5.0
@export_range(5.0, 300.0, 1.0) var watchdog_offline_max_seconds := 60.0

var _startup_active := false
var _startup_request_id := -1
var _startup_first_request_id := -1
var _startup_context: Dictionary = {}
var _startup_deadline_msec := 0
var _startup_attempt := 0
var _startup_backoff := 0.25
var _startup_last_failure := "server_unreachable"
var _startup_launch_attempted := false
var _startup_timer: Timer
var _last_launch_attempt_msec := -MIN_LAUNCH_GAP_MSEC
var _watchdog_timer: Timer
var _watchdog_request_id := -1
var _watchdog_online := false
var _watchdog_enabled_by_ensure := false
var _watchdog_last_reason := ""
var _watchdog_offline_delay_seconds := 5.0


func ensure_local_service(context: Dictionary = {}) -> int:
	## Idempotent until completion. Repeated health calls continue to use the
	## public request_finished contract and never block rendering.
	if _startup_active:
		return _startup_first_request_id
	if not is_inside_tree():
		return _reject("health", context, "not_in_tree")
	_watchdog_enabled_by_ensure = true
	if is_instance_valid(_watchdog_timer):
		_watchdog_timer.stop()
	if _watchdog_request_id != -1:
		var old_watchdog_id := _watchdog_request_id
		_watchdog_request_id = -1
		cancel_request(old_watchdog_id)
	_startup_active = true
	_startup_context = context.duplicate(true)
	_startup_deadline_msec = Time.get_ticks_msec() + int(startup_timeout_seconds * 1000.0)
	_startup_first_request_id = -1
	_startup_attempt = 0
	_startup_backoff = 0.25
	_startup_last_failure = "server_unreachable"
	_startup_launch_attempted = false
	if _startup_timer == null:
		_startup_timer = Timer.new()
		_startup_timer.one_shot = true
		add_child(_startup_timer)
		_startup_timer.timeout.connect(_startup_probe)
	_emit_startup_status("checking", "")
	return _startup_probe()


func _startup_probe() -> int:
	if not _startup_active or not is_inside_tree():
		return -1
	_startup_attempt += 1
	var metadata := _startup_context.duplicate(true)
	metadata["local_service_probe"] = true
	if not metadata.has("purpose"):
		metadata["purpose"] = "startup"
	var request_id := _send("health", HTTPClient.METHOD_GET, "/health", {}, metadata)
	_startup_request_id = request_id
	if _startup_first_request_id == -1:
		_startup_first_request_id = request_id
	return request_id


func _on_startup_health_result(result: Dictionary) -> void:
	if not _startup_active:
		return
	_startup_request_id = -1
	if String(result.get("error", "")) == "cancelled":
		_finish_startup("offline", "cancelled")
		return
	var payload: Variant = result.get("data", null)
	# Recovery API remains available when its primary PostgreSQL connection
	# is down: the service can durably queue records in local SQLite.
	var healthy := bool(result.get("ok", false)) and payload is Dictionary \
		and String(payload.get("database", "")) in ["connected", "recovery"]
	if healthy:
		_finish_startup("online", "")
		return
	var status := int(result.get("status", 0))
	if status > 0:
		# HTTP already listens on this port. An API reporting 503 because of
		# missing DB credentials/schema must NOT trigger a second listener.
		_startup_last_failure = "database_auth_or_schema" if status == 503 else "http_health_failed"
	elif not _startup_launch_attempted:
		if not _can_launch_local_service():
			_startup_last_failure = "launcher_disabled"
		elif not FileAccess.file_exists(_startup_script_path()) or not _has_saved_credentials():
			_finish_startup("offline", "setup_required")
			return
		else:
			if Time.get_ticks_msec() - _last_launch_attempt_msec < MIN_LAUNCH_GAP_MSEC:
				# An earlier launch may still be warming up; keep probing.
				_startup_last_failure = "server_unreachable"
			else:
				_startup_launch_attempted = true
				_last_launch_attempt_msec = Time.get_ticks_msec()
				var launch_result := _start_local_service_process()
				if not bool(launch_result.get("ok", false)):
					_finish_startup("offline", String(launch_result.get("reason", "launch_failed")))
					return
				_emit_startup_status("starting", "")
	if Time.get_ticks_msec() >= _startup_deadline_msec:
		_finish_startup("offline", _startup_last_failure)
		return
	_emit_startup_status("retrying", _startup_last_failure)
	var remaining := float(_startup_deadline_msec - Time.get_ticks_msec()) / 1000.0
	_startup_timer.start(minf(_startup_backoff, remaining))
	_startup_backoff = minf(_startup_backoff * 1.65, 1.5)


func _finish_startup(state: String, reason: String) -> void:
	_startup_active = false
	_startup_request_id = -1
	if is_instance_valid(_startup_timer):
		_startup_timer.stop()
	_watchdog_online = state == "online"
	_watchdog_last_reason = reason
	if _watchdog_online:
		_watchdog_offline_delay_seconds = watchdog_offline_min_seconds
	_emit_startup_status(state, reason)
	_schedule_watchdog()


func _schedule_watchdog() -> void:
	if not enable_local_service_watchdog or not _watchdog_enabled_by_ensure or not is_inside_tree():
		return
	if _startup_active or _watchdog_request_id != -1:
		return
	if not is_instance_valid(_watchdog_timer):
		_watchdog_timer = Timer.new()
		_watchdog_timer.one_shot = true
		add_child(_watchdog_timer)
		_watchdog_timer.timeout.connect(_watchdog_tick)
	if _watchdog_online:
		_watchdog_timer.start(watchdog_online_interval_seconds)
	elif _watchdog_last_reason == "setup_required":
		# Detect credentials saved during a running game without polling the API
		# or launching any process before a configuration exists.
		_watchdog_timer.start(watchdog_offline_min_seconds)
	else:
		_watchdog_timer.start(_watchdog_offline_delay_seconds)
		_watchdog_offline_delay_seconds = minf(
			maxf(watchdog_offline_min_seconds, _watchdog_offline_delay_seconds * 2.0),
			maxf(watchdog_offline_min_seconds, watchdog_offline_max_seconds))


func _watchdog_tick() -> void:
	if not enable_local_service_watchdog or not is_inside_tree() or _startup_active:
		return
	if _watchdog_online:
		# Healthy sessions need just one inexpensive asynchronous check every
		# interval. Don't show UI state changes unless the health actually fails.
		_watchdog_request_id = _send("health", HTTPClient.METHOD_GET, "/health", {}, {
			"purpose": "watchdog", "local_service_probe": true,
			"local_service_watchdog": true,
		})
		return
	if _watchdog_last_reason == "setup_required" \
		and (not FileAccess.file_exists(_startup_script_path()) or not _has_saved_credentials()):
		_schedule_watchdog()
		return
	ensure_local_service({"purpose": "watchdog_reconnect"})


func _on_watchdog_health_result(result: Dictionary) -> void:
	_watchdog_request_id = -1
	if not enable_local_service_watchdog or not is_inside_tree():
		return
	var payload: Variant = result.get("data", null)
	if bool(result.get("ok", false)) and payload is Dictionary \
		and String(payload.get("database", "")) in ["connected", "recovery"]:
		_watchdog_online = true
		_schedule_watchdog()
		return
	if String(result.get("error", "")) == "cancelled":
		_schedule_watchdog()
		return
	_watchdog_online = false
	_watchdog_last_reason = "database_auth_or_schema" if int(result.get("status", 0)) == 503 else "server_unreachable"
	_emit_startup_status("offline", _watchdog_last_reason)
	# The running API could have died after a completed round. Begin one
	# bounded recovery cycle now, and increase the delay only if it fails.
	ensure_local_service({"purpose": "watchdog_reconnect"})


func _emit_startup_status(state: String, reason: String) -> void:
	local_service_status_changed.emit(state, {
		"reason": reason,
		"attempt": _startup_attempt,
		"origin": _origin(),
		"launcher_attempted": _startup_launch_attempted,
	})


func _can_launch_local_service() -> bool:
	return enable_local_service_launcher and OS.get_name() == "Windows" \
		and DisplayServer.get_name() != "headless"


func _startup_script_path() -> String:
	# Godot exports resources to a .pck, but PowerShell cannot execute a
	# script *inside* a PCK. Windows release staging supplies a physical
	# database/ directory beside KilosGrammar.exe. Keep F5 editor fallback.
	var installed := OS.get_executable_path().get_base_dir().path_join("database/start_auto.ps1")
	if FileAccess.file_exists(installed):
		return installed
	return ProjectSettings.globalize_path(AUTO_START_SCRIPT)


func _has_saved_credentials() -> bool:
	## start_auto.ps1 uses this exact per-user DPAPI path. File presence is
	## checked only; the game never opens/decrypts the credential file.
	var app_data := OS.get_environment("LOCALAPPDATA").strip_edges()
	if app_data.is_empty():
		return false
	return FileAccess.file_exists(app_data.path_join("KilosGrammar").path_join("db_credentials.xml"))


func _start_local_service_process() -> Dictionary:
	## No password, connection string, SQL or teacher data is ever passed on
	## the command line. start_auto.ps1 owns secure local credential loading.
	var path := _startup_script_path()
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "setup_required"}
	var args := PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
		"-ExecutionPolicy", "Bypass", "-File", path,
		"-HttpPort", str(_service_port()),
	])
	var pid := OS.create_process("powershell.exe", args, false)
	if pid <= 0:
		pid = OS.create_process("pwsh.exe", args, false)
	if pid <= 0:
		return {"ok": false, "reason": "powershell_unavailable"}
	return {"ok": true, "pid": pid}


func health(context: Dictionary = {}) -> int:
	return _send("health", HTTPClient.METHOD_GET, "/health", {}, context)


func check_health(context: Dictionary = {}) -> int:
	return health(context)


func find_student(student_id: String, context: Dictionary = {}) -> int:
	var sid := student_id.strip_edges()
	var info := _with_fields(context, {"student_id": sid})
	if not _valid_text(sid, MAX_IDENTIFIER_LENGTH):
		return _reject("find_student", info, "invalid_student_id")
	return _send("find_student", HTTPClient.METHOD_GET, "/students/" + sid.uri_encode(), {}, info)


func find_student_by_name(full_name: String, context: Dictionary = {}) -> int:
	var name_text := full_name.strip_edges()
	var info := _with_fields(context, {"student_name": name_text})
	if not _valid_text(name_text, MAX_NAME_LENGTH) or name_text.split(" ", false).size() < 2:
		return _reject("find_student_by_name", info, "invalid_full_name")
	return _send("find_student_by_name", HTTPClient.METHOD_GET,
		"/students/by-name?name=" + name_text.uri_encode(), {}, info)


func register_student(student_id: String, student_name: String, grade_section: String, context: Dictionary = {}) -> int:
	var sid := student_id.strip_edges()
	var name_text := student_name.strip_edges()
	var grade := grade_section.strip_edges()
	var info := _with_fields(context, {"student_id": sid})
	if not _valid_text(sid, MAX_IDENTIFIER_LENGTH):
		return _reject("register_student", info, "invalid_student_id")
	if not _valid_text(name_text, MAX_NAME_LENGTH):
		return _reject("register_student", info, "invalid_student_name")
	if not _valid_text(grade, MAX_GRADE_LENGTH):
		return _reject("register_student", info, "invalid_grade_section")
	return _send("register_student", HTTPClient.METHOD_POST, "/students", {
		"student_id": sid,
		"student_name": name_text,
		"grade_section": grade,
	}, info)


func update_student(student_id: String, student_name: String, grade_section: String, context: Dictionary = {}) -> int:
	## Call only after the teacher explicitly confirms the identity update.
	var sid := student_id.strip_edges()
	var name_text := student_name.strip_edges()
	var grade := grade_section.strip_edges()
	var info := _with_fields(context, {"student_id": sid})
	if not _valid_text(sid, MAX_IDENTIFIER_LENGTH):
		return _reject("update_student", info, "invalid_student_id")
	if not _valid_text(name_text, MAX_NAME_LENGTH):
		return _reject("update_student", info, "invalid_student_name")
	if not _valid_text(grade, MAX_GRADE_LENGTH):
		return _reject("update_student", info, "invalid_grade_section")
	return _send("update_student", HTTPClient.METHOD_PATCH, "/students/" + sid.uri_encode(), {
		"student_name": name_text,
		"grade_section": grade,
	}, info)


func find_score(student_id: String, game_style: String, game_mode: String, difficulty: String, context: Dictionary = {}) -> int:
	var sid := student_id.strip_edges()
	var selection := _selection(game_style, game_mode, difficulty)
	var info := _with_fields(context, selection)
	info["student_id"] = sid
	if not _valid_text(sid, MAX_IDENTIFIER_LENGTH):
		return _reject("find_score", info, "invalid_student_id")
	if not _valid_selection(selection):
		return _reject("find_score", info, "invalid_game_selection")
	var params := _query({
		"student_id": sid,
		"game_style": selection["game_style"],
		"game_mode": selection["game_mode"],
		"difficulty": selection["difficulty"],
		"minigame": _score_minigame(context),
	})
	return _send("find_score", HTTPClient.METHOD_GET, "/scores?" + params, {}, info)


func complete_round(student_id: String, game_style: String, game_mode: String, difficulty: String, score: int, context: Dictionary = {}) -> int:
	## Only invoke after an actually completed round; never on abort/failure.
	## The server performs an atomic upsert of the latest completed score.
	var sid := student_id.strip_edges()
	var selection := _selection(game_style, game_mode, difficulty)
	var info := _with_fields(context, selection)
	info["student_id"] = sid
	if not _valid_text(sid, MAX_IDENTIFIER_LENGTH):
		return _reject("complete_round", info, "invalid_student_id")
	if not _valid_selection(selection):
		return _reject("complete_round", info, "invalid_game_selection")
	if score < 0:
		return _reject("complete_round", info, "invalid_score")
	var payload := selection.duplicate()
	payload["student_id"] = sid
	payload["score"] = score
	# The grammar topic is NOT the minigame. Both dimensions determine the
	# latest completed score, preventing a Human Plane round from overwriting
	# a Catch the Word score for the same student/topic/mode/difficulty.
	payload["minigame"] = _score_minigame(context)
	# The immutable Godot recovery-event ID identifies one physical round.
	# If an HTTP acknowledgement disappears, the SQLite service can safely
	# deduplicate the retry instead of replaying the same score twice.
	var recovery_id := String(context.get("recovery_event_id", "")).strip_edges()
	if not recovery_id.is_empty():
		payload["request_id"] = recovery_id
	return _send("complete_round", HTTPClient.METHOD_POST, "/rounds/complete", payload, info)


func get_leaderboard(game_style: String = "", game_mode: String = "", difficulty: String = "", grade_section: String = "", context: Dictionary = {}) -> int:
	var selection := _selection(game_style, game_mode, difficulty)
	var grade := grade_section.strip_edges()
	var info := _with_fields(context, selection)
	info["grade_section"] = grade
	if not _valid_optional_selection(selection):
		return _reject("get_leaderboard", info, "invalid_game_selection")
	if grade.length() > MAX_GRADE_LENGTH or (not grade.is_empty() and not _valid_text(grade, MAX_GRADE_LENGTH)):
		return _reject("get_leaderboard", info, "invalid_grade_section")
	var params := {}
	if not String(context.get("minigame", "")).strip_edges().is_empty():
		params["minigame"] = String(context["minigame"]).strip_edges()
	for key in selection:
		if not String(selection[key]).is_empty():
			params[key] = selection[key]
	if not grade.is_empty():
		params["grade_section"] = grade
	var route := "/leaderboard"
	if not params.is_empty():
		route += "?" + _query(params)
	return _send("get_leaderboard", HTTPClient.METHOD_GET, route, {}, info)


func _score_minigame(context: Dictionary) -> String:
	# Backward-compatible scripts without an activity remain explicitly Legacy.
	# Live gameplay always passes the chosen minigame from session setup.
	var name := String(context.get("minigame", context.get("activity", "Legacy"))).strip_edges()
	return name if name in ["Catch the Word", "Balloon Popping", "Human Plane"] else "Legacy"


func export_data_csv(context: Dictionary = {}) -> int:
	## Unlike get_leaderboard, this includes *all* student records (even those
	## without scores), not just the first 500 ranked rows. Teacher-authorized.
	return _send("export_data_csv", HTTPClient.METHOD_GET, "/data/export", {}, context)


func import_data_csv(csv_text: String, context: Dictionary = {}) -> int:
	## The server performs strict CSV validation and one atomic transaction.
	## Never silently replace an existing student identity or import partial data.
	var size_bytes := csv_text.to_utf8_buffer().size()
	if size_bytes == 0 or size_bytes > MAX_IMPORT_CSV_BYTES:
		return _reject("import_data_csv", context, "invalid_csv_size")
	return _send("import_data_csv", HTTPClient.METHOD_POST, "/data/import", {
		"csv": csv_text,
	}, context)


func request_delete_all_challenge(context: Dictionary = {}) -> int:
	## Read-only; a server nonce must be fetched BEFORE any delete request.
	return _send("request_delete_all_challenge", HTTPClient.METHOD_GET,
		"/data/delete_all/challenge", {}, context)


func delete_all_data(challenge: String, confirmation: String, context: Dictionary = {}) -> int:
	## The server also validates and atomically consumes its short-lived nonce.
	## A missing exact phrase is refused before any HTTP request is issued.
	if challenge.strip_edges().is_empty() or confirmation != "DELETE ALL DATA":
		return _reject("delete_all_data", context, "confirmation_required")
	return _send("delete_all_data", HTTPClient.METHOD_POST, "/data/delete_all", {
		"challenge": challenge,
		"confirmation": confirmation,
	}, context)


func cancel_request(request_id: int) -> void:
	if not _inflight.has(request_id):
		return
	var pending: Dictionary = _inflight[request_id]
	_inflight.erase(request_id)
	var http := pending["http"] as HTTPRequest
	if is_instance_valid(http):
		http.cancel_request()
		http.queue_free()
	_emit_result.call_deferred(pending["context"], _failure(request_id, "cancelled", "Request cancelled."))


func cancel_all() -> void:
	for request_id in _inflight.keys():
		cancel_request(int(request_id))


func _exit_tree() -> void:
	## Disconnect and free requests when the owning UI leaves the scene tree.
	## No callbacks are sent to destroyed screens.
	_startup_active = false
	_startup_request_id = -1
	_watchdog_enabled_by_ensure = false
	_watchdog_request_id = -1
	if is_instance_valid(_startup_timer):
		_startup_timer.stop()
	if is_instance_valid(_watchdog_timer):
		_watchdog_timer.stop()
	for request_id in _inflight.keys():
		var pending: Dictionary = _inflight[request_id]
		var http := pending["http"] as HTTPRequest
		if is_instance_valid(http):
			http.cancel_request()
			http.queue_free()
	_inflight.clear()


func _send(operation: String, method: int, route: String, payload: Dictionary, context: Dictionary) -> int:
	var request_id := _take_id()
	var info := _request_context(operation, request_id, context)
	if not is_inside_tree():
		_emit_result.call_deferred(info, _failure(request_id, "not_in_tree", "Database client is not active."))
		return request_id
	var admin_token := ""
	if operation in ADMIN_OPERATIONS:
		admin_token = _read_admin_token()
		if admin_token.is_empty():
			_emit_result.call_deferred(info, _failure(request_id, "admin_authorization_unavailable",
				"Teacher database controls are unavailable. Restart the local API and try again."))
			return request_id
	var http := HTTPRequest.new()
	http.timeout = STARTUP_PROBE_TIMEOUT_SECONDS if bool(context.get("local_service_probe", false)) else REQUEST_TIMEOUT_SECONDS
	http.use_threads = true
	add_child(http)
	_inflight[request_id] = {"http": http, "context": info}
	http.request_completed.connect(_on_request_completed.bind(request_id))
	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	if not admin_token.is_empty():
		headers.append("X-Kilos-Admin-Token: " + admin_token)
	var body := JSON.stringify(payload) if method != HTTPClient.METHOD_GET else ""
	var error := http.request(_origin() + route, headers, method, body)
	if error != OK:
		_inflight.erase(request_id)
		http.queue_free()
		_emit_result.call_deferred(info, _failure(request_id, "request_start_failed", "Could not start local database request."))
	return request_id


func _read_admin_token() -> String:
	## Startup writes an OS-user-scoped token to LOCALAPPDATA; it isn't a
	## PostgreSQL password and is never placed in scene fields or commit files.
	var app_data := OS.get_environment("LOCALAPPDATA").strip_edges()
	if app_data.is_empty():
		return ""
	var path := app_data.path_join("KilosGrammar").path_join("admin_api_token.txt")
	if not FileAccess.file_exists(path):
		return ""
	var token := FileAccess.get_file_as_string(path).strip_edges()
	if token.length() < 32 or token.length() > 256:
		return ""
	for code in token.to_utf8_buffer():
		if code <= 32 or code >= 127 or code == 58:
			return "" # No control characters, whitespace or HTTP header delimiters.
	return token


func has_local_admin_token() -> bool:
	## Local Windows-user access check for teacher database controls. This is
	## UI gating only; the backend independently checks the token on EVERY call.
	return not _read_admin_token().is_empty()


func _on_request_completed(transport: int, status: int, _headers: PackedStringArray, body: PackedByteArray, request_id: int) -> void:
	if not _inflight.has(request_id):
		return # Cancelled requests must never deliver a late success.
	var pending: Dictionary = _inflight[request_id]
	_inflight.erase(request_id)
	var http := pending["http"] as HTTPRequest
	if is_instance_valid(http):
		http.queue_free()
	var info: Dictionary = pending["context"]
	if transport != HTTPRequest.RESULT_SUCCESS:
		var fail := _failure(request_id, "connection_error", "Local database service is unavailable.")
		fail["transport_result"] = transport
		fail["status"] = status
		_emit_result(info, fail)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		var bad := _failure(request_id, "invalid_response", "Database service returned invalid JSON.")
		bad["status"] = status
		_emit_result(info, bad)
		return
	var response: Dictionary = parsed
	var success := status >= 200 and status < 300 and bool(response.get("ok", true))
	var result: Dictionary = {
		"ok": success,
		"data": response.get("data", null),
		"status": status,
		"request_id": request_id,
		"error": "",
		"message": "",
	}
	if not success:
		var error_value: Variant = response.get("error", "http_error")
		if error_value is Dictionary:
			result["error"] = str(error_value.get("code", "http_error"))
			result["message"] = str(error_value.get("message", "Database request failed."))
		else:
			result["error"] = str(error_value)
			result["message"] = str(response.get("message", "Database request failed."))
	_emit_result(info, result)


func _emit_result(context: Dictionary, result: Dictionary) -> void:
	if is_inside_tree():
		request_finished.emit(context, result)
		if _startup_active and int(context.get("request_id", -1)) == _startup_request_id:
			_on_startup_health_result(result)
		elif int(context.get("request_id", -1)) == _watchdog_request_id:
			_on_watchdog_health_result(result)


func _reject(operation: String, context: Dictionary, reason: String) -> int:
	var request_id := _take_id()
	var info := _request_context(operation, request_id, context)
	_emit_result.call_deferred(info, _failure(request_id, reason, "Invalid database request fields."))
	return request_id


func _failure(request_id: int, reason: String, explanation: String) -> Dictionary:
	return {
		"ok": false,
		"data": null,
		"status": 0,
		"request_id": request_id,
		"error": reason,
		"message": explanation,
	}


func _take_id() -> int:
	_next_request_id += 1
	return _next_request_id


func _request_context(operation: String, request_id: int, context: Dictionary) -> Dictionary:
	var info := context.duplicate(true)
	info["operation"] = operation
	info["request_id"] = request_id
	return info


func _with_fields(context: Dictionary, fields: Dictionary) -> Dictionary:
	var result := context.duplicate(true)
	for key in fields:
		result[key] = fields[key]
	return result


func _selection(game_style: String, game_mode: String, difficulty: String) -> Dictionary:
	return {
		"game_style": game_style.strip_edges(),
		"game_mode": game_mode.strip_edges(),
		"difficulty": difficulty.strip_edges(),
	}


func _valid_selection(selection: Dictionary) -> bool:
	return _valid_text(String(selection["game_style"]), MAX_IDENTIFIER_LENGTH) \
		and _valid_text(String(selection["game_mode"]), MAX_IDENTIFIER_LENGTH) \
		and _valid_text(String(selection["difficulty"]), MAX_IDENTIFIER_LENGTH)


func _valid_optional_selection(selection: Dictionary) -> bool:
	for key in selection:
		var entry := String(selection[key])
		if not entry.is_empty() and not _valid_text(entry, MAX_IDENTIFIER_LENGTH):
			return false
	return true


func _valid_text(value: String, max_length: int) -> bool:
	if value.is_empty() or value.length() > max_length:
		return false
	for index in value.length():
		if value.unicode_at(index) < 32:
			return false
	return true


func _query(params: Dictionary) -> String:
	var pieces := PackedStringArray()
	for key in params.keys():
		pieces.append(String(key).uri_encode() + "=" + String(params[key]).uri_encode())
	return "&".join(pieces)


func _origin() -> String:
	## The host is intentionally fixed to IPv4 loopback, never a public URL.
	return "http://127.0.0.1:%d" % _service_port()


func _service_port() -> int:
	var port := DEFAULT_PORT
	var raw := OS.get_environment("KILOSGRAMMAR_DB_PORT").strip_edges()
	if not raw.is_empty() and raw.is_valid_int():
		var env_port := raw.to_int()
		if env_port > 0 and env_port <= 65535:
			port = env_port
	return port
