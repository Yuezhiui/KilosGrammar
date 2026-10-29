extends SceneTree

## Isolated Student Setup Continue gate regression (no DB, HTTP, scores or camera).
## Run with Godot 4.7.2:
##   godot --headless --path . --script res://tools/test_student_continue_gate_20261029.gd
##   godot --rendering-driver opengl3 --path . --script res://tools/test_student_continue_gate_20261029.gd
const SCENE_PATH := "res://ui/student/setup/student_setup.tscn"
const GRAY_ART := "res://Components/Student Setup/Redesign/btn_uncontinue.png"
const GREEN_ART := "res://Components/Student Setup/Redesign/btn_continue.png"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const RECT_PATHS := [
    "SetupStage/StudentProfileCard",
    "SetupStage/StudentProfileCard/StudentIdGroup/StudentIdEdit",
    "SetupStage/StudentProfileCard/StudentNameGroup/StudentNameEdit",
    "SetupStage/StudentProfileCard/GradeSectionGroup/GradeSectionEdit",
    "SetupStage/GameSetupCard",
    "SetupStage/GameSetupCard/GameContent/GameStyleGrid/NounButton",
    "SetupStage/GameSetupCard/GameContent/GameStyleGrid/PronounButton",
    "SetupStage/GameSetupCard/GameContent/GameStyleGrid/VerbButton",
    "SetupStage/GameSetupCard/GameContent/GameStyleGrid/AdjectiveButton",
    "SetupStage/GameSetupCard/GameContent/GameStyleGrid/AdverbButton",
    "SetupStage/GameSetupCard/GameContent/LowerSelections/ModeColumn/ModeRow/SecondsButton",
    "SetupStage/GameSetupCard/GameContent/LowerSelections/ModeColumn/ModeRow/LivesButton",
    "SetupStage/GameSetupCard/GameContent/LowerSelections/DifficultyColumn/DifficultyRow/EasyButton",
    "SetupStage/GameSetupCard/GameContent/LowerSelections/DifficultyColumn/DifficultyRow/NormalButton",
    "SetupStage/GameSetupCard/GameContent/LowerSelections/DifficultyColumn/DifficultyRow/HardButton",
    "SetupStage/SetupActions",
    "SetupStage/SetupActions/BackButton",
    "SetupStage/SetupActions/ContinueButton",
    "SetupStage/SetupActions/ContinueButton/ButtonArtwork",
    "SetupStage/SetupActions/ContinueButton/ContinueDisabledArtwork",
]

var checks := 0
var issues: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var packed := load(SCENE_PATH) as PackedScene
    _check(packed != null, "real Student Setup PackedScene loads")
    if packed == null:
        _finish()
        return
    _check(FileAccess.file_exists(GRAY_ART), "user-supplied gray artwork exists")
    for screen_size in SIZES:
        root.size = screen_size
        root.content_scale_size = screen_size
        var form := packed.instantiate() as Control
        _check(form != null, "form instantiates at " + str(screen_size))
        if form == null:
            continue
        var authored := _snapshot(form)
        var student_id_edit := form.get_node("SetupStage/StudentProfileCard/StudentIdGroup/StudentIdEdit") as LineEdit
        var original_focus_style := student_id_edit.get_theme_stylebox("focus")
        var original_normal_style := student_id_edit.get_theme_stylebox("normal")
        var original_caret_color := student_id_edit.get_theme_color("caret_color")
        root.add_child(form)
        form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        form.set_context({"entry_source": "play"})
        await process_frame
        await process_frame
        _check(_snapshot(form) == authored, "all scene-authored button and field rects unchanged after ready " + str(screen_size))
        var factor := minf(float(screen_size.x) / 1280.0, float(screen_size.y) / 720.0)
        var stage := form.get_node("SetupStage") as Control
        _check(stage.scale.is_equal_approx(Vector2.ONE * factor), "only parent stage responsive scale changes " + str(screen_size))
        _check_art_sources(form, str(screen_size))
        _gate(form, false, "blank fresh form " + str(screen_size))
        _check_no_default_selection(form, str(screen_size))
        if screen_size == SIZES[0]:
            await _functional_cases(form)
        _check(_snapshot(form) == authored, "authored rects unchanged across gate transitions " + str(screen_size))
        _check(student_id_edit.get_theme_stylebox("focus") == original_focus_style
            and student_id_edit.get_theme_stylebox("normal") == original_normal_style
            and student_id_edit.get_theme_color("caret_color") == original_caret_color,
            "temporary ID status cue never changes focus outline, field style or caret " + str(screen_size))
        form.queue_free()
        await process_frame
    _finish()


func _snapshot(form: Control) -> Dictionary:
    var result := {}
    for path in RECT_PATHS:
        var control := form.get_node_or_null(path) as Control
        _check(control != null, "authored layout node " + path + " exists")
        if control == null:
            continue
        result[path] = [
            control.position,
            control.size,
            Vector4(control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom),
            control.pivot_offset,
            control.rotation,
            control.scale,
        ]
    return result


func _check_art_sources(form: Control, label: String) -> void:
    var next := form.get("_continue_button") as Button
    _check(next != null, label + " ContinueButton bound")
    if next == null:
        return
    var enabled_art := next.get_node_or_null("ButtonArtwork") as TextureRect
    var gray_art := next.get_node_or_null("ContinueDisabledArtwork") as TextureRect
    _check(enabled_art != null and gray_art != null, label + " both art layers exist")
    if enabled_art == null or gray_art == null:
        return
    _check(enabled_art.texture != null and enabled_art.texture.resource_path == GREEN_ART,
        label + " enabled art remains designed green image")
    _check(gray_art.texture != null and gray_art.texture.resource_path == GRAY_ART,
        label + " disabled art uses NEW btn_uncontinue.png source")
    # The artist-authored clickable button is 246px wide, while BOTH matched
    # PNG layers are 244px wide. Preserve that intentional 2px hit-area margin.
    _check(enabled_art.position == Vector2.ZERO and gray_art.position == Vector2.ZERO
        and enabled_art.size == gray_art.size
        and is_equal_approx(enabled_art.size.y, next.size.y)
        and enabled_art.size.x <= next.size.x
        and next.size.x - enabled_art.size.x <= 2.0,
        label + " matched artwork aligns with authored ContinueButton, including 2px hit-area margin")


func _gate(form: Control, enabled: bool, label: String) -> void:
    var next := form.get("_continue_button") as Button
    _check(next != null, label + " ContinueButton exists")
    if next == null:
        return
    var green := next.get_node_or_null("ButtonArtwork") as CanvasItem
    var gray := next.get_node_or_null("ContinueDisabledArtwork") as CanvasItem
    _check(green != null and gray != null, label + " art layers exist")
    if green == null or gray == null:
        return
    _check(next.disabled == not enabled, label + " Button.disabled is " + str(not enabled))
    _check(green.visible == enabled, label + " green visible iff valid")
    _check(gray.visible == not enabled, label + " gray visible iff invalid")
    _check(next.modulate == Color.WHITE, label + " no dimming contaminates authored artwork")
    var feedback := form.get_node("SetupStage/GameSetupCard/GameContent/ValidationPanel/ValidationLabel") as Label
    _check(not feedback.visible and feedback.text.is_empty(),
        label + " retired red ValidationLabel is fully blank and hidden")


func _check_no_default_selection(form: Control, label: String) -> void:
    _check(String(form.get("_selected_style")).is_empty(), label + " no topic preselected")
    _check(String(form.get("_selected_mode")).is_empty(), label + " no mode preselected")
    _check(String(form.get("_selected_difficulty")).is_empty(), label + " no difficulty preselected")
    for key in ["_style_buttons", "_mode_buttons", "_difficulty_buttons"]:
        var buttons: Dictionary = form.get(key)
        for option in buttons:
            _check(not (buttons[option] as Button).button_pressed,
                label + " " + key + "/" + str(option) + " not visually selected")


func _edit(edit: LineEdit, value: String) -> void:
    edit.text = value
    edit.text_changed.emit(value)


func _fill_profile(form: Control) -> void:
    _edit(form.get("_student_id_edit") as LineEdit, "QA-127")
    _edit(form.get("_name_edit") as LineEdit, "Sample Learner")
    _edit(form.get("_grade_edit") as LineEdit, "Grade 4 - Jade")


func _choose(form: Control, category: String, value: String) -> void:
    var button := ((form.get(category) as Dictionary).get(value)) as Button
    _check(button != null, category + " " + value + " exists")
    if button != null:
        button.pressed.emit()


func _functional_cases(form: Control) -> void:
    var id := form.get("_student_id_edit") as LineEdit
    var name := form.get("_name_edit") as LineEdit
    var grade := form.get("_grade_edit") as LineEdit
    var routes: Array[Dictionary] = []
    form.requested.connect(func(target: String, payload: Dictionary) -> void:
        routes.append({"target": target, "payload": payload.duplicate(true)}))
    _edit(id, "QA-127")
    _gate(form, false, "ID only")
    _edit(name, "Sample Learner")
    _gate(form, false, "ID and name, grade missing")
    _edit(grade, "Grade 4 - Jade")
    _gate(form, false, "all profile fields, all selections missing")
    _choose(form, "_style_buttons", "Noun")
    _gate(form, false, "topic only; mode and difficulty missing")
    _choose(form, "_difficulty_buttons", "Easy")
    _gate(form, false, "difficulty selected but mode missing")
    _choose(form, "_mode_buttons", "Seconds")
    _gate(form, true, "all six fields selected")
    _check((form.get("_style_buttons") as Dictionary)["Noun"].button_pressed
        and (form.get("_mode_buttons") as Dictionary)["Seconds"].button_pressed
        and (form.get("_difficulty_buttons") as Dictionary)["Easy"].button_pressed,
        "all selected buttons visually pressed")
    _edit(grade, "   ")
    _gate(form, false, "grade cleared after valid setup")
    form.call("_continue")
    _check(routes.is_empty(), "grade missing cannot emit game route")
    _edit(grade, "Grade 4 - Jade")
    _gate(form, true, "grade restored")
    _edit(name, "")
    _gate(form, false, "name cleared after valid setup")
    _edit(name, "Sample Learner")
    _gate(form, true, "name restored")
    _edit(id, "")
    _gate(form, false, "ID cleared after valid setup")
    form.call("_continue")
    _check(routes.is_empty(), "ID missing cannot emit game route")
    _fill_profile(form)
    _gate(form, true, "student profile restored")
    form.call("_select_style", "Preposition")
    _gate(form, false, "invalid unlisted grammar topic rejected")
    form.call("_select_style", "Noun")
    _gate(form, true, "supported grammar topic restored")
    form.show_registration_error("ID ALREADY REGISTERED")
    _gate(form, false, "registration conflict forces gray")
    _check(String(form.get("_registration_error")) == "ID ALREADY REGISTERED",
        "true registration conflict remains held internally despite hidden label")
    _check((id.get_theme_color("font_color")).is_equal_approx(
            form.get_script().get_script_constant_map()["CONFLICT_ID_TEXT_COLOR"]),
        "only Student ID's existing inline text color signals true identity conflict")
    form.call("_continue")
    _check(routes.is_empty(), "registration conflict cannot emit game route")
    _edit(grade, "Grade 4 - Rose")
    _gate(form, true, "editing profile clears registration conflict")
    _check(id.get_theme_color("font_color").is_equal_approx(form.get("_default_id_text_color")),
        "Student ID text restores authored color after dispute cleared")
    _edit(grade, "Grade 4 - Jade")
    form.call("_continue")
    _check(routes.size() == 1 and String(routes[0].get("target", "")) == "play_activity",
        "complete valid setup emits exactly one play route")
    if routes.size() == 1:
        var data: Dictionary = routes[0]["payload"]
        _check(data.get("student_id") == "QA-127"
            and data.get("student_name") == "Sample Learner"
            and data.get("grade_section") == "Grade 4 - Jade"
            and data.get("game_style") == "Noun"
            and data.get("game_mode") == "Seconds"
            and data.get("difficulty") == "Easy",
            "game route carries only exact current identity and selections")

    # A complete profile still cannot proceed with a missing topic or difficulty.
    form.set_context({"entry_source": "play", "student_id": "STALE",
        "student_name": "Stale User", "grade_section": "Grade 6",
        "game_style": "Verb", "game_mode": "Lives", "difficulty": "Hard"})
    _gate(form, false, "fresh Play context forcibly clears prior profile and options")
    _check(id.text.is_empty() and name.text.is_empty() and grade.text.is_empty(),
        "fresh Play does not inherit old identity")
    _check_no_default_selection(form, "fresh Play after completed route")
    _fill_profile(form)
    _choose(form, "_mode_buttons", "Lives")
    _choose(form, "_difficulty_buttons", "Hard")
    _gate(form, false, "only grammar topic missing")
    _choose(form, "_style_buttons", "Verb")
    _gate(form, true, "topic added after mode and difficulty")
    form.set_context({"entry_source": "play"})
    _fill_profile(form)
    _choose(form, "_style_buttons", "Adjective")
    _choose(form, "_mode_buttons", "Seconds")
    _gate(form, false, "only difficulty missing")
    _choose(form, "_difficulty_buttons", "Normal")
    _gate(form, true, "difficulty added")

    # Explicit retry is the one route permitted to restore complete prior data.
    form.set_context({"entry_source": "retry", "student_id": "QA-777",
        "student_name": "Retry Learner", "grade_section": "Grade 5 - Pearl",
        "game_style": "Pronoun", "game_mode": "Lives", "difficulty": "Normal"})
    _gate(form, true, "authorized retry prefill with complete fields")
    _check(id.text == "QA-777" and name.text == "Retry Learner"
        and grade.text == "Grade 5 - Pearl"
        and (form.get("_style_buttons") as Dictionary)["Pronoun"].button_pressed
        and (form.get("_mode_buttons") as Dictionary)["Lives"].button_pressed
        and (form.get("_difficulty_buttons") as Dictionary)["Normal"].button_pressed,
        "retry prefill visibly restores the correct exact profile and options")
    form.set_context({"entry_source": "retry", "student_id": "QA-777",
        "student_name": "Retry Learner", "grade_section": "Grade 5 - Pearl",
        "game_style": "Pronoun", "game_mode": "Lives"})
    _gate(form, false, "partial retry prefill omits difficulty")
    form.set_context({"entry_source": "retry", "student_setup_prefill": false,
        "student_id": "SHOULD-NOT-APPEAR", "student_name": "Old Retry Learner",
        "grade_section": "Grade 6", "game_style": "Verb",
        "game_mode": "Lives", "difficulty": "Hard"})
    _gate(form, false, "explicit false prefill overrides stale retry entry source")
    _check(id.text.is_empty() and name.text.is_empty() and grade.text.is_empty(),
        "explicit false retry prefill clears all stale student identity fields")
    _check_no_default_selection(form, "explicit false retry prefill")
    form.set_context({"entry_source": "play", "student_setup_prefill": false})
    _gate(form, false, "new play after retry returns to default gray")

    # Reject an old database callback by matching both edit epoch and exact identity.
    _edit(id, "QA-OLD")
    var old_token := int(form.get("_autofill_epoch"))
    _edit(id, "QA-NEW")
    var stale := {"lookup_confirmed": true, "student_id": "QA-OLD",
        "student_name": "Old Learner", "grade_section": "Grade 2"}
    _check(not bool(form.apply_autofill_result(stale, "id", "QA-OLD", old_token)),
        "stale lookup cannot restore old student's data")
    _check(id.text == "QA-NEW" and name.text.is_empty() and grade.text.is_empty(),
        "stale lookup leaves current incomplete profile untouched")
    _gate(form, false, "late callback leaves Continue gray")

    # Regression: changing Grade & Section must revoke an already pending
    # lookup, even when the delayed reply has the *same* new grade. Prior to
    # this safeguard, such a response could populate the missing profile
    # field and unlock Continue without the teacher approving the lookup.
    form.set_context({"entry_source": "play"})
    _choose(form, "_style_buttons", "Noun")
    _choose(form, "_mode_buttons", "Lives")
    _choose(form, "_difficulty_buttons", "Easy")
    _edit(id, "QA-LATE-ID")
    var stale_id_epoch := int(form.get("_autofill_epoch"))
    _edit(grade, "Grade 3 - Teacher")
    _check(int(form.get("_autofill_epoch")) > stale_id_epoch,
        "grade edit revokes pending ID lookup epoch")
    _check(not bool(form.apply_autofill_result({
        "lookup_confirmed": true, "student_id": "QA-LATE-ID",
        "student_name": "Unapproved Returned Name", "grade_section": "Grade 3 - Teacher"
    }, "id", "QA-LATE-ID", stale_id_epoch)),
        "grade edit rejects late ID response even when grade matches")
    _check(name.text.is_empty() and grade.text == "Grade 3 - Teacher",
        "stale ID reply does not fill missing name or replace teacher's grade")
    _gate(form, false, "late ID reply cannot falsely unlock green")
    form.set_context({"entry_source": "play"})
    _choose(form, "_style_buttons", "Noun")
    _choose(form, "_mode_buttons", "Lives")
    _choose(form, "_difficulty_buttons", "Easy")
    _edit(name, "Pending Name Lookup")
    var stale_name_epoch := int(form.get("_autofill_epoch"))
    _edit(grade, "Grade 4 - Teacher")
    _check(int(form.get("_autofill_epoch")) > stale_name_epoch,
        "grade edit revokes pending name lookup epoch")
    _check(not bool(form.apply_autofill_result({
        "lookup_confirmed": true, "student_id": "QA-EXTERNAL-ID",
        "student_name": "Pending Name Lookup", "grade_section": "Grade 4 - Teacher"
    }, "name", "Pending Name Lookup", stale_name_epoch)),
        "grade edit rejects late name response even when grade matches")
    _check(id.text.is_empty() and name.text == "Pending Name Lookup"
        and grade.text == "Grade 4 - Teacher",
        "stale name reply cannot restore a different student's ID")
    _gate(form, false, "late name reply cannot falsely unlock green")

    # Returning a legitimate student after a previous hold: only an exact,
    # confirmed lookup with matching ID, name and grade may release it.
    form.set_context({"entry_source": "play"})
    _fill_profile(form)
    _choose(form, "_style_buttons", "Noun")
    _choose(form, "_mode_buttons", "Lives")
    _choose(form, "_difficulty_buttons", "Easy")
    _edit(id, "QA-127")
    var returning_epoch := int(form.get("_autofill_epoch"))
    form.show_registration_error("ID ALREADY REGISTERED • CHECK STUDENT DETAILS")
    _gate(form, false, "prior registration conflict holds returning learner")
    _check(not bool(form.apply_autofill_result({
        "lookup_confirmed": true, "student_id": "QA-127",
        "student_name": "Different Learner", "grade_section": "Grade 4 - Jade"
    }, "id", "QA-127", returning_epoch)),
        "mismatched confirmed lookup does not clear prior conflict")
    _gate(form, false, "unrelated learner cannot take returning ID")
    _check(bool(form.apply_autofill_result({
        "lookup_confirmed": true, "student_id": "QA-127",
        "student_name": "Sample Learner", "grade_section": "Grade 4 - Jade"
    }, "id", "QA-127", returning_epoch)),
        "exact confirmed lookup releases prior registration hold")
    _gate(form, true, "verified returning learner may play again")
    _check(id.get_theme_color("font_color").is_equal_approx(form.get("_default_id_text_color")),
        "verified returning learner restores normal ID text color")


func _check(ok: bool, label: String) -> void:
    checks += 1
    if not ok:
        issues.append(label)
        printerr("STUDENT CONTINUE GATE FAIL: " + label)


func _finish() -> void:
    print("STUDENT CONTINUE GATE: ", "PASS" if issues.is_empty() else "FAIL",
        " checks=", checks, " failures=", issues.size(),
        " screens=", SIZES.size())
    quit(0 if issues.is_empty() else 1)
