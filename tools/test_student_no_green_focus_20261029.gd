extends SceneTree
## Focus styling QA. Never edits the teacher-authored Student Setup geometry.
const SCENE := preload("res://ui/student/setup/student_setup.tscn")
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const FIELDS := [
    "SetupStage/StudentProfileCard/StudentIdGroup/StudentIdEdit",
    "SetupStage/StudentProfileCard/StudentNameGroup/StudentNameEdit",
    "SetupStage/StudentProfileCard/GradeSectionGroup/GradeSectionEdit",
]
var checks := 0
var errors: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    for resolution in SIZES:
        root.size = resolution
        root.content_scale_size = resolution
        var form := SCENE.instantiate() as Control
        var rects := {}
        for path in FIELDS:
            var field := form.get_node(path) as LineEdit
            rects[path] = [field.position, field.size,
                Vector4(field.anchor_left, field.anchor_top, field.anchor_right, field.anchor_bottom)]
            _check(field.has_theme_stylebox_override("focus"),
                "authored focus style exists " + path)
            _check(field.get_theme_stylebox("focus") is StyleBoxEmpty,
                "no green focus rectangle " + path)
            _check(field.get_theme_color("caret_color").is_equal_approx(Color(0.2, 0.16, 0.12, 1)),
                "dark readable typing cursor " + path)
        root.add_child(form)
        form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        await process_frame
        await process_frame
        for path in FIELDS:
            var field := form.get_node(path) as LineEdit
            field.grab_focus()
            await process_frame
            _check(field.has_focus(), "field still accepts keyboard focus: " + path)
            _check(field.get_theme_stylebox("focus") is StyleBoxEmpty,
                "focus remains invisible while actively typing: " + path)
            field.text = "Teacher Edit"
            field.text_changed.emit(field.text)
            await process_frame
            var current := [field.position, field.size,
                Vector4(field.anchor_left, field.anchor_top, field.anchor_right, field.anchor_bottom)]
            _check(current == rects[path], "authored field geometry unchanged: " + path)
        form.queue_free()
        await process_frame
    print("STUDENT NO GREEN FOCUS: %s checks=%d failures=%d" %
        ["PASS" if errors.is_empty() else "FAIL", checks, errors.size()])
    for error in errors:
        printerr("FOCUS QA: " + error)
    quit(0 if errors.is_empty() else 1)


func _check(ok: bool, explanation: String) -> void:
    checks += 1
    if not ok:
        errors.append(explanation)
