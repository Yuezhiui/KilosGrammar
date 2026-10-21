## Run: godot --headless --path . --script res://ui/redesign/shared/smoke_test.gd
extends SceneTree

const WIDGETS = preload("res://ui/redesign/shared/cartoon_widgets.gd")
const RESPONSIVE = preload("res://ui/redesign/shared/responsive_canvas.gd")
const MANIFEST_PATH := "res://ui/redesign/assets/phase3_manifest.json"
const CATEGORIES := {
	"game_over": ["bg_teal_clean", "panel_student", "panel_student_blank",
		"score_footer", "button_retry", "button_main_menu", "icon_student_id"],
	"tutorial": ["bg_classroom", "panel_blank", "title_whole_body",
		"button_guided", "button_movement", "button_grammar", "button_back"],
	"settings": ["title_settings", "panel_main", "panel_sidebar",
		"tab_settings_green", "tab_controls_cream", "field_row_cream", "button_home"]
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not manifest is Dictionary:
		push_error("Missing/invalid source-provenance manifest")
		quit(1)
		return
	var loaded := 0
	for category in manifest:
		for entry in manifest[category]:
			var texture := WIDGETS.art(String(category), String(entry["name"]))
			if texture == null or texture.get_size() != Vector2(entry["size"][0], entry["size"][1]):
				push_error("Godot failed manifest asset: %s" % entry["path"])
				quit(1)
				return
			loaded += 1
	if loaded != 105:
		push_error("Expected 105 semantic original-art sprites, found %d" % loaded)
		quit(1)
		return
	for category in CATEGORIES:
		for sprite in CATEGORIES[category]:
			var texture := WIDGETS.art(category, sprite)
			if texture == null or texture.get_size().x <= 0:
				push_error("Missing source-derived image %s/%s" % [category, sprite])
				quit(1)
				return
	var holder := Control.new()
	root.add_child(holder)
	var b := WIDGETS.button(holder, "game_over", "button_retry", "Retry", "button_retry_hover")
	if b == null or b.focus_mode != Control.FOCUS_ALL or b.tooltip_text != "Retry" or b.custom_minimum_size.x > 360.0:
		push_error("Native button with source sprite failed")
		quit(1)
		return
	# A source image 631x179 is proportionally different from a 348x78
	# layout slot. The art child must keep its own ratio as it fits inside it.
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
	if b.text != "Retry":
		push_error("Art button must keep native semantic label")
		quit(1)
		return
	# Disabled art is selected by native state and remains centered without
	# modifying the underlying Button's interaction or semantic label.
	WIDGETS.skin_button(b, "game_over", "button_retry", "button_retry_hover",
		"", "button_retry_disabled")
	b.disabled = true
	await process_frame
	await process_frame
	var disabled_texture := WIDGETS.art("game_over", "button_retry_disabled")
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
	var atlas := WIDGETS.atlas_texture(WIDGETS.art("game_over", "icon_star_large"), Rect2i(0, 0, 30, 30))
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
	print("PASS redesign art toolkit: %d source-manifest textures, native aspect-safe Button with focus/input, scroll, AtlasTexture, compact/wide columns and fit" % loaded)
	quit(0)
