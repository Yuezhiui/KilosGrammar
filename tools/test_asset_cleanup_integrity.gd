extends SceneTree

## Read-only post-cleanup integrity audit. Does not launch MainMenu._ready(),
## contact PostgreSQL, click destructive controls, change assets or write CSVs.
## Godot --headless --path . --script res://tools/test_asset_cleanup_integrity.gd
## Optional: compare serialized refs with `git show HEAD:<resource>` if git exists.

const LEADERBOARD := "res://ui/secondary/leaderboard.tscn"
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080)]
const SCREEN_FIXTURES := [
	"res://main_menu.tscn", "res://ui/secondary/settings.tscn",
	"res://ui/secondary/results.tscn",
	"res://ui/student/student_setup.tscn", "res://ui/play/pause.tscn",
	"res://ui/tutorial/tutorial_home.tscn", LEADERBOARD
]
const MODAL_PNG_BUTTONS := {
	"DeleteFirstOverlay/FirstCancelButton": "cancel.png",
	"DeleteFirstOverlay/FirstContinueButton": "show final conf.png",
	"DeleteFinalOverlay/ConfirmPanel/FinalCancelButton": "cancel.png",
	"DeleteFinalOverlay/ConfirmPanel/FinalDeleteButton": "permanent delete if add_.png"
}
const ACTION_BUTTONS := ["BackButton", "ImportCsvButton", "ExportCsvButton", "DeleteAllButton"]
const REQUIRED_MODAL_ART := [
	"DeleteFirstOverlay/BoardArtwork", "DeleteFirstOverlay/WarningHeader",
	"DeleteFinalOverlay/ConfirmPanel", "DeleteFinalOverlay/HeaderArtwork",
	"DeleteFinalOverlay/ConfirmPanel/TypedFieldArtwork"
]

var checks := 0
var failures: Array[String] = []
var scene_files: Array[String] = []
var missing_paths: Array[String] = []
var missing_identifiers: Array[String] = []
var orphan_declarations: Array[String] = []
var baseline_added: Array[String] = []
var baseline_removed: Array[String] = []
var unorganized_pngs: Array[String] = []
var component_groups: Dictionary = {}
var loaded_scenes := 0
var discovered_scenes := 0
var loaded_resources := 0
var texture_dependencies := 0
var baseline_comparisons := 0
var _missing_lookup: Dictionary = {}
var _id_lookup: Dictionary = {}
var _orphan_lookup: Dictionary = {}
var _verified_art: Dictionary = {}
var checked_renderables := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var all_files: Array[String] = []
	_walk("res://", all_files)
	all_files.sort()
	_check_components_png_organization(all_files)
	for path in all_files:
		if not path.ends_with(".tscn") and not path.ends_with(".tres"):
			continue
		if path.ends_with(".tscn"):
			discovered_scenes += 1
		scene_files.append(path)
		var content := FileAccess.get_file_as_string(path)
		_check(not content.is_empty(), "Nonempty serialized resource: " + path)
		_inspect_serialized(path, content)
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		_check(resource != null, "Godot loads scene/resource: " + path)
		if resource is PackedScene:
			loaded_scenes += 1
			var instance := (resource as PackedScene).instantiate()
			_check(instance != null, "Scene instantiates without adding side effects: " + path)
			if instance != null:
				_audit_loaded_art(instance, path)
				instance.free() # Do not run script _ready() on all application scenes.
		elif resource != null:
			loaded_resources += 1
	_check(loaded_scenes == discovered_scenes and loaded_scenes >= 20 and loaded_resources >= 1,
		"Every discovered Godot .tscn parses and instantiates after inlining reusable 3D geometry (found %d scenes/%d resources)" % [
		loaded_scenes, loaded_resources])
	_check("res://ui/secondary/credits.tscn" in all_files,
		"Explicitly restored Credits screen stays intact with its dependencies")
	_check(texture_dependencies >= 143,
		"Cleanup retains at least 143 referenced, decodable source textures (found %d)" % texture_dependencies)
	for fixture in SCREEN_FIXTURES:
		var scene := ResourceLoader.load(fixture, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		_check(scene != null, "Representative screen is a valid PackedScene: " + fixture)
		if scene != null:
			var inactive := scene.instantiate()
			_check(inactive is Control, "Representative screen root is Control: " + fixture)
			if inactive != null:
				_check_static_screen(inactive, fixture)
				inactive.free()
	await _exercise_modal_geometry()
	_sort_report()
	print("ASSET_CLEANUP SCENES=%d TRES=%d TEXTURE_DEPS=%d RENDERABLES=%d CHECKS=%d" % [
		loaded_scenes, loaded_resources, texture_dependencies, checked_renderables, checks])
	print("ASSET_CLEANUP MISSING_PATHS=%d %s" % [missing_paths.size(), str(missing_paths)])
	print("ASSET_CLEANUP MISSING_REFERENCES=%d %s" % [missing_identifiers.size(), str(missing_identifiers)])
	print("ASSET_CLEANUP UNUSED_DECLARATIONS=%d %s" % [orphan_declarations.size(), str(orphan_declarations)])
	print("ASSET_CLEANUP PNG_OUTSIDE_COMPONENTS=%d %s" % [unorganized_pngs.size(), str(unorganized_pngs)])
	print("ASSET_CLEANUP COMPONENT_GROUPS=%s" % str(component_groups.keys()))
	print("ASSET_CLEANUP BASELINE_COMPARE=%d ADDED=%d %s REMOVED=%d %s" % [
		baseline_comparisons, baseline_added.size(), str(baseline_added),
		baseline_removed.size(), str(baseline_removed)])
	for error in failures:
		printerr("ASSET CLEANUP FAIL: ", error)
	print("ASSET CLEANUP INTEGRITY: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _walk(folder: String, result: Array[String]) -> void:
	var directory := DirAccess.open(folder)
	if directory == null:
		_fail("Unable to read resource directory " + folder)
		return
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		if filename != ".godot" and filename != ".git" and not filename.begins_with("."):
			var full := folder.path_join(filename)
			if directory.current_is_dir():
				_walk(full, result)
			else:
				result.append(full)
		filename = directory.get_next()
	directory.list_dir_end()


func _check_components_png_organization(all_files: Array[String]) -> void:
	# Keep source assets centralized. Screenshots from prior test runs are
	# review artifacts rather than runtime UI; they can stay in showcase/.
	# Godot's icon.svg is not a PNG and is intentionally left untouched.
	for path in all_files:
		if not path.to_lower().ends_with(".png"):
			continue
		if path.begins_with("res://Components/"):
			var relative: String = path.trim_prefix("res://Components/")
			var sections := relative.split("/")
			if sections.size() >= 2:
				component_groups[sections[0]] = true
			else:
				unorganized_pngs.append(path + " (no screen-specific folder)")
		elif not _is_optional_qa_image(path):
			unorganized_pngs.append(path)
	_check(component_groups.size() >= 3,
		"Components organizes UI PNGs in at least three separate screen/functional groups")
	_check(unorganized_pngs.is_empty(),
		"All production PNG assets live under Components/<screen>/; found %d outside" % unorganized_pngs.size())


func _is_optional_qa_image(path: String) -> bool:
	if path.begins_with("res://showcase/") or path == "res://icon.png":
		return true
	var filename := path.get_file().to_lower()
	# Review captures have explicit QA naming; don't exempt source assets just
	# because they happen to live in tools/, ui/, or a top-level image folder.
	return filename.begins_with("qa_") or filename.begins_with("_review_")


func _inspect_serialized(path: String, content: String) -> void:
	var externals: Dictionary = {}
	var subs: Dictionary = {}
	var ext_used: Dictionary = {}
	var sub_used: Dictionary = {}
	var dependencies: Dictionary = {}
	for line in content.split("\n"):
		if line.begins_with("[ext_resource "):
			# `uid="..."` precedes `id="..."`; match whole attribute so an
			# ext-resource UID is never mistaken for the local ExtResource ID.
			var id := _capture(line, '(?:^|\\s)id="([^"]+)"')
			var target := _capture(line, 'path="([^"]+)"')
			if not id.is_empty():
				externals[id] = target
			if target.begins_with("res://"):
				dependencies[target] = true
				if not FileAccess.file_exists(target) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target)):
					_report_once(_missing_lookup, missing_paths, path + " -> " + target)
					_fail("Missing external asset: " + path + " -> " + target)
				elif target.is_empty():
					_report_once(_id_lookup, missing_identifiers, path + " -> empty path for " + id)
		elif line.begins_with("[sub_resource "):
			var id := _capture(line, '(?:^|\\s)id="([^"]+)"')
			if not id.is_empty():
				subs[id] = true
	for match_item in _matches(content, 'ExtResource\\("([^"]+)"\\)'):
		ext_used[match_item] = true
		if not externals.has(match_item):
			_report_once(_id_lookup, missing_identifiers, path + " -> undefined ExtResource(" + match_item + ")")
			_fail("Missing ExtResource id: " + path + " -> " + match_item)
	for match_item in _matches(content, 'SubResource\\("([^"]+)"\\)'):
		sub_used[match_item] = true
		if not subs.has(match_item):
			_report_once(_id_lookup, missing_identifiers, path + " -> undefined SubResource(" + match_item + ")")
			_fail("Missing SubResource id: " + path + " -> " + match_item)
	for id in externals:
		if not ext_used.has(id):
			_report_once(_orphan_lookup, orphan_declarations, path + " -> unreferenced ext_resource " + str(id))
	for id in subs:
		if not sub_used.has(id):
			_report_once(_orphan_lookup, orphan_declarations, path + " -> unreferenced sub_resource " + str(id))
	for asset_path in dependencies:
		if _texture_ext(String(asset_path)):
			texture_dependencies += 1
			var texture := ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_IGNORE)
			_check(texture is Texture2D, "Texture dependency decodes: " + path + " -> " + asset_path)
			if texture is Texture2D:
				_check((texture as Texture2D).get_size().x > 0.0
					and (texture as Texture2D).get_size().y > 0.0,
					"Texture dependency has pixels: " + asset_path)
	_compare_git_baseline(path, dependencies)


func _compare_git_baseline(path: String, current: Dictionary) -> void:
	var output: Array = []
	var target := path.trim_prefix("res://")
	var exit_code := OS.execute("git", ["show", "HEAD:" + target], output, true)
	if exit_code != 0 or output.is_empty():
		return # Newly created resource or Git unavailable; don't invent baseline.
	baseline_comparisons += 1
	var base: Dictionary = {}
	for line in str(output[0]).split("\n"):
		if line.begins_with("[ext_resource "):
			var old_path := _capture(line, 'path="([^"]+)"')
			if old_path.begins_with("res://"):
				base[old_path] = true
	for dep in current:
		if not base.has(dep):
			baseline_added.append(target + " -> " + str(dep))
	for dep in base:
		if not current.has(dep):
			baseline_removed.append(target + " -> " + str(dep))


func _capture(line: String, pattern: String) -> String:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return ""
	var found := regex.search(line)
	return found.get_string(1) if found != null else ""


func _matches(content: String, pattern: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	if regex.compile(pattern) == OK:
		for item in regex.search_all(content):
			result.append(item.get_string(1))
	return result


func _texture_ext(path: String) -> bool:
	return path.to_lower().get_extension() in ["png", "webp", "jpg", "jpeg", "svg", "bmp", "tga"]


func _audit_loaded_art(node: Node, owner_scene: String) -> void:
	# Validate editor-bound art even when the whole screen is never mounted.
	# A texture-less runtime placeholder is legitimate; but a bound PNG must
	# still contain real image data and not a transparent/invalid replacement.
	var tex: Texture2D = null
	if node is TextureRect:
		tex = (node as TextureRect).texture
	elif node is NinePatchRect:
		tex = (node as NinePatchRect).texture
	elif node is Sprite2D:
		tex = (node as Sprite2D).texture
	elif node is TextureButton:
		tex = (node as TextureButton).texture_normal
	if tex != null:
		checked_renderables += 1
		_check(_pixels_present(tex),
			"Editor image retains renderable pixels: %s :: %s" % [owner_scene, node.name])
	if node is BaseButton:
		var button := node as BaseButton
		for state in ["normal", "disabled"]:
			var style := button.get_theme_stylebox(state)
			if style is StyleBoxTexture:
				checked_renderables += 1
				_check(_pixels_present((style as StyleBoxTexture).texture),
					"PNG-backed editor button retains %s artwork: %s :: %s" % [
						state, owner_scene, node.name])
	for child in node.get_children():
		_audit_loaded_art(child, owner_scene)


func _check_static_screen(scene: Node, path: String) -> void:
	if path == LEADERBOARD:
		for obsolete in ["DownloadButton", "TransferStatusPanel", "TransferStatus", "MinigameFilter",
				"FiltersToggle", "FiltersArt", "MoreFiltersPanel", "CloseMoreFilters"]:
			_check(scene.find_child(obsolete, true, false) == null,
				"Deleted hidden/legacy leaderboard node stays physically absent: " + obsolete)
		_check(scene.has_method("set_transfer_status") and scene.has_method("set_transfer_pending")
			and scene.has_method("request_filtered_csv_export"),
			"Removed UI nodes do not remove CSV/status host compatibility APIs")
		for key in MODAL_PNG_BUTTONS:
			var button := scene.get_node_or_null(key) as Button
			_check(button != null, "Delete modal serialized button exists: " + key)
			if button != null:
				_check(_source_path(_button_texture(button)).ends_with(str(MODAL_PNG_BUTTONS[key])),
					"Delete button retains original PNG: " + key)
				_check(_pixels_present(_button_texture(button)),
					"Delete button asset still renders nontransparent pixels: " + key)
		for key in REQUIRED_MODAL_ART:
			var image := scene.get_node_or_null(key) as TextureRect
			_check(image != null and image.texture != null and _source_path(image.texture).ends_with(".png"),
				"Custom delete modal editor art intact: " + key)
			if image != null:
				_check(_pixels_present(image.texture), "Custom modal artwork has visible pixels: " + key)
		for key in ACTION_BUTTONS:
			var button := scene.get_node_or_null(key) as Button
			var artwork: TextureRect = button.get_node_or_null("Artwork") as TextureRect if button != null else null
			var has_editor_png := artwork != null and artwork.texture != null
			_check(button != null and (_button_texture(button) != null or (key == "BackButton" and has_editor_png)),
				"Active leaderboard action button is PNG-backed: " + key)
		_check(scene.get_node_or_null("DeleteFirstOverlay") != null
			and scene.get_node_or_null("DeleteFinalOverlay") != null,
			"Both editor-authored modal overlay branches retained")
		_check(not (scene.get_node("DeleteFirstOverlay") as Control).visible
			and not (scene.get_node("DeleteFinalOverlay") as Control).visible,
			"Both modal branches remain hidden in editor until intentionally opened")
		_check(scene.get_node_or_null("DeleteFirstWarning") == null,
			"Obsolete native first-stage dialog not reintroduced")
		var disabled_style := (scene.get_node_or_null("DeleteFinalOverlay/ConfirmPanel/FinalDeleteButton") as Button)
		if disabled_style != null:
			_check(_source_path(_button_texture(disabled_style, "disabled")).ends_with("permanent delete default.png"),
				"Final destructive action has original disabled artwork")
			_check(_pixels_present(_button_texture(disabled_style, "disabled")),
				"Disabled destructive action has visible PNG rather than blank image")
	elif path in ["res://main_menu.tscn", "res://ui/secondary/settings.tscn",
			"res://ui/student/student_setup.tscn", "res://ui/tutorial/tutorial_home.tscn"]:
		# Other secondary screens can intentionally render vector/solid fills
		# with no image files. Check PNGs only on screens that actually use them.
		var count := _count_display_textures(scene)
		_check(count > 0, "PNG-backed representative screen retains editor textures: " + path)


func _count_display_textures(node: Node) -> int:
	var result := 0
	if node is TextureRect and (node as TextureRect).texture != null:
		result += 1
	elif node is NinePatchRect and (node as NinePatchRect).texture != null:
		result += 1
	elif node is BaseButton and _button_texture(node as BaseButton) != null:
		result += 1
	for child in node.get_children():
		result += _count_display_textures(child)
	return result


func _button_texture(button: BaseButton, state: String = "normal") -> Texture2D:
	if button == null:
		return null
	var style := button.get_theme_stylebox(state)
	if style is StyleBoxTexture:
		return (style as StyleBoxTexture).texture
	if button is TextureButton:
		return (button as TextureButton).texture_normal
	return null


func _source_path(texture: Texture2D) -> String:
	if texture == null:
		return ""
	if texture is AtlasTexture:
		return _source_path((texture as AtlasTexture).atlas)
	return texture.resource_path.to_lower()


func _pixels_present(texture: Texture2D) -> bool:
	if texture == null:
		return false
	var key := _source_path(texture) + "|" + str(texture.get_size())
	if _verified_art.has(key):
		return bool(_verified_art[key])
	var pixels := texture.get_image()
	var valid := pixels != null and pixels.get_used_rect().has_area()
	_verified_art[key] = valid
	return valid


func _exercise_modal_geometry() -> void:
	var original_size := root.size
	var original_content := root.content_scale_size
	root.content_scale_size = Vector2i(1280, 720)
	var prior_normalized := Rect2()
	var board_scene := ResourceLoader.load(LEADERBOARD, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if board_scene == null:
		_fail("Missing leaderboard during live modal geometry")
		return
	for resolution in SIZES:
		root.size = resolution
		var board := board_scene.instantiate() as Control
		root.add_child(board)
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		board.set_context({"teacher_authorized": true, "database_connected": true, "leaderboard_rows": []})
		await process_frame
		await process_frame
		var logical := board.size # DO NOT substitute physical Window.size in canvas_items stretch.
		print("ASSET_CLEANUP GEOMETRY PHYSICAL=%s LOGICAL=%s" % [resolution, logical])
		var expected_screen := Rect2(Vector2.ZERO, logical)
		var first := board.get_node("DeleteFirstOverlay") as Control
		var final := board.get_node("DeleteFinalOverlay") as Control
		var dim_first := first.get_node("DimBackground") as ColorRect
		var dim_final := final.get_node("DimBackground") as ColorRect
		_check(not first.visible and not final.visible, "Both modals initially hidden: " + str(resolution))
		_check(logical.x > 1000.0 and logical.y > 600.0,
			"Board uses real logical canvas (not zero or tiny): " + str(resolution))
		board.call("_begin_delete_all") # UI method only. Never dispatch final deletion.
		await process_frame
		_check(first.visible and not final.visible, "First overlay alone opens: " + str(resolution))
		_check(_rect_near(first.get_global_rect(), expected_screen, 3.0)
			and _rect_near(dim_first.get_global_rect(), expected_screen, 3.0),
			"First overlay and dim backdrop fill logical canvas: " + str(resolution))
		_check(_modal_parts_valid(first, logical), "First board/header/buttons remain visible and separate: " + str(resolution))
		board.call("_on_delete_first_confirmed")
		await process_frame
		_check(not first.visible and final.visible, "Only final overlay opens after first: " + str(resolution))
		_check(_rect_near(final.get_global_rect(), expected_screen, 3.0)
			and _rect_near(dim_final.get_global_rect(), expected_screen, 3.0),
			"Final overlay and dim backdrop fill logical canvas: " + str(resolution))
		_check(_modal_parts_valid(final, logical), "Final board/header/buttons remain visible and separate: " + str(resolution))
		var final_art := final.get_node("ConfirmPanel") as TextureRect
		var scaled := Rect2(final_art.get_global_rect().position / logical,
			final_art.get_global_rect().size / logical)
		if prior_normalized.has_area():
			_check(_rect_near(scaled, prior_normalized, 0.015),
				"Normalized modal geometry stable across physical resolutions: " + str(resolution))
		prior_normalized = scaled
		var edit := final.get_node("ConfirmPanel/TypedConfirmationEdit") as LineEdit
		var submit := final.get_node("ConfirmPanel/FinalDeleteButton") as Button
		_check(edit != null and submit != null and submit.disabled and edit.text.is_empty(),
			"Final input pristine and destructive button disabled: " + str(resolution))
		board.call("_cancel_delete_all")
		_check(not first.visible and not final.visible and submit.disabled,
			"Cancel restores both hidden overlays without database signal: " + str(resolution))
		board.queue_free()
		await process_frame
	root.size = original_size
	root.content_scale_size = original_content


func _modal_parts_valid(overlay: Control, logical: Vector2) -> bool:
	var full := Rect2(Vector2.ZERO, logical)
	var top_art: TextureRect = overlay.get_node_or_null("WarningHeader") as TextureRect
	if top_art == null:
		top_art = overlay.get_node_or_null("HeaderArtwork") as TextureRect
	var board_art: TextureRect = overlay.get_node_or_null("BoardArtwork") as TextureRect
	if board_art == null:
		board_art = overlay.get_node_or_null("ConfirmPanel") as TextureRect
	if top_art == null or board_art == null or not _fits(top_art.get_global_rect(), full):
		return false
	if not _fits(board_art.get_global_rect(), full):
		return false
	if _source_path(top_art.texture).is_empty() or _source_path(board_art.texture).is_empty():
		return false
	var buttons := overlay.find_children("*", "Button", true, false)
	if buttons.size() != 2:
		return false
	var a := (buttons[0] as Button).get_global_rect()
	var b := (buttons[1] as Button).get_global_rect()
	return (_fits(a, full) and _fits(b, full)
		and a.size.x >= 70.0 and b.size.x >= 70.0
		and a.size.y >= 30.0 and b.size.y >= 30.0
		and not a.intersects(b))


func _fits(rect: Rect2, screen: Rect2) -> bool:
	return rect.has_area() and screen.grow(3.0).encloses(rect)


func _rect_near(a: Rect2, b: Rect2, tolerance: float) -> bool:
	return a.position.distance_to(b.position) <= tolerance and a.size.distance_to(b.size) <= tolerance


func _sort_report() -> void:
	missing_paths.sort()
	missing_identifiers.sort()
	orphan_declarations.sort()
	baseline_added.sort()
	baseline_removed.sort()
	unorganized_pngs.sort()


func _report_once(dictionary: Dictionary, entries: Array[String], value: String) -> void:
	if not dictionary.has(value):
		dictionary[value] = true
		entries.append(value)


func _check(success: bool, reason: String) -> void:
	checks += 1
	if not success:
		failures.append(reason)


func _fail(reason: String) -> void:
	_check(false, reason)
