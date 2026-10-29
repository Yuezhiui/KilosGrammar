# Solo student camera confidence flicker — offline regression

## User-visible defect

A child remains within view of the webcam, and the camera still sees exactly one
person, but YOLO's short pose-confidence dips repeatedly toggle the visible
PAUSE/PLAY state. Leaving/reentering the webcam appears to restore operation.
This is distinct from a real empty camera (0 people), a crowd (2+ people), or a
stopped camera process.

## Reproduce safely

From the KILOS GRAMMAR repository, run:

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_solo_pose_pause_oscillation_qa.gd
```

This initially reproduced the bug, and now passes after the confidence-drop
fix. It instantiates the actual `ui/play/gameplay.tscn` for each of Catch the
Word, Balloon Popping, and Human Plane, plus the actual calibration scene.
PoseService is the real autoload, but its packet fields are supplied by a
synthetic test; no physical webcam, Python worker, PostgreSQL or score writes.

The deterministic gameplay trace has 84 renderer ticks at 60 Hz, a moving solo
person with a pose update near 20 Hz, and 6 one-frame confidence dips. During
each dip `people=1` and `camera=true` still report a solo camera population,
but the pose packet has `pose=false`. The script counts transitions of the
gameplay wrapper's `tracking_suspended` state and its minigame process mode.
The calibration trace has 22 camera observations with 3 isolated dips; it
counts surviving fresh samples in the current held stage.

### First observed result — 2026-10-28

* **Catch:** 12 PAUSE/PLAY flips, 3 retained calibration observations.
* **Balloon:** 12 PAUSE/PLAY flips, 3 retained calibration observations.
* **Human Plane:** 12 PAUSE/PLAY flips, 3 retained calibration observations.
* First run: **39 assertions / 6 failures**, exit 1, no Godot script parse errors.
* All immediate 0 / 2 / 3-person safety pauses, fresh solo recovery, and
  synthetic >5-second missing-student state retention checks passed.

The error messages identify each failure. 250ms with no new inference packet
is separately checked to distinguish a low camera FPS from a failed pose.
The test also confirms that zero/multiple people still cancel calibration
holds, rather than treating unsafe occupancy as transient confidence noise.

## Confirmed causes and integrated fixes

* `ui/play/gameplay.gd`: a brief confidence-only dropout with `people=1`
  previously flipped `tracking_suspended` every time. The fix **immediately
  disables minigame processing and clears gestures** while the pose is invalid,
  but defers the visible solo-only suspension state for 0.35 seconds. Invalid
  control never updates timer, lives, score or movement. A zero/multiple/unknown
  population still suspends immediately.
* `ui/vision/calibration.gd`: `_process()` and
  `_process_stationary_plane()` previously erased all hold samples on a single
  bad pose frame. Now a strictly fresh, exactly-one-person temporary confidence
  loss (at most 0.35s, packet no older than 250ms) can preserve previously
  measured hold samples **without recording any invalid samples or crediting
  the invalid seconds**. Zero/multiple/stale/lost camera resets immediately.
* `ui/vision/pose_service.gd`: `has_valid_pose()` requires `pose=true`, state
  `tracking`, exact solo occupancy, and a fresh frame. This strict gate remains.
  Body/gesture source ages now include already-elapsed camera/inference latency
  so slow source packets cannot receive a second stale-data grace period.
* `ui/vision/student_lock.py`: a solo moving more than 0.24 normalized units
  between YOLO packets or one low-confidence torso frame previously triggered
  an unnecessary 0.65s/4-frame reenrollment. A previously confirmed sole
  occupant can now move normally, and a brief unusable torso frame invalidates
  **that frame's control only**, not the prior hold. Genuine 0/2+ or prolonged
  bad pose still requires fresh steady reenrollment.
* `ui/vision/pose_worker.py`: genuinely observed same-side shoulder+hip pairs
  can provide torso X when the far-side landmarks are obscured, with no invented
  joints. The raw-webcam fallback no longer blanks valid pose overlay after a
  mere 0.6s JPEG gap; it remains bounded below the 1.4s preview-age budget.

### After the local fix — 2026-10-28

* **Catch / Balloon / Human Plane:** 0 fast PAUSE/PLAY transitions each.
* **Calibration:** 19 of 22 real solo samples remain after three brief dips in
  each activity (three invalid observations are *not* accepted).
* **`tools/test_solo_pose_pause_oscillation_qa.gd`: 72/72 PASS**, no failed
  assertions, including explicit checks that rejected pose packets never
  advance the round's physics or the current calibration hold. Source age
  and occupancy checks live separately in
  `tools/test_pose_solo_pause_oscillation_stress.gd` (209/209 PASS).
* **Python:** `python -m unittest discover -s ui/vision -p 'test_*.py' -q`
  includes `test_solo_motion_dropout_stress.py` for single moving person,
  intermittent confidence dips, prolonged failure, crowd/empty safety and
  same-side anatomical pairs. Latest complete run: **126 tests passed (one
  optional skipped)**.

## Acceptance contract and remaining hardware test

Keep all game **movement**, scoring and shooting disabled when no fresh valid
pose exists; never keep steering using stale bones. Preserve immediate freeze
for genuine 0 people or 2+ people, unknown/stalled camera, and out-of-date
source frames. Distinguish `people=1` with a brief pose-confidence dip from
these occupancy changes so the paused/play indicator and calibration hold
aren't repeatedly reset by one bad inference. An appropriate bounded
confidence-only grace is bounded as above; the real Windows webcam is still
needed to verify detection behavior in the classroom. A new round recalibrates
once, while returning after >5s absence resumes the existing round after a
fresh solo re-enrollment, never a repeat physical calibration. No live database
or student frame data is touched by synthetic QA. No editor-authored `.tscn`
geometry was changed to work around camera-state oscillation.
