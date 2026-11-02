extends SceneTree

# Pure scene regression: no service, disk, or database writes.
const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const NAMES := ["StyleFilter", "ModeFilter", "DifficultyFilter", "ScoreSort"]
const SOURCE := "res://Components/Leaderboard/SharedDropdown20261102/dropdown_base.png"
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("SHARED DROPDOWN QA FAIL: ", reason)

func _source(style: StyleBoxTexture) -> String:
	if style == null or style.texture == null:
		return ""
	if style.texture is AtlasTexture:
		return (style.texture as AtlasTexture).atlas.resource_path
	return style.texture.resource_path

func _run() -> void:
	for size in [Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]:
		root.size = size
		root.content_scale_size = size
		var board := BOARD.instantiate() as Control
		root.add_child(board)
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		board.set_context({"database_connected":true,"teacher_authorized":false,
			"leaderboard_rows":[
				{"student_id":"B-9","student_name":"Beta","grade_section":"Grade 4 - Ruby","game_style":"Noun","game_mode":"Seconds","difficulty":"Easy","score":9},
				{"student_id":"A-2","student_name":"Alpha","grade_section":"Grade 2 - Jade","game_style":"Verb","game_mode":"Lives","difficulty":"Hard","score":70}]})
		await process_frame
		var caption_font := -1
		var base_style: StyleBoxTexture
		var previous_right := -1.0
		for name in NAMES:
			var control := board.get_node_or_null("%" + name) as OptionButton
			_check(control != null and control.is_visible_in_tree(),str(size)+" native dropdown present "+name)
			if control == null:
				continue
			var style := control.get_theme_stylebox("normal") as StyleBoxTexture
			_check(style != null and _source(style) == SOURCE,str(size)+" shared wood source "+name)
			if base_style == null:
				base_style = style
			else:
				_check(style == base_style or (style.texture is AtlasTexture and base_style.texture is AtlasTexture
					and (style.texture as AtlasTexture).atlas == (base_style.texture as AtlasTexture).atlas),str(size)+" same style or atlas "+name)
			var font := control.get_theme_font_size("font_size")
			if caption_font < 0:
				caption_font = font
			_check(font == caption_font and font >= 14,str(size)+" consistent readable native font "+name)
			_check(control.get_theme_color("font_color").a >= 0.95,str(size)+" native selected caption visible "+name)
			var arrow := control.get_theme_icon("arrow")
			_check(arrow != null and arrow.get_size() == Vector2(2,2) and arrow.get_image().get_pixel(0,0).a < 0.02,str(size)+" no duplicate native arrow "+name)
			var rect := control.get_global_rect()
			var scale := float(size.x) / 1280.0
			_check(rect.position.x >= 157.0 * scale and rect.end.x <= 1109.0 * scale
				and rect.position.y < 290.0 * scale,str(size)+" four-dropdown top row geometry "+name)
			_check(previous_right < 0 or rect.position.x >= previous_right - 1.0,str(size)+" no dropdown overlap "+name)
			previous_right = rect.end.x
			for index in control.item_count:
				control.select(index)
				control.item_selected.emit(index)
				_check(control.get_item_text(control.selected).strip_edges().length() > 0 and control.get_theme_stylebox("normal") == style,
					str(size)+" dynamic selected caption on same wood "+name+" #"+str(index))
			control.select(0)
			control.item_selected.emit(0)
		var search := board.get_node("%StudentSearch") as LineEdit
		_check(search.is_visible_in_tree() and search.size.x >= 550.0,str(size)+" dedicated wide search row")
		var sort := board.get_node("%ScoreSort") as OptionButton
		for pair in [["LOWEST SCORE","B-9"],["HIGHEST SCORE","A-2"],["STUDENT ID A-Z","A-2"],["GRADE LEVEL","A-2"]]:
			for i in sort.item_count:
				if sort.get_item_text(i).to_upper() == pair[0]:
					sort.select(i)
					break
			board.call("_on_filter_changed")
			var shown: Array = board.get("_visible_rows")
			_check(shown.size() == 2 and shown[0].get("student_id") == pair[1],str(size)+" sorting semantics "+pair[0])
		board.queue_free()
		await process_frame
	print("SHARED DROPDOWN: %s checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL",checks,failures])
	quit(0 if failures == 0 else 1)
