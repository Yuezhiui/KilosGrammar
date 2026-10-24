extends SceneTree

# Godot --headless --path . --script res://tools/test_calibration_fullscreen_editor_layout.gd
# Contract test for the clean full-screen calibration screenshots (images 2-5).
# All foreground geometry must remain editor-authored. No camera is launched.

const CALIBRATION_PATH := "res://ui/vision/calibration.tscn"
const SIZES := [Vector2i(875, 500), Vector2i(1280, 720), Vector2i(1920, 1080)]
const STAGE := "TutorialStage"
const SOURCE_BACKGROUND := "C:/Users/Yue/Downloads/CALIB/BACKGROUND.png"
const BACKGROUND_BASENAME := "BACKGROUND.png"
const STAGES := ["CenterCalibrationLane", "RightCalibrationLane", "LeftCalibrationLane"]
const REQUIRED_PARTS := [
	"CameraBlackBacking", "LiveCameraInset", "CalibrationGuideBar", "CalibrationGuideCursor",
	"LeftCalibrationLane", "CenterCalibrationLane", "RightCalibrationLane",
	"InstructionLabel", "InstructionEN", "InstructionFIL", "CountdownLabel",
	"StepBadge", "ProgressLabel", "StageHeading", "CameraStatusLabel",
	"CameraUnavailableLabel", "IntroOverlay", "IntroOverlay/IntroCountdown",
	"BackButton", "ContinueButton"
]
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := root.get_node_or_null("PoseService")
	_expect(service != null, "PoseService autoload is present")
	if service == null:
		_finish()
		return
	# Never supply camera_requested to this layout preview. The camera must
	# remain idle, even when instantiating all three screen resolutions.
	service.stop_camera()
	# Load after project autoload initialization; preload would compile the
	# calibration script before the PoseService global has been registered.
	var calibration_scene := load(CALIBRATION_PATH) as PackedScene
	_expect(calibration_scene != null, "calibration scene loads with PoseService registered")
	if calibration_scene == null:
		_finish()
		return
	for viewport_size in SIZES:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		var screen := calibration_scene.instantiate() as Control
		_expect(screen != null, "Calibration scene instantiates")
		if screen == null:
			continue
		var authored_controls: Array[String] = []
		_collect_control_paths(screen, screen, authored_controls)
		root.add_child(screen)
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			# Layout inspection never enters an actual camera session.
			# Do not call set_context() here: production intentionally requests
			# PoseService for all real entries, with no keyboard shortcut.
		await process_frame
		await process_frame
		screen.set_process(false)

		_expect(_in_bounds(screen.get_global_rect(), viewport_size), "screen fills %s" % viewport_size)
		var stage := screen.get_node_or_null(STAGE) as Control
		_expect(stage != null and stage.owner == screen, "stage is authored in .tscn")
		if stage != null:
			var stage_rect := stage.get_global_rect()
			_expect(_in_bounds(stage_rect, viewport_size), "stage stays within %s" % viewport_size)
			_expect(stage_rect.size.x >= viewport_size.x * 0.82
				and stage_rect.size.y >= viewport_size.y * 0.82,
				"calibration uses most of the %s display" % viewport_size)
			for path in REQUIRED_PARTS:
				var item := stage.get_node_or_null(path) as Control
				_expect(item != null, "%s is an editable scene node" % path)
				if item == null:
					continue
				_expect(item.owner == screen, "%s persists in the editor" % path)
				_expect(_in_bounds(item.get_global_rect(), viewport_size), "%s remains on screen at %s" % [path, viewport_size])
			for lane_name in ["LeftCalibrationLane", "CenterCalibrationLane", "RightCalibrationLane"]:
				var lane := stage.get_node_or_null(lane_name) as Control
				if lane == null:
					continue
				var zone_label := lane.get_node_or_null(lane_name.trim_suffix("CalibrationLane") + "Name") as Label
				_expect(zone_label != null and zone_label.owner == screen,
					"%s has separately editable zone instructions" % lane_name)
			var camera_view := stage.get_node_or_null("LiveCameraInset") as TextureRect
			var backing := stage.get_node_or_null("CameraBlackBacking") as ColorRect
			if camera_view != null:
				_expect(camera_view.get_global_rect().size.x >= stage_rect.size.x * 0.55,
					"camera presentation is wide enough for whole-screen positioning")
				_expect(camera_view.texture == null and not camera_view.visible,
					"without a camera, no dummy snapshot is shown as live video")
			if backing != null and camera_view != null:
				_expect(backing.color.r < 0.08 and backing.color.g < 0.08
					and backing.color.b < 0.08 and backing.color.a > 0.95,
					"live-video fallback is an opaque black preview slot")
				_expect(backing.get_global_rect().encloses(camera_view.get_global_rect()),
					"live video TextureRect aligns with camera's black inset")
				var camera_rect := camera_view.get_global_rect()
				for lane_name in STAGES:
					var lane := stage.get_node_or_null(lane_name) as Control
					if lane != null:
						_expect(camera_rect.encloses(lane.get_global_rect()),
							"%s is an editable standing guide fully INSIDE live camera preview" % lane_name)
						var rect := lane.get_global_rect()
						_expect(rect.size.y >= rect.size.x * 1.15,
							"%s is a tall standing outline, not a wide lane card" % lane_name)
						var stroke := lane.get_theme_stylebox("panel") as StyleBoxFlat
						_expect(stroke != null and stroke.border_width_left >= 3
							and stroke.shadow_size >= 4 and stroke.shadow_color.a > 0.5,
							"%s has a clearly authored glowing border" % lane_name)
			var back := stage.get_node_or_null("BackButton") as Button
			_expect(back != null and back.text.to_upper().contains("MAIN"),
				"Back button explicitly returns to Main")
			if back != null:
				_expect(back.focus_mode == Control.FOCUS_ALL, "Back to Main supports keyboard navigation")
			for removed in ["SkipButton", "RetryButton", "DemoButton", "KeyboardButton"]:
				_expect(stage.get_node_or_null(removed) == null,
					"deleted control cannot be edited or clicked: " + removed)

			var background := screen.get_node_or_null("ClassroomBackground") as TextureRect
			_expect(background != null, "exact CALIB background has an independent TextureRect")
			if background != null:
				_expect(background.owner == screen and _in_bounds(background.get_global_rect(), viewport_size),
					"CALIB background remains scene-authored and viewport-sized")
				_expect(background.texture != null and background.texture.resource_path.get_file() == BACKGROUND_BASENAME,
					"CALIB background is the user's NEW supplied PNG, not previous PLAY art")
				if FileAccess.file_exists(SOURCE_BACKGROUND) and background.texture != null:
					var installed := ProjectSettings.globalize_path(background.texture.resource_path)
					_expect(FileAccess.get_sha256(SOURCE_BACKGROUND) == FileAccess.get_sha256(installed),
						"installed CALIB PNG is byte-identical to user's supplied original")
			var dimmer := screen.get_node_or_null("ClassroomDimmer") as ColorRect
			_expect(dimmer != null and dimmer.owner == screen, "bright-reference dimmer is editor-authored")
			if dimmer != null:
				_expect(_in_bounds(dimmer.get_global_rect(), viewport_size),
					"subtle black dimmer covers the entire viewport")
				_expect(dimmer.color.r <= 0.01 and dimmer.color.g <= 0.01 and dimmer.color.b <= 0.01
					and dimmer.color.a >= 0.0 and dimmer.color.a <= 0.15,
					"bright CALIB background uses pure-black dim at no more than 15% opacity")
			_check_intro_only(stage, viewport_size)
			for heading_path in ["Heading", "StageHeading", "InstructionEN", "InstructionFIL",
				"CountdownLabel", "IntroOverlay/IntroHeading"]:
				var title := stage.get_node_or_null(heading_path) as Label
				_expect(title != null and title.owner == screen and _uses_gochi(title),
						"%s uses editor-assigned Gochi Hand font" % heading_path)
			# Check actual stage visibility after intro, while camera remains offline.
			screen.call("_process", 2.51)
			var intro := stage.get_node_or_null("IntroOverlay") as Control
			_expect(intro != null and not intro.visible, "intro disappears after 2.5 seconds")
			_check_restored_footer(stage)
			_expect(_only_zone_visible(stage, "CenterCalibrationLane"),
				"only CENTER standing guide is visible when camera is unavailable")
			var unavailable := stage.get_node_or_null("CameraUnavailableLabel") as Label
			_expect(unavailable != null and unavailable.visible, "offline camera has a clear textual fallback")
		var runtime_controls: Array[String] = []
		_collect_control_paths(screen, screen, runtime_controls)
		for path in runtime_controls:
			_expect(authored_controls.has(path), "no runtime-created visual Control: %s" % path)

		screen.queue_free()
		await process_frame
	service.stop_camera()
	_finish()


func _collect_control_paths(origin: Node, current: Node, paths: Array[String]) -> void:
	for child in current.get_children():
		if child is Control:
			paths.append(str(origin.get_path_to(child)))
		_collect_control_paths(origin, child, paths)


func _in_bounds(rect: Rect2, viewport: Vector2i) -> bool:
	return rect.position.x >= -2.0 and rect.position.y >= -2.0 \
		and rect.end.x <= viewport.x + 2.0 and rect.end.y <= viewport.y + 2.0


func _uses_gochi(label: Label) -> bool:
	var font := label.get_theme_font("font")
	return font != null and "gochi" in font.resource_path.to_lower()


func _only_zone_visible(stage: Control, expected: String) -> bool:
	var shown := 0
	for path in STAGES:
		var zone := stage.get_node_or_null(path) as Control
		if zone != null and zone.visible:
			shown += 1
			if path != expected:
				return false
	return shown == 1


func _check_intro_only(stage: Control, viewport: Vector2i) -> void:
	# This checks actual Control.visible, rather than just a dark overlay
	# drawn over clickable buttons: no footer/control can remain interactive.
	var intro := stage.get_node_or_null("IntroOverlay") as ColorRect
	_expect(intro != null and intro.visible and intro.is_visible_in_tree(),
		"intro is the only visible calibration panel before 2.5 seconds at %s" % viewport)
	for child in stage.get_children():
		if child is Control and child != intro:
			var visual := child as Control
			_expect(not visual.visible and not visual.is_visible_in_tree(),
				"during intro, other stage Control is hidden and cannot take input: %s" % visual.name)
	if intro == null:
		return
	_expect(_in_bounds(intro.get_global_rect(), viewport), "intro overlay fits display at %s" % viewport)
	_expect(intro.color.a <= 0.01,
			"intro adds no second black tint over the bright CALIB background")
	var heading := intro.get_node_or_null("IntroHeading") as Label
	var back := intro.get_node_or_null("IntroBackButton") as Button
	_expect(heading != null and heading.visible and heading.is_visible_in_tree()
		and heading.text.strip_edges().to_upper() == "CALIBRATION",
		"intro shows only the large CALIBRATION title")
	_expect(back != null and back.visible and back.is_visible_in_tree()
		and back.text.to_upper().contains("MAIN") and not back.disabled,
		"intro Back to Main remains visible and enabled")
	if back != null:
		_expect(back.focus_mode == Control.FOCUS_ALL,
			"intro Back to Main is keyboard-focusable")
	for child in intro.get_children():
		if child is Control and child != heading and child != back:
			_expect(not (child as Control).visible,
				"extra intro element stays hidden: %s" % child.name)
	for removed in ["SkipButton", "RetryButton", "DemoButton", "KeyboardButton"]:
		_expect(stage.get_node_or_null(removed) == null,
			"intro has no forbidden action underneath: " + removed)


func _check_restored_footer(stage: Control) -> void:
	for path in ["StageHeading", "InstructionFIL", "StepBadge", "CameraFrame",
		"CameraBlackBacking", "BackButton"]:
		var control := stage.get_node_or_null(path) as Control
		_expect(control != null and control.visible and control.is_visible_in_tree(),
			"after intro the authored stage/footer returns: %s" % path)
	for path in ["ContinueButton", "InstructionEN", "Heading", "CalibrationGuideCursor",
		"CalibrationGuideBar", "CountdownLabel", "LiveCameraInset"]:
		var hidden := stage.get_node_or_null(path) as Control
		_expect(hidden != null and not hidden.visible,
			"after intro unused/locked Control remains hidden: %s" % path)
	var back := stage.get_node_or_null("BackButton") as Button
	_expect(back != null and not back.disabled,
		"after intro the teacher Back Main button alone is enabled")


func _expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)


func _finish() -> void:
	if failures.is_empty():
		print("PASS calibration editor fullscreen: %d checks / %d viewports" % [checks, SIZES.size()])
		quit(0)
	else:
		for problem in failures:
			printerr("FAIL calibration fullscreen: ", problem)
		print("FAIL calibration editor fullscreen: %d failures / %d checks" % [failures.size(), checks])
		quit(1)
