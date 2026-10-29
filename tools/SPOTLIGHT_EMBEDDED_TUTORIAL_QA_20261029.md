# Embedded Tutorial Spotlight — isolated QA (29 October 2026)

Owner: worker-17. New isolated runner: `res://tools/test_spotlight_embedded_tutorial_20261029.gd`. All minigame and gameplay production files were **read-only** to this worker.

## Final focused verification

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_spotlight_embedded_tutorial_20261029.gd
# EMBEDDED SPOTLIGHT QA: PASS (1216 checks, 0 failures)

& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --rendering-driver opengl3 --path . --script res://tools/test_spotlight_embedded_tutorial_20261029.gd
# OpenGL 3.3 NVIDIA GeForce RTX 3050 6 GB
# EMBEDDED SPOTLIGHT QA: PASS (1216 checks, 0 failures)

& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --check-only --script res://tools/test_spotlight_embedded_tutorial_20261029.gd
# exit 0
```

Coverage: Catch the Word, Balloon Popping and Human Plane; **1280×720 / 1600×900 / 1920×1080**; Seconds **and** Lives. Checks that each game scene contains exactly one editor-instanced `GuidedSpotlight` with `[editable path="GuidedSpotlight"]`, draggable focus regions, arrows, captions, and navigation buttons. Normal Play leaves it invisible. The gameplay wrapper uses that **same** child after a guided, calibration-measured context, without creating a separate popup.

Across all five steps, verifies NEXT/BACK/SKIP/REPLAY, corresponding mode-specific steps and arrows, positive on-screen focus rectangles, unchanged authored positions, frozen score/hearts/timer/waves, and one countdown on exit. Webcam `PoseService` state/process resources remain unchanged; Human Plane's normal Camera3D/SubViewport is counted independently, rather than misidentified as another webcam. Test uses keyboard-only context with `calibration_measured=true` and **does not simulate authentic live camera calibration**.

## Read-only results for existing regression tests

| Original suite | Latest outcome | Scope / qualification |
| --- | --- | --- |
| `tools/test_guided_onboarding.gd` | **PASS** | Real wrapper on all three games × both modes; freeze, guide, countdown and return to game |
| `tools/test_play_tutorial_session_isolation_stress.gd` | **PASS: 276 checks, 0 failures** | In-memory backend ensures Tutorial never writes a Play score |
| `tools/test_spotlight_overlay.gd` | **FAIL: 2/106** | Legacy assertions expect passed live HUD targets to override authored focus; `use_editor_highlights=true` now intentionally prefers editor rectangles |
| `tools/test_guided_routing.gd` | **FAIL: 7** | Legacy synthetic calibration injects `player_x/current_status/packet_sequence`, but real calibration requires fresh authenticated `get_pose_samples_after(...)` samples |
| `tools/test_play_tutorial_shared_calibration_cleanup.gd` | **FAIL: 2/37** | Test expects former `PoseGuidePlaneLeft/Right`; current calibration scene has `PoseGuidePlaneCenter`, not those retired nodes |

These **legacy failures are not counted as passed**, have been reported to the prime worker, and were not modified because this worker owns only the new standalone QA and optional report. No real webcam, database, production scenes, commits, resets or pushes.
