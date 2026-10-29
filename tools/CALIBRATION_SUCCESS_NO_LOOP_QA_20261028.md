# KILOS GRAMMAR calibration SUCCESS no-loop adversarial QA

**Date:** 2026-10-28. **Godot:** 4.7.2 stable, Windows headless. **Scope:** deterministic synthetic current-session YOLO-style source packets, real Godot `calibration.gd`, real `PoseService` validation, real Play/Tutorial gameplay wrapper. This is not a webcam, screen recording, GPU inference, audio audibility, or live-database test.

## Reproduction

From the `kilos-grammar` project directory:

```powershell
$godot = 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --script res://tools/test_calibration_success_no_loop_20261028.gd
& $godot --headless --path . --script res://tools/test_calibration_success_overlay_stress.gd
& $godot --headless --path . --script res://tools/test_calibration_three_second_sequence.gd
& $godot --headless --path . --script res://tools/test_calibration_minimal_ui.gd
& $godot --headless --path . --script res://tools/test_calibration_human_plane_center_only.gd
& $godot --headless --path . --script res://tools/test_calibration_success_latched_raw_solo.gd
& $godot --headless --path . --script res://tools/test_calibration_five_pose_png_sequences.gd
```

Final **combined recheck**, all exit code `0` and no Godot parse errors:

| Test | Current result |
| --- | --- |
| **New** `test_calibration_success_no_loop_20261028.gd` | **PASS 271 assertions, 7 Play/Tutorial interruption cases** |
| Migrated `test_calibration_success_overlay_stress.gd` | **PASS 185 assertions** |
| Migrated `test_calibration_three_second_sequence.gd` | **PASS 649 assertions** |
| Migrated `test_calibration_minimal_ui.gd` | **PASS 126 assertions** |
| Migrated `test_calibration_human_plane_center_only.gd` | **PASS 79 assertions** |
| Worker16's existing `test_calibration_success_latched_raw_solo.gd` | **PASS 109 assertions** |
| Existing `test_calibration_five_pose_png_sequences.gd` | **PASS 193 assertions** |

## What is actually tested

The new suite exercises seven independent sequences: normal Play with rapid post-success left/right movement and missing wrists; guided Tutorial with a fresh one-person raw YOLO count but low-confidence/missing torso; Play with **0** people; Tutorial with **2** people; Play with expired capture/source age; Tutorial with a disconnected camera; and Play with an entirely changed camera-session token. Every case starts at a fresh screen, completes **the full three-second CALIBRATION intro**, then independently verifies **CENTER → RIGHT → LEFT** each requires at least **three seconds** and **eight strictly increasing real-source-like measurements**. It only permits the separate **three-second CALIBRATION SUCCESS** overlay after these three actual holds have established valid physical floor bounds. No fabricated CENTER-only, keyboard/demo, or skipped mode is accepted.

When already successful, post-capture **wrist/torso joint loss** is intentionally not treated as loss of the student's physical position measurements: fresh authenticated raw YOLO **one-person occupancy** can continue the success handoff even if no green skeleton is currently drawable. Conversely **0, 2+, stale/unknown person count, camera disconnect, or wrong/old session** freeze progress and **never authorize gameplay**. Importantly they do not erase previously completed measurements or silently send a moving child back to CENTER. Once a new authentic solo source is seen again, success continues and emits **exactly one** `requested("gameplay", payload)` event. The test verifies actual measured positions and correct `camera_live`, `calibration_measured`, `start_countdown`, `guided_tutorial`, and no-keyboard/skip fields.

To validate the downstream route rather than only its payload, the new suite mounts the actual `ui/play/gameplay.tscn`. Guided Tutorial must first show **Spotlight**, then the frozen **3-2-1 countdown**. Ordinary Play enters the frozen **3-2-1 countdown** directly. Both refuse GO while the source is absent, then permit one real GO on recovered source-valid solo pose; duplicate countdown-completion callbacks are inert. The wrapper intentionally clears its `guided_stage` when GO succeeds, so the post-GO state is an empty stage string with gameplay processing restored, not a lingering `"completed"` label.

## Source authenticity and earlier RED reproduction

The first version of the new test reported **12 false failures out of 138 checks** because its fixture set only `PoseService.active=true`, `player_x`, and a status dictionary. That did **not** satisfy production's correct `fresh_camera_population()` security checks. In particular, the test failed to provide the session token, live stub process, bound transport, current-session `token/kind` source packet, `camera_phase=tracking`, and `_apply_pose_packet()` arrival event. A pending success therefore correctly remained frozen, producing zero routes. **This was a test harness error, not a reason to weaken production checks.**

The corrected fixture supplies an isolated `PacketPeerUDP` bound to **127.0.0.1** only, a **mock live worker PID** using the Godot test runner's own process ID, a unique current session token, and source-verified monotonic pose packets passed through `PoseService._apply_pose_packet()` and `_record_fresh_calibration_pose()`. No external worker, internet request, physical camera, Python/YOLO process, or actual UDP packet transmission occurs. The fixture resets the mock PID to `-1` **before** any camera/gameplay `stop_camera()` teardown so the test cannot terminate its own Godot process. Current occupancy and source-age checks remain exactly as strict as production. A second fixture mismatch expected the wrapper to leave `guided_stage="completed"` after GO; `_clear_guided_ui()` correctly clears it to `""` after gameplay starts. Both test errors were corrected. **Current new suite: PASS 271/271.**

The four legacy suites were rerun **before migration** against the newer, intentionally safer success-latching runtime and reproduced these historical RED outputs:

| Legacy suite before QA migration | Historical RED cause |
| --- | --- |
| `test_calibration_success_overlay_stress.gd` | **FAIL 29/193**; demanded erasing all completed captures on crowd/zero/session restart |
| `test_calibration_three_second_sequence.gd` | **FAIL 2/637**; only synthesized torso status, not an authenticated live raw occupancy observation, before GO |
| `test_calibration_minimal_ui.gd` | **FAIL 10/132**; demanded resetting on stale pose/crowd and redoing all holds after authentic success |
| `test_calibration_human_plane_center_only.gd` | **FAIL 8/72**; lacked source-authenticated GO fixture and demanded removing completed T-pose upon 0/2 people |

The prime explicitly expanded this worker's **QA-file ownership** to migrate those four existing tests. They now check the correct **freeze/preserve/no-unsafe-GO** invariants; the mandatory original 3-second hold and solo source restrictions are unchanged. These historical RED counts do **not** represent current production failures. Before worker16's production fix, the original success handler did call `_reset_live_samples()` on a temporary invalid pose; the current verified source uses the correct latched success gate and checks raw person-box freshness independently of wrists.

## Boundaries / manual follow-up

These tests cannot prove that the **green skeleton visual overlay remains physically smooth**: it is generated from webcam/YOLO preview pixels by the Python worker, not drawn from Godot's synthetic packet fields. The tests only establish that a missing wrist or momentary low-confidence pose does not force recalibration, that a cached preview texture remains bound, and that source-unsafe GO is blocked. Observe real webcam footage with one moving child, deliberate wrist occlusion, 0/2 classmates, and a camera reconnect on a school PC to assess actual skeleton flicker and transport reliability. Also separately confirm classroom audio and GPU camera FPS.

**Changed by this QA worker:** new `test_calibration_success_no_loop_20261028.gd`, this report, and only the four specifically reauthorized legacy QA scripts above. **Not changed:** any production `.gd`/`.tscn`, assets, unrelated test/capture scripts, camera service implementation, database, or Git history. The source-authenticity rules were not relaxed.
