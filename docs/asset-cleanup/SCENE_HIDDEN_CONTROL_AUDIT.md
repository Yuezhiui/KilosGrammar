# Scene-node visibility inventory (25 October 2026)

An initially hidden scene node is **not** automatically unused. Many are activated by mode, context, dialog or animation at runtime. Preserve conditional controls unless their caller and exact asset/status dependencies are also removed.

Godot scenes inspected: **29**.

| Scene | Initially hidden nodes | Initially hidden buttons |
| --- | ---: | ---: |
| `main_menu.tscn` | 2 | 0 |
| `ui/minigames/balloon_popping/balloon_popping.tscn` | 1 | 0 |
| `ui/minigames/catch_the_word/catch_word.tscn` | 13 | 1 |
| `ui/minigames/human_plane.tscn` | 33 | 0 |
| `ui/play/gameplay.tscn` | 1 | 0 |
| `ui/secondary/leaderboard.tscn` | 6 | 2 |
| `ui/secondary/settings.tscn` | 3 | 0 |
| `ui/student/student_setup.tscn` | 2 | 2 |
| `ui/tutorial/spotlight_overlay.tscn` | 10 | 0 |
| `ui/vision/calibration.tscn` | 31 | 1 |

## Important categories

- **Leaderboard:** `TransferStatusPanel` and hidden `DownloadButton` are user-authorized cleanup targets; custom final/first deletion overlays start hidden **by design**.
- **Catch/Plane/Calibration:** state-dependent inactive characters, guides, controls, HUD text and lane geometry often start hidden. These must survive unless runtime code no longer references them.
- **Settings / Student Setup:** alternate pages and recovery buttons have lifecycle-dependent visibility; hidden does not imply orphan.
- **Main menu / Tutorials:** ephemeral tooltip, falling template and spotlight arrows are initially hidden but animate/appear later.

This inventory documents the pre-cleanup audit. Post-cleanup preservation and tests are recorded in `tools/test_all_scenes_bruteforce.gd` and the project asset-integrity test (when present).

## Completed cleanup (final)

The following **four obsolete nodes** were deleted from `ui/secondary/leaderboard.tscn`:

- `DownloadButton` — long-hidden duplicate filtered CSV trigger, while the callable `request_filtered_csv_export()` API remains supported
- `TransferStatusPanel` — unwanted beige status banner
- `TransferStatus` — label exclusively owned by the removed banner
- `MinigameFilter` — permanently hidden native OptionButton replaced by script-only minigame selection state; the existing compatibility filtering API remains callable

The now-unused `TransferStatusBackground` and `MinigameLightStyle` serialized style resources were also removed. Genuine CSV/backend outcomes now route through the existing `EmptyNotice` dialog; pending-progress messages do not flash a large banner. The custom two-step deletion panels stay as separate, editor-authored overlays, and the red/gray destructive button remains **one editable `FinalDeleteButton` node**, with normal and disabled PNG styles.

The other 20 non-gameplay scenes and eight gameplay/minigame scenes were audited individually by separate workers. **No other hidden authored buttons were provably unused.** Student recovery controls, scroll hints, guided tutorial overlays, pause/finish UI, character/plane mode alternatives, calibration gates and modal controls are all used by runtime state or existing scene contracts. These were deliberately preserved to avoid breaking functionality.

The new `tools/test_all_scenes_bruteforce.gd` loads all 29 `.tscn` resources, constructs/unloads each repeatedly at three resolutions and tests safe isolated UI navigation and deletion cancellation without touching live PostgreSQL. A separate pre-`_ready()` context access error was found and corrected while running this new suite. See test output for final assertion counts and any explicitly known unrelated gameplay regressions.
