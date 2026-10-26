# Human Plane 3D QA — updated for smooth rings, scoring and forest

Validated October 26, 2026 with Godot **4.7.2** on Windows; real screenshots were captured on **NVIDIA RTX 3050 6 GB / OpenGL 3.3 Compatibility**. All tests instantiate the real Human Plane PackedScene without opening a camera, touching PostgreSQL, or using the gameplay wrapper.

| Verification | Result | Scope |
| --- | --- | --- |
| `tools/test_human_plane_3d_world.gd` | **PASS 155/155** | Serialized 3D SubViewport, current Camera3D, genuine torus meshes and Label3D, three lanes, distinct materials, loaded resources, HUD on 1280×720 / 1600×900 / 1920×1080, legacy 2D imagery hidden, scene teardown. |
| `tools/test_human_plane_3d_interactions.gd` | **PASS 120/120** | +100 only on valid ring, unchanged score for wrong/missed gates, one heart deducted for each wrong/missed gate, duplicate resolution blocked, 3D plane follows active pose, frozen tracking when arms lowered, opt-in keyboard debug, paused 3D scenery and voice stopped, positive/wrong/missed recorded Catch voice cues and resource cleanup. |
| `tools/test_gameplay_nonnegative_scoring.gd` | **PASS 342/342** | All 18 combinations of three resolutions × Seconds/Lives × Easy/Normal/Hard. Starting score 325 stays 325 after wrong/miss, rises to 425 after correct, never double-counts; results and HUD agree; time and hearts preserved. |
| `tools/test_human_plane_3d_motion_performance.gd` | **PASS 377/377** | 30/60 FPS forward ring interpolation, equivalence after equal elapsed time, per-frame movement bounds, pause/resume, independent blue/green/orange rings, GPU MultiMesh forest/grass, fixed number of scene nodes during recycling, 12 mount/unmount cycles with bounded object count. |
| `tools/test_human_plane_3d_visual.gd` | **PASS 6/6 valid GPU captures** | Real graphical renderer at 1280×720, 1600×900 and 1920×1080; near and distant rings at each. Pre-capture check explicitly verifies real 3D world, camera, and TorusMesh so broken scenes cannot produce false passing screenshots. |
| `tools/test_human_plane_fixed_score_speed.gd` (existing) | **PASS 271/271** | Existing speed/streak/lives checks now assert no deductions for wrong or missed gates and retain +100 correct answers. |
| `tools/test_human_plane_body_steering.gd` (existing) | **PASS 696/696** | Pose eligibility, smooth 30/60 FPS body steering, tracking-loss freeze and calibration across difficulties and modes. |
| `tools/test_human_plane_modes.gd` (existing) | **PASS** | Seconds 60 seconds and Lives three chances in all six mode/difficulty combinations. |

The resulting user-visible screenshots are under Godot's `user://` path:

`_qa_human_plane_3d_1280x720_distant.png`, `_qa_human_plane_3d_1280x720_near.png`, `_qa_human_plane_3d_1600x900_distant.png`, `_qa_human_plane_3d_1600x900_near.png`, `_qa_human_plane_3d_1920x1080_distant.png`, `_qa_human_plane_3d_1920x1080_near.png`.

On this Windows machine, `user://` is `C:\Users\Yue\AppData\Roaming\Godot\app_userdata\KilosGrammar\`. The 1600×900 near capture was inspected directly: mountains, grassy forest, tree rows, blue/green/orange word toruses, 3D airplane and the existing title, timer, pause and score HUD are visibly present. Real screenshots require actual graphics hardware; headless checks cannot verify image quality.

Run all four offline tests from `/kilos-grammar`:

```powershell
$godot = 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --script res://tools/test_human_plane_3d_world.gd
& $godot --headless --path . --script res://tools/test_human_plane_3d_interactions.gd
& $godot --headless --path . --script res://tools/test_human_plane_3d_motion_performance.gd
& $godot --headless --path . --script res://tools/test_gameplay_nonnegative_scoring.gd
```

Run the six captures on the real renderer:

```powershell
& $godot --path . --rendering-method gl_compatibility --script res://tools/test_human_plane_3d_visual.gd
```

## Compatibility and remaining QA

The earlier `tools/test_human_plane_fixed_score_speed.gd` version contained obsolete **-40 points** for wrong gates and **-20 points** for missed gates. During this QA session the owning implementation agent updated those assertions, and a rerun now passes **271/271**. This QA worker did not modify that script.

An older editor-layout test, `tools/test_human_plane_editor_layout.gd`, previously reported six HUD exact-position mismatches versus Catch the Word at 1280×720 and 1920×1080. These are separate from the new 3D tests and may require a separate review.

All passing object-lifecycle tests mount and remove scenes under the editor-less SceneTree without retaining children; the test avoids live database or webcam access. This establishes bounded object count during repeated instances but **does not claim a complete GPU memory-leak proof under long classroom sessions**. `test_gameplay_nonnegative_scoring.gd` and its verbose run exited normally without ObjectDB leaks on the final verification. A live YOLO tracking session and an extended GPU/VRAM profile remain appropriate for release QA.
