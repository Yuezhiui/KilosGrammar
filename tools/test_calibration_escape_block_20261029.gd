extends SceneTree

# Regression: Escape must never leave Calibration, including key-repeat and
# release events. The scene-authored BackButton remains the way to return.
# Run with Godot 4.7.2:
#   Godot_v4.7.2-stable_win64_console.exe --headless --path . \
#     --script res://tools/test_calibration_escape_block_20261029.gd
# No webcam, pose capture, score persistence, or successful calibration is
# required. Routing is exercised in the real main menu controller.

const MAIN_MENU := "res://ui/main_menu/main_menu.tscn"
const CALIBRATION := "res://ui/vision/calibration/calibration.tscn"

class GameplayPauseProbe extends Control:
	var pauses := 0
	func _pause() -> void:
		pauses += 1

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(MAIN_MENU) as PackedScene
	_check(packed != null, "main menu scene loads")
	var calibration_packed := load(CALIBRATION) as PackedScene
	_check(calibration_packed != null, "calibration scene loads")
	if packed == null or calibration_packed == null:
		_finish()
		return
	var app := packed.instantiate() as Control
	root.add_child(app)
	await process_frame
	# The menu normally opens calibration through routing, which starts YOLO.
	# Set only the router state here: do not start the webcam for key handling.
	var baseline: Dictionary = (app.get("session_state") as Dictionary).duplicate(true)
	app.set("current_route", "calibration")
	var previous_panel: Node = app.get("active_panel") as Node
	for event in [_key(true, false), _key(true, true), _key(false, false)]:
		# Dispatch a real viewport input event as well as a direct unhandled
		# callback, so the test covers both Godot delivery and the router guard.
		root.push_input(event, true)
		_check(String(app.get("current_route")) == "calibration",
			"viewport Escape cannot navigate from calibration (pressed=%s echo=%s)" %
			[event.pressed, event.echo])
		app.call("_unhandled_input", event)
		_check(root.is_input_handled(),
			"calibration Escape is consumed (pressed=%s echo=%s)" %
			[event.pressed, event.echo])
		_check(String(app.get("current_route")) == "calibration",
			"direct Escape handler cannot navigate from calibration")
		_check(app.get("active_panel") == previous_panel,
			"Escape does not destroy or replace the active calibration panel")
		_check(app.get("session_state") == baseline,
			"Escape preserves student/round context")
	# Game Escape must still call the actual minigame pause hook.
	var pause_probe := GameplayPauseProbe.new()
	root.add_child(pause_probe)
	app.set("active_panel", pause_probe)
	app.set("current_route", "gameplay")
	app.call("_unhandled_input", _key(true, false))
	_check(pause_probe.pauses == 1, "Escape in gameplay still calls _pause once")
	_check(String(app.get("current_route")) == "gameplay",
		"gameplay pause hook retains ownership of the route transition")
	app.set("active_panel", previous_panel)
	pause_probe.queue_free()
	# An ordinary selection screen must continue to use the existing Escape
	# back mapping, while Calibration is explicitly blocked.
	app.set("current_route", "play_topic")
	app.call("_unhandled_input", _key(true, false))
	_check(String(app.get("current_route")) == "play_activity",
		"Escape in play_topic still returns to play_activity")
	# Check the real Calibration scene's editor-authored button contract without
	# calling set_context(), which would try to start a camera.
	var calibration := calibration_packed.instantiate() as Control
	root.add_child(calibration)
	calibration.set_process(false)
	var back := calibration.get_node_or_null("TutorialStage/Navigation/BackButton") as Button
	_check(back != null, "calibration still owns editor-authored BackButton")
	var requested: Array[String] = []
	calibration.requested.connect(func(target: String, _payload: Dictionary) -> void:
		requested.append(target)
	)
	# The actual Calibration panel stays mounted while the menu routes ESC.
	app.set("active_panel", calibration)
	app.set("current_route", "calibration")
	root.push_input(_key(true, false), true)
	await process_frame
	_check(String(app.get("current_route")) == "calibration",
		"real mounted Calibration panel remains open after Escape")
	_check(app.get("active_panel") == calibration and is_instance_valid(calibration),
		"Escape does not free or replace the real Calibration panel")
	_check(requested.is_empty(), "Escape never fires Calibration's BackButton signal")
	# After the three-second intro, Back is visible and can hold keyboard focus.
	# Escape must still stay on Calibration in that actual interaction state.
	calibration.call("_process", 3.2)
	await process_frame
	if back != null:
		_check(back.is_visible_in_tree() and not back.disabled,
			"editor-authored Back is visible after calibration intro")
		back.grab_focus()
		await process_frame
		root.push_input(_key(true, false), true)
		_check(String(app.get("current_route")) == "calibration",
			"focused Back does not turn Escape into navigation")
		_check(requested.is_empty(), "focused Back only activates from its own action")
	# A physical Escape key with no logical keycode is still suppressed.
	var physical_escape := _key(true, false)
	physical_escape.keycode = KEY_NONE
	app.call("_unhandled_input", physical_escape)
	_check(String(app.get("current_route")) == "calibration",
		"physical Escape without logical keycode is blocked")
	_check(root.is_input_handled(), "physical Escape marks the event handled")
	if back != null:
		_check(back.owner == calibration, "BackButton remains editable in calibration.tscn")
		_check(not back.disabled, "BackButton remains enabled")
		back.pressed.emit()
		_check(requested == ["play_activity"],
			"BackButton still requests activity selection")
	app.set("active_panel", previous_panel)
	calibration.queue_free()
	await process_frame
	await process_frame
	app.call("_return_to_main")
	await app.call("prepare_for_shutdown")
	app.queue_free()
	await process_frame
	await process_frame
	_finish()


func _key(pressed: bool, echo: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = pressed
	event.echo = echo
	return event


func _check(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures.append(detail)
		printerr("CALIBRATION ESCAPE FAIL: " + detail)


func _finish() -> void:
	print("CALIBRATION ESCAPE BLOCK: %s | checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
