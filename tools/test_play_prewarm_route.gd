extends SceneTree

# Menu-only routing predicate. No camera/process/DB is instantiated.
# Godot --headless --path . --script res://tools/test_play_prewarm_route.gd

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu := (load("res://ui/main_menu/main_menu.gd") as Script).new() as Control
	_check(menu != null, "Main Menu script loads")
	if menu == null:
		_finish()
		return
	menu.set("current_route", "main")
	_check(bool(menu.call("_should_prewarm_for_student_setup", "student_setup", {})),
		"Main Menu Play prewarms pose before an activity is chosen")
	menu.set("current_route", "play_activity")
	for activity in ["Catch the Word", "Balloon Popping", "Human Plane"]:
		_check(bool(menu.call("_should_prewarm_for_student_setup", "student_setup",
			{"activity": activity})),
			"Tutorial prewarms selected " + activity)
	_check(not bool(menu.call("_should_prewarm_for_student_setup", "student_setup",
		{"activity": "Not a camera activity"})),
		"No prewarm for an unknown selected activity")
	_check(not bool(menu.call("_should_prewarm_for_student_setup", "play_topic",
		{"activity": "Catch the Word"})),
		"No repeated student-setup prewarm on unrelated routes")
	menu.set("current_route", "results")
	for retry_route in ["retry", "play_again", "last_play", "student_setup"]:
		_check(bool(menu.call("_should_prewarm_for_student_setup", retry_route,
			{"activity": "Catch the Word"})),
			"Results -> " + retry_route + " prewarms YOLO during the new student form")
	menu.set("current_route", "pause")
	_check(bool(menu.call("_should_prewarm_for_student_setup", "student_setup", {})),
		"Pause -> new student setup prewarms YOLO without opening the webcam")
	menu.set("current_route", "main")
	_check(not bool(menu.call("_should_prewarm_for_student_setup", "retry", {})),
		"Unrelated Main Menu Retry event cannot trigger a camera model")
	menu.free()
	_finish()


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL PLAY PREWARM ROUTE: ", label)


func _finish() -> void:
	print("PLAY PREWARM ROUTE: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
