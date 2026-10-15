extends SceneTree

# Static editor (.tscn) and runtime regression after removing the objective UI.
# Godot 4.7.2 --headless --path . --script res://tools/test_catch_objective_editor_static.gd
const SCENE := "res://ui/minigames/catch_word.tscn"
const REMOVED := ["ObjectivePlaque", "FeedbackLabel", "TopicIcon"]
const WINDOWS := [Vector2i(1280, 720), Vector2i(875, 500)]
const TOPICS := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
const MODES := ["Seconds", "Lives"]

var checks := 0
var scenarios := 0
var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var old_size := root.size
	var packed := load(SCENE) as PackedScene
	_check(packed != null, "authored Catch .tscn loads")
	var scene_text := FileAccess.get_file_as_string(SCENE)
	_check(not scene_text.is_empty(), "authored .tscn source is readable")
	for absent_name in REMOVED:
		_check(not scene_text.contains('name="' + absent_name + '"'),
			"saved editor file has no " + absent_name + " node definition")
	_check(not scene_text.contains("AudioStream"),
		"saved editor file contains no audio player or stream resource")

	if packed != null:
		for physical in WINDOWS:
			await _check_window(packed, physical)
	root.size = old_size
	if errors.is_empty():
		print("PASS Catch editor/no objective: %d checks, %d topic/mode/editor-window scenarios" % [checks, scenarios])
		quit(0)
	else:
		for error in errors:
			push_error("CATCH EDITOR STATIC: " + error)
		print("FAIL Catch editor/no objective: %d failures in %d checks over %d scenarios" % [errors.size(), checks, scenarios])
		quit(1)


func _check_window(packed: PackedScene, physical: Vector2i) -> void:
	root.size = physical
	await process_frame
	await process_frame
	var old_children := root.get_child_count()

	# Disable the root gameplay script to inspect the actual saved editor controls.
	var raw := packed.instantiate() as Control
	_check(raw != null, "%s: serialized scene instantiated" % physical)
	if raw != null:
		raw.set_script(null)
		root.add_child(raw)
		raw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		_assert_hud_without_objective(raw, "%s saved editor" % physical)
		_check(_count_sound_players(raw) == 0, "%s: saved editor contains no authored sound player" % physical)
		var static_prompt := raw.get_node_or_null("HUDLayer/HUD/PromptLabel") as Label
		_check(static_prompt != null and static_prompt.text.contains("NOUN"),
			"%s: authored wooden grammar question is retained" % physical)
		root.remove_child(raw)
		raw.free()

	var live := packed.instantiate() as Control
	_check(live != null and live.get_script() != null,
		"%s: gameplay scene/script instantiates" % physical)
	if live == null or live.get_script() == null:
		if live != null:
			live.free()
		_check(root.get_child_count() == old_children, "%s: failed load leaves no children" % physical)
		return
	root.add_child(live)
	live.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	live.set_process(false)
	_check(_count_sound_players(live) == 1 and live.get_node_or_null("CatchVoicePlayer") is AudioStreamPlayer,
		"%s: runtime game creates exactly one recorded feedback player" % physical)
	for mode in MODES:
		for topic in TOPICS:
			live.call("set_context", {
				"activity": "Catch the Word",
				"topic": topic,
				"game_mode": mode,
				"difficulty": "Normal",
				"catch_character": "Boy",
				"catch_map": "City",
				"score": 18,
				"lives": 2,
			})
			live.set_process(false)
			await process_frame
			scenarios += 1
			var ctx := "%s %s %s" % [physical, mode, topic]
			_assert_hud_without_objective(live, ctx)
			var prompt := live.get_node_or_null("HUDLayer/HUD/PromptLabel") as Label
			var score := live.get_node_or_null("HUDLayer/HUD/ScoreBottomContainer/ScoreNumber") as Label
			_check(prompt != null and prompt.is_visible_in_tree()
				and prompt.text.contains(topic.to_upper()),
				ctx + ": live grammar question remains visible")
			_check(score != null and score.is_visible_in_tree() and score.text == "18",
				ctx + ": numeric score remains visible and editable")
			_check(_count_sound_players(live) == 1 and live.get_node_or_null("CatchVoicePlayer") is AudioStreamPlayer,
				ctx + ": context preserves exactly one reusable recorded voice player")
	root.remove_child(live)
	live.free()
	await process_frame
	_check(root.get_child_count() == old_children,
		"%s: editor and runtime test leave no leaked root children" % physical)


func _assert_hud_without_objective(game: Node, ctx: String) -> void:
	var hud := game.get_node_or_null("HUDLayer/HUD") as Control
	_check(hud != null, ctx + ": expected HUD remains")
	if hud == null:
		return
	for name in REMOVED:
		_check(not hud.has_node(name), ctx + ": removed " + name + " absent")
	_check(hud.has_node("TitlePlaque") and hud.has_node("PromptLabel")
		and hud.has_node("ScorePlaque") and hud.has_node("LivesPlaque")
		and hud.has_node("TimerPlaque"), ctx + ": original HUD artwork remains")


func _count_sound_players(node: Node) -> int:
	var count := 1 if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D else 0
	for child in node.get_children():
		count += _count_sound_players(child)
	return count


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		errors.append(description)
