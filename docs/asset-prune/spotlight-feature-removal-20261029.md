# KILOS GRAMMAR — Retired Spotlight tutorial feature

Date: 29 October 2026 · Godot 4.7.2 · User request: delete `DynamicTitle`, Spotlight, `spotlight_overlay`, and `spotlight_overlay.tscn`.

## Why and what changed

The named `DynamicTitle` was **active**, not a broken or unused label: it rendered five changing Spotlight step titles. The shared `spotlight_overlay.tscn` and `spotlight_overlay.gd` drove the embedded per-game highlights, narration, arrows and Replay/Back/Next/Skip buttons. Removing these **intentionally retires the five-step in-game tutorial**, rather than leaving a missing-resource error.

The following were actually removed from the current working tree:

- `ui/tutorial/spotlight/spotlight_overlay.tscn` (SHA256 `D0B65E3E4B2CDD382B7D705A2246066F45A007FC70FD65D18844032A69ABC0D4`)
- `ui/tutorial/spotlight/spotlight_overlay.gd` (SHA256 `30502C13ED170A5FF86CB9C2473EA228EEFF9BEDAF8372648D9B2F01F7B5ED1A`)
- `ui/tutorial/spotlight/spotlight_overlay.gd.uid` (SHA256 `668847627C2F5176D2B8B9BDBCE31EA696CCC06FC2CECFAAEEE2832CF6C4D5B8`)
- The empty `ui/tutorial/spotlight/` directory.
- The `GuidedSpotlight` instance, its `DynamicTitle` inherited override, `voice_clip_paths`, authoring overrides and all former child-reference records from **each** of `catch_word.tscn`, `balloon_popping.tscn` and `human_plane.tscn`. Their original HUD, 3D flight, sprites and gameplay controls remain.
- `Components/Tutorial/Spotlight/` and its `NewDesign/` child, containing ten now-unused PNGs and exactly ten matching `.png.import` files. Before deletion these were individually inventoried, checked for remaining live scene/code references, and hashed. The original files in the user's Downloads directory were **not** modified.
- Five Spotlight-only QA/capture tools and their five `.gd.uid` files, which tested deleted nodes (ten QA files total): `test_spotlight_overlay`, `test_spotlight_embedded_tutorial_20261029`, `test_spotlight_prune_20261029`, `capture_embedded_spotlight_newdesign_20261029`, and `test_tutorial_voice_integration_20261029`.

## Remaining user workflow

The existing `guided_tutorial` route is **not broken or removed from menus**. After the standard camera/solo-student calibration it goes directly to `ui/play/gameplay/guided_countdown.tscn` and its **3 → 2 → 1 → GO**. Normal Play continues to use the same game scenes and countdown when selected. The wrapper freezes the round during countdown and blocks camera-based GO without an authenticated fresh calibrated solo pose.

Tutorial Home messages and Ready-button text now accurately describe the direct countdown. No code pretends the five lesson steps or their Replay/Next/Skip controls remain available.

The **18 generated full-English WAVs** and their legitimate `.wav.import` sidecars were deliberately **retained** under `assets/audio/tutorial_spotlight/`: they are previously generated user voice assets and were not explicitly requested deleted. They are now **unconnected to playback** (no current in-game Spotlight narrator). The voice scripts, generation manifest and generator code are also preserved. An independent asset-only audio test retains the format/hash checks without asserting nonexistent replay/music-duck behavior.

## Validation

- Godot 4.7.2 headless editor import: **PASS**.
- `tools/test_spotlight_removal_guided_countdown_20261029.gd`: **PASS 1,374 checks**, three games × two modes × three sizes × Guided/Play, real countdown transitions, GO, missing/crowd/wrong-camera-session pose gates. Also **PASS 1,374 native OpenGL** on RTX 3050.
- `tools/test_kilos_gameplay_bruteforce_20261028.gd`: **PASS 1,079 checks**, 30 remaining `.tscn` scenes and real game rounds.
- `tools/test_all_scenes_bruteforce.gd`: **PASS 1,510 checks**, 30 scenes.
- `tools/test_asset_cleanup_integrity.gd`: **PASS 688 checks**, all assets/resources load, no dangling external PNG references.
- `tools/test_component_prune_integrity.gd`: **PASS 836 checks**.
- `tools/test_ui_feature_layout_20261029.gd`: **PASS 75 checks**, no old path expected.
- `tools/test_tutorial_no_persistence_credits.gd`: **PASS 13 checks**, no unauthorized tutorial score persistence.
- `tools/test_tutorial_voice_assets_20261029.gd`: **PASS 327 checks**, 18/18 English WAVs still distinct and valid; does **not** claim they play in Guided mode.

Existing unrelated gameplay-art/layout QA has documented Catch character geometry and Balloon delayed-projectile issues from the earlier cleanup report. Do not treat those as caused or fixed by this UI deletion.

**No Git commit, push, reset, stash, clean, real webcam test, or PostgreSQL operations** were performed in this feature removal.
