# Human Plane pure-2D cleanup and arc readability QA — 28 October 2026

> **Historical state, superseded 29 October 2026:** This document describes an earlier pure-2D implementation. Current Human Plane uses the real downloaded airplane and native 3D torus world; its pure-2D-only QA was retired during cleanup. See `docs/asset-prune/spotlight-project-cleanup-20261029.md`. Do not remove the current 3D scene chain to satisfy these older observations.

## Active gameplay architecture

- `res://ui/minigames/human_plane.tscn` is the **only Human Plane gameplay scene**. It owns an editor-authored `FlightBackground` TextureRect, three moving and three preloaded original 2D arc gates, `PlaneRig/PlaneArtwork`, the authoritative `PlaneRig/Hitbox`, `FlightPaths` guides, and the unchanged game HUD.
- The foreground plane is `res://Components/Gameplay/Human Plane/PLANE.png`; the scene background is the original `BACKGROUND.png` from the user-supplied PLANE folder; the left, center, and right arcs reuse the existing purple, green, and blue PNG resources.
- `human_plane.gd` computes inverse-depth apparent gate progress from `focal / (focal + depth)` and interpolates **the same editor-authored gate rectangles** used by visible artwork and score collision. No `WorldView3D`, `Camera3D`, `Node3D` or 3D-physics path remains in the active game.
- The user-approved original curved **ARC** shapes remain, not rectangle replacements. Larger word fitting and much quieter/later upcoming-gate preview keep the active three answers readable. Near scoring arc paths were deliberately left at their original authorable coordinates: experimental enlargement changed boundary-hit behavior and was reverted after regression testing. Plane art and other HUD geometry were not moved.

## Removed legacy resources

- Deleted `ui/minigames/human_plane_3d_view.tscn`, `human_plane_3d_view.gd` and its script UID, the dedicated `human_plane_3d_ring.gd`, `human_plane_3d_mountains.gd`, and `human_plane_3d_foliage.gd` scripts and their UIDs.
- Deleted the retired `Components/Gameplay/Human Plane/3D/` subtree (old FBX/glTF models, PBR assets, mountains, vegetation, cloud sky, resource imports and accompanying license records). None of these files is needed by the retained pure-2D game.
- Removed now-irrelevant 3D-only QA scripts and 3D-specific design documents; migrated projectwide scene inventory and relevant movement/collision tests to the 2D contract. Historical asset-pruning notes outside the active docs may still describe prior experiments; they are not runtime dependencies.
- Before any deletion, archived the retired local 3D project assets/source (including user-local scene edits) to `C:\Users\Yue\Documents\GODOT\KilosGrammar_legacy3D_archive_2026-10-28.zip` **outside the active project**. Archive verified with 91 ZIP entries and retained only as a rollback copy. Do not ship that archive or any unverified private 3D models.

## Offline validation (no hardware and no live student database)

- `tools/test_human_plane_retired_3d_prune_qa.gd` — no old 3D resources or runtime dependencies, all original 2D art present.
- `tools/test_human_plane_2d_perspective.gd` and `tools/test_human_plane_2d_arc_screen_stress.gd` — perspective, gate order and readable labels, including OpenGL GPU screenshot QA at 1280×720, 1600×900 and 1920×1080.
- `tools/test_human_plane_collision_boundary.gd`, `test_human_plane_motion_collision.gd`, `test_human_plane_continuous_flight.gd`, `test_human_plane_visual_cleanup.gd`, `test_human_plane_speed_multiplier.gd` — scoring boundaries, smooth input, passing waves, pause and retained earned speed.
- `tools/test_all_scenes_bruteforce.gd`, `test_component_prune_integrity.gd`, and `test_projectwide_orphan_integrity.gd` — clean scene inventory and source/import dependencies.

**Acceptance limitation:** Real classroom camera, child occlusion under poor light, full Play-to-PostgreSQL persistence, and a second exported Windows EXE still require supervised hardware testing. These offline tests are not evidence that a real webcam/teacher database has passed.
