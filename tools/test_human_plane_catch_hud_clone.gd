extends SceneTree

# Exact editor-authored Catch HUD clone regression; no live camera or database.
# Godot --headless --path . --script res://tools/test_human_plane_catch_hud_clone.gd
const CATCH := preload("res://ui/minigames/catch_word.tscn")
const PLANE := preload("res://ui/minigames/human_plane.tscn")
const NODES := [
	"TitlePlaque", "PromptLabel", "TimerPlaque", "TimeLabel",
	"PauseButton", "PausePlaque", "ScorePlaque", "ScoreBottomContainer",
	"ScoreBottomContainer/ScoreNumber", "LivesPlaque"
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
	_check(target_hud.owner == target, "complete HUD copied as scene-authored nodes")
	_check((target.get_node("HUDLayer") as CanvasLayer).layer == (source.get_node("HUDLayer") as CanvasLayer).layer, "CanvasLayer 20 matches Catch and stays above moving gates")
	for path in NODES:
		var a := source_hud.get_node(path) as Control
		var b := target_hud.get_node_or_null(path) as Control
		_check(b != null and b.owner == target, "copied editor node: " + path)
		if b == null:
			continue
		_check(a.get_class() == b.get_class(), "same source node type " + path)
		_check(a.get_rect().is_equal_approx(b.get_rect()), "exact Catch position and size " + path)
		_check([a.anchor_left, a.anchor_top, a.anchor_right, a.anchor_bottom] == [b.anchor_left, b.anchor_top, b.anchor_right, b.anchor_bottom], "exact Catch anchors " + path)
		if a is TextureRect:
			_check((a as TextureRect).texture.resource_path == (b as TextureRect).texture.resource_path, "exact Catch texture " + path)
		if a is Label:
			_check(a.get_theme_font_size("font_size") == b.get_theme_font_size("font_size"), "exact Catch font size " + path)
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


func _check(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		failures.append(reason)
		printerr("HUMAN HUD CLONE FAIL: ", reason)
