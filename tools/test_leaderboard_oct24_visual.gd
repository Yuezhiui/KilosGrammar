extends SceneTree

# Pixel/geometry and native-interaction checks for the current approved art.
# No camera, PostgreSQL connection, import, file-dialog writing or student data.
const BOARD := preload("res://ui/secondary/leaderboard/leaderboard.tscn")
const ASSETS := "res://Components/Leaderboard/"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    for path in ["res://Components/Leaderboard/SharedDropdown20261102/dropdown_base.png",
            "res://Components/Credits/Redesign/background1.png",
            "res://Components/Credits/Redesign/HOME.png",
            "res://Components/Leaderboard/NewButtons20261102/IMPORT_transparent.png",
            "res://Components/Leaderboard/NewButtons20261102/EXPORT_transparent.png",
            "res://Components/Leaderboard/NewButtons20261102/DELETE_transparent.png"]:
        _check(ResourceLoader.exists(path), "retained shared/background/action asset exists: " + path)
    var authored_scene := FileAccess.get_file_as_string("res://ui/secondary/leaderboard/leaderboard.tscn")
    _check(not authored_scene.contains("FILTERS.png"), "deleted FILTERS sprite is not referenced by active leaderboard scene")
    for retired in ["ALL STYLES.png", "ALL MODES.png", "ALL DIFFICULTIES.png",
            "NOUN.png", "PRONOUN.png", "VERB.png", "ADJECTIVE.png", "ADVERB.png",
            "seconds.png", "2lives.png", "easy.png", "normal.png", "Hard.png"]:
        _check(not authored_scene.contains(retired), "obsolete per-option dropdown art unreferenced: " + retired)
    for viewport in SIZES:
        root.size = viewport
        root.content_scale_size = viewport
        var scene := BOARD.instantiate() as Control
        # Verify editor-visible appearance BEFORE _ready() runs. A script-only
        # arrow override hides the extra chevron in the game but not in Godot's
        # 2D editor, which caused the user's two-arrow screenshot.
        for filter_name in ["StyleFilter", "ModeFilter", "DifficultyFilter"]:
            var authored_filter := scene.get_node("%" + filter_name) as OptionButton
            _check(authored_filter.has_theme_icon_override("arrow"),
                str(viewport) + " " + filter_name + " hides duplicate arrow in the editor-authored scene")
        root.add_child(scene)
        scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        await process_frame
        await process_frame
        var prefix := str(viewport) + " "
        var full := Rect2(Vector2.ZERO, Vector2(viewport))
        var backdrop := scene.get_node("Background") as TextureRect
        _check(backdrop.texture != null and backdrop.texture.resource_path ==
            "res://Components/Credits/Redesign/background1.png",
            prefix + " current editor-authored background remains the approved Credits artwork")
        _check(backdrop.get_global_rect().is_equal_approx(full), prefix + " background fills viewport")
        var board := scene.get_node("BoardArtwork") as NinePatchRect
        _check(board.texture.resource_path.begins_with("res://Components/")
            and board.texture.resource_path.get_file() == "panel_main.png",
            prefix + " board reuses exact Settings BoardArtwork texture")
        _check(board.patch_margin_left == 74 and board.patch_margin_top == 64
            and board.patch_margin_right == 74 and board.patch_margin_bottom == 64,
            prefix + " board retains Settings nine-patch margins")
        var title := scene.get_node("TitleArt") as TextureRect
        var header := scene.get_node("TableHeaderArt") as TextureRect
        # The decorative cream score body can be separately authored or
        # incorporated into the new BoardArtwork; either is a valid design.
        var frame := scene.get_node_or_null("TableBodyArt") as TextureRect
        var content := scene.get_node("TableContent") as Control
        var empty := scene.get_node("%EmptyMessage") as Label
        _check(_leaderboard_asset(_atlas_source(title.texture), "LEADERBOARD.png"), prefix + " exact title pixels from user")
        var score_area := frame.get_global_rect() if frame != null else content.get_global_rect()
        _check(_overlap_fraction(empty.get_global_rect(), score_area) > 0.88,
            prefix + " empty state remains inside score table, not at screen origin")
        _check(_overlap_fraction(content.get_global_rect(), score_area) > 0.9,
            prefix + " rows render inside table, not behind buttons")
        _check(board.get_global_rect().end.x <= viewport.x + 2.0 and board.get_global_rect().position.x >= -2.0,
            prefix + " board centered inside full screen")
        _check(title.get_global_rect().end.x <= viewport.x + 2.0 and title.get_global_rect().position.x >= -2.0,
            prefix + " title follows responsive stage")
        _check(header.get_global_rect().end.y < score_area.end.y,
            prefix + " real column header stays above rows")
        var filter_buttons: Array[Control] = []
        for setting in ["StyleFilter", "ModeFilter", "DifficultyFilter"]:
            var selector := scene.get_node("%" + setting) as OptionButton
            filter_buttons.append(selector)
            _check(selector.focus_mode == Control.FOCUS_ALL and selector.is_visible_in_tree(),
                prefix + setting + " remains a keyboard-accessible native dropdown")
            _check(_inside(selector.get_global_rect(), full, 3.0),
                prefix + setting + " in viewport")
        for selector in filter_buttons:
            var image_style := selector.get_theme_stylebox("normal") as StyleBoxTexture
            _check(image_style != null and image_style.texture != null
                and _atlas_source(image_style.texture).ends_with("SharedDropdown20261102/dropdown_base.png"),
                prefix + " " + selector.name + " uses shared original wood texture")
            _check(selector.get_theme_color("font_color").a > 0.95,
                prefix + " " + selector.name + " renders native text over wood")
            var arrow := selector.get_theme_icon("arrow")
            _check(arrow != null and arrow.get_size() == Vector2(2, 2)
                and arrow.get_image().get_pixel(0, 0).a < 0.01,
                prefix + " " + selector.name + " hides duplicate arrow")
            _check(selector.get_theme_font_size("font_size") >= 14,
                prefix + " " + selector.name + " keeps readable native dropdown font")
            _check(selector.get_item_text(selector.selected).strip_edges().length() > 0,
                prefix + " " + selector.name + " has live selected caption")
            _check(image_style != null and image_style.texture is AtlasTexture,
                prefix + " " + selector.name + " reuses atlas-backed shared wood")
        for obsolete in ["FiltersToggle", "FiltersArt", "MoreFiltersPanel", "CloseMoreFilters"]:
            _check(scene.find_child(obsolete, true, false) == null,
                prefix + " obsolete FILTERS/popover node physically absent: " + obsolete)
        _check(scene.find_child("MinigameFilter", true, false) == null
            and scene.find_child("DownloadButton", true, false) == null,
            prefix + " minigame and filtered CSV hidden controls removed completely")
        _check(scene.has_method("set_minigame_filter") and scene.has_method("_validate_import_xlsx"),
            prefix + " hidden minigame filtering and XLSX import verification remain callable")
        _check(filter_buttons[0].get_global_rect().end.y < header.get_global_rect().position.y,
            prefix + " reference keeps one clean filter row above the table")
        var main: Array[Control] = []
        for pair in [
                ["BackButton", "HOME.png"], ["ImportCsvButton", "IMPORT_transparent.png"],
                ["ExportCsvButton", "EXPORT_transparent.png"], ["DeleteAllButton", "DELETE_transparent.png"]]:
            var button := scene.get_node("%" + pair[0]) as Button
            var image_style := button.get_theme_stylebox("normal") as StyleBoxTexture
            if pair[0] == "BackButton":
                # The approved HOME artwork is a separately draggable child;
                # the native button uses an intentionally transparent skin.
                var art := button.get_node_or_null("Artwork") as TextureRect
                _check(button.get_theme_stylebox("normal") is StyleBoxEmpty
                    and art != null and art.texture != null
                    and art.texture.resource_path == "res://Components/Credits/Redesign/HOME.png"
                    and art.mouse_filter == Control.MOUSE_FILTER_IGNORE,
                    prefix + " BackButton uses the editor-adjustable HOME artwork with a transparent hit target")
            else:
                _check(image_style != null and _leaderboard_asset(_atlas_source(image_style.texture), pair[1]),
                    prefix + pair[0] + " uses user provided transparent PNG")
            if image_style != null and image_style.texture != null and pair[0] != "BackButton":
                var img := image_style.texture.get_image()
                var corners := [Vector2i(0, 0), Vector2i(img.get_width() - 1, 0),
                    Vector2i(0, img.get_height() - 1), Vector2i(img.get_width() - 1, img.get_height() - 1)]
                for sample in corners:
                    var col := img.get_pixelv(sample)
                    _check(col.a < 0.02, prefix + pair[0]
                        + " cropped action artwork has transparent edge corner (no black shadow square)")
                _check(button.get_theme_stylebox("hover") == image_style
                    and button.get_theme_stylebox("pressed") == image_style,
                    prefix + pair[0] + " hover and pressed preserve PNG without opaque black overlay")
            _check(_inside(button.get_global_rect(), full, 3.0), prefix + pair[0] + " in viewport")
            _check(button.is_visible_in_tree() and button.focus_mode == Control.FOCUS_ALL,
                prefix + pair[0] + " accessible native input")
            main.append(button)
        _check(bool(scene.call("set_minigame_filter", "CATCH THE WORD"))
            and bool(scene.call("set_minigame_filter", "BALLOON POPPING"))
            and bool(scene.call("set_minigame_filter", "HUMAN PLANE")),
            prefix + " all three supported activities stay selectable from host API without a hidden control")
        _check(bool(scene.call("set_minigame_filter", "Legacy")),
            prefix + " hidden host API still accepts historical Legacy records without exposing them as a menu option")
        _check(bool(scene.call("set_minigame_filter", "ALL MINIGAMES")),
            prefix + " historical compatibility selection safely resets to all")
        for i in range(1, main.size()):
            for j in range(i + 1, main.size()):
                _check(not main[i].get_global_rect().intersects(main[j].get_global_rect()),
                    prefix + " import/export/delete actions never overlap")
        _check(scene.find_child("MinigameFilter", true, false) == null
            and scene.find_child("DownloadButton", true, false) == null,
            prefix + " removed popup cannot intercept clicks or resurrect unused controls")
        _check(scene.get_node_or_null("DecorativePot") == null
            and scene.get_node_or_null("DecorativeStar") == null
            and scene.get_node_or_null("DecorativeBooks") == null,
            prefix + " obsolete décor removed; complete new title/art has original composition")
        var style := scene.get_node("%StyleFilter") as OptionButton
        var normal_style := style.get_theme_stylebox("normal") as StyleBoxTexture
        _check(normal_style != null and _atlas_source(normal_style.texture).ends_with("SharedDropdown20261102/dropdown_base.png"),
            prefix + " default filter uses shared wood background")
        _check(style.get_theme_color("font_color").a > 0.95,
            prefix + " native text is visible over shared wood")
        var expected_counts := [6, 3, 4]
        for k in range(filter_buttons.size()):
            var control := filter_buttons[k] as OptionButton
            var base_style := control.get_theme_stylebox("normal") as StyleBoxTexture
            _check(control.item_count == expected_counts[k],
                prefix + " selectable topic/mode/difficulty options preserved")
            for chosen in range(control.item_count):
                control.select(chosen)
                control.item_selected.emit(chosen)
                var chosen_style := control.get_theme_stylebox("normal") as StyleBoxTexture
                _check(chosen_style == base_style and control.get_item_text(control.selected).length() > 0,
                    prefix + " native selected caption and unchanged shared wood " + str(control.name) + "[" + str(chosen) + "]")
                _check(control.get_theme_color("font_color").a > 0.95,
                    prefix + " selected caption remains visible")
                _check(control.get_theme_icon("arrow").get_image().get_pixel(0, 0).a < 0.01,
                    prefix + " shared PNG arrow remains single")
            control.select(0)
            control.item_selected.emit(0)
        for obsolete_option in ["INTERJECTION", "PREPOSITION", "CONJUNCTION", "QUIZ", "ACTIVITY"]:
            for control in filter_buttons:
                var present := false
                for i in (control as OptionButton).item_count:
                    present = present or (control as OptionButton).get_item_text(i).to_upper() == obsolete_option
                _check(not present, prefix + " removed obsolete option " + obsolete_option)
        for button_name in ["ImportCsvButton", "ExportCsvButton", "DeleteAllButton"]:
            var decorated := scene.get_node("%" + button_name) as Button
            var texture_style := decorated.get_theme_stylebox("normal") as StyleBoxTexture
            _check(texture_style != null and not decorated.has_theme_stylebox_override("focus"),
                prefix + " " + button_name + " uses clipped PNG styling, no black focus halo")
        var authored := board.position
        board.position += Vector2(11.0, 4.0)
        await process_frame
        _check(board.position.is_equal_approx(authored + Vector2(11.0, 4.0)),
            prefix + " native board remains independently movable, no per-frame script snapping")
        scene.queue_free()
        await process_frame
    for reason in failures:
        printerr("LEADERBOARD OCT24 QA FAIL: ", reason)
    print("LEADERBOARD OCT24 DESIGN: %s (%d checks, %d failures)" %
        ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
    quit(0 if failures.is_empty() else 1)

func _atlas_source(texture: Texture2D) -> String:
    if texture is AtlasTexture:
        return (texture as AtlasTexture).atlas.resource_path
    return texture.resource_path if texture != null else ""

func _leaderboard_asset(path: String, filename: String) -> bool:
    return path.begins_with(ASSETS) and path.get_file() == filename and ResourceLoader.exists(path)

func _find_asset(folder: String, filename: String) -> bool:
    var directory := DirAccess.open(folder)
    if directory == null:
        return false
    directory.list_dir_begin()
    var item := directory.get_next()
    while not item.is_empty():
        var candidate := folder.path_join(item)
        if directory.current_is_dir():
            if _find_asset(candidate, filename):
                directory.list_dir_end()
                return true
        elif item == filename and ResourceLoader.exists(candidate):
            directory.list_dir_end()
            return true
        item = directory.get_next()
    directory.list_dir_end()
    return false

func _overlap_fraction(a: Rect2, b: Rect2) -> float:
    return a.intersection(b).get_area() / maxf(a.get_area(), 1.0)

func _inside(inner: Rect2, outer: Rect2, tolerance: float) -> bool:
    return inner.position.x >= outer.position.x - tolerance \
        and inner.position.y >= outer.position.y - tolerance \
        and inner.end.x <= outer.end.x + tolerance \
        and inner.end.y <= outer.end.y + tolerance

func _check(condition: bool, description: String) -> void:
    checks += 1
    if not condition:
        failures.append(description)
