# KILOS GRAMMAR UI feature-folder migration — 2026-10-29

> **Follow-up later on 29 October:** The user explicitly removed the
> shared Spotlight scene/script, their embedded minigame children, and
> Spotlight UI artwork. The row below records an earlier migration,
> not a current file to reopen. The Guided route now goes from
> calibration straight to the existing 3-2-1 countdown.

This manifest documents the SAFE editor-facing reorganization for the UI
outside the minigames. Godot serialized scene transforms, node paths,
animations, colors, camera logic, and settings behavior were **not changed**.
For every moved `.gd` file, the accompanying `.gd.uid` was moved byte-for-byte.
No source paths were reset, discarded, cleaned, or committed.

## Exact moved resources

| Feature folder | Original resource names | New folder |
|---|---|---|
| Play — choose game | `ui/play/play_activity.gd`, `play_activity.tscn` | `ui/play/activity/` |
| Play — choose topic | `ui/play/play_topic.gd`, `play_topic.tscn` | `ui/play/topic/` |
| Play — choose difficulty | `ui/play/play_difficulty.gd`, `play_difficulty.tscn` | `ui/play/difficulty/` |
| Play — pregame countdown (Ready screen retired) | `guided_countdown.tscn` | `ui/play/gameplay/` |
| Play — runtime | `ui/play/gameplay.gd`, `gameplay.tscn`, `guided_countdown.tscn`, `catch_asset_preloader.gd` | `ui/play/gameplay/` |
| Play — pause | `ui/play/pause.gd`, `pause.tscn` | `ui/play/pause/` |
| Play — reusable UI | `ui/play/play_ui.gd` | `ui/play/shared/` |
| Student registration | `ui/student/student_setup.gd`, `student_setup.tscn` | `ui/student/setup/` |
| Student duplicate-score dialog (retired after initial move) | Removed by teacher-requested UI cleanup | No live scene/folder |
| Leaderboard | `ui/secondary/leaderboard.gd`, `leaderboard.tscn`, `leaderboard_row.tscn` | `ui/secondary/leaderboard/` |
| Settings | `ui/secondary/settings.gd`, `settings.tscn` | `ui/secondary/settings/` |
| Results | `ui/secondary/results.gd`, `results.tscn` | `ui/secondary/results/` |
| Credits | `ui/secondary/credits.gd`, `credits.tscn` | `ui/secondary/credits/` |
| Physical camera calibration | `ui/vision/calibration.gd`, `calibration.tscn`, `calibration_voice.gd` | `ui/vision/calibration/` |
| Camera check (retired after initial move) | Removed; Calibration handles direct camera entry | No live scene/folder |
| Tutorial grammar guide | `ui/tutorial/grammar_guide.gd`, `grammar_guide.tscn` | `ui/tutorial/grammar_guide/` |
| Tutorial guided spotlight | `ui/tutorial/spotlight_overlay.gd`, `spotlight_overlay.tscn` | `ui/tutorial/spotlight/` |

Historical migration totals: **37 runtime resources + 19 existing script UID sidecars = 56 moved files**, into **17 feature folders** at the time of migration. The later teacher-requested deletion of Camera Check, Existing Score and Ready makes this inventory historical, not the live scene count.

## Ownership boundaries and untouched assets

- `ui/tutorial/tutorial_home.tscn`, `tutorial_home.gd` and its CTA artwork remain in place for worker15.
- `ui/minigames/**` was **not edited by this migration worker**. Worker14 handled the single Balloon Popping import change to `res://ui/play/shared/play_ui.gd`.
- `main_menu.gd` was **not edited by this migration worker**. Prime updated its route scene map, Catch asset preloader import, and Settings import.
- `project.godot`, `ui/vision/pose_service.gd`, `pose_worker.py`, `student_lock.py`, the source camera stack, `ui/database/`, and the shared `ui/secondary/secondary_theme.tres` remain in place.
- Tutorial/theme support, database logic, artwork pixels, scenes' editor-native node geometry, and real webcam/database state are unaffected.
- Existing `ui/**/test_*.gd` scripts remain at their historical runnable locations, with *references* updated to the new scene paths rather than relocating their test entrypoints.

## References and quality assurance

The one-time helper `tools/migrate_ui_feature_paths_20261029.py` contains the exact map, collision checks, source-to-target moves, and targeted UTF-8 literal rewrite. It was run **once**; do not rerun after migration. It rewrote `res://` path strings in **126 permitted** UI, tools, showcase and documentation text files; it deliberately did not modify external owner files. Prime and worker14 then updated their respective external references.

Godot 4.7.2 headless results following the migration:

- `tools/test_ui_feature_layout_20261029.gd`: **PASS 79/79**, all 18 relocated scene files load and instantiate, moved script IDs and retained shared resources resolve.
- `--headless --editor --quit`: **PASS**, no project script parse errors after main-menu owner path updates.
- `tools/test_ui_screens.gd`: **PASS**, 14 public UI scenes and navigation flows including Student Setup → Game Selection → Calibration Back, Play/Tutorial separation, Results/Retry, and Settings. Its original test-only Calibration Back call was accidentally placed inside a removed-Skip error branch; the two lines were unindented to make the existing assertion actually exercise Back.
- `tools/test_calibration_success_latched_raw_solo.gd`: **PASS 159/159**.
- `tools/test_calibration_success_no_loop_20261028.gd`: **PASS 271/271**.
- `tools/test_settings_redesign_qa.gd`: **PASS**.
- `tools/test_play_navigation_persistence.gd`: **PASS 61/61**.

Known separate QA issue: `tools/test_ui_actual_button_flow.gd` does **not pass**. It reports a Nil access at its line 55 after the scripted student button fixture, without reaching its later route checks. Its test fixture/controller timing should be audited separately; it is not evidence that the relocated packed scenes fail to load. No webcam, PostgreSQL or external network was used for this migration.
