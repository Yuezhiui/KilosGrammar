# Calibration pose guides — current editor workflow and archived layout

## Current editable guides (October 28, 2026)

Open `ui/vision/calibration.tscn` in Godot and expand `TutorialStage`.

The active artwork is now organized in six independently selectable **Control**
groups instead of a long flat list beneath TutorialStage:

| Control path under `TutorialStage` | What you can edit |
| --- | --- |
| `CameraArea` | `LiveCameraInset`, its frame/backing, and `SkeletonPlacement` (real YOLO bone drawing) |
| `PoseGuides` | The nine independent default, Balloon and Plane pose PNG TextureRects |
| `Directions` | `ArtTitle*`, `ArtArrow*`, `ArtStep*`, and `ArtMoveHint*` artwork |
| `CountdownArtwork` | The three `ArtCountdown1/2/3` visual digits |
| `CameraFeedback` | The camera unavailable/feedback indicators |
| `Navigation` | `BackButton` and `BackButton/Artwork` |

`IntroOverlay` stays directly below `TutorialStage`; moving it under another
group would alter the isolated three-second intro. Every group is an editor-
authored full-canvas zero-offset Control, while each artwork child keeps its
previous position, size and transform. The user-requested obsolete 16 labels,
panels and duplicate badges have been deleted from the scene and corresponding
script bindings; they are not merely hidden. **Play and Tutorial share this
same Calibration scene** and retain their distinct score-saving rules.

- `PoseGuideDefault` — **CENTER** for Catch/default Balloon pose.
- `PoseGuideRight` — **RIGHT**, independent duplicate of `PoseGuideDefault`.
- `PoseGuideLeft` — **LEFT**, independent duplicate of `PoseGuideDefault`.
- `PoseGuideBalloonRaise`, `PoseGuideBalloonRaiseRight`, and
  `PoseGuideBalloonRaiseLeft` — separate raised-hand art for each Balloon zone.
- `PoseGuidePlaneCenter`, `PoseGuidePlaneLeft`, and `PoseGuidePlaneRight` —
  **separate Human Plane poses**, not copies of the default standing artwork.

`PosePlacementLeft`, `PosePlacementCenter`, and `PosePlacementRight` have been
**removed at the user's request**. The script never overwrites a guide's X,
Y, size, or scale; it only changes which existing TextureRect is visible.
Drag or resize any of these guides in the Godot 2D editor, save the scene,
and the authored changes will be respected in every calibration stage.
`SkeletonPlacement` is **different**: it controls real YOLO bone alignment
against `LiveCameraInset`, so leave it alone when moving the decorative PNGs.

## Historical pre-migration layout (do not recreate)

> **October 28, 2026 — historical document only.** The five-pose PNG update
> replaced `ArtGuideLeft`, `ArtGuideCenter`, `ArtGuideRight` and the three
> `*CalibrationLane` panels. Those scene nodes, their unused style resources,
> and the retired `Components/Gameplay/Calibration/PARAMETERS.png` asset are
> now removed. **Do not recreate these neon/legacy nodes** from the old
> measurements below. Edit `TutorialStage/PoseGuides/PoseGuideDefault`,
> `PoseGuideBalloonRaise`, `PoseGuidePlaneCenter`, `PoseGuidePlaneLeft`, and
> `PoseGuidePlaneRight` within that group instead. See
> `tools/FIVE_POSE_PNG_CALIBRATION_QA.md` for the current mode-specific holds.

The following records the obsolete pre-migration layout for history only.

This is a **UI/artwork-only** revision. Human Plane remains an airplane and its
existing pose-calibration logic is unchanged; the possible car redesign is
deferred. The normal CENTER → RIGHT → LEFT calibration stays intact for
Catch the Word and Balloon Popping.

Open `ui/vision/calibration.tscn` in the Godot **2D** editor. All positions
below are **native coordinates on the 1280 × 720 design canvas**. Select a
node in **TutorialStage**, then change **Inspector → Layout → Transform →
Position / Size**, or drag its 2D handles. There is no runtime hardcoded
repositioning of these decorative elements.

| Node under TutorialStage | Position (X, Y) | Size (W, H) | Function |
|---|---|---|---|
| `CenterCalibrationLane` | (501, 186) | (278, 353) | Legacy reference only, permanently hidden; NOT the displayed standing square |
| `LeftCalibrationLane` | (204, 192) | (275, 345) | Legacy reference only, permanently hidden |
| `RightCalibrationLane` | (800, 192) | (275, 345) | Legacy reference only, permanently hidden |
| `ArtGuideCenter` | (490, 34) | (332, 685) | Updated `PARAMETERS.png` glowing center square |
| `ArtGuideLeft` | (122, 34) | (332, 685) | Independently adjustable LEFT `PARAMETERS.png` |
| `ArtGuideRight` | (836, 34) | (332, 685) | Independently adjustable RIGHT `PARAMETERS.png` |
| `SkeletonPlacement` | (141, 147) | (1007, 446) | Green YOLO skeleton **drawing** rectangle |
| `LiveCameraInset` | (141, 147) | (1007, 446) | Actual camera preview rectangle |
| `ArtTitleCenter/Right/Left` | (320, 12) | (640, 148) | Three updated full-width directional title PNGs |
| `ArtCountdown1/2/3` | (1035, 12) | (228, 172) | Art 3/2/1 without offscreen controls |
| `ArtCameraFrame` | (70, 19) | (1150, 700) | Wooden `BORDER.png`, positioned so **visible ink** stays on-screen |
| `BackButton` | (47, 622) | (255, 85) | New local `BACK.png`; returns to Choose Activity |

The center `PARAMETERS.png` square is visible by default **in the editor**
for easy selection. LEFT and RIGHT are initially hidden to avoid three
overlapping artworks; temporarily toggle each node's **Visible** checkbox
to edit it, then hide it again. Runtime shows **only the current step's**
square. The older green standing panels and their CENTER/STOP HERE captions
are now **intentionally hidden both in the editor and at runtime**. Those
duplicate overlays caused the yellow guide to display with a green box and
extra text after the previous revision. Resize only the yellow
`ArtGuideCenter/Left/Right` nodes for the intended visible square. The
hidden reference rectangles remain serialized so existing scene references
still load, but the camera calibration logic never relies on their visuals.

The three updated `STAY ... .png` titles are **1672 × 432** and load directly:
the obsolete AtlasTexture crop coordinates used with the old taller files
were cutting the words off. The STEP art retains its separately trimmed
AtlasTextures because those three source PNGs still have transparent padding.
All updated source PNG bytes are kept intact.

Both Intro and active calibration Back use
`Components/Gameplay/Calibration/BACK.png`, not the older Game Chooser back.
Their native Button click and keyboard activation remain available, but the
yellow focus style is a `StyleBoxEmpty`, so the artwork never gains extra
colored corner boxes. Similarly, the three Activity Chooser buttons use
`StyleBoxEmpty` focus styles rather than the purple/blue focus outline;
their original PNG tint and right-hand preview still show selection.

**Important:** `SkeletonPlacement` scales/offsets only where YOLO joints
are **drawn** relative to the camera preview. It is not a movement-calibration
threshold. Keep its bounds aligned with `LiveCameraInset` unless you are
deliberately changing skeleton visualization. The artwork guides and green
standing-box rectangles do not modify the underlying camera pixels.
