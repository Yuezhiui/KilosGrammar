# Other UI asset pruning ? October 25, 2026

Removed 118 unused PNG assets, 118 matching .import sidecars, and one stale Main Panel README (237 files in total). Each image was verified byte-identical to the tracked pre-migration Git original; imported UIDs were checked against their original tracked sidecars.

## Exact removed image paths

Each listed image was removed together with its corresponding same-path .import sidecar.

### Components/Main Panel/Original

Unused original buttons, icons, typos and duplicate copies. The scene-backed original images remain. The former green-button.png image was also removed after the Main Menu regression was updated to load its live green-play.png image.

- Components/Main Panel/Original/green-button.png
- Components/Main Panel/Original/Book.png
- Components/Main Panel/Original/exit.png
- Components/Main Panel/Original/play.png
- Components/Main Panel/Original/purple-button.png
- Components/Main Panel/Original/red-button.png
- Components/Main Panel/Original/setting-lage.png
- Components/Main Panel/Original/setting.png
- Components/Main Panel/Original/settings.png
- Components/Main Panel/Original/stars.png
- Components/Main Panel/Original/starts.png
- Components/Main Panel/Original/trophy.png

### Components/Main Panel/Redesign

Unused Phase-2 extracted Main Menu alternate art. No runtime or test references, and no caller requests main-category sprites through cartoon_widgets. Extraction is reproducible from its source art.

- Components/Main Panel/Redesign/bg_clouds.png
- Components/Main Panel/Redesign/bg_clouds_starry.png
- Components/Main Panel/Redesign/btn_blank_green.png
- Components/Main Panel/Redesign/btn_blank_nav.png
- Components/Main Panel/Redesign/btn_blank_purple.png
- Components/Main Panel/Redesign/btn_blank_red.png
- Components/Main Panel/Redesign/btn_credits.png
- Components/Main Panel/Redesign/btn_leaderboard.png
- Components/Main Panel/Redesign/btn_play.png
- Components/Main Panel/Redesign/btn_quit.png
- Components/Main Panel/Redesign/btn_settings.png
- Components/Main Panel/Redesign/btn_tutorial.png
- Components/Main Panel/Redesign/cloud_edge_center.png
- Components/Main Panel/Redesign/cloud_edge_left.png
- Components/Main Panel/Redesign/cloud_edge_right.png
- Components/Main Panel/Redesign/logo_compact.png
- Components/Main Panel/Redesign/logo_full.png
- Components/Main Panel/Redesign/sparkle_gold.png
- Components/Main Panel/Redesign/sparkle_white.png
- Components/Main Panel/Redesign/sticker_book.png
- Components/Main Panel/Redesign/sticker_book_green.png
- Components/Main Panel/Redesign/sticker_soft.png
- Components/Main Panel/Redesign/sticker_today.png

### Components/Settings/Redesign

Older redundant knob; the active Settings screens and generator load slider_knob_green_28.png.

- Components/Settings/Redesign/slider_knob_green.png

### Components/Student Setup/Redesign

Unused Phase-2 icons, setup-required caption and three locked-out grammar topic variants; omitted from the active game and scene tests.

- Components/Student Setup/Redesign/icon_book.png
- Components/Student Setup/Redesign/icon_clipboard.png
- Components/Student Setup/Redesign/icon_gamepad.png
- Components/Student Setup/Redesign/icon_graduation.png
- Components/Student Setup/Redesign/setup_required_caption.png
- Components/Student Setup/Redesign/topic_conjunction_locked.png
- Components/Student Setup/Redesign/topic_interjection_locked.png
- Components/Student Setup/Redesign/topic_preposition_locked.png

## Images retained for safety

- All Phase-3 images actively referenced by editor-authored .tscn scenes, the current smoke test, or dynamic Settings tabs. The current smoke test checks actual scene artwork and no longer requires all historical extracted variants.
- All Main Menu scene assets, including green-play.png now loaded by tools/test_main_menu_editor_layout.gd.
- All current Student Setup, Results, Settings, Tutorial, and Shared textures referenced by production scenes, runtime code, tests, and the Settings builder.
- All image assets outside the six assigned Components folders and all uncertain dynamic variants.

## Historical metadata outside the task scope

The main agent independently removed the stale ui/redesign/assets/asset_manifest.json, phase3_manifest.json, ART_INVENTORY.md and PHASE3_INVENTORY.md files. Those files were outside the six Components directories assigned to this worker and were not modified here. The historical Phase-2/Phase-3 extractors remain available to regenerate sprites from original source sheets if desired.

## Audit and validation

The project .tscn, .gd, .tres, other executable/test references, cartoon_widgets dynamic categories, Phase-2/Phase-3 manifests, and image extraction scripts were checked. Godot 4.7.2 headless editor parse: PASS. Scene-based sprite smoke test: PASS (45 active scene-referenced sprites). Settings integration: PASS; Settings UI 328/328; Student Setup 126/126; Guided Tutorial 144/144; Tutorial accessibility 156/156; Spotlight 106/106; Main Menu cursor routing: PASS with an existing ObjectDB leak warning. Main Menu editor layout: 6 existing button-size assertion mismatches (the scene authoring dimensions differ from fixed test expectations), unrelated to image removal. All 73 remaining in-scope images have an .import sidecar and every serialized .tscn/.tres image reference resolves.

## Second pass: obsolete Phase-3 extracted variants

After the prime agent updated ui/redesign/shared/smoke_test.gd to verify current authored scene references rather than requiring 105 historical source art outputs, 74 more image+import pairs were proven unused and deleted. The changing Settings tab images were explicitly protected: tab_settings_cream.png, tab_controls_green.png, and tab_camera_green.png are constructed via runtime string formatting.

The prime separately deleted the no-longer-needed 105-entry Phase-3 provenance manifest, and the revised smoke test now checks active scene dependencies.


### Components/Results/Redesign

Rationale: Unused Game Over decorative, alternative button and panel images; Results scene uses bg_teal_clean.png and keeps it.

- Components/Results/Redesign/bg_teal_decorated.png
- Components/Results/Redesign/button_blank_blue.png
- Components/Results/Redesign/button_blank_purple.png
- Components/Results/Redesign/button_main_menu.png
- Components/Results/Redesign/button_main_menu_disabled.png
- Components/Results/Redesign/button_main_menu_hover.png
- Components/Results/Redesign/button_retry.png
- Components/Results/Redesign/button_retry_disabled.png
- Components/Results/Redesign/button_retry_hover.png
- Components/Results/Redesign/decor_balloons.png
- Components/Results/Redesign/decor_books_blue.png
- Components/Results/Redesign/decor_books_red.png
- Components/Results/Redesign/decor_books_stack.png
- Components/Results/Redesign/decor_clouds.png
- Components/Results/Redesign/decor_word_him.png
- Components/Results/Redesign/decor_word_learn.png
- Components/Results/Redesign/decor_word_often.png
- Components/Results/Redesign/decor_word_play.png
- Components/Results/Redesign/decor_word_today.png
- Components/Results/Redesign/icon_avatar.png
- Components/Results/Redesign/icon_chart.png
- Components/Results/Redesign/icon_controller.png
- Components/Results/Redesign/icon_gear.png
- Components/Results/Redesign/icon_grad_cap.png
- Components/Results/Redesign/icon_star_green.png
- Components/Results/Redesign/icon_star_large.png
- Components/Results/Redesign/icon_star_small.png
- Components/Results/Redesign/icon_student_id.png
- Components/Results/Redesign/icon_target.png
- Components/Results/Redesign/panel_results_header.png
- Components/Results/Redesign/panel_results_side.png
- Components/Results/Redesign/panel_round.png
- Components/Results/Redesign/panel_round_blank.png
- Components/Results/Redesign/panel_round_rows.png
- Components/Results/Redesign/panel_student.png
- Components/Results/Redesign/panel_student_blank.png
- Components/Results/Redesign/panel_student_rows.png
- Components/Results/Redesign/score_footer.png

### Components/Settings/Redesign

Rationale: Unused decorative variants, example switches, blank cards and volume previews; Settings remains backed by actual scene images and six dynamic tab variants.

- Components/Settings/Redesign/button_blank_cream.png
- Components/Settings/Redesign/button_blank_green.png
- Components/Settings/Redesign/decor_books_blue.png
- Components/Settings/Redesign/decor_books_purple.png
- Components/Settings/Redesign/decor_books_red.png
- Components/Settings/Redesign/decor_books_standing.png
- Components/Settings/Redesign/decor_green_leaves.png
- Components/Settings/Redesign/decor_leaf_cluster.png
- Components/Settings/Redesign/decor_plant.png
- Components/Settings/Redesign/field_card_blue.png
- Components/Settings/Redesign/field_card_cream.png
- Components/Settings/Redesign/field_row_blue.png
- Components/Settings/Redesign/field_row_cream.png
- Components/Settings/Redesign/field_row_header.png
- Components/Settings/Redesign/field_row_white.png
- Components/Settings/Redesign/icon_cap.png
- Components/Settings/Redesign/icon_cat.png
- Components/Settings/Redesign/toggle_off_sample.png
- Components/Settings/Redesign/toggle_on_sample.png
- Components/Settings/Redesign/volume_preview_empty.png
- Components/Settings/Redesign/volume_preview_full.png
- Components/Settings/Redesign/volume_preview_mid.png

### Components/Tutorial/Redesign

Rationale: Unused archived tutorial artwork; kept the separate scene-authored cards, arrow, star, button and backdrop images.

- Components/Tutorial/Redesign/button_movement.png
- Components/Tutorial/Redesign/camera_advisory.png
- Components/Tutorial/Redesign/decor_leaf.png
- Components/Tutorial/Redesign/decor_leaves.png
- Components/Tutorial/Redesign/decor_pencil.png
- Components/Tutorial/Redesign/icon_calibration.png
- Components/Tutorial/Redesign/icon_cap.png
- Components/Tutorial/Redesign/icon_cat.png
- Components/Tutorial/Redesign/icon_guide.png
- Components/Tutorial/Redesign/icon_home.png
- Components/Tutorial/Redesign/icon_movement.png
- Components/Tutorial/Redesign/panel_blank.png
- Components/Tutorial/Redesign/path_title.png
- Components/Tutorial/Redesign/steps_three.png

## Concurrent final fixture removal

The prime agent updated tools/test_main_menu_editor_layout.gd to use the scene-backed Components/Main Panel/Original/green-play.png. The previously QA-only Components/Main Panel/Original/green-button.png and its matching .import were then already deleted concurrently before this worker attempted its final image cleanup. Both are absent and recorded here without replaying a deletion.
