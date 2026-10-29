extends SceneTree

# Godot 4.7.2 --headless --path . --script res://tools/test_ui_feature_layout_20261029.gd
# Scene loads and script/UID preservation without starting webcam or database.
const FEATURES := [
	["res://ui/play/activity/play_activity.tscn", "res://ui/play/activity/play_activity.gd"],
	["res://ui/play/topic/play_topic.tscn", "res://ui/play/topic/play_topic.gd"],
	["res://ui/play/difficulty/play_difficulty.tscn", "res://ui/play/difficulty/play_difficulty.gd"],
	["res://ui/play/gameplay/gameplay.tscn", "res://ui/play/gameplay/gameplay.gd"],
	["res://ui/play/gameplay/guided_countdown.tscn", ""],
	["res://ui/play/pause/pause.tscn", "res://ui/play/pause/pause.gd"],
	["res://ui/student/setup/student_setup.tscn", "res://ui/student/setup/student_setup.gd"],
	["res://ui/secondary/leaderboard/leaderboard.tscn", "res://ui/secondary/leaderboard/leaderboard.gd"],
	["res://ui/secondary/leaderboard/leaderboard_row.tscn", ""],
	["res://ui/secondary/settings/settings.tscn", "res://ui/secondary/settings/settings.gd"],
	["res://ui/secondary/results/results.tscn", "res://ui/secondary/results/results.gd"],
	["res://ui/secondary/credits/credits.tscn", "res://ui/secondary/credits/credits.gd"],
	["res://ui/vision/calibration/calibration.tscn", "res://ui/vision/calibration/calibration.gd"],
	["res://ui/tutorial/grammar_guide/grammar_guide.tscn", "res://ui/tutorial/grammar_guide/grammar_guide.gd"]
]
const REMAIN := [
	"res://ui/tutorial/tutorial_home.tscn",
	"res://ui/tutorial/tutorial_home.gd",
	"res://ui/tutorial/tutorial_theme.gd",
	"res://ui/vision/pose_service.gd",
	"res://ui/secondary/secondary_theme.tres"
]
const EXTRA_SCRIPTS := [
	"res://ui/play/gameplay/catch_asset_preloader.gd",
	"res://ui/play/shared/play_ui.gd",
	"res://ui/vision/calibration/calibration_voice.gd"
]
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for entry in FEATURES:
		var scene_path: String = entry[0]
		var script_path: String = entry[1]
		var packed := load(scene_path) as PackedScene
		_check(packed != null, "Feature scene loads: " + scene_path)
		if packed == null:
			continue
		var instance := packed.instantiate()
		_check(instance != null, "Feature scene instantiates: " + scene_path)
		if instance != null:
			if not script_path.is_empty():
				var source := instance.get_script() as Script
				_check(source != null and source.resource_path == script_path,
					"Root script resolves at moved path: " + script_path)
				_check(FileAccess.file_exists(script_path + ".uid"),
					"Preserved script UID sidecar: " + script_path)
			instance.free()
	for path in REMAIN:
		_check(ResourceLoader.exists(path), "Shared or excluded resource preserved: " + path)
	for path in EXTRA_SCRIPTS:
		_check(load(path) is Script, "Moved extra script loads: " + path)
		_check(FileAccess.file_exists(path + ".uid"), "Moved extra UID preserved: " + path)
	print("UI FEATURE PATH QA: %s checks=%d failures=%d" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size()
	])
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		printerr("UI FEATURE PATH FAIL: ", description)
