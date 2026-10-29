extends SceneTree

# 2D renderer, single authored PlaneRig and actual hitbox. No camera/DB.
# --headless --path . --script res://tools/test_human_plane_live_arm_bank_2d.gd
const GAME := preload("res://ui/minigames/human_plane/human_plane.tscn")
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for fps in [30, 60]:
		await _test_banking(fps)
	print("HUMAN PLANE FRESH ARM BANK 2D: %s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _new_game() -> Control:
	var game := GAME.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity": "Human Plane", "topic": "Noun",
		"game_mode": "Seconds", "difficulty": "Easy", "camera_live": false})
	return game


func _test_banking(fps: int) -> void:
	var game := _new_game()
	await process_frame
	await process_frame
	game.set_process(false)
	var label := "%dfps" % fps
	var dt := 1.0 / float(fps)
	var plane_rig := game.get_node("PlaneRig") as Control
	var artwork := game.get_node("PlaneRig/PlaneArtwork") as TextureRect
	var hitbox := game.get_node("PlaneRig/Hitbox") as Control
	var default_texture := artwork.texture
	var initial_hitbox := hitbox.get_rect()
	var authored_size := artwork.size
	var authored_offset: float = float(game.get("_plane_authored_offset_x"))
	_check(plane_rig != null and artwork != null and hitbox != null
		and game.get_node_or_null("WorldView3D") == null,
		label + " existing editable PURE 2D plane + hitbox preserved")
	game.set("plane_x_norm", 0.5)
	game.set("target_x_norm", 0.5)
	game.set_airplane_pose_active(false)
	game.set_body_x(1.0)
	game.call("_update_plane_motion", dt)
	_check(is_equal_approx(float(game.get("plane_x_norm")), 0.5),
		label + " no steering until fresh real pose explicitly active")
	game.set_airplane_pose_active(true)
	game.call("_update_plane_motion", dt)
	_check(is_equal_approx(float(game.get("plane_x_norm")), 0.5),
		label + " acquiring a pose cannot replay an old bank input")
	game.set_body_x(0.0)
	for _step in range(fps):
		game.call("_update_plane_motion", dt)
	_check(is_equal_approx(float(game.get("plane_x_norm")), 0.5),
		label + " centered horizontal T-pose does not drift for a full second")
	game.set_body_x(1.0)
	var previous := 0.5
	for i in range(fps):
		game.call("_update_plane_motion", dt)
		var current := float(game.get("plane_x_norm"))
		_check(current >= previous - 0.00001
			and current - previous <= dt * 0.82 + 0.0001,
			label + " bank-right frame%d moves smoothly without teleport" % i)
		game.call("_sync_visuals")
		_check(absf(plane_rig.get_rect().get_center().x
			- float(game.call("_plane_center_x"))) < 0.03,
			label + " frame%d rendered plane == scoring X" % i)
		previous = current
	_check(previous > 0.93 and previous <= 1.0,
		label + " sustained bank can reach right gate continuously")
	game.call("_update_flight_artwork", dt)
	_check(int(game.get("_bank_art_state")) == 1,
		label + " max screen-right bank selects right-facing artwork state")
	var right: Texture2D = game.get("_plane_bank_right_texture")
	if right != null:
		_check(artwork.texture == right,
			label + " right PNG uses existing authored PlaneArtwork TextureRect")
	# A single invalid pose or zero/2+ people forces this OFF from gameplay;
	# invalidating the gate must halt immediately even if velocity was high.
	game.set_airplane_pose_active(false)
	var held := float(game.get("plane_x_norm"))
	for _i in range(fps):
		game.call("_update_plane_motion", dt)
	_check(is_equal_approx(float(game.get("plane_x_norm")), held),
		label + " no stale bank velocity for a FULL SECOND after lost pose")
	_check(int(game.get("_bank_art_state")) == 0 and artwork.texture == default_texture,
		label + " loss of valid pose restores original PLANE.png artwork")
	_check(absf(artwork.rotation - float(game.get("_artwork_base_rotation"))) < 0.0001,
		label + " losing real wrists immediately removes old wing angle")
	game.set_airplane_pose_active(true)
	game.call("_update_plane_motion", dt)
	_check(is_equal_approx(float(game.get("plane_x_norm")), held),
		label + " resuming does not replay last bank until fresh target arrives")
	game.set_body_x(-0.80)
	var start := float(game.get("plane_x_norm"))
	for _i in range(fps):
		game.call("_update_plane_motion", dt)
	_check(float(game.get("plane_x_norm")) < start - 0.35,
		label + " proportional left tilt continuously traverses toward left gate")
	game.set_body_x(-1.0)
	game.call("_update_flight_artwork", dt)
	_check(int(game.get("_bank_art_state")) == -1,
		label + " max screen-left bank selects left-facing artwork state")
	var left: Texture2D = game.get("_plane_bank_left_texture")
	if left != null:
		_check(artwork.texture == left,
			label + " left PNG uses existing authored PlaneArtwork TextureRect")
	var left_before := float(game.get("plane_x_norm"))
	game.set_body_x(0.0)
	for _i in range(fps):
		game.call("_update_plane_motion", dt)
	_check(absf(float(game.get("plane_x_norm")) - left_before) < 0.15,
		label + " centered wing level softly decelerates, no instant recenter")
	game.call("_update_flight_artwork", dt)
	_check(int(game.get("_bank_art_state")) == 0,
		label + " level T-pose visually returns to default plane")
	game.set_body_x(1.0)
	game.call("_update_plane_motion", dt)
	game.call("_pause")
	var paused_x := float(game.get("plane_x_norm"))
	game.call("_resume")
	game.call("_update_plane_motion", dt)
	_check(is_equal_approx(float(game.get("plane_x_norm")), paused_x),
		label + " scene Pause/Resume requires NEW valid wing-bank packet")
	_check(artwork.size.distance_to(authored_size) < 0.02
		and hitbox.get_rect().position.distance_to(initial_hitbox.position) < 0.02
		and hitbox.size.distance_to(initial_hitbox.size) < 0.02
		and absf(float(game.get("_plane_authored_offset_x")) - authored_offset) < 0.001,
		label + " authored plane dimensions/hitbox/offset preserved after art swaps")
	var gate_left := game.get_node("MovingGates/GateLeft") as Control
	var gate_center := game.get_node("MovingGates/GateCenter") as Control
	var gate_right := game.get_node("MovingGates/GateRight") as Control
	_check(gate_left != null and gate_center != null and gate_right != null,
		label + " ALL original 2D pseudo-perspective gates preserved")
	game.queue_free()
	await process_frame


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FAIL ARM BANK: ", label)
