extends SceneTree

const SCENE := preload("res://ui/student/setup/student_setup.tscn")
const SOURCE_FOLDER := "res://Components/StudentSetup/Original20261102/"

var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _assert(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("STUDENT FULLWIDTH: " + detail)


func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var screen := SCENE.instantiate() as Control
	viewport.add_child(screen)
	await process_frame
	await process_frame
	var stage := screen.get_node("SetupStage") as Control
	var profile := stage.get_node("StudentProfileCard") as Control
	var game := stage.get_node("GameSetupCard") as Control
	var profile_board := stage.get_node("WoodenSetupBoard") as TextureRect
	var game_board := stage.get_node("GameWoodenSetupBoard") as TextureRect
	_assert(stage.size.is_equal_approx(Vector2(1280, 720)), "the editable stage is 1280×720")
	_assert(profile.size.x > 1200 and game.size.x > 1200, "each setup phase is a full-width card")
	_assert(profile.visible and not game.visible and profile_board.visible and not game_board.visible,
		"first screen is Student Profile with its own full board")
	_assert(profile_board.texture.resource_path == SOURCE_FOLDER + "profile_board.png",
		"Student Profile uses the exact downloaded blank board")
	_assert(game_board.texture.resource_path == SOURCE_FOLDER + "game_board.png",
		"Game Setup uses the exact downloaded blank board")
	_assert((profile.get_node("StudentCardTitle") as TextureRect).texture.resource_path == SOURCE_FOLDER + "profile_header.png",
		"Student Profile uses its downloaded header")
	for group in ["StudentId", "StudentName", "GradeSection"]:
		var control := profile.get_node(group + "Group") as Control
		_assert(control.size.x > 900, group + " row stretches across the board")
		var field_art := control.get_node("FieldArtwork") as TextureRect
		_assert(field_art.texture.resource_path == SOURCE_FOLDER + "profile_entry_field.png",
			group + " row reuses original source field art")
		_assert((control.get_node(group + "Edit") as LineEdit).size.x > 480,
			group + " editor remains a native full-width input")
	var go := stage.get_node("SetupActions/ContinueButton") as Button
	_assert(go.disabled, "Continue starts gray")
	for field in ["StudentId", "StudentName", "GradeSection"]:
		var value := "QA-20261102" if field == "StudentId" else "Sample Student" if field == "StudentName" else "Grade 3 Apple"
		(profile.get_node(field + "Group/" + field + "Edit") as LineEdit).text = value
	screen.call("_update_validation")
	_assert(not go.disabled, "complete student profile turns Continue green")
	_assert((go.get_node("ButtonArtwork") as CanvasItem).visible, "green art visible when enabled")
	_assert(not (go.get_node("ContinueDisabledArtwork") as CanvasItem).visible, "gray art hidden when enabled")
	_capture(viewport, "STUDENT_SETUP_profile_preview.png")
	screen.call("_continue")
	_assert(not profile.visible and game.visible and not profile_board.visible and game_board.visible,
		"Continue opens only the wide Game Setup screen")
	_assert(go.disabled, "game selections are initially required")
	var style_grid := game.get_node("GameContent/GameStyleGrid") as Control
	var topics := ["Noun", "Pronoun", "Verb", "Adjective", "Adverb"]
	for item in topics:
		var btn := style_grid.get_node(item + "Button") as Button
		_assert(btn.size.x >= 120 and btn.size.y >= 75 and btn.position.x > -1, item + " source art is usable")
		_assert((btn.get_node("ButtonArtwork") as TextureRect).texture.resource_path == SOURCE_FOLDER + "topic_" + item.to_lower() + ".png",
			item + " artwork is the separate original PNG")
	_assert((game.get_node("PlayerModeTitle") as TextureRect).texture.resource_path == SOURCE_FOLDER + "player_mode_caption.png",
		"the Player Mode label is original artwork")
	_capture(viewport, "STUDENT_SETUP_game_preview.png")
	screen.call("_select_style", "Noun")
	screen.call("_select_mode", "Seconds")
	screen.call("_select_difficulty", "Easy")
	screen.call("_select_player_mode", "Single Player")
	_assert(not go.disabled, "all valid single-player choices enable Continue")
	var routes: Array[String] = []
	screen.requested.connect(func(route: String, _payload: Dictionary) -> void: routes.append(route))
	screen.call("_continue")
	_assert(routes == ["play_activity"], "ordinary single-player setup routes to activity chooser")
	routes.clear()
	screen.call("_select_player_mode", "Multiplayer")
	var p2_panel := game.get_node("PlayerTwoPanel") as Panel
	var p2_done := p2_panel.get_node("Player2DoneButton") as Button
	_assert(p2_panel.visible and p2_done.disabled, "multiplayer opens separate Player Two form requiring independent identity")
	var p2_id := p2_panel.get_node("Player2IdEdit") as LineEdit
	p2_id.text = "QA-20261102"
	(p2_panel.get_node("Player2NameEdit") as LineEdit).text = "Second Student"
	(p2_panel.get_node("Player2GradeEdit") as LineEdit).text = "Grade 3 Apple"
	screen.call("_update_validation")
	_assert(p2_done.disabled and go.disabled, "two players cannot share the same student ID")
	p2_id.text = "QA-PLAYER2"
	screen.call("_update_validation")
	_assert(not p2_done.disabled and not go.disabled, "unique complete Player Two identity enables setup")
	p2_done.pressed.emit()
	_assert(not p2_panel.visible, "Done returns to game choices with Player Two fields preserved")
	screen.call("_continue")
	_assert(routes == ["calibration"], "valid multiplayer setup requests calibration")
	viewport.queue_free()
	await process_frame
	print("STUDENT FULLWIDTH ART: ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _capture(viewport: SubViewport, filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	if image.is_empty():
		return
	var output := "C:/Users/Yue/Downloads/" + filename
	var result := image.save_png(output)
	if result == OK:
		print("Review screenshot: ", output)
