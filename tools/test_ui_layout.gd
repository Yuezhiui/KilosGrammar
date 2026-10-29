extends SceneTree

# Validate controls fit common KilosGrammar classroom desktop viewports.
# Run with Godot 4.7.2: --headless --path . --script res://tools/test_ui_layout.gd
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const ROUTES: Array[String] = [
	"tutorial_home", "grammar_guide",
	"student_setup", "play_activity", "play_topic", "play_difficulty",
		"calibration", "gameplay", "pause",
	"results", "leaderboard", "settings"
]

var failures: Array[String] = []
var measured := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: PackedScene = load("res://ui/main_menu/main_menu.tscn")
	if scene == null:
		push_error("Cannot load main scene")
		quit(1)
		return
	var app: Control = scene.instantiate()
	root.add_child(app)
	await create_timer(1.35).timeout
	for viewport_size in SIZES:
		root.size = viewport_size
		await process_frame
		await process_frame
		var routes_checked := 0
		for route in ROUTES:
			app.call("_on_panel_requested", route, {})
			await process_frame
			await process_frame
			if String(app.get("current_route")) != route:
				failures.append("Missing route or load failure: " + route)
				continue
			var panel: Control = app.get("active_panel")
			if panel == null:
				failures.append("Cannot show route: " + route)
				continue
			var controls: Array[Node] = []
			_find_controls(panel, controls)
			var frame_rect := Rect2(Vector2.ZERO, Vector2(viewport_size))
			for node in controls:
				var control := node as Control
				if (control is Button or control is HSlider or control is LineEdit or control is Label) and control.is_visible_in_tree() and not _in_scroller(control):
					# Falling-word labels start offscreen within a clipped gameplay parent.
					var rect := _drawn_rect(control)
					if rect.size.x < 1.0 or rect.size.y < 1.0:
						continue
					if not frame_rect.encloses(rect.grow(-1.0)):
						failures.append("%s %s: visible control %s outside frame, rect=%s" % [str(viewport_size), route, control.name, str(rect)])
					measured += 1
			routes_checked += 1
		print("CHECK %s: %d scenes" % [str(viewport_size), routes_checked])
	app.call("_return_to_main")
	var music: AudioStreamPlayer = app.get("title_music_player")
	if music:
		music.stop()
		music.stream = null
	app.queue_free()
	await process_frame
	await process_frame
	# Let outstanding MP3 playback callbacks retire before the headless
	# test shuts down the audio server; this is not a gameplay delay.
	await create_timer(0.5).timeout
	if failures.is_empty():
		print("PASS  layout boundaries: %d visible labels and interactive controls across %d target sizes" % [measured, SIZES.size()])
		quit(0)
	else:
		for reason in failures:
			push_error("LAYOUT: " + reason)
		quit(1)


func _find_controls(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child is Control:
			out.append(child)
		_find_controls(child, out)


func _in_scroller(control: Control) -> bool:
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			return true
		ancestor = ancestor.get_parent()
	return false


func _drawn_rect(control: Control) -> Rect2:
	var visible_rect := control.get_global_rect()
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).clip_contents:
			visible_rect = visible_rect.intersection((ancestor as Control).get_global_rect())
			if not visible_rect.has_area():
				return Rect2()
		ancestor = ancestor.get_parent()
	return visible_rect
