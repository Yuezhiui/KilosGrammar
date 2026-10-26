# Human Plane — calibrated pose, real 3D ring collision, speed and camera QA

**FINAL STATUS: PASS after the synchronized 3-anchor renderer change.**
The final hardware-free test completed **409/409 checks, 0 failures**;
the NVIDIA RTX3050 OpenGL3-backed run completed
**431/431 checks, 0 failures**, including red-aircraft pixels
at 1280×720, 1600×900 and 1920×1080. Both Seconds and Lives
were covered. The historical 12/24 failing snapshots recorded
below were taken during concurrent renderer changes or used an
outdated linear test inverse; they are **not outstanding failures**.
The verified fix and final numbers appear at the end of this report.

**Run date:** 2026-10-26.
**Owner:** worker-4, QA only.
**Scope:** new offline/optional OpenGL test
`tools/test_human_plane_pose_hitbox_qa.gd`, source-read-only investigation.
All production gameplay, 3D camera/rig, PoseService, worker model, user artwork
and database files were deliberately left unchanged.

## Historical defect: visible 3D rings vs hidden scoring hitbox

Human Plane has **two different lane coordinate systems**:

1. The visible original red FBX is drawn in 3D. The renderer maps the
   pilot's normalized horizontal position `plane_x_norm` from **0..1**
   onto its authored lateral travel span. This was world X **−9.5..+9.5**
   in the initial capture, but was narrowed to **−3.6..+3.6** during an
   in-progress camera/rig revision. The three visible torus centerlines
   remained world X **−6, 0, +6**.
2. The authoritative answer evaluator
   `human_plane.gd::_lane_hit_at_answer_line()` uses invisible
   editor-authored **2D** `PlaneRig/Hitbox` and `MovingGates/*/GateArtwork`
   rectangles. These 2D visuals are deliberately hidden in full-3D mode,
   but their art bounds continue to determine score, lives and boosts.

For the initial larger travel span, the three 3D torus centers corresponded
to normalized pilot X **0.1842105**, **0.5000000**, **0.8157895**.
**After narrowing to world X −3.6..+3.6**, the outer ring centers
instead imply normalized X **−0.333333** and **1.333333**, both
physically unreachable by an input clamped to 0..1.
The hidden 2D scoring guide's gate horizontal centers in the authored
1280×720 coordinate system are **449.674px**, **640.000px**,
**829.326px**, corresponding to normalized source hit positions
**0.326785**, **0.493855**, **0.660048**. Under the current
−3.6..+3.6 travel, the world-ring positions required for perfect
alignment to those existing hitbox centers would be approximately
**−1.247, −0.044, +1.152**. These numbers are diagnostic, not
instructions to blindly compress ring geometry and introduce
visual overlap. Ring footprint, plane width, perspective and gameplay
collision must be coordinated by their production owners.

**Reproduced on real Godot PackedScenes at all three render sizes and
both modes:** moving the actual 3D pilot toward either outside ring center
yields `_lane_hit_at_answer_line()==-1` (**MISSED**) with the
source hitbox mapping. The original issue was 3D/2D misalignment;
the updated narrow travel makes the side torus centers impossible to reach.
The middle ring at approximately normalized X 0.5 scores CENTER.
These results repeat in **1280×720, 1600×900 and 1920×1080**
and **Seconds/Lives** (12 failing assertions, two per combination).

Thus the user can visually fly through a side ring and still lose a heart.
This is a **mismatch between world-space ring/pilot coordinates and the
invisible 2D score geometry**, not proof of a YOLO detection failure.
The test also confirms that each hidden 2D ring's *own* true center scores
its corresponding lane, so the collision code itself is internally coherent.
Worker-2 owns the coordinate mapping/ring-selection production fix; the
prime agent was informed with the exact failure positions and counts.

### Collision ambiguity safety

The new test performs an independent 1D collision check from the scene's
editable image rectangles and physical pilot hitbox. A lane is eligible
**only if one visible ring footprint intersects the hitbox**, at least
70% of the physical hitbox width is covered, and its center is inside
the inner 30%-of-ring-width safe window. Any overlap with two adjacent
ring rectangles—no matter how thin—returns **MISS**, never a guessed
left-to-right winner or a free correct answer. The test sampled
**201 positions per viewport/mode**, **1,206 positions total**; no
disagreements between its independent collision oracle and production
selection logic were observed. It found **66 overlapping-two-ring**
sample positions over all cases, all correctly marked ambiguous.
Adjacent-ring center midpoints also scored MISS. This safety requirement
must survive the visual/alignment fix.

### Live pose/arm permission

The test uses the real PoseService `set_calibration(0.18,0.50,0.82)`
and `normalized_body_x()` with **synthetic fresh locked-student packets**.
No camera is opened. Positions 0.18, 0.34, 0.50, 0.66 and 0.82
normalize to −1, −0.5, 0, +0.5, +1 respectively. A regular
body position alone must not steer: verified airplane arm extension
must activate the gate, and a fresh position must arrive after
reenabling it. Lowered/occluded hands, disabled gesture or pause
immediately stop lateral movement. A 900ms-old gesture expires while
the more permissive 1,750ms body-pose timeout has not yet expired;
that expired gesture cannot leave the plane drifting.

### Scoring and speed invariants

- A valid centered answer grants exactly **+100 points** and **+14%
  cumulative flight speed**, stored independently of streak.
- A missed ring or a geometrically ambiguous adjacent crossing
  subtracts **zero score**, loses **one heart**, and **never removes
  earlier speed boosts**.
- A genuine wrong ring subtracts **zero score**, loses one heart, resets
  the correctness streak but leaves all previously earned speed boosts.
- Idempotent repeated collision callbacks cannot count the same ring
  twice. The next ring's actual gameplay progress advances at
  difficulty speed × retained multiplier after both an ambiguous
  miss and a wrong answer.
- The full-3D renderer's speed multiplier and the results/pause
  payload preserve the earned pace across these scoring events.

## Camera and original FBX projection

The scene's real Camera3D is current with an authored FOV, and the supplied
red airplane FBX has **22 imported mesh components**. At the neutral
pilot position under the initial camera, CPU frustum projection
of those mesh corners gave a bounding rectangle approximately
**69×31 pixels** inside the 1280×720 SubViewport,
at **x≈606..674, y≈461..492**. A subsequent camera/rig update
improved projection to **~97×55 pixels**, near
**x≈591..689, y≈561..617**. All 176 sampled mesh-AABB corner projections
were in front of the camera. This proves the aircraft is not culled or
behind the camera at neutral, but the original **~69px width was small**
for an educational game on classroom displays. Worker-1 owns camera/scale
adjustments and GPU-visible enlargement; do not simply change the user's
desired FBX scale without checking the torus perspective and ring occlusion.

The optional real OpenGL 3.3 run used an NVIDIA RTX 3050 6GB laptop GPU
and saved screenshots to Godot's `user://` area, not production
`Components/` or `tools/`. Strong-red pixel samples in the expected
lower-center aircraft region passed at 1280×720, 1600×900 and
1920×1080. A screenshot with some red pixels is evidence of a rendered
aircraft, not proof of an adequate visual size or that the 3D torus hit
is aligned with collision.

## Command and preliminary results

```powershell
$godot = 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --script res://tools/test_human_plane_pose_hitbox_qa.gd
& $godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 --script res://tools/test_human_plane_pose_hitbox_qa.gd -- --gpu
```

Initial headless run: **385 total checks, 12 failed**, solely the
left/right world ring centers not scoring at their visually apparent centers.
All pose arm gating, robust hitbox-overlap ambiguity, zero-penalty wrong/miss,
persisting earned speed, imported FBX/camera existence and projection checks
passed. GPU run: **395 total checks, 12 failed**, with the additional
red-aircraft pixel/screenshot checks passing. The 12 geometry failures are
repeated viewport/mode instances of the **same two coordinate errors**,
not twelve unrelated crashes.

**Owner handoff:** fix 3D world lane center alignment with the exact
editor-authored physical hitbox and ring choices; preserve strict adjacent
ring ambiguity and existing 0-point miss/wrong behavior. Independently
evaluate camera/rig framing so the plane is readable rather than merely
present. Worker-4 will rerun these unchanged scoring and projection
assertions after the production owners finish; no webcam/DB/commit
is necessary.

### In-flight camera/rig geometry recheck

The extended test queries the **actual running 3D view's**
`sync_flight(0)` and `sync_flight(1)` and reads
real ring Node3D X values; it no longer assumes a historical
player travel span. After the travel changed to **−3.6..+3.6**
while torus rings remained at **−6/0/+6**, the test recorded
**403 checks, 12 failures**. The failing conditions are the same
unreachable LEFT/RIGHT ring centers across three viewport settings and
two game modes. Correct/wrong/miss score handling, 1,206
independent hitbox samples, body-arm permission and boost retention
remained valid. Red-plane projection improved to **~97×55 pixels**.
Final signoff is deferred until worker-2 aligns the actual rendered
lane centers with the authoritative safe selection regions and
worker-1 confirms the final camera/FBX framing.

**Further physical mid-lane regression (important):** after worker-1
restored an inspector-authored `visual_lane_extent=9.5`, the
actual 3D pilot spans world X **−9.5..+9.5** again, while
three toruses remain centered at **−6/0/+6**. This yields
required world-space ring centers **−3.291/−0.117/+3.041**
from the still-authoritative 2D scoring hitboxes, so the hidden
scorer considers the aircraft almost perfectly LEFT or RIGHT while
the **visible plane is physically between the ring centers**:
world X −3 (normalized 0.342) is midway between LEFT and CENTER;
world X +3 (normalized 0.658) is midway between CENTER and RIGHT.
These **must** be ambiguous misses rather than guessed/incorrect or
correct ring hits. The expanded strict oracle now reproduces both
failure types: **403 checks, 24 failures**—12 outer torus center
false misses and 12 ring-midpoint false selected lanes across six
viewport/mode combinations. The other **379 checks passed**, including
all real-PoseService arms and normalization, cumulative scoring/boosts,
and 1,206 independent legacy 2D collision oracle samples.
The latest neutral camera projection was about **83×43 px**
in the 1280×720 SubViewport, demonstrating that framing remains
actively under revision. These are in-progress owner edits, not a
final production QA verdict.

## Final correction: actual 3-anchor world mapping verified

The production 3D view now receives **three measured normalized
scoring centers** from `HumanPlane::_normalized_scoring_lane_centers()`,
derived from the actual scene-authored PlaneRig hitbox and GateArtwork
rectangles at the answer-line crossing. The renderer
`_render_x_from_body_norm()` uses those exact anchors
with piecewise interpolation and monotone tanh tails. It alters
**presentation only**, preserving authoritative score and collision
decisions in `human_plane.gd`.

| Ring | Authoritative scored body norm | Rendered torus world X |
| --- | ---: | ---: |
| LEFT | 0.32678536 | −5.99999977 |
| CENTER | 0.49385528 | −0.00000051 |
| RIGHT | 0.66004750 | +5.99999897 |

World-coordinate alignment error is below **0.000002** units.
At those positions the visible 3D pilot goes directly through
the scored torus center. Physically between adjacent real rings,
the scorer returns **MISS**, not a false winner. All **1,206
sampled normalized body positions** across 3 screen sizes and
2 modes agree with an independent strict hitbox oracle; the
**66 ambiguous overlap samples** also fail safely.

The final test had to fix **its own stale world-coordinate inverse**.
An earlier linear pilot X range was replaced by the nonlinear
3-anchor renderer; evaluating a world midpoint with the old
`(world−min)/(max−min)` expression measured an unrelated body
position. The test now performs a **32-step bounded binary search**
of the actual monotone renderer mapping, without changing any
production files. That explains the transient false regressions
while production owners were actively adjusting geometry.

### Verified final QA

| Check | Result |
| --- | --- |
| Headless Godot test | **PASS — 409/409** |
| Real OpenGL3 GPU test, NVIDIA RTX 3050 6GB | **PASS — 431/431** |
| All 3 viewport sizes × Seconds/Lives | **PASS** |
| 22-part original RED FBX on-screen camera projection | **PASS**, about 83×43 px in the internal 1280×720 SubViewport |
| Original torus center and between-ring selection | **PASS** |
| Independent strict collision oracle, 1,206 positions | **PASS** |
| 66 ambiguous two-ring samples | **PASS** (all miss) |
| Fresh calibrated CENTER/RIGHT/LEFT body pose and raised-arm gating | **PASS** |
| Wrong and missed answer point deduction | **0** |
| Correct ring scoring and permanent speed | **+100 points**, **+14% per correct** |
| Score, speed and lives persistence after wrong/miss | **PASS** |

Real webcam/student movement was not tested by worker-4.
The optional GPU checks confirm that bright-red aircraft pixels
appear in the expected screen region, but do not guarantee
readability on every classroom display. No production files,
database or camera devices were modified or opened by this
QA worker; screenshot captures remain outside the project
under Godot's `user://` directory.

### Actual full-game compositing verification (not just model viewer)

The final GPU test also mounts the **actual `human_plane.tscn`**
with its real scoreboard, UI overlays, SubViewport and red-plane FBX
at all three output resolutions. It freezes gameplay/world state and
compares two adjacent OpenGL render captures: aircraft visible vs
only the original red FBX temporarily hidden in-memory. All other
elements and the exact camera state remain unchanged. This differential
demonstrates **actual in-game aircraft visibility** rather than falsely
crediting red HUD/text/sky colors.

| Actual gameplay resolution | Sampled bright-red plane pixels | Same frame with FBX hidden |
| --- | ---: | ---: |
| 1280×720 | **89** | **0** |
| 1600×900 | **133** | **0** |
| 1920×1080 | **194** | **0** |

All three differential assertions passed. The captured full-game
images are stored only in Godot's `user://human_plane_pose_hitbox_full_*.png`,
outside version-controlled project assets. The user-reported invisible
aircraft cannot be reproduced in this controlled current-project
OpenGL render. That does **not** exclude a stale packaged build,
different active camera mode, intermittent live state, GPU driver
configuration, or a real classroom display difference—none of those
was probed with physical devices in this worker's scope.
