extends SceneTree

## Read-only geometry regression for teacher-edited Student Setup after
## ExistingScoreDialog and the three SOON topics were removed. Snapshot the
## latest authored coordinates at runtime: the teacher actively adjusts them.
## Never opens a database/camera or modifies the production .tscn.
## Run: godot --headless --path . --script res://tools/test_student_setup_survivor_layout_20261029.gd
const SCENE := preload("res://ui/student/setup/student_setup.tscn")
const STYLES := ["NounButton", "PronounButton", "VerbButton",
	"AdjectiveButton", "AdverbButton"]
const REMOVED := ["PrepositionButton", "ConjunctionButton", "InterjectionButton"]
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var assertions := 0
var issues: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for target in SIZES:
		root.size = target
		root.content_scale_size = target
		# Check the authored values before _ready() or any responsive scaling.
		var scene := SCENE.instantiate() as Control
		var grid := scene.get_node_or_null("SetupStage/GameSetupCard/GameContent/GameStyleGrid") as Control
		_check(grid != null, "GameStyleGrid authored at " + str(target))
		if grid == null:
			scene.free()
			continue
		_check(grid.get_child_count() == 5, "Only five active grammar buttons, no ghost nodes")
		var before := _snapshot(grid, "authored before ready " + str(target))
		_check(scene.get_node_or_null("ExistingScoreDialog") == null,
			"Retired ExistingScoreDialog absent from PackedScene")
		for node_name in REMOVED:
			_check(scene.find_child(node_name, true, false) == null,
				"Retired " + node_name + " absent from PackedScene")
		root.add_child(scene)
		scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await process_frame
		await process_frame
		var stage := scene.get_node_or_null("SetupStage") as Control
		var factor := minf(float(target.x) / 1280.0, float(target.y) / 720.0)
		_check(stage != null and stage.scale.is_equal_approx(Vector2.ONE * factor),
			"Responsive scaling is confined to parent SetupStage " + str(target))
		_check(_same_snapshot(before, _snapshot(grid, "after ready " + str(target))),
			"All five local positions/sizes/anchors stay unchanged after _ready at " + str(target))
		# Context transitions and user selection must not reset teacher-adjusted
		# geometry or resurrect deleted elements.
		scene.set_context({"entry_source": "play", "student_setup_prefill": false})
		var noun := grid.get_node_or_null("NounButton") as Button
		if noun != null:
			noun.pressed.emit()
		scene.set_context({"entry_source": "tutorial", "guided_tutorial": true,
			"activity": "Balloon Popping", "student_setup_prefill": false})
		await process_frame
		_check(_same_snapshot(before, _snapshot(grid, "after context " + str(target))),
			"All five authored button coordinates survive selection/context changes at " + str(target))
		_check(not scene.has_node("ExistingScoreDialog"),
			"Context changes do not resurrect removed score dialog")
		for name in REMOVED:
			_check(grid.get_node_or_null(name) == null,
				"Context changes do not resurrect removed " + name)
		scene.queue_free()
		await process_frame
		_check(not is_instance_valid(scene), "Scene released cleanly after " + str(target))
	print("STUDENT SETUP SURVIVOR LAYOUT: %s checks=%d failures=%d screens=%d" %
		["PASS" if issues.is_empty() else "FAIL", assertions, issues.size(), SIZES.size()])
	for issue in issues:
		printerr("STUDENT LAYOUT FAIL: " + issue)
	quit(0 if issues.is_empty() else 1)


func _snapshot(grid: Control, phase: String) -> Dictionary:
	var result := {}
	for name in STYLES:
		var button := grid.get_node_or_null(name) as Button
		_check(button != null, phase + ": surviving " + name + " present")
		if button == null:
			continue
		_check(button.size.x > 0 and button.size.y > 0 and button.position.x >= 0
			and button.position.y >= 0,
			phase + ": latest user-authored " + name + " has a valid local rect: "
			+ str(Rect2(button.position, button.size)))
		_check(button.owner != null and not button.disabled and button.toggle_mode,
			phase + ": " + name + " remains editor-owned playable toggle")
		var art := button.get_node_or_null("ButtonArtwork") as TextureRect
		_check(art != null and art.texture != null and art.texture.resource_path.to_lower().contains(name.trim_suffix("Button").to_lower()),
			phase + ": " + name + " retains original editable topic PNG")
		result[name] = {
			"rect": Rect2(button.position, button.size),
			"anchors": Vector4(button.anchor_left, button.anchor_top, button.anchor_right, button.anchor_bottom),
			"pivot": button.pivot_offset,
			"rotation": button.rotation,
		}
	return result


func _same_snapshot(before: Dictionary, after: Dictionary) -> bool:
	if before.size() != after.size():
		return false
	for key in before:
		if not after.has(key) or before[key] != after[key]:
			return false
	return true


func _check(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		issues.append(label)
