# Calibration screen — pixel-safe artwork and guide placement

**Date:** October 26, 2026
**Scope:** `ui/vision/calibration.tscn` editor-authored transforms, and optional GPU capture / sizing assertions in `tools/test_calibration_assets_layering.gd`. No calibration logic, pose service, YOLO worker, camera, database, source PNGs, imports, font, shader, or runtime placement changes.

## Original fault, confirmed in real GPU captures

An isolated Godot 4.7.2 regression, running without camera consent or student data, produced **16 failures out of 540 assertions** at 1280×720 and 1920×1080. The scene's fixed 1280×720 `TutorialStage` correctly scales to 1920×1080; its nested images had authored coordinates partly beyond that canvas:

| Asset group | Before, authored 1280×720 layout | Impact |
| --- | --- | --- |
| `ArtCountdownBadge`, `ArtCountdown1`, `ArtCountdown2`, `ArtCountdown3` | Bounds `x=1075..1303`, `y=-21..151` | The *actual opaque portions* of `1.png`, `2.png`, `3.png` extended to y ≈ −14..−20 (scaled to approximately −21..−30 at 1920×1080), so the top of the wooden circular timer decoration was cropped. Badge uses the existing original alpha-mask shader. |
| `ArtCameraFrame` | Bounds `x=69..1219`, `y=45..745` | The `BORDER.png` composited alpha footprint extended down to y ≈ 730.8. In screenshots the visible frame was largely intact; approximately 11 px of lower decorative fringe / drop-shadow bleeds past the screen edge. That bleed *could* have been an intentional overscan rather than a broken essential frame element, but did not meet the strict no-visible-pixel clipping criterion. |
| `ArtGuideCenter`, `ArtGuideRight`, `ArtGuideLeft` | Each image `y=60..745`, width=332, height=685 | The original guides were still recognizable, but their editable **Control** rectangles extended 25 px beyond the bottom of the screen. The bright standing guide was slightly too low relative to the camera window. |

The original 1280×720 CENTER and 1920×1080 RIGHT GPU captures were inspected before changes. Art ordering, step title, status text, original black camera area and back button were already otherwise functional. There was no justification to resize or re-render supplied art.

## Minimal scene-only adjustment

| Nodes | Authored transform adjustment | Dimensions and textures |
| --- | --- | --- |
| All four countdown assets | Move **down 24 px**: `top -21→3`, `bottom 151→175` | Original 228×172 rectangles preserved. Top wood badge and highlights are now onscreen. |
| `ArtCameraFrame` | Move **up 12 px**: `top 45→33`, `bottom 745→733` | Original 1150×700 rectangle preserved. The soft lower fringe now fits. |
| All three `ArtGuide*` overlays | Move **up 26 px**: `top 60→34`, `bottom 745→719` | Original 332×685 rectangles preserved. Yellow dashed guide and corners remain fully visible and better centered in the existing black camera area. |

All node parents, IDs, layering order, view anchors, step titles, instructions, resource paths, shader overrides, camera inset and `SkeletonPlacement` were retained exactly. The existing `calibration.gd` continues to choose the active CENTER/RIGHT/LEFT image and update the countdown; these edits introduce **no hardcoded runtime UI coordinates**. All supplied `Components/Gameplay/Calibration/*.png` files stay byte-for-byte unchanged.

The countdown margin and the lower wood border were not intentionally cropped in the new layout; they are now completely on screen. The original lower BORDER fringe appeared decorative, not essential functionality. The adjustment preserves its visual geometry instead of stretching it or changing the source image. This is a visual placement fix, not a change to any pose detection, calibration sensitivity, timer, or camera startup behavior.

## Verification

| Run | Outcome |
| --- | --- |
| Baseline HEADLESS test before changes | **FAIL — 16 / 540 assertions** |
| Headless same test immediately after position corrections | **PASS — 540 / 540** |
| Final HEADLESS test with eight new geometry-preservation checks per resolution | **PASS — 556 / 556** |
| Final GPU graphical test on RTX 3050 / OpenGL 3.3 with `--capture` | **PASS — 564 / 564**; eight screenshots (intro, center, right, left at both resolutions) |
| Existing calibration fullscreen editor layout | **PASS — 737 / 737** across three viewport sizes |
| Existing camera full-frame framing | **PASS — 37 / 37** for 4:3 and 16:9 source frames |
| Existing three-position calibration sequence | **PASS — 223 / 223** |
| Existing single guide lifecycle | **PASS** |

From the Godot project root:

```powershell
$godot = 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --script res://tools/test_calibration_assets_layering.gd
& $godot --path . --rendering-method gl_compatibility --script res://tools/test_calibration_assets_layering.gd -- --capture
```

The optional `--capture` mode is not part of the game and has no UI code. It saves the **actual GPU framebuffer** into the Godot `user://` directory, including:

```text
_qa_calibration_layout_1280x720_intro.png
_qa_calibration_layout_1280x720_center.png
_qa_calibration_layout_1280x720_right.png
_qa_calibration_layout_1280x720_left.png
_qa_calibration_layout_1920x1080_intro.png
_qa_calibration_layout_1920x1080_center.png
_qa_calibration_layout_1920x1080_right.png
_qa_calibration_layout_1920x1080_left.png
```

On the QA machine these live under `C:\Users\Yue\AppData\Roaming\Godot\app_userdata\KilosGrammar\`. Comparative CENTER (1280) and RIGHT (1920) framebuffer images were visually inspected before and after; background, header, active yellow guide and game UI remain legible, with repaired safe-area margins. The artwork and `LiveCameraInset` are still editor-draggable independently.

**Testing limitation:** These screenshots deliberately show the camera-unavailable placeholder to guarantee no webcam use. They prove scene bounds, original assets and static layering, not pose detection with a live student; the Python worker, database and physical camera were never touched.
