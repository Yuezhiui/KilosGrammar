extends SceneTree

# No webcam, DB, main-menu navigation, or 3D viewport is used here.
# Run with -- --capture to write two near/far PNG previews into user:// only.
const GAME = preload("res://ui/minigames/human_plane/human_plane.tscn")
const SIZES = [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080)]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for dims in SIZES:
		root.size = dims
		root.content_scale_size = dims
		var game := GAME.instantiate() as Control
		root.add_child(game)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game.set_context({"game_mode":"Seconds","difficulty":"Normal","topic":"Noun",
			"camera_live":false})
		await process_frame
		await process_frame
		game.set_process(false)
		var bg := game.get_node_or_null("FlightBackground") as TextureRect
		var moving := game.get_node("MovingGates") as Control
		var pilot := game.get_node("PlaneRig") as Control
		_check(game.get_node_or_null("WorldView3D") == null,
			"2D game has zero WorldView3D dependency "+str(dims))
		_check(bg != null and bg.texture != null and
			bg.texture.resource_path.ends_with("BACKGROUND.png"),
			"supplied BACKGROUND.png renders directly "+str(dims))
		_check(moving.modulate.a > 0.99 and pilot.modulate.a > 0.99,
			"original 2D plane and moving arcs are not hidden "+str(dims))
		_check(game.get_node("HUDLayer") is CanvasLayer,
			"unchanged Catch-style HUD overlays 2D arc scene "+str(dims))
		var prev_projected := -1.0
		var prev_width := -1.0
		for p in [0.0,0.25,0.5,0.75,1.0]:
			var proj: float = game.call("_gate_eased_progress",p)
			var rect: Rect2 = game.call("_gate_rect",1,p)
			_check(proj >= prev_projected and rect.size.x > prev_width,
				"inverse-depth projection grows each approaching arc "+str(dims)+" p="+str(p))
			prev_projected=proj
			prev_width=rect.size.x
		_check(absf(float(game.call("_gate_eased_progress",0.0)))<0.00001 and
			absf(float(game.call("_gate_eased_progress",1.0))-1.0)<0.00001,
			"perspective remains locked to authored GateStart/End "+str(dims))
		_check(float(game.call("_gate_eased_progress",0.75))-
			float(game.call("_gate_eased_progress",0.5)) >
			float(game.call("_gate_eased_progress",0.5))-
			float(game.call("_gate_eased_progress",0.25)),
			"normalized focal projection accelerates when gates approach "+str(dims))
		for i in range(3):
			var gate := game.get_node("MovingGates").get_child(i) as Control
			_check(gate.get_node("GateArtwork") is TextureRect and
				(gate.get_node("GateArtwork") as TextureRect).texture != null,
				"original colored arc art is available lane "+str(i))
			for legacy in ["LeftPillar","RightPillar","TopBar","Interior"]:
				_check(not (gate.get_node(legacy) as Control).visible,
					"legacy rectangle remains hidden "+legacy+" lane "+str(i))
		var answer_p: float = game.call("_progress_for_answer_line")
		_check(answer_p>0.0 and answer_p<1.0,
			"2D arc crosses authored answer line exactly "+str(dims))
		var current := game.get_node("MovingGates/GateCenter") as Control
		for progress in [0.12,0.68]:
			game.set("round_data",{"options":["ANIMALS","APPLE","RUN"],"valid_indices":[1],
				"prompt":"WHICH WORD IS A NOUN?"})
			game.set("gate_progress",progress)
			game.call("_sync_visuals")
			_check(current.visible and
				(current.get_node("WordLabel") as Label).text=="APPLE",
				"visible arc text uses actual question "+str(dims))
			_check(current.size.x > 30 and current.size.y > 30,
				"arc has legible projected size "+str(dims))
			if "--capture" in OS.get_cmdline_user_args():
				await process_frame
				await RenderingServer.frame_post_draw
				var image_out := root.get_texture().get_image()
				var phase := "far" if progress < 0.5 else "near"
				var pth := "user://_qa_human_plane_2d_%dx%d_%s.png" % [dims.x,dims.y,phase]
				_check(image_out.save_png(pth)==OK,"GPU image saved "+pth)
				print("2D_PERSPECTIVE_SCREENSHOT ",ProjectSettings.globalize_path(pth))
		game.set("paused",true)
		var stopped_progress: float = game.get("gate_progress")
		game._process(0.5)
		_check(is_equal_approx(float(game.get("gate_progress")),stopped_progress),
			"pause freezes arc and plane updates "+str(dims))
		game.queue_free()
		await process_frame
		await process_frame
	print("HUMAN PLANE PURE 2D PERSPECTIVE: ",
		"PASS" if failures.is_empty() else "FAIL",
		" (",checks," checks; ",failures.size()," failures)")
	quit(0 if failures.is_empty() else 1)

func _check(ok:bool, note:String)->void:
	checks+=1
	if not ok:
		failures.append(note)
		printerr("2D PERSPECTIVE FAIL: ",note)
