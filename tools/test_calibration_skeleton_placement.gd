extends SceneTree

## No hardware/YOLO: inspect and adjust the manually editable green-skeleton
## placement control without changing actual student pose measurements.
const SCENE_PATH := "res://ui/vision/calibration/calibration.tscn"
var errors: Array[String] = []
var checks := 0


func _check(ok: bool, detail: String) -> void:
	checks += 1
	if not ok:
		errors.append(detail)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pose_service := root.get_node_or_null("PoseService")
	_check(pose_service != null, "PoseService autoload is available")
	if pose_service == null:
		quit(1)
		return
	var scene := load(SCENE_PATH) as PackedScene
	_check(scene != null, "Calibration scene loads")
	if scene == null:
		quit(1)
		return
	var original_offset: Vector2 = pose_service.skeleton_visual_offset
	var original_scale: Vector2 = pose_service.skeleton_visual_scale
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = dimensions
		var calibration := scene.instantiate() as Control
		root.add_child(calibration)
		calibration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		calibration.set_process(false)
		var stage := calibration.get_node("TutorialStage") as Control
		var video := stage.get_node("CameraArea/LiveCameraInset") as TextureRect
		var placement := stage.get_node("CameraArea/SkeletonPlacement") as ReferenceRect
		_check(placement.owner == calibration, "SkeletonPlacement persists as editor-authored node at %s" % dimensions)
		_check(placement.get_parent() == video.get_parent(), "Overlay transform is separately editable beside live camera")
		_check(placement.editor_only, "The adjustment border is invisible to students")
		var authored_offset := (placement.position - video.position) / video.size
		var authored_scale := placement.size / video.size
		_check(placement.size.x > 0 and placement.size.y > 0,
			"Authored skeleton overlay has editable positive dimensions at %s" % dimensions)
		calibration.call("_apply_skeleton_placement")
		_check(pose_service.skeleton_visual_offset.is_equal_approx(authored_offset) and
			pose_service.skeleton_visual_scale.is_equal_approx(authored_scale),
			"Visual transform matches actual editor-authored overlay")
		placement.position += Vector2(40, 20)
		placement.size *= Vector2(0.85, 0.75)
		calibration.call("_apply_skeleton_placement")
		_check(pose_service.skeleton_visual_offset.is_equal_approx(authored_offset + Vector2(40, 20) / video.size),
			"2D editor position offsets the visual bones with proportional camera coordinates")
		_check(pose_service.skeleton_visual_scale.is_equal_approx(authored_scale * Vector2(0.85, 0.75)),
			"2D editor resizing scales the green bones independently of camera")
		_check(video.size.is_equal_approx(Vector2(1007, 446)),
			"Original camera dimensions remain unchanged by skeleton placement")
		calibration.queue_free()
		await process_frame
	pose_service.set_skeleton_visual_transform(original_offset, original_scale)
	if errors.is_empty():
		print("PASS calibration skeleton editor placement: %d assertions, no camera/YOLO" % checks)
		quit(0)
	else:
		for reason in errors:
			push_error(reason)
		quit(1)
