extends SceneTree

# Dedicated regression for the current hand-edited Human Plane scene.
# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_visual_cleanup.gd
const SCENE := preload("res://ui/minigames/human_plane.tscn")
const CATCH := preload("res://ui/minigames/catch_word.tscn")
const LIVES_STATE_3 := preload("res://ui/minigames/catch_hud/generated/replacement/lives_state_3.png")
const LIVES_STATE_2 := preload("res://ui/minigames/catch_hud/generated/replacement/lives_state_2.png")
const ORIGINAL_SHA256 := {
	"BACKGROUND.png": "719c02bc595678295c3f8a48b61b1748dc65bbd6b600fc3fe278299fb630dee0",
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
	"PlaneRig/PlaneArtwork", "SceneBackground/SkyBackdrop"
]
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for file in ORIGINAL_SHA256:
		_check(FileAccess.get_sha256("res://Components/HumanPlaneAssets/" + file) == ORIGINAL_SHA256[file], file + " exact original checksum")
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
	# The user's artwork, offsets, hidden previews, and deleted AnswerLine are
	# authoritative; do not recreate them or generate new UI during _ready().
	var original_layout := {}
	var catch := CATCH.instantiate() as Control
	_check(catch != null and catch.get_node_or_null("HUDLayer/HUD") != null, label + " Catch HUD source is available")
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
					_check(_layout(item) == _layout(source), label + " source Catch pixel-perfect original position " + path)
					if item is TextureRect and source is TextureRect:
						_check((item as TextureRect).texture.resource_path == (source as TextureRect).texture.resource_path,
							label + " exact Catch source art " + path)
	catch.free()
	for path in ["PlaneRig/PlaneBody", "PlaneRig/PlaneWings", "PlaneRig/PlaneTail", "PlaneRig/Cockpit", "SceneBackground/Cloud1", "SceneBackground/Cloud2", "SceneBackground/Cloud3", "SceneBackground/Cloud4", "SceneBackground/Sun", "SceneBackground/FarHills", "SceneBackground/GreenGround", "SceneBackground/PerspectiveArtwork", "SceneBackground/PerspectiveArtwork/Runway", "AnswerLine", "HUD/StatsBar/WaveLabel",
		"HUD/ScoreArtwork", "HUD/LivesArtwork", "HUD/TimerArtwork", "HUD/TitleArtwork",
		"HUD/StatsBar", "HUD/ObjectivePanel", "HUD/LivesHearts", "HUD/ModeLabel",
		"HUD/FeedbackPanel", "HUD/InstructionLabel", "HUD/DifficultyLabel",
		"PauseButton", "HUDLayer/HUD/WaveLabel"]:
		_check(scene.get_node_or_null(path) == null, label + " obsolete element deleted: " + path)
	_check(scene.get_node("SceneBackground/SkyBackdrop") is TextureRect, label + " original backdrop remains")
	var plane_rig := scene.get_node("PlaneRig") as Control
	var plane := scene.get_node("PlaneRig/PlaneArtwork") as TextureRect
	_check(plane_rig.get_node_or_null("Hitbox") != null, label + " real airplane hitbox preserved")
	_check(plane.texture.resource_path.ends_with("HumanPlaneAssets/PLANE.png"), label + " exactly one supplied airplane image")
	var title := scene.get_node("HUDLayer/HUD/TitlePlaque") as TextureRect
	_check(title.texture.resource_path.ends_with("catch_hud/generated/title_board.png"),
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
