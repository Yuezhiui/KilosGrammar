# Shared Play / Tutorial and 2D Human Plane ARC QA

**Scope:** New test scripts and this QA note only. No production source, existing tests, physical webcam, real database, network service or saved student records were changed by this worker. This is an offline mock regression suite for the new 27 October 2026 behavior.

## Contract and test matrices

**One common calibration and gameplay pipeline.** Both Main Menu Play and guided Tutorial select among Catch the Word, Balloon Popping and Human Plane; proceed through the same actual `ui/vision/calibration.tscn` and same camera-backed gameplay wrapper, then share the same scores, timer/lives and pause/resume logic. The calibration intro and model warmup must never credit samples. Catch/Balloon continue to require measured CENTER/RIGHT/LEFT floor-zone holds; Human Plane uses a single measured stationary neutral posture, eight unique fresh source samples and no fabricated side positions. A fake button skip or stale packet must never bypass calibration. Tutorial's practice flag and Play's saving eligibility must be maintained across retries.

**Database isolation.** Only a genuinely completed **Play** session with a confirmed student identity (`student_lookup_connected=true`), a valid ID and online database is eligible for persistence. An unverified Play student remains unsaved; an aborted/paused result remains unsaved. Tutorial never registers a student, never creates a score insert and stays practice-only—even after Retry, high scores, a direct save attempt or the delayed response to a preceding Play save. All DB calls in this suite use the existing deterministic `test_postgres_csv_delete_menu_fixture.gd` and `test_postgres_csv_delete_mock.gd`, whose requests never open sockets. No student identity or score is real.

**StudentLock / camera interruption.** Stress the two entry flows, all three games and three physical viewport sizes with predecoded camera statuses: two people visible but one uniquely locked student, bystander identity switch, an occluded wrist/locked person, camera warming/recovering, two fresh zero-person observations, and same-student reacquisition. The game must suspend after its grace period, preserve scores, avoid a false return-to-camera warning when someone is still visible, and resume without corrupting the round. The real missing-person prompt is appropriate only with recent `camera=true`, actual `people=0`, and a sustained missing-student interval. Camera warmup is simulated as a status, never by starting the real Python/YOLO process or opening a webcam.

**2D ARC first.** The real `ui/minigames/human_plane.tscn` must show supplied original 2D `FlightBackground`, `PlaneRig/PlaneArtwork`, and two independent native `MovingGates`/`UpcomingGates` trios. No `SubViewport3D` may own flight rendering. Test progressively approaching ARC/answer PNG bounds at gate depths 0, 0.15, 0.35, 0.55, 0.78 and 1; each native image's area must grow monotonically, preserve left/center/right order, and keep long answers within the authored word plaque. The same authoritative plane X/hitbox must remain frozen without a valid pose and during tracking loss. Renderer updates alone must not grant points. Verify at 1280×720, 1600×900 and 1920×1080 in repeat scene mount/teardown cycles.

## New regression scripts

From the project root, using Godot 4.7.2 (the installed Windows console executable is `C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe`):

```powershell
godot --headless --path . --script res://tools/test_play_tutorial_session_isolation_stress.gd
godot --headless --path . --script res://tools/test_shared_calibration_entry_compare_stress.gd
godot --headless --path . --script res://tools/test_shared_camera_lock_occlusion_stress.gd
godot --headless --path . --script res://tools/test_human_plane_2d_arc_screen_stress.gd
```

For actual GPU screenshot QA (not a dummy headless renderer):

```powershell
godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --script res://tools/test_human_plane_2d_arc_screen_stress.gd -- --capture
```

The GPU capture files are saved to Godot `user://_qa_plane_2d_arc_1280x720.png`, `user://_qa_plane_2d_arc_1600x900.png` and `user://_qa_plane_2d_arc_1920x1080.png`, outside the repository (on the test PC at `C:\Users\Yue\AppData\Roaming\Godot\app_userdata\KilosGrammar\`). They are intended for inspecting perspective, word legibility and original art without introducing generated `.import` files into version control.

### Verified execution results (27 October 2026)

| New standalone test | Result | Checks |
|---|---|---:|
| `test_play_tutorial_session_isolation_stress.gd` | **PASS**; Tutorial never registers/saves, verified completed Play writes exactly one request, unverified/aborted Play is unsaved, delayed mock callback cannot mark Tutorial saved | 276 |
| `test_shared_calibration_entry_compare_stress.gd` | **PASS**; identical live calibration scene, timestamps, hold bounds and measured results for Play/Tutorial across all three minigames and viewport sizes | 197 |
| `test_shared_camera_lock_occlusion_stress.gd` | **PASS**; two-person lock, bystander ID switch, camera warmup/recovering, occlusion, true zero-person notice and same-student recovery across both entry modes | 203 |
| `test_human_plane_2d_arc_screen_stress.gd` | **PASS**; 2D-only PNG plane, two ARC trios, six perspective distances, long-word text fit, hitbox gating, six mount/unmount trials | 524 |
| Same 2D test on **actual NVIDIA RTX 3050 OpenGL** with `--capture` | **PASS**; three original PNG screenshots at 1280×720, 1600×900 and 1920×1080, captured outside repo | 530 |

`git diff --check` passed. These results verify logic, rendered images and mock protocol behavior but not actual hardware or database persistence. Other agents own the production changes and legacy test migrations.

## Observed findings / limitations

The previous `tools/test_camera_only_tracking_recovery.gd` assumes that a bare `state=lost, pose=false` (without a fresh actual camera result or zero-person detection) must show a missing-child warning after 0.71 s. That conflicts with the current intentional requirement to avoid false warnings while the selected student is occluded, enrolling, or the camera is warming. Likewise, its Human Plane fixture does not establish a one-student verified neutral calibration. It is an **obsolete test fixture**, not evidence that physical recovery failed; this worker did not edit it. The new StudentLock stress explicitly tests both a genuine zero-person alert and the no-false-alert cases.

**Not covered by offline mocks:** real webcam hardware startup latency, CUDA/YOLO model load, Bluetooth/USB camera stability, schoolroom multi-child tracking accuracy, actual physical pose ergonomics, PostgreSQL write durability and server-specific permissions. A supervised device-backed classroom acceptance test is needed to verify those; the tests cannot imply real student sessions were saved.
