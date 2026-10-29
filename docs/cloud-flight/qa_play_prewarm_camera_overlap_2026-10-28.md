# Play camera prewarm/preview latency regression — 2026-10-28

## Reproduced root cause

Tutorial starts the normal webcam worker: `pose_worker.run()` opens the
camera and publishes a real 640 × 480 JPEG before it imports/warms YOLO.
Play previously started `prewarm_worker()` from activity/student setup; the
entire model load ran synchronously **before** the worker listened for its
authenticated `start_camera` command. If a student finished setup during a
five-second model warmup, calibration's camera waited those five seconds to
begin opening, even though the teacher had already authorized camera access.

## Repair

- `prewarm_worker` prepares the same YOLO model in a background thread while
  accepting a token-verified loopback start command. It never opens a camera
  until that command arrives. If it arrives during warmup, `run()` opens the
  webcam, publishes a real preview, then waits for the *same* model to finish
  preparing. If the model was already ready, the previous fast cached path
  is preserved.
- Progress/heartbeat packets stop after permission is acknowledged; old
  `prewarming` statuses cannot overwrite the live webcam state.
- `pose_service.gd` recognizes the start acknowledgement even when newer
  `opening` packets are coalesced into the same Godot render frame. Camera
  startup timeout starts from this acknowledgement. No fake student pose or
  calibration samples are synthesized during startup.
- CPU-only inference caps torch's intra-operation threads at four to reserve
  processing capacity for game rendering, JPEG preview and webcam capture.

## Hardware-free verification

`python -m unittest -v test_pose_prewarm_overlap.py` in `ui/vision`
verifies that (1) no webcam can open before authorization, (2) the worker
begins the camera path while artificial model loading is still blocked,
(3) one and only one warmup model is reused, (4) the *real* worker publishes
an encoded 640 × 480 JPEG from a synthetic camera before model loading
finishes, and (5) CPU-only warmup limits Torch threads before inference.

Existing worker/startup tests and Godot pose preview/watchdog tests also run
with the same code. These tests deliberately do **not** open a physical
webcam or connect to PostgreSQL. Actual Windows camera-driver first-frame
latency, GPU saturation during a full minigame, and Play movement after
countdown still require a teacher's device-level play session for acceptance.

`tools/test_pose_warmup_start_ack_coalesced.gd` additionally sends two
synthetic UDP statuses into the actual Godot autoload in one render frame:
an authorized camera-start ACK followed immediately by a newer
`opening` status. It verifies that the start is recognized, watchdog
timing resets, the newest status wins visually, and no pose is fabricated.
An ACK with the wrong token is rejected. **PASS: 16 checks.**

The separate historical `tools/test_calibration_latency_retries.gd` fixture
currently forces **Human Plane** through the retired three-stage center,
right, left path; the current Human Plane calibration has one real neutral
hold. Its stage-count assertions are obsolete and are not evidence of a
camera prewarm regression.
