# Five PNG pose guides and mode-specific calibration — QA contract

**2026-10-28. Scope: dedicated Godot regression + documentation only.** No
production GDScript, `.tscn` geometry, PNG assets, model, webcam, database,
or Git commit were modified by this QA worker.

## New requirements (replace the former shared 3-step routine)

The classroom introduction remains a **separate EXACT 3.0 seconds** of
designed CALIBRATION title; no instruction or physical-hold credit occurs
during that introduction. The intro is **not** part of any durations below.

| Game | Physical calibration after intro | Total physical holds | Elapsed with intro |
| --- | --- | ---: | ---: |
| **Catch the Word** | CENTER DEFAULT 3s → RIGHT DEFAULT 3s → LEFT DEFAULT 3s | **9s** | **12s** |
| **Balloon Popping** | CENTER DEFAULT 3s → CENTER BALOON POP/one hand raised 3s → RIGHT DEFAULT 3s → RIGHT raised 3s → LEFT DEFAULT 3s → LEFT raised 3s | **18s** | **21s** |
| **Human Plane** | CENTER **full T-pose** 3s, then game starts using smooth arm banking | **3s** | **6s** |

These are minimum *genuine, consecutive valid observation* durations, not
promises of fixed wall-clock completion when a child moves, disappears, has
an occluded wrist, or YOLO is too slow. Each hold needs **at least eight
distinct source packets** in addition to 3.0 seconds.

The five user-supplied assets are now located under
`Components/Gameplay/Calibration/Pose Guides/` and correspond to five
**independently editor-draggable** `TutorialStage` `TextureRect` nodes:

1. `PoseGuideDefault` → `DEFAULT.png` for Catch and Balloon default holds
2. `PoseGuideBalloonRaise` → `BALOON POP.png` for Balloon raised-hand holds
3. `PoseGuidePlaneCenter` → `PLANE T POSE.png` for Plane physical calibration
4. `PoseGuidePlaneLeft` → `PLANE GOING TO LEFT.png` for Plane bank reference
5. `PoseGuidePlaneRight` → `PLANE GOING TO RIGHT.png` for Plane bank reference

The former neon `PARAMETERS.png` guides, including
`ArtGuideCenter`, `ArtGuideRight`, `ArtGuideLeft`, must stay **hidden** after
the intro. Merely leaving those neon squares visible underneath the new PNGs
does not meet the request. Do not flatten the images into a background or
hardcode UI coordinates.

## Real source / gesture safety

During physical calibration, YOLO must see **exactly one fresh person**;
0 people, 2+ people, an unknown/stale camera state, duplicated source
timestamps or a stale preview never earn progress or complete a hold.

* DEFAULT is the observed lowered-hand posture; a raised-hand sample or
  unknown/occluded wrists does **not** earn a DEFAULT hold.
* BALOON POP requires an observed raised hand, but never a cached/unknown
  wrist. A down frame cannot earn a raised-hand hold. The raised phase is a
  separate fresh 3s measurement, not a 3s still image swapped over the timer.
* Plane starts only after an observed full arms-out **T-pose**, with both
  wrists legitimately observed, held stationary in CENTER for 3 seconds;
  the previous 2.5-second neutral torso hold is obsolete.
* After Plane enters gameplay, arm banking should move left/right smoothly;
  the body cannot move based on cached/bystander/synthetic hand gestures.
  The five PNGs are visual references, not pose detector shortcuts.

This physical-hold safety rule is **separate** from the newer *post-GO*
gameplay rule: once calibrated, any fresh exactly-one-person camera detection
keeps a round PLAYING even while pose is unavailable; only its movement and
gesture input are withheld. Tests must never retroactively apply that
presence-only gameplay rule to physical calibration.

## New headless regression

Run in repository root:

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_calibration_five_pose_png_sequences.gd
```

`test_calibration_five_pose_png_sequences.gd` mounts the **actual**
`calibration.tscn`, binds a localhost `PacketPeerUDP`, installs a mock
current-process worker PID only for `PoseService` freshness checks, and uses
the real `_apply_pose_packet` and `_record_fresh_calibration_pose` API.
It deliberately sets `PoseService.worker_pid=-1` before every scene
teardown/`stop_camera()` so the test never kills its own Godot process. No
physical webcam, Python/YOLO worker, external network, or live DB is used.

For each of the three games, checks cover intro 2.99s vs 3.00s, five
independent authored PNG node resources, neon-square absence, staged guide
visibility, exact 3s timing, >=8 genuinely fresh packets, wrong pose,
occluded wrists, source-frame replay, 0/2+/3 occupants, each expected phase
transition, and completed physical measurements. After Human Plane's T-pose
calibration, an additional test holds the student's torso X at center and
sends opposite genuine arm-bank values; left/right steering must respond to
the arms rather than requiring the child to slide horizontally to steer.

### RED → GREEN integration history

At first execution the calibration owner was editing production files in the
same shared workspace. Godot emitted a **production GDScript parse error**
in `ui/vision/calibration.gd`: `Expected statement, found "Indent" instead`
at line 482. Subsequent concurrent changes moved that parse error to lines
507 and then 584. The next compile failure `Identifier not found:
PoseService` from `calibration.gd:109` was exposed by a QA-fixture ordering
problem: its `const SCENE := preload(...)` compiled the script before the
`PoseService` autoload registered in `--script` mode. The fixture was
corrected to use **runtime `load(SCENE_PATH)`** after resolving the autoload.
With the fixture fixed, the real stage controller executed.

**First meaningful RED:** the complete fixture ran with **181 checks,
12 failures** (all in Catch DEFAULT). Raised-hand samples could complete a
Catch DEFAULT hold, as could hands with no trusted wrist observation.
Consequently the UI advanced too early, creating cascading hold-timing
failures in subsequent Catch stages. Balloon's six phases and Plane's T-pose
and arm-bank checks were already passing. The regression now replays genuine
completed earlier holds after a failed stage, preventing cascading errors
from disguising independent defects.

**Final GREEN (after production owner integrated the missing Catch DEFAULT
wrist/posture gate):** `FIVE PNG CALIBRATION STAGES: PASS checks=181
failures=0`, Godot **exit 0**, no script errors. The new requested sequences,
PNG scene references, source-frame safety, and synthetic arm banking passed.

### Legacy regression migration (prime-authorized QA-only follow-up)

Three pre-existing suites were still asserting the **superseded** 2.5-second
Plane center-only pose, `ArtGuideCenter/Right/Left` neon-square visibility,
or only three Balloon floor stages. They were migrated **in-place**, retaining
their distinct UI/navigation, physical zone stability, safety, loss and Retry
assertions rather than deleting or bypassing tests:

| Script | Additional coverage carried forward | Final result |
| --- | --- | --- |
| `test_calibration_three_second_sequence.gd` | Intro exclusivity, buttons/focus, preview rebind, wrong-zone and stale packet checks, native authored DEFAULT/T-POSE PNGs and legacy neon hidden, **six** Balloon source-verified 3s phases | **PASS 1,488 / 1,488** |
| `test_calibration_single_person_round.gd` | 0/2+/unknown occupants, 5+ seconds missing, changing tracker IDs, same-round resume, scene retry, 3s full-T-pose, Balloon's six real holds and id-free physical measurements | **PASS 79 / 79** |
| `test_calibration_human_plane_center_only.gd` | Legacy center-only/fabricated floor limits rejected, source-packet T-POSE duration below/above 3s, Catch three floor locations, Balloon six default/raised phases, valid gameplay handoff | **PASS 28 / 28** |

The dedicated five-PNG test remains authoritative for nuanced gesture/wrist
gating, arm banking at a fixed torso X, and distinct PNG resource bindings.
The older suites now supplement rather than contradict it.

The stage implementation was being actively changed while QA executed, so
the final verified GREEN result supersedes the earlier parse/compile-blocked
attempts. All snapshots were of the shared workspace; this QA worker did
not modify production GDScript or visual scene files.

**Acceptance:** test exits **0 with zero failures and no Godot SCRIPT ERROR**;
real webcam follow-up must verify a student's actual hand raise, full T-pose,
multi-person safety, and smooth arm bank, since synthetic inference cannot
prove those physical motions.
