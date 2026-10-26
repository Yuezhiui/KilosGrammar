extends SceneTree

# Dedicated regression for the current hand-edited Human Plane scene.
# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_visual_cleanup.gd
const SCENE := preload("res://ui/minigames/human_plane.tscn")
const CATCH := preload("res://ui/minigames/catch_word.tscn")
const LIVES_STATE_3 := preload("res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_3.png")
const LIVES_STATE_2 := preload("res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_2.png")
const ORIGINAL_SHA256 := {
	"PLANE.png": "81826ebd6e13131793ff6bf8dafe4f03499b94661a1953ec24b2351189944b0e",
	"human_plane_gate_purple_LEFT.png": "3e476898a6d996484bd6e8ff99297a35554a2d45848ceeea8aa21efc34c4f146",
	"human_plane_gate_green_CENTER.png": "37cbd228e8c844f55e0c119a55be399f1ef2682acda9850de549bc03dc430e42",
	"human_plane_gate_blue_RIGHT.png": "011b8452faaad74ab05ede0eff510e3bf70e53662f45294b5d8fda882c706ed8"
}
const HUD_PARTS := [
	"HUDLayer/HUD/TitlePlaque", "HUDLayer/HUD/PromptLabel",
	"HUDLayer/HUD/TimerPlaque", "HUDLayer/HUD/TimeLabel",
	"HUDLayer/HUD/LivesPlaque", "HUDLayer/HUD/PausePlaque",
	"HUDLayer/HUD/PauseButton", "HUDLayer/HUD/ScorePlaque",
	"HUDLayer/HUD/ScoreBottomContainer", "HUDLayer/HUD/ScoreBottomContainer/ScoreNumber",
	"PlaneRig/PlaneArtwork"
]
const HUD_AUTHORED_PLACEMENT := [
	"HUDLayer/HUD/TitlePlaque",
	"HUDLayer/HUD/PromptLabel",
	"HUDLayer/HUD/TimeLabel"
]
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for file in ORIGINAL_SHA256:
		_check(FileAccess.get_sha256("res://Components/Gameplay/Human Plane/" + file) == ORIGINAL_SHA256[file], file + " exact original checksum")
	for dims in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		for mode in ["Seconds", "Lives"]:
			await _verify(dims, mode)
	print("HUMAN PLANE VISUAL CLEANUP: ", "PASS" if failures.is_empty() else "FAIL", " (%d checks, %d failures)" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _verify(dims: Vector2i, mode: String) -> void:
	root.size = dims
	var scene := SCENE.instantiate() as Control
	if scene == null or not scene.has_method("set_context"):
		_check(false, "Human Plane scene/script instantiates")
		return
	var label := "%dx%d/%s" % [dims.x, dims.y, mode]
	# The native full-3D view and the invisible, editor-authored AnswerLine
	# are authoritative. Game-specific HUD offsets need not duplicate Catch.
	var original_layout := {}
	var catch := CATCH.instantiate() as Control
	_check(catch != null and catch.get_node_or_null("HUDLayer/HUD") != null, label + " Catch HUD source is available")
	var world_3d := scene.get_node_or_null("WorldView3D") as SubViewportContainer
	_check(world_3d != null and world_3d.get_node_or_null("Viewport3D/FlightWorld/Camera3D") is Camera3D,
		label + " only native full-3D flight world and its camera remain")
	_check(scene.get_node_or_null("WorldView25D") == null,
		label + " retired 2.5D experiment is absent")
	for path in HUD_PARTS:
		var item := scene.get_node_or_null(path) as Control
		_check(item != null and item.owner == scene, label + " authored node " + path)
		if item != null:
			original_layout[path] = {"offsets": [item.offset_left, item.offset_top, item.offset_right, item.offset_bottom],
				"anchors": [item.anchor_left, item.anchor_top, item.anchor_right, item.anchor_bottom], "id": item.get_instance_id()}
			if path.begins_with("HUDLayer/HUD/"):
				var source := catch.get_node_or_null(path) as Control
				_check(source != null, label + " source Catch HUD control " + path)
				if source != null:
					if path in HUD_AUTHORED_PLACEMENT:
						_check(_game_specific_hud_alignment(item, source, scene, path),
							label + " editor-authored HUD placement stays aligned to gameplay panel " + path)
					else:
						_check(_layout(item) == _layout(source),
							label + " shared Catch HUD pixel-perfect original position " + path)
					if item is TextureRect and source is TextureRect:
						_check((item as TextureRect).texture.resource_path == (source as TextureRect).texture.resource_path,
							label + " exact Catch source art " + path)
	catch.free()
	for path in ["PlaneRig/PlaneBody", "PlaneRig/PlaneWings", "PlaneRig/PlaneTail", "PlaneRig/Cockpit", "SceneBackground/Cloud1", "SceneBackground/Cloud2", "SceneBackground/Cloud3", "SceneBackground/Cloud4", "SceneBackground/Sun", "SceneBackground/FarHills", "SceneBackground/GreenGround", "SceneBackground/PerspectiveArtwork", "SceneBackground/PerspectiveArtwork/Runway", "HUD/StatsBar/WaveLabel",
		"HUD/ScoreArtwork", "HUD/LivesArtwork", "HUD/TimerArtwork", "HUD/TitleArtwork",
		"HUD/StatsBar", "HUD/ObjectivePanel", "HUD/LivesHearts", "HUD/ModeLabel",
		"HUD/FeedbackPanel", "HUD/InstructionLabel", "HUD/DifficultyLabel",
		"PauseButton", "HUDLayer/HUD/WaveLabel"]:
		_check(scene.get_node_or_null(path) == null, label + " obsolete element deleted: " + path)
	var answer_line := scene.get_node_or_null("AnswerLine") as Control
	_check(answer_line != null and answer_line.owner == scene
		and answer_line.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		label + " invisible editor-authored AnswerLine collision guide remains, noninteractive")
	_check(answer_line != null and answer_line.size.x > 0.0
		and answer_line.size.y > 0.0
		and answer_line.anchor_top >= 0.6 and answer_line.anchor_top <= 0.8,
		label + " answer crossing guide has a valid mid-lower scoring region")
	var plane_rig := scene.get_node("PlaneRig") as Control
	var plane := scene.get_node("PlaneRig/PlaneArtwork") as TextureRect
	_check(plane_rig.get_node_or_null("Hitbox") != null, label + " real airplane hitbox preserved")
	_check(plane.texture.resource_path == "res://Components/Gameplay/Human Plane/PLANE.png",
		label + " hidden collision-guide plane retains the supplied authored texture")
	var title := scene.get_node("HUDLayer/HUD/TitlePlaque") as TextureRect
	_check(title.texture.resource_path == "res://Components/Gameplay/Catch the Word/HUD/generated/title_board.png",
		label + " native Catch Word full title plaque replaces old objective banner")
	_check((scene.get_node("MovingGates") as Control).visible, label + " three answer gates visibly render")
	_check(scene.get_node("HUDLayer/HUD/ScoreBottomContainer/ScoreNumber") is Label,
		label + " original scene-authored Catch ScoreNumber")
	_check(scene.get_node("HUDLayer/HUD/LivesPlaque").texture == LIVES_STATE_3,
		label + " original native 3-heart LivesPlaque, not overlay hearts")
	_check(scene.get_node_or_null("HUDLayer/HUD/LivesHearts") == null and
		scene.get_node_or_null("HUD/LivesHearts") == null,
		label + " deleted custom hearts overlay never double-renders")

	scene.set_context({"activity": "Human Plane", "topic": "Noun", "difficulty": "Normal", "game_mode": mode})
	root.add_child(scene)
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	scene.set_process(false)
	var hud := scene.get_node("HUDLayer/HUD") as Control
	var score := scene.get_node("HUDLayer/HUD/ScoreBottomContainer/ScoreNumber") as Label
	var timer := scene.get_node("HUDLayer/HUD/TimeLabel") as Label
	var timer_plaque := scene.get_node("HUDLayer/HUD/TimerPlaque") as TextureRect
	var lives_plaque := scene.get_node("HUDLayer/HUD/LivesPlaque") as TextureRect
	_check(hud.is_visible_in_tree(), label + " original Catch HUD displayed")
	_check(score.is_visible_in_tree() and score.text == "0", label + " original Catch unpadded score numeral visible")
	_check(timer.text == "60s" if mode == "Seconds" else not timer.visible,
		label + " original Catch TimeLabel changes for Seconds/Lives")
	_check(timer_plaque.is_visible_in_tree() if mode == "Seconds" else not timer_plaque.visible,
		label + " native Catch TimerPlaque shown only in Seconds")
	_check(not lives_plaque.visible if mode == "Seconds" else lives_plaque.is_visible_in_tree(),
		label + " native Catch three-heart LivesPlaque shown only in Lives")
	_check(lives_plaque.texture == LIVES_STATE_3, label + " all 3 lives displayed at round start")
	_check((scene.get_node("HUDLayer/HUD/PromptLabel") as Label).text == "WHICH WORD IS A NOUN?",
		label + " Catch grammar objective prompt updates")
	_check(int(scene.get("lives")) == 3 and scene.get_node_or_null("HUDLayer/HUD/WaveLabel") == null,
		label + " three lives and no WAVE")
	_check(int(scene.get("score")) == 0, label + " original score unchanged")
	var starting_gate := scene.call("_gate_rect", 1, 0.6) as Rect2
	scene.set("plane_x_norm", -0.2)
	scene.call("_resolve_at_answer_line")
	_check(int(scene.get("lives")) == 2, label + " missed gate subtracts a single heart")
	_check(lives_plaque.texture == LIVES_STATE_2, label + " 2-heart Catch state after miss")
	_check(score.text == str(scene.get("score")), label + " text follows score without zero-padding")
	_check((scene.call("_gate_rect", 1, 0.6) as Rect2).is_equal_approx(starting_gate),
		label + " gate path unaffected by Catch HUD update")
	for path in HUD_PARTS:
		var item := scene.get_node(path) as Control
		var before: Dictionary = original_layout[path]
		_check(item.get_instance_id() == before["id"], label + " no generated ghost: " + path)
		_check([item.anchor_left, item.anchor_top, item.anchor_right, item.anchor_bottom] == before["anchors"], label + " preserved authored anchors: " + path)
		# Control layout can convert offsets via full-rect anchors when resizing,
		# so test that value-updating _sync_visuals never overwrites offsets.
		var live_offsets := [item.offset_left, item.offset_top, item.offset_right, item.offset_bottom]
		scene.call("_sync_visuals")
		_check([item.offset_left, item.offset_top, item.offset_right, item.offset_bottom] == live_offsets, label + " runtime does not reposition: " + path)
	# The Pause button is a native focusable editor control, not a decorative
	# sprite. Its pressed signal must stop the FULL-3D round and preserve the
	# result-navigation contract without touching camera/DB services.
	var pause_button := scene.get_node("HUDLayer/HUD/PauseButton") as Button
	var pause_events: Array[Dictionary] = []
	scene.requested.connect(func(target: String, payload: Dictionary) -> void:
		pause_events.append({"target": target, "payload": payload.duplicate(true)}))
	_check(pause_button.focus_mode == Control.FOCUS_ALL and not pause_button.disabled
		and pause_button.is_visible_in_tree(),
		label + " native HUD Pause button remains keyboard-focusable and visible")
	pause_button.pressed.emit()
	_check(bool(scene.get("paused")) and not bool(scene.get("running")),
		label + " native HUD Pause button freezes the actual game")
	_check(pause_events.size() == 1 and pause_events[0].get("target", "") == "pause"
		and (pause_events[0].get("payload", {}) as Dictionary).get("round_completed", true) == false,
		label + " Pause emits original navigation signal with safe incomplete round payload")
	pause_button.pressed.emit()
	_check(pause_events.size() == 1, label + " duplicate Pause cannot emit a second route")
	scene.call("_resume")
	_check(not bool(scene.get("paused")) and bool(scene.get("running")),
		label + " resume restores gameplay after paused 3D scene")
	scene.queue_free()
	await process_frame
	await process_frame


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("FAIL HumanPlane cleanup: ", message)


func _layout(control: Control) -> Array:
	return [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom,
		control.offset_left, control.offset_top, control.offset_right, control.offset_bottom,
		control.custom_minimum_size]


func _game_specific_hud_alignment(item: Control, source: Control, game: Control, path: String) -> bool:
	# Human Plane's title and prompt were authored *together* as a pair
	# compared with Catch Word: they intentionally sit 19px lower. Keep both
	# the source panel dimensions and their relative prompt positioning.
	if path in ["HUDLayer/HUD/TitlePlaque", "HUDLayer/HUD/PromptLabel"]:
		var identical_horizontal := is_equal_approx(item.offset_left, source.offset_left) \
			and is_equal_approx(item.offset_right, source.offset_right)
		var authored_vertical := is_equal_approx(item.offset_top, source.offset_top + 19.0) \
			and is_equal_approx(item.offset_bottom, source.offset_bottom + 19.0)
		var title := game.get_node("HUDLayer/HUD/TitlePlaque") as Control
		if path.ends_with("PromptLabel"):
			var inside_title := item.offset_left >= title.offset_left \
				and item.offset_right <= title.offset_right \
				and item.offset_top >= title.offset_top \
				and item.offset_bottom <= title.offset_bottom
			return identical_horizontal and authored_vertical and inside_title
		return identical_horizontal and authored_vertical
	if path.ends_with("TimeLabel"):
		var timer := game.get_node("HUDLayer/HUD/TimerPlaque") as Control
		var source_label := source as Label
		var game_label := item as Label
		return game_label != null and source_label != null \
			and game_label.horizontal_alignment == source_label.horizontal_alignment \
			and game_label.vertical_alignment == source_label.vertical_alignment \
			and game_label.get_theme_font_size("font_size") == source_label.get_theme_font_size("font_size") \
			and item.offset_left >= timer.offset_left and item.offset_right <= timer.offset_right \
			and item.offset_top >= timer.offset_top and item.offset_bottom <= timer.offset_bottom \
			and absf((item.offset_top + item.offset_bottom) * 0.5 - (timer.offset_top + timer.offset_bottom) * 0.5) < 3.0
	return false
