extends SceneTree

# No camera, worker, database or Git. Repeat instantiation and state changes
# against the real post-cleanup scenes without depending on deleted legacy UI.
# Godot 4.7.2 --headless --path . --script res://tools/test_calibration_settings_prune_resilience.gd
const CALIBRATION := "res://ui/vision/calibration/calibration.tscn"
const SETTINGS := "res://ui/secondary/settings/settings.tscn"
const ACTIVITIES := ["Catch the Word", "Balloon Popping", "Human Plane"]
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const POSE_GUIDES := ["PoseGuideDefault", "PoseGuideRight", "PoseGuideLeft",
	"PoseGuideBalloonRaise", "PoseGuideBalloonRaiseRight", "PoseGuideBalloonRaiseLeft",
	"PoseGuidePlaneCenter", "PoseGuidePlaneLeft", "PoseGuidePlaneRight"]
const SETTINGS_FILE := "user://kilos_settings.cfg"

var checks := 0
var failures: Array[String] = []
var _finished := false


func _initialize() -> void:
	call_deferred("_run")
	call_deferred("_watchdog")


func _watchdog() -> void:
	await create_timer(30.0).timeout
	if not _finished:
		_check(false, "Scene cleanup stress exceeded 30 seconds")
		_finish()


func _run() -> void:
	var saved_size := root.size
	var saved_content_size := root.content_scale_size
	var previous_config_exists := FileAccess.file_exists(SETTINGS_FILE)
	var previous_config := FileAccess.get_file_as_bytes(SETTINGS_FILE) if previous_config_exists else PackedByteArray()
	var previous_window := DisplayServer.window_get_mode()
	var saved_buses: Dictionary = {}
	for name in ["Master", "KilosMusic", "KilosSFX"]:
		var idx := AudioServer.get_bus_index(name)
		if idx >= 0:
			saved_buses[name] = [AudioServer.get_bus_volume_db(idx), AudioServer.is_bus_mute(idx)]
	var service := root.get_node_or_null("PoseService")
	_check(service != null, "PoseService singleton is available")
	if service == null:
		_finish()
		return
	_check(not service.active, "No real camera session starts in isolated cleanup stress")
	_audit_external_resources(CALIBRATION)
	_audit_external_resources(SETTINGS)
	# Runtime load only AFTER all autoloads are initialized.
	var calibration_scene := load(CALIBRATION) as PackedScene
	var settings_scene := load(SETTINGS) as PackedScene
	_check(calibration_scene != null, "Calibration PackedScene still parses")
	_check(settings_scene != null, "Settings PackedScene still parses")
	if calibration_scene != null and settings_scene != null:
		for dimensions in SIZES:
			root.size = dimensions
			root.content_scale_size = dimensions
			await process_frame
			for activity in ACTIVITIES:
				for repetition in range(2):
					await _calibration_round(calibration_scene, activity, dimensions, repetition)
			for repetition in range(2):
				await _settings_round(settings_scene, dimensions, repetition)
	for bus_name in saved_buses:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
			AudioServer.set_bus_volume_db(index, saved_buses[bus_name][0])
			AudioServer.set_bus_mute(index, saved_buses[bus_name][1])
	DisplayServer.window_set_mode(previous_window)
	if previous_config_exists:
		var file := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
		if file != null:
			file.store_buffer(previous_config)
		else:
			_check(false, "Settings fixture can restore original settings bytes")
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	root.content_scale_size = saved_content_size
	root.size = saved_size
	_check(not service.active, "Scene stress never launched webcam")
	_finish()


func _audit_external_resources(path: String) -> void:
	var source := FileAccess.get_file_as_string(path)
	_check(not source.is_empty(), path + " source is readable")
	if source.is_empty():
		return
	var resource_pattern := RegEx.create_from_string('^\\[ext_resource[^\\n]*path="([^"]+)" id="([^"]+)"\\]')
	var used_ids: Dictionary = {}
	for line in source.split("\n"):
		var match_data := resource_pattern.search(line)
		if match_data == null:
			continue
		var item_path := match_data.get_string(1)
		var item_id := match_data.get_string(2)
		_check(not used_ids.has(item_id), path + " resource ID remains unique: " + item_id)
		used_ids[item_id] = true
		_check(ResourceLoader.exists(item_path), path + " retained external asset exists: " + item_path)
		_check(source.contains('ExtResource("' + item_id + '")'),
			path + " external resource has a consumer: " + item_id)
	var sub_pattern := RegEx.create_from_string('^\\[sub_resource[^\\n]*id="([^"]+)"\\]')
	for line in source.split("\n"):
		var submatch := sub_pattern.search(line)
		if submatch != null:
			var sub_id := submatch.get_string(1)
			_check(source.contains('SubResource("' + sub_id + '")'),
				path + " style/shader sub-resource has a consumer: " + sub_id)
	print("CLEANUP AUDIT ", path, " resources=", used_ids.size())


func _calibration_round(packed: PackedScene, activity: String,
		dimensions: Vector2i, repetition: int) -> void:
	var prefix := "%s %s run %d" % [dimensions, activity, repetition]
	var screen := packed.instantiate() as Control
	_check(screen != null, prefix + " scene instantiates")
	if screen == null:
		return
	root.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	screen.set_process(false)
	var stage := screen.get_node_or_null("TutorialStage") as Control
	var intro := screen.get_node_or_null("TutorialStage/IntroOverlay") as Control
	var live_camera := screen.get_node_or_null("TutorialStage/CameraArea/LiveCameraInset") as TextureRect
	var skeleton := screen.get_node_or_null("TutorialStage/CameraArea/SkeletonPlacement") as ReferenceRect
	var back := screen.get_node_or_null("TutorialStage/Navigation/BackButton") as Button
	_check(stage != null and intro != null and live_camera != null and skeleton != null and back != null,
		prefix + " cleanup preserved stage, 3s intro, camera, skeleton placement, Back")
	if stage != null and intro != null and live_camera != null and skeleton != null and back != null:
		_check(intro.visible and screen.intro_running, prefix + " intro is initially visible")
		_check(intro.get_node_or_null("IntroBackButton") != null,
			prefix + " authored intro back reference still exists")
		_check(live_camera.owner == screen and skeleton.owner == screen,
			prefix + " live inset and skeleton layout remain editor-authored")
		_check(live_camera.get_child_count() == 0, prefix + " camera preview is not flattened into UI")
		for name in POSE_GUIDES:
			var node := stage.get_node_or_null("PoseGuides/" + name) as TextureRect
			_check(node != null and node.owner == screen and node.texture != null
				and ResourceLoader.exists(node.texture.resource_path),
				prefix + " pose asset retained as editor-authored PNG: " + name)
		# Simulate activity selection without triggering physical camera setup.
		screen.context = {"activity": activity}
		# The scene may have already rendered a frame while this fixture bound
		# its authored nodes. Isolate exact intro timing from that real frame.
		screen.intro_elapsed = 0.0
		screen._process(2.99)
		_check(screen.intro_running, prefix + " 2.99s still intro")
		screen._process(0.01)
		_check(not screen.intro_running and not intro.visible, prefix + " intro ends at 3.00s")
		_check(back.visible and not back.disabled, prefix + " Back usable after intro")
		for loop in range(5):
			screen.live_step = 0 if activity == "Human Plane" else loop % 3
			screen.balloon_pose_phase = loop % 2 if activity == "Balloon Popping" else 0
			screen._sync_reference_art()
			var zone: String = ["CENTER", "RIGHT", "LEFT"][loop % 3]
			var expected := "PoseGuidePlaneCenter"
			if activity != "Human Plane":
				var raised := activity == "Balloon Popping" and loop % 2 == 1
				expected = "PoseGuideBalloonRaise" if raised else "PoseGuideDefault"
				if zone != "CENTER":
					expected = ("PoseGuideBalloonRaise" if raised else "PoseGuide") + zone.capitalize()
			var count_visible := 0
			for name in POSE_GUIDES:
				var art := stage.get_node_or_null("PoseGuides/" + name) as TextureRect
				if art != null and art.visible:
					count_visible += 1
					_check(name == expected, prefix + " loop %d correct active PNG" % loop)
			_check(count_visible == 1, prefix + " loop %d only one pose reference visible" % loop)
			# Deleted obsolete nodes are valid, but if still present they must not
			# become visible after changing activity/phase or resizing.
			for legacy in ["ArtGuideLeft", "ArtGuideCenter", "ArtGuideRight"]:
				var retired := stage.get_node_or_null(legacy) as Control
				_check(retired == null or not retired.visible,
					prefix + " loop %d legacy neon stays absent or hidden" % loop)
		for player: Node in _animation_players(screen):
			_check(_animation_tracks_resolve(player), prefix + " animations refer only to existing scene nodes")
		var routes: Array[String] = []
		screen.requested.connect(func(route: String, _payload: Dictionary) -> void: routes.append(route))
		back.pressed.emit()
		_check(routes == ["play_activity"], prefix + " real Back callback routes to activity chooser")
	screen.queue_free()
	await process_frame
	await process_frame


func _settings_round(packed: PackedScene, dimensions: Vector2i, repetition: int) -> void:
	var prefix := "%s Settings run %d" % [dimensions, repetition]
	var panel := packed.instantiate() as Control
	_check(panel != null, prefix + " Settings scene instantiates")
	if panel == null:
		return
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	panel.call("_apply_responsive_layout")
	await process_frame
	var board := panel.find_child("SettingsCard", true, false) as Control
	var scroll := panel.find_child("PageScroll", true, false) as ScrollContainer
	var home := panel.find_child("BackButton", true, false) as Button
	_check(board != null and scroll != null and home != null, prefix + " board, scroll and Home retained")
	_check(panel.find_child("MuteCheck", true, false) == null and panel.find_child("ToggleMuteallaudioRow", true, false) == null,
		prefix + " retired Mute All Audio row is gone")
	_check(panel.find_child("ControlsPage", true, false) == null and panel.find_child("CameraPage", true, false) == null,
		prefix + " unused Settings pages were not regenerated")
	for name in ["VolumeSlider", "MusicSlider", "EffectsSlider"]:
		var slider := panel.find_child(name, true, false) as HSlider
		_check(slider != null, prefix + " active audio control: " + name)
		if slider != null:
			_check(slider.value_changed.get_connections().size() == 1,
				prefix + " slider callback wired once: " + name)
	var fullscreen := panel.find_child("FullscreenCheck", true, false) as CheckButton
	_check(fullscreen != null and fullscreen.toggled.get_connections().size() == 1,
		prefix + " fullscreen switch connected once")
	if board != null:
		_check(board.get_global_rect().size.x > 0 and board.get_global_rect().size.y > 0,
			prefix + " real board retains layout")
	for player: Node in _animation_players(panel):
		_check(_animation_tracks_resolve(player), prefix + " animations refer only to existing scene nodes")
	if home != null:
		var routes: Array[String] = []
		panel.requested.connect(func(route: String, _payload: Dictionary) -> void: routes.append(route))
		home.pressed.emit()
		_check(routes.has("main"), prefix + " Settings Home still routes to Main Menu")
	panel.queue_free()
	await process_frame
	await process_frame


func _animation_players(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	var todo: Array[Node] = [node]
	while not todo.is_empty():
		var current: Node = todo.pop_back() as Node
		if current is AnimationPlayer:
			result.append(current)
		for child in current.get_children():
			todo.append(child)
	return result


func _animation_tracks_resolve(animation_player: AnimationPlayer) -> bool:
	var animation_root := animation_player.get_node_or_null(animation_player.root_node)
	if animation_root == null:
		return false
	for name in animation_player.get_animation_list():
		var animation := animation_player.get_animation(name)
		for index in range(animation.get_track_count()):
			var track := animation.track_get_path(index)
			if animation_root.get_node_or_null(NodePath(track.get_concatenated_names())) == null:
				return false
	return true


func _check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		printerr("SCENE CLEANUP STRESS FAIL: ", description)


func _finish() -> void:
	if _finished:
		return
	_finished = true
	for error in failures:
		push_error(error)
	print("SCENE_CLEANUP_STRESS %s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
