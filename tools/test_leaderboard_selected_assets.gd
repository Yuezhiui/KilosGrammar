extends SceneTree

## Focused October 25 regression for fully image-skinned native filter selections.
## No database server or destructive operations are called.
const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const ASSETS := "res://Components/Leaderboard/"
const CAPTURE_PATH := "res://ui/secondary/_review_selected_leaderboard.png"

var errors: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	var panel := BOARD.instantiate() as Control
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	_check(panel.get_node_or_null("FiltersArt") == null
		and panel.get_node_or_null("FiltersToggle") == null
		and panel.get_node_or_null("MoreFiltersPanel") == null,
		"FILTERS art, button, and popover are entirely removed")
	_check(panel.has_method("set_minigame_filter")
		and panel.has_method("request_filtered_csv_export"),
		"minigame and filtered CSV backend remain callable without popover")
	_check(panel.find_child("MinigameFilter", true, false) == null
		and panel.find_child("DownloadButton", true, false) == null,
		"retired backend-only controls are physically removed and cannot intercept clicks")

	var groups := [
		["StyleFilter", ["ALL STYLES", "NOUN", "PRONOUN", "VERB", "ADJECTIVE", "ADVERB"],
			["ALL STYLES.png", "NOUN.png", "PRONOUN.png", "VERB.png", "ADJECTIVE.png", "ADVERB.png"]],
		["ModeFilter", ["ALL MODES", "SECONDS", "LIVES"],
			["ALL MODES.png", "seconds.png", "2lives.png"]],
		["DifficultyFilter", ["ALL DIFFICULTIES", "EASY", "NORMAL", "HARD"],
			["ALL DIFFICULTIES.png", "easy.png", "normal.png", "Hard.png"]],
	]
	for group in groups:
		var selector := panel.get_node("%" + group[0]) as OptionButton
		var labels: Array = group[1]
		var filenames: Array = group[2]
		_check(selector != null and selector.item_count == labels.size(),
			group[0] + " has exactly the supported options")
		if selector == null:
			continue
		for index in labels.size():
			_check(selector.get_item_text(index) == labels[index],
				"%s option %d has expected label" % [group[0], index])
			selector.select(index)
			selector.item_selected.emit(index)
			var skin := selector.get_theme_stylebox("normal") as StyleBoxTexture
			_check(skin != null and skin.texture != null
					and _is_leaderboard_png(_asset_source(skin.texture), filenames[index]),
				"%s index %d uses supplied image %s" % [group[0], index, filenames[index]])
			_check(selector.get_theme_color("font_color").a < 0.01,
				"%s index %d hides the native duplicate caption" % [group[0], index])
			_check(selector.get_theme_icon("arrow").get_image().get_pixel(0, 0).a < 0.01,
				"%s index %d hides the native duplicate chevron" % [group[0], index])
		selector.select(0)
		selector.item_selected.emit(0)

	panel.set_context({"leaderboard_rows": [
		{"student_id":"A","student_name":"One","minigame":"Catch the Word","game_style":"Noun","game_mode":"Seconds","difficulty":"Easy","score":12},
		{"student_id":"B","student_name":"Two","minigame":"Human Plane","game_style":"Noun","game_mode":"Seconds","difficulty":"Easy","score":10},
		{"student_id":"C","student_name":"Three","minigame":"Human Plane","game_style":"Verb","game_mode":"Lives","difficulty":"Hard","score":16}
	], "database_connected":true})
	_check((panel.get_node("%ScoreRows") as VBoxContainer).get_child_count() == 3,
		"initial records render when backend supplies scores")
	_check(panel.set_minigame_filter("Human Plane"), "host can filter minigame by name")
	_check((panel.get_node("%ScoreRows") as VBoxContainer).get_child_count() == 2,
		"API minigame filter keeps only the requested records")
	_check(not panel.set_minigame_filter("Does not exist"),
		"unknown minigame filter is rejected")
	_check(panel.set_minigame_filter("ALL MINIGAMES"), "host can reset minigame selection")
	var path := ProjectSettings.globalize_path("user://_lb_selected_art_test.csv")
	panel.call("_write_csv", path)
	var exported := FileAccess.get_file_as_string(path)
	_check(exported.contains("MINIGAME") and exported.contains("Catch the Word")
		and exported.contains("Human Plane"), "filtered CSV implementation remains functional")
	DirAccess.remove_absolute(path)
	if OS.get_environment("CAPTURE_LEADERBOARD_SELECTED") == "1" and DisplayServer.get_name() != "headless":
		panel.set_transfer_status("")
		for target in [["StyleFilter", 3], ["ModeFilter", 2], ["DifficultyFilter", 3]]:
			var selector := panel.get_node("%" + target[0]) as OptionButton
			selector.select(target[1])
			selector.item_selected.emit(target[1])
		_check((panel.get_node("%ScoreRows") as VBoxContainer).get_child_count() == 1,
			"combined selected art and filters show the one matching score")
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(CAPTURE_PATH)) == OK,
			"selected-art graphical screenshot created")
		print("LEADERBOARD CAPTURE: ", ProjectSettings.globalize_path(CAPTURE_PATH))
	for viewport in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]:
		root.size = viewport
		root.content_scale_size = viewport
		await process_frame
		await process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport)).grow(3)
		for name in ["StyleFilter", "ModeFilter", "DifficultyFilter", "ImportCsvButton", "ExportCsvButton", "DeleteAllButton"]:
			var control := panel.get_node("%" + name) as Control
			_check(bounds.encloses(control.get_global_rect()),
				"%s stays inside %s viewport" % [name, viewport])
	panel.queue_free()
	await process_frame
	for failure in errors:
		printerr("LEADERBOARD SELECTED ASSETS FAIL: ", failure)
	print("LEADERBOARD SELECTED ASSETS: %s %d checks, %d failures" %
		["PASS" if errors.is_empty() else "FAIL", checks, errors.size()])
	quit(0 if errors.is_empty() else 1)

func _asset_source(texture: Texture2D) -> String:
	if texture is AtlasTexture:
		return (texture as AtlasTexture).atlas.resource_path
	return texture.resource_path if texture != null else ""

func _is_leaderboard_png(path: String, original_name: String) -> bool:
	# Image organization may add screen-specific folders without changing the
	# pixels, dropdown option ordering or the editor-authored selected sprites.
	return path.begins_with(ASSETS) and path.get_file() == original_name and ResourceLoader.exists(path)

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		errors.append(description)
