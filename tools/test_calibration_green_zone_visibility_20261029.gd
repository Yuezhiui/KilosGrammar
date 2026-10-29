extends SceneTree

## QA ONLY. Never calls calibration.set_context(), starts a camera/YOLO worker,
## or writes to calibration.gd/.tscn. Synthetic camera texture is inert.
##
## Godot 4.7.2 --headless --path . --script \
##   res://tools/test_calibration_green_zone_visibility_20261029.gd

const CALIBRATION_SCENE := "res://ui/vision/calibration/calibration.tscn"
const ROOT_STAGE := "TutorialStage/"
const CAMERA := ROOT_STAGE + "CameraArea/LiveCameraInset"
const PLACEMENT := ROOT_STAGE + "CameraArea/SkeletonPlacement"
const GROUP := ROOT_STAGE + "PoseGuides/"
const EXPECTED_GUIDES := {
	"PoseGuideDefault": "res://Components/Gameplay/Calibration/Pose Guides/DEFAULT.png",
	"PoseGuideRight": "res://Components/Gameplay/Calibration/Pose Guides/DEFAULT.png",
	"PoseGuideLeft": "res://Components/Gameplay/Calibration/Pose Guides/DEFAULT.png",
	"PoseGuideBalloonRaise": "res://Components/Gameplay/Calibration/Pose Guides/BALOON POP.png",
	"PoseGuideBalloonRaiseRight": "res://Components/Gameplay/Calibration/Pose Guides/BALOON POP.png",
	"PoseGuideBalloonRaiseLeft": "res://Components/Gameplay/Calibration/Pose Guides/BALOON POP.png",
	"PoseGuidePlaneCenter": "res://Components/Gameplay/Calibration/Pose Guides/PLANE T POSE.png",
	"PoseGuidePlaneLeft": "res://Components/Gameplay/Calibration/Pose Guides/PLANE GOING TO LEFT.png",
	"PoseGuidePlaneRight": "res://Components/Gameplay/Calibration/Pose Guides/PLANE GOING TO RIGHT.png",
}
const VIEWPORTS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const STEPS := [
	{"game": "Catch the Word", "zone": "CENTER", "step": 0, "phase": 0, "guide": "PoseGuideDefault"},
	{"game": "Catch the Word", "zone": "RIGHT", "step": 1, "phase": 0, "guide": "PoseGuideRight"},
	{"game": "Catch the Word", "zone": "LEFT", "step": 2, "phase": 0, "guide": "PoseGuideLeft"},
	{"game": "Balloon Popping", "zone": "CENTER / BOTH DOWN", "step": 0, "phase": 0, "guide": "PoseGuideDefault"},
	{"game": "Balloon Popping", "zone": "CENTER / BOTH UP", "step": 0, "phase": 1, "guide": "PoseGuideBalloonRaise"},
	{"game": "Balloon Popping", "zone": "RIGHT / BOTH DOWN", "step": 1, "phase": 0, "guide": "PoseGuideRight"},
	{"game": "Balloon Popping", "zone": "RIGHT / BOTH UP", "step": 1, "phase": 1, "guide": "PoseGuideBalloonRaiseRight"},
	{"game": "Balloon Popping", "zone": "LEFT / BOTH DOWN", "step": 2, "phase": 0, "guide": "PoseGuideLeft"},
	{"game": "Balloon Popping", "zone": "LEFT / BOTH UP", "step": 2, "phase": 1, "guide": "PoseGuideBalloonRaiseLeft"},
	{"game": "Human Plane", "zone": "CENTER T-POSE", "step": 0, "phase": 0, "guide": "PoseGuidePlaneCenter"},
]
const GREEN_RATIO_MIN := 0.004
const ALPHA_RATIO_MIN := 0.015

var assertions := 0
var failed := 0
var categories := {"intro": 0, "phase": 0, "order": 0, "geometry": 0, "asset": 0, "skeleton": 0}
var incidents: Array[String] = []
var packed: PackedScene
var stage_count := 0
var processed_steps := 0
var texture_stats := {}
var pose: Node
var previous_offset := Vector2.ZERO
var previous_scale := Vector2.ONE


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	pose = root.get_node_or_null("PoseService")
	_check(pose != null, "PoseService autoload exists; no camera needed", "skeleton")
	if pose != null:
		previous_offset = pose.skeleton_visual_offset
		previous_scale = pose.skeleton_visual_scale
		_check(not pose.active, "PoseService starts inactive in this isolated headless run", "skeleton")
	packed = load(CALIBRATION_SCENE) as PackedScene
	_check(packed != null, "Production calibration scene loads", "asset")
	if packed == null:
		_report_and_exit()
		return
	_check_assets_once()
	for viewport_size in VIEWPORTS:
		var vp := SubViewport.new()
		vp.name = "CalibrationGreenVisibilityQA"
		vp.disable_3d = true
		vp.size = viewport_size
		root.add_child(vp)
		# Entry with activity established BEFORE _ready, but no set_context.
		await _exercise(vp, viewport_size, true)
		# Entry with activity supplied DURING intro, still no camera activation.
		await _exercise(vp, viewport_size, false)
		vp.queue_free()
		await process_frame
		_check(not is_instance_valid(vp), "QA SubViewport released", "geometry")
	if pose != null:
		pose.set_skeleton_visual_transform(previous_offset, previous_scale)
		_check(not pose.active, "QA never starts live camera or YOLO", "skeleton")
	for _frame in range(2):
		await process_frame
	_report_and_exit()


func _exercise(vp: SubViewport, viewport_size: Vector2i, before_ready: bool) -> void:
	var scene := packed.instantiate() as Control
	if scene == null:
		_check(false, "Calibration instance creates", "asset")
		return
	stage_count += 1
	if before_ready:
		scene.set("context", {"activity": "Catch the Word"})
	vp.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scene.set_process(false) # Prevent actual intro/holds from ticking in QA.
	if not before_ready:
		scene.set("context", {"activity": "Catch the Word"})
	await process_frame
	var stage := scene.get_node_or_null("TutorialStage") as Control
	var camera := scene.get_node_or_null(CAMERA) as TextureRect
	var placement := scene.get_node_or_null(PLACEMENT) as ReferenceRect
	var group := scene.get_node_or_null(ROOT_STAGE + "PoseGuides") as Control
	var intro := scene.get_node_or_null(ROOT_STAGE + "IntroOverlay") as Control
	var back := scene.get_node_or_null(ROOT_STAGE + "Navigation/BackButton") as BaseButton
	var tag := "%s / %s" % [str(viewport_size), "pre-ready" if before_ready else "during intro"]
	_check(stage != null and camera != null and placement != null and group != null,
		tag + ": authored camera, skeleton placement and pose group exist", "asset")
	if stage == null or camera == null or placement == null or group == null:
		scene.queue_free()
		await process_frame
		return
	_check(scene.get("intro_running") == true and intro != null and intro.is_visible_in_tree(),
		tag + ": intro runs and hides main calibration stage", "intro")
	_check(not group.is_visible_in_tree(), tag + ": guide group hidden before intro finishes", "intro")
	_check(not camera.is_visible_in_tree(), tag + ": camera not prematurely shown under intro", "intro")
	scene.call("_sync_reference_art")
	_check(not group.is_visible_in_tree(), tag + ": early sync cannot leak guide under intro", "intro")
	for name in EXPECTED_GUIDES:
		var early := group.get_node_or_null(name) as TextureRect
		_check(early != null and not early.is_visible_in_tree(),
			tag + ": hidden during intro: " + name, "intro")
	_check(back != null and not back.is_visible_in_tree(),
		tag + ": Back hidden by intro, remains authored", "intro")

	# End the intro explicitly. _process and set_context are intentionally NOT
	# used; no webcam or YOLO service may be launched by this test.
	scene.set("intro_running", false)
	scene.call("_finish_intro_only")
	scene.call("_sync_reference_art")
	await process_frame
	_check(intro != null and not intro.is_visible_in_tree(),
		tag + ": intro overlay actually removed after intro", "intro")
	_check(group.is_visible_in_tree(), tag + ": authored pose group restored after intro", "intro")
	_check(back != null and back.visible and not back.disabled,
		tag + ": physical Back button restored after intro", "intro")
	_check(not pose.active if pose != null else true,
		tag + ": _finish_intro_only doesn't start camera", "intro")
	# A synthetic image is attached DIRECTLY to the editor-authored camera
	# TextureRect. Do NOT call _on_live_preview or set_context: neither camera
	# service nor Python YOLO needs to exist to validate composite geometry.
	var image := Image.create(640, 480, false, Image.FORMAT_RGB8)
	image.fill(Color(0.18, 0.22, 0.27))
	camera.texture = ImageTexture.create_from_image(image)
	camera.visible = true
	_check(camera.is_visible_in_tree(), tag + ": synthetic camera preview visible", "geometry")
	_check(camera.texture != null and camera.texture.get_size() == Vector2(640, 480),
		tag + ": known synthetic webcam dimension unchanged", "geometry")

	_check_skeleton(scene, camera, placement, tag)
	_check_zone_geometry(group, camera, tag)
	for step in STEPS:
		var game := String(step["game"])
		# The same scene switches games and visual stages. No set_context().
		scene.set("context", {"activity": game})
		scene.set("live_step", int(step["step"]))
		scene.set("balloon_pose_phase", int(step["phase"]))
		scene.call("_update_target_guide")
		scene.call("_sync_reference_art")
		var label := "%s | %s | %s" % [tag, game, step["zone"]]
		_check_guide_state(group, camera, String(step["guide"]), label)
		processed_steps += 1
	# A completed activity must hide all guides instead of retaining a ghost.
	for game in ["Catch the Word", "Balloon Popping", "Human Plane"]:
		scene.set("context", {"activity": game})
		scene.set("live_step", 1 if game == "Human Plane" else 3)
		scene.set("balloon_pose_phase", 0)
		scene.call("_sync_reference_art")
		_check_guide_state(group, camera, "", tag + " completed " + game)
	# A fresh Catch CENTER after completed Plane must restore only Catch guide.
	scene.set("context", {"activity": "Catch the Word"})
	scene.set("live_step", 0)
	scene.call("_sync_reference_art")
	_check_guide_state(group, camera, "PoseGuideDefault", tag + " restart Catch")
	camera.texture = null
	camera.visible = false
	if scene.has_node("CalibrationVoice"):
		var voice := scene.get_node("CalibrationVoice")
		voice.call("stop")
	scene.queue_free()
	await process_frame
	await process_frame
	_check(not is_instance_valid(scene), tag + ": calibration instance released", "asset")


func _check_guide_state(group: Control, camera: TextureRect,
		expected_name: String, tag: String) -> void:
	var visible_count := 0
	for name in EXPECTED_GUIDES:
		var guide := group.get_node_or_null(name) as TextureRect
		_check(guide != null, tag + ": independent authored node " + name, "asset")
		if guide == null:
			continue
		var expected_path: String = EXPECTED_GUIDES[name]
		_check(guide.texture != null and guide.texture.resource_path == expected_path,
			tag + ": " + name + " binds exactly " + expected_path, "asset")
		var actual := guide.is_visible_in_tree()
		if actual:
			visible_count += 1
		_check(actual == (name == expected_name),
			tag + ": " + name + " expected visible=" + str(name == expected_name) +
				", actual=" + str(actual), "phase")
		if name == expected_name:
			_check(guide.modulate.a > 0.3 and guide.self_modulate.a > 0.3,
				tag + ": active PNG is not transparent by node tint", "asset")
			var rect := guide.get_global_rect()
			var webcam_rect := camera.get_global_rect()
			var intersection := rect.intersection(webcam_rect)
			var overlap_fraction := intersection.get_area() / maxf(rect.get_area(), 1.0)
			_check(rect.has_area() and webcam_rect.has_area() and
				intersection.has_area() and overlap_fraction > 0.30,
				tag + ": guide intersects live camera by >=30% of guide area (actual " +
					"%.3f" % overlap_fraction + ")", "geometry")
			_check(_draws_above_camera(guide, camera),
				tag + ": pose texture must draw ABOVE LiveCameraInset", "order")
			_check(guide.texture != null and _has_visible_green_pixels(guide.texture),
				tag + ": active PNG contains actual opaque green guide art", "asset")
			_check(_green_intersects_camera(guide, camera),
				tag + ": green opaque image pixels (not only blank PNG rect) intersect live camera",
				"geometry")
	_check(visible_count == (1 if not expected_name.is_empty() else 0),
		tag + ": exactly one guide visible, observed " + str(visible_count), "phase")


func _draws_above_camera(guide: CanvasItem, camera: CanvasItem) -> bool:
	if guide.z_index != camera.z_index:
		return guide.z_index > camera.z_index
	var guide_branch: Node = guide
	var camera_branch: Node = camera
	# First sibling under their shared calibration TutorialStage wins the
	# canvas draw order; later sibling should be higher without z_index.
	while guide_branch.get_parent() != camera_branch.get_parent():
		if guide_branch.get_parent() == null or camera_branch.get_parent() == null:
			return false
		var guide_depth := _depth(guide_branch)
		var camera_depth := _depth(camera_branch)
		if guide_depth > camera_depth:
			guide_branch = guide_branch.get_parent()
		elif camera_depth > guide_depth:
			camera_branch = camera_branch.get_parent()
		else:
			guide_branch = guide_branch.get_parent()
			camera_branch = camera_branch.get_parent()
	if guide_branch.get_parent() == null:
		return false
	return guide_branch.get_index() > camera_branch.get_index()


func _depth(node: Node) -> int:
	var depth := 0
	while node.get_parent() != null:
		depth += 1
		node = node.get_parent()
	return depth


func _check_skeleton(scene: Control, camera: TextureRect,
		placement: ReferenceRect, tag: String) -> void:
	_check(camera.get_parent() == placement.get_parent(),
		tag + ": skeleton target shares camera transform parent", "skeleton")
	_check(placement.editor_only,
		tag + ": editable SkeletonPlacement border is not mistaken for drawn YOLO bones", "skeleton")
	_check(camera.stretch_mode == TextureRect.STRETCH_SCALE,
		tag + ": video fills camera box, no crop/letterbox", "skeleton")
	var inset := camera.get_global_rect()
	var bones := placement.get_global_rect()
	var size_error := bones.size.distance_to(inset.size) / maxf(inset.size.length(), 1.0)
	_check(_skeleton_rect_aligned(inset, bones),
		"%s: SkeletonPlacement must match camera rect; camera=%s bones=%s delta=%.4f (suspected green-bones misalignment)" %
			[tag, inset, bones, size_error], "skeleton")
	# Regression sensitivity: the original scene had a 40px wider overlay
	# (skeleton right=1188 vs video right=1148). That must be rejected even
	# though the production author has already corrected the current asset.
	var old_mismatch := Rect2(inset.position, inset.size + Vector2(40, 0))
	_check(not _skeleton_rect_aligned(inset, old_mismatch),
		tag + ": catches original 40px misaligned skeleton geometry", "skeleton")
	if pose != null:
		# This only updates the GODOT property passed to Python on a FUTURE
		# start_camera(). It does not start any camera or worker.
		scene.call("_apply_skeleton_placement")
		var expected_offset := (placement.position - camera.position) / camera.size
		var expected_scale := placement.size / camera.size
		_check(pose.skeleton_visual_offset.is_equal_approx(expected_offset) and
			pose.skeleton_visual_scale.is_equal_approx(expected_scale),
			tag + ": skeleton bones math follows editor boxes", "skeleton")
		_check(pose.skeleton_visual_scale.distance_to(Vector2.ONE) < 0.01,
			tag + ": default green skeleton scale must not stretch outside webcam preview; actual=" +
				str(pose.skeleton_visual_scale), "skeleton")


func _skeleton_rect_aligned(camera_rect: Rect2, skeleton_rect: Rect2) -> bool:
	return camera_rect.position.distance_to(skeleton_rect.position) < 1.0 and \
		skeleton_rect.size.distance_to(camera_rect.size) / maxf(camera_rect.size.length(), 1.0) < 0.01


func _check_zone_geometry(group: Control, camera: TextureRect, tag: String) -> void:
	# Every LEFT/CENTER/RIGHT guide intentionally reuses the same source PNG
	# but has a DIFFERENT authored rectangle. Verify each region is actually
	# placed at the named floor position, not just given the correct node name.
	for prefix in ["PoseGuide", "PoseGuideBalloonRaise"]:
		var names := (["PoseGuideLeft", "PoseGuideDefault", "PoseGuideRight"]
			if prefix == "PoseGuide" else
			["PoseGuideBalloonRaiseLeft", "PoseGuideBalloonRaise", "PoseGuideBalloonRaiseRight"])
		var left := group.get_node_or_null(names[0]) as TextureRect
		var center := group.get_node_or_null(names[1]) as TextureRect
		var right := group.get_node_or_null(names[2]) as TextureRect
		if left == null or center == null or right == null:
			_check(false, tag + ": zone guides not independently scene-authored: " + prefix, "geometry")
			continue
		var mid_x := center.get_global_rect().get_center().x
		var x_left := left.get_global_rect().get_center().x
		var x_right := right.get_global_rect().get_center().x
		var min_separation := camera.get_global_rect().size.x * 0.16
		_check(x_left + min_separation < mid_x and mid_x + min_separation < x_right,
			tag + ": named guide positions really progress LEFT < CENTER < RIGHT for " +
				prefix + ": " + str([x_left, mid_x, x_right]), "geometry")


func _check_assets_once() -> void:
	for path in EXPECTED_GUIDES.values():
		if texture_stats.has(path):
			continue
		_check(ResourceLoader.exists(path), "Visible guide PNG exists: " + path, "asset")
		if not ResourceLoader.exists(path):
			continue
		var texture := load(path) as Texture2D
		_check(texture != null, "Guide PNG imports as Texture2D: " + path, "asset")
		if texture == null:
			continue
		var image := texture.get_image()
		_check(image != null and not image.is_empty(),
			"Guide PNG readable independently of camera: " + path, "asset")
		if image == null or image.is_empty():
			continue
		var colored := 0
		var green := 0
		var total := 0
		for py in range(0, image.get_height(), maxi(1, image.get_height() / 90)):
			for px in range(0, image.get_width(), maxi(1, image.get_width() / 90)):
				total += 1
				var pixel := image.get_pixel(px, py)
				if pixel.a > 0.15:
					colored += 1
					if _is_green(pixel):
						green += 1
		texture_stats[path] = {"green": green, "opaque": colored, "total": total}
		print("GUIDE ASSET PIXELS %s dimensions=%s sampled=%d opaque=%d green=%d" %
			[path, texture.get_size(), total, colored, green])
		_check(colored >= int(total * ALPHA_RATIO_MIN),
			"Guide art is not empty/fully transparent: " + path, "asset")
		_check(green >= int(total * GREEN_RATIO_MIN),
			"Guide art actually contains substantial visible GREEN (sampled " +
				str(green) + " of " + str(total) + "): " + path, "asset")


func _is_green(pixel: Color) -> bool:
	return pixel.a > 0.15 and pixel.g > 0.32 and +		pixel.g > pixel.r * 1.2 and pixel.g > pixel.b * 1.12


func _has_visible_green_pixels(texture: Texture2D) -> bool:
	var stats: Dictionary = texture_stats.get(texture.resource_path, {})
	return int(stats.get("green", 0)) > 0


func _green_intersects_camera(guide: TextureRect, camera: TextureRect) -> bool:
	if guide.texture == null:
		return false
	var image := guide.texture.get_image()
	if image == null or image.is_empty():
		return false
	var rect := guide.get_global_rect()
	var camera_rect := camera.get_global_rect()
	if not rect.has_area() or not camera_rect.has_area():
		return false
	for py in range(0, image.get_height(), maxi(1, image.get_height() / 70)):
		for px in range(0, image.get_width(), maxi(1, image.get_width() / 70)):
			var pixel := image.get_pixel(px, py)
			if not _is_green(pixel):
				continue
			var world_point := rect.position + rect.size * Vector2(
				(float(px) + 0.5) / float(image.get_width()),
				(float(py) + 0.5) / float(image.get_height()))
			if camera_rect.has_point(world_point):
				return true
	return false


func _check(ok: bool, message: String, category: String) -> void:
	assertions += 1
	if ok:
		return
	failed += 1
	categories[category] = int(categories.get(category, 0)) + 1
	if incidents.size() < 40:
		incidents.append("[" + category + "] " + message)
	if failed <= 12:
		printerr("CALIBRATION GREEN GUIDE FAIL: [" + category + "] " + message)


func _report_and_exit() -> void:
	print("CALIBRATION GREEN GUIDE: %s | scenes=%d phases=%d checks=%d failures=%d" %
		["PASS" if failed == 0 else "FAIL", stage_count, processed_steps, assertions, failed])
	print("CALIBRATION GREEN GUIDE CATEGORIES: " + str(categories))
	for issue in incidents:
		print("CALIBRATION GREEN GUIDE ISSUE: " + issue)
	quit(0 if failed == 0 else 1)
