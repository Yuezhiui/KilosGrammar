# KilosGrammar build and version

**Source version:** `v0.1.0-beta.1`

**Revision date:** 2026-10-24 (Asia/Manila)

**Engine:** Godot 4.7.2.stable

**Windows export platform:** Windows Desktop x86-64

## Human Plane update

- Uses actual measured CENTER → RIGHT → LEFT body calibration with fresh three-second holds per zone, matching Catch the Word.
- A student must spread BOTH arms wide to enable flight. Lowering either arm, a missing wrist, or lost student tracking immediately freezes horizontal motion. Re-spreading both arms resumes without recalibration.
- Smooth, frame-rate-independent left/right movement follows calibrated body X across the entire authored flight path. Arm banking/gyro angles no longer steer.
- Preserves the original scene-authored gate positions, HUD, 60-second mode, three lives, and other minigames.

## Build status and limitations

This tag marks a **source-code beta**, not a completed standalone installer or Windows executable.
The Windows offline release preflight remains BLOCKED until the matching Godot
4.7.2 Windows export templates and the reviewed local offline inputs (YOLO model,
Python 3.11 runtime, PostgreSQL 18 installer, Windows x64 dependency wheels) are staged.
The release scripts intentionally refuse to create incomplete or misleading EXE/PCK
or checksum manifests.

To prepare a future offline build on Windows, follow `release/windows/README.md`,
verify the required assets and prerequisites, then use
`release/windows/Build-WindowsRelease.ps1 -PreflightOnly` before exporting.

Source-code tests run with Godot 4.7.2 and Python's `unittest` are camera-free.
Real classroom webcam tracking, offline deployment to another school PC, and
live PostgreSQL durability still require acceptance testing.
