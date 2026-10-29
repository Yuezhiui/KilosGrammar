extends SceneTree
## No-socket release regression: a score ACK arriving after the first
## Leaderboard query must refresh the already-visible scoreboard. All durable
## data is isolated from the real classroom recovery outbox and PostgreSQL.
const MENU := "res://ui/main_menu/main_menu.tscn"
const FAKE_MENU := "res://tools/test_postgres_main_menu.gd"
const RECOVERY := preload("res://ui/database/recovery_journal.gd")
var menu: Control
var client: Node
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	ProjectSettings.set_setting("kilos/recovery_test_directory",
		"user://test_recovery_release_board_%d_%d" % [
			OS.get_process_id(), Time.get_ticks_usec()])
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load(MENU) as PackedScene
	var fixture := load(FAKE_MENU) as Script
	_check(packed != null and fixture != null, "Real menu and mock subclass load")
	if packed == null or fixture == null:
		_finish()
		return
	menu = packed.instantiate() as Control
	menu.set_script(fixture)
	root.add_child(menu)
	await process_frame
	client = menu.get("database_client") as Node
	_check(client != null and client.get_child_count() == 0, "Transport cannot create HTTP socket")
	_check(bool(client.call("reply", "health", {"ok": true, "data": {"database": "connected"}}, "startup")),
		"Simulated service is online")
	_check(RECOVERY.pending().is_empty(), "No prior test or classroom recovery events visible")

	# An existing verified student can have a profile without any score
	# (historical import/registration); opening leaderboard cannot invent data.
	menu.set("session_state", {
		"student_id": "QA-BOARD-RETURN", "student_name": "Test Returning Student",
		"grade_section": "Grade 3 - QA", "student_lookup_connected": true,
		"entry_source": "play", "guided_tutorial": false,
		"game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy",
		"activity": "Catch the Word",
	})
	menu.set("current_route", "gameplay")
	menu.call("_on_panel_requested", "results", {
		"round_completed": true, "completion_reason": "manual", "time_remaining": 0.0,
		"activity": "Catch the Word", "game_mode": "Seconds", "score": 111,
	})
	await process_frame
	_check(RECOVERY.pending().is_empty() and int(client.call("count", "complete_round")) == 0,
		"Historical profile + interrupted game produces no completed score")

	# A later legitimately finished game produces one immutable score journal
	# event, then the HTTP mock holds its ACK while Leaderboard first loads.
	menu.set("current_route", "gameplay")
	menu.call("_on_panel_requested", "results", {
		"round_completed": true, "completion_reason": "time_up", "time_remaining": 0.0,
		"activity": "Catch the Word", "game_mode": "Seconds", "score": 428,
	})
	await process_frame
	_check(RECOVERY.pending().size() == 1
		and int(client.call("count", "complete_round")) == 1,
		"Finished game creates one durable event and one queued save request")
	var pending: Dictionary = client.call("find_pending", "complete_round", "recovery_replay")
	_check(String(pending.get("args", {}).get("student_id", "")) == "QA-BOARD-RETURN"
		and int(pending.get("args", {}).get("score", -1)) == 428,
		"Only finished score targets verified returning student")

	menu.call("_on_panel_requested", "leaderboard", {})
	await process_frame
	var board := menu.get("active_panel") as Control
	_check(String(menu.get("current_route")) == "leaderboard" and board != null,
		"Student leaderboard is visible while last score ACK is outstanding")
	var first_fetches := int(client.call("count", "get_leaderboard"))
	_check(first_fetches == 1, "Visible scoreboard reads actual backend query")
	_check(bool(client.call("reply", "get_leaderboard", {
		"ok": true, "data": {"leaderboard": []},
	}, "leaderboard")), "Backend initially returns no scores before ACK")
	_check((board.get_node("%ScoreRows") as VBoxContainer).get_child_count() == 0,
		"No completed scores label reflects actual empty backend response")

	_check(bool(client.call("reply", "complete_round", {
		"ok": true, "data": {"score": {"score": 428}, "recovery_pending": false},
	}, "recovery_replay")), "Late completed-score ACK is delivered with Leaderboard open")
	await process_frame
	_check(RECOVERY.pending().is_empty(), "ACK removes durable score only after success")
	_check(int(client.call("count", "get_leaderboard")) == first_fetches + 1,
		"Completed-score ACK refreshes currently visible leaderboard without reopening")
	_check(bool(client.call("reply", "get_leaderboard", {
		"ok": true, "data": {"leaderboard": [{
			"student_id": "QA-BOARD-RETURN", "student_name": "Test Returning Student",
			"grade_section": "Grade 3 - QA", "minigame": "Catch the Word",
			"game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy",
			"score": 428,
		}]},
	}, "leaderboard")), "Post-save refresh reads confirmed score from mocked backend")
	await process_frame
	_check((board.get_node("%ScoreRows") as VBoxContainer).get_child_count() == 1,
		"Newly finished result appears on screen without leaving Leaderboard")
	var rows: Array = board.get("_all_rows") as Array
	_check(rows.size() == 1 and int(rows[0].get("score", -1)) == 428,
		"Leaderboard displays exact saved score from server")
	_check(int(client.call("count", "complete_round")) == 1
		and int(client.call("count", "register_student")) == 0,
		"Refresh never duplicates score or registers a preexisting student")

	# Returning to Play for another completed round must never leave the
	# first score permanently displayed. Simulate an OLD leaderboard GET
	# arriving after the new score and a newer GET were both acknowledged.
	menu.call("_return_to_main")
	await process_frame
	menu.set("session_state", {
		"student_id": "QA-BOARD-RETURN", "student_name": "Test Returning Student",
		"grade_section": "Grade 3 - QA", "student_lookup_connected": true,
		"entry_source": "play", "guided_tutorial": false,
		"game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy",
		"activity": "Catch the Word",
	})
	menu.set("current_route", "gameplay")
	menu.call("_on_panel_requested", "results", {
		"round_completed": true, "completion_reason": "time_up", "time_remaining": 0.0,
		"activity": "Catch the Word", "game_mode": "Seconds", "score": 501,
	})
	await process_frame
	_check(RECOVERY.pending().size() == 1
		and int(client.call("count", "complete_round")) == 2,
		"Same returning student completes a distinct second round without duplicate submission")
	menu.call("_on_panel_requested", "leaderboard", {})
	await process_frame
	board = menu.get("active_panel") as Control
	var old_fetch: Dictionary = client.call("find_pending", "get_leaderboard", "leaderboard")
	_check(not old_fetch.is_empty(), "Reopening leaderboard starts a new query before second ACK")
	_check(bool(client.call("reply", "complete_round", {
		"ok": true, "data": {"score": {"score": 501}, "recovery_pending": false},
	}, "recovery_replay")), "Second completed score receives backend acceptance")
	await process_frame
	var fresh_fetch: Dictionary = client.call("find_pending", "get_leaderboard", "leaderboard")
	_check(not fresh_fetch.is_empty()
		and int(fresh_fetch.get("context", {}).get("request_id", -1)) > int(old_fetch.get("context", {}).get("request_id", -1)),
		"Accepted second round supersedes in-flight old leaderboard query")
	_check(bool(client.call("reply", "get_leaderboard", {
		"ok": true, "data": {"leaderboard": [{
			"student_id": "QA-BOARD-RETURN", "student_name": "Test Returning Student",
			"grade_section": "Grade 3 - QA", "minigame": "Catch the Word",
			"game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy",
			"score": 501,
		}]},
	}, "leaderboard")), "Latest leaderboard query returns second completed round")
	await process_frame
	rows = board.get("_all_rows") as Array
	_check(rows.size() == 1 and int(rows[0].get("score", -1)) == 501,
		"Repeated completed score replaces older displayed score")
	_check(bool(client.call("reply", "get_leaderboard", {
		"ok": true, "data": {"leaderboard": [{
			"student_id": "QA-BOARD-RETURN", "student_name": "Test Returning Student",
			"grade_section": "Grade 3 - QA", "minigame": "Catch the Word",
			"game_style": "Noun", "game_mode": "Seconds", "difficulty": "Easy",
			"score": 428,
		}]},
	}, "leaderboard")), "Late older leaderboard query is delivered")
	await process_frame
	rows = board.get("_all_rows") as Array
	_check(rows.size() == 1 and int(rows[0].get("score", -1)) == 501
		and RECOVERY.pending().is_empty()
		and int(client.call("count", "complete_round")) == 2
		and int(client.call("count", "register_student")) == 0,
		"Stale callback cannot roll back displayed score, create duplicate or re-register student")
	menu.queue_free()
	await process_frame
	_finish()


func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures.append(reason)
		printerr("RELEASE BOARD FAIL: " + reason)


func _finish() -> void:
	print("RELEASE SCOREBOARD REFRESH: %s | checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	ProjectSettings.set_setting("kilos/recovery_test_directory", "")
	quit(0 if failures.is_empty() else 1)
