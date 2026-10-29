extends SceneTree

# Isolated graceful-quit audio QA; never starts the camera or writes student data.
# Godot --headless --verbose --path . --script res://tools/test_main_menu_audio_shutdown.gd
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://ui/main_menu/main_menu.tscn") as PackedScene
	if packed == null:
		quit(1)
		return
	var menu := packed.instantiate() as Control
	var modes := OS.get_cmdline_user_args()
	root.add_child(menu)
	await create_timer(1.4).timeout
	if modes.has("after_games") or modes.has("after_catch") or modes.has("after_catch_no_voice") or modes.has("after_balloon") or modes.has("after_plane"):
		for activity in ["Catch the Word", "Balloon Popping", "Human Plane"]:
			if (modes.has("after_catch") or modes.has("after_catch_no_voice")) and activity != "Catch the Word":
				continue
			if modes.has("after_balloon") and activity != "Balloon Popping":
				continue
			if modes.has("after_plane") and activity != "Human Plane":
				continue
			menu.call("_on_panel_requested", "gameplay", {
				"activity": activity, "topic": "Noun", "difficulty": "Easy",
				"game_mode": "Seconds", "catch_map": "City",
				"catch_character": "Bear", "camera_live": false
			})
			await process_frame
			await process_frame
			var gameplay := menu.get("active_panel") as Control
			var game := gameplay.get("active_game") as Control if gameplay else null
			if game != null and activity == "Catch the Word" and not modes.has("after_catch_no_voice"):
				game.call("_handle_catch", {"matching": true, "word": "apple"})
			if game != null and activity == "Balloon Popping":
				game.call("_speak_balloon_feedback", true)
			menu.call("_return_to_main")
			await process_frame
			await process_frame
			if activity == "Catch the Word":
				var preloader := menu.get("catch_asset_preloader") as Node
				if preloader != null:
					var requested := preloader.get("_wanted") as Dictionary
					if requested.has("res://ui/minigames/catch_the_word/catch_word.tscn"):
						printerr("MAIN MENU AUDIO FAIL: scripted Catch PackedScene was sent to threaded loader")
						quit(1)
						return
			print("MAIN MENU AUDIO: exercising Quit after synthetic minigame routes")
		menu.call("_on_panel_requested", "quit", {})
		await create_timer(1.50).timeout
		printerr("MAIN MENU AUDIO FAIL: game-exit route failed to close")
		quit(1)
		return
	if modes.has("quit_button"):
		print("MAIN MENU AUDIO: exercising real Quit route with mixer grace")
		menu.call("_on_panel_requested", "quit", {})
		await create_timer(1.50).timeout
		printerr("MAIN MENU AUDIO FAIL: Quit route failed to close application")
		quit(1)
		return
	if modes.has("window_close"):
		print("MAIN MENU AUDIO: exercising window-close notification with mixer grace")
		menu.notification(1006) # MainLoop.NOTIFICATION_WM_CLOSE_REQUEST
		await create_timer(1.50).timeout
		printerr("MAIN MENU AUDIO FAIL: window-close route failed to exit")
		quit(1)
		return
	if not menu.has_method("prepare_for_shutdown"):
		printerr("MAIN MENU AUDIO: cleanup API missing")
		quit(1)
		return
	await menu.call("prepare_for_shutdown")
	var drained := bool(menu.get("_shutdown_audio_drain_complete"))
	print("MAIN MENU AUDIO: requested drain returned, completed=", drained)
	if not drained:
		# Calling the dynamically dispatched coroutine must not free a menu
		# while it is still holding playback reference objects.
		await create_timer(0.75).timeout
		drained = bool(menu.get("_shutdown_audio_drain_complete"))
	print("MAIN MENU AUDIO: mixer drain completed=", drained)
	menu.queue_free()
	await process_frame
	await process_frame
	print("MAIN MENU AUDIO: ", "PASS" if drained else "FAIL")
	quit(0 if drained else 1)
