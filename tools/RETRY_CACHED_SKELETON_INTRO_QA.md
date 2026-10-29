# Results Retry -> calibration intro / cached skeleton regression

## Scope

Standalone, **test-only** Godot 4.7.2 integration fixture:

```powershell
& 'C:\Users\Yue\Documents\GODOT\GDSCRIPT\Godot_v4.7.2-stable_win64_console.exe' --headless --verbose --path . --script res://tools/test_retry_cached_skeleton_intro_qa.gd
```

**Fixture:** `tools/test_retry_cached_skeleton_intro_qa.gd`

This script makes **no** production, Godot editor scene, webcam, Python worker,
YOLO model, database, or Git changes. It instantiates the actual
`main_menu.tscn`, real Results, Student Setup, activity selector and calibration
Controls. The database is replaced with the existing in-memory
`tools/play_route_mock_database.gd`; the app runs headless with database access
disabled. The pose service's normal processing is disabled. The green skeleton
is a recognizable synthetic green polyline baked into an `ImageTexture`, not a
real person or a prediction from the YOLO model.

To test the **existing service's production preview-rebind guard** without
opening a physical camera, the test temporarily represents a live worker with
an unbound `PacketPeerUDP` and the already-running Godot process's own PID.
It does not create any new OS process or open any network port. It always
restores `worker_pid = -1` and `peer = null` **before** any
`PoseService.stop_camera()`, Main Menu navigation, or test shutdown.

## Test matrix

| Scenario | Play | Tutorial |
| --- | --- | --- |
| Actual Results `%RetryButton` -> Student Setup | Yes | Yes |
| Edit name, grade/section, topic, difficulty for new round | Yes | Yes |
| Same Catch the Word activity preserved through retry | Yes | Yes |
| Actual activity selection and calibration route | Yes | Tutorial's preselected activity routes from form directly to calibration |
| Former round's calibration cleared | Yes | Yes |
| 3.0-second intro, cumulative 60–70% black treatment | Yes | Yes |
| Only the CALIBRATION title visible, no intro description/countdown | Yes | Yes |
| No header, yellow guide, arrow, step badge, countdown art or hint leaking beneath intro | Yes | Yes |
| Intro Back hidden and disabled; normal Back available after 3 seconds | Yes | Yes |
| CENTER stage not rendered before intro is over | Yes | Yes |
| Fresh **cached** bones JPEG preview rebound on scene attach | Yes | Yes |
| Visible skeleton immediately after intro, no leave/reenter event | Yes | Yes |
| Unchanged next preview event also renders bones | Yes | Yes |
| Continuous fresh SOLO packet stream measures CENTER -> RIGHT -> LEFT | Yes | Yes |
| All physical measurements valid; no stale score or premature handoff | Yes | Yes |

The calibration stages are fed more than the required eight distinct
monotonic-timestamped samples, with fresh tracked SOLO state and intentional
body position changes. During intro, the same student remains present while
synthetic pose updates continue. The fixture checks that the intro contributes
no time to a physical hold. It does **not** fake a student leaving and
reentering the camera to force a skeleton to appear.

## Previously reproduced gaps and latest result

Before the prime's accompanying production integration, source inspection
and the first end-to-end run identified `INTRO_SECONDS = 2.5`, an effective
~10% black intro, and no visible cached green skeleton at calibration entry.
That is why this fixture tests all three contracts explicitly rather than
only asserting that calibration can finish.

After the prime's latest calibration work, the focused run returned:

```text
RETRY INTRO & CACHED SKELETON QA: PASS (76 checks, 0 failures)
Godot exit code: 0
Script errors / Godot warnings / resource leaks: 0
```

## Limitations / manual classroom reproduction

1. A synthetic green image proves **UI preview replay and TextureRect
   visibility** only. It cannot demonstrate real YOLO bone/keypoint inference.
   Worker 6 has separately identified a possible source of the physical bug:
   `model.track(persist=True)` may suppress raw visible people until
   ByteTrack obtains a confirmed track. Their raw-detection occupancy change
   must be checked with a physical webcam.
2. A live physical test should keep the same learner **continuously visible**
   after Game Over -> Retry -> new student setup -> same activity -> calibration.
   Do not move out of the frame as a workaround. Confirm green bones appear
   immediately at the end of the three-second title; then measure CENTER,
   RIGHT and LEFT without reentry.
3. Repeat for Play and Tutorial, for two consecutive rounds, and with 0/2+
   people intermittently entering the scene. The one-player hold and the
   ordinary in-game pause/resume behavior are covered by separate suites.
4. The existing Main Menu intentionally ends the prior camera session when
   navigating from Results to setup. This headless fixture **re-seeds a safe
   fresh SOLO stream before the new calibration**; it does not claim to prove
   continuous transport across Main Menu routes on hardware.
5. Regression can distinguish UI cache rebind from YOLO inference only with
   real camera capture or recorded frames replayed through the worker. Do not
   interpret a synthetic PASS as an all-hardware-clear result.

## Ownership

Worker 9 owns this *new* QA script/document only. Main Menu, calibration
production scripts, scene-authored editor layout, YOLO worker, and database
production files were not edited as part of this QA task.
