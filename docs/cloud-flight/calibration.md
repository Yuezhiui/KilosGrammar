# Human Plane — one neutral hand-pose calibration

**Current UX:** a student stands alone and still in the webcam view, keeps their shoulders and **both wrists visible**, and holds one comfortable neutral hand position for **2.5 seconds with at least eight distinct valid pose detections**. The regular 2.5-second introduction still appears before the neutral hold; after it passes, the existing two-second handoff launches Human Plane automatically. There are **no separate right/left calibration poses**, floor position changes, fully extended T-poses, buttons to continue or mobile gyroscopes.

The camera remains behind existing explicit camera-game selection; starting model prewarm alone does not open it. Source webcam frames stay in the local worker/preview pipeline. Nothing is saved to a database, uploaded or recorded by calibration.

## What the student does

1. Stand naturally near the camera center with feet planted; display both wrists and shoulders.
2. Relax both hands at any comfortable height (wrists can be below shoulders) and hold that single position steadily while the three-second countdown graphic displays. The actual hold is 2.5 seconds and eight different worker measurements.
3. The screen automatically advances after successful neutral calibration and the existing two-second handoff. While flying, gently bank the wrists or shift the shoulders a little: right-side banking steers right and left-side banking steers left. No wide-arm flight permission gate.

The live-calibration title and note are editor-authored as `PlaneSteeringTitle` and `PlaneSteeringFootnote` in `ui/vision/calibration.tscn`. The centered camera guide stays in place. The native `PlaneStepBadge` says **ONE POSE**. Contradictory right/left floor arrows, text/art and previous STEP 1/3 images are hidden only in Human Plane. Other games retain their own 3-stage artwork, bilingual prompts, and exact CENTER→RIGHT→LEFT **floor-location** holds.

## Worker packet and sensor signal

`ui/vision/pose_worker.py` calculates `plane_steering` from actual mirrored-camera-normalized shoulder, wrist and (when available) hip joints of **one StudentLock-selected student**. Positive is screen right, negative screen left. The signal uses measured wrist-height difference and shoulder tilt, with extra torso lean from visible hips. Distances are normalized to body proportions so webcam distance does not require manual range tuning. Hips may be cropped if both wrists and shoulders are confidently visible.

The worker sends:

* `plane_steering`: real signed [-1,+1] shoulder/wrist signal, not absolute body camera X.
* `plane_steering_valid`: current trusted locked-student motion signal is sufficiently observed. During gameplay, if one wrist becomes temporarily occluded, the other wrist plus real shoulder/hip lean may still steer; an unavailable or indeterminate bank closes the gate.
* `plane_neutral_valid`: both shoulders **and both wrists** were confidently visible for enrollment. Only frames with this additional evidence count toward the one-hold neutral calibration.
* `locked_id` and `lock_state`: existing on-camera temporary tracking IDs, never biometrics.

Only camera packets with the active session token and a strictly increasing worker `when` timestamp reach the bounded pose sample history. PoseService rejects duplicate/reordered timestamps even when recording directly. Invalid/bystander/lost packets do not contribute samples. Eight source frames cannot be manufactured by 60 Hz rendering. The neutral hold resets on pose loss, >0.7-second source gaps (adaptive for low detector FPS), excessive wrist variation or large movement around the initial camera location. A changed locked ID discards the unfinished baseline.

## Public Godot API

```gdscript
PoseService.set_stationary_plane_calibration(
    neutral, locked_track_id, camera_center_x, neutral_noise
) -> bool
PoseService.has_stationary_plane_pose() -> bool
PoseService.normalized_plane_steering() -> float
PoseService.plane_calibration: Dictionary
```

`plane_calibration` holds a **measured neutral `center`**, camera center X, locked ID, median absolute deviation noise, calibrated symmetric `sensitivity` and `deadzone`, and `valid=true`, `mode="plane_stationary"`, `neutral_only=true`. It deliberately has **no measured left/right** values. The neutral baseline uses the median of the eight or more observed raw steering frames, and the jitter uses the median absolute deviation. Sensitivity automatically increases with observed jitter to avoid a shaky neutral pose sending the plane to an edge:

```text
deadzone    = clamp(2.5 × neutral_noise + 0.012, 0.014, 0.055)
sensitivity = clamp(3.5 × neutral_noise + 0.16,  0.16,  0.30)
steering    = sign(raw-neutral) ×
              clamp((abs(raw-neutral)-deadzone)/(sensitivity-deadzone), 0, 1)
```

This yields the full [-1,+1] horizontal range from a small, safe wrist or shoulder bank of either sign, without requiring separate maximum-left/maximum-right poses. PoseService adds no additional steering animation filter; the Godot gameplay wrapper and minigame animate toward the freshest target at render FPS even when camera inference runs more slowly. The permission gate closes on missing/ambiguous/changed student, invalid steering observation or packets **older than 650 ms**, freezing current flight control. The packet and track lock use the original existing behavior; no synthetic webcam packets in production.

Existing `PoseService.calibration.valid` stays true for compatibility with the shared game wrapper, with the new mode explicitly marking the differently measured steering. The Human Plane route passes `calibration_center` (actual neutral), `calibration_steering_sensitivity`, `calibration_steering_deadzone`, `calibration_camera_center_x`, `calibration_neutral_only=true` and `plane_steering_mode="neutral_wrist_shoulder"`. It **does not pass fake `calibration_left/right`**. Catch the Word and Balloon Popping still call their original `set_calibration(left, center, right)` and `normalized_body_x()`.

## Offline regression

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_human_plane_stationary_calibration.gd
py -3.11 -m unittest ui.vision.test_stationary_plane_steering ui.vision.test_gesture_detector ui.vision.test_airplane_wing_roll
```

The Godot regression loads the real scene but injects isolated synthetic *test* pose observations into an offline PoseService with no webcam. It checks one neutral hold, eight-source-packet minimum, duplicate timestamps, same-camera-X motion, left/right gain symmetry, dead zone, missing wrists, changed ID, stale packets, routing payload, and both other games' intact physical three-zone calibration. Python checks real skeletal joint geometry and optional one-wrist gameplay continuity. These tests do not invoke YOLO, use the camera or write a database.

The user's Pauline reference link could not be inspected conclusively. This implementation follows the requested single-stand-still concept, without claiming to copy a particular video frame or proprietary implementation.
