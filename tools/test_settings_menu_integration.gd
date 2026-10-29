extends SceneTree

# Validate Settings through the real menu host, with its real Music/SFX buses.
const MENU := "res://ui/main_menu/main_menu.tscn"
const SETTINGS_FILE := "user://kilos_settings.cfg"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)


func _run() -> void:
	var original_bytes := FileAccess.get_file_as_bytes(SETTINGS_FILE) if FileAccess.file_exists(SETTINGS_FILE) else PackedByteArray()
	var original_exists := FileAccess.file_exists(SETTINGS_FILE)
	var original_display := DisplayServer.window_get_mode()
	var original_bus_levels: Dictionary = {}
	for bus_name in ["Master", "KilosMusic", "KilosSFX"]:
		var index := AudioServer.get_bus_index(bus_name)
		if index >= 0:
			original_bus_levels[bus_name] = [AudioServer.get_bus_volume_db(index), AudioServer.is_bus_mute(index)]

	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	# Autoload names are registered by the SceneTree before the menu is loaded.
	# Preloading at script parse time can compile the menu too early.
	var app := (load(MENU) as PackedScene).instantiate() as Control
	root.add_child(app)
	await create_timer(1.4).timeout
	app.call("_on_panel_requested", "settings", {})
	await process_frame
	var panel := app.get("active_panel") as Control
	_check(panel != null, "Settings did not open from the actual menu")
	if panel != null:
		for removed in ["SidebarPanel", "SidebarSettingsTab", "SidebarControlsTab",
				"SidebarCameraTab", "ControlsPage", "CameraPage", "TabsRow"]:
			_check(panel.find_child(removed, true, false) == null,
				"Removed obsolete Settings UI must be absent: " + removed)
		_check(String(panel.get("_active_tab")) == "settings"
			and (panel.find_child("SettingsPage", true, false) as Control).visible,
			"Audio & Display is the only active Settings page")
		await process_frame
		for info in [["VolumeSlider", "Master"], ["MusicSlider", "KilosMusic"], ["EffectsSlider", "KilosSFX"]]:
			var bus_index := AudioServer.get_bus_index(info[1])
			var slider := panel.find_child(info[0], true, false) as HSlider
			_check(bus_index >= 0 and slider != null and slider.editable, info[1] + " audio control unavailable")
			if bus_index >= 0 and slider != null:
				slider.value = 37.0
				await process_frame
				var level := db_to_linear(AudioServer.get_bus_volume_db(bus_index))
				_check(absf(level - 0.37) < 0.01, info[1] + " live volume slider does not control its bus")
		var fullscreen_button := panel.find_child("FullscreenCheck", true, false) as CheckButton
		_check(fullscreen_button != null, "Fullscreen control missing")
		_check(panel.find_child("MuteCheck", true, false) == null, "Obsolete mute switch was not deleted")
		_check(panel.find_child("ToggleMuteallaudioRow", true, false) == null, "Obsolete mute row was not deleted")
		var master_slider := panel.find_child("VolumeSlider", true, false) as HSlider
		if master_slider != null:
			master_slider.value = 0.0
			await process_frame
			_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Master 0% must silence audio")
			master_slider.value = 37.0
			await process_frame
			_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Master >0% must restore audio")
		var home := panel.find_child("BackButton", true, false) as Button
		_check(home != null, "Home button missing")
		if home != null:
			home.pressed.emit()
			await process_frame
			_check(String(app.get("current_route")) == "main", "Home button did not return to main")

	var title_music := app.get("title_music_player") as AudioStreamPlayer
	if title_music != null:
		title_music.stop()
		title_music.stream = null
	# The shared menu owns cached looping sounds. Let its production mixer
	# drain before freeing the mock-routed Settings app (avoids ObjectDB warnings).
	if app.has_method("prepare_for_shutdown"):
		await app.call("prepare_for_shutdown")
	app.queue_free()
	await process_frame
	for bus_name in original_bus_levels:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, original_bus_levels[bus_name][0])
			AudioServer.set_bus_mute(idx, original_bus_levels[bus_name][1])
	DisplayServer.window_set_mode(original_display)
	if original_exists:
		var file := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
		if file != null:
			file.store_buffer(original_bytes)
		else:
			failures.append("Cannot restore original settings file")
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_FILE))
	if failures.is_empty():
		print("PASS Audio & Display only, live mixer, Master 0% silence, fullscreen and Home")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)
