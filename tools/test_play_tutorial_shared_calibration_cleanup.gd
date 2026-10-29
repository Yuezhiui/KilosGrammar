extends SceneTree

# Headless scene/router contract. No camera, database, or score writes.
# Complements test_play_navigation_persistence.gd (mock persistence paths).
const REMOVED := [
	"PlaneSteeringFootnote", "PlaneSteeringTitle", "InstructionLabel",
	"BadgeLabel", "PlayerLabel", "StatusCapsule", "PlaneStepBadge",
	"CenterOnlyLabel", "ArtStars", "Heading", "StageHeading",
	"InstructionFIL", "Description", "StepBadgeBackground", "StepBadge",
	"CountdownLabel"
]
const POSES := [
	"PoseGuideDefault", "PoseGuideBalloonRaise", "PoseGuidePlaneCenter"
]
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu_script := load("res://ui/main_menu/main_menu.gd") as Script
	var menu_scene := load("res://ui/main_menu/main_menu.tscn") as PackedScene
	var calibration_scene := load("res://ui/vision/calibration/calibration.tscn") as PackedScene
	var gameplay_scene := load("res://ui/play/gameplay/gameplay.tscn") as PackedScene
	_check(menu_script != null and menu_scene != null and calibration_scene != null and gameplay_scene != null,
		"MainMenu, shared calibration, and gameplay resources parse")
	if menu_script == null or calibration_scene == null:
		_finish()
		return
	var source := menu_script.source_code
	_check(source.contains('"calibration": "res://ui/vision/calibration/calibration.tscn"'),
		"Both modes resolve one calibration scene via MainMenu router")
	_check(source.contains('"gameplay": "res://ui/play/gameplay/gameplay.tscn"'),
		"Successful calibration routes to shared gameplay scene")
	_check(source.contains('route = "calibration"') and source.contains('current_route == "calibration"'),
		"Router enforces calibration entry and recognizes calibration completion")
	_check(source.contains('"guided_tutorial"') and source.contains('"entry_source"'),
		"Router retains distinct Tutorial/Play provenance")
	_check(source.contains('if bool(state.get("guided_tutorial", false)) or String(state.get("entry_source", "")) == "tutorial"'),
		"Direct score-save function rejects Tutorial even on completed rounds")
	var view := calibration_scene.instantiate() as Control
	_check(view != null, "Shared calibration scene instantiates")
	if view != null:
		var stage := view.get_node_or_null("TutorialStage") as Control
		_check(stage != null, "Calibration stage exists")
		if stage != null:
			for name in REMOVED:
				_check(stage.find_child(name, true, false) == null,
					"Obsolete control absent from both routes: " + name)
			for name in POSES:
				var pose := stage.find_child(name, true, false) as TextureRect
				_check(pose != null and pose.texture != null and pose.owner == view,
						"Mode-appropriate PNG guide authored and shared by both modes: " + name)
			for retired in ["PoseGuidePlaneLeft", "PoseGuidePlaneRight"]:
				_check(stage.find_child(retired, true, false) == null,
					"Retired unused directional T-pose duplicate absent: " + retired)
			for name in ["ArtGuideCenter", "ArtGuideRight", "ArtGuideLeft", "CenterCalibrationLane", "RightCalibrationLane", "LeftCalibrationLane", "ArtCountdownBadge"]:
				_check(stage.find_child(name, true, false) == null, "Retired calibration visual absent: " + name)
		_check(view.get_script() != null and view.get_script().resource_path == "res://ui/vision/calibration/calibration.gd",
			"Both routes use the same calibration controller")
		view.free()
	_finish()


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _finish() -> void:
	for failure in failures:
		printerr("FAIL shared calibration cleanup: ", failure)
	print("SHARED PLAY/TUTORIAL CALIBRATION CLEANUP: ",
		"PASS" if failures.is_empty() else "FAIL", " (", checks, " checks, ", failures.size(), " failures)")
	quit(0 if failures.is_empty() else 1)
