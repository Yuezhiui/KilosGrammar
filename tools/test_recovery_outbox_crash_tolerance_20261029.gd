extends SceneTree
## Crash between fsync and rename, malformed JSON safety and exact replay.
## ALWAYS isolated from actual classroom data, even if run in GUI mode.
const JOURNAL := preload("res://ui/database/recovery_journal.gd")
var checks := 0
var failures: Array[String] = []
var qa_directory := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	qa_directory = "user://test_recovery_atomic_" + str(Time.get_ticks_usec())
	ProjectSettings.set_setting("kilos/recovery_test_directory", qa_directory)
	var sid := "QA-CRASH-" + str(Time.get_ticks_usec())
	var profile: Dictionary = JOURNAL.enqueue_profile(sid, "Crash Test Child", "Grade 4 - Hope")
	_check(bool(profile.get("ok", false)), "atomic profile commit succeeds")
	var first: Array[Dictionary] = JOURNAL.pending()
	_check(first.size() == 1, "committed profile appears in queue")
	if first.size() != 1:
		_finish()
		return
	var event_id := String(profile.get("id", ""))
	var committed_path := ProjectSettings.globalize_path(qa_directory.path_join(event_id + ".json"))
	var staged_path := committed_path + ".tmp"
	_check(DirAccess.rename_absolute(committed_path, staged_path) == OK,
		"simulate process crash after fsync, before rename")
	_check(not FileAccess.file_exists(committed_path) and FileAccess.file_exists(staged_path),
		"only staged event survives the simulated crash")
	var recovered: Array[Dictionary] = JOURNAL.pending()
	_check(recovered.size() == 1 and String(recovered[0].get("id", "")) == event_id,
		"next startup promotes complete staging file without losing identity")
	_check(FileAccess.file_exists(committed_path) and not FileAccess.file_exists(staged_path),
		"recovered event now has committed .json extension")
	_check(String(JOURNAL.find_pending_profile("id", sid).get("student_name", "")) == "Crash Test Child",
		"exact student ID remains readable after staging replay")
	var broken_path := ProjectSettings.globalize_path(qa_directory.path_join("corrupt-preserved.json"))
	var broken := FileAccess.open(broken_path, FileAccess.WRITE)
	_check(broken != null, "fixture can prepare malformed JSON")
	if broken != null:
		broken.store_string("{ incomplete")
		broken.flush()
		broken.close()
	var with_corruption: Array[Dictionary] = JOURNAL.pending()
	_check(with_corruption.size() == 1, "malformed event never becomes a false replay")
	_check(FileAccess.file_exists(broken_path), "corrupt event is retained for teacher recovery, not deleted")
	var score: Dictionary = JOURNAL.enqueue_score(sid, "Noun", "Seconds", "Easy",
		"Catch the Word", 321)
	_check(bool(score.get("ok", false)), "new valid score is not blocked by a corrupt older file")
	var after: Array[Dictionary] = JOURNAL.pending()
	_check(after.size() == 2 and String(after[0].get("kind", "")) == "profile"
		and String(after[1].get("kind", "")) == "score",
		"other valid profile and score still replay in chronological order")
	_check(JOURNAL.acknowledge(event_id), "only confirmed profile acknowledged")
	_check(JOURNAL.acknowledge(String(score.get("id", ""))), "only confirmed score acknowledged")
	_check(JOURNAL.pending().is_empty() and FileAccess.file_exists(broken_path),
		"acknowledging valid events never destroys the malformed evidence")
	# Cleanup ONLY the fixture's deliberately malformed test data.
	_check(DirAccess.remove_absolute(broken_path) == OK, "fixture removes only its own synthetic corrupt file")
	_finish()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _finish() -> void:
	print("RECOVERY CRASH TOLERANCE: %s | checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for reason in failures:
		printerr("RECOVERY CRASH FAIL: " + reason)
	ProjectSettings.set_setting("kilos/recovery_test_directory", "")
	quit(0 if failures.is_empty() else 1)
