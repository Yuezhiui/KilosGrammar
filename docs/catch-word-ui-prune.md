# Catch the Word: verified UI-only pruning

The following scene-authored nodes were permanently invisible or redundant
and are removed from `ui/minigames/catch_the_word/catch_word.tscn`:

- `HUDLayer/HUD/TitleLabel`, `TitleTheLabel`, `TitleWordLabel` — all static
  lettering is already baked into the active `TitlePlaque` PNG.
- `HUDLayer/HUD/ScoreLabel` — redundant hidden label. The actual numeric score
  is `ScoreDrawLayer/ScoreBottomContainer/ScoreNumber`.
- `HUDLayer/HUD/LivesLabel` — hidden; actual Lives mode uses three supplied
  static heart-state textures.
- `HUDLayer/HUD/StreakLabel` — hidden and never shown; *streak state,
  best_streak, round scores and Results payload are unchanged*.
- `HUDLayer/HUD/FooterLabel` — hidden instructional copy.
- `HUDLayer/HUD/FinishButton` — hidden unused manual button; the existing
  `_manual_finish()` API is retained for valid scripted/testing round finish.

Removed the matching `@onready` properties, obsolete label updates and
invisible button styling/connect code from `catch_word.gd`. Active pause
button, grammar prompt, timer, score label number, all four
character/body/basket rigs, spawned falling tiles, foreground collected
apples and real HUD/score backgrounds remain unchanged. No PNG or texture
file was deleted merely because a legacy hidden node was removed.

Camera presence warnings are managed by `ui/play/gameplay.gd`, not the
Catch `.tscn` scene. Tutorial skip does not bypass calibration; it advances
through the same 3-2-1 count-in. The "come back" notice now needs fresh,
explicitly missing-student inference observations from PoseService, not
merely a temporarily invalid wrist, calibration value, startup or stalled
camera. Real pose loss still suspends the game. Live classroom camera tests
remain necessary before deployment.
