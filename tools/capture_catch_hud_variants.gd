extends SceneTree

# Capture real Catch the Word HUD screenshots for a few lesson/mode combinations.
# Godot --path . --rendering-method gl_compatibility --script res://tools/capture_catch_hud_variants.gd

const OUTPUT_DIR := "res://showcase/catch_word_hud"
const SCENE := "res://ui/minigames/catch_word.tscn"
const CHARACTERS := ["Boy", "Girl", "Grandma", "Grandpa"]
const MAPS := ["City", "Forest", "Mountain"]
const SHOWCASE_CASES := [
	["Boy", "City", "Noun", "Seconds"], ["Boy", "Forest", "Verb", "Lives"],
	["Boy", "Mountain", "Adjective", "Seconds"], ["Boy", "City", "Adverb", "Lives"],
	["Girl", "City", "Pronoun", "Lives"], ["Girl", "Forest", "Adverb", "Seconds"],
	["Girl", "Mountain", "Noun", "Lives"], ["Girl", "Forest", "Noun", "Seconds"],
	["Grandma", "City", "Verb", "Seconds"], ["Grandma", "Forest", "Adjective", "Lives"],
	["Grandma", "Mountain", "Adverb", "Seconds"], ["Grandma", "City", "Pronoun", "Seconds"],
	["Grandpa", "City", "Adjective", "Seconds"], ["Grandpa", "Forest", "Pronoun", "Lives"],
	["Grandpa", "Mountain", "Verb", "Lives"], ["Grandpa", "Mountain", "Noun", "Seconds"]
]
const EXTRA_RESOLUTION_CASES := [
	["Girl", "City", "Pronoun", "Lives", 1600, 900],
	["Grandma", "Forest", "Adjective", "Lives", 1600, 900],
	["Grandpa", "Mountain", "Verb", "Lives", 1920, 1080],
	["Boy", "City", "Noun", "Seconds", 1920, 1080],
	["Girl", "Forest", "Adverb", "Seconds", 875, 500],
	["Grandpa", "City", "Adjective", "Seconds", 875, 500]
]
const CASES := [
	{"topic": "Noun", "mode": "Seconds", "difficulty": "Easy"},
	{"topic": "Noun", "mode": "Lives", "difficulty": "Normal"},
	{"topic": "Pronoun", "mode": "Seconds", "difficulty": "Normal"},
	{"topic": "Pronoun", "mode": "Lives", "difficulty": "Hard"},
	{"topic": "Verb", "mode": "Seconds", "difficulty": "Easy"},
	{"topic": "Verb", "mode": "Lives", "difficulty": "Normal"},
	{"topic": "Adjective", "mode": "Seconds", "difficulty": "Easy"},
	{"topic": "Adjective", "mode": "Lives", "difficulty": "Normal"},
	{"topic": "Adverb", "mode": "Seconds", "difficulty": "Normal"},
	{"topic": "Adverb", "mode": "Lives", "difficulty": "Hard"},
]
const EXAMPLE_WORDS := {
	"Noun": ["GARDEN", "TEACHER", "LIBRARY"],
	"Pronoun": ["THEY", "SHE", "HIM"],
	"Verb": ["DANCE", "WRITE", "JUMP"],
	"Adjective": ["BRIGHT", "HAPPY", "KIND"],
	"Adverb": ["QUICKLY", "SOFTLY", "SLOWLY"]
}

func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_size(root.size)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var packed := load(SCENE) as PackedScene
	if packed == null:
		push_error("Catch HUD screenshot: cannot load the scene")
		quit(1)
		return
	var captured := 0
	var variants: Array[Dictionary] = []
	for selection in SHOWCASE_CASES:
		var variant: Dictionary = {"character": selection[0], "map": selection[1], "topic": selection[2], "mode": selection[3], "difficulty": "Normal", "size": Vector2i(1280, 720)}
		variants.append(variant)
	for selection in EXTRA_RESOLUTION_CASES:
		variants.append({"character": selection[0], "map": selection[1], "topic": selection[2], "mode": selection[3], "difficulty": "Normal", "size": Vector2i(selection[4], selection[5])})
	for entry in variants:
		root.size = entry["size"]
		DisplayServer.window_set_size(root.size)
		await process_frame
		await process_frame
		var game := packed.instantiate() as Control
		root.add_child(game)
		game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		game.call("set_context", {
			"activity": "Catch the Word",
			"topic": entry["topic"],
			"game_style": entry["topic"],
			"game_mode": entry["mode"],
			"difficulty": entry["difficulty"],
				"catch_character": entry["character"],
				"catch_map": entry["map"]
		})
		game.set_process(false)
		game.call("_clear_falling_tiles")
		var words: Array = EXAMPLE_WORDS[String(entry["topic"])]
		var tiles: Array = game.get("falling_tiles")
		# Gameplay already scales its 1280x720 logical coordinates to the viewport.
		var target_positions := [Vector2(236, 249), Vector2(1007, 277), Vector2(824, 462)]
		for index in range(words.size()):
			var word := String(words[index])
			var node: Control = game.call("_create_tile_node", word, Color.WHITE)
			var tile := {
				"word": word, "matching": true,
				"pos": target_positions[index], "speed": 0.0,
				"color": Color.WHITE, "passed_line": false, "node": node
			}
			tiles.append(tile)
			game.call("_sync_tile_node", tile)
		var basket_words: Array = game.get("collected_words")
		basket_words.clear()
		basket_words.append(String(words[0]))
		basket_words.append(String(words[1]))
		game.call("_refresh_collected_words")
		game.set("score", 5000)
		game.set("feedback_text", "CATCH THE %s WORDS!" % String(entry["topic"]).to_upper())
		await process_frame
		await process_frame
		game.call("_refresh_hud")
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		var filename := "%s_%s_%s_%s_%dx%d.png" % [String(entry["character"]).to_lower(), String(entry["map"]).to_lower(), String(entry["topic"]).to_lower(), String(entry["mode"]).to_lower(), root.size.x, root.size.y]
		var output := ProjectSettings.globalize_path(OUTPUT_DIR.path_join(filename))
		var error := screenshot.save_png(output)
		if error == OK:
			captured += 1
			print("CAPTURED ", output)
		else:
			push_error("Catch HUD capture failed: %s, error=%d" % [filename, error])
		root.remove_child(game)
		game.queue_free()
		await process_frame
	if captured == variants.size():
		print("PASS: captured %d Catch the Word UI variants" % captured)
		quit(0)
	else:
		quit(1)
