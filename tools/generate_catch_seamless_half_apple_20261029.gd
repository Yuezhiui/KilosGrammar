extends SceneTree
## Make an additive seam-only derivative; NEVER overwrite the teacher's PNG.
## The original hand-painted top/stem/leaves remain byte-identical above y169.
const SOURCE := "res://Components/Gameplay/Catch the Word/Items/APPLE HALF.png"
const OUTPUT := "res://Components/Gameplay/Catch the Word/Items/APPLE HALF SEAMLESS.png"
const OPAQUE_LAST_ROW := 168
const FILL_SOURCE_ROW := 160

func _initialize() -> void:
	var original := Image.load_from_file(SOURCE)
	if original == null or original.is_empty() or original.get_size() != Vector2i(307, 190):
		printerr("CATCH APPLE ART: unexpected supplied source; refusing modification")
		quit(1)
		return
	if FileAccess.file_exists(OUTPUT):
		printerr("CATCH APPLE ART: output already exists; refusing to overwrite")
		quit(1)
		return
	var derived := original.duplicate() as Image
	# Only the 21 transparent bottom rows are extended. The basket's higher
	# editor-authored z-index hides this newly continuous red edge under its rim.
	for y in range(OPAQUE_LAST_ROW + 1, derived.get_height()):
		for x in range(derived.get_width()):
			derived.set_pixel(x, y, original.get_pixel(x, FILL_SOURCE_ROW))
	var code := derived.save_png(OUTPUT)
	print("CATCH APPLE SEAM ART: ", "PASS" if code == OK else "FAIL", " ", OUTPUT)
	quit(0 if code == OK else 1)
