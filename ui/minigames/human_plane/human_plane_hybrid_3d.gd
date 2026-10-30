extends Node2D

## Native perspective 3D flight world in its own Node3D .tscn, composited below
## the unchanged 2D score/grammar HUD. 2D editor guides place three real
## torus openings; native 3D collision volumes determine actual passage.
@export var hybrid_enabled := true
@export var draw_3d_gates := true
@export_range(0.75, 1.0, 0.05) var viewport_resolution_scale := 1.0
@export_range(120.0, 330.0, 1.0) var plane_width_pixels := 150.0
@export_range(5.0, 20.0, 0.5) var airplane_camera_distance := 8.5
## Keep the scene at native screen pixels (up to 1080p), but reduce MSAA
## bandwidth above 720p on integrated GPUs. Opt into 4x on faster laptops.
@export var force_4x_msaa := false
## 22-mesh imported glTF is ~8.4 model units wide before local placement.
## Artists can also drag/scale PlaneModelPlacement in the 3D scene editor.
@export_range(1.0, 20.0, 0.1) var plane_model_width_units := 8.4
@export_range(0.0, 24.0, 0.5) var visual_bank_degrees := 11.0
## Minimum clear hole around the full airplane wings at the answer line.
## Teacher-controlled model width and the native TorusMesh hole set the fit.
@export_range(1.05, 1.6, 0.05) var plane_ring_clearance := 1.35
## Prevent a floating-point edge touch from claiming a physical pass.
const PASSAGE_CLEARANCE_EPSILON := 0.001

const DESIGN_SIZE := Vector2(1280.0, 720.0)
const GATE_COLORS := [Color("#A944F1"), Color("#43DF79"), Color("#299AF7")]

@onready var overlay: TextureRect = $OverlayTexture
@onready var viewport: SubViewport = $RenderViewport
@onready var view_camera: Camera3D = $RenderViewport/FlightWorld3D/Camera
@onready var plane_anchor: Node3D = $RenderViewport/FlightWorld3D/PlaneAnchor
@onready var far_clouds: Node3D = $RenderViewport/FlightWorld3D/FarClouds
@onready var near_clouds: Node3D = $RenderViewport/FlightWorld3D/NearClouds
@onready var gate_units: Array[Node3D] = [
	$RenderViewport/FlightWorld3D/Gates/GateLeft,
	$RenderViewport/FlightWorld3D/Gates/GateCenter,
	$RenderViewport/FlightWorld3D/Gates/GateRight
]

var _game: Control
var _last_size := Vector2.ZERO
var _cloud_elapsed := 0.0
var _lane_materials: Array[StandardMaterial3D] = []
var _ring_pools: Array = []
var _ring_material_pools: Array = []
var _first_gate_group: Control
var _world_camera_start := Vector3.ZERO
var _forward_distance := 0.0
var _wave_origin_distance := 0.0
var _last_wave_count := -1
var _last_progress := 0.0
var _pool_words: Array[String] = ["", ""]
var _ring_world_scales: Array[float] = []
var _ring_world_positions: Array = [[], []]


func _ready() -> void:
	_game = get_parent() as Control
	viewport.transparent_bg = false
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X if force_4x_msaa else Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	overlay.texture = viewport.get_texture()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_first_gate_group = _game.get_node("MovingGates") as Control
	_world_camera_start = view_camera.position
	# Keep the THREE source-authored ring meshes and clone exactly THREE
	# additional node instances ONCE at startup. Both pools retain the same
	# TorusMesh resource from the world scene; there is no per-wave allocation.
	var queued_units: Array[Node3D] = []
	for lane in range(3):
		var ring := gate_units[lane].duplicate(0) as Node3D
		ring.name = "Queued" + gate_units[lane].name
		gate_units[lane].get_parent().add_child(ring)
		ring.visible = false
		queued_units.append(ring)
	_ring_pools = [gate_units, queued_units]
	_ring_world_positions = [[], []]
	# One immutable world radius per native authored TorusMesh. Perspective
	# naturally changes its ON-SCREEN diameter while camera/aircraft moves.
	# Never stretch x and y independently or rebuild TorusMesh each frame.
	for pool in _ring_pools:
		var materials: Array[StandardMaterial3D] = []
		for lane in range(3):
			var mat := StandardMaterial3D.new()
			mat.albedo_color = GATE_COLORS[lane]
			mat.metallic = 0.16
			mat.roughness = 0.34
			mat.emission_enabled = true
			mat.emission = GATE_COLORS[lane] * 0.18
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			((pool[lane] as Node3D).get_node("Ring") as MeshInstance3D).material_override = mat
			materials.append(mat)
		_ring_material_pools.append(materials)
	_lane_materials = _ring_material_pools[0]
	_sync_visibility()
	set_process(true)


func _process(delta: float) -> void:
	if not is_instance_valid(_game) or not _game.is_node_ready():
		return
	_sync_visibility()
	if not hybrid_enabled:
		return
	var canvas_size := _game.size
	if canvas_size.x < 2.0 or canvas_size.y < 2.0:
		return
	if not canvas_size.is_equal_approx(_last_size):
		_last_size = canvas_size
		overlay.size = canvas_size
		viewport.size = Vector2i(maxi(320, roundi(canvas_size.x * viewport_resolution_scale)),
			maxi(180, roundi(canvas_size.y * viewport_resolution_scale)))
		viewport.msaa_3d = Viewport.MSAA_4X if force_4x_msaa or canvas_size.y <= 720.0 else Viewport.MSAA_2X
	var scored_progress := maxf(0.05, float(_game.call("_progress_for_answer_line")))
	var now_progress := float(_game.get("gate_progress"))
	var step_forward := 42.0 - _gate_distance(now_progress, scored_progress)
	var wave_count := int(_game.get("waves_completed"))
	if _last_wave_count < 0:
		_last_wave_count = wave_count
	elif wave_count != _last_wave_count:
		# The gameplay advances at its own fixed substeps, independently of 3D
		# frame scheduling. A camera update may have skipped the entire passage
		# after the last scored frame; advance through that distance explicitly.
		# The prefetched torus is already fixed at this exact handoff position.
		var entry_progress := float(_game.get("_wave_entry_progress"))
		var previous_wave_end := 42.0 - _gate_distance(1.0, scored_progress)
		var new_wave_start := 42.0 - _gate_distance(entry_progress, scored_progress)
		_wave_origin_distance += (previous_wave_end - new_wave_start) * \
			float(maxi(wave_count - _last_wave_count, 1))
		_last_wave_count = wave_count
	elif now_progress + 0.01 < _last_progress:
		# The prefetched pool becomes active with a nonzero head start. Keep
		# camera world-Z continuous during an explicit manual restart.
		_wave_origin_distance = _forward_distance - step_forward
	_last_progress = now_progress
	_forward_distance = _wave_origin_distance + step_forward
	view_camera.position = _world_camera_start - Vector3(0, 0, _forward_distance)
	var pilot := _game.get_node("PlaneRig") as Control
	var bank := float(_game.get("_bank_input"))
	var pilot_pos := pilot.get_rect().get_center()
	var plane_depth := airplane_camera_distance
	plane_anchor.position = _project_at(pilot_pos, plane_depth, canvas_size)
	plane_anchor.rotation_degrees.z = -bank * visual_bank_degrees
	plane_anchor.rotation_degrees.y = bank * 9.0
	var world_units_per_pixel := _units_per_pixel(plane_depth, canvas_size)
	var target_width := plane_width_pixels * canvas_size.y / DESIGN_SIZE.y
	plane_anchor.scale = Vector3.ONE * (target_width * world_units_per_pixel / plane_model_width_units)

	if bool(_game.get("running")) and not bool(_game.get("paused")) and not bool(_game.get("finished")) and bool(_game.get("airplane_pose_active")):
		_cloud_elapsed += maxf(delta, 0.0)
		# Clouds recycle relative to real forward travel, never expire after
		# the first gate. Their independent XY drift remains intact.
	far_clouds.position = Vector3(-bank * 0.24 + sin(_cloud_elapsed * 0.14) * 0.34,
		sin(_cloud_elapsed * 0.09) * 0.14, -_forward_distance - 22.0 + sin(_cloud_elapsed * 0.11) * 0.8)
	near_clouds.position = Vector3(-bank * 0.85 + sin(_cloud_elapsed * 0.32) * 0.95,
		sin(_cloud_elapsed * 0.22) * 0.34, -_forward_distance - 12.0 + sin(_cloud_elapsed * 0.27) * 1.6)

	var active_gates: Array[Control] = _game.get("_gate_nodes")
	var upcoming_gates: Array[Control] = _game.get("_upcoming_gate_nodes")
	var front_index := 0 if active_gates[0].get_parent() == _first_gate_group else 1
	_update_ring_pool(front_index, active_gates, _game.get("_authored_gate_rect_offsets"),
		_game.get("round_data"), float(_game.get("gate_progress")), true, canvas_size)
	_update_ring_pool(1 - front_index, upcoming_gates, _game.get("_upcoming_rect_offsets"),
		_game.get("next_round_data"), float(_game.get("next_gate_progress")), false, canvas_size)


func _update_ring_pool(pool_index: int, controls: Array[Control], offsets: Array[Rect2],
		data: Dictionary, progress: float, is_front: bool, canvas_size: Vector2) -> void:
	var pool: Array = _ring_pools[pool_index]
	var materials: Array = _ring_material_pools[pool_index]
	var options: Array = data.get("options", [])
	var scoring_progress := maxf(0.05, float(_game.call("_progress_for_answer_line")))
	var passing := is_front and bool(_game.get("gate_resolved"))
	var alpha := float(_game.call("_gate_passage_alpha", progress)) if passing else 1.0
	var target_width := plane_width_pixels * canvas_size.y / DESIGN_SIZE.y
	var world_ring_radius := target_width * plane_ring_clearance * 0.5 / 0.82 * \
		_units_per_pixel(airplane_camera_distance, canvas_size)
	var signature := "|".join(options)
	if signature != _pool_words[pool_index]:
		_pool_words[pool_index] = signature
		_ring_world_positions[pool_index] = []
		for lane in range(3):
			if lane >= options.size():
				break
			# The editor-authored 2D scoring guide determines ring world XY ONCE.
			# Preserve that world XY/Z while the CAMERA AND PLANE fly forward.
			var at_score: Rect2 = _game.call("_gate_visible_rect_with_offsets",
				lane, scoring_progress, offsets, controls)
			var target := Vector2(at_score.get_center().x,
				(_game.get_node("PlaneRig") as Control).get_rect().get_center().y)
			var projected := _project_at(target, airplane_camera_distance, canvas_size)
			var fixed_z := view_camera.position.z - _gate_distance(progress, scoring_progress)
			if not is_front:
				# A queued ring is a STATIONARY physical destination for the NEXT
				# forward-flight segment. At prefetch, predict the queued head
				# start at handoff from the real scene's preview travel factor.
				# Align its fixed world Z with the future camera/airplane crossing,
				# not just the current preview depth (which moves 0.6x faster).
				# This also prevents post-first-wave physical pass-through drift.
				var active_progress := float(_game.get("gate_progress"))
				var preview_factor := float(_game.get_script().get_script_constant_map().get(
					"GATE_PREVIEW_TRAVEL_FACTOR", 0.6))
				var at_handoff := clampf(progress +
					maxf(0.0, 1.0 - active_progress) *
					preview_factor, 0.0, 1.0)
				var next_origin := _wave_origin_distance + (
					42.0 - _gate_distance(1.0, scoring_progress)) - (
					42.0 - _gate_distance(at_handoff, scoring_progress))
				fixed_z = _world_camera_start.z - next_origin - 42.0
			_ring_world_positions[pool_index].append(Vector3(projected.x,
				projected.y, fixed_z))
	for lane in range(3):
		var ring := pool[lane] as Node3D
		ring.visible = draw_3d_gates and not bool(_game.get("finished")) and \
			lane < options.size() and alpha > 0.001
		if not ring.visible:
			continue
		var rect: Rect2 = _game.call("_gate_visible_rect_with_offsets",
			lane, progress, offsets, controls)
		if not rect.has_area():
			ring.visible = false
			continue
		if lane >= _ring_world_positions[pool_index].size():
			ring.visible = false
			continue
		ring.position = _ring_world_positions[pool_index][lane]
		ring.scale = Vector3.ONE * world_ring_radius
		var chosen := passing and int(_game.get("selected_lane")) == lane
		var color: Color = (Color("#43DF79") if bool(_game.get("selected_was_correct"))
			else Color("#FF5068")) if chosen else GATE_COLORS[lane]
		color.a = alpha
		var material := materials[lane] as StandardMaterial3D
		if material.albedo_color != color:
			material.albedo_color = color
			material.emission = Color(color.r * 0.18, color.g * 0.18, color.b * 0.18)


func physical_lane_at_answer_line(require_live_collision: bool = false) -> int:
	# The live path is called by the real wave crossing. It reads the physical
	# 3D shapes after synchronizing them to the SAME frame as the scoring event.
	# The predictive path remains available to layout/calibration tests which
	# ask which aperture will fit before a wave has reached the airplane.
	if not hybrid_enabled or not draw_3d_gates or not is_instance_valid(_game):
		return -1
	# A crossing is an intentional answer only while the enrolled student's
	# calibrated BOTH-ARMS pose remains active. Missing wrists, arms lowered,
	# occlusion, and student-lock loss cannot win an unattended +100.
	if not bool(_game.get("airplane_pose_active")):
		return -1
	var options: Array = (_game.get("round_data") as Dictionary).get("options", [])
	if options.size() != 3:
		return -1
	if require_live_collision:
		return _lane_from_live_collision_shapes()
	var canvas_size := _game.size
	if canvas_size.x <= 0.0 or canvas_size.y <= 0.0:
		return -1
	var pilot_hit_shape := plane_anchor.get_node("PlanePassageHitbox/HitShape") as CollisionShape3D
	if not (pilot_hit_shape.shape is SphereShape3D):
		return -1
	var pilot_radius: float = (pilot_hit_shape.shape as SphereShape3D).radius
	var target_width := plane_width_pixels * canvas_size.y / DESIGN_SIZE.y
	var units_at_plane := _units_per_pixel(airplane_camera_distance, canvas_size)
	var plane_scale := target_width * units_at_plane / plane_model_width_units
	pilot_radius *= plane_scale
	var pilot_screen := Vector2(float(_game.call("_plane_center_x")),
		float(_game.call("_plane_y")))
	var pilot_world := _project_at(pilot_screen, airplane_camera_distance, canvas_size)
	pilot_world += pilot_hit_shape.position * plane_scale
	var active_gates: Array[Control] = _game.get("_gate_nodes")
	var offsets: Array[Rect2] = _game.get("_authored_gate_rect_offsets")
	var score_progress := float(_game.call("_progress_for_answer_line"))
	var ring_scale := target_width * plane_ring_clearance * 0.5 / 0.82 * units_at_plane
	var front_index := 0 if active_gates[0].get_parent() == _first_gate_group else 1
	var winners := 0
	var winning_lane := -1
	for lane in range(3):
		var ring := _ring_pools[front_index][lane] as Node3D
		var mesh := ring.get_node("Ring") as MeshInstance3D
		var aperture_shape := ring.get_node("RingPassageHitbox/HitShape") as CollisionShape3D
		if not (mesh.mesh is TorusMesh) or not (aperture_shape.shape is CylinderShape3D):
			return -1
		var torus := mesh.mesh as TorusMesh
		var cylinder := aperture_shape.shape as CylinderShape3D
		# Never score contact with the torus tube. Use the SMALLER of the
		# teacher-editable aperture cylinder and the actual hollow mesh radius.
		var open_radius := minf(cylinder.radius, torus.inner_radius) * ring_scale
		var rect: Rect2 = _game.call("_gate_visible_rect_with_offsets",
			lane, score_progress, offsets, active_gates)
		if not rect.has_area():
			continue
		var ring_screen := Vector2(rect.get_center().x, pilot_screen.y)
		var ring_world := _project_at(ring_screen, airplane_camera_distance, canvas_size)
		ring_world += aperture_shape.position * ring_scale
		# The airplane and torus both have scene-authored physical hitboxes.
		# Their XY clearance is measured in world units at the common crossing
		# Z-plane, independent of projected sprite width or the monitor size.
		var radial_distance := Vector2(pilot_world.x - ring_world.x,
			pilot_world.y - ring_world.y).length()
		if radial_distance + pilot_radius + PASSAGE_CLEARANCE_EPSILON < open_radius:
			winning_lane = lane
			winners += 1
	# Two coincident or artist-overlapped rings are ambiguous, even if both
	# options happen to be correct. The game may award a score only once.
	return winning_lane if winners == 1 else -1


func _lane_from_live_collision_shapes() -> int:
	# _advance_gate_step changes gate_progress before the Node2D's own render
	# tick. Resync the authored pilot rig and 3D world once, so a moving plane
	# can never be scored against its position from the preceding video frame.
	_game.call("_sync_visuals")
	_process(0.0)
	var active_gates: Array[Control] = _game.get("_gate_nodes")
	var front_index := 0 if active_gates[0].get_parent() == _first_gate_group else 1
	var pilot_hit := plane_anchor.get_node("PlanePassageHitbox/HitShape") as CollisionShape3D
	if not (pilot_hit.shape is SphereShape3D):
		return -1
	var pilot_center := pilot_hit.global_position
	var pilot_scale := pilot_hit.global_transform.basis.get_scale()
	var pilot_radius := (pilot_hit.shape as SphereShape3D).radius * \
		maxf(pilot_scale.x, maxf(pilot_scale.y, pilot_scale.z))
	var winning_lane := -1
	for lane in range(3):
		var ring := _ring_pools[front_index][lane] as Node3D
		if not ring.visible:
			continue
		var mesh := ring.get_node("Ring") as MeshInstance3D
		var hole := ring.get_node("RingPassageHitbox/HitShape") as CollisionShape3D
		if not (mesh.mesh is TorusMesh) or not (hole.shape is CylinderShape3D):
			return -1
		var cylinder := hole.shape as CylinderShape3D
		var cylinder_scale := hole.global_transform.basis.get_scale()
		var ring_scale := ring.global_transform.basis.get_scale()
		var opening_radius := minf(cylinder.radius * minf(cylinder_scale.x, cylinder_scale.z),
			(mesh.mesh as TorusMesh).inner_radius * minf(ring_scale.x, ring_scale.y))
		# The cylinder's local Y axis is rotated to the torus' forward Z axis.
		# A wing touching its inner tube, an off-center lane, or a ring still
		# ahead of/behind the airplane does not count as a complete passage.
		var normal := hole.global_transform.basis.y.normalized()
		var delta := pilot_center - hole.global_position
		var axial_gap := absf(delta.dot(normal))
		var radial_gap := (delta - normal * delta.dot(normal)).length()
		var half_depth := cylinder.height * cylinder_scale.y * 0.5
		if axial_gap > pilot_radius + half_depth + PASSAGE_CLEARANCE_EPSILON:
			continue
		if radial_gap + pilot_radius + PASSAGE_CLEARANCE_EPSILON >= opening_radius:
			continue
		if winning_lane >= 0:
			return -1
		winning_lane = lane
	return winning_lane


func get_ring_highlight_rect(lane: int) -> Rect2:
	# The tutorial spotlight follows the CURRENT 3D torus itself. A 2D gate
	# guide would outline empty space while perspective moves the ring.
	var canvas := _game.size
	var active: Array[Control] = _game.get("_gate_nodes")
	var front_index := 0 if active[0].get_parent() == _first_gate_group else 1
	var pool: Array = _ring_pools[front_index]
	if pool.is_empty() or viewport.size.x <= 0 or viewport.size.y <= 0:
		return Rect2()
	var ring := pool[clampi(lane, 0, 2)] as Node3D
	var mesh := ring.get_node("Ring") as MeshInstance3D
	if not (mesh.mesh is TorusMesh):
		return Rect2()
	var dist := absf(view_camera.global_position.z - ring.global_position.z)
	var image_center := view_camera.unproject_position(ring.global_position)
	image_center *= Vector2(canvas.x / float(viewport.size.x), canvas.y / float(viewport.size.y))
	var radius := ((mesh.mesh as TorusMesh).outer_radius * ring.scale.x) / \
		maxf(_units_per_pixel(dist, canvas), 0.0001)
	# Give the far-away target a useful readable cutout without modifying the
	# ring mesh, actual physical radius, or the camera perspective.
	radius = maxf(radius, canvas.y / DESIGN_SIZE.y * 28.0)
	return Rect2(image_center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)


func get_airplane_highlight_rect() -> Rect2:
	# The painted airplane has 22 editable glTF mesh parts. Its actual rendered
	# AABB corners, projected through the live camera, are the only reliable
	# highlight; the collision sphere may be smaller than a wingtip and the
	# hidden 2D pilot guide may be much larger than the painted model.
	var canvas := _game.size
	var factor := Vector2(canvas.x / float(viewport.size.x), canvas.y / float(viewport.size.y))
	var has_bounds := false
	var bounds := Rect2()
	for node in plane_anchor.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var aabb := mesh.get_aabb()
		for corner in range(8):
			var world := mesh.to_global(aabb.get_endpoint(corner))
			if view_camera.is_position_behind(world):
				continue
			var pixel := view_camera.unproject_position(world) * factor
			if not has_bounds:
				bounds = Rect2(pixel, Vector2.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(pixel)
	if has_bounds:
		return bounds
	# Imported artwork may still be loading before the first viewport frame;
	# retain a stable procedural collision-sphere fallback for that frame only.
	var center := view_camera.unproject_position(plane_anchor.global_position) * factor
	var hitbox := plane_anchor.get_node("PlanePassageHitbox/HitShape") as CollisionShape3D
	var radius: float = (hitbox.shape as SphereShape3D).radius * plane_anchor.scale.x / \
		maxf(_units_per_pixel(airplane_camera_distance, canvas), 0.0001)
	return Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)


func _gate_distance(progress: float, scored_progress: float) -> float:
	if progress <= scored_progress:
		return lerpf(42.0, airplane_camera_distance, clampf(progress / scored_progress, 0.0, 1.0))
	var through := clampf((progress - scored_progress) / maxf(1.0 - scored_progress, 0.001), 0.0, 1.0)
	return lerpf(airplane_camera_distance, view_camera.near * 1.05, through)


func gate_screen_center(lane: int, progress: float, rect: Rect2, upcoming: bool,
		offsets: Array[Rect2] = [], gates: Array[Control] = []) -> Vector2:
	# All three rings converge on the actual AIRCRAFT HEIGHT at collision.
	# The hidden AnswerLine remains the strict scoring authority and the
	# lane's authored guide remains the authority for horizontal hit testing.
	var canvas := _game.size
	var plane_screen := (_game.get_node("PlaneRig") as Control).get_rect().get_center()
	var score_progress := maxf(0.05, float(_game.call("_progress_for_answer_line")))
	if progress <= score_progress:
		var approaching := clampf(progress / score_progress, 0.0, 1.0)
		return Vector2(rect.get_center().x,
			lerpf(rect.get_center().y, plane_screen.y, approaching * approaching))
	var score_rect := rect
	if offsets.size() == 3 and gates.size() == 3:
		score_rect = _game.call("_gate_visible_rect_with_offsets",
			lane, score_progress, offsets, gates)
	var score_center := Vector2(score_rect.get_center().x, plane_screen.y)
	var near_distance := _gate_distance(progress, score_progress)
	# With fixed world XY, the ring naturally expands/moves out of camera view.
	return canvas * 0.5 + (score_center - canvas * 0.5) * airplane_camera_distance / near_distance


func _units_per_pixel(distance: float, canvas_size: Vector2) -> float:
	return 2.0 * distance * tan(deg_to_rad(view_camera.fov) * 0.5) / maxf(canvas_size.y, 1.0)


func _project_at(screen_point: Vector2, distance: float, canvas_size: Vector2) -> Vector3:
	# Viewport is same aspect as canvas; project_position yields actual 3D
	# coordinates from each screen-space scoring guide at a chosen 3D depth.
	var pixel := Vector2(screen_point.x / canvas_size.x * float(viewport.size.x),
		screen_point.y / canvas_size.y * float(viewport.size.y))
	return view_camera.project_position(pixel, distance)


func _sync_visibility() -> void:
	if not is_instance_valid(_game):
		return
	overlay.visible = hybrid_enabled
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if hybrid_enabled else SubViewport.UPDATE_DISABLED
	var background := _game.get_node_or_null("FlightBackground") as CanvasItem
	if background != null:
		background.visible = false
	var artwork := _game.get_node_or_null("PlaneRig/PlaneArtwork") as CanvasItem
	if artwork != null:
		artwork.visible = not hybrid_enabled
	for group in ["MovingGates", "UpcomingGates"]:
		for lane in ["GateLeft", "GateCenter", "GateRight"]:
			var sprite := _game.get_node_or_null(group + "/" + lane + "/GateArtwork") as TextureRect
			if sprite != null:
				sprite.visible = not (hybrid_enabled and draw_3d_gates)
