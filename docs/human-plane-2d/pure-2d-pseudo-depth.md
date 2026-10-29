# Human Plane — restored pure 2D pseudo-3D gameplay

## Single editable gameplay scene

The playable Human Plane uses **one** editor-authored scene:
`ui/minigames/human_plane.tscn`, driven by `human_plane.gd`. The previously
instanced `WorldView3D` and its runtime dependency have been removed from this
gameplay scene. The old authored 3D view, imported models, sky materials and
cloud sources remain on disk unchanged; this implementation neither loads
nor mutates them.

The source `C:\Users\Yue\Downloads\PLANE\BACKGROUND.png` was copied
byte-for-byte to `res://Components/Gameplay/Human Plane/BACKGROUND.png`
(1672×941) and is rendered by the editor-selectable full-rect
`FlightBackground` TextureRect. It fills the screen behind all movement,
gate artwork and the existing Catch-style CanvasLayer HUD.

All three original **arc** gate PNGs are still used: purple LEFT, green CENTER,
blue RIGHT. The original `PLANE.png` remains in the fixed lower `PlaneRig`
with gentle decorative banking/bobbing that does not move its hitbox.
The six active/upcoming arc `GateArtwork` TextureRects and their word labels
are draggable/editable directly in this scene. Older ColorRect pillars,
rectangle top bars and interior elements remain `visible=false`; these
legacy guides are not drawn. Existing HUD plaques, buttons, positions, labels
and textures were not edited.

## Lou-style pseudo perspective

The gate projection now follows a simple inverse-depth focal-length model:

```text
depth(p) = lerp(farDepth, nearDepth, clamp(p, 0, 1))
q(p) = focalLength / (focalLength + depth(p))
t(p) = (q(p) - q(0)) / (q(1) - q(0))
visibleRect(p) = lerp(authored GateStart, authored GateEnd, t(p))
```

Current constants are `focalLength=1.5`, `farDepth=4.5`,
`nearDepth=0.7`. This accelerates apparent gate growth near the aircraft,
while exactly respecting the edited Start/End position and dimensions.
The answer-line binary search, visible TextureRect bounds and collision
overlap all use this **same** projected rect, avoiding independent physics
or visual lag. The next wave uses the same arc projection with its slower
prefetch progress and a separate lower painter `z_index`.

The painter order is background (z=-10), prefetched gates (z=0), active gates
(z=1), red airplane (z=2), and original HUD CanvasLayer (layer 20).
No 3D rendering or additional per-frame texture/node allocation is needed.

## Gameplay rules unchanged

The calibrated, student-locked pose drives the original body-X smoothing.
The painted plane and authoritative hitbox use the exact same horizontal
coordinate. Straddling two gates without a sufficiently dominant geometric
overlap is a miss, not an arbitrary selection. A correct gate awards **+100**
points and adds a persistent **+14%** speed bonus; wrong and missed gates
deduct **0 points** (and consume one heart). No hidden 3D collision volume
or copied 3D scoring code exists.

Seconds uses 60 seconds, Lives has three hearts, and Pause freezes wave
progress, input movement and decoration until resumed.

## No-camera validation

- `tools/test_human_plane_2d_perspective.gd`: **96/96** headless assertions
  across 1280×720, 1600×900, 1920×1080; **102/102** with real NVIDIA OpenGL
  screenshot capture at near/far phases. Captures are saved exclusively to
  Godot `user://` and were visually inspected.
- `tools/test_human_plane_fixed_score_speed.gd`: **271/271**.
- `tools/test_human_plane_collision_boundary.gd`: **486/486**.
- `tools/test_human_plane_continuous_flight.gd`: **1212/1212** across two
  resolutions and both game modes.
- `tools/test_human_plane_assets_pose.gd`: **97/97**.
- `tools/test_human_plane_continuous_integration.gd`: **469/469**.

The preexisting Catch HUD exact-clone test differs from the currently
user-authored HUD at several positions/font sizes, which were **not changed**
by this 2D restoration. Older tests that require `WorldView3D` must be
retired or migrated by their owners: the missing 3D node is intentional,
not a renderer failure. During the editor scan `main_menu.gd` independently
reported unresolved method references and is outside this task's ownership.
