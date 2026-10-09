# KilosGrammar UI Flow

This directory contains the Godot 4 UI screens opened as overlays by
`main_menu.gd` while the original KilosGrammar animated background, music,
falling grammar words, and custom cursor stay active.

## Main panel

- **Tutorial** → Tutorial Home → Camera Check → Calibration → Movement Practice
  → Tutorial Complete → Grammar Guide / Play / Main Panel.
- **Play** → Student & Game Setup (Student ID / Name / Grade & Section /
  Grammar Style / Quiz or Activity / Difficulty) → Select Activity
  → Camera Check → Calibration Preview → Ready → Gameplay Demo → Game Over.
- **Game Over → Retry** returns to the Student & Game Setup with previous
  selections ready to edit; **Main Menu** exits the preview.
- **Leaderboard**, **Settings**, **Credits** → standalone subpanels with Back.
- **Quit** → exit the application.

## Credits and Settings visual system

- **Credits** uses a centered cream scroll panel and fixed dark-purple header.
  KERNEL lists the verified contributor names without role descriptions; the
  bottom of the scroll retains required Godot and Titan One license credits,
  plus attribution for Comic Lemon by Khurasan.
- **Settings** uses one centered dark-purple card with readable cream labels,
  amber slider knobs, and functional SETTINGS / CONTROLS / CAMERA tabs.
- The Settings tab row sits **outside and below** the card so it never covers
  the Fullscreen row, including at 1280×720.
- Both titles use Comic Lemon and an animated Godot RichTextLabel wave effect
  (`[wave amp=40.0 freq=4.0 connected=1]`). Titan One remains the clear,
  stationary font for controls and contributor names.
- Their palette is based on the user's local visual reference: cream `#FDE4B9`,
  deep slate-purple `#474660`, sage `#57826C`, mint `#74AB8E`. The procedural
  `ui/shared/lexi_reference_backdrop` recreates the look with original polygons,
  not copied background artwork.
- Master, Music and Effects sliders control actual Godot `AudioServer` buses:
  `Master`, `KilosMusic`, `KilosSFX`. `main_menu.gd` creates missing menu buses
  and routes music and one-shot menu sounds to them; Mute All and Fullscreen
  controls also work immediately.
- Audio/display changes are **session-only** for now; the informational
  Controls and Camera tabs do not pretend to access a live camera.

## Play selections

- Activities: Catch the Word, Human Plane, Balloon Popping.
- MVP grammar styles: Noun, Verb, Adjective, Adverb, Pronoun.
- Mode choices: Quiz and Activity (frontend labels, gameplay modes not yet wired).
- Difficulties: Easy, Normal, Hard.
- Direct Play starts with **all student/configuration fields empty**, never
  silently defaults to a student or difficulty.

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
grammar game rules, and **local PostgreSQL** student/score persistence are
separate development milestones. There is no cloud score storage/sync planned.
Until implemented, their UI must clearly indicate
preview/demo/not-connected state instead of presenting fabricated telemetry,
scores, or success indicators as real measurements.

The future PostgreSQL score identity will be `(student_id, game_style,
game_mode, difficulty)`, with the **latest completed score replacing** the
previous score for that exact combination. Aborted or interrupted attempts
must not overwrite a completed score. Do not place database passwords in
GDScript or Git-tracked settings.

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

For layout-boundary checks across 1280×720, 1600×900 and 1920×1080, run
`--script res://tools/test_ui_layout.gd` with the same Godot executable.
