extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_assets_pose.gd
# The four currently referenced plane/gate PNGs are checked byte-for-byte via SHA256.
const SCENE := preload("res://ui/minigames/human_plane.tscn")
const ASSETS := {
	"PLANE.png": ["81826ebd6e13131793ff6bf8dafe4f03499b94661a1953ec24b2351189944b0e", Vector2i(1254, 1254)],
	"human_plane_gate_purple_LEFT.png": ["3e476898a6d996484bd6e8ff99297a35554a2d45848ceeea8aa21efc34c4f146", Vector2i(724, 724)],
	"human_plane_gate_green_CENTER.png": ["37cbd228e8c844f55e0c119a55be399f1ef2682acda9850de549bc03dc430e42", Vector2i(724, 724)],
	"human_plane_gate_blue_RIGHT.png": ["011b8452faaad74ab05ede0eff510e3bf70e53662f45294b5d8fda882c706ed8", Vector2i(724, 724)]
}
const AUTHORED_IMAGES := {
	"PlaneRig/PlaneArtwork": "PLANE.png",
	"MovingGates/GateLeft/GateArtwork": "human_plane_gate_purple_LEFT.png",
	"MovingGates/GateCenter/GateArtwork": "human_plane_gate_green_CENTER.png",
	"MovingGates/GateRight/GateArtwork": "human_plane_gate_blue_RIGHT.png"
}
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	for name in ASSETS:
		var expected: Array = ASSETS[name]
		var path: String = "res://Components/Gameplay/Human Plane/" + name
		var hex_hash := FileAccess.get_sha256(path)
		_check(hex_hash == String(expected[0]).replace(" ", ""), name + " SHA256 matches original file")
	var panel := SCENE.instantiate() as Control
	var authored := {}
	_collect_authored(panel, panel, authored)
	for node_path in AUTHORED_IMAGES:
		var image := panel.get_node_or_null(node_path) as TextureRect
		var filename: String = AUTHORED_IMAGES[node_path]
		_check(image != null, node_path + " TextureRect exists")
		if image == null:
			continue
		_check(image.owner == panel and authored.has(image.get_instance_id()), node_path + " is editor-authored")
		_check(image.texture != null, node_path + " texture actually resolves")
		if image.texture != null:
			_check(Vector2i(image.texture.get_size()) == ASSETS[filename][1], filename + " imported native dimensions preserved")
		_check(image.stretch_mode in [TextureRect.STRETCH_KEEP_ASPECT_CENTERED, TextureRect.STRETCH_KEEP_ASPECT_COVERED], node_path + " preserves aspect ratio")
	# The old Human Plane-specific HUD was replaced by the exact Catch Word
	# scene-authored plaques; gate/pose QA must check the current source nodes.
	for path in ["HUDLayer/HUD/TitlePlaque", "HUDLayer/HUD/PromptLabel", "HUDLayer/HUD/TimerPlaque", "HUDLayer/HUD/TimeLabel", "HUDLayer/HUD/LivesPlaque", "HUDLayer/HUD/PausePlaque", "HUDLayer/HUD/PauseButton", "HUDLayer/HUD/ScorePlaque", "HUDLayer/HUD/ScoreBottomContainer/ScoreNumber"]:
		var node := panel.get_node_or_null(path)
		_check(node != null and node.owner == panel, path + " editor-authored HUD")
	panel.set_context({"topic": "Noun", "game_mode": "Lives", "difficulty": "Hard"})
	root.add_child(panel)
	await process_frame
	await process_frame
	panel.set_process(false)
	_check(panel.has_method("set_airplane_pose_active"), "airplane pose activation API available")
	_check(not bool(panel.get("airplane_pose_active")), "starts disarmed without a verified airplane pose")
	var at_start := float(panel.get("plane_x_norm"))
	panel.call("set_body_x", 1.0)
	panel.call("_update_plane_motion", 0.5)
	_check(is_equal_approx(float(panel.get("plane_x_norm")), at_start), "lowered arms block movement")
	panel.call("set_airplane_pose_active", true)
	panel.call("_update_plane_motion", 0.25)
	_check(is_equal_approx(float(panel.get("plane_x_norm")), at_start), "re-enable clears stale camera target")
	panel.call("set_body_x", 1.0)
	panel.call("_update_plane_motion", 0.33)
	var active_x := float(panel.get("plane_x_norm"))
	_check(active_x > at_start + 0.1, "valid airplane pose smoothly steers to the right")
	panel.call("set_airplane_pose_active", false)
	panel.call("set_body_x", -1.0)
	panel.call("_update_plane_motion", 3.0)
	_check(is_equal_approx(float(panel.get("plane_x_norm")), active_x), "lowered arms freeze X even after large delta")
	panel.call("set_airplane_pose_active", false)
	panel.call("_update_plane_motion", 2.0)
	_check(is_equal_approx(float(panel.get("plane_x_norm")), active_x), "repeated invalid pose never moves")
	panel.call("set_airplane_pose_active", true)
	panel.call("_update_plane_motion", 0.5)
	_check(is_equal_approx(float(panel.get("plane_x_norm")), active_x), "re-raised arms do not replay stale target")
	panel.call("set_body_x", -1.0)
	panel.call("_update_plane_motion", 0.4)
	_check(float(panel.get("plane_x_norm")) < active_x - 0.1, "re-raised arms resume fresh tracking movement")
	panel.call("_process", 0.1)
	_check(int(panel.get("lives")) == 3, "three-life mode remains unchanged during pose transitions")
	_check(is_zero_approx(float(panel.get("time_remaining"))), "Lives remains untimed during pose transitions")
	_check((panel.get_node("HUDLayer/HUD/LivesPlaque") as TextureRect).visible and not (panel.get_node("HUDLayer/HUD/TimerPlaque") as TextureRect).visible, "Lives mode uses original Catch hearts, not the Seconds clock")
	panel.queue_free()
	await process_frame
	await process_frame
	# Regression: the editor can make a gate's travel rectangle wider than its
	# square PNG. The letterboxed margin must never score as a visible gate.
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		await _verify_visible_gate_alignment(resolution)
	print("HUMAN PLANE ASSETS/POSE: ", "PASS" if failures.is_empty() else "FAIL", " (%d checks; %d failures)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _verify_visible_gate_alignment(resolution: Vector2i) -> void:
	root.size = resolution
	var game := SCENE.instantiate() as Control
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_context({"activity": "Human Plane", "topic": "Noun", "difficulty": "Hard", "game_mode": "Lives"})
	await process_frame
	await process_frame
	game.set_process(false)
	var label := "%dx%d" % [resolution.x, resolution.y]
	var progress := float(game.call("_progress_for_answer_line"))
	var initial_box := game.call("_gate_rect", 1, progress) as Rect2
	var initial_sprite := game.call("_gate_visible_rect", 1, progress) as Rect2
	# With the currently shipped authored square gate markers, no letterbox
	# exists. This assertion also documents that the default layout is safe.
	_check(absf(initial_box.size.x - initial_sprite.size.x) < 1.5 and absf(initial_box.size.y - initial_sprite.size.y) < 1.5, label + " default gate travel bounds render square without invisible side margins")
	var gate := game.get_node("MovingGates/GateCenter") as Control
	var image := gate.get_node("GateArtwork") as TextureRect
	_check(image.texture != null and image.texture.get_size() == Vector2(724, 724), label + " original square gate texture used")
	_check(image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, label + " original gate artwork is aspect-preserving and centered")
	var gates_layer := game.get_node("MovingGates") as Control
	var plane_rig := game.get_node("PlaneRig") as Control
	# The old gate foreground obscured the pilot airplane in the user's real
	# screenshot. New flight readability requires the airplane above all gates.
	_check(plane_rig.z_index > gates_layer.z_index, label + " airplane stays in FRONT of gates without foreground occlusion")
	for lane_name in ["Left", "Center", "Right"]:
		var authored_gate := game.get_node("MovingGates/Gate" + lane_name) as Control
		var authored_art := authored_gate.get_node("GateArtwork") as TextureRect
		var pixels := authored_art.texture.get_image()
		_check(pixels.get_pixel(362, 350).a < 0.12, label + " " + lane_name + " arch center is transparent, revealing airplane/scenery behind")
		_check(pixels.get_pixel(362, 655).a > 0.50, label + " " + lane_name + " baked footer is opaque and draws above airplane")

	# Simulate an editor resizing both path markers to a wide rectangle while
	# preserving their centers. Art remains 1:1; its horizontal letterbox grows.
	var expansion := float(resolution.x) / 1280.0 * 220.0
	for path in ["FlightPaths/GateStartCenter", "FlightPaths/GateEndCenter"]:
		var marker := game.get_node(path) as Control
		marker.position.x -= expansion * 0.5
		marker.size.x += expansion
	progress = float(game.call("_progress_for_answer_line"))
	var travel_box := game.call("_gate_rect", 1, progress) as Rect2
	var drawn_box := game.call("_gate_visible_rect", 1, progress) as Rect2
	_check(travel_box.size.x > travel_box.size.y + 50.0, label + " editor resize creates a rectangular travel container")
	_check(absf(drawn_box.size.x - drawn_box.size.y) < 1.5, label + " actual square PNG still has equal rendered width and height")
	_check(drawn_box.size.x + 80.0 < travel_box.size.x, label + " image draws narrower than its widened container")
	_check(absf(drawn_box.get_center().x - travel_box.get_center().x) < 1.5, label + " centered texture and movement gate centers align")
	var hitbox := game.get_node("PlaneRig/Hitbox") as Control
	var half_plane := hitbox.size.x * 0.5
	# _lane_hit_at_answer_line() centers its overlap test on the *authored*
	# Hitbox, not necessarily the center of PlaneRig. Include that offset when
	# converting a desired world-space hitbox center to plane_x_norm.
	var hitbox_center_offset := hitbox.get_rect().get_center().x - plane_rig.size.x * 0.5
	var left_limit := game.get_node("FlightPaths/PlaneLeftLimit") as Control
	var right_limit := game.get_node("FlightPaths/PlaneRightLimit") as Control
	var left_bound := left_limit.get_rect().get_center().x
	var right_bound := right_limit.get_rect().get_center().x
	var authored_shift := float(game.get("_plane_authored_offset_x"))
	# Put airplane wholly outside the center PNG but inside its old broad travel
	# rectangle. Neighboring gates may legitimately overlap the plane at these
	# X coordinates; this must never falsely count as the CENTER lane.
	for side in [-1.0, 1.0]:
		var outside_x: float = drawn_box.get_center().x + float(side) * (drawn_box.size.x * 0.5 + half_plane + 5.0)
		var full_overlap: bool = outside_x + half_plane > travel_box.position.x and outside_x - half_plane < travel_box.end.x
		_check(full_overlap, label + " %.0f-side control would have hit old oversized rectangle" % side)
		var normalized: float = (outside_x - left_bound - authored_shift - hitbox_center_offset) / maxf(right_bound - left_bound, 1.0)
		game.set("plane_x_norm", normalized)
		var actual_x: float = float(game.call("_plane_center_x")) + hitbox_center_offset
		_check(absf(actual_x - outside_x) < 1.5, label + " %.0f-side test places actual authored plane hitbox at intended coordinate" % side)
		var hit_lane := int(game.call("_lane_hit_at_answer_line"))
		_check(hit_lane != 1, label + " %.0f-side invisible CENTER letterbox cannot falsely score the center gate" % side)
		if hit_lane >= 0:
			var neighboring_sprite := game.call("_gate_visible_rect", hit_lane, progress) as Rect2
			_check(outside_x + half_plane > neighboring_sprite.position.x and outside_x - half_plane < neighboring_sprite.end.x,
				label + " %.0f-side valid neighboring gate hit overlaps visible neighboring art" % side)
	# Also isolate the center gate by shifting only its neighboring editor guide
	# markers away; verify neither formerly invisible center margin can score.
	for lane in [0, 2]:
		var direction := -1.0 if lane == 0 else 1.0
		for marker_name in ["GateStart", "GateEnd"]:
			var lane_name := "Left" if lane == 0 else "Right"
			var guide := game.get_node("FlightPaths/" + marker_name + lane_name) as Control
			guide.position.x += direction * float(resolution.x)
	for side in [-1.0, 1.0]:
		var outside_x: float = drawn_box.get_center().x + float(side) * (drawn_box.size.x * 0.5 + half_plane + 5.0)
		var normalized: float = (outside_x - left_bound - authored_shift - hitbox_center_offset) / maxf(right_bound - left_bound, 1.0)
		game.set("plane_x_norm", normalized)
		_check(int(game.call("_lane_hit_at_answer_line")) == -1,
			label + " %.0f-side isolated invisible center letterbox cannot be hit" % side)
	# Center still registers as correct and awards the same 100 points as all modes.
	var centered_norm := (drawn_box.get_center().x - left_bound - authored_shift - hitbox_center_offset) / maxf(right_bound - left_bound, 1.0)
	game.set("plane_x_norm", centered_norm)
	_check(int(game.call("_lane_hit_at_answer_line")) == 1, label + " actual visible center gate correctly selects lane 1")
	var round_values := game.get("round_data") as Dictionary
	round_values["valid_indices"] = [1]
	game.set("round_data", round_values)
	var previous_lives := int(game.get("lives"))
	game.call("_resolve_at_answer_line")
	_check(bool(game.get("selected_was_correct")), label + " visible center gate still scores as correct")
	_check(int(game.get("score")) == 100 and int(game.get("correct_count")) == 1, label + " Hard center gate awards fixed 100 points")
	_check(int(game.get("lives")) == previous_lives, label + " correct visible center gate preserves lives")
	game.queue_free()
	await process_frame
	await process_frame


func _collect_authored(node: Node, owner: Node, ids: Dictionary) -> void:
	for child in node.get_children():
		if child.owner == owner:
			ids[child.get_instance_id()] = true
		_collect_authored(child, owner, ids)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("HUMAN PLANE ASSETS/POSE FAIL: ", message)
