extends RefCounted
## Crash-tolerant, local-first emergency handoff when even the localhost API
## process is unavailable. One immutable, flushed file per event avoids losing
## already-saved events when a subsequent write fails. PostgreSQL remains the
## canonical score store; this folder is only an unsynced recovery outbox.
##
## IMPORTANT: Student names/IDs here are sensitive. Keep this directory inside
## user:// (Windows user profile), never res://, screenshots, or Git.

const DIRECTORY := "user://recovery_outbox"
const MAX_EVENTS := 10000
static var _last_stamp_us := 0
static var _warned_unreadable_events: Dictionary = {}


static func _directory() -> String:
	# Godot integration fixtures set a runtime-only ProjectSettings override
	# BEFORE mounting Main Menu, ensuring test registrations can NEVER enter the
	# actual classroom's recovery outbox or be replayed into production PostgreSQL.
	var test_override := String(ProjectSettings.get_setting("kilos/recovery_test_directory", ""))
	if test_override.begins_with("user://test_recovery_"):
		return test_override
	# Automated Godot QA never touches the live Windows-user score outbox.
	# The shipped classroom game runs with an actual graphical window.
	if DisplayServer.get_name() == "headless":
		return "user://test_recovery_headless"
	return DIRECTORY


static func enqueue_profile(student_id: String, student_name: String, grade_section: String) -> Dictionary:
	return _enqueue("profile", {
		"student_id": student_id.strip_edges(),
		"student_name": student_name.strip_edges(),
		"grade_section": grade_section.strip_edges(),
	})


static func enqueue_score(student_id: String, game_style: String,
		game_mode: String, difficulty: String, minigame: String, score: int) -> Dictionary:
	return _enqueue("score", {
		"student_id": student_id.strip_edges(),
		"game_style": game_style.strip_edges(),
		"game_mode": game_mode.strip_edges(),
		"difficulty": difficulty.strip_edges(),
		"minigame": minigame.strip_edges(),
		"score": maxi(score, 0),
	})


static func enqueue_completed_round(student_id: String, student_name: String,
		grade_section: String, game_style: String, game_mode: String,
		difficulty: String, minigame: String, score: int,
		completion_reason: String) -> Dictionary:
	# A genuinely finished NEW student's profile and score are committed in
	# ONE fsynced/renamed event. A crash between separate profile and score
	# files could strand a student profile without any recoverable result.
	return _enqueue("completed_round", {
		"student_id": student_id.strip_edges(),
		"student_name": student_name.strip_edges(),
		"grade_section": grade_section.strip_edges(),
		"game_style": game_style.strip_edges(),
		"game_mode": game_mode.strip_edges(),
		"difficulty": difficulty.strip_edges(),
		"minigame": minigame.strip_edges(),
		"score": score,
		"round_completed": true,
		"completion_reason": completion_reason.strip_edges(),
	})


static func _enqueue(kind: String, payload: Dictionary) -> Dictionary:
	if not _valid_payload(kind, payload):
		return {"ok": false, "error": "invalid_recovery_payload"}
	var path := ProjectSettings.globalize_path(_directory())
	if DirAccess.make_dir_recursive_absolute(path) != OK:
		return {"ok": false, "error": "recovery_directory_unavailable"}
	if pending().size() >= MAX_EVENTS:
		return {"ok": false, "error": "recovery_queue_full"}
	# A random suffix alone does NOT preserve the ordering of two completed
	# scores in the same millisecond. Monotonically advance across process
	# restarts and clock changes by examining all pending event filenames.
	var stamp := _next_ordered_stamp_us()
	var unique_id := "%016d_%s" % [stamp,
		Crypto.new().generate_random_bytes(16).hex_encode()]
	var event := {
		"version": 1, "id": unique_id, "kind": kind,
		"created_unix": Time.get_unix_time_from_system(),
		"sequence_us": stamp, "data": payload.duplicate(true),
	}
	var filename := path.path_join(unique_id + ".json")
	# A kill or power loss during WRITE must not expose half a JSON event as
	# a completed queue item. Stage to a sibling file, fsync via flush, then
	# atomically rename within the same directory. Pending() can promote a
	# fully written staged file left by a crash between flush and rename.
	var staged := filename + ".tmp"
	var output := FileAccess.open(staged, FileAccess.WRITE)
	if output == null:
		return {"ok": false, "error": "recovery_file_unavailable"}
	output.store_string(JSON.stringify(event))
	output.flush()
	var write_error := output.get_error()
	output.close()
	if write_error != OK:
		# Retain failed bytes for offline forensic recovery; never silently
		# discard a possibly partially recorded student round.
		push_warning("A staged recovery event could not be fully written: " + unique_id)
		return {"ok": false, "error": "recovery_write_failed"}
	if DirAccess.rename_absolute(staged, filename) != OK:
		push_warning("A staged recovery event needs retry after restart: " + unique_id)
		return {"ok": false, "error": "recovery_commit_failed"}
	return {"ok": true, "id": unique_id}


static func _event_stamp(id: String) -> int:
	var prefix := id.get_slice("_", 0)
	if not prefix.is_valid_int():
		return 0
	var raw := int(prefix)
	# Historical V1 generated 13-digit millisecond IDs. They must remain
	# correctly ordered ahead of 16-digit microsecond V2 IDs.
	return raw * 1000 if prefix.length() <= 13 else raw


static func _next_ordered_stamp_us() -> int:
	var next_stamp := maxi(int(Time.get_unix_time_from_system() * 1000000.0), _last_stamp_us + 1)
	var folder := DirAccess.open(_directory())
	if folder != null:
		for filename in folder.get_files():
			if filename.ends_with(".json"):
				next_stamp = maxi(next_stamp, _event_stamp(filename.trim_suffix(".json")) + 1)
	_last_stamp_us = next_stamp
	return next_stamp


static func _valid_payload(kind: String, data: Dictionary) -> bool:
	var student_id := String(data.get("student_id", "")).strip_edges()
	if student_id.is_empty() or student_id.length() > 64:
		return false
	var pattern := RegEx.new()
	if pattern.compile("^[A-Za-z0-9][A-Za-z0-9._-]*$") != OK \
			or pattern.search(student_id) == null:
		return false
	if kind == "profile":
		return _valid_personal_text(String(data.get("student_name", ""))) \
			and _valid_personal_text(String(data.get("grade_section", "")))
	if kind == "completed_round":
		var reason := String(data.get("completion_reason", ""))
		var mode := String(data.get("game_mode", ""))
		return bool(data.get("round_completed", false)) \
			and ((mode == "Seconds" and reason == "time_up") \
				or (mode == "Lives" and reason == "lives_empty")) \
			and _valid_payload("profile", data) and _valid_payload("score", data)
	if kind == "score":
		return int(data.get("score", -1)) >= 0 and int(data.get("score", -1)) <= 2147483647 \
			and not String(data.get("game_style", "")).strip_edges().is_empty() \
			and not String(data.get("game_mode", "")).strip_edges().is_empty() \
			and not String(data.get("difficulty", "")).strip_edges().is_empty() \
			and String(data.get("minigame", "")) in ["Catch the Word", "Balloon Popping", "Human Plane"]
	return false


static func _valid_personal_text(value: String) -> bool:
	var clean := value.strip_edges()
	if clean.is_empty() or clean.length() > 150:
		return false
	for character in clean:
		if character.unicode_at(0) < 32 or character.unicode_at(0) == 127:
			return false
	return true


static func pending() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	_recover_staged_events()
	var folder := DirAccess.open(_directory())
	if folder == null:
		return events
	var filenames := folder.get_files()
	filenames.sort()
	for filename in filenames:
		if not filename.ends_with(".json"):
			continue
		var path := _directory().path_join(filename)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		var parser := JSON.new()
		var value: Variant = parser.data if parser.parse(text) == OK else null
		if value is Dictionary and value.get("data", null) is Dictionary \
				and String(value.get("id", "")) + ".json" == filename \
				and _valid_payload(String(value.get("kind", "")), value["data"]):
			events.append(value)
		else:
			_warn_once(filename, "Unreadable recovery event kept for manual repair: " + filename)
	# The replay order must be chronological, not alphabetic: V1 and V2 IDs
	# have different precision, and arbitrary UUID bytes cannot break ties.
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _event_stamp(String(a.get("id", ""))) < _event_stamp(String(b.get("id", ""))))
	return events


static func _recover_staged_events() -> void:
	var folder := DirAccess.open(_directory())
	if folder == null:
		return
	for filename in folder.get_files():
		if not filename.ends_with(".json.tmp"):
			continue
		var staged_path := _directory().path_join(filename)
		var final_path := staged_path.trim_suffix(".tmp")
		if FileAccess.file_exists(final_path):
			_warn_once(filename, "Staged recovery event has an existing committed file: " + filename)
			continue
		var file := FileAccess.open(staged_path, FileAccess.READ)
		if file == null:
			_warn_once(filename, "Staged recovery event is unreadable: " + filename)
			continue
		var parser := JSON.new()
		var value: Variant = parser.data if parser.parse(file.get_as_text()) == OK else null
		file.close()
		if not (value is Dictionary and value.get("data", null) is Dictionary \
				and String(value.get("id", "")) + ".json.tmp" == filename \
				and _valid_payload(String(value.get("kind", "")), value["data"])):
			_warn_once(filename, "Incomplete staged recovery event retained for manual repair: " + filename)
			continue
		if DirAccess.rename_absolute(
				ProjectSettings.globalize_path(staged_path),
				ProjectSettings.globalize_path(final_path)) != OK:
			_warn_once(filename, "Staged recovery event could not be promoted: " + filename)


static func _warn_once(key: String, message: String) -> void:
	if _warned_unreadable_events.has(key):
		return
	_warned_unreadable_events[key] = true
	push_warning(message)


static func acknowledge(event_id: String) -> bool:
	if event_id.is_empty() or not event_id.is_valid_filename() or event_id.contains("/") \
			or event_id.contains("\\"):
		return false
	var path := ProjectSettings.globalize_path(_directory().path_join(event_id + ".json"))
	return DirAccess.remove_absolute(path) == OK


static func find_pending_profile(field: String, value: String) -> Dictionary:
	var needle := value.strip_edges().to_lower()
	if needle.is_empty():
		return {}
	var matches: Dictionary = {}
	for event in pending():
		if String(event.get("kind", "")) not in ["profile", "completed_round"]:
			continue
		var record: Dictionary = event["data"]
		var candidate := String(record.get("student_name" if field == "name" else "student_id", "")).strip_edges().to_lower()
		if candidate == needle:
			matches[String(record["student_id"])] = record
	return (matches.values()[0] as Dictionary).duplicate(true) if matches.size() == 1 else {}
