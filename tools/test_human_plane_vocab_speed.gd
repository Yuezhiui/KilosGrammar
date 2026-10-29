extends SceneTree

# Run: Godot --headless --path . --script res://tools/test_human_plane_vocab_speed.gd
# Covers real GrammarBank integration without modifying game source or other tests.
const PLANE := preload("res://ui/minigames/human_plane/human_plane.tscn")
const BANK := preload("res://ui/minigames/shared/grammar_bank.gd")
const TOPICS := ["Noun", "Verb", "Adjective"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const SPEEDS := {"Easy": 0.20, "Normal": 0.27, "Hard": 0.34}
const WAVES := {"Easy": 12, "Normal": 14, "Hard": 16}
# Long enough to consume every genuine matching tier in all three expanded
# topics and therefore prove real GrammarBank cycle rollover in BOTH modes.
const CROSS_CYCLE_WAVES := 105

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for topic in TOPICS:
		for difficulty in DIFFICULTIES:
			for mode in ["Seconds", "Lives"]:
				await _check_session(topic, difficulty, mode)
	await _check_short_fallback_exhaustion()
	await _check_long_word_render_fit()
	await _check_seconds_rebuild_from_pause()
	_check(float(SPEEDS["Hard"]) > float(SPEEDS["Normal"]) and float(SPEEDS["Normal"]) > float(SPEEDS["Easy"]), "gate speeds strictly increase with difficulty")
	print("HUMAN PLANE VOCAB/SPEED: ", "PASS" if failures.is_empty() else "FAIL", " (", checks, " checks, ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)


func _check_session(topic: String, difficulty: String, mode: String) -> void:
	var label := "%s %s %s" % [topic, difficulty, mode]
	var game := PLANE.instantiate() as Control
	if game == null or not game.has_method("set_context"):
		_check(false, label + " Human Plane gameplay script failed to load")
		if game != null:
			game.free()
		return
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {"activity": "Human Plane", "topic": topic, "difficulty": difficulty, "game_mode": mode})
	await process_frame
	await process_frame
	game.set_process(false)
	var bank := game.get("grammar_bank") as Script
	_check(bank != null and bank.has_method("lane_round"), label + " shared GrammarBank loaded")
	_check(int(game.get("waves_total")) == int(WAVES[difficulty]), label + " preserves wave count")
	_check(int(game.get("lives")) == 3, label + " 3 hearts in Seconds/Lives on every difficulty")
	_check(is_zero_approx(float(game.get("time_remaining"))) if mode == "Lives" else float(game.get("time_remaining")) > 59.0, label + " preserves selected timing rule")
	var seen := {}
	var cycle_seen := {}
	var cycle_carried := {}
	var last_presented := {}
	var previous_cycle := int(game.get("_vocabulary_cycle"))
	var rollover_count := 0
	var expected_count := int(WAVES[difficulty])
	# Start includes the initial wave in `_ensure_started`. Continue through a
	# full original set and past actual source-bank depletion, bypassing ONLY
	# collision/timer while inspecting generated vocabulary. Repetition is legal
	# across cycles, NEVER within the same independently tracked cycle.
	for wave in range(CROSS_CYCLE_WAVES):
		if wave > 0:
			game.set("waves_completed", wave)
			game.call("_start_wave")
		var cycle := int(game.get("_vocabulary_cycle"))
		_check(cycle >= previous_cycle and cycle <= previous_cycle + 1,
			label + " wave %d advances at most one genuine vocabulary cycle" % [wave + 1])
		if cycle != previous_cycle:
			rollover_count += 1
			cycle_seen.clear()
			cycle_carried = last_presented.duplicate(true)
			_check((game.get("used_round_words") as Dictionary).size() >= cycle_carried.size(),
				label + " cycle boundary retains only genuine previous-trio exclusions")
		var data := game.get("round_data") as Dictionary
		var options: Array = data.get("options", [])
		_check(options.size() == 3, label + " wave %d has three displayed words" % [wave + 1])
		if options.size() != 3:
			break
		var valid: Array = data.get("valid_indices", [])
		_check(valid.size() in [1, 2], label + " wave %d contains valid answer indices" % [wave + 1])
		var current_trio := {}
		for index in range(options.size()):
			var word := String(options[index]).strip_edges().to_lower()
			_check(not word.is_empty(), label + " wave %d word is nonempty" % [wave + 1])
			_check(not cycle_seen.has(word), label + " cycle %d never repeats '%s' at wave %d" % [cycle, word, wave + 1])
			_check(not last_presented.has(word),
				label + " no adjacent duplicate '%s' across normal or cycle boundary" % word)
			_check(not (cycle != previous_cycle and cycle_carried.has(word)),
				label + " new cycle excludes prior visible trio '%s' when bank has options" % word)
			cycle_seen[word] = true
			current_trio[word] = true
			if wave < expected_count:
				_check(not seen.has(word), label + " original %d waves never repeat '%s'" % [expected_count, word])
				seen[word] = true
			if bank != null:
				var matching := bool(bank.call("is_matching", word, topic))
				_check(matching == (index in valid), label + " wave %d '%s' grammar class matches valid lane" % [wave + 1, word])
			# Matching and distractor words from the three expanded topics must
			# actually be drawn from the selected (Easy/Normal/Hard) vocabulary tier.
			for bank_topic in TOPICS:
				if not BANK.WORD_BANK[bank_topic].has(word):
					continue
				var window: Vector2i = BANK.TIER_RANGES[bank_topic][difficulty]
				var tier_pool: Array = BANK.WORD_BANK[bank_topic].slice(window.x, window.y)
				_check(tier_pool.has(word), label + " wave %d '%s' uses correct %s tier" % [wave + 1, word, difficulty])
		var expected_excluded := cycle_carried.duplicate(true)
		for key in cycle_seen:
			expected_excluded[key] = true
		_check((game.get("used_round_words") as Dictionary) == expected_excluded,
			label + " wave %d exclusions equal current-cycle words plus retained previous trio" % [wave + 1])
		_check((game.get("_last_presented_words") as Dictionary) == current_trio,
			label + " latest ACTUALLY displayed trio is tracked, not a prefetched ghost")
		_check(not bool(game.get("_words_exhausted")) and not bool(game.get("finished")),
			label + " cycling source GrammarBank never artificially finishes play")
		_check(int(game.get("score")) == 0 and int(game.get("attempts")) == 0, label + " vocabulary prep does not award score or deduct lives")
		previous_cycle = cycle
		last_presented = current_trio
	_check(seen.size() == expected_count * 3, label + " entire round has %d distinct displayed words" % (expected_count * 3))
	_check(rollover_count >= 1 and not bool(game.get("finished")),
		label + " authentic tier allows at least one full cycle rollover without early Results")
	# Confirm the actual gate velocity instead of just checking a configuration value.
	game.call("_start_wave")
	game.call("_update_gate_wave", 0.5)
	_check(absf(float(game.get("gate_progress")) - float(SPEEDS[difficulty]) * 0.5) < 0.0001, label + " live gate speed matches tier")
	# Defensive rejection of duplicate words and currently excluded words,
	# including case variations. A completed PRIOR cycle may legally repeat.
	_check(not bool(game.call("_round_is_valid", {"prompt": "p", "options": ["Book", "BOOK", "go"], "valid_indices": [0]})), label + " rejects duplicates within one wave")
	var excluded_keys: Array = (game.get("used_round_words") as Dictionary).keys()
	if not excluded_keys.is_empty():
		var excluded := String(excluded_keys[0])
		_check(not bool(game.call("_round_is_valid", {"prompt": "p", "options": [excluded, "freshword1", "freshword2"], "valid_indices": [0]})), label + " rejects word already used in CURRENT cycle or protected trio")
	game.queue_free()
	await process_frame
	await process_frame
	print("Verified vocabulary: ", label, " (", seen.size(), " unique options)")


func _check_short_fallback_exhaustion() -> void:
	# A tiny AUTHORED fallback bank necessarily recycles during a long Lives or
	# Seconds round. Test consecutive REAL source vocabulary generations across
	# multiple complete cycles, then drive actual timed prefetch and promotion.
	# No invented words, no fabricated Results, no weakened grammar validation.
	for mode in ["Seconds", "Lives"]:
		var label := "fallback/%s" % mode
		var game := PLANE.instantiate() as Control
		if game == null or not game.has_method("set_context"):
			_check(false, label + " Human Plane gameplay script failed to load")
			if game != null:
				game.free()
			return
		root.add_child(game)
		game.call("set_context", {"topic": "Pronoun", "difficulty": "Easy", "game_mode": mode})
		await process_frame
		await process_frame
		game.set_process(false)
		# Exercise the genuine fallback generator, not a fabricated round bank.
		game.set("grammar_bank", null)
		game.set("used_round_words", {})
		game.set("_last_presented_words", {})
		var result_events: Array[Dictionary] = []
		game.requested.connect(func(target: String, _payload: Dictionary) -> void:
			if target == "results":
				result_events.append(_payload.duplicate(true)))
		var seen_current := {}
		var previous_visible := {}
		var inherited_words := {}
		var previous_cycle := int(game.get("_vocabulary_cycle"))
		var rollovers := 0
		for wave in range(28):
			game.call("_start_wave")
			var cycle := int(game.get("_vocabulary_cycle"))
			_check(cycle >= previous_cycle and cycle <= previous_cycle + 1,
				label + " wave %d increments cycle only on true source-bank depletion" % [wave + 1])
			if cycle > previous_cycle:
				rollovers += 1
				seen_current.clear()
				inherited_words = previous_visible.duplicate(true)
			var options: Array = (game.get("round_data") as Dictionary).get("options", [])
			_check(options.size() == 3, label + " wave %d always has three real words" % [wave + 1])
			var valid: Array = (game.get("round_data") as Dictionary).get("valid_indices", [])
			_check(valid.size() in [1, 2], label + " wave %d has one/two valid Pronoun lanes" % [wave + 1])
			var current_visible := {}
			for index in range(options.size()):
				var word := String(options[index]).strip_edges().to_lower()
				_check(not seen_current.has(word),
					label + " cycle %d cannot repeat '%s' within its eligible cycle" % [cycle, word])
				_check(not previous_visible.has(word),
					label + " no immediate last-visible-trio repeat '%s' on rollover" % word)
				_check(not (cycle > previous_cycle and inherited_words.has(word)),
					label + " cycle boundary excludes prior displayed '%s' when fallback permits" % word)
				var is_pronoun: bool = word.to_upper() in game.FALLBACK_WORDS["Pronoun"]
				_check(is_pronoun == (index in valid),
					label + " wave %d correct/distractor Pronoun grammar is accurate for '%s'" % [wave + 1, word])
				var authored := false
				for authored_topic in game.FALLBACK_WORDS:
					if word.to_upper() in game.FALLBACK_WORDS[authored_topic]:
						authored = true
				_check(authored, label + " '%s' comes from original fallback grammar words" % word)
				seen_current[word] = true
				current_visible[word] = true
			var expected_excluded := inherited_words.duplicate(true)
			for used in seen_current:
				expected_excluded[used] = true
			_check((game.get("used_round_words") as Dictionary) == expected_excluded,
				label + " exact current cycle + carryover exclusion integrity at wave %d" % [wave + 1])
			_check((game.get("_last_presented_words") as Dictionary) == current_visible,
				label + " only the three ACTUALLY displayed words are the boundary guard")
			_check(not bool(game.get("_words_exhausted")) and not bool(game.get("finished"))
				and result_events.is_empty(),
				label + " real fallback cycles neither stall nor trigger fake Results")
			previous_visible = current_visible
			previous_cycle = cycle
		_check(rollovers >= 2, label + " fallback really replenishes >=2 natural source cycles")
		_check(not bool(game.get("finished")) and result_events.is_empty(),
			label + " cycling vocabulary NEVER ends any still-active game")
		# End-to-end PRELOAD/HANDOFF: the real move progression crosses the
		# scoring line on the actual correct lane, reserves genuine next words,
		# then atomically promotes the same editor-authored queued trio.
		var current_round: Dictionary = (game.get("round_data") as Dictionary).duplicate(true)
		var correct_slots: Array = current_round.get("valid_indices", [])
		_check(not correct_slots.is_empty(), label + " prefetched flight has real correct lane")
		if correct_slots.is_empty():
			game.queue_free()
			await process_frame
			continue
		var centers: PackedFloat32Array = game.call("_normalized_scoring_lane_centers",
			float(game.call("_progress_for_answer_line")))
		_check(centers.size() == 3, label + " real collision-based lane positions are available")
		if centers.size() == 3:
			game.set("plane_x_norm", centers[int(correct_slots[0])])
		var last_current: Dictionary = (game.get("_last_presented_words") as Dictionary).duplicate(true)
		# Latest 3D flight shows the genuine next torus trio BEFORE the current
		# ring hits the airplane. The original collision/scoring line remains
		# authoritative; prefetch must never award points by itself.
		var starting_attempts := int(game.get("attempts"))
		var starting_score := int(game.get("score"))
		var starting_boost := float(game.get("speed_multiplier"))
		var next_round: Dictionary = {}
		for step in range(110):
			game.call("_update_gate_wave", 0.055)
			if not (game.get("next_round_data") as Dictionary).is_empty():
				next_round = (game.get("next_round_data") as Dictionary).duplicate(true)
				break
		_check((next_round.get("options", []) as Array).size() == 3,
			label + " real VISIBLE next torus PREFETCH has three legitimate next words")
		_check((game.get("_last_presented_words") as Dictionary) == last_current,
			label + " next prefetch does not replace the current wave's cycle-boundary guard")
		var upcoming_nodes: Array = game.get("_upcoming_gate_nodes")
		var upcoming_visible := upcoming_nodes.size() == 3
		for lane in range(3):
			if not upcoming_visible:
				break
			var next_control := upcoming_nodes[lane] as Control
			var word_label := next_control.get_node("WordLabel") as Label
			upcoming_visible = (next_control.visible and
				word_label.visible and
				word_label.text == String((next_round.get("options") as Array)[lane]).to_upper())
		_check(upcoming_visible and (upcoming_nodes[0] as Control).get_parent().visible,
			label + " authentic incoming words appear BEFORE first scored collision")
		var prev_used := {}
		for word in current_round.get("options", []):
			prev_used[String(word).to_lower()] = true
		for word in next_round.get("options", []):
			_check(not prev_used.has(String(word).to_lower()),
				label + " prefetched next trio avoids immediate prior-visible word '%s'" % String(word))
		var pending_id := ((game.get("_upcoming_gate_nodes") as Array)[1] as Control).get_instance_id()
		_check(int(game.get("attempts")) == starting_attempts
			and int(game.get("score")) == starting_score
			and is_equal_approx(float(game.get("speed_multiplier")), starting_boost),
			label + " visible next prefetch alone never grants a false score/speed boost")
		for step in range(110):
			if int(game.get("attempts")) > starting_attempts:
				break
			game.call("_update_gate_wave", 0.055)
		_check(int(game.get("attempts")) == starting_attempts + 1
			and int(game.get("score")) == starting_score + 100
			and float(game.get("speed_multiplier")) > starting_boost,
			label + " ONLY actual original answer-line crossing awards +100 and permanent speed")
		for step in range(110):
			game.call("_update_gate_wave", 0.055)
			if int(game.get("waves_completed")) >= 1:
				break
		_check(int(game.get("waves_completed")) == 1
				and int(game.get("attempts")) == starting_attempts + 1,
			label + " natural flight completes first real gate collision exactly once (waves=%d attempts=%d original_attempts=%d)" % [
				int(game.get("waves_completed")), int(game.get("attempts")), starting_attempts])
		_check((game.get("round_data") as Dictionary).get("options", []) == next_round.get("options", [])
			and ((game.get("_gate_nodes") as Array)[1] as Control).get_instance_id() == pending_id,
			label + " queued source-word trio is atomically promoted without replacement")
		_check((game.get("_last_presented_words") as Dictionary).size() == 3,
			label + " actual promotion finally marks the previously hidden trio as visible")
		_check(int(game.get("score")) == starting_score + 100
			and float(game.get("speed_multiplier")) > starting_boost,
			label + " real correct gate scores +100 and permanent earned speed (selected=%d valid=%s score=%d boost=%.3f expected-lane=%d plane=%.3f)" % [
				int(game.get("selected_lane")), correct_slots, int(game.get("score")),
				float(game.get("speed_multiplier")), int(correct_slots[0]), float(game.get("plane_x_norm"))])
		_check(int(game.get("lives")) == 3 and result_events.is_empty(),
			label + " correct prefetch/gate handoff keeps all hearts and never emits Results")
		if mode == "Seconds":
			_check(float(game.get("time_remaining")) > 59.0 and int(game.get("lives")) == 3,
				label + " cycling vocabulary preserves exactly 60s and inert hearts")
			game.call("_process", 59.0)
			_check(not bool(game.get("finished")) and result_events.is_empty()
				and float(game.get("time_remaining")) > 0.0,
				label + " cycling Seconds round remains active before time zero")
			game.call("_process", 1.1)
			_check(bool(game.get("finished")) and is_zero_approx(float(game.get("time_remaining")))
				and result_events.size() == 1 and int(game.get("lives")) == 3,
				label + " cycling Seconds ends EXACTLY once when 60s reaches zero")
		else:
			game.call("_process", 0.10)
			_check(not bool(game.get("finished")) and result_events.is_empty()
				and int(game.get("lives")) == 3 and is_zero_approx(float(game.get("time_remaining"))),
				label + " cycling Lives has no timer or artificial depletion loss")
			game.call("_pause")
			var pause_payload := game.call("get_context") as Dictionary
			_check(int(pause_payload.get("plane_vocabulary_cycle", -1)) >= 2
				and (pause_payload.get("plane_previous_wave_words", []) as Array).size() == 3
				and not bool(pause_payload.get("plane_words_exhausted", true))
				and result_events.is_empty(),
				label + " pause persists real cycle and last visible trio without fake Results")
			game.call("_resume")
			for missed in range(1, 4):
				game.call("_start_wave")
				game.set("plane_x_norm", -10.0) # Actual collision resolver: hit nothing.
				game.call("_resolve_at_answer_line")
				_check(int(game.get("lives")) == 3 - missed
					and bool(game.get("finished")) == (missed == 3)
					and result_events.size() == (1 if missed == 3 else 0),
					label + " miss %d loses 1 life and ends only at EXACTLY 0 hearts" % missed)
		game.call("_process", 1.0)
		_check(result_events.size() == 1,
			label + " only selected true mode ending emits exactly ONE Results event")
		game.queue_free()
		await process_frame
		await process_frame


func _check_long_word_render_fit() -> void:
	var game := PLANE.instantiate() as Control
	if game == null or not game.has_method("_gate_word_fit"):
		_check(false, "Human Plane word-fitting helper failed to load")
		if game != null:
			game.free()
		return
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	for viewport_width in [1280, 1920]:
		var gate_width := float(viewport_width) * 0.09 # narrowest horizon gate
		for word in ["INTERDISCIPLINARY", "MISCHARACTERIZATION", "INCOMPREHENSIBILITY"]:
			var fit := game.call("_gate_word_fit", word, gate_width, 22) as Dictionary
			var effective := float(fit["rendered_width"])
			_check(effective <= gate_width * 0.88 + 0.001, "long word %s fits %.0f-pixel gate header" % [word, gate_width])
			_check(float(fit["scale_x"]) > 0.0 and float(fit["scale_x"]) <= 1.0, "long word '%s' uses valid horizontal fit" % word)
			_check(int(fit["font_size"]) >= 8, "long word '%s' keeps minimum font size" % word)
	game.queue_free()
	await process_frame
	await process_frame


func _check_seconds_rebuild_from_pause() -> void:
	# Legacy pause/rebuild callers may still reconstruct the scene from its
	# payload. The 60s start value must not erase genuine elapsed round time.
	var game := PLANE.instantiate() as Control
	root.add_child(game)
	game.call("set_context", {"topic": "Noun", "difficulty": "Normal", "game_mode": "Seconds", "time_remaining": 21.5})
	await process_frame
	await process_frame
	game.set_process(false)
	var remaining := float(game.get("time_remaining"))
	_check(remaining <= 21.5 and remaining >= 21.2, "restored Seconds clock respects a paused 21.5s payload")
	game.call("_pause")
	var pause_payload := game.call("get_context") as Dictionary
	game.queue_free()
	await process_frame
	await process_frame
	var resumed := PLANE.instantiate() as Control
	root.add_child(resumed)
	resumed.call("set_context", pause_payload)
	await process_frame
	await process_frame
	resumed.set_process(false)
	var resumed_remaining := float(resumed.get("time_remaining"))
	_check(resumed_remaining <= remaining and resumed_remaining >= remaining - 0.2, "recreated Seconds game retains elapsed round time")
	resumed.queue_free()
	await process_frame
	await process_frame


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("FAIL HumanPlane words: ", description)
