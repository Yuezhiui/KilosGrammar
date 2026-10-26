# Choose Game art and editable Godot layout

All 13 PNGs in this folder were copied byte-for-byte from
`C:\Users\Yue\Downloads\Gamemode chooser` on 2026-10-26.
Original filenames, dimensions, transparency and colors are retained.
The matching `.png.import` files are Godot-generated resource import metadata.

The production chooser is **`res://ui/play/play_activity.tscn`** and its
controller is **`res://ui/play/play_activity.gd`**. Open the scene directly in
Godot to drag, resize or replace its visible, scene-authored Controls:

- `CleanBackdrop`: uses the project's existing classroom environment art,
  `res://Components/Shared/Redesign/classroom_bg.png` (no duplicate copy).
- `LayoutMargins/Content/Header`: title artwork `choose an activity.png`
  and `header1.png`.
- `LayoutMargins/Content/GameRow/GameOptions`: `bg1.png` wooden game
  board and three clickable native Buttons containing the matching PNGs.
- `LayoutMargins/Content/GameRow/GameDetail/DetailContent/SelectedPreview`:
  the **single** right preview TextureRect. It starts as
  `select game default.png` and switches to the selected game's image.
- `LayoutMargins/Content/Footer/{BackButton,NextButton}`: native input
  controls with child artwork. The Next texture changes from
  `next student setup.png` to
  `next student setup if already choose.png` when a game is selected.

The 1280 × 720 `LayoutMargins` artboard scales uniformly with the viewport,
so all authored child positions stay editable and retain their proportions at
1280 × 720, 1600 × 900 and 1920 × 1080. Existing global native button hover
animations still apply to the buttons and their child image artwork.

An empty/unrecognized game selection leaves Next truly disabled, prevents
emitting a navigation event, and displays the default preview. Pressing any of
the three game images stores the original exact activity name in context,
shows that game's preview, gently brightens the selected image and enables Next.
Pressing the already-selected button keeps it selected. Next continues through
the existing Teacher/Student Setup, topic and auto-calibration routes; Back
keeps its original guided/ordinary behavior. No database, camera, or gameplay
service is needed for this chooser.

## Cleanup and live-asset audit (2026-10-26)

The former **gold rounded selection border** was the extra
`SelectedFrame` panel (three copies) with the `SelectedOutline` style.
Those unused nodes and their style were deleted from the chooser scene.
Their visibility code was removed from the chooser script. The legacy,
always-hidden `SelectedBadge`, `SelectedTitle`, and
`SelectedDescription` labels and related dead copy were also removed.
The selected state now uses the existing artwork with a small brightness
change; native keyboard focus is still indicated by a thin, understated
light-blue underline rather than a yellow rounded border. The GlobalButtonHover
animation is unchanged.

**No PNG or `.png.import` in this folder is orphaned.** All 13 PNGs
were checked against **production scene references and script preloads**,
not just the inventory. Their corresponding 13 Godot imports are also
active and must be retained. Deleting any of these would break a current
state, game preview, Next/Back control, title, instruction, or options board:

| Artwork | Active purpose |
| --- | --- |
| `choose an activity.png`, `header1.png` | Top title and instruction artwork |
| `bg1.png` | Left Game Options board |
| `catch the word button.png`, `human plane button.png`, `ballooon popping button.png` | Three native clickable game buttons |
| `catch the word.png`, `human plane.png`, `balloon popping.png` | Three dynamically selected game previews |
| `select game default.png` | Right preview before a selection |
| `back button.png` | Back navigation |
| `next student setup.png`, `next student setup if already choose.png` | Disabled and enabled Next artwork |

No unused chooser image, backup art, source JSON, or orphaned import metadata
was found; deleting arbitrary originals solely to reduce the count would
remove active runtime dependencies.

Verification commands (run from the project root with Godot 4.7.2):

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_game_chooser_redesign.gd
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --script res://tools/test_game_chooser_redesign_visual.gd
```

Visual test screenshots are written to `user://_qa_chooser_*.png`, outside
the production artwork directory.

## Original PNG SHA-256 checksums

| Original filename | SHA-256 |
| --- | --- |
| `back button.png` | `f543bc918f8e5355cd9f6902edef8083eb8d338f5a223ccffd9009272d9b3569` |
| `balloon popping.png` | `c51f5b8ec575887adcbd1cad714be91943e814eb483fa0c654bcb954df3f6ad3` |
| `ballooon popping button.png` | `65e491066d3348a94827caa448140bf865acaed6175cea71856ab88e5764ac47` |
| `bg1.png` | `732c72f144f6c87f2c852467e28cc7e592030b307c0c6ed731871c51c8178cdb` |
| `catch the word button.png` | `c885fdc182a0a20dbb540aee21b0035d679a9341fffda708f4b120a768bc5d26` |
| `catch the word.png` | `e6e192eee7a03602633158753e0661e7f35906c0fa029bee009915b309deb097` |
| `choose an activity.png` | `5efce5bc36b0e2b9e10c5bdff2004ee49f4e4f0d7617de1a07b5620c3bef76c8` |
| `header1.png` | `140b0cfa8696b9656441c1ce51b5989074161f9d3eb8f7f288c38bb3972d9d6a` |
| `human plane button.png` | `331f8fe496683211c8e944b4046e8498188d4e6acc842a7bd66ddaafdfbadbd3` |
| `human plane.png` | `4cc53711768ac3fcda1577d7cb03eefc01349ab7e2c441dbbcb5169628feb0f0` |
| `next student setup if already choose.png` | `fe13dc0d6b1fafd6c5683c8e84446c24b17da6540edc75b64a2975bafcea80c7` |
| `next student setup.png` | `82e528378c9c3f07c38a5bcb118a1abbeb021e1e5f620d316493cda639b9b6e4` |
| `select game default.png` | `c259e8059c305d898eb302e57c95f5c1679f041b77c1af97d9c77e5e4452f0fb` |
