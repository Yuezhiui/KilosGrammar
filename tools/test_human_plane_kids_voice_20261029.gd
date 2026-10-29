extends SceneTree

# Actual mounted Human Plane scoring path, native children-recorded WAV playback.
# Real OpenGL audio/display:
#   Godot --path . --rendering-driver opengl3 --script res://tools/test_human_plane_kids_voice_20261029.gd
# Headless validates real event->clip selection but cannot assert audible playback:
#   Godot --headless --path . --script res://tools/test_human_plane_kids_voice_20261029.gd
const SCENE := preload("res://ui/minigames/human_plane/human_plane.tscn")
const VOICES := preload("res://ui/shared/kids_voice_feedback.gd")
const STEP := 1.0 / 60.0
const BUS := "KilosSFX"
const SCENARIOS := ["correct", "wrong", "miss"]

var checks := 0
var failures: Array[String] = []
var native := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	native = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1280, 720)
	if native:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		root.content_scale_size = Vector2i(1280, 720)
	_check(AudioServer.get_bus_index("Master") >= 0, "Godot Master audio bus exists")
	for case_name in SCENARIOS:
		await _exercise(case_name)
	_check(AudioServer.get_bus_index(BUS) >= 0, "GameAudio creates effects bus on scene setup")
	print("HUMAN PLANE KIDS VOICE: %s (%d assertions, %d failures, renderer=%s)" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size(), DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)


func _exercise(case_name: String) -> void:
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity": "Human Plane", "topic": "Noun",
		"difficulty": "Normal", "game_mode": "Seconds"})
	for i in range(4):
		await process_frame
	game.set_process(false)
	var renderer := game.get_node_or_null("HybridFlight3D") as Node2D
	if renderer != null:
		renderer.set_process(false)
	var player := game.get_node_or_null("HumanPlaneVoicePlayer") as AudioStreamPlayer
	_check(player != null, case_name + " live scene creates named voice player")
	if player == null:
		game.queue_free()
		await process_frame
		return
	_check(_player_count(game) == 1, case_name + " exactly one reusable game voice player")
	_check(player.stream == null and not player.playing, case_name + " starts without stale clip")
	_check(player.bus == BUS, case_name + " voice routed through KilosSFX effects bus")
	# Gameplay wrapper calls GameAudio.start_gameplay() at GO. Exercise that
	# same real soundtrack manager, without preloading wrapper/PoseService
	# (unavailable as a global in standalone SceneTree --script tests).
	var music := root.get_node_or_null("KilosGameAudio")
	_check(music != null, case_name + " shared GameAudio manager exists")
	if music != null:
		music.call("stop_gameplay")
		music.call("start_gameplay")
		for _frame in range(3):
			await process_frame
		_check(bool(music.call("is_gameplay_active")),
			case_name + " actual gameplay soundtrack is active alongside child voice")
	var bus_index := AudioServer.get_bus_index(BUS)
	_check(bus_index >= 0 and AudioServer.get_bus_send(bus_index) == "Master",
		case_name + " effects bus sends to audible Master")
	if bus_index >= 0:
		print("VOICE BUS ", case_name, ": muted=", AudioServer.is_bus_mute(bus_index),
			" dB=", AudioServer.get_bus_volume_db(bus_index),
			" MasterMuted=", AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")))
		_check(not AudioServer.is_bus_mute(bus_index)
			and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")),
			case_name + " voice bus and Master are unmuted in QA session")

	var words := game.get("round_data") as Dictionary
	var options := words.get("options", []) as Array
	var valid := words.get("valid_indices", []) as Array
	_check(options.size() == 3 and not valid.is_empty(),
		case_name + " authentic GrammarBank 3-gate question")
	if options.size() != 3 or valid.is_empty():
		game.queue_free()
		await process_frame
		return
	var chosen_lane := -1
	if case_name == "correct":
		chosen_lane = int(valid[0])
	elif case_name == "wrong":
		for lane_index in range(3):
			if not valid.has(lane_index):
				chosen_lane = lane_index
				break
		_check(chosen_lane >= 0, "authentic prompt includes an incorrect distractor")
	if chosen_lane >= 0:
		_place_at_lane(game, chosen_lane)
	else:
		# 0.0 is the authored left flight limit and outside all three projected
		# rings at answer depth. Miss is a real scoring collision miss.
		game.set("plane_x_norm", 0.0)
		game.call("_sync_visuals")
	var projected_lane := int(game.call("_lane_hit_at_answer_line"))
	_check(projected_lane == chosen_lane,
		case_name + " real authored airplane hitbox selects expected gate/miss")

	var start_attempts := int(game.get("attempts"))
	var start_score := int(game.get("score"))
	var active := false
	for tick in range(1500):
		# This is exactly the regular progressive flight-scoring call path, not
		# a direct voice playback or a synthetic _resolve_at_answer_line call.
		game.call("_update_gate_wave", STEP)
		if bool(game.get("gate_resolved")):
			active = true
			break
	_check(active, case_name + " real moving gate crosses physical answer line")
	_check(int(game.get("attempts")) == start_attempts + 1,
		case_name + " scored exactly one hit event")
	_check(int(game.get("selected_lane")) == chosen_lane,
		case_name + " scorer used real gate collision, not injected feedback")
	_check(bool(game.get("selected_was_correct")) == (case_name == "correct"),
		case_name + " real scoring outcome matches expected voice category")
	_check(int(game.get("score")) == start_score + (100 if case_name == "correct" else 0),
		case_name + " correct only awards 100 points")

	var expected_bank := VOICES.CORRECT if case_name == "correct" else (
		VOICES.MISSED if case_name == "miss" else VOICES.ENCOURAGEMENT)
	_check(player.stream is AudioStreamWAV,
		case_name + " score handler loads genuine WAV recording")
	var stream := player.stream as AudioStreamWAV
	var path := stream.resource_path if stream != null else ""
	_check(expected_bank.has(path.get_file()) and
		path.begins_with("res://assets/audio/kids_voice/"),
		case_name + " recorded voice category: " + path)
	_check(stream != null and stream.get_length() > 0.20,
		case_name + " audio stream decodes to nonzero audible duration")
	if stream != null:
		print("VOICE CLIP ", case_name, ": ", path, " length=", stream.get_length(),
			" playing=", player.playing, " playbackPos=", player.get_playback_position())
	if native:
		_check(player.playing, case_name + " genuine display-backed sound player started")
		if music != null:
			var soundtrack := music.get("_music_player") as AudioStreamPlayer
			_check(soundtrack != null and soundtrack.stream is AudioStreamWAV,
				case_name + " shared gameplay soundtrack WAV is loaded")
			print("MUSIC STATE ", case_name, " active=", music.call("is_gameplay_active"),
				" playing=", soundtrack.playing if soundtrack != null else false)
			_check(soundtrack != null and is_equal_approx(soundtrack.volume_db, -11.0),
				case_name + " GameAudio ducks background music by -11 dB for children's voice")
		await process_frame
		await process_frame
		_check(player.playing and player.get_playback_position() >= 0.0,
			case_name + " playback remains active after renderer frames")
		# Audio mixer runs on its own real-time callback. Rendering two frames
		# may be faster than one output buffer, so allow 180 ms for audible mix.
		await create_timer(0.18).timeout
		var peak_bus := AudioServer.get_bus_index(BUS)
		if peak_bus >= 0:
			var peak_left := AudioServer.get_bus_peak_volume_left_db(peak_bus, 0)
			var peak_right := AudioServer.get_bus_peak_volume_right_db(peak_bus, 0)
			if maxf(peak_left, peak_right) < -75.0:
				await create_timer(0.18).timeout
				peak_left = maxf(peak_left, AudioServer.get_bus_peak_volume_left_db(peak_bus, 0))
				peak_right = maxf(peak_right, AudioServer.get_bus_peak_volume_right_db(peak_bus, 0))
			print("VOICE MIX PEAK ", case_name, " left=", peak_left,
				" right=", peak_right, " output_device=", AudioServer.output_device)
			_check(maxf(peak_left, peak_right) > -75.0,
				case_name + " actual non-silent sample energy reaches KilosSFX mix bus")
	else:
		_check(not player.playing, case_name + " headless only loads recording (no playback)")

	# The scoring guard must prevent a second voice trigger while the same
	# gate is already marked resolved. Re-enter real gate updates, no player calls.
	var old_stream := player.stream
	var old_voice_player_id := player.get_instance_id()
	for tick in range(4):
		game.call("_update_gate_wave", STEP)
	_check(int(game.get("attempts")) == start_attempts + 1
		and player.stream == old_stream and player.get_instance_id() == old_voice_player_id,
		case_name + " post-score frames neither repeat sound nor double-score")
	_check(_player_count(game) == 1, case_name + " playback never layers second audio player")

	game.call("_pause")
	_check(player.stream == null and not player.playing,
		case_name + " actual pause stops and releases the phrase")
	if music != null:
		music.call("stop_gameplay")
	game.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(player), case_name + " scene teardown frees voice player")


func _place_at_lane(game: Control, lane: int) -> void:
	var answer_p := float(game.call("_progress_for_answer_line"))
	var centers: PackedFloat32Array = game.call("_normalized_scoring_lane_centers", answer_p)
	_check(centers.size() == 3, "authored lane centers resolve to 3 steering X coordinates")
	if centers.size() == 3:
		game.set("plane_x_norm", centers[lane])
		game.call("_sync_visuals")


func _player_count(host: Node) -> int:
	var result := 0
	for child in host.get_children():
		if child is AudioStreamPlayer:
			result += 1
	return result


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		printerr("HUMAN PLANE VOICE FAIL: " + description)
