extends SceneTree

const JOURNAL: Script = preload("res://ui/database/recovery_journal.gd")
var checks := 0
var failures: Array[String] = []
var created: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := _ids(JOURNAL.pending())
	var nonce := str(Time.get_ticks_usec())
	var sid := "QA-" + nonce
	var first: Dictionary = JOURNAL.enqueue_profile(sid, "Test Student " + nonce, "Grade 4 - Orion")
	_check(bool(first.get("ok", false)), "offline profile write succeeds")
	if bool(first.get("ok", false)):
		created.append(String(first["id"]))
	var second: Dictionary = JOURNAL.enqueue_score(sid, "Noun", "Seconds", "Easy",
		"Catch the Word", 340)
	_check(bool(second.get("ok", false)), "offline completed score write succeeds")
	if bool(second.get("ok", false)):
		created.append(String(second["id"]))
	var after: Array[Dictionary] = JOURNAL.pending()
	_check(after.size() >= original.size() + 2, "reloading from disk contains both events")
	_check(after.any(func(item: Dictionary) -> bool:
		return String(item.get("id", "")) == String(first.get("id", ""))),
		"durable profile has stable ID on reload")
	_check(after.any(func(item: Dictionary) -> bool:
		return String(item.get("id", "")) == String(second.get("id", ""))),
		"durable score has stable ID on reload")
	var by_id: Dictionary = JOURNAL.find_pending_profile("id", sid)
	_check(String(by_id.get("student_id", "")) == sid and String(by_id.get("grade_section", "")) == "Grade 4 - Orion",
		"exact offline ID retrieves only its own matching profile")
	var by_name: Dictionary = JOURNAL.find_pending_profile("name", "TEST STUDENT " + nonce)
	_check(String(by_name.get("student_id", "")) == sid,
		"exact case-insensitive full-name retrieves same profile")
	_check(JOURNAL.find_pending_profile("name", "TEST STUDENT") == {},
		"partial names are never accepted as exact matches")
	_check(not bool(JOURNAL.enqueue_profile("bad/id", "Unsafe", "Grade 5").get("ok", true)),
		"invalid student IDs cannot poison replay queue")
	_check(not bool(JOURNAL.enqueue_score(sid, "Noun", "Seconds", "Easy",
		"UNKNOWN GAME", 100).get("ok", true)),
		"unexpected game cannot enter recovery")
	_check(not JOURNAL.acknowledge("../other"),
		"path traversal cannot delete unrelated files")
	# Complete rounds can be finished rapidly in stress fixtures, including
	# multiple writes inside the same millisecond. Replaying a later score
	# before an earlier one would silently replace the correct final score.
	var burst_ids: Array[String] = []
	for score in range(48):
		var burst: Dictionary = JOURNAL.enqueue_score(sid, "Noun", "Seconds", "Easy",
			"Catch the Word", 1000 + score)
		_check(bool(burst.get("ok", false)), "rapid sequence can persist score " + str(score))
		if bool(burst.get("ok", false)):
			created.append(String(burst["id"]))
			burst_ids.append(String(burst["id"]))
	var ordered_ids: Array[String] = []
	for event in JOURNAL.pending():
		if burst_ids.has(String(event["id"])):
			ordered_ids.append(String(event["id"]))
	_check(ordered_ids == burst_ids,
		"48 rapidly written scores replay in exact original order, not random UUID order")
	var observed_before: int = JOURNAL.pending().size()
	for item_id in created:
		_check(JOURNAL.acknowledge(item_id), "only our acknowledged event is removed")
	_check(JOURNAL.pending().size() == observed_before - created.size(),
		"acknowledged events are removed from durable queue")
	_check(_ids(JOURNAL.pending()) == original,
		"all preexisting unsynced recovery data remained untouched")
	print("RECOVERY OUTBOX: %s | checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for failure in failures:
		printerr("RECOVERY OUTBOX FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)


func _ids(items: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for item in items:
		result.append(String(item.get("id", "")))
	return result


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
