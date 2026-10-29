extends SceneTree

## Godot 4.7.2 regression: Guided Tutorial goes directly from successful
## calibration to the EXISTING 3-2-1 countdown. No spotlight files, scene
## nodes, residual resource UIDs, duplicate GO, webcam, database, or worker.
## --headless --path . --script res://tools/test_spotlight_removal_guided_countdown_20261029.gd
## --rendering-driver opengl3 --path . --script res://tools/test_spotlight_removal_guided_countdown_20261029.gd
const WRAPPER := "res://ui/play/gameplay/gameplay.tscn"
const COUNTDOWN := "res://ui/play/gameplay/guided_countdown.tscn"
const DELETED_SCENE := "res://ui/tutorial/spotlight/spotlight_overlay.tscn"
const DELETED_SCRIPT := "res://ui/tutorial/spotlight/spotlight_overlay.gd"
const DELETED_SCRIPT_UID := "res://ui/tutorial/spotlight/spotlight_overlay.gd.uid"
const SCENE_UID := "uid://djpgqs6cc52xa"
const SCRIPT_UID := "uid://8knh2es2vh24"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const GAMES := [
	{"activity": "Catch the Word", "key": "catch_word",
		"path": "res://ui/minigames/catch_the_word/catch_word.tscn"},
	{"activity": "Balloon Popping", "key": "balloon_popping",
		"path": "res://ui/minigames/balloon_popping/balloon_popping.tscn"},
	{"activity": "Human Plane", "key": "human_plane",
		"path": "res://ui/minigames/human_plane/human_plane.tscn"},
]
const MODES := ["Seconds", "Lives"]
const SNAPSHOT := ["score", "attempts", "correct_count", "hearts", "lives",
	"time_remaining", "round_time_remaining", "round_running", "round_completed",
	"wave_index", "round_finished", "projectile_active", "is_seconds_mode", "is_lives_mode"]
const OLD_NODE_NAMES := ["GuidedSpotlight", "SpotlightOverlay", "DynamicTitle",
	"MovementFeedbackPanel", "MovementHeading", "MovementStatus"]

var checks := 0
var failures: Array[String] = []
var pose: Node
var music: Node
var _started_ms := 0


func _initialize() -> void:
	_started_ms = Time.get_ticks_msec()
	call_deferred("_run")


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "real PoseService singleton exists")
	if pose == null:
		_finish()
		return
	pose.stop_camera()
	pose.set_process(false)
	_check(ResourceLoader.exists(WRAPPER) and ResourceLoader.exists(COUNTDOWN),
		"real gameplay wrapper and 3-2-1 scene remain intact")
	_audit_removed_resources()
	_audit_preserved_english_recordings()
	var wrapper_scene := load(WRAPPER) as PackedScene
	if wrapper_scene == null:
		_check(false, "real gameplay wrapper still loads")
		_cleanup()
		return
	for size in SIZES:
		root.size = size
		root.content_scale_size = size
		for spec in GAMES:
			_audit_game_scene(spec, size)
			for mode in MODES:
				await _check_route(wrapper_scene, size, spec, mode, true)
				await _check_route(wrapper_scene, size, spec, mode, false)
	# Live-camera authorization is verified separately from the no-camera
	# rendering matrix. No mock person is ever treated as production data.
	root.size = SIZES[0]
	root.content_scale_size = SIZES[0]
	for spec in GAMES:
		for mode in MODES:
			await _check_calibrated_camera_gate(wrapper_scene, spec, mode)
	_cleanup()


func _audit_removed_resources() -> void:
	for path in [DELETED_SCENE, DELETED_SCRIPT, DELETED_SCRIPT_UID]:
		_check(not FileAccess.file_exists(path), "deleted spotlight resource absent: " + path)
	var scene_dir := DELETED_SCENE.get_base_dir()
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(scene_dir)):
		var dir := DirAccess.open(scene_dir)
		if dir != null:
			_check(dir.get_files().is_empty() and dir.get_directories().is_empty(),
				"removed spotlight directory contains no orphan feature files")
	# Check production source, including resources outside minigame .tscn.
	# Test tools intentionally still mention former scene names for historical QA.
	for scope in ["res://ui", "res://Components", "res://assets", "res://addons"]:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(scope)):
			_scan_source_tree(scope)
	var project_source := FileAccess.get_file_as_string("res://project.godot")
	_check(not _has_old_resource_ref(project_source),
		"project.godot has no orphan spotlight path or resource UID")


func _scan_source_tree(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		_check(false, "read production folder " + folder)
		return
	for name in dir.get_files():
		var ext := name.get_extension().to_lower()
		if ext not in ["gd", "tscn", "tres", "godot", "uid", "cfg"]:
			continue
		var file_path := folder.path_join(name)
		var source := FileAccess.get_file_as_string(file_path)
		_check(not _has_old_resource_ref(source),
			"no dangling spotlight path/UID in " + file_path)
	for subfolder in dir.get_directories():
		if subfolder.begins_with("."):
			continue
		_scan_source_tree(folder.path_join(subfolder))


func _has_old_resource_ref(source: String) -> bool:
	return source.contains("spotlight_overlay.tscn") \
		or source.contains("spotlight_overlay.gd") \
		or source.contains(SCENE_UID) or source.contains(SCRIPT_UID)


func _audit_game_scene(spec: Dictionary, size: Vector2i) -> void:
	var name: String = String(spec["activity"])
	var path: String = String(spec["path"])
	_check(ResourceLoader.exists(path), name + " PackedScene still exists")
	var source := FileAccess.get_file_as_string(path)
	for obsolete in OLD_NODE_NAMES:
		_check(not source.contains('name="' + obsolete + '"'),
			name + " has no authored " + obsolete)
	_check(not source.contains('[editable path="GuidedSpotlight"]'),
		name + " obsolete editable scene inheritance removed")
	var packed := load(path) as PackedScene
	_check(packed != null, name + " scene parses after spotlight deletion")
	if packed == null:
		return
	var game := packed.instantiate() as Control
	_check(game != null, name + " instantiates after resource pruning")
	if game != null:
		for obsolete in OLD_NODE_NAMES:
			_check(_count_named(game, obsolete) == 0,
				"%s at %dx%d contains zero %s" % [name, size.x, size.y, obsolete])
		game.free()


func _audit_preserved_english_recordings() -> void:
	var root_path := "res://assets/audio/tutorial_spotlight/"
	var total := 0
	for spec in GAMES:
		for suffix in ["prompt", "movement", "seconds", "lives", "score", "pause"]:
			var filename: String = String(spec["key"]) + "_" + suffix + ".wav"
			var path := root_path + filename
			_check(FileAccess.file_exists(path), "original English recording retained: " + filename)
			if FileAccess.file_exists(path):
				var audio := FileAccess.open(path, FileAccess.READ)
				_check(audio != null and audio.get_length() > 44,
					"recording has nonempty WAV data: " + filename)
				total += 1
	_check(total == 18, "all 18 English source WAVs remain available for reuse")


func _check_route(wrapper_scene: PackedScene, size: Vector2i, spec: Dictionary,
		mode: String, guided: bool) -> void:
	var tag := "%dx%d %s / %s / %s" % [
		size.x, size.y, String(spec["activity"]), mode, "Guided" if guided else "Play"]
	var host := wrapper_scene.instantiate() as Control
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.set_process(false)
	_stop_game_music()
	var source_pose := _pose_status()
	var context := _context(spec, mode, guided, false)
	host.set_context(context)
	await process_frame
	await process_frame
	var game := host.get("active_game") as Control
	_check(game != null, tag + " mounts the real activity")
	if game == null:
		host.queue_free()
		await process_frame
		return
	_check(String(game.get_script().resource_path).ends_with(
		String(spec["path"]).get_file().trim_suffix(".tscn") + ".gd"),
		tag + " uses production minigame script")
	_check((host.get("context") as Dictionary).get("guided_tutorial", null) == guided
		and (host.get("context") as Dictionary).get("game_mode", null) == mode
		and bool((host.get("context") as Dictionary).get("calibration_measured", false)),
		tag + " retains calibrated activity, mode and entry source")
	_check(String(game.get("game_mode")) == mode,
		tag + " minigame honors the selected Seconds/Lives mode")
	_check(game.process_mode == Node.PROCESS_MODE_DISABLED,
		tag + " real game is frozen before GO")
	_check(_count_named(host, "GuidedSpotlight") == 0
		and _count_named(host, "SpotlightOverlay") == 0,
		tag + " does not instantiate any removed spotlight overlay")
	_check(_no_legacy_spotlight_field(host), tag + " wrapper no longer depends on spotlight_overlay")
	_check(String(host.get("guided_stage")) == "countdown",
		tag + " goes directly into countdown after calibration")
	_check(_count_named(host, "GuidedCountdown") == 1,
		tag + " opens exactly one shared countdown")
	var countdown := host.get("countdown_panel") as Control
	_check(countdown != null and countdown.get_parent() is CanvasLayer,
		tag + " countdown is a layered real Control")
	if countdown == null:
		host.queue_free()
		await process_frame
		return
	var digits := countdown.get_node_or_null("CountdownNumber") as Label
	var timer := countdown.get_node_or_null("CountdownTimer") as Timer
	_check(digits != null and digits.text == "3" and timer != null and not timer.is_stopped(),
		tag + " starts at 3 with one running Timer")
	_check(not bool(host.get("_countdown_requires_locked_pose")),
		tag + " camera-off QA does not fabricate a valid live pose")
	_check(_pose_status() == source_pose, tag + " mounting countdown never starts another camera")
	_check(game.size.x > 0 and game.size.y > 0 and countdown.size.x > 0,
		tag + " scene remains visible/sized at this viewport")
	var game_id := game.get_instance_id()
	var original := _game_snapshot(game)
	var active_before := _music_active()
	_check(not active_before, tag + " music stays stopped during 3-2-1")
	# Exactly one countdown node, no gameplay mutations, and no early GO.
	for next_digit in ["2", "1"]:
		host.call("_on_countdown_tick")
		_check(digits != null and digits.text == next_digit,
			tag + " countdown moves to " + next_digit)
		_check(game.process_mode == Node.PROCESS_MODE_DISABLED
			and _game_snapshot(game) == original,
			tag + " score, lives, clock and game processing remain frozen at " + next_digit)
		_check(_count_named(host, "GuidedCountdown") == 1
			and not _music_active(), tag + " no second countdown or early gameplay music")
	host.call("_on_countdown_tick")
	_check(game.get_instance_id() == game_id and game.process_mode == Node.PROCESS_MODE_INHERIT,
		tag + " GO resumes the SAME game exactly once")
	_check(host.get("countdown_panel") == null
		and _count_named(host, "GuidedCountdown") == 0
		and String(host.get("guided_stage")) == "",
		tag + " GO removes countdown and clears transition state")
	_check(_music_active(), tag + " gameplay music starts only at GO")
	for retry in range(3):
		host.call("_on_countdown_tick")
		host.call("_complete_countdown_start")
	_check(game.get_instance_id() == game_id and game.process_mode == Node.PROCESS_MODE_INHERIT
		and host.get("countdown_panel") == null
		and _count_named(host, "GuidedCountdown") == 0,
		tag + " late timeout/GO retries cannot create duplicate rounds")
	_check(_game_snapshot(game) == original, tag + " GO transition itself never changes score or lives")
	_check(_pose_status() == source_pose, tag + " no camera session or lock was reset by GO")
	host.queue_free()
	await process_frame
	await process_frame
	_stop_game_music()


func _check_calibrated_camera_gate(wrapper_scene: PackedScene, spec: Dictionary,
		mode: String) -> void:
	var tag := "Camera gate %s %s" % [spec["activity"], mode]
	pose.stop_camera()
	pose.set_process(false)
	pose.session_token = "SPOTLIGHT_REMOVAL_TEST_SESSION"
	_set_test_student(1, true)
	if String(spec["activity"]) == "Human Plane":
		_check(bool(pose.set_stationary_plane_calibration(0.50, 71, 0.50, 0.0)),
			tag + " uses measured stationary plane calibration")
	else:
		_check(bool(pose.set_calibration(0.20, 0.50, 0.80, 71)),
			tag + " uses physical CENTER/RIGHT/LEFT calibration")
	var host := wrapper_scene.instantiate() as Control
	root.add_child(host)
	host.set_process(false)
	_stop_game_music()
	host.set_context(_context(spec, mode, true, true))
	await process_frame
	await process_frame
	var game := host.get("active_game") as Control
	_check(game != null, tag + " calibrated live session mounts minigame")
	if game == null:
		pose.worker_pid = -1
		host.queue_free()
		await process_frame
		return
	_check(bool(host.get("_countdown_requires_locked_pose")),
		tag + " a live, measured calibration requires a trusted solo player at GO")
	_check(String(host.get("guided_stage")) == "countdown"
		and host.get("countdown_panel") != null,
		tag + " guided camera session starts countdown without spotlight")
	_set_test_student(2, false)
	_check(not bool(host.call("_has_live_calibrated_player")),
		tag + " missing/crowded/invalid tracked pose is rejected")
	var invalid_source := (pose.current_status as Dictionary).duplicate(true)
	pose.call("_apply_pose_packet", {
		"kind": "pose", "token": "WRONG-SESSION-CANNOT-UNLOCK-GO",
		"when": 7000.0, "camera": true, "camera_phase": "tracking",
		"state": "tracking", "pose": true, "people": 1,
		"lock_state": "locked", "x": 0.5, "camera_frame_age_ms": 10,
		"plane_bank_valid": true, "plane_bank": 0.0
	}, Time.get_ticks_msec())
	_check(pose.current_status == invalid_source
		and not bool(host.call("_has_live_calibrated_player")),
		tag + " replayed packets from another camera session cannot authorize GO")
	var state := _game_snapshot(game)
	for tick in range(3):
		host.call("_on_countdown_tick")
	_check(String(host.get("guided_stage")) == "countdown"
		and game.process_mode == Node.PROCESS_MODE_DISABLED
		and bool(host.get("_countdown_waiting_for_pose"))
		and host.get("countdown_panel") != null,
		tag + " refused GO remains frozen until one fresh calibrated student returns")
	_check(_game_snapshot(game) == state and not _music_active(),
		tag + " rejected GO cannot spend time, score, lives or start music")
	var panel := host.get("countdown_panel") as Control
	var hint := panel.get_node_or_null("MovementHint") as Label
	_check(hint != null and hint.text.contains("TRACKING PAUSED"),
		tag + " waiting screen explains why GO was blocked")
	_set_test_student(1, true)
	_check(bool(host.call("_has_live_calibrated_player")),
		tag + " fresh solo calibration restores GO eligibility without second calibration")
	host.call("_complete_countdown_start")
	_check(String(host.get("guided_stage")) == ""
		and game.process_mode == Node.PROCESS_MODE_INHERIT
		and host.get("countdown_panel") == null,
		tag + " recovered pose releases one existing countdown to gameplay")
	_check(_game_snapshot(game) == state and _music_active(),
		tag + " recovered GO preserves score/lives and starts soundtrack once")
	host.call("_complete_countdown_start")
	_check(host.get("countdown_panel") == null
		and _count_named(host, "GuidedCountdown") == 0,
		tag + " duplicate camera GO callback cannot reenter countdown")
	pose.worker_pid = -1
	host.queue_free()
	await process_frame
	await process_frame
	_stop_game_music()
	pose.stop_camera()
	pose.set_process(false)


func _set_test_student(people: int, valid: bool) -> void:
	# Camera-frame-shaped test data only; no webcam process or network socket.
	pose.active = true
	pose.player_x = 0.5 if valid else -1.0
	pose.last_pose_ms = Time.get_ticks_msec()
	pose.set("_last_packet_ms", Time.get_ticks_msec())
	pose.set("_ever_tracked", valid)
	pose.current_status = {
		"state": "tracking", "camera": true, "camera_phase": "tracking",
		"pose": valid, "people": people, "lock_state": "locked" if valid else "lost",
		"camera_frame_age_ms": 12, "hand_observation_valid": valid,
		"plane_bank_valid": valid, "plane_bank": 0.0, "hand_up": false
	}


func _context(spec: Dictionary, mode: String, guided: bool, camera_live: bool) -> Dictionary:
	return {
		"activity": String(spec["activity"]), "entry_source": "tutorial" if guided else "play",
		"guided_tutorial": guided, "start_countdown": true,
		"camera_live": camera_live, "calibration_measured": true,
		"keyboard_mode": not camera_live, "camera_requested": camera_live,
		"calibration_skipped": false, "game_mode": mode, "difficulty": "Easy",
		"topic": "Noun", "game_style": "Noun",
		"student_id": "SPOTLIGHT-REMOVAL-TEST", "student_name": "QA ONLY",
	}


func _game_snapshot(game: Control) -> Dictionary:
	var state := {}
	var properties := {}
	for property in game.get_property_list():
		properties[String(property.get("name", ""))] = true
	for key in SNAPSHOT:
		if properties.has(key):
			state[key] = game.get(key)
	return state


func _pose_status() -> Dictionary:
	return {
		"active": bool(pose.get("active")),
		"peer": pose.get("peer"),
		"session_token": String(pose.get("session_token")),
		"worker_pid": int(pose.get("worker_pid")),
		"calibration": (pose.get("calibration") as Dictionary).duplicate(true),
	}


func _no_legacy_spotlight_field(host: Control) -> bool:
	for property in host.get_property_list():
		if String(property.get("name", "")) == "spotlight_overlay":
			return false
	return true


func _music_active() -> bool:
	music = root.get_node_or_null("KilosGameAudio")
	return music != null and bool(music.call("is_gameplay_active"))


func _stop_game_music() -> void:
	music = root.get_node_or_null("KilosGameAudio")
	if music != null:
		music.call("stop_gameplay")


func _count_named(node: Node, wanted: String) -> int:
	var total := 1 if node.name == wanted else 0
	for child in node.get_children():
		total += _count_named(child, wanted)
	return total


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("DIRECT GUIDED COUNTDOWN QA FAIL: ", description)


func _cleanup() -> void:
	_stop_game_music()
	# Never leave an imaginary worker PID that stop_camera() might try to kill.
	pose.worker_pid = -1
	pose.stop_camera()
	pose.set_process(true)
	_finish()


func _finish() -> void:
	var elapsed := Time.get_ticks_msec() - _started_ms
	print("SPOTLIGHT REMOVAL DIRECT COUNTDOWN: ",
		"PASS" if failures.is_empty() else "FAIL", " (", checks, " checks, ",
		failures.size(), " failures, ", elapsed,
		"ms; 3 games x 2 modes x 3 sizes x Guided/Play, plus camera GO gate)")
	quit(0 if failures.is_empty() else 1)
