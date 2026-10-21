# Redesign Phase 3: original Game Over, Tutorial, and Settings sprites

Source material is the user's **actual** PNG artwork in Windows Downloads.
This extraction contains **105 individual runtime PNGs**, not screenshots
or a flattened page:

| Folder | Original source sheets | Exported assets | Contents |
| --- | --- | --- | --- |
| `GAME OVER` | 5 files; one duplicate | `game_over/` — 39 | Blank/baked result cards, independent retry/main-menu button states, score bar, teal backdrops, stars and classroom decorations |
| `TUTORIAL` | 5 | `tutorial/` — 24 | Standalone classroom background, title, three-step preview, tutorial disclaimer, 4 independent buttons, blank cream card, mascot and icons |
| `SETTINGS` | 6 | `settings/` — 42 | Baked SETTINGS title, blank framed panels/fields, HOME and tab buttons, icon sets, static slider/toggle samples, books/plants |

The complete input inventory is **27 PNGs** across five user folders:
`MAIN` (7), `STUDENT GAME SETUP` (4), `GAME OVER` (5),
`TUTORIAL` (5), and `SETTINGS` (6). Phase 2 already extracted the
MAIN/STUDENT artwork into their respective directories; this phase does
not alter those outputs. The duplicate `GAME OVER/bd415751-... (1).png`
was byte-identical to the canonical panel sheet and is deliberately
not a second set of assets.

The source PNGs remain in Downloads, unmodified. Regenerate this phase:

```powershell
python ui/redesign/assets/extract_phase3.py
python ui/redesign/assets/extract_phase3.py --source-dir "D:/some/Downloads"
```

The extractor defaults to `KILOS_GRAMMAR_SOURCE_DIR` or
`Path.home()/Downloads`. Its `--overwrite` flag is required if a
generated sprite was subsequently edited and differs from the original
export. Dependencies Pillow, numpy and OpenCV are required **only**
when a developer runs the extraction; the game loads the finished
PNGs normally with Godot and does not run Python.

## Precise manifest and source fidelity

[phase3_manifest.json](phase3_manifest.json) records, for all 105
exported files:

- Godot resource path, original source filename and SHA-256 fingerprint
- original source connected-alpha component rank and crop rectangle
- exact pixel dimensions, alpha bounds, exported bytes and role
- whether words/icons are baked into the original artwork

All cutouts come from the actual source RGBA pixels and keep the
original antialiasing. Adjacent atlas contents are masked using the
original alpha-connected component rather than painting replacements.
The classroom tutorial background is an **original standalone RGB
illustration**, converted to RGBA for consistent runtime texture
handling. The GAME OVER teal backgrounds are individual source
background panels, not copied from the flattened screenshot.

## How to integrate correctly

Godot scene builders can use
`res://ui/redesign/shared/cartoon_widgets.gd` and
`res://ui/redesign/shared/responsive_canvas.gd`, documented in
`ui/redesign/shared/README.md`. These use native Godot Buttons,
TextureRects, ScrollContainers and GridContainers with real input,
keyboard focus and viewport scaling.

- The `game_over/button_*.png`, `tutorial/button_*.png` and
  `settings/tab_*.png` sprites contain printed words and icons.
  Do not duplicate that text visually on top of them. The native
  Button still needs a meaningful `text` and `tooltip_text`.
- GAME OVER `panel_student`/`panel_round` have baked captions, but
  `panel_student_blank` and `panel_round_blank` leave room for
  live student name, score, mode and other values.
- TUTORIAL `steps_three.png` is a printed illustration describing
  camera/calibration/practice. The note `camera_advisory.png` clearly
  identifies body tracking as a UI preview until it is connected.
- SETTINGS `volume_preview_*.png` and `toggle_*_sample.png`
  display **baked numeric/ON/OFF labels** and cannot represent live
  slider or toggle state. For functional controls, use a native HSlider
  or CheckButton with source-derived blank field/frames and dynamic
  labels. The sample artwork is useful as a visual reference only.
- Avoid applying nine-slice stretching to completed illustrated
  buttons; preserve their original aspect ratio, rounded corners,
  shadows and baked text.
- The five source folders do not contain an independent `CREDITS`
  illustration sheet. Use the available shared classroom/teal
  backgrounds and native text for that screen.

## Validation

Tested with Windows Godot **4.7.2**:

```powershell
godot --headless --editor --path . --import
godot --headless --path . --script res://ui/redesign/shared/smoke_test.gd
```

Use the Godot 4.7.2 executable appropriate for the workstation (or the
absolute executable path when `godot` is not on `PATH`). The import exited 0. Every PNG under
`game_over/`, `tutorial/`, and `settings/` had a corresponding
`.png.import` and a nonempty Godot `.ctex` cache: **39/39,
24/24, 42/42**. The shared UI runtime smoke test exited 0 and
loaded 21 representative sprites, built a native focused Button,
and checked compact/wide grid behavior and viewport aspect fitting.

This asset milestone does not assert that the independent screen
integrations have passed user-journey or visual QA. Review these at
875×500, 1280×720, and 1920×1080 after integration.
