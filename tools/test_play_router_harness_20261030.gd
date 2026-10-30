extends "res://ui/main_menu/main_menu.gd"

## The production main-menu controller with its real scene router, isolated
## from database startup, camera, persistent preferences, and intro animations.
## Only the calibration screen is intercepted before it starts a real webcam.
var route_history: Array[String] = []
var intercepted_calibration_payload: Dictionary = {}


func _ready() -> void:
	_setup_panel_host()
	button_sounds = BUTTON_SOUND_WIRING.new() as Node
	add_child(button_sounds)
	intro_done = true
	fall_timer.stop()
	# Production _process animates menu tiles using _ready's populated home
	# position dictionaries; the test intentionally does not run that intro.
	set_process(false)
	# Reuse the same physical Play/Tutorial Button -> _on_main_navigation
	# signal bindings as production MainMenu._ready, while skipping its DB boot.
	$MainLayer/CenterMenu/Play.pressed.connect(_on_main_navigation.bind("student_setup"))
	$MainLayer/CenterMenu/Tutorial.pressed.connect(_on_main_navigation.bind("tutorial_home"))


func _request_camera_model_prewarm() -> void:
	pass


func _sync_title_music_for_route(_route: String) -> void:
	pass


func _show_panel(route: String) -> void:
	route_history.append(route)
	if route == "calibration":
		# Check the actual route target exists while keeping PoseService off.
		assert(ResourceLoader.exists(PANEL_SCENES["calibration"]))
		intercepted_calibration_payload = session_state.duplicate(true)
		if is_instance_valid(active_panel):
			panel_host.remove_child(active_panel)
			active_panel.queue_free()
		active_panel = Control.new()
		active_panel.name = "CalibrationCameraSuppressedByQA"
		panel_host.add_child(active_panel)
		active_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		current_route = route
		return
	super._show_panel(route)
