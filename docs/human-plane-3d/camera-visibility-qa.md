# Human Plane 3D — FINAL RED PLANE camera / scored-lane visibility QA

**Validated October 26, 2026** with Godot 4.7.2, Windows, NVIDIA RTX 3050 6 GB Laptop GPU (OpenGL 3.3 Compatibility). Worker-3 owns only this document and `tools/test_human_plane_3d_camera_visibility.gd`. No production `.gd`/`.tscn`, meshes, FBX, camera services, or databases were modified by this worker. All camera and steering inputs in the test are synthetic; no physical webcam is opened.

## Final independent tests and outcome

| QA | Result | Coverage |
| --- | --- | --- |
| Headless real-scene projection + score alignment | **PASS — 309/309** | Three viewports × three actual scored student centers × three ring progress states; native FBX mesh hierarchy/PBR, screen frustum, actual 2D scored lane selection, 3D world X lane alignment, tight WordLabel3D overlap check and node lifecycle |
| Real RTX 3050 OpenGL GPU | **PASS — 507/507** | All the headless checks plus 27 positive pixel-difference proofs with aircraft visible/hidden, 27 plane-hidden/hidden stability negative controls, source-red color checks, genuine 3D-word regions, and nine representative saved framebuffers |

Representative output:

| Screen | Left/right projected RedPlane size | Center projected size | Plane actually rendered? | Word-label overpaint |
| --- | --- | --- | --- | --- |
| 1280 × 720 | ~109 × 57 px | ~86 × 57 px | Yes: source-red GPU pixel changes | None above strict allowed threshold |
| 1600 × 900 | ~136 × 71 px | ~107 × 71 px | Yes | None above threshold |
| 1920 × 1080 | ~164 × 86 px | ~129 × 86 px | Yes | None above threshold |

The final production model's center projected width is **6.70%** of viewport width and side lanes approximately **8.52%**. This is fully onscreen and confirmed by real GPU image differences. The test logs an **aesthetic advisory** (not a false regression) when apparent width is under 8%; the renderer owner decides whether to enlarge the middle-lane plane while preserving the educational ring text.

## Important authored-anchor versus actual scored-center distinction

The parent `ui/minigames/human_plane.tscn` has editor-authored **GateEnd Control container anchors** with X center fractions `0.22 / 0.50 / 0.78`. Projecting these *outer Control anchor positions* linearly between original PlaneLeftLimit `0.055` and PlaneRightLimit `0.945` yields body normals approximately **0.185393 / 0.5 / 0.814607**. That was the source of the initial proposed simple ±9.5 visual mapping.

However, **these are not the authoritative collision centers**. The actual scoring function `_lane_hit_at_answer_line()` checks the **visible gate sprite bounds**, which may be narrower than their editor Control boxes, and adjusts for the original PlaneRig/Hitbox center. These dynamically displayed regions differ slightly with viewport scaling and source artwork. The prime's latest gameplay bridge now derives exact values with `_normalized_scoring_lane_centers(_progress_for_answer_line())`, then passes them into `WorldView3D.set_scoring_lane_centers()`. Worker-1's 3D renderer uses those source-of-truth centers when mapping the model to real ring world X positions `[-6, 0, +6]`; it also safely keeps out-of-lane poses away from a valid ring.

The dedicated test **instantiates the full parent game with `camera_live=false` and no database**, retrieves the authoritative per-viewport scored normals, sets `plane_x_norm` to each, calls the real scoring function to verify that left/center/right resolves to **0/1/2**, and then supplies those same coordinates to the actual standalone 3D renderer before `sync_flight()`. This exactly mirrors the production API; it does **not** incorrectly assert that a naked Control anchor midpoint equals the visible child sprite's scored midpoint.

Measured scoring centers:

| Resolution | Scored left norm | Scored center norm | Scored right norm | 3D plane world X at targets |
| --- | ---: | ---: | ---: | --- |
| 1280 × 720 | 0.326785 | 0.493855 | 0.660048 | −6 / 0 / +6 |
| 1600 × 900 | 0.303091 | 0.491826 | 0.679858 | −6 / 0 / +6 |
| 1920 × 1080 | 0.287296 | 0.490473 | 0.693064 | −6 / 0 / +6 |

**This matters:** attempting to match the simple 0.1854 raw anchor instead of the actual scored sprite center makes the plane appear outside the ring even when gameplay correctly scores an answer. The earlier test deliberately caught a mismatch when it used those outer anchors; after updating the QA fixture to respect the real collision contract, it passes without production changes.

## Camera and GPU methodology

The test instances the actual `res://ui/minigames/human_plane_3d_view.tscn` scene. It recursively gathers the original 20+ imported RedPlane `MeshInstance3D` parts and original material surfaces, aggregates each `part.global_transform * part.mesh.get_aabb()`, and projects all eight global corners with the active native `Camera3D`. Each of the 27 3D cases must satisfy:

- Real meshes/materials exist, camera is active, all eight aircraft corners are in front of camera, and 3D viewport dimensions match target resolution.
- Projected plane is **within a four-pixel viewport margin** and neither practically invisible nor huge (hard width guard 4%–50% of screen).
- Both the actual scored-lane world's X coordinate and the native ring center world X are `−6/0/+6`, with tolerance 0.25 world units for the plane.
- All three actual `Label3D` words (**APPLE**, **TEACHER**, **DOG**) are located using measured font/string size, 3D pixel scale, global transform, and native camera projection. The source plane bounding rectangle cannot cover more than 18% of a word rectangle; the real GPU additionally checks at most 2% of pixels within each word region are affected by red aircraft.

Real-GPU mode renders *the identical frozen 3D scene* once with only `RedPlane.visible=true` and again with only `RedPlane.visible=false`. For each projected aircraft ROI it requires genuine RGB changes (**at least 24 samples**) and source-red changed samples (**at least 12 samples**) at two-pixel stepping. A second background-only image is captured as a **negative control** and must have at most three changed ROI samples, preventing a shifting torus/sky/scenery from falsely passing as aircraft. A few frames are allowed between toggles to avoid reporting stale GPU framebuffer content. Renderer/world children are removed on teardown.

The final camera remains scene-authored and the current rig depth is approximately **Z=8** (the worker-1 target was revised from the earlier Z=13 during iteration to preserve camera framing and actual scorer lane alignment). The test does not hardcode a preferred camera Z. Its role is to verify current genuine visibility, accurate scoring-lane presentation and ring word legibility.

## Screenshot paths

Nine GPU proof captures (each plane visible, never background-only) are saved under `user://`, which maps locally to `C:\Users\Yue\AppData\Roaming\Godot\app_userdata\KilosGrammar\`:

```text
_qa_human_plane_3d_camera_1280x720_far_left.png
_qa_human_plane_3d_camera_1280x720_mid_center.png
_qa_human_plane_3d_camera_1280x720_near_right.png
_qa_human_plane_3d_camera_1600x900_far_left.png
_qa_human_plane_3d_camera_1600x900_mid_center.png
_qa_human_plane_3d_camera_1600x900_near_right.png
_qa_human_plane_3d_camera_1920x1080_far_left.png
_qa_human_plane_3d_camera_1920x1080_mid_center.png
_qa_human_plane_3d_camera_1920x1080_near_right.png
```

The actual **1280×720 near-right screenshot was visually inspected**: a red four-engine FBX plane flies directly below the orange right ring, the word **DOG** remains legible, and no part of the plane is cut off by viewport edges. The other resolutions also pass the source-red GPU visibility and word-overpainting checks.

## Rerun commands

```powershell
$godot = 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --script res://tools/test_human_plane_3d_camera_visibility.gd
& $godot --path . --rendering-method gl_compatibility --script res://tools/test_human_plane_3d_camera_visibility.gd
```

**Conclusion:** The current view renders the actual red FBX, keeps it legible and onscreen, aligns **actual scored body positions** with the same three 3D ring centers, and preserves all three answer words. This is camera/rendering QA, not a physical webcam calibration or database test.
