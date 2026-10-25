# Godot UI image migration

> **Historical relocation record, not the current artwork inventory.** A later reference-audited deletion removed obsolete images, sidecars and extraction manifests. The live inventory and preservation rules are in `Components/README_ASSETS.md`; exact removals are in `docs/asset-prune/`. Historical JSON old-to-new path mappings intentionally retain paths that no longer exist, for provenance only. Do not rerun this one-time migration to restore deleted prototype art.

On 25 October 2026, the editable UI images were reorganized into screen-specific folders under `res://Components/`, while scripts and `.tscn` scenes stayed in their normal project locations.

The image migration itself was intentionally **non-destructive**: no PNG/SVG was recompressed, renamed or replaced with a flattened screenshot. Image copies were verified by hash and `.import` sidecars preserved import UIDs. The working tree was already modified by other gameplay and Leaderboard features; no `git reset`, wholesale checkout, commit, push, or database mutation was performed.

The audit trail comprises:

- `worker2.json` — 81 gameplay images and SVGs moved from old top-level catch/balloon source folders, original `Components/` root, and `ui/minigames/`.
- `worker24.json` — 326 old/new path entries for 163 redesign/UI image source files and their 163 imported sidecars.
- `prime.json` — 50 original pack images moved from MainMenu, CalibrationV2, HumanPlaneAssets and TutorialSpotlight into screen-organized subfolders.
- `rewrite_report.json` — paths changed in GDScript, scenes, Python, tests and manifests by the controlled text-only replacement.
- `../asset-cleanup/README.md` — prior conservative deletion/inventory audit (historical pre-migration layout; see `Components/README_ASSETS.md` for the current folder tree).

For compatibility, raw legacy database values and canonical CSV field names were not changed. The Leaderboard UI omits the misleading `LEGACY / NOUN` label for older records; it displays `NOUN` and keeps later game identifiers separate.

To validate assets after future scene or image edits, run Godot 4.7.2's editor import, `res://tools/test_asset_cleanup_integrity.gd`, relevant scene tests, and check 1280×720, 1600×900 and 1920×1080 visually. No `res://` paths should reference the retired image directories.
