extends Node

# Small, session-scoped resource holder owned by main_menu.gd. All requests
# begin on the Ready screen, never during application/menu startup.
# Large textures and voices are loaded on Godot's loader thread and retained
# until next selection/exit. The small scripted Catch PackedScene intentionally
# loads through gameplay: threading that scene leaked two RefCounted objects.

const MAPS := {
	"City": "res://WordCatcherMaps/CityMap.png",
	"Forest": "res://WordCatcherMaps/ForestMap.png",
	"Mountain": "res://WordCatcherMaps/MountainMap.png"
}
const CHARACTERS := {
	"Boy": ["res://WordCatcherCharacters/BOY BODY.png", "res://WordCatcherCharacters/BOY BASKET.png"],
	"Girl": ["res://WordCatcherCharacters/GIRL BODY.png", "res://WordCatcherCharacters/GIRL BASKET.png"],
	"Grandma": ["res://WordCatcherCharacters/GRANDMA BODY.png", "res://WordCatcherCharacters/GRANDMA BASKET.png"],
	"Grandpa": ["res://WordCatcherCharacters/GRANDPA BODY.png", "res://WordCatcherCharacters/GRANDPA BASKET.png"]
}
const HUD_ART := [
	"res://ui/minigames/catch_hud/generated/title_board.png",
	"res://ui/minigames/catch_hud/generated/lives_badge.png",
	"res://ui/minigames/catch_hud/generated/timer_badge.png",
	"res://ui/minigames/catch_hud/generated/pause_badge.png",
	"res://ui/minigames/catch_hud/generated/score_board.png",
	"res://ui/minigames/catch_hud/generated/character/word_apple.png",
	"res://ui/minigames/catch_hud/generated/replacement/lives_state_1.png",
	"res://ui/minigames/catch_hud/generated/replacement/lives_state_2.png",
	"res://ui/minigames/catch_hud/generated/replacement/lives_state_3.png",
	"res://Components/Apple.png",
	"res://Components/HeartRed.png",
	"res://Components/HeartBlack.png"
]
const VOICE_FILES := [
	"GoodJob.mp3", "niceee.mp3", "Awesome.mp3", "Perfect.mp3",
	"You Nailed it.mp3", "Awww.mp3", "Wrong Answer.mp3",
	"You Missed.mp3", "Better Luck.mp3"
]
const VOICE_DIR := "res://assets/audio/catch_voice/"

var selection_character := ""
var selection_map := ""
var _wanted: Dictionary = {}
var _pending: Dictionary = {}
var _held: Dictionary = {}


func _ready() -> void:
	set_process(false)


func prepare(character: String, map_name: String) -> void:
	if not CHARACTERS.has(character) or not MAPS.has(map_name):
		clear_selection()
		return
	selection_character = character
	selection_map = map_name
	var desired: Dictionary = {}
		# The tiny Catch .tscn with scripted subresources loads during gameplay.
		# Sending that PackedScene through load_threaded_request() reproducibly
		# leaked two RefCounted objects on Godot 4.7.2 app exit. Keep the actual
		# heavy textures and voice clips asynchronous instead.
	for path in CHARACTERS[character]:
		desired[path] = true
	desired[MAPS[map_name]] = true
	for path in HUD_ART:
		desired[path] = true
	for filename in VOICE_FILES:
		desired[VOICE_DIR + filename] = true
	# Retain only the next round's selected originals and shared HUD/voice set.
	for path in _held.keys():
		if not desired.has(path):
			_held.erase(path)
	_wanted = desired
	for path in _wanted:
		if _held.has(path) or _pending.has(path):
			continue
		# Cached resources are already decoded: retaining a reference is cheap.
		if ResourceLoader.has_cached(path):
			var cached := load(path) as Resource
			if cached != null:
				_held[path] = cached
			continue
		var result := ResourceLoader.load_threaded_request(path)
		if result == OK:
			_pending[path] = true
		else:
			push_warning("Catch Ready preloader could not queue %s (error %d)" % [path, result])
	set_process(not _pending.is_empty())


func clear_selection() -> void:
	selection_character = ""
	selection_map = ""
	_wanted.clear()
	_held.clear()
	# In-flight engine requests cannot be cancelled. Drain their results without
	# retaining obsolete textures once they report complete.
	set_process(not _pending.is_empty())


func finish_pending_for_shutdown() -> void:
	# During NORMAL play, preloads must stay async. During final shutdown,
		# however, freeing this node with outstanding ResourceLoader requests
		# can leave their internal refs alive through engine teardown.
	# The completion barrier runs only after the user explicitly exits; no
	# selected textures, voice assets or PackedScene are retained afterward.
	clear_selection()
	for path in _pending.keys():
		var state := ResourceLoader.load_threaded_get_status(path)
		if state != ResourceLoader.THREAD_LOAD_FAILED and state != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			# Godot's threaded_get waits for this already-requested asset to finish
			# and retrieves its engine-owned ref. We deliberately discard it.
			var completed: Resource = ResourceLoader.load_threaded_get(path)
			completed = null
		_pending.erase(path)
	_held.clear()
	_wanted.clear()
	set_process(false)


func _process(_delta: float) -> void:
	for path in _pending.keys():
		var state := ResourceLoader.load_threaded_get_status(path)
		if state == ResourceLoader.THREAD_LOAD_LOADED:
			var resource := ResourceLoader.load_threaded_get(path)
			if resource != null and _wanted.has(path):
				_held[path] = resource
			_pending.erase(path)
		elif state == ResourceLoader.THREAD_LOAD_FAILED or state == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_warning("Catch Ready preloader failed to load %s" % path)
			_pending.erase(path)
	if _pending.is_empty():
		set_process(false)


func get_preload_stats() -> Dictionary:
	return {
		"character": selection_character,
		"map": selection_map,
		"requested": _wanted.size(),
		"held": _held.size(),
		"pending": _pending.size(),
		"complete": not _wanted.is_empty() and _pending.is_empty() and _held.size() == _wanted.size()
	}
