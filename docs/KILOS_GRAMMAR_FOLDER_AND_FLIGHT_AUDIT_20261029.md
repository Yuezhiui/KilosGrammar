# KILOS GRAMMAR — feature folders, downloaded 3D aircraft and cleanup audit

Date: 2026-10-29. Godot: 4.7.2. This is a file-path and rendering integration audit, not a physical classroom/camera performance certification.

## Active folder organization

| Feature | Scene/script directory | Notes |
|---|---|---|
| Main menu | `ui/main_menu/` | Original `main_menu.tscn`, supporting .gd scripts and original .gd.uid sidecars; project entry remains the same scene UID |
| Catch the Word | `ui/minigames/catch_the_word/` | `catch_word.tscn`, `catch_word.gd`, separate character and HUD subfolders |
| Balloon Popping | `ui/minigames/balloon_popping/` | `balloon_popping.tscn`, script, and `balloon_art/` scenes |
| Human Plane | `ui/minigames/human_plane/` | `human_plane.tscn`, controller, native `human_plane_flight_world_3d.tscn` and 3D viewport wrapper |
| Shared minigame vocabulary | `ui/minigames/shared/grammar_bank.gd` | This is live, shared grammar data for all 3 games. **Do not delete.** |
| Play | `ui/play/{activity,topic,difficulty,gameplay,pause,shared}/` | Separate Ready screen retired; gameplay owns countdown |
| Student Setup | `ui/student/setup/` | Existing Score dialog retired; five active grammar choices remain |
| Calibration | `ui/vision/calibration/` | Separate Camera Check retired; `ui/vision/pose_service.gd` remains at its correct autoload path |
| Tutorial | `ui/tutorial/`, `grammar_guide/`, `spotlight/` | Tutorial home stays under the tutorial feature; supplied button art and existing routing preserved |
| Secondary UI | `ui/secondary/{leaderboard,settings,results,credits}/` | Common theme remains `ui/secondary/secondary_theme.tres` |

Existing `res://` paths in source code/tests were rewritten to the new feature paths; scene/script UIDs were kept. See `ui/minigames/MINIGAME_FOLDER_RELOCATION_20261029.md` and `docs/ui-feature-layout-2026-10-29.md` for additional move manifests. The Windows/GUI Godot editor may still have previously-opened old paths in unsaved scene tabs: save/copy any *wanted unsaved work* before closing it, then reopen the project and scenes from the new paths. Do **not** save an obsolete pre-migration editor tab over the new canonical scene. Any already-generated old-path scene duplicates have been retained byte-for-byte as `docs/legacy_scene_autosaves_20261029/*.backup` rather than silently discarded.

## Live Human Plane rendering and editor adjustment

- The flight scene is a genuine `Node3D` .tscn with `Camera3D`, low-cost `WorldEnvironment` sky, separately editable 3D near/far cloud meshes and three native `TorusMesh` ring lanes (purple/green/blue).
- The red airplane is the user's **original downloaded 22-mesh textured glTF** from `C:\Users\Yue\Downloads\01- Cartoon.Plane`, optimized to `assets/models/cartoon_plane/cartoon_plane_1k.gltf` and `plane_basecolor_1024.png`. 4096² source texture -> 1024² color texture means 16x fewer texels. The source original in Downloads was not modified.
- **Drag and drop:** Open `ui/minigames/human_plane/human_plane_flight_world_3d.tscn`. Select `PlaneAnchor/PlaneModelPlacement` and drag, rotate, or resize its local transform. The parent `PlaneAnchor` is script-driven by the authenticated pose/gameplay hitbox, so do **not** edit that as an art offset. Each `Gates/Gate*/Ring` mesh and each `FarClouds`/`NearClouds` child is also individually editable in the native 3D editor.
- `ui/minigames/human_plane/human_plane_hybrid_3d.gd` exposes **plane_width_pixels**, **plane_model_width_units**, **airplane_camera_distance**, and MSAA/viewport quality settings in the Inspector.
- The three ring nodes are **fixed and reused** for every real GrammarBank wave, instead of allocating another set of 3D meshes per question. At the authoritative scored answer-line crossing, all three rings reach the airplane's 3D depth and are immediately culled along with the associated 2D word labels. The same three nodes reactivate for the next wave. This avoids geometric buildup and stale gate collisions while retaining the exact source scoring.
- HUD, mode selection, 60-second clock, three lives, +100 correct, difficulty speed boosts, question cycling, calibration, hand-pose controls and pause/result routing remain governed by the original gameplay controller. No fabricated vocabulary or 3D physics-based scoring was introduced.
- Default project renderer was changed to GL Compatibility (OpenGL 3.3) for broader integrated graphics support; native 720p 4x MSAA and larger native canvas sizes 2x MSAA reduce render bandwidth. Shadows are disabled. This is a goal/compatibility configuration, **not** proof of performance on every integrated laptop.

## Guided Tutorial visual fix

The yellow outer border seen when `START GUIDED TUTORIAL` receives focus was the **4 px yellow Godot focus StyleBox**, not the supplied PNG. Only the StartButton focus override in `ui/tutorial/tutorial_home.tscn` is now empty. The authored green button PNG and its label, size, hover/click animations and routing remain intact.

## Residue audit decisions

| Item | Decision |
|---|---|
| `grammar_bank.gd` | Live runtime shared dependency — **retain** |
| `human_plane_hybrid_3d.*` and `human_plane_flight_world_3d.tscn` | Live native viewport/world dependencies — **retain** |
| Old `flight_lowpoly_3d.*`, `flight_parallax_2d.gd`, two old plane shaders | Originally archived as a standalone, nonproduction mockup; **subsequently retired/deleted** with prototype-only QA and UIDs during the user's 29 Oct redundant `.tscn` cleanup. See `docs/asset-prune/spotlight-project-cleanup-20261029.md`. The active downloaded-plane/torus 3D scenes remain. |
| Older 512px `cartoon_plane_light.gltf` and `plane_color_512.png` | No live references; **archived** under `assets/models/cartoon_plane/legacy/`, leaving the 1K textured import as the live source |
| Two `_inspect_user_*.png` under model assets | Hash-identical duplicates of the actual title PNGs under `assets/ui/game_titles/`; removed only duplicate inspect copies and their import metadata |
| Temporary local 3D QA previews | Discarded project copies after actual native screenshot review. Stable native captures are stored under Godot `user://` |
| Original Human Plane background, PLANE.png, gate PNGs, calibration art | Source/fallback artwork, potentially useful to re-edit and already part of user work — **do not delete** |
| Other showcase screenshot/asset duplicates and unused historical assets | Audit candidates only; **no mass deletion** without confirming manual archive or release usage |

## Distribution caveat

The original model attribution lists Sketchfab **Cartoon Plane** by 3DPolyForge / MahdiHasan, 7,869 vertices and 15,016 polygons. The supplied attribution text does **not** contain explicit redistribution/license terms. Keep that attribution and verify the actual Sketchfab usage license **before distributing a Windows installer containing the model**.

## QA commands (Windows PowerShell)

```powershell
$godot = 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --script res://tools/test_human_plane_native_torus_20261029.gd
& $godot --headless --path . --script res://tools/test_human_plane_motion_collision.gd
& $godot --headless --path . --script res://tools/test_human_plane_mode_speed_lock_20261029.gd
& $godot --headless --path . --script res://tools/test_human_plane_vocab_cycle_strict_modes_20261029.gd
& $godot --headless --path . --script res://tools/test_all_scenes_bruteforce.gd
& $godot --headless --path . --script res://tools/test_ui_feature_layout_20261029.gd
& $godot --windowed --resolution 1280x720 --script res://tools/test_human_plane_native_torus_20261029.gd -- --capture
```

Focused synthetic checks do not validate physical webcam lighting, real children, driver stability, or CPU-only integrated graphics FPS. Do not commit, push, clean or reset the user's existing dirty working tree without a separate instruction.
