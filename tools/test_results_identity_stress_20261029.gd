extends SceneTree

# QA ONLY: Results game identity stress regression. Never invokes camera, DB,
# gameplay, or an actual app navigation. Does not modify project assets.
# Godot 4.7.2:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
#     --script res://tools/test_results_identity_stress_20261029.gd
#
# Deterministic 3,456 context switches (3 viewports x 2 modes x 3 starting
# games x 192 updates), 216 Results scene recreations, 6,912 button events.
# Includes invalid/missing activity, input/output deep-copy tests and fallback.

const SCENE_PATH := "res://ui/secondary/results/results.tscn"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const MODES := ["Seconds", "Lives"]
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const SCORES := [0, 199, 499, 500, 780, 900, 1250]
const GAMES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const BANNER_NAMES := ["%GameOverBannerCatch", "%GameOverBannerBalloon", "%GameOverBannerPlane"]
const BANNER_PATHS := [
	"res://Components/Results/Redesign/Assets/game_over_catch_the_word.png",
	"res://Components/Results/Redesign/Assets/game_over_balloon_popping.png",
	"res://Components/Results/Redesign/Assets/game_over_human_plane.png",
]
const STEPS_PER_SCENARIO := 192
const RECREATE_EVERY := 16
const FIRST_FAILURES_TO_PRINT := 35
const FIRST_FAILURES_TO_KEEP := 60

var packed: PackedScene
var checks := 0
var failed := 0
var failed_banner := 0
var failed_context := 0
var failed_routes := 0
var failed_other := 0
var first_failures: Array[String] = []
var scenarios := 0
var transitions := 0
var scenes_created := 0
var routes_checked := 0
var activities_seen := {}
var mode_counts := {}
var viewport_counts := {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline_root_children := root.get_child_count()
	var baseline_audio_players := _count_audio_players(root)
	packed = load(SCENE_PATH) as PackedScene
	_expect(packed != null, "Results scene loads", "other")
	for i in range(GAMES.size()):
		_expect(ResourceLoader.exists(BANNER_PATHS[i]),
			"Expected game banner asset imported: " + BANNER_PATHS[i], "banner")
	if packed == null:
		_finish()
		return
	for viewport_size in SIZES:
		var viewport := SubViewport.new()
		viewport.name = "ResultsIdentityStressViewport"
		viewport.disable_3d = true
		viewport.size = viewport_size
		root.add_child(viewport)
		await process_frame
		for mode_index in range(MODES.size()):
			for start_index in range(GAMES.size()):
				await _run_scenario(viewport, viewport_size, mode_index, start_index)
		viewport.queue_free()
		await process_frame
	await _multi_instance_isolation()
	await _repeat_navigation_voice_stop()
	for unused_frame in range(4):
		await process_frame
	# AudioStreamMP3 decoding and playback cleanup also uses an audio mixing
	# thread. Do not immediately destroy the SceneTree after releasing a voice:
	# allow that thread to retire its final playback resource first.
	await create_timer(0.75).timeout
	_expect(root.get_child_count() == baseline_root_children,
		"Stress fixture leaves no extra root nodes", "other")
	_expect(_count_audio_players(root) == baseline_audio_players,
		"Stress fixture leaves no extra audio players", "other")
	_finish()


func _run_scenario(viewport: SubViewport, size: Vector2i,
		mode_index: int, start_index: int) -> void:
	scenarios += 1
	var results: Control = null
	var request_log: Array[Dictionary] = []
	var previous_game := ""
	for step in range(STEPS_PER_SCENARIO):
		var serial := (scenarios - 1) * STEPS_PER_SCENARIO + step
		var expected := _make_context(serial, step, start_index, mode_index)
		var input_context := expected.duplicate(true)
		var create_again := results == null or step % RECREATE_EVERY == 0
		if create_again:
			if results != null:
				await _release_results(results, "recreation step=%d" % step)
			results = packed.instantiate() as Control
			_expect(results != null, "Results instance created serial=%d" % serial, "other")
			if results == null:
				break
			scenes_created += 1
			request_log.clear()
			results.requested.connect(func(target: String, payload: Dictionary) -> void:
				request_log.append({"target": target, "payload": payload})
			)
			# Both documented entrypoints: context before _ready or after _ready.
			if scenes_created % 2 == 0:
				results.set_context(input_context)
			viewport.add_child(results)
			results.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			if scenes_created % 2 != 0:
				results.set_context(input_context)
			await process_frame
			_expect(results.size.distance_to(Vector2(size)) <= 2.0,
				"Results viewport mismatch at serial=%d size=%s" % [serial, size], "other")
		else:
			results.set_context(input_context)
			# Reusing the same Results panel can start Catch encouragement on
			# this very update. Allow the MP3 playback to enter AudioServer's
			# mixing cycle before the immediate Retry/Main stress clicks stop it.
			var newly_playing := results.get_node_or_null("LowScoreVoicePlayer") as AudioStreamPlayer
			if newly_playing != null and newly_playing.playing:
				await process_frame
				await process_frame

		# Attack the caller's own object after set_context. Nothing displayed
		# or emitted by the scene should now contain the injected values.
		input_context["activity"] = "MUTATED BY CALLER"
		input_context["student_name"] = "MUTATED STUDENT"
		input_context["score"] = -999
		input_context["nested"]["identity"]["key"] = "MUTATED NESTED"
		input_context["nested"]["history"][0] = "MUTATED ARRAY"
		var expected_activity: String = String(expected.get("activity", "")).strip_edges()
		var case_label := "serial=%d %s/%s start=%s actual=%s previous=%s" % [
			serial, size, MODES[mode_index], GAMES[start_index],
			expected_activity, previous_game,
		]
		_verify_identity(results, expected_activity, case_label)
		_verify_data(results, expected, case_label)
		_verify_routes(results, expected, request_log, case_label)
		# The navigation callback cannot mutate the scene's saved context.
		_verify_identity(results, expected_activity, case_label + " after navigation")
		_verify_data(results, expected, case_label + " after navigation")
		previous_game = expected_activity
		transitions += 1
		var activity_bucket := expected_activity if GAMES.has(expected_activity) else (
			"<missing/empty>" if expected_activity.is_empty() else "<unknown>")
		activities_seen[activity_bucket] = int(activities_seen.get(activity_bucket, 0)) + 1
		var actual_mode := String(expected.get("game_mode", ""))
		mode_counts[actual_mode] = int(mode_counts.get(actual_mode, 0)) + 1
		var size_name := "%dx%d" % [size.x, size.y]
		viewport_counts[size_name] = int(viewport_counts.get(size_name, 0)) + 1
	if results != null and is_instance_valid(results):
		await _release_results(results, "scenario last instance")
	print("RESULTS IDENTITY SCENARIO %02d | %s | initial mode=%s | start=%s | %d updates" %
		[scenarios, size, MODES[mode_index], GAMES[start_index], STEPS_PER_SCENARIO])


func _make_context(serial: int, step: int,
		start_index: int, mode_index: int) -> Dictionary:
	# Every ordinary consecutive context switches game. Interrupted cases
	# introduce invalid/missing values and must clear the prior game banner.
	var activity: String = GAMES[(step + start_index) % GAMES.size()]
	var mode: String = MODES[(step + mode_index) % MODES.size()]
	var payload := {
		"activity": activity,
		"game_mode": mode,
		"score": SCORES[serial % SCORES.size()],
		"student_id": "STRESS-%05d" % serial,
		"student_name": "Student %05d" % serial,
		"grade_section": "Grade %d - Section %d" % [1 + serial % 6, serial % 9],
		"game_style": TOPICS[serial % TOPICS.size()],
		"topic": TOPICS[serial % TOPICS.size()],
		"difficulty": DIFFICULTIES[serial % DIFFICULTIES.size()],
		"round_completed": serial % 7 != 0,
		"completion_reason": "timeout" if mode == "Seconds" else "lives_exhausted",
		"entry_source": "tutorial" if serial % 13 == 0 else "play",
		"guided_tutorial": serial % 13 == 0,
		"nested": {
			"identity": {"key": "K-%05d" % serial, "source": activity},
			"history": ["FIRST-%d" % serial, activity, mode],
		},
	}
	# Deterministic independent edge cases for stale-row and stale-banner data.
	if step % 23 == 0:
		payload.erase("activity")
	elif step % 19 == 0:
		payload["activity"] = "Unknown Arcade %d" % serial
	elif step % 17 == 0:
		payload["activity"] = ""
	if step % 11 == 0:
		payload.erase("student_id")
	if step % 13 == 0:
		payload.erase("student_name")
	if step % 29 == 0:
		payload.erase("grade_section")
	if step % 31 == 0:
		payload.erase("game_style")
		payload.erase("topic")
	if step % 37 == 0:
		payload.erase("difficulty")
	if step % 41 == 0:
		payload.erase("game_mode")
	if step % 43 == 0:
		payload.erase("score")
		payload["points"] = 333 + serial
	if step % 47 == 0:
		payload.erase("score")
		payload.erase("points")
	return payload


func _verify_identity(scene: Control, activity: String, label: String) -> void:
	var active_index := GAMES.find(activity)
	var visible_count := 0
	for i in range(BANNER_NAMES.size()):
		var banner := scene.get_node_or_null(BANNER_NAMES[i]) as TextureRect
		_expect(banner != null,
			label + ": game banner node missing " + BANNER_NAMES[i], "banner")
		if banner == null:
			continue
		_expect(banner.texture != null and
			String(banner.texture.resource_path) == BANNER_PATHS[i],
			label + ": incorrect texture on " + BANNER_NAMES[i], "banner")
		var is_visible := banner.visible and banner.is_visible_in_tree()
		if is_visible:
			visible_count += 1
		_expect(is_visible == (i == active_index),
			label + ": %s banner %s, expected %s" %
				[GAMES[i], "visible" if is_visible else "hidden",
					"visible" if i == active_index else "hidden"], "banner")
	_expect(visible_count == (1 if active_index >= 0 else 0),
		label + ": exactly one correct banner visible, found %d" % visible_count, "banner")
	_expect(scene.get_node_or_null("%GameOverFallback") == null
		and scene.get_node_or_null("%ActivityValue") == null,
		label + ": removed duplicate fallback/activity title labels", "banner")


func _verify_data(scene: Control, payload: Dictionary, label: String) -> void:
	var fields := {
		"%StudentIdValue": _first_text(payload, ["student_id", "studentId", "id"]),
		"%StudentNameValue": _first_text(payload, ["student_name", "name"]),
		"%GradeValue": _first_text(payload, ["grade", "grade_section", "section"]),
		"%GameStyleValue": _first_text(payload, ["game_style", "topic", "style"]),
		"%GameModeValue": _first_text(payload, ["game_mode", "mode"]),
		"%DifficultyValue": _first_text(payload, ["difficulty"]),
		"%ScoreValue": _first_text(payload, ["score", "points"]),
	}
	var row_map := {
		"%StudentIdValue": "%StudentIdRow",
		"%StudentNameValue": "%StudentNameRow",
		"%GradeValue": "%GradeRow",
		"%GameStyleValue": "%GameStyleRow",
		"%GameModeValue": "%GameModeRow",
		"%DifficultyValue": "%DifficultyRow",
	}
	for path in fields:
		var field := scene.get_node_or_null(path) as Label
		_expect(field != null, label + ": missing data node " + path, "context")
		if field == null:
			continue
		_expect(field.text == fields[path],
			label + ": stale " + path + " expected '%s' got '%s'" %
				[fields[path], field.text], "context")
		if row_map.has(path):
			var row := scene.get_node_or_null(row_map[path]) as Control
			_expect(row != null and row.visible == not String(fields[path]).is_empty(),
				label + ": stale row visibility " + row_map[path], "context")
	var student_card := scene.get_node_or_null("%StudentCard") as Control
	_expect(student_card != null and student_card.visible == (
		not String(fields["%StudentIdValue"]).is_empty() or
		not String(fields["%StudentNameValue"]).is_empty() or
		not String(fields["%GradeValue"]).is_empty()
	), label + ": stale StudentCard visibility", "context")
	var game_card := scene.get_node_or_null("%GameCard") as Control
	_expect(game_card != null and game_card.visible == (
		not String(fields["%GameStyleValue"]).is_empty() or
		not String(fields["%GameModeValue"]).is_empty() or
		not String(fields["%DifficultyValue"]).is_empty()
	), label + ": stale GameCard visibility", "context")
	var score_card := scene.get_node_or_null("%ScoreCard") as Control
	_expect(score_card != null and score_card.visible ==
		not String(fields["%ScoreValue"]).is_empty(),
		label + ": stale ScoreCard visibility", "context")
	_expect(scene.get("_context") == payload,
		label + ": internal context changed or retained previous payload", "context")


func _first_text(payload: Dictionary, keys: Array) -> String:
	for key in keys:
		if payload.has(key):
			var candidate := str(payload[key]).strip_edges()
			if not candidate.is_empty():
				return candidate
	return ""


func _verify_routes(scene: Control, payload: Dictionary,
		request_log: Array[Dictionary], label: String) -> void:
	var retry := scene.get_node_or_null("%RetryButton") as BaseButton
	var main := scene.get_node_or_null("%MainButton") as BaseButton
	_expect(retry != null and main != null,
		label + ": retry/main buttons present", "routes")
	if retry == null or main == null:
		return
	var before := request_log.size()
	retry.pressed.emit()
	_expect(request_log.size() == before + 1,
		label + ": Retry must emit exactly once", "routes")
	if request_log.size() != before + 1:
		return
	var first := request_log[before]
	_expect(first["target"] == "student_setup",
		label + ": Retry target leaks or changed", "routes")
	_expect(first["payload"] == payload,
		label + ": Retry emits stale/wrong context", "routes")
	routes_checked += 1
	# Mutating one emitted payload MUST NOT affect source, subsequent Main
	# payload, or the displayed Results scene.
	var first_payload: Dictionary = first["payload"]
	first_payload["activity"] = "CORRUPTED RETRY OUTPUT"
	first_payload["student_name"] = "CORRUPTED RETRY STUDENT"
	first_payload["nested"]["identity"]["key"] = "CORRUPTED ROUTE NESTED"
	first_payload["nested"]["history"][0] = "CORRUPTED ROUTE ARRAY"
	main.pressed.emit()
	_expect(request_log.size() == before + 2,
		label + ": Main must emit exactly once", "routes")
	if request_log.size() == before + 2:
		var second := request_log[before + 1]
		_expect(second["target"] == "main",
			label + ": Main target leaks or changed", "routes")
		_expect(second["payload"] == payload,
			label + ": Main inherited corrupted Retry context", "routes")
		_expect(second["payload"] != first_payload,
			label + ": Retry and Main share mutable payload", "routes")
		routes_checked += 1
	_expect(scene.get("_context") == payload,
		label + ": Retry/Main modified current scene context", "routes")


func _multi_instance_isolation() -> void:
	# Simultaneously mounted panels must each own their banner visibility,
	# not accidentally share global/static game identity.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.disable_3d = true
	root.add_child(viewport)
	var mounted: Array[Control] = []
	for i in range(GAMES.size()):
		var panel := packed.instantiate() as Control
		panel.set_context({
			"activity": GAMES[i], "score": 800 + i,
			"student_id": "ISOLATION-%d" % i, "game_mode": MODES[i % 2],
		})
		viewport.add_child(panel)
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mounted.append(panel)
		scenes_created += 1
	await process_frame
	for i in range(GAMES.size()):
		_verify_identity(mounted[i], GAMES[i], "simultaneous scene " + GAMES[i])
		var score := mounted[i].get_node_or_null("%ScoreValue") as Label
		_expect(score != null and score.text == str(800 + i),
			"simultaneous scene score leaks between games", "context")
	for panel in mounted:
		_stop_all_audio(panel)
		panel.queue_free()
	await process_frame
	await process_frame
	for panel in mounted:
		_expect(not is_instance_valid(panel), "simultaneous scene fully freed", "other")
	viewport.queue_free()
	await process_frame


func _repeat_navigation_voice_stop() -> void:
	# Auditable Catch-only cue cleanup on actual buttons; no external route.
	for target in ["%RetryButton", "%MainButton"]:
		var scene := packed.instantiate() as Control
		root.add_child(scene)
		scenes_created += 1
		scene.set_context({
			"activity": "Catch the Word", "game_mode": "Lives",
			"score": 199, "round_completed": true,
		})
		# Give AudioServer one mixing boundary after starting the MP3 before
		# simulating immediate navigation. A play()+stop() in the same frame
		# intermittently leaves AudioStreamPlaybackMP3 referenced at engine exit.
		await process_frame
		await process_frame
		var voice := scene.get_node_or_null("LowScoreVoicePlayer") as AudioStreamPlayer
		_expect(voice != null and voice.playing,
			target + ": low-score Catch Results voice starts", "routes")
		var button := scene.get_node_or_null(target) as BaseButton
		_expect(button != null, target + ": navigation button exists", "routes")
		if button != null:
			button.pressed.emit()
			_expect(voice == null or not voice.playing,
				target + ": leaving Results must stop Catch voice", "routes")
		await _release_results(scene, target + " voice cleanup")


func _release_results(scene: Control, label: String) -> void:
	if not is_instance_valid(scene):
		return
	var former_parent := scene.get_parent()
	_stop_all_audio(scene)
	scene.queue_free()
	await process_frame
	await process_frame
	_expect(not is_instance_valid(scene), label + ": scene fully freed", "other")
	if is_instance_valid(former_parent):
		for child in former_parent.get_children():
			_expect(child.name != "Results", label + ": no orphan Results child", "other")


func _stop_all_audio(node: Node) -> void:
	if node is AudioStreamPlayer:
		var player := node as AudioStreamPlayer
		player.stop()
		player.stream = null
	for child in node.get_children():
		_stop_all_audio(child)


func _count_audio_players(node: Node) -> int:
	var count := 1 if node is AudioStreamPlayer else 0
	for child in node.get_children():
		count += _count_audio_players(child)
	return count


func _expect(condition: bool, message: String, category: String) -> void:
	checks += 1
	if condition:
		return
	failed += 1
	match category:
		"banner": failed_banner += 1
		"context": failed_context += 1
		"routes": failed_routes += 1
		_: failed_other += 1
	if failed <= FIRST_FAILURES_TO_KEEP:
		first_failures.append("[%s] %s" % [category, message])
	if failed <= FIRST_FAILURES_TO_PRINT:
		printerr("RESULTS IDENTITY STRESS FAIL: [%s] %s" % [category, message])


func _finish() -> void:
	print("RESULTS IDENTITY STRESS: %s" % ("PASS" if failed == 0 else "FAIL"))
	print("  scenarios=%d transitions=%d scene_instances=%d routes=%d assertions=%d" %
		[scenarios, transitions, scenes_created, routes_checked, checks])
	print("  deterministic_pattern=20261029 viewport_counts=%s mode_counts=%s" %
		[str(viewport_counts), str(mode_counts)])
	print("  activity_counts=%s" % str(activities_seen))
	print("  failures=%d banner=%d context=%d routes=%d other=%d" %
		[failed, failed_banner, failed_context, failed_routes, failed_other])
	if failed > FIRST_FAILURES_TO_PRINT:
		print("  First %d of %d failures printed above. Sample follows:" %
			[FIRST_FAILURES_TO_PRINT, failed])
		for i in range(FIRST_FAILURES_TO_PRINT, first_failures.size()):
			print("  " + first_failures[i])
	quit(0 if failed == 0 else 1)
