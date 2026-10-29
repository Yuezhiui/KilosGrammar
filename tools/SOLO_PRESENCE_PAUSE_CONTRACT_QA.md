# Post-calibration SOLO presence: pause/PLAY contract and regression

**Scope:** offline QA and integrated implementation. No webcam, YOLO worker,
database, editor `.tscn` changes or Git commit. This regression instantiates
the *actual* gameplay wrapper and the
three actual minigames, not a mocked gameplay policy.

## Final user contract

After genuine physical calibration, Tutorial/Play spotlight and 3-2-1 have
finished and the round has started:

* A **fresh real YOLO detection count of exactly one** keeps the same minigame
  **PLAYING**, with its clock/spawning/other game mechanics running—even if
  `pose=false`, wrists/torso are missing, `lock_state=waiting/lost`, no tracker
  ID has been enrolled, or a different child is now the sole visible person.
  No transient PAUSE/PLAY state or tracking-notice overlay in these cases.
* **Invalid pose still means no body input, plane steering or hand shooting**;
  never replay previous movement/gestures. Fresh motion resumes on newly
  validated landmarks, without registering a specific identity or repeating
  the completed calibration.
* **Zero people or two-plus people** immediately disable the minigame's
  timer/physics/scoring and show the correct missing-person/crowd notice.
  Unknown, malformed or **stale camera observations** must also freeze safely.
  Any newly received, genuinely fresh one-person frame resumes the same round.
* The presence-only rule applies **after** GO; the initial new-round
  calibration and start countdown must still demand a verified real pose.

The Python worker publishes the raw YOLO `detected_count` as the authenticated
Godot packet's `people` field. The regression tests that field, accepting
integer `1` and JSON-decoded float `1.0`, not unknown or fractional counts.

## Run

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tools/test_gameplay_solo_presence_pause_contract.gd
```

The fixture initializes the real `PoseService` autoload and calls its actual
`_apply_pose_packet` with synthetic authenticated camera-phase packets; it
never starts a worker. It records a valid real three-point or Human Plane
neutral calibration, mounts `gameplay.tscn`, completes the actual 3-2-1 for
**Catch the Word, Balloon Popping and Human Plane**, each in **Play and
Tutorial**. It then examines real minigame `process_mode`, `time_remaining`,
`tracking_suspended`, overlay visibility, gesture/movement gates, instance
identity, saved calibration, and navigation emissions.

For each of the **six** configurations, the fixture exercises:

1. Twelve simulated seconds of a visibly present solo child with continuous
   `pose=false` / alternating `waiting` and `lost`, no registered tracker ID;
   **time must progress** while shooting/movement remain disabled.
2. A sole person with an invalid wrist/plane-steering observation; the round
   still runs, but airplane steering cannot be armed.
3. Previous child disappears (zero-person safety freeze), then a different
   person becomes sole visible occupant while still unenrolled; immediate
   resume with no ID and no pose, followed by normal pose recovery with a
   different numeric ID. The same game instance and calibration survive.
4. True 2- and 3-person scenes, including a misleading `pose=true` packet;
   immediate freeze and the correct warning until one sole person is seen.
5. UDP packet arrival older than 1.4 seconds, stale source-capture age 1.9
   seconds despite fresh UDP arrival, unknown/malformed `people`, and a
   genuinely fresh 1-person packet following a stale frame.

## RED reproduction and verified correction — October 28, 2026

Initial test against the integration tree:

`SOLO PRESENCE PLAY CONTRACT: FAIL (338 checks, 6 failures)` — exit 1, no
Godot parse/script errors. **332/338 checks passed.** All six failures are
**exactly the same stale-capture safety defect**: a packet with `people=1`,
`pose=false`, `camera_frame_age_ms=1900`, and a newly updated UDP arrival time
incorrectly kept the round PLAYING. The bug reproduced separately in Play
and Tutorial for all three games.

Fixed root in `ui/play/gameplay.gd`: the wrapper now calls
`PoseService.fresh_camera_population()` rather than trusting only UDP arrival
time. The service verifies exact raw YOLO box count, active session/transport,
live worker, source frame age and elapsed receipt age. It cannot reuse an old
person-detection observation, yet it does NOT require pose confidence or a
registered tracker ID. Movements, hands and plane steering independently
require fresh eligible landmarks. Balloon Popping also clears stored launcher
velocity immediately on a lost pose, while its round continues.

**Final verified result:** `SOLO PRESENCE PLAY CONTRACT: PASS (346 checks, 0 failures)`,
including two additional stale-balloon-launcher checks. Independent strict raw
occupancy test `test_pose_raw_solo_occupancy_gate.gd` PASS (102 checks).

**PASS criterion:** every one of the six configurations completes
with zero failures; a stale captured frame, an unknown population, and any
0/2+ crowd freeze immediately; a *fresh* one-person observation resumes
clock/scoring mechanics, even while pose input remains invalid. Physical
webcam validation is still necessary for tuning source freshness budgets.

This test targets the **new** presence-only specification. Old tests expecting
physics to freeze for a single person with `pose=false` must be migrated to
this latest user policy, not used to weaken strict camera freshness.
