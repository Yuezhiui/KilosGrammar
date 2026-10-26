# KILOS GRAMMAR: intermittent CENTER / RIGHT / LEFT pose registration

**Date:** 2026-10-26. **Scope:** read-only diagnosis of
`ui/vision/calibration.gd`, `ui/vision/pose_service.gd`, the Python
`StudentLock`/offline pose worker, plus synthetic regression tests. No
production code, physical camera, student image, database, models or commits
were modified or opened by this QA worker.

## User-visible symptom and exact acceptance criteria

Calibration needs actual body motion in three stages, **CENTER → RIGHT → LEFT**.
At each position the student must remain stable for **at least 3.0 seconds**
*and* present **at least eight distinct live pose frames**; renderer refreshes
must **never** substitute for real inference. Each stage has independent
measurements and previously completed stages survive a temporary tracking
loss. The user reports that sometimes a movement appears to be unregistered.

Inspected 2026-10-26 pre-fix behavior, followed by the prime agent's
same-day production changes. Keep the two versions distinct:

| Gate | Current rule | Why an apparent movement can be rejected |
| --- | --- | --- |
| StudentLock initial enrollment | ≥1.2 s and ≥8 genuine inference frames, CENTER x∈[0.28,0.72], sufficient bounding box | At 2 FPS, initial identity lock alone needs ≥3.5 s after model/camera startup; cannot use 60 UI redraws |
| CENTER | **Old:** [0.34,0.66]; **new:** [0.32,0.68] | Wider centered standing box tolerates small tracking jitter; x=0.31 still rejected |
| RIGHT | **Old:** ≥max(0.68,center+0.12); **new:** ≥max(0.64,center+0.12) | For center=0.50, x=0.635 still rejected; x=0.641 accepted |
| LEFT | **Old:** ≤min(0.32,center−0.12); **new:** ≤min(0.36,center−0.12) | For center=0.50, x=0.361 rejected; x=0.359 accepted |
| Stationary body x | anchor drift ≤0.095 | RIGHT x=0.70 then 0.81 are *both in-zone* but movement is >0.095, so hold deliberately restarts |
| Packet continuity | **Old:** ≤0.7s. **New:** adaptive budget when worker reports 0<fps<5, using clamp(1.75/fps, 0.7, 1.45) | Honest 1.5Hz inference can finish a 3s/8-frame hold; a 1.3s stall still resets at reported 1.5Hz |
| Real frame criterion | live_samples.size()≥8; **new** bounded queue preserves individual source positions/timestamps | The earlier collapse of eight **source** frames to one **UI** sample is fixed without counting renderer redraws |
| PoseService freshness | max 1,750ms for body pose; gesture 650ms | Tracking failure produces invalid pose; calibration immediately resets the current hold |
| UI stage intro | 2.5s and no pose credit | Camera first appearance additionally waits YOLO model and StudentLock; intro countdown is not a calibration countdown |

These conservative thresholds are intentional protection against giving
calibration credit for motion, a bystander, or stale poses. They should not be
casually relaxed to make an unobserved student pass.

## Baseline deterministic reproduction: real pose packets lost at renderer boundary

Before the patch, the PoseService UDP loop drained up to 192 datagrams per
render frame, selects the *one* largest monotonically increasing `when`
timestamp, and then calls `_apply_pose_packet()` once. The public
`packet_sequence` advances by **1**, irrespective of how many independently
inferred student frames arrived before that UI render. Meanwhile
`calibration.gd` checks only `packet_sequence != last_packet_sequence` and
appends **one** value to `live_samples` per UI update. The result can be
fewer than eight accepted calibration samples even though the worker actually
produced eight genuine, separately timestamped poses within the hold.

The new `tools/test_calibration_sparse_pose_fps.gd` creates an isolated
local UDP receiver and sends **eight** same-session, same-student,
`state=tracking`, `lock_state=locked` datagrams with strictly increasing
`when` timestamps, then invokes one real PoseService render tick. This is a
realistic backlog burst (a frame stall, busy UI, or OS scheduling). Baseline
result before prime's fix:

```text
CALIBRATION UDP BURST SOURCE_FRAMES=8 ACCOUNTED_UNIQUE_POSES=1
CALIBRATION SPARSE POSE: FAIL (53 checks, 1 failures)
FAIL: All eight genuine distinct tracked person packets survive a single queued UDP burst
```

All other 52 baseline assertions passed, including delayed startup, 2.5 Hz real
inference with 60 Hz redraw, all three 3s holds, and the seven-vs-eight
distinct-frame boundary. **An eightfold `packet_sequence` increment alone
would not fix the underlying calibration hold**: its `live_samples` array
currently still accepts only one normalized x per UI tick. A correct pipeline
needs bounded, timestamped, genuinely unique locked-student pose samples that
are consumed once, while only the newest image/status is used for rendering.
Maintain freshness ordering, session token and original StudentLock safety.

## Other movement / timing outcomes reproduced safely

- Simulated first **7 s without a valid student pose** does not credit
  CENTER or begin a hidden hold. A subsequent **2.5 Hz**, x-jittered
  (<0.01) real source stream satisfies CENTER, RIGHT and LEFT in order,
  each after 3 s and at least eight separately advanced packets. No
  camera/device/worker was started.
- With 2 Hz stable source packets, 3 s elapsed and **seven** genuine pose
  frames still cannot complete CENTER. The **eighth** distinct frame does.
  60 FPS screen redraws of an unchanged packet do not earn extra credit.
- Before the patch, x≈0.675 on RIGHT lay below its 0.68 edge and canceled a hold.
  The new 0.64 boundary accepts x≈0.675. However,
  x≈0.70 to x≈0.81 is inside the same zone but breaches the separate 0.095
  stability limit. Both explain apparently ignored input without proving
  that the tracking data was dropped.
- Previous fixed 0.7 s packet-gap reset affected ~1.4 FPS inference (or a
  brief scheduler stall) even with a well-locked student. The new adaptive
  interval supports actual 1.5 FPS inference while a longer 1.3-second
  dropout still resets the hold instead of synthesizing time.
- PoseService also smooths body x over 110 ms. RIGHT/LEFT steps close to
  thresholds may take another genuine frame to enter the target zone,
  especially on slow inference, because the UI does not use raw x.
- Real Python `StudentLock` safely refuses to hand the student's track to
  a background person walking through the center. Recovery after an
  identity change requires the view to become empty and then a new solo
  CENTER enrollment; no bystander can complete the remaining stages using
  the prior student's pose.

## Repeatable no-camera tests

From the Godot workspace root, on Windows:

```powershell
$godot = 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --script res://tools/test_calibration_sparse_pose_fps.gd
& $godot --headless --path . --script res://tools/test_calibration_latency_retries.gd
& $godot --headless --path . --script res://tools/test_calibration_packet_latency.gd
& $godot --headless --path . --script res://tools/test_calibration_prewarm_bridge.gd
& 'C:\Espressif\tools\python\python.exe' -B -m unittest discover -s ui\vision -p test_calibration_sparse_pose.py -v
& 'C:\Espressif\tools\python\python.exe' -B -m unittest discover -s ui\vision -p test_student_lock.py -v
```

The five new Python calibration/identity scenarios PASS without any real
camera, network requests or YOLO weights. Existing Python StudentLock and
Godot retry, UDP, prewarm suites are independently rerunnable.

**Integration signoff criteria:** all 3×(3s + ≥8 actual unique poses) checks
remain true under 2–4 Hz inference and burst scheduling, old/out-of-order
timestamps and bystander positions do not count, packet gaps do not create
fake hold time, startup with 0 valid poses never progresses, and completed
zone measurements remain stable during recovery. Inspect any production
packet-buffer change carefully for memory bounds and reentrancy. Final
test results after prime's production patches are recorded below.

## Post-patch verification

The prime agent's production patch added a **bounded 96-entry**
`_recent_pose_samples` buffer in PoseService, independent increasing
`latest_pose_sample_id` IDs, `get_pose_samples_after(id)` for calibration,
strict source-time ordering/token checking, and retained latest-only UI
rendering. Calibration now evaluates **each genuine buffered x value** for
the correct zone and anchor stability, including when many frames arrive
between UI ticks. A fresh sample cannot be reused after zone reset.
The prime agent also widened the standing zones and made the packet gap
adaptive for genuinely low inference FPS; the 3.0s + eight-distinct-frame
requirement is unchanged.

The updated strict Godot test `tools/test_calibration_sparse_pose_fps.gd`
reports **PASS (91 checks, zero failures)**. It verifies:

- Eight authenticated, strictly increasing timestamps produce **eight** real
  retained student positions and eight source packet-sequence increments,
  despite rendering only the latest pose once; screen adds eight samples but
  does not finish until 3 real seconds have elapsed.
- Duplicate/out-of-order worker timestamps, previous session tokens, and
  `pose=false` ambiguous/bystander reports cannot add calibration samples.
- A single burst moving the real student from CENTER to RIGHT does **not**
  sneak through as a fake stationary eight-frame CENTER hold: per-sample
  zone/stability checks reject mixed positions.
- 2.5Hz honest inference with 60Hz UI redraws finishes all three stages,
  2Hz needs the eighth actual frame after a full 3s, and 1.5Hz finishes
  with the adaptive timing budget. A long 1.3s pause still resets the hold.
- Seven-second delayed worker startup, updated center/right/left boundaries,
  actual left/center/right normalized Human Plane steering, and no stale ghost
  movement.
- A 96-entry FIFO history limit: after 120 genuine source frames, the oldest
  24 are evicted, recent IDs remain monotonic, returned dictionaries cannot
  mutate retained samples, and camera stop clears all retained frame data.

The existing UDP unit `tools/test_calibration_packet_latency.gd` was
updated to its **correct 22-check PASS** contract: in a batch of worker
source times `100,103,101`, only two monotonically increasing valid
sources (`100,103`) are retained, while the single final rendered pose
and preview remain the newest. The stale `packet_sequence==1` expectation
was intentionally replaced; unknown sessions and duplicates still cannot
increment the count. Other old 19-check calibration-retry, 23-check
prewarm-bridge, five new Python crowd/sparse-rate and nine existing
Python StudentLock tests also pass in their no-camera runs. A separate
real three-position screen suite
`tools/test_calibration_human_plane_center_only.gd` passed all **56 checks**.
Additional post-patch hardware-free Python checks
`test_pose_camera_startup.py` passed **9/9** (Windows backend fallback,
camera-independent fake capture timestamp freshness, stale YOLO inference and
cleanup), and `test_pose_latency_offline.py` passed **5/5** (bounded latest
capture and correct StudentLock enrollment/recovery timing). Neither suite
opened the computer's actual webcam or loaded a YOLO inference model.

**Separate calibration artwork/layout finding:** the existing
`tools/test_calibration_assets_layering.gd` ran **540 checks, 16 failures**
at 1280×720 and 1920×1080. All 16 concern artwork bounds—top illustration
1.png/2.png/3.png protruding slightly above the viewport, BORDER.png extending
below, and ArtGuideCenter/Right/Left overlay bounds outside the viewport.
These are *not* missing pose packets or false player enrollment. The
production-authored scene geometry was left untouched: a visual/UI owner
must distinguish intentional border bleed from actually clipped instructions
before revising layouts or assertions.

The QA worker touched **only** the new Godot/Python calibration tests,
`tools/test_calibration_packet_latency.gd`, and this report. The prime owns
the production changes. A deployment check with an actual student, school
lighting, webcam and real inference FPS remains necessary to establish
field responsiveness.
