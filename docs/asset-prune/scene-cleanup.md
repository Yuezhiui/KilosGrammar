# Scene navigation and verified resource cleanup — 26 October 2026

Scope: UI navigation from calibration back to Choose Activity, image geometry and keyboard focus in the chooser, and removal of the verified orphan Credits scene. Inspection covered the **31 Godot `.tscn` paths originally present in the working tree**, project scene route declarations, packed scene references, script preloads/dynamic loads, and the 13 Game Chooser PNGs with their import sidecars. This work was performed without a real webcam or student database.

## Calibration: two editable Back buttons

`ui/vision/calibration.tscn` has two native scene-authored buttons:

- `TutorialStage/IntroOverlay/IntroBackButton` during the initial introduction.
- `TutorialStage/BackButton` throughout calibration, including camera failure.

Each now has a separate, editor-editable `Artwork` TextureRect containing the **exact original** `res://Components/Game Chooser/back button.png`. Both occupy the same authored lower-left 255 × 85 control bounds, at (47, 622) on the 1280 × 720 canvas. The native Button is transparent and has an explicit **“Back to Choose Activity”** accessibility name and tooltip, with a visible keyboard focus outline. The old generic `BACK TO MAIN` style and its unused `PurpleButton` scene style were removed. Scene node names remain stable for script callers.

`main_menu.gd` routes ESC from `calibration` to `play_activity`, matching the intended screen Back behavior. Its session-state merge preserves existing student name/ID, grade, teacher selections, and activity context when changing the selected game. The calibration controller `_go_back()` lives in `ui/vision/calibration.gd` and was updated by its pose worker to emit `play_activity` with the deep-copied context after stopping its camera. The two buttons already connect to that one method.

Human Plane's one-center-pose calibration and its initial visible-hands guidance are separate from Catch the Word and Balloon Popping's original three physical standing zones. The shared `CenterCalibrationLane` now uses a clear green border and glow to identify the central standing region. The `SkeletonPlacement` rectangle was restored to the exact 1007 × 446 editor-authored `LiveCameraInset` bounds so drawn pose joints match camera pixels. All three physical calibration zone Panels, their editor-authored materials, and `InstructionFIL` are intentionally preserved. No camera or pose packets were mocked in production.

The supplied `ArtCountdownBadge` and three independent numbered countdown textures were each moved down 16 px, retaining their existing 228 × 172 authored dimensions, so their visible ink no longer clips at the top edge. The `ArtCameraFrame` containing `BORDER.png` was moved up 24 px without resizing its 1150 × 700 art, bringing the visible bottom edge inside the viewport while keeping the frame behind the live camera.

## Chooser active and disabled Next alignment

`ui/play/play_activity.tscn` uses the 1280 × 720 authored footer button at (920, 641), sized **335 × 72**. The original gray PNG is 2172 × 724 and includes broad transparent top/bottom margins; a scene-authored `AtlasTexture` with `Rect2(72, 144, 2028, 435)` frames its visible artwork without editing its bytes. The supplied green PNG is 2007 × 430 and needs no trim. Both display through `TextureRect.stretch_mode = 5` (Keep Aspect Centered), preventing letterform/pill distortion and crop in either state. `play_activity.gd` retains a reference to the gray editor-authored atlas for restoring the disabled state.

All three chooser game Buttons retain `focus_mode = FOCUS_ALL`. The former cyan 2-pixel bottom-only underline is gone; the replacement is an unobtrusive purple 2-pixel full focus outline with rounded corners. Focus remains keyboard-visible and follows activity selection; clicking a game still enables the green Next artwork and updates its preview.

GPU-rendered chooser screenshots were inspected at 1280 × 720 for default and selected states. The art, Back, footer Next button and focus controls remain legible without clipped button lettering.

## Historical original 31-scene inventory

**Update, October 29, 2026:** This table records the earlier audit, not the
current scene inventory. The separate Ready, Camera Check and Existing Score
screens and their folders have since been removed at the teacher's request,
with gameplay countdown and Calibration retained. Do not restore any retired
scene based on a historical "Retain" entry below.

The route or owner listed below explains why a scene must be retained despite being instantiated dynamically or referenced indirectly:

| Scene | Runtime use / evidence | Decision |
| --- | --- | --- |
| `main_menu.tscn` | Project main scene; hosts all screens | Retain |
| `ui/student/student_setup.tscn` | `main_menu.gd` route | Retain |
| `ui/student/existing_score_dialog.tscn` | PackedScene in `student_setup.tscn` | Retain |
| `ui/shared/lexi_reference_backdrop.tscn` | Settings scene and script | Retain |
| `ui/tutorial/tutorial_home.tscn` | `main_menu.gd` route | Retain |
| `ui/tutorial/spotlight_overlay.tscn` | `gameplay.gd` guided flow | Retain |
| `ui/tutorial/grammar_guide.tscn` | `main_menu.gd` route | Retain |
| `ui/play/ready.tscn` | `main_menu.gd` countdown compatibility route | Retain |
| `ui/play/play_topic.tscn` | `main_menu.gd` route | Retain |
| `ui/play/play_difficulty.tscn` | `main_menu.gd` route | Retain |
| `ui/play/play_activity.tscn` | Active Choose Activity route | Retain |
| `ui/play/pause.tscn` | `main_menu.gd` route | Retain |
| `ui/play/guided_countdown.tscn` | PackedScene in `gameplay.gd` | Retain |
| `ui/play/gameplay.tscn` | `main_menu.gd` route | Retain |
| `ui/vision/camera_check.tscn` | Legacy/compatibility route in main menu | Retain |
| `ui/vision/calibration.tscn` | Active camera/game calibration route | Retain |
| `ui/secondary/settings.tscn` | `main_menu.gd` route | Retain |
| `ui/secondary/results.tscn` | `main_menu.gd` route | Retain |
| `ui/secondary/leaderboard_row.tscn` | Dynamic per-row preload in `leaderboard.gd` | Retain |
| `ui/secondary/leaderboard.tscn` | `main_menu.gd` route | Retain |
| `ui/secondary/credits.tscn` | No production route; depended on removed `credits.gd` | **Delete** |
| `ui/minigames/catch_the_word/catch_word.tscn` | Dynamic activity lookup in `gameplay.gd` | Retain |
| `ui/minigames/balloon_popping/balloon_popping.tscn` | Dynamic activity lookup in `gameplay.gd` | Retain |
| `ui/minigames/human_plane.tscn` | Dynamic activity lookup in `gameplay.gd` | Retain |
| `ui/minigames/human_plane_3d_view.tscn` | PackedScene in Human Plane; actively developed | Retain |
| `ui/minigames/human_plane_3d_ring.tscn` | 3D ownership/transition under separate worker | Independently removed by 3D scene worker after authoring rings into the sole 3D view |
| `ui/minigames/balloon_popping/balloon_art/balloon_blue.tscn` | `balloon_popping.tscn` PackedScene | Retain |
| `ui/minigames/balloon_popping/balloon_art/balloon_green.tscn` | `balloon_popping.tscn` PackedScene | Retain |
| `ui/minigames/balloon_popping/balloon_art/balloon_purple.tscn` | `balloon_popping.tscn` PackedScene | Retain |
| `ui/minigames/balloon_popping/balloon_art/launcher.tscn` | `balloon_popping.tscn` PackedScene | Retain |
| `ui/minigames/balloon_popping/balloon_art/stone.tscn` | `balloon_popping.gd` preload | Retain |

**Only scene deletion by this worker:** `ui/secondary/credits.tscn`. Its accompanying `credits.gd` and `credits.gd.uid` were already removed by the owner; it had no standalone `.tscn.uid` sidecar. A separate 3D worker also removed `human_plane_3d_ring.tscn` during the same run, leaving **29 scenes** in the current working tree. The user-requested removal of Credits is corroborated by active main-menu routes, integration tests expecting the scene to be absent, and `docs/asset-prune/credits-removal.md`, which retains the contributor names and license notice formerly displayed in Credits. This cleanup did not delete author/model attributions or third-party license files.

## Game Chooser asset and dynamic import check

**All 13 supplied PNGs and their 13 `.png.import` files are live. Zero are safe deletions.** Runtime lookup uses both `play_activity.tscn` (header, buttons, gray Next, game board and Back) and `play_activity.gd` (three preview choices, green Next). Files and purposes:

| Purpose | Original PNGs |
| --- | --- |
| Heading/instruction | `choose an activity.png`, `header1.png` |
| Game options board | `bg1.png` |
| Game choice input images | `catch the word button.png`, `human plane button.png`, `ballooon popping button.png` |
| Dynamically changing preview | `select game default.png`, `catch the word.png`, `human plane.png`, `balloon popping.png` |
| Navigation | `back button.png`, `next student setup.png`, `next student setup if already choose.png` |

The exact PNG originals remain untouched. `Components/Game Chooser/README.md` records their original SHA-256 checksums. Shared classroom artwork comes from the existing `Components/Shared/Redesign/classroom_bg.png`. Beyond this folder, the audit also checked the dynamic loader paths in `settings.gd`, the dynamically chosen minigames in `gameplay.gd`, and the glTF scene-relative texture/binary dependencies. Those assets cannot be safely deleted based solely on missing literal full-path matches.

## Validation and removal of obsolete controls

- Godot 4.7.2 `test_game_chooser_redesign_visual.gd` OpenGL GUI: **PASS**, 42 checks at 1280 × 720, 1600 × 900, 1920 × 1080; inspected the default/selected screenshots.
- Godot 4.7.2 `test_main_menu_editor_layout.gd` headless: **PASS**, editor layout and routes intact (the runner printed shutdown leak warnings).
- `test_game_chooser_redesign.gd` headless: **PASS**, 258/258 checks after the prime/test owner updated old expectations for the gray AtlasTexture and full focus outline.
- `test_calibration_assets_layering.gd` headless: **PASS, 560/560 checks** at 1280 × 720 and 1920 × 1080, including both the countdown and frame's visible pixels remaining on screen.
- `test_calibration_back_navigation_visibility.gd` headless: **PASS, 94/94 assertions** for intro/active native keyboard and mouse Back buttons, exact supplied PNG, student/game context preservation, accurate camera/bone dimensions and route to `play_activity`.
- `test_ui_screens.gd` headless: **PASS** from setup → chooser → calibration → Choose Activity, through all 13 UI route panels and 3 minigame scenes.
- `test_projectwide_orphan_integrity.gd` headless: **PASS, 2779 checks, zero failures**, after the separate 3D owner removed an orphan QA-only `.png.import` sidecar under Human Plane 3D.
- After pose worker removed obsolete bindings from `calibration.gd`, deleted exactly four unused `calibration.tscn` nodes: `InstructionEN`, `ContinueButton`, `CalibrationGuideBar`, `CalibrationGuideCursor`. Removed the two StyleBox resources exclusively used by Continue. The visible `StageHeading`, `InstructionFIL`, live camera skeleton overlay, native Back, and all three Catch/Balloon movement areas remain intact.
- Post-prune Godot headless verification: `test_calibration_single_guide.gd` **PASS**, `test_calibration_minimal_ui.gd` **PASS 97/97**, `test_calibration_three_second_sequence.gd` **PASS 223/223**, `test_calibration_fullscreen_editor_layout.gd` **PASS 692/692**, and `test_pose_calibration.gd` **PASS**. The tests now assert the sole authored English heading, camera-independent Back and automatic gameplay transition, without looking up nonexistent dead nodes.
- Full project editor initialization and resource import with `--headless --editor --quit`: **PASS**, exit code 0.
