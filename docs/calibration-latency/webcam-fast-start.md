# Webcam first-frame latency — YOLO26 calibration follow-up

October 26, 2026. Scope: `ui/vision/pose_worker.py` and hardware-free Python tests. No production Godot scene/pose_service/DB changes were made. The worker must only open the camera after explicit authorization, including authenticated `start_camera` from a reusable `--prewarm` process.

## Why the webcam can still look slow after model prewarm

YOLO prewarming keeps the imported Torch/Ultralytics model, CUDA weights and ByteTrack predictor ready. It **does not open the webcam without permission**. Camera initialization is a distinct stage: Windows capture backend selection → `VideoCapture.isOpened()` → camera format negotiation → first actual `read()` → JPEG → UDP preview → subsequent YOLO/StudentLock enrollment. The previous worker tried **MSMF first**, even on laptops where DirectShow opens sooner, and treated `isOpened() == True` as success even if no images were returned. It did not time individual backend/frame stages. Forcing several capture properties before reading can also incur additional driver negotiation.

The previous *offline* Python + model/CUDA warmup benchmark measured **9.346 seconds**. A second fully local benchmark on this same RTX 3050 machine, using the cached 7,878,574-byte YOLO26n pose weights, synthetic 320×320 zero frames and **no camera**, measured:

| Model phase (no camera) | Observed seconds |
| --- | ---: |
| NumPy/Ultralytics/Torch import | 2.401 |
| YOLO local weights construction | 0.079 |
| First synthetic inference / CUDA initialization | 2.634 |
| **Total** | **5.115** |
| Subsequent synthetic inference mean | 0.026/frame |

These differing real cold-process measurements reflect changing disk and GPU cache state. They **are not webcam-open timings**. A real webcam has deliberately *not* been opened in QA, so measured device-specific DirectShow or MSMF duration remains unknown. Running prewarm in advance still helps by removing these seconds of model work from the camera-permission-to-first-pose path.

## Implemented low-risk worker changes

1. On Windows, attempt **DirectShow → Media Foundation → automatic** for camera index only; other platforms use automatic backend. Every failed capture is released before trying the next. A backend's synchronous `VideoCapture` time is logged separately.
2. Request low-bandwidth **MJPG**, 640×480 dimensions and the existing preferred 60 FPS; unsupported property settings are ignored safely, and measured `camera_fps` continues to report actual capture performance. A first successful real camera frame is required within **2.3 seconds after a backend begins reading**. If the driver claims opened but yields nothing, close the reader and retry the next backend, rather than blank calibration. If a Windows `read()` remains stuck even after release, refuse to open a concurrent backend that could contend for the camera.
3. Use a **single continually overwriting `LatestCamera` frame slot** with atomic frame, sequence and capture timestamp. Capture runs on its existing daemon thread; `wait_for_first_frame` stops early if the reader fails. On first real frame, send the first full-resolution mirror JPEG **immediately before model loading**. The background startup-preview thread continues at most 15 FPS, and the ordinary tracked preview uses its existing bounded one-slot 24 FPS encoder.
4. Reject inference results whose real input frame is older than **850 ms** rather than refreshing a previous student/gesture with delayed detections. The age is measured using the same worker's `time.monotonic()` before/after YOLO, never against Godot's different clock epoch. Late samples publish `state=recovering`, `pose=false` and a reason; the original StudentLock and gesture edge/cooldown logic remain unmodified.
5. Preserve `--prewarm` authentication and reuse unchanged. The authorized prewarmed Python process still invokes `run(..., prepared_model=(model, device, gpu))` and never calls `prepare_pose_model` again. Student enrollment remains solo/bystander-safe, and camera resources are released when the session terminates.

## Additive status telemetry for the prime / PoseService owner

The existing UDP packet `kind=pose`, authenticated `token`, `when`, `state`, `pose` and `hand_up` fields are unchanged. New optional values can be displayed/logged directly by `pose_service.gd` without protocol changes:

| Field | Meaning |
| --- | --- |
| `camera_phase` | `opening`, `awaiting_frame`, `no_frames`, `driver_stalled`, `streaming`, `preview`, `tracking`, `stale_inference` or `failed` |
| `camera_backend` | Attempted or selected `DSHOW`, `MSMF`, `ANY` |
| `camera_attempts` | Count of backend attempts made in current authorized session |
| `camera_open_ms` | Synchronous `VideoCapture(...)` and `isOpened()` duration of successful (or last attempted) backend |
| `camera_configure_ms` | Requested capture format/FPS/buffer setup time |
| `camera_first_frame_ms` | Time from beginning capture reader to its first **actual** frame |
| `camera_startup_ms` | Total camera-open-backend/fallback-to-first-frame elapsed time, including failed attempts |
| `camera_first_preview_ms` | Worker process start to first successfully UDP-sent actual preview JPEG |
| `camera_frame_age_ms` | Input image age *at inference completion*; if over 850ms, pose=false/recovering |

The prime can show `camera_phase` and `camera_backend` while opening, and record real device-specific `camera_open_ms` and `camera_startup_ms` at school. For a camera that opens only through slow MSMF, the selected backend will be visible. `camera_first_preview_ms` includes Python initialization if not prewarmed; `camera_startup_ms` isolates camera initialization from it.

## Offline regressions

Run from `ui/vision/`:

```powershell
python -m unittest -v test_pose_camera_startup.py
python -m unittest -q test_pose_worker_latency.py test_pose_startup_preview.py test_pose_latency_offline.py test_pose_recovery.py test_student_lock.py
```

New `test_pose_camera_startup.py` tests cover: DirectShow priority, MSMF fallback, opened-but-zero-images fallback, failed backend cleanup, non-Windows automatic backend selection, VideoCapture exceptions, real one-slot frame timestamp, empty frame reader shutdown, and delayed synthetic YOLO inference that cannot emit a stale pose. All use fake camera backends or synthetic NumPy frames; none call a real device.

At this verification, **9/9 new startup tests** and **30 existing tests (29 passed, 1 optional cold benchmark skipped)** passed. `python -m py_compile pose_worker.py` passed. Synthetic model speed and frame age tests are not substitutes for observing a real classroom webcam and GPU, so no unsupported camera-open millisecond improvement is claimed.

### Device-level follow-up, after explicit teacher camera consent

Collect the first minute of authenticated Godot camera status fields from the target Windows laptop on its actual integrated USB or laptop camera. Compare DirectShow and MSMF backend selection, open/format/first-frame timing, first preview timing, and first locked pose. Verify privacy indicator and release when leaving calibration, along with camera sharing conflicts. If `VideoCapture` itself blocks for many seconds, Python threads cannot reliably cancel that native Windows call: minimizing backend attempts or investigating device drivers/OS privacy settings is preferable to concurrent probe opens.
