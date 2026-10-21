extends SceneTree

# Run: Godot --headless --path . --script res://tools/test_button_sound_wiring.gd
# Checks actual signal hookups and KilosSFX playback nodes; no audio device needed.
const ROUTER: Script = preload("res://ui/shared/button_sound_wiring.gd")
const HOVER: AudioStream = preload("res://assets/audio/lexispell_intro/button_hover.wav")
const CLICK: AudioStream = preload("res://assets/audio/lexispell_intro/button_click.wav")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var bus_index := AudioServer.get_bus_index("KilosSFX")
	var created_bus := false
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, "KilosSFX")
		AudioServer.set_bus_send(bus_index, "Master")
		created_bus = true
	var initial_volume := AudioServer.get_bus_volume_db(bus_index)
	var initial_mute := AudioServer.is_bus_mute(bus_index)
	AudioServer.set_bus_volume_db(bus_index, -13.0)
	AudioServer.set_bus_mute(bus_index, true)

	var router: Node = ROUTER.new()
	root.add_child(router)
	var panel := Control.new()
	root.add_child(panel)
	var container := VBoxContainer.new()
	panel.add_child(container)
	var button := Button.new()
	button.text = "Start"
	container.add_child(button)
	router.call("watch", panel)
	router.call("watch", panel) # Connecting twice must not duplicate playback.
	await process_frame
	_assert(button.mouse_entered.get_connections().size() == 1, "Expected one hover callback")
	_assert(button.button_down.get_connections().size() == 1, "Expected one click callback")
	_assert(button.focus_entered.get_connections().size() == 1, "Expected one focus callback")
	button.mouse_entered.emit()
	_assert(_players(router).size() == 0, "Artificial initial hover should be silent")
	button.focus_entered.emit()
	_assert(_players(router).size() == 0, "Programmatic focus should be silent")
	var keyboard_navigation := InputEventKey.new()
	keyboard_navigation.keycode = KEY_TAB
	keyboard_navigation.pressed = true
	router.call("_input", keyboard_navigation)
	_assert(int(router.get("_navigation_frame")) == Engine.get_process_frames(), "Keyboard navigation was not detected")
	router.call("_input", InputEventMouseMotion.new())
	_assert(int(router.get("_navigation_frame")) == -1, "Pointer motion did not clear keyboard navigation intent")
	button.set_meta("kilos_button_sfx_pointer_origin", Vector2(-200, -200))
	button.mouse_entered.emit()
	_check_last(router, HOVER, -4.0, 1, "Move-to-hover")
	button.button_down.emit()
	_check_last(router, CLICK, -1.0, 2, "Main click")
	router.set("_navigation_frame", Engine.get_process_frames())
	button.focus_entered.emit()
	_assert(_players(router).size() == 2, "Focus and pointer hover doubled in one frame")
	await process_frame
	router.set("_navigation_frame", Engine.get_process_frames())
	button.focus_entered.emit()
	_check_last(router, HOVER, -4.0, 3, "Keyboard focus hover")
	router.set("_navigation_frame", -1)
	_assert(AudioServer.is_bus_mute(bus_index), "Sound routing altered saved mute")
	_assert(is_equal_approx(AudioServer.get_bus_volume_db(bus_index), -13.0), "Sound routing altered SFX volume")

	# A tab/check button created AFTER watch() must be connected without a
	# second manual scan or double-playing its toggled/pressed signals.
	var dynamic_group := HBoxContainer.new()
	container.add_child(dynamic_group)
	var toggle := CheckButton.new()
	toggle.text = "Mute"
	dynamic_group.add_child(toggle)
	var texture := TextureButton.new()
	dynamic_group.add_child(texture)
	var link := LinkButton.new()
	link.text = "Open"
	dynamic_group.add_child(link)
	await process_frame
	_assert(toggle.button_down.get_connections().size() == 1, "Late CheckButton was not wired once")
	_assert(texture.button_down.get_connections().size() == 1, "Late TextureButton was not wired once")
	_assert(link.button_down.get_connections().size() == 1, "Late LinkButton was not wired once")
	toggle.set_pressed_no_signal(true)
	toggle.toggled.emit(true)
	toggle.pressed.emit()
	_assert(_players(router).size() == 3, "Programmatic toggle/pressed played an extra sound")
	toggle.button_down.emit()
	_check_last(router, CLICK, -1.0, 4, "Toggle activation")
	texture.button_down.emit()
	_check_last(router, CLICK, -1.0, 5, "Texture button activation")
	link.button_down.emit()
	_check_last(router, CLICK, -1.0, 6, "Link button activation")

	button.disabled = true
	button.button_down.emit()
	button.mouse_entered.emit()
	_assert(_players(router).size() == 6, "Disabled button played")
	button.disabled = false
	panel.hide()
	button.button_down.emit()
	_assert(_players(router).size() == 6, "Hidden ancestor played")
	panel.show()
	button.set_meta("kilos_button_sfx_pointer_origin", Vector2(-200, -200))
	panel.hide()
	panel.show()
	button.mouse_entered.emit()
	_assert(_players(router).size() == 6, "Revealed tab played an artificial initial hover")
	button.modulate.a = 0.0
	button.button_down.emit()
	_assert(_players(router).size() == 6, "Alpha-hidden button played")
	button.modulate.a = 1.0
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.mouse_entered.emit()
	_assert(_players(router).size() == 6, "Mouse-ignore button hovered audibly")

	# New subtrees from a dialog/next route are picked up, too.
	var next_panel := Control.new()
	panel.add_child(next_panel)
	var next_button := Button.new()
	next_panel.add_child(next_button)
	await process_frame
	next_button.button_down.emit()
	_check_last(router, CLICK, -1.0, 7, "Dynamic nested panel activation")
	router.call("watch", panel)
	next_button.button_down.emit()
	_check_last(router, CLICK, -1.0, 8, "Repeated recursive watch")

	for player: AudioStreamPlayer in _players(router):
		player.stop()
		player.stream = null
	panel.queue_free()
	router.queue_free()
	await process_frame
	await process_frame
	# The audio mixer can hold stream references briefly after players stop.
	await create_timer(0.5).timeout
	AudioServer.set_bus_mute(bus_index, initial_mute)
	AudioServer.set_bus_volume_db(bus_index, initial_volume)
	if created_bus:
		AudioServer.remove_bus(bus_index)
	for failure in failures:
		push_error(failure)
	print("BUTTON_SOUND_WIRING: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " issues)")
	quit(0 if failures.is_empty() else 1)


func _players(parent: Node) -> Array[AudioStreamPlayer]:
	var result: Array[AudioStreamPlayer] = []
	for child in parent.get_children():
		if child is AudioStreamPlayer:
			result.append(child as AudioStreamPlayer)
	return result


func _check_last(router: Node, expected_stream: AudioStream, expected_db: float, count: int, reason: String) -> void:
	var players := _players(router)
	_assert(players.size() == count, "%s produced %d sounds, expected %d" % [reason, players.size(), count])
	if players.is_empty():
		return
	var last: AudioStreamPlayer = players.back()
	_assert(last.stream == expected_stream, "%s used wrong sound" % reason)
	_assert(last.bus == "KilosSFX", "%s did not use KilosSFX" % reason)
	_assert(is_equal_approx(last.volume_db, expected_db), "%s changed playback gain" % reason)


func _assert(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
