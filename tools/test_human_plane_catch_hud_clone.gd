extends SceneTree

# Shared Catch/Human Plane HUD art comparison; Human Plane has its own
# inspector-authored positions/title/fonts. Do NOT overwrite with Catch geometry.
# Godot --headless --path . --script res://tools/test_human_plane_catch_hud_clone.gd
const CATCH := preload("res://ui/minigames/catch_the_word/catch_word.tscn")
const PLANE := preload("res://ui/minigames/human_plane/human_plane.tscn")
const NODES := [
	"TitlePlaque", "PromptLabel", "TimerPlaque", "TimeLabel",
	"PauseButton", "PausePlaque", "ScorePlaque", "LivesPlaque"
]
const REMOVED := [
	"HUD", "PauseButton", "HUD/StatsBar", "HUD/TitleArtwork",
	"HUD/ObjectivePanel", "HUD/ScoreArtwork", "HUD/TimerArtwork",
	"HUD/LivesArtwork", "HUD/ModeArtwork", "HUD/ModeLabel",
	"HUD/LivesHearts", "HUD/InstructionLabel", "HUD/DifficultyLabel",
	"HUD/FeedbackPanel"
]
var checks := 0
var failures: Array[String] = []
var authored_rects: Dictionary = {}
var authored_anchors: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source := CATCH.instantiate() as Control
	var target := PLANE.instantiate() as Control
	_check(source != null and target != null, "source and target scenes load")
	if source == null or target == null:
		quit(1)
		return
	var source_hud := source.get_node("HUDLayer/HUD") as Control
	var target_hud := target.get_node("HUDLayer/HUD") as Control
	_check(source_hud.has_node("ScoreNumber") and not source_hud.has_node("ScoreBottomContainer"),
		"Catch keeps its designer-authored direct ScoreNumber without an empty container")
	_check(target_hud.has_node("ScoreBottomContainer/ScoreNumber"),
		"Human Plane retains its separate, unchanged score hierarchy")
	_check(target_hud.owner == target, "complete HUD copied as scene-authored nodes")
	_check((target.get_node("HUDLayer") as CanvasLayer).layer == (source.get_node("HUDLayer") as CanvasLayer).layer, "CanvasLayer 20 matches Catch and stays above moving gates")
	var title_plate := target_hud.get_node_or_null("HumanPlaneTitlePanel") as Panel
	var independent_title := target_hud.get_node_or_null("HumanPlaneTitlePanel/HumanPlaneTitle") as Label
	_check(title_plate == null and independent_title == null
		and (target_hud.get_node("TitlePlaque") as TextureRect).visible
		and (target_hud.get_node("TitlePlaque") as TextureRect).texture.resource_path.ends_with("/human_plane.png"),
		"removed redundant title nodes and replaced the Catch plaque with supplied Human Plane title PNG")
	_check((target_hud.get_node("PromptLabel") as Label).visible
		and _valid_design_rect((target_hud.get_node("PromptLabel") as Label).get_rect()),
		"compact grammar question sits inside the supplied title board")
	for path in NODES:
		var a := source_hud.get_node(path) as Control
		var b := target_hud.get_node_or_null(path) as Control
		_check(b != null and b.owner == target, "copied editor node: " + path)
		if b == null:
			continue
		_check(a.get_class() == b.get_class(), "same source node type " + path)
		_check(_valid_design_rect(b.get_rect()),
			"independently authored Human Plane " + path + " has finite positive, on-canvas geometry")
		authored_rects[path] = b.get_rect()
		var anchors := [b.anchor_left, b.anchor_top, b.anchor_right, b.anchor_bottom]
		authored_anchors[path] = anchors
		_check(_valid_design_anchors(anchors),
			"independent Human Plane " + path + " has valid editor-authored anchors")
		if a is TextureRect:
			_check(((b as TextureRect).texture.resource_path.ends_with("/human_plane.png") if path == "TitlePlaque"
				else (a as TextureRect).texture.resource_path == (b as TextureRect).texture.resource_path), "correct Catch/shared or supplied Human Plane texture " + path)
		if a is Label:
			_check(b.get_theme_font_size("font_size") >= 14 and b.get_theme_font_size("font_size") <= 50,
				"independent Human Plane " + path + " remains legible without forcing Catch font size")
	for path in REMOVED:
		_check(target.get_node_or_null(path) == null, "old Human Plane HUD node removed: " + path)
	_check((target.get_node("PlaneRig/PlaneArtwork") as TextureRect).texture.resource_path.ends_with("/PLANE.png"), "one original airplane remains")
	_check(target.get_node("MovingGates/GateCenter/GateArtwork") is TextureRect, "playable answer gates preserved")
	_check(target.get_node("FlightPaths/GateEndCenter") is Control, "calibration-dependent hitbox guide preserved")
	source.free()
	target.free()
	for dims in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		for mode in ["Seconds", "Lives"]:
			await _check_live(dims, mode)
	print("HUMAN PLANE CATCH HUD CLONE: ", "PASS" if failures.is_empty() else "FAIL", " (%d checks, %d failures)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check_live(dims: Vector2i, mode: String) -> void:
	# Match the graphical QA window viewport, not Godot's fixed design stretch.
	root.content_scale_size = dims
	root.size = dims
	var game := PLANE.instantiate() as Control
	game.set_context({"activity": "Human Plane", "topic": "Noun", "difficulty": "Normal", "game_mode": mode})
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	game.set_process(false)
	var label := "%s/%s" % [str(dims), mode]
	var hud := game.get_node("HUDLayer/HUD") as Control
	_check(is_equal_approx(hud.scale.x, minf(float(dims.x) / 1280.0, float(dims.y) / 720.0)), label + " HUD scales as one unit, preserving individual authored positions (actual=%s viewport=%s game=%s)" % [hud.scale.x, game.get_viewport_rect().size, game.size])
	for path in NODES:
		var item := hud.get_node_or_null(path) as Control
		_check(item != null and authored_rects.has(path) and
			item.get_rect().is_equal_approx(authored_rects.get(path, Rect2())),
			label + " runtime scaling and game mode preserve authored " + path + " geometry")
		_check(item != null and authored_anchors.has(path) and
			[item.anchor_left, item.anchor_top, item.anchor_right, item.anchor_bottom] == authored_anchors.get(path, []),
			label + " runtime mode and resolution preserve independent " + path + " anchors")
	var title_panel := hud.get_node_or_null("HumanPlaneTitlePanel") as Panel
	var title_text := hud.get_node_or_null("HumanPlaneTitlePanel/HumanPlaneTitle") as Label
	_check(title_panel == null and title_text == null
		and (hud.get_node("TitlePlaque") as TextureRect).visible
		and (hud.get_node("TitlePlaque") as TextureRect).texture.resource_path.ends_with("/human_plane.png"),
		label + " supplied Human Plane title remains visible without duplicate nodes")
	var score := game.get_node("HUDLayer/HUD/ScoreBottomContainer/ScoreNumber") as Label
	var prompt := game.get_node("HUDLayer/HUD/PromptLabel") as Label
	var timer_art := game.get_node("HUDLayer/HUD/TimerPlaque") as TextureRect
	var timer := game.get_node("HUDLayer/HUD/TimeLabel") as Label
	var lives := game.get_node("HUDLayer/HUD/LivesPlaque") as TextureRect
	var pause := game.get_node("HUDLayer/HUD/PauseButton") as Button
	_check(score.text == "0", label + " dynamic source ScoreNumber initialized")
	_check(prompt.text == "WHICH WORD IS A NOUN?", label + " source-style grammar question")
	_check(int(game.get("lives")) == 3, label + " three chances preserved")
	_check(timer_art.visible == (mode == "Seconds") and timer.visible == (mode == "Seconds"), label + " Catch timer is shown only in Seconds mode")
	_check(lives.visible == (mode == "Lives"), label + " three-heart source plaque shown only in Lives")
	if mode == "Seconds":
		_check(timer.text == "60s", label + " 60-second timer inside source plaque")
	else:
		_check(lives.texture.resource_path.ends_with("lives_state_3.png"), label + " three bright hearts on source plaque")
	game.set("score", 275)
	game.set("topic", "Adjective")
	game.call("_sync_visuals")
	_check(score.text == "275", label + " score updates in source ScoreNumber")
	_check(prompt.text == "WHICH WORD IS AN ADJECTIVE?", label + " question follows grammar topic")
	game.set("lives", 2)
	game.call("_sync_visuals")
	_check(lives.texture.resource_path.ends_with("lives_state_2.png"), label + " life loss updates source LivesPlaque")
	game.set("lives", 0)
	game.call("_sync_visuals")
	_check(lives.texture.resource_path.ends_with("lives_badge.png"), label + " zero hearts never shows false filled heart")
	var requested_pause := [false]
	game.requested.connect(func(action: String, _payload: Dictionary) -> void:
		if action == "pause":
			requested_pause[0] = true
	)
	pause.pressed.emit()
	_check(requested_pause[0] and bool(game.get("paused")), label + " cloned PauseButton is wired to Human Plane pause")
	game.queue_free()
	await process_frame
	await process_frame


func _valid_design_rect(rect: Rect2) -> bool:
	return is_finite(rect.position.x) and is_finite(rect.position.y) \
		and is_finite(rect.size.x) and is_finite(rect.size.y) \
		and rect.size.x > 10.0 and rect.size.y > 10.0 \
		and rect.position.x >= -10.0 and rect.position.y >= -10.0 \
		and rect.end.x <= 1290.0 and rect.end.y <= 730.0


func _valid_design_anchors(anchors: Array) -> bool:
	if anchors.size() != 4:
		return false
	for value in anchors:
		if not is_finite(float(value)) or float(value) < -0.01 or float(value) > 1.01:
			return false
	return float(anchors[0]) <= float(anchors[2]) \
		and float(anchors[1]) <= float(anchors[3])


func _check(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		failures.append(reason)
		printerr("HUMAN HUD CLONE FAIL: ", reason)
