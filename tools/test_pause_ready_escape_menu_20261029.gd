extends "res://tools/test_calibration_countdown_offline_menu.gd"

## QA-only MainMenu subclass. Real Play/Countdown/Pause/Results panels are
## mounted, but an actual Restart -> Calibration is intercepted at the FINAL
## mount boundary to ensure this headless fixture cannot open any webcam.
var intercepted_calibration_routes := 0


func _request_camera_model_prewarm() -> void:
	# MainMenu's normal Play entry intentionally starts loading YOLO; tests
	# must never create a Python process or camera prewarm worker.
	pass


func _show_panel(route: String) -> void:
	if route == "calibration":
		intercepted_calibration_routes += 1
		current_route = "calibration"
		return
	super._show_panel(route)
