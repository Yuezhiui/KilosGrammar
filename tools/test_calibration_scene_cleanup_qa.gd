extends SceneTree

# Scene-only regression for the five-PNG calibration cleanup.
# It never adds Calibration to the tree, so no camera/database runtime starts.

const SCENE_PATH := "res://ui/vision/calibration/calibration.tscn"
const REMOVED_STAGE_NODES := [
	"ArtGuideLeft",
	"ArtGuideCenter",
	"ArtGuideRight",
	"LeftCalibrationLane",
	"CenterCalibrationLane",
	"RightCalibrationLane",
	"ArtArrow",
	"ArtMoveHint",
	"ArtCountdownBadge",
	"PosePlacementCenter",
	"PosePlacementLeft",
	"PosePlacementRight",
]
const REMOVED_USER_NODES := [
	"PlaneSteeringFootnote", "PlaneSteeringTitle", "InstructionLabel",
	"BadgeLabel", "PlayerLabel", "StatusCapsule", "PlaneStepBadge",
	"CenterOnlyLabel", "ArtStars", "Heading", "StageHeading",
	"InstructionFIL", "Description", "StepBadgeBackground", "StepBadge",
	"CountdownLabel"
]
const REQUIRED_POSE_GUIDES := [
	"PoseGuideDefault",
	"PoseGuideLeft",
	"PoseGuideRight",
	"PoseGuideBalloonRaise",
	"PoseGuideBalloonRaiseLeft",
	"PoseGuideBalloonRaiseRight",
	"PoseGuidePlaneCenter",
	"PoseGuidePlaneLeft",
	"PoseGuidePlaneRight",
]
const REQUIRED_ACTIVE_STAGE_NODES := [
	"CameraArea/CameraFrame",
	"CameraArea/LiveCameraInset",
	"CameraArea/SkeletonPlacement",
	"CameraArea/ArtCameraFrame",
	"Directions/ArtArrowCenter",
	"Directions/ArtArrowRight",
	"Directions/ArtArrowLeft",
	"Directions/ArtTitleCenter",
	"Directions/ArtTitleRight",
	"Directions/ArtTitleLeft",
	"Directions/ArtStep1",
	"Directions/ArtStep2",
	"Directions/ArtStep3",
	"CountdownArtwork/ArtCountdown1",
	"CountdownArtwork/ArtCountdown2",
	"CountdownArtwork/ArtCountdown3",
	"Directions/ArtMoveHintCenter",
	"Directions/ArtMoveHintRight",
	"Directions/ArtMoveHintLeft",
	"CameraFeedback/CameraStatusLabel",
	"CameraFeedback/ProgressLabel",
	"Navigation/BackButton",
	"IntroOverlay",
	"IntroOverlay/ArtIntroTitle",
	"SuccessOverlay",
	"SuccessOverlay/SuccessTitle",
	"SuccessOverlay/SuccessSubtitle",
]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_check(packed != null, "Calibration scene parses as PackedScene")
	if packed == null:
		_finish()
		return
	var calibration := packed.instantiate()
	_check(calibration != null, "Calibration scene instantiates")
	if calibration == null:
		_finish()
		return
	var stage := calibration.get_node_or_null("TutorialStage")
	_check(stage != null, "TutorialStage remains present")
	if stage != null:
		for retired_intro in ["IntroHeading", "IntroDescription", "IntroCountdown", "IntroBackButton"]:
			_check(stage.get_node_or_null("IntroOverlay/" + retired_intro) == null,
				"Retired intro duplicate removed rather than only hidden: " + retired_intro)
		for node_name in REMOVED_STAGE_NODES:
			_check(stage.find_child(node_name, true, false) == null,
				"Removed legacy node is absent: " + node_name)
		_check(REMOVED_USER_NODES.size() == 16, "Exactly sixteen user-deleted names audited")
		for deleted_name in REMOVED_USER_NODES:
			_check(stage.find_child(deleted_name, true, false) == null,
				"User-deleted control absent from all editor groups: " + deleted_name)
		for group_name in ["CameraArea", "PoseGuides", "Directions", "CountdownArtwork", "CameraFeedback", "Navigation"]:
			_check(stage.get_node_or_null(group_name) is Control,
				"Active controls under zero-offset editable group: " + group_name)
		for node_name in REQUIRED_POSE_GUIDES:
			var guide := stage.get_node_or_null("PoseGuides/" + node_name)
			_check(guide is TextureRect, "Editor-authored pose guide remains TextureRect: " + node_name)
			if guide is TextureRect:
				# The original CENTER guide and dormant Plane reference nodes
				# retain their scene-authored visibility; runtime hides other
				# phases. New LEFT/RIGHT duplicates must start hidden.
				if node_name in ["PoseGuideLeft", "PoseGuideRight", "PoseGuideBalloonRaiseLeft", "PoseGuideBalloonRaiseRight"]:
					_check(not guide.visible, "New independent guide begins hidden: " + node_name)
				_check((guide as TextureRect).texture != null,
					"Independent pose guide keeps assigned texture: " + node_name)
		for node_name in REQUIRED_ACTIVE_STAGE_NODES:
			_check(stage.get_node_or_null(node_name) != null,
				"Active/editor-authored node preserved: " + node_name)
		var camera := stage.get_node_or_null("CameraArea/LiveCameraInset") as TextureRect
		if camera != null:
			_check(camera.position == Vector2(141.0, 147.0),
				"LiveCameraInset authored position preserved")
			_check(camera.size == Vector2(1007.0, 446.0),
				"LiveCameraInset authored size preserved")
	calibration.free()

	var file := FileAccess.open(SCENE_PATH, FileAccess.READ)
	_check(file != null, "Calibration scene source is readable")
	if file != null:
		var source := file.get_as_text()
		_check(not source.contains("PARAMETERS.png"),
			"Legacy PARAMETERS.png scene resource removed")
		for style_name in ["ZoneLeft", "ZoneCenter", "ZoneRight"]:
			_check(not source.contains('id="' + style_name + '"'),
				"Legacy lane style removed: " + style_name)
		for filename in [
			"Pose Guides/DEFAULT.png",
			"Pose Guides/BALOON POP.png",
			"Pose Guides/PLANE T POSE.png",
			"Pose Guides/PLANE GOING TO LEFT.png",
			"Pose Guides/PLANE GOING TO RIGHT.png",
		]:
			_check(source.contains(filename), "Five-PNG resource retained: " + filename)
	_finish()


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("CALIBRATION CLEANUP FAIL: ", message)


func _finish() -> void:
	print("CALIBRATION SCENE CLEANUP: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL",
		checks,
		failures.size(),
	])
	quit(0 if failures.is_empty() else 1)
