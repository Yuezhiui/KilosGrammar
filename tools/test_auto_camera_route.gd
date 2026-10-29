extends SceneTree

## Camera-play navigation regression: fake an available camera so this test
## never opens the webcam or downloads weights.
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := root.get_node("PoseService")
	service.stop_camera()
	service.set_process(false) # Never start a real pose worker in this routing fixture.
	service.active = true
	service.current_status = {"state": "tracking", "pose": true}
	service.player_x = 0.5
	service.last_pose_ms = Time.get_ticks_msec()
	var app := (load("res://ui/main_menu/main_menu.tscn") as PackedScene).instantiate() as Control
	root.add_child(app)
	app.call("_on_panel_requested", "play_activity", {
		"entry_source": "play", "student_id": "test", "student_name": "Test",
		"grade_section": "Grade 5", "game_style": "Noun", "topic": "Noun",
		"game_mode": "Seconds", "difficulty": "Easy"
	})
	await process_frame # Let deferred focus settle before swapping routes.
	var select := app.get("active_panel") as Control
	var activity_buttons: Dictionary = select.get("activity_buttons")
	(activity_buttons["Catch the Word"] as Button).pressed.emit()
	(select.get("next_button") as Button).pressed.emit()
	await process_frame # Allow calibration's deferred focus callback to finish.
	var route := String(app.get("current_route"))
	_expect(route == "calibration", "Camera Play enters calibration without a separate Camera Check screen")
	_expect(bool((app.get("session_state") as Dictionary).get("camera_requested", false)), "Camera request is explicit in Play payload")
	var calibration := app.get("active_panel") as Control
	# Mode-specific illustrations are independently authored; Plane side
	# guides are demonstration visuals after its single physical center hold.
	for guide in ["PoseGuides/PoseGuideDefault", "PoseGuides/PoseGuideBalloonRaise", "PoseGuides/PoseGuidePlaneCenter"]:
		_expect(calibration.get_node_or_null("TutorialStage/" + guide) is TextureRect,
			"Editor-authored calibration retains " + guide)
	for demo_guide in ["PoseGuides/PoseGuidePlaneLeft", "PoseGuides/PoseGuidePlaneRight"]:
		var guide_node := calibration.get_node_or_null("TutorialStage/" + demo_guide) as TextureRect
		_expect(guide_node != null and guide_node.size == Vector2(767, 484)
			and guide_node.position == Vector2(262, 66),
			"Plane side illustration shares T-pose guide geometry: " + demo_guide)
	for obsolete in ["CenterCalibrationLane", "LeftCalibrationLane", "RightCalibrationLane",
			"ArtGuideCenter", "ArtGuideLeft", "ArtGuideRight"]:
		_expect(calibration.get_node_or_null("TutorialStage/" + obsolete) == null,
			"Dead calibration node removed: " + obsolete)
	_expect(calibration.get_node_or_null("TutorialStage/CameraArea/LiveCameraInset") is TextureRect,
		"Camera preview remains independently editor-authored")
	for removed in ["DemoButton", "RetryButton", "SkipButton", "KeyboardButton"]:
		_expect(calibration.get_node_or_null("TutorialStage/" + removed) == null,
			"Calibration no longer exposes deleted action: " + removed)
	_expect(calibration.get_node_or_null("TutorialStage/Navigation/BackButton") is Button,
		"Teacher Back to Main is available")
	app.call("_return_to_main")
	_expect(not service.active, "Returning home closes camera session")
	if app.has_method("prepare_for_shutdown"):
		await app.call("prepare_for_shutdown")
	app.queue_free()
	await process_frame
	await process_frame
	print("AUTO CAMERA ROUTE: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)


func _expect(valid: bool, message: String) -> void:
	if not valid:
		failures += 1
		printerr("FAIL camera-route: ", message)
