# UI image ownership and cleanup notes

> **Updated after the screen-folder consolidation:** All image assets previously
> under `ui/redesign/assets/`, `ui/minigames/catch_hud/`, and
> `ui/minigames/balloon_art/reference/` now live in screen-specific folders
> under `res://Components/`. This document records the **earlier cleanup audit**
> and the original source locations; consult `Components/README_ASSETS.md` and
> `docs/asset-migration/README.md` for the current folders and exact path maps.

The UI keeps its editor-authored scenes and original artwork in place. Before
deleting an image, search **the whole project**, including `.tscn`, `.tres`,
`.gd`, tests, Python/PowerShell generators, and code assembling resource paths
from directory constants and filenames. Godot `.import` UIDs and source image
variants also need checking. A missing literal `res://...` reference is **not**
proof that a file is disposable.

## Existing folders and suggested organization

| Folder | Purpose | Cleanup guidance |
| --- | --- | --- |
| `redesign/assets/{main,student,settings,game_over,tutorial,shared}` | Reusable UI sprites and scene art | Preserve names referenced by scenes, runtime UI builders and generator scripts. |
| `minigames/balloon_art/reference` | Extracted carnival sprites, extraction script, and contact sheet | Treat as art sources, even when an individual image is not currently drawn. |
| `minigames/catch_hud/generated` | Live HUD PNGs and archived iterations | Live HUD uses `title_board`, `timer_badge`, `pause_badge`, `score_board`, `lives_badge`, `character/word_apple` and `replacement/lives_state_1..3`. |
| `minigames/catch_hud/generated/character` | Generated character experiments | Current characters are sourced from `Components/Gameplay/Catch the Word/Characters/`; retain experimental PNGs until their art owner approves archival/removal. |
| `minigames/catch_hud/generated/replacement` | Lives sprites and reference panels | `lives_state_1..3` are used by three minigames; `hearts_1..3_reference` are retained design references. |
| `minigames/catch_hud/*.svg` and `topics/*.svg` | Editable vector art and topic graphics | Keep the source vectors even when a generated PNG is used at runtime. |
| `secondary` | Individually authored page assets and styles | Check scene and script references before making changes. |

## Conservative audit — 25 October 2026

The audit inventoried 204 Git-tracked UI image files and searched project source,
scenes, resources, tests, import UIDs, and generator code. It also checked the
working tree before changes. Only the following tracked, unchanged and
unreferenced resize variants were removed, together with their matching imports:

- `redesign/assets/settings/slider_knob_green_24.png[.import]`
- `redesign/assets/settings/slider_knob_green_32.png[.import]`

`slider_knob_green_28.png` is the active image referenced by
`secondary/settings.tscn`, `secondary/settings.gd`, and
`tools/build_settings_tscn.gd`; it remains in place.

**Review separately before any further removal:** generated character
`boy_body/boy_basket_hands/girl_*/grandma_*/grandpa_*` PNGs,
`replacement/hearts_*_reference.png`, historical
`generated/objective_banner.png`, settings `slider_knob_green.png`,
balloon `reference/cannon_front.png` and `contact_sheet.png`.
Some are expected by an installer, design documentation or extraction workflow.
They have not been removed.

The untracked `minigames/5e404e45-74fb-4f27-b5e9-eaf8aadb98e3.png` and its
import belong to active work and were preserved. The audit did not move assets
or edit any production `.tscn` / `.gd` files.
