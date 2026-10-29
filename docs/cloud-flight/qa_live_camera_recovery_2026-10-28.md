# Live webcam recovery acceptance — October 28, 2026

This checklist is for **physical classroom acceptance** only. Headless synthetic
tests validate software state transitions, not the installed Windows camera,
actual YOLO frame rate, room lighting, or the offline installer.

## Current classroom contract (supersedes earlier tracker-ID requirement)

- A round measures physical positions **once**; there is no registered YOLO
  tracker identity attached to those position measurements. The registration
  ID used for the school's Play score records is a separate student field;
  this change does not disable Play student registration or score persistence.
- A camera observation containing **zero** or **two or more** people pauses
  the entire minigame (timer, scoring, movement), including when one of the
  people was previously visible. Skeletons for all detected people may remain
  visible as passive visual feedback, but nobody controls the game.
- After any duration off camera (2, 5, 15, 60 seconds), **one** detected person
  with new, stable, genuine solo YOLO frames may resume the **same round** and
  previous score, time, lives and calibration, regardless of changing ByteTrack
  IDs. Never use stale packets, old skeletons or a previous body position.
- A camera-worker restart should pause until a new real solo pose arrives. It
  must not route to repeat calibration in the same unfinished round.
- Catch the Word and Balloon Popping calibrate CENTER → RIGHT → LEFT; Human
  Plane retains one neutral CENTER hold (2.5s, eight distinct source frames).
- Every teacher-requested NEW round/retry starts with its own calibration.
- Tutorial never registers or saves scores. Play saves only completed rounds;
  pausing, abandoning or recovering a round must never save phantom records.
- **Tradeoff agreed by user:** the app no longer confirms the person's
  identity after a break. If a different child becomes the only person in
  frame, they can control the remaining round after the stable solo hold.

## Manual classroom matrix (Play **and** Tutorial)

1. Solo child: finish calibration, 3-2-1, steer left and right, verify that
   score, lives and timer work during valid tracking.
2. Step outside for 2, 5–8, 15 and 60 seconds, return to camera as exactly
   one person. The timer/lives/score must stay still while absent; the old
   round should resume as soon as fresh stable solo tracking is confirmed.
3. While a round is running, let one classmate step into view. All movement,
   scoring and timer progression should pause at the **two-person** frame.
   Show both skeletons if YOLO observes two people. Have the classmate leave;
   after a stable one-person hold, resume the original round with no recalibration.
4. Repeat with three people; verify all are passive and the round pauses.
5. Return to frame with a different ByteTrack numeric ID and with a recycled
   numeric ID, both with and without a camera worker restart. Neither changes
   the calibrated positions or navigates to the calibration screen.
6. Cross two people or obscure shoulders/wrists; verify ambiguous poses freeze
   input immediately and the first frame after separation is not reused.
7. Return under both bright and dim classroom lighting. Verify real skeleton
   freshness; the offline bright/dim simulation does **not** prove lighting.
8. Repeat three consecutive Catch rounds, then Balloon and Human Plane; use
   the required activity-specific calibration and no legacy 3D plane assets.
9. Simulate a camera-driver interruption or unplug/replug **only under teacher
   supervision**. It must either reconnect and resume with one fresh solo
   student pose without recalibration, or show an actionable driver error.
10. Verify that the wooden Catch score number is centered inside the dark
    recess and does not extend past the sign's bottom edge in both entries.
11. For completed **Play** rounds, reopen Leaderboard and verify results
    persist. For **Tutorial**, verify no persistent results were added.

Capture the Godot console's camera-state messages, a screenshot of the last
visible skeleton/score, whether the same or a different physical student
returned, and which activity/mode was active if any case fails. Do not share
student IDs or personal information in bug reports.

## Automated tests (no webcam / database)

- `tools/test_shared_camera_lock_occlusion_stress.gd`
- `tools/test_play_vs_tutorial_live_countdown_movement.gd`
- `tools/test_camera_only_tracking_recovery.gd`
- `ui/vision/test_long_absence_reacquisition.py`

All automated coverage should be run with a matching Godot 4.7.2 build and
logs scanned for `SCRIPT ERROR` / `ERROR` even when Godot exits with status 0.
