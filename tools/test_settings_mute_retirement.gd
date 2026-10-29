extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_settings_mute_retirement.gd
# Uses a temporary preference file and restores the user's bytes/audio buses.
const SETTINGS := preload("res://ui/secondary/settings/settings.tscn")
const PREFS := preload("res://ui/secondary/settings/settings.gd")
const CONFIG_PATH := "user://kilos_settings.cfg"
const BUS_NAMES := ["Master", "KilosMusic", "KilosSFX"]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _write_config(master: float, music: float, effects: float, old_mute: bool) -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "Master", master)
	config.set_value("audio", "KilosMusic", music)
	config.set_value("audio", "KilosSFX", effects)
	config.set_value("audio", "mute", old_mute)
	config.set_value("display", "fullscreen", false)
	_check(config.save(CONFIG_PATH) == OK, "write temporary legacy settings")


func _bus_linear(name: String) -> float:
	var index := AudioServer.get_bus_index(name)
	return db_to_linear(AudioServer.get_bus_volume_db(index)) if index >= 0 else -1.0


func _run() -> void:
	var had_file := FileAccess.file_exists(CONFIG_PATH)
	var old_bytes := FileAccess.get_file_as_bytes(CONFIG_PATH) if had_file else PackedByteArray()
	var old_bus: Dictionary = {}
	var new_buses: Array[String] = []
	for name in BUS_NAMES:
		var index := AudioServer.get_bus_index(name)
		if index < 0 and name != "Master":
			# Main Menu normally creates its music/effects buses before Settings opens.
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, name)
			new_buses.append(name)
		_check(index >= 0, "required mixer bus present: " + name)
		if index >= 0 and not new_buses.has(name):
			old_bus[name] = [AudioServer.get_bus_volume_db(index), AudioServer.is_bus_mute(index)]

	if AudioServer.get_bus_index("Master") >= 0 and AudioServer.get_bus_index("KilosMusic") >= 0 and AudioServer.get_bus_index("KilosSFX") >= 0:
		# A legacy true mute is ignored when the Master slider has an audible value.
		_write_config(65.0, 28.0, 82.0, true)
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
		PREFS.restore_saved_preferences(false)
		_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "legacy mute=true cannot silence Master 65%")
		_check(absf(_bus_linear("Master") - 0.65) < 0.01, "restore Master 65%")
		_check(absf(_bus_linear("KilosMusic") - 0.28) < 0.01, "restore Music 28%")
		_check(absf(_bus_linear("KilosSFX") - 0.82) < 0.01, "restore Effects 82%")

		# Master 0% is the only remaining way to mute the entire output.
		_write_config(0.0, 28.0, 82.0, false)
		PREFS.restore_saved_preferences(false)
		_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "saved Master 0% gives complete silence")
		_check(absf(_bus_linear("KilosMusic") - 0.28) < 0.01, "Master 0% preserves Music percentage")
		_check(absf(_bus_linear("KilosSFX") - 0.82) < 0.01, "Master 0% preserves Effects percentage")

		root.size = Vector2i(1280, 720)
		var scene := SETTINGS.instantiate() as Control
		root.add_child(scene)
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		_check(scene.find_child("MuteCheck", true, false) == null, "authored MuteCheck removed")
		_check(scene.find_child("ToggleMuteallaudioRow", true, false) == null, "authored mute row with label/icon removed")
		_check(scene.find_child("FullscreenCheck", true, false) is CheckButton, "Display switch retained")
		for control in ["VolumeSlider", "MusicSlider", "EffectsSlider"]:
			_check(scene.find_child(control, true, false) is HSlider, "authored slider retained: " + control)

		var master := scene.find_child("VolumeSlider", true, false) as HSlider
		var music := scene.find_child("MusicSlider", true, false) as HSlider
		var effects := scene.find_child("EffectsSlider", true, false) as HSlider
		if master != null and music != null and effects != null:
			_check(is_zero_approx(master.value), "authored slider displays persisted 0%")
			_check(is_equal_approx(music.value, 28.0), "authored Music slider keeps saved percent")
			_check(is_equal_approx(effects.value, 82.0), "authored Effects slider keeps saved percent")
			master.value = 41.0
			_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "raising Master from zero resumes sound")
			var written := ConfigFile.new()
			_check(written.load(CONFIG_PATH) == OK, "Master slider saves preferences")
			_check(not written.has_section_key("audio", "mute"), "new settings file no longer contains audio/mute")
			_check(is_equal_approx(float(written.get_value("audio", "Master", -1.0)), 41.0), "Master 41% saved")
			_check(is_equal_approx(float(written.get_value("audio", "KilosMusic", -1.0)), 28.0), "Music 28% retained")
			_check(is_equal_approx(float(written.get_value("audio", "KilosSFX", -1.0)), 82.0), "Effects 82% retained")
			master.value = 0.0
			_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Master slider zero mutes immediately")
			_check(written.load(CONFIG_PATH) == OK and is_zero_approx(float(written.get_value("audio", "Master", -1.0))), "Master exactly 0% saved")

		scene.queue_free()
		await process_frame
		var fallback := PREFS.new() as Control
		root.add_child(fallback)
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		_check(fallback.find_child("MuteCheck", true, false) == null, "fallback Settings never recreates mute switch")
		_check(fallback.find_child("ToggleMuteallaudioRow", true, false) == null, "fallback Settings never recreates mute row")
		_check(fallback.find_child("FullscreenCheck", true, false) is CheckButton, "fallback Display switch retained")
		fallback.queue_free()
		await process_frame

		# A missing saved file must also release an obsolete in-memory mute.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_PATH))
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)
		PREFS.restore_saved_preferences(false)
		_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "missing preferences cannot leave stale mute enabled")

	for name in old_bus:
		var index := AudioServer.get_bus_index(name)
		AudioServer.set_bus_volume_db(index, old_bus[name][0])
		AudioServer.set_bus_mute(index, old_bus[name][1])
	for i in range(new_buses.size() - 1, -1, -1):
		AudioServer.remove_bus(AudioServer.get_bus_index(new_buses[i]))
	if had_file:
		var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
		_check(file != null, "original settings file reopened for restore")
		if file != null:
			file.store_buffer(old_bytes)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_PATH))

	for failure in failures:
		push_error(failure)
	print("SETTINGS_MUTE_RETIREMENT %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
