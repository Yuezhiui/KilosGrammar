extends SceneTree
## Verify the five user-supplied button PNGs without altering teacher-edited
## Student Setup geometry, registration or game selection. No camera or DB.
const SCENE := preload("res://ui/student/setup/student_setup.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const MODE_ROW := "SetupStage/GameSetupCard/GameContent/LowerSelections/ModeColumn/ModeRow"
const DIFFICULTY_ROW := "SetupStage/GameSetupCard/GameContent/LowerSelections/DifficultyColumn/DifficultyRow"
const CASES := [
	{"name": "Seconds", "parent": MODE_ROW, "image": "60s.png", "type": "mode"},
	{"name": "Lives", "parent": MODE_ROW, "image": "3 lives.png", "type": "mode"},
	{"name": "Easy", "parent": DIFFICULTY_ROW, "image": "easy.png", "type": "difficulty"},
	{"name": "Normal", "parent": DIFFICULTY_ROW, "image": "normal.png", "type": "difficulty"},
	{"name": "Hard", "parent": DIFFICULTY_ROW, "image": "hard.png", "type": "difficulty"}
]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for viewport in SIZES:
		root.size = viewport
		root.content_scale_size = viewport
		var form := SCENE.instantiate() as Control
		var original: Dictionary = {}
		for specification in CASES:
			var key := String(specification["name"])
			var button := form.get_node(String(specification["parent"]) + "/" + key + "Button") as Button
			_check(button != null, "authored " + key + " selection exists")
			if button != null:
				original[key] = _geometry(button)
				# The teacher may save new authored coordinates between QA runs.
				# Snapshot the current editor scene, never replace with older values.
				_check(button.size.x > 0.0 and button.size.y > 0.0,
					key + " teacher-authored button has a usable positive hitbox")
		root.add_child(form)
		form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		for specification in CASES:
			var key := String(specification["name"])
			var button := form.get_node(String(specification["parent"]) + "/" + key + "Button") as Button
			if button == null:
				continue
			var art := button.get_node_or_null("ButtonArtwork") as TextureRect
			_check(art != null and art.texture != null,
				key + " has independent editable PNG artwork")
			if art != null and art.texture != null:
				_check(art.texture.resource_path.ends_with("/" + String(specification["image"])),
					key + " uses correct original image")
				_check(art.mouse_filter == Control.MOUSE_FILTER_IGNORE,
					key + " artwork never intercepts teacher's clicks")
				_check(art.stretch_mode in [
					TextureRect.STRETCH_SCALE, TextureRect.STRETCH_KEEP_ASPECT_CENTERED],
					key + " artwork uses an authored scale or aspect-preserving display mode")
				_check(art.position.x >= -4.0 and art.position.y >= -4.0
					and art.size.x <= button.size.x + 4.0
					and art.size.y <= button.size.y + 4.0,
					key + " artwork stays approximately within teacher-authored button hitbox")
			_check(_geometry(button) == original[key] and not button.disabled and button.toggle_mode,
				key + " native button geometry and selection function unchanged at " + str(viewport))
			button.pressed.emit()
			var field := "_selected_mode" if specification["type"] == "mode" else "_selected_difficulty"
			_check(String(form.get(field)) == key and button.button_pressed,
				key + " original selection/click binding still works")
		for specification in CASES:
			var key := String(specification["name"])
			var button := form.get_node(String(specification["parent"]) + "/" + key + "Button") as Button
			if button != null:
				_check(_geometry(button) == original[key],
					key + " position stays unchanged after teacher selections")
		form.queue_free()
		await process_frame
	print("STUDENT MODE & DIFFICULTY ART: %s checks=%d failures=%d" %
		["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for issue in failures:
		printerr("MODE ART FAIL: " + issue)
	quit(0 if failures.is_empty() else 1)


func _geometry(control: Control) -> Dictionary:
	return {"rect": Rect2(control.position, control.size),
		"anchors": Vector4(control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom),
		"rotation": control.rotation, "pivot": control.pivot_offset}


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
