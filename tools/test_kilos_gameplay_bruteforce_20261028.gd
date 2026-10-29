extends SceneTree

## Deterministic adversarial game QA. No webcam, worker process, HTTP or database.
## Run: Godot --headless --path . --script res://tools/test_kilos_gameplay_bruteforce_20261028.gd
## Every failure includes a stable seed and scenario for reproduction.

const SEED := 20261028
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const ACTIVITIES := {
	"Catch the Word": "res://ui/minigames/catch_the_word/catch_word.tscn",
	"Balloon Popping": "res://ui/minigames/balloon_popping/balloon_popping.tscn",
	"Human Plane": "res://ui/minigames/human_plane/human_plane.tscn",
}
const MODES := ["Seconds", "Lives"]
const GameAudio = preload("res://ui/shared/game_audio.gd")

var scenes: Array[String] = []
var failures: Array[String] = []
var checks := 0
var instances := 0
var mounted := 0
var round_cases := 0
var old_size := Vector2i.ZERO
var old_content_scale := Vector2i.ZERO


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	seed(SEED)
	old_size = root.size
	old_content_scale = root.content_scale_size
	var pose := root.get_node_or_null("PoseService")
	_check(pose != null, "autoload PoseService must exist")
	if pose != null:
		pose.stop_camera()
	_scan("res://")
	scenes.sort()
	# The old low-poly mockup and shared Spotlight have both been retired.
	# Keep the two live imported-model Human Plane scenes and the 3-2-1 scene.
	_check(scenes.size() == 30, "expected 30 authored .tscn files after retiring old Spotlight and low-poly scenes; observed %d" % scenes.size())
	_check("res://ui/minigames/human_plane/legacy/flight_lowpoly_3d.tscn" not in scenes,
		"obsolete standalone low-poly 3D mockup remains retired")
	_check("res://ui/tutorial/spotlight/spotlight_overlay.tscn" not in scenes,
		"obsolete shared Spotlight tutorial scene remains retired")
	_check("res://ui/minigames/human_plane/human_plane_hybrid_3d.tscn" in scenes
		and "res://ui/minigames/human_plane/human_plane_flight_world_3d.tscn" in scenes,
		"both active 3D plane/torus world scenes are retained")
	await _scene_construction_matrix()
	if pose != null:
		_test_untrusted_pose_packets(pose)
	await _calibration_intro_matrix()
	await _gameplay_matrix()
	await _audio_route_matrix()
	root.size = old_size
	root.content_scale_size = old_content_scale
	if pose != null:
		pose.stop_camera()
	for child in root.get_children():
		if child.name.begins_with("QA20261028"):
			_check(false, "leaked QA host: " + child.name)
	for f in failures:
		printerr("KILOS_GAMEPLAY_BRUTE_FAIL seed=%d %s" % [SEED, f])
	print("KILOS_GAMEPLAY_BRUTE_%s seed=%d scenes=%d instances=%d live_mounts=%d game_rounds=%d checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", SEED, scenes.size(), instances,
		mounted, round_cases, checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _scan(folder: String) -> void:
	var dir := DirAccess.open(folder)
	_check(dir != null, "can open directory " + folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not name.begins_with("."):
			var path := folder.path_join(name)
			if dir.current_is_dir():
				_scan(path)
			elif name.ends_with(".tscn"):
				scenes.append(path)
		name = dir.get_next()
	dir.list_dir_end()


func _scene_construction_matrix() -> void:
	var packed: Dictionary = {}
	for path in scenes:
		var resource := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
		_check(resource is PackedScene, "PackedScene parse %s" % path)
		if resource is PackedScene:
			packed[path] = resource
			var scene := (resource as PackedScene).instantiate()
			instances += 1
			_check(scene != null and not scene.name.is_empty(), "initial instantiate %s" % path)
			if scene != null:
				# Godot can instantiate an authored .tscn despite a broken root
				# .gd compile, leaving a plain Control that masks production failure.
				var sibling_script := path.trim_suffix(".tscn") + ".gd"
				if FileAccess.file_exists(sibling_script):
					_check(scene.get_script() != null and (scene.get_script() as Script).can_instantiate(),
						"required root GDScript compiles %s" % sibling_script)
				_inspect_offline_tree(scene, path)
				scene.free()
	for res in RESOLUTIONS:
		root.size = res
		root.content_scale_size = Vector2i(1280, 720)
		for cycle in range(3):
			for path in scenes:
				var source := packed.get(path) as PackedScene
				if source == null:
					continue
				var scene := source.instantiate()
				instances += 1
				_check(scene != null and scene.get_parent() == null,
					"unmounted scene %s resolution=%s cycle=%d" % [path, res, cycle])
				if scene != null:
					scene.free()
		await process_frame


func _inspect_offline_tree(node: Node, source: String) -> void:
	if node is TextureRect:
		var tex := (node as TextureRect).texture
		if tex != null:
			_check(tex.get_width() > 0 and tex.get_height() > 0,
				"nonzero TextureRect dimensions %s/%s" % [source, node.name])
	if node is TextureButton:
		var tex := (node as TextureButton).texture_normal
		_check(tex == null or (tex.get_width() > 0 and tex.get_height() > 0),
			"nonzero TextureButton dimensions %s/%s" % [source, node.name])
	for child in node.get_children():
		_inspect_offline_tree(child, source)


func _test_untrusted_pose_packets(pose: Node) -> void:
	# Pure packet checks are safe with no worker process. Real UDP transport,
	# source timestamp verification and authenticated session are separate.
	var base := {
		"token": "QA20261028_fake_token", "kind": "pose", "state": "tracking",
		"camera": true, "camera_phase": "tracking", "pose": true,
		"lock_state": "locked", "people": 1,
		"x": 0.52, "camera_frame_age_ms": 30,
	}
	for people in [0, 1, 2, 4, -1, 1.5, "1", null]:
		var packet := base.duplicate()
		packet["people"] = people
		var expected_solo: bool = people is int and people == 1
		_check(bool(pose.call("_trusted_live_tracking_packet", packet)) == expected_solo,
			"trusted packet people=%s equals explicit solo validity=%s" % [people, expected_solo])
		var raw_count := int(pose.call("_raw_camera_population", packet))
		_check(raw_count == (people if people is int and people >= 0 and people <= 12 else -1),
			"raw count rejects fractional/invalid occupancy: %s" % [people])
	for age in [-1, 0, 649, 650, 651, 5000, "20", null]:
		var packet := base.duplicate()
		packet["camera_frame_age_ms"] = age
		var valid_age: bool = age is int and age >= 0 and age <= 650
		_check(bool(pose.call("_trusted_live_tracking_packet", packet)) == valid_age,
			"source capture age %s valid=%s" % [age, valid_age])
	for condition in ["preview", "warming", "error", "tracking"]:
		var packet := base.duplicate()
		packet["state"] = condition
		_check(bool(pose.call("_is_raw_camera_occupancy_packet", packet)) == (condition == "tracking"),
			"only live YOLO tracking grants raw population state=%s" % condition)
	_check(not bool(pose.call("has_valid_pose")), "no webcam/worker means no controlling pose")
	_check(int(pose.call("fresh_camera_population")) == -1,
		"no webcam/worker means unknown occupancy, never fictional zero or one")


func _calibration_intro_matrix() -> void:
	var source := ResourceLoader.load("res://ui/vision/calibration/calibration.tscn") as PackedScene
	_check(source != null, "calibration exists")
	if source == null:
		return
	for activity in ACTIVITIES.keys():
		for repetition in range(3):
			var host := Control.new()
			host.name = "QA20261028Calibration"
			host.size = Vector2(1280, 720)
			root.add_child(host)
			var screen := source.instantiate() as Control
			host.add_child(screen)
			mounted += 1
			if not screen.has_method("_finish_intro_only"):
				_check(false, "calibration script failed to load activity=%s" % activity)
				host.queue_free()
				await process_frame
				await process_frame
				return
			screen.set("context", {"activity": activity})
			screen.set_process(false) # Manually advance exact clock, no camera opened.
			var intro := screen.get_node_or_null("TutorialStage/IntroOverlay") as Control
			var state := str(screen.get("intro_running"))
			_check(screen.get("intro_running") == true and intro != null and intro.visible,
				"intro visible activity=%s repeat=%d initial=%s" % [activity, repetition, state])
			screen.call("_process", 2.8)
			_check(screen.get("intro_running") == true and intro.visible,
				"intro does not finish before 3s activity=%s" % activity)
			screen.call("_process", 0.19)
			_check(screen.get("intro_running") == true, "intro still active at 2.99s activity=%s" % activity)
			screen.call("_process", 0.02)
			_check(screen.get("intro_running") == false and not intro.visible,
				"intro ends at 3s activity=%s" % activity)
			_check(int(screen.get("live_step")) == 0 and float(screen.get("live_timer")) == 0.0,
				"intro does not credit physical calibration holds activity=%s" % activity)
			host.queue_free()
			await process_frame
			await process_frame
			_check(not is_instance_valid(host), "calibration screen frees without orphan activity=%s" % activity)


func _gameplay_matrix() -> void:
	for activity in ACTIVITIES:
		var source := load(ACTIVITIES[activity]) as PackedScene
		_check(source != null, "gameplay source %s" % activity)
		if source == null:
			continue
		for mode in MODES:
			for attempt in range(3):
				var context := {
					"activity": activity, "game_style": "Noun", "topic": "Noun",
					"game_mode": mode, "difficulty": ["Easy", "Normal", "Hard"][attempt],
					"lives": 3, "hearts": 3, "student_id": "QA_LOCAL_NO_DB",
					"camera_live": false, "guided_mode": false,
				}
				await _stress_one_game(source, activity, mode, attempt, context)


func _stress_one_game(source: PackedScene, activity: String, mode: String,
		attempt: int, context: Dictionary) -> void:
	round_cases += 1
	var viewport: Vector2i = RESOLUTIONS[attempt]
	root.size = viewport
	var marker := "%s mode=%s difficulty=%s attempt=%d" % [
		activity, mode, context["difficulty"], attempt]
	var host := Control.new()
	host.name = "QA20261028Game"
	host.size = Vector2(viewport)
	root.add_child(host)
	var game := source.instantiate() as Control
	_check(game != null, "instantiate " + marker)
	if game == null:
		host.queue_free()
		await process_frame
		return
	host.add_child(game)
	mounted += 1
	if not game.has_method("get_context") or not game.has_method("set_context"):
		_check(false, "gameplay script failed to compile " + marker)
		host.queue_free()
		await process_frame
		await process_frame
		return
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_process(false) # Use deterministic accelerated frames, not wall clock.
	game.set_physics_process(false)
	if game.get("rng") is RandomNumberGenerator:
		(game.get("rng") as RandomNumberGenerator).seed = SEED + attempt + round_cases * 997
	game.call("set_context", context)
	await process_frame
	# Deferred callbacks started by a scene use the real scene, no mock game.
	game.set_process(false)
	game.set_physics_process(false)
	_check(game.is_inside_tree() and game.size.x > 0 and game.size.y > 0,
		"mounted game retains usable layout viewport=%s %s" % [viewport, marker])
	var routes: Array[String] = []
	game.requested.connect(func(target: String, _payload: Dictionary) -> void:
		routes.append(target))
	var initial := game.call("get_context") as Dictionary
	_check(int(initial.get("score", -1)) >= 0, "score nonnegative initially " + marker)
	_check(int(initial.get("lives", initial.get("hearts", -1))) <= 3,
		"three-heart limit initially " + marker)
	if mode == "Seconds":
		_check(float(initial.get("time_remaining", -1)) <= 60.01 and
			float(initial.get("time_remaining", -1)) > 0.0,
			"Seconds round starts within 60s " + marker)
	for cycle in range(6):
		if bool(game.call("get_context").get("round_completed", false)):
			break
		game.call("_pause")
		var before := game.call("get_context") as Dictionary
		game.call("_process", 1.0)
		var paused_ctx := game.call("get_context") as Dictionary
		_check(is_equal_approx(float(before.get("time_remaining", 0)),
			float(paused_ctx.get("time_remaining", 0))), "pause freezes timer %s cycle=%d" % [marker, cycle])
		game.call("_resume")
		if game.has_method("set_body_x"):
			game.call("set_body_x", [-1.0, 0.0, 1.0, 0.0, -1.0, 1.0][cycle])
		game.call("_process", 0.1)
	for second in range(65):
		var payload := game.call("get_context") as Dictionary
		if bool(payload.get("round_completed", false)):
			break
		if game.has_method("set_body_x"):
			game.call("set_body_x", [-1.0, 0.0, 1.0][second % 3])
		game.call("_process", 1.0)
		if game.has_method("_physics_process"):
			game.call("_physics_process", 0.016)
	var last := game.call("get_context") as Dictionary
	_check(int(last.get("score", -1)) >= 0, "score never negative after accelerated updates " + marker)
	_check(int(last.get("lives", last.get("hearts", -1))) <= 3, "hearts do not exceed 3 " + marker)
	_check(float(last.get("time_remaining", 0)) >= 0, "timer never negative " + marker)
	if mode == "Seconds":
		_check(bool(last.get("round_completed", false)) and "results" in routes,
			"Seconds round terminates and emits results under 65 seconds " + marker)
	var post_finish := routes.count("results")
	if bool(last.get("round_completed", false)):
		game.call("_process", 2.0)
		game.call("_finish_round")
		_check(routes.count("results") == post_finish,
			"finish callback emits results at most once " + marker)
	# Remove the entire live subtree, including temporary audio and tweens.
	host.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(game) and not is_instance_valid(host),
		"game and dynamically authored nodes free after activity retry " + marker)


func _audio_route_matrix() -> void:
	# Real gameplay music service; a synthetic title player isolates the menu
	# policy so no real audio device, external sound, DB or webcam is required.
	var service: Node = GameAudio.ensure(self)
	_check(service != null and is_instance_valid(service), "game audio manager initializes")
	if service == null:
		return
	var identical: Node = GameAudio.ensure(self)
	_check(identical == service, "gameplay audio manager is reused, not duplicated")
	var music := service.get_node_or_null("GameplayTrack") as AudioStreamPlayer
	_check(music != null and music.bus == "KilosMusic" and music.stream != null,
		"user gameplay WAV is loaded on KilosMusic")
	if music == null:
		service.queue_free()
		await process_frame
		return
	var title := AudioStreamPlayer.new()
	title.name = "QA20261028TitleMusic"
	title.bus = "KilosMusic"
	root.add_child(title)
	for cycle in range(12):
		# Menus should present the title track; GO hands control to gameplay.
		title.stream_paused = false
		service.call("start_gameplay")
		title.stream_paused = true
		# A headless AudioStreamPlayer reports stream_paused=false even after
		# assigning true when no native playback exists. Verify manager state;
		# test actual title/track playback with a real output device separately.
		_check(bool(service.call("is_gameplay_active")),
			"GO activates manager cycle=%d" % cycle)
		service.call("duck_for_voice", 1.0)
		_check(is_equal_approx(music.volume_db, -11.0),
			"child voice attenuates background soundtrack cycle=%d" % cycle)
		service.call("pause_music")
		_check(bool(service.call("is_music_paused")),
			"Pause changes music manager state cycle=%d" % cycle)
		service.call("resume_music")
		_check(not bool(service.call("is_music_paused")),
			"Resume changes music manager state cycle=%d" % cycle)
		service.call("_process", 1.1)
		_check(is_equal_approx(music.volume_db, 0.0),
			"voice duck resets after phrase expires cycle=%d" % cycle)
		service.call("stop_gameplay")
		title.stream_paused = false
		_check(not bool(service.call("is_gameplay_active")) and not title.stream_paused,
			"Results returns control to menu title music cycle=%d" % cycle)
	_check(service.get_child_count() == 1,
		"rapid route loops never spawn duplicate sound players")
	service.queue_free()
	title.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(service) and not is_instance_valid(title),
		"music services and title player release on exit")


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		failures.append(detail)
