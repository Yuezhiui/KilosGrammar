# KILOSGRAMMAR asset cleanup — 25 October 2026

> **Historical audit:** This report describes the conservative cleanup
> performed **before** the later one-folder UI asset migration on the same
> date. See `docs/asset-migration/README.md` and
> `Components/README_ASSETS.md` for the current layout. The deleted unused
> textures described below were not restored by the migration.

This folder contains the **cleanup record** for the existing Godot project. The goal is to remove demonstrably dead files **without** breaking editor-authored scenes, PNG-backed buttons, CSV dialogs, gameplay artwork, or user-supplied source packs. This is not a replacement resource folder: active images deliberately remain next to their existing scenes so their `res://` paths and Godot import UIDs remain stable.

## Changes completed

- Removed the redundant `Deletion requires TWO confirmations and exact typed DELETE ALL DATA.` beige status notice from the Leaderboard's Delete CSV opening flow. The wooden first/final confirmation overlays now provide that information. The existing status panel is still available for important CSV import/export or database results, and is temporarily hidden whenever a delete modal is open.
- Deleted two obsolete **tracked** generated/legacy images from `assets/ui/`, together with their import sidecars: `main_panel_buttons.png` and `kilos_curved.png`. No runtime scene or script loads either texture. The `tools/generate_curved_kilos.gd` source generator was retained, and can recreate the latter if needed.
- Deleted two unused **tracked** Settings slider-knob variants from `ui/redesign/assets/settings/`, with matching import sidecars: `slider_knob_green_24.png` and `slider_knob_green_32.png`. The current UI uses `slider_knob_green_28.png`; it is intact.
- Removed six unused legacy delete-dialog styles from `ui/secondary/leaderboard.tscn`. Current notification resources and all actual controls remain editable.
- Added resource/ownership notes in `Components/README_ASSETS.md` and `ui/ASSETS.md`.
- Added repeatable safety audit `tools/test_asset_cleanup_integrity.gd` (plus its Godot `.uid`), which loads every `.tscn` and `.tres` resource, checks texture links, button skins, and the delete overlays at all three target resolutions.

**Totals: four obsolete PNGs plus their four `.import` files removed; six dead scene style resources removed.** No broad deletion, destructive rewrite of art, or `git reset` occurred. These were already-tracked files, so their former bytes remain recoverable from normal Git history.

## Asset folders to retain

| Area | Why it stays |
| --- | --- |
| `Components/Main Panel/Original/` | Original supplied artwork, documented variants and editable source references |
| `Components/Gameplay/Calibration/` | Scene art plus exact-image tests, including files not directly drawn |
| `Components/Gameplay/Human Plane/` | Scene-bound plane imagery and checksum-protected originals |
| `Components/Leaderboard/2026-10-24/` | Current dropdown/button background states and an untracked user image |
| `Components/Leaderboard/NotifLeader/` | All **eight** original separate PNGs used by the custom Delete CSV modals |
| `ui/redesign/assets/` | Active Settings, Main Menu, Student, tutorial and game-over sprite packs |
| `ui/minigames/catch_the_word/catch_hud/`, `ui/minigames/balloon_popping/balloon_art/` | Live sprites, generated image sources, editor references and extraction tooling |
| `Components/Gameplay/Catch the Word/Maps/`, `Components/Gameplay/Catch the Word/Characters/` | Dynamically selected map and character files |
| `Components/Gameplay/Balloon Popping/Background/`, `Components/Gameplay/Balloon Popping/Balloons/` | Runtime balloon and carnival assets; unused alternative colors are deliberately retained |
| `assets/fonts/`, `assets/audio/`, `assets/icons/` | Active fonts, feedback and controls, including dynamically loaded voiceover paths |
| `showcase/` | **Git-ignored** local test snapshots and visual review material (around 370 MiB at audit). These are not gameplay assets, but may be needed to compare designs; deliberately **not deleted** |

`Components/Settings/Secondary/qwqwqw.png` was formerly used by a decorative cat that covered the Fullscreen row. The October 26 single-page Audio & Display cleanup deleted its scene node and resource reference, verified it had no remaining runtime references, and then removed this source PNG and its matching `.import`. No active Settings art was deleted.

Some image pairs are byte-identical yet separately used by different editable scenes, or explicitly retained by the original artwork pack manifests. Matching hashes or no direct literal `res://` hit do not alone authorize deletion. See the detailed reports in `Components/README_ASSETS.md` and `ui/ASSETS.md`.

## Verification and scope

- Godot 4.7.2 headless editor scan: zero resource/import errors.
- `tools/test_asset_cleanup_integrity.gd`: **469 checks passed**, loaded 29 `.tscn` plus one `.tres`; decoded 148 texture dependencies; zero missing resource paths, resource IDs, or unused serialized declarations.
- Leaderboard delete-modal, database mock, editor-layout and PNG selected-art checks passed. The deletion flow was verified using **mock signals only**; no PostgreSQL records were touched.
- Settings design/integration and button visuals passed, including 328 Settings visual checks. Main UI button-hover and general minigame tests also passed.

**Separate existing regressions discovered during broad QA:** `tools/test_art_scenes.gd` has Catch Girl/Grandma/Grandpa body/basket clipping and Balloon projectile interaction assertions; `tools/test_gameplay_hud_visibility_recovery.gd` reports 18 alternate-character clipping assertions. Their underlying character/projectile files were **not removed or renamed** by this cleanup, and unrelated gameplay layout or physics was not rewritten. These require an independent fix rather than hiding the failures or deleting artwork.

## Safe future changes

1. Identify a tracked, clean candidate and inspect its original purpose and any supporting source-pack README/manifest.
2. Search `.tscn`, `.tres`, `.gd`, `.py`, `.ps1`, tests, import UIDs and filenames built dynamically at runtime. Treat generated design references as owned source material, not orphan output.
3. If the file is truly obsolete, delete it alongside its `.import` file, or update **every** consumer when moving it; never move a live texture alone.
4. Run the Godot editor scan, `tools/test_asset_cleanup_integrity.gd`, and relevant scene/gameplay tests, then inspect the target screen in the native renderer.

No unrelated dirty user work was discarded, and nothing was committed or pushed by this cleanup.
