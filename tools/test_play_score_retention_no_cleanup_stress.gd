extends SceneTree

## Real MainMenu completed-Play retention, using an in-memory no-socket DB mock
## and a uniquely isolated on-disk recovery journal. Never touches the user's
## existing scores, profile, production PostgreSQL or classroom recovery outbox.
## Godot --headless --path . --script res://tools/test_play_score_retention_no_cleanup_stress.gd
const MENU := "res://ui/main_menu/main_menu.tscn"
const FIXTURE := "res://tools/test_postgres_csv_delete_menu_fixture.gd"
const JOURNAL := preload("res://ui/database/recovery_journal.gd")
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const MODES := ["Seconds", "Lives"]
const STUDENT_ID := "QA-VERIFIED-ONLY"
var checks := 0
var failures: Array[String] = []
var app: Control
var mock: Node
var saved_scores := 0
var storage_prefix := ""
var acknowledged_event_ids: Dictionary = {}


func _initialize() -> void:
	# MUST precede load(MENU) and scene mounting. The recovery journal refuses
	# live-user directories whenever this test_recovery_ override is present.
	storage_prefix = "user://test_recovery_score_retention_%d_%d" % [
		OS.get_process_id(), Time.get_ticks_usec()]
	ProjectSettings.set_setting("kilos/recovery_test_directory", storage_prefix)
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(19.0).timeout
	_check(false, "No-socket score retention fixture timed out")
	quit(1)


func _run() -> void:
	root.size = Vector2i(1280, 720)
	_check(String(ProjectSettings.get_setting("kilos/recovery_test_directory", "")) == storage_prefix
		and storage_prefix.begins_with("user://test_recovery_"),
		"Unique isolated recovery directory is installed before any scene import")
	_check(JOURNAL.pending().is_empty(), "Isolated recovery journal initially contains no scores")
	var menu := load(MENU) as PackedScene
	var fixture := load(FIXTURE) as Script
	_check(menu != null and fixture != null and fixture.can_instantiate(),
		"MainMenu and no-socket test-only subclass parse")
	if menu == null or fixture == null or not fixture.can_instantiate():
		_finish()
		return
	app = menu.instantiate() as Control
	app.set_script(fixture)
	root.add_child(app)
	await process_frame
	mock = app.get("database_client") as Node
	_check(mock != null and mock.has_method("count") and mock.get_child_count() == 0,
		"DB mock cannot spawn PostgreSQL process or HTTP socket")
	if mock == null:
		_finish()
		return
	_check(JOURNAL.pending().is_empty(), "Opening Menu cannot read a previous classroom recovery event")
	# All combinations of three games, both finish modes and three separate
	# completed rounds. Every genuine completion enqueues one durable score
	# event before asynchronous HTTP; acknowledgement removes only that event.
	for repeated_round in range(3):
		for activity in ACTIVITIES:
			for mode in MODES:
				await _completed_round(activity, mode, repeated_round)
	_check(mock.call("count", "complete_round") == 18,
		"All 18 distinct finished Play rounds submitted once via recovery replay")
	_check(_no_database_mutation(), "18 completed rounds never delete/import/register another student")
	_check(JOURNAL.pending().is_empty(), "All 18 acknowledged scores leave no queued event")

	# A manual exit must NEVER save, even with an inflated score and apparently
	# expired timer / zero hearts. Also reject false end evidence.
	for mode in MODES:
		for activity in ACTIVITIES:
			var interrupted := _play_context(activity, mode)
			interrupted["score"] = 4999
			interrupted["round_completed"] = true
			interrupted["completion_reason"] = "manual"
			interrupted["time_remaining"] = 0.0
			interrupted["lives"] = 0
			await _expect_no_save(interrupted, "Manual abort in %s / %s is not completed" % [activity, mode])
			var not_finished := _finished_payload(activity, mode, 4000)
			if mode == "Seconds":
				not_finished["time_remaining"] = 15.0
			else:
				not_finished["lives"] = 1
			await _expect_no_save(not_finished, "Non-exhausted %s / %s cannot be saved" % [activity, mode])
			var no_completion := _finished_payload(activity, mode, 3999)
			no_completion["round_completed"] = false
			await _expect_no_save(no_completion, "Uncompleted %s / %s cannot be saved" % [activity, mode])
	_check(mock.call("count", "complete_round") == 18
		and JOURNAL.pending().is_empty(), "All 18 manual/unfinished cases leave complete history untouched")

	# A truly completed offline round MUST be durable on disk without claiming
	# a server save. It replays when the mocked service reconnects.
	app.set("database_online", false)
	var before_offline := int(mock.call("count", "complete_round"))
	app.set("session_state", _play_context("Balloon Popping", "Seconds"))
	app.set("current_route", "gameplay")
	var interrupted_offline := _finished_payload("Balloon Popping", "Seconds", 899)
	interrupted_offline["completion_reason"] = "manual"
	app.call("_on_panel_requested", "results", interrupted_offline)
	await process_frame
	_check(JOURNAL.pending().is_empty()
		and int(mock.call("count", "complete_round")) == before_offline,
		"Interrupted offline game must not create even an unsent recovery record")
	app.set("session_state", _play_context("Catch the Word", "Seconds"))
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", _finished_payload("Catch the Word", "Seconds", 900))
	await process_frame
	var offline: Array[Dictionary] = JOURNAL.pending()
	_check(offline.size() == 1 and String(offline[0].get("kind", "")) == "score",
		"Valid offline Play completion survives as one durable recovery score event")
	_check(String((offline[0].get("data", {}) as Dictionary).get("minigame", "")) == "Catch the Word"
		and int((offline[0].get("data", {}) as Dictionary).get("score", -1)) == 900,
		"Offline recovery event retains exact minigame, student and score")
	_check(mock.call("count", "complete_round") == 18 and
		not bool((app.get("session_state") as Dictionary).get("score_saved", false))
		and bool((app.get("session_state") as Dictionary).get("recovery_pending", false)),
		"Offline Play is locally pending, not falsely marked saved to PostgreSQL")
	app.set("database_online", true)
	app.call("_flush_recovery_outbox")
	await process_frame
	_check(mock.call("count", "complete_round") == 19,
		"Reconnection replays offline completed round once")
	var retry: Dictionary = mock.call("find_pending", "complete_round", "recovery_replay")
	_check(String((retry.get("args", {}) as Dictionary).get("student_id", "")) == STUDENT_ID
		and int((retry.get("args", {}) as Dictionary).get("score", -1)) == 900,
		"Offline replay retains original student ID and score")
	_check(bool(mock.call("reply", "complete_round", {
		"ok": true, "status": 201, "data": {"score": {"score": 900}, "recovery_pending": false},
	}, "recovery_replay")), "Backend mock acknowledges recovered offline score")
	await process_frame
	_check(JOURNAL.pending().is_empty() and
		bool((app.get("session_state") as Dictionary).get("score_saved", false)),
		"Server acceptance acknowledges offline score and clears only its outbox event")
	_check(_no_database_mutation(), "Offline completion/replay never deletes or registers data")

	# Tutorial's authentic finish evidence must still be ignored, even if the
	# caller forges a verified student lookup and repeats the activity.
	for activity in ACTIVITIES:
		for mode in MODES:
			var context := _play_context(activity, mode)
			context["entry_source"] = "tutorial"
			context["guided_tutorial"] = true
			app.set("database_online", true)
			app.set("session_state", context)
			app.set("current_route", "gameplay")
			app.call("_on_panel_requested", "results", _finished_payload(activity, mode, 9000))
			await process_frame
			_check(mock.call("count", "complete_round") == 19 and JOURNAL.pending().is_empty()
				and not bool((app.get("session_state") as Dictionary).get("score_saved", false)),
				"Tutorial %s / %s is never stored despite authentic terminal evidence" % [activity, mode])
	_check(_no_database_mutation(), "No automatic cleanup, purge, import or registration after any round")
	app.queue_free()
	await process_frame
	await process_frame
	_finish()


func _play_context(activity: String, mode: String) -> Dictionary:
	return {
		"entry_source": "play", "guided_tutorial": false,
		"student_id": STUDENT_ID, "student_lookup_connected": true,
		"student_name": "Mock Student", "grade_section": "Grade 4 - Test",
		"activity": activity, "game_mode": mode,
		"game_style": "Noun", "difficulty": "Easy",
	}


func _finished_payload(activity: String, mode: String, score: int) -> Dictionary:
	var evidence := {
		"round_completed": true, "activity": activity, "game_mode": mode,
		"score": score,
	}
	if mode == "Seconds":
		evidence["completion_reason"] = "time_up"
		evidence["time_remaining"] = 0.0
	else:
		evidence["completion_reason"] = "lives_empty"
		evidence["lives"] = 0
	return evidence


func _completed_round(activity: String, mode: String, repeated_round: int) -> void:
	var score := 100 + 100 * repeated_round
	var previous_count := int(mock.call("count", "complete_round"))
	app.set("database_online", true)
	app.set("session_state", _play_context(activity, mode))
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", _finished_payload(activity, mode, score))
	var events: Array[Dictionary] = JOURNAL.pending()
	var event_id := String(events[0].get("id", "")) if events.size() == 1 else ""
	_check(events.size() == 1 and String(events[0].get("kind", "")) == "score",
		"%s / %s round %d commits exactly one score on disk before HTTP" % [
			activity, mode, repeated_round + 1])
	_check(not event_id.is_empty() and not acknowledged_event_ids.has(event_id),
		"Every independently completed round receives a fresh immutable journal ID")
	if not event_id.is_empty():
		acknowledged_event_ids[event_id] = true
	if events.size() == 1:
		var data: Dictionary = events[0].get("data", {})
		_check(String(data.get("student_id", "")) == STUDENT_ID
			and String(data.get("game_mode", "")) == mode
			and String(data.get("minigame", "")) == activity
			and int(data.get("score", -1)) == score,
			"Durable event retains exact student, game, mode and completed score")
	else:
		_check(false, "Finished round has an inspectable recovery event")
	_check(not bool((app.get("session_state") as Dictionary).get("score_saved", false)),
		"Score is NOT marked saved before server acknowledgement")
	await process_frame
	saved_scores += 1
	_check(int(mock.call("count", "complete_round")) == previous_count + 1
		and int(mock.call("count", "complete_round")) == saved_scores,
		"Exactly one asynchronous score replay requested per completed round")
	var request: Dictionary = mock.call("find_pending", "complete_round", "recovery_replay")
	var args: Dictionary = request.get("args", {})
	var info: Dictionary = request.get("context", {})
	_check(not request.is_empty() and String(args.get("student_id", "")) == STUDENT_ID
		and String(args.get("game_mode", "")) == mode
		and int(args.get("score", -1)) == score
		and String(info.get("minigame", "")) == activity
		and String(info.get("recovery_event_id", "")) == event_id,
		"Score-only recovery replay preserves activity, event ID and score")
	_check(bool(mock.call("reply", "complete_round", {
		"ok": true, "status": 201, "data": {
			"score": {"score": score}, "recovery_pending": false},
	}, "recovery_replay")), "One mocked completed-score acknowledgement accepted")
	await process_frame
	_check(JOURNAL.pending().is_empty()
		and bool((app.get("session_state") as Dictionary).get("score_saved", false))
		and not bool((app.get("session_state") as Dictionary).get("recovery_pending", true)),
		"Acknowledged score becomes saved and only its own journal event clears")
	_check(int(mock.call("count", "complete_round")) == saved_scores
		and _no_database_mutation(),
		"Completed Play save never duplicates, deletes, imports or registers")
	app.call("_flush_recovery_outbox")
	await process_frame
	_check(JOURNAL.pending().is_empty()
		and int(mock.call("count", "complete_round")) == saved_scores,
		"Repeated recovery flush after acknowledgement never saves same round twice")


func _expect_no_save(evidence: Dictionary, description: String) -> void:
	var original_mode := String(evidence.get("game_mode", ""))
	var original_activity := String(evidence.get("activity", ""))
	var previous_count := int(mock.call("count", "complete_round"))
	app.set("database_online", true)
	app.set("session_state", _play_context(original_activity, original_mode))
	app.set("current_route", "gameplay")
	app.call("_on_panel_requested", "results", evidence)
	await process_frame
	_check(int(mock.call("count", "complete_round")) == previous_count
		and JOURNAL.pending().is_empty()
		and not bool((app.get("session_state") as Dictionary).get("score_saved", false)),
		description)


func _no_database_mutation() -> bool:
	return int(mock.call("count", "register_student")) == 0 \
		and int(mock.call("count", "delete_all_data")) == 0 \
		and int(mock.call("count", "delete_data")) == 0 \
		and int(mock.call("count", "import_data_csv")) == 0 \
		and int(mock.call("count", "request_delete_all_challenge")) == 0


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("SCORE RETENTION QA FAIL: ", description)


func _finish() -> void:
	print("PLAY COMPLETED SCORE RETENTION (NO DB): %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	ProjectSettings.set_setting("kilos/recovery_test_directory", "")
	quit(0 if failures.is_empty() else 1)
