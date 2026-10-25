extends SceneTree

# Live renderer screenshots and visibility assertions for the clean Catch HUD.
# Run with a graphical Godot 4.7 build (do not use --headless):
# godot --path . --rendering-method gl_compatibility --script res://tools/capture_catch_clean_hud.gd
#
# Each map/mode combination is captured at both target resolutions. The test
# checks both authored and runtime state without hiding any nodes in the test.
# On older builds that expose feedback_text, a long feedback message is tested.

const SCENE := "res://ui/minigames/catch_word.tscn"
const OUTPUT_DIR := "res://showcase/catch_word_hud/clean_objective"
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(875, 500)]
const LOGICAL_HUD_SIZE := Vector2(1280, 720)
const CASES := [
	{"map": "City", "mode": "Seconds", "topic": "Noun", "character": "Boy"},
	{"map": "City", "mode": "Lives", "topic": "Pronoun", "character": "Girl"},
	{"map": "Forest", "mode": "Seconds", "topic": "Verb", "character": "Grandma"},
	{"map": "Forest", "mode": "Lives", "topic": "Adjective", "character": "Grandpa"},
	{"map": "Mountain", "mode": "Seconds", "topic": "Adverb", "character": "Girl"},
	{"map": "Mountain", "mode": "Lives", "topic": "Noun", "character": "Boy"}
]
const FORBIDDEN_PATHS := [
	"HUDLayer/HUD/ObjectivePlaque",
	"HUDLayer/HUD/FeedbackLabel",
	"HUDLayer/HUD/TopicIcon"
]
const REQUIRED_HUD_PATHS := [
	"HUDLayer/HUD/TitlePlaque",
	"HUDLayer/HUD/PausePlaque",
	"HUDLayer/HUD/ScorePlaque"
]
const LONG_FEEDBACK := "EXCELLENT! YOU CAUGHT THE CORRECT ADJECTIVE WORD AND EARNED BONUS POINTS!"

var failures: Array[String] = []
var screenshots := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		push_error("CLEAN HUD: Cannot load Catch scene")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var authored := packed.instantiate() as Control
	if authored == null:
		push_error("CLEAN HUD: Cannot instantiate Catch scene")
		quit(1)
		return
	_assert_no_objective(authored, "authored .tscn")
	authored.free()

	for viewport_size in RESOLUTIONS:
		root.size = viewport_size
		DisplayServer.window_set_size(viewport_size)
		await process_frame
		await process_frame
		for entry in CASES:
			await _capture_case(packed, viewport_size, entry)

	print("CLEAN HUD: captured %d/%d screenshots; %d assertion failures" %
		[screenshots, RESOLUTIONS.size() * CASES.size(), failures.size()])
	if failures.is_empty():
		print("PASS Catch clean HUD: no objective/feedback visuals in any captured map/mode")
		quit(0)
	else:
		for issue in failures:
			push_error("CLEAN HUD FAIL: " + issue)
		quit(1)


func _capture_case(packed: PackedScene, viewport_size: Vector2i, entry: Dictionary) -> void:
	var label := "%s/%s/%s/%s %dx%d" % [
		entry["map"], entry["mode"], entry["topic"], entry["character"],
		viewport_size.x, viewport_size.y
	]
	var game := packed.instantiate() as Control
	if game == null:
		_fail(label + ": scene instantiate failed")
		return
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.call("set_context", {
		"activity": "Catch the Word",
		"topic": entry["topic"],
		"game_mode": entry["mode"],
		"difficulty": "Normal",
		"catch_character": entry["character"],
		"catch_map": entry["map"]
	})
	# Freeze movement while preserving the actual constructed gameplay HUD.
	game.set_process(false)
	await process_frame
	await process_frame
	_assert_no_objective(game, label + " initial")
	_assert_retained_hud(game, viewport_size, entry, label)
	_assert_no_active_audio(game, label)

	# The clean implementation removes feedback_text entirely; if an older
	# implementation still exposes it, exercise that path too.
	if _has_property(game, "feedback_text"):
		game.set("feedback_text", LONG_FEEDBACK)
	if game.has_method("_refresh_hud"):
		game.call("_refresh_hud")
	await process_frame
	await process_frame
	_assert_no_objective(game, label + " long feedback")
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	if picture.get_size() != viewport_size:
		_fail(label + ": output image resolution %s instead of %s" % [picture.get_size(), viewport_size])
	var filename := "%s_%s_%s_%s_%dx%d.png" % [
		String(entry["character"]).to_lower(),
		String(entry["map"]).to_lower(),
		String(entry["topic"]).to_lower(),
		String(entry["mode"]).to_lower(),
		viewport_size.x, viewport_size.y
	]
	var out_path := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(filename))
	var result := picture.save_png(out_path)
	if result == OK:
		screenshots += 1
		print("CAPTURED ", out_path)
	else:
		_fail(label + ": save_png returned %d" % result)
	root.remove_child(game)
	game.queue_free()
	await process_frame


func _assert_no_objective(game: Control, label: String) -> void:
	for node_path in FORBIDDEN_PATHS:
		var element := game.get_node_or_null(node_path) as CanvasItem
		if element != null and element.visible:
			_fail(label + ": unexpected visible " + node_path)
		if element != null and element.is_inside_tree() and element.is_visible_in_tree():
			_fail(label + ": unexpected painted " + node_path)


func _assert_retained_hud(game: Control, viewport_size: Vector2i, entry: Dictionary, label: String) -> void:
	for node_path in REQUIRED_HUD_PATHS:
		var item := game.get_node_or_null(node_path) as Control
		if item == null or not item.is_visible_in_tree():
			_fail(label + ": retained HUD missing/hidden: " + node_path)
			continue
		# CanvasLayer renders via its own canvas transform. get_global_rect()
		# alone does not include its scaling at the smaller screenshot viewport.
		var to_viewport := item.get_global_transform_with_canvas()
		var bounds := Rect2(to_viewport * Vector2.ZERO, to_viewport * item.size - to_viewport * Vector2.ZERO)
		# Project stretch keeps the internal drawing region at 1280x720
		# while Windows scales the final image to the requested window size.
		# The score board art has ~4px transparent bleed below logical y=720.
		if bounds.position.x < -8.0 or bounds.position.y < -8.0 or bounds.end.x > LOGICAL_HUD_SIZE.x + 8.0 or bounds.end.y > LOGICAL_HUD_SIZE.y + 8.0:
			_fail(label + ": HUD boundary outside logical canvas: " + node_path + " " + str(bounds))
	var mode_path := "HUDLayer/HUD/TimerPlaque" if entry["mode"] == "Seconds" else "HUDLayer/HUD/LivesPlaque"
	var mode_plaque := game.get_node_or_null(mode_path) as CanvasItem
	if mode_plaque == null or not mode_plaque.is_visible_in_tree():
		_fail(label + ": selected mode badge is missing/hidden " + mode_path)
	var background := game.get_node_or_null("Background") as TextureRect
	var body := game.get_node_or_null("CharacterRig/Body") as Sprite2D
	var basket := game.get_node_or_null("CharacterRig/Basket") as Sprite2D
	var expected_map := "res://Components/Gameplay/Catch the Word/Maps/%sMap.png" % entry["map"]
	var expected_body := "res://Components/Gameplay/Catch the Word/Characters/%s BODY.png" % String(entry["character"]).to_upper()
	var expected_basket := "res://Components/Gameplay/Catch the Word/Characters/%s BASKET.png" % String(entry["character"]).to_upper()
	if background == null or background.texture == null or background.texture.resource_path != expected_map:
		_fail(label + ": wrong/missing original map " + expected_map)
	if body == null or body.texture == null or body.texture.resource_path != expected_body:
		_fail(label + ": wrong/missing original body " + expected_body)
	if basket == null or basket.texture == null or basket.texture.resource_path != expected_basket:
		_fail(label + ": wrong/missing original basket " + expected_basket)


func _assert_no_active_audio(root_node: Node, label: String) -> void:
	var active_players: Array[String] = []
	_collect_playing_audio(root_node, active_players)
	if not active_players.is_empty():
		_fail(label + ": audio player(s) currently playing: " + ", ".join(active_players))


func _has_property(node: Object, property_name: String) -> bool:
	for property in node.get_property_list():
		if String(property["name"]) == property_name:
			return true
	return false


func _collect_playing_audio(node: Node, active_players: Array[String]) -> void:
	if node is AudioStreamPlayer and (node as AudioStreamPlayer).playing:
		active_players.append(str(node.get_path()))
	if node is AudioStreamPlayer2D and (node as AudioStreamPlayer2D).playing:
		active_players.append(str(node.get_path()))
	if node is AudioStreamPlayer3D and (node as AudioStreamPlayer3D).playing:
		active_players.append(str(node.get_path()))
	for child in node.get_children():
		_collect_playing_audio(child, active_players)


func _fail(message: String) -> void:
	failures.append(message)
	print("FAIL ", message)
