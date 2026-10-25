extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_human_plane_three_heart_hud.gd
# Verify the HUMAN PLANE HUD is a genuine scene-authored clone of Catch the
# Word, with original editable coordinates and precisely three life states.
const SCENE := preload("res://ui/minigames/human_plane.tscn")
const CATCH_SCENE := preload("res://ui/minigames/catch_word.tscn")
const LIVES_STATE_3 := preload("res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_3.png")
const LIVES_STATE_2 := preload("res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_2.png")
const LIVES_STATE_1 := preload("res://Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_1.png")
const LIVES_STATE_EMPTY := preload("res://Components/Gameplay/Catch the Word/HUD/generated/lives_badge.png")
const SCREENS := [Vector2i(1280, 720), Vector2i(1920, 1080)]
const MODES := ["Seconds", "Lives"]
const DIFFICULTIES := ["Easy", "Normal", "Hard"]
const HUD_PARTS := [
    "HUDLayer/HUD/TitlePlaque",
    "HUDLayer/HUD/PromptLabel",
    "HUDLayer/HUD/TimerPlaque",
    "HUDLayer/HUD/TimeLabel",
    "HUDLayer/HUD/LivesPlaque",
    "HUDLayer/HUD/PausePlaque",
    "HUDLayer/HUD/PauseButton",
    "HUDLayer/HUD/ScorePlaque",
    "HUDLayer/HUD/ScoreBottomContainer",
    "HUDLayer/HUD/ScoreBottomContainer/ScoreNumber"
]
const DELETED_PARTS := [
    "HUD/ScoreArtwork", "HUD/LivesArtwork", "HUD/TimerArtwork", "HUD/TitleArtwork",
    "HUD/ModeArtwork", "HUD/HeaderLabel", "HUD/StatsBar", "HUD/LivesHearts",
    "HUD/ModeLabel", "HUD/ObjectivePanel", "HUD/FeedbackPanel",
    "HUD/InstructionLabel", "HUD/DifficultyLabel",
    "HUD/StatsBar/ScoreLabel", "HUD/StatsBar/TimerLabel",
    "HUD/StatsBar/WaveLabel", "PauseButton", "HUDLayer/HUD/WaveLabel",
    "HUDLayer/HUD/LivesHearts/Heart4", "HUDLayer/HUD/LivesHearts/Heart5"
]
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var catch := CATCH_SCENE.instantiate() as Control
    _check(catch != null, "Catch the Word reference scene loads")
    if catch == null:
        quit(1)
        return
    for screen in SCREENS:
        for mode in MODES:
            for difficulty in DIFFICULTIES:
                await _exercise(catch, screen, mode, difficulty)
    catch.free()
    print("HUMAN PLANE THREE-HEART HUD: ", "PASS" if failures.is_empty() else "FAIL",
        " (%d checks, %d failures)" % [checks, failures.size()])
    quit(0 if failures.is_empty() else 1)


func _exercise(catch: Control, screen: Vector2i, mode: String, difficulty: String) -> void:
    root.size = screen
    var tag := "%dx%d/%s/%s" % [screen.x, screen.y, mode, difficulty]
    var game := SCENE.instantiate() as Control
    if game == null or not game.has_method("set_context"):
        _check(false, tag + " gameplay scene and script load")
        return
    var layer := game.get_node_or_null("HUDLayer") as CanvasLayer
    var hud := game.get_node_or_null("HUDLayer/HUD") as Control
    _check(layer != null and layer.owner == game and layer.layer == 20, tag + " editor-authored HUD CanvasLayer")
    _check(hud != null and hud.owner == game, tag + " editor-authored HUD root")
    for path in DELETED_PARTS:
        _check(game.get_node_or_null(path) == null, tag + " obsolete HUD element removed: " + path)
    var source_nodes := {}
    for path in HUD_PARTS:
        var item := game.get_node_or_null(path) as Control
        var source := catch.get_node_or_null(path) as Control
        _check(item != null and item.owner == game, tag + " scene-authored HUD control " + path)
        _check(source != null, "Catch reference control " + path)
        if item == null or source == null:
            continue
        _check(item.get_class() == source.get_class(), tag + " matches Catch node type " + path)
        _check(_coordinates(item) == _coordinates(source), tag + " exact original Catch inspector layout " + path)
        if item is TextureRect and source is TextureRect:
            var picture := item as TextureRect
            var ref_picture := source as TextureRect
            _check(picture.texture != null and ref_picture.texture != null
                and picture.texture.resource_path == ref_picture.texture.resource_path,
                tag + " identical source artwork " + path)
        if item is Label and source is Label:
            var label_node := item as Label
            var ref_label := source as Label
            _check(label_node.get_theme_font("font") == ref_label.get_theme_font("font"),
                tag + " original Catch font " + path)
        source_nodes[path] = item.get_instance_id()
    var score := game.get_node("HUDLayer/HUD/ScoreBottomContainer/ScoreNumber") as Label
    var timer_plaque := game.get_node("HUDLayer/HUD/TimerPlaque") as TextureRect
    var timer := game.get_node("HUDLayer/HUD/TimeLabel") as Label
    var lives_art := game.get_node("HUDLayer/HUD/LivesPlaque") as TextureRect
    _check(lives_art.texture == LIVES_STATE_3, tag + " initial three-heart native Catch plaque")
    _check(game.get_node_or_null("SceneBackground/SkyBackdrop") is TextureRect and
        game.get_node_or_null("PlaneRig/PlaneArtwork") is TextureRect,
        tag + " original game background and airplane remain intact")

    game.set_context({"activity": "Human Plane", "difficulty": difficulty,
        "topic": "Adjective", "game_mode": mode, "lives": 5, "score": 48})
    root.add_child(game)
    game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    await process_frame
    await process_frame
    game.set_process(false)
    _check(int(game.get("lives")) == 3, tag + " both modes cap fresh/legacy lives at THREE")
    _check(int(game.get_context().get("lives", -1)) == 3, tag + " saved context cannot leak 4/5 hearts")
    _check(int(game.get("score")) == 48 and score.text == "48",
        tag + " ScoreNumber shows str(score), NOT padded with zeroes")
    _check(score.is_visible_in_tree(), tag + " ScoreNumber visible in Catch's lower-right ScorePlaque")
    _check((game.get_node("HUDLayer/HUD/PromptLabel") as Label).text == "WHICH WORD IS AN ADJECTIVE?",
        tag + " prompt matches Catch-style grammar instruction")
    _check(lives_art.texture == LIVES_STATE_3, tag + " actual runtime three-heart artwork")
    if mode == "Seconds":
        _check(absf(float(game.get("time_remaining")) - 60.0) < 1.0, tag + " 60s Seconds remains unchanged")
        _check(timer_plaque.is_visible_in_tree() and timer.is_visible_in_tree(), tag + " timer and TimeLabel visible in Seconds")
        _check(timer.text == "60s", tag + " source Catch timer starts at 60s")
        _check(not lives_art.visible and not lives_art.is_visible_in_tree(), tag + " LivesPlaque hidden in Seconds")
    else:
        _check(is_zero_approx(float(game.get("time_remaining"))), tag + " Lives mode has no timer")
        _check(not timer_plaque.visible and not timer.is_visible_in_tree(), tag + " TimeLabel and TimerPlaque hidden in Lives")
        _check(lives_art.is_visible_in_tree(), tag + " original Catch LivesPlaque shown in Lives")
    var initial_rects := {}
    for path in HUD_PARTS:
        var control := game.get_node(path) as Control
        initial_rects[path] = control.get_rect()
    var original_gate := game.call("_gate_rect", 1, 0.85) as Rect2
    game.set("plane_x_norm", -0.2)
    game.call("_resolve_at_answer_line")
    _check(int(game.get("lives")) == 2, tag + " missing the visible gate deducts precisely one chance")
    _check(lives_art.texture == LIVES_STATE_2, tag + " LivesPlaque moves to original two-heart artwork")
    game.call("_sync_visuals")
    _check(score.text == str(game.get("score")), tag + " ScoreNumber follows score changes")
    for remaining in [1, 0, 3]:
        game.set("lives", remaining)
        game.call("_sync_visuals")
        var expected := {0: LIVES_STATE_EMPTY, 1: LIVES_STATE_1, 3: LIVES_STATE_3}[remaining] as Texture2D
        _check(lives_art.texture == expected, tag + " original exact %d-heart plaque" % remaining)
    _check(game.get_node_or_null("HUDLayer/HUD/WaveLabel") == null
        and game.get_node_or_null("HUD/StatsBar/WaveLabel") == null, tag + " no WAVE in runtime tree")
    for path in HUD_PARTS:
        var control := game.get_node(path) as Control
        _check(control.get_instance_id() == source_nodes[path], tag + " no HUD ghost replacements " + path)
        _check(control.get_rect().is_equal_approx(initial_rects[path]),
            tag + " update does not hardcode/move inspector rect " + path)
    _check((game.call("_gate_rect", 1, 0.85) as Rect2).is_equal_approx(original_gate),
        tag + " gate movement/collision geometry unaffected by HUD")
    game.queue_free()
    await process_frame
    await process_frame


func _coordinates(control: Control) -> Array:
    return [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom,
        control.offset_left, control.offset_top, control.offset_right, control.offset_bottom,
        control.custom_minimum_size]


func _check(ok: bool, description: String) -> void:
    checks += 1
    if not ok:
        failures.append(description)
        printerr("HUMAN PLANE THREE-HEART HUD FAIL: ", description)
