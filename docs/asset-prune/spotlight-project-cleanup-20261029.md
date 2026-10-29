# KILOS GRAMMAR — Spotlight and projectwide redundant-resource cleanup

> **Historical earlier state, superseded later on 29 October:** The user subsequently instructed removal of the ENTIRE Spotlight UI and shared scene, including the former DynamicTitle, its three minigame instances, and its unused PNG/import artwork. This document describes the earlier intermediate cleanup. The new authoritative manifest is `docs/asset-prune/spotlight-feature-removal-20261029.md`; its 18 English WAV recordings were retained but are no longer hooked to playback.

Date: 2026-10-29 · Godot 4.7.2 · scope: current dirty Windows workspace, **no Git commit or push**.

## Serialized Spotlight controls

Removed the shared tutorial-only `Overlay/MovementFeedbackPanel`, its `MovementHeading` and `MovementStatus` labels, and the obsolete movement-status handler/state and `StyleBox_card` subresource. `CaptionCard/Header` was **not blindly deleted**: it was renamed to the editor-authored `CaptionCard/DynamicTitle` (same node unique ID), because each non-prompt step needs a different title. `Caption`, per-game focus rectangles, arrows, navigation artwork and real Button hitboxes, replay, English voice, music ducking, and 5 steps per active game/mode remain.

The three minigame `.tscn` files preserve their embedded `GuidedSpotlight` and Inspector-draggable art while updating the inherited DynamicTitle editor description. The redundant movement panel does not appear in normal Play or Guided Tutorial. Guided Tutorial still starts only after measured calibration, before the game timer.

## Source assets and files

| Action | Paths / evidence | Reason |
|---|---|---|
| **Relocated, not deleted** | `Components/Gameplay/Unsorted User Uploads/5e404e45-74fb-4f27-b5e9-eaf8aadb98e3.png[.import]` → `Components/Main Panel/Original/` with same filename and `.import` | Unique original main-menu cloud/star sprite sheet; source SHA256 `767356407EA43475CCC013462E6FB496C86AB2FC93A5C2997F1C328E53BB512A`; texture import UID `uid://cfq6hwgit0s2u` preserved and reimported. `ui/redesign/assets/extract_phase2.py` documents five derivative art crops. The now-empty **Unsorted User Uploads** folder was removed. |
| **Deleted** | `ui/minigames/human_plane/legacy/flight_lowpoly_3d.tscn`, two retired `flight_*.gd` files, their `.gd.uid` files, two old mockup `.gdshader` files and their UIDs (9 files total), plus `tools/test_human_plane_lowpoly_3d_visual_20261029.gd[.uid]` (2 files) | Optional primitive-box prototype with no production caller; its sole test instantiated only that prototype. Replaced in live gameplay by the **retained** `human_plane.tscn → human_plane_hybrid_3d.tscn → human_plane_flight_world_3d.tscn` chain using the downloaded real 3D plane and torus rings. Pre-deletion file hashes are available in the execution log. |
| **Deleted** | `tools/test_human_plane_retired_3d_prune_qa.gd[.uid]` (2 files) | An untracked historical test demanded **pure 2D gameplay** and rejected every Node3D/SubViewport, directly contradicting the newer user-approved real airplane and torus 3D design. No production/test runner referenced it; current `test_human_plane_native_torus_20261029.gd` and `test_human_plane_hybrid_3d_20261029.gd` cover the current architecture instead. Original 2026-10-28 QA documentation remains as historical evidence. |
| **Deleted** | Nine orphan `tools/_occlusion_tmp_*.png.import`, `tools/_tmp_catch_half_apple_*.png.import`, `tools/_tmp_human_plane_25d_*.(png\|jpg).import`, and `tools/_tmp_plane_heading_*.png.import` | Each source screenshot was already missing; its import UID had no external resource consumer. Deleted individually, not via recursive wildcard removal. |
| **Deleted** | `tools/_temp_lowpoly_view.png` and its `.png.import` | Generated, unreferenced one-off QA preview, not a supplied art asset. |
| **Removed empty directories** | `Components/Settings/Secondary`, `ui/minigames/catch_the_word/catch_hud/topics`, `ui/minigames/catch_the_word/catch_hud/generated/character`, `ui/minigames/catch_the_word/catch_hud/generated/replacement`, and the subsequently empty `ui/minigames/catch_the_word/catch_hud/generated` parent | No files/subdirectories at deletion time; no scene/resource content removed. The `catch_hud/README.md` and its containing folder remain. |

Exact removed orphan import sidecars (all were under `tools/`, with missing source file and no other source UID consumer):

| File | Former import UID |
|---|---|
| `_occlusion_tmp_bear_1280x720.png.import` | `uid://csl1ef1vi2e85` |
| `_occlusion_tmp_panda_1920x1080.png.import` | `uid://om2xgjqujxef` |
| `_tmp_catch_half_apple_bear_1280x720.png.import` | `uid://qftebukhvtf2` |
| `_tmp_catch_half_apple_lion_1280x720.png.import` | `uid://diwrctgagi4n0` |
| `_tmp_human_plane_25d_0.png.import` | `uid://bjc6qog1lsbmf` |
| `_tmp_human_plane_25d_1.png.import` | `uid://ds6tfq0r383dd` |
| `_tmp_human_plane_25d_1_small.jpg.import` | `uid://cl6km7e10f5li` |
| `_tmp_plane_heading_1280.png.import` | `uid://bixpryp8sjook` |
| `_tmp_plane_heading_1920.png.import` | `uid://bqxrgq56p8rmt` |

Retired stand-alone prototype `.tscn` SHA256: `AF96880F86453C0ACB52849DA4741495542736913919ECB9C627F4C8F00D13B6`. No remaining production script or scene referenced its original path.

## Kept by deliberate dependency/safety review

- All **18 full-English tutorial WAVs** and live `.wav.import` sidecars, plus Spotlight NewDesign user PNGs.
- `Components/Gameplay/Calibration/STARS.png` and `BACK.png`: unique source CALIB artwork, even when not serialized directly. `Components/Gameplay/Human Plane/Parallax/cloud_wisp_2d.png`: unique untracked 2.5D source, reserved pending its art owner's decision.
- Calibration and Leaderboard `BACKGROUND.png` files share content hash but have **separate live scene paths**. Do not delete either without migrating references.
- Three byte-identical `balloon_blue/green/purple.tscn` scene templates are **individually referenced** by the Balloon game and QA. Duplicate bytes alone are not proof of an orphan; consolidation was not attempted.
- Active imported 3D plane PNGs under `assets/models/cartoon_plane/` and game-title images under `assets/ui/game_titles/` are allowed in the asset-integrity test by an **exact four-path whitelist**. All four imports and textures must decode; any additional unclassified PNG outside Components still fails the test.
- Unique original artwork, camera/Yolo models, main-menu controls, PostgreSQL/CSV schema, gameplay UI and downloaded model source are not modified or blindly pruned.

## Post-cleanup validation (headless unless marked)

| Test | Result |
|---|---|
| Godot `--headless --editor --path . --quit` | PASS, exit 0; relocated `.import` re-generated with new cached texture path and same UID |
| `tools/test_spotlight_overlay.gd` | PASS 138 checks |
| `tools/test_spotlight_prune_20261029.gd` | PASS 683 checks |
| `tools/test_spotlight_embedded_tutorial_20261029.gd` | PASS 1,459 checks across 3 games × 3 viewports × 2 modes; **native OpenGL 3 also PASS** (NVIDIA RTX3050) |
| `tools/test_tutorial_voice_integration_20261029.gd` | PASS 195 checks, 18 English-only voice mappings |
| `tools/test_tutorial_voice_assets_20261029.gd` | PASS 620 checks, 18 voice files intact |
| `tools/test_calibration_mode_countdown.gd` | PASS 172 checks |
| `tools/test_all_scenes_bruteforce.gd` | PASS 31 scenes, 1,718 checks |
| `tools/test_kilos_gameplay_bruteforce_20261028.gd` | PASS 31 scenes, 1,166 checks; retired mockup assertion migrated, live native 3D world explicitly asserted |
| `tools/test_component_prune_integrity.gd` | PASS 1,002 checks, 31 scenes |
| `tools/test_asset_cleanup_integrity.gd` | PASS 783 checks, 31 scenes, no unclassified external PNGs |
| `tools/test_human_plane_native_torus_20261029.gd` and `tools/test_human_plane_hybrid_3d_20261029.gd` | PASS 589 checks each, live imported airplane and torus rendering scene intact |
| `git -c core.safecrlf=false diff --check` | PASS, exit 0; no commit/reset/stash/clean/push |

## Separate gameplay QA findings — not fixed by this resource cleanup

The existing `tools/test_art_scenes.gd` was migrated to match the user's current design: collected `APPLE HALF.png` fruit must be small and unlabelled, falling word apples must retain grammar labels, and Balloon hand-raise firing must respect a **1.5-second** cooldown and lowering-to-rearm. Its actual final headless execution is **RED: 301 checks, 13 failures**, with two distinct production issues unrelated to deleting orphan assets:

- **Catch the Word (11 failures):** Bear, Cat, Dog, Lion and Panda character body/feet reach below the 1280×720 logical canvas, and collected-basket height is below the test's authored expected band. Lion's basket also crosses the bottom edge slightly. Needs a game-art geometry review before any editor-authored placement change.
- **Balloon Popping (2 failures):** A stone leaving the screen after the round has become inactive still counts as a missed attempt and costs a life. `_update_projectiles` can call `_on_projectile_missed` when `round_active` is false. This is a scoring/life-transition bug, not a resource-load failure.

The separate legacy `tools/test_catch_character_editor_rig.gd` also remained RED (120/1,786 assertions), combining stale collected-apple label assumptions with current character bounds issues. These unresolved tests are **not** claimed to pass, and no production gameplay logic or character artwork was altered as part of this cleanup.

**Editor warning:** A stale, already-open Godot scene tab temporarily re-saved the deleted Spotlight nodes during concurrent work. The shared `.tscn` was repaired and retested, but the user should reload the canonical Spotlight scene from disk before saving any older editor tab. Do not discard wanted unsaved changes without reviewing them.

This cleanup deliberately does not claim every unreferenced-by-literal art file is safe to delete: dynamic filename construction, distinct original assets, scene inheritance and future art work require more evidence than `rg` alone.
