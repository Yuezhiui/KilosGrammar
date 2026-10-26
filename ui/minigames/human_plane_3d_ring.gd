extends Node3D

## One independently editable portrait 9:16 flight portal. Its frame,
## inset trim and floating word plaque are all native, editor-authored 3D.
## The large doorway beneath the plaque remains open for the aircraft.
@onready var portal_frame: MeshInstance3D = $FrameLeft
@onready var portal_accent: MeshInstance3D = $InsetLeft
@onready var word_label: Label3D = $WordLabel

var _current_word := ""
var _current_color := Color.TRANSPARENT


func set_word(word: String, tint: Color, resolved: bool = false, correct: bool = false) -> void:
	var next_color := (Color("#4fee9b") if correct else Color("#ff6b7a")) if resolved else tint
	if _current_word != word:
		_current_word = word
		word_label.text = word.to_upper()
		# The actual chosen Titan One font sets the width of each word.
		# Fit to the plaque's open central area using measured glyph bounds,
		# including wide letters, rather than guessing from character count.
		if word_label.font != null:
			var glyph_size := word_label.font.get_string_size(
				word_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, word_label.font_size)
			word_label.pixel_size = minf(0.009,
				minf(3.43 / maxf(glyph_size.x, 1.0),
					0.90 / maxf(glyph_size.y, 1.0)))
	if next_color != _current_color:
		_current_color = next_color
		var material := portal_frame.material_override as StandardMaterial3D
		var glow_material := portal_accent.material_override as StandardMaterial3D
		# The four frame segments and four inset segments share their own
		# per-gate local scene materials, so answer feedback stays isolated.
		if material != null:
			material.albedo_color = next_color
			material.emission = next_color * 0.65
		if glow_material != null:
			glow_material.albedo_color = next_color.lightened(0.44)
			glow_material.emission = next_color.lightened(0.44)
