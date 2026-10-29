# Calibration grouped-editor regression QA

**Run** (Godot 4.7.2, from the KILOS GRAMMAR repository root):

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_calibration_grouped_editor_qa.gd
```

**Current result:** `GROUPED_CALIBRATION_EDITOR_QA PASS checks=2069 failures=0`.

This new test verifies the actual `ui/vision/calibration.tscn` and production controller, with no webcam, Python worker, database, or Git actions. Its isolated localhost UDP fixture submits monotonic, session-token-authenticated, source-fresh observations through **PoseService's real packet receiver and safety gates**. These packets are synthetic test observations, not claims of real YOLO inference, and production source validation is never disabled.

## Editor-authoring contract

- All 16 retired names are absent throughout the scene: `PlaneSteeringFootnote`, `PlaneSteeringTitle`, `InstructionLabel`, `BadgeLabel`, `PlayerLabel`, `StatusCapsule`, `PlaneStepBadge`, `CenterOnlyLabel`, `ArtStars`, `Heading`, `StageHeading`, `InstructionFIL`, `Description`, `StepBadgeBackground`, `StepBadge`, and `CountdownLabel`.
- `TutorialStage/CameraArea` retains `CameraFrame`, `CameraBlackBacking`, `LiveCameraInset`, `SkeletonPlacement`, and `ArtCameraFrame`.
- `TutorialStage/PoseGuides` retains **nine** independently editor-movable `TextureRect` pose references for Catch, Balloon, and Plane, using exactly **five** original PNG source files. It tests preservation of original positions, sizes, scales, rotations, texture identities and SHA-256 bytes during the whole stage sequence.
- `TutorialStage/Directions` retains three titles, three directional arrows, three step artworks, and three move hints; `TutorialStage/CountdownArtwork` retains `ArtCountdown1/2/3`.
- `TutorialStage/CameraFeedback` retains the camera unavailable, camera status, and progress labels; `TutorialStage/Navigation` retains the Back button and its decorative artwork. `TutorialStage/IntroOverlay` remains a direct child.
- Regrouping adds identity-transform `Control` parents, without changing stage-relative authored coordinates. The regression remembers the original 1280×720 design positions of all nine pose references, the camera and skeleton, three titles, three arrows, three countdown images, and Back.

## Routing and physical calibration contract

The intro is title-only for precisely 3 seconds; before it ends, no pose artwork leaks. Catch requires three distinct center/right/left 3-second holds, Balloon requires default + raised-hand 3-second holds at each zone (six total), and Human Plane requires one 3-second center T-pose with no fabricated side measurements. Fresh source frames count toward holds; no person or multiple people (`people=0` or `people=2`) cannot progress. The completed result requests the shared gameplay route, keeps the Play/Tutorial source and tutorial flag, preserves camera-only controls and countdown, and never enables keyboard fallback. A separate fresh scene verifies that the regrouped Back button returns to Choose Activity.

## Legacy-test relocation notes

After the grouped scene migration, four explicitly assigned existing regression suites have also been updated to use their correct grouped scene paths and current live artwork (without restoring retired controls or weakening PoseService source freshness):

| Existing regression | Post-migration result |
| --- | --- |
| `test_calibration_five_pose_png_sequences.gd` | **PASS 193/193** |
| `test_calibration_three_second_sequence.gd` | **PASS 536/536** |
| `test_calibration_settings_prune_resilience.gd` | **PASS 1037/1037** |
| `test_calibration_scene_cleanup_qa.gd` | **PASS 100/100** |

The grouped-editor integration suite remains **PASS 2069/2069**. The unchanged `test_calibration_single_person_round.gd` separately passed 79 checks. Other still-unmigrated tests (including `test_retry_cached_skeleton_intro_qa.gd` and `test_auto_camera_route.gd`) may retain direct `TutorialStage/<old-child>` lookups; their owners should migrate those tests separately.

The new focused test was authored during concurrent scene edits; the scene was already regrouped when the test first ran, so a reliable pre-implementation RED result was not captured. An initial false failure was corrected to account for the left arrow's intentional negative horizontal scale and pivot; this regression compares **authored offsets** rather than the mirrored transform origin.
