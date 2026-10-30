extends SceneTree

## Read-only native leaderboard UI validation using synthetic demo names.
## No database, CSV mutation, webcam, or user-data access.
const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const DEMO := [
	{"student_id":"DEMO-KG-20261030-C", "student_name":"Demo Learner Charlie", "grade":"Grade 5 - DEMO", "minigame":"Catch the Word", "game_style":"Verb", "game_mode":"Seconds", "difficulty":"Hard", "score":600},
	{"student_id":"DEMO-KG-20261030-B", "student_name":"Demo Learner Bravo", "grade":"Grade 4 - DEMO", "minigame":"Human Plane", "game_style":"Verb", "game_mode":"Lives", "difficulty":"Easy", "score":500},
	{"student_id":"DEMO-KG-20261030-E", "student_name":"Demo Learner Echo", "grade":"Grade 6 - DEMO", "minigame":"Catch the Word", "game_style":"Adverb", "game_mode":"Seconds", "difficulty":"Normal", "score":500}
]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for size in SIZES:
		root.size = size
		root.content_scale_size = size
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_size(size)
		var scene := BOARD.instantiate() as Control
		root.add_child(scene)
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		scene.set_context({"database_connected":true, "leaderboard_rows":DEMO})
		await process_frame
		var container := scene.get_node("%ScoreRows") as VBoxContainer
		_check(container.get_child_count() == DEMO.size(), str(size) + " exactly three demo rows")
		for i in range(mini(container.get_child_count(), DEMO.size())):
			var row := container.get_child(i) as Control
			var name := row.get_node("StudentName") as Label
			var grade := row.get_node("Grade") as Label
			var style := row.get_node("GameStyle") as Label
			var font := grade.get_theme_font("font")
			var grade_width := font.get_string_size(grade.text, HORIZONTAL_ALIGNMENT_LEFT, -1, grade.get_theme_font_size("font_size")).x
			var name_width := name.get_theme_font("font").get_string_size(name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name.get_theme_font_size("font_size")).x
			_check(grade.text == DEMO[i]["grade"], str(size) + " grade data not truncated")
			_check(grade_width + 10.0 < grade.size.x, str(size) + " full grade text fits safely")
			_check(name_width + 10.0 < name.size.x, str(size) + " full student name fits")
			_check(name.position.x + name.size.x + 4.0 <= grade.position.x, str(size) + " name and grade do not overlap")
			_check(grade.position.x + grade.size.x + 3.0 <= style.position.x, str(size) + " grade and style do not overlap")
			_check(grade.position.x < 410.0, str(size) + " grade shifted left from old 410px")
		if DisplayServer.get_name() != "headless":
			for frame in range(3):
				await process_frame
			await RenderingServer.frame_post_draw
			var picture := root.get_texture().get_image()
			var filename := "res://showcase/qa_leaderboard_grade_20261030/grade_%dx%d.png" % [size.x, size.y]
			_check(picture != null and not picture.is_empty() and picture.save_png(filename) == OK,
				str(size) + " native GPU screenshot")
		scene.queue_free()
		await process_frame
	print("LEADERBOARD GRADE QA: %s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
		printerr("LEADERBOARD GRADE FAIL: " + text)
