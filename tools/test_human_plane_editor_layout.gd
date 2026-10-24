extends SceneTree

# Godot --headless --path . --script res://tools/test_human_plane_editor_layout.gd
# Assertions inspect PackedScene instances BEFORE _ready; runtime-made controls
# cannot pass as Godot-editor-authored, draggable components.
const SCENE := preload("res://ui/minigames/human_plane.tscn")
const CATCH := preload("res://ui/minigames/catch_word.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const NAMES := ["Left", "Center", "Right"]
const REQUIRED := {
	"SceneBackground/SkyBackdrop": "TextureRect",
	"PlaneRig": "Control",
	"PlaneRig/Hitbox": "Panel",
	"HUDLayer/HUD": "Control",
	"HUDLayer/HUD/TitlePlaque": "TextureRect",
	"HUDLayer/HUD/PromptLabel": "Label",
	"HUDLayer/HUD/TimerPlaque": "TextureRect",
	"HUDLayer/HUD/TimeLabel": "Label",
	"HUDLayer/HUD/LivesPlaque": "TextureRect",
	"HUDLayer/HUD/PausePlaque": "TextureRect",
	"HUDLayer/HUD/PauseButton": "Button",
	"HUDLayer/HUD/ScorePlaque": "TextureRect",
	"HUDLayer/HUD/ScoreBottomContainer": "VBoxContainer",
	"HUDLayer/HUD/ScoreBottomContainer/ScoreNumber": "Label",
}
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport in SIZES:
		await _exercise_scene(viewport)
	print("HUMAN PLANE EDITOR LAYOUT: ", "PASS" if failures.is_empty() else "FAIL", " (%d checks; %d failures)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _exercise_scene(viewport: Vector2i) -> void:
	root.size = viewport
	var game := SCENE.instantiate() as Control
	_check(game != null and game.has_method("_gate_rect"), "scene and gameplay script load")
	if game == null or not game.has_method("_gate_rect"):
		return
	var authored_ids := {}
	_collect_authored(game, game, authored_ids)
	var catch := CATCH.instantiate() as Control
	_check(catch != null and catch.get_node_or_null("HUDLayer/HUD") != null, "original Catch HUD reference is available")
	_check(game.get_node_or_null("HUDLayer") is CanvasLayer, "authored HUDLayer CanvasLayer is preserved")
	if game.get_node_or_null("HUDLayer") is CanvasLayer:
		_check((game.get_node("HUDLayer") as CanvasLayer).layer == (catch.get_node("HUDLayer") as CanvasLayer).layer,
			"HUD CanvasLayer draw layer exactly matches Catch")
	for path in REQUIRED:
		var item := game.get_node_or_null(path)
		_check(item != null and item.get_class() == String(REQUIRED[path]), "%s %s serialized type" % [viewport, path])
		if item != null:
			_check(item.owner == game and authored_ids.has(item.get_instance_id()), "%s %s directly editable in scene" % [viewport, path])
			if path.begins_with("HUDLayer/HUD/"):
				var original := catch.get_node_or_null(path) as Control
				_check(original != null, "Catch originally authors HUD part " + path)
				if original != null and item is Control:
					var control := item as Control
					_check(_layout_signature(control) == _layout_signature(original),
						"%s %s exact Catch editable original placement" % [viewport, path])
					if control is TextureRect and original is TextureRect:
						_check((control as TextureRect).texture.resource_path == (original as TextureRect).texture.resource_path,
							"original Catch HUD texture reused: " + path)
	catch.free()
	for old_hud in ["HUD", "PauseButton", "HUD/ScoreArtwork", "HUD/StatsBar",
		"HUD/ObjectivePanel", "HUD/LivesArtwork", "HUD/TimerArtwork", "HUD/ModeLabel",
		"HUD/LivesHearts", "HUD/StatsBar/WaveLabel", "HUDLayer/HUD/WaveLabel",
		"HUDLayer/HUD/LivesHearts/Heart4", "HUDLayer/HUD/LivesHearts/Heart5"]:
		_check(game.get_node_or_null(old_hud) == null, "deleted obsolete HUD control " + old_hud)
	# The user requested deletion of the entire old procedural scenery/airplane
	# system. Do not restore these invisible duplicates just to satisfy legacy QA.
	for obsolete_path in [
		"SceneBackground/FarHills", "SceneBackground/GreenGround", "SceneBackground/Sun",
		"SceneBackground/Cloud1", "SceneBackground/Cloud2", "SceneBackground/Cloud3",
		"SceneBackground/Cloud4", "SceneBackground/PerspectiveArtwork",
		"SceneBackground/PerspectiveArtwork/Runway",
		"PlaneRig/PlaneBody", "PlaneRig/PlaneWings", "PlaneRig/PlaneTail", "PlaneRig/Cockpit"
	]:
		_check(game.get_node_or_null(obsolete_path) == null, "old procedural style removed: " + obsolete_path)
	for i in range(4):
		_check(game.get_node_or_null("SceneBackground/PerspectiveArtwork/LaneGuide%d" % i) == null, "old runway guide %d removed" % i)
	_check((game.get_node("MovingGates") as Control).visible, "actual editor-authored answer gates visible during gameplay")
	for lane in NAMES:
		for marker in ["GateStart", "GateEnd"]:
			var path: String = "FlightPaths/" + String(marker) + String(lane)
			var control := game.get_node_or_null(path) as Control
			_check(control != null and control.owner == game and control.visible, "editor-visible draggable " + path)
		for piece in ["Interior", "LeftPillar", "RightPillar", "TopBar", "WordLabel", "LaneLabel"]:
			var part := game.get_node_or_null("MovingGates/Gate" + lane + "/" + piece)
			_check(part != null and part.owner == game, "authored Gate" + lane + "/" + piece)
	_check(game.get_node_or_null("FlightPaths/PlaneLeftLimit") is Control, "authored left steering marker")
	_check(game.get_node_or_null("FlightPaths/PlaneRightLimit") is Control, "authored right steering marker")
	var original_children := authored_ids.size()
	# Moving the rig BEFORE it enters the tree mirrors repositioning it in the
	# Godot editor (only the X movement from pose tracking remains scripted).
	var rig := game.get_node("PlaneRig") as Control
	rig.position.x += 17.0
	var authored_left_gate := game.get_node("MovingGates/GateLeft") as Control
	var authored_left_start := game.get_node("FlightPaths/GateStartLeft") as Control
	var original_left_rect := authored_left_gate.get_rect()
	var original_left_start := authored_left_start.get_rect()
	var left_authored_offset := Rect2(original_left_rect.position - original_left_start.position, original_left_rect.size - original_left_start.size)
	var authored_right_gate := game.get_node("MovingGates/GateRight") as Control
	authored_right_gate.position.x += 35.0
	var authored_right_start := game.get_node("FlightPaths/GateStartRight") as Control
	var original_right_rect := authored_right_gate.get_rect()
	var original_right_start := authored_right_start.get_rect()
	var right_authored_offset := Rect2(original_right_rect.position - original_right_start.position, original_right_rect.size - original_right_start.size)
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {"activity": "Human Plane", "topic": "Noun", "difficulty": "Hard", "game_mode": "Seconds"})
	await process_frame
	await process_frame
	game.set_process(false)
	var runtime_ids := {}
	_collect_authored(game, game, runtime_ids)
	_check(runtime_ids.size() == original_children, "%s no generated UI ghost nodes" % viewport)
	var gate_parts: Array = []
	for lane in NAMES:
		gate_parts.append(game.get_node("MovingGates/Gate" + lane) as Control)
	_check(gate_parts.size() == 3, "exactly three authored moving gates")
	var lane0_start := (game.call("_gate_rect", 0, 0.0) as Rect2)
	var marker := game.get_node("FlightPaths/GateStartLeft") as Control
	var expected_left := Rect2(marker.get_rect().position + left_authored_offset.position, marker.get_rect().size + left_authored_offset.size)
	_check(lane0_start.is_equal_approx(expected_left), "gate 0 path preserves the user-authored visible gate offset from its marker")
	var right_start := game.call("_gate_rect", 2, 0.0) as Rect2
	var right_marker := game.get_node("FlightPaths/GateStartRight") as Control
	var expected_right := Rect2(right_marker.get_rect().position + right_authored_offset.position, right_marker.get_rect().size + right_authored_offset.size)
	_check(right_start.is_equal_approx(expected_right), "dragging visible gate artwork before _ready preserves its original offset plus 35px")
	var gate_end := game.get_node("FlightPaths/GateEndLeft") as Control
	var before := game.call("_gate_rect", 0, 1.0) as Rect2
	gate_end.position.x += 48.0
	var after := game.call("_gate_rect", 0, 1.0) as Rect2
	_check(absf(after.get_center().x - before.get_center().x - 48.0) < 0.25, "dragging editor gate endpoint changes collision path by 48px")
	game.set("gate_progress", 0.5)
	game.call("_draw_hud")
	var shown := gate_parts[0] as Control
	var expected := game.call("_gate_rect", 0, 0.5) as Rect2
	_check(shown.get_rect().is_equal_approx(expected), "visible gate animation uses the SAME editor path as collision")
	var original_line_y := float(game.call("_answer_line_y"))
	var answer_line := game.get_node_or_null("AnswerLine") as Control
	if answer_line != null:
		answer_line.position.y += 28.0
		_check(absf(float(game.call("_answer_line_y")) - original_line_y - 28.0) < 0.25, "dragging authored AnswerLine updates collision crossing height")
	else:
		# The owner intentionally deleted AnswerLine. The current gameplay
		# script uses the editor-authored GateEndCenter guide as its fallback.
		var fallback := game.get_node("FlightPaths/GateEndCenter") as Control
		_check(fallback.owner == game, "deleted AnswerLine uses draggable authored GateEndCenter fallback")
		fallback.position.y += 28.0
		_check(absf(float(game.call("_answer_line_y")) - original_line_y - 28.0) < 0.25, "dragging fallback guide changes collision crossing height")
	var original_plane_y := float(game.call("_plane_y"))
	rig.position.y += 19.0
	game.call("_draw_plane")
	_check(absf(float(game.call("_plane_y")) - original_plane_y - 19.0) < 0.25, "dragging PlaneRig changes live hitbox height")
	var answer_line_y := float(game.call("_answer_line_y"))
	_check(absf(answer_line_y - float(game.call("_answer_line_y"))) < 0.001, "visual update does not reset answer line position")
	_check(game.has_method("_gate_word_fit") and game.has_method("_lane_hit_at_answer_line"), "old hitbox and word-fit API retained")
	_check(game.has_method("_draw_hud") and game.has_method("_draw_plane"), "legacy draw entry points are compatible")
	# All editable HUD text must remain on screen on both desktop resolutions.
	for path in REQUIRED:
		var node := game.get_node_or_null(path)
		if node is Label and node.is_visible_in_tree() and not path.begins_with("MovingGates"):
			var label := node as Label
			var bounds := label.get_global_rect()
			var viewport_bounds := Rect2(game.global_position, game.size)
			_check(viewport_bounds.encloses(bounds), "%s HUD %s fits in viewport" % [viewport, path])
	var timer := game.get_node("HUDLayer/HUD/TimeLabel") as Label
	var lives := game.get_node("HUDLayer/HUD/LivesPlaque") as TextureRect
	var score := game.get_node("HUDLayer/HUD/ScoreBottomContainer/ScoreNumber") as Label
	_check(timer.is_visible_in_tree() and timer.text == "60s", "Seconds 60s shown on Catch TimeLabel")
	_check(not lives.visible and not lives.is_visible_in_tree(), "Catch LivesPlaque hidden in Seconds")
	_check(score.is_visible_in_tree() and score.text == "0", "cloned Catch ScoreNumber shows unpadded score")
	_check(game.get_node_or_null("HUDLayer/HUD/WaveLabel") == null, "obsolete WAVE counter is not part of cloned HUD")
	_check(game.get_node_or_null("HUD/LivesHearts/Heart4") == null and game.get_node_or_null("HUD/LivesHearts/Heart5") == null,
		"only native three-heart plaque exists (no overlay hearts)")
	game.queue_free()
	await process_frame
	await process_frame
	print("Verified authored Human Plane at ", viewport)


func _collect_authored(node: Node, owner: Node, ids: Dictionary) -> void:
	for child in node.get_children():
		if child.owner == owner:
			ids[child.get_instance_id()] = true
		_collect_authored(child, owner, ids)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("HUMAN-PLANE EDITOR FAIL: ", description)


func _layout_signature(control: Control) -> Array:
	return [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom,
		control.offset_left, control.offset_top, control.offset_right, control.offset_bottom,
		control.custom_minimum_size]
