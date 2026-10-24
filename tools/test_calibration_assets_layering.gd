extends SceneTree

# Godot --headless --path . --script res://tools/test_calibration_assets_layering.gd
# Isolated, deterministic, NO-WEBCAM regression for the NEW CALIB artwork,
# scene-editable UI layers and calibration hold behavior.
#
# Source of truth: C:/Users/Yue/Downloads/CALIB; installed copies are expected
# under Components/CalibrationV2. This test NEVER edits production files,
# student preferences, or the Python pose worker.
const SCENE_PATH := "res://ui/vision/calibration.tscn"
const INSTALLED_ART := "res://Components/CalibrationV2/"
const SOURCE_ART := "C:/Users/Yue/Downloads/CALIB/"
const ART_NAMES := [
	"1.png", "2.png", "3.png", "ARROW.png", "BACKGROUND.png",
	"BORDER.png", "CAT MEOW.png", "MOVE TO HIGHLIGHTED AREA.png",
	"PARAMETERS.png", "STARS.png", "STAY IN THE CENTER.png",
	"STAY OF THE LEFT.png", "STAY ON THE RIGHT.png",
	"STEP 1.png", "STEP 2.png", "STEP 3.png"
]
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const STANDING_ZONES := ["CenterCalibrationLane", "RightCalibrationLane", "LeftCalibrationLane"]
const ART_ZONES := ["ArtGuideCenter", "ArtGuideRight", "ArtGuideLeft"]
const ART_ARROWS := ["ArtArrowCenter", "ArtArrowRight", "ArtArrowLeft"]
const STAGE_IMAGES := ["STEP 1.png", "STEP 2.png", "STEP 3.png"]
const POSITION_IMAGES := ["STAY IN THE CENTER.png", "STAY ON THE RIGHT.png", "STAY OF THE LEFT.png"]
const HOLD_DURATION := 3.0
const INTRO_DURATION := 2.5
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := root.get_node_or_null("PoseService")
	_expect(service != null, "PoseService autoload exists without launching a webcam")
	if service == null:
		_finish()
		return
	# All transitions use stage state instead of a camera device.
	_expect(not bool(service.get("active")), "Camera service starts inactive")
	var scene_resource := load(SCENE_PATH) as PackedScene
	_expect(scene_resource != null, "Calibration scene parses and loads")
	if scene_resource == null:
		_finish()
		return
	_check_installed_asset_bytes()
	var root_size := root.size
	var root_content_size := root.content_scale_size
	for size in SIZES:
		root.size = size
		root.content_scale_size = size
		await process_frame
		await _check_viewport(scene_resource, size, service)
	root.content_scale_size = root_content_size
	root.size = root_size
	_finish()


func _check_installed_asset_bytes() -> void:
	for art_name in ART_NAMES:
		var installed: String = INSTALLED_ART + String(art_name)
		var source: String = SOURCE_ART + String(art_name)
		_expect(FileAccess.file_exists(installed),
			"Installed supplied image exists: %s" % art_name)
		if FileAccess.file_exists(source) and FileAccess.file_exists(installed):
			_expect(FileAccess.get_sha256(source) == FileAccess.get_sha256(installed),
				"Installed %s matches supplied PNG byte-for-byte" % art_name)


func _check_viewport(packed: PackedScene, dimensions: Vector2i, service: Node) -> void:
	var view := packed.instantiate() as Control
	_expect(view != null, "Calibration instantiates as Control at %s" % dimensions)
	if view == null:
		return
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	view.set_process(false)
	var stage := view.get_node_or_null("TutorialStage") as Control
	var camera := view.get_node_or_null("TutorialStage/LiveCameraInset") as TextureRect
	var intro := view.get_node_or_null("TutorialStage/IntroOverlay") as Control
	_expect(stage != null and stage.owner == view, "%s: stage is scene-authored" % dimensions)
	_expect(camera != null and camera.owner == view, "%s: live-feed slot is editor-authored TextureRect" % dimensions)
	_expect(intro != null and intro.owner == view and intro.is_visible_in_tree(),
		"%s: scene-authored intro appears at start" % dimensions)
	_expect(_inside(view.get_global_rect(), dimensions), "%s: entire scene stays within display" % dimensions)
	if stage == null or camera == null:
		view.queue_free()
		await process_frame
		return
	_expect(_inside(stage.get_global_rect(), dimensions), "%s: design stage has no offscreen bounds" % dimensions)
	_expect(_inside(camera.get_global_rect(), dimensions), "%s: live camera preview is inside display" % dimensions)
	_expect(camera.get_child_count() == 0, "%s: camera TextureRect has NO overlaid UI/guide children" % dimensions)

	var observed: Dictionary = {}
	var authored_count := 0
	var unowned := PackedStringArray()
	var art_nodes: Array[Node] = []
	var stack: Array[Node] = [view]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node == view:
			continue
		if node.owner == view:
			authored_count += 1
		else:
			unowned.append(String(view.get_path_to(node)))
		var art_path := _art_resource_path(node)
		if not art_path.is_empty() and art_path.begins_with(INSTALLED_ART):
			var key := art_path.get_file()
			if not observed.has(key):
				observed[key] = []
			observed[key].append(node)
			art_nodes.append(node)
	_expect(unowned.is_empty(), "%s: NO runtime-only/unowned UI nodes (%s)" % [dimensions, unowned])
	_expect(authored_count >= ART_NAMES.size(), "%s: %d scene-owned editable child nodes" % [dimensions, authored_count])
	for name in ART_NAMES:
		var matches: Array = observed.get(name, [])
		_expect(not matches.is_empty(), "%s: supplied %s has a separately editor-authored art node" % [dimensions, name])
		for candidate in matches:
			var node := candidate as Node
			_expect(node.owner == view, "%s: %s is persistent in .tscn" % [dimensions, name])
			_expect(node is TextureRect or node is NinePatchRect or node is Sprite2D or node is TextureButton,
				"%s: %s uses a native editable artwork node" % [dimensions, name])
			if node is Control:
				var control := node as Control
				if name != "BACKGROUND.png" and node is TextureRect:
					# Artwork PNGs contain deliberately transparent margins. A
					# TextureRect may extend above the viewport, provided all its
					# NON-TRANSPARENT content remains visible and uncropped.
					var content_rect := _drawn_art_rect(node as TextureRect)
					_expect(_inside(content_rect, dimensions),
						"%s: visible pixels of %s stay on-screen (content=%s)" %
						[dimensions, name, content_rect])
				else:
					_expect(_inside(_visual_rect(control), dimensions),
						"%s: artwork %s (%s) stays on-screen" % [dimensions, name, control.get_path()])

	var background := view.get_node_or_null("ClassroomBackground") as TextureRect
	_expect(background != null and _art_resource_path(background).ends_with("BACKGROUND.png")
		and _inside(background.get_global_rect(), dimensions),
		"%s: supplied CALIB BACKGROUND fills authored display surface" % dimensions)
	var header := _find_stage_title(stage)
	_expect(header != null and header.owner == view,
		"%s: editable CALIBRATION title/header is present" % dimensions)
	var step_badge := stage.get_node_or_null("StepBadge") as Label
	_expect(step_badge != null and step_badge.owner == view,
		"%s: stage has editor-authored step indicator" % dimensions)
	var back_main := intro.get_node_or_null("IntroBackButton") as Button if intro != null else null
	_expect(back_main != null and back_main.owner == view and back_main.is_visible_in_tree(),
		"%s: intro has visible authored Back to Main" % dimensions)
	if intro != null:
		for child in stage.get_children():
			if child is Control and child != intro:
				_expect(not (child as Control).is_visible_in_tree(),
					"%s: intro hides other camera/zone/HUD control: %s" % [dimensions, child.name])

	# The artwork for the THREE circular steps must have independently
	# editable handles, distinct from the three full title/step images.
	for number in ["1.png", "2.png", "3.png"]:
		var matches: Array = observed.get(number, [])
		_expect(matches.size() >= 1, "%s: circle %s is independently movable" % [dimensions, number])
	# The stand boxes are on Godot UI, NOT drawn into YOLO/camera pixels. They
	# must be siblings of the live camera TextureRect, behind no camera children.
	for zone_name in STANDING_ZONES:
		var zone := stage.get_node_or_null(zone_name) as Control
		_expect(zone != null and zone.owner == view, "%s: authored %s" % [dimensions, zone_name])
		if zone != null:
			_expect(zone.get_parent() == camera.get_parent(),
				"%s: %s is sibling of LiveCameraInset, NOT inside camera image" % [dimensions, zone_name])
			_expect(camera.get_global_rect().encloses(zone.get_global_rect()),
				"%s: %s guide fits inside UI camera placeholder" % [dimensions, zone_name])
			_expect(_inside(zone.get_global_rect(), dimensions),
				"%s: %s remains inside full-screen display" % [dimensions, zone_name])
			_expect(zone.z_index >= camera.z_index or zone.get_index() > camera.get_index(),
				"%s: %s overlays preview at UI layer without changing video bytes" % [dimensions, zone_name])
	for index in range(ART_ZONES.size()):
		for guide_name in [ART_ZONES[index], ART_ARROWS[index]]:
			var guide_art := stage.get_node_or_null(guide_name) as TextureRect
			_expect(guide_art != null and guide_art.owner == view,
				"%s: editable %s is authored instead of drawn on camera video" %
				[dimensions, guide_name])
			if guide_art == null:
				continue
			_expect(guide_art.get_parent() == camera.get_parent(),
				"%s: %s is a sibling of LiveCameraInset, never a child" % [dimensions, guide_name])
			_expect(guide_art.texture != null and _art_resource_path(guide_art).begins_with(INSTALLED_ART),
				"%s: %s is the actual supplied overlay texture" % [dimensions, guide_name])
			_expect(_inside(_visual_rect(guide_art), dimensions),
				"%s: %s UI overlay remains inside the viewport" % [dimensions, guide_name])
	# Guard no deprecated controls. Keep existing hidden status/Continue
	# compatibility nodes; only controls user requested removed are forbidden.
	for button_name in ["SkipButton", "RetryButton", "DemoButton", "KeyboardButton", "StopCameraButton"]:
		_expect(stage.get_node_or_null(button_name) == null,
			"%s: removed obsolete %s does not exist" % [dimensions, button_name])
	var constants: Dictionary = view.get_script().get_script_constant_map() if view.get_script() != null else {}
	_expect(absf(float(constants.get("HOLD_SECONDS", -1.0)) - HOLD_DURATION) < 0.001,
		"%s: stationary calibration remains exactly 3 seconds" % dimensions)
	_expect(absf(float(constants.get("INTRO_SECONDS", -1.0)) - INTRO_DURATION) < 0.001,
		"%s: intro duration remains exactly 2.5 seconds" % dimensions)
	_expect(constants.get("CAPTURE_ORDER", []) == ["CENTER", "RIGHT", "LEFT"],
		"%s: three positions remain CENTER -> RIGHT -> LEFT" % dimensions)

	# Finish intro in a deterministic simulated frame (no waiting or camera).
	view.call("_process", INTRO_DURATION + 0.01)
	view.set_process(false)
	_expect(intro != null and not intro.visible, "%s: intro clears after 2.5 seconds" % dimensions)
	var stage_phases := ["CENTER", "RIGHT", "LEFT"]
	for index in range(3):
		view.set("live_step", index)
		view.call("_update_target_guide")
		view.call("_set_stage_instruction")
		var step_count := 0
		for path in STANDING_ZONES:
			var zone := stage.get_node_or_null(path) as Control
			if zone != null and zone.is_visible_in_tree():
				step_count += 1
				_expect(path == STANDING_ZONES[index],
					"%s: only %s guide active, not %s" % [dimensions, stage_phases[index], path])
		_expect(step_count == 1,
			"%s: %s step has exactly ONE highlighted UI standing region" % [dimensions, stage_phases[index]])
		if step_badge != null:
			_expect(step_badge.text.contains(str(index + 1)),
				"%s: step plaque text updates to stage %d" % [dimensions, index + 1])
		var source_images: Array = observed.get(STAGE_IMAGES[index], [])
		_expect(not source_images.is_empty(), "%s: Step-%d artwork remains present" % [dimensions, index + 1])
		var direction_images: Array = observed.get(POSITION_IMAGES[index], [])
		_expect(not direction_images.is_empty(),
			"%s: corresponding %s artwork remains scene-owned" % [dimensions, stage_phases[index]])
		for group in [ART_ZONES, ART_ARROWS, ["ArtStep1", "ArtStep2", "ArtStep3"],
			["ArtTitleCenter", "ArtTitleRight", "ArtTitleLeft"]]:
			var shown := 0
			for item_name in group:
				var art := stage.get_node_or_null(item_name) as Control
				if art != null and art.is_visible_in_tree():
					shown += 1
					_expect(item_name == group[index],
						"%s: stage %d lights its own %s, not %s" %
						[dimensions, index + 1, group[index], item_name])
			_expect(shown == 1,
				"%s: stage %d has ONE matching asset visible among %s" %
				[dimensions, index + 1, group])
		# The countdown assets are independent circle images; exactly ONE
		# shows the current 3/2/1, with stationary hold timing unchanged.
		for elapsed in [0.0, 1.1, 2.1]:
			view.set("live_timer", elapsed)
			view.call("_update_hold_countdown")
			var remaining := clampi(ceili(HOLD_DURATION - elapsed), 1, 3)
			var circles_shown := 0
			for number in range(1, 4):
				var circle := stage.get_node_or_null("ArtCountdown%d" % number) as Control
				if circle != null and circle.is_visible_in_tree():
					circles_shown += 1
					_expect(number == remaining,
						"%s: stage %d countdown uses circle %d after %.1fs" %
						[dimensions, index + 1, remaining, elapsed])
			_expect(circles_shown == 1,
					"%s: stage %d shows ONE countdown circle after %.1fs" %
					[dimensions, index + 1, elapsed])
	# Synthetic preview proves this UI compositing never modifies camera pixels.
	var camera_image := Image.create(160, 90, false, Image.FORMAT_RGB8)
	camera_image.fill(Color(0.2, 0.3, 0.4))
	var before := camera_image.get_data()
	var synthetic_video := ImageTexture.create_from_image(camera_image)
	view.call("_on_live_preview", synthetic_video)
	_expect(camera.texture == synthetic_video and camera_image.get_data() == before,
		"%s: changing UI guides does not draw boxes into camera ImageTexture" % dimensions)
	_expect(not bool(service.get("active")), "%s: regression never launched physical camera" % dimensions)
	print("CALIB ASSET QA ", dimensions, " scene-owned=", authored_count,
		" CALIB art textures=", art_nodes.size(), " supplied detected=", observed.size())
	view.queue_free()
	await process_frame
	await process_frame


func _art_resource_path(node: Node) -> String:
	if node == null:
		return ""
	var tex: Texture2D
	if node is TextureRect:
		tex = (node as TextureRect).texture
	elif node is NinePatchRect:
		tex = (node as NinePatchRect).texture
	elif node is Sprite2D:
		tex = (node as Sprite2D).texture
	elif node is TextureButton:
		tex = (node as TextureButton).texture_normal
	if tex == null:
		return ""
	if tex is AtlasTexture:
		var atlas := (tex as AtlasTexture).atlas
		return atlas.resource_path if atlas != null else ""
	return tex.resource_path


func _find_stage_title(stage: Control) -> Control:
	for name in ["CalibrationTitle", "CalibrationHeading", "Heading", "StageHeading"]:
		var node := stage.get_node_or_null(name) as Control
		if node != null:
			return node
	return null


func _visual_rect(ctrl: Control) -> Rect2:
	# Control.get_rect().position is its PARENT-space offset and the global
	# transform already includes it. Multiplying both double-counts offsets,
	# falsely flagging correctly positioned artwork as clipped.
	var rect := Rect2(Vector2.ZERO, ctrl.size)
	var tx := ctrl.get_global_transform_with_canvas()
	var lo: Vector2 = tx * rect.position
	var hi: Vector2 = lo
	for vertex in [
		Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)
	]:
		var point: Vector2 = tx * vertex
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, hi - lo)


func _drawn_art_rect(ctrl: TextureRect) -> Rect2:
	if ctrl.texture == null:
		return _visual_rect(ctrl)
	var image := ctrl.texture.get_image()
	if image == null or image.is_empty():
		return _visual_rect(ctrl)
	var image_size := Vector2(image.get_size())
	var used := image.get_used_rect()
	if used.size == Vector2i.ZERO:
		used = Rect2i(Vector2i.ZERO, image.get_size())
	var factors := Vector2(
		ctrl.size.x / maxf(image_size.x, 1.0),
		ctrl.size.y / maxf(image_size.y, 1.0))
	var offset := Vector2.ZERO
	match ctrl.stretch_mode:
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED:
			var scale_factor := minf(factors.x, factors.y)
			factors = Vector2.ONE * scale_factor
			offset = (ctrl.size - image_size * scale_factor) * 0.5
		TextureRect.STRETCH_KEEP_ASPECT_COVERED:
			var scale_factor := maxf(factors.x, factors.y)
			factors = Vector2.ONE * scale_factor
			offset = (ctrl.size - image_size * scale_factor) * 0.5
		TextureRect.STRETCH_KEEP_ASPECT:
			factors = Vector2.ONE * minf(factors.x, factors.y)
		TextureRect.STRETCH_KEEP_CENTERED:
			factors = Vector2.ONE
			offset = (ctrl.size - image_size) * 0.5
		TextureRect.STRETCH_KEEP:
			factors = Vector2.ONE
	var used_origin := Vector2(used.position) * factors + offset
	var used_size := Vector2(used.size) * factors
	var frame := Rect2(used_origin, used_size)
	var frame_rect := Rect2(Vector2.ZERO, ctrl.size)
	# Content outside its own TextureRect is cut by stretch/cover cropping
	# regardless of the scene's global viewport clipping.
	if not frame_rect.encloses(frame.grow(-1.0)):
		return Rect2(Vector2(-100000.0, -100000.0), Vector2.ONE)
	var transform := ctrl.get_global_transform_with_canvas()
	var lo: Vector2 = transform * frame.position
	var hi: Vector2 = lo
	for vertex in [
		Vector2(frame.end.x, frame.position.y), frame.end,
		Vector2(frame.position.x, frame.end.y)
	]:
		var point: Vector2 = transform * vertex
		lo = lo.min(point)
		hi = hi.max(point)
	return Rect2(lo, hi - lo)


func _inside(rect: Rect2, full_size: Vector2i) -> bool:
	return rect.has_area() and rect.position.x >= -3.0 and rect.position.y >= -3.0 \
		and rect.end.x <= float(full_size.x) + 3.0 \
		and rect.end.y <= float(full_size.y) + 3.0


func _expect(ok: bool, explanation: String) -> void:
	checks += 1
	if not ok:
		failures.append(explanation)


func _finish() -> void:
	if failures.is_empty():
		print("PASS calibration assets/layering: %d checks at %s" % [checks, SIZES])
		quit(0)
		return
	for problem in failures:
		printerr("CALIB_ASSETS FAIL ", problem)
	print("FAIL calibration assets/layering: %d failures / %d checks" % [failures.size(), checks])
	quit(1)
