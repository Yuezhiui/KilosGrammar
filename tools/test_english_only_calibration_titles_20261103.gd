extends SceneTree

## Read-only language/layout QA. Never mounts the scene, starts a camera,
## opens an audio device, connects to PostgreSQL, or writes user data.
const HUMAN_PLANE_SCENE := "res://ui/vision/calibration/human_plane_calibration.tscn"
const SOLO_SCRIPT := "res://ui/vision/calibration/calibration.gd"
const NEUTRAL_ART := "res://Components/Gameplay/Balloon Popping/Art/reference/prompt_blank.png"
const ENGLISH_HEADINGS := {
	"Center": "STAY IN THE CENTER",
	"Right": "STAY ON THE RIGHT",
	"Left": "STAY ON THE LEFT",
}
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)


func _run() -> void:
	var source := FileAccess.get_file_as_string(SOLO_SCRIPT)
	_check(not source.is_empty(), "single-player calibration controller is readable")
	_check(source.contains('_set_live_instruction("PLEASE STAND A LITTLE STEADIER IN CENTER.")'),
		"unstable-pose instruction retains clear English-only wording")
	_check(not source.contains('PLEASE STAND A LITTLE STEADIER IN CENTER.\\n'),
		"single-player fallback contains no second-language continuation")
	var scene_source := FileAccess.get_file_as_string(HUMAN_PLANE_SCENE)
	_check(not scene_source.is_empty(), "Human Plane scene is readable")
	for retired in ["STAY IN THE CENTER.png", "STAY ON THE RIGHT.png", "STAY OF THE LEFT.png"]:
		_check(not scene_source.contains(retired),
			"Human Plane never imports a bilingual source texture: " + retired)
	_check(scene_source.contains(NEUTRAL_ART),
		"Human Plane loads one reusable English-neutral blank artwork")
	var packed := load(HUMAN_PLANE_SCENE) as PackedScene
	_check(packed != null, "Human Plane calibration scene parses")
	if packed != null:
		var scene := packed.instantiate() as Control
		_check(scene != null, "Human Plane scene instantiates without mounting its camera")
		if scene != null:
			for zone in ENGLISH_HEADINGS:
				var node_path: String = "TutorialStage/Directions/ArtTitle" + String(zone)
				var title := scene.get_node_or_null(node_path) as TextureRect
				_check(title != null, "existing editor-authored title node retained: " + zone)
				if title == null:
					continue
				_check(title.position.is_equal_approx(Vector2(320, 28))
					and title.size.is_equal_approx(Vector2(640, 148)),
					zone + " preserves original title position and geometry")
				_check(not title.visible, zone + " preserves initial hidden state")
				_check(title.texture == null, zone + " never displays a baked bilingual texture")
				var plaque := title.get_node_or_null("EnglishPlaque") as NinePatchRect
				_check(plaque != null and plaque.texture != null
					and plaque.texture.resource_path == NEUTRAL_ART,
					zone + " displays reusable English-neutral plaque")
				var heading := title.get_node_or_null("EnglishHeading") as Label
				_check(heading != null and heading.text == ENGLISH_HEADINGS[zone],
					zone + " uses correctly authored English-only editable heading")
				if heading != null:
					var font := heading.get_theme_font("font")
					var size := heading.get_theme_font_size("font_size")
					var rendered := font.get_string_size(heading.text,
						HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
					# Anchor-based child sizes are resolved only after mounting a
					# Control. Use the authored 640px parent less 18px side insets;
					# don't enter _ready() just to calculate text geometry (it
					# would initialize the real camera).
					var available_width := title.size.x - 36.0
					_check(rendered <= available_width - 2.0,
						zone + " English wording fits authored plaque width (%.1f <= %.1f)" % [rendered, available_width - 2.0])
			scene.free()
	print("ENGLISH CALIBRATION TITLES QA: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	for reason in failures:
		printerr("ENGLISH CALIBRATION TITLE FAIL: ", reason)
	quit(0 if failures.is_empty() else 1)
