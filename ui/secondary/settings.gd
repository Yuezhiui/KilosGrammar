extends Control

signal requested(target: String, payload: Dictionary)

@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value: Label = %VolumeValue
@onready var mute_check: CheckButton = %MuteCheck
@onready var fullscreen_check: CheckButton = %FullscreenCheck

var _context: Dictionary = {}
var _master_bus := 0


func _ready() -> void:
	_master_bus = AudioServer.get_bus_index("Master")
	if _master_bus < 0:
		_master_bus = 0
	_sync_from_system()
	volume_slider.value_changed.connect(_on_volume_changed)
	mute_check.toggled.connect(_on_mute_toggled)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	%BackButton.pressed.connect(_request_main)
	%BackButton.grab_focus()


func set_context(context: Dictionary) -> void:
	_context = context.duplicate(true)


func _sync_from_system() -> void:
	var volume_linear := db_to_linear(AudioServer.get_bus_volume_db(_master_bus))
	volume_slider.set_value_no_signal(clampf(volume_linear * 100.0, 0.0, 100.0))
	mute_check.set_pressed_no_signal(AudioServer.is_bus_mute(_master_bus))
	var mode := DisplayServer.window_get_mode()
	fullscreen_check.set_pressed_no_signal(mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	_update_volume_label(volume_slider.value)


func _on_volume_changed(value: float) -> void:
	var linear := clampf(value / 100.0, 0.0001, 1.0)
	AudioServer.set_bus_volume_db(_master_bus, linear_to_db(linear))
	_update_volume_label(value)


func _on_mute_toggled(enabled: bool) -> void:
	AudioServer.set_bus_mute(_master_bus, enabled)


func _on_fullscreen_toggled(enabled: bool) -> void:
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)


func _update_volume_label(value: float) -> void:
	volume_value.text = "%d%%" % int(round(value))


func _request_main() -> void:
	requested.emit("main", _context.duplicate(true))
