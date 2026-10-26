# Human Plane 3D camera and airplane visibility

Godot 4.7.2, 2026-10-26. The issue reported by the user was that the original red FBX airplane was visible from the editor top view but nearly invisible in full-3D gameplay. The relevant presentation files are `ui/minigames/human_plane_3d_view.gd` and `.tscn`. No webcam, calibration, authoritative scoring, source FBX, PBR, or mountain geometry was modified.

## Reproduced cause

In the user-edited scene, `PlayerRig.scale=(0.035,0.035,0.035)`, `RedPlane.scale=1750`, and `PlayerRig.position.z=-0.763`. The tiny FBX's actual 22 mesh surfaces had a world-space wingspan of just **0.067141 world units**. With the Camera3D at `(0,7.25,20.75)`, 65° FOV, looking toward `(0,2.4,-19)`, actual OpenGL screenshots and `Camera3D.unproject_position()` measured:

| Resolution | Originally invisible plane | Final medium plane: GPU projected size | Final screen rectangle (x, y, width, height) |
| --- | --- | --- | --- |
| 1280×720 | 1.73 × 0.75 px | **68.31 × 35.48 px** | (615.38, 525.97, 68.31, 35.48) |
| 1600×900 | 2.17 × 0.94 px | **85.39 × 44.34 px** | (769.22, 657.47, 85.39, 44.34) |
| 1920×1080 | 2.60 × 1.13 px | **102.47 × 53.21 px** | (923.07, 788.96, 102.47, 53.21) |

The same bounds were recorded for distant and near-ring phases because the player's aircraft is anchored to the camera-relative pilot plane, while the rings travel toward it.

## Editor-authored solution

- `PlayerRig` has the user's **exact `(1,1,1)` scale** and is authored at `(0,1.1,8)`. Its descendant imported **`RedPlane` remains exactly 100× scaled in magnitude on each axis**, keeping the original FBX's mirrored X and Z axes. The artist/source FBX and PBR material surfaces were not modified.
- The earlier **`RedPlaneImportNormalization`** intermediary was removed after an isolated successful importer experiment. The original FBX file itself remains untouched; its Godot import configuration now has `nodes/apply_root_scale=true` and `nodes/root_scale=14.5`, baking the tiny source geometry's unit correction into the imported mesh.
- The imported `RedPlane` is now a direct child of `PlayerRig`, with exact 100-scale magnitude, original mirrored X/Z axes, and local Y offset `0.215`, preserving the previous visual altitude. Effective source scale is `1 × (imported 14.5) × 100 = 1450`, yielding **1.5894626379 units** of measured real FBX wingspan, about 36% of the 4.44-unit torus outer diameter. For art direction, adjust only explicitly intended nodes or the import configuration; do not add hidden normalization to the view script.
- The `PlayerRig` origin stays near the gameplay's **Z=7.9 answer plane**. The current downward-looking Camera3D framing and **65° FOV** are retained. The active cloud-flight scene displays a 2D panoramic sky plus low-poly cloud meshes; prior mountains/road/grass are retained but hidden.
- The world view's existing gentle bobbing animation now adds to the **authored Y=1.1**. It no longer snaps the rig to hardcoded Y=2.0 on the first frame.
- All **24 user-authored mountain transformations**, original PBR terrain, real grass-green FBX MultiMesh batches and source trees are preserved; no 2.5D rendering paths were introduced.

## Actual 3D steering follows the authoritative scored hitbox

**Canonical imported plane node path with baked FBX unit normalization:**

```text
WorldView3D/Viewport3D/FlightWorld/PlayerRig/RedPlane
```

The 3D view's `@onready red_plane` path and recursive source-mesh material routines traverse the imported FBX directly. The intermediate pivot path is obsolete; tests or integrations still using `RedPlaneImportNormalization/RedPlane` must return to the direct path. The active Human Plane controller continues to address `WorldView3D` without changes.

The three visibly correct rings have world-X centers **-6, 0, +6**, while the parent's moving quiz art and hitboxes produce live body-X centers that need not correspond to the nominal old lane guides. The parent `HumanPlane.gd` now passes its dynamically computed source-of-truth centers via:

```gdscript
set_scoring_lane_centers(PackedFloat32Array([left_norm, center_norm, right_norm]))
```

The view validates the 3 ordered finite values and maps each of them onto the matching 3D torus's center X. Between scored centers it interpolates continuously; outside the scored lanes, it smoothly approaches X=±8 so the aircraft is visibly out of the torus but remains within the camera. A separate group of exported editor-editable fallback body-X anchors remains for scenes tested without the parent.

This mapping changes **only the 3D rendering position**. The parent continues to decide success, failure, life loss, ambiguity between choices, and score through its existing hitbox/answer-line checks. The renderer does not perform a replacement collision calculation.

## Validation

- `tools/test_human_plane_3d_scale_flow.gd`: measures real imported FBX geometry, inherited scales, near/distant screen-space AABBs at 1280×720 / 1600×900 / 1920×1080, three projected lane alignments at crossing, out-of-range steering visibility, pause freeze, continuous Z travel, and parent->view alignment with the **actual scorer's authored hitbox geometry**. The parent integration test uses `camera_live=false` and never captures a hardware camera.
- `tools/test_human_plane_3d_visual.gd`: creates six real NVIDIA RTX 3050 OpenGL screenshots with the actual gameplay HUD, testing distant/near rings at all three resolutions. The screenshot at 1600×900 was inspected: aircraft at lower center, below the grammar labels, clear of the bottom-right score panel, with 3D mountains/road/PBR models intact.
- The independent world, motion and interaction suites confirm that answer scoring, route UI and 3D movement were retained.

The fix leaves the gameplay-owned `human_plane.gd/.tscn`, pose calibration, the original airplane FBX and every 3D mountain instance unchanged.

### Latest required 1× / 100× scale verification

After the user's final explicit scale correction, Godot 4.7.2 headless editor parsing passed. The focused full-3D scale/rig suite passed **67/67 headless assertions**, and its NVIDIA RTX 3050 OpenGL run passed **145/145 checks** with six real near/distant `user://` captures at 1280×720, 1600×900 and 1920×1080. The current plane center was measured around **Y=1.317916** during the frame, matching the previous composition without elevating the airplane into the words. No QA PNGs need to be stored as project assets.
