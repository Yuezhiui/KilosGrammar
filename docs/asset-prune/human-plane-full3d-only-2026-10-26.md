# Human Plane 3D-only orphan audit — 2026-10-26

**Status: authorized 2.5D cleanup COMPLETE — 22 files deleted.**
The prime explicitly approved deletion after removing all 2.5D
references from `ui/minigames/human_plane.gd` and `.tscn`.
The scope is strictly the discarded 2.5D experiment and its
derivative artwork/tests; original legacy 2D collision artwork and
all full-3D/HUD assets remain protected. Shared QA files are owned
by the separate test agent and were not rewritten here.

**Live follow-up audit:** The prime's updated `human_plane.gd` and
`human_plane.tscn` now contain **zero 2.5D scene, WorldView25D,
environment-view-toggle or F6-A/B routing references**. The 3D scene
also contains no reference to `rendered-sprite.png`. With express
approval, the exclusive files below were deleted; no unrelated source
was changed. The main scene continues to reference `PLANE.png` and
all three original `human_plane_gate_*.png` as native guide textures.
It does not reference `BACKGROUND.png` anymore.

## Deleted artifacts — exact 22-file manifest

### Exclusive 2.5D production code (3 files)

- `ui/minigames/human_plane_25d_view.gd`
- `ui/minigames/human_plane_25d_view.gd.uid`
- `ui/minigames/human_plane_25d_view.tscn`

### 2.5D-only focused tests (8 scripts + 8 UIDs)

- `tools/test_human_plane_25d_ab_visual.gd[.uid]`
- `tools/test_human_plane_25d_integration.gd[.uid]`
- `tools/test_human_plane_25d_motion.gd[.uid]`
- `tools/test_human_plane_25d_red_plane_diagnostics.gd[.uid]`
- `tools/test_human_plane_25d_red_plane_gpu.gd[.uid]`
- `tools/test_human_plane_25d_visual.gd[.uid]`
- `tools/test_human_plane_25d_world.gd[.uid]`
- `tools/test_human_plane_environment_modes.gd[.uid]`

The diagnostics and GPU render tests load the same original red FBX, but
exist solely to validate the **discarded 2.5D sprite experiment**.
Retain dedicated full-3D FBX, PBR, ring, scoring and performance tests.

### 2.5D-only documentation and generated sprite

- `docs/human-plane-3d/2.5d-experiment.md`
- `Components/Gameplay/Human Plane/3D/red-plane/rendered-sprite.png`
- `Components/Gameplay/Human Plane/3D/red-plane/rendered-sprite.png.import`

The generated sprite is referenced by the discontinued 2.5D scene and
its dedicated tests only, **not** by the full-3D flight renderer.
It is a render derivative, not the source aircraft. Retain all original
source FBX meshes and five textures, `red_plane_pbr.tres`, their imports
and `Cartoon Plane by MahdiHasan.txt` attribution.

### Retained, conditional original 2D scene art (5 PNG + 5 imports)

- `Components/Gameplay/Human Plane/BACKGROUND.png`
- `Components/Gameplay/Human Plane/PLANE.png`
- `Components/Gameplay/Human Plane/human_plane_gate_purple_LEFT.png`
- `Components/Gameplay/Human Plane/human_plane_gate_green_CENTER.png`
- `Components/Gameplay/Human Plane/human_plane_gate_blue_RIGHT.png`
- The matching five `.png.import` files.

These are **not** automatically safe just because the visible gameplay
now uses 3D. At audit time, `human_plane.tscn` still declared
`r_gate_left`, `r_gate_center`, `r_gate_right` and `r_plane` and
bound them to authored `GateArtwork`/`PlaneArtwork` children; the
2.5D scene also held `BACKGROUND.png`. Native, editor-draggable
`FlightPaths`, `PlaneRig/Hitbox`, `MovingGates` and
`UpcomingGates` may still be required to resolve hits **independent**
of whether their artwork is visually hidden. Do not delete native
collision/plane/gate nodes merely to prune textures: preserve their
control bounds and gameplay methods. Remove image bindings, their
serialized resources and derived unused files **only when** the
main scene and QA expectations have been safely migrated.

## Other code/test references that must be updated by owners

- `human_plane.gd` formerly contained `_world_25d`, F6 toggle handling,
  `environment_view_mode`, `set_environment_view`,
  `_apply_environment_view` and 2.5D/3D conditional
  `sync_flight` dispatch. The prime removed these, retaining the
  full-3D-only `WorldView3D` synchronization. This cleanup did not
  edit the main game script or scene.
- `tools/test_human_plane_3d_interactions.gd` and
  `tools/test_human_plane_3d_motion_performance.gd` invoke
  `set_environment_view(1)` unconditionally and will need 3D-only
  expectations. `tools/test_human_plane_3d_world.gd` and
  `tools/test_human_plane_speed_multiplier.gd` make guarded
  calls, which can be simplified after the mode API disappears.
- `tools/test_human_plane_assets_pose.gd` asserts the five exact
  legacy PNG names/hashes/dimensions and authored TextureRect paths.
  `tools/test_human_plane_visual_cleanup.gd` asserts the same
  hashes. `tools/test_human_plane_catch_hud_clone.gd` explicitly
  asserts `PlaneRig/PlaneArtwork` is bound to `PLANE.png`.
  A 3D-only test migration must update those **before** deleting
  the 2D PNGs. Do not blindly delete these QA suites: they also
  verify unrelated critical pose/HUD geometry.
- Current projectwide asset inventory and historical documentation
  contain descriptions of the old 2.5D paths, but narrative mentions
  are not executable resource dependencies. This report supersedes
  their 2.5D retention guidance without rewriting another worker's
  owned files.

## Protected active resources

Preserve the entire **full-3D** chain: `human_plane_3d_view.gd/.tscn`,
`human_plane_3d_ring.gd/.tscn`, 3D mountain and foliage scripts,
RED PLANE original FBX/PBR/attribution, road/grass material resources,
grass MultiMesh bands, trees, mountains, skybox and associated imports,
and all shared gameplay HUD/Catch Word scene art and font paths.
Do not remove `PlaneRig/Hitbox` or `FlightPaths` because they
participate in the scoring and body-steering collision contract.
The old `3D/toy_plane/**` is a different 3D-model pruning decision,
outside this narrowly assigned 2.5D/2D asset scope.

## Verification and remaining separately owned tasks

The delete routine checked **all 22 explicit paths**, verified each
was inside the project, verified the main script/scene and full-3D
view no longer referenced the experiment/sprite, and removed only
those 22 files in one guarded operation. No Git reset/commit, database,
camera or calibration edit occurred.

| After cleanup | Observed result |
| --- | --- |
| Godot 4.7.2 headless editor import/parse | Completed, exit code 0 |
| Cumulative speed multiplier | PASS, 345 assertions / 0 failed |
| Fixed scoring | PASS, 271 / 0 |
| Full-3D PBR / grass | PASS, 53 / 0 |
| Full-3D ring motion/performance | PASS, 377 / 0 |
| Full-3D world nodes / HUD | PASS, 154 / 0 |
| Strict final QA | 240 checks / 1 failed: *obsolete expected 32 scenes, actual 31* |
| Component prune integrity | 926 checks / 1 failed: same obsolete 32-scene assertion |
| Asset cleanup integrity | 758 checks / 1 failed: same 32-scene assertion; **zero** missing resource paths, references, serialized IDs or unused declarations |
| Projectwide orphan integrity | 2 failures: unrelated full-3D QA review PNGs without .import; other scene/resource dependencies resolved |

The three **scene-count assertions** need updating to 31 by the
owner of shared QA tests; this scoped asset worker has not touched
those files. The projectwide checker found
`docs/human-plane-3d/_review_scaled_far.png` and
`_review_scaled_near.png` (2 orphan full-3D screenshots with no
`.import`). They are **not part of the 2.5D experiment**; verified
by visually inspecting their 3D aircraft/terrain scene, so they were
left for the full-3D QA owner to move/delete if no longer needed.

During one later batch, another agent's concurrent edits to
`ui/vision/pose_service.gd:278` temporarily triggered an
indentation parse error, causing dependent calibration/camera
brute-force testing failures. The isolated Human Plane tests above
still reported PASS. The vision script is outside this worker's
owned files; the prime was notified so its owner can fix and rerun
the complete project suite. **No full-project all-green result is
claimed for this transient workspace state.**

## Final full-3D-only test migration — latest QA result

The two remaining stale suites were subsequently migrated under
explicit QA-only authorization, **without modifying production scenes
or scripts**. This section supersedes the earlier intermediate
failing counts above.

- `tools/test_all_scenes_bruteforce.gd`: 31 scenes now replace the
  deleted 2.5D scene's former 32-scene baseline. The original
  3-resolution × 2-cycle scene lifecycle, navigation, button,
  visibility and destructive-action safety checks remain intact.
- `tools/test_human_plane_visual_cleanup.gd`: preserved byte-exact
  source PNG checks for the **four live plane/gate guides**, all
  pixel-perfect Catch Word HUD assets shared with Human Plane, and
  authoritative scene-owned control positions. Three deliberately
  customized Human Plane HUD positions are now checked for their
  actual editor-authored design: TitlePlaque and PromptLabel both
  sit 19px below their Catch Word counterparts, and TimeLabel remains
  properly centered **inside** TimerPlaque with matched typography.
  The native `AnswerLine` is **retained**, invisible and noninteractive,
  because it marks the full-3D game's scoring crossing; the old
  assertion that it must be deleted was incorrect. Actual
  `res://Components/Gameplay/Human Plane/PLANE.png` and shared
  Catch Word `title_board.png` paths replace pre-migration aliases.
- Additional behavior verified: **native full-3D Viewport/camera**
  exists while `WorldView25D` is absent; Pause is a live keyboard-
  focusable native button, emits the original safe `requested("pause",
  payload)` signal exactly once, and stops/resumes the actual game.
  Score, lives, Seconds/Lives HUD visibility, source artwork and
  zero-generated-overlay checks remain mandatory.

| Godot 4.7.2 suite (after final QA migration) | Verified result |
| --- | --- |
| Editor import/parse | PASS, exit 0 |
| All scenes brute-force, 31 scenes / 186 offline instances / 15 live mounts / 468 buttons | **PASS 1,722 / 0** |
| Full-3D Human Plane visual + HUD + pause/navigation | **PASS 508 / 0** |
| Strict Human Plane final QA | **PASS 240 / 0** |
| Projectwide orphan integrity | **PASS 2,794 / 0** |
| Component prune integrity | **PASS 924 / 0** |
| Asset cleanup integrity | **PASS 758 / 0**, 0 missing references |

No original source textures, native collider/flight-guide nodes,
HUD controls, 3D models, files or assets were changed in this final
QA migration, and no live database or camera was touched.
