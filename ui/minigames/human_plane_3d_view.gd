extends SubViewportContainer

## Presentation-only 3D world. HumanPlane owns quiz generation, calibrated
## webcam steering, timing, pause and authoritative hit detection. This scene
## presents that SAME state with editor-authored portrait 3D portals and labels.
const LANE_X := [-6.0, 0.0, 6.0]
const LANE_TINTS := [Color("#bda1f7"), Color("#91e9bb"), Color("#9bc9ff")]
const SCENERY_SPEED := 7.5
const RING_FAR_Z := -22.0
const RING_CROSSING_Z := 7.9
const PREVIEW_LIMIT_SECONDS := 0.025
const SCENERY_REUSE_LENGTH := 160.0
const FOREST_REUSE_LENGTH := 180.0
const CLOUD_REUSE_LENGTH := 180.0
const CLOUD_REUSE_NEAR_Z := 24.0
const RED_PLANE_PATH := "res://Components/Gameplay/Human Plane/3D/toy_plane/scene.gltf"

# Public export: the CC BY Toy Plane keeps its native imported materials.
# Editable in the WorldView3D inspector. Optional template can be assigned. The old template contains ALL five
# original artist textures. Per-mesh material cloning below preserves each
# original FBX surface's albedo and identities rather than painting every
# propeller/cockpit/window red with a global override.
@export var red_plane_pbr_template: StandardMaterial3D = null
# The old [-9.5,+9.5] linear steering was calibrated for placeholder lane
# guides. The live game's actual _lane_hit_at_answer_line() uses moving sprite
# bounds: these are the measured student body-X positions that resolve cleanly
# to the three answer choices. Keep them editable with the scene.
@export_range(0.0, 1.0, 0.0001) var scored_left_x_norm := 0.3267854
@export_range(0.0, 1.0, 0.0001) var scored_center_x_norm := 0.4938553
@export_range(0.0, 1.0, 0.0001) var scored_right_x_norm := 0.6600475

# Small per-wave render timelines. The authoritative gameplay only provides
# progress snapshots; _process advances the 3D picture every rendered frame.
# Render prediction is capped to 25 ms and never changes answer resolution.
class RingTimeline:
	var key := ""
	var sample := 0.0
	var presented := 0.0
	var velocity := 0.0
	var sampled_at := 0.0
	var valid := false
	var resolved := false
	var crossing := 0.5

@onready var viewport_3d: SubViewport = $Viewport3D
@onready var flight_world: Node3D = $Viewport3D/FlightWorld
@onready var camera: Camera3D = $Viewport3D/FlightWorld/Camera3D
@onready var player_rig: Node3D = $Viewport3D/FlightWorld/PlayerRig
@onready var red_plane: Node3D = $Viewport3D/FlightWorld/PlayerRig/RedPlane
@onready var scenery: Node3D = $Viewport3D/FlightWorld/Scenery
@onready var cloud_props: Node3D = $Viewport3D/FlightWorld/CloudFlight/CloudProps
@onready var current_rings: Node3D = $Viewport3D/FlightWorld/CurrentRings
@onready var upcoming_rings: Node3D = $Viewport3D/FlightWorld/UpcomingRings
@onready var _current_gates: Array[Node3D] = [
	$Viewport3D/FlightWorld/CurrentRings/GateLeft,
	$Viewport3D/FlightWorld/CurrentRings/GateCenter,
	$Viewport3D/FlightWorld/CurrentRings/GateRight,
]
@onready var _upcoming_gates: Array[Node3D] = [
	$Viewport3D/FlightWorld/UpcomingRings/GateLeft,
	$Viewport3D/FlightWorld/UpcomingRings/GateCenter,
	$Viewport3D/FlightWorld/UpcomingRings/GateRight,
]

var _running := true
var speed_multiplier := 1.0
var _last_x_norm := 0.5
var _flight_time := 0.0
var _rig_authored_y := 2.0
var _render_clock := 0.0
var _current_timeline := RingTimeline.new()
var _upcoming_timeline := RingTimeline.new()
var _scrolling_props: Array[Node3D] = []
var _scrolling_clouds: Array[Node3D] = []
var _scoring_lane_centers := PackedFloat32Array()
var _bank_target := 0.0


func _ready() -> void:
	# SubViewportContainer automatically stretches the 3D texture, and it does
	# not steal mouse input from Pause or the game's native CanvasLayer HUD.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The plane's height/depth are editor-authored: keep them when gameplay
	# starts. PlayerRig stays at exact unit scale and the RedPlane imported
	# instance scale is editor-authored (the public fallback uses Toy Plane).
	# Private FBX imports may require root_scale
	# 14.5; no hidden intermediate scale node alters the Inspector hierarchy.
	_rig_authored_y = player_rig.position.y
	# Camera aim, position, and FOV are authored entirely in the scene. The
	# former look_at() here overwrote manual Godot camera adjustments at launch.
	for item in cloud_props.get_children():
		if item is Node3D:
			_scrolling_clouds.append(item)
	# Old world assets are deliberately preserved for editing but are hidden
	# during cloud flight. Avoid cloning/tinting dozens of unused FBX materials
	# or moving invisible grass/tree/rock scenery every rendered frame.
	if scenery.visible:
		for item in scenery.get_children():
			if item is Node3D:
				if item.name == "GrassInstances":
					for grass_band in item.get_children():
						if grass_band is MultiMeshInstance3D:
							_scrolling_props.append(grass_band)
					continue
				_scrolling_props.append(item)
	# The public Toy Plane retains the imported CC BY material.
	# Never desaturate/replace the artist's textures with the old grey toy tint.
	_detach_imported_plane_skin(red_plane)
	_apply_plane_pbr(red_plane)
	current_rings.visible = false
	upcoming_rings.visible = false
	set_process(true)


func _tint_model(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = tint
		material.roughness = 0.84
		var mesh_instance := node as MeshInstance3D
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.visibility_range_end = 145.0
	for descendant in node.get_children():
		_tint_model(descendant, tint)


func set_speed_multiplier(multiplier: float) -> void:
	# Real scenery must accelerate WITH the rings. Never reduce the boost
	# after an incorrect gate and never cap the user's earned speed.
	if is_finite(multiplier):
		speed_multiplier = maxf(speed_multiplier, maxf(multiplier, 1.0))


func set_scoring_lane_centers(centers: PackedFloat32Array) -> void:
	# Provided by HumanPlane before sync_flight: derived from the CURRENT
	# editor-authored rendered quiz option rectangles and plane hitbox, not from
	# obsolete fixed lane guide midpoints. This prevents aircraft/gate scoring
	# mismatch when teachers reposition UI hitboxes or change the viewport.
	if centers.size() != 3:
		return
	var left := float(centers[0])
	var middle := float(centers[1])
	var right := float(centers[2])
	if not is_finite(left) or not is_finite(middle) or not is_finite(right):
		return
	if left <= 0.0 or right >= 1.0 or left >= middle or middle >= right:
		return
	_scoring_lane_centers = centers.duplicate()


func _detach_imported_plane_skin(node: Node) -> void:
	# This particular supplied FBX imports its 22 meshes as skin-bound parts.
	# Its animation skeleton deforms the visible wings far above/away from the
	# original fuselage (verified by real OpenGL screenshot). Disconnecting skin
	# and skeleton restores all 22 ORIGINAL mesh surfaces in correct positions,
	# WITHOUT generating substitute geometry or altering the source FBX/PBR.
	if node is MeshInstance3D:
		var part := node as MeshInstance3D
		part.skin = null
		part.skeleton = NodePath()
	for child in node.get_children():
		_detach_imported_plane_skin(child)


func _apply_plane_pbr(node: Node) -> void:
	if node is MeshInstance3D and red_plane_pbr_template != null:
		var part := node as MeshInstance3D
		if part.mesh != null:
			for surface in range(part.mesh.get_surface_count()):
				var original := part.get_active_material(surface) as StandardMaterial3D
				var material: StandardMaterial3D = original.duplicate() if original != null \
					else red_plane_pbr_template.duplicate()
				# Preserve original per-part base color/texture and normal where
				# present; attach full source physical maps on every FBX mesh.
				if material.albedo_texture == null:
					material.albedo_texture = red_plane_pbr_template.albedo_texture
				if not material.normal_enabled or material.normal_texture == null:
					material.normal_enabled = true
					material.normal_texture = red_plane_pbr_template.normal_texture
				material.metallic = red_plane_pbr_template.metallic
				material.metallic_texture = red_plane_pbr_template.metallic_texture
				material.metallic_texture_channel = red_plane_pbr_template.metallic_texture_channel
				material.roughness = red_plane_pbr_template.roughness
				material.roughness_texture = red_plane_pbr_template.roughness_texture
				material.roughness_texture_channel = red_plane_pbr_template.roughness_texture_channel
				material.ao_enabled = true
				material.ao_texture = red_plane_pbr_template.ao_texture
				material.ao_texture_channel = red_plane_pbr_template.ao_texture_channel
				part.set_surface_override_material(surface, material)
	for child in node.get_children():
		_apply_plane_pbr(child)


func sync_flight(plane_x_norm: float, current_data: Dictionary, current_progress: float,
		upcoming_data: Dictionary, upcoming_progress: float, resolved: bool,
		selected_lane: int, selected_correct: bool, round_finished: bool,
		round_paused: bool, answer_progress: float, pose_active: bool) -> void:
	if not is_node_ready():
		return
	_running = not round_finished and not round_paused
	# Keep X position corresponding to the calibrated -1..+1 body input.
	var x := clampf(plane_x_norm, 0.0, 1.0)
	# Line up the aircraft with the real scored 2D hitbox centers and the
	# editor-authored X positions of the corresponding 3D portrait portals.
	player_rig.position.x = _render_x_from_body_norm(x)
	# Position follows the *authoritative* body scorer immediately, including
	# at the crossing line. Only the visual banking angle is smoothed between
	# incoming camera packets, so presentation never misses a hitbox by lag.
	if pose_active and _running:
		_bank_target = clampf((_last_x_norm - x) * 2.1, -0.27, 0.27)
	_last_x_norm = x
	_sync_ring_group(current_rings, _current_timeline, current_data, current_progress,
		resolved, selected_lane, selected_correct, round_finished, answer_progress)
	_sync_ring_group(upcoming_rings, _upcoming_timeline, upcoming_data, upcoming_progress,
		false, -1, false, round_finished, answer_progress)
	if not _running:
		# Round pause/finish is a hard presentation freeze. Never extrapolate past
		# the current visual position while gameplay is suspended. Keep the
		# final subframe's tiny render lead to avoid a pause-time backwards jump.
		_current_timeline.presented = maxf(
			_current_timeline.presented, _current_timeline.sample)
		_upcoming_timeline.presented = maxf(
			_upcoming_timeline.presented, _upcoming_timeline.sample)
	_render_rings()


func _render_x_from_body_norm(x: float) -> float:
	var left: float = scored_left_x_norm
	var middle: float = scored_center_x_norm
	var right: float = scored_right_x_norm
	if _scoring_lane_centers.size() == 3:
		left = _scoring_lane_centers[0]
		middle = _scoring_lane_centers[1]
		right = _scoring_lane_centers[2]
	middle = clampf(middle, 0.01, 0.99)
	left = minf(left, middle - 0.001)
	right = maxf(right, middle + 0.001)
	# Read the 3D gate X centers from the scene every time, so moving a portal
	# in the Godot editor also moves its aligned airplane flight target.
	var left_world := _current_gates[0].position.x
	var center_world := _current_gates[1].position.x
	var right_world := _current_gates[2].position.x
	if x < left:
		return left_world - 2.0 * tanh((left - x) * 3.0 / (middle - left))
	if x <= middle:
		return lerpf(left_world, center_world, (x - left) / (middle - left))
	if x <= right:
		return lerpf(center_world, right_world, (x - middle) / (right - middle))
	return right_world + 2.0 * tanh((x - right) * 3.0 / (right - middle))


func _sync_ring_group(group: Node3D, track: RingTimeline, data: Dictionary,
		progress: float, resolved: bool, selected_lane: int, correct: bool,
		round_finished: bool, answer_progress: float) -> void:
	var words: Array = data.get("options", [])
	group.visible = not round_finished and words.size() == 3
	if not group.visible:
		track.valid = false
		return
	var authoritative := clampf(progress, 0.0, 1.0)
	var key := "|".join(PackedStringArray([
		String(words[0]), String(words[1]), String(words[2])]))
	if not track.valid or track.key != key or authoritative < track.sample - 0.04:
		# When a prefetched question becomes active, retain its exact world Z;
		# both groups use an identical progress-to-Z function, so promotion cannot
		# teleport the approaching ring set forward.
		if track == _current_timeline and _upcoming_timeline.valid \
				and _upcoming_timeline.key == key:
			track.presented = _upcoming_timeline.presented
			track.velocity = _upcoming_timeline.velocity
		else:
			track.presented = authoritative
			track.velocity = 0.0
		track.key = key
		track.valid = true
	else:
		var sample_period := _render_clock - track.sampled_at
		if sample_period > 0.0001 and authoritative > track.sample:
			var measured_speed := (authoritative - track.sample) / sample_period
			# Speeds are tied to gameplay, never inferred from YOLO packet FPS.
			# Previous 0.7 cap caused ring movement to visually decelerate after
			# sufficiently many correct answers even as gameplay sped up.
			track.velocity = maxf(measured_speed, 0.0)
		elif authoritative < track.sample:
			track.velocity = 0.0
	track.sample = authoritative
	track.sampled_at = _render_clock
	track.resolved = resolved
	track.crossing = clampf(answer_progress, 0.05, 0.99)
	# A new sample is never allowed to leave the visual behind the hit plane.
	# Cap any earlier interpolation lead to the next 25 ms of measured progress.
	var ahead_limit := track.velocity * PREVIEW_LIMIT_SECONDS
	track.presented = clampf(maxf(track.presented, authoritative),
		authoritative, minf(authoritative + ahead_limit, 1.0))
	var gates := _current_gates if group == current_rings else _upcoming_gates
	for i in range(3):
		var gate := gates[i]
		gate.visible = true
		# Each gate owns its own native 9:16 frame, plaque, and live word Label3D.
		gate.call("set_word", String(words[i]), LANE_TINTS[i],
			resolved and selected_lane == i, correct)


func _render_rings() -> void:
	_render_ring_group(current_rings, _current_timeline)
	_render_ring_group(upcoming_rings, _upcoming_timeline)


func _render_ring_group(group: Node3D, track: RingTimeline) -> void:
	if not track.valid or not group.visible:
		return
	if _running:
		# Smoothly fill the interval between gameplay snapshots. The maximum
		# lookahead is shorter than two display frames; do not draw a ring through
		# the scoring plane before the authoritative collision is resolved.
		var age := clampf(_render_clock - track.sampled_at, 0.0, PREVIEW_LIMIT_SECONDS)
		var candidate := minf(1.0, track.sample + track.velocity * age)
		if not track.resolved:
			candidate = minf(candidate, track.crossing)
		track.presented = maxf(track.presented, candidate)
	# Maintain the exact same world-space depth velocity BEFORE and AFTER
	# crossing the gameplay-authoritative answer plane. The old approach/exit
	# lerps had different slopes and slowed each ring >2x once it passed the
	# plane. One affine mapping keeps flight speed continuous at every score
	# multiplier and camera pose, including when the ring passes the camera.
	var distance_per_progress := (RING_CROSSING_Z - RING_FAR_Z) / track.crossing
	var z := RING_FAR_Z + track.presented * distance_per_progress
	var gates := _current_gates if group == current_rings else _upcoming_gates
	for i in range(3):
		var gate := gates[i]
		# Animate depth only. Editor-authored horizontal/vertical placement
		# stays editable and is never overwritten by a runtime transform.
		gate.position.z = z


func _process(delta: float) -> void:
	if not _running or delta <= 0.0:
		return
	var step := minf(delta, 0.1)
	_render_clock += step
	_flight_time += step
	_render_rings()
	# Low-poly cloud instances are editor-authored and pooled. Recycle whole
	# cloud groups at the far edge instead of allocating objects each frame.
	for cloud in _scrolling_clouds:
		cloud.position.z += SCENERY_SPEED * speed_multiplier * step
		if cloud.position.z > CLOUD_REUSE_NEAR_Z:
			cloud.position.z -= CLOUD_REUSE_LENGTH
	if scenery.visible:
		for prop in _scrolling_props:
			prop.position.z += SCENERY_SPEED * speed_multiplier * step
			if prop.name.begins_with("NatureGrass"):
				if prop.position.z > 64.0:
					prop.position.z -= FOREST_REUSE_LENGTH
			elif prop.position.z > 38.0:
				prop.position.z -= SCENERY_REUSE_LENGTH
	# Smooth banking on the render clock, independent of low pose packet FPS.
	# Lateral position itself is always an exact scored ring-space position.
	player_rig.rotation.z = lerpf(player_rig.rotation.z, _bank_target,
		1.0 - exp(-20.0 * step))
	_bank_target = lerpf(_bank_target, 0.0, 1.0 - exp(-7.0 * step))
	# Small lift makes the plane feel alive without changing the collision X.
	player_rig.position.y = _rig_authored_y + sin(_flight_time * 2.5) * 0.07
