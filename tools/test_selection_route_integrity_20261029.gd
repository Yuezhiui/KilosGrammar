extends SceneTree

# QA ONLY (2026-10-29): all 180 selection combinations, 5 source grammar
# categories, and scene/button signal routing. NO webcam or database calls.
# IMPORTANT: a true camera-calibration SUCCESS cannot be asserted here.
# We inspect the calibration scene without set_context(), then mount the real
# gameplay wrapper with an explicitly unverified, synthetic handoff.
const GrammarBank = preload("res://ui/minigames/shared/grammar_bank.gd")
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const LEVELS := ["Easy", "Normal", "Hard"]
const MODES := ["Seconds", "Lives"]
const GAMES := ["Catch the Word", "Human Plane", "Balloon Popping"]
const RESULT_BANNERS := {
	"Catch the Word": ["GameOverBannerCatch", "game_over_catch_the_word.png"],
	"Human Plane": ["GameOverBannerPlane", "game_over_human_plane.png"],
	"Balloon Popping": ["GameOverBannerBalloon", "game_over_balloon_popping.png"],
}
const FLOWS := ["Play", "Guided"]
const SCENES := {
	"student_setup": "res://ui/student/setup/student_setup.tscn",
	"play_activity": "res://ui/play/activity/play_activity.tscn",
	"tutorial_home": "res://ui/tutorial/tutorial_home.tscn",
	"calibration": "res://ui/vision/calibration/calibration.tscn",
	"gameplay": "res://ui/play/gameplay/gameplay.tscn",
	"results": "res://ui/secondary/results/results.tscn",
}

var failures: Array[String] = []
var inspected_combinations := 0
var inspected_bank_rounds := 0
var inspected_in_game_rounds := 0
var forced_results_routes := 0
var actual_buttons_emitted := 0
var unverified_handoffs := 0
var signal_log: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _capture(target: String, payload: Dictionary) -> void:
	signal_log.append({"target": target, "payload": payload.duplicate(true)})


func _press(node: Button, label: String) -> bool:
	if node == null:
		_fail("%s missing Button" % label)
		return false
	if node.disabled:
		_fail("%s is disabled" % label)
		return false
	actual_buttons_emitted += 1
	node.pressed.emit()
	return true


func _latest(expected: String, label: String) -> Dictionary:
	if signal_log.is_empty():
		_fail("%s did not emit requested(%s, payload)" % [label, expected])
		return {}
	var last: Dictionary = signal_log.back()
	if String(last.get("target", "")) != expected:
		_fail("%s route expected %s, got %s" % [label, expected, last.get("target", "")])
		return {}
	return (last.get("payload", {}) as Dictionary).duplicate(true)


func _instantiate(path: String) -> Control:
	var packed := load(path) as PackedScene
	if packed == null:
		_fail("PackedScene missing: %s" % path)
		return null
	var scene := packed.instantiate() as Control
	if scene == null:
		_fail("Not a Control: %s" % path)
	return scene


func _run() -> void:
	root.size = Vector2i(1280, 720)
	print("QA_DIAGNOSTIC PoseServiceAutoload=%s registered=%s" % [
		str(ProjectSettings.has_setting("autoload/PoseService")),
		str(root.get_node_or_null("PoseService") != null)])
	# Main menu is intentionally NOT instantiated: its _ready starts database,
	# title audio and an intro. Routing source is audited separately, while
	# these fixtures exercise real Student/Chooser/Guided button connections.
	for route in SCENES:
		_expect(ResourceLoader.exists(SCENES[route]), "Scene missing: %s" % SCENES[route])
	var setup := _instantiate(SCENES["student_setup"])
	var chooser := _instantiate(SCENES["play_activity"])
	var guided_home := _instantiate(SCENES["tutorial_home"])
	var calibration := _instantiate(SCENES["calibration"])
	if setup == null or chooser == null or guided_home == null or calibration == null:
		_end()
		return
	for panel in [setup, chooser, guided_home, calibration]:
		panel.visible = false
		root.add_child(panel)
		if panel.has_signal("requested"):
			panel.requested.connect(_capture)
	# Calibration _ready() only builds and binds artwork; intentionally NEVER
	# call calibration.set_context(), which invokes _try_start_camera().
	calibration.set_process(false)
	_expect(calibration.get_node_or_null("TutorialStage/CameraArea/LiveCameraInset") != null,
		"Calibration scene lacks authored camera inset")
	_expect(calibration.get_node_or_null("TutorialStage/Navigation/BackButton") is Button,
		"Calibration scene lacks authored Back button")
	_check_grammar_bank()
	for flow in FLOWS:
		for topic in TOPICS:
			for difficulty in LEVELS:
				for mode in MODES:
					for activity in GAMES:
						var label := "%s/%s/%s/%s/%s" % [flow, activity, topic, difficulty, mode]
						signal_log.clear()
						var selected := {}
						if flow == "Guided":
							guided_home.call("set_context", {})
							_press(guided_home.get_node_or_null("TutorialStage/StartButton") as Button,
								label + " tutorial Start")
							var tutorial_payload := _latest("play_activity", label + " tutorial Start")
							chooser.context.clear()
							chooser.call("set_context", tutorial_payload)
							_press(chooser.activity_buttons.get(activity) as Button,
								label + " activity")
							_press(chooser.next_button as Button, label + " chooser Next")
							var guided_setup_payload := _latest("student_setup", label + " chooser Next")
							_expect(bool(guided_setup_payload.get("guided_tutorial", false)),
								label + " lost guided_tutorial before Student Setup")
							_expect(String(guided_setup_payload.get("activity", "")) == activity,
								label + " chooser did not retain activity")
							setup.call("set_context", guided_setup_payload)
							selected = _complete_student_form(setup, label, topic, difficulty, mode)
						else:
							setup.call("set_context", {"entry_source": "play"})
							var play_setup_payload := _complete_student_form(setup, label, topic, difficulty, mode)
							_expect(String(_last_target()) == "play_activity",
								label + " Play StudentSetup did not lead to chooser")
							chooser.context.clear()
							chooser.call("set_context", play_setup_payload)
							_press(chooser.activity_buttons.get(activity) as Button,
								label + " activity")
							_press(chooser.next_button as Button, label + " chooser Next")
							selected = _latest("calibration", label + " chooser Next")
						_check_selection(selected, flow, activity, topic, difficulty, mode, label)
						# Direct context assignment is diagnostic only, not a valid
						# calibration success or a camera/pose observation.
						calibration.context = selected.duplicate(true)
						var expected_order := ["CENTER"] if activity == "Human Plane" else (
							["LEFT", "CENTER", "RIGHT"] if activity == "Balloon Popping" else ["CENTER", "RIGHT", "LEFT"])
						_expect(calibration.call("_capture_order") == expected_order,
							label + " calibration stage order incorrect")
						# This fixture explicitly does not pretend that a pose
						# was measured or that physical calibration completed.
						var fixture := selected.duplicate(true)
						fixture["camera_live"] = false
						fixture["calibration_measured"] = false
						fixture["start_countdown"] = false
						fixture["unverified_qa_handoff"] = true
						unverified_handoffs += 1
						await _inspect_wrapper_and_results(fixture, flow, activity, topic, difficulty, mode, label)
						inspected_combinations += 1
	await process_frame
	for panel in [setup, chooser, guided_home, calibration]:
		if is_instance_valid(panel):
			panel.queue_free()
	await process_frame
	_end()


func _complete_student_form(setup: Control, label: String, topic: String, difficulty: String, mode: String) -> Dictionary:
	(setup.get("_student_id_edit") as LineEdit).text = "QA-ONLY-TEST"
	(setup.get("_name_edit") as LineEdit).text = "Test Student"
	(setup.get("_grade_edit") as LineEdit).text = "Grade 5"
	_press(setup.get("_style_buttons")[topic] as Button, label + " topic")
	_press(setup.get("_mode_buttons")[mode] as Button, label + " mode")
	_press(setup.get("_difficulty_buttons")[difficulty] as Button, label + " difficulty")
	_press(setup.get("_continue_button") as Button, label + " Continue")
	var target := "calibration" if bool(setup.context.get("guided_tutorial", false)) else "play_activity"
	return _latest(target, label + " Student Continue")


func _last_target() -> String:
	return String(signal_log.back().get("target", "")) if not signal_log.is_empty() else ""


func _check_selection(values: Dictionary, flow: String, activity: String, topic: String,
		difficulty: String, mode: String, label: String) -> void:
	for key in ["activity", "topic", "game_style", "difficulty", "game_mode"]:
		var expected: String = String({"activity": activity, "topic": topic,
			"game_style": topic, "difficulty": difficulty, "game_mode": mode}[key])
		_expect(String(values.get(key, "")) == expected,
			"%s lost %s: expected %s, got %s" % [label, key, expected, values.get(key, "")])
	var guided := flow == "Guided"
	_expect(bool(values.get("guided_tutorial", false)) == guided, label + " guided flag incorrect")
	_expect(String(values.get("entry_source", "")) == ("tutorial" if guided else "play"),
		label + " entry_source incorrect")
	_expect(bool(values.get("camera_requested", false)), label + " did not request calibration camera")
	_expect(not bool(values.get("keyboard_mode", true)), label + " selected keyboard bypass")


func _inspect_wrapper_and_results(fixture: Dictionary, flow: String, activity: String,
		topic: String, difficulty: String, mode: String, label: String) -> void:
	var wrapper := _instantiate(SCENES["gameplay"])
	if wrapper == null:
		return
	if not wrapper.has_method("set_context"):
		_fail("%s gameplay.tscn failed to load its gameplay.gd script" % label)
		wrapper.free()
		return
	# Set context BEFORE adding the actual PackedScene, avoiding a blank initial
	# mount; game starts without a live camera. No fake calibration success.
	wrapper.call("set_context", fixture)
	root.add_child(wrapper)
	var mini := wrapper.get("active_game") as Control
	_expect(is_instance_valid(mini), label + " gameplay wrapper did not mount minigame")
	if is_instance_valid(mini):
		var gameplay_payload := wrapper.call("get_context") as Dictionary
		_expect(String(mini.scene_file_path) == String(wrapper.GAME_SCENES[activity]),
			label + " wrong minigame scene mounted: %s" % mini.scene_file_path)
		_check_selection(gameplay_payload, flow, activity, topic, difficulty, mode, label + " minigame")
		_check_minigame_generated_words(mini, activity, topic, difficulty, label)
		# This is a ROUTING fixture, not a claim of actual elapsed classroom
		# time or genuine student mistakes. Balloon now correctly rejects any
		# early _finish_round() call, so supply the *explicit terminal state*
		# required by the chosen mode before invoking its real Results path.
		# Separate balloon gameplay suites drive actual timer/miss mechanics.
		if activity == "Balloon Popping":
			if mode == "Seconds":
				mini.set("time_remaining", 0.0)
			else:
				mini.set("hearts", 0)
		wrapper.requested.connect(_capture)
		var before_finish := signal_log.size()
		mini.call("_finish_round")
		_expect(signal_log.size() > before_finish,
			label + " actual minigame finish did not emit wrapper Results route")
		if signal_log.size() > before_finish and _last_target() == "results":
			forced_results_routes += 1
		var report := _latest("results", label + " wrapper result") if signal_log.size() > before_finish else gameplay_payload.duplicate(true)
		_check_selection(report, flow, activity, topic, difficulty, mode, label + " result payload")
		_expect(bool(report.get("round_completed", false)), label + " forced minigame finish did not mark completed")
		# Only the display fixture's score is synthetic; never claim an earned
		# physical score or completed YOLO capture.
		report["score"] = 800
		report["score_saved"] = false
		report["database_connected"] = false
		var result_scene := _instantiate(SCENES["results"])
		if result_scene != null:
			root.add_child(result_scene)
			result_scene.call("set_context", report)
			_check_result_banner_identity(result_scene, report, activity, label)
			var expected := {"topic": topic, "game_mode": mode, "difficulty": difficulty}
			for key in expected:
				var path: String = {"topic": "%GameStyleValue", "game_mode": "%GameModeValue",
					"difficulty": "%DifficultyValue"}[key]
				var field := result_scene.get_node_or_null(path) as Label
				_expect(field != null, label + " results missing %s" % key)
				if field != null:
					_expect(field.text == String(expected[key]),
						label + " Results displays wrong %s: %s" % [key, field.text])
			_expect(result_scene.get_node_or_null("%SaveStatus") == null,
				label + " results contain no redundant save-status label")
			if flow == "Guided":
				_expect(bool(report.get("guided_tutorial", false)),
					label + " guided results retain practice-only routing")
			result_scene.queue_free()
	wrapper.queue_free()
	await process_frame


func _check_result_banner_identity(result_scene: Control, actual_payload: Dictionary,
		expected_game: String, label: String) -> void:
	# This assertion starts at the REAL minigame _finish_round -> gameplay
	# wrapper requested("results", payload), not a synthetic Results-only input.
	_expect(String(actual_payload.get("activity", "")) == expected_game,
		label + " minigame emitted wrong results activity")
	var banners_visible := 0
	for game in RESULT_BANNERS:
		var ref: Array = RESULT_BANNERS[game]
		var banner := result_scene.find_child(String(ref[0]), true, false) as TextureRect
		_expect(banner != null and banner.texture != null,
			label + " missing " + game + " banner image")
		if banner == null or banner.texture == null:
			continue
		_expect(String(banner.texture.resource_path).ends_with(String(ref[1])),
			label + " " + game + " banner has wrong artwork")
		if banner.is_visible_in_tree():
			banners_visible += 1
		_expect(banner.is_visible_in_tree() == (game == expected_game),
			label + " WRONG RESULTS BANNER: expected " + expected_game + " while checking " + game)
	_expect(banners_visible == 1, label + " must show EXACTLY ONE game-over banner")
	_expect(result_scene.get_node_or_null("%GameOverFallback") == null
		and result_scene.get_node_or_null("%ActivityValue") == null,
		label + " Results has no redundant generic/activity labels")
	var displayed_score := result_scene.get_node_or_null("%ScoreValue") as Label
	_expect(displayed_score != null and displayed_score.text == str(actual_payload.get("score", "")),
		label + " Results score does not match emitted game score")


func _check_minigame_generated_words(mini: Control, activity: String, topic: String,
		difficulty: String, label: String) -> void:
	var generated := {}
	match activity:
		"Catch the Word":
			var apple_words: Array = mini.call("_pick_unused_wave_words", 1)
			var correct: Array[int] = [1]
			generated = {"options": apple_words, "valid_indices": correct}
		"Balloon Popping":
			generated = mini.call("_request_round_data")
		"Human Plane":
			generated = mini.call("_make_lane_round")
	var words: Array = generated.get("options", [])
	var indices: Array = generated.get("valid_indices", [])
	_expect(words.size() == 3, label + " actual in-game generator has no complete three-word set")
	if words.size() != 3:
		return
	var observed_indices: Array[int] = []
	var used := {}
	for index in range(3):
		var word := String(words[index]).strip_edges().to_lower()
		_expect(not used.has(word), label + " duplicate generated game word: %s" % word)
		used[word] = true
		var correct := GrammarBank.is_matching(word, topic)
		if correct:
			observed_indices.append(index)
		var owner := ""
		for candidate_topic in TOPICS:
			if GrammarBank.is_matching(word, candidate_topic):
				_expect(owner.is_empty(), label + " word belongs to more than one grammar category: " + word)
				owner = candidate_topic
		_expect(not owner.is_empty(), label + " generated word missing from shared grammar source: " + word)
		if GrammarBank.TIER_RANGES.has(owner):
			var limits: Vector2i = GrammarBank.TIER_RANGES[owner][difficulty]
			var tier: Array = GrammarBank.WORD_BANK[owner].slice(limits.x, limits.y)
			_expect(tier.has(word), label + " generated incorrect %s tier %s" % [difficulty, word])
	_expect(observed_indices == indices,
		label + " actual game declared wrong source-grammar answers: %s vs %s" % [indices, observed_indices])
	inspected_in_game_rounds += 1


func _check_grammar_bank() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261029
	var all_seen := {}
	for topic in TOPICS:
		for value in GrammarBank.WORD_BANK[topic]:
			var word := String(value).to_lower()
			_expect(not all_seen.has(word), "Duplicate word across source categories: %s" % word)
			all_seen[word] = topic
	for topic in TOPICS:
		for level in LEVELS:
			for _index in range(8):
				var fresh: Dictionary = GrammarBank.lane_round(topic, level, rng)
				var options: Array = fresh.get("options", [])
				var valid: Array = fresh.get("valid_indices", [])
				_expect(String(fresh.get("topic", "")) == topic, "%s/%s bank topic changed" % [topic, level])
				_expect(options.size() == 3, "%s/%s bank did not issue three options" % [topic, level])
				if options.size() != 3:
					continue
				var unique := {}
				var true_indices: Array[int] = []
				for i in range(options.size()):
					var word := String(options[i])
					_expect(not unique.has(word), "%s/%s duplicate within round: %s" % [topic, level, word])
					unique[word] = true
					var is_correct := GrammarBank.is_matching(word, topic)
					_expect(all_seen.get(word, "") != "", "Unknown bank word: %s" % word)
					if is_correct:
						true_indices.append(i)
						_expect(all_seen[word] == topic, "%s falsely correct for %s" % [word, topic])
					else:
						_expect(all_seen[word] != topic, "%s falsely distractor for %s" % [word, topic])
					if GrammarBank.TIER_RANGES.has(all_seen.get(word, "")):
						var owner := String(all_seen[word])
						var bounds: Vector2i = GrammarBank.TIER_RANGES[owner][level]
						var source_words: Array = GrammarBank.WORD_BANK[owner].slice(bounds.x, bounds.y)
						_expect(source_words.has(word), "%s/%s wrongly sourced %s-tier %s" % [topic, level, level, word])
					elif is_correct and (topic == "Adverb" or topic == "Pronoun"):
						_expect(not GrammarBank.TIER_RANGES.has(topic), "%s incorrectly assigned level tier" % topic)
				_expect(true_indices == valid, "%s/%s truth vs valid indices wrong: %s / %s" % [topic, level, true_indices, valid])
				_expect(not valid.is_empty(), "%s/%s no correct answers" % [topic, level])
				inspected_bank_rounds += 1
	_expect(not GrammarBank.TIER_RANGES.has("Pronoun") and not GrammarBank.TIER_RANGES.has("Adverb"),
		"Pronoun and Adverb expected shared difficulty pools; update QA if product design changes")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _fail(message: String) -> void:
	if failures.size() < 90:
		failures.append(message)


func _end() -> void:
	print("QA_SUMMARY combinations=%d source_bank_rounds=%d game_generated_rounds=%d forced_game_to_results_routes=%d button_pressed_signals=%d unverified_camera_handoffs=%d failures=%d" %
		[inspected_combinations, inspected_bank_rounds, inspected_in_game_rounds,
		forced_results_routes, actual_buttons_emitted, unverified_handoffs, failures.size()])
	print("QA_SCOPE: Real StudentSetup/Chooser/TutorialHome Button.pressed, actual in-game grammar generators, forced real game->wrapper Results signals, and authored Results UI were exercised.")
	print("QA_LIMIT: Calibration was instantiated/read-only; no webcam, source-auth pose, physical success, main-menu DB routing, real score, or physical game completion was exercised.")
	if failures.is_empty():
		print("PASS selection route integrity (scene/button fixture; NOT physical end-to-end)")
		quit(0)
	else:
		for issue in failures:
			push_error("QA_FAIL " + issue)
		quit(1)
