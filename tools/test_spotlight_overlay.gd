extends SceneTree

# Godot --headless --path . --script res://tools/test_spotlight_overlay.gd
# Focused tests for the reusable editor-authored tutorial; no camera required.

const TUTORIAL := preload("res://ui/tutorial/spotlight_overlay.tscn")
const ARROW_PATH := "res://Components/TutorialSpotlight/right-arrow.png"

var failures: Array[String] = []
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var host := Control.new()
	host.name = "TutorialHost"
	host.size = Vector2(1280, 720)
	root.add_child(host)
	var tutorial := TUTORIAL.instantiate() as CanvasLayer
	_check(tutorial != null, "scene instantiates as a CanvasLayer")
	if tutorial == null:
		_end(host)
		return
	host.add_child(tutorial)
	await process_frame
	_check(not tutorial.visible, "tutorial stays hidden until started")
	_check(tutorial.layer > 20, "spotlight overlays Catch the Word HUD layer 20")
	_check(tutorial.get_node("Overlay/DimMask").material is ShaderMaterial,
		"true transparent shader spotlight mask exists in scene")
	_check(tutorial.get_node("Overlay/VoicePlayer") is AudioStreamPlayer,
		"optional voice playback is an editable scene node")
	for button in ["NextButton", "BackButton", "ReplayButton", "SkipButton"]:
		_check(tutorial.get_node_or_null("Overlay/CaptionCard/" + button) is Button,
			button + " is scene-authored")
	for name in ["PromptArrow", "PlayArrow", "ModeArrow", "ScoreArrow", "PauseArrow", "PlanePauseArrow"]:
		var arrow := tutorial.get_node_or_null("Overlay/GuideArrows/" + name) as TextureRect
		_check(arrow != null and arrow.texture != null and arrow.texture.resource_path == ARROW_PATH,
			name + " uses the editable original arrow PNG")

	var started_events: Array[String] = []
	var counters := {"finished": 0, "skipped": 0}
	tutorial.tutorial_started.connect(func(game: String, mode: String) -> void:
		started_events.append(game + "/" + mode))
	tutorial.finished.connect(func() -> void:
		counters["finished"] += 1)
	tutorial.skipped.connect(func() -> void:
		counters["skipped"] += 1)

	var games := ["catch_word", "balloon_popping", "human_plane"]
	var modes := ["seconds", "lives"]
	for game in games:
		var name: String = {"catch_word": "CatchWord", "balloon_popping": "BalloonPopping", "human_plane": "HumanPlane"}[game]
		for mode in modes:
			tutorial.start_tutorial(game, mode)
			await process_frame
			_check(tutorial.visible and bool(tutorial.call("is_tutorial_active")), game + "/" + mode + " opens")
			var ids: PackedStringArray = tutorial.call("get_step_ids")
			_check(ids.size() == 5, game + "/" + mode + " has five steps")
			_check(ids[2] == game + "_" + mode, "active game mode only (" + game + "/" + mode + ")")
			_check(not ids.has(game + ("_lives" if mode == "seconds" else "_seconds")),
				"inactive game mode is not announced (" + game + "/" + mode + ")")
			var regions := tutorial.get_node_or_null("Overlay/FocusRegions/" + name) as Control
			_check(regions != null and regions.get_child_count() == 6, name + " has six editable fallback bounds")
			var rect: Rect2 = tutorial.call("get_spotlight_rect")
			_check(rect.get_area() > 0.0, game + " uses a real spotlight rectangle")
			_check((tutorial.get_node("Overlay/CaptionCard/Caption") as Label).text.length() > 20,
				game + " captions work with no audio")
			tutorial.go_next()
			_check(String(tutorial.call("get_current_step_id")) == game + "_movement",
				game + " moves to movement practice")
			_check(tutorial.get_node("Overlay/MovementFeedbackPanel").visible,
				game + " movement practice feedback opens")
			for key_code in [KEY_A, KEY_S, KEY_D]:
				var key := InputEventKey.new()
				key.keycode = key_code
				key.pressed = true
				tutorial.call("_unhandled_key_input", key)
			if game == "human_plane":
				_check((tutorial.get("_visited_lanes") as Dictionary).is_empty(),
					"Human Plane requires real outstretched wing tilts, not keyboard shortcuts")
			else:
				_check((tutorial.get("_visited_lanes") as Dictionary).size() == 3,
					game + " supports legacy tutorial-only A/S/D movement practice")
			tutorial.go_next()
			_check(tutorial.get_node("Overlay/CaptionCard/Caption").text.contains(
				"60 seconds" if mode == "seconds" else "three lives"),
				game + "/" + mode + " explains the selected rules")
			var stable_id := String(tutorial.call("get_current_step_id"))
			tutorial.replay()
			_check(String(tutorial.call("get_current_step_id")) == stable_id,
				game + " voice replay does not reset the step")
			tutorial.go_back()
			_check(String(tutorial.call("get_current_step_id")) == game + "_movement",
				game + " back navigation works")
			tutorial.skip()
			_check(not tutorial.visible and not bool(tutorial.call("is_tutorial_active")),
				game + " SKIP closes the tutorial")

	# Explicit HUD CanvasLayer target takes priority over scene fallback, and
	# follows live UI transforms as the HUD moves in the game.
	var hud := CanvasLayer.new()
	hud.layer = 20
	host.add_child(hud)
	var live_target := Control.new()
	live_target.position = Vector2(991, 9)
	live_target.size = Vector2(202, 82)
	hud.add_child(live_target)
	tutorial.start_tutorial("catch_word", "lives", {"mode": live_target})
	tutorial.go_next()
	tutorial.go_next()
	var live_rect: Rect2 = tutorial.call("get_spotlight_rect")
	_check(absf(live_rect.position.x - 979.0) <= 2.0
		and absf(live_rect.position.y - (-3.0)) <= 2.0,
		"real CanvasLayer HUD is spotlighted in overlay coordinates")
	live_target.position += Vector2(45, 20)
	await process_frame
	var moved_rect: Rect2 = tutorial.call("get_spotlight_rect")
	_check(moved_rect.position.distance_to(live_rect.position + Vector2(45, 20)) <= 1.0,
		"spotlight follows live HUD target motion")
	tutorial.go_next()
	tutorial.go_next()
	tutorial.go_next()
	_check(not tutorial.visible, "NEXT on final step closes tutorial")
	_check(int(counters["finished"]) == 1, "finished signal emitted once")
	_check(int(counters["skipped"]) == 6, "skipped emitted once per skipped run")
	_check(started_events.size() == 7, "tutorial_started emitted for all runs")
	# Human Plane's gameplay wrapper can pass the entire game Control as
	# play_area. That must never punch an almost full-screen transparent hole.
	var full_screen_game := Control.new()
	full_screen_game.size = Vector2(1280, 720)
	host.add_child(full_screen_game)
	tutorial.start_tutorial("human_plane", "seconds", {"play_area": full_screen_game})
	tutorial.go_next()
	var movement_rect: Rect2 = tutorial.get_spotlight_rect()
	_check(movement_rect.size.x < 0.9 * 1280.0 and movement_rect.size.y < 0.9 * 720.0,
		"Human Plane full-screen game root uses editor-authored movement bounds")
	tutorial.skip()
	full_screen_game.queue_free()
	hud.queue_free()
	_end(host)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _end(host: Control) -> void:
	host.queue_free()
	if failures.is_empty():
		print("PASS spotlight overlay: %d checks, 3 activities x 2 modes" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error("SPOTLIGHT QA: " + failure)
		print("FAIL spotlight overlay: %d of %d checks failed" % [failures.size(), checks])
		quit(1)
