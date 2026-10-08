# KilosGrammar UI Flow

This directory contains the Godot 4 UI screens opened as overlays by
`main_menu.gd` while the original KilosGrammar animated background, music,
falling grammar words, and custom cursor stay active.

## Main panel

- **Tutorial** → Tutorial Home → Camera Check → Calibration → Movement Practice
  → Tutorial Complete → Grammar Guide / Play / Main Panel.
- **Play** → Select Activity → Select Grammar Topic → Select Difficulty
  → Camera Check → Calibration Verification → Ready → Gameplay → Results.
- **Leaderboard**, **Settings**, **Credits** → standalone subpanels with Back.
- **Quit** → exit the application.

## Play selections

- Activities: Catch the Word, Human Plane, Balloon Popping.
- MVP grammar topics: Noun, Verb, Adjective, Adverb, Pronoun.
- Difficulties: Easy, Normal, Hard.

The three physical lanes (LEFT, CENTER, RIGHT) are logical states shared by all
players. The vision integration must calibrate real-world boundaries separately
for every new player and verify saved calibration for a continuing player.

## Screen interface

Each screen has a `Control` scene root and emits:

```gdscript
signal requested(target: String, payload: Dictionary)
```

The host merges `payload` into its session context and opens the named route.
Screens may implement `set_context(context: Dictionary)` to display active
activity, topic, difficulty, and any session-specific results.

## Feature status and honesty

The current work adds **front-end screens and navigable mock interactions**.
Real camera capture, YOLO26n-Pose/ONNX, pose tracking, spatial calibration,
grammar game rules, SQLite storage, and Supabase synchronization are separate
development milestones. Until implemented, their UI must clearly indicate
preview/demo/not-connected state instead of presenting fabricated telemetry,
scores, or success indicators as real measurements.

Render target: Godot 60 FPS, with asynchronous pose inference (initial target
20–30+ updates/second) once computer vision is implemented.

## Validate screens

Open the existing `project.godot` in Godot 4.7.2, then press Play. The Main Panel
opens the new screens without changing the main scene in project settings.

There is also a checked-in smoke test that loads every UI scene and walks
through the main Play/Tutorial routes:

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path 'C:\Users\Yue\Documents\GODOT\kilos-grammar' --script 'res://tools/test_ui_screens.gd'
```
