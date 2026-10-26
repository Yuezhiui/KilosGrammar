# Projectwide asset dependency and orphan audit ? 2026-10-26

**Outcome: 0 files deleted.** The extensive earlier asset-prune passes already removed verified stale copies, and this pass did not find another production duplicate that could be deleted without affecting a live scene or a protected source. This is a deliberate safety finding after checking actual files, SHA-256 contents, serialized scene/script references, dynamic loaders, QA/extraction sources and metadata?not an unperformed cleanup.

## Scope and evidence

- Snapshot inspected: **1,793 ordinary workspace files** excluding `.git`, `.godot`, `.venv` and `__pycache__`, including **599 source art/audio/font/model asset payloads**. The inventory includes **237 Components/ and assets/ source payloads** plus **359 protected showcase images**, the project icon, and glTF model dependencies.
- Import and script metadata: **595 `.import` files**, **209 `.uid` files**, **0 `.import` with missing source**, **0 `.uid` with missing source**. Two transient **QA screenshot outputs** (`tools/_tmp_25d_far_1280.png`, `tools/_tmp_25d_near_1280.png`) have no `.import` yet; neither is a runtime asset and both are preserved. Every non-QA source image/audio/font has an import sidecar.
- Parsed **141 production-oriented text files** (`.gd`, `.tscn`, `.tres`, glTF and supported build scripts) and found **292 distinct quoted literal `res://` paths**; full source inventory also includes tools, test names, docs and provenance to guard non-runtime source assets. These are quoted-literal counts; composed runtime paths require separate reasoning.
- Cryptographic duplicate check: **27 SHA-256 duplicate groups** across image/audio/font/model payloads. **26 groups** occur exclusively in protected `showcase/` captures. **One cross-screen duplicate group** is the pair below; both are active.
- Earlier reports read: `docs/asset-prune/gameplay.json` (39 Gameplay image+import pairs removed by earlier workers), `docs/asset-prune/other-ui.md` (192 redundant UI images and paired imports), `docs/asset-prune/leaderboard.md` (42 historical board images/imports and obsolete manifests); also inspected `docs/asset-cleanup/README.md` and `docs/asset-cleanup/SCENE_HIDDEN_CONTROL_AUDIT.md`. None of their historical deletions was replayed.

## Deletion record

| Deleted file or import/UID | Count | Reason |
| --- | ---: | --- |
| Source artwork/audio/models | **0** | No safely unused duplicate among the unprotected production files |
| Matching `.import` sidecars | **0** | Every present import retains a corresponding source |
| Matching `.uid` companions | **0** | No source-less UID companion observed |
| JSON/extraction manifests | **0** | Remaining historical records and source generators have possible regeneration/provenance value |
| QA snapshots / user originals / licensed material | **0** | Explicitly protected by this task |

## Exact duplicate that must be retained

- `Components/Gameplay/Calibration/BACKGROUND.png` ? SHA-256 `242d920db42fb6a102e19b6d33e4f70c846ad28ea1e01820287270a841682cf3`, **1,809,776 B**; active quoted resource reference: `ui/vision/calibration.tscn`; paired `.png.import` retained.
- `Components/Leaderboard/2026-10-24/BACKGROUND.png` ? SHA-256 `242d920db42fb6a102e19b6d33e4f70c846ad28ea1e01820287270a841682cf3`, **1,809,776 B**; active quoted resource reference: `ui/secondary/leaderboard.tscn`; paired `.png.import` retained.

Each scene owns its editor-authored resource path and import UID. Removing either file would break its serialized `ext_resource` even though the PNG bytes are identical. No asset or scene relocation is authorized in this audit.

## Dynamic/reference-only cases intentionally retained

- `assets/audio/catch_voice/*.mp3` (nine voice recordings) is resolved using runtime `VOICE_DIR + filename` in Catch the Word, Balloon Popping, Human Plane and the shared asset preloader; a scanner searching only full hard-coded filenames would misclassify these.
- `Components/Gameplay/Balloon Popping/Art/reference/*.png` has runtime path concatenation with `CARNIVAL_ART` plus selected filename; others are artist/extractor contact sheets and source frames documented in `docs/asset-prune/gameplay.json`.
- `Components/Settings/Redesign/` includes runtime-selected tab sprites and alternate settings state resources assembled by `ui/secondary/settings.gd` and the Settings generator; nonliteral paths remain protected.
- `assets/audio/lexispell_intro/title_music.ogg` (legacy soundtrack, not presently selected by `main_menu.gd`) retained as original/source music, because `assets/audio/user_provided/wii_fit_user_settings.mp3` is a different user-supplied track rather than a byte-identical substitute. No destructive audio substitution is authorized.
- `assets/fonts/Comic Lemon.otf` is loaded from a const string by `ui/secondary/settings.gd` and the offline Windows packaging script; all other fonts and original audio remain in place.
- All `Components/Gameplay/Human Plane/3D/**` originals (red plane, FBX/glTF, grass/mountain and PBR textures), related `ui/minigames/human_plane*` files, `Components/Game Chooser/**` **13 art items**, and test snapshots are explicitly protected. The 3D importer reads relative glTF texture URIs and `*.bin` buffers; literal `res://` searches alone cannot prove safety.
- New `Components/Credits/` art is authored and referenced by the concurrently edited Credits scene; no files were touched while that worker changed them.

## Retained source payload inventory

Every path below was preserved. `[scene/script literal]` indicates an exact quoted runtime resource path in a production-oriented source; `[retain: composed/original/test/attribution]` signals path composition, source-sheet provenance, test references, or explicit preservation even when no exact production literal is present. No uncertain path is considered safe to delete.

### Components/Credits ? 4 retained

- `Components/Credits/background1.png` ? scene/script literal
- `Components/Credits/background2.png` ? scene/script literal
- `Components/Credits/CREDITS.png` ? scene/script literal
- `Components/Credits/HOME.png` ? scene/script literal

### Components/Game Chooser ? 13 retained

- `Components/Game Chooser/back button.png` ? scene/script literal
- `Components/Game Chooser/balloon popping.png` ? scene/script literal
- `Components/Game Chooser/ballooon popping button.png` ? scene/script literal
- `Components/Game Chooser/bg1.png` ? scene/script literal
- `Components/Game Chooser/catch the word button.png` ? scene/script literal
- `Components/Game Chooser/catch the word.png` ? scene/script literal
- `Components/Game Chooser/choose an activity.png` ? scene/script literal
- `Components/Game Chooser/header1.png` ? scene/script literal
- `Components/Game Chooser/human plane button.png` ? scene/script literal
- `Components/Game Chooser/human plane.png` ? scene/script literal
- `Components/Game Chooser/next student setup if already choose.png` ? scene/script literal
- `Components/Game Chooser/next student setup.png` ? scene/script literal
- `Components/Game Chooser/select game default.png` ? scene/script literal

### Components/Gameplay ? 97 retained

- `Components/Gameplay/Balloon Popping/Art/reference/balloon_blue.png` ? dynamic art/source-sheet
- `Components/Gameplay/Balloon Popping/Art/reference/balloon_green.png` ? dynamic art/source-sheet
- `Components/Gameplay/Balloon Popping/Art/reference/balloon_purple.png` ? dynamic art/source-sheet
- `Components/Gameplay/Balloon Popping/Art/reference/cannon_front.png` ? dynamic art/source-sheet
- `Components/Gameplay/Balloon Popping/Art/reference/contact_sheet.png` ? dynamic art/source-sheet
- `Components/Gameplay/Balloon Popping/Art/reference/objective_panel.png` ? scene/script literal
- `Components/Gameplay/Balloon Popping/Art/reference/prompt_blank.png` ? dynamic art/source-sheet
- `Components/Gameplay/Balloon Popping/Art/reference/score_plaque_blank.png` ? scene/script literal
- `Components/Gameplay/Balloon Popping/Art/reference/title_marquee.png` ? dynamic art/source-sheet
- `Components/Gameplay/Balloon Popping/Background/0826b13c-250f-42e1-9398-a83d2922a1d8.png` ? scene/script literal
- `Components/Gameplay/Balloon Popping/Background/95ae2a22-302d-48f7-9b5f-e12b0104c822.png` ? scene/script literal
- `Components/Gameplay/Balloon Popping/Balloons/blue.png` ? scene/script literal
- `Components/Gameplay/Balloon Popping/Balloons/green.png` ? scene/script literal
- `Components/Gameplay/Balloon Popping/Balloons/purple.png` ? scene/script literal
- `Components/Gameplay/Balloon Popping/Effects/Pop.png` ? scene/script literal
- `Components/Gameplay/Balloon Popping/Launcher/Gun.png` ? scene/script literal
- `Components/Gameplay/Calibration/1.png` ? scene/script literal
- `Components/Gameplay/Calibration/2.png` ? scene/script literal
- `Components/Gameplay/Calibration/3.png` ? scene/script literal
- `Components/Gameplay/Calibration/ARROW.png` ? scene/script literal
- `Components/Gameplay/Calibration/BACK.png` ? original, QA/extraction or unverified dynamic source
- `Components/Gameplay/Calibration/BACKGROUND.png` ? scene/script literal
- `Components/Gameplay/Calibration/BORDER.png` ? scene/script literal
- `Components/Gameplay/Calibration/MOVE TO HIGHLIGHTED AREA.png` ? scene/script literal
- `Components/Gameplay/Calibration/PARAMETERS.png` ? scene/script literal
- `Components/Gameplay/Calibration/STARS.png` ? scene/script literal
- `Components/Gameplay/Calibration/STAY IN THE CENTER.png` ? scene/script literal
- `Components/Gameplay/Calibration/STAY OF THE LEFT.png` ? scene/script literal
- `Components/Gameplay/Calibration/STAY ON THE RIGHT.png` ? scene/script literal
- `Components/Gameplay/Calibration/STEP 1.png` ? scene/script literal
- `Components/Gameplay/Calibration/STEP 2.png` ? scene/script literal
- `Components/Gameplay/Calibration/STEP 3.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/Characters/BOY BASKET.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/Characters/BOY BODY.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/Characters/Generated/word_apple.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/Characters/GIRL BASKET.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/Characters/GIRL BODY.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/Characters/GRANDMA BASKET.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/Characters/GRANDMA BODY.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/Characters/GRANDPA BASKET.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/Characters/GRANDPA BODY.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/HUD/generated/lives_badge.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/HUD/generated/pause_badge.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_1.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_2.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/HUD/generated/replacement/lives_state_3.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/HUD/generated/score_board.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/HUD/generated/timer_badge.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/HUD/generated/title_board.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/Items/Apple.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/Maps/CityMap.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/Maps/ForestMap.png` ? scene/script literal
- `Components/Gameplay/Catch the Word/Maps/MountainMap.png` ? scene/script literal
- `Components/Gameplay/Controls/pause_white.svg` ? scene/script literal
- `Components/Gameplay/Controls/play_white.svg` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/CUTTED TREE.fbx` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/grass-green/source/Grass_green.fbx` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/grass-green/textures/Grass_green.png` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/grass-green/textures/Normal_grass.png` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/mountain/scene.bin` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/mountain/scene.gltf` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/mountain/textures/Default_OBJ_baseColor.jpeg` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/mountain/textures/Default_OBJ_metallicRoughness.png` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/mountain/textures/Default_OBJ_normal.png` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/pbr/grass004/Grass004_1K-PNG_AmbientOcclusion.png` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/pbr/grass004/Grass004_1K-PNG_Color.png` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/pbr/grass004/Grass004_1K-PNG_NormalGL.png` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/pbr/grass004/Grass004_1K-PNG_Roughness.png` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/pbr/road008a/Road008A_1K-PNG_AmbientOcclusion.png` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/pbr/road008a/Road008A_1K-PNG_Color.png` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/pbr/road008a/Road008A_1K-PNG_NormalGL.png` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/pbr/road008a/Road008A_1K-PNG_Roughness.png` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/PINE TREE.fbx` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/red-plane/2b69a53022ec45b396ce8015291cc9ea.fbx` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/red-plane/73967189f63d4364a9d08f5e29c8523e_R_plane_roughness.png` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/red-plane/798d9b9285514ddababd3c5b1eaeef7c_R_plane_AO.png` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/red-plane/9a9ac995d92f4b24a1131987f5313e7f_RGB_plane_basecolor.png` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/red-plane/c600cf14d6254b8a92a1a81d96477e67_N_plane_normal.png` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/red-plane/f60d02ce7b06482f994791f5f9523926_R_plane_metallic.png` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/red-plane/Thumbnail.jpg` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/Skybox/textures/clouds_anime_2k.jpg` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/Skybox/textures/clouds_anime_6k.jpg` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/STONE.fbx` ? scene/script literal
- `Components/Gameplay/Human Plane/3D/toy_plane/scene.bin` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/toy_plane/scene.gltf` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/toy_plane/textures/phong1_baseColor.jpeg` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/toy_plane/textures/phong1_metallicRoughness.png` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/toy_plane/textures/phong1_normal.png` ? protected user 3D/PBR/model original
- `Components/Gameplay/Human Plane/3D/TREE.fbx` ? scene/script literal
- `Components/Gameplay/Human Plane/BACKGROUND.png` ? scene/script literal
- `Components/Gameplay/Human Plane/human_plane_gate_blue_RIGHT.png` ? scene/script literal
- `Components/Gameplay/Human Plane/human_plane_gate_green_CENTER.png` ? scene/script literal
- `Components/Gameplay/Human Plane/human_plane_gate_purple_LEFT.png` ? scene/script literal
- `Components/Gameplay/Human Plane/PLANE.png` ? scene/script literal
- `Components/Gameplay/Shared/Hearts/HeartBlack.png` ? scene/script literal
- `Components/Gameplay/Shared/Hearts/HeartRed.png` ? scene/script literal
- `Components/Gameplay/Unsorted User Uploads/5e404e45-74fb-4f27-b5e9-eaf8aadb98e3.png` ? original, QA/extraction or unverified dynamic source

### Components/Leaderboard ? 32 retained

- `Components/Leaderboard/2026-10-24/2lives.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/ADJECTIVE.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/ADVERB.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/ALL DIFFICULTIES.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/ALL MODES.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/ALL STYLES.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/BACK.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/BACKGROUND.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/DELETE.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/easy.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/EXPORT.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/Hard.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/IMPORT.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/LEADERBOARD.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/normal.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/NOUN.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/PRONOUN.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/seconds.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/table_header.png` ? scene/script literal
- `Components/Leaderboard/2026-10-24/VERB.png` ? scene/script literal
- `Components/Leaderboard/NotifLeader/cancel.png` ? scene/script literal
- `Components/Leaderboard/NotifLeader/header end.png` ? scene/script literal
- `Components/Leaderboard/NotifLeader/hgeader before end.png` ? scene/script literal
- `Components/Leaderboard/NotifLeader/notif background.png` ? scene/script literal
- `Components/Leaderboard/NotifLeader/permanent delete default.png` ? scene/script literal
- `Components/Leaderboard/NotifLeader/permanent delete if add_.png` ? scene/script literal
- `Components/Leaderboard/NotifLeader/show final conf.png` ? scene/script literal
- `Components/Leaderboard/NotifLeader/type delete all data.png` ? scene/script literal
- `Components/Leaderboard/Secondary/transparent_dropdown_arrow.png` ? scene/script literal
- `Components/Leaderboard/Success/00669de2-99cd-46c6-bef9-f3a0f69c72e1.png` ? scene/script literal
- `Components/Leaderboard/Success/bg.png` ? scene/script literal
- `Components/Leaderboard/Success/OkayButton.png` ? scene/script literal

### Components/Main Panel ? 15 retained

- `Components/Main Panel/Original/A-.png` ? scene/script literal
- `Components/Main Panel/Original/A.png` ? scene/script literal
- `Components/Main Panel/Original/background.png` ? scene/script literal
- `Components/Main Panel/Original/credits.png` ? scene/script literal
- `Components/Main Panel/Original/G.png` ? scene/script literal
- `Components/Main Panel/Original/green-play.png` ? scene/script literal
- `Components/Main Panel/Original/KILOS GRAMMAR.png` ? scene/script literal
- `Components/Main Panel/Original/leaderboard.png` ? scene/script literal
- `Components/Main Panel/Original/M-.png` ? scene/script literal
- `Components/Main Panel/Original/M.png` ? scene/script literal
- `Components/Main Panel/Original/purple-tutorial.png` ? scene/script literal
- `Components/Main Panel/Original/R-.png` ? scene/script literal
- `Components/Main Panel/Original/R.png` ? scene/script literal
- `Components/Main Panel/Original/red-quit.png` ? scene/script literal
- `Components/Main Panel/Original/setting-large.png` ? scene/script literal

### Components/Results ? 1 retained

- `Components/Results/Redesign/bg_teal_clean.png` ? scene/script literal

### Components/Settings ? 24 retained

- `Components/Settings/Redesign/button_blank_purple.png` ? dynamic settings state/art
- `Components/Settings/Redesign/button_home.png` ? scene/script literal
- `Components/Settings/Redesign/icon_camera.png` ? dynamic settings state/art
- `Components/Settings/Redesign/icon_controls.png` ? dynamic settings state/art
- `Components/Settings/Redesign/icon_fullscreen.png` ? scene/script literal
- `Components/Settings/Redesign/icon_music.png` ? scene/script literal
- `Components/Settings/Redesign/icon_muted.png` ? scene/script literal
- `Components/Settings/Redesign/icon_screen.png` ? scene/script literal
- `Components/Settings/Redesign/icon_settings.png` ? dynamic settings state/art
- `Components/Settings/Redesign/icon_sound.png` ? scene/script literal
- `Components/Settings/Redesign/icon_star.png` ? scene/script literal
- `Components/Settings/Redesign/panel_main.png` ? scene/script literal
- `Components/Settings/Redesign/panel_sidebar.png` ? dynamic settings state/art
- `Components/Settings/Redesign/slider_knob_green_28.png` ? scene/script literal
- `Components/Settings/Redesign/tab_camera_cream.png` ? scene/script literal
- `Components/Settings/Redesign/tab_camera_green.png` ? dynamic settings state/art
- `Components/Settings/Redesign/tab_controls_cream.png` ? scene/script literal
- `Components/Settings/Redesign/tab_controls_green.png` ? dynamic settings state/art
- `Components/Settings/Redesign/tab_settings_cream.png` ? dynamic settings state/art
- `Components/Settings/Redesign/tab_settings_green.png` ? scene/script literal
- `Components/Settings/Redesign/title_settings.png` ? scene/script literal
- `Components/Settings/Redesign/toggle_off.png` ? scene/script literal
- `Components/Settings/Redesign/toggle_on.png` ? scene/script literal
- `Components/Settings/Secondary/qwqwqw.png` ? scene/script literal

### Components/Shared ? 1 retained

- `Components/Shared/Redesign/classroom_bg.png` ? scene/script literal

### Components/Student Setup ? 18 retained

- `Components/Student Setup/Redesign/btn_back.png` ? scene/script literal
- `Components/Student Setup/Redesign/btn_continue.png` ? scene/script literal
- `Components/Student Setup/Redesign/difficulty_easy.png` ? scene/script literal
- `Components/Student Setup/Redesign/difficulty_hard.png` ? scene/script literal
- `Components/Student Setup/Redesign/difficulty_normal.png` ? scene/script literal
- `Components/Student Setup/Redesign/icon_player.png` ? scene/script literal
- `Components/Student Setup/Redesign/mode_lives.png` ? scene/script literal
- `Components/Student Setup/Redesign/mode_seconds.png` ? scene/script literal
- `Components/Student Setup/Redesign/setup_difficulty_caption.png` ? scene/script literal
- `Components/Student Setup/Redesign/setup_heading.png` ? scene/script literal
- `Components/Student Setup/Redesign/setup_main_panel.png` ? scene/script literal
- `Components/Student Setup/Redesign/setup_mode_caption.png` ? scene/script literal
- `Components/Student Setup/Redesign/setup_topic_caption.png` ? scene/script literal
- `Components/Student Setup/Redesign/topic_adjective.png` ? scene/script literal
- `Components/Student Setup/Redesign/topic_adverb.png` ? scene/script literal
- `Components/Student Setup/Redesign/topic_noun.png` ? scene/script literal
- `Components/Student Setup/Redesign/topic_pronoun.png` ? scene/script literal
- `Components/Student Setup/Redesign/topic_verb.png` ? scene/script literal

### Components/Tutorial ? 14 retained

- `Components/Tutorial/Home/0e12567d-88f7-49e6-9bce-06cc27a6d16b.png` ? scene/script literal
- `Components/Tutorial/Home/Cat.png` ? scene/script literal
- `Components/Tutorial/Home/Grad_hat.png` ? scene/script literal
- `Components/Tutorial/Redesign/bg_classroom.png` ? scene/script literal
- `Components/Tutorial/Redesign/button_back.png` ? scene/script literal
- `Components/Tutorial/Redesign/button_grammar.png` ? scene/script literal
- `Components/Tutorial/Redesign/button_guided.png` ? scene/script literal
- `Components/Tutorial/Redesign/icon_books.png` ? scene/script literal
- `Components/Tutorial/Redesign/icon_camera.png` ? scene/script literal
- `Components/Tutorial/Redesign/icon_controller.png` ? scene/script literal
- `Components/Tutorial/Redesign/icon_play.png` ? scene/script literal
- `Components/Tutorial/Redesign/icon_star.png` ? scene/script literal
- `Components/Tutorial/Redesign/title_whole_body.png` ? scene/script literal
- `Components/Tutorial/Spotlight/right-arrow.png` ? scene/script literal

### assets/audio ? 15 retained

- `assets/audio/catch_voice/Awesome.mp3` ? runtime voice-directory composition
- `assets/audio/catch_voice/Awww.mp3` ? runtime voice-directory composition
- `assets/audio/catch_voice/Better Luck.mp3` ? scene/script literal
- `assets/audio/catch_voice/GoodJob.mp3` ? runtime voice-directory composition
- `assets/audio/catch_voice/niceee.mp3` ? runtime voice-directory composition
- `assets/audio/catch_voice/Perfect.mp3` ? runtime voice-directory composition
- `assets/audio/catch_voice/Wrong Answer.mp3` ? runtime voice-directory composition
- `assets/audio/catch_voice/You Missed.mp3` ? runtime voice-directory composition
- `assets/audio/catch_voice/You Nailed it.mp3` ? runtime voice-directory composition
- `assets/audio/lexispell_intro/button_click.wav` ? scene/script literal
- `assets/audio/lexispell_intro/button_hover.wav` ? scene/script literal
- `assets/audio/lexispell_intro/letter_pop.wav` ? scene/script literal
- `assets/audio/lexispell_intro/logo_bloop.wav` ? scene/script literal
- `assets/audio/lexispell_intro/title_music.ogg` ? legacy original soundtrack
- `assets/audio/user_provided/wii_fit_user_settings.mp3` ? scene/script literal

### assets/fonts ? 3 retained

- `assets/fonts/Comic Lemon.otf` ? scene/script literal
- `assets/fonts/GochiHand-Regular.ttf` ? scene/script literal
- `assets/fonts/TitanOne-Regular.ttf` ? scene/script literal

## Retained screenshot groups (never candidates for deletion)

The following folders contain QA/visual evidence and are preserved in full. There is no image-by-image deletion authorization for showcases; checksum duplicates among screenshots remain useful for before/after comparison.

- `showcase/_tmp_chooser_fidelity.png/` ? 1 image files retained
- `showcase/art_review/` ? 3 image files retained
- `showcase/balloon_asset_review/` ? 55 image files retained
- `showcase/balloon_qa_baseline/` ? 2 image files retained
- `showcase/catch_siblings_boy.png/` ? 1 image files retained
- `showcase/catch_siblings_girl.png/` ? 1 image files retained
- `showcase/catch_siblings_grandma.png/` ? 1 image files retained
- `showcase/catch_siblings_grandpa.png/` ? 1 image files retained
- `showcase/catch_word_hud/` ? 126 image files retained
- `showcase/cursor_qa_20261016/` ? 3 image files retained
- `showcase/leaderboard_asset_contact.png/` ? 1 image files retained
- `showcase/leaderboard_bg_preview.png/` ? 1 image files retained
- `showcase/leaderboard_fixed_new_1920_960.png/` ? 1 image files retained
- `showcase/leaderboard_fixed_new_960.png/` ? 1 image files retained
- `showcase/leaderboard_oct24_1280_720.png/` ? 1 image files retained
- `showcase/leaderboard_oct24_1600_900.png/` ? 1 image files retained
- `showcase/leaderboard_oct24_1920_1080.png/` ? 1 image files retained
- `showcase/leaderboard_oct24_final_preview.png/` ? 1 image files retained
- `showcase/leaderboard_oct24_preview.png/` ? 1 image files retained
- `showcase/leaderboard_oct24_preview_1920.png/` ? 1 image files retained
- `showcase/leaderboard_old_new_table_body.png/` ? 1 image files retained
- `showcase/leaderboard_old_new_table_header.png/` ? 1 image files retained
- `showcase/leaderboard_old_new_wood_board.png/` ? 1 image files retained
- `showcase/leaderboard_options_oct24_1280_720.png/` ? 1 image files retained
- `showcase/leaderboard_options_oct24_1600_900.png/` ? 1 image files retained
- `showcase/leaderboard_options_oct24_1920_1080.png/` ? 1 image files retained
- `showcase/leaderboard_options_review.png/` ? 1 image files retained
- `showcase/leaderboard_options_review_final.png/` ? 1 image files retained
- `showcase/leaderboard_rows_oct24_1280_720.png/` ? 1 image files retained
- `showcase/leaderboard_rows_oct24_1600_900.png/` ? 1 image files retained
- `showcase/leaderboard_rows_oct24_1920_1080.png/` ? 1 image files retained
- `showcase/leaderboard_selected_1280_720.png/` ? 1 image files retained
- `showcase/leaderboard_selected_1600_900.png/` ? 1 image files retained
- `showcase/leaderboard_selected_1920_1080.png/` ? 1 image files retained
- `showcase/leaderboard_status_oct24_1280_720.png/` ? 1 image files retained
- `showcase/leaderboard_status_oct24_1600_900.png/` ? 1 image files retained
- `showcase/leaderboard_status_oct24_1920_1080.png/` ? 1 image files retained
- `showcase/redesign_phase2/` ? 4 image files retained
- `showcase/review_1280_720.png/` ? 1 image files retained
- `showcase/review_1920_1080.png/` ? 1 image files retained
- `showcase/screens/` ? 3 image files retained
- `showcase/ui_redesign_20261016/` ? 84 image files retained
- `showcase/ui_redesign_m1/` ? 45 image files retained

## Integrity check and limitations

- `tools/test_projectwide_orphan_integrity.gd` is read-only: checks every discoverable source/import pair and `.uid`, checks relative glTF textures, validates quoted resource paths, loads resource scenes without `_ready()` side effects, and attempts to parse production GDScripts. **No database/camera/gameplay data is opened.**
- **Latest post-import smoke test PASS:** Godot 4.7.2 `--headless --editor --path . --quit` exited 0; `tools/test_projectwide_orphan_integrity.gd` checked **32 scenes, eight .tres resources, 44 production scripts, 597 import sidecars, 215 script UIDs, 391 literal paths, six glTF texture references, two glTF binary-buffer references**, with **2,809 checks and zero failures**. All scenes load off-tree. The inventory is live: worker-owned 2.5D QA screenshots and import sidecars were being created concurrently, so exact totals can rise during a full editor pass.
- **Existing test assumptions need updating by their owners:** `tools/test_component_prune_integrity.gd` reports **938 checks, one failure**, its hardcoded 31-scene expectation now stale because a concurrently added 2.5D scene raises the current total to **32**. `tools/test_asset_cleanup_integrity.gd` reports **750 checks, two failures**: the same 31-scene assertion and three transient 2.5D screenshots under `tools/_tmp_25d_*.png` flagged as regular production PNGs outside Components. Its substantive validations report **zero missing resource paths**, **zero missing ExtResource/SubResource identifiers**, **zero unused serialized declarations**, and **175 referenced texture dependencies**. The worker-3 temporary capture files are explicitly protected; edit those test expectations only in their assigned test-owner scope.
- **Final concurrent-workspace recheck PASS:** the most recent `tools/test_projectwide_orphan_integrity.gd` run covered **32 scenes, 8 resources, 44 production scripts, 595 imports, 216 UIDs, 396 quoted paths, six glTF texture URIs and two glTF buffer URIs**, with **2,803 checks and zero failures**. The count differs from the previous snapshot because other workers are generating/removing temporary screenshots and metadata during the audit. Newly generated `tools/_qa_red_plane_review.png` is also a retained 3D visual QA output and is explicitly exempt from importer-sidecar expectations.
- **Five apparent Component orphan candidates are all protected red-plane originals:** `red-plane/73967189f63d4364a9d08f5e29c8523e_R_plane_roughness.png`, `798d9b9285514ddababd3c5b1eaeef7c_R_plane_AO.png`, `9a9ac995d92f4b24a1131987f5313e7f_RGB_plane_basecolor.png`, `c600cf14d6254b8a92a1a81d96477e67_N_plane_normal.png`, and `f60d02ce7b06482f994791f5f9523926_R_plane_metallic.png` beneath `Components/Gameplay/Human Plane/3D/`. They remain exactly as supplied while the model/material mapping is being edited by its owner.
- The test intentionally ignores optional screenshots written by tests and documentary placeholder `res://.../clip.ogg`; these are outputs/examples, not missing production artwork.
- One in-progress **2.5D** scene `ui/minigames/human_plane_25d_view.tscn` temporarily referred to a script being authored by worker-3 during this audit, and was not altered or deleted. Its script subsequently became available and the final projectwide load/parse passed; its author owns any future visual adjustments.
- A renderer-backed 2D/3D playthrough on the final synchronized workspace is still advisable. Source-only analysis cannot determine that a generated or dynamically enumerated sprite will never be needed, nor safely identify an ?unused? copyrighted/user-original art source.

**Decision:** keep the current library intact rather than destroying the two live scene-owned copies or deleting protected QA/model/original resources. Earlier completed asset-prune records remain the evidence of confirmed prior removals.

## Final Human Plane 3D preservation verification — 26 October integration pass

This focused follow-up is **read-only** and does not repeat any historical asset
deletion. The new tools/test_human_plane_final_qa.gd validates the serialized
Human Plane scene and NATURE/PBR source packs without starting gameplay, a
physical camera, pose inference or a database. Unlike a real GPU screenshot,
headless asset validation cannot prove that a model is visible in the frustum.

- Original sources preserved: **all five supplied red-plane maps** (base color,
  normal, AO, roughness, metallic), the original red FBX and attribution,
  Grass_green.fbx and its textures, NATURE mountain scene.gltf with original
  textures/license, and all **eight** supplied Road008A and Grass004
  Color/NormalGL/AO/Roughness maps with matched import sidecars.
- Materials: editable grass004_ground.tres and road008a_path.tres retain
  enabled albedo, normal, AO and roughness textures. The grass GPU resources
  reference the supplied grass-green FBX geometry and alpha-cutout material.
- Editor placement: exactly **four NatureGrass[A-D] MultiMeshInstance3D**
  children with 340 authored transforms each (**1,360 grass instances**);
  the on-disk serialized buffer for each band contains a finite nonzero 3D
  translation, and all four bands have authored visible=true and culling ranges.
- NATURE terrain: **24 imported mountain glTF instances** with nonempty
  geometry and editable transforms under Terrain/Mountains. License retained.
- Trees: **16 supplied FBX tree instances**, not generated cone/cylinder trees.
  No stand-in cone, sphere, prism or cylinder mesh constructors in the scripts.
- Red plane: the scene has a nested RedPlaneModelScale/RedPlane FBX, with
  **22 populated meshes and 22 imported surface materials** and a large authored
  scale factor. All **22 of 22 materials retain albedo textures loaded from the
  original red-plane source directory**; material hookups are real, not generic
  flat-color replacements. This verifies the imported asset, NOT its on-screen
  appearance. Worker-2 owns the final RTX/OpenGL visual confirmation.
- **All five RED PLANE maps VERIFIED after initialization:** the initial
  off-tree-only diagnostic inspected the raw FBX importer and found its unaltered
  base surfaces lacked metallic, roughness and AO. The final read-only test
  instead adds only the isolated 3D view to a disposable SceneTree, allowing
  worker-2's actual _ready-time per-surface PBR material overrides to run,
  **without instantiating gameplay, a real webcam or any database**. Effective
  mesh material inspection then finds albedo **22/22**, normal **22/22**,
  roughness **22/22**, metallic **22/22** and AO **22/22**. The editor-authored
  red_plane_pbr.tres template also individually references all five original
  user-supplied texture sources. The earlier warning is now resolved.
- **GPU visual evidence recovered:** a real 1280×720 rendered local capture
  named tools/_qa_red3d_review.png was inspected during the integration pass.
  It clearly displays the bright-red aircraft centered below the three
  blue/green/orange answer rings, backed by the mountain ridge and textured
  roadway. Thus the earlier report of a missing plane does **not** describe
  this newer screenshot; final screenshot correspondence with worker-2's final
  scene revision must still be confirmed by its author. The original transient
  tools/ capture has now been cleaned up by the capture-owning worker.

### Final synchronized QA results

The headless Godot editor-import pass exited successfully. All five final
read-only runs exited **PASS**, after the screenshot-owning workers cleared
temporary files from tools/ (worker-4 did not delete them):

| Validation | Scope / result | Outcome |
| --- | --- | --- |
| Godot 4.7.2 editor import | Project resource parse and import | PASS |
| tools/test_projectwide_orphan_integrity.gd | **2,814 checks**, 32 scenes, 10 serialized TRES, 44 scripts, 595 import sidecars, 222 UIDs, 409 resource literals, 6 glTF image and 2 glTF buffer references | **PASS**, 0 failures |
| tools/test_component_prune_integrity.gd | **940 checks**, 32 scenes, 203 Components PNG, **0 orphan candidates**, no missing serialized resources | **PASS**, 0 failures |
| tools/test_asset_cleanup_integrity.gd | **772 checks**, 32 scenes, 10 TRES, 184 texture dependencies, **0 PNG outside Components**, 0 missing paths or resource IDs | **PASS**, 0 failures |
| tools/test_human_plane_3d_pbr.gd | **53 checks** for source NATURE FBX grass geometry, 4 authored 340-transform batches, Road008A/Grass004 texture channels | **PASS**, 0 failures |
| tools/test_human_plane_final_qa.gd | **242 checks**, 24 mountains, 16 supplied model trees, four visible authored grass batches with nonzero serialized transforms, 5 red-plane texture channels on 22/22 effective materials, no tools/ PNG snapshots | **PASS**, 0 failures |

This is read-only **asset and scene preservation QA**, not a claim of end-to-end
YOLO/calibration performance, graded gameplay scoring, accessibility or every
GPU frame. The verified 1280×720 red-aircraft capture is affirmative visual
evidence, but the production renderer and camera viewpoint remain under
worker-2's ownership for ongoing visual refinements. No asset deletion,
production script mutation, commit, camera access or database action was
performed in worker-4's final QA.
