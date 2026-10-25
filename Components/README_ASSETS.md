# KILOSGRAMMAR — Live UI artwork

All current gameplay and screen artwork (PNG/JPEG/WebP/SVG) is organized under **`res://Components/`**. Godot scene files remain in `ui/` and `main_menu.tscn`; no UI screen was flattened into an image. Controls, hitboxes, selected-state artwork, and editable layout are still authored in Godot.

## Current verified inventory — 26 October 2026

| Folder | Artwork files | Active use |
| --- | ---: | --- |
| `Gameplay/` | 63 | Catch the Word, Balloon Popping, Human Plane, calibration, HUD and dynamically chosen gameplay images |
| `Leaderboard/` | 32 | Live Leaderboard, filters, both teacher-only delete-confirmation stages and the wooden success notice with separate illustrated header |
| `Main Panel/` | 15 | Main Menu and native button states |
| `Settings/` | 24 | Settings scene and dynamic tab states |
| `Student Setup/` | 18 | Student details, grade and grammar-topic controls |
| `Tutorial/` | 14 | Guided/tutorial cards, navigation and spotlight |
| `Results/` | 1 | End-of-round results background |
| `Shared/` | 1 | Shared classroom artwork |
| **Total** | **168** | **166 PNG + 2 SVG, with matching `.import` sidecars** |

`res://icon.svg` is the Godot project icon outside `Components/`. Ignored `showcase/` screenshots are not runtime sprites. Empty or obsolete prototype artwork, copied originals, historic extraction manifests and unused `.import` sidecars were pruned only after checking serialized scene dependencies, test fixtures and dynamically constructed paths. The dated Leaderboard images, eight current `NotifLeader` button/panel parts, Main Menu original images still used by its scene, Settings dynamic tab states and uncertain original user art were retained.

## Provenance and pruning records

- `docs/asset-migration/` records the **historical relocation** into `Components/`; its path mappings are an audit trail, **not a list of files still present**. Do not rerun migration against the current tree.
- `docs/asset-prune/leaderboard.md` lists the old Leaderboard prototypes, manifests, extraction helpers, the retired red button and their removed imports.
- `docs/asset-prune/other-ui.md` lists 118 verified unused images (and their `.import` pairs) removed from Main Panel, Settings, Student Setup, Tutorial, Results and Shared.
- `docs/asset-prune/gameplay.json` audits 37 Gameplay image/import removals by hash, with two additional subsequently verified removals recorded separately.

The historical `ui/redesign/assets/asset_manifest.json`, `phase3_manifest.json`, `ART_INVENTORY.md` and `PHASE3_INVENTORY.md` were retired after the redesigned sprite smoke test was updated to inspect currently referenced scene textures. Optional extraction scripts remain for intentional artwork regeneration.

## Editor and verification contract

Keep PNG-backed buttons and all Godot `.tscn` layouts native and draggable. Leaderboard's `%FinalDeleteButton` uses one editor-authored native Button (currently 288×71) with gray/updated-red StyleBoxTextures; both styles have matching visible bounds. Both Delete confirmation overlays start hidden, and activating the red state requires exact typed `DELETE ALL DATA` plus the existing two-stage/teacher authorization logic. The separately hidden deletion-success overlay uses the user-supplied `Success/bg.png`, `Success/OkayButton.png`, and `Success/00669de2-99cd-46c6-bef9-f3a0f69c72e1.png` header image, with native text for live backend counts.

Validate future deletions with `tools/test_component_prune_integrity.gd`, `tools/test_asset_cleanup_integrity.gd`, `tools/test_all_scenes_bruteforce.gd`, `tools/test_leaderboard_delete_modal_visual.gd`, and the scene-specific suites. Test at 1280×720, 1600×900 and 1920×1080. Never infer non-use only from a missing literal `res://` text match: scripts dynamically select gameplay artwork and Settings tab states. No PostgreSQL data should be modified by asset cleanup or its tests.
