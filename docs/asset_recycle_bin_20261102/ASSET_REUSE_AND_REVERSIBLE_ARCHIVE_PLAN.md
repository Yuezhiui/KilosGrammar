# KilosGrammar calibration artwork: full-repo reuse and reversible archive audit

Audit date: **2026-11-02**. Scope: 20 live PNGs under `Components/Gameplay/Calibration/`, their 20 PNG import sidecars, and candidate reuse from other `Components/` folders. Examined **544** textual source/QA/manifest files, including all current `.tscn`, `.gd`, and `.tres` files. Exact filename/path/UID cross-references and SHA-256 digests are in `calibration_reference_audit.json`; rerun `python docs/asset_recycle_bin_20261102/scan_calibration_references.py` after additional scene changes.

## Actual reusable assets (confirmed by inspecting the PNG pixels)

| Existing source | Exact image | Suitable reuse | Current live use |
| --- | --- | --- | --- |
| `Components/Gameplay/Calibration/BORDER.png` | 1448×1086 wood/clover frame with **baked black center**, not a heading | Camera frame, with the scene's existing transparent-center shader | Single and multiplayer camera frames; Human Plane retains it |
| `Components/Gameplay/Calibration/1.png`, `2.png`, `3.png` | Three separate **1254×1254** circular wooden numbered countdown badges | Countdowns with separately movable `TextureRect` nodes | Single, multiplayer, and Human Plane scenes |
| `Components/Gameplay/Balloon Popping/Art/reference/prompt_blank.png` | **472×235** blank cream/gold bordered plaque (not a wooden heading with prewritten words) | Header or Player One/Two backing, with separate Godot text labels; `NinePatchRect` can resize | Single `HeaderPlaque`/`PlayerOnePlaque`; multiplayer `WoodenHeaderBoard`, two `NamePlate` controls |
| `Components/StudentSetup/Redesign/STUDENT PROIFILE.png` | 2172×724 wooden banner **with STUDENT PROFILE baked in** | Only for its actual student profile heading | Student setup |
| `Components/StudentSetup/Redesign/STUDENT GAME SETUP.png` and `qw.png` | 2172×724 decorative wooden banners **with existing setup wording baked in** | Not suitable for blank calibration/player labels | Student setup/reference use |
| `Components/Game Chooser/header1.png` | 1938×497 bordered header with instructional wording baked in | Not suitable as blank Player One/Two header | Game chooser |
| `Components/Gameplay/Catch the Word/HUD/generated/title_board.png` | 1200×400 title board with **CATCH THE WORD baked in** | Do not repurpose as generic heading | Catch minigame |
| `Components/Tutorial/Redesign/grammar_panel_green.png` | 1672×604 green panel with white blank center | Possible decorative backdrop; **not wood** | Grammar tutorial |
| `Components/Results/Redesign/Assets/panel_student_wide.png` | 2170×725 orange/blue student panel, **STUDENT baked in** | Player details panel, not a blank nameplate | Results |

**No separate PNG with exact editable `CALIBRATION`, `PLAYER ONE`, or `PLAYER TWO` wooden header artwork was found in the 253 `Components/` PNGs inspected.** The current two-player scene deliberately overlays editor-authored English labels on the genuine blank plaque. This avoids inventing graphics or cropping text out of composites. Do not claim the gold plaque is a dedicated wood title.

## Confirmed live references: DO NOT ARCHIVE

- `calibration.tscn`: `BACKGROUND.png`, `BORDER.png`, and three numbered wooden countdown badges. The prime has already removed the old directional/image-guide nodes from this **single-player** scene.
- `multiplayer_calibration.tscn`: `BACKGROUND.png`, `BORDER.png`, `BACK.png`, and three numbered countdown badges; it also uses the real `prompt_blank.png` from Balloon Popping.
- `human_plane_calibration.tscn`: still references the old `ARROW.png`, `MOVE TO HIGHLIGHTED AREA.png`, three `STAY ...` images, three `STEP ...` images, `Pose Guides/DEFAULT.png`, `Pose Guides/BALOON POP.png`, `Pose Guides/PLANE T POSE.png`, and both `PLANE GOING TO ...` PNGs. Some are currently hidden, but they are still serialized dependencies. **Human Plane T-pose artwork must be preserved unchanged.**
- `STARS.png`: original live PNG is restored. Though no active scene has an explicit image reference, the standalone QA, documentation, and existing reversible archive use it. **Keep this exact live file and its `.import` sidecar.**

References marked `possible_dynamic` in the JSON are *uncertain textual matches* (a script can concatenate a directory and filename); do **not** interpret them as safe-to-delete evidence. Generated imports, UID references, QA fixtures, and potential externally packed release dependencies require caution even when the scene no longer draws the image.

## Existing recycle bin: preserved and verified

The pre-existing `recycled_assets.zip` already holds six files: PNG + `.import` for `StudentSetup/Redesign/CONTINUE FILL.png`, `CONTINUE NOT FILL.png`, and a **backup-only** `Gameplay/Calibration/STARS.png`. The README's three SHA-256 values were checked against the ZIP payload. Live `STARS.png` matches its archived checksum **E7616EE74CDE8FB894CAA9497216B2C69B43D1425DD050CB18A9846867C93359**. Do not re-archive or overwrite those entries.

## Reversible archiving procedure (future work only; no new assets moved)

1. Finish and save all prime-owned `.tscn` changes. Re-run the reference scanner. Require **zero full-path and UID references in all source scenes/scripts**, and inspect each possible dynamic reference and test/manifest entry manually. A merely invisible TextureRect is **not** evidence that its PNG is unused.
2. For any newly confirmed unused asset, record original `res://` path, SHA-256, PNG dimensions, matching `.png.import` UID, referring tests, and explicit written decision. Back up the **PNG and its exact `.import` together** with their original relative paths.
3. Put the archive **outside Godot's `res://` scan**, or in one ZIP only (like `recycled_assets.zip`); do not place loose `.png.import` copies into `res://docs` or duplicate a UID. Do not overwrite the existing ZIP without verifying and preserving its entries.
4. Move only the newly approved PNG/`.import` pair. Immediately run Godot headless editor import, the affected standalone layout and camera-flow QA, and the relevant Windows export checks. On any missing resource, invalid UID, or failing test, restore **both** files to their original paths from the archive and verify the SHA-256 before reimporting.
5. For `STARS.png` and the inherited Human Plane images, the standing decision is **KEEP**. No unilateral archival or deletion is authorized.

### Independent QA coordination

`tools/test_calibration_assets_layering.gd` is the focused asset authenticity/layout regression for 1280×720, 1600×900 and 1920×1080. It must validate both the new single-player scene and the unchanged Human Plane scene, and inspect multiplayer's authored nodes without mounting the multiplayer root (its `_ready()` starts the camera).

At initial post-prime run, this test correctly detected a **real single-player label overlap**: Godot's two-line `NeutralInstruction` expanded from its requested height to 111px, covering camera y209..265 by **56px** at all three resolutions. The prime corrected the production node to a shorter single-line 27pt English prompt, **without weakening the QA assertion**. On re-run, Godot 4.7.2 headless reports **PASS 210 checks, 0 failures**, at all three resolutions, including no camera/prompt overlap and untouched Human Plane T-pose. No scene edit was made by the audit worker.

**Changes performed by this audit:** only documentation and the authorized focused QA test. **No image, import sidecar, production scene/script, existing ZIP, Git history, camera service, or database was changed by the audit worker.**
