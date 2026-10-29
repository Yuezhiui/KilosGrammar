extends Node2D

## Native perspective 3D flight world in its own Node3D .tscn, composited below
## the unchanged 2D scoring/grammar HUD. 2D editor guides determine the hit
## lane; visual positions are projected from those SAME scoring rectangles.
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


func _ready() -> void:
	_game = get_parent() as Control
	viewport.transparent_bg = false
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X if force_4x_msaa else Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	overlay.texture = viewport.get_texture()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_first_gate_group = _game.get_node("MovingGates") as Control
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
	# Distinct 3D distances, true perspective scaling, and different movement
	# speed/parallax. Camera/plane movement never depends on these clouds.
	far_clouds.position = Vector3(-bank * 0.24 + sin(_cloud_elapsed * 0.14) * 0.34,
		sin(_cloud_elapsed * 0.09) * 0.14, sin(_cloud_elapsed * 0.11) * 0.8)
	near_clouds.position = Vector3(-bank * 0.85 + sin(_cloud_elapsed * 0.32) * 0.95,
		sin(_cloud_elapsed * 0.22) * 0.34, sin(_cloud_elapsed * 0.27) * 1.6)

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
	var plane_depth := airplane_camera_distance
	var target_width := plane_width_pixels * canvas_size.y / DESIGN_SIZE.y
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
		var at_score_rect: Rect2 = _game.call("_gate_visible_rect_with_offsets",
			lane, scoring_progress, offsets, controls)
		var distance := _gate_distance(progress, scoring_progress)
		var center := gate_screen_center(lane, progress, rect, not is_front, offsets, controls)
		if progress > scoring_progress:
			# XY is FROZEN at the plane's physical crossing position. Only Z
			# advances toward the near clip. Reprojecting at every Z would move
			# the ring with the camera ray instead of flying through it.
			var at_score_center := gate_screen_center(lane, scoring_progress,
				at_score_rect, not is_front, offsets, controls)
			var at_plane := _project_at(at_score_center, plane_depth, canvas_size)
			var now := _project_at(at_score_center, distance, canvas_size)
			ring.position = Vector3(at_plane.x, at_plane.y, now.z)
		else:
			ring.position = _project_at(center, distance, canvas_size)
		var scale_depth := plane_depth if progress > scoring_progress else distance
		var basis_rect := at_score_rect if progress > scoring_progress else rect
		var pixels_per_unit := _units_per_pixel(scale_depth, canvas_size)
		var minimum_outer_width := target_width * plane_ring_clearance / 0.82
		ring.scale = Vector3(maxf(basis_rect.size.x, lerpf(0.0, minimum_outer_width,
			clampf(progress / scoring_progress, 0.0, 1.0))) * pixels_per_unit * 0.5,
			maxf(basis_rect.size.y, minimum_outer_width * 0.82) * pixels_per_unit * 0.5, 1.0)
		var chosen := passing and int(_game.get("selected_lane")) == lane
		var color: Color = (Color("#43DF79") if bool(_game.get("selected_was_correct"))
			else Color("#FF5068")) if chosen else GATE_COLORS[lane]
		color.a = alpha
		var material := materials[lane] as StandardMaterial3D
		if material.albedo_color != color:
			material.albedo_color = color
			material.emission = Color(color.r * 0.18, color.g * 0.18, color.b * 0.18)


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
