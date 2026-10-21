# Phase 2: MAIN + STUDENT GAME SETUP art inventory

Status: **source-derived assets prepared, not yet an integrated/responsive UI**.
All output PNGs are new. Eleven source images under Windows Downloads are
unchanged, as are all preexisting Godot production scenes, scripts and assets.

## Source provenance

The reproducible extractor is `extract_phase2.py`; run
`python ui/redesign/assets/extract_phase2.py main student shared` when the
original PNGs are available under these folders inside Windows Downloads:

- `MAIN/` — seven original 1672×941 sheets; six layered transparent component
  sheets and one flattened opaque MAIN design reference.
- `STUDENT GAME SETUP/` — four transparent 1672×941 component sheets.
- `SETTINGS/52c44321-00e4-4f07-92ce-012696fa4ce6.png` — an independent
  1672×941 classroom illustration used **only** for the shared backdrop.

See [asset_manifest.json](asset_manifest.json) for the **exact complete source
filenames, SHA-256 hashes, source pixel crop rectangles (xyxy; right/bottom
exclusive), output paths, pixel dimensions, file sizes and alpha reports**.
Manifest paths are portable relative to `Downloads/`, without usernames.

## MAIN — runtime sprites

| Output under `main/` | Role | Extraction notes |
|---|---|---|
| `bg_clouds.png` | Teal classroom/menu backdrop with clouds | Transparent rounded corners; standalone source area, not a flattened mockup |
| `bg_clouds_starry.png` | Alternative teal/cloud/star background | Independent source area |
| `logo_full.png` | **Complete KILOS GRAMMAR logo** | Letterforms/colored tiles/stars baked together |
| `logo_compact.png` | Alternate KILOS wordmark **only** | NOT a full replacement for `logo_full.png` |
| `btn_tutorial.png` | Purple TUTORIAL with book | Complete labeled button |
| `btn_play.png` | Green PLAY with triangle | Complete labeled button |
| `btn_quit.png` | Red QUIT with exit icon | Complete labeled button |
| `btn_leaderboard.png` | Small dark LEADERBOARD with trophy | Complete labeled button |
| `btn_settings.png` | Small dark SETTINGS with gear | Complete labeled button |
| `btn_credits.png` | Small dark CREDITS with star | Complete labeled button |
| `btn_blank_purple.png` | Unlabeled purple rounded button | May carry live text/icons if desired |
| `btn_blank_green.png` | Unlabeled green rounded button | May carry live text/icons |
| `btn_blank_red.png` | Unlabeled red rounded button | May carry live text/icons |
| `btn_blank_nav.png` | Unlabeled short dark navigation button | Live text/icon required |
| `cloud_edge_left.png` | Narrow edge cloud cluster | Standalone transparent decoration |
| `cloud_edge_center.png` | Wide cloud strip | Standalone transparent decoration |
| `cloud_edge_right.png` | Second cloud strip | Standalone transparent decoration |
| `sparkle_gold.png` | Yellow four-point sparkle | Source pixels, transparent |
| `sparkle_white.png` | Cyan/white four-point sparkle | Source pixels, transparent |
| `sticker_today.png` | Blue TODAY decorative badge/rays | Alpha-isolated from adjacent SOFT rays |
| `sticker_soft.png` | Gold SOFT decorative badge/rays | Alpha-isolated from adjacent TODAY rays |
| `sticker_book.png` | White/teal book motif | Alpha-isolated from adjacent book variant |
| `sticker_book_green.png` | Dark green book motif | Alpha-isolated from adjacent book variant |

**MAIN source mapping:** `f2abe4b3…` supplies the full/alternate logos,
`5e404e45…` the teal cloud backdrops, `81a7d8bd…` the six actual buttons
and blank states, `16e2cc3e…` white/gold sparkles, `4ba88951…`
TODAY/SOFT, `7ef65dc8…` book motifs. The opaque flattened
`91190188-c67a-449d-a03f-a52542d668a5.png` is retained as a **reference
only** and was not copied or used as a runtime background.

## STUDENT GAME SETUP — runtime sprites

| Output under `student/` | Role |
|---|---|
| `btn_back.png` | Purple BACK navigation with left arrow |
| `btn_continue.png` | Green CONTINUE navigation with right arrow and yellow highlights |
| `topic_noun.png` | NOUN choice |
| `topic_pronoun.png` | PRONOUN choice |
| `topic_verb.png` | VERB choice |
| `topic_adjective.png` | ADJECTIVE choice |
| `topic_adverb.png` | ADVERB choice |
| `topic_preposition_locked.png` | PREPOSITION — SOON, noninteractive |
| `topic_conjunction_locked.png` | CONJUNCTION — SOON, noninteractive |
| `topic_interjection_locked.png` | INTERJECTION — SOON, noninteractive |
| `mode_seconds.png` | 60s game-mode selector; baked 60s text |
| `mode_lives.png` | 3 LIVES game-mode selector; baked 3 LIVES text |
| `difficulty_easy.png` | EASY with one star |
| `difficulty_normal.png` | NORMAL with two stars |
| `difficulty_hard.png` | HARD with three stars |
| `setup_main_panel.png` | Large independently cropped blue-border/cream-center panel |
| `setup_heading.png` | GAME SETUP header with gamepad |
| `setup_topic_caption.png` | GAME STYLE / GRAMMAR TOPIC caption strip |
| `setup_mode_caption.png` | GAME MODE / UI PREVIEW caption strip |
| `setup_difficulty_caption.png` | DIFFICULTY caption strip |
| `setup_required_caption.png` | REQUIRED form-fields caption strip |
| `icon_player.png` | Orange student icon |
| `icon_clipboard.png` | Blue clipboard icon |
| `icon_graduation.png` | Graduation cap |
| `icon_gamepad.png` | Game controller |
| `icon_book.png` | Open-book icon |

**STUDENT source mapping:** `42268c5f…` supplies BACK, CONTINUE and
classroom icons; `435d767e…` all eight grammar topic cards;
`7ee2f611…` both game modes and all difficulties; `ce1ac866…`
separate large panel, heading and labeled strips.

## Shared art

| Output | Original | Usage |
|---|---|---|
| `shared/classroom_bg.png` (1672×941) | `SETTINGS/52c44321-00e4-4f07-92ce-012696fa4ce6.png` | Clean standalone chalkboard, sunlit window, books, plants and desk background for Student two-column form |

This source is intentionally an **opaque background illustration**, not a
flattened UI screenshot and not a sliced atlas component.

## Integration limitations to respect

1. **Artwork is not interaction.** Add separate Godot Button/TextureRect nodes
   and live state/focus/keyboard semantics. Real art has baked labels, so never
   overlay duplicate TUTORIAL/PLAY/QUIT, subject, mode or difficulty words.
2. **Baked advisory text:** Student `setup_mode_caption.png` literally says
   **UI PREVIEW**; `setup_required_caption.png` includes example required
   fields. Treat these as static labels, not editable text.
3. **Selectable scope:** Five grammar topics are playable. Three "SOON" cards
   are deliberately locked, not implemented lessons. Mode badges are selectors
   with baked 60s/3 LIVES, **not** runtime time/life HUDs.
4. **Stretching:** The 811×465 cloud background has rounded transparent
   corners; place teal beneath it to avoid empty corner flashes. The 1434×507
   blue frame is not author-provided nine-slice metadata. Avoid distorting
   its corners, fonts, or border. Keep button image aspect ratios.
5. **True-source separations:** MAIN stickers' yellow rays and paired book
   motifs come from close islands; only source-alpha connected components
   were included, without painting replacements. All MAIN and STUDENT exports
   preserve transparencies and antialiasing from the source sheets.
6. **Review scope:** The output is semantically sliced, not a pixel-perfect
   recreation of the flattened screenshot. Actual two-column layout,
   interactive selection highlights, navigation and responsive viewport
   checks are integration work. Test 875×500, 1280×720 and 1920×1080.
7. **Unmanaged extra:** Another `main/sticker_book_white.png` currently exists
   beside the generated sprites but is **not in the reproducible extractor or
   manifest**. Its owner/provenance should be checked before use; this
   extraction has not deleted, modified or claimed that file.

QA contact sheets live under ignored `showcase/redesign_phase2/`, not the
runtime asset directories. This milestone leaves all older resource trees
and gameplay mechanics intact.
