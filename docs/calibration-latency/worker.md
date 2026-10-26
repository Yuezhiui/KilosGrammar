# YOLO26 calibration worker latency: profiling and implementation

Measured/implemented on 2026-10-26, Windows, local offline `yolo26n-pose.pt` (7.9 MB), Python 3.11 with Ultralytics, PyTorch CUDA, RTX 3050 6 GB. This report covers only `ui/vision/pose_worker.py` and `ui/vision/test_pose_worker_latency.py`; Godot `PoseService` and calibration UI are maintained by the prime agent.

## Root cause of the five-to-ten-second first pose

Before this change, every camera start created a fresh Python process, imported Ultralytics/Torch, loaded the model and performed a first CUDA warmup **after opening the webcam**. The baseline cold-process probe, using the real cached local model and a synthetic 640 × 480 image with no webcam, measured:

| Cold-start stage | Measured |
| --- | ---: |
| `from ultralytics import YOLO` | 2.611 s |
| `YOLO(existing_pose_weights)` | 0.091 s |
| First CUDA `model.predict` warmup | 3.592 s |
| First ByteTrack `model.track` after warmup | 0.114 s |

This is about **6.3 seconds of import and CUDA initialization** even with cached weights. Existing `StudentLock` intentionally requires **1.2 seconds and eight fresh frames** of unambiguous center enrollment after live tracking begins; those safety conditions must remain. A warmed new-worker local-model test now takes **5.979 seconds** to initialize the same YOLO26 weights and ByteTrack tracker without opening any camera. That work occurs while the teacher/student completes game setup, so on-time completion removes most of the visible calibration delay. A student who reaches calibration before warmup is complete still waits for the remaining initialization time. Measured timings are machine-dependent, not promises for CPU-only school computers.

## Prewarm protocol coordinated with Godot

**Normal launch is backwards-compatible.** The existing `--port`, `--token`, `--camera`, `--model`, `--weights-dir`, `--bones-*` flags still start the camera immediately. In new `--prewarm` mode, the worker **never calls camera capture or opens a webcam** until Godot explicitly authorizes camera calibration. Ultralytics may import OpenCV internally as a dependency while preparing the model.

1. Godot starts the worker with existing arguments plus `--prewarm` when the camera-game setup begins. The worker binds an ephemeral control port on **127.0.0.1 only**, and sends JSON over the existing Godot-bound pose/status UDP socket: `{"kind":"pose","token":"<session>","when":<monotonic_seconds>,"state":"prewarming","pose":false,"model_ready":false,"control_port":<ephemeral>}`. Loading heartbeats run every ~0.7 seconds, including throughout the blocking Torch/CUDA initialization, so Godot's worker watchdog does not falsely consider the process stuck.
2. Once YOLO and **ByteTrack itself** are warmed, the worker sends `state:"ready",model_ready:true,pose:false,control_port:<same>`. The model remains resident inside the same worker process. No frame, student image or tracking packet is collected during prewarm.
3. When the student proceeds to calibration, Godot sends the exact UDP JSON `{"command":"start_camera","token":"<same_session_token>"}` to `127.0.0.1:<control_port>` using the retained local UDP peer. The worker requires an exact token match, loopback source address and exact command. Invalid, unrecognized or unauthenticated requests are ignored. If sent before the warmup finishes, the OS UDP socket holds the one small command until the model is ready.
4. The worker stops its prewarm heartbeat, sends `state:"loading",camera:true,pose:false` immediately to acknowledge the accepted camera start, and then calls the **same normal camera loop** with the *already initialized* `(model, device, gpu)` tuple. It does not import/reload the model a second time. The original JSON pose states, ByteTrack ID locking, normalized keypoints, mono-clock `when` field, JPEG `\x01` preview bytes and localhost UDP delivery remain unchanged.

The prewarm process must be reused across student setup and calibration; killing/restarting it discards the CUDA model warmup. Abandoning setup terminates the worker, so its memory is released. The worker still exits with the usual normal-camera error code when webcam access fails.

## Other worker-side changes

- **Tracker-ready warmup:** the previous warmup ran a generic `predict` on a 320×320 blank image and initialized ByteTrack on the first actual student frame. Now one zero-person 640×480 synthetic frame passes through the exact normal `track(..., persist=True, tracker="bytetrack.yaml", imgsz=320, classes=[0])` path. The blank image never creates a student identity or skips enrollment. Model weights are instantiated once per process and use the bundled or existing offline path supplied by Godot.
- **Device fallback:** CUDA is preferred when PyTorch reports availability. On CUDA/CuDNN/driver/VRAM initialization errors, the worker creates a fresh model predictor and warms on CPU, reporting that fallback in loading status; corrupted or missing weights still produce a real error. A system without CUDA uses CPU from the outset. The worker preserves all existing student-lock and gesture-detection logic.
- **Latest inference frame:** `LatestCamera` already has one replaceable frame slot and advances the frame sequence on each webcam capture; no growing frame queue was introduced. The tracking loop consumes only `newest(previous_sequence)`, avoiding processing old capture frames when inference is slower than camera FPS.
- **Independent JPEG work:** previously, the prediction loop blocked while compressing and sending a camera preview after every detection. `LatestPreview` now compresses only the latest already-inferred mirrored frame in a separate bounded thread at up to 24 FPS, with a single replaceable slot and no backlog. The pose/skeleton and its image share the same inferred frame; no bystander skeleton is added. Preview threads stop and clear their image references when the worker exits, before the UDP socket closes.
- **Timing field:** normal `tracking` JSON packets include optional fixed `startup_ms`, measured from entry into the camera phase to the end of model initialization. In a prewarmed process it excludes the work already completed during student setup. Existing `when=time.monotonic()` seconds is unchanged so Godot can continue choosing the freshest pose packet.

## Verification

Camera-free Python suites:

```powershell
& 'C:\Espressif\tools\python\python.exe' -B -m unittest discover -s ui\vision -p test_pose_worker_latency.py -v
& 'C:\Espressif\tools\python\python.exe' -B -m unittest discover -s ui\vision -p test_pose_*.py -v
& 'C:\Espressif\tools\python\python.exe' -B -m unittest discover -s ui\vision -p test_student_lock.py -v
```

The focused tests verify tracker-warmup settings and CUDA→CPU fallback, malformed-weight failures, unchanged token/monotonic status format, a newest-only preview queue, local UDP control-port authentication, no camera use before an authorized start command, immediate `camera:true` acknowledgement, reuse of the exact loaded model, and ongoing prewarm heartbeats during simulated multi-second CUDA startup. Existing pose/student-lock suites check no invented positions, correct owner enrollment and bystander rejection, and skeleton rendering. The optional *real weights, still camera-free* benchmark runs only when `KILOSGRAMMAR_POSE_MODEL` points to an existing local `.pt` file:

```powershell
$env:KILOSGRAMMAR_POSE_MODEL = Join-Path $env:APPDATA 'Godot\app_userdata\KilosGrammar\pose_models\yolo26n-pose.pt'
& 'C:\Espressif\tools\python\python.exe' -B -m unittest discover -s ui\vision -p test_pose_worker_latency.py -k test_real_offline_tracker_warmup -v
Remove-Item Env:KILOSGRAMMAR_POSE_MODEL
```

The optional real CUDA warmup passed in **5.979 s**. No database, teacher/student webcam, or actual calibration was accessed in these tests. Real 5/10/60-second moving-user measurements must be repeated on the deployment PC because camera backend startup, USB capture FPS, low-light landmarks, and CPU inference can still dominate; the webcam's advertised 60 FPS is not an inference guarantee. **A successful local warmup is not a successful calibration:** the original one-student lock and three measured zone holds remain authoritative.
