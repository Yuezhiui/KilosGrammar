extends SceneTree

const WRAPPER_PATH := "res://ui/play/gameplay/gameplay.tscn"
const DIMENSIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var wrapper_scene := load(WRAPPER_PATH) as PackedScene
	for dims in DIMENSIONS:
		root.size = dims
		root.content_scale_size = dims
		var wrapper := wrapper_scene.instantiate() as Control
		root.add_child(wrapper)
		wrapper.set_context({"activity": "Human Plane", "game_mode": "Seconds",
			"topic": "Noun", "difficulty": "Easy", "guided_tutorial": true,
			"camera_live": false, "start_countdown": true})
		for i in range(4):
			await process_frame
		var game := wrapper.get("active_game") as Control
		if game == null:
			failures.append(str(dims) + " wrapper failed to mount game")
			wrapper.queue_free()
			await process_frame
			continue
		var hybrid := game.get_node("HybridFlight3D") as Node2D
		var plane := game.get_node("PlaneRig") as Control
		var outline := game.get_node("TutorialSpotlightLayer/TutorialSpotlight/HighlightOutline") as Control
		var renderer_rect: Rect2 = hybrid.call("get_airplane_highlight_rect")
		print("GEOMETRY %s PlaneRig=%s 3D=%s Outline=%s Pose=%s" % [dims,
			plane.get_global_rect(), renderer_rect, outline.get_global_rect(), game.plane_x_norm])
		if not outline.get_global_rect().intersects(renderer_rect):
			failures.append(str(dims) + " 3D airplane outside movement spotlight")
		wrapper.queue_free()
		await process_frame
		await process_frame
	print("HUMAN PLANE WRAPPER SPOTLIGHT: %s failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
