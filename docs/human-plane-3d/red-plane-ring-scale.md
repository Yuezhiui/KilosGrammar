# Human Plane full-3D airplane and ring proportions

**Historical scale audit:** This document records the earlier torus and red-plane import correction. The user subsequently requested a further camera/rig visibility repair, so the *current* PlayerRig/RedPlane transforms, pixel bounds, and live scored-lane steering mapping are documented in [camera-rig-visibility.md](camera-rig-visibility.md). Treat numerical rig values below as prior measurements.

Tested on 2026-10-26 using Godot 4.7.2, the original supplied red-plane FBX, and an NVIDIA RTX 3050 OpenGL renderer. The user requested full 3D and abandoned the 2.5D experiment; the gameplay scene's mode selection belongs to the parent Human Plane controller. This update changes presentation geometry only and preserves authoritative scoring and pose input.

## Verified model dimensions

The actual red airplane source FBX has **22 original mesh parts**, imported at tiny source-space dimensions. A Godot recursive mesh AABB inspection found:

| Model state | Wingspan (units) | Height | Depth |
| --- | ---: | ---: | ---: |
| FBX as imported (scene coordinates) | 0.001096 | 0.000452 | 0.000783 |
| Previous `PlayerRig/RedPlane` scale 4100 | 4.494 | 1.855 | 3.209 |
| `RedPlane` scale 1750, measured in `PlayerRig` coordinates | ~1.918 | ~0.792 | ~1.370 |
| Current `PlayerRig` uniform scale 0.035, measured in final world coordinates | **0.067141** | ~0.0277 | ~0.0480 |

The actual original model remains referenced by `human_plane_3d_view.tscn` at `res://Components/Gameplay/Human Plane/3D/red-plane/2b69a53022ec45b396ce8015291cc9ea.fbx`. The source FBX and original PBR maps are untouched. The scene's `PlayerRig/RedPlane` child stores its negative-X, positive-Y, negative-Z **1750** transform in the Inspector; its `PlayerRig` parent also has an editor-authored uniform scale of **0.035**. Both transforms affect the rendered width; adjust them in the scene without altering collision or body-coordinate logic. The full 3D view keeps its material skin detach/restore steps for that source's 22 mesh parts.

## Real torus ring sizing and timing

Each `human_plane_3d_ring.tscn` instance uses a real `TorusMesh`, with `outer_radius=2.22`, `inner_radius=1.78` (formerly 2.87/2.37), an open center, and a `Label3D` in the hole. The three lanes remain X = **-6, 0, +6**, blue/green/orange; 3D text sizing is `min(0.0105, 0.049 / character_count)`, preserving readability for words of varying lengths. The editor default center ring Z was aligned to its left/right companions: active Z=-12, upcoming Z=-26. All sizes, default positions, torus materials, and labels are inspector-editable.

The previous renderer used **two different ring depth slopes** on opposite sides of the answer plane:

- Approach: `lerp(-22, 7.9, progress / answer_progress)`.
- Exit: `lerp(7.9, 20, (progress - answer_progress) / (1 - answer_progress))`.

When `answer_progress=0.5`, that old exit slope was only **24.2 world-units per progress**, compared with **59.8 before crossing**: a **2.47× visual slowdown** just after a correct or incorrect ring.

The renderer now uses a **single continuous linear depth relationship**:

```gdscript
distance_per_progress = (7.9 - (-22.0)) / answer_progress
z = -22.0 + presented_progress * distance_per_progress
```

The ring continues at the same world-space depth velocity beyond the answer line and through the camera's near region. The authoritative collision point remains **Z=7.9** exactly at the gameplay-owned `answer_progress`. Existing bounded 25 ms render prediction, pause freeze, scene recycling, cumulative speed-multiplier setter, and the `sync_flight(...) ` public API remain in place. More correct answers make gameplay progress advance faster, so both the rings and scrolling scenery honor the earned speed increase. An incorrect or missed answer does not trigger visual deceleration in this presentation layer.

## Preservation and verification

The original **24 editor-authored NATURE mountain instances** and their transforms were verified unchanged (SHA-256 of all Mountain headers/transforms: `720FD7E71F6842175416265BEAE271AAF8D0911E4095E689DB76E4AB2FC1F531`). Grass004/Road008A PBR terrain materials, four `MultiMeshInstance3D` original `Grass_green.fbx` bands, and authored FBX tree models remain.

Standalone **`tools/test_human_plane_3d_scale_flow.gd`** checks the original FBX's measured ~1.918 wingspan **relative to `PlayerRig`** and that the final world width respects the separately editable parent scale. The older check mistakenly required ~1.918 in final world space even when the user had set `PlayerRig.scale=0.035`; Godot measured the correct final width as **0.067141097**. The corrected test also checks torus dimensions, 24 mountains, FBX grass batch, ring lanes, word label, authoritative crossing position, 35%/50%/65% crossing-speed continuity and pause freeze. Run:

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_human_plane_3d_scale_flow.gd
```

For actual OpenGL screenshot previews, run the same script without `--headless` and append `-- --capture`. The screenshots are emitted to Godot's `user://` workspace; do not import QA screenshots into production `Components/`. Screen previews at 1280×720 and 1920×1080 were inspected: airplane wingspan and ring diameters are substantially smaller, and the real 3D mountain/PBR/grass scenery is preserved.

**Final validation:** With the inherited-scale regression added, the focused scale/pass-through checks pass **36/36**. Rerun of the full-3D motion/performance suite passed **377/377** and the world/assets suite passed **154/154**. The previous game/pose interaction suite passed **120/120**, and the OpenGL GUI screenshot suite captured **6/6** near and far shots at 1280×720, 1600×900, and 1920×1080. The resulting full-3D 1280×720 near screenshot was inspected: the airplane and torus words are readable, and the source mountains, tree models, and PBR route remain in view.

The old 2.5D selector calls were removed from the 3D-specific motion, world, and interaction QA scripts to match the full-3D-only parent implementation. The parent scene and pose service continue to be maintained by the prime agent and its other workers; this change contains no edits to either.
