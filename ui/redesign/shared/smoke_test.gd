## Run: godot --headless --path . --script res://ui/redesign/shared/smoke_test.gd
extends SceneTree

const WIDGETS = preload("res://ui/redesign/shared/cartoon_widgets.gd")
const RESPONSIVE = preload("res://ui/redesign/shared/responsive_canvas.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# The historical Phase3 provenance manifest describes extracted candidates,
	# including sprites never referenced by a runnable scene. A cleanup may
	# rightfully remove those. Validate current scene resources instead of
	# requiring all 105 extraction-era images to stay in the shipped project.
	var active := _scene_authored_redesign_images()
	if active.is_empty():
		push_error("No actual scene-authored redesign PNG dependencies found")
		quit(1)
		return
	var loaded := 0
	for path in active:
		var texture := load(path) as Texture2D
		if texture == null or texture.get_size().x <= 0 or texture.get_size().y <= 0:
			push_error("Godot failed active scene artwork: %s" % path)
			quit(1)
			return
		for category in WIDGETS.ART_FOLDERS:
			if path.begins_with(String(WIDGETS.ART_FOLDERS[category])):
				if WIDGETS.art(String(category), path.get_file().get_basename()) != texture:
					push_error("Reusable widget cannot load actively referenced PNG: %s" % path)
					quit(1)
					return
		loaded += 1
	var holder := Control.new()
	root.add_child(holder)
	# Tutorial guided-button art is referenced by tutorial_home.tscn, so this
	# test exercises WIDGETS against a real kept PNG, not a QA-only sprite.
	var b := WIDGETS.button(holder, "tutorial", "button_guided", "Guided")
	if b == null or b.focus_mode != Control.FOCUS_ALL or b.tooltip_text != "Guided" or b.custom_minimum_size.x > 360.0:
		push_error("Native button with source sprite failed")
		quit(1)
		return
	# Image child always keeps the original aspect inside an edited button slot.
	b.size = Vector2(348, 78)
	var face := b.get_node_or_null("ArtButtonFace") as TextureRect
	if face == null or face.stretch_mode != TextureRect.STRETCH_KEEP_ASPECT_CENTERED or face.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		push_error("Art Button child must preserve original aspect without stealing input")
		quit(1)
		return
	if b.get_theme_stylebox("normal") is StyleBoxTexture:
		push_error("Full painted button art cannot use deformable StyleBoxTexture")
		quit(1)
		return
	if b.text != "Guided":
		push_error("Art button must keep native semantic label")
		quit(1)
		return
	# The disabled state remains a functional native button even when the
	# shipped scene has no dedicated, otherwise-unused disabled illustration.
	WIDGETS.skin_button(b, "tutorial", "button_guided", "", "", "button_guided")
	b.disabled = true
	await process_frame
	await process_frame
	var disabled_texture := WIDGETS.art("tutorial", "button_guided")
	if face.texture != disabled_texture:
		push_error("Disabling the native button did not select its real disabled PNG")
		quit(1)
		return
	b.disabled = false
	var grid := GridContainer.new()
	holder.add_child(grid)
	WIDGETS.columns(grid, 875.0)
	if grid.columns != 1:
		push_error("Compact responsive layout did not choose 1 column")
		quit(1)
		return
	WIDGETS.columns(grid, 1280.0)
	if grid.columns != 2:
		push_error("Wide responsive layout did not choose 2 columns")
		quit(1)
		return
	var scroller := WIDGETS.scrolling_root(holder)
	if scroller.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		push_error("Compact scrolling area allows unintended horizontal scrolling")
		quit(1)
		return
	var atlas := WIDGETS.atlas_texture(WIDGETS.art("tutorial", "icon_star"), Rect2i(0, 0, 30, 30))
	if atlas == null or atlas.atlas == null:
		push_error("Optional source AtlasTexture helper did not construct an atlas region")
		quit(1)
		return
	var stage := Control.new()
	holder.add_child(stage)
	var factor := WIDGETS.fit_stage(stage, Vector2(875, 500))
	if not is_equal_approx(factor, minf(875.0 / 1280.0, 500.0 / 720.0)):
		push_error("Responsive stage aspect-fit is wrong")
		quit(1)
		return
	var responsive := RESPONSIVE.new()
	if responsive == null:
		push_error("Responsive canvas script failed to instantiate")
		quit(1)
		return
	holder.free()
	responsive.free()
	print("PASS redesign art toolkit: %d actually scene-referenced textures, native aspect-safe Button with focus/input, scroll, AtlasTexture, compact/wide columns and fit" % loaded)
	quit(0)


func _scene_authored_redesign_images() -> Dictionary:
	var result := {}
	var paths: Array[String] = []
	_walk_scenes("res://", paths)
	var pattern := RegEx.new()
	pattern.compile('path="(res://Components/[^"]+\\.png)"')
	for scene_path in paths:
		var serialized := FileAccess.get_file_as_string(scene_path)
		for entry in pattern.search_all(serialized):
			var path := entry.get_string(1)
			for folder in WIDGETS.ART_FOLDERS.values():
				if path.begins_with(String(folder)):
					result[path] = true
					break
	return result


func _walk_scenes(directory_path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if not name.begins_with("."):
			var path := directory_path.path_join(name)
			if directory.current_is_dir():
				_walk_scenes(path, output)
			elif path.ends_with(".tscn"):
				output.append(path)
		name = directory.get_next()
	directory.list_dir_end()
