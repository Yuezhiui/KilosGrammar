# Camera, StudentLock, Play/Tutorial Score Retention — Synthetic QA (28 October 2026)

> **Historical gameplay note (29 October 2026):** References below to the definitive Human Plane as pure 2D reflect the older build; the current user-approved game uses native 3D airplane and torus visuals alongside authoritative 2D HUD/collision guides. The obsolete pure-2D-only resource-prune QA was retired. See `docs/asset-prune/spotlight-project-cleanup-20261029.md`.

**Ownership:** This document and the new dedicated `tools/test_camera_eight_classroom_scenarios.py` and `tools/test_play_score_retention_no_cleanup_stress.gd` QA files only. Production workers own `student_lock.py`, `pose_worker.py`, `pose_service.gd`, Play/Menu, Settings, the main 2D Human Plane scene, and asset deletion. The tests do **not** open a physical webcam, load YOLO model weights, contact live PostgreSQL, create teacher records, persist school scores, or call an actual hardware inference API.

## Eight classroom scenarios

Run `py -3.11 -m unittest discover -s tools -p test_camera_eight_classroom_scenarios.py -v` (Python standard-library unittest; no `opencv-python` dependency required for this file). All **eight tests PASS** against the actual `ui/vision/student_lock.py` and `pose_worker.py` joint and preview helpers:

| No. | Synthetic input | Safety assertions |
|---|---|---|
| 1 | One stationary child in center for multiple timestamped frames | No premature enrollment; after hold, exactly that track ID gets lock; steering waits for two fresh consistent observations |
| 2 | One locked child and a smaller classmate walking along the side of the image | Child retains lock; candidate skeleton is independently visible but passive; bystander never steers |
| 3 | Brief small box-edge overlap followed by substantial close overlapping person boxes | Minor non-crossing doesn't revoke owner; crossing freezes command and demands new enrollment instead of guessing identity |
| 4 | Full occlusion/invalid torso while an occluder is visible, followed by empty scene and player return | No control by occluder, no ghost last-frame skeleton, fresh clear-view gap then stable solo enrollment required |
| 5 | Two equally prominent, stationary children in center | No arbitrary lock even after 36 source frames; request unambiguous solo student |
| 6 | Original player briefly disappears and returns with same ID, then ByteTrack identity switches | Brief uncontested return may resume; swapped ID can never take over until the view clears and fresh prolonged solo enrollment succeeds |
| 7 | Synthetic bright (high-confidence landmarks), dim (low-confidence landmarks), and one/both missing wrists | Measured bright torso/steering accepted; low-confidence joints and missing both wrists denied; one measured wrist suffices during actual steering; no false drawn bones |
| 8 | Five consecutive completed/restarted rounds with new track IDs, stale and implausible steering | Every new round enrolls separately; two independent consistent observations needed for steering; abrupt single-joint jump never immediately moves the game |

**Critical qualification for scenario 7:** Synthetic brightness here means **mocked keypoint confidence values**, not images passed through YOLO in bright and dim lighting. These tests cannot prove sensor exposure tolerance or classroom inference robustness. An actual camera and student acceptance test must cover real lighting, crowd movement and model FPS.

## Persistence never performs automatic cleanup

`tools/test_play_score_retention_no_cleanup_stress.gd` exercises the real main-menu routing and the existing in-memory **no-socket** test backend. **PASS 95 assertions:** 3 games × 2 modes × 3 repeated completed verified Play rounds generate **18 individually retained `complete_round` requests**, all acknowledged by fake success responses. The mock request history is append-only; zero `delete_all_data`, `delete_data`, `import_data_csv`, or any automatic cleanup command is emitted by saving. Offline/aborted sessions are unsaved, prior completed mock requests remain, and Tutorial cannot save/register even when injected with a spoofed verified-lookup flag. This verifies **request creation and routing**, not actual PostgreSQL commit durability—only a safe opt-in real DB integration test can confirm that separate property.

## Existing independent regression suites executed

| Test | Result |
|---|---|
| `py -3.11 -m unittest ui.vision.test_pose_multi_person_resilience -v` | **PASS 8/8**, preview role isolation, crossing, occlusion and preview-send recovery |
| Python offline suites `test_student_lock`, `test_stationary_plane_steering`, `test_pose_preview_skeleton`, `test_pose_latency_offline`, `test_pose_worker_latency`, `test_pose_startup_preview` (with `PYTHONPATH=ui/vision`) | **PASS 40**, including 13 optional-dependency skips |
| `tools/test_pose_multi_person_bridge.gd` | **PASS 14** |
| `tools/test_pose_preview_freshness_audit.gd` | **PASS 25** |
| `tools/test_shared_camera_lock_occlusion_stress.gd` | **PASS 203**, Play/Tutorial and all games at three screen sizes |
| `tools/test_shared_calibration_entry_compare_stress.gd` | **PASS 197**, shared live calibration for the two entry paths |
| `tools/test_play_tutorial_session_isolation_stress.gd` | **PASS 276**, verified Play versus unregistered/unsaved Tutorial/aborted Play |
| `tools/test_play_navigation_persistence.gd` | **PASS 32**; Godot printed **2 ObjectDB instances / 1 resource still in use at exit**, needing separate fixture teardown review |
| `tools/test_camera_only_tracking_recovery.gd` | **PASS 129**, migrated fixture |
| `tools/test_settings_mute_retirement.gd` (Settings worker owns) | **PASS 34**, removed obsolete Mute All Audio switch; Master 0% mute |
| `tools/test_settings_menu_integration.gd` | **PASS**, real mixer sliders, fullscreen and Home navigation |
| `tools/test_settings_redesign_qa.gd` | **PASS**, single Audio & Display page |
| `tools/test_human_plane_retired_3d_prune_qa.gd` (new) | **PASS 19**, obsolete 3D artifacts absent, real native 2D scenes and supplied PNGs retained |

All Godot commands use Godot 4.7.2 from the project root with `--headless --path . --script res://tools/<name>.gd`. Tests exclusively use manual statuses, locally constructed pose packets and test-only fake request sinks, not physical devices or the school database.

## Legacy 3D-only test/asset audit

The definitive runtime Human Plane is **pure 2D** with the user's `BACKGROUND.png`, `PLANE.png`, ARC gate PNGs, `MovingGates` and `UpcomingGates`. Older tests that loaded `WorldView3D`, `Viewport3D/FlightWorld`, 3D toruses and imported FBX plane assets were tests of the **retired** architecture, not applicable to the current 2D spec. Prime owns deletion of old imported assets and incompatible 3D test suites, including former `test_human_plane_3d_*`, `test_human_plane_cloud_flight.gd`, `test_human_plane_final_qa.gd` and `test_human_plane_pose_hitbox_qa.gd`; this worker did not edit or delete those files. The new `tools/test_human_plane_retired_3d_prune_qa.gd` **PASS 19** confirms the old runtime source/scene/assets are absent, and the supplied 2D background, plane and ARC images all remain available. The separate `tools/test_human_plane_2d_arc_screen_stress.gd` and `tools/test_human_plane_2d_perspective.gd` check correct 2D perspective and original sprites. Do not re-add 3D assets merely to satisfy archived tests.

## Unverified requirements / follow-up

The **obsolete Mute All Audio row must be REMOVED** (not added); the Settings owner separately removed the row and owns `tools/test_settings_mute_retirement.gd` (reported PASS 34 checks). Master Volume at **0%** continues to silence audio; Master above zero restores audio, while Music and Effects retain their separate sliders. This worker withdrew an initially contradictory test of a nonexistent new mute switch and did not change any Settings UI or production logic.

Physical classroom and PostgreSQL acceptance still need teacher-supervised real device/database validation, not synthetic inference. Stored student records and actual score retention were not touched by this work. All fake IDs in this QA are non-identifying test literals.
